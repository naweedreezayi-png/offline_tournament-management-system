import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/domain/race.dart';

void main() {
  test('parseTime accepts valid times and rejects bad ones', () {
    expect(Race.parseTime('9.58'), 9580);
    expect(Race.parseTime('9,58'), 9580);
    expect(Race.parseTime('59.9'), 59900);
    expect(Race.parseTime('1:02.34'), 62340);
    expect(Race.parseTime('1:02:03.5'), 3723500);
    expect(Race.parseTime(''), isNull);
    expect(Race.parseTime('abc'), isNull);
    expect(Race.parseTime('0'), isNull);
    expect(Race.parseTime('1:75'), isNull);
    expect(Race.parseTime('-5'), isNull);
    expect(Race.parseTime('1:2:3:4'), isNull);
  });

  test('formatTime', () {
    expect(Race.formatTime(9580), '9.58');
    expect(Race.formatTime(62340), '1:02.34');
    expect(Race.formatTime(3723500), '1:02:03.50');
  });

  test('rank: by time, ties share a place, non-finishers have none', () {
    final r = Race.rank({
      'a': const RaceResult(RaceStatus.finished, 10000),
      'b': const RaceResult(RaceStatus.finished, 9500),
      'c': const RaceResult(RaceStatus.finished, 10000),
      'd': const RaceResult(RaceStatus.dnf),
      'e': const RaceResult(RaceStatus.finished, 12000),
      'f': null,
    });
    expect(r['b'], 1);
    expect(r['a'], 2);
    expect(r['c'], 2);
    expect(r['e'], 4);
    expect(r['d'], isNull);
    expect(r['f'], isNull);
  });

  test('result json round trip and rejection of garbage', () {
    final json = const RaceResult(RaceStatus.finished, 9580).toJson();
    final back = RaceResult.fromJson(json)!;
    expect(back.status, RaceStatus.finished);
    expect(back.timeMs, 9580);
    expect(RaceResult.fromJson('{"status":"dsq"}')!.status, RaceStatus.dsq);
    expect(RaceResult.fromJson('{"status":"finished"}'), isNull);
    expect(RaceResult.fromJson('not json'), isNull);
    expect(RaceResult.fromJson(null), isNull);
  });
}
