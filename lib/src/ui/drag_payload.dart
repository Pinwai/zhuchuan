import '../models/catalog_item.dart';

class CatalogDragPayload {
  const CatalogDragPayload({
    required this.item,
    required this.sizeMm,
  });

  final CatalogItem item;
  final int sizeMm;
}
