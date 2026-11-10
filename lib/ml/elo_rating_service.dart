import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../data/database_helper.dart';
import '../models/match_model.dart';
import '../models/tournament.dart';

/// Sport-specific behaviour of the rating model.
///
/// * [draws]        – can a match end level? (football yes; volleyball, judo… no)
/// * [marginScale]  – how big a "one unit" winning margin is in this sport's
///                    scoring (1 goal in football, ~10 points in basketball…),
///                    so a 90-point cricket win is not treated like a 90-goal rout.
/// * [defaultScale] – starting width of the probability curve. Football's
///                    value (500) comes from an offline experiment on public match
///                    data (its report is not part of this package, so treat it as
///                    unverified here); other sports start at 400 and the scale is
///                    re-tuned automatically from the user's own data.
class SportProfile {
  final String id;
  final bool draws;
  final double marginScale;
  final double defaultScale;
  const SportProfile(this.id, this.draws, this.marginScale, this.defaultScale);
}

class SportProfiles {
  static const generic = SportProfile('other', true, 1, 400);
  static const football = SportProfile('football', true, 1, 500);
  static const _all = <String, SportProfile>{
    'football': football,
    // futsal / table tennis: profiles reuse football / tennis-style settings;
    // their prediction accuracy has not been measured.
    'futsal': SportProfile('futsal', true, 1, 500),
    'tableTennis': SportProfile('tableTennis', false, 1, 400),
    'basketball': SportProfile('basketball', false, 10, 400),
    'volleyball': SportProfile('volleyball', false, 1, 400),
    'tennis': SportProfile('tennis', false, 1, 400),
    'cricket': SportProfile('cricket', false, 30, 450),
    'wrestling': SportProfile('wrestling', false, 3, 400),
    'judo': SportProfile('judo', false, 2, 400), // "Free Fighting"
    'judoSport': SportProfile('judoSport', false, 1, 400), // Judo
    'taekwondo': SportProfile('taekwondo', false, 3, 400),
    // chess: draws are common (kept); kurash: bouts cannot end level. Accuracy not measured.
    'chess': SportProfile('chess', true, 1, 400),
    'kurash': SportProfile('kurash', false, 3, 400),
    'esports': SportProfile('esports', false, 1, 400),
    // single-start races: every race gives pairwise results (who beat whom)
    'dash': SportProfile('dash', false, 1, 400),
    'athletics': SportProfile('athletics', false, 1, 400),
    'swimming': SportProfile('swimming', false, 1, 400),
    'cycling': SportProfile('cycling', false, 1, 400),
    'other': generic,
  };
  static SportProfile of(String? id) => _all[id] ?? generic;
}

/// One finished match, as seen by the learning model.
class RatingEvent {
  final String matchId;
  final String tournamentId;
  final String sport;
  final String teamA; // team name (ratings follow the team across tournaments)
  final String teamB;
  final int goalsA;
  final int goalsB;
  /// 1 = A won, 0 = B won, 0.5 = draw (incl. level aggregate decided on penalties).
  final double resultA;
  final int seq;
  const RatingEvent({
    required this.matchId,
    required this.tournamentId,
    this.sport = 'other',
    required this.teamA,
    required this.teamB,
    required this.goalsA,
    required this.goalsB,
    required this.resultA,
    required this.seq,
  });
}

/// A team's learned strength.
class TeamRating {
  final String name;
  double rating;
  int played = 0, wins = 0, draws = 0, losses = 0;
  TeamRating(this.name, this.rating);
}

/// Win/draw/loss probabilities predicted for a fixture.
class MatchPrediction {
  final double pA, pDraw, pB;
  const MatchPrediction(this.pA, this.pDraw, this.pB);
  /// 0 = A, 1 = draw, 2 = B  (most likely outcome)
  int get argmax => (pA >= pDraw && pA >= pB) ? 0 : (pB >= pDraw ? 2 : 1);
}

/// One bin of the reliability (calibration) table: predictions whose confidence
/// fell into [low, high), how confident they were on average and how often
/// the predicted outcome really happened.
class CalibrationBin {
  final double low, high;
  final int count;
  final double meanConfidence; // 0..1
  final double hitRate; // 0..1
  const CalibrationBin(this.low, this.high, this.count, this.meanConfidence, this.hitRate);
}

