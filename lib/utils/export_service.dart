import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:path/path.dart' show join;

import '../data/database_helper.dart';
import '../domain/csv_export.dart';
import '../models/tournament.dart';
import '../providers/tournament_provider.dart';
import 'calendars.dart';

/// Writes a tournament to files inside the app's backups folder
/// (`.../backups/exports`). Import of these files is NOT implemented.
class ExportService {
  ExportService._();

  static Future<Directory> _dir() async {
    if (kIsWeb) throw UnsupportedError('Database backup and file export need the Android app. In the browser your data stays in the browser storage.');
    final d = Directory(join(await DatabaseHelper.instance.backupsPath(), 'exports'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[^\w؀-ۿ-]+'), '_');

  static String matchesCsv(Tournament t) {
    final names = {for (final x in t.teams) x.id: x.name};
    String n(String? id) => id == null ? '' : (names[id] ?? '');
    final rows = <List<Object?>>[
      ['group', 'round', 'team A', 'team B', 'score A', 'score B', 'played']
    ];
    for (final m in t.matches) {
      rows.add(['', m.round, n(m.teamAId), n(m.teamBId), m.scoreA, m.scoreB, m.isPlayed]);
    }
    for (final g in t.groups) {
      for (final m in g.matches) {
        rows.add([g.name, m.round, n(m.teamAId), n(m.teamBId), m.scoreA, m.scoreB, m.isPlayed]);
      }
    }
    return Csv.table(rows);
  }

  static String standingsCsv(List<StandingRow> table) => Csv.table([
        ['#', 'team', 'P', 'W', 'D', 'L', 'GF', 'GA', 'GD', 'Pts'],
        for (var i = 0; i < table.length; i++)
          [i + 1, table[i].team.name, table[i].played, table[i].win, table[i].draw,
           table[i].loss, table[i].gf, table[i].ga, table[i].gd, table[i].pts],
      ]);

  /// Returns the paths written.
  static Future<List<String>> exportTournament(
      Tournament t, TournamentProvider provider) async {
    final dir = await _dir();
    final base = join(dir.path, _safe(t.name));
    final out = <String>[];
    final json = File('$base.json');
    await json.writeAsString(const JsonEncoder.withIndent('  ').convert(t.toJson()));
    out.add(json.path);
    final m = File('${base}_matches.csv');
    await m.writeAsString(matchesCsv(t));
    out.add(m.path);
    if (t.type == TournamentType.league) {
      final s = File('${base}_standings.csv');
      await s.writeAsString(standingsCsv(provider.computeStandings(t)));
      out.add(s.path);
    }
    return out;
  }

  // ---------------------------------------------------------------- Excel
  /// Builds an .xlsx workbook: sheet "Matches" (+ "Standings" for leagues).
  /// Dates are written in all three calendars. NOT tested on a device.
  static List<int> xlsxBytes(Tournament t, TournamentProvider provider) {
    final book = Excel.createExcel();
    final names = {for (final x in t.teams) x.id: x.name};
    String n(String? id) => id == null ? '' : (names[id] ?? '');
    String d(DateTime? v, CalKind k) => v == null ? '' : Calendars.numeric(k, v);

    final ms = book['Matches'];
    ms.appendRow([
      for (final h in ['group', 'round', 'team A', 'team B', 'score A', 'score B', 'played', 'date (Shamsi)', 'date (Hijri)', 'date (Gregorian)'])
        TextCellValue(h)
    ]);
    void addMatch(String g, m) {
      ms.appendRow([
        TextCellValue(g),
        IntCellValue(m.round as int),
        TextCellValue(n(m.teamAId)),
        TextCellValue(n(m.teamBId)),
        m.scoreA == null ? TextCellValue('') : IntCellValue(m.scoreA as int),
        m.scoreB == null ? TextCellValue('') : IntCellValue(m.scoreB as int),
        TextCellValue(m.isPlayed ? 'yes' : 'no'),
        TextCellValue(d(m.scheduledAt, CalKind.shamsi)),
        TextCellValue(d(m.scheduledAt, CalKind.hijri)),
        TextCellValue(d(m.scheduledAt, CalKind.gregorian)),
      ]);
    }
    for (final m in t.matches) { addMatch('', m); }
    for (final g in t.groups) { for (final m in g.matches) { addMatch(g.name, m); } }

    if (t.type == TournamentType.league) {
      final st = book['Standings'];
      st.appendRow([for (final h in ['#', 'team', 'P', 'W', 'D', 'L', 'GF', 'GA', 'GD', 'Pts']) TextCellValue(h)]);
      final table = provider.computeStandings(t);
      for (var i = 0; i < table.length; i++) {
        final r = table[i];
        st.appendRow([
          IntCellValue(i + 1), TextCellValue(r.team.name), IntCellValue(r.played), IntCellValue(r.win),
          IntCellValue(r.draw), IntCellValue(r.loss), IntCellValue(r.gf), IntCellValue(r.ga),
          IntCellValue(r.gd), IntCellValue(r.pts),
        ]);
      }
    }
    book.delete('Sheet1');
    return book.save() ?? <int>[];
  }

  static Future<String> exportXlsx(Tournament t, TournamentProvider provider) async {
    final f = File('${join((await _dir()).path, _safe(t.name))}.xlsx');
    await f.writeAsBytes(xlsxBytes(t, provider));
    return f.path;
  }

  // ------------------------------------------------------------------ PDF
  static String _esc(String s) => s
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// HTML report rendered to PDF by the platform (correct Arabic/Persian
  /// shaping, unlike drawing text with the `pdf` package without a font).
  static String reportHtml(Tournament t, TournamentProvider provider, {bool rtl = true}) {
    final names = {for (final x in t.teams) x.id: x.name};
    String n(String? id) => id == null ? '' : _esc(names[id] ?? '');
    final b = StringBuffer('<html><head><meta charset="utf-8"><style>'
        'body{font-family:sans-serif;direction:${rtl ? 'rtl' : 'ltr'};padding:16px}'
        'table{border-collapse:collapse;width:100%;margin:12px 0}'
        'td,th{border:1px solid #889;padding:5px;text-align:center;font-size:12px}'
        'th{background:#dde6ff}h1{color:#1c3f94}</style></head><body>');
    b.write('<h1>${_esc(t.name)}</h1><p>${_esc(t.sport)} — ${t.type.name}</p>');
    if (t.type == TournamentType.league) {
      final table = provider.computeStandings(t);
      b.write('<table><tr><th>#</th><th>Team</th><th>P</th><th>W</th><th>D</th><th>L</th><th>GF</th><th>GA</th><th>GD</th><th>Pts</th></tr>');
      for (var i = 0; i < table.length; i++) {
        final r = table[i];
        b.write('<tr><td>${i + 1}</td><td>${_esc(r.team.name)}</td><td>${r.played}</td><td>${r.win}</td><td>${r.draw}</td><td>${r.loss}</td><td>${r.gf}</td><td>${r.ga}</td><td>${r.gd}</td><td><b>${r.pts}</b></td></tr>');
      }
      b.write('</table>');
    }
    b.write('<table><tr><th>Round</th><th>Team A</th><th>Score</th><th>Team B</th><th>Date (Shamsi / Hijri / Gregorian)</th></tr>');
    void row(m) {
      final dt = m.scheduledAt as DateTime?;
      final date = dt == null
          ? ''
          : '${Calendars.numeric(CalKind.shamsi, dt)} / ${Calendars.numeric(CalKind.hijri, dt)} / ${Calendars.numeric(CalKind.gregorian, dt)}';
      b.write('<tr><td>${(m.round as int) + 1}</td><td>${n(m.teamAId)}</td><td>${m.scoreA ?? '-'} : ${m.scoreB ?? '-'}</td><td>${n(m.teamBId)}</td><td>$date</td></tr>');
    }
    for (final m in t.matches) { row(m); }
    for (final g in t.groups) { for (final m in g.matches) { row(m); } }
    b.write('</table></body></html>');
    return b.toString();
  }

  /// Opens the system share/print sheet with the PDF. Works on Android/iOS;
  /// not verified on web.
  static Future<void> sharePdf(Tournament t, TournamentProvider provider, {bool rtl = true}) async {
    final bytes = await Printing.convertHtml(
        format: PdfPageFormat.a4, html: reportHtml(t, provider, rtl: rtl));
    await Printing.sharePdf(bytes: bytes, filename: '${_safe(t.name)}.pdf');
  }
}
