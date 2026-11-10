import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../ml/elo_rating_service.dart';
import '../ml/ensemble_model.dart';
import '../theme/app_theme.dart';

/// Shows the AI (Elo model) win-probability prediction for a fixture.
class WinProbabilityCard extends StatelessWidget {
  final String teamA;
  final String teamB;
  final bool allowDraw;
  final String sport;
  const WinProbabilityCard(
      {super.key,
      required this.teamA,
      required this.teamB,
      required this.allowDraw,
      this.sport = 'other'});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(RatingModel, List<RatingEvent>)>(
      future: () async {
        final m = await EloRatingService.instance.train(sport: sport);
        final ev = await EloRatingService.instance.eventsOf(sport);
        return (m, ev);
      }(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final model = snap.data!.$1;
        final events = snap.data!.$2;
        // with enough history the ensemble (Elo + Poisson + logistic regression) decides
        final p = events.length >= 8
            ? EnsembleModel.trainFrom(events, profile: model.profile)
                .predict(teamA, teamB, allowDraw: allowDraw)
                .ensemble
            : model.predict(teamA, teamB, allowDraw: allowDraw);
        final canDraw = allowDraw && model.profile.draws;
        final low = model.playedOf(teamA) + model.playedOf(teamB) == 0;
        int pc(double v) => (v * 100).round();
        final flexA = (p.pA * 1000).round().clamp(1, 1000);
        final flexD = (p.pDraw * 1000).round();
        final flexB = (p.pB * 1000).round().clamp(1, 1000);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.psychology, size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(context.tr('winProbability'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                Text('${model.ratingOf(teamA).round()}  •  ${model.ratingOf(teamB).round()}',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 10,
                  child: Row(children: [
                    Expanded(flex: flexA, child: Container(color: AppColors.success)),
                    if (flexD > 0)
                      Expanded(flex: flexD, child: Container(color: Colors.grey)),
                    Expanded(flex: flexB, child: Container(color: Theme.of(context).colorScheme.secondary)),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${pc(p.pA)}%',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                  if (canDraw)
                    Text('${context.tr('drawLabel')} ${pc(p.pDraw)}%',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  Text('${pc(p.pB)}%',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary)),
                ],
              ),
              if (low)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(context.tr('modelLearning'),
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
            ],
          ),
        );
      },
    );
  }
}
