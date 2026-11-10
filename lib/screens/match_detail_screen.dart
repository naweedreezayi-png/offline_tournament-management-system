import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/api_client.dart';
import '../domain/sport_scoring.dart';
import '../l10n/app_strings.dart';
import '../models/match_model.dart';
import '../models/tournament.dart';
import '../providers/settings_provider.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/detailed_result_dialog.dart';
import '../widgets/gradient_button.dart';
import '../widgets/team_avatar.dart';
import '../widgets/tri_date.dart';
import '../widgets/win_probability_card.dart';

enum _Step { single, leg1, leg2, penalties }

class MatchDetailScreen extends StatefulWidget {
  final Tournament tournament;
  final MatchModel match;
  final bool isLeague;

  /// Finished matches are opened read-only: shows the result and how it was reached.
  final bool readOnly;

  const MatchDetailScreen({
    super.key,
    required this.tournament,
    required this.match,
    required this.isLeague,
    this.readOnly = false,
  });

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  late _Step _step;
  late int _scoreA;
  late int _scoreB;
  String? _detail;
  DateTime? _when;

  bool get _isTwoLegged => !widget.isLeague && widget.tournament.isTwoLeggedMatch(widget.match);

  @override
  void initState() {
    super.initState();
    final m = widget.match;
    _detail = m.detail;
    _when = m.scheduledAt;
    if (!_isTwoLegged) {
      _step = _Step.single;
      _scoreA = m.scoreA ?? 0;
      _scoreB = m.scoreB ?? 0;
    } else if (m.scoreA == null) {
      _step = _Step.leg1;
      _scoreA = 0;
      _scoreB = 0;
    } else if (m.scoreA2 == null) {
      _step = _Step.leg2;
      _scoreA = 0;
      _scoreB = 0;
    } else if (m.penA != null) {
      // penalties were already entered once — allow correcting them
      _step = _Step.penalties;
      _scoreA = m.penA ?? 0;
      _scoreB = m.penB ?? 0;
    } else if (!m.isPlayed) {
      // aggregate is tied and penalties haven't been entered yet
      _step = _Step.penalties;
      _scoreA = 0;
      _scoreB = 0;
    } else {
      // aggregate was already decisive — allow correcting leg 2 if needed
      _step = _Step.leg2;
      _scoreA = m.scoreA2 ?? 0;
      _scoreB = m.scoreB2 ?? 0;
    }
  }

  String _stepTitle(BuildContext context) {
    switch (_step) {
      case _Step.single:
        return context.tr('enterResult');
      case _Step.leg1:
        return context.tr('leg1');
      case _Step.leg2:
        return context.tr('leg2');
      case _Step.penalties:
        return context.tr('penalties');
    }
  }

  Future<void> _pickDate() async {
    final res = await showTriDatePicker(context, initial: _when);
    if (!mounted || res == null) return;
    final when = res.cleared ? null : res.value;
    await context.read<TournamentProvider>().setMatchSchedule(widget.tournament, widget.match, when);
    if (mounted) setState(() => _when = when);
  }

  Future<void> _openDetail(String nameA, String nameB) async {
    final scoring = SportScoring.of(widget.tournament.sport);
    if (scoring == null) return;
    final lang = context.read<SettingsProvider>().languageCode;
    final res = await showDialog<DetailedResult>(
      context: context,
      builder: (_) => DetailedResultDialog(
        scoring: scoring,
        teamA: nameA,
        teamB: nameB,
        lang: lang,
        initial: SportScoring.inputOf(_detail),
      ),
    );
    if (!mounted || res == null) return;
    setState(() {
      _scoreA = res.outcome.scoreA;
      _scoreB = res.outcome.scoreB;
      _detail = SportScoring.encode(scoring, res.input, res.outcome);
    });
  }

