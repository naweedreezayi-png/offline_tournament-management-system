import 'dart:math';
import '../models/match_model.dart';
import '../models/tournament.dart';
import 'elo_rating_service.dart';

enum ForecastKind { league, knockout }

/// Forecast for one team.
class TeamForecast {
  final String id;
  final String name;
  /// True when the rating model has seen enough matches of this team
  /// (otherwise it is treated as an average team and flagged in the UI).
  final bool known;
  final double rating;
  final int matches;
  double pChampion = 0;
  double expectedPoints = 0; // league / group only
  /// League: P(finishing in position i+1). Knockout: P(reaching round i).
  List<double> stage = const [];
  TeamForecast(this.id, this.name, this.known, this.rating, this.matches);
}

class Forecast {
  final ForecastKind kind;
  /// True for "groups then knockout" tournaments whose bracket does not exist yet.
  final bool preBracket;
  final List<TeamForecast> teams; // in the order teams were entered
  final int stageCount;
  final int trials;
  /// Knockout: number of rounds of the (real or simulated) bracket.
  final int totalRounds;
  Forecast({
    required this.kind,
    required this.preBracket,
    required this.teams,
    required this.stageCount,
    required this.trials,
    required this.totalRounds,
  });

  int get unknownCount => teams.where((t) => !t.known).length;
  bool get allUnknown => teams.isNotEmpty && unknownCount == teams.length;
  List<TeamForecast> get ranked => [...teams]
    ..sort((a, b) => b.pChampion.compareTo(a.pChampion));
}

class _Fx {
  final int a, b; // local indices
  final double pa, pd;
  const _Fx(this.a, this.b, this.pa, this.pd);
}

/// A (mini-)league: played results are fixed, remaining fixtures are sampled.
class _League {
  final List<int> members; // global team indices
  final List<double> pts0;
  final List<double> gd0;
  final List<_Fx> fx;
  List<double> lastPts = const [];
  _League(this.members, this.pts0, this.gd0, this.fx);

  /// Returns local indices ordered from 1st to last.
  List<int> simulate(Random rng) {
    final n = members.length;
    final pts = List<double>.from(pts0);
    final gd = List<double>.from(gd0);
    for (final f in fx) {
      final u = rng.nextDouble();
      if (u < f.pa) {
        pts[f.a] += 3;
        gd[f.a] += 1;
        gd[f.b] -= 1;
      } else if (u < f.pa + f.pd) {
        pts[f.a] += 1;
        pts[f.b] += 1;
      } else {
        pts[f.b] += 3;
        gd[f.b] += 1;
        gd[f.a] -= 1;
      }
    }
    lastPts = pts;
    final key = List<double>.generate(
        n, (i) => pts[i] * 100000 + gd[i] * 10 + rng.nextDouble());
    final order = List<int>.generate(n, (i) => i);
    order.sort((x, y) => key[y].compareTo(key[x]));
    return order;
  }
}

/// Monte-Carlo tournament forecast driven by the Elo rating model:
/// the remaining matches are simulated thousands of times using the model's
/// win probabilities, and the share of simulations in which a team wins the
/// title (or reaches a round / finishes in a position) is its probability.
/// Already played matches are fixed, so the forecast sharpens as results
/// come in.
class TournamentSimulator {
  TournamentSimulator._();

  /// A team needs at least this many learned matches to count as "known".
  static const int minGames = 3;

  static List<int> _seedOrder(int size) {
    var o = <int>[1];
    while (o.length < size) {
      final len = o.length * 2;
      o = [
        for (final s in o) ...[s, len + 1 - s]
      ];
    }
    return o;
  }

