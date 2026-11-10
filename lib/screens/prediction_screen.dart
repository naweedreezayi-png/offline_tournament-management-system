import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/prediction_signature.dart';
import '../l10n/app_strings.dart';
import '../ml/elo_rating_service.dart';
import '../ml/tournament_simulator.dart';
import '../models/tournament.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/team_avatar.dart';

/// AI forecast for a tournament: title chances (and stage chances) obtained
/// by simulating the remaining matches with the Elo rating model. It
/// recomputes automatically whenever a result is entered or undone.
class PredictionScreen extends StatefulWidget {
  final String tournamentId;
  const PredictionScreen({super.key, required this.tournamentId});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  Forecast? _fc;
  Map<String, double> _delta = {};
  bool _busy = false;
  String _requested = '';
  int _view = 0;

  String _signature(Tournament t) => PredictionSignature.of(t);

  Future<void> _compute(Tournament t, String sig) async {
    if (mounted) setState(() => _busy = true);
    Forecast? fc;
    Map<String, double> delta = {};
    try {
      EloRatingService.instance
          .ingestAll(context.read<TournamentProvider>().activeTournaments);
      await EloRatingService.instance.syncTournament(t);
      final model = await EloRatingService.instance.train(sport: t.sport);
      fc = await TournamentSimulator.run(t, model);
      delta = await _deltaFor(t, sig, fc);
    } catch (_) {
      fc = null;
    }
    if (!mounted || _requested != sig) return;
    setState(() {
      if (fc != null) {
        _fc = fc;
        _delta = delta;
      }
      _busy = false;
    });
  }

  /// Change in title chance since the previous state of the tournament
  /// (persisted per tournament, one snapshot per result count).
  Future<Map<String, double>> _deltaFor(Tournament t, String sig, Forecast fc) async {
    final cur = {for (final f in fc.teams) f.id: f.pChampion};
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'pred_snap_${t.id}';
      Map<String, dynamic>? saved;
      final raw = prefs.getString(key);
      if (raw != null) saved = jsonDecode(raw) as Map<String, dynamic>;
      Map<String, dynamic>? prev;
      if (saved != null) {
        prev = (saved['sig'] == sig ? saved['prev'] : saved['cur']) as Map<String, dynamic>?;
      }
      await prefs.setString(key, jsonEncode({'sig': sig, 'cur': cur, 'prev': prev}));
      if (prev == null) return {};
      return {
        for (final e in cur.entries)
          if (prev[e.key] is num) e.key: e.value - (prev[e.key] as num).toDouble()
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final exists = provider.activeTournaments.any((t) => t.id == widget.tournamentId) ||
        provider.deletedTournaments.any((t) => t.id == widget.tournamentId);
    if (!exists) return Scaffold(appBar: AppBar(), body: const SizedBox());
    final t = provider.byId(widget.tournamentId);
    final sig = _signature(t);
    if (_requested != sig) {
      _requested = sig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _compute(t, sig);
      });
    }

