import 'package:flutter/material.dart';
import '../data/api_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_strings.dart';
import '../ml/elo_rating_service.dart';
import '../models/team.dart';
import '../models/tournament.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';
import '../utils/name_check.dart';
import '../utils/password_hasher.dart';
import '../utils/zoom_route.dart';
import '../utils/team_storage.dart';
import '../widgets/gradient_button.dart';
import '../widgets/team_avatar.dart';
import 'tournament_detail_screen.dart';

/// Each draft team owns a persistent [TextEditingController]. Because this
/// controller lives on our own retained Dart object (kept in [_teams]),
/// not inside the TextField's ephemeral Element/State, its text survives
/// even if ListView virtualization disposes and later rebuilds the row's
/// widgets (e.g. once the list grows past one screen and needs to
/// scroll) — this is what was wiping out earlier teams' names before.
class _DraftTeam {
  final String id;
  final TextEditingController nameController;
  String? imagePath;
  bool isRemoved = false; // soft-deleted: shown struck-through, can be undone
  _DraftTeam({required this.id, String name = ''})
      : nameController = TextEditingController(text: name);

  String get name => nameController.text;

  void dispose() => nameController.dispose();
}

class TeamSetupScreen extends StatefulWidget {
  final String tournamentName;
  final TournamentType type;
  final bool hasGroupStage;
  final SeedingMode seedingMode;
  final String sport;
  final String? password;
  final bool twoLegged;

  const TeamSetupScreen({
    super.key,
    required this.tournamentName,
    required this.type,
    required this.hasGroupStage,
    required this.seedingMode,
    required this.sport,
    required this.twoLegged,
    this.password,
  });

  @override
  State<TeamSetupScreen> createState() => _TeamSetupScreenState();
}

