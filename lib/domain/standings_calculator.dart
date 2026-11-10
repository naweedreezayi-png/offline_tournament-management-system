/// Pure-Dart standings engine (no Flutter imports, so it can be unit-tested
/// and later mirrored on the backend).
///
/// Behaviour is deliberately backward compatible with the old
/// `computeStandings`: teams are ranked by points, then goal difference,
/// then goals scored. The only change is what happens when teams are still
/// equal after those keys: they are now separated by their head-to-head
/// record instead of an arbitrary order.
library;

/// One finished match between two teams of the same table.
class MatchResult {
  final String teamA;
  final String teamB;
  final int scoreA;
  final int scoreB;

  /// Table points decided by the sport's own rules for this match (for
  /// example wrestling classification points). When both are given they are
  /// used instead of the points rule.
  final int? pointsA;
  final int? pointsB;
  const MatchResult(this.teamA, this.teamB, this.scoreA, this.scoreB,
      {this.pointsA, this.pointsB});
}

/// Points awarded per result. The default (3/1/0) is the rule the app has
/// always used for every sport. Sports whose points depend on the score
/// itself (e.g. volleyball sets) supply [perMatch] instead.
class PointsRule {
  final int win;
  final int draw;
  final int loss;

  /// Optional score-dependent rule: given the team's own score and the
  /// opponent's score, returns the points that team earns. When set it
  /// replaces win/draw/loss.
  final int Function(int own, int opp)? perMatch;

  const PointsRule({this.win = 3, this.draw = 1, this.loss = 0, this.perMatch});

  /// Points earned by a team that scored [own] against [opp].
  int pointsFor(int own, int opp) {
    final f = perMatch;
    if (f != null) return f(own, opp);
    if (own > opp) return win;
    if (own < opp) return loss;
    return draw;
  }

  Map<String, int> toJson() => {'win': win, 'draw': draw, 'loss': loss};

  factory PointsRule.fromJson(Map<String, dynamic> j) => PointsRule(
        win: (j['win'] as num?)?.toInt() ?? 3,
        draw: (j['draw'] as num?)?.toInt() ?? 1,
        loss: (j['loss'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is PointsRule &&
      other.win == win &&
      other.draw == draw &&
      other.loss == loss &&
      other.perMatch == perMatch;

  @override
  int get hashCode => Object.hash(win, draw, loss, perMatch);
}

/// Tie-breakers applied, in order, to teams level on points.
enum TieBreaker {
  goalDifference,
  goalsFor,

  /// Mini-table of only the matches played among the tied teams:
  /// head-to-head points, then head-to-head goal difference, then
  /// head-to-head goals scored.
  headToHead,
}

class StandingEntry {
  final String id;
  int played = 0, win = 0, draw = 0, loss = 0, gf = 0, ga = 0;
  int pts = 0;
  int get gd => gf - ga;
  StandingEntry(this.id);
}

class StandingsCalculator {
  StandingsCalculator._();

  /// The order that reproduces the app's historical ranking, with head to
  /// head added last so it only ever resolves ties that used to be random.
  static const List<TieBreaker> defaultOrder = [
    TieBreaker.goalDifference,
    TieBreaker.goalsFor,
    TieBreaker.headToHead,
  ];

  /// Ranks [teamIds]. Matches that involve a team outside [teamIds] are
  /// ignored. Ties that no tie-breaker can separate keep the order of
  /// [teamIds], so the result is deterministic.
  static List<StandingEntry> compute({
    required List<String> teamIds,
    required Iterable<MatchResult> matches,
    PointsRule rule = const PointsRule(),
    List<TieBreaker> order = defaultOrder,
  }) {
    final entries = {for (final id in teamIds) id: StandingEntry(id)};
    final used = <MatchResult>[];
    for (final m in matches) {
      final a = entries[m.teamA];
      final b = entries[m.teamB];
      if (a == null || b == null || m.teamA == m.teamB) continue;
      used.add(m);
      a.played++;
      b.played++;
      a.gf += m.scoreA;
      a.ga += m.scoreB;
      b.gf += m.scoreB;
      b.ga += m.scoreA;
      if (m.scoreA > m.scoreB) {
        a.win++;
        b.loss++;
      } else if (m.scoreA < m.scoreB) {
        b.win++;
        a.loss++;
      } else {
        a.draw++;
        b.draw++;
      }
      final pa = m.pointsA, pb = m.pointsB;
      if (pa != null && pb != null) {
        a.pts += pa;
        b.pts += pb;
      } else {
        a.pts += rule.pointsFor(m.scoreA, m.scoreB);
        b.pts += rule.pointsFor(m.scoreB, m.scoreA);
      }
    }

    final position = {for (var i = 0; i < teamIds.length; i++) teamIds[i]: i};
    final all = entries.values.toList();
    // Dart's List.sort is not guaranteed stable, so the input position is an
    // explicit last key.
    all.sort((x, y) {
      if (y.pts != x.pts) return y.pts - x.pts;
      return position[x.id]! - position[y.id]!;
    });

    final result = <StandingEntry>[];
    var start = 0;
    while (start < all.length) {
      var end = start + 1;
      while (end < all.length && all[end].pts == all[start].pts) {
        end++;
      }
      result.addAll(_resolve(all.sublist(start, end), order, 0, used, rule, position));
      start = end;
    }
    return result;
  }

  /// Splits a run of teams that are level so far, using order[from], then
  /// recurses on each still-level group with the next tie-breaker.
  static List<StandingEntry> _resolve(
    List<StandingEntry> run,
    List<TieBreaker> order,
    int from,
    List<MatchResult> matches,
    PointsRule rule,
    Map<String, int> position,
  ) {
    if (run.length < 2 || from >= order.length) return run;

    final keys = <String, List<int>>{};
    switch (order[from]) {
      case TieBreaker.goalDifference:
        for (final e in run) {
          keys[e.id] = [e.gd];
        }
      case TieBreaker.goalsFor:
        for (final e in run) {
          keys[e.id] = [e.gf];
        }
      case TieBreaker.headToHead:
        final ids = {for (final e in run) e.id};
        final mini = compute(
          teamIds: run.map((e) => e.id).toList(),
          matches: matches.where((m) => ids.contains(m.teamA) && ids.contains(m.teamB)),
          rule: rule,
          order: const [TieBreaker.goalDifference, TieBreaker.goalsFor],
        );
        for (final e in mini) {
          keys[e.id] = [e.pts, e.gd, e.gf];
        }
    }

    int compareKeys(List<int> a, List<int> b) {
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return b[i] - a[i]; // higher is better
      }
      return 0;
    }

    final sorted = List<StandingEntry>.from(run)
      ..sort((x, y) {
        final c = compareKeys(keys[x.id]!, keys[y.id]!);
        return c != 0 ? c : position[x.id]! - position[y.id]!;
      });

    final out = <StandingEntry>[];
    var start = 0;
    while (start < sorted.length) {
      var end = start + 1;
      while (end < sorted.length &&
          compareKeys(keys[sorted[end].id]!, keys[sorted[start].id]!) == 0) {
        end++;
      }
      out.addAll(_resolve(sorted.sublist(start, end), order, from + 1, matches, rule, position));
      start = end;
    }
    return out;
  }
}
