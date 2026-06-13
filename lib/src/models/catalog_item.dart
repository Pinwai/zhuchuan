enum CatalogCategory {
  bead,
  spacer,
  pendant,
}

extension CatalogCategoryLabel on CatalogCategory {
  String get id {
    switch (this) {
      case CatalogCategory.bead:
        return 'bead';
      case CatalogCategory.spacer:
        return 'spacer';
      case CatalogCategory.pendant:
        return 'pendant';
    }
  }

  String get label {
    switch (this) {
      case CatalogCategory.bead:
        return '珠子';
      case CatalogCategory.spacer:
        return '隔片/配飾';
      case CatalogCategory.pendant:
        return '吊墜';
    }
  }

  static CatalogCategory fromId(String value) {
    return CatalogCategory.values.firstWhere(
      (category) => category.id == value,
      orElse: () => CatalogCategory.bead,
    );
  }
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    required this.category,
    required this.material,
    required this.colorTags,
    required this.availableSizesMm,
    required this.imageAsset,
    required this.isPlaceholder,
    required this.hexColors,
    required this.texture,
  });

  final String id;
  final String name;
  final CatalogCategory category;
  final String material;
  final List<String> colorTags;
  final List<int> availableSizesMm;
  final String imageAsset;
  final bool isPlaceholder;
  final List<String> hexColors;
  final String texture;

  bool supportsSize(int sizeMm) => availableSizesMm.contains(sizeMm);

  int nearestSize(int requestedSizeMm) {
    if (availableSizesMm.isEmpty) {
      return requestedSizeMm;
    }
    final sorted = [...availableSizesMm]..sort();
    return sorted.reduce((best, next) {
      final bestDistance = (best - requestedSizeMm).abs();
      final nextDistance = (next - requestedSizeMm).abs();
      return nextDistance < bestDistance ? next : best;
    });
  }

  CatalogItem copyWith({
    String? id,
    String? name,
    CatalogCategory? category,
    String? material,
    List<String>? colorTags,
    List<int>? availableSizesMm,
    String? imageAsset,
    bool? isPlaceholder,
    List<String>? hexColors,
    String? texture,
  }) {
    return CatalogItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      material: material ?? this.material,
      colorTags: colorTags ?? this.colorTags,
      availableSizesMm: availableSizesMm ?? this.availableSizesMm,
      imageAsset: imageAsset ?? this.imageAsset,
      isPlaceholder: isPlaceholder ?? this.isPlaceholder,
      hexColors: hexColors ?? this.hexColors,
      texture: texture ?? this.texture,
    );
  }

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    return CatalogItem(
      id: json['id'] as String,
      name: json['name'] as String,
      category: CatalogCategoryLabel.fromId(json['category'] as String),
      material: json['material'] as String,
      colorTags: (json['colorTags'] as List<dynamic>).cast<String>(),
      availableSizesMm: (json['availableSizesMm'] as List<dynamic>)
          .map((value) => value as int)
          .toList(),
      imageAsset: json['imageAsset'] as String,
      isPlaceholder: json['isPlaceholder'] as bool,
      hexColors: (json['hexColors'] as List<dynamic>).cast<String>(),
      texture: json['texture'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category.id,
      'material': material,
      'colorTags': colorTags,
      'availableSizesMm': availableSizesMm,
      'imageAsset': imageAsset,
      'isPlaceholder': isPlaceholder,
      'hexColors': hexColors,
      'texture': texture,
    };
  }
}
