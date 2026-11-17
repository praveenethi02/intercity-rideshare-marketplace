import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_components.dart';

/// Shown instead of PENDING while documents are missing, because no admin can review it yet.
const driverStatusDocumentsNeeded = 'DOCUMENTS_NEEDED';

/// Coloured label for a verification, account or trip status.
class DriverStatusChip extends StatelessWidget {
  final String status;
  const DriverStatusChip(this.status, {super.key});

  static (String, StatusTone) _style(String status) => switch (status) {
        driverStatusDocumentsNeeded => ('Documents needed', StatusTone.info),
        'PENDING' => ('In review', StatusTone.warning),
        'APPROVED' => ('Approved', StatusTone.success),
        'REJECTED' => ('Rejected', StatusTone.danger),
        'ACTIVE' => ('Active', StatusTone.success),
        'SUSPENDED' => ('Suspended', StatusTone.danger),
        'DEACTIVATED' => ('Deactivated', StatusTone.neutral),
        'DRAFT' => ('Draft', StatusTone.neutral),
        'SCHEDULED' => ('Scheduled', StatusTone.info),
        'IN_PROGRESS' => ('In progress', StatusTone.warning),
        'COMPLETED' => ('Completed', StatusTone.success),
        'CANCELLED' => ('Cancelled', StatusTone.danger),
        _ => (status, StatusTone.neutral),
      };

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _style(status);
    return AppBadge(label, tone: tone);
  }
}

/// Tap to choose a date. The value is kept as YYYY-MM-DD, the format the API uses.
class DriverDateField extends StatelessWidget {
  final String label;
  final String? value;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime initialDate;
  final ValueChanged<String> onChanged;
  final String? errorText;

  const DriverDateField({
    super.key,
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.initialDate,
    required this.onChanged,
    this.errorText,
  });

  Future<void> _pick(BuildContext context) async {
    final parsed = value == null ? null : DateTime.tryParse(value!);
    final picked = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: parsed ?? initialDate,
      helpText: label,
    );
    if (picked != null) onChanged(isoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final parsed = value == null ? null : DateTime.tryParse(value!);
    return InkWell(
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        isEmpty: parsed == null,
        child: parsed == null ? null : Text(formatDate(parsed)),
      ),
    );
  }
}

/// Client-side checks that match the backend's rules, so mistakes show before a request is sent.
abstract final class DriverValidators {
  static String? licence(String? v) =>
      RegExp(r'^[A-Za-z0-9-]{5,20}$').hasMatch(v?.trim() ?? '') ? null : 'Use 5 to 20 letters, digits or hyphens';

  static String? nic(String? v) => RegExp(r'^(\d{9}[VvXx]|\d{12})$').hasMatch(v?.trim() ?? '')
      ? null
      : 'Enter 9 digits and V or X, or 12 digits';

  static String? phone(String? v) => RegExp(r'^(\+94|94|0)7\d{8}$').hasMatch((v ?? '').replaceAll(RegExp(r'[\s-]'), ''))
      ? null
      : 'Enter a Sri Lankan mobile number';

  static String? required(String? v) => (v == null || v.trim().isEmpty) ? 'This is required' : null;

  /// The latest birth date that makes someone 18 today.
  static DateTime latestAdultBirthDate(DateTime today) {
    final year = today.year - 18;
    final lastDayOfMonth = DateTime(year, today.month + 1, 0).day;
    return DateTime(year, today.month, today.day > lastDayOfMonth ? lastDayOfMonth : today.day);
  }
}
