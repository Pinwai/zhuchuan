class BraceletPreset {
  const BraceletPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeMm,
    required this.itemIds,
  });

  final String id;
  final String name;
  final String description;
  final int sizeMm;
  final List<String> itemIds;

  factory BraceletPreset.fromJson(Map<String, dynamic> json) {
    return BraceletPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      sizeMm: json['sizeMm'] as int,
      itemIds: (json['itemIds'] as List<dynamic>).cast<String>(),
    );
  }
}
