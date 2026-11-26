import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/rating_api.dart';

/// Opens the rating sheet. Returns true when the rating was saved.
Future<bool> showRatingSheet(BuildContext context, RatingApi api, PendingRating pending) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RatingSheet(api: api, pending: pending),
  );
  return saved ?? false;
}

/// 1 to 5 stars and an optional review (SCRUM-304).
class RatingSheet extends StatefulWidget {
  final RatingApi api;
  final PendingRating pending;
  const RatingSheet({super.key, required this.api, required this.pending});

  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet> {
  final _review = TextEditingController();
  int _stars = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      setState(() => _error = 'Choose 1 to 5 stars');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.rate(widget.pending, _stars, _review.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ApiException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.pending;
    return SingleChildScrollView(
      // Keeps the sheet above the keyboard.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Rate ${p.rateeName}', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          p.route,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              iconSize: 40,
              tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
              color: theme.colorScheme.primary,
              icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded),
              onPressed: _busy ? null : () => setState(() => _stars = i),
            ),
        ]),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _review,
          enabled: !_busy,
          maxLength: 500,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Review (optional)'),
        ),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: AppSpacing.md),
        ],
        BusyButton(busy: _busy, onPressed: _submit, label: 'Submit rating'),
      ]),
    );
  }
}
