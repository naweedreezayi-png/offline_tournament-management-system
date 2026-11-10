import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' show join, basename;
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'schema.dart';

/// One backup file on disk.
class BackupInfo {
  final String path;
  final String name;
  final int bytes;
  final DateTime modified;
  const BackupInfo(this.path, this.name, this.bytes, this.modified);
}

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => message;
}

/// Manual backup / restore of the whole SQLite database file.
///
/// Restore never overwrites data blindly: the candidate file is opened
/// read-only and must pass `PRAGMA integrity_check` and contain the expected
/// tables, and the current database is copied to the backups folder first
/// (a "safety backup"), so a restore can itself be undone.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _requiredTables = ['tournaments', 'teams', 'matches'];

  static const _webMsg = 'Database backup and file export need the Android app. In the browser your data stays in the browser storage.';

  Future<Directory> _dir() async {
    if (kIsWeb) throw BackupException(_webMsg);
    final d = Directory(await DatabaseHelper.instance.backupsPath());
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  String _stamp() =>
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

  /// Creates a consistent copy of the live database. Returns its path.
  Future<String> createBackup({String label = 'manual'}) async {
    if (kIsWeb) throw BackupException(_webMsg);
    final helper = DatabaseHelper.instance;
    // Close so that no write is in flight while the file is copied, then
    // reopen lazily on the next access.
    await helper.close();
    final src = File(await helper.databasePath());
    if (!await src.exists()) throw BackupException('No database file to back up.');
    final dest = join((await _dir()).path, 'tournament_master_${label}_${_stamp()}.db');
    await src.copy(dest);
    return dest;
  }

  Future<List<BackupInfo>> listBackups() async {
    if (kIsWeb) return const [];
    final dir = await _dir();
    final out = <BackupInfo>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.db')) {
        final st = await e.stat();
        out.add(BackupInfo(e.path, basename(e.path), st.size, st.modified));
      }
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  /// Returns null if the file is a usable Tournament Master database,
  /// otherwise a human-readable reason.
  Future<String?> verify(String path) async {
    if (kIsWeb) return _webMsg;
    if (!await File(path).exists()) return 'File not found.';
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true);
      final check = await db.rawQuery('PRAGMA integrity_check');
      if (check.isEmpty || check.first.values.first != 'ok') {
        return 'Integrity check failed.';
      }
      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toSet();
      for (final t in _requiredTables) {
        if (!tables.contains(t)) return 'Missing table "$t": not a Tournament Master backup.';
      }
      final v = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;
      if (v > kDbVersion) {
        return 'Backup was made by a newer app version (schema v$v).';
      }
      return null;
    } catch (e) {
      return 'Cannot open file: $e';
    } finally {
      await db?.close();
    }
  }

  /// Replaces the live database with [path] (after verification and a
  /// safety backup). The caller must reload the in-memory state afterwards.
  Future<void> restore(String path) async {
    final problem = await verify(path);
    if (problem != null) throw BackupException(problem);
    final helper = DatabaseHelper.instance;
    await createBackup(label: 'before_restore');
    await helper.close();
    final live = await helper.databasePath();
    // sqlite sidecar files from the old database must not survive.
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('$live$suffix');
      if (await f.exists()) await f.delete();
    }
    await File(path).copy(live);
  }
}
