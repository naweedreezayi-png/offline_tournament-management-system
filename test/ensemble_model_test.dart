import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/ml/elo_rating_service.dart';
import 'package:tournament_master_offline/ml/ensemble_model.dart';

List<RatingEvent> _synthetic(int n, {bool draws = false}) {
  final r = Random(7);
  const strength = {'A': 2.0, 'B': 1.4, 'C': 1.0, 'D': 0.6};
  final names = strength.keys.toList();
  final out = <RatingEvent>[];
  for (var i = 0; i < n; i++) {
    final a = names[r.nextInt(4)];
    var b = names[r.nextInt(4)];
    while (b == a) {
      b = names[r.nextInt(4)];
    }
    int goals(double lam) {
      var k = 0;
      var p = 1.0;
      final l = exp(-lam);
      do {
        k++;
        p *= r.nextDouble();
      } while (p > l);
      return k - 1;
    }

    final ga = goals(strength[a]!), gb = goals(strength[b]!);
    if (!draws && ga == gb) continue;
    out.add(RatingEvent(
      matchId: 'm$i',
      tournamentId: 't',
      sport: draws ? 'football' : 'kurash',
      teamA: a,
      teamB: b,
      goalsA: ga,
      goalsB: gb,
      resultA: ga > gb ? 1 : (ga == gb ? 0.5 : 0),
      seq: i,
    ));
  }
  return out;
}

void main() {
  test('probabilities sum to 1 for every model', () {
    final m = EnsembleModel.trainFrom(_synthetic(200, draws: true), profile: SportProfiles.of('football'));
    final p = m.predict('A', 'D', allowDraw: true);
    for (final x in [p.elo, p.poisson, p.logistic, p.ensemble]) {
      expect(x.pA + x.pDraw + x.pB, closeTo(1, 1e-9));
    }
  });

  test('the stronger team is favoured', () {
    final m = EnsembleModel.trainFrom(_synthetic(300), profile: SportProfiles.of('kurash'));
    final p = m.predict('A', 'D', allowDraw: false);
    expect(p.ensemble.pA, greaterThan(p.ensemble.pB));
    expect(p.ensemble.pDraw, 0);
  });

  test('walk-forward report: ensemble is not worse than the frequency baseline', () {
    final m = EnsembleModel.trainFrom(_synthetic(400), profile: SportProfiles.of('kurash'));
    final base = m.report.score('baseline')!;
    final ens = m.report.score('ensemble')!;
    expect(m.report.evaluated, greaterThan(100));
    expect(ens.logLoss, lessThan(base.logLoss));
    expect(m.report.weights.fold<double>(0, (s, v) => s + v), closeTo(1, 1e-9));
  });

  test('no events: no crash, empty report', () {
    final m = EnsembleModel.trainFrom(const []);
    expect(m.report.evaluated, 0);
    expect(m.predict('x', 'y', allowDraw: true).ensemble.pA, greaterThan(0));
  });
}
