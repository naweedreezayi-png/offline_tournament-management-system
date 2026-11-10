import 'package:flutter/material.dart';
import '../data/api_client.dart';
import 'package:provider/provider.dart';
import '../domain/sport_rules.dart';
import '../domain/standings_calculator.dart';
import '../l10n/app_strings.dart';
import '../models/tournament.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/gradient_button.dart';
import 'group_stage_view.dart';
import 'knockout_bracket_view.dart';
import 'league_table_view.dart';
import 'race_view.dart';
import 'prediction_screen.dart';
import '../utils/name_check.dart';
import '../utils/zoom_route.dart';

class TournamentDetailScreen extends StatefulWidget {
  final String tournamentId;
  const TournamentDetailScreen({super.key, required this.tournamentId});

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  bool _unlocked = false;
  bool _showGroups = false;

  Future<void> _addTeamsFlow(String tournamentId) async {
    final names = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _AddTeamsDialog(),
    );
    if (names == null || names.isEmpty || !mounted) return;
    final provider = context.read<TournamentProvider>();
    final t = provider.byId(tournamentId);
    final checked = NameCheck.check(names, existing: t.teams.map((e) => e.name));
    if (checked.unique.isNotEmpty) provider.addTeams(t, checked.unique);
    if (checked.hasDuplicates && mounted) {
      await NameCheck.showDuplicateDialog(context, checked.duplicates);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final exists = provider.activeTournaments.any((t) => t.id == widget.tournamentId) ||
        provider.deletedTournaments.any((t) => t.id == widget.tournamentId);
    if (!exists) {
      return Scaffold(appBar: AppBar(), body: const SizedBox());
    }
    final t = provider.byId(widget.tournamentId);

    if (t.password != null && !_unlocked) {
      return _PasswordGate(
        tournament: t,
        onUnlocked: () => setState(() => _unlocked = true),
      );
    }

    Widget body;
    if (t.type == TournamentType.race) {
      body = RaceView(tournament: t);
    } else if (t.type == TournamentType.league) {
      body = LeagueTableView(tournament: t, showFinalResultsButton: true);
    } else if (t.hasGroupStage && t.matches.isEmpty) {
      _showGroups = false; // when the bracket is regenerated, open on it
      body = GroupStageView(tournament: t);
    } else if (t.hasGroupStage) {
      // Group-stage tournament whose bracket exists: let the user flip
      // between the knockout bracket and the (read-only) groups, and go
      // back to the group stage to fix results.
      final showGroups = _showGroups;
      body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.account_tree_rounded, size: 18),
                    label: Text(context.tr('knockout'), overflow: TextOverflow.ellipsis)),
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.grid_view_rounded, size: 18),
                    label: Text(context.tr('groupStageTab'), overflow: TextOverflow.ellipsis)),
              ],
              selected: {showGroups},
              onSelectionChanged: (v) => setState(() => _showGroups = v.first),
            ),
          ),
          Expanded(
            child: showGroups
                ? GroupStageView(tournament: t, bracketExists: true)
                : KnockoutBracketView(tournament: t),
          ),
        ],
      );
    } else {
      body = KnockoutBracketView(tournament: t);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.name),
        actions: [
          if (t.type != TournamentType.race)
            IconButton(
            icon: const Icon(Icons.insights_rounded),
            tooltip: context.tr('predictions'),
            onPressed: () => Navigator.of(context)
                .push(ZoomRoute(page: PredictionScreen(tournamentId: t.id))),
          ),
          // Only offered before the first match is played (and again after
          // Undo has taken the tournament back to its start).
          if (ApiClient.instance.canEdit(t) && provider.canAddTeams(t))
            IconButton(
              icon: const Icon(Icons.group_add_rounded),
              tooltip: context.tr('addTeamsTitle'),
              onPressed: () => _addTeamsFlow(t.id),
            ),
          if (ApiClient.instance.canEdit(t) && provider.canUndo(t.id))
            IconButton(
              icon: const Icon(Icons.undo_rounded),
              tooltip: context.tr('undo'),
              onPressed: () => provider.undoLastAction(t.id),
            ),
          if (ApiClient.instance.canEdit(t) && (t.type == TournamentType.league || t.hasGroupStage))
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip: context.tr('scoringRules'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _ScoringRulesDialog(tournament: t),
              ),
            ),
          if (ApiClient.instance.canEdit(t))
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                useRootNavigator: true,
                builder: (dialogContext) => AlertDialog(
                  title: Text(context.tr('confirmDelete')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(context.tr('cancel')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(context.tr('confirm')),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                if (!context.mounted) return;
                final provider = context.read<TournamentProvider>();
                final id = t.id;
                provider.softDelete(id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

class _PasswordGate extends StatefulWidget {
  final Tournament tournament;
  final VoidCallback onUnlocked;
  const _PasswordGate({required this.tournament, required this.onUnlocked});

  @override
  State<_PasswordGate> createState() => _PasswordGateState();
}

class _PasswordGateState extends State<_PasswordGate> {
  final _controller = TextEditingController();
  String? _error;

  Future<void> _submit() async {
    final provider = context.read<TournamentProvider>();
    final ok = await provider.verifyPassword(widget.tournament.id, _controller.text);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = context.tr('wrongPassword'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.tournament.name)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 72),
              const SizedBox(height: 20),
              Icon(Icons.lock_rounded, size: 36, color: AppColors.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 10),
              Text(context.tr('locked'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                obscureText: true,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: context.tr('enterPassword'),
                  errorText: _error,
                  prefixIcon: const Icon(Icons.password),
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              GradientButton(
                label: context.tr('unlock'),
                icon: Icons.lock_open_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Dialog for typing the names of teams to add. It owns (and disposes) its
/// own text controller, so closing it can never leave a stale listener.
class _AddTeamsDialog extends StatefulWidget {
  const _AddTeamsDialog();

  @override
  State<_AddTeamsDialog> createState() => _AddTeamsDialogState();
}

class _AddTeamsDialogState extends State<_AddTeamsDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('addTeamsTitle')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(context.tr('addTeamsHint'), style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            maxLines: 8,
            minLines: 4,
            decoration: InputDecoration(
              hintText: 'Team 1\nTeam 2\n...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _controller.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
          ),
          child: Text(context.tr('addTeam')),
        ),
      ],
    );
  }
}


/// Lets the organiser change how many points a win / draw / loss earns in
/// this tournament's tables, or go back to the sport's own default.
class _ScoringRulesDialog extends StatefulWidget {
  final Tournament tournament;
  const _ScoringRulesDialog({required this.tournament});

  @override
  State<_ScoringRulesDialog> createState() => _ScoringRulesDialogState();
}

class _ScoringRulesDialogState extends State<_ScoringRulesDialog> {
  late final TextEditingController _win;
  late final TextEditingController _draw;
  late final TextEditingController _loss;

  @override
  void initState() {
    super.initState();
    final r = context.read<TournamentProvider>().effectivePoints(widget.tournament);
    _win = TextEditingController(text: '${r.win}');
    _draw = TextEditingController(text: '${r.draw}');
    _loss = TextEditingController(text: '${r.loss}');
  }

  @override
  void dispose() {
    _win.dispose();
    _draw.dispose();
    _loss.dispose();
    super.dispose();
  }

  int _read(TextEditingController c, int fallback) {
    final v = int.tryParse(c.text.trim());
    if (v == null || v < 0) return fallback;
    return v > 99 ? 99 : v;
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          maxLength: 2,
          decoration: InputDecoration(labelText: label, counterText: ''),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final rules = SportRules.of(t.sport);
    return AlertDialog(
      title: Text(context.tr('scoringRules')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${context.tr('rulesBasis')}: ${rules.basis}', style: const TextStyle(fontSize: 12)),
          _field(_win, context.tr('pointsWin')),
          _field(_draw, context.tr('pointsDraw')),
          _field(_loss, context.tr('pointsLoss')),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await context.read<TournamentProvider>().setScoringRules(t, null);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(context.tr('resetSportDefault')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        TextButton(
          onPressed: () async {
            final r = context.read<TournamentProvider>().effectivePoints(t);
            final rule = PointsRule(
              win: _read(_win, r.win),
              draw: _read(_draw, r.draw),
              loss: _read(_loss, r.loss),
            );
            await context.read<TournamentProvider>().setScoringRules(t, rule);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(context.tr('saveShort')),
        ),
      ],
    );
  }
}
