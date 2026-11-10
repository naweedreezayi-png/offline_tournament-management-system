import 'dart:convert';

/// Single-start events (dash, athletics, swimming, cycling): every entrant has
/// one result and the ranking is by time. Pure Dart, unit-tested.
enum RaceStatus { finished, dnf, dns, dsq }

class RaceResult {
  final RaceStatus status;
  final int? timeMs; // only for [RaceStatus.finished]
  const RaceResult(this.status, [this.timeMs]);

  String toJson() => jsonEncode({'status': status.name, if (timeMs != null) 'timeMs': timeMs});

  /// Reads a stored result; returns null for anything that is not a valid result.
  static RaceResult? fromJson(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final m = jsonDecode(text);
      if (m is! Map) return null;
      final status = RaceStatus.values.where((s) => s.name == m['status']);
      if (status.isEmpty) return null;
      final t = m['timeMs'];
      if (status.first == RaceStatus.finished) {
        if (t is! int || t <= 0) return null;
        return RaceResult(RaceStatus.finished, t);
      }
      return RaceResult(status.first);
    } catch (_) {
      return null;
    }
  }
}

class Race {
  /// Parses "9.58", "59.9", "1:02.34", "1:02:03.5" (h:mm:ss) into milliseconds.
  /// Returns null if the text is not a valid positive time.
  static int? parseTime(String input) {
    final text = input.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length > 3) return null;
    var seconds = 0.0;
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      final isLast = i == parts.length - 1;
      if (isLast) {
        if (!RegExp(r'^\d{1,4}(\.\d{1,3})?$').hasMatch(p)) return null;
        seconds = seconds * 60 + double.parse(p);
      } else {
        if (!RegExp(r'^\d{1,3}$').hasMatch(p)) return null;
        seconds = seconds * 60 + int.parse(p);
      }
    }
    if (parts.length > 1) {
      // minutes and seconds fields must be below 60 when they are not the first field
      final fields = text.split(':');
      for (var i = 1; i < fields.length; i++) {
        final v = double.parse(fields[i]);
        if (v >= 60) return null;
      }
    }
    final ms = (seconds * 1000).round();
    return ms > 0 ? ms : null;
  }

  /// 9580 -> "9.58", 62340 -> "1:02.34", 3723500 -> "1:02:03.50"
  static String formatTime(int ms) {
    final totalCs = (ms / 10).round();
    final cs = totalCs % 100;
    final totalSec = totalCs ~/ 100;
    final s = totalSec % 60;
    final m = (totalSec ~/ 60) % 60;
    final h = totalSec ~/ 3600;
    final c = cs.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.$c';
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}.$c';
    return '$s.$c';
  }

  /// Ranks entrants. Finished entrants get places 1..n by time (equal times
  /// share a place: 1, 1, 3). Others (DNF, DNS, DSQ) and entrants without a
  /// result get null. Returns a map entrantId -> place.
  static Map<String, int?> rank(Map<String, RaceResult?> results) {
    final finished = <MapEntry<String, int>>[
      for (final e in results.entries)
        if (e.value != null && e.value!.status == RaceStatus.finished) MapEntry(e.key, e.value!.timeMs!),
    ]..sort((a, b) => a.value.compareTo(b.value));
    final out = <String, int?>{for (final e in results.keys) e: null};
    for (var i = 0; i < finished.length; i++) {
      final sameAsPrevious = i > 0 && finished[i].value == finished[i - 1].value;
      out[finished[i].key] = sameAsPrevious ? out[finished[i - 1].key] : i + 1;
    }
    return out;
  }
}
