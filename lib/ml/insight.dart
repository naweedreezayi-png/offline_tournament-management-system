import 'elo_rating_service.dart';
import 'score_model.dart';

/// Recent results of one team (newest last), as W / D / L letters, with a
/// recency-weighted form score between 0 (all lost) and 1 (all won).
class TeamForm {
  final String name;
  final List<String> last;
  final double score;
  const TeamForm(this.name, this.last, this.score);

  /// Form of [team] from the event log of one sport (events are in time order).
  static TeamForm of(List<RatingEvent> events, String team, {int n = 5}) {
    final key = EloRatingService.key(team);
    final results = <double>[];
    for (final e in events) {
      if (EloRatingService.key(e.teamA) == key) {
        results.add(e.resultA);
      } else if (EloRatingService.key(e.teamB) == key) {
        results.add(1 - e.resultA);
      }
    }
    final recent = results.length <= n ? results : results.sublist(results.length - n);
    if (recent.isEmpty) return TeamForm(team, const [], 0.5);
    var num = 0.0, den = 0.0;
    for (var i = 0; i < recent.length; i++) {
      final w = 1.0 + i * 0.5; // newer results weigh more
      num += w * recent[i];
      den += w;
    }
    return TeamForm(team, [for (final r in recent) r == 1 ? 'W' : (r == 0 ? 'L' : 'D')], num / den);
  }
}

enum Confidence { low, medium, high }

/// One reason behind a prediction. [favours]: +1 favours team A, -1 team B, 0 neutral.
class InsightFactor {
  final String key; // 'rating', 'form', 'attack', 'defence', 'home', 'data'
  final double value;
  final int favours;
  const InsightFactor(this.key, this.value, this.favours);
}

/// Everything the "Match lab" shows about a pairing.
class MatchInsight {
  final MatchPrediction blended; // Elo (+ goal model when available)
  final MatchPrediction elo;
  final ScoreForecast? forecast;
  final TeamForm formA, formB;
  final Confidence confidence;
  final List<InsightFactor> factors;
  const MatchInsight(this.blended, this.elo, this.forecast, this.formA, this.formB, this.confidence, this.factors);

  /// Combines the Elo model with the goal model (weight 0.5 / 0.5 when both
  /// are usable; the goal model also needs both teams to have played).
  static MatchInsight build({
    required RatingModel model,
    GoalModel? goals,
    required List<RatingEvent> events,
    required String a,
    required String b,
    bool allowDraw = true,
  }) {
    final elo = model.predict(a, b, allowDraw: allowDraw);
    ScoreForecast? f;
    var blended = elo;
    final useGoals = goals != null &&
        goals.isUsable &&
        model.profile.draws &&
        allowDraw &&
        goals.gamesOf(a) > 0 &&
        goals.gamesOf(b) > 0;
    if (useGoals) {
      f = goals.forecast(a, b);
      blended = MatchPrediction(
        0.5 * elo.pA + 0.5 * f.pA,
        0.5 * elo.pDraw + 0.5 * f.pDraw,
        0.5 * elo.pB + 0.5 * f.pB,
      );
    }
    final fa = TeamForm.of(events, a), fb = TeamForm.of(events, b);
    final minPlayed = [model.playedOf(a), model.playedOf(b)].reduce((x, y) => x < y ? x : y);
    final top = [blended.pA, blended.pDraw, blended.pB].reduce((x, y) => x > y ? x : y);
    final conf = (minPlayed < 3 || top < 0.42)
        ? Confidence.low
        : (minPlayed >= 6 && top >= 0.6 ? Confidence.high : Confidence.medium);

    final factors = <InsightFactor>[];
    final gap = model.ratingOf(a) + model.homeAdvantage - model.ratingOf(b);
    factors.add(InsightFactor('rating', gap, gap.abs() < 15 ? 0 : (gap > 0 ? 1 : -1)));
    final df = fa.score - fb.score;
    factors.add(InsightFactor('form', df, df.abs() < 0.1 ? 0 : (df > 0 ? 1 : -1)));
    if (useGoals) {
      final att = goals.attackOf(a) - goals.attackOf(b);
      factors.add(InsightFactor('attack', att, att.abs() < 0.1 ? 0 : (att > 0 ? 1 : -1)));
      final def = goals.defenceOf(b) - goals.defenceOf(a); // a weaker defence of B favours A
      factors.add(InsightFactor('defence', def, def.abs() < 0.1 ? 0 : (def > 0 ? 1 : -1)));
    }
    if (model.homeAdvantage > 0) factors.add(InsightFactor('home', model.homeAdvantage, 1));
    if (minPlayed < 3) factors.add(InsightFactor('data', minPlayed.toDouble(), 0));
    return MatchInsight(blended, elo, f, fa, fb, conf, factors);
  }
}