/// Result of replaying the whole history of one sport.
class RatingModel {
  final Map<String, TeamRating> ratings; // key = normalized name
  final double drawRate; // learned global draw frequency
  final int evaluated; // matches that were predicted before being learned
  final double accuracy; // share of correctly predicted outcomes
  final double brier; // mean Brier score (lower = better; 0.667 = random 3-way)
  final double homeAdvantage; // rating points added to the home side
  final double scale; // width of the probability curve (auto-tuned per sport)
  final SportProfile profile;
  final List<CalibrationBin> calibration;
  RatingModel(
    this.ratings,
    this.drawRate,
    this.evaluated,
    this.accuracy,
    this.brier, {
    this.homeAdvantage = 0,
    this.scale = 400,
    this.profile = SportProfiles.generic,
    this.calibration = const [],
  });

  /// Expected calibration error: average |confidence - hit rate| over the bins
  /// (0 = perfectly calibrated), weighted by bin size. null without data.
  double? get calibrationError {
    final n = calibration.fold<int>(0, (s, b) => s + b.count);
    if (n == 0) return null;
    return calibration.fold<double>(0, (s, b) => s + b.count * (b.meanConfidence - b.hitRate).abs()) / n;
  }

  double ratingOf(String name) =>
      ratings[EloRatingService.key(name)]?.rating ?? EloRatingService.initialRating;
  int playedOf(String name) => ratings[EloRatingService.key(name)]?.played ?? 0;

  /// [allowDraw] is the caller's wish (e.g. league match); the sport decides
  /// whether a draw is possible at all.
  MatchPrediction predict(String a, String b, {required bool allowDraw}) =>
      EloRatingService.predict(ratingOf(a) + homeAdvantage, ratingOf(b), drawRate,
          allowDraw: allowDraw && profile.draws, scale: scale);

  List<TeamRating> get ranking {
    final l = ratings.values.where((r) => r.played > 0).toList()
      ..sort((x, y) => y.rating.compareTo(x.rating));
    return l;
  }
}

/// Machine-learning component: an online Elo-style rating model.
///
/// * Model:  E_A = 1 / (1 + 10^((R_B - R_A)/scale))  (logistic win expectancy)
/// * Learning: after every match R_A += K * G * (S_A - E_A), where S_A is the
///   real result (1 / 0.5 / 0), G a margin multiplier (scaled to the sport)
///   and K a learning rate that is larger for teams with little data.
/// * Draw model: P(draw) = d * 4 * E * (1-E), with d the draw frequency
///   learned (Laplace-smoothed) from the data — only for sports with draws.
/// * Hyper-parameter learning: once ≥ 30 matches of a sport exist, the curve
///   width `scale` is chosen from {250,300,400,500,650} (+ the sport default)
///   by minimising the walk-forward Brier score on that sport's own history.
/// * Evaluation: each match is predicted BEFORE it is learned (prequential /
///   walk-forward validation) → accuracy and Brier score are honest.
///
/// Ratings are kept PER SPORT (a team called "Kabul" in football is unrelated
/// to "Kabul" in wrestling). State is never stored incrementally: ratings are
/// replayed from an event log, so undo / edits can never leave the model
/// inconsistent.
class EloRatingService {
  EloRatingService._();
  static final EloRatingService instance = EloRatingService._();

  static const double initialRating = 1000;
  static const double _priorDraw = 0.25;
  static const double _priorWeight = 10;
  static const int _tuneMinMatches = 30;
  static const List<double> _scaleCandidates = [250, 300, 400, 500, 650];

  static String key(String name) => name.trim().toLowerCase();

  static double expected(double ra, double rb, {double scale = 400}) =>
      1.0 / (1.0 + pow(10, (rb - ra) / scale).toDouble());

  static double _k(int played) => played < 10 ? 32 : 20;

  static double _marginFactor(int gd, double marginScale) {
    final d = gd.abs() / marginScale;
    if (d <= 1) return 1;
    if (d <= 2) return 1.5;
    return (11 + min(d, 8.0)) / 8;
  }

  static MatchPrediction predict(double ra, double rb, double drawRate,
      {required bool allowDraw, double scale = 400}) {
    final e = expected(ra, rb, scale: scale);
    if (!allowDraw) return MatchPrediction(e, 0, 1 - e);
    final double d = drawRate.clamp(0.05, 0.45).toDouble();
    final pd = d * 4 * e * (1 - e);
    return MatchPrediction(e - pd / 2, pd, 1 - e - pd / 2);
  }

