import 'package:flutter/material.dart';

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

  Color _color() {
    switch (status) {
      case 'APPROVED':
      case 'ACCEPTED':
        return Colors.green.shade700;
      case 'PENDING':
      case 'UPLOADED':
        return Colors.orange.shade800;
      case 'REJECTED':
        return Colors.red.shade700;
      default:
        return Colors.blueGrey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        _labels[status] ?? status,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
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

/// Loading / error-with-retry helpers so every screen looks the same.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: error ? Colors.red.shade700 : null),
  );
}
