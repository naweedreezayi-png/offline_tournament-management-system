import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/domain/sport_scoring.dart';
import 'package:tournament_master_offline/domain/standings_calculator.dart';

ScoreOutcome run(String sport, Map<String, int> v) => SportScoring.of(sport)!.evaluate(v);

void expectOk(ScoreOutcome o, int a, int b, {int? pa, int? pb}) {
  expect(o.isValid, isTrue, reason: o.error);
  expect([o.scoreA, o.scoreB], [a, b]);
  expect(o.pointsA, pa);
  expect(o.pointsB, pb);
}

void main() {
  group('judo', () {
    test('ippon ends the contest', () {
      expectOk(run('judoSport', {'ipponA': 1, 'wazaariB': 1}), 10, 7, pa: 1, pb: 0);
    });
    test('waza-ari beats yuko', () {
      expectOk(run('judoSport', {'wazaariA': 1, 'yukoB': 1}), 7, 5, pa: 1, pb: 0);
    });
    test('level scores need a golden-score winner', () {
      expect(run('judoSport', {'wazaariA': 1, 'wazaariB': 1}).isValid, isFalse);
      expectOk(run('judoSport', {'wazaariA': 1, 'wazaariB': 1, 'golden': 2}), 7, 8,
          pa: 0, pb: 1);
    });
    test('two waza-ari win automatically', () {
      expectOk(run('judoSport', {'wazaariA': 2}), 10, 0, pa: 1, pb: 0);
      expect(run('judoSport', {'wazaariA': 2, 'wazaariB': 2}).isValid, isFalse);
    });
    test('third shido loses by hansoku-make', () {
      expectOk(run('judoSport', {'shidoA': 3}), 0, 10, pa: 0, pb: 1);
    });
    test('two ippons are invalid', () {
      expect(run('judoSport', {'ipponA': 1, 'ipponB': 1}).isValid, isFalse);
    });
  });

  group('wrestling', () {
    test('fall gives 5-0 to the chosen winner', () {
      expectOk(run('wrestling', {'method': 1, 'winner': 2, 'techA': 6}), 0, 5, pa: 0, pb: 5);
      expect(run('wrestling', {'method': 1}).isValid, isFalse);
    });
    test('technical superiority at a 10-point lead', () {
      expectOk(run('wrestling', {'techA': 12}), 4, 0, pa: 4, pb: 0);
      expectOk(run('wrestling', {'techA': 14, 'techB': 4}), 4, 1, pa: 4, pb: 1);
      expectOk(run('wrestling', {'techA': 10}), 4, 0, pa: 4, pb: 0);
    });
    test('decision on points', () {
      expectOk(run('wrestling', {'techA': 9}), 3, 0, pa: 3, pb: 0);
      expectOk(run('wrestling', {'techA': 5, 'techB': 3}), 3, 1, pa: 3, pb: 1);
    });
    test('level points need a chosen winner', () {
      expect(run('wrestling', {'techA': 3, 'techB': 3}).isValid, isFalse);
      expectOk(run('wrestling', {'techA': 3, 'techB': 3, 'winner': 1}), 3, 1, pa: 3, pb: 1);
    });
  });

  group('volleyball', () {
    test('3-0 and 3-2 with table points', () {
      expectOk(
          run('volleyball', {'s1A': 25, 's1B': 20, 's2A': 25, 's2B': 23, 's3A': 25, 's3B': 10}),
          3, 0, pa: 3, pb: 0);
      expectOk(
          run('volleyball', {
            's1A': 25, 's1B': 20, 's2A': 20, 's2B': 25, 's3A': 25, 's3B': 23,
            's4A': 23, 's4B': 25, 's5A': 15, 's5B': 13,
          }),
          3, 2, pa: 2, pb: 1);
    });
    test('win by two rules', () {
      expectOk(
          run('volleyball', {'s1A': 26, 's1B': 24, 's2A': 25, 's2B': 20, 's3A': 25, 's3B': 20}),
          3, 0, pa: 3, pb: 0);
      expect(
          run('volleyball', {'s1A': 26, 's1B': 23, 's2A': 25, 's2B': 20, 's3A': 25, 's3B': 20})
              .isValid,
          isFalse);
      expect(
          run('volleyball', {'s1A': 25, 's1B': 24, 's2A': 25, 's2B': 20, 's3A': 25, 's3B': 20})
              .isValid,
          isFalse);
    });
    test('unfinished or over-long matches are rejected', () {
      expect(run('volleyball', {'s1A': 25, 's1B': 20, 's2A': 25, 's2B': 20}).isValid, isFalse);
      expect(
          run('volleyball', {
            's1A': 25, 's1B': 20, 's2A': 25, 's2B': 20, 's3A': 25, 's3B': 20,
            's4A': 25, 's4B': 20,
          }).isValid,
          isFalse);
    });
  });

  group('basketball, tennis, taekwondo, table tennis', () {
    test('basketball sums 1/2/3-point baskets and rejects a draw', () {
      expectOk(
          run('basketball', {
            'ftA': 10, 'fg2A': 20, 'fg3A': 10, 'ftB': 12, 'fg2B': 25, 'fg3B': 8,
          }),
          80, 86, pa: 1, pb: 2);
      expect(run('basketball', {'ftA': 2, 'ftB': 2}).isValid, isFalse);
    });
    test('tennis best of 3 / 5', () {
      expectOk(run('tennis', {'setsA': 2, 'setsB': 1}), 2, 1);
      expectOk(run('tennis', {'setsA': 3, 'setsB': 2}), 3, 2);
      expect(run('tennis', {'setsA': 2, 'setsB': 2}).isValid, isFalse);
    });
    test('taekwondo best of three rounds', () {
      expectOk(run('taekwondo', {'roundsA': 1, 'roundsB': 2}), 1, 2);
      expect(run('taekwondo', {'roundsA': 1, 'roundsB': 1}).isValid, isFalse);
      expectOk(run('taekwondo', {'forfeit': 1}), 2, 0);
    });
    test('table tennis games', () {
      expectOk(run('tableTennis', {'gamesA': 3, 'gamesB': 1}), 3, 1);
      expect(run('tableTennis', {'gamesA': 3, 'gamesB': 3}).isValid, isFalse);
    });
  });

  group('chess', () {
    test('win, draw and impossible combinations', () {
      expectOk(run('chess', {'result': 1, 'method': 0}), 1, 0, pa: 2, pb: 0);
      expectOk(run('chess', {'result': 3, 'method': 1}), 0, 1, pa: 0, pb: 2);
      expectOk(run('chess', {'result': 2, 'method': 4}), 1, 1, pa: 1, pb: 1);
      expect(run('chess', {'result': 0}).isValid, isFalse);
      expect(run('chess', {'result': 2, 'method': 0}).isValid, isFalse);
      expect(run('chess', {'result': 1, 'method': 5}).isValid, isFalse);
    });
  });

  group('kurash', () {
    test('points, halal, penalties and judges decision', () {
      expectOk(run('kurash', {'chalaA': 2, 'yonboshA': 1, 'chalaB': 1}), 4, 1, pa: 3, pb: 0);
      expectOk(run('kurash', {'halalB': 1}), 0, 10, pa: 0, pb: 3);
      expect(run('kurash', {'chalaA': 1, 'chalaB': 1}).isValid, isFalse);
      expectOk(run('kurash', {'chalaA': 1, 'chalaB': 1, 'winner': 1}), 1, 1, pa: 3, pb: 0);
      expect(run('kurash', {'halalA': 1, 'halalB': 1}).isValid, isFalse);
    });
    test('two yonbosh = halal win', () {
      expectOk(run('kurash', {'yonboshA': 2, 'chalaB': 1}), 10, 1, pa: 3, pb: 0);
    });
    test('girom, two dakki, three tanbeh lose automatically', () {
      expectOk(run('kurash', {'giromA': 1, 'chalaA': 3}), 3, 10, pa: 0, pb: 3);
      expectOk(run('kurash', {'dakkiB': 2, 'chalaB': 5}), 10, 5, pa: 3, pb: 0);
      expectOk(run('kurash', {'tanbehA': 3}), 0, 10, pa: 0, pb: 3);
    });
    test('tanbeh gives automatic points to the opponent', () {
      expectOk(run('kurash', {'tanbehA': 1}), 0, 1, pa: 0, pb: 3); // +1 chala to B
      expectOk(run('kurash', {'tanbehB': 2}), 3, 0, pa: 3, pb: 0); // +1 chala +1 yonbosh to A
      final e = KurashScoring.effective({'tanbehA': 2});
      expect([e['chalaB'], e['yonboshB'], e['dakkiA']], [1, 1, 1]);
    });
    test('contradictory input is invalid', () {
      expect(run('kurash', {'tanbehA': 3, 'tanbehB': 3}).isValid, isFalse);
      expect(run('kurash', {'giromA': 1, 'halalA': 1}).isValid, isFalse);
    });
  });

  group('cricket', () {
    test('margin in wickets when the chasing side wins', () {
      final o = run('cricket', {'runsA': 150, 'runsB': 151, 'wktsB': 4, 'chase': 2});
      expectOk(o, 150, 151, pa: 0, pb: 2);
      expect(o.summary, 'B wins by 6 wickets');
    });
    test('margin in runs when the side batting first wins', () {
      final o = run('cricket', {'runsA': 180, 'runsB': 151, 'chase': 2});
      expectOk(o, 180, 151, pa: 2, pb: 0);
      expect(o.summary, 'A wins by 29 runs');
    });
    test('tie, no result and missing chase side', () {
      expectOk(run('cricket', {'runsA': 150, 'runsB': 150, 'chase': 1}), 150, 150, pa: 1, pb: 1);
      expectOk(run('cricket', {'noResult': 1}), 0, 0, pa: 1, pb: 1);
      expect(run('cricket', {'runsA': 1}).isValid, isFalse);
    });
  });

  group('storage and standings', () {
    test('detail round-trips and classification points are read back', () {
      final s = SportScoring.of('wrestling')!;
      final input = {'techA': 14, 'techB': 4};
      final o = s.evaluate(input);
      final json = SportScoring.encode(s, input, o);
      expect(SportScoring.classificationPoints(json), [4, 1]);
      expect(SportScoring.inputOf(json)['techA'], 14);
      expect(SportScoring.summaryOf(json), contains('technical superiority'));
      expect(SportScoring.classificationPoints(null), isNull);
      expect(SportScoring.classificationPoints('not json'), isNull);
    });
    test('standings use classification points when present', () {
      final r = StandingsCalculator.compute(
        teamIds: ['A', 'B'],
        matches: const [MatchResult('A', 'B', 4, 1, pointsA: 4, pointsB: 1)],
      );
      expect(r.firstWhere((e) => e.id == 'A').pts, 4);
      expect(r.firstWhere((e) => e.id == 'B').pts, 1);
    });
    test('sports without a detailed model return null', () {
      expect(SportScoring.of('football'), isNull);
      expect(SportScoring.of(null), isNull);
    });
  });
}