  // ------------------------------------------------------------ storage

  // ---------------------------------------------------------------- memory fallback
  // The database can be unavailable (e.g. Flutter Web without the sqflite web worker).
  // Learning then runs from an in-memory copy of the events, so the AI screens never hang.
  final Map<String, List<RatingEvent>> _mem = {}; // tournamentId -> events
  final Map<String, int> _memSeq = {}; // matchId -> stable sequence number
  int _nextSeq = 1;
  bool _dbBroken = false;

  /// Opens the database, or returns null when it cannot be used (fast, never hangs).
  Future<Database?> _db() async {
    if (_dbBroken) return null;
    try {
      return await DatabaseHelper.instance.database.timeout(const Duration(seconds: 4));
    } catch (_) {
      _dbBroken = true;
      return null;
    }
  }

  /// Rebuilds the in-memory copy from tournaments the app already holds. Cheap and
  /// synchronous, call it before reading AI data.
  void ingestAll(Iterable<Tournament> tournaments) {
    final ids = <String>{};
    for (final t in tournaments) {
      ids.add(t.id);
      ingestOne(t);
    }
    _mem.removeWhere((k, _) => !ids.contains(k));
  }

  void ingestOne(Tournament t) {
    final events = <RatingEvent>[];
    for (final w in _wanted(t).values) {
      final id = w['matchId'] as String;
      final seq = _memSeq.putIfAbsent(id, () => _nextSeq++);
      events.add(RatingEvent(
        matchId: id,
        tournamentId: t.id,
        sport: w['sport'] as String,
        teamA: w['teamA'] as String,
        teamB: w['teamB'] as String,
        goalsA: w['goalsA'] as int,
        goalsB: w['goalsB'] as int,
        resultA: (w['resultA'] as num).toDouble(),
        seq: seq,
      ));
    }
    _mem[t.id] = events;
  }

