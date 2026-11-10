import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../ml/elo_rating_service.dart';
import '../widgets/match_lab.dart';
import '../widgets/ensemble_card.dart';
import '../models/sport.dart';
import '../providers/settings_provider.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';

/// "AI Insights": learned team ratings + live model-quality metrics,
/// separately for every sport (ratings of different sports never mix).
class AiInsightsScreen extends StatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  State<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends State<AiInsightsScreen> {
  String? _sport;
  late Future<Map<String, int>> _sportsFuture;

  @override
  void initState() {
    super.initState();
    // make sure the in-memory copy knows every tournament (works without the database)
    EloRatingService.instance.ingestAll(context.read<TournamentProvider>().activeTournaments);
    _sportsFuture = EloRatingService.instance.sportsWithData();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('aiInsights'))),
      body: FutureBuilder<Map<String, int>>(
        future: _sportsFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('${context.tr('liveErrOther')}\n${snap.error}', textAlign: TextAlign.center)));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final sports = snap.data!;
          // keep the app's sport order; unknown ids (if any) go last
          final ids = [
            for (final s in Sports.all)
              if (sports.containsKey(s.id)) s.id,
            for (final k in sports.keys)
              if (!Sports.all.any((s) => s.id == k)) k,
          ];
          if (ids.isEmpty) {
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(context.tr('aiInsightsDesc'),
                  style: TextStyle(color: mutedText(context), fontSize: 13)),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                    child: Text(context.tr('noRatingsYet'), textAlign: TextAlign.center)),
              ),
            ]);
          }
          final selected = (_sport != null && ids.contains(_sport)) ? _sport! : ids.first;
          return FutureBuilder<RatingModel>(
            key: ValueKey(selected),
            future: EloRatingService.instance.train(sport: selected),
            builder: (context, ms) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(context.tr('aiInsightsDesc'),
                      style: TextStyle(color: mutedText(context), fontSize: 13)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: ids.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final id = ids[i];
                        final sp = Sports.byId(id);
                        return ChoiceChip(
                          avatar: Icon(sp.icon, size: 16, color: sp.color),
                          label: Text('${sp.label(lang)} (${sports[id]})'),
                          selected: id == selected,
                          onSelected: (_) => setState(() => _sport = id),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!ms.hasData)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    ..._content(context, ms.data!, selected),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _content(BuildContext context, RatingModel m, String sportId) {
    final rank = m.ranking;
    return [
      Row(children: [
        _stat(context, context.tr('matchesLearned'),
            '${rank.fold<int>(0, (s, r) => s + r.played) ~/ 2}'),
        const SizedBox(width: 8),
        _stat(context, context.tr('modelAccuracy'),
            m.evaluated == 0 ? '—' : '${(m.accuracy * 100).round()}%'),
        const SizedBox(width: 8),
        _stat(context, context.tr('brierScore'),
            rank.isEmpty ? '—' : m.brier.toStringAsFixed(2)),
      ]),
      const SizedBox(height: 8),
      Text(
        '${context.tr('aiScaleInfo')}: ${m.scale.round()}'
        '${m.profile.draws ? '' : ' · ${context.tr('aiNoDraws')}'}',
        style: TextStyle(color: mutedText(context), fontSize: 12),
      ),
      const SizedBox(height: 14),
      FutureBuilder<List<RatingEvent>>(
        key: ValueKey('lab-$sportId-${rank.length}'),
        future: EloRatingService.instance.eventsOf(sportId),
        builder: (context, es) => !es.hasData
            ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            : Column(children: [
                EnsembleCard(sportId: sportId, events: es.data!),
                const SizedBox(height: 12),
                _calibrationCard(context, m),
                const SizedBox(height: 12),
                MatchLab(sportId: sportId, model: m, events: es.data!),
              ]),
      ),
      const SizedBox(height: 14),
      Text(context.tr('teamRatings'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      for (var i = 0; i < rank.length; i++)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Text('${i + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.primary)),
            ),
            title: Text(rank[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(m.profile.draws
                ? '${context.tr('winsShort')} ${rank[i].wins}  ${context.tr('drawLabel')} ${rank[i].draws}  ${context.tr('lossesShort')} ${rank[i].losses}'
                : '${context.tr('winsShort')} ${rank[i].wins}  ${context.tr('lossesShort')} ${rank[i].losses}'),
            trailing: Text(rank[i].rating.round().toString(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ),
        ),
      const SizedBox(height: 12),
      Text(context.tr('aiModelExplain'),
          style: TextStyle(color: mutedText(context), fontSize: 12)),
    ];
  }

  Widget _calibrationCard(BuildContext context, RatingModel m) {
    if (m.calibration.isEmpty) return const SizedBox.shrink();
    final err = m.calibrationError;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.verified_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(context.tr('aiCalibration'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            if (err != null)
              Text('${context.tr('aiCalibrationError')}: ${(err * 100).round()}%',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text(context.tr('aiCalibrationHelp'),
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          for (final b in m.calibration)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${(b.low * 100).round()}–${(b.high * 100).round()}%  ·  n=${b.count}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                _bar(context, '${context.tr('aiConfidenceLabel')} ${(b.meanConfidence * 100).round()}%', b.meanConfidence, AppColors.primary),
                const SizedBox(height: 2),
                _bar(context, '${context.tr('aiHitLabel')} ${(b.hitRate * 100).round()}%', b.hitRate, AppColors.cyanDeep),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _bar(BuildContext context, String label, double v, Color color) => Row(children: [
        SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 11))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: v.clamp(0, 1).toDouble(), minHeight: 7, color: color, backgroundColor: color.withValues(alpha: 0.15)),
          ),
        ),
      ]);

  Widget _stat(BuildContext context, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: mutedText(context))),
        ]),
      ),
    );
  }
}
