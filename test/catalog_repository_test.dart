import 'package:flutter_test/flutter_test.dart';
import 'package:zhuchuan_app/src/data/catalog_repository.dart';
import 'package:zhuchuan_app/src/models/catalog_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads curated catalog without generated duplicate bead variants',
      () async {
    final catalog = await const CatalogRepository().load();
    final ids = catalog.items.map((item) => item.id).toSet();
    final catalogKeys = catalog.items
        .map((item) => '${item.category.id}|${item.name}|${item.imageAsset}')
        .toSet();
    final beadCount = catalog.items
        .where((item) => item.category == CatalogCategory.bead)
        .length;
    final spacerCount = catalog.items
        .where((item) => item.category == CatalogCategory.spacer)
        .length;
    final pendantCount = catalog.items
        .where((item) => item.category == CatalogCategory.pendant)
        .length;

    expect(catalog.items, hasLength(52));
    expect(beadCount, 49);
    expect(spacerCount, 3);
    expect(pendantCount, 0);
    expect(ids, hasLength(catalog.items.length));
    expect(catalogKeys, hasLength(catalog.items.length));
    expect(
      catalog.presets.expand((preset) => preset.itemIds),
      isNot(contains('moon_charm')),
    );
    expect(
      catalog.items.any((item) => item.id.contains('_v')),
      isFalse,
    );
  });
}
