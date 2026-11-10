import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../models/sport.dart';
import '../models/tournament.dart';
import '../providers/settings_provider.dart';
import '../screens/tournament_detail_screen.dart';
import '../theme/app_theme.dart';
import '../utils/zoom_route.dart';
import 'team_avatar.dart';

class TournamentCard extends StatelessWidget {
  final Tournament tournament;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TournamentCard({
    super.key,
    required this.tournament,
    this.selectionMode = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isLeague = tournament.type == TournamentType.league;
    final isRace = tournament.type == TournamentType.race;
    final preview = tournament.teams.take(4).toList();
    final sport = Sports.byId(tournament.sport);
    final langCode = context.watch<SettingsProvider>().languageCode;

    return AnimatedScale(
      scale: isSelected ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? Border.all(color: AppColors.primary, width: 2) : null,
        ),
        child: Material(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap ??
                () => Navigator.of(context).push(
                    ZoomRoute(page: TournamentDetailScreen(tournamentId: tournament.id))),
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (selectionMode) ...[
                        Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                          color: isSelected ? AppColors.primary : Colors.grey,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: isLeague ? AppTheme.primaryGradient : AppTheme.knockoutGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isRace
                              ? context.tr('raceTypeLabel')
                              : (isLeague ? context.tr('league') : context.tr('knockout')),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: sport.color.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.32 : 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(sport.icon, size: 13, color: sport.tone(Theme.of(context).brightness == Brightness.dark)),
                            const SizedBox(width: 4),
                            Text(sport.label(langCode),
                                style: TextStyle(
                                    fontSize: 11, color: sport.tone(Theme.of(context).brightness == Brightness.dark), fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                          ],
                        ),
                      ),
                      if (tournament.password != null)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.lock_rounded, size: 16, color: Colors.grey),
                        ),
                      Icon(isRace ? Icons.flag_rounded : (isLeague ? Icons.table_chart_rounded : Icons.account_tree_rounded),
                          size: 18, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(tournament.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _progress(context),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        height: 32,
                        child: Stack(
                          children: [
                            for (int i = 0; i < preview.length; i++)
                              Padding(
                                padding: EdgeInsets.only(left: i * 20.0),
                                child: IgnorePointer(
                                  ignoring: selectionMode,
                                  child: TeamAvatar(
                                      name: preview[i].name,
                                      imagePath: preview[i].imagePath,
                                      radius: 14),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text('${tournament.teams.length}',
                          style: TextStyle(color: mutedText(context), fontSize: 12)),
                      const SizedBox(width: 4),
                      Icon(Icons.groups_rounded, size: 14, color: mutedText(context)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "played / total" matches with a thin progress bar.
  Widget _progress(BuildContext context) {
    final all = [
      ...tournament.matches,
      for (final g in tournament.groups) ...g.matches,
    ].where((m) => !m.isBye).toList();
    if (all.isEmpty) return const SizedBox.shrink();
    final played = all.where((m) => m.isPlayed).length;
    final v = played / all.length;
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: v,
            minHeight: 6,
            color: v >= 1 ? AppColors.success : AppColors.primary,
            backgroundColor: AppColors.primary.withValues(alpha: 0.14),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Text('$played / ${all.length}', style: TextStyle(fontSize: 12, color: mutedText(context))),
      const SizedBox(width: 4),
      Icon(Icons.sports_score_rounded, size: 14, color: mutedText(context)),
    ]);
  }
}
