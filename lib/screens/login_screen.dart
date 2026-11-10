import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api_client.dart';
import '../l10n/app_strings.dart';
import '../providers/tournament_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'home_screen.dart';

/// Decides what to show after the splash: the sign-in page, or the home page when a
/// session is stored on this device (so the app also opens without a network).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.load().then((_) {
      // Offline edition: one local administrator, no server, no sign-in.
      ApiClient.instance.role = 'org_admin';
      ApiClient.instance.userId = 'local-admin';
      ApiClient.instance.baseUrl = null;
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return const HomeScreen();
  }
}

/// Everybody signs in with a username and a password. The role (administrator, referee,
/// viewer) comes from the server and decides what the app lets the person do.
class LoginScreen extends StatefulWidget {
  final VoidCallback onSignedIn;
  const LoginScreen({super.key, required this.onSignedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _federation = TextEditingController();
  bool _busy = false;
  bool _showPass = false;
  bool _createMode = false;
  String _error = '';

  ApiClient get _api => ApiClient.instance;

  @override
  void initState() {
    super.initState();
    _url.text = _api.baseUrl ?? 'http://localhost:8081';
    _user.text = _api.email ?? '';
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _federation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = context.tr('loginMissing'));
      return;
    }
    if (_createMode) {
      final ok = RegExp(r'^[^@\s]{1,64}@[^@\s]{1,255}\.[^@\s]{2,}$').hasMatch(_user.text.trim());
      if (!ok) {
        setState(() => _error = context.tr('loginBadEmail'));
        return;
      }
      if (_pass.text.length < 8) {
        setState(() => _error = context.tr('loginShortPassword'));
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final provider = context.read<TournamentProvider>();
    try {
      await _api.setBaseUrl(_url.text);
      if (_createMode) {
        await _api.register(_user.text, _pass.text, _federation.text);
      } else {
        await _api.login(_user.text, _pass.text);
      }
      _pass.clear();
      try {
        await _api.sync(provider); // load what this account may see
      } catch (_) {
        // the first synchronisation can be repeated from the server screen
      }
      if (mounted) widget.onSignedIn();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 84)),
                  const SizedBox(height: 14),
                  Text(context.tr('appName'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: dark ? const Color(0xFF6EE7B7) : AppColors.primaryDark)),
                  const SizedBox(height: 4),
                  Text(context.tr(_createMode ? 'loginCreateTitle' : 'loginTitle'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: dark ? const Color(0xFFD5F2E5) : AppColors.primaryDark, fontSize: 14)),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _url,
                            enabled: !_busy,
                            keyboardType: TextInputType.url,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                                labelText: context.tr('serverUrl'),
                                prefixIcon: const Icon(Icons.dns_outlined)),
                          ),
                          const SizedBox(height: 12),
                          if (_createMode) ...[
                            TextField(
                              controller: _federation,
                              enabled: !_busy,
                              decoration: InputDecoration(
                                  labelText: context.tr('federationName'),
                                  prefixIcon: const Icon(Icons.badge_outlined)),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: _user,
                            enabled: !_busy,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: InputDecoration(
                                labelText: context.tr('usernameLabel'),
                                prefixIcon: const Icon(Icons.person_outline)),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pass,
                            enabled: !_busy,
                            obscureText: !_showPass,
                            textDirection: TextDirection.ltr,
                            onSubmitted: (_) => _busy ? null : _submit(),
                            decoration: InputDecoration(
                              labelText: context.tr('passwordLabel'),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _showPass = !_showPass),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.5))
                                : Text(context.tr(_createMode ? 'loginCreateButton' : 'signIn')),
                          ),
                          if (_error.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(_error,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: dark ? const Color(0xFFFF9A9A) : AppColors.danger, fontWeight: FontWeight.w600)),
                          ],
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _createMode = !_createMode;
                                      _error = '';
                                    }),
                            child: Text(context.tr(_createMode ? 'loginBack' : 'loginNewFederation')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(context.tr('loginRolesNote'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, height: 1.5, color: dark ? const Color(0xFFD5F2E5) : AppColors.primaryDark)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
