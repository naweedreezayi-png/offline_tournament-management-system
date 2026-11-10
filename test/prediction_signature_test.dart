import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/domain/prediction_signature.dart';
import 'package:tournament_master_offline/models/match_model.dart';
import 'package:tournament_master_offline/models/team.dart';
import 'package:tournament_master_offline/models/tournament.dart';

Tournament make(int a, int b) => Tournament(
      id: 't',
      name: 'T',
      type: TournamentType.league,
      teams: [Team(id: '1', name: 'A'), Team(id: '2', name: 'B')],
      matches: [
        MatchModel(
            id: 'm', teamAId: '1', teamBId: '2', scoreA: a, scoreB: b,
            isPlayed: true, round: 0, order: 0),
      ],
    );

void main() {
  test('same data gives the same signature', () {
    expect(PredictionSignature.of(make(2, 1)), PredictionSignature.of(make(2, 1)));
  });

  test('a corrected score changes the signature even if played count is equal', () {
    expect(PredictionSignature.of(make(2, 1)), isNot(PredictionSignature.of(make(1, 2))));
    expect(PredictionSignature.of(make(2, 1)), isNot(PredictionSignature.of(make(2, 0))));
  });

  test('renaming a team changes the signature', () {
    final t = make(1, 0);
    final s = PredictionSignature.of(t);
    t.teams[0].name = 'Z';
    expect(PredictionSignature.of(t), isNot(s));
  });
}
