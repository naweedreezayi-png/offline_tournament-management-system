class MatchModel {
  final String id;
  String? teamAId;
  String? teamBId;
  int? scoreA; // leg 1 score (or the only score, for single-match ties)
  int? scoreB;
  int? scoreA2; // leg 2 score (two-legged ties only)
  int? scoreB2;
  int? penA; // penalty shootout score, only used if aggregate is tied
  int? penB;
  bool isPlayed; // true once the tie is fully decided (winner known)
  int round; // 0 = first round / round of X, increasing towards final
  int order; // position within round, used to link to next match
  String? winnerId;
  bool isBye; // true if this "match" is an automatic walkover
  bool isThirdPlaceMatch; // unused (kept for backward compatibility)
  DateTime? scheduledAt;

  /// JSON with the detailed, sport-specific result (see SportScoring), or null.
  String? detail;

  MatchModel({
    required this.id,
    this.teamAId,
    this.teamBId,
    this.scoreA,
    this.scoreB,
    this.scoreA2,
    this.scoreB2,
    this.penA,
    this.penB,
    this.isPlayed = false,
    required this.round,
    required this.order,
    this.winnerId,
    this.isBye = false,
    this.isThirdPlaceMatch = false,
    this.scheduledAt,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'teamAId': teamAId,
        'teamBId': teamBId,
        'scoreA': scoreA,
        'scoreB': scoreB,
        'scoreA2': scoreA2,
        'scoreB2': scoreB2,
        'penA': penA,
        'penB': penB,
        'isPlayed': isPlayed,
        'round': round,
        'order': order,
        'winnerId': winnerId,
        'isBye': isBye,
        'isThirdPlaceMatch': isThirdPlaceMatch,
        'scheduledAt': scheduledAt?.toIso8601String(),
        'detail': detail,
      };

  MatchModel clone() => MatchModel(
        id: id,
        teamAId: teamAId,
        teamBId: teamBId,
        scoreA: scoreA,
        scoreB: scoreB,
        scoreA2: scoreA2,
        scoreB2: scoreB2,
        penA: penA,
        penB: penB,
        isPlayed: isPlayed,
        round: round,
        order: order,
        winnerId: winnerId,
        isBye: isBye,
        isThirdPlaceMatch: isThirdPlaceMatch,
        scheduledAt: scheduledAt,
        detail: detail,
      );

  factory MatchModel.fromJson(Map<String, dynamic> json) => MatchModel(
        id: json['id'],
        teamAId: json['teamAId'],
        teamBId: json['teamBId'],
        scoreA: json['scoreA'],
        scoreB: json['scoreB'],
        scoreA2: json['scoreA2'],
        scoreB2: json['scoreB2'],
        penA: json['penA'],
        penB: json['penB'],
        isPlayed: json['isPlayed'] ?? false,
        round: json['round'] ?? 0,
        order: json['order'] ?? 0,
        winnerId: json['winnerId'],
        isBye: json['isBye'] ?? false,
        isThirdPlaceMatch: json['isThirdPlaceMatch'] ?? false,
        scheduledAt: json['scheduledAt'] != null
            ? DateTime.tryParse(json['scheduledAt'])
            : null,
        detail: json['detail'] as String?,
      );
}