  /// [seed] makes a run reproducible (tests, reports). When omitted, a seed
  /// derived from the tournament and its played results is used, so the same
  /// state always gives the same forecast.
  static Future<Forecast> run(Tournament t, RatingModel model,
      {int? seed}) async {
    final teams = t.teams;
    final n = teams.length;
    final idx = <String, int>{for (var i = 0; i < n; i++) teams[i].id: i};
    final rating = List<double>.generate(n, (i) => model.ratingOf(teams[i].name));
    final forecasts = List<TeamForecast>.generate(
      n,
      (i) => TeamForecast(teams[i].id, teams[i].name,
          model.playedOf(teams[i].name) >= minGames, rating[i], model.playedOf(teams[i].name)),
    );
    final effectiveSeed = seed ?? t.id.hashCode ^ (t.matches.where((m) => m.isPlayed).length * 7919) ^
        (t.groups.fold<int>(0, (s, g) => s + g.matches.where((m) => m.isPlayed).length) * 104729);
    final rng = Random(effectiveSeed);

    if (n < 2) {
      return Forecast(
          kind: ForecastKind.league,
          preBracket: false,
          teams: forecasts,
          stageCount: 0,
          trials: 0,
          totalRounds: 0);
    }

    _League buildLeague(List<String> teamIds, List<MatchModel> matches) {
      final members = [for (final id in teamIds) if (idx.containsKey(id)) idx[id]!];
      final local = {for (var i = 0; i < members.length; i++) members[i]: i};
      final pts = List<double>.filled(members.length, 0);
      final gd = List<double>.filled(members.length, 0);
      final fx = <_Fx>[];
      for (final m in matches) {
        final ga = idx[m.teamAId];
        final gb = idx[m.teamBId];
        if (ga == null || gb == null) continue;
        final a = local[ga], b = local[gb];
        if (a == null || b == null) continue;
        if (m.isPlayed && m.scoreA != null && m.scoreB != null) {
          final sa = m.scoreA!, sb = m.scoreB!;
          gd[a] += sa - sb;
          gd[b] += sb - sa;
          if (sa > sb) {
            pts[a] += 3;
          } else if (sa < sb) {
            pts[b] += 3;
          } else {
            pts[a] += 1;
            pts[b] += 1;
          }
        } else {
          final p = EloRatingService.predict(rating[ga], rating[gb], model.drawRate,
              allowDraw: model.profile.draws, scale: model.scale);
          fx.add(_Fx(a, b, p.pA, p.pDraw));
        }
      }
      return _League(members, pts, gd, fx);
    }

    int trialsFor(int work) => (4000000 ~/ max(1, work)).clamp(500, 6000);

    // ------------------------------------------------------------ league
    if (t.type == TournamentType.league) {
      final lg = buildLeague(teams.map((e) => e.id).toList(), t.matches);
      final k = min(n, 8);
      final trials = trialsFor(lg.fx.length + n);
      final pos = List<int>.filled(n * k, 0);
      final champ = List<int>.filled(n, 0);
      final ptsSum = List<double>.filled(n, 0);
      for (var s = 0; s < trials; s++) {
        final order = lg.simulate(rng);
        for (var p = 0; p < min(k, order.length); p++) {
          pos[lg.members[order[p]] * k + p]++;
        }
        champ[lg.members[order[0]]]++;
        for (var i = 0; i < n; i++) {
          ptsSum[lg.members[i]] += lg.lastPts[i];
        }
        if (s % 200 == 199) await Future<void>.delayed(Duration.zero);
      }
      for (var i = 0; i < n; i++) {
        forecasts[i]
          ..pChampion = champ[i] / trials
          ..expectedPoints = ptsSum[i] / trials
          ..stage = [for (var p = 0; p < k; p++) pos[i * k + p] / trials];
      }
      return Forecast(
          kind: ForecastKind.league,
          preBracket: false,
          teams: forecasts,
          stageCount: k,
          trials: trials,
          totalRounds: 0);
    }

    // ------------------------------------------------- knockout, groups first
    if (t.hasGroupStage && t.matches.isEmpty && t.groups.isNotEmpty) {
      final leagues = [for (final g in t.groups) buildLeague(g.teamIds, g.matches)];
      const qualifiersPerGroup = 2;
      final nq = leagues.fold<int>(0, (s, l) => s + min(qualifiersPerGroup, l.members.length));
      var size = 1;
      while (size < max(2, nq)) {
        size *= 2;
      }
      final rounds = (log(size) / log(2)).round();
      final order = _seedOrder(size);
      final work = leagues.fold<int>(0, (s, l) => s + l.fx.length) + size;
      final trials = trialsFor(work);
      final reach = List<int>.filled(n * rounds, 0);
      final champ = List<int>.filled(n, 0);
      for (var s = 0; s < trials; s++) {
        final q = <int>[];
        for (final l in leagues) {
          final o = l.simulate(rng);
          for (var p = 0; p < min(qualifiersPerGroup, o.length); p++) {
            q.add(l.members[o[p]]);
          }
        }
        q.shuffle(rng);
        var cur = List<int>.generate(size, (i) {
          final sd = order[i];
          return sd <= q.length ? q[sd - 1] : -1;
        });
        for (final tm in cur) {
          if (tm >= 0) reach[tm * rounds + 0]++;
        }
        for (var r = 0; r < rounds; r++) {
          final next = <int>[];
          for (var i = 0; i < cur.length; i += 2) {
            final a = cur[i], b = cur[i + 1];
            int w;
            if (a < 0) {
              w = b;
            } else if (b < 0) {
              w = a;
            } else {
              w = rng.nextDouble() < EloRatingService.expected(rating[a], rating[b], scale: model.scale) ? a : b;
            }
            next.add(w);
            if (w >= 0 && r + 1 < rounds) reach[w * rounds + r + 1]++;
          }
          cur = next;
        }
        if (cur.isNotEmpty && cur[0] >= 0) champ[cur[0]]++;
        if (s % 200 == 199) await Future<void>.delayed(Duration.zero);
      }
      // expected group points (informational)
      for (final l in leagues) {
        final tmp = Random(effectiveSeed);
        final sum = List<double>.filled(l.members.length, 0);
        const sample = 400;
        for (var s = 0; s < sample; s++) {
          l.simulate(tmp);
          for (var i = 0; i < l.members.length; i++) {
            sum[i] += l.lastPts[i];
          }
        }
        for (var i = 0; i < l.members.length; i++) {
          forecasts[l.members[i]].expectedPoints = sum[i] / sample;
        }
      }
      for (var i = 0; i < n; i++) {
        forecasts[i]
          ..pChampion = champ[i] / trials
          ..stage = [for (var r = 0; r < rounds; r++) reach[i * rounds + r] / trials];
      }
      return Forecast(
          kind: ForecastKind.knockout,
          preBracket: true,
          teams: forecasts,
          stageCount: rounds,
          trials: trials,
          totalRounds: rounds);
    }

    // ------------------------------------------------ knockout, real bracket
    final byRound = <int, List<MatchModel>>{};
    for (final m in t.matches) {
      if (m.isThirdPlaceMatch) continue;
      byRound.putIfAbsent(m.round, () => []).add(m);
    }
    final R = byRound.isEmpty ? 0 : byRound.keys.reduce(max) + 1;
    final rounds = <List<MatchModel>>[
      for (var r = 0; r < R; r++) (byRound[r] ?? [])..sort((a, b) => a.order.compareTo(b.order))
    ];
    final a0 = <List<int>>[], b0 = <List<int>>[], w0 = <List<int>>[];
    var work = 0;
    for (final ms in rounds) {
      a0.add([for (final m in ms) idx[m.teamAId] ?? -1]);
      b0.add([for (final m in ms) idx[m.teamBId] ?? -1]);
      w0.add([for (final m in ms) (m.isPlayed && m.winnerId != null) ? (idx[m.winnerId] ?? -1) : -1]);
      work += ms.length;
    }
    final trials = trialsFor(work + n);
    final reach = List<int>.filled(n * max(1, R), 0);
    final champ = List<int>.filled(n, 0);
    for (var s = 0; s < trials; s++) {
      var prev = <int>[];
      for (var r = 0; r < R; r++) {
        final cur = List<int>.filled(rounds[r].length, -1);
        for (var o = 0; o < rounds[r].length; o++) {
          var a = a0[r][o], b = b0[r][o];
          if (r > 0) {
            if (a < 0 && 2 * o < prev.length) a = prev[2 * o];
            if (b < 0 && 2 * o + 1 < prev.length) b = prev[2 * o + 1];
          }
          if (a >= 0) reach[a * R + r]++;
          if (b >= 0) reach[b * R + r]++;
          int w;
          if (w0[r][o] >= 0) {
            w = w0[r][o];
          } else if (a < 0) {
            w = b;
          } else if (b < 0) {
            w = a;
          } else {
            w = rng.nextDouble() < EloRatingService.expected(rating[a], rating[b], scale: model.scale) ? a : b;
          }
          cur[o] = w;
        }
        prev = cur;
      }
      if (R > 0 && prev.isNotEmpty && prev[0] >= 0) champ[prev[0]]++;
      if (s % 200 == 199) await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < n; i++) {
      forecasts[i]
        ..pChampion = champ[i] / trials
        ..stage = [for (var r = 0; r < R; r++) reach[i * R + r] / trials];
    }
    return Forecast(
        kind: ForecastKind.knockout,
        preBracket: false,
        teams: forecasts,
        stageCount: R,
        trials: trials,
        totalRounds: R);
  }
}
