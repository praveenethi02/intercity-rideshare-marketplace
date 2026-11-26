import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/rating_api.dart';
import '../widgets/rating_sheet.dart';

/// People the user can still rate after their completed trips.
class PendingRatingsScreen extends StatefulWidget {
  final RatingApi api;
  const PendingRatingsScreen({super.key, required this.api});

  @override
  State<PendingRatingsScreen> createState() => _PendingRatingsScreenState();
}

class _PendingRatingsScreenState extends State<PendingRatingsScreen> {
  late Future<List<PendingRating>> _future = widget.api.pending();

  Future<void> _reload() async {
    final future = widget.api.pending();
    setState(() {
      _future = future;
    });
    await future.then((_) {}, onError: (_) {});
  }

  Future<void> _rate(PendingRating pending) async {
    final saved = await showRatingSheet(context, widget.api, pending);
    if (!saved || !mounted) return;
    showSnack(context, 'Thanks for your rating');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rate your trips')),
      body: FutureBuilder<List<PendingRating>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SkeletonList();
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyView(icon: Icons.star_outline_rounded, message: 'No trips to rate.');
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: AppSpacing.screen,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) {
                final p = items[i];
                return Card(
                  child: ListTile(
                    leading: Icon(p.rateeIsDriver ? Icons.directions_car : Icons.person_outline),
                    title: Text(p.rateeName),
                    subtitle: Text(
                      '${p.rateeIsDriver ? 'Driver' : 'Passenger'} · ${p.route}\n${formatDate(p.departureTime)}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _rate(p),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
