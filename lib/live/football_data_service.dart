import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/api_client.dart';
import '../ml/elo_rating_service.dart';
import 'live_models.dart';

enum LiveErrorType { noKey, badKey, restricted, rateLimit, network, other }

class LiveException implements Exception {
  final LiveErrorType type;
  final String detail;
  LiveException(this.type, [this.detail = '']);
  @override
  String toString() => 'LiveException($type $detail)';
}

/// Everything the UI needs for one competition.
class LiveCompetitionData {
  final List<LiveMatch> matches;
  final List<LiveStandingGroup> tables;
  final bool fromCache;
  final DateTime fetchedAt;
  LiveCompetitionData(this.matches, this.tables, this.fromCache, this.fetchedAt);

  List<LiveMatch> get upcoming =>
      matches.where((m) => m.isUpcoming || m.isLive).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  List<LiveMatch> get finished =>
      matches.where((m) => m.isFinished && m.hasScore).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
}

/// Talks to https://api.football-data.org/v4 using only dart:io (no extra
/// packages). The API token is entered by the user in the app and kept on
/// the device (SharedPreferences) — it is never hard-coded.
class FootballDataService {
  FootballDataService._();
  static final FootballDataService instance = FootballDataService._();

  static const _base = 'https://api.football-data.org/v4';
  static const _tokenPref = 'football_data_token';
  static const _freshFor = Duration(minutes: 10);

