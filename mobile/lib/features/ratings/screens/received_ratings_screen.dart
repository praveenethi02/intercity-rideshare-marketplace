import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/rating_api.dart';

/// The ratings a user received, with their average.
class ReceivedRatingsScreen extends StatefulWidget {
  final RatingApi api;
  final String userId;
  const ReceivedRatingsScreen({super.key, required this.api, required this.userId});

  @override
  State<ReceivedRatingsScreen> createState() => _ReceivedRatingsScreenState();
}

class _ReceivedRatingsScreenState extends State<ReceivedRatingsScreen> {
  late Future<RatingSummary> _future = widget.api.received(widget.userId);

  Future<void> _reload() async {
    final future = widget.api.received(widget.userId);
    setState(() {
      _future = future;
    });
    await future.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('My ratings')),
      body: FutureBuilder<RatingSummary>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SkeletonList();
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final summary = snap.data!;
          final average = summary.average;
          if (average == null) {
            return const EmptyView(icon: Icons.star_outline_rounded, message: 'No ratings yet.');
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: AppSpacing.screen,
              children: [
                AppCard(
                  child: Column(children: [
                    Text(average.toStringAsFixed(1), style: theme.textTheme.displaySmall),
                    _Stars(average.round()),
                    const SizedBox(height: AppSpacing.xs),
                    Text('${summary.count} ${summary.count == 1 ? 'rating' : 'ratings'}'),
                  ]),
                ),
                for (final r in summary.ratings) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(r.reviewerName, style: theme.textTheme.titleSmall)),
                        _Stars(r.stars),
                      ]),
                      Text(
                        formatDate(r.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (r.review != null) ...[const SizedBox(height: AppSpacing.sm), Text(r.review!)],
                    ]),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final int stars;
  const _Stars(this.stars);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$stars out of 5 stars',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
      ]),
    );
  }
}
