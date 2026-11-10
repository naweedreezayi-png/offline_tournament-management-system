import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../models/tournament.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/podium_results_view.dart';
import '../widgets/team_avatar.dart';

class LeagueResultsScreen extends StatelessWidget {
  final Tournament tournament;
  const LeagueResultsScreen({super.key, required this.tournament});

  @override
  Widget build(BuildContext context) {
    final standings = context.watch<TournamentProvider>().computeStandings(tournament);

    final entries = <PodiumEntry>[
      if (standings.isNotEmpty) PodiumEntry(1, standings[0].team),
      if (standings.length > 1) PodiumEntry(2, standings[1].team),
      if (standings.length > 2) PodiumEntry(3, standings[2].team),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('podium'))),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            PodiumResultsView(title: tournament.name, entries: entries, showTable: false),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(context.tr('table'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Table(
                columnWidths: const {0: FixedColumnWidth(56), 1: FlexColumnWidth()},
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1)),
                    children: [
                      _headerCell(context.tr('rank')),
                      _headerCell(context.tr('team')),
                    ],
                  ),
                  for (int i = 0; i < standings.length; i++)
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          child: Row(
                            children: [
                              TeamAvatar(
                                  name: standings[i].team.name,
                                  imagePath: standings[i].team.imagePath,
                                  radius: 14),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(standings[i].team.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text('${standings[i].pts} ${context.tr('pts')}',
                                  style: TextStyle(color: mutedText(context), fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      );
}
