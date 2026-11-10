import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/domain/standings_calculator.dart';

List<String> ids(List<StandingEntry> e) => e.map((x) => x.id).toList();

void main() {
  group('StandingsCalculator', () {
    test('ranks by points, then goal difference, then goals scored', () {
      final r = StandingsCalculator.compute(
        teamIds: ['A', 'B', 'C'],
        matches: const [
          MatchResult('A', 'B', 2, 0),
          MatchResult('B', 'C', 1, 0),
          MatchResult('A', 'C', 1, 1),
        ],
      );
      expect(ids(r), ['A', 'B', 'C']);
      expect(r[0].pts, 4);
      expect(r[0].gd, 2);
      expect(r[1].pts, 3);
      expect(r[2].pts, 1);
      expect(r.map((e) => e.played), [2, 2, 2]);
    });

    test('no matches keeps the input order with zero points', () {
      final r = StandingsCalculator.compute(
        teamIds: ['C', 'A', 'B'],
        matches: const [],
      );
      expect(ids(r), ['C', 'A', 'B']);
      expect(r.every((e) => e.pts == 0 && e.played == 0), isTrue);
    });

    test('head-to-head separates teams equal on points, gd and goals', () {
      // A and B both finish on 6 pts, gd +2, gf 3 - B beat A directly.
      final r = StandingsCalculator.compute(
        teamIds: ['A', 'B', 'C', 'D'],
        matches: const [
          MatchResult('B', 'A', 1, 0),
          MatchResult('A', 'C', 2, 0),
          MatchResult('A', 'D', 1, 0),
          MatchResult('B', 'C', 2, 0),
          MatchResult('B', 'D', 0, 1),
        ],
      );
      expect(ids(r), ['B', 'A', 'D', 'C']);
      expect(r[0].pts, r[1].pts);
      expect(r[0].gd, r[1].gd);
      expect(r[0].gf, r[1].gf);
    });

    test('a circular tie that nothing can split keeps the input order', () {
      const cycle = [
        MatchResult('A', 'B', 1, 0),
        MatchResult('B', 'C', 1, 0),
        MatchResult('C', 'A', 1, 0),
      ];
      expect(
        ids(StandingsCalculator.compute(teamIds: ['A', 'B', 'C'], matches: cycle)),
        ['A', 'B', 'C'],
      );
      expect(
        ids(StandingsCalculator.compute(teamIds: ['C', 'B', 'A'], matches: cycle)),
        ['C', 'B', 'A'],
      );
    });

    test('tie-breaker order is configurable (head-to-head first)', () {
      const matches = [
        MatchResult('B', 'A', 1, 0),
        MatchResult('A', 'X', 5, 0),
        MatchResult('Y', 'B', 1, 0),
      ];
      // Default: goal difference decides among A, B, Y (all on 3 pts).
      expect(
        ids(StandingsCalculator.compute(teamIds: ['A', 'B', 'X', 'Y'], matches: matches)),
        ['A', 'Y', 'B', 'X'],
      );
      // Head-to-head first: the mini-table of A, B, Y decides.
      expect(
        ids(StandingsCalculator.compute(
          teamIds: ['A', 'B', 'X', 'Y'],
          matches: matches,
          order: const [TieBreaker.headToHead, TieBreaker.goalDifference],
        )),
        ['Y', 'B', 'A', 'X'],
      );
    });

    test('ignores matches with unknown teams and self-matches', () {
      final r = StandingsCalculator.compute(
        teamIds: ['A', 'B'],
        matches: const [
          MatchResult('A', 'Z', 9, 0),
          MatchResult('A', 'A', 3, 0),
          MatchResult('A', 'B', 1, 0),
        ],
      );
      expect(r[0].id, 'A');
      expect(r[0].played, 1);
      expect(r[0].gf, 1);
    });

    test('points rule is configurable', () {
      final r = StandingsCalculator.compute(
        teamIds: ['A', 'B'],
        matches: const [MatchResult('A', 'B', 80, 70)],
        rule: const PointsRule(win: 2, draw: 0, loss: 1),
      );
      expect(r[0].pts, 2);
      expect(r[1].pts, 1);
    });
  });
}
