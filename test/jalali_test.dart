import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/utils/jalali.dart';

void main() {
  // Reference pairs checked against the official Afghan/Iranian calendar.
  final known = <DateTime, String>{
    DateTime(2024, 3, 20): '1403/01/01',
    DateTime(2025, 3, 21): '1404/01/01',
    DateTime(2026, 3, 21): '1405/01/01',
    DateTime(2026, 11, 5): '1405/08/14',
    DateTime(2000, 1, 1): '1378/10/11',
    DateTime(1979, 2, 11): '1357/11/22',
  };

  test('Gregorian to Shamsi, known dates', () {
    known.forEach((g, j) => expect(JalaliDate.fromGregorian(g).format(), j, reason: '$g'));
  });

  test('Shamsi to Gregorian round trip for every day of 1380..1420', () {
    var d = DateTime(2001, 3, 21);
    final end = DateTime(2042, 3, 21);
    while (d.isBefore(end)) {
      final j = JalaliDate.fromGregorian(d);
      expect(j.toGregorian(), d);
      expect(j.month >= 1 && j.month <= 12, isTrue);
      expect(j.day >= 1 && j.day <= JalaliDate.daysInMonth(j.year, j.month), isTrue);
      d = DateTime(d.year, d.month, d.day + 1);
    }
  });

  test('leap years and month lengths', () {
    expect(JalaliDate.isLeapYear(1403), isTrue);
    expect(JalaliDate.isLeapYear(1404), isFalse);
    expect(JalaliDate.daysInMonth(1403, 12), 30);
    expect(JalaliDate.daysInMonth(1404, 12), 29);
    expect(JalaliDate.daysInMonth(1404, 1), 31);
    expect(JalaliDate.daysInMonth(1404, 7), 30);
  });

  test('long format uses Dari month names', () {
    expect(JalaliDate.fromGregorian(DateTime(2026, 11, 5)).formatLong(), '14 عقرب 1405');
  });
}
