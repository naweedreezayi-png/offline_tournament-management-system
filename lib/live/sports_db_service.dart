import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/api_client.dart';
import 'football_data_service.dart';
import 'live_models.dart';

/// Reads cricket / basketball / volleyball leagues from TheSportsDB
/// (https://www.thesportsdb.com) with its public free key — no sign-up and
/// no token. The free plan returns the latest 15 results and the next 15
/// fixtures of each league, so predictions are a rough guide only.
class SportsDbService {
  SportsDbService._();
  static final SportsDbService instance = SportsDbService._();

  static const _base = 'https://www.thesportsdb.com/api/v1/json/3';
  static const _freshFor = Duration(minutes: 10);

  /// Through our own server when signed in, otherwise straight from TheSportsDB.
  Future<dynamic> _get(String path) async {
    final api = ApiClient.instance;
    final m = RegExp(r'^/(eventspastleague|eventsnextleague)\.php\?id=(\d+)$').firstMatch(path);
    if (api.signedIn && m != null) {
      try {
        return await api.liveGet('/api/v1/live/tsdb/${m.group(1)}?id=${m.group(2)}');
      } on ApiException catch (e) {
        if (e.code == 'LIVE_RATE_LIMIT') throw LiveException(LiveErrorType.rateLimit);
        // server unreachable or provider error: try the provider directly
      }
    }
    return _direct(path);
  }

  Future<dynamic> _direct(String path) async {
    try {
      final res = await http
          .get(Uri.parse('$_base$path'), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 429) throw LiveException(LiveErrorType.rateLimit);
      throw LiveException(LiveErrorType.other, 'HTTP ${res.statusCode}');
    } on LiveException {
      rethrow;
    } on TimeoutException {
      throw LiveException(LiveErrorType.network);
    } on http.ClientException {
      throw LiveException(LiveErrorType.network);
    } catch (e) {
      throw LiveException(LiveErrorType.other, '$e');
    }
  }

  List<LiveMatch> _parse(dynamic past, dynamic next) {
    final out = <int, LiveMatch>{};
    for (final json in [past, next]) {
      final list = json is Map ? json['events'] : null;
      if (list is! List) continue;
      for (final e in list) {
        final m = SportsDbParser.parse(e);
        if (m == null || m.status == 'SKIPPED') continue;
        out[m.id != 0 ? m.id : out.length + 1000000] = m;
      }
    }
    return out.values.toList();
  }

  /// Loads results + fixtures for league [id] (10-minute cache, offline copy
  /// shown when the network fails).
  Future<LiveCompetitionData> load(String id, {bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'tsdb_cache_$id';
    Map<String, dynamic>? cached;
    try {
      final raw = prefs.getString(key);
      if (raw != null) cached = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}

    LiveCompetitionData fromCached(Map<String, dynamic> c) => LiveCompetitionData(
          _parse(c['p'], c['n']),
          const [],
          true,
          DateTime.tryParse('${c['t']}') ?? DateTime.now(),
        );

    if (cached != null && !force) {
      final t = DateTime.tryParse('${cached['t']}');
      if (t != null && DateTime.now().difference(t) < _freshFor) return fromCached(cached);
    }
    try {
      final past = await _get('/eventspastleague.php?id=$id');
      dynamic next;
      try {
        next = await _get('/eventsnextleague.php?id=$id');
      } on LiveException {
        next = null; // fixtures are optional
      }
      final now = DateTime.now();
      try {
        await prefs.setString(key, jsonEncode({'t': now.toIso8601String(), 'p': past, 'n': next}));
      } catch (_) {}
      return LiveCompetitionData(_parse(past, next), const [], false, now);
    } on LiveException catch (e) {
      if (cached != null && (e.type == LiveErrorType.network || e.type == LiveErrorType.rateLimit)) {
        return fromCached(cached);
      }
      rethrow;
    }
  }
}
