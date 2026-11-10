import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../ml/elo_rating_service.dart';
import '../ml/ensemble_model.dart';
import '../theme/app_theme.dart';

/// Shows how well each model of the ensemble predicted this sport's own history
/// (walk-forward) and lets the user compare their predictions for any two teams.
class EnsembleCard extends StatefulWidget {
  final String sportId;
  final List<RatingEvent> events;
  const EnsembleCard({super.key, required this.sportId, required this.events});

  @override
  State<EnsembleCard> createState() => _EnsembleCardState();
}

class _EnsembleCardState extends State<EnsembleCard> {
  late EnsembleModel _m;
  String? _a, _b;

  @override
  void initState() {
    super.initState();
    _train();
  }

  @override
  void didUpdateWidget(covariant EnsembleCard old) {
    super.didUpdateWidget(old);
    if (old.events.length != widget.events.length || old.sportId != widget.sportId) _train();
  }

  void _train() {
    _m = EnsembleModel.trainFrom(widget.events, profile: SportProfiles.of(widget.sportId));
    final t = _m.teams;
    if (_a == null || !t.contains(_a)) _a = t.isNotEmpty ? t.first : null;
    if (_b == null || !t.contains(_b)) _b = t.length > 1 ? t[1] : null;
  }

  String _name(BuildContext c, String id) => c.tr('mdl_$id');

  @override
  Widget build(BuildContext context) {
    final rep = _m.report;
    final scores = rep.scores;
    // best model = lowest log-loss
    var best = scores.first;
    for (final s in scores) {
      if (s.n > 0 && s.logLoss < best.logLoss) best = s;
    }
    final muted = mutedText(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.hub_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(context.tr('aiEnsemble'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          ]),
          const SizedBox(height: 4),
          Text(context.tr('aiEnsembleHelp'), style: TextStyle(fontSize: 11.5, color: muted)),
          const SizedBox(height: 10),
          if (rep.evaluated == 0)
            Text(context.tr('mdlNeedData'), style: TextStyle(color: muted))
          else ...[
            Table(
              columnWidths: const {0: FlexColumnWidth(2.4), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
              children: [
                TableRow(children: [
                  const SizedBox(),
                  for (final h in ['mdlAcc', 'mdlLogLoss', 'mdlBrier'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(context.tr(h),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: muted)),
                    ),
                ]),
                for (final s in scores)
                  TableRow(
                    decoration: s.id == best.id
                        ? BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8))
                        : null,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                        child: Text(_name(context, s.id),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: s.id == 'ensemble' ? FontWeight.w800 : FontWeight.w500)),
                      ),
                      for (final v in [
                        '${(s.accuracy * 100).round()}%',
                        s.logLoss.toStringAsFixed(2),
                        s.brier.toStringAsFixed(2)
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(v, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                '${context.tr('mdlEvaluated')}: ${rep.evaluated}  ·  ${context.tr('mdlWeights')}: '
                'Elo ${(rep.weights[0] * 100).round()}% · Poisson ${(rep.weights[1] * 100).round()}% · '
                'Logistic ${(rep.weights[2] * 100).round()}%',
                style: TextStyle(fontSize: 11.5, color: muted)),
            if (rep.evaluated < 30)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(context.tr('mdlFewData'),
                    style: const TextStyle(fontSize: 11.5, color: AppColors.warning)),
              ),
          ],
          if (_m.teams.length >= 2) ...[
            const Divider(height: 24),
            Text(context.tr('mdlPredict'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _pick(_a, (v) => setState(() => _a = v))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('vs')),
              Expanded(child: _pick(_b, (v) => setState(() => _b = v))),
            ]),
            const SizedBox(height: 10),
            if (_a != null && _b != null && _a != _b) _prediction(context),
          ],
        ]),
      ),
    );
  }

  Widget _pick(String? v, ValueChanged<String?> on) => DropdownButtonFormField<String>(
        initialValue: v,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: [for (final t in _m.teams) DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))],
        onChanged: on,
      );

  Widget _prediction(BuildContext context) {
    final p = _m.predict(_a!, _b!, allowDraw: true);
    final rows = <MapEntry<String, MatchPrediction>>[
      MapEntry('elo', p.elo),
      MapEntry('poisson', p.poisson),
      MapEntry('logistic', p.logistic),
      MapEntry('ensemble', p.ensemble),
    ];
    String pc(double v) => '${(v * 100).round()}%';
    final draws = _m.profile.draws;
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
                width: 92,
                child: Text(_name(context, r.key),
                    style: TextStyle(fontSize: 12, fontWeight: r.key == 'ensemble' ? FontWeight.w800 : FontWeight.w500))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  height: 18,
                  child: Row(children: [
                    Expanded(flex: (r.value.pA * 1000).round().clamp(1, 1000), child: Container(color: AppColors.primary)),
                    if (draws && r.value.pDraw > 0)
                      Expanded(flex: (r.value.pDraw * 1000).round().clamp(1, 1000), child: Container(color: Colors.grey)),
                    Expanded(flex: (r.value.pB * 1000).round().clamp(1, 1000), child: Container(color: AppColors.cyanDeep)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(draws ? '${pc(r.value.pA)} / ${pc(r.value.pDraw)} / ${pc(r.value.pB)}' : '${pc(r.value.pA)} / ${pc(r.value.pB)}',
                style: const TextStyle(fontSize: 11.5)),
          ]),
        ),
    ]);
  }
}
