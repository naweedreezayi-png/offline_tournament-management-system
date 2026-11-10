import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../live/football_data_service.dart';
import '../live/live_models.dart';
import '../live/sports_db_service.dart';
import 'dart:math' as math;
import '../ml/elo_rating_service.dart';
import '../ml/insight.dart';
import '../ml/score_model.dart';
import '../theme/app_theme.dart';
import '../widgets/live_knockout_view.dart';
import '../widgets/live_standings_table.dart';
import '../widgets/tri_date.dart';
import '../widgets/team_avatar.dart';

class LiveLeagueDetailScreen extends StatefulWidget {
  final LiveCompetition competition;
  const LiveLeagueDetailScreen({super.key, required this.competition});

  @override
  State<LiveLeagueDetailScreen> createState() => _LiveLeagueDetailScreenState();
}

class _LiveLeagueDetailScreenState extends State<LiveLeagueDetailScreen> {
  LiveCompetitionData? _data;
  RatingModel? _model;
  GoalModel? _goals;
  List<RatingEvent> _events = const [];
  LiveException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = widget.competition;
      final d = c.isFootballData
          ? await FootballDataService.instance.load(c.code, force: force)
          : await SportsDbService.instance.load(c.code, force: force);
      final model = FootballDataService.instance.trainModel(d.finished,
          profile: SportProfiles.of(c.sport), homeField: c.homeField);
      // Goal model (football only): learned from the same finished matches.
      final fin = [...d.finished]..sort((a, b) => a.date.compareTo(b.date));
      final events = <RatingEvent>[
        for (var i = 0; i < fin.length; i++)
          RatingEvent(
            matchId: '${fin[i].id}',
            tournamentId: 'live',
            teamA: fin[i].home,
            teamB: fin[i].away,
            goalsA: fin[i].homeGoals!,
            goalsB: fin[i].awayGoals!,
            resultA: fin[i].homeGoals == fin[i].awayGoals ? 0.5 : (fin[i].homeGoals! > fin[i].awayGoals! ? 1.0 : 0.0),
            seq: i,
          )
      ];
      final homeFactor = c.homeField ? math.pow(10, model.homeAdvantage / 800).toDouble().clamp(1.0, 1.3).toDouble() : 1.0;
      final goals = c.sport == 'football' ? GoalModel.train(events, homeFactor: homeFactor) : null;
      if (!mounted) return;
      setState(() {
        _data = d;
        _events = events;
        _goals = goals;
        _model = model;
        _loading = false;
      });
    } on LiveException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = LiveException(LiveErrorType.other, '$e');
        _loading = false;
      });
    }
  }

  /// Cups always have a knockout tab; other competitions get one only when the
  /// feed contains play-off rounds (cricket / basketball / volleyball).
  bool get _showKnockout =>
      widget.competition.isCup || (_data?.matches.any((m) => m.isKnockout) ?? false);

  String _errorText(BuildContext context, LiveException e) {
    switch (e.type) {
      case LiveErrorType.noKey:
        return context.tr('liveErrNoKey');
      case LiveErrorType.badKey:
        return context.tr('liveErrBadKey');
      case LiveErrorType.restricted:
        return context.tr('liveErrRestricted');
      case LiveErrorType.rateLimit:
        return context.tr('liveErrRate');
      case LiveErrorType.network:
        return context.tr('liveErrNetwork');
      case LiveErrorType.other:
        return '${context.tr('liveErrOther')} ${e.detail}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final showKo = _showKnockout;
    return DefaultTabController(
      key: ValueKey(showKo),
      length: showKo ? 4 : 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.competition.name, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: context.tr('liveRefresh'),
              onPressed: _loading ? null : () => _load(force: true),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: context.tr('liveFixtures')),
              Tab(text: context.tr('liveResults')),
              Tab(text: context.tr(widget.competition.isCup ? 'liveTableCup' : 'liveTable')),
              if (showKo) Tab(text: context.tr('liveKnockout')),
            ],
            isScrollable: showKo,
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView(context)
                : _content(context),
      ),
    );
  }

  Widget _errorView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_errorText(context, _error!), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _load(force: true),
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('liveRefresh')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final d = _data!;
    final model = _model!;
    final info = context
        .tr('liveModelInfo')
        .replaceAll('{n}', '${d.finished.length}')
        .replaceAll('{a}', model.evaluated == 0 ? '—' : '${(model.accuracy * 100).round()}');
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppColors.primary.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            const Icon(Icons.psychology, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(info, style: const TextStyle(fontSize: 12))),
            if (d.fromCache)
              Text(context.tr('liveOffline'),
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
          ]),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _fixtures(context, d, model),
              _results(context, d),
              _tables(context, d),
              if (_showKnockout) LiveKnockoutView(matches: d.matches),
            ],
          ),
        ),
        if (!widget.competition.isFootballData)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(context.tr('liveOtherNote'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange.shade700, fontSize: 11)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(context.tr('liveDisclaimer'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
        ),
      ],
    );
  }

  Widget _empty(String text) => Center(
      child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center)));

  Widget _fixtures(BuildContext context, LiveCompetitionData d, RatingModel model) {
    final list = d.upcoming;
    if (list.isEmpty) return _empty(context.tr('liveNoUpcoming'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final m = list[i];
        final ins = MatchInsight.build(
            model: model,
            goals: _goals,
            events: _events,
            a: m.home,
            b: m.away,
            allowDraw: widget.competition.isFootballData);
        final p = ins.blended;
        final fc = ins.forecast;
        int pc(double v) => (v * 100).round();
        final fa = (p.pA * 1000).round().clamp(1, 1000);
        final fd = (p.pDraw * 1000).round();
        final fb = (p.pB * 1000).round().clamp(1, 1000);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: TriDate(date: m.date),
                  ),
                  if (m.isLive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                      child: Text(context.tr('liveLive'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  else if (m.matchday != null)
                    Text('${context.tr('liveMatchday')} ${m.matchday}',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _teamCol(m.home)),
                  const Text('vs', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: _teamCol(m.away)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 8,
                    child: Row(children: [
                      Expanded(flex: fa, child: Container(color: AppColors.success)),
                      if (fd > 0) Expanded(flex: fd, child: Container(color: Colors.grey)),
                      Expanded(flex: fb, child: Container(color: Theme.of(context).colorScheme.secondary)),
                    ]),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${pc(p.pA)}%',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: AppColors.success)),
                    if (fd > 0)
                      Text('${context.tr('drawLabel')} ${pc(p.pDraw)}%',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    Text('${pc(p.pB)}%',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary)),
                  ],
                ),
                if (fc != null) ...[
                  const SizedBox(height: 6),
                  Text(
                      '${context.tr('aiLiveScore')}: ${fc.mostLikely[0]} - ${fc.mostLikely[1]}   ·   xG ${fc.lambdaA.toStringAsFixed(1)} - ${fc.lambdaB.toStringAsFixed(1)}',
                      style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _teamCol(String name) => Column(children: [
        TeamAvatar(name: name, radius: 18),
        const SizedBox(height: 4),
        Text(name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]);

  Widget _results(BuildContext context, LiveCompetitionData d) {
    final list = d.finished;
    if (list.isEmpty) return _empty(context.tr('liveNoResults'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final m = list[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TriDate(date: m.date),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: Text(m.home,
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: m.homeGoals! > m.awayGoals!
                                ? FontWeight.bold
                                : FontWeight.normal))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('${m.homeGoals} - ${m.awayGoals}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                    child: Text(m.away,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: m.awayGoals! > m.homeGoals!
                                ? FontWeight.bold
                                : FontWeight.normal))),
              ]),
            ]),
          ),
        );
      },
    );
  }

  static String _groupTitle(String t) {
    final s = t.replaceAll('_', ' ').toLowerCase();
    return s.isEmpty ? t : s[0].toUpperCase() + s.substring(1);
  }

  Widget _tables(BuildContext context, LiveCompetitionData d) {
    if (d.tables.isEmpty) return _empty(context.tr('liveNoTable'));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final g in d.tables)
          LiveStandingsTable(
            rows: g.rows,
            title: (g.title != null && d.tables.length > 1) ? _groupTitle(g.title!) : null,
          ),
      ],
    );
  }
}
