import 'dart:math';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../data/database_helper.dart';
import '../models/tournament.dart';
import '../models/team.dart';
import '../models/match_model.dart';
import '../models/group_model.dart';
import '../utils/name_check.dart';
import '../utils/team_storage.dart';
import '../utils/password_hasher.dart';
import '../ml/elo_rating_service.dart';
import '../domain/race.dart';
import '../domain/standings_calculator.dart';
import '../domain/fixture_generator.dart';
import '../domain/sport_rules.dart';
import '../domain/sport_scoring.dart';

class StandingRow {
  final Team team;
  int played = 0, win = 0, draw = 0, loss = 0, gf = 0, ga = 0;
  int get gd => gf - ga;
  /// Set by the standings calculator so the table can use a sport's own
  /// points rule; falls back to the classic 3-1-0 when absent.
  int? pointsOverride;
  int get pts => pointsOverride ?? (win * 3 + draw);
  StandingRow(this.team);
}

/// A full point-in-time copy of everything a result-recording action can
/// change, used to power multi-level undo.
class _TournamentSnapshot {
  final List<MatchModel> matches;
  final List<GroupModel> groups;
  final String? champion;
  final String? runnerUp;
  final List<String> thirdPlaceTeams;
  /// Team list at that moment (teams can be added after creation).
  final List<Team> teams;
  /// True for the snapshot taken right before the knockout bracket was
  /// generated from the group stage.
  final bool promotion;
  _TournamentSnapshot({
    this.promotion = false,
    required this.matches,
    required this.groups,
    required this.champion,
    required this.runnerUp,
    required this.thirdPlaceTeams,
    required this.teams,
  });
}

class TournamentProvider extends ChangeNotifier {
  final _uuid = const Uuid();
  final _db = DatabaseHelper.instance;

  List<Tournament> _tournaments = [];
  bool _loaded = false;
  bool get isLoaded => _loaded;

  // ---- Multi-level undo support ------------------------------------
  // Every recorded result pushes a snapshot of "how things were right
  // before" onto a per-tournament stack. Pressing Undo pops one snapshot
  // at a time, so pressing it repeatedly walks all the way back to
  // before the very first result was ever entered.
  final Map<String, List<_TournamentSnapshot>> _undoStacks = {};

  bool canUndo(String tournamentId) =>
      (_undoStacks[tournamentId]?.isNotEmpty) ?? false;

  void _snapshotBeforeEdit(Tournament t, {bool promotion = false}) {
    final stack = _undoStacks.putIfAbsent(t.id, () => []);
    stack.add(_TournamentSnapshot(
      promotion: promotion,
      matches: t.matches.map((m) => m.clone()).toList(),
      groups: t.groups
          .map((g) => GroupModel(
                id: g.id,
                name: g.name,
                teamIds: List.of(g.teamIds),
                matches: g.matches.map((m) => m.clone()).toList(),
              ))
          .toList(),
      champion: t.champion,
      runnerUp: t.runnerUp,
      thirdPlaceTeams: List.of(t.thirdPlaceTeams),
      teams: List.of(t.teams),
    ));
  }

  /// Reverts the tournament to the state it was in right before the most
  /// recent result was recorded (like Ctrl+Z). Calling it again keeps
  /// stepping further back, all the way to before the first result was
  /// ever entered.
  void undoLastAction(String tournamentId) {
    final stack = _undoStacks[tournamentId];
    if (stack == null || stack.isEmpty) return;
    final snap = stack.removeLast();
    final t = byId(tournamentId);
    final bracketIdsBefore = t.matches.map((m) => m.id).toSet();

    final teamIdsBefore = t.teams.map((e) => e.id).toSet();
    t.matches = snap.matches;
    t.groups = snap.groups;
    t.champion = snap.champion;
    t.runnerUp = snap.runnerUp;
    t.thirdPlaceTeams = snap.thirdPlaceTeams;
    t.teams = snap.teams;

    notifyListeners();
    final teamIdsAfter = t.teams.map((e) => e.id).toSet();
    final teamsChanged = teamIdsBefore.length != teamIdsAfter.length ||
        !teamIdsBefore.containsAll(teamIdsAfter);
    final bracketIdsAfter = t.matches.map((m) => m.id).toSet();
    final bracketChanged = bracketIdsBefore.length != bracketIdsAfter.length ||
        !bracketIdsBefore.containsAll(bracketIdsAfter);
    if (teamsChanged) {
      // A team (and its fixtures) was added or removed by this step.
      _resyncAllRows(t);
    } else if (bracketChanged) {
      // The bracket was created or removed by this undo step.
      _resyncBracketRows(t).then((_) => _persistFullMatchState(t));
    } else {
      _persistFullMatchState(t);
    }
    EloRatingService.instance.syncTournament(t);
  }

