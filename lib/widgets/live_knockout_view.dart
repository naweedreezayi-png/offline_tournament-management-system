import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../live/live_models.dart';
import '../theme/app_theme.dart';
import 'tri_date.dart';

/// Knockout bracket of a real-world cup (World Cup, Champions League, Euro).
/// One column per round, in the order the rounds are played, scrolling
/// horizontally. Only matches whose two teams are already known are shown
/// (the feed omits undecided slots).
class LiveKnockoutView extends StatelessWidget {
  final List<LiveMatch> matches;
  const LiveKnockoutView({super.key, required this.matches});

  @override
  Widget build(BuildContext context) {
    final byStage = <String, List<LiveMatch>>{};
    for (final m in matches) {
      if (m.isKnockout) byStage.putIfAbsent(m.stage!, () => []).add(m);
    }
    final stages = kKnockoutStages.where(byStage.containsKey).toList();
    if (stages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.account_tree_rounded, size: 52, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(context.tr('liveNoKnockout'), textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      itemCount: stages.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, i) {
        final s = stages[i];
        final list = byStage[s]!..sort((a, b) => a.date.compareTo(b.date));
        return _RoundColumn(stage: s, list: list);
      },
    );
  }
}

class _RoundColumn extends StatelessWidget {
  final String stage;
  final List<LiveMatch> list;
  const _RoundColumn({required this.stage, required this.list});

  @override
  Widget build(BuildContext context) {
    final isFinal = stage == 'FINAL';
    return SizedBox(
      width: 232,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
            decoration: BoxDecoration(
              gradient: isFinal ? AppTheme.goldGradient : AppTheme.knockoutGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (isFinal) ...[
                const Icon(Icons.emoji_events_rounded, size: 18, color: Colors.black87),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(context.tr('stage_$stage'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: isFinal ? Colors.black87 : Colors.white)),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _MatchCard(m: list[i], highlight: isFinal),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final LiveMatch m;
  final bool highlight;
  const _MatchCard({required this.m, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = m.date;
    final hw = m.isFinished && m.hasScore && m.homeGoals! > m.awayGoals!;
    final aw = m.isFinished && m.hasScore && m.awayGoals! > m.homeGoals!;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: m.isLive
                ? AppColors.danger
                : highlight
                    ? AppColors.gold.withValues(alpha: 0.7)
                    : cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: TriDate(date: d, fontSize: 9.5)),
            if (m.isLive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration:
                    BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(6)),
                child: Text(context.tr('liveLive'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
              ),
          ]),
          const SizedBox(height: 6),
          _teamRow(context, m.home, m.hasScore ? '${m.homeGoals}' : '–', hw),
          const SizedBox(height: 4),
          _teamRow(context, m.away, m.hasScore ? '${m.awayGoals}' : '–', aw),
        ]),
      ),
    );
  }

  Widget _teamRow(BuildContext context, String name, String score, bool won) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(
        child: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13,
                fontWeight: won ? FontWeight.w800 : FontWeight.w500,
                color: won ? cs.onSurface : cs.onSurface.withValues(alpha: 0.85))),
      ),
      Container(
        constraints: const BoxConstraints(minWidth: 26),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: won ? AppColors.primary : cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(score,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: won ? Colors.white : cs.onSurface)),
      ),
    ]);
  }
}
