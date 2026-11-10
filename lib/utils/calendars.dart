import 'hijri.dart';
import 'jalali.dart';

/// The three calendars the app shows side by side.
enum CalKind { shamsi, hijri, gregorian }

class Calendars {
  Calendars._();

  static const List<String> gregorianMonthsFa = [
    'جنوری', 'فبروری', 'مارچ', 'اپریل', 'می', 'جون', 'جولای', 'اگست', 'سپتمبر', 'اکتوبر', 'نومبر', 'دسمبر'
  ];
  static const List<String> gregorianMonthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static bool _rtlNames(String lang) => lang == 'fa' || lang == 'ps' || lang == 'ar';

  static String monthName(CalKind k, int month, String lang) {
    switch (k) {
      case CalKind.shamsi:
        return JalaliDate.monthNamesFa[month - 1];
      case CalKind.hijri:
        return HijriDate.monthNamesFa[month - 1];
      case CalKind.gregorian:
        return (_rtlNames(lang) ? gregorianMonthsFa : gregorianMonthsEn)[month - 1];
    }
  }

  static int daysInMonth(CalKind k, int year, int month) {
    switch (k) {
      case CalKind.shamsi:
        return JalaliDate.daysInMonth(year, month);
      case CalKind.hijri:
        return HijriDate.daysInMonth(year, month);
      case CalKind.gregorian:
        return DateTime(year, month + 1, 0).day;
    }
  }

  /// (year, month, day) of [d] in calendar [k].
  static (int, int, int) parts(CalKind k, DateTime d) {
    switch (k) {
      case CalKind.shamsi:
        final j = JalaliDate.fromGregorian(d);
        return (j.year, j.month, j.day);
      case CalKind.hijri:
        final h = HijriDate.fromGregorian(d);
        return (h.year, h.month, h.day);
      case CalKind.gregorian:
        return (d.year, d.month, d.day);
    }
  }

  /// The Gregorian date (midnight) of a date written in calendar [k]. The day is clamped to the month length.
  static DateTime toGregorian(CalKind k, int year, int month, int day) {
    final maxDay = daysInMonth(k, year, month);
    final int dd = day < 1 ? 1 : (day > maxDay ? maxDay : day);
    switch (k) {
      case CalKind.shamsi:
        return JalaliDate(year, month, dd).toGregorian();
      case CalKind.hijri:
        return HijriDate(year, month, dd).toGregorian();
      case CalKind.gregorian:
        return DateTime(year, month, dd);
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// `1405/08/16`, `1448/05/26` or `2026-11-07` (numeric, no names).
  static String numeric(CalKind k, DateTime d) {
    final (y, m, dd) = parts(k, d);
    return k == CalKind.gregorian ? '$y-${_two(m)}-${_two(dd)}' : '$y/${_two(m)}/${_two(dd)}';
  }

  /// `16 عقرب 1405`
  static String long(CalKind k, DateTime d, String lang) {
    final (y, m, dd) = parts(k, d);
    return '$dd ${monthName(k, m, lang)} $y';
  }

  static String time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
}
