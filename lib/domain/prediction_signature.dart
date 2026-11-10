import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/match_model.dart';
import '../models/tournament.dart';

/// A short fingerprint of everything a forecast depends on.
///
/// The old signature only counted played matches, so correcting a score
/// (same number of finished matches) left a stale forecast on screen. This
/// one hashes every score, penalty, winner, team and the points rule, so any
/// relevant change produces a different value.
class PredictionSignature {
  PredictionSignature._();

  static String of(Tournament t) {
    final b = StringBuffer()
      ..write(t.id)
      ..write('|')
      ..write(t.sport)
      ..write('|')
      ..write(t.type.name)
      ..write('|')
      ..write(t.twoLegged)
      ..write('|')
      ..write(t.champion)
      ..write('|');
    final p = t.customPoints;
    if (p != null) b.write('p${p.win},${p.draw},${p.loss}|');
    for (final team in t.teams) {
      b
        ..write(team.id)
        ..write(':')
        ..write(team.name)
        ..write(';');
    }
    b.write('|');
    for (final m in t.matches) {
      _match(b, m);
    }
    for (final g in t.groups) {
      b
        ..write('G')
        ..write(g.id)
        ..write(':')
        ..write(g.teamIds.join(','))
        ..write('{');
      for (final m in g.matches) {
        _match(b, m);
      }
      b.write('}');
    }
    return _hash(b.toString());
  }

  static void _match(StringBuffer b, MatchModel m) {
    b
      ..write(m.id)
      ..write(',')
      ..write(m.teamAId)
      ..write(',')
      ..write(m.teamBId)
      ..write(',')
      ..write(m.scoreA)
      ..write('-')
      ..write(m.scoreB)
      ..write(',')
      ..write(m.scoreA2)
      ..write('-')
      ..write(m.scoreB2)
      ..write(',')
      ..write(m.penA)
      ..write('-')
      ..write(m.penB)
      ..write(',')
      ..write(m.isPlayed)
      ..write(',')
      ..write(m.winnerId)
      ..write(';');
  }

  /// SHA-1 is used only as a compact fingerprint (not for security).
  static String _hash(String s) =>
      sha1.convert(utf8.encode(s)).toString().substring(0, 16);
}
