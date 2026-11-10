/// Sport-specific scoring rules, kept out of the UI so they can be tested.
///
/// Honesty note: only rules that follow a published governing-body rule or a
/// widely used league convention are given non-default values, and each one
/// says which it is in [SportRules.basis]. Every other sport keeps the
/// generic 3/1/0 table the app has always used - that is NOT claimed to be
/// an official rule for that sport, and organisers can override the points
/// per tournament.
library;

import 'standings_calculator.dart';

class SportRules {
  final String sportId;
  final PointsRule points;

  /// Where the points rule comes from, shown to administrators.
  final String basis;

  /// Tie-breakers applied after points.
  final List<TieBreaker> tieBreakers;

  const SportRules({
    required this.sportId,
    required this.points,
    required this.basis,
    this.tieBreakers = StandingsCalculator.defaultOrder,
  });

  /// Volleyball (FIVB best-of-five): 3-0 and 3-1 earn 3 points, 3-2 earns 2
  /// for the winner and 1 for the loser. Assumes the match score is the
  /// number of sets won by each side.
  static int volleyballPoints(int own, int opp) {
    if (own > opp) return opp <= 1 ? 3 : 2;
    if (own < opp) return own == 2 ? 1 : 0;
    return 0; // a volleyball match cannot end level
  }

  /// Wrestling stores UWW classification points as the match score, so a
  /// side's table points are simply its own score.
  static int ownScorePoints(int own, int opp) => own;

  static const _football = SportRules(
    sportId: 'football',
    points: PointsRule(win: 3, draw: 1, loss: 0),
    basis: 'FIFA / common league convention: win 3, draw 1, loss 0',
  );

  static const _generic = SportRules(
    sportId: 'other',
    points: PointsRule(win: 3, draw: 1, loss: 0),
    basis: 'Generic default (the app\'s original rule) - not an official rule; editable per tournament',
  );

  static final Map<String, SportRules> _all = {
    'football': _football,
    'futsal': const SportRules(
      sportId: 'futsal',
      points: PointsRule(win: 3, draw: 1, loss: 0),
      basis: 'Common league convention: win 3, draw 1, loss 0',
    ),
    'basketball': const SportRules(
      sportId: 'basketball',
      points: PointsRule(win: 2, draw: 1, loss: 1),
      basis: 'FIBA competition standings: win 2, loss 1 (a draw cannot occur; 1 each if entered)',
    ),
    'volleyball': const SportRules(
      sportId: 'volleyball',
      points: PointsRule(perMatch: SportRules.volleyballPoints),
      basis: 'FIVB best-of-five: 3-0/3-1 = 3 pts, 3-2 = 2 pts (winner) and 1 pt (loser). '
          'Enter sets won as the score.',
    ),
    'judoSport': const SportRules(
      sportId: 'judoSport',
      points: PointsRule(win: 1, draw: 0, loss: 0),
      basis: 'Judo: win 1, loss 0 (a contest cannot end level). Editable; see the detailed result rules (IJF).',
    ),
    'wrestling': const SportRules(
      sportId: 'wrestling',
      points: PointsRule(perMatch: SportRules.ownScorePoints),
      basis: 'UWW classification points (fall 5-0, technical superiority 4-0/4-1, decision 3-0/3-1) are stored as the match score.',
    ),
    'taekwondo': const SportRules(
      sportId: 'taekwondo',
      points: PointsRule(win: 3, draw: 0, loss: 0),
      basis: 'World Taekwondo defines no league points; win 3, loss 0 is an editable convention.',
    ),
    'tennis': const SportRules(
      sportId: 'tennis',
      points: PointsRule(win: 1, draw: 0, loss: 0),
      basis: 'Tennis round robin: win 1, loss 0; ties are broken by sets then games. Editable.',
    ),
    'tableTennis': const SportRules(
      sportId: 'tableTennis',
      points: PointsRule(win: 2, draw: 0, loss: 0),
      basis: 'Table tennis league convention: win 2, loss 0 (editable); score = games won.',
    ),
    'chess': const SportRules(
      sportId: 'chess',
      points: PointsRule(win: 2, draw: 1, loss: 0),
      basis: 'FIDE: win 1, draw 1/2, loss 0 - kept in half-point units (win 2, draw 1, loss 0). Editable.',
    ),
    'kurash': const SportRules(
      sportId: 'kurash',
      points: PointsRule(win: 3, draw: 0, loss: 0),
      basis: 'Kurash has no official league points; win 3, loss 0 is an editable convention (see detailed result rules, IKA).',
    ),
    'cricket': const SportRules(
      sportId: 'cricket',
      points: PointsRule(win: 2, draw: 1, loss: 0),
      basis: 'Common league convention (e.g. T20 leagues): win 2, tie/no result 1, loss 0',
    ),
  };

  /// Rules for [sportId]; unknown or generic sports fall back to 3/1/0.
  static SportRules of(String? sportId) => _all[sportId] ?? _generic;

  /// Sports whose points rule is anything other than the generic default.
  static bool hasSpecificRule(String? sportId) => _all.containsKey(sportId);
}
