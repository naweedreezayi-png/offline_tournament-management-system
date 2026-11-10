class Team {
  final String id;
  String name;
  String? imagePath; // local file path, optional

  Team({
    required this.id,
    required this.name,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imagePath': imagePath,
      };

  factory Team.fromJson(Map<String, dynamic> json) => Team(
        id: json['id'],
        name: json['name'],
        imagePath: json['imagePath'],
      );
}
