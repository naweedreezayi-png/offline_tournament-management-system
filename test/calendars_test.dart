import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/utils/calendars.dart';

void main() {
  final d = DateTime(2026, 11, 7);

  test('the same day in the three calendars', () {
    expect(Calendars.numeric(CalKind.gregorian, d), '2026-11-07');
    expect(Calendars.numeric(CalKind.shamsi, d), '1405/08/16');
    expect(Calendars.numeric(CalKind.hijri, d), '1448/05/26');
  });

  test('toGregorian reverses parts for all calendars and clamps the day', () {
    for (final k in CalKind.values) {
      final (y, m, dd) = Calendars.parts(k, d);
      expect(Calendars.toGregorian(k, y, m, dd), d);
    }
    expect(Calendars.toGregorian(CalKind.gregorian, 2026, 2, 31), DateTime(2026, 2, 28));
  });

  test('month names', () {
    expect(Calendars.monthName(CalKind.shamsi, 8, 'fa'), 'عقرب');
    expect(Calendars.monthName(CalKind.gregorian, 11, 'en'), 'November');
  });
}
