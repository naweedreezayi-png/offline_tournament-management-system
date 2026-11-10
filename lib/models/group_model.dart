import 'match_model.dart';

class GroupModel {
  final String id;
  String name; // e.g. "Group A"
  List<String> teamIds;
  List<MatchModel> matches;

  GroupModel({
    required this.id,
    required this.name,
    required this.teamIds,
    required this.matches,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'teamIds': teamIds,
        'matches': matches.map((m) => m.toJson()).toList(),
      };

  factory GroupModel.fromJson(Map<String, dynamic> json) => GroupModel(
        id: json['id'],
        name: json['name'],
        teamIds: List<String>.from(json['teamIds'] ?? []),
        matches: (json['matches'] as List? ?? [])
            .map((m) => MatchModel.fromJson(m))
            .toList(),
      );
}
