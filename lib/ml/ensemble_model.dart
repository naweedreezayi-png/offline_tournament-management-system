import 'dart:math';
import 'elo_rating_service.dart';

/// Quality of one model, measured walk-forward (every match is predicted BEFORE it is learned).
class ModelScore {
  final String id; // baseline | elo | poisson | logistic | ensemble
  final int n;
  final double accuracy; // share of correctly predicted outcomes
  final double logLoss; // lower is better; ln(3)=1.10 is random 3-way
  final double brier; // lower is better; 0.667 is random 3-way
  const ModelScore(this.id, this.n, this.accuracy, this.logLoss, this.brier);
}

class EnsembleReport {
  final int evaluated;
  final List<ModelScore> scores;
  final List<double> weights; // learned weights of elo, poisson, logistic
  const EnsembleReport(this.evaluated, this.scores, this.weights);

  ModelScore? score(String id) {
    for (final s in scores) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class EnsemblePrediction {
  final MatchPrediction elo, poisson, logistic, ensemble;
  final List<double> weights;
  const EnsemblePrediction(this.elo, this.poisson, this.logistic, this.ensemble, this.weights);
}

class _Team {
  double elo = EloRatingService.initialRating;
  int n = 0;
  double gf = 0, ga = 0;
  double form = 0.5; // exponential moving average of results (1 win, 0.5 draw, 0 loss)
}

/// Ensemble of three different learners plus an honest baseline:
///
///  1. **Elo**: online rating model (see [EloRatingService]).
///  2. **Poisson**: attack / defence strength from goals scored and conceded
///     (normal approximation for high-scoring sports such as basketball).
///  3. **Logistic**: a multinomial logistic-regression classifier trained online by
///     stochastic gradient descent on three features (rating gap, form gap,
///     goal-difference gap). This is the "real" machine-learning part.
///  4. **Ensemble**: weighted average of the three; the weights are learned online with the
///     Hedge (multiplicative-weights) algorithm from each model's own log-loss.
///
/// All of it is learned from the user's own finished matches of ONE sport, replayed in time
/// order, so undo and edits can never leave it inconsistent. Quality is measured
/// walk-forward and compared with a baseline that only knows how often each outcome occurs.
class EnsembleModel {
  final SportProfile profile;
  final EnsembleReport report;
  final Map<String, _Team> _teams;
  final double _scale, _lg, _drawRate;
  final List<List<double>> _w; // logistic weights [class][feature]
  final List<double> _hedge;

  EnsembleModel._(this.profile, this.report, this._teams, this._scale, this._lg, this._drawRate,
      this._w, this._hedge);

  static const int _features = 4;
  static const double _lr = 0.03, _l2 = 0.001, _eta = 0.5;

  static String _k(String n) => EloRatingService.key(n);

  static double _kFactor(int n) => n < 10 ? 32 : 20;

  static double _margin(int gd, double marginScale) {
    final d = gd.abs() / marginScale;
    if (d <= 1) return 1;
    if (d <= 2) return 1.5;
    return (11 + min(d, 8.0)) / 8;
  }

  // ------------------------------------------------------------------ maths

  static double _phi(double x) {
    // standard normal CDF (Abramowitz-Stegun 7.1.26)
    final t = 1 / (1 + 0.2316419 * x.abs());
    final d = 0.3989423 * exp(-x * x / 2);
    final p = d *
        t *
        (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));
    return x >= 0 ? 1 - p : p;
  }

  static MatchPrediction _norm(double a, double d, double b, bool draws) {
    if (!draws) {
      final s = a + b;
      return s <= 0 ? const MatchPrediction(0.5, 0, 0.5) : MatchPrediction(a / s, 0, b / s);
    }
    final s = a + d + b;
    return MatchPrediction(a / s, d / s, b / s);
  }

  static MatchPrediction _poisson(double la, double lb, bool draws) {
    la = max(0.05, la);
    lb = max(0.05, lb);
    if (la + lb > 12) {
      final m = la - lb, s = sqrt(la + lb);
      final pa = 1 - _phi((0.5 - m) / s);
      final pb = _phi((-0.5 - m) / s);
      return _norm(pa, max(0.0, 1 - pa - pb), pb, draws);
    }
    const g = 14;
    List<double> pmf(double l) {
      final r = List<double>.filled(g + 1, 0);
      r[0] = exp(-l);
      for (var i = 1; i <= g; i++) {
        r[i] = r[i - 1] * l / i;
      }
      return r;
    }

    final pa = pmf(la), pb = pmf(lb);
    var win = 0.0, draw = 0.0, loss = 0.0;
    for (var i = 0; i <= g; i++) {
      for (var j = 0; j <= g; j++) {
        final p = pa[i] * pb[j];
        if (i > j) {
          win += p;
        } else if (i == j) {
          draw += p;
        } else {
          loss += p;
        }
      }
    }
    return _norm(win, draw, loss, draws);
  }

  static List<double> _softmax(List<double> z, bool draws) {
    final m = z.reduce(max);
    final e = [for (final v in z) exp(v - m)];
    if (!draws) e[1] = 0;
    final s = e.fold<double>(0, (a, b) => a + b);
    return [for (final v in e) v / s];
  }

  static List<double> _features3(_Team a, _Team b, double scale, double lg) {
    final gdA = a.n == 0 ? 0.0 : (a.gf - a.ga) / a.n;
    final gdB = b.n == 0 ? 0.0 : (b.gf - b.ga) / b.n;
    return [
      ((a.elo - b.elo) / scale).clamp(-3.0, 3.0).toDouble(),
      (a.form - b.form),
      ((gdA - gdB) / max(lg, 0.5)).clamp(-3.0, 3.0).toDouble(),
      1.0,
    ];
  }

  // ------------------------------------------------------- one-step predict

  static List<MatchPrediction> _predictAll(_Team a, _Team b, SportProfile pr, double scale,
      double lg, double drawRate, List<List<double>> w) {
    final draws = pr.draws;
    final elo = EloRatingService.predict(a.elo, b.elo, drawRate, allowDraw: draws, scale: scale);

    final lgx = max(lg, 0.05);
    const prior = 3.0;
    double att(_Team t) => ((t.gf + prior * lgx) / (t.n + prior)) / lgx;
    double dff(_Team t) => ((t.ga + prior * lgx) / (t.n + prior)) / lgx;
    final poisson = _poisson(lgx * att(a) * dff(b), lgx * att(b) * dff(a), draws);

    final x = _features3(a, b, scale, lg);
    final z = [
      for (var k = 0; k < 3; k++)
        List.generate(_features, (j) => w[k][j] * x[j]).fold<double>(0, (s, v) => s + v)
    ];
    final p = _softmax(z, draws);
    final logistic = MatchPrediction(p[0], p[1], p[2]);
    return [elo, poisson, logistic];
  }

  static MatchPrediction _blend(List<MatchPrediction> ps, List<double> h) {
    var a = 0.0, d = 0.0, b = 0.0;
    for (var i = 0; i < ps.length; i++) {
      a += h[i] * ps[i].pA;
      d += h[i] * ps[i].pDraw;
      b += h[i] * ps[i].pB;
    }
    return MatchPrediction(a, d, b);
  }

  static double _pOf(MatchPrediction p, int idx) => idx == 0 ? p.pA : (idx == 1 ? p.pDraw : p.pB);

  // --------------------------------------------------------------- training

  static EnsembleModel trainFrom(List<RatingEvent> events, {SportProfile? profile}) {
    final pr = profile ?? SportProfiles.generic;
    // scale: tuned by the same walk-forward log-loss idea, kept simple (default per sport)
    final scale = pr.defaultScale;
    final teams = <String, _Team>{};
    _Team get(String n) => teams.putIfAbsent(_k(n), () => _Team());

    final w = [
      [1.15, 0.0, 0.0, 0.1],
      [0.0, 0.0, 0.0, -0.4],
      [-1.15, 0.0, 0.0, -0.1],
    ];
    final hedge = [1 / 3, 1 / 3, 1 / 3];
    var draws = 0, total = 0;
    var goals = 0.0;
    final counts = [0.0, 0.0, 0.0];

    const ids = ['baseline', 'elo', 'poisson', 'logistic', 'ensemble'];
    final n = List<int>.filled(5, 0);
    final hit = List<int>.filled(5, 0);
    final ll = List<double>.filled(5, 0);
    final br = List<double>.filled(5, 0);
    var evaluated = 0;

    for (final ev in events) {
      final a = get(ev.teamA), b = get(ev.teamB);
      final dr = (draws + 0.25 * 10) / (total + 10);
      final lg = (goals + 3 * 1.0) / (2 * total + 3);
      final idx = ev.resultA == 1 ? 0 : (ev.resultA == 0 ? 2 : 1);

      final three = _predictAll(a, b, pr, scale, lg, dr, w);
      final ens = _blend(three, hedge);

      if (a.n + b.n > 0) {
        evaluated++;
        final cs = counts.fold<double>(0, (s, v) => s + v);
        final baseline = cs == 0
            ? const MatchPrediction(0.4, 0.2, 0.4)
            : _norm((counts[0] + 1) / (cs + 3), pr.draws ? (counts[1] + 1) / (cs + 3) : 0,
                (counts[2] + 1) / (cs + 3), pr.draws);
        final all = [baseline, ...three, ens];
        for (var i = 0; i < 5; i++) {
          final q = all[i];
          n[i]++;
          if (q.argmax == idx) hit[i]++;
          ll[i] += -log(max(_pOf(q, idx), 1e-3));
          final oa = idx == 0 ? 1.0 : 0.0, od = idx == 1 ? 1.0 : 0.0, ob = idx == 2 ? 1.0 : 0.0;
          br[i] += ((q.pA - oa) * (q.pA - oa) + (q.pDraw - od) * (q.pDraw - od) + (q.pB - ob) * (q.pB - ob));
        }
      }

      // ---- learn ----
      // Hedge weights from each model's own log-loss on this match
      for (var i = 0; i < 3; i++) {
        hedge[i] *= exp(-_eta * -log(max(_pOf(three[i], idx), 1e-3)));
      }
      final hs = hedge.fold<double>(0, (s, v) => s + v);
      for (var i = 0; i < 3; i++) {
        hedge[i] = max(0.02, hedge[i] / hs);
      }
      final hs2 = hedge.fold<double>(0, (s, v) => s + v);
      for (var i = 0; i < 3; i++) {
        hedge[i] /= hs2;
      }

      // logistic regression: one SGD step on the cross-entropy
      final x = _features3(a, b, scale, lg);
      final p = three[2];
      final pv = [p.pA, p.pDraw, p.pB];
      for (var k = 0; k < 3; k++) {
        if (!pr.draws && k == 1) continue;
        final err = pv[k] - (k == idx ? 1.0 : 0.0);
        for (var j = 0; j < _features; j++) {
          w[k][j] -= _lr * (err * x[j] + _l2 * w[k][j]);
        }
      }

      // Elo update
      final e = EloRatingService.expected(a.elo, b.elo, scale: scale);
      final g = _margin(ev.goalsA - ev.goalsB, pr.marginScale);
      a.elo += _kFactor(a.n) * g * (ev.resultA - e);
      b.elo += _kFactor(b.n) * g * ((1 - ev.resultA) - (1 - e));

      // goals + form
      a.gf += ev.goalsA;
      a.ga += ev.goalsB;
      b.gf += ev.goalsB;
      b.ga += ev.goalsA;
      a.form = 0.7 * a.form + 0.3 * ev.resultA;
      b.form = 0.7 * b.form + 0.3 * (1 - ev.resultA);
      a.n++;
      b.n++;
      goals += ev.goalsA + ev.goalsB;
      counts[idx] += 1;
      if (idx == 1) draws++;
      total++;
    }

    final scores = [
      for (var i = 0; i < 5; i++)
        ModelScore(ids[i], n[i], n[i] == 0 ? 0 : hit[i] / n[i], n[i] == 0 ? 0 : ll[i] / n[i],
            n[i] == 0 ? 0 : br[i] / n[i]),
    ];
    final dr = (draws + 0.25 * 10) / (total + 10);
    final lg = (goals + 3 * 1.0) / (2 * total + 3);
    return EnsembleModel._(pr, EnsembleReport(evaluated, scores, List.of(hedge)), teams, scale, lg, dr,
        w, List.of(hedge));
  }

  /// Predicts [a] vs [b] with every model and with the ensemble.
  /// [allowDraw] is the caller's wish (league match); the sport decides if a draw can exist.
  EnsemblePrediction predict(String a, String b, {required bool allowDraw}) {
    final pr = allowDraw
        ? profile
        : SportProfile(profile.id, false, profile.marginScale, profile.defaultScale);
    final ta = _teams[_k(a)] ?? _Team();
    final tb = _teams[_k(b)] ?? _Team();
    final three = _predictAll(ta, tb, pr, _scale, _lg, _drawRate, _w);
    return EnsemblePrediction(three[0], three[1], three[2], _blend(three, _hedge), List.of(_hedge));
  }

  /// Names of every team the model has seen.
  List<String> get teams => _teams.keys.toList()..sort();
}
