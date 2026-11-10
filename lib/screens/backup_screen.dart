import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/backup_service.dart';
import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../models/tournament.dart';
import '../providers/tournament_provider.dart';
import '../utils/export_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<BackupInfo> _items = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final list = await BackupService.instance.listBackups();
    if (mounted) setState(() => _items = list);
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<String> Function() job) async {
    setState(() => _busy = true);
    try {
      final m = await job();
      if (m.isNotEmpty) _msg(m);
    } catch (e) {
      // browsers cannot write files to disk: say so instead of showing "UnimplementedError"
      _msg((e is UnimplementedError || e is UnsupportedError) ? context.tr('webNoFiles') : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _restore(BackupInfo b) async {
    final provider = context.read<TournamentProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.tr('backupRestore')),
        content: Text(context.tr('restoreConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(context.tr('confirm'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = context.tr('backupDone');
    await _run(() async {
      await BackupService.instance.restore(b.path);
      await provider.reloadFromDatabase();
      return done;
    });
  }

  /// Imports a tournament from a .json file written by "Export tournament".
  /// Never replaces an existing tournament: the id and the name must be new.
  Future<void> _importJson() async {
    final provider = context.read<TournamentProvider>();
    final ok = context.tr('importJsonOk');
    final bad = context.tr('importJsonBad');
    final dup = context.tr('importJsonDup');
    await _run(() async {
      final res = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json'], withData: true);
      final bytes = res?.files.single.bytes;
      if (bytes == null) return '';
      Tournament t;
      try {
        final j = jsonDecode(utf8.decode(bytes));
        if (j is! Map || j['name'] == null || j['teams'] is! List || j['matches'] is! List) {
          return bad;
        }
        t = Tournament.fromJson(Map<String, dynamic>.from(j));
      } catch (_) {
        return bad;
      }
      return await provider.importTournament(t) ? ok : dup;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TournamentProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('backupRestore'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.backup_outlined),
            label: Text(context.tr('createBackup')),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      final p = await BackupService.instance.createBackup();
                      return p;
                    }),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.file_upload_outlined),
            label: Text(context.tr('importJson')),
            onPressed: _busy ? null : _importJson,
          ),
          const SizedBox(height: 8),
          if (provider.activeTournaments.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.file_download_outlined),
              label: Text(context.tr('exportTournament')),
              onPressed: _busy
                  ? null
                  : () async {
                      final choice = await showDialog<dynamic>(
                        context: context,
                        builder: (c) => SimpleDialog(children: [
                          for (final t in provider.activeTournaments)
                            SimpleDialogOption(
                                onPressed: () => Navigator.pop(c, t), child: Text(t.name)),
                        ]),
                      );
                      if (choice == null) return;
                      await _run(() async {
                        final files = await ExportService.exportTournament(choice, provider);
                        files.add(await ExportService.exportXlsx(choice, provider));
                        return files.join('\n');
                      });
                    },
            ),
          const SizedBox(height: 8),
          if (provider.activeTournaments.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(context.tr('exportPdf')),
              onPressed: _busy
                  ? null
                  : () async {
                      final choice = await showDialog<dynamic>(
                        context: context,
                        builder: (c) => SimpleDialog(children: [
                          for (final t in provider.activeTournaments)
                            SimpleDialogOption(
                                onPressed: () => Navigator.pop(c, t), child: Text(t.name)),
                        ]),
                      );
                      if (choice == null) return;
                      final rtl = context.read<SettingsProvider>().isRtl;
                      await _run(() async {
                        await ExportService.sharePdf(choice, provider, rtl: rtl);
                        return context.tr('backupDone');
                      });
                    },
            ),
          const SizedBox(height: 16),
          if (_items.isEmpty)
            Center(child: Padding(
                padding: const EdgeInsets.all(24), child: Text(context.tr('noBackups'))))
          else
            for (final b in _items)
              Card(
                child: ListTile(
                  title: Text(b.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text('${(b.bytes / 1024).toStringAsFixed(0)} KB · ${b.modified.toLocal().toString().split('.').first}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.restore),
                    onPressed: _busy ? null : () => _restore(b),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
