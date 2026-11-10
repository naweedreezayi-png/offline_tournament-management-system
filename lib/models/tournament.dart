import '../domain/standings_calculator.dart';
import 'team.dart';
import 'match_model.dart';
import 'group_model.dart';

/// `race` = single-start event (dash, swimming, cycling...): entrants are ranked
/// by time; there are no pairings.
enum TournamentType { league, knockout, race }

enum SeedingMode { manual, random, balanced }

class Tournament {
  final String id;
  String name;
  TournamentType type;

  // Knockout-specific config
  bool hasGroupStage; // true = group stage first, then knockout bracket
  SeedingMode seedingMode;

  String sport; // e.g. 'football', 'judo' — used to file the tournament into a folder
  String? password; // optional local access-lock, null = no password
  bool twoLegged; // true = double round-robin (league) or two-leg aggregate ties (knockout)

  /// Points override for league/group tables. null = use the sport's own
  /// default (see SportRules). Tournaments created before v34 are stored
  /// with 3/1/0 so their tables do not change.
  PointsRule? customPoints;

  List<Team> teams;
  List<MatchModel> matches; // used for league mode, or knockout bracket
  List<GroupModel> groups; // used when hasGroupStage == true

  DateTime createdAt;
  bool isDeleted;
  DateTime? deletedAt;

  // Final results for knockout.
  // No 3rd-place playoff and no 4th place: both semifinal losers are
  // automatically awarded joint bronze (like judo/wrestling repechage).
  String? champion;
  String? runnerUp;
  List<String> thirdPlaceTeams; // 0, 1, or 2 team ids (joint bronze)

  Tournament({
    required this.id,
    required this.name,
    required this.type,
    this.hasGroupStage = false,
    this.seedingMode = SeedingMode.random,
    this.sport = 'other',
    this.password,
    this.twoLegged = false,
    this.customPoints,
    List<Team>? teams,
    List<MatchModel>? matches,
    List<GroupModel>? groups,
    DateTime? createdAt,
    this.isDeleted = false,
    this.deletedAt,
    this.champion,
    this.runnerUp,
    List<String>? thirdPlaceTeams,
  })  : teams = teams ?? [],
        matches = matches ?? [],
        groups = groups ?? [],
        thirdPlaceTeams = thirdPlaceTeams ?? [],
        createdAt = createdAt ?? DateTime.now();

  Team? teamById(String? id) {
    if (id == null) return null;
    try {
      return teams.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Whether [match] should use the two-leg (home & away) flow. Even when
  /// the tournament is set to "Home & Away", the final is always a single
  /// match — exactly like real football finals (World Cup, Champions
  /// League, etc.).
  bool isTwoLeggedMatch(MatchModel match) {
    if (!twoLegged) return false;
    if (matches.isEmpty) return false;
    final totalRounds = matches.map((m) => m.round).reduce((a, b) => a > b ? a : b) + 1;
    final isFinal = match.round == totalRounds - 1;
    return !isFinal;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'hasGroupStage': hasGroupStage,
        'seedingMode': seedingMode.name,
        'sport': sport,
        'password': password,
        'twoLegged': twoLegged,
        'customPoints': customPoints?.toJson(),
        'teams': teams.map((t) => t.toJson()).toList(),
        'matches': matches.map((m) => m.toJson()).toList(),
        'groups': groups.map((g) => g.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'isDeleted': isDeleted,
        'deletedAt': deletedAt?.toIso8601String(),
        'champion': champion,
        'runnerUp': runnerUp,
        'thirdPlaceTeams': thirdPlaceTeams,
      };

  factory Tournament.fromJson(Map<String, dynamic> json) => Tournament(
        id: json['id'],
        name: json['name'],
        type: TournamentType.values.firstWhere((e) => e.name == json['type']),
        hasGroupStage: json['hasGroupStage'] ?? false,
        seedingMode: SeedingMode.values.firstWhere(
            (e) => e.name == (json['seedingMode'] ?? 'random'),
            orElse: () => SeedingMode.random),
        sport: json['sport'] ?? 'other',
        password: json['password'],
        twoLegged: json['twoLegged'] ?? false,
        customPoints: json['customPoints'] is Map
            ? PointsRule.fromJson(Map<String, dynamic>.from(json['customPoints'] as Map))
            : null,
        teams: (json['teams'] as List? ?? [])
            .map((t) => Team.fromJson(t))
            .toList(),
        matches: (json['matches'] as List? ?? [])
            .map((m) => MatchModel.fromJson(m))
            .toList(),
        groups: (json['groups'] as List? ?? [])
            .map((g) => GroupModel.fromJson(g))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        isDeleted: json['isDeleted'] ?? false,
        deletedAt: json['deletedAt'] != null
            ? DateTime.tryParse(json['deletedAt'])
            : null,
        champion: json['champion'],
        runnerUp: json['runnerUp'],
        thirdPlaceTeams: (json['thirdPlaceTeams'] as List? ?? []).map((e) => e as String).toList(),
      );
}