  List<RatingEvent> _memEvents(String? sport) {
    final l = [
      for (final e in _mem.values) ...e.where((x) => sport == null || x.sport == sport)
    ]..sort((x, y) => x.seq.compareTo(y.seq));
    return l;
  }

  Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rating_events (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        matchId TEXT NOT NULL UNIQUE,
        tournamentId TEXT NOT NULL,
        sport TEXT NOT NULL DEFAULT 'other',
        teamA TEXT NOT NULL,
        teamB TEXT NOT NULL,
        goalsA INTEGER NOT NULL,
        goalsB INTEGER NOT NULL,
        resultA REAL NOT NULL
      )
    ''');
  }

  /// The learning events a tournament currently justifies, keyed by match id.
  Map<String, Map<String, Object?>> _wanted(Tournament t) {
      final all = [...t.matches, for (final g in t.groups) ...g.matches];
      final wanted = <String, Map<String, Object?>>{};
      if (t.type == TournamentType.race) {
        // A race has no head-to-head matches: every pair of classified finishers is one
        // learning event (the faster entrant beat the slower one; equal places = draw).
        final placed = [
          for (final m in t.matches)
            if (m.isPlayed && m.scoreA != null && t.teamById(m.teamAId) != null) m
        ]..sort((x, y) => x.scoreA!.compareTo(y.scoreA!));
        final capped = placed.length > 40 ? placed.sublist(0, 40) : placed;
        for (var i = 0; i < capped.length; i++) {
          for (var j = i + 1; j < capped.length; j++) {
            final x = capped[i], y = capped[j];
            final tie = x.scoreA == y.scoreA;
            final id = '${x.id}:${y.id}';
            wanted[id] = {
              'matchId': id,
              'tournamentId': t.id,
              'sport': t.sport,
              'teamA': t.teamById(x.teamAId)!.name.trim(),
              'teamB': t.teamById(y.teamAId)!.name.trim(),
              'goalsA': tie ? 0 : 1,
              'goalsB': 0,
              'resultA': tie ? 0.5 : 1.0,
            };
          }
        }
      }
      for (final m in (t.type == TournamentType.race ? const <MatchModel>[] : all)) {
        if (!m.isPlayed || m.isBye) continue;
        final a = t.teamById(m.teamAId), b = t.teamById(m.teamBId);
        if (a == null || b == null || m.scoreA == null || m.scoreB == null) continue;
        final ga = m.scoreA! + (m.scoreA2 ?? 0);
        final gb = m.scoreB! + (m.scoreB2 ?? 0);
        double res;
        if (ga != gb) {
          res = ga > gb ? 1 : 0;
        } else {
          res = 0.5;
        }
        wanted[m.id] = {
          'matchId': m.id,
          'tournamentId': t.id,
          'sport': t.sport,
          'teamA': a.name.trim(),
          'teamB': b.name.trim(),
          'goalsA': ga,
          'goalsB': gb,
          'resultA': res,
        };
      }
    return wanted;
  }

  /// Brings the event log of [t] in line with its finished matches.
  /// Call after every result change and after undo.
  Future<void> syncTournament(Tournament t) async {
    ingestOne(t);
    try {
      final db = await _db();
      if (db == null) return;
      await _ensureTable(db);
      final wanted = _wanted(t);
      final existing = await db.query('rating_events',
          where: 'tournamentId = ?', whereArgs: [t.id]);
      final batch = db.batch();
      final seen = <String>{};
      for (final r in existing) {
        final id = r['matchId'] as String;
        final w = wanted[id];
        if (w == null) {
          batch.delete('rating_events', where: 'matchId = ?', whereArgs: [id]);
          continue;
        }
        seen.add(id);
        final same = r['teamA'] == w['teamA'] &&
            r['teamB'] == w['teamB'] &&
            r['goalsA'] == w['goalsA'] &&
            r['goalsB'] == w['goalsB'] &&
            r['sport'] == w['sport'];
        if (!same) {
          // result was corrected: re-enter at the end of the log
          batch.delete('rating_events', where: 'matchId = ?', whereArgs: [id]);
          batch.insert('rating_events', w);
        }
      }
      for (final e in wanted.entries) {
        if (!seen.contains(e.key)) batch.insert('rating_events', e.value);
      }
      await batch.commit(noResult: true);
    } catch (_) {
      // learning must never break match entry
    }
  }

  Future<void> deleteTournamentEvents(String tournamentId) async {
    _mem.remove(tournamentId);
    try {
      final db = await _db();
      if (db == null) return;
      await _ensureTable(db);
      await db.delete('rating_events',
          where: 'tournamentId = ?', whereArgs: [tournamentId]);
    } catch (_) {}
  }

  /// Sports that have at least one learned match, with their match counts.
  Future<Map<String, int>> sportsWithData() async {
    try {
      final db = await _db();
      if (db != null) {
        await _ensureTable(db);
        final rows = await db.rawQuery(
            'SELECT sport, COUNT(*) AS c FROM rating_events GROUP BY sport');
        final fromDb = {for (final r in rows) r['sport'] as String: (r['c'] as num).toInt()};
        if (fromDb.isNotEmpty) return fromDb;
      }
    } catch (_) {
      _dbBroken = true;
    }
    final out = <String, int>{};
    for (final e in _memEvents(null)) {
      out[e.sport] = (out[e.sport] ?? 0) + 1;
    }
    return out;
  }

  /// The learning events of [sport] in time order (empty when none / on error).
  Future<List<RatingEvent>> eventsOf(String sport) async {
    try {
      return await _loadEvents(sport);
    } catch (_) {
      return const [];
    }
  }

  Future<List<RatingEvent>> _loadEvents(String? sport) async {
    final db = await _db();
    if (db == null) return _memEvents(sport);
    await _ensureTable(db);
    final rows = await db.query('rating_events',
        where: sport == null ? null : 'sport = ?',
        whereArgs: sport == null ? null : [sport],
        orderBy: 'seq ASC');
    if (rows.isEmpty) return _memEvents(sport);
    return rows
        .map((r) => RatingEvent(
              matchId: r['matchId'] as String,
              tournamentId: r['tournamentId'] as String,
              sport: (r['sport'] as String?) ?? 'other',
              teamA: r['teamA'] as String,
              teamB: r['teamB'] as String,
              goalsA: r['goalsA'] as int,
              goalsB: r['goalsB'] as int,
              resultA: (r['resultA'] as num).toDouble(),
              seq: r['seq'] as int,
            ))
        .toList();
  }

  /// Replays the history of [sport] (or of everything when null) and returns
  /// the trained model.
  Future<RatingModel> train({String? sport}) async {
    List<RatingEvent> events;
    try {
      events = await _loadEvents(sport);
    } catch (_) {
      events = _memEvents(sport);
    }
    return trainFrom(events,
        profile: sport == null ? SportProfiles.generic : SportProfiles.of(sport));
  }

  // ------------------------------------------------------------- learning

  static RatingModel trainFrom(
    List<RatingEvent> events, {
    double homeAdvantage = 0,
    SportProfile profile = SportProfiles.generic,
    bool tune = true,
  }) {
    var best = _replay(events, homeAdvantage, profile.defaultScale, profile);
    if (tune && events.length >= _tuneMinMatches) {
      for (final s in _scaleCandidates) {
        if (s == profile.defaultScale) continue;
        final m = _replay(events, homeAdvantage, s, profile);
        if (m.brier < best.brier - 1e-9) best = m;
      }
    }
    return best;
  }

  static RatingModel _replay(
      List<RatingEvent> events, double ha, double scale, SportProfile profile) {
    final ratings = <String, TeamRating>{};
    var draws = 0, total = 0, evaluated = 0, correct = 0;
    var brierSum = 0.0;
    const edges = [0.0, 0.4, 0.5, 0.6, 0.7, 0.8, 1.0001];
    final binN = List<int>.filled(edges.length - 1, 0);
    final binConf = List<double>.filled(edges.length - 1, 0);
    final binHit = List<int>.filled(edges.length - 1, 0);

    TeamRating get(String n) =>
        ratings.putIfAbsent(key(n), () => TeamRating(n.trim(), initialRating));

    for (final ev in events) {
      final a = get(ev.teamA), b = get(ev.teamB);
      final dr = (draws + _priorDraw * _priorWeight) / (total + _priorWeight);

      // 1) predict BEFORE learning (honest evaluation)
      final p = predict(a.rating + ha, b.rating, dr,
          allowDraw: profile.draws, scale: scale);
      final actualIdx = ev.resultA == 1 ? 0 : (ev.resultA == 0 ? 2 : 1);
      final oa = actualIdx == 0 ? 1.0 : 0.0;
      final od = actualIdx == 1 ? 1.0 : 0.0;
      final ob = actualIdx == 2 ? 1.0 : 0.0;
      brierSum += (p.pA - oa) * (p.pA - oa) +
          (p.pDraw - od) * (p.pDraw - od) +
          (p.pB - ob) * (p.pB - ob);
      if (a.played + b.played > 0) {
        // skip pure cold-start (nothing learned yet) from the accuracy score
        evaluated++;
        if (p.argmax == actualIdx) correct++;
        final conf = [p.pA, p.pDraw, p.pB][p.argmax];
        var bi = 0;
        while (bi < binN.length - 1 && conf >= edges[bi + 1]) {
          bi++;
        }
        binN[bi]++;
        binConf[bi] += conf;
        if (p.argmax == actualIdx) binHit[bi]++;
      }

      // 2) learn
      final e = expected(a.rating + ha, b.rating, scale: scale);
      final g = _marginFactor(ev.goalsA - ev.goalsB, profile.marginScale);
      final da = _k(a.played) * g * (ev.resultA - e);
      final db = _k(b.played) * g * ((1 - ev.resultA) - (1 - e));
      a.rating += da;
      b.rating += db;
      a.played++;
      b.played++;
      if (ev.resultA == 1) {
        a.wins++;
        b.losses++;
      } else if (ev.resultA == 0) {
        b.wins++;
        a.losses++;
      } else {
        a.draws++;
        b.draws++;
        draws++;
      }
      total++;
    }

    final dr = (draws + _priorDraw * _priorWeight) / (total + _priorWeight);
    return RatingModel(
      ratings,
      dr,
      evaluated,
      evaluated == 0 ? 0 : correct / evaluated,
      events.isEmpty ? 0 : brierSum / events.length,
      homeAdvantage: ha,
      scale: scale,
      profile: profile,
      calibration: [
        for (var i = 0; i < binN.length; i++)
          if (binN[i] > 0)
            CalibrationBin(edges[i], edges[i + 1].clamp(0, 1).toDouble(), binN[i], binConf[i] / binN[i], binHit[i] / binN[i]),
      ],
    );
  }
}