  void _save() {
    final provider = context.read<TournamentProvider>();
    final t = widget.tournament;
    final m = widget.match;

    // Knockout ties can never end level — a single match (including the
    // final) or a penalty shootout must always produce a winner.
    final needsDecisiveResult =
        !widget.isLeague && (_step == _Step.single || _step == _Step.penalties);
    if (needsDecisiveResult && _scoreA == _scoreB) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('drawNotAllowed'))),
      );
      return;
    }

    switch (_step) {
      case _Step.single:
        if (widget.isLeague) {
          provider.recordLeagueResult(t, m, _scoreA, _scoreB);
        } else {
          provider.recordKnockoutResult(t, m, _scoreA, _scoreB);
        }
        if (_detail != m.detail) provider.setMatchDetail(t, m, _detail);
        Navigator.of(context).pop();
        return;
      case _Step.leg1:
        provider.recordKnockoutLeg1(t, m, _scoreA, _scoreB);
        Navigator.of(context).pop();
        return;
      case _Step.leg2:
        provider.recordKnockoutLeg2(t, m, _scoreA, _scoreB);
        if (m.isPlayed) {
          Navigator.of(context).pop();
        } else {
          // aggregate tied — move straight to a penalty shootout
          setState(() {
            _step = _Step.penalties;
            _scoreA = 0;
            _scoreB = 0;
          });
        }
        return;
      case _Step.penalties:
        provider.recordKnockoutPenalties(t, m, _scoreA, _scoreB);
        Navigator.of(context).pop();
        return;
    }
  }

  Widget _readOnlyResult(BuildContext context, dynamic a, dynamic b, int aggA, int aggB) {
    final m = widget.match;
    final two = _isTwoLegged;
    final sa = two ? aggA : (m.scoreA ?? 0);
    final sb = two ? aggB : (m.scoreB ?? 0);
    Widget side(dynamic team, bool win) => Expanded(
          child: Column(children: [
            TeamAvatar(name: team.name, imagePath: team.imagePath, radius: 34),
            const SizedBox(height: 10),
            Text(team.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: win ? FontWeight.w900 : FontWeight.w600, fontSize: 15)),
            if (win)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.emoji_events_rounded, color: AppColors.warning, size: 20),
              ),
          ]),
        );
    final winnerA = m.winnerId != null ? m.winnerId == a.id : sa > sb;
    final winnerB = m.winnerId != null ? m.winnerId == b.id : sb > sa;
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        side(a, winnerA),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
          child: Text('$sa - $sb', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
        ),
        side(b, winnerB),
      ]),
      if (two)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              '${context.tr('leg1')}: ${m.scoreA}-${m.scoreB}   ${context.tr('leg2')}: ${m.scoreA2}-${m.scoreB2}'
              '${m.penA != null ? '   ${context.tr('penalties')}: ${m.penA}-${m.penB}' : ''}',
              style: TextStyle(color: mutedText(context), fontSize: 12)),
        ),
    ]);
  }

  /// How the result was reached, in the sport's own scoring (ippon, waza-ari, ...).
  Widget _detailCard(BuildContext context) {
    final scoring = SportScoring.of(widget.tournament.sport);
    final lang = context.read<SettingsProvider>().languageCode;
    final summary = SportScoring.summaryOf(_detail);
    final input = SportScoring.inputOf(_detail);
    final rows = <Widget>[];
    if (scoring != null && input.isNotEmpty) {
      final a = widget.tournament.teamById(widget.match.teamAId)!.name;
      final b = widget.tournament.teamById(widget.match.teamBId)!.name;
      for (final f in scoring.fields) {
        if (f.perSide) {
          final va = input['${f.key}A'] ?? 0, vb = input['${f.key}B'] ?? 0;
          if (va == 0 && vb == 0) continue;
          rows.add(_row(f.label(lang), '$va', '$vb'));
        } else if (input[f.key] != null) {
          final opts = f.optionLabels(lang);
          final i = input[f.key]!;
          final txt = (opts != null && i >= 0 && i < opts.length)
              ? opts[i].replaceAll('{A}', a).replaceAll('{B}', b)
              : '$i';
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text('${f.label(lang)}: $txt', style: const TextStyle(fontSize: 13)),
          ));
        }
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.rule_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(context.tr('resultHow'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          if (summary != null)
            Text(summary, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))
          else
            Text(scoring == null ? context.tr('resultPlainScore') : context.tr('resultNoDetail'),
                style: TextStyle(color: mutedText(context), fontSize: 13)),
          if (rows.isNotEmpty) ...[const Divider(height: 18), ...rows],
        ]),
      ),
    );
  }

  Widget _row(String label, String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 28, child: Text(a, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
          SizedBox(width: 28, child: Text(b, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final m = widget.match;
    final a = t.teamById(m.teamAId)!;
    final b = t.teamById(m.teamBId)!;

    final aggA = (m.scoreA ?? 0) + (m.scoreA2 ?? 0);
    final aggB = (m.scoreB ?? 0) + (m.scoreB2 ?? 0);

    return Scaffold(
      appBar: AppBar(title: Text(widget.readOnly ? context.tr('matchResult') : _stepTitle(context))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (_isTwoLegged)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _step == _Step.leg1
                      ? context.tr('leg1')
                      : _step == _Step.leg2
                          ? '${context.tr('leg2')} (${context.tr('aggregate')}: $aggA-$aggB)'
                          : context.tr('aggregateTied'),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            if (_step == _Step.leg2)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('${context.tr('leg1')}: ${m.scoreA} - ${m.scoreB}',
                    style: TextStyle(color: mutedText(context), fontSize: 12)),
              ),
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.event_rounded, color: AppColors.primary),
                title: Text(context.tr('matchDate'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: _when == null
                    ? Text(context.tr('noDate'), style: TextStyle(color: mutedText(context), fontSize: 12))
                    : TriDate(date: _when!, fontSize: 12),
                trailing: ApiClient.instance.canEdit(widget.tournament)
                    ? IconButton(icon: const Icon(Icons.edit_calendar_rounded), onPressed: _pickDate)
                    : null,
              ),
            ),
            if (widget.readOnly)
              _readOnlyResult(context, a, b, aggA, aggB)
            else
            Row(
              children: [
                Expanded(child: _TeamScoreColumn(
                  team: a,
                  score: _scoreA,
                  onChanged: (v) => setState(() {
                    _scoreA = v;
                    _detail = null;
                  }),
                )),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('-', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
                Expanded(child: _TeamScoreColumn(
                  team: b,
                  score: _scoreB,
                  onChanged: (v) => setState(() {
                    _scoreB = v;
                    _detail = null;
                  }),
                )),
              ],
            ),
            if (widget.readOnly) ...[
              const SizedBox(height: 16),
              _detailCard(context),
            ],
            if (!widget.readOnly && _step == _Step.single && SportScoring.of(t.sport) != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _openDetail(a.name, b.name),
                icon: const Icon(Icons.rule_rounded),
                label: Text(context.tr('detailedResult')),
              ),
              if (SportScoring.summaryOf(_detail) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(SportScoring.summaryOf(_detail)!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedText(context), fontSize: 12)),
                ),
            ],
            const SizedBox(height: 20),
            if (!widget.readOnly)
              WinProbabilityCard(
                  teamA: a.name,
                  teamB: b.name,
                  allowDraw: widget.isLeague,
                  sport: t.sport),
            const Spacer(),
            if (!widget.readOnly)
              GradientButton(
                label: context.tr('save'),
                icon: Icons.check,
                onPressed: _save,
              ),
          ],
        ),
      ),
    );
  }
}

class _TeamScoreColumn extends StatelessWidget {
  final dynamic team;
  final int score;
  final ValueChanged<int> onChanged;

  const _TeamScoreColumn({required this.team, required this.score, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TeamAvatar(name: team.name, imagePath: team.imagePath, radius: 34),
        const SizedBox(height: 10),
        Text(team.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _stepButton(Icons.remove, () {
              if (score > 0) onChanged(score - 1);
            }),
            Container(
              width: 56,
              alignment: Alignment.center,
              child: Text('$score',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            ),
            _stepButton(Icons.add, () => onChanged(score + 1)),
          ],
        ),
      ],
    );
  }

  Widget _stepButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
      ),
    );
  }
}