class _TeamSetupScreenState extends State<TeamSetupScreen> {
  final _uuid = const Uuid();
  final List<_DraftTeam> _teams = [];
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _teams.add(_DraftTeam(id: _uuid.v4()));
    _teams.add(_DraftTeam(id: _uuid.v4()));
  }

  @override
  void dispose() {
    for (final t in _teams) {
      t.dispose();
    }
    super.dispose();
  }

  List<String> get _activeNames =>
      _teams.where((t) => !t.isRemoved).map((t) => t.name).toList();

  /// Names (as typed) that repeat another active draft name.
  List<String> _currentDuplicates() {
    final rep = NameCheck.repeatedKeys(_activeNames);
    if (rep.isEmpty) return const [];
    return _activeNames
        .where((n) => n.trim().isNotEmpty && rep.contains(NameCheck.key(n)))
        .toList();
  }

  bool _isDuplicate(_DraftTeam t) {
    if (t.isRemoved || t.name.trim().isEmpty) return false;
    final k = NameCheck.key(t.name);
    return _teams.where((x) => !x.isRemoved && NameCheck.key(x.name) == k && x.name.trim().isNotEmpty).length > 1;
  }

  void _addTeam() {
    final dups = _currentDuplicates();
    if (dups.isNotEmpty) {
      NameCheck.showDuplicateDialog(context, dups);
      return;
    }
    setState(() => _teams.add(_DraftTeam(id: _uuid.v4())));
  }

  Future<void> _bulkAdd() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('teamsOrPlayers')),
        content: TextField(
          controller: controller,
          maxLines: 10,
          minLines: 6,
          decoration: InputDecoration(
            hintText: 'Team 1\nTeam 2\nTeam 3\n...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(context.tr('addTeam'))),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    final typed = result.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    // Names already in the list (ignoring blank rows) count as taken.
    final taken = _teams.where((t) => !t.isRemoved && t.name.trim().isNotEmpty).map((t) => t.name);
    final checked = NameCheck.check(typed, existing: taken);
    final names = checked.unique;
    setState(() {
      // drop empty trailing draft rows before bulk-appending
      final empties = _teams.where((t) => t.name.trim().isEmpty).toList();
      for (final e in empties) {
        _teams.remove(e);
        e.dispose();
      }
      for (final n in names) {
        _teams.add(_DraftTeam(id: _uuid.v4(), name: n));
      }
      if (_teams.isEmpty) _teams.add(_DraftTeam(id: _uuid.v4()));
    });
    if (checked.hasDuplicates && mounted) {
      await NameCheck.showDuplicateDialog(context, checked.duplicates);
    }
  }

  void _removeTeam(String id) {
    setState(() {
      _teams.firstWhere((t) => t.id == id).isRemoved = true;
    });
  }

  void _undoRemoveTeam(String id) {
    setState(() {
      _teams.firstWhere((t) => t.id == id).isRemoved = false;
    });
  }

  Future<void> _pickImage(_DraftTeam team) async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file != null) {
      final permanentPath = await TeamImageStorage.persist(file.path);
      setState(() => team.imagePath = permanentPath);
    }
  }

  bool get _canCreate =>
      _teams.where((t) => !t.isRemoved && t.name.trim().isNotEmpty).length >= 2;

  Future<void> _create() async {
    final dups = _currentDuplicates();
    if (dups.isNotEmpty) {
      await NameCheck.showDuplicateDialog(context, dups);
      return;
    }
    var teams = _teams
        .where((t) => !t.isRemoved && t.name.trim().isNotEmpty)
        .map((t) => Team(id: t.id, name: t.name.trim(), imagePath: t.imagePath))
        .toList();

    if (widget.seedingMode == SeedingMode.balanced) {
      // AI-balanced draw: order teams from strongest to weakest using the
      // ratings learned for THIS sport, so strong teams are spread out
      // (different groups / opposite sides of the bracket). Teams without
      // history count as average; ties keep the entry order.
      try {
        final model = await EloRatingService.instance.train(sport: widget.sport);
        final indexed = [for (var i = 0; i < teams.length; i++) (i, teams[i])];
        indexed.sort((a, b) {
          final c = model.ratingOf(b.$2.name).compareTo(model.ratingOf(a.$2.name));
          return c != 0 ? c : a.$1.compareTo(b.$1);
        });
        teams = [for (final e in indexed) e.$2];
      } catch (_) {}
      if (!mounted) return;
    }

    // The tournament password is hashed before it ever reaches storage.
    final rawPassword = widget.password;
    final storedPassword = (rawPassword == null || rawPassword.trim().isEmpty)
        ? null
        : await PasswordHasher.hash(rawPassword);
    if (!mounted) return;

    final tournament = context.read<TournamentProvider>().createTournament(
          name: widget.tournamentName,
          type: widget.type,
          hasGroupStage: widget.hasGroupStage,
          seedingMode: widget.seedingMode,
          teams: teams,
          sport: widget.sport,
          password: storedPassword,
          twoLegged: widget.twoLegged,
        );

    await ApiClient.instance.claim(tournament.id); // the creator owns it (referees edit only their own)
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      ZoomRoute(page: TournamentDetailScreen(tournamentId: tournament.id)),
      (route) => route.isFirst,
    );
  }

  Widget _buildTeamRow(BuildContext context, int index, {required bool dragHandle}) {
    final t = _teams[index];
    final activeCount = _teams.where((x) => !x.isRemoved).length;

    return Padding(
      key: ValueKey(t.id),
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: t.isRemoved ? 0.5 : 1,
        child: Row(
          children: [
            if (dragHandle)
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.drag_handle, color: Colors.grey),
                ),
              ),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                AnimatedBuilder(
                  animation: t.nameController,
                  builder: (context, _) => TeamAvatar(
                    name: t.name,
                    imagePath: t.imagePath,
                    radius: 24,
                    onTap: t.isRemoved ? null : () => _pickImage(t),
                  ),
                ),
                if (!t.isRemoved)
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt, size: 11, color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: t.isRemoved
                  ? Text(
                      t.name.trim().isEmpty ? '${context.tr('teamName')} ${index + 1}' : t.name,
                      style: const TextStyle(
                          decoration: TextDecoration.lineThrough, color: Colors.grey),
                    )
                  : TextField(
                      controller: t.nameController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        errorText: _isDuplicate(t) ? context.tr('dupField') : null,
                        hintText: '${context.tr('teamName')} ${index + 1}',
                        filled: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
            ),
            if (t.isRemoved)
              IconButton(
                icon: const Icon(Icons.undo, color: AppColors.primary),
                tooltip: context.tr('undo'),
                onPressed: () => _undoRemoveTeam(t.id),
              )
            else if (activeCount > 2)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => _removeTeam(t.id),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('teamsOrPlayers'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Text('${context.tr('teamsOrPlayers')} (${_teams.where((t) => !t.isRemoved).length})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _bulkAdd,
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: Text(context.tr('addTeam')),
                ),
              ],
            ),
          ),
          if (widget.seedingMode == SeedingMode.manual)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.drag_indicator, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(context.tr('manualSeedHint'),
                          style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: widget.seedingMode == SeedingMode.manual
                ? ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    itemCount: _teams.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final item = _teams.removeAt(oldIndex);
                        _teams.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) =>
                        _buildTeamRow(context, index, dragHandle: true),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    itemCount: _teams.length,
                    itemBuilder: (context, index) =>
                        _buildTeamRow(context, index, dragHandle: false),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: _addTeam,
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('addTeam')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                if (!_canCreate)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(context.tr('needMoreTeams'),
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                GradientButton(
                  label: context.tr('createTournamentBtn'),
                  icon: Icons.check_circle_outline,
                  onPressed: _canCreate ? _create : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
