import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/catalog_data.dart';
import '../models/catalog_item.dart';
import '../models/preset.dart';

class CatalogRepository {
  const CatalogRepository({
    this.assetPath = 'assets/catalog.json',
  });

  final String assetPath;

  Future<CatalogData> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final baseItems = (json['items'] as List<dynamic>)
        .map((value) => CatalogItem.fromJson(value as Map<String, dynamic>))
        .toList();
    final basePresets = (json['presets'] as List<dynamic>)
        .map((value) => BraceletPreset.fromJson(value as Map<String, dynamic>))
        .toList();
    final items = _dedupeItems(baseItems);
    final itemIds = items.map((item) => item.id).toSet();
    final presets = basePresets
        .map(
          (preset) => BraceletPreset(
            id: preset.id,
            name: preset.name,
            description: preset.description,
            sizeMm: preset.sizeMm,
            itemIds: preset.itemIds.where(itemIds.contains).toList(),
          ),
        )
        .toList();

    return CatalogData(
      version: json['version'] as String,
      items: items,
      presets: presets,
    );
  }

  List<CatalogItem> _dedupeItems(List<CatalogItem> items) {
    final seenIds = <String>{};
    final seenCatalogKeys = <String>{};
    final result = <CatalogItem>[];

    for (final item in items) {
      if (item.category == CatalogCategory.pendant) {
        continue;
      }
      final catalogKey = '${item.category.id}|${item.name}|${item.imageAsset}';
      if (!seenIds.add(item.id) || !seenCatalogKeys.add(catalogKey)) {
        continue;
      }
      result.add(item);
    }

    return result;
  }
}
