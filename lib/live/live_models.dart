/// A fixture or result of a real-world competition.
class LiveMatch {
  final int id;
  final DateTime date; // local time
  final String status; // SCHEDULED, TIMED, IN_PLAY, PAUSED, FINISHED, ...
  final String home;
  final String away;
  final int? homeGoals;
  final int? awayGoals;
  final int? matchday;
  final String? stage;
  final String? group;

  const LiveMatch({
    required this.id,
    required this.date,
    required this.status,
    required this.home,
    required this.away,
    this.homeGoals,
    this.awayGoals,
    this.matchday,
    this.stage,
    this.group,
  });

  bool get isFinished => status == 'FINISHED' || status == 'AWARDED';
  bool get isLive => status == 'IN_PLAY' || status == 'PAUSED' || status == 'LIVE';
  bool get isUpcoming => status == 'SCHEDULED' || status == 'TIMED';
  bool get hasScore => homeGoals != null && awayGoals != null;

  /// Parses one entry of football-data.org's `matches` array. Returns null
  /// if the entry is unusable (never throws).
  static LiveMatch? fromJson(dynamic j) {
    try {
      if (j is! Map) return null;
      final home = (j['homeTeam'] as Map?)?['name'] ?? (j['homeTeam'] as Map?)?['shortName'];
      final away = (j['awayTeam'] as Map?)?['name'] ?? (j['awayTeam'] as Map?)?['shortName'];
      if (home == null || away == null) return null; // e.g. TBD knockout slot
      final full = (j['score'] as Map?)?['fullTime'] as Map?;
      final dt = DateTime.tryParse('${j['utcDate']}');
      if (dt == null) return null;
      return LiveMatch(
        id: (j['id'] as num?)?.toInt() ?? 0,
        date: dt.toLocal(),
        status: '${j['status'] ?? ''}',
        home: '$home',
        away: '$away',
        homeGoals: (full?['home'] as num?)?.toInt(),
        awayGoals: (full?['away'] as num?)?.toInt(),
        matchday: (j['matchday'] as num?)?.toInt(),
        stage: j['stage'] as String?,
        group: j['group'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Parsing of TheSportsDB events (used for cricket, basketball, volleyball).
class SportsDbParser {
  SportsDbParser._();

  static int? _score(dynamic v) {
    if (v == null) return null;
    final m = RegExp(r'^\s*(\d+)').firstMatch('$v'); // "180/5" -> 180
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static const _notPlayed = {'NS', 'NOT STARTED', 'TBD', 'POSTPONED', 'PST', 'CANCELLED', 'CANC', 'ABANDONED', 'SUSPENDED'};

  /// Returns null when the event is unusable or was not played (never throws).
  static LiveMatch? parse(dynamic j) {
    try {
      if (j is! Map) return null;
      final home = j['strHomeTeam'];
      final away = j['strAwayTeam'];
      if (home == null || away == null || '$home'.trim().isEmpty || '$away'.trim().isEmpty) {
        return null;
      }
      var ts = '${j['strTimestamp'] ?? ''}'.trim();
      if (ts.isEmpty) {
        ts = '${j['dateEvent'] ?? ''}T${j['strTime'] ?? '00:00:00'}';
      }
      if (!ts.endsWith('Z') && !RegExp(r'[+-]\d\d:?\d\d$').hasMatch(ts)) ts = '${ts}Z'; // API gives UTC
      final dt = DateTime.tryParse(ts);
      if (dt == null) return null;
      final hs = _score(j['intHomeScore']);
      final awayS = _score(j['intAwayScore']);
      final raw = '${j['strStatus'] ?? ''}'.trim().toUpperCase();
      final local = dt.toLocal();
      String status;
      if (_notPlayed.contains(raw)) {
        status = (raw == 'NS' || raw == 'NOT STARTED' || raw == 'TBD') && local.isAfter(DateTime.now())
            ? 'SCHEDULED'
            : 'SKIPPED';
      } else if (hs != null && awayS != null && local.isBefore(DateTime.now())) {
        status = 'FINISHED';
      } else if (local.isAfter(DateTime.now())) {
        status = 'SCHEDULED';
      } else {
        status = 'SKIPPED';
      }
      return LiveMatch(
        id: int.tryParse('${j['idEvent']}') ?? 0,
        date: local,
        status: status,
        home: '$home'.trim(),
        away: '$away'.trim(),
        homeGoals: status == 'FINISHED' ? hs : null,
        awayGoals: status == 'FINISHED' ? awayS : null,
        matchday: int.tryParse('${j['intRound']}'),
        stage: stageFromRound(int.tryParse('${j['intRound']}')),
      );
    } catch (_) {
      return null;
    }
  }

  /// TheSportsDB marks play-off rounds with special round numbers (125 = quarter-final,
  /// 150 = semi-final, 160 = play-off, 200 = final). This mapping is taken from the
  /// API's conventions as recalled, NOT verified against a live feed, so a round
  /// number that is not in the list is simply treated as a regular-season round.
  static String? stageFromRound(int? r) {
    switch (r) {
      case 125:
        return 'QUARTER_FINALS';
      case 150:
        return 'SEMI_FINALS';
      case 160:
        return 'PLAYOFFS';
      case 200:
        return 'FINAL';
    }
    return null;
  }
}

class LiveStandingRow {
  final int position;
  final String team;
  final int played, won, draw, lost, points, goalsFor, goalsAgainst;
  const LiveStandingRow({
    required this.position,
    required this.team,
    required this.played,
    required this.won,
    required this.draw,
    required this.lost,
    required this.points,
    required this.goalsFor,
    required this.goalsAgainst,
  });
  int get goalDiff => goalsFor - goalsAgainst;

  static LiveStandingRow? fromJson(dynamic j) {
    try {
      if (j is! Map) return null;
      final name = (j['team'] as Map?)?['name'];
      if (name == null) return null;
      int n(String k) => (j[k] as num?)?.toInt() ?? 0;
      return LiveStandingRow(
        position: n('position'),
        team: '$name',
        played: n('playedGames'),
        won: n('won'),
        draw: n('draw'),
        lost: n('lost'),
        points: n('points'),
        goalsFor: n('goalsFor'),
        goalsAgainst: n('goalsAgainst'),
      );
    } catch (_) {
      return null;
    }
  }
}

/// One table (a league has one; a tournament with groups has several).
class LiveStandingGroup {
  final String? title;
  final List<LiveStandingRow> rows;
  const LiveStandingGroup(this.title, this.rows);
}

/// How a competition is shown: a league (one table, played to the end) or a cup
/// (group / league phase followed by knockout rounds, like the Champions League).
enum LiveFormat { league, cup }

/// Knockout rounds in the order they are played (football-data.org stage names).
const kKnockoutStages = <String>[
  'PLAYOFFS', 'LAST_64', 'LAST_32', 'LAST_16', 'QUARTER_FINALS', 'SEMI_FINALS', 'THIRD_PLACE', 'FINAL',
];

extension LiveMatchStage on LiveMatch {
  /// true for matches of a knockout round (not group / league phase / regular season)
  bool get isKnockout => stage != null && kKnockoutStages.contains(stage);
}

class LiveCompetition {
  final String code;
  final String name;
  final String region;

  /// 'fd' = football-data.org (needs the user's free token),
  /// 'tsdb' = TheSportsDB (free public key, no sign-up).
  final String provider;

  /// Id of the AI sport profile used for predictions (see SportProfiles).
  final String sport;

  /// Does "home" mean a real home advantage? (false for cricket, where the
  /// home/away order in the data is only a listing order.)
  final bool homeField;

  /// League (table only) or cup (groups/league phase + knockout rounds).
  final LiveFormat format;

  const LiveCompetition(this.code, this.name, this.region,
      {this.provider = 'fd',
      this.sport = 'football',
      this.homeField = true,
      this.format = LiveFormat.league});

  bool get isCup => format == LiveFormat.cup;

  bool get isFootballData => provider == 'fd';
}

/// Competitions available on football-data.org's free plan.
const kLiveCompetitions = <LiveCompetition>[
  LiveCompetition('WC', 'FIFA World Cup', 'world', format: LiveFormat.cup),
  LiveCompetition('CL', 'UEFA Champions League', 'europe', format: LiveFormat.cup),
  LiveCompetition('EC', 'UEFA European Championship', 'europe', format: LiveFormat.cup),
  LiveCompetition('PL', 'Premier League (England)', 'europe'),
  LiveCompetition('PD', 'La Liga (Spain)', 'europe'),
  LiveCompetition('BL1', 'Bundesliga (Germany)', 'europe'),
  LiveCompetition('SA', 'Serie A (Italy)', 'europe'),
  LiveCompetition('FL1', 'Ligue 1 (France)', 'europe'),
  LiveCompetition('DED', 'Eredivisie (Netherlands)', 'europe'),
  LiveCompetition('PPL', 'Primeira Liga (Portugal)', 'europe'),
  LiveCompetition('ELC', 'Championship (England)', 'europe'),
  LiveCompetition('BSA', 'Brasileirão (Brazil)', 'america'),
];

/// Other sports, from TheSportsDB (free key, no registration). Only sports
/// that have a real free league feed are listed; judo, wrestling, taekwondo,
/// tennis and e-sports have none, so they learn only from the user's own
/// tournaments.
const kOtherSportCompetitions = <LiveCompetition>[
  LiveCompetition('4460', 'Indian Premier League (Cricket)', 'cricket',
      provider: 'tsdb', sport: 'cricket', homeField: false),
  LiveCompetition('4461', 'Big Bash League (Cricket)', 'cricket',
      provider: 'tsdb', sport: 'cricket', homeField: false),
  LiveCompetition('5534', 'Shpageeza Cricket League (Afghanistan)', 'cricket',
      provider: 'tsdb', sport: 'cricket', homeField: false),
  LiveCompetition('5176', 'Caribbean Premier League (Cricket)', 'cricket',
      provider: 'tsdb', sport: 'cricket', homeField: false),
  LiveCompetition('5529', 'Bangladesh Premier League (Cricket)', 'cricket',
      provider: 'tsdb', sport: 'cricket', homeField: false),
  LiveCompetition('4387', 'NBA (Basketball)', 'basketball',
      provider: 'tsdb', sport: 'basketball'),
  LiveCompetition('4434', 'NBL Australia (Basketball)', 'basketball',
      provider: 'tsdb', sport: 'basketball'),
  LiveCompetition('5613', 'European Volleyball Championship (Men)', 'volleyball',
      provider: 'tsdb', sport: 'volleyball'),
  LiveCompetition('5848', 'European Volleyball League (Men)', 'volleyball',
      provider: 'tsdb', sport: 'volleyball'),
  LiveCompetition('5614', 'CEV Challenge Cup (Volleyball)', 'volleyball',
      provider: 'tsdb', sport: 'volleyball'),
];