    final fc = _fc;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('predictions')),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: t.teams.length < 2
          ? _message(context.tr('predNeedTeams'))
          : fc == null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(context.tr('predCalculating')),
                  ]),
                )
              : _body(context, t, fc),
    );
  }

  Widget _message(String text) => Center(
      child: Padding(padding: const EdgeInsets.all(28), child: Text(text, textAlign: TextAlign.center)));

  // ------------------------------------------------------------------ body

  Widget _body(BuildContext context, Tournament t, Forecast fc) {
    final ranked = fc.ranked;
    final views = [
      context.tr('predRanking'),
      context.tr('predEntryOrder'),
      fc.kind == ForecastKind.league ? context.tr('predPositions') : context.tr('predStages'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _notice(context, fc),
        if (!fc.allUnknown) _hero(context, t, ranked.first),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: views.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text(views[i]),
              selected: _view == i,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(color: _view == i ? Colors.white : null),
              onSelected: (_) => setState(() => _view = i),
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(
            key: ValueKey('$_view-${fc.trials}-${ranked.first.pChampion}'),
            child: switch (_view) {
              0 => _bars(context, t, fc, ranked, showRank: true),
              1 => _bars(context, t, fc, fc.teams, showRank: false),
              _ => _heatmap(context, t, fc, ranked),
            },
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('predFooter').replaceAll('{n}', '${fc.trials}'),
          style: TextStyle(color: mutedText(context), fontSize: 11),
        ),
      ],
    );
  }

  Widget _notice(BuildContext context, Forecast fc) {
    String? text;
    IconData icon = Icons.info_outline;
    if (fc.allUnknown) {
      text = context.tr('predBannerAll');
      icon = Icons.school_outlined;
    } else if (fc.unknownCount > 0) {
      text = context.tr('predBannerSome').replaceAll('{n}', '${fc.unknownCount}');
    } else if (fc.preBracket) {
      text = context.tr('predGroupsNote');
    }
    if (text == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.orange.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
      ]),
    );
  }

  Widget _hero(BuildContext context, Tournament t, TeamForecast top) {
    final team = t.teamById(top.id);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        Container(
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_pct(top.pChampion),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: top.pChampion.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('predFavorite'),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Row(children: [
              if (team != null) ...[
                TeamAvatar(name: team.name, imagePath: team.imagePath, radius: 14),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(top.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ]),
            if (!top.known)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(context.tr('predInsufficient'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
          ]),
        ),
      ]),
    );
  }

  static String _pct(double p) {
    final v = p * 100;
    if (v <= 0) return '0%';
    if (v < 0.1) return '<0.1%';
    return v < 10 ? '${v.toStringAsFixed(1)}%' : '${v.round()}%';
  }

  // ------------------------------------------------------------------ bars

  Widget _bars(BuildContext context, Tournament t, Forecast fc, List<TeamForecast> list,
      {required bool showRank}) {
    final maxP = fc.teams.fold<double>(0, (m, e) => max(m, e.pChampion));
    return Column(
      children: [
        for (var i = 0; i < list.length; i++)
          _probRow(context, t, fc, list[i], i, maxP, showRank),
      ],
    );
  }

  Widget _probRow(BuildContext context, Tournament t, Forecast fc, TeamForecast f, int i,
      double maxP, bool showRank) {
    final team = t.teamById(f.id);
    final delta = (_delta[f.id] ?? 0) * 100;
    final base = f.known ? AppColors.primary : Colors.grey;
    final extra = (fc.kind == ForecastKind.league || fc.preBracket) && f.known
        ? ' · ${context.tr('predExpPts')} ${f.expectedPoints.toStringAsFixed(1)}'
        : '';
    final sub = f.known
        ? '${f.rating.round()} · ${f.matches} ${context.tr('predMatches')}$extra'
        : context.tr('predInsufficient');
    final factor = maxP <= 0 ? 0.0 : (f.pChampion / maxP).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(
          width: 26,
          child: showRank
              ? Text('${i + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: i < 3 && f.known ? Theme.of(context).colorScheme.secondary : Colors.grey))
              : const SizedBox.shrink(),
        ),
        TeamAvatar(name: f.name, imagePath: team?.imagePath, radius: 17),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              if (!f.known)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.help_outline, size: 15, color: Colors.grey),
                ),
            ]),
            const SizedBox(height: 4),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: factor),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LayoutBuilder(
                builder: (_, c) => Stack(children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: base.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: max(4.0, c.maxWidth * v),
                      height: 10,
                      child: f.known
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                                  AppColors.primary,
                                  AppColors.primary.withValues(alpha: 0.65),
                                ]),
                              ),
                            )
                          : CustomPaint(painter: _HatchPainter(Colors.grey)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(fontSize: 11, color: mutedText(context))),
          ]),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 58,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_pct(f.pChampion),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: f.known ? null : Colors.grey)),
            if (delta.abs() >= 0.5)
              Text('${delta > 0 ? '▲' : '▼'} ${delta.abs().toStringAsFixed(1)}',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: delta > 0 ? AppColors.success : AppColors.danger)),
          ]),
        ),
      ]),
    );
  }

  // --------------------------------------------------------------- heatmap

  List<String> _stageHeaders(BuildContext context, Forecast fc) {
    if (fc.kind == ForecastKind.league) {
      return [for (var i = 0; i < fc.stageCount; i++) '#${i + 1}'];
    }
    final R = fc.totalRounds;
    return [
      for (var r = 0; r < R; r++)
        switch (R - 1 - r) {
          0 => 'F',
          1 => 'SF',
          2 => 'QF',
          final e => 'R${1 << (e + 1)}',
        }
    ];
  }

  Widget _heatmap(BuildContext context, Tournament t, Forecast fc, List<TeamForecast> ranked) {
    final headers = _stageHeaders(context, fc);
    final isKo = fc.kind == ForecastKind.knockout;
    final cols = [...headers, if (isKo) context.tr('predChampion')];
    const rowH = 36.0, cellW = 58.0;

    Widget cell(String text, Color bg, {Color? fg, bool bold = false}) => Container(
          width: cellW,
          height: rowH - 4,
          margin: const EdgeInsets.all(2),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Text(text,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: fg)),
        );

    Color heat(double p, bool known) {
      final a = (sqrt(p.clamp(0.0, 1.0)) * 0.9).clamp(0.05, 0.9);
      return (known ? AppColors.primary : Colors.grey).withValues(alpha: a);
    }

    final legend = isKo
        ? 'F = ${context.tr('final')} · SF = ${context.tr('semiFinals')} · QF = ${context.tr('quarterFinals')} · R16 = ${context.tr('roundOf')} 16'
        : context.tr('predPositionsLegend');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 112,
          child: Column(children: [
            const SizedBox(height: rowH),
            for (final f in ranked)
              SizedBox(
                height: rowH,
                child: Row(children: [
                  Expanded(
                    child: Text(f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: f.known ? null : Colors.grey)),
                  ),
                  if (!f.known) const Icon(Icons.help_outline, size: 13, color: Colors.grey),
                ]),
              ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(children: [
              Row(children: [
                for (final c in cols)
                  SizedBox(
                    width: cellW + 4,
                    height: rowH,
                    child: Center(
                        child: Text(c,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold))),
                  ),
              ]),
              for (final f in ranked)
                Row(children: [
                  for (var i = 0; i < headers.length; i++)
                    cell(
                      i < f.stage.length ? _pct(f.stage[i]) : '–',
                      heat(i < f.stage.length ? f.stage[i] : 0, f.known),
                    ),
                  if (isKo)
                    cell(_pct(f.pChampion), heat(f.pChampion, f.known), bold: true),
                ]),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Text(legend, style: TextStyle(fontSize: 11, color: mutedText(context))),
    ]);
  }
}

// ----------------------------------------------------------------- painters

class _HatchPainter extends CustomPainter {
  final Color color;
  _HatchPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color.withValues(alpha: 0.25));
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    for (double x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => false;
}
