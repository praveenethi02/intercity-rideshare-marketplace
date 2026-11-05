import 'package:flutter/material.dart';

import '../../../core/formatters.dart';

/// Shown instead of PENDING while documents are missing, because no admin can review it yet.
const driverStatusDocumentsNeeded = 'DOCUMENTS_NEEDED';

/// Coloured label for a verification, account or trip status.
class DriverStatusChip extends StatelessWidget {
  final String status;
  const DriverStatusChip(this.status, {super.key});

  static (String, Color) _style(String status) => switch (status) {
        driverStatusDocumentsNeeded => ('Documents needed', const Color(0xFF0B57D0)),
        'PENDING' => ('In review', const Color(0xFF9A6700)),
        'APPROVED' => ('Approved', const Color(0xFF0B6E4F)),
        'REJECTED' => ('Rejected', const Color(0xFFB3261E)),
        'ACTIVE' => ('Active', const Color(0xFF0B6E4F)),
        'SUSPENDED' => ('Suspended', const Color(0xFFB3261E)),
        'DEACTIVATED' => ('Deactivated', const Color(0xFF5F6368)),
        'DRAFT' => ('Draft', const Color(0xFF5F6368)),
        'SCHEDULED' => ('Scheduled', const Color(0xFF0B57D0)),
        'IN_PROGRESS' => ('In progress', const Color(0xFF9A6700)),
        'COMPLETED' => ('Completed', const Color(0xFF0B6E4F)),
        'CANCELLED' => ('Cancelled', const Color(0xFFB3261E)),
        _ => (status, const Color(0xFF5F6368)),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color) = _style(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
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
