import 'package:flutter/material.dart';
import '../data/api_client.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../models/match_model.dart';
import '../models/tournament.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_button.dart';
import '../widgets/team_avatar.dart';
import 'league_results_screen.dart';
import 'match_detail_screen.dart';
import '../utils/zoom_route.dart';

class LeagueTableView extends StatefulWidget {
  final Tournament tournament;
  final List<MatchModel>? matchesOverride;
  final List<String>? teamIdsOverride;
  final bool showFinalResultsButton;

  const LeagueTableView({
    super.key,
    required this.tournament,
    this.matchesOverride,
    this.teamIdsOverride,
    this.showFinalResultsButton = false,
  });

  @override
  State<LeagueTableView> createState() => _LeagueTableViewState();
}

class _LeagueTableViewState extends State<LeagueTableView>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final t = widget.tournament;
    final matches = widget.matchesOverride ?? t.matches;
    final standings = provider.computeStandings(t,
        teamIds: widget.teamIdsOverride, matches: matches);
    final allPlayed = matches.isNotEmpty && matches.every((m) => m.isPlayed);

    return Column(
      children: [
        TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          tabs: [Tab(text: context.tr('table')), Tab(text: context.tr('matches'))],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _StandingsTable(standings: standings),
              _MatchesList(tournament: t, matches: matches),
            ],
          ),
        ),
        if (widget.showFinalResultsButton && allPlayed)
          Padding(
            padding: const EdgeInsets.all(16),
            child: GradientButton(
              label: context.tr('next'),
              icon: Icons.arrow_forward_rounded,
              onPressed: () => Navigator.of(context)
                  .push(ZoomRoute(page: LeagueResultsScreen(tournament: t))),
            ),
          ),
      ],
    );
  }
}

class _StandingsTable extends StatelessWidget {
  final List<StandingRow> standings;
  const _StandingsTable({required this.standings});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              const SizedBox(width: 28),
              const Expanded(flex: 3, child: SizedBox()),
              _headerCell(context, 'pld'),
              _headerCell(context, 'win'),
              _headerCell(context, 'draw'),
              _headerCell(context, 'loss'),
              _headerCell(context, 'gd'),
              _headerCell(context, 'pts', bold: true),
            ],
          ),
        ),
        for (int i = 0; i < standings.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: _positionColor(i, standings.length), width: 4)),
            ),
            child: Row(
              children: [
                SizedBox(
                    width: 28,
                    child: Text('${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      TeamAvatar(
                          name: standings[i].team.name,
                          imagePath: standings[i].team.imagePath,
                          radius: 12),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(standings[i].team.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
                _valueCell('${standings[i].played}'),
                _valueCell('${standings[i].win}'),
                _valueCell('${standings[i].draw}'),
                _valueCell('${standings[i].loss}'),
                _valueCell('${standings[i].gd}'),
                _valueCell('${standings[i].pts}', bold: true),
              ],
            ),
          ),
      ],
    );
  }

  Color _positionColor(int index, int total) {
    // Top 3: green shades (darkest = 1st place)
    if (index == 0) return const Color(0xFF0B7A3F); // dark green
    if (index == 1) return const Color(0xFF2FA968); // medium green
    if (index == 2) return const Color(0xFF7FCBA0); // light green

    // Bottom 3 (from the end): red shades (darkest = last place)
    final fromEnd = total - 1 - index;
    if (total > 5) {
      if (fromEnd == 0) return const Color(0xFFB3261E); // dark red
      if (fromEnd == 1) return const Color(0xFFE05B4E); // medium red
      if (fromEnd == 2) return const Color(0xFFF3A79C); // light red
    }
    return Colors.transparent;
  }

  Widget _headerCell(BuildContext context, String key, {bool bold = false}) {
    return SizedBox(
      width: 30,
      child: Text(
        context.tr(key),
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
    );
  }

  Widget _valueCell(String v, {bool bold = false}) {
    return SizedBox(
      width: 30,
      child: Text(v,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
    );
  }
}

class _MatchesList extends StatelessWidget {
  final Tournament tournament;
  final List<MatchModel> matches;
  const _MatchesList({required this.tournament, required this.matches});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final m = matches[index];
        final a = tournament.teamById(m.teamAId);
        final b = tournament.teamById(m.teamBId);
        if (a == null || b == null) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            onTap: !m.isPlayed && !ApiClient.instance.canEdit(tournament)
                ? null
                : () => Navigator.of(context).push(ZoomRoute(
                    page: MatchDetailScreen(
                        tournament: tournament, match: m, isLeague: true, readOnly: m.isPlayed),
                  )),
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [TeamAvatar(name: a.name, imagePath: a.imagePath, radius: 14)],
            ),
            title: Row(
              children: [
                Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                Text(
                  m.isPlayed ? '${m.scoreA} - ${m.scoreB}' : context.tr('vs'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(
                    child: Text(b.name,
                        textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
              ],
            ),
            trailing: TeamAvatar(name: b.name, imagePath: b.imagePath, radius: 14),
            subtitle: Center(
              child: Text(
                m.isPlayed ? context.tr('fullTime') : context.tr('notPlayed'),
                style: TextStyle(fontSize: 11, color: mutedText(context)),
              ),
            ),
          ),
        );
      },
    );
  }
}
