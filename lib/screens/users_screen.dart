import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../l10n/app_strings.dart';
import '../models/sport.dart';
import '../theme/app_theme.dart';

/// Administrator only: create referees and viewers, change roles, block, reset passwords, remove.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _error = '';

  ApiClient get _api => ApiClient.instance;

  @override
  void initState() {
    super.initState();
    _future = _api.members();
  }

  void _reload() => setState(() => _future = _api.members());

  Future<void> _guard(Future<void> Function() job) async {
    try {
      await job();
      if (mounted) setState(() => _error = '');
      _reload();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _roleName(BuildContext c, String role) => role == 'org_admin'
      ? c.tr('roleAdmin')
      : role == 'referee'
          ? c.tr('roleReferee')
          : c.tr('roleViewerShort');

  Future<void> _addDialog() async {
    final user = TextEditingController();
    final pass = TextEditingController();
    var role = 'referee';
    var sport = 'football';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setL) => AlertDialog(
          title: Text(ctx.tr('userAdd')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: user,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: ctx.tr('usernameLabel'))),
              const SizedBox(height: 10),
              TextField(
                  controller: pass,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: ctx.tr('passwordLabel'))),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: role,
                decoration: InputDecoration(labelText: ctx.tr('userRole')),
                items: [
                  for (final r in ['referee', 'viewer', 'org_admin'])
                    DropdownMenuItem(value: r, child: Text(_roleName(ctx, r))),
                ],
                onChanged: (v) => setL(() => role = v ?? role),
              ),
              if (role == 'referee') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: sport,
                  decoration: InputDecoration(labelText: ctx.tr('userSport')),
                  items: [
                    for (final s in Sports.all)
                      DropdownMenuItem(value: s.id, child: Text(s.label('en'))),
                  ],
                  onChanged: (v) => setL(() => sport = v ?? sport),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('confirm'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _guard(() => _api.addMember(
          username: user.text, password: pass.text, role: role, sport: role == 'referee' ? sport : null));
    }
  }

  Future<void> _roleDialog(Map<String, dynamic> m) async {
    var role = m['role'] as String;
    var sport = (m['sport'] as String?) ?? 'football';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setL) => AlertDialog(
          title: Text('${ctx.tr('userRole')} · ${m['username']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: role,
              items: [
                for (final r in ['referee', 'viewer', 'org_admin'])
                  DropdownMenuItem(value: r, child: Text(_roleName(ctx, r))),
              ],
              onChanged: (v) => setL(() => role = v ?? role),
            ),
            if (role == 'referee') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: Sports.all.any((s) => s.id == sport) ? sport : 'football',
                items: [
                  for (final s in Sports.all) DropdownMenuItem(value: s.id, child: Text(s.label('en'))),
                ],
                onChanged: (v) => setL(() => sport = v ?? sport),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('confirm'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _guard(() => _api.updateMember(
          m['id'] as String, {'role': role, if (role == 'referee') 'sport': sport}));
    }
  }

  Future<void> _passwordDialog(Map<String, dynamic> m) async {
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${ctx.tr('userResetPassword')} · ${m['username']}'),
        content: TextField(
            controller: pass,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: ctx.tr('passwordLabel'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('confirm'))),
        ],
      ),
    );
    if (ok == true) await _guard(() => _api.updateMember(m['id'] as String, {'password': pass.text}));
  }

  Future<void> _removeDialog(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('userRemove')),
        content: Text('${m['username']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('confirm'))),
        ],
      ),
    );
    if (ok == true) await _guard(() => _api.removeMember(m['id'] as String));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('usersTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDialog,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(context.tr('userAdd')),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final e = snap.error;
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(e is ApiException ? e.message : '$e', textAlign: TextAlign.center),
            ));
          }
          final list = snap.data ?? [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            children: [
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error, style: const TextStyle(color: AppColors.danger)),
                ),
              for (final m in list)
                Card(
                  child: ListTile(
                    leading: Icon(
                        m['role'] == 'org_admin'
                            ? Icons.admin_panel_settings_rounded
                            : m['role'] == 'referee'
                                ? Icons.sports_rounded
                                : Icons.visibility_rounded,
                        color: m['status'] == 'blocked' ? AppColors.danger : AppColors.primary),
                    title: Text('${m['username']}'),
                    subtitle: Text(
                        '${_roleName(context, m['role'] as String)}${m['sport'] != null ? ' · ${m['sport']}' : ''}'
                        '${m['status'] == 'blocked' ? ' · ${context.tr('userBlocked')}' : ''}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        switch (v) {
                          case 'role':
                            _roleDialog(m);
                          case 'pass':
                            _passwordDialog(m);
                          case 'block':
                            _guard(() => _api.updateMember(m['id'] as String,
                                {'status': m['status'] == 'blocked' ? 'active' : 'blocked'}));
                          case 'remove':
                            _removeDialog(m);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(value: 'role', child: Text(ctx.tr('userRole'))),
                        PopupMenuItem(value: 'pass', child: Text(ctx.tr('userResetPassword'))),
                        PopupMenuItem(
                            value: 'block',
                            child: Text(ctx.tr(m['status'] == 'blocked' ? 'userUnblock' : 'userBlock'))),
                        PopupMenuItem(value: 'remove', child: Text(ctx.tr('userRemove'))),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
