// Plain-Dart formatting helpers (no intl package needed). Money is LKR cents.

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// 250000 -> "LKR 2,500"
String formatLkr(int cents) {
  final rupees = (cents / 100).round();
  final digits = rupees.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return 'LKR ${rupees < 0 ? '-' : ''}$buffer';
}

/// "2500" or "2,500.50" -> cents. Returns null if not a valid amount.
int? parseLkrToCents(String text) {
  final value = double.tryParse(text.replaceAll(',', '').trim());
  if (value == null || value < 0) return null;
  return (value * 100).round();
}

/// Thu, 20 Nov 2026
String formatDate(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';

/// 6:05 AM
String formatTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
}

String formatDateTime(DateTime d) => '${formatDate(d)} · ${formatTime(d)}';

/// 2026-11-20 (used by the search API)
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String formatKm(double km) => km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';

/// "2h 15m" between two times
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
