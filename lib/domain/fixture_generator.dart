/// Pure-Dart round-robin fixture generation (circle method).
///
/// Extracted from the provider so it can be unit-tested for odd and even
/// team counts. The first-leg algorithm is identical to the one the app has
/// always used; the second leg of a double round-robin now keeps the round
/// of the first leg instead of re-deriving it from the match index (which
/// produced wrong round numbers when the team count is odd, because one team
/// sits out every round).
library;

class Fixture {
  final String home;
  final String away;

  /// 0-based round number.
  final int round;

  /// Position in the whole schedule, unique and increasing.
  final int order;
  const Fixture(this.home, this.away, this.round, this.order);
}

class FixtureGenerator {
  FixtureGenerator._();

  /// Number of rounds in one leg: n-1 for even n, n for odd n.
  static int roundsPerLeg(int teamCount) {
    if (teamCount < 2) return 0;
    return teamCount.isEven ? teamCount - 1 : teamCount;
  }

  /// Every team meets every other team once (or twice, with sides swapped,
  /// when [doubleRound] is true). A team never plays twice in the same round.
  static List<Fixture> roundRobin(List<String> teamIds, {bool doubleRound = false}) {
    if (teamIds.length < 2) return const [];
    if (teamIds.toSet().length != teamIds.length) {
      throw ArgumentError('team ids must be unique');
    }
    const bye = '\u0000BYE';
    final ids = List<String>.of(teamIds);
    if (ids.length.isOdd) ids.add(bye);
    final n = ids.length;
    final rounds = n - 1;
    final half = n ~/ 2;
    final arr = List<String>.of(ids);
    final fixtures = <Fixture>[];
    var order = 0;
    for (var r = 0; r < rounds; r++) {
      for (var i = 0; i < half; i++) {
        final home = arr[i];
        final away = arr[n - 1 - i];
        if (home != bye && away != bye) {
          fixtures.add(Fixture(home, away, r, order++));
        }
      }
      final last = arr.removeLast();
      arr.insert(1, last);
    }
    if (doubleRound) {
      final firstLeg = List<Fixture>.of(fixtures);
      for (final f in firstLeg) {
        fixtures.add(Fixture(f.away, f.home, rounds + f.round, order++));
      }
    }
    return fixtures;
  }
}
