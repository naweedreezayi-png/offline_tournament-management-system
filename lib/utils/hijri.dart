/// Hijri (Qamari / lunar) calendar, tabular "civil" algorithm. Pure Dart, no dependencies.
///
/// Honest limit: the real calendar follows the moon sighting of each country, so a printed
/// or announced date can differ by one or two days from this arithmetic calendar
/// (the same limit applies to every offline converter). Use it for display, not for religious rulings.
class HijriDate {
  final int year;
  final int month;
  final int day;
  const HijriDate(this.year, this.month, this.day);

  static const List<String> monthNamesFa = [
    'محرم', 'صفر', 'ربیع‌الاول', 'ربیع‌الثانی', 'جمادی‌الاول', 'جمادی‌الثانی',
    'رجب', 'شعبان', 'رمضان', 'شوال', 'ذیقعده', 'ذیحجه'
  ];

  static int _jdnOfGregorian(int y, int m, int d) {
    final a = (14 - m) ~/ 12;
    final yy = y + 4800 - a;
    final mm = m + 12 * a - 3;
    return d + (153 * mm + 2) ~/ 5 + 365 * yy + yy ~/ 4 - yy ~/ 100 + yy ~/ 400 - 32045;
  }

  static DateTime _gregorianOfJdn(int jdn) {
    final a = jdn + 32044;
    final b = (4 * a + 3) ~/ 146097;
    final c = a - 146097 * b ~/ 4;
    final d = (4 * c + 3) ~/ 1461;
    final e = c - 1461 * d ~/ 4;
    final m = (5 * e + 2) ~/ 153;
    final day = e - (153 * m + 2) ~/ 5 + 1;
    final month = m + 3 - 12 * (m ~/ 10);
    final year = 100 * b + d - 4800 + m ~/ 10;
    return DateTime(year, month, day);
  }

  /// Islamic day number of 1 Muharram of [year] (civil epoch Friday 16 July 622).
  static int _jdnOfHijri(int y, int m, int d) =>
      d + ((59 * (m - 1) + 1) ~/ 2) + (y - 1) * 354 + (3 + 11 * y) ~/ 30 + 1948439;

  static bool isLeapYear(int y) => (14 + 11 * y) % 30 < 11;

  static int daysInMonth(int y, int m) => m == 12 ? (isLeapYear(y) ? 30 : 29) : (m.isOdd ? 30 : 29);

  /// Converts a Gregorian date (the time of day is ignored).
  factory HijriDate.fromGregorian(DateTime g) {
    final jdn = _jdnOfGregorian(g.year, g.month, g.day);
    var y = ((30 * (jdn - 1948440) + 10646) ~/ 10631);
    // The closed formula can be off by one at year borders: correct it exactly.
    while (_jdnOfHijri(y, 1, 1) > jdn) {
      y--;
    }
    while (_jdnOfHijri(y + 1, 1, 1) <= jdn) {
      y++;
    }
    var m = ((jdn - _jdnOfHijri(y, 1, 1)) * 2 ~/ 59) + 1;
    if (m > 12) m = 12;
    while (m > 1 && _jdnOfHijri(y, m, 1) > jdn) {
      m--;
    }
    while (m < 12 && _jdnOfHijri(y, m + 1, 1) <= jdn) {
      m++;
    }
    return HijriDate(y, m, jdn - _jdnOfHijri(y, m, 1) + 1);
  }

  DateTime toGregorian() => _gregorianOfJdn(_jdnOfHijri(year, month, day));

  /// `1448/05/26`
  String format() => '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}';

  /// `26 جمادی‌الاول 1448`
  String formatLong() => '$day ${monthNamesFa[month - 1]} $year';

  @override
  bool operator ==(Object other) =>
      other is HijriDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => format();
}
