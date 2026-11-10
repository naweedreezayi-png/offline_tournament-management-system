import 'dart:async';
import 'dart:convert';
import '../providers/notification_center.dart';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/tournament.dart';
import '../providers/tournament_provider.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  ApiException(this.status, this.code, this.message);
  @override
  String toString() => message;
}

/// What a synchronisation did, in numbers.
String _withFieldErrors(Map json) {
  final base = json['message']?.toString() ?? 'Request failed.';
  final errs = json['errors'];
  if (errs is List && errs.isNotEmpty) {
    final parts = <String>[];
    for (final e in errs) {
      if (e is Map && e['message'] != null) parts.add(e['message'].toString());
    }
    if (parts.isNotEmpty) return parts.join('\n');
  }
  return base;
}

class SyncReport {
  int pushed = 0;
  int imported = 0;
  final List<String> conflicts = [];
  int rejected = 0;
  final List<String> notes = [];
}

/// Talks to the Tournament Master backend (see backend/server).
///
/// Offline-first: the phone database stays the working copy. Synchronisation
/// never overwrites a tournament silently:
///  - push sends only tournaments whose content changed since the last push;
///    if the server holds a newer version the server answers "conflict" and
///    nothing is overwritten on either side;
///  - pull only imports tournaments that do not exist on the phone yet.
/// The lock password hash never leaves the phone.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _kUrl = 'server_url';
  static const _kAccess = 'server_access';
  static const _kRefresh = 'server_refresh';
  static const _kEmail = 'server_email';
  static const _kRole = 'server_role';
  static const _kSport = 'server_sport';
  static const _kUid = 'server_uid';
  static const _kOwners = 'server_owners';
  static const _kState = 'server_sync_state';
  static const _kCursor = 'server_sync_cursor';

  String? baseUrl;
  String? email;
  /// org_admin, referee or viewer (as told by the server at sign-in).
  String? role;
  /// The sport a referee manages (null for admin / viewer).
  String? sport;
  String? userId;
  // tournament id -> user id of its creator (own tournaments for referees)
  Map<String, String> _owners = {};
  String? _access;
  String? _refresh;
  int _cursor = 0;
  // tournament id -> {"v": server version, "h": content hash at last sync}
  Map<String, Map<String, dynamic>> _state = {};

  bool get signedIn => _refresh != null;

  /// Viewers only read results; they never push changes.
  bool get isViewer => role == 'viewer';
  bool get isReferee => role == 'referee';
  bool get isAdmin => role == 'org_admin';

  /// May this account create a tournament of [sportId]?
  bool canCreate(String sportId) => isAdmin || (isReferee && sport == sportId);

  /// May this account change (scores, teams, rules, delete) [t]? The server enforces the same rule.
  bool canEdit(Tournament t) {
    if (isAdmin) return true;
    if (isReferee) return t.sport == sport && userId != null && _owners[t.id] == userId;
    return false;
  }

  /// Remember that the signed-in user created tournament [id].
  Future<void> claim(String id) async {
    if (userId == null) return;
    _owners[id] = userId!;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kOwners, jsonEncode(_owners));
  }

  Future<void> _rememberOwner(String id, String? owner) async {
    if (owner == null) return;
    _owners[id] = owner;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kOwners, jsonEncode(_owners));
  }

  /// May this account send changes of a tournament of [sportId] to the server?
  /// (The server enforces this too; the check only avoids pointless requests.)
  bool canPush(String sportId) {
    if (role == 'viewer') return false;
    if (role == 'referee') return sport == sportId;
    return true;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString(_kUrl);
    email = p.getString(_kEmail);
    role = p.getString(_kRole);
    sport = p.getString(_kSport);
    userId = p.getString(_kUid);
    try {
      final o = p.getString(_kOwners);
      if (o != null) _owners = Map<String, String>.from(jsonDecode(o) as Map);
    } catch (_) {
      _owners = {};
    }
    _access = p.getString(_kAccess);
    _refresh = p.getString(_kRefresh);
    _cursor = p.getInt(_kCursor) ?? 0;
    try {
      final raw = p.getString(_kState);
      if (raw != null) {
        final d = jsonDecode(raw) as Map<String, dynamic>;
        _state = {
          for (final e in d.entries) e.key: Map<String, dynamic>.from(e.value as Map)
        };
      }
    } catch (_) {
      _state = {};
    }
  }

  /// Returns a clean "scheme://host[:port]" or null when the text is not a
  /// usable address.
  static String? normalizeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    final u = Uri.tryParse(s);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) {
      return null;
    }
    return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
  }

  Future<void> setBaseUrl(String url) async {
    final n = normalizeUrl(url);
    if (n == null) {
      throw ApiException(0, 'BAD_URL', 'The server address is not valid.');
    }
    if (n != baseUrl) {
      // another server: forget the old session and sync bookkeeping
      await _clearSession();
      _state = {};
      _cursor = 0;
      await _saveState();
    }
    baseUrl = n;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, n);
  }

  Future<void> _saveTokens(Map<String, dynamic> d) async {
    _access = d['accessToken'] as String?;
    _refresh = d['refreshToken'] as String?;
    final p = await SharedPreferences.getInstance();
    if (_access != null) await p.setString(_kAccess, _access!);
    if (_refresh != null) await p.setString(_kRefresh, _refresh!);
    if (d.containsKey('role')) {
      role = d['role'] as String?;
      sport = d['sport'] as String?;
      userId = d['userId'] as String? ?? userId;
      if (userId != null) await p.setString(_kUid, userId!);
      if (role != null) await p.setString(_kRole, role!); else await p.remove(_kRole);
      if (sport != null) await p.setString(_kSport, sport!); else await p.remove(_kSport);
    }
  }

  Future<void> _clearSession() async {
    _access = null;
    _refresh = null;
    email = null;
    role = null;
    sport = null;
    userId = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kUid);
    await p.remove(_kRole);
    await p.remove(_kSport);
    await p.remove(_kAccess);
    await p.remove(_kRefresh);
    await p.remove(_kEmail);
  }

  Future<void> _saveState() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kState, jsonEncode(_state));
    await p.setInt(_kCursor, _cursor);
  }

  // ------------------------------------------------------------------ HTTP

  /// Live world-sports data relayed (and cached for 10 minutes) by our own server.
  /// Works in the browser too (no cross-origin call to the provider) and lets users
  /// without a personal football-data.org token see live football. Returns the
  /// provider's JSON. [footballToken] is only sent when the server has no token of its own.
  Future<dynamic> liveGet(String path, {String? footballToken}) async {
    final r = await _request('GET', path,
        extraHeaders: (footballToken != null && footballToken.isNotEmpty)
            ? {'X-Football-Token': footballToken}
            : null);
    return (r['data'] as Map)['payload'];
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool canRetry = true,
    Map<String, String>? extraHeaders,
  }) async {
    final base = baseUrl;
    if (base == null) {
      throw ApiException(0, 'NO_SERVER', 'Set the server address first.');
    }
    try {
      final headers = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
      if (auth && _access != null) headers['Authorization'] = 'Bearer $_access';
      if (extraHeaders != null) headers.addAll(extraHeaders);
      final uri = Uri.parse('$base$path');
      final enc = body == null ? null : jsonEncode(body);
      late http.Response res;
      switch (method) {
        case 'GET':
          res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
          break;
        case 'POST':
          res = await http.post(uri, headers: headers, body: enc ?? '{}').timeout(const Duration(seconds: 30));
          break;
        case 'PUT':
          res = await http.put(uri, headers: headers, body: enc ?? '{}').timeout(const Duration(seconds: 30));
          break;
        case 'PATCH':
          res = await http.patch(uri, headers: headers, body: enc ?? '{}').timeout(const Duration(seconds: 30));
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: headers, body: enc).timeout(const Duration(seconds: 30));
          break;
        default:
          throw ApiException(0, 'BAD_METHOD', 'Unsupported method $method.');
      }
      Map<String, dynamic> json = {};
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map) json = Map<String, dynamic>.from(d);
      } catch (_) {}
      if (res.statusCode == 401 &&
          auth &&
          canRetry &&
          _refresh != null &&
          !path.startsWith('/api/v1/auth/')) {
        if (await _refreshTokens()) {
          return _request(method, path, body: body, auth: auth, canRetry: false, extraHeaders: extraHeaders);
        }
      }
      if (json['success'] != true) {
        throw ApiException(
          res.statusCode,
          json['errorCode']?.toString() ?? 'HTTP_${res.statusCode}',
          _withFieldErrors(json),
        );
      }
      return json;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(0, 'TIMEOUT', 'The server did not answer in time.');
    } on http.ClientException {
      throw ApiException(0, 'NETWORK',
          'Cannot reach the server. Check the address, the network and that the server is running (and CORS_ORIGIN when using the web version).');
    } on FormatException {
      throw ApiException(0, 'BAD_URL', 'The server address is not valid.');
    }
  }

  Future<bool> _refreshTokens() async {
    try {
      final r = await _request('POST', '/api/v1/auth/refresh',
          body: {'refreshToken': _refresh}, auth: false);
      await _saveTokens(Map<String, dynamic>.from(r['data'] as Map));
      return true;
    } on ApiException {
      await _clearSession();
      return false;
    }
  }

  // ------------------------------------------------------------------ auth

  Future<void> login(String user, String password) async {
    final r = await _request('POST', '/api/v1/auth/login',
        body: {'username': user.trim(), 'password': password}, auth: false);
    await _saveTokens(Map<String, dynamic>.from(r['data'] as Map));
    email = user.trim(); // shown as the signed-in name
    final p = await SharedPreferences.getInstance();
    await p.setString(_kEmail, email!);
  }

  /// Self-registration: creates a VIEWER account in the federation (e-mail required).
  /// Referee and admin accounts can only be created by an administrator.
  Future<void> register(String emailAddr, String password, String displayName) async {
    final r = await _request('POST', '/api/v1/auth/register',
        body: {
          'email': emailAddr.trim(),
          'password': password,
          if (displayName.trim().isNotEmpty) 'username': displayName.trim(),
        },
        auth: false);
    await _saveTokens(Map<String, dynamic>.from(r['data'] as Map));
    email = emailAddr.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kEmail, email!);
  }

  // ----------------------------------------------------- federation tables
  // resource: venues | players | referees | finance (finance: administrator only)

  Future<List<Map<String, dynamic>>> fedList(String resource, {String? sport}) async {
    final q = sport == null ? '' : '?sport=${Uri.encodeQueryComponent(sport)}';
    final r = await _request('GET', '/api/v1/federation/$resource$q');
    return (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> fedSave(String resource, Map<String, dynamic> body, {String? id}) async {
    if (id == null) {
      await _request('POST', '/api/v1/federation/$resource', body: body);
    } else {
      await _request('PATCH', '/api/v1/federation/$resource/$id', body: body);
    }
  }

  Future<void> fedDelete(String resource, String id) async {
    await _request('DELETE', '/api/v1/federation/$resource/$id');
  }

  // ----------------------------------------------------- members (admin only)

  Future<List<Map<String, dynamic>>> members() async {
    final r = await _request('GET', '/api/v1/members');
    return (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> addMember(
      {required String username, required String password, required String role, String? sport}) async {
    await _request('POST', '/api/v1/members', body: {
      'username': username.trim(),
      'password': password,
      'role': role,
      if (role == 'referee') 'sport': sport,
    });
  }

  Future<void> updateMember(String id, Map<String, dynamic> changes) async {
    await _request('PATCH', '/api/v1/members/$id', body: changes);
  }

  Future<void> removeMember(String id) async {
    await _request('DELETE', '/api/v1/members/$id');
  }

  Future<void> logout() async {
    stopLiveUpdates();
    final token = _refresh;
    if (token != null && baseUrl != null) {
      try {
        await _request('POST', '/api/v1/auth/logout',
            body: {'refreshToken': token}, auth: false);
      } on ApiException {
        // the local session is removed in any case
      }
    }
    await _clearSession();
  }

  /// Totals computed by the server for this organisation (GET /api/v1/stats/overview).
  Future<Map<String, dynamic>> overview() async {
    final r = await _request('GET', '/api/v1/stats/overview');
    final d = r['data'];
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  Future<bool> ping() async {
    try {
      await _request('GET', '/api/v1/health', auth: false);
      return true;
    } on ApiException {
      return false;
    }
  }

  // ------------------------------------------------------------------ sync

  static String _digest(Map<String, dynamic> doc) =>
      sha1.convert(utf8.encode(jsonEncode(doc))).toString();

  static Map<String, dynamic> _docFor(Tournament t) {
    final doc = t.toJson();
    doc.remove('password'); // the lock hash stays on this phone
    return doc;
  }

  // ------------------------------------------------- live updates (SSE)
  http.Client? _sse;
  bool _sseOn = false;

  /// Keeps one Server-Sent-Events connection open; every "changed" event triggers a
  /// pull. Reconnects after 5 s when the connection drops. NOT tested on a device.
  void startLiveUpdates(TournamentProvider provider) {
    if (_sseOn || !signedIn || baseUrl == null) return;
    _sseOn = true;
    () async {
      while (_sseOn && signedIn) {
        final client = http.Client();
        _sse = client;
        try {
          final req = http.Request('GET', Uri.parse('$baseUrl/api/v1/events'))
            ..headers['Authorization'] = 'Bearer $_access'
            ..headers['Accept'] = 'text/event-stream';
          final res = await client.send(req);
          if (res.statusCode == 401) {
            try { await sync(provider); } catch (_) {} // refreshes the token
          } else if (res.statusCode == 200) {
            await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
              if (!_sseOn) break;
              if (line.startsWith('data:') && line.contains('tournaments')) {
                try {
                  await sync(provider);
                  // The server tells us only that something changed, not what.
                  NotificationCenter.instance.add('notifTournament'); // l10n key, translated when shown
                } catch (_) {}
              }
            }
          }
        } catch (_) {
          // offline or server restarting: retry below
        } finally {
          client.close();
        }
        if (_sseOn) await Future<void>.delayed(const Duration(seconds: 5));
      }
    }();
  }

  void stopLiveUpdates() {
    _sseOn = false;
    _sse?.close();
    _sse = null;
  }

  Future<SyncReport> sync(TournamentProvider provider) async {
    final report = SyncReport();
    if (!signedIn) {
      throw ApiException(401, 'NOT_SIGNED_IN', 'Sign in first.');
    }

    // 1) push what changed on the phone
    final ops = <Map<String, dynamic>>[];
    final opTournament = <String, Tournament>{};
    final opHash = <String, String>{};
    var skippedByRole = 0;
    for (final t in provider.activeTournaments) {
      if (!canPush(t.sport)) {
        skippedByRole++;
        continue;
      }
      final doc = _docFor(t);
      final h = _digest(doc);
      final known = _state[t.id];
      if (known != null && known['h'] == h) continue;
      final opId = const Uuid().v4();
      ops.add({
        'clientOperationId': opId,
        'op': 'upsert',
        'entityId': t.id,
        'baseVersion': (known?['v'] as int?) ?? 0,
        'doc': doc,
      });
      opTournament[opId] = t;
      opHash[opId] = h;
    }
    for (var i = 0; i < ops.length; i += 100) {
      final chunk = ops.sublist(i, i + 100 > ops.length ? ops.length : i + 100);
      final r = await _request('POST', '/api/v1/sync/push', body: {'operations': chunk});
      final results = (r['data']['results'] as List).cast<Map>();
      for (final res in results) {
        final opId = res['clientOperationId'] as String?;
        final t = opId == null ? null : opTournament[opId];
        final status = res['status'];
        if (t == null) continue;
        if (status == 'applied') {
          report.pushed++;
          _state[t.id] = {'v': res['version'] as int, 'h': opHash[opId]};
        } else if (status == 'conflict') {
          report.conflicts.add(t.name);
          report.notes.add('${t.name}: server has a different version; nothing was overwritten.');
        } else {
          report.rejected++;
          report.notes.add('${t.name}: ${res['reason'] ?? 'rejected'}');
        }
      }
    }

    if (skippedByRole > 0 && role != 'org_admin') {
      report.notes.add(isViewer
          ? 'Viewer account: results are read-only, nothing was sent.'
          : '$skippedByRole tournament(s) of other sports were not sent (referee: $sport only).');
    }

    // 2) pull tournaments that exist only on the server
    var guard = 0;
    while (guard++ < 50) {
      final r = await _request('GET', '/api/v1/sync/pull?since=$_cursor');
      final data = Map<String, dynamic>.from(r['data'] as Map);
      for (final c in (data['changes'] as List).cast<Map>()) {
        final id = c['entityId'] as String;
        await _rememberOwner(id, c['createdBy'] as String?);
        if (isViewer) {
          // A viewer's phone is a read-only mirror of the server: apply deletions and newer versions.
          if (c['deleted'] == true) {
            provider.deleteForever(id);
            _state.remove(id);
            continue;
          }
          if (c['doc'] is Map) {
            try {
              final t = Tournament.fromJson(Map<String, dynamic>.from(c['doc'] as Map));
              if (await provider.replaceFromServer(t)) {
                report.imported++;
                _state[t.id] = {'v': c['version'] as int, 'h': _digest(_docFor(t))};
              }
            } catch (_) {
              report.rejected++;
            }
          }
          continue;
        }
        if (c['deleted'] == true || c['doc'] is! Map) continue;
        final exists = provider.activeTournaments.any((t) => t.id == id) ||
            provider.deletedTournaments.any((t) => t.id == id);
        if (exists) continue; // never overwrite local data
        try {
          final doc = Map<String, dynamic>.from(c['doc'] as Map);
          final t = Tournament.fromJson(doc);
          if (await provider.importTournament(t)) {
            report.imported++;
            _state[t.id] = {'v': c['version'] as int, 'h': _digest(_docFor(t))};
          } else {
            report.notes.add('${t.name}: a local tournament with this name exists; not imported.');
          }
        } catch (_) {
          report.rejected++;
        }
      }
      _cursor = (data['cursor'] as int?) ?? _cursor;
      if (data['hasMore'] != true) break;
    }
    await _saveState();
    return report;
  }
}
