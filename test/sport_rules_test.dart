import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/domain/sport_rules.dart';
import 'package:tournament_master_offline/domain/standings_calculator.dart';

void main() {
  test('football and futsal use 3/1/0', () {
    for (final s in ['football', 'futsal']) {
      final p = SportRules.of(s).points;
      expect([p.pointsFor(1, 0), p.pointsFor(1, 1), p.pointsFor(0, 1)], [3, 1, 0]);
    }
  });

  test('basketball uses 2/1 (loss earns 1)', () {
    final p = SportRules.of('basketball').points;
    expect([p.pointsFor(80, 70), p.pointsFor(70, 80)], [2, 1]);
  });

  test('cricket uses 2/1/0', () {
    final p = SportRules.of('cricket').points;
    expect([p.pointsFor(1, 0), p.pointsFor(1, 1), p.pointsFor(0, 1)], [2, 1, 0]);
  });

  test('volleyball: 3-0 and 3-1 = 3/0, 3-2 = 2/1', () {
    final p = SportRules.of('volleyball').points;
    expect([p.pointsFor(3, 0), p.pointsFor(0, 3)], [3, 0]);
    expect([p.pointsFor(3, 1), p.pointsFor(1, 3)], [3, 0]);
    expect([p.pointsFor(3, 2), p.pointsFor(2, 3)], [2, 1]);
  });

  test('unknown sport falls back to generic 3/1/0', () {
    expect(SportRules.hasSpecificRule('judo'), isFalse);
    expect(SportRules.of('judo').points.pointsFor(1, 0), 3);
  });

  test('volleyball standings are computed with the per-match rule', () {
    final r = StandingsCalculator.compute(
      teamIds: ['A', 'B'],
      matches: const [MatchResult('A', 'B', 3, 2)],
      rule: SportRules.of('volleyball').points,
    );
    expect(r.firstWhere((e) => e.id == 'A').pts, 2);
    expect(r.firstWhere((e) => e.id == 'B').pts, 1);
  });

  test('PointsRule JSON round-trips', () {
    const p = PointsRule(win: 2, draw: 1, loss: 0);
    expect(PointsRule.fromJson(p.toJson()), p);
  });
}
