import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api_client.dart';
import '../l10n/app_strings.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Connect the app to a Tournament Master server: sign in and synchronise.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _url = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _org = TextEditingController();
  bool _busy = false;
  bool _ready = false;
  String _status = '';
  bool _isError = false;
  Future<Map<String, dynamic>>? _stats;

  ApiClient get _api => ApiClient.instance;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _api.load();
    if (!mounted) return;
    setState(() {
      _url.text = _api.baseUrl ?? '';
      _email.text = _api.email ?? '';
      _ready = true;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _email.dispose();
    _pass.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() job) async {
    setState(() {
      _busy = true;
      _status = '';
      _isError = false;
    });
    try {
      final msg = await job();
      if (mounted) setState(() => _status = msg);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _status = e.message;
          _isError = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '$e';
          _isError = true;
        });
      }
    } finally {
      _stats = null; // totals are reloaded after every action (sync, sign in, sign out)
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _signIn({required bool register}) async {
    await _api.setBaseUrl(_url.text);
    if (register) {
      await _api.register(_email.text, _pass.text, _org.text);
    } else {
      await _api.login(_email.text, _pass.text);
    }
    _pass.clear();
    return '✔ ${_api.email}';
  }

  Future<String> _sync() async {
    final provider = context.read<TournamentProvider>();
    final r = await _api.sync(provider);
    final lines = <String>[
      '↑ ${r.pushed}   ↓ ${r.imported}   ⚠ ${r.conflicts.length}',
      if (r.conflicts.isNotEmpty) '⚠ ${r.conflicts.join(', ')}',
      ...r.notes,
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _ready && _api.signedIn;
    if (signedIn) {
      _stats ??= _api.overview();
    } else {
      _stats = null;
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('serverSync'))),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (signedIn && _api.role != null) ...[
                  Card(
                    child: ListTile(
                      leading: Icon(
                          _api.role == 'org_admin'
                              ? Icons.admin_panel_settings_rounded
                              : _api.role == 'referee'
                                  ? Icons.sports_rounded
                                  : Icons.visibility_rounded,
                          color: AppColors.primary),
                      title: Text(_api.role == 'org_admin'
                          ? context.tr('roleAdmin')
                          : _api.role == 'referee'
                              ? '${context.tr('roleReferee')} · ${_api.sport ?? ''}'
                              : context.tr('roleViewer')),
                      subtitle: Text(context.tr(_api.role == 'org_admin'
                          ? 'roleAdminInfo'
                          : _api.role == 'referee'
                              ? 'roleRefereeInfo'
                              : 'roleViewerInfo')),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (signedIn) ...[
                  _ServerStats(future: _stats!),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _url,
                          enabled: !_busy && !signedIn,
                          keyboardType: TextInputType.url,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: context.tr('serverUrl'),
                            prefixIcon: const Icon(Icons.dns_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!signedIn) ...[
                          TextField(
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: context.tr('usernameLabel'),
                              prefixIcon: const Icon(Icons.alternate_email),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pass,
                            enabled: !_busy,
                            obscureText: true,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: context.tr('password'),
                              prefixIcon: const Icon(Icons.lock_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _org,
                            enabled: !_busy,
                            decoration: InputDecoration(
                              labelText: context.tr('orgName'),
                              prefixIcon: const Icon(Icons.apartment_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() => _signIn(register: false)),
                                  child: Text(context.tr('signIn')),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() => _signIn(register: true)),
                                  child: Text(context.tr('createAccount')),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.verified_user_outlined),
                            title: Text(_api.email ?? ''),
                            subtitle: Text(_api.baseUrl ?? ''),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.sync),
                            label: Text(context.tr('syncNow')),
                            onPressed: _busy ? null : () => _run(_sync),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.logout),
                            label: Text(context.tr('signOut')),
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                      await _api.logout();
                                      if (mounted) {
                                        Navigator.of(context).pushAndRemoveUntil(
                                            MaterialPageRoute(builder: (_) => const AuthGate()), (r) => false);
                                      }
                                      return '';
                                    }),
                          ),
                        ],
                        if (_busy) ...[
                          const SizedBox(height: 16),
                          const LinearProgressIndicator(),
                        ],
                        if (_status.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            _status,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              color: _isError ? Colors.redAccent : Colors.greenAccent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    context.tr('syncHelp'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }
}


/// Totals from the server (tournaments, teams, matches...), loaded once when shown.
class _ServerStats extends StatelessWidget {
  final Future<Map<String, dynamic>> future;
  const _ServerStats({required this.future});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snap.hasError) {
          final e = snap.error;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(e is ApiException ? e.message : '$e',
                  style: TextStyle(color: cs.error)),
            ),
          );
        }
        final d = snap.data ?? const <String, dynamic>{};
        Widget tile(IconData icon, String label, Object? value) => Expanded(
              child: Column(
                children: [
                  Icon(icon, color: cs.secondary),
                  const SizedBox(height: 4),
                  Text('${value ?? 0}',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface)),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            );
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Row(
              children: [
                tile(Icons.emoji_events_outlined, 'Tournaments', d['tournaments']),
                tile(Icons.play_circle_outline, 'Active', d['active']),
                tile(Icons.groups_outlined, 'Teams', d['teams']),
                tile(Icons.sports_score, 'Matches', d['matches']),
                tile(Icons.event_outlined, 'Upcoming', d['upcoming']),
              ],
            ),
          ),
        );
      },
    );
  }
}
