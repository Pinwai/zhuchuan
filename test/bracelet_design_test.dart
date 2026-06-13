import 'package:flutter_test/flutter_test.dart';
import 'package:zhuchuan_app/src/models/bracelet_capacity.dart';
import 'package:zhuchuan_app/src/models/bracelet_design.dart';
import 'package:zhuchuan_app/src/models/catalog_item.dart';

void main() {
  group('BraceletDesign.estimateSlotCount', () {
    test('estimates common wrist and bead sizes', () {
      expect(BraceletDesign.estimateSlotCount(21, 6), 35);
      expect(BraceletDesign.estimateSlotCount(21, 8), 26);
      expect(BraceletDesign.estimateSlotCount(21, 10), 21);
      expect(BraceletDesign.estimateSlotCount(21, 12), 17);
    });

    test('clamps unsafe wrist values', () {
      expect(BraceletDesign.estimateSlotCount(5, 8), 15);
      expect(BraceletDesign.estimateSlotCount(80, 8), 37);
    });
  });

  test('CatalogItem.nearestSize picks closest supported size', () {
    const item = CatalogItem(
      id: 'rose_quartz',
      name: '粉水晶',
      category: CatalogCategory.bead,
      material: '水晶',
      colorTags: ['粉'],
      availableSizesMm: [6, 8, 12],
      imageAsset: 'procedural://rose_quartz',
      isPlaceholder: false,
      hexColors: ['#FFFFFF'],
      texture: 'clear',
    );

    expect(item.nearestSize(10), 8);
    expect(item.nearestSize(11), 12);
  });

  test('BraceletDesign JSON round trip preserves slots', () {
    final design = BraceletDesign.empty().copyWith(
      wristCm: 18.5,
      selectedSizeMm: 10,
      slots: [
        BraceletSlot(itemId: 'clear_quartz', sizeMm: 10, isPendant: false),
        BraceletSlot(itemId: 'moon_charm', sizeMm: 12, isPendant: true),
      ],
    );

    final decoded = BraceletDesign.fromJson(design.toJson());

    expect(decoded.wristCm, 18.5);
    expect(decoded.selectedSizeMm, 10);
    expect(decoded.slots, hasLength(2));
    expect(decoded.slots.last.isPendant, isTrue);
  });

  test('BraceletCapacity counts beads and spacers but ignores pendants', () {
    const bead = CatalogItem(
      id: 'bead',
      name: '珠子',
      category: CatalogCategory.bead,
      material: '水晶',
      colorTags: ['白'],
      availableSizesMm: [10],
      imageAsset: 'procedural://bead',
      isPlaceholder: false,
      hexColors: ['#FFFFFF'],
      texture: 'clear',
    );
    const spacer = CatalogItem(
      id: 'spacer',
      name: '隔片',
      category: CatalogCategory.spacer,
      material: '銀',
      colorTags: ['銀'],
      availableSizesMm: [10],
      imageAsset: 'procedural://spacer',
      isPlaceholder: false,
      hexColors: ['#CCCCCC'],
      texture: 'metal',
    );
    const pendant = CatalogItem(
      id: 'pendant',
      name: '吊墜',
      category: CatalogCategory.pendant,
      material: '銀',
      colorTags: ['銀'],
      availableSizesMm: [12],
      imageAsset: 'procedural://pendant',
      isPlaceholder: false,
      hexColors: ['#CCCCCC'],
      texture: 'metal',
    );
    final itemById = {
      bead.id: bead,
      spacer.id: spacer,
      pendant.id: pendant,
    };
    final capacity = BraceletCapacity.fromSlots(
      wristCm: 21,
      selectedSizeMm: 10,
      slots: [
        BraceletSlot(itemId: bead.id, sizeMm: 10, isPendant: false),
        BraceletSlot(itemId: spacer.id, sizeMm: 10, isPendant: false),
        BraceletSlot(itemId: pendant.id, sizeMm: 12, isPendant: true),
      ],
      itemById: itemById,
    );

    expect(capacity.targetLengthMm, closeTo(210, 0.001));
    expect(capacity.usedLengthMm, closeTo(15.8, 0.001));
    expect(capacity.isOverfilled, isFalse);

    final sameWristDifferentFutureSize = BraceletCapacity.fromSlots(
      wristCm: 21,
      selectedSizeMm: 6,
      slots: [
        BraceletSlot(itemId: bead.id, sizeMm: 10, isPendant: false),
      ],
      itemById: itemById,
    );

    expect(sameWristDifferentFutureSize.targetLengthMm, closeTo(210, 0.001));
    expect(sameWristDifferentFutureSize.remainingCount, greaterThan(30));

    final overfilled = BraceletCapacity.fromSlots(
      wristCm: 21,
      selectedSizeMm: 10,
      slots: List.generate(
        22,
        (_) => BraceletSlot(itemId: bead.id, sizeMm: 10, isPendant: false),
      ),
      itemById: itemById,
    );

    expect(overfilled.isOverfilled, isTrue);
    expect(overfilled.overCount, 1);

    final notFullAtTwentySevenSixMm = BraceletCapacity.fromSlots(
      wristCm: 21,
      selectedSizeMm: 6,
      slots: List.generate(
        27,
        (_) => BraceletSlot(itemId: bead.id, sizeMm: 6, isPendant: false),
      ),
      itemById: itemById,
    );
    final fullAtThirtyFiveSixMm = BraceletCapacity.fromSlots(
      wristCm: 21,
      selectedSizeMm: 6,
      slots: List.generate(
        35,
        (_) => BraceletSlot(itemId: bead.id, sizeMm: 6, isPendant: false),
      ),
      itemById: itemById,
    );
    final oneTooManySixMm = BraceletCapacity.fromSlots(
      wristCm: 21,
      selectedSizeMm: 6,
      slots: List.generate(
        36,
        (_) => BraceletSlot(itemId: bead.id, sizeMm: 6, isPendant: false),
      ),
      itemById: itemById,
    );

    expect(notFullAtTwentySevenSixMm.isFull, isFalse);
    expect(notFullAtTwentySevenSixMm.remainingMm, 48);
    expect(notFullAtTwentySevenSixMm.remainingCount, 8);
    expect(fullAtThirtyFiveSixMm.isFull, isTrue);
    expect(fullAtThirtyFiveSixMm.remainingCount, 0);
    expect(oneTooManySixMm.isOverfilled, isTrue);
    expect(oneTooManySixMm.overCount, 1);

    final smallGapButNotFull = BraceletCapacity.fromSlots(
      wristCm: 21,
      selectedSizeMm: 6,
      slots: [
        ...List.generate(
          34,
          (_) => BraceletSlot(itemId: bead.id, sizeMm: 6, isPendant: false),
        ),
        BraceletSlot(itemId: spacer.id, sizeMm: 6, isPendant: false),
      ],
      itemById: itemById,
    );

    expect(smallGapButNotFull.remainingMm, greaterThan(0));
    expect(smallGapButNotFull.remainingCount, 0);
    expect(smallGapButNotFull.isFull, isFalse);
  });
}
