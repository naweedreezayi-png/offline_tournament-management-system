import 'package:flutter/material.dart';
import '../data/api_client.dart';
import 'package:provider/provider.dart';

import '../domain/race.dart';
import '../ml/elo_rating_service.dart';
import 'dart:math' as math;
import '../l10n/app_strings.dart';
import '../models/match_model.dart';
import '../models/tournament.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';

/// Result screen of a single-start event (dash, athletics, swimming, cycling):
/// podium on top, then every entrant ranked by time. Tap an entrant to enter
/// the time or a status (did not finish / start, disqualified).
class RaceView extends StatelessWidget {
  final Tournament tournament;
  const RaceView({super.key, required this.tournament});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final t = tournament;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final results = {for (final m in t.matches) m.teamAId!: provider.raceResultOf(m)};
    final ranks = Race.rank(results);

    int group(MatchModel m) {
      final r = results[m.teamAId!];
      if (r == null) return 1; // waiting for a result
      return r.status == RaceStatus.finished ? 0 : 2; // finished first, DNF/DNS/DSQ last
    }

    final entries = [...t.matches]..sort((a, b) {
        final g = group(a).compareTo(group(b));
        if (g != 0) return g;
        if (group(a) == 0) {
          final c = results[a.teamAId!]!.timeMs!.compareTo(results[b.teamAId!]!.timeMs!);
          if (c != 0) return c;
        }
        return a.order.compareTo(b.order);
      });

    final podium = [for (final m in entries) if ((ranks[m.teamAId!] ?? 99) <= 3) m];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: dark ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.flag_rounded, color: cs.secondary),
              const SizedBox(width: 10),
              Expanded(child: Text(context.tr('raceNote'), style: TextStyle(color: cs.onSurface, height: 1.4))),
            ],
          ),
        ),
        if (results.values.any((r) => r == null)) _AiFavourites(tournament: t, pendingIds: [for (final m in t.matches) if (results[m.teamAId!] == null) m.teamAId!]),
        if (podium.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final m in podium) _PodiumTile(entry: m, tournament: t, place: ranks[m.teamAId!]!, time: results[m.teamAId!]!.timeMs!),
        ],
        const SizedBox(height: 16),
        Text(context.tr('raceRanking'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        for (final m in entries)
          _EntryRow(
            tournament: t,
            entry: m,
            place: ranks[m.teamAId!],
            result: results[m.teamAId!],
          ),
      ],
    );
  }
}

