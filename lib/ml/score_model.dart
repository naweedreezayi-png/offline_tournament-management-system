import 'dart:math';

import 'elo_rating_service.dart';

/// Forecast of one match from the goal model: expected goals, the full
/// score-line probability grid and the outcome probabilities derived from it.
class ScoreForecast {
  final double lambdaA, lambdaB; // expected goals of A and of B
  final List<List<double>> grid; // grid[a][b] = P(A scores a, B scores b)
  final double pA, pDraw, pB;
  const ScoreForecast(this.lambdaA, this.lambdaB, this.grid, this.pA, this.pDraw, this.pB);

  /// The single most likely score line, as [goalsA, goalsB].
  List<int> get mostLikely {
    var best = -1.0;
    var ba = 0, bb = 0;
    for (var a = 0; a < grid.length; a++) {
      for (var b = 0; b < grid[a].length; b++) {
        if (grid[a][b] > best) {
          best = grid[a][b];
          ba = a;
          bb = b;
        }
      }
    }
    return [ba, bb];
  }

  double get mostLikelyProbability {
    final m = mostLikely;
    return grid[m[0]][m[1]];
  }

  /// The [n] most likely score lines with their probabilities.
  List<MapEntry<List<int>, double>> top(int n) {
    final all = <MapEntry<List<int>, double>>[];
    for (var a = 0; a < grid.length; a++) {
      for (var b = 0; b < grid[a].length; b++) {
        all.add(MapEntry([a, b], grid[a][b]));
      }
    }
    all.sort((x, y) => y.value.compareTo(x.value));
    return all.take(n).toList();
  }

  /// P(total goals > [line]), e.g. 2.5.
  double over(double line) {
    var p = 0.0;
    for (var a = 0; a < grid.length; a++) {
      for (var b = 0; b < grid[a].length; b++) {
        if (a + b > line) p += grid[a][b];
      }
    }
    return p;
  }

  /// P(both teams score).
  double get bothScore {
    var p = 0.0;
    for (var a = 1; a < grid.length; a++) {
      for (var b = 1; b < grid[a].length; b++) {
        p += grid[a][b];
      }
    }
    return p;
  }
}

class _Strength {
  double attack = 1, defence = 1;
  int games = 0;
}

/// Goal model (independent Poisson goals, "Dixon-Coles lite") for low-scoring
/// sports such as football and futsal.
///
/// For every team an attack strength and a defence weakness are learned from
/// the event log, opponent-adjusted by a few fixed-point iterations and
/// shrunk towards the league average when a team has few matches:
///   expected goals of A  = avg * attack(A) * defence(B) * home
///   expected goals of B  = avg * attack(B) * defence(A) / home
/// The score-line grid is the product of two Poisson distributions.
/// It is a statistical estimate: it never guarantees an outcome.
class GoalModel {
  final Map<String, _Strength> _teams;
  final double avgGoals; // league average goals per team per match
  final double home; // multiplicative home factor (1 = none)
  final int matches;
  GoalModel._(this._teams, this.avgGoals, this.home, this.matches);

  /// Sports whose scores follow goal-like counts. Others only use the Elo model.
  static bool supports(String sportId) => sportId == 'football' || sportId == 'futsal' || sportId == 'other';

  static const int _maxGoals = 9;
  static const double _priorGoals = 3; // shrinkage strength (in goals)

  static String _k(String n) => EloRatingService.key(n);

  /// Not enough data for a meaningful forecast.
  bool get isUsable => matches >= 8;

  int gamesOf(String team) => _teams[_k(team)]?.games ?? 0;
  double attackOf(String team) => _teams[_k(team)]?.attack ?? 1;
  double defenceOf(String team) => _teams[_k(team)]?.defence ?? 1;

  static GoalModel train(List<RatingEvent> events, {double homeFactor = 1}) {
    final n = events.length;
    if (n == 0) return GoalModel._({}, 1.3, homeFactor, 0);
    var totalGoals = 0;
    for (final e in events) {
      totalGoals += e.goalsA + e.goalsB;
    }
    final avg = max(0.2, totalGoals / (2 * n));
    final teams = <String, _Strength>{};
    _Strength get(String name) => teams.putIfAbsent(_k(name), () => _Strength());
    final gf = <String, double>{}, ga = <String, double>{};
    for (final e in events) {
      final a = get(e.teamA), b = get(e.teamB);
      a.games++;
      b.games++;
      gf[_k(e.teamA)] = (gf[_k(e.teamA)] ?? 0) + e.goalsA;
      ga[_k(e.teamA)] = (ga[_k(e.teamA)] ?? 0) + e.goalsB;
      gf[_k(e.teamB)] = (gf[_k(e.teamB)] ?? 0) + e.goalsB;
      ga[_k(e.teamB)] = (ga[_k(e.teamB)] ?? 0) + e.goalsA;
    }
    final prior = _priorGoals;
    for (var iter = 0; iter < 8; iter++) {
      final expFor = <String, double>{}, expAgainst = <String, double>{};
      for (final e in events) {
        final a = teams[_k(e.teamA)]!, b = teams[_k(e.teamB)]!;
        // goals A would score with attack = 1, and goals B would concede with defence = 1
        expFor[_k(e.teamA)] = (expFor[_k(e.teamA)] ?? 0) + avg * b.defence * homeFactor;
        expFor[_k(e.teamB)] = (expFor[_k(e.teamB)] ?? 0) + avg * a.defence / homeFactor;
        expAgainst[_k(e.teamA)] = (expAgainst[_k(e.teamA)] ?? 0) + avg * b.attack / homeFactor;
        expAgainst[_k(e.teamB)] = (expAgainst[_k(e.teamB)] ?? 0) + avg * a.attack * homeFactor;
      }
      for (final entry in teams.entries) {
        final k = entry.key;
        entry.value.attack = ((gf[k] ?? 0) + prior) / ((expFor[k] ?? 0) + prior);
        entry.value.defence = ((ga[k] ?? 0) + prior) / ((expAgainst[k] ?? 0) + prior);
      }
    }
    return GoalModel._(teams, avg, homeFactor, n);
  }

  static List<double> _poisson(double lambda) {
    final p = List<double>.filled(_maxGoals + 1, 0);
    p[0] = exp(-lambda);
    for (var k = 1; k <= _maxGoals; k++) {
      p[k] = p[k - 1] * lambda / k;
    }
    final s = p.fold<double>(0, (x, y) => x + y);
    return [for (final v in p) v / s];
  }

  ScoreForecast forecast(String a, String b) {
    final la = (avgGoals * attackOf(a) * defenceOf(b) * home).clamp(0.05, 8.0).toDouble();
    final lb = (avgGoals * attackOf(b) * defenceOf(a) / home).clamp(0.05, 8.0).toDouble();
    final pa = _poisson(la), pb = _poisson(lb);
    final grid = [
      for (var i = 0; i <= _maxGoals; i++) [for (var j = 0; j <= _maxGoals; j++) pa[i] * pb[j]]
    ];
    var w = 0.0, d = 0.0, l = 0.0;
    for (var i = 0; i <= _maxGoals; i++) {
      for (var j = 0; j <= _maxGoals; j++) {
        if (i > j) {
          w += grid[i][j];
        } else if (i == j) {
          d += grid[i][j];
        } else {
          l += grid[i][j];
        }
      }
    }
    return ScoreForecast(la, lb, grid, w, d, l);
  }
}
