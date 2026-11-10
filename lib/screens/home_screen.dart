import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/api_client.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/sport.dart';
import '../providers/settings_provider.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';
import '../utils/zoom_route.dart';
import '../widgets/app_logo.dart';
import '../widgets/tournament_card.dart';
import 'create_tournament_screen.dart';
import 'live_leagues_screen.dart';
import 'settings_screen.dart';
import 'sport_folder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  final Set<String> _selected = {};

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
    });
  }

  void _toggleSelected(String id) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    try {
      await _deleteSelectedImpl();
    } catch (e) {
      rootMessengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text('Delete error: $e')));
    }
  }

  Future<void> _deleteSelectedImpl() async {
    if (_selected.isEmpty) return;
    final provider = context.read<TournamentProvider>();
    final ids = _selected.where((id) => ApiClient.instance.canEdit(provider.byId(id))).toList();
    if (ids.isEmpty) return;
    final title = context.tr('deleteTournament');
    final body = ids.length == 1
        ? context.tr('confirmDelete')
        : '${context.tr('confirmDelete')} (${ids.length})';
    final cancelLabel = context.tr('cancel');
    final confirmLabel = context.tr('confirm');

    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
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
    if (confirm != true) return;

    try {
      provider.softDeleteMany(ids);
    } catch (e) {
      rootMessengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      return;
    }
    if (mounted) setState(() => _selected.clear());
  }

  /// Large, always-visible action bar shown while tournaments are
  /// selected: Select all + Delete (asks for confirmation first).
  Widget _buildSelectionBar(BuildContext context, Set<String> allIds, bool allSelected) {
    return Material(
      elevation: 12,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                  label: Text(allSelected ? context.tr('cancel') : context.tr('selectAll'),
                      overflow: TextOverflow.ellipsis),
                  onPressed: () => setState(() {
                    if (allSelected) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(allIds);
                    }
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  icon: const Icon(Icons.delete_outline),
                  label: Text('${context.tr('deleteTournament')} (${_selected.length})',
                      overflow: TextOverflow.ellipsis),
                  onPressed: _deleteSelected,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, Set<String> allIds, bool allSelected) {
    if (_selectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _selected.clear()),
        ),
        title: Text('${_selected.length} ${context.tr('selected')}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
            tooltip: 'Select all',
            onPressed: () => setState(() {
              if (allSelected) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(allIds);
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: context.tr('deleteTournament'),
            onPressed: _deleteSelected,
          ),
        ],
      );
    }

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Row(
        children: [
          const AppLogo(size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('appName'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, height: 1.15)),
                Text(context.tr('myTournaments'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.sports_soccer),
          tooltip: context.tr('liveLeagues'),
          onPressed: () =>
              Navigator.of(context).push(ZoomRoute(page: const LiveLeaguesScreen())),
        ),
        PopupMenuButton<String>(
          tooltip: context.tr('settings'),
          icon: const Icon(Icons.more_vert),
          position: PopupMenuPosition.under,
          offset: const Offset(0, 6),
          onSelected: (v) async {
            switch (v) {
              case 'settings':
                Navigator.of(context).push(ZoomRoute(page: const SettingsScreen()));
                break;
            }
          },
          itemBuilder: (c) => [
            PopupMenuItem(
                value: 'settings',
                child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.settings_outlined),
                    title: Text(c.tr('settings')))),
          ],
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    final langCode = context.watch<SettingsProvider>().languageCode;
    final tournaments = provider.search(_query);
    final counts = provider.sportCounts();
    final allIds = tournaments.map((t) => t.id).toSet();
    final allSelected = _selected.isNotEmpty && allIds.difference(_selected).isEmpty;

    return Scaffold(
      // The app bar (both normal and selection-mode versions) lives here
      // instead of inside the scroll view, so it always stays fixed at
      // the top — exactly like modern apps — no matter how far the list
      // is scrolled.
      appBar: _buildAppBar(context, allIds, allSelected),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: context.tr('searchHint'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            if (_query.isEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(context.tr('sportFolders'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: Sports.all.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final sport = Sports.all[index];
                      final count = counts[sport.id] ?? 0;
                      final dark = Theme.of(context).brightness == Brightness.dark;
                      final tone = sport.tone(dark);
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.of(context).push(
                            ZoomRoute(page: SportFolderScreen(sportId: sport.id))),
                        child: Container(
                          width: 80,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: dark
                                ? sport.color.withValues(alpha: 0.30)
                                : Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: tone.withValues(alpha: dark ? 0.75 : 0.55), width: 1.2),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(sport.icon, color: tone, size: 28),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(sport.label(langCode),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: tone)),
                              ),
                              if (count > 0) ...[
                                const SizedBox(height: 2),
                                Text('$count',
                                    style: TextStyle(
                                        fontSize: 10, fontWeight: FontWeight.w700, color: tone)),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(context.tr('allTournaments'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
            if (tournaments.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(hasQuery: _query.isNotEmpty),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final t = tournaments[index];
                      return TournamentCard(
                        tournament: t,
                        selectionMode: _selectionMode,
                        isSelected: _selected.contains(t.id),
                        onTap: _selectionMode ? () => _toggleSelected(t.id) : null,
                        onLongPress: ApiClient.instance.canEdit(t) ? () => _toggleSelected(t.id) : null,
                      );
                    },
                    childCount: tournaments.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _selectionMode
          ? _buildSelectionBar(context, allIds, allSelected)
          : null,
      floatingActionButton: _selectionMode
          ? null
          : (!ApiClient.instance.isAdmin && !ApiClient.instance.isReferee)
          ? null // viewers cannot create tournaments
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context)
                  .push(ZoomRoute(page: const CreateTournamentScreen())),
              icon: const Icon(Icons.add),
              label: Text(context.tr('newTournament')),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  const _EmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hasQuery ? Icons.search_off_rounded : Icons.emoji_events_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(hasQuery ? context.tr('noResults') : context.tr('noTournaments'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (!hasQuery) ...[
              const SizedBox(height: 6),
              Text(context.tr('createTournamentHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.6))),
            ],
          ],
        ),
      ),
    );
  }
}
