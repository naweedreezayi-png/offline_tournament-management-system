import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../live/live_models.dart';
import '../theme/app_theme.dart';
import 'team_avatar.dart';

/// League / group table of a live competition, drawn exactly like the tables of the
/// app's own tournaments (rows as cards, coloured edge for top and bottom places).
class LiveStandingsTable extends StatelessWidget {
  final List<LiveStandingRow> rows;
  final String? title;
  const LiveStandingsTable({super.key, required this.rows, this.title});

  static Color edge(int index, int total) {
    if (index == 0) return const Color(0xFF0B7A3F);
    if (index == 1) return const Color(0xFF2FA968);
    if (index == 2) return const Color(0xFF7FCBA0);
    final fromEnd = total - 1 - index;
    if (total > 5) {
      if (fromEnd == 0) return const Color(0xFFB3261E);
      if (fromEnd == 1) return const Color(0xFFE05B4E);
      if (fromEnd == 2) return const Color(0xFFF3A79C);
    }
    return Colors.transparent;
  }

  Widget _h(BuildContext c, String k, {bool bold = false}) => SizedBox(
        width: 30,
        child: Text(c.tr(k),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11, color: mutedText(c), fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      );

  Widget _v(String v, {bool bold = false}) => SizedBox(
        width: 30,
        child: Text(v,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
          child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          const SizedBox(width: 28),
          const Expanded(flex: 3, child: SizedBox()),
          _h(context, 'pld'),
          _h(context, 'win'),
          _h(context, 'draw'),
          _h(context, 'loss'),
          _h(context, 'gd'),
          _h(context, 'pts', bold: true),
        ]),
      ),
      for (var i = 0; i < rows.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: edge(i, rows.length), width: 4)),
          ),
          child: Row(children: [
            SizedBox(
                width: 28,
                child: Text('${rows[i].position}', style: const TextStyle(fontWeight: FontWeight.bold))),
            Expanded(
              flex: 3,
              child: Row(children: [
                TeamAvatar(name: rows[i].team, radius: 12),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(rows[i].team,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
            _v('${rows[i].played}'),
            _v('${rows[i].won}'),
            _v('${rows[i].draw}'),
            _v('${rows[i].lost}'),
            _v('${rows[i].goalDiff}'),
            _v('${rows[i].points}', bold: true),
          ]),
        ),
    ]);
  }
}