/// AI title chances of the entrants that have no result yet: a Bradley-Terry style share
/// of the learned ratings (rating = what the app learned from earlier races of this sport).
class _AiFavourites extends StatelessWidget {
  final Tournament tournament;
  final List<String> pendingIds;
  const _AiFavourites({required this.tournament, required this.pendingIds});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RatingModel>(
      future: EloRatingService.instance.train(sport: tournament.sport),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final m = snap.data!;
        final rows = <MapEntry<String, double>>[];
        for (final id in pendingIds) {
          final team = tournament.teamById(id);
          if (team == null) continue;
          rows.add(MapEntry(team.name, math.pow(10, m.ratingOf(team.name) / m.scale).toDouble()));
        }
        final known = pendingIds.any((id) {
          final team = tournament.teamById(id);
          return team != null && m.playedOf(team.name) > 0;
        });
        if (rows.length < 2 || !known) return const SizedBox.shrink();
        final total = rows.fold<double>(0, (s, e) => s + e.value);
        rows.sort((a, b) => b.value.compareTo(a.value));
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.psychology_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(context.tr('aiRaceFavourites'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                for (final e in rows.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(width: 110, child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: e.value / total, minHeight: 8, color: AppColors.primary, backgroundColor: AppColors.primary.withValues(alpha: 0.15)),
                        ),
                      ),
                      SizedBox(width: 44, child: Text('${(e.value / total * 100).round()}%', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
                    ]),
                  ),
                Text(context.tr('aiRaceFavouritesHint'),
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _PodiumTile extends StatelessWidget {
  final MatchModel entry;
  final Tournament tournament;
  final int place;
  final int time;
  const _PodiumTile({required this.entry, required this.tournament, required this.place, required this.time});

  @override
  Widget build(BuildContext context) {
    final team = tournament.teamById(entry.teamAId);
    final colors = {1: AppColors.gold, 2: const Color(0xFFB8C4E0), 3: const Color(0xFFCD8F5B)};
    final c = colors[place] ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: place == 1 ? AppTheme.goldGradient : null,
        color: place == 1 ? null : c.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_rounded, color: place == 1 ? const Color(0xFF3A2A00) : c, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(team?.name ?? '?',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: place == 1 ? const Color(0xFF2B1F00) : Theme.of(context).colorScheme.onSurface)),
          ),
          Text(Race.formatTime(time),
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: place == 1 ? const Color(0xFF2B1F00) : Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final Tournament tournament;
  final MatchModel entry;
  final int? place;
  final RaceResult? result;
  const _EntryRow({required this.tournament, required this.entry, required this.place, required this.result});

  String _statusText(BuildContext context) {
    final r = result;
    if (r == null) return context.tr('raceNoResult');
    switch (r.status) {
      case RaceStatus.finished:
        return Race.formatTime(r.timeMs!);
      case RaceStatus.dnf:
        return 'DNF';
      case RaceStatus.dns:
        return 'DNS';
      case RaceStatus.dsq:
        return 'DSQ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final team = tournament.teamById(entry.teamAId);
    final bad = result != null && result!.status != RaceStatus.finished;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: ApiClient.instance.canEdit(tournament) ? () => _enter(context) : null,
        leading: CircleAvatar(
          backgroundColor: place != null ? AppColors.primary : cs.surfaceContainerHighest,
          child: Text(place?.toString() ?? '–',
              style: TextStyle(fontWeight: FontWeight.w800, color: place != null ? Colors.white : cs.onSurface)),
        ),
        title: Text(team?.name ?? '?', style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Text(_statusText(context),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: bad ? AppColors.danger : (result == null ? cs.onSurfaceVariant : cs.secondary))),
      ),
    );
  }

  Future<void> _enter(BuildContext context) async {
    final provider = context.read<TournamentProvider>();
    final out = await showDialog<_Picked>(
      context: context,
      builder: (_) => _EnterDialog(name: tournament.teamById(entry.teamAId)?.name ?? '?', current: result),
    );
    if (out == null) return;
    await provider.setRaceResult(tournament, entry, out.clear ? null : out.result);
  }
}

class _Picked {
  final RaceResult? result;
  final bool clear;
  const _Picked(this.result, {this.clear = false});
}

class _EnterDialog extends StatefulWidget {
  final String name;
  final RaceResult? current;
  const _EnterDialog({required this.name, required this.current});

  @override
  State<_EnterDialog> createState() => _EnterDialogState();
}

class _EnterDialogState extends State<_EnterDialog> {
  late RaceStatus _status = widget.current?.status ?? RaceStatus.finished;
  late final TextEditingController _time = TextEditingController(
      text: widget.current?.timeMs != null ? Race.formatTime(widget.current!.timeMs!) : '');
  String? _error;

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  void _save() {
    if (_status == RaceStatus.finished) {
      final ms = Race.parseTime(_time.text);
      if (ms == null) {
        setState(() => _error = context.tr('raceBadTime'));
        return;
      }
      Navigator.pop(context, _Picked(RaceResult(RaceStatus.finished, ms)));
    } else {
      Navigator.pop(context, _Picked(RaceResult(_status)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = {
      RaceStatus.finished: context.tr('raceFinished'),
      RaceStatus.dnf: context.tr('raceDnf'),
      RaceStatus.dns: context.tr('raceDns'),
      RaceStatus.dsq: context.tr('raceDsq'),
    };
    return AlertDialog(
      title: Text(widget.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final s in RaceStatus.values)
                  ChoiceChip(
                    label: Text(labels[s]!),
                    selected: _status == s,
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _status == s ? Colors.white : Theme.of(context).colorScheme.onSurface),
                    onSelected: (_) => setState(() {
                      _status = s;
                      _error = null;
                    }),
                  ),
              ],
            ),
            if (_status == RaceStatus.finished) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _time,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: context.tr('raceTime'),
                  errorText: _error,
                  prefixIcon: const Icon(Icons.timer_outlined),
                ),
                onSubmitted: (_) => _save(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
              onPressed: () => Navigator.pop(context, const _Picked(null, clear: true)),
              child: Text(context.tr('delete'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(onPressed: _save, child: Text(context.tr('saveShort'))),
      ],
    );
  }
}
