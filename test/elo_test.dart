import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/ml/elo_rating_service.dart';

RatingEvent ev(int seq, String a, String b, int ga, int gb, {String id = ''}) =>
    RatingEvent(
      matchId: id.isEmpty ? 'm$seq' : id,
      tournamentId: 't1',
      teamA: a,
      teamB: b,
      goalsA: ga,
      goalsB: gb,
      resultA: ga > gb ? 1 : (ga < gb ? 0 : 0.5),
      seq: seq,
    );

void main() {
  group('Elo expected score', () {
    test('equal ratings give 0.5', () {
      expect(EloRatingService.expected(1000, 1000), closeTo(0.5, 1e-12));
    });
    test('is symmetric: E(a,b) + E(b,a) = 1', () {
      expect(EloRatingService.expected(1200, 1000) + EloRatingService.expected(1000, 1200),
          closeTo(1.0, 1e-12));
    });
    test('400 points higher means about 10:1 odds', () {
      expect(EloRatingService.expected(1400, 1000), closeTo(10 / 11, 1e-9));
    });
  });

  group('Elo replay', () {
    test('is deterministic', () {
      final events = [ev(1, 'A', 'B', 2, 0), ev(2, 'B', 'C', 1, 1), ev(3, 'A', 'C', 0, 3)];
      final m1 = EloRatingService.trainFrom(events);
      final m2 = EloRatingService.trainFrom(events);
      for (final k in m1.ratings.keys) {
        expect(m1.ratings[k]!.rating, m2.ratings[k]!.rating);
      }
    });

    test('first match between two new teams is zero-sum', () {
      final m = EloRatingService.trainFrom([ev(1, 'A', 'B', 1, 0)]);
      final a = m.ratings['a']!.rating, b = m.ratings['b']!.rating;
      expect(a + b, closeTo(2000, 1e-9));
      expect(a, greaterThan(1000));
    });

    test('team names are matched case- and space-insensitively', () {
      final m = EloRatingService.trainFrom([ev(1, 'Ahmadi', 'B', 1, 0), ev(2, ' ahmadi ', 'C', 1, 0)]);
      expect(m.ratings.length, 3);
      expect(m.ratings['ahmadi']!.played, 2);
    });

    test('correction: replaying history with a corrected score changes ratings', () {
      final before = EloRatingService.trainFrom([ev(1, 'A', 'B', 2, 0)]);
      final after = EloRatingService.trainFrom([ev(1, 'A', 'B', 0, 2)]);
      expect(before.ratings['a']!.rating, greaterThan(1000));
      expect(after.ratings['a']!.rating, lessThan(1000));
    });

    test('reversal: removing a match restores the earlier rating exactly', () {
      final base = [ev(1, 'A', 'B', 1, 0)];
      final withExtra = [...base, ev(2, 'A', 'C', 3, 0)];
      final m0 = EloRatingService.trainFrom(base);
      final m2 = EloRatingService.trainFrom(withExtra);
      final back = EloRatingService.trainFrom(withExtra.sublist(0, 1));
      expect(m2.ratings['a']!.rating, isNot(m0.ratings['a']!.rating));
      expect(back.ratings['a']!.rating, m0.ratings['a']!.rating);
    });

    test('a win never lowers the winner rating (first matches)', () {
      final m = EloRatingService.trainFrom([ev(1, 'A', 'B', 5, 4)]);
      expect(m.ratings['a']!.rating, greaterThan(1000));
      expect(m.ratings['b']!.rating, lessThan(1000));
    });

    test('draw between equal new teams changes nothing', () {
      final m = EloRatingService.trainFrom([ev(1, 'A', 'B', 1, 1)]);
      expect(m.ratings['a']!.rating, closeTo(1000, 1e-9));
    });
  });

  group('Duplicate events', () {
    // DB-level uniqueness (rating_events.matchId UNIQUE) is enforced by the
    // schema; it is NOT covered by a Dart test yet (needs sqflite_common_ffi).
    test('profiles exist for every sport id used by the app', () {
      for (final id in ['football', 'futsal', 'basketball', 'volleyball', 'cricket', 'tableTennis']) {
        expect(SportProfiles.of(id), isNotNull);
      }
    });
  });
}
