import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/team.dart';
import '../models/tournament.dart';
import '../widgets/podium_results_view.dart';

class KnockoutResultsScreen extends StatelessWidget {
  final Tournament tournament;
  const KnockoutResultsScreen({super.key, required this.tournament});

  @override
  Widget build(BuildContext context) {
    final champion = tournament.teamById(tournament.champion);
    final runnerUp = tournament.teamById(tournament.runnerUp);
    final thirds = tournament.thirdPlaceTeams
        .map((id) => tournament.teamById(id))
        .whereType<Team>()
        .toList();

    final entries = <PodiumEntry>[
      if (champion != null) PodiumEntry(1, champion),
      if (runnerUp != null) PodiumEntry(2, runnerUp),
      for (final t in thirds) PodiumEntry(3, t),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('podium'))),
      body: SafeArea(
        child: SingleChildScrollView(
          child: PodiumResultsView(title: tournament.name, entries: entries),
        ),
      ),
    );
  }
}
