import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/ml/elo_rating_service.dart';
import 'package:tournament_master_offline/ml/insight.dart';
import 'package:tournament_master_offline/ml/score_model.dart';

RatingEvent ev(int i, String a, String b, int ga, int gb) => RatingEvent(
      matchId: 'm$i',
      tournamentId: 't',
      sport: 'football',
      teamA: a,
      teamB: b,
      goalsA: ga,
      goalsB: gb,
      resultA: ga == gb ? 0.5 : (ga > gb ? 1 : 0),
      seq: i,
    );

List<RatingEvent> history() {
  // Strong beats weak by 3-0 / 2-0, mid team in between.
  final out = <RatingEvent>[];
  var i = 0;
  for (var r = 0; r < 4; r++) {
    out.add(ev(i++, 'Strong', 'Weak', 3, 0));
    out.add(ev(i++, 'Weak', 'Strong', 0, 2));
    out.add(ev(i++, 'Strong', 'Mid', 2, 1));
    out.add(ev(i++, 'Mid', 'Strong', 1, 1));
    out.add(ev(i++, 'Mid', 'Weak', 2, 0));
    out.add(ev(i++, 'Weak', 'Mid', 1, 1));
  }
  return out;
}

void main() {
  group('GoalModel', () {
    final events = history();
    final gm = GoalModel.train(events);

    test('is usable with enough matches and ranks attack sensibly', () {
      expect(gm.isUsable, isTrue);
      expect(gm.attackOf('Strong'), greaterThan(gm.attackOf('Weak')));
      expect(gm.defenceOf('Strong'), lessThan(gm.defenceOf('Weak'))); // smaller = concedes less
    });

    test('forecast probabilities sum to 1 and favour the stronger team', () {
      final f = gm.forecast('Strong', 'Weak');
      expect(f.pA + f.pDraw + f.pB, closeTo(1.0, 1e-9));
      expect(f.pA, greaterThan(f.pB));
      expect(f.lambdaA, greaterThan(f.lambdaB));
      expect(f.mostLikely[0], greaterThanOrEqualTo(f.mostLikely[1]));
      expect(f.over(2.5), inInclusiveRange(0, 1));
      expect(f.top(3).length, 3);
    });

    test('unknown teams get a neutral forecast', () {
      final f = gm.forecast('Nobody', 'Anybody');
      expect(f.pA, closeTo(f.pB, 1e-9));
    });
  });

  group('MatchInsight', () {
    final events = history();
    final model = EloRatingService.trainFrom(events, profile: SportProfiles.football);
    final goals = GoalModel.train(events);

    test('blends Elo with the goal model and explains itself', () {
      final ins = MatchInsight.build(model: model, goals: goals, events: events, a: 'Strong', b: 'Weak');
      expect(ins.blended.pA + ins.blended.pDraw + ins.blended.pB, closeTo(1.0, 1e-9));
      expect(ins.blended.pA, greaterThan(ins.blended.pB));
      expect(ins.forecast, isNotNull);
      expect(ins.factors.map((f) => f.key), containsAll(['rating', 'form', 'attack', 'defence']));
      expect(ins.confidence, isNot(Confidence.low));
    });

    test('form uses the latest results first', () {
      final f = TeamForm.of(events, 'Strong');
      expect(f.last.length, 5);
      expect(f.score, inInclusiveRange(0, 1));
    });

    test('a team without data gives low confidence', () {
      final ins = MatchInsight.build(model: model, goals: goals, events: events, a: 'Strong', b: 'Brand New');
      expect(ins.confidence, Confidence.low);
    });
  });

  group('calibration', () {
    test('bins cover every evaluated prediction', () {
      final events = history();
      final m = EloRatingService.trainFrom(events, profile: SportProfiles.football);
      final n = m.calibration.fold<int>(0, (s, b) => s + b.count);
      expect(n, m.evaluated);
      for (final b in m.calibration) {
        expect(b.hitRate, inInclusiveRange(0, 1));
        expect(b.meanConfidence, inInclusiveRange(0, 1));
      }
      expect(m.calibrationError, isNotNull);
    });
  });
}
