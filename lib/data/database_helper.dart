import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

/// Advanced local storage backed by SQLite (via sqflite), replacing a
/// single giant JSON blob. Tournaments, teams, groups and matches are
/// normalized into their own tables with indexes, so that tournaments
/// with hundreds of teams (and thousands of generated matches) can be
/// read and updated efficiently — single-row updates instead of
/// re-serializing the entire dataset on every score change.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _fileName = 'tournament_master.db';

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database async {
    if (_db != null) return _db!;
    // Concurrent callers share one open operation instead of racing.
    _opening ??= _open().whenComplete(() => _opening = null);
    _db = await _opening;
    return _db!;
  }

  /// Full path of the live database file.
  Future<String> databasePath() async => join(await getDatabasesPath(), _fileName);

  /// Folder that holds automatic and manual backups.
  Future<String> backupsPath() async => join(await getDatabasesPath(), 'backups');

  /// Closes the connection (it reopens lazily on the next access). Used
  /// around backup and restore so the file is not written while it is copied.
  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  Future<Database> _open() async {
    final path = await databasePath();
    await _backupBeforeUpgrade(path);
    return openDatabase(
      path,
      version: kDbVersion,
      // Foreign keys are switched on after migrations (onOpen) because a
      // table rebuild is not possible while they are enforced.
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final sql in kCreateSchema) {
          await db.execute(sql);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE tournaments ADD COLUMN twoLegged INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE matches ADD COLUMN scoreA2 INTEGER');
          await db.execute('ALTER TABLE matches ADD COLUMN scoreB2 INTEGER');
          await db.execute('ALTER TABLE matches ADD COLUMN penA INTEGER');
          await db.execute('ALTER TABLE matches ADD COLUMN penB INTEGER');
        }
        if (oldVersion < 3) {
          await _createRatingEvents(db);
        } else if (oldVersion < 4) {
          // ratings are now kept per sport
          await db.execute(
              "ALTER TABLE rating_events ADD COLUMN sport TEXT NOT NULL DEFAULT 'other'");
          await db.execute(
              "UPDATE rating_events SET sport = COALESCE((SELECT sport FROM tournaments WHERE tournaments.id = rating_events.tournamentId), 'other')");
        }
        if (oldVersion < 5) {
          for (final sql in kMigrateV4toV5) {
            await db.execute(sql);
          }
        }
        if (oldVersion < 6) {
          for (final sql in kMigrateV5toV6) {
            await db.execute(sql);
          }
        }
      },
    );
  }

  /// Before an existing database file is migrated to a newer schema, a
  /// complete copy is saved to the backups folder. If the migration fails,
  /// sqflite rolls the transaction back and this copy is still there.
  Future<void> _backupBeforeUpgrade(String path) async {
    if (kIsWeb) return; // no file system in the browser
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final probe = await openDatabase(path, readOnly: true);
      final version = Sqflite.firstIntValue(await probe.rawQuery('PRAGMA user_version')) ?? 0;
      await probe.close();
      if (version <= 0 || version >= kDbVersion) return;
      final dir = Directory(await backupsPath());
      if (!await dir.exists()) await dir.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      await file.copy(join(dir.path, 'tournament_master_before_v${kDbVersion}_from_v${version}_$stamp.db'));
    } catch (e) {
      // Never block start-up on the backup itself, but say so loudly: the
      // upgrade that follows is still transactional.
      debugPrint('Pre-migration backup failed: $e');
    }
  }

  /// Event log used by the machine-learning rating model (lib/ml). Only used
  /// when upgrading databases older than v3.
  Future<void> _createRatingEvents(Database db) async {
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

  Future<void> deleteTournamentCascade(String tournamentId) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('matches', where: 'tournamentId = ?', whereArgs: [tournamentId]);
    batch.delete('groups_table', where: 'tournamentId = ?', whereArgs: [tournamentId]);
    batch.delete('teams', where: 'tournamentId = ?', whereArgs: [tournamentId]);
    batch.delete('tournaments', where: 'id = ?', whereArgs: [tournamentId]);
    await batch.commit(noResult: true);
  }

  /// Returns the imagePath of every team in a tournament, so the caller
  /// can delete the underlying files from disk once the tournament is
  /// permanently removed (see image persistence notes in team_storage.dart).
  Future<List<String>> teamImagePaths(String tournamentId) async {
    final db = await database;
    final rows = await db.query('teams',
        columns: ['imagePath'], where: 'tournamentId = ? AND imagePath IS NOT NULL', whereArgs: [tournamentId]);
    return rows.map((r) => r['imagePath'] as String).toList();
  }
}
