import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/domain/fixture_generator.dart';

List<String> teams(int n) => [for (var i = 0; i < n; i++) 't$i'];

void main() {
  group('FixtureGenerator.roundRobin', () {
    test('fewer than two teams gives no fixtures', () {
      expect(FixtureGenerator.roundRobin([]), isEmpty);
      expect(FixtureGenerator.roundRobin(['a']), isEmpty);
    });

    test('duplicate team ids are rejected', () {
      expect(() => FixtureGenerator.roundRobin(['a', 'a']), throwsArgumentError);
    });

    for (var n = 2; n <= 16; n++) {
      test('single round-robin with $n teams is complete and clash-free', () {
        final f = FixtureGenerator.roundRobin(teams(n));
        expect(f.length, n * (n - 1) ~/ 2);
        final pairs = f.map((x) => ({x.home, x.away}.toList()..sort()).join('|'));
        expect(pairs.toSet().length, f.length, reason: 'a pair met twice');
        expect(f.map((x) => x.round).reduce((a, b) => a > b ? a : b) + 1,
            FixtureGenerator.roundsPerLeg(n));
        _expectNoTeamTwiceInARound(f);
        expect(f.map((x) => x.order), List.generate(f.length, (i) => i));
      });

      test('double round-robin with $n teams has correct rounds', () {
        final f = FixtureGenerator.roundRobin(teams(n), doubleRound: true);
        expect(f.length, n * (n - 1));
        final ordered = f.map((x) => '${x.home}>${x.away}');
        expect(ordered.toSet().length, f.length, reason: 'duplicate fixture');
        final rounds = FixtureGenerator.roundsPerLeg(n);
        expect(f.map((x) => x.round).reduce((a, b) => a > b ? a : b) + 1, rounds * 2);
        _expectNoTeamTwiceInARound(f);
        // Every second-leg match is the mirror of a first-leg match played
        // exactly one leg (rounds) later.
        final first = {
          for (final x in f.where((x) => x.round < rounds)) '${x.home}>${x.away}': x.round
        };
        for (final x in f.where((x) => x.round >= rounds)) {
          expect(first['${x.away}>${x.home}'], x.round - rounds);
        }
      });
    }
  });
}

void _expectNoTeamTwiceInARound(List<Fixture> f) {
  final byRound = <int, List<String>>{};
  for (final x in f) {
    byRound.putIfAbsent(x.round, () => []).addAll([x.home, x.away]);
  }
  byRound.forEach((r, list) {
    expect(list.toSet().length, list.length, reason: 'a team plays twice in round $r');
  });
}
