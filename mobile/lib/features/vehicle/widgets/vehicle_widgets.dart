import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_components.dart';

/// Coloured chip for NOT_SUBMITTED / PENDING / APPROVED / REJECTED (and document statuses).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;

  static const _labels = {
    'NOT_SUBMITTED': 'Not submitted',
    'PENDING': 'Pending review',
    'APPROVED': 'Approved',
    'REJECTED': 'Rejected',
    'UPLOADED': 'Uploaded',
    'ACCEPTED': 'Accepted',
    'MISSING': 'Not uploaded',
  };

  StatusTone get _tone => switch (status) {
        'APPROVED' || 'ACCEPTED' => StatusTone.success,
        'PENDING' || 'UPLOADED' => StatusTone.warning,
        'REJECTED' => StatusTone.danger,
        _ => StatusTone.neutral,
      };

  @override
  Widget build(BuildContext context) => AppBadge(_labels[status] ?? status, tone: _tone);
}

/// "-  4  +" stepper that never goes outside [min]..[max].
class SeatStepper extends StatelessWidget {
  const SeatStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                if (helper != null) Text(helper!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton.outlined(
            icon: const Icon(Icons.remove),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 40,
            child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton.outlined(
            icon: const Icon(Icons.add),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}
