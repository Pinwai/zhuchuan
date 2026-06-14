import 'package:flutter_test/flutter_test.dart';
import 'package:zhuchuan_app/src/models/catalog_item.dart';
import 'package:zhuchuan_app/src/ui/bracelet_canvas.dart';

void main() {
  test('bracelet preview keeps bead sizes visually distinct', () {
    const targetPitch = 16.0;

    final six = braceletCanvasVisualSizeFor(
      6,
      CatalogCategory.bead,
      targetExtent: targetPitch,
    );
    final eight = braceletCanvasVisualSizeFor(
      8,
      CatalogCategory.bead,
      targetExtent: targetPitch * 8 / 6,
    );
    final ten = braceletCanvasVisualSizeFor(
      10,
      CatalogCategory.bead,
      targetExtent: targetPitch * 10 / 6,
    );
    final twelve = braceletCanvasVisualSizeFor(
      12,
      CatalogCategory.bead,
      targetExtent: targetPitch * 12 / 6,
    );

    expect(eight.width, greaterThan(six.width + 4));
    expect(ten.width, greaterThan(eight.width + 4));
    expect(twelve.width, greaterThan(ten.width + 4));
  });

  test('bracelet preview keeps spacers compact on the ring tangent', () {
    const targetPitch = 16.0;
    final bead = braceletCanvasVisualSizeFor(
      6,
      CatalogCategory.bead,
      targetExtent: targetPitch,
    );
    final spacer = braceletCanvasVisualSizeFor(
      6,
      CatalogCategory.spacer,
      targetExtent: targetPitch * 0.66,
    );

    expect(spacer.height, lessThan(bead.width * 0.5));
    expect(spacer.width, lessThan(bead.width));
  });
}
