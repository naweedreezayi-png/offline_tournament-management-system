import 'dart:convert';

import 'sport_rules.dart';

/// One input the organiser fills in for a match (for example "ippon").
///
/// Per-side fields are stored under the keys `<key>A` and `<key>B`; shared
/// fields (such as the wrestling method) use the plain `<key>`.
class ScoreField {
  final String key;
  final String en;
  final String fa;
  final int max;
  final bool perSide;

  /// When not null the field is a choice; the value is the option index.
  /// `{A}` and `{B}` in an option are replaced by the team names in the UI.
  final List<String>? options;
  final List<String>? optionsFa;

  const ScoreField(
    this.key,
    this.en,
    this.fa, {
    this.max = 99,
    this.perSide = true,
    this.options,
    this.optionsFa,
  });

  String label(String lang) => lang == 'fa' ? fa : en;

  List<String>? optionLabels(String lang) =>
      lang == 'fa' && optionsFa != null ? optionsFa : options;
}

/// Result of evaluating the entered details of one match.
class ScoreOutcome {
  /// English message when the input is not a valid result, otherwise null.
  final String? error;

  /// Values stored in the match (what the standings and brackets compare).
  final int scoreA;
  final int scoreB;

  /// Classification points for the table, when the sport defines them per
  /// match. Null means: use the tournament's points rule.
  final int? pointsA;
  final int? pointsB;
  final String summary;

  const ScoreOutcome.ok({
    required this.scoreA,
    required this.scoreB,
    this.pointsA,
    this.pointsB,
    required this.summary,
  }) : error = null;

  const ScoreOutcome.invalid(String message)
      : error = message,
        scoreA = 0,
        scoreB = 0,
        pointsA = null,
        pointsB = null,
        summary = '';

  bool get isValid => error == null;
}

int _g(Map<String, int> v, String k) => v[k] ?? 0;

/// A sport's own way of turning detailed input into a result.
///
/// Rules implemented here are summaries of the federations' rules as known
/// to the author; every [note] names the source and must be checked against
/// the rulebook version your competition uses.
abstract class SportScoring {
  const SportScoring();

  String get sportId;
  String get note;
  List<ScoreField> get fields;
  ScoreOutcome evaluate(Map<String, int> v);

  static const Map<String, SportScoring> _all = {
    'judoSport': JudoScoring(),
    'wrestling': WrestlingScoring(),
    'taekwondo': TaekwondoScoring(),
    'tennis': TennisScoring(),
    'volleyball': VolleyballScoring(),
    'basketball': BasketballScoring(),
    'cricket': CricketScoring(),
    'tableTennis': TableTennisScoring(),
    'chess': ChessScoring(),
    'kurash': KurashScoring(),
  };

  /// The detailed model of [sportId], or null when the sport is scored by
  /// a plain score (football, futsal, generic sports...).
  static SportScoring? of(String? sportId) => _all[sportId];

  /// JSON stored in `matches.detail`.
  static String encode(SportScoring s, Map<String, int> input, ScoreOutcome o) =>
      jsonEncode({
        'sport': s.sportId,
        'in': input,
        'pA': o.pointsA,
        'pB': o.pointsB,
        'summary': o.summary,
      });

