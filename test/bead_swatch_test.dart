import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhuchuan_app/src/models/catalog_item.dart';
import 'package:zhuchuan_app/src/ui/bead_painter.dart';

void main() {
  testWidgets('falls back to procedural bead when image asset is missing', (
    tester,
  ) async {
    const item = CatalogItem(
      id: 'missing-photo',
      name: '缺圖珠',
      category: CatalogCategory.bead,
      material: '測試',
      colorTags: ['白'],
      availableSizesMm: [6, 8, 10, 12],
      imageAsset: 'assets/does-not-exist.png',
      isPlaceholder: false,
      hexColors: ['#ECEFF4', '#AEB6C2'],
      texture: 'smooth',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 72,
              child: BeadSwatch(item: item, sizeMm: 8),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BeadSwatch), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
