/// Minimal RFC 4180 CSV writer (pure Dart, unit-tested).
class Csv {
  Csv._();

  static String cell(Object? v) {
    var s = v == null ? '' : v.toString();
    // Spreadsheet formula injection guard: a cell that starts with one of
    // these is treated as a formula by Excel / LibreOffice.
    if (s.isNotEmpty && '=+@'.contains(s[0])) s = "'$s";
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      s = '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String row(List<Object?> cells) => cells.map(cell).join(',');

  /// Rows joined with CRLF and prefixed with a UTF-8 BOM so Excel opens
  /// Persian / Arabic / Chinese text correctly.
  static String table(List<List<Object?>> rows) =>
      '﻿${rows.map(row).join('\r\n')}\r\n';
}
