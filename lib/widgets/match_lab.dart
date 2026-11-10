import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../ml/elo_rating_service.dart';
import '../ml/insight.dart';
import '../ml/score_model.dart';
import '../theme/app_theme.dart';

/// "Match lab": pick any two teams of a sport and see the AI's forecast with its reasons:
/// win/draw/win probabilities, expected goals and most likely scores (goal sports),
/// recent form, the confidence level and the factors behind the numbers.
class MatchLab extends StatefulWidget {
  final String sportId;
  final RatingModel model;
  final List<RatingEvent> events;
  const MatchLab({super.key, required this.sportId, required this.model, required this.events});

  @override
  State<MatchLab> createState() => _MatchLabState();
}

class _MatchLabState extends State<MatchLab> {
  String? _a, _b;
  late final GoalModel? _goals = GoalModel.supports(widget.sportId) ? GoalModel.train(widget.events) : null;

  @override
  Widget build(BuildContext context) {
    final names = [for (final r in widget.model.ranking) r.name];
    if (names.length < 2) {
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(14), child: Text(context.tr('aiNeedData'))));
    }
    final cs = Theme.of(context).colorScheme;
    final a = names.contains(_a) ? _a! : names[0];
    final b = names.contains(_b) && _b != a ? _b! : names.firstWhere((n) => n != a);
    final ins = MatchInsight.build(
        model: widget.model,
        goals: _goals,
        events: widget.events,
        a: a,
        b: b,
        allowDraw: widget.model.profile.draws);
    int pc(double v) => (v * 100).round();
    final f = ins.forecast;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.science_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(context.tr('aiMatchLab'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _picker(names, a, (v) => setState(() => _a = v))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('vs')),
            Expanded(child: _picker(names, b, (v) => setState(() => _b = v))),
          ]),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(children: [
                Expanded(flex: (ins.blended.pA * 1000).round().clamp(1, 1000), child: Container(color: AppColors.primary)),
                if (ins.blended.pDraw > 0)
                  Expanded(flex: (ins.blended.pDraw * 1000).round().clamp(1, 1000), child: Container(color: cs.outline)),
                Expanded(flex: (ins.blended.pB * 1000).round().clamp(1, 1000), child: Container(color: AppColors.cyan)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${pc(ins.blended.pA)}%', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
            if (ins.blended.pDraw > 0) Text('${context.tr('drawLabel')} ${pc(ins.blended.pDraw)}%', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            Text('${pc(ins.blended.pB)}%', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.cyanDeep)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(context, context.tr('aiConfidence'), context.tr(switch (ins.confidence) {
              Confidence.low => 'aiConfLow',
              Confidence.medium => 'aiConfMedium',
              Confidence.high => 'aiConfHigh',
            })),
            if (f != null) ...[
              _chip(context, context.tr('aiExpectedGoals'), '${f.lambdaA.toStringAsFixed(2)} - ${f.lambdaB.toStringAsFixed(2)}'),
              _chip(context, context.tr('aiMostLikely'), '${f.mostLikely[0]} - ${f.mostLikely[1]} (${pc(f.mostLikelyProbability)}%)'),
              _chip(context, context.tr('aiOver25'), '${pc(f.over(2.5))}%'),
              _chip(context, context.tr('aiBothScore'), '${pc(f.bothScore)}%'),
            ],
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _form(context, ins.formA)),
            const SizedBox(width: 8),
            Expanded(child: _form(context, ins.formB)),
          ]),
          const SizedBox(height: 12),
          Text(context.tr('aiWhy'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final fc in ins.factors) _factor(context, fc, a, b),
          const SizedBox(height: 6),
          Text(context.tr('aiLabDisclaimer'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Widget _picker(List<String> names, String value, ValueChanged<String> onChanged) =>
      DropdownButtonFormField<String>(
        isExpanded: true,
        value: value,
        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );

  Widget _chip(BuildContext context, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$label: ', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          TextSpan(text: value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        ])),
      );

  Widget _form(BuildContext context, TeamForm f) {
    Color c(String r) => r == 'W' ? AppColors.success : (r == 'L' ? AppColors.danger : Colors.grey);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${context.tr('aiForm')} · ${f.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      if (f.last.isEmpty)
        const Text('—')
      else
        Row(children: [
          for (final r in f.last)
            Container(
              margin: const EdgeInsets.only(right: 4),
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c(r), borderRadius: BorderRadius.circular(6)),
              child: Text(r, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
        ]),
    ]);
  }

  Widget _factor(BuildContext context, InsightFactor fc, String a, String b) {
    final who = fc.favours > 0 ? a : (fc.favours < 0 ? b : '');
    final text = context
        .tr('aiFactor_${fc.key}')
        .replaceAll('{team}', who)
        .replaceAll('{v}', fc.key == 'form' ? '${(fc.value.abs() * 100).round()}%' : fc.value.abs().toStringAsFixed(fc.key == 'rating' || fc.key == 'home' ? 0 : 2));
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(fc.favours == 0 ? Icons.remove_rounded : Icons.arrow_circle_right_outlined, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(child: Text(fc.favours == 0 && fc.key != 'data' ? context.tr('aiFactorEven') : text, style: const TextStyle(fontSize: 12.5))),
      ]),
    );
  }
}
