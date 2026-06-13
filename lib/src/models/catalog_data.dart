import 'catalog_item.dart';
import 'preset.dart';

class CatalogData {
  const CatalogData({
    required this.version,
    required this.items,
    required this.presets,
  });

  final String version;
  final List<CatalogItem> items;
  final List<BraceletPreset> presets;

  Map<String, CatalogItem> get itemById {
    return {
      for (final item in items) item.id: item,
    };
  }
}
