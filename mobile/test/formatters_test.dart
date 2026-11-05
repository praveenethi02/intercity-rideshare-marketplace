import 'package:flutter_test/flutter_test.dart';
import 'package:rideshare_mobile/core/formatters.dart';

void main() {
  test('formatLkr adds commas and drops cents', () {
    expect(formatLkr(250000), 'LKR 2,500');
    expect(formatLkr(132000), 'LKR 1,320');
    expect(formatLkr(10000000), 'LKR 100,000');
    expect(formatLkr(0), 'LKR 0');
  });

  test('parseLkrToCents', () {
    expect(parseLkrToCents('2500'), 250000);
    expect(parseLkrToCents('2,500.50'), 250050);
    expect(parseLkrToCents('abc'), isNull);
    expect(parseLkrToCents('-5'), isNull);
  });

  test('dates and times', () {
    final d = DateTime(2026, 11, 20, 6, 5);
    expect(formatDate(d), 'Fri, 20 Nov 2026');
    expect(formatTime(d), '6:05 AM');
    expect(formatTime(DateTime(2026, 1, 1, 12, 0)), '12:00 PM');
    expect(formatTime(DateTime(2026, 1, 1, 0, 30)), '12:30 AM');
    expect(isoDate(DateTime(2026, 3, 7)), '2026-03-07');
  });

  test('km and duration', () {
    expect(formatKm(4.26), '4.3 km');
    expect(formatKm(122.24), '122 km');
    expect(formatDuration(const Duration(hours: 2, minutes: 15)), '2h 15m');
    expect(formatDuration(const Duration(minutes: 40)), '40m');
  });
}