  Future<String> getToken() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getString(_tokenPref) ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> saveToken(String token) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_tokenPref, token.trim());
    } catch (_) {}
  }

  /// Through our own server when signed in (no CORS problem, shared cache, shared token);
  /// otherwise (or when the server cannot be reached) straight from the provider.
  Future<dynamic> _get(String path, String token) async {
    final api = ApiClient.instance;
    if (api.signedIn) {
      try {
        return await api.liveGet('/api/v1/live/fd$path', footballToken: token);
      } on ApiException catch (e) {
        switch (e.code) {
          case 'LIVE_NO_KEY':
            throw LiveException(LiveErrorType.noKey);
          case 'LIVE_BAD_KEY':
            throw LiveException(LiveErrorType.badKey);
          case 'LIVE_RESTRICTED':
            throw LiveException(LiveErrorType.restricted);
          case 'LIVE_RATE_LIMIT':
            throw LiveException(LiveErrorType.rateLimit);
          default:
            if (token.isEmpty) throw LiveException(LiveErrorType.network);
            // server unreachable or provider error: try the provider directly
        }
      }
    }
    return _direct(path, token);
  }

  Future<dynamic> _direct(String path, String token) async {
    try {
      final res = await http
          .get(Uri.parse('$_base$path'), headers: {'X-Auth-Token': token, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 400 || res.statusCode == 401) {
        throw LiveException(LiveErrorType.badKey);
      }
      if (res.statusCode == 403) throw LiveException(LiveErrorType.restricted);
      if (res.statusCode == 429) throw LiveException(LiveErrorType.rateLimit);
      throw LiveException(LiveErrorType.other, 'HTTP ${res.statusCode}');
    } on LiveException {
      rethrow;
    } on TimeoutException {
      throw LiveException(LiveErrorType.network);
    } on http.ClientException {
      // no connection, DNS failure, TLS problem, or (in a browser) a blocked cross-origin request
      throw LiveException(LiveErrorType.network);
    } catch (e) {
      throw LiveException(LiveErrorType.other, '$e');
    }
  }

  /// Checks a token with one lightweight request. Returns normally when the
  /// key works; throws [LiveException] otherwise.
  Future<void> validateToken(String token) async {
    await _get('/competitions', token.trim());
  }

  List<LiveMatch> _parseMatches(dynamic json) {
    final list = (json is Map ? json['matches'] : null);
    if (list is! List) return [];
    return list.map(LiveMatch.fromJson).whereType<LiveMatch>().toList();
  }

  List<LiveStandingGroup> _parseTables(dynamic json) {
    final out = <LiveStandingGroup>[];
    final st = (json is Map ? json['standings'] : null);
    if (st is! List) return out;
    for (final s in st) {
      if (s is! Map) continue;
      if (s['type'] != null && s['type'] != 'TOTAL') continue;
      final rows = (s['table'] is List ? s['table'] as List : [])
          .map(LiveStandingRow.fromJson)
          .whereType<LiveStandingRow>()
          .toList();
      if (rows.isEmpty) continue;
      out.add(LiveStandingGroup(s['group'] as String?, rows));
    }
    return out;
  }

  /// Loads matches + tables for [code]. Uses a 10-minute cache; when the
  /// network fails the last cached copy (if any) is shown instead.
  Future<LiveCompetitionData> load(String code, {bool force = false}) async {
    final token = await getToken();
    final prefs = await SharedPreferences.getInstance();
    final key = 'fd_cache_$code';
    Map<String, dynamic>? cached;
    try {
      final raw = prefs.getString(key);
      if (raw != null) cached = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}

    LiveCompetitionData fromCached(Map<String, dynamic> c) => LiveCompetitionData(
          _parseMatches(c['m']),
          _parseTables(c['s']),
          true,
          DateTime.tryParse('${c['t']}') ?? DateTime.now(),
        );

    if (cached != null && !force) {
      final t = DateTime.tryParse('${cached['t']}');
      if (t != null && DateTime.now().difference(t) < _freshFor) return fromCached(cached);
    }
    if (token.isEmpty && !ApiClient.instance.signedIn) {
      if (cached != null) return fromCached(cached);
      throw LiveException(LiveErrorType.noKey);
    }
    try {
      final m = await _get('/competitions/$code/matches', token);
      dynamic s;
      try {
        s = await _get('/competitions/$code/standings', token);
      } on LiveException catch (e) {
        if (e.type == LiveErrorType.badKey) rethrow;
        s = null; // table is optional
      }
      final now = DateTime.now();
      try {
        await prefs.setString(key, jsonEncode({'t': now.toIso8601String(), 'm': m, 's': s}));
      } catch (_) {}
      return LiveCompetitionData(_parseMatches(m), _parseTables(s), false, now);
    } on LiveException catch (e) {
      if (cached != null && (e.type == LiveErrorType.network || e.type == LiveErrorType.rateLimit)) {
        return fromCached(cached);
      }
      rethrow;
    }
  }

  /// Trains the rating model on every finished match of the competition
  /// (oldest first) and learns the home advantage from the same data.
  RatingModel trainModel(List<LiveMatch> finishedMatches,
      {SportProfile profile = SportProfiles.football, bool homeField = true}) {
    final ms = finishedMatches.where((m) => m.isFinished && m.hasScore).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    var homeScore = 0.0;
    final events = <RatingEvent>[];
    for (var i = 0; i < ms.length; i++) {
      final m = ms[i];
      final hg = m.homeGoals!, ag = m.awayGoals!;
      final res = hg == ag ? 0.5 : (hg > ag ? 1.0 : 0.0);
      homeScore += res;
      events.add(RatingEvent(
        matchId: '${m.id}',
        tournamentId: 'live',
        teamA: m.home,
        teamB: m.away,
        goalsA: hg,
        goalsB: ag,
        resultA: res,
        seq: i,
      ));
    }
    // Learned home advantage: logit of the average home "score", in Elo points.
    // Smoothed with a prior of 10 matches at 0.55 so tiny samples can't explode.
    final n = events.length;
    final p = (homeScore + 5.5) / (n + 10);
    final ha = homeField ? (400 * _log10(p / (1 - p))).clamp(0, 120).toDouble() : 0.0;
    return EloRatingService.trainFrom(events,
        homeAdvantage: ha, profile: profile);
  }

  double _log10(double x) => x <= 0 ? 0 : math.log(x) / math.ln10;
}
