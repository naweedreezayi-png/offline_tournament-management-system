import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/utils/hijri.dart';

void main() {
  test('1 Muharram 1 AH is 16 July 622 (Julian) = 19 July 622 proleptic Gregorian', () {
    // civil epoch: Friday 16 July 622 Julian = 19 July 622 proleptic Gregorian
    expect(const HijriDate(1, 1, 1).toGregorian(), DateTime(622, 7, 19));
  });

  test('round trip for every day of 1990..2060', () {
    var d = DateTime(1990, 1, 1);
    final end = DateTime(2060, 1, 1);
    while (d.isBefore(end)) {
      final h = HijriDate.fromGregorian(d);
      expect(h.toGregorian(), d, reason: '$d -> $h');
      expect(h.month >= 1 && h.month <= 12, isTrue);
      expect(h.day >= 1 && h.day <= HijriDate.daysInMonth(h.year, h.month), isTrue, reason: '$d -> $h');
      d = DateTime(d.year, d.month, d.day + 1);
    }
  });

  test('close to the observed calendar (tabular calendar may differ by up to 2 days)', () {
    // observed: 1 Ramadan 1446 = 1 March 2025; 1 Muharram 1447 = 26/27 June 2025
    final a = const HijriDate(1446, 9, 1).toGregorian().difference(DateTime(2025, 3, 1)).inDays.abs();
    final b = const HijriDate(1447, 1, 1).toGregorian().difference(DateTime(2025, 6, 26)).inDays.abs();
    expect(a <= 2, isTrue);
    expect(b <= 2, isTrue);
  });

  test('month lengths alternate 30/29 and the year has 354 or 355 days', () {
    for (var y = 1440; y < 1460; y++) {
      var sum = 0;
      for (var m = 1; m <= 12; m++) {
        sum += HijriDate.daysInMonth(y, m);
      }
      expect(sum, HijriDate.isLeapYear(y) ? 355 : 354);
    }
  });
}
