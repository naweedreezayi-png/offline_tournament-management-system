import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/team.dart';
import '../theme/app_theme.dart';
import 'team_avatar.dart';

class PodiumEntry {
  final int rank; // 1, 2, or 3 — rank 3 may appear twice (joint bronze)
  final Team team;
  const PodiumEntry(this.rank, this.team);
}

/// Shared podium + vertical results table, used both by the knockout
/// final-results screen and the league final-results screen. There is
/// intentionally no 4th place anywhere in this widget.
class PodiumResultsView extends StatelessWidget {
  final String title;
  final List<PodiumEntry> entries;
  final bool showTable;

  const PodiumResultsView({
    super.key,
    required this.title,
    required this.entries,
    this.showTable = true,
  });

  @override
  Widget build(BuildContext context) {
    final first = entries.where((e) => e.rank == 1).map((e) => e.team).toList();
    final second = entries.where((e) => e.rank == 2).map((e) => e.team).toList();
    final thirds = entries.where((e) => e.rank == 3).map((e) => e.team).toList();

    final blocks = <Widget>[];

    if (second.isNotEmpty) {
      blocks.add(_PodiumBlock(
        team: second.first,
        place: 2,
        height: 130,
        color: const Color(0xFFB0B4C1),
      ));
    }
    if (first.isNotEmpty) {
      blocks.add(_PodiumBlock(
        team: first.first,
        place: 1,
        height: 170,
        color: const Color(0xFFFFD86B),
      ));
    }
    for (int i = 0; i < thirds.length; i++) {
      blocks.add(_PodiumBlock(
        team: thirds[i],
        place: 3,
        height: 95,
        color: const Color(0xFFE0A672),
      ));
    }

    final combined = [
      ...first.map((t) => PodiumEntry(1, t)),
      ...second.map((t) => PodiumEntry(2, t)),
      ...thirds.map((t) => PodiumEntry(3, t)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD86B), size: 36),
              const SizedBox(height: 8),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: blocks,
            ),
          ),
        ),
        if (showTable) ...[
          const SizedBox(height: 36),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(context.tr('finalResults'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(56),
                  1: FlexColumnWidth(),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15)),
                    children: [
                      _headerCell(context, context.tr('rank')),
                      _headerCell(context, context.tr('team')),
                    ],
                  ),
                  for (int idx = 0; idx < combined.length; idx++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: idx.isEven ? Colors.transparent : AppColors.primary.withValues(alpha: 0.04),
                      ),
                      children: [
                        _rankCell(combined[idx].rank),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          child: Row(
                            children: [
                              TeamAvatar(name: combined[idx].team.name, imagePath: combined[idx].team.imagePath, radius: 14),
                              const SizedBox(width: 10),
                              Expanded(child: Text(combined[idx].team.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _headerCell(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      );

  Widget _rankCell(int rank) {
    final medalColor = rank == 1
        ? const Color(0xFFFFD86B)
        : rank == 2
            ? const Color(0xFFB0B4C1)
            : const Color(0xFFE0A672);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: medalColor.withValues(alpha: 0.25),
        child: Text('$rank', style: TextStyle(color: medalColor, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _PodiumBlock extends StatelessWidget {
  final Team team;
  final int place;
  final double height;
  final Color color;

  const _PodiumBlock({
    required this.team,
    required this.place,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (place == 1)
          const Icon(Icons.emoji_events, color: Color(0xFFFFD86B), size: 32),
        const SizedBox(height: 6),
        TeamAvatar(name: team.name, imagePath: team.imagePath, radius: place == 1 ? 26 : 22),
        const SizedBox(height: 6),
        SizedBox(
          width: 80,
          child: Text(team.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        Container(
          width: 80,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.zero,
            border: const Border(top: BorderSide(color: Colors.white24, width: 1)),
            boxShadow: place == 1
                ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, -4))]
                : null,
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 10),
          child: Text('$place',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ],
    );
  }
}