  /// Classification points saved with a match, or null.
  static List<int>? classificationPoints(String? detail) {
    if (detail == null || detail.isEmpty) return null;
    try {
      final m = jsonDecode(detail);
      if (m is Map && m['pA'] is int && m['pB'] is int) {
        return [m['pA'] as int, m['pB'] as int];
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String? summaryOf(String? detail) {
    if (detail == null || detail.isEmpty) return null;
    try {
      final m = jsonDecode(detail);
      if (m is Map && m['summary'] is String) return m['summary'] as String;
    } catch (_) {
      return null;
    }
    return null;
  }

  static Map<String, int> inputOf(String? detail) {
    final out = <String, int>{};
    if (detail == null || detail.isEmpty) return out;
    try {
      final m = jsonDecode(detail);
      if (m is Map && m['in'] is Map) {
        (m['in'] as Map).forEach((k, val) {
          if (k is String && val is int) out[k] = val;
        });
      }
    } catch (_) {
      return out;
    }
    return out;
  }
}

// ---------------------------------------------------------------- judo

/// Judo (IJF contest rules, 2017 onwards): ippon ends the contest, waza-ari
/// decides on points, a third shido is a loss (hansoku-make), level scores
/// go to golden score. Yuko was removed from the IJF rules (2017); it is kept
/// as an optional legacy field because many local competitions still use it.
///
/// Stored values (an app convention, not an IJF number): ippon and
/// hansoku-make wins store 10; otherwise waza-ari = 7 and yuko = 5 are
/// summed; a golden-score win stores the level score + 1.
class JudoScoring extends SportScoring {
  const JudoScoring();
  static const int ipponValue = 10;
  static const int wazaariValue = 7;
  static const int yukoValue = 5;

  @override
  String get sportId => 'judoSport';

  @override
  String get note =>
      'IJF contest rules (2017+): ippon, waza-ari, shido. Automatic: 1 ippon or 2 waza-ari = win; '
      '3 shido = loss. '
      'Yuko is an optional legacy field. Table points: win 1, loss 0. '
      'Verify against the rulebook version of your competition.';

  @override
  List<ScoreField> get fields => const [
        ScoreField('ippon', 'Ippon', 'ایپون', max: 1),
        ScoreField('wazaari', 'Waza-ari', 'وازاری', max: 5),
        ScoreField('yuko', 'Yuko (legacy)', 'یوکو (قدیمی)', max: 9),
        ScoreField('shido', 'Shido', 'شیدو', max: 3),
        ScoreField('golden', 'Golden score / decision winner',
            'برندهٔ گلدن اسکور / تصمیم',
            perSide: false,
            options: ['—', '{A}', '{B}'],
            optionsFa: ['—', '{A}', '{B}']),
      ];

  @override
  ScoreOutcome evaluate(Map<String, int> v) {
    final ipA = _g(v, 'ipponA'), ipB = _g(v, 'ipponB');
    final wA = _g(v, 'wazaariA'), wB = _g(v, 'wazaariB');
    final yA = _g(v, 'yukoA'), yB = _g(v, 'yukoB');
    final sA = _g(v, 'shidoA'), sB = _g(v, 'shidoB');
    final golden = _g(v, 'golden');
    if (ipA > 0 && ipB > 0) {
      return const ScoreOutcome.invalid('Only one competitor can score ippon.');
    }
    if (sA >= 3 && sB >= 3) {
      return const ScoreOutcome.invalid('Both competitors cannot reach 3 shido.');
    }
    final valA = wA * wazaariValue + yA * yukoValue;
    final valB = wB * wazaariValue + yB * yukoValue;
    String winner;
    String how;
    if (ipA > 0) {
      winner = 'A';
      how = 'ippon';
    } else if (ipB > 0) {
      winner = 'B';
      how = 'ippon';
    } else if (sA >= 3) {
      winner = 'B';
      how = 'hansoku-make';
    } else if (sB >= 3) {
      winner = 'A';
      how = 'hansoku-make';
    } else if (wA >= 2 && wB >= 2) {
      return const ScoreOutcome.invalid('Both competitors cannot have two waza-ari.');
    } else if (wA >= 2) {
      winner = 'A';
      how = 'two waza-ari (waza-ari awasete ippon)';
    } else if (wB >= 2) {
      winner = 'B';
      how = 'two waza-ari (waza-ari awasete ippon)';
    } else if (valA > valB) {
      winner = 'A';
      how = 'points';
    } else if (valB > valA) {
      winner = 'B';
      how = 'points';
    } else if (golden == 1) {
      winner = 'A';
      how = 'golden score';
    } else if (golden == 2) {
      winner = 'B';
      how = 'golden score';
    } else {
      return const ScoreOutcome.invalid(
          'Scores are level: choose the golden-score / decision winner.');
    }
    int a, b;
    if (how == 'ippon' || how == 'hansoku-make' || how.startsWith('two waza-ari')) {
      final loserVal = winner == 'A' ? valB : valA;
      final capped = loserVal > 9 ? 9 : loserVal;
      a = winner == 'A' ? ipponValue : capped;
      b = winner == 'B' ? ipponValue : capped;
    } else if (how == 'golden score') {
      a = winner == 'A' ? valA + 1 : valA;
      b = winner == 'B' ? valB + 1 : valB;
    } else {
      a = valA;
      b = valB;
    }
    return ScoreOutcome.ok(
      scoreA: a,
      scoreB: b,
      pointsA: winner == 'A' ? 1 : 0,
      pointsB: winner == 'B' ? 1 : 0,
      summary: '$winner wins by $how',
    );
  }
}

// ------------------------------------------------------------ wrestling

/// Wrestling (UWW): technical points, fall, technical superiority (lead of
/// [superiorityLead] points) and classification points. The stored match
/// score is the classification points, so the winner is always the larger
/// number and the table uses them directly.
///   fall / injury / default / disqualification: 5-0
///   technical superiority: 4-0, or 4-1 if the loser scored technical points
///   decision on points: 3-0, or 3-1 if the loser scored technical points
class WrestlingScoring extends SportScoring {
  const WrestlingScoring();
  static const int superiorityLead = 10;

  @override
  String get sportId => 'wrestling';

  @override
  String get note =>
      'UWW classification points (fall 5-0, technical superiority 4-0/4-1 at a '
      '10-point lead, decision 3-0/3-1). Verify against the current UWW rules '
      'for your style and age group.';

  @override
  List<ScoreField> get fields => const [
        ScoreField('tech', 'Technical points', 'امتیاز فنی', max: 60),
        ScoreField('method', 'Result type', 'نوع پیروزی',
            perSide: false,
            options: ['Points', 'Fall (pin)', 'Default / injury / disqualification'],
            optionsFa: ['امتیازی', 'ضربه فنی / خوابیدن (فال)', 'انصراف / مصدومیت / رد صلاحیت']),
        ScoreField('winner', 'Winner (needed for fall, default or equal points)',
            'برنده (برای فال، انصراف یا امتیاز مساوی)',
            perSide: false,
            options: ['—', '{A}', '{B}'],
            optionsFa: ['—', '{A}', '{B}']),
      ];

  @override
  ScoreOutcome evaluate(Map<String, int> v) {
    final tA = _g(v, 'techA'), tB = _g(v, 'techB');
    final method = _g(v, 'method');
    final chosen = _g(v, 'winner');
    String? winner = chosen == 1 ? 'A' : (chosen == 2 ? 'B' : null);
    String how;
    int cpWin;
    if (method == 1 || method == 2) {
      if (winner == null) {
        return const ScoreOutcome.invalid('Choose the winner.');
      }
      how = method == 1 ? 'fall' : 'default';
      cpWin = 5;
      return ScoreOutcome.ok(
        scoreA: winner == 'A' ? cpWin : 0,
        scoreB: winner == 'B' ? cpWin : 0,
        pointsA: winner == 'A' ? cpWin : 0,
        pointsB: winner == 'B' ? cpWin : 0,
        summary: '$winner wins by $how (technical $tA-$tB)',
      );
    }
    if (tA > tB) {
      winner = 'A';
    } else if (tB > tA) {
      winner = 'B';
    } else if (winner == null) {
      return const ScoreOutcome.invalid(
          'Technical points are level: choose the winner (criteria).');
    }
    final lead = tA > tB ? tA - tB : (tB > tA ? tB - tA : 0);
    final loserTech = winner == 'A' ? tB : tA;
    if (lead >= superiorityLead) {
      how = 'technical superiority';
      cpWin = 4;
    } else {
      how = 'decision';
      cpWin = 3;
    }
    final cpLose = loserTech > 0 ? 1 : 0;
    return ScoreOutcome.ok(
      scoreA: winner == 'A' ? cpWin : cpLose,
      scoreB: winner == 'B' ? cpWin : cpLose,
      pointsA: winner == 'A' ? cpWin : cpLose,
      pointsB: winner == 'B' ? cpWin : cpLose,
      summary: '$winner wins by $how (technical $tA-$tB)',
    );
  }
}

// ------------------------------------------------------------ taekwondo

/// Taekwondo (World Taekwondo): best of three rounds. Stored score = rounds
/// won. A withdrawal or disqualification is recorded as a 2-0 win.
class TaekwondoScoring extends SportScoring {
  const TaekwondoScoring();

  @override
  String get sportId => 'taekwondo';

  @override
  String get note =>
      'WT: best of three rounds; stored score = rounds won. World Taekwondo '
      'defines no league points, so the table uses an editable rule (3/0).';

  @override
  List<ScoreField> get fields => const [
        ScoreField('rounds', 'Rounds won', 'راندهای برده', max: 2),
        ScoreField('forfeit', 'Withdrawal / disqualification winner',
            'برندهٔ انصراف / رد صلاحیت',
            perSide: false,
            options: ['—', '{A}', '{B}'],
            optionsFa: ['—', '{A}', '{B}']),
      ];

  @override
  ScoreOutcome evaluate(Map<String, int> v) {
    final forfeit = _g(v, 'forfeit');
    if (forfeit == 1 || forfeit == 2) {
      return ScoreOutcome.ok(
        scoreA: forfeit == 1 ? 2 : 0,
        scoreB: forfeit == 2 ? 2 : 0,
        summary: '${forfeit == 1 ? 'A' : 'B'} wins by withdrawal / disqualification',
      );
    }
    final a = _g(v, 'roundsA'), b = _g(v, 'roundsB');
    final hi = a > b ? a : b;
    final lo = a > b ? b : a;
    if (hi != 2 || lo > 1) {
      return const ScoreOutcome.invalid(
          'Best of three rounds: the winner needs 2 rounds, the other 0 or 1.');
    }
    return ScoreOutcome.ok(
      scoreA: a,
      scoreB: b,
      summary: '${a > b ? 'A' : 'B'} wins $hi-$lo in rounds',
    );
  }
}

// --------------------------------------------------------------- tennis

/// Tennis: best of three or five sets. Stored score = sets won.
class TennisScoring extends SportScoring {
  const TennisScoring();

  @override
  String get sportId => 'tennis';

  @override
  String get note =>
      'Best of 3 (2 sets) or best of 5 (3 sets); stored score = sets won. '
      'Games are kept for information. Table points: win 1, loss 0 (editable).';

  @override
  List<ScoreField> get fields => const [
        ScoreField('sets', 'Sets won', 'ست‌های برده', max: 3),
        ScoreField('games', 'Games won (total)', 'گیم‌های برده (مجموع)', max: 99),
      ];

  @override
  ScoreOutcome evaluate(Map<String, int> v) {
    final a = _g(v, 'setsA'), b = _g(v, 'setsB');
    final hi = a > b ? a : b;
    final lo = a > b ? b : a;
    final ok = (hi == 2 && lo <= 1) || (hi == 3 && lo <= 2);
    if (!ok) {
      return const ScoreOutcome.invalid(
          'Best of 3 or 5 sets: the winner needs 2 (or 3) sets and the other fewer.');
    }
    return ScoreOutcome.ok(
      scoreA: a,
      scoreB: b,
      summary: '${a > b ? 'A' : 'B'} wins $hi-$lo in sets '
          '(games ${_g(v, 'gamesA')}-${_g(v, 'gamesB')})',
    );
  }
}

// ----------------------------------------------------------- volleyball

/// Volleyball (FIVB): best of five sets, sets to 25 (the fifth to 15), win
/// by two points. Stored score = sets won; table points 3/2/1/0.
class VolleyballScoring extends SportScoring {
  const VolleyballScoring();

  @override
  String get sportId => 'volleyball';

  @override
  String get note =>
      'FIVB: sets to 25 (5th set to 15), two-point margin; 3-0 and 3-1 = 3 '
      'points, 3-2 = 2 for the winner and 1 for the loser.';

  @override
  List<ScoreField> get fields => const [
        ScoreField('s1', 'Set 1 points', 'امتیاز ست ۱', max: 60),
        ScoreField('s2', 'Set 2 points', 'امتیاز ست ۲', max: 60),
        ScoreField('s3', 'Set 3 points', 'امتیاز ست ۳', max: 60),
        ScoreField('s4', 'Set 4 points', 'امتیاز ست ۴', max: 60),
        ScoreField('s5', 'Set 5 points', 'امتیاز ست ۵', max: 60),
      ];

  @override
  ScoreOutcome evaluate(Map<String, int> v) {
    var wonA = 0, wonB = 0;
    for (var i = 1; i <= 5; i++) {
      final a = _g(v, 's${i}A'), b = _g(v, 's${i}B');
      final decided = wonA == 3 || wonB == 3;
      if (a == 0 && b == 0) {
        if (!decided) return ScoreOutcome.invalid('Set $i is missing.');
        continue;
      }
      if (decided) {
        return ScoreOutcome.invalid('Set $i was played after the match was decided.');
      }
      final target = i == 5 ? 15 : 25;
      final w = a > b ? a : b;
      final l = a > b ? b : a;
      final okSet = w >= target && w - l >= 2 && (w == target || w - l == 2);
      if (!okSet) {
        return ScoreOutcome.invalid(
            'Set $i ($a-$b) is not valid: play to $target and win by two.');
      }
      if (a > b) {
        wonA++;
      } else {
        wonB++;
      }
    }
    if (wonA != 3 && wonB != 3) {
      return const ScoreOutcome.invalid('The match is not finished: a team needs 3 sets.');
    }
    return ScoreOutcome.ok(
      scoreA: wonA,
      scoreB: wonB,
      pointsA: SportRules.volleyballPoints(wonA, wonB),
      pointsB: SportRules.volleyballPoints(wonB, wonA),
      summary: '${wonA > wonB ? 'A' : 'B'} wins ${wonA > wonB ? wonA : wonB}-'
          '${wonA > wonB ? wonB : wonA} in sets',
    );
  }
}

// ----------------------------------------------------------- basketball

/// Basketball (FIBA): free throws 1, field goals 2, three-pointers 3. A game
/// cannot end level. Table points: win 2, loss 1.
class BasketballScoring extends SportScoring {
  const BasketballScoring();

  @override
  String get sportId => 'basketball';

  @override
  String get note =>
      'FIBA: free throw 1, field goal 2, three-pointer 3; no draws (overtime). '
      'Table points: win 2, loss 1.';

  @override
  List<ScoreField> get fields => const [
        ScoreField('ft', 'Free throws made (1 pt)', 'پرتاب آزاد (۱ امتیاز)', max: 80),
        ScoreField('fg2', 'Two-pointers made (2 pts)', 'دو امتیازی (۲ امتیاز)', max: 80),
        ScoreField('fg3', 'Three-pointers made (3 pts)', 'سه امتیازی (۳ امتیاز)', max: 60),
      ];

  @override
  ScoreOutcome evaluate(Map<String, int> v) {
    final a = _g(v, 'ftA') + 2 * _g(v, 'fg2A') + 3 * _g(v, 'fg3A');
    final b = _g(v, 'ftB') + 2 * _g(v, 'fg2B') + 3 * _g(v, 'fg3B');
    if (a == b) {
      return const ScoreOutcome.invalid(
          'A basketball game cannot end level: play overtime.');
    }
    return ScoreOutcome.ok(
      scoreA: a,
      scoreB: b,
      pointsA: a > b ? 2 : 1,
      pointsB: b > a ? 2 : 1,
      summary: '${a > b ? 'A' : 'B'} wins ${a > b ? a : b}-${a > b ? b : a}',
    );
  }
}

// -------------------------------------------------------------- cricket

/// Cricket: runs, wickets lost and overs. The winner is the side with more
/// runs; the margin is in runs (if the side batting first won) or in wickets
/// (if the chasing side won). Table points: win 2, tie or no result 1, loss 0.
/// Net run rate is NOT calculated.
class CricketScoring extends SportScoring {
  const CricketScoring();

  @override
  String get sportId => 'cricket';

  @override
  String get note =>
      'Runs decide the winner; margin by runs or wickets. Points: win 2, tie or '
      'no result 1, loss 0 (common league convention). Net run rate is not implemented.';

  @override
  List<ScoreField> get fields => const [
        ScoreField('runs', 'Runs', 'ران', max: 999),
        ScoreField('wkts', 'Wickets lost', 'ویکت از دست رفته', max: 10),
        ScoreField('overs', 'Overs', 'اور', max: 50),
        ScoreField('balls', 'Balls', 'توپ', max: 5),
        ScoreField('chase', 'Team batting second', 'تیم دوم (تعقیب‌کننده)',
            perSide: false,
            options: ['—', '{A}', '{B}'],
            optionsFa: ['—', '{A}', '{B}']),
        ScoreField('noResult', 'Match result', 'وضعیت بازی',
            perSide: false,
            options: ['Completed', 'No result / abandoned'],
            optionsFa: ['تمام‌شده', 'بدون نتیجه / لغو']),
      ];

  @override
  ScoreOutcome evaluate(Map<String, int> v) {
    if (_g(v, 'noResult') == 1) {
      return const ScoreOutcome.ok(
          scoreA: 0, scoreB: 0, pointsA: 1, pointsB: 1, summary: 'No result');
    }
    final rA = _g(v, 'runsA'), rB = _g(v, 'runsB');
    final wA = _g(v, 'wktsA'), wB = _g(v, 'wktsB');
    final chase = _g(v, 'chase');
    if (chase != 1 && chase != 2) {
      return const ScoreOutcome.invalid('Choose the team that batted second.');
    }
    if (rA == rB) {
      return ScoreOutcome.ok(
          scoreA: rA, scoreB: rB, pointsA: 1, pointsB: 1, summary: 'Match tied at $rA');
    }
    final aWins = rA > rB;
    final winnerChased = (aWins && chase == 1) || (!aWins && chase == 2);
    final String margin;
    if (winnerChased) {
      final lost = aWins ? wA : wB;
      margin = '${10 - lost} wickets';
    } else {
      margin = '${aWins ? rA - rB : rB - rA} runs';
    }
    return ScoreOutcome.ok(
      scoreA: rA,
      scoreB: rB,
      pointsA: aWins ? 2 : 0,
      pointsB: aWins ? 0 : 2,
      summary: '${aWins ? 'A' : 'B'} wins by $margin',
    );
  }
}

// ---------------------------------------------------------- table tennis

/// Table tennis (ITTF): best of five or seven games. Stored score = games won.
class TableTennisScoring extends SportScoring {
  const TableTennisScoring();

  @override
  String get sportId => 'tableTennis';

  @override
  String get note =>
      'ITTF: games to 11, win by two; best of 5 (3 games) or 7 (4 games). '
      'Stored score = games won. Table points: win 2, loss 0 (editable).';

  @override
  List<ScoreField> get fields => const [
        ScoreField('games', 'Games won', 'گیم‌های برده', max: 4),
      ];

  @override
  ScoreOutcome evaluate(Map<String, int> v) {
    final a = _g(v, 'gamesA'), b = _g(v, 'gamesB');
    final hi = a > b ? a : b;
    final lo = a > b ? b : a;
    if (!(hi >= 2 && hi <= 4 && lo < hi)) {
      return const ScoreOutcome.invalid(
          'The winner needs 2 to 4 games and the other fewer.');
    }
    return ScoreOutcome.ok(
      scoreA: a,
      scoreB: b,
      summary: '${a > b ? 'A' : 'B'} wins $hi-$lo in games',
    );
  }
}

// ---------------------------------------------------------------- chess

/// Chess (FIDE): a win is 1 point, a draw 1/2, a loss 0. The app keeps whole
/// numbers, so table points are stored in half-point units: win 2, draw 1,
/// loss 0 (this equals 1 / 1/2 / 0 multiplied by two). The stored match
/// score is 1-0, 1-1 (draw) or 0-1. Pick how the game ended so impossible
/// combinations (for example "draw by checkmate") are rejected.
class ChessScoring extends SportScoring {
  const ChessScoring();

  @override
  String get sportId => 'chess';

  @override
  String get note =>
      'FIDE scoring: win 1, draw 1/2, loss 0. Table points are shown in half-point '
      'units (win 2, draw 1, loss 0). Tie-breaks such as Buchholz or Sonneborn-Berger '
      'are NOT implemented; the table uses points, then score difference.';

  @override
  List<ScoreField> get fields => const [
        ScoreField('result', 'Result', 'نتیجه',
            perSide: false,
            options: ['—', '{A} wins', 'Draw', '{B} wins'],
            optionsFa: ['—', 'برد {A}', 'مساوی', 'برد {B}']),
        ScoreField('method', 'How the game ended', 'چگونه بازی پایان یافت',
            perSide: false,
            options: [
              'Checkmate',
              'Resignation',
              'Time forfeit',
              'Opponent absent / forfeit',
              'Draw by agreement',
              'Stalemate',
              'Repetition / 50 moves / insufficient material',
            ],
            optionsFa: [
              'کیش و مات',
              'استعفا',
              'اتمام زمان',
              'غیبت حریف / انصراف',
              'تساوی با توافق',
              'پات (بن‌بست)',
              'تکرار حرکات / ۵۰ حرکت / مهرهٔ ناکافی',
            ]),
      ];

  @override
  ScoreOutcome evaluate(Map<String, int> v) {
    final r = _g(v, 'result');
    final m = _g(v, 'method');
    if (r < 1 || r > 3) return const ScoreOutcome.invalid('Choose the result.');
    final draw = r == 2;
    if (draw && m < 4) {
      return const ScoreOutcome.invalid('A draw must end by agreement, stalemate or repetition.');
    }
    if (!draw && m > 3) {
      return const ScoreOutcome.invalid('A win must end by checkmate, resignation, time or forfeit.');
    }
    const how = [
      'checkmate', 'resignation', 'time forfeit', 'forfeit',
      'agreement', 'stalemate', 'repetition / 50-move / insufficient material',
    ];
    if (draw) {
      return ScoreOutcome.ok(
        scoreA: 1, scoreB: 1, pointsA: 1, pointsB: 1,
        summary: '1/2-1/2 draw by ${how[m]}',
      );
    }
    final aWins = r == 1;
    return ScoreOutcome.ok(
      scoreA: aWins ? 1 : 0,
      scoreB: aWins ? 0 : 1,
      pointsA: aWins ? 2 : 0,
      pointsB: aWins ? 0 : 2,
      summary: '${aWins ? 'A' : 'B'} wins by ${how[m]}',
    );
  }
}

// --------------------------------------------------------------- kurash

/// Kurash (Central-Asian belt wrestling, IKA rules as known to the author):
/// chala = 1 point, yonbosh = 2 points, halal = a clean throw that ends the
/// bout at once. Halal is stored as 10 (an app convention, like judo's
/// ippon), so the larger stored score is always the winner. When points are
/// level the side with fewer penalties (tanbeh) wins; if that is level too
/// the organiser picks the winner (judges' decision). Table points: win 3,
/// loss 0 (editable convention; kurash has no official league points).
class KurashScoring extends SportScoring {
  const KurashScoring();

  /// Stored value of a clean win (halal), larger than any point total.
  static const int halalValue = 10;

  @override
  String get sportId => 'kurash';

  @override
  String get note =>
      'Kurash, automatic rules: halal, or two yonbosh = clean win. A girom, two dakki or three '
      'tanbeh = loss (the opponent gets halal). Tanbeh (cumulative): 1st = +1 chala to the opponent; '
      '2nd = +1 yonbosh to the opponent and +1 dakki to the player; 3rd = girom to the player and '
      'halal to the opponent. Otherwise the higher chala/yonbosh total wins, then fewer tanbeh, '
      'then the judges\' decision. Check the values against the current IKA rulebook; table points '
      '(win 3, loss 0) are an editable convention.';

  @override
  List<ScoreField> get fields => const [
        ScoreField('chala', 'Chala (1 point)', 'چالا (۱ امتیاز)', max: 30),
        ScoreField('yonbosh', 'Yonbosh (2 points)', 'یونبوش (۲ امتیاز)', max: 30),
        ScoreField('halal', 'Halal (clean win)', 'حلال (پیروزی کامل)', max: 1),
        ScoreField('dakki', 'Dakki (2 = loss)', 'داکی (۲ = باخت)', max: 2),
        ScoreField('girom', 'Girom (1 = loss)', 'گیروم (۱ = باخت)', max: 1),
        ScoreField('tanbeh', 'Penalties (tanbeh, 3 = loss)', 'اخطار (تنبیه، ۳ = باخت)', max: 3),
        ScoreField('winner', 'Winner (only when points and penalties are level)',
            'برنده (فقط وقتی امتیاز و اخطار برابر است)',
            perSide: false,
            options: ['—', '{A}', '{B}'],
            optionsFa: ['—', '{A}', '{B}']),
      ];

  /// The values after the automatic rules were applied to what was entered.
  /// Public so the dialog and the unit tests can show / check them.
  static Map<String, int> effective(Map<String, int> v) {
    final out = <String, int>{
      for (final side in ['A', 'B']) ...{
        'chala$side': _g(v, 'chala$side'),
        'yonbosh$side': _g(v, 'yonbosh$side'),
        'halal$side': _g(v, 'halal$side'),
        'dakki$side': _g(v, 'dakki$side'),
        'girom$side': _g(v, 'girom$side'),
      },
    };
    void tanbehOf(String side, String other) {
      final t = _g(v, 'tanbeh$side').clamp(0, 3);
      if (t >= 1) out['chala$other'] = out['chala$other']! + 1;
      if (t >= 2) {
        out['yonbosh$other'] = out['yonbosh$other']! + 1;
        out['dakki$side'] = out['dakki$side']! + 1;
      }
      if (t >= 3) {
        out['girom$side'] = out['girom$side']! + 1;
        out['halal$other'] = out['halal$other']! + 1;
      }
    }

    tanbehOf('A', 'B');
    tanbehOf('B', 'A');
    return out;
  }

  /// true when [side] has lost automatically (girom, two dakki, three tanbeh).
  static bool _lost(Map<String, int> e, Map<String, int> v, String side) =>
      e['girom$side']! >= 1 || e['dakki$side']! >= 2 || _g(v, 'tanbeh$side') >= 3;

  /// true when [side] has won automatically (halal, or two yonbosh).
  static bool _cleanWin(Map<String, int> e, String side) =>
      e['halal$side']! >= 1 || e['yonbosh$side']! >= 2;

  @override
  ScoreOutcome evaluate(Map<String, int> v) {
    final e = effective(v);
    final lostA = _lost(e, v, 'A'), lostB = _lost(e, v, 'B');
    if (lostA && lostB) {
      return const ScoreOutcome.invalid('Both wrestlers cannot lose by girom, dakki or tanbeh.');
    }
    final winA = _cleanWin(e, 'A') || lostB;
    final winB = _cleanWin(e, 'B') || lostA;
    if (winA && winB) {
      return const ScoreOutcome.invalid('Only one side can win by halal / two yonbosh.');
    }
    final pa = e['chalaA']! + 2 * e['yonboshA']!;
    final pb = e['chalaB']! + 2 * e['yonboshB']!;
    String? winner;
    var how = 'points';
    if (winA || winB) {
      winner = winA ? 'A' : 'B';
      if (lostA || lostB) {
        how = (e['giromA']! + e['giromB']! > 0)
            ? 'girom (halal to the opponent)'
            : (e['dakkiA']! >= 2 || e['dakkiB']! >= 2)
                ? 'two dakki (halal to the opponent)'
                : 'three tanbeh';
      } else if (e['halalA']! + e['halalB']! > 0) {
        how = 'halal';
      } else {
        how = 'two yonbosh (halal)';
      }
    } else if (pa != pb) {
      winner = pa > pb ? 'A' : 'B';
    } else {
      final pA = _g(v, 'tanbehA'), pB = _g(v, 'tanbehB');
      if (pA != pB) {
        winner = pA < pB ? 'A' : 'B';
        how = 'fewer penalties';
      } else {
        final chosen = _g(v, 'winner');
        if (chosen == 0) {
          return const ScoreOutcome.invalid(
              'Points and penalties are level: choose the winner (judges\' decision).');
        }
        winner = chosen == 1 ? 'A' : 'B';
        how = 'judges\' decision';
      }
    }
    final decisive = winA || winB;
    final a = decisive && winner == 'A' ? halalValue : pa;
    final b = decisive && winner == 'B' ? halalValue : pb;
    return ScoreOutcome.ok(
      scoreA: a,
      scoreB: b,
      pointsA: winner == 'A' ? 3 : 0,
      pointsB: winner == 'B' ? 3 : 0,
      summary: '$winner wins by $how ($pa-$pb)',
    );
  }
}
