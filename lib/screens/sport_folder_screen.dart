import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../models/sport.dart';
import '../providers/settings_provider.dart';
import '../providers/tournament_provider.dart';
import '../widgets/tournament_card.dart';

class SportFolderScreen extends StatelessWidget {
  final String sportId;
  const SportFolderScreen({super.key, required this.sportId});

  @override
  Widget build(BuildContext context) {
    final sport = Sports.byId(sportId);
    final langCode = context.watch<SettingsProvider>().languageCode;
    final tournaments = context.watch<TournamentProvider>().tournamentsBySport(sportId);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sport.icon, color: sport.tone(Theme.of(context).brightness == Brightness.dark), size: 20),
            const SizedBox(width: 8),
            Text(sport.label(langCode)),
          ],
        ),
      ),
      body: tournaments.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(sport.icon, size: 64, color: sport.tone(Theme.of(context).brightness == Brightness.dark).withValues(alpha: 0.45)),
                  const SizedBox(height: 12),
                  Text(context.tr('noTournaments')),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tournaments.length,
              itemBuilder: (context, index) => TournamentCard(tournament: tournaments[index]),
            ),
    );
  }
}