  /// Replaces every stored top-level (bracket) match row of [t] with the
  /// current in-memory bracket.
  Future<void> _resyncBracketRows(Tournament t) async {
    try {
      final db = await _db.database;
      final batch = db.batch();
      batch.delete('matches',
          where: 'tournamentId = ? AND groupId IS NULL', whereArgs: [t.id]);
      for (final m in t.matches) {
        batch.insert('matches', _matchToRow(t.id, null, m),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('Bracket resync failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // ADD TEAMS AFTER CREATION (undoable)
  // ---------------------------------------------------------------------

  /// True once any real match of [t] has been played (group, league or
  /// bracket). Teams can only be added while this is false.
  bool hasStarted(Tournament t) {
    bool touched(MatchModel m) =>
        !m.isBye && (m.isPlayed || m.scoreA != null || m.scoreA2 != null);
    return t.matches.any(touched) || t.groups.any((g) => g.matches.any(touched));
  }

  /// Whether the "add teams" action is offered: only before play begins.
  /// After Undo has taken the tournament back to its start, it is offered
  /// again.
  bool canAddTeams(Tournament t) => t.type != TournamentType.race && !hasStarted(t);

  /// Adds [names] as new teams to a tournament in which nothing has been
  /// played yet. Empty and duplicate names are skipped. The fixtures /
  /// groups / bracket are redrawn with the same rules used at creation.
  /// Can be reverted with Undo. Returns how many teams were added.
  int addTeams(Tournament t, List<String> names) {
    if (!canAddTeams(t)) return 0;
    final existing = t.teams.map((e) => NameCheck.key(e.name)).toSet();
    final added = <Team>[];
    for (final raw in names) {
      final n = raw.trim();
      if (n.isEmpty || !existing.add(NameCheck.key(n))) continue;
      added.add(Team(id: _uuid.v4(), name: n));
    }
    if (added.isEmpty) return 0;

    _snapshotBeforeEdit(t);
    t.teams = [...t.teams, ...added];

    final seeded = List<Team>.of(t.teams);
    if (t.seedingMode == SeedingMode.random) seeded.shuffle(Random());
    if (t.type == TournamentType.league) {
      t.matches = _generateRoundRobin(seeded, doubleRound: t.twoLegged);
    } else if (t.hasGroupStage) {
      t.groups = _generateGroups(seeded,
          doubleRound: t.twoLegged,
          potShuffle: t.seedingMode == SeedingMode.balanced);
      t.matches = [];
    } else {
      t.matches = _generateKnockoutBracket(seeded,
          manualOrder: t.seedingMode == SeedingMode.manual);
    }

    notifyListeners();
    _resyncAllRows(t);
    EloRatingService.instance.syncTournament(t);
    return added.length;
  }

  /// Rewrites every stored team, group and match row of [t] from memory.
  Future<void> _resyncAllRows(Tournament t) async {
    try {
      final db = await _db.database;
      final batch = db.batch();
      batch.delete('matches', where: 'tournamentId = ?', whereArgs: [t.id]);
      batch.delete('groups_table', where: 'tournamentId = ?', whereArgs: [t.id]);
      batch.delete('teams', where: 'tournamentId = ?', whereArgs: [t.id]);
      for (final team in t.teams) {
        batch.insert('teams', {
          'id': team.id,
          'tournamentId': t.id,
          'name': team.name,
          'imagePath': team.imagePath,
        });
      }
      for (final m in t.matches) {
        batch.insert('matches', _matchToRow(t.id, null, m));
      }
      for (final g in t.groups) {
        batch.insert('groups_table', {
          'id': g.id,
          'tournamentId': t.id,
          'name': g.name,
          'teamIds': g.teamIds.join(','),
        });
        for (final m in g.matches) {
          batch.insert('matches', _matchToRow(t.id, g.id, m));
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('Full resync failed: $e');
    }
  }

  /// Whether the knockout bracket of a group-stage tournament already has
  /// at least one decided tie.
  bool bracketHasResults(Tournament t) =>
      t.matches.any((m) => m.isPlayed && !m.isBye);

  /// Discards the knockout bracket and goes back to the group stage so
  /// wrongly entered group results can be corrected (via Undo) and the
  /// bracket regenerated with "Next". Group results are untouched.
  void returnToGroupStage(Tournament t) {
    if (!t.hasGroupStage || t.matches.isEmpty) return;
    final stack = _undoStacks[t.id];
    if (stack != null) {
      // Drop undo steps that belong to the discarded bracket, and the
      // "bracket created" step itself (the group state is already current).
      while (stack.isNotEmpty && stack.last.matches.isNotEmpty) {
        stack.removeLast();
      }
      if (stack.isNotEmpty && stack.last.promotion) stack.removeLast();
    }
    t.matches = [];
    t.champion = null;
    t.runnerUp = null;
    t.thirdPlaceTeams = [];
    notifyListeners();
    _resyncBracketRows(t).then((_) => _updateTournamentResultFields(t));
    EloRatingService.instance.syncTournament(t);
  }


  // ---------------------------------------------------------------------
  // RACE (single-start events: dash, athletics, swimming, cycling)
  // ---------------------------------------------------------------------

  List<MatchModel> _generateRaceEntries(List<Team> entrants) => [
        for (var i = 0; i < entrants.length; i++)
          MatchModel(id: _uuid.v4(), teamAId: entrants[i].id, round: 0, order: i),
      ];

  /// The stored result of one entrant (null = nothing entered yet).
  RaceResult? raceResultOf(MatchModel m) => RaceResult.fromJson(m.detail);

  /// Sets (or clears) the date and time of a match. Shown in the Shamsi, Hijri and Gregorian calendars.
  Future<void> setMatchSchedule(Tournament t, MatchModel m, DateTime? when) async {
    m.scheduledAt = when;
    notifyListeners();
    try {
      await _persistFullMatchState(t);
    } catch (e) {
      debugPrint('Saving match date failed: $e');
    }
  }

  /// Saves (or clears, with null) one entrant's result, re-ranks everybody and
  /// stores the final podium once every entrant has a result.
  Future<void> setRaceResult(Tournament t, MatchModel entry, RaceResult? result) async {
    entry.detail = result?.toJson();
    final results = {for (final m in t.matches) m.teamAId!: raceResultOf(m)};
    final ranks = Race.rank(results);
    for (final m in t.matches) {
      final r = results[m.teamAId!];
      m.isPlayed = r != null;
      m.scoreA = ranks[m.teamAId!]; // the place (null for DNF/DNS/DSQ or no result)
      m.winnerId = ranks[m.teamAId!] == 1 ? m.teamAId : null;
    }
    final allDone = t.matches.isNotEmpty && t.matches.every((m) => m.isPlayed);
    String? atPlace(int place) {
      for (final m in t.matches) {
        if (ranks[m.teamAId!] == place) return m.teamAId;
      }
      return null;
    }

    t.champion = allDone ? atPlace(1) : null;
    t.runnerUp = allDone ? atPlace(2) : null;
    final third = allDone ? atPlace(3) : null;
    t.thirdPlaceTeams = third == null ? [] : [third];
    notifyListeners();
    try {
      await _persistFullMatchState(t);
    } catch (e) {
      debugPrint('Saving race result failed: $e');
    }
    EloRatingService.instance.syncTournament(t); // the AI learns from the finishing order
  }

  Future<void> _persistFullMatchState(Tournament t) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final m in t.matches) {
      batch.update('matches', _matchToRow(t.id, null, m), where: 'id = ?', whereArgs: [m.id]);
    }
    for (final g in t.groups) {
      for (final m in g.matches) {
        batch.update('matches', _matchToRow(t.id, g.id, m), where: 'id = ?', whereArgs: [m.id]);
      }
    }
    batch.update(
      'tournaments',
      {
        'champion': t.champion,
        'runnerUp': t.runnerUp,
        'thirdPlace': t.thirdPlaceTeams.isEmpty ? null : t.thirdPlaceTeams.join(','),
      },
      where: 'id = ?',
      whereArgs: [t.id],
    );
    await batch.commit(noResult: true);
  }

  List<Tournament> get activeTournaments =>
      _tournaments.where((t) => !t.isDeleted).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<Tournament> get deletedTournaments =>
      _tournaments.where((t) => t.isDeleted).toList()
        ..sort((a, b) => (b.deletedAt ?? b.createdAt)
            .compareTo(a.deletedAt ?? a.createdAt));

  TournamentProvider() {
    _loadAll();
  }

  // ---------------------------------------------------------------------
  // LOAD (relational tables -> in-memory object graph used by the UI)
  // ---------------------------------------------------------------------

  /// Drops all in-memory state and reloads from the database. Used after a
  /// restore. Undo history is cleared because it refers to the old data.
  Future<void> reloadFromDatabase() async {
    _undoStacks.clear();
    _loaded = false;
    notifyListeners();
    await _loadAll();
  }

  Future<void> _loadAll() async {
    final db = await _db.database;
    final tRows = await db.query('tournaments', orderBy: 'createdAt DESC');

    final loaded = <Tournament>[];
    for (final row in tRows) {
      final id = row['id'] as String;

      final teamRows = await db.query('teams', where: 'tournamentId = ?', whereArgs: [id]);
      final teams = teamRows
          .map((r) => Team(id: r['id'] as String, name: r['name'] as String, imagePath: r['imagePath'] as String?))
          .toList();

      final groupRows = await db.query('groups_table', where: 'tournamentId = ?', whereArgs: [id]);
      final groups = <GroupModel>[];
      for (final g in groupRows) {
        final gId = g['id'] as String;
        final gMatchRows = await db.query('matches',
            where: 'groupId = ?', whereArgs: [gId], orderBy: 'round ASC, matchOrder ASC');
        groups.add(GroupModel(
          id: gId,
          name: g['name'] as String,
          teamIds: (g['teamIds'] as String).split(',').where((s) => s.isNotEmpty).toList(),
          matches: gMatchRows.map(_matchFromRow).toList(),
        ));
      }

      final topMatchRows = await db.query('matches',
          where: 'tournamentId = ? AND groupId IS NULL', whereArgs: [id], orderBy: 'round ASC, matchOrder ASC');

      loaded.add(Tournament(
        id: id,
        name: row['name'] as String,
        type: TournamentType.values.firstWhere((e) => e.name == row['type']),
        hasGroupStage: (row['hasGroupStage'] as int) == 1,
        seedingMode: SeedingMode.values.firstWhere((e) => e.name == row['seedingMode']),
        sport: row['sport'] as String? ?? 'other',
        password: row['password'] as String?,
        twoLegged: (row['twoLegged'] as int? ?? 0) == 1,
        customPoints: _scoringFromDb(row['scoring'] as String?),
        teams: teams,
        matches: topMatchRows.map(_matchFromRow).toList(),
        groups: groups,
        createdAt: DateTime.tryParse(row['createdAt'] as String) ?? DateTime.now(),
        isDeleted: (row['isDeleted'] as int) == 1,
        deletedAt: row['deletedAt'] != null ? DateTime.tryParse(row['deletedAt'] as String) : null,
        champion: row['champion'] as String?,
        runnerUp: row['runnerUp'] as String?,
        thirdPlaceTeams: ((row['thirdPlace'] as String?) ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
      ));
    }

    _tournaments = loaded;
    EloRatingService.instance.ingestAll(loaded.where((x) => !x.isDeleted));
    _loaded = true;
    notifyListeners();

    // Plain-text passwords from older versions are hashed once, in place.
    await _migratePlaintextPasswords();

    // Recycle bin auto-purge: anything soft-deleted more than 30 days ago
    // is now permanently removed — same behavior as Samsung Gallery's
    // trash. Runs once per app launch, after the initial load.
    await _purgeExpiredTrash();
  }

  static const _kTrashRetention = Duration(days: 30);

  Future<void> _purgeExpiredTrash() async {
    final now = DateTime.now();
    final expired = _tournaments
        .where((t) => t.isDeleted && t.deletedAt != null && now.difference(t.deletedAt!) >= _kTrashRetention)
        .map((t) => t.id)
        .toList();
    for (final id in expired) {
      deleteForever(id);
    }
  }

  /// Days remaining before [tournament] is automatically purged from the
  /// recycle bin (never negative — clamped to 0 so the UI can safely
  /// show "deletes today").
  int daysUntilPermanentDelete(Tournament tournament) {
    if (!tournament.isDeleted || tournament.deletedAt == null) return 0;
    final elapsed = DateTime.now().difference(tournament.deletedAt!);
    final remaining = _kTrashRetention - elapsed;
    if (remaining.isNegative) return 0;
    return remaining.inHours ~/ 24 + (remaining.inHours % 24 > 0 ? 1 : 0);
  }

  MatchModel _matchFromRow(Map<String, Object?> r) => MatchModel(
        id: r['id'] as String,
        teamAId: r['teamAId'] as String?,
        teamBId: r['teamBId'] as String?,
        scoreA: r['scoreA'] as int?,
        scoreB: r['scoreB'] as int?,
        scoreA2: r['scoreA2'] as int?,
        scoreB2: r['scoreB2'] as int?,
        penA: r['penA'] as int?,
        penB: r['penB'] as int?,
        isPlayed: (r['isPlayed'] as int) == 1,
        round: r['round'] as int,
        order: r['matchOrder'] as int,
        winnerId: r['winnerId'] as String?,
        isBye: (r['isBye'] as int) == 1,
        isThirdPlaceMatch: (r['isThirdPlaceMatch'] as int) == 1,
        scheduledAt: r['scheduledAt'] != null ? DateTime.tryParse(r['scheduledAt'] as String) : null,
        detail: r['detail'] as String?,
      );

  Map<String, Object?> _matchToRow(String tournamentId, String? groupId, MatchModel m) => {
        'id': m.id,
        'tournamentId': tournamentId,
        'groupId': groupId,
        'teamAId': m.teamAId,
        'teamBId': m.teamBId,
        'scoreA': m.scoreA,
        'scoreB': m.scoreB,
        'scoreA2': m.scoreA2,
        'scoreB2': m.scoreB2,
        'penA': m.penA,
        'penB': m.penB,
        'isPlayed': m.isPlayed ? 1 : 0,
        'round': m.round,
        'matchOrder': m.order,
        'winnerId': m.winnerId,
        'isBye': m.isBye ? 1 : 0,
        'isThirdPlaceMatch': m.isThirdPlaceMatch ? 1 : 0,
        'scheduledAt': m.scheduledAt?.toIso8601String(),
        'detail': m.detail,
      };

  // ---- scoring rules (points per result) ---------------------------------

  static String? _scoringToDb(PointsRule? r) =>
      r == null ? null : '${r.win},${r.draw},${r.loss}';

  static PointsRule? _scoringFromDb(String? s) {
    if (s == null || s.isEmpty) return null;
    final p = s.split(',');
    if (p.length != 3) return null;
    final v = p.map(int.tryParse).toList();
    if (v.any((e) => e == null)) return null;
    return PointsRule(win: v[0]!, draw: v[1]!, loss: v[2]!);
  }

  /// The points rule currently used for [t]'s tables.
  PointsRule effectivePoints(Tournament t) => t.customPoints ?? SportRules.of(t.sport).points;

  /// Sets (or, with null, resets to the sport default) the points rule of a
  /// tournament. Tables update at once; the change is written to the database.
  Future<void> setScoringRules(Tournament t, PointsRule? rule) async {
    t.customPoints = rule;
    notifyListeners();
    try {
      final db = await _db.database;
      await db.update('tournaments', {'scoring': _scoringToDb(rule)},
          where: 'id = ?', whereArgs: [t.id]);
    } catch (e) {
      debugPrint('Saving scoring rules failed: $e');
    }
  }

  /// Adds a tournament received from the server. It never replaces a local
  /// tournament with the same id, and a name that is already used locally is
  /// refused (returns false) so names stay unique.
  Future<bool> importTournament(Tournament t) async {
    if (_tournaments.any((x) => x.id == t.id)) return false;
    final key = NameCheck.key(t.name);
    if (_tournaments.any((x) => !x.isDeleted && NameCheck.key(x.name) == key)) {
      return false;
    }
    t.password = null;
    _tournaments.add(t);
    notifyListeners();
    try {
      await _insertTournament(t);
      await _persistFullMatchState(t);
    } catch (e) {
      debugPrint('Importing tournament failed: $e');
      _tournaments.remove(t);
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Viewer accounts keep a read-only mirror of the server: replaces (or adds) the
  /// local copy of [t] with the server version.
  Future<bool> replaceFromServer(Tournament t) async {
    t.password = null;
    final i = _tournaments.indexWhere((x) => x.id == t.id);
    try {
      if (i >= 0) {
        await _db.deleteTournamentCascade(t.id);
        _tournaments[i] = t;
      } else {
        _tournaments.add(t);
      }
      notifyListeners();
      await _insertTournament(t);
      await _persistFullMatchState(t);
      return true;
    } catch (e) {
      debugPrint('Replacing tournament from server failed: $e');
      return false;
    }
  }

  Tournament byId(String id) => _tournaments.firstWhere((t) => t.id == id);

  /// Checks [attempt] against the tournament's stored password. Hashing runs
  /// on a background isolate. A correct password on a legacy (plain-text) or
  /// weaker-than-current hash is upgraded to the current hash on the spot.
  Future<bool> verifyPassword(String tournamentId, String attempt) async {
    final t = byId(tournamentId);
    final stored = t.password;
    if (stored == null) return true;
    final ok = await PasswordHasher.verify(attempt, stored);
    if (ok && PasswordHasher.needsRehash(stored)) {
      await _storeHashedPassword(t, attempt);
    }
    return ok;
  }

  Future<void> _storeHashedPassword(Tournament t, String plain) async {
    try {
      final hashed = await PasswordHasher.hash(plain);
      final db = await _db.database;
      await db.update('tournaments', {'password': hashed},
          where: 'id = ?', whereArgs: [t.id]);
      t.password = hashed;
    } catch (e) {
      debugPrint('Password upgrade failed: $e');
    }
  }

  /// One-time migration: any tournament that still holds a plain-text
  /// password (created before v34) is hashed in place. The same password
  /// keeps working because verification accepts the new format.
  Future<void> _migratePlaintextPasswords() async {
    for (final t in List<Tournament>.of(_tournaments)) {
      final pw = t.password;
      if (pw != null && !PasswordHasher.isHashed(pw)) {
        await _storeHashedPassword(t, pw);
      }
    }
  }

  List<Tournament> tournamentsBySport(String sportId) =>
      activeTournaments.where((t) => t.sport == sportId).toList();

  Map<String, int> sportCounts() {
    final map = <String, int>{};
    for (final t in activeTournaments) {
      map[t.sport] = (map[t.sport] ?? 0) + 1;
    }
    return map;
  }

  List<Tournament> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return activeTournaments;
    return activeTournaments.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  // ---------------------------------------------------------------------
  // CREATE
  // ---------------------------------------------------------------------

  Tournament createTournament({
    required String name,
    required TournamentType type,
    required bool hasGroupStage,
    required SeedingMode seedingMode,
    required List<Team> teams,
    String sport = 'other',
    String? password,
    bool twoLegged = false,
  }) {
    final t = Tournament(
      id: _uuid.v4(),
      name: name,
      type: type,
      hasGroupStage: type == TournamentType.knockout ? hasGroupStage : false,
      seedingMode: seedingMode,
      teams: teams,
      sport: sport,
      password: (password != null && password.trim().isEmpty) ? null : password,
      twoLegged: twoLegged,
    );

    List<Team> seeded = List.of(teams);
    if (seedingMode == SeedingMode.random) {
      seeded.shuffle(Random());
    }

    if (type == TournamentType.race) {
      // One entry per entrant, in the order typed (start list). No pairings.
      t.matches = _generateRaceEntries(teams);
    } else if (type == TournamentType.league) {
      t.matches = _generateRoundRobin(seeded, doubleRound: twoLegged);
    } else {
      if (hasGroupStage) {
        t.groups = _generateGroups(seeded,
            doubleRound: twoLegged, potShuffle: seedingMode == SeedingMode.balanced);
      } else {
        t.matches = _generateKnockoutBracket(seeded, manualOrder: seedingMode == SeedingMode.manual);
      }
    }

    _tournaments.add(t);
    notifyListeners();

    // Persist in the background via a single batched transaction — safe
    // even for 100-200+ teams and their generated round-robin/bracket
    // matches, since it's one commit instead of thousands of awaits.
    _insertTournament(t);

    return t;
  }

  Future<void> _insertTournament(Tournament t) async {
    final db = await _db.database;
    final batch = db.batch();

    batch.insert('tournaments', {
      'id': t.id,
      'name': t.name,
      'type': t.type.name,
      'hasGroupStage': t.hasGroupStage ? 1 : 0,
      'seedingMode': t.seedingMode.name,
      'sport': t.sport,
      'password': t.password,
      'twoLegged': t.twoLegged ? 1 : 0,
      'scoring': _scoringToDb(t.customPoints),
      'createdAt': t.createdAt.toIso8601String(),
      'isDeleted': 0,
      'deletedAt': null,
      'champion': null,
      'runnerUp': null,
      'thirdPlace': null,
    });

    for (final team in t.teams) {
      batch.insert('teams', {
        'id': team.id,
        'tournamentId': t.id,
        'name': team.name,
        'imagePath': team.imagePath,
      });
    }

    for (final m in t.matches) {
      batch.insert('matches', _matchToRow(t.id, null, m));
    }

    for (final g in t.groups) {
      batch.insert('groups_table', {
        'id': g.id,
        'tournamentId': t.id,
        'name': g.name,
        'teamIds': g.teamIds.join(','),
      });
      for (final m in g.matches) {
        batch.insert('matches', _matchToRow(t.id, g.id, m));
      }
    }

    await batch.commit(noResult: true);
  }

  List<MatchModel> _generateRoundRobin(List<Team> teams, {bool doubleRound = false}) {
    // Fixture maths lives in the pure-Dart FixtureGenerator (unit-tested for
    // odd and even team counts); here we only turn fixtures into models.
    final fixtures = FixtureGenerator.roundRobin(
      teams.map((t) => t.id).toList(),
      doubleRound: doubleRound,
    );
    return [
      for (final f in fixtures)
        MatchModel(
          id: _uuid.v4(),
          teamAId: f.home,
          teamBId: f.away,
          round: f.round,
          order: f.order,
        ),
    ];
  }

  List<GroupModel> _generateGroups(List<Team> teams,
      {bool doubleRound = false, bool potShuffle = false}) {
    int groupCount = (teams.length / 4).ceil();
    if (groupCount < 2 && teams.length >= 4) groupCount = 2;
    if (groupCount < 1) groupCount = 1;
    final buckets = List.generate(groupCount, (i) => <Team>[]);
    final order = List<Team>.of(teams);
    if (potShuffle) {
      // "Pots": the strongest groupCount teams are pot 1, the next ones
      // pot 2, ... Every group receives exactly one team from each pot;
      // inside a pot the group is drawn at random.
      final rnd = Random();
      for (int i = 0; i < order.length; i += groupCount) {
        final end = min(i + groupCount, order.length);
        final pot = order.sublist(i, end)..shuffle(rnd);
        order.replaceRange(i, end, pot);
      }
    }
    for (int i = 0; i < order.length; i++) {
      buckets[i % groupCount].add(order[i]);
    }

    final groupModels = <GroupModel>[];
    for (int gi = 0; gi < buckets.length; gi++) {
      final letter = String.fromCharCode(65 + gi);
      final bucketTeams = buckets[gi];
      final matches = _generateRoundRobin(bucketTeams, doubleRound: doubleRound);
      groupModels.add(GroupModel(
        id: _uuid.v4(),
        name: 'Group $letter',
        teamIds: bucketTeams.map((t) => t.id).toList(),
        matches: matches,
      ));
    }
    return groupModels;
  }

  /// Standard single-elimination seeding order (e.g. for size 8:
  /// [1,8,4,5,2,7,3,6]) so that first-round pairs are always (seed s,
  /// seed size+1-s). Byes are the weakest ("highest") seed numbers, and
  /// with this placement a bye can only ever be paired against a real
  /// team — never against another bye — which is what was producing the
  /// broken "Full time, — vs —" match in earlier versions.
  List<int> _seedOrder(int size) {
    if (size == 1) return [1];
    final prev = _seedOrder(size ~/ 2);
    final result = <int>[];
    for (final s in prev) {
      result.add(s);
      result.add(size + 1 - s);
    }
    return result;
  }

  /// For manual seeding: pairs teams in the exact order the organizer
  /// arranged them (slot 0 vs slot 1, slot 2 vs slot 3, ...) so "who
  /// plays whom" is entirely their choice. Byes are spread out evenly
  /// (never clustered at the end) so two byes can never land in the same
  /// pair — same safety guarantee as the seeded algorithm above, just
  /// with organizer-controlled pairing instead of seed-priority pairing.
  List<String?> _manualSlots(List<Team> teams, int bracketSize) {
    final n = teams.length;
    final byes = bracketSize - n;
    if (byes == 0) return teams.map((t) => t.id).toList();

    final gap = bracketSize ~/ byes; // always >= 2 since byes <= bracketSize/2
    final slots = <String?>[];
    int teamIndex = 0;
    int byesPlaced = 0;
    for (int i = 0; i < bracketSize; i++) {
      final wantsBye = (i + 1) % gap == 0 && byesPlaced < byes;
      if (wantsBye) {
        slots.add(null);
        byesPlaced++;
      } else if (teamIndex < n) {
        slots.add(teams[teamIndex].id);
        teamIndex++;
      } else {
        slots.add(null);
        byesPlaced++;
      }
    }
    return slots;
  }

  List<MatchModel> _generateKnockoutBracket(List<Team> teams,
      {bool manualOrder = false, List<String?>? presetSlots}) {
    final n = teams.length;
    int bracketSize = 1;
    while (bracketSize < n) {
      bracketSize *= 2;
    }
    if (presetSlots != null) bracketSize = presetSlots.length;
    // slots[i] = team occupying bracket position i (null = bye)
    final slots = presetSlots ??
        (manualOrder
            ? _manualSlots(teams, bracketSize)
            : List<String?>.generate(bracketSize, (i) {
                final seed = _seedOrder(bracketSize)[i];
                return seed <= n ? teams[seed - 1].id : null;
              }));

    final totalRounds = (log(bracketSize) / log(2)).round();
    final matches = <MatchModel>[];

    int order = 0;
    final round0 = <MatchModel>[];
    for (int i = 0; i < bracketSize; i += 2) {
      final a = slots[i];
      final b = slots[i + 1];
      final isBye = a == null || b == null;
      final m = MatchModel(
        id: _uuid.v4(),
        teamAId: a,
        teamBId: b,
        round: 0,
        order: order++,
        isBye: isBye,
        isPlayed: isBye,
        winnerId: isBye ? (a ?? b) : null,
      );
      round0.add(m);
      matches.add(m);
    }

    var prevRound = round0;
    for (int r = 1; r < totalRounds; r++) {
      final thisRound = <MatchModel>[];
      order = 0;
      for (int i = 0; i < prevRound.length; i += 2) {
        final m = MatchModel(
          id: _uuid.v4(),
          teamAId: null,
          teamBId: null,
          round: r,
          order: order++,
        );
        thisRound.add(m);
        matches.add(m);
      }
      prevRound = thisRound;
    }

    // No 3rd-place playoff match: both semifinal losers are automatically
    // awarded joint bronze once their matches are recorded (see
    // recordKnockoutResult). No 4th place exists in this format.
    _propagateByeWinners(matches, totalRounds);

    return matches;
  }

  void _propagateByeWinners(List<MatchModel> matches, int totalRounds) {
    for (int r = 0; r < totalRounds - 1; r++) {
      final current = matches.where((m) => m.round == r && !m.isThirdPlaceMatch).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      final next = matches.where((m) => m.round == r + 1 && !m.isThirdPlaceMatch).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      for (int i = 0; i < current.length; i++) {
        final m = current[i];
        if (m.isPlayed && m.winnerId != null) {
          final target = next[i ~/ 2];
          if (i.isEven) {
            target.teamAId = m.winnerId;
          } else {
            target.teamBId = m.winnerId;
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------
  // RESULTS
  // ---------------------------------------------------------------------

  void recordLeagueResult(Tournament t, MatchModel match, int scoreA, int scoreB) {
    _snapshotBeforeEdit(t);
    match.scoreA = scoreA;
    match.scoreB = scoreB;
    match.isPlayed = true;
    match.winnerId = scoreA == scoreB ? null : (scoreA > scoreB ? match.teamAId : match.teamBId);
    notifyListeners();
    _updateMatchRow(t.id, _groupIdFor(t, match), match);
    EloRatingService.instance.syncTournament(t);
  }

  void recordGroupResult(Tournament t, GroupModel group, MatchModel match, int scoreA, int scoreB) {
    recordLeagueResult(t, match, scoreA, scoreB);
  }

  String? _groupIdFor(Tournament t, MatchModel match) {
    for (final g in t.groups) {
      if (g.matches.any((m) => m.id == match.id)) return g.id;
    }
    return null;
  }

  Future<void> _updateMatchRow(String tournamentId, String? groupId, MatchModel m) async {
    final db = await _db.database;
    await db.update('matches', _matchToRow(tournamentId, groupId, m),
        where: 'id = ?', whereArgs: [m.id]);
  }

  /// Records a knockout result and automatically advances the winner to
  /// the next round's match. There is no 3rd-place playoff: as soon as a
  /// semifinal is recorded, its loser is added to the joint-bronze list
  /// (up to two teams share 3rd place; there is no 4th place).
  ///
  /// Used only for single-match ties (tournament.twoLegged == false).
  void recordKnockoutResult(Tournament t, MatchModel match, int scoreA, int scoreB) {
    _snapshotBeforeEdit(t);
    match.scoreA = scoreA;
    match.scoreB = scoreB;
    final winnerId = scoreA >= scoreB ? match.teamAId : match.teamBId;
    _finalizeKnockoutTie(t, match, winnerId, extraRowsToSave: [match]);
  }

  /// Two-legged ties — leg 1: just records the score, the tie is not
  /// decided yet so nothing advances.
  void recordKnockoutLeg1(Tournament t, MatchModel match, int scoreA, int scoreB) {
    _snapshotBeforeEdit(t);
    match.scoreA = scoreA;
    match.scoreB = scoreB;
    notifyListeners();
    _updateMatchRow(t.id, null, match);
  }

  /// Two-legged ties — leg 2: computes the aggregate. If it's decisive the
  /// tie is finalized immediately; if level, the match is left undecided
  /// (isPlayed stays false) so the UI can prompt for a penalty shootout.
  void recordKnockoutLeg2(Tournament t, MatchModel match, int scoreA2, int scoreB2) {
    _snapshotBeforeEdit(t);
    match.scoreA2 = scoreA2;
    match.scoreB2 = scoreB2;
    final aggA = (match.scoreA ?? 0) + scoreA2;
    final aggB = (match.scoreB ?? 0) + scoreB2;
    if (aggA != aggB) {
      final winnerId = aggA > aggB ? match.teamAId : match.teamBId;
      _finalizeKnockoutTie(t, match, winnerId, extraRowsToSave: [match]);
    } else {
      notifyListeners();
      _updateMatchRow(t.id, null, match);
    }
  }

  /// Two-legged ties — penalty shootout, only reached when the aggregate
  /// score after both legs is tied.
  void recordKnockoutPenalties(Tournament t, MatchModel match, int penA, int penB) {
    _snapshotBeforeEdit(t);
    match.penA = penA;
    match.penB = penB;
    final winnerId = penA >= penB ? match.teamAId : match.teamBId;
    _finalizeKnockoutTie(t, match, winnerId, extraRowsToSave: [match]);
  }

  void _finalizeKnockoutTie(Tournament t, MatchModel match, String? winnerId,
      {required List<MatchModel> extraRowsToSave}) {
    match.isPlayed = true;
    match.winnerId = winnerId;
    final loserId = winnerId == match.teamAId ? match.teamBId : match.teamAId;
    final changed = List<MatchModel>.of(extraRowsToSave);

    final totalRounds =
        t.matches.where((m) => !m.isThirdPlaceMatch).map((m) => m.round).reduce(max) + 1;
    final isFinal = match.round == totalRounds - 1;
    final semiRound = totalRounds - 2;

    if (isFinal) {
      t.champion = winnerId;
      t.runnerUp = loserId;
    } else {
      final nextRound = t.matches.where((m) => m.round == match.round + 1 && !m.isThirdPlaceMatch).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      final targetIndex = match.order ~/ 2;
      if (targetIndex < nextRound.length) {
        final target = nextRound[targetIndex];
        if (match.order.isEven) {
          target.teamAId = winnerId;
        } else {
          target.teamBId = winnerId;
        }
        changed.add(target);
      }

      if (match.round == semiRound && loserId != null && !t.thirdPlaceTeams.contains(loserId)) {
        t.thirdPlaceTeams.add(loserId);
      }
    }

    notifyListeners();
    _batchUpdateMatches(t.id, changed);
    if (isFinal || match.round == semiRound) _updateTournamentResultFields(t);
    EloRatingService.instance.syncTournament(t);
  }

  Future<void> _batchUpdateMatches(String tournamentId, List<MatchModel> ms) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final m in ms) {
      batch.update('matches', _matchToRow(tournamentId, null, m), where: 'id = ?', whereArgs: [m.id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _updateTournamentResultFields(Tournament t) async {
    final db = await _db.database;
    await db.update(
      'tournaments',
      {
        'champion': t.champion,
        'runnerUp': t.runnerUp,
        'thirdPlace': t.thirdPlaceTeams.isEmpty ? null : t.thirdPlaceTeams.join(','),
      },
      where: 'id = ?',
      whereArgs: [t.id],
    );
  }

  bool allGroupMatchesPlayed(Tournament t) {
    for (final g in t.groups) {
      for (final m in g.matches) {
        if (!m.isPlayed) return false;
      }
    }
    return true;
  }

  /// Bracket slots for "group winners vs runners-up" knockouts.
  ///
  /// Rules guaranteed here:
  ///  1. every first-round tie is a group winner against a runner-up of a
  ///     DIFFERENT group (only when byes / an odd group count make this
  ///     impossible does a tie become winner-vs-winner or runner-up-vs-
  ///     runner-up);
  ///  2. the winner and the runner-up of the same group are always in
  ///     opposite halves (Block A / Block B) of the bracket, so they can
  ///     only meet in the final;
  ///  3. when the bracket needs byes, they go to group winners first.
  ///
  /// [groupOrder] lists group indexes from the strongest/first group to the
  /// last; [winners]/[runners] are indexed by group. Returns null if some
  /// group has no runner-up (caller falls back to the plain seeding).
  List<String?>? _groupPairedSlots({
    required List<int> groupOrder,
    required List<String?> winners,
    required List<String?> runners,
    required List<int> runnerRank, // runnerRank[g] = strength rank of group g's runner-up (0 = best)
  }) {
    final g = groupOrder.length;
    if (g < 2) return null;
    for (final i in groupOrder) {
      if (winners[i] == null || runners[i] == null) return null;
    }
    // Block A gets the winners of the groups at even positions plus the
    // runners-up of the groups at odd positions; Block B the opposite.
    final blockW = <List<int>>[[], []]; // group indexes whose winner is in block 0 / 1
    final blockR = <List<int>>[[], []];
    for (var p = 0; p < g; p++) {
      final gi = groupOrder[p];
      blockW[p % 2].add(gi);
      blockR[(p + 1) % 2].add(gi);
    }
    var half = 1;
    while (half < g) {
      half *= 2;
    }
    final matchesPerHalf = half ~/ 2;
    final positions = _seedOrder(matchesPerHalf); // rank -> slot position
    final slots = List<String?>.filled(half * 2, null);

    for (var b = 0; b < 2; b++) {
      final ws = [for (final gi in blockW[b]) winners[gi]!]; // strongest first
      final rsGroups = List<int>.of(blockR[b])
        ..sort((x, y) => runnerRank[x].compareTo(runnerRank[y]));
      final rs = [for (final gi in rsGroups) runners[gi]!];
      final byes = half - g;
      // teams that get a bye: winners first, then best runners-up
      final byeTeams = <String>[];
      final wLeft = List<String>.of(ws);
      final rLeft = List<String>.of(rs);
      for (var i = 0; i < byes; i++) {
        if (wLeft.isNotEmpty) {
          byeTeams.add(wLeft.removeAt(0));
        } else {
          byeTeams.add(rLeft.removeAt(0));
        }
      }
      // real ties: strongest winner meets the weakest runner-up, etc.
      final ties = <List<String>>[];
      while (wLeft.isNotEmpty && rLeft.isNotEmpty) {
        ties.add([wLeft.removeAt(0), rLeft.removeLast()]);
      }
      while (wLeft.length >= 2) {
        ties.add([wLeft.removeAt(0), wLeft.removeLast()]);
      }
      while (rLeft.length >= 2) {
        ties.add([rLeft.removeAt(0), rLeft.removeLast()]);
      }
      // order the ties in the half: bye teams are the strongest ranks
      final ranked = <List<String>>[
        for (final t in byeTeams) [t],
        ...ties,
      ];
      for (var rank = 0; rank < ranked.length && rank < matchesPerHalf; rank++) {
        final pos = positions.indexOf(rank + 1);
        final base = b * half + pos * 2;
        slots[base] = ranked[rank][0];
        slots[base + 1] = ranked[rank].length > 1 ? ranked[rank][1] : null;
      }
    }
    return slots;
  }

  /// Once every group match has been played, take the top 2 of every
  /// group and build the knockout bracket automatically.
  void promoteGroupWinners(Tournament t) {
    if (t.matches.isNotEmpty) return;
    _snapshotBeforeEdit(t, promotion: true);

    int cmp(StandingRow a, StandingRow b) {
      if (b.pts != a.pts) return b.pts - a.pts;
      if (b.gd != a.gd) return b.gd - a.gd;
      return b.gf - a.gf;
    }

    final gc = t.groups.length;
    final winners = List<StandingRow?>.filled(gc, null);
    final runners = List<StandingRow?>.filled(gc, null);
    for (var i = 0; i < gc; i++) {
      final g = t.groups[i];
      final st = computeStandings(t, teamIds: g.teamIds, matches: g.matches);
      if (st.isNotEmpty) winners[i] = st[0];
      if (st.length > 1) runners[i] = st[1];
    }

    // Group order: balanced = strongest winner first; manual = group order
    // (A, B, C ...); random = shuffled.
    var order = List<int>.generate(gc, (i) => i);
    if (t.seedingMode == SeedingMode.balanced) {
      order.sort((x, y) {
        if (winners[x] == null || winners[y] == null) return 0;
        return cmp(winners[x]!, winners[y]!);
      });
    } else if (t.seedingMode == SeedingMode.random) {
      order.shuffle(Random());
    }
    // strength rank of every runner-up (0 = best); in non-balanced modes
    // simply follow the group order so nothing unexpected is reordered.
    final runnerRank = List<int>.filled(gc, 0);
    if (t.seedingMode == SeedingMode.balanced) {
      final rs = [for (final i in order) i]
        ..sort((x, y) {
          if (runners[x] == null || runners[y] == null) return 0;
          return cmp(runners[x]!, runners[y]!);
        });
      for (var r = 0; r < rs.length; r++) {
        runnerRank[rs[r]] = r;
      }
    } else {
      for (var p = 0; p < order.length; p++) {
        runnerRank[order[p]] = p;
      }
    }

    final slots = _groupPairedSlots(
      groupOrder: order,
      winners: [for (final w in winners) w?.team.id],
      runners: [for (final r in runners) r?.team.id],
      runnerRank: runnerRank,
    );

    if (slots != null) {
      final qualifiers = [
        for (final i in order) ...[winners[i]!.team, runners[i]!.team],
      ];
      t.matches = _generateKnockoutBracket(qualifiers, presetSlots: slots);
    } else {
      // Fallback (a single group / a group without a runner-up): plain seeding.
      final qualifiers = <Team>[];
      for (final g in t.groups) {
        final st = computeStandings(t, teamIds: g.teamIds, matches: g.matches);
        qualifiers.addAll(st.take(2).map((s) => s.team));
      }
      t.matches = _generateKnockoutBracket(qualifiers,
          manualOrder: t.seedingMode == SeedingMode.manual);
    }
    notifyListeners();
    _insertBracketMatches(t);
  }

  Future<void> _insertBracketMatches(Tournament t) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final m in t.matches) {
      batch.insert('matches', _matchToRow(t.id, null, m));
    }
    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------------
  // STANDINGS
  // ---------------------------------------------------------------------

  /// Match as seen by the standings; sport-specific classification points
  /// saved with the match (wrestling, judo, volleyball...) take precedence.
  static MatchResult _resultOf(MatchModel m) {
    final cp = SportScoring.classificationPoints(m.detail);
    return MatchResult(m.teamAId!, m.teamBId!, m.scoreA ?? 0, m.scoreB ?? 0,
        pointsA: cp?[0], pointsB: cp?[1]);
  }

  /// Saves (or clears, with null) the detailed result of a match.
  Future<void> setMatchDetail(Tournament t, MatchModel m, String? detail) async {
    m.detail = detail;
    notifyListeners();
    try {
      final db = await _db.database;
      await db.update('matches', {'detail': detail}, where: 'id = ?', whereArgs: [m.id]);
    } catch (e) {
      debugPrint('Saving match detail failed: $e');
    }
  }

  List<StandingRow> computeStandings(Tournament t, {List<String>? teamIds, List<MatchModel>? matches}) {
    final ids = teamIds ?? t.teams.map((e) => e.id).toList();
    final ms = matches ?? t.matches;
    // Ranking is done by the pure-Dart StandingsCalculator (points, goal
    // difference, goals scored, then head-to-head).
    final sportRules = SportRules.of(t.sport);
    final entries = StandingsCalculator.compute(
      teamIds: ids,
      rule: t.customPoints ?? sportRules.points,
      order: sportRules.tieBreakers,
      matches: [
        for (final m in ms)
          if (m.isPlayed && m.teamAId != null && m.teamBId != null)
            _resultOf(m),
      ],
    );
    return [
      for (final e in entries)
        StandingRow(t.teamById(e.id)!)
          ..played = e.played
          ..win = e.win
          ..draw = e.draw
          ..loss = e.loss
          ..gf = e.gf
          ..ga = e.ga
          ..pointsOverride = e.pts,
    ];
  }

  // ---------------------------------------------------------------------
  // RECYCLE BIN
  // ---------------------------------------------------------------------

  /// Moves one or more tournaments to the recycle bin. The in-memory list
  /// is updated immediately (so the UI reacts at once) and the database is
  /// written in one batch. Unknown ids are ignored instead of throwing.
  void softDelete(String id) => softDeleteMany([id]);

  void softDeleteMany(Iterable<String> ids) {
    final now = DateTime.now();
    final changed = <Tournament>[];
    for (final id in ids) {
      final idx = _tournaments.indexWhere((t) => t.id == id);
      if (idx < 0) continue;
      final t = _tournaments[idx];
      t.isDeleted = true;
      t.deletedAt = now;
      changed.add(t);
    }
    notifyListeners();
    _writeDeletionStates(changed);
  }

  void restore(String id) => restoreMany([id]);

  void restoreMany(Iterable<String> ids) {
    final changed = <Tournament>[];
    for (final id in ids) {
      final idx = _tournaments.indexWhere((t) => t.id == id);
      if (idx < 0) continue;
      final t = _tournaments[idx];
      t.isDeleted = false;
      t.deletedAt = null;
      changed.add(t);
    }
    notifyListeners();
    _writeDeletionStates(changed);
  }

  Future<void> _writeDeletionStates(List<Tournament> list) async {
    if (list.isEmpty) return;
    try {
      final db = await _db.database;
      final batch = db.batch();
      for (final t in list) {
        batch.update(
          'tournaments',
          {'isDeleted': t.isDeleted ? 1 : 0, 'deletedAt': t.deletedAt?.toIso8601String()},
          where: 'id = ?',
          whereArgs: [t.id],
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('Trash state write failed: $e');
    }
  }

  /// Permanently removes tournaments (and their photos). Memory is updated
  /// first so the UI reacts immediately; the database delete is awaited so
  /// the caller can be sure nothing comes back after a restart.
  void deleteForever(String id) {
    deleteForeverMany([id]);
  }

  Future<void> deleteForeverMany(Iterable<String> ids) async {
    final list = ids.toList();
    _tournaments.removeWhere((t) => list.contains(t.id));
    for (final id in list) {
      _undoStacks.remove(id);
    }
    notifyListeners();
    for (final id in list) {
      await _cleanupAndDelete(id);
    }
  }

  Future<void> _cleanupAndDelete(String id) async {
    List<String> imagePaths = const [];
    try {
      imagePaths = await _db.teamImagePaths(id);
    } catch (_) {}
    try {
      await _db.deleteTournamentCascade(id);
    } catch (e) {
      debugPrint('Permanent delete failed: $e');
    }
    await EloRatingService.instance.deleteTournamentEvents(id);
    await TeamImageStorage.deleteAll(imagePaths);
  }
}
