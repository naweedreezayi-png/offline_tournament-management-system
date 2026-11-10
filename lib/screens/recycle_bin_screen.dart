import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _confirmAndDelete(List<String> ids) async {
    if (ids.isEmpty) return;
    final provider = context.read<TournamentProvider>();
    final title = context.tr('deleteForever');
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
    if (mounted) setState(() => _selected.clear());
    await provider.deleteForeverMany(ids);
  }

  @override
  Widget build(BuildContext context) {
    final deleted = context.watch<TournamentProvider>().deletedTournaments;
    final allIds = deleted.map((t) => t.id).toSet();
    final allSelected = _selected.isNotEmpty && _selected.length == allIds.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? '${_selected.length}' : context.tr('recycleBin')),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selected.clear()),
              )
            : null,
        actions: [
          if (deleted.isNotEmpty)
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
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              tooltip: context.tr('deleteForever'),
              onPressed: () => _confirmAndDelete(_selected.toList()),
            ),
        ],
      ),
      body: Column(
        children: [
          if (deleted.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              child: Text(
                context.tr('trashRetentionNotice'),
                style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
              ),
            ),
          Expanded(
            child: deleted.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 64, color: mutedText(context)),
                        const SizedBox(height: 12),
                        Text(context.tr('emptyRecycleBin')),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: deleted.length,
                    itemBuilder: (context, index) {
                      final t = deleted[index];
                      final isSelected = _selected.contains(t.id);
                      final daysLeft = context.read<TournamentProvider>().daysUntilPermanentDelete(t);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: isSelected
                              ? const BorderSide(color: Colors.redAccent, width: 1.6)
                              : BorderSide.none,
                        ),
                        child: ListTile(
                          onTap: _selectionMode ? () => _toggle(t.id) : null,
                          onLongPress: () => _toggle(t.id),
                          leading: _selectionMode
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (_) => _toggle(t.id),
                                )
                              : null,
                          title: Text(t.name),
                          subtitle: Text(
                            '${t.teams.length} ${context.tr('team')} · ${context.tr('daysUntilDeleteLabel')} $daysLeft',
                          ),
                          trailing: _selectionMode
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.restore, color: Colors.green),
                                      tooltip: context.tr('restore'),
                                      onPressed: () =>
                                          context.read<TournamentProvider>().restore(t.id),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                                      tooltip: context.tr('deleteForever'),
                                      onPressed: () => _confirmAndDelete([t.id]),
                                    ),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
