import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../models/tournament.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_button.dart';
import 'league_table_view.dart';

class GroupStageView extends StatefulWidget {
  final Tournament tournament;
  /// True when the knockout bracket already exists and the groups are
  /// shown only for review (with a button to go back and edit them).
  final bool bracketExists;
  const GroupStageView({super.key, required this.tournament, this.bracketExists = false});

  @override
  State<GroupStageView> createState() => _GroupStageViewState();
}

class _GroupStageViewState extends State<GroupStageView> {
  int _selectedGroup = 0;

  Future<void> _backToGroups(BuildContext context, Tournament t) async {
    final provider = context.read<TournamentProvider>();
    final hasResults = provider.bracketHasResults(t);
    final title = context.tr('backToGroups');
    final warn = context.tr('backToGroupsWarn');
    final cancelLabel = context.tr('cancel');
    final confirmLabel = context.tr('confirm');
    if (hasResults) {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(warn),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(cancelLabel)),
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(confirmLabel)),
          ],
        ),
      );
      if (ok != true) return;
    }
    provider.returnToGroupStage(t);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final t = widget.tournament;
    final groups = t.groups;
    final allPlayed = provider.allGroupMatchesPlayed(t);

    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final selected = index == _selectedGroup;
              return ChoiceChip(
                label: Text(groups[index].name),
                selected: selected,
                onSelected: (_) => setState(() => _selectedGroup = index),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(color: selected ? Colors.white : null),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LeagueTableView(
            tournament: t,
            matchesOverride: groups[_selectedGroup].matches,
            teamIdsOverride: groups[_selectedGroup].teamIds,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: widget.bracketExists
              ? GradientButton(
                  label: context.tr('backToGroups'),
                  icon: Icons.undo_rounded,
                  onPressed: () => _backToGroups(context, t),
                )
              : GradientButton(
                  label: context.tr('next'),
                  icon: Icons.arrow_forward_rounded,
                  onPressed: allPlayed
                      ? () => context.read<TournamentProvider>().promoteGroupWinners(t)
                      : null,
                ),
        ),
      ],
    );
  }
}
