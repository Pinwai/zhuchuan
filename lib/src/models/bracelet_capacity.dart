import 'dart:math' as math;

import 'bracelet_design.dart';
import 'catalog_item.dart';

class BraceletCapacity {
  const BraceletCapacity({
    required this.targetLengthMm,
    required this.usedLengthMm,
    required this.selectedSizeMm,
  });

  final double targetLengthMm;
  final double usedLengthMm;
  final int selectedSizeMm;

  static const _epsilonMm = 0.001;

  double get remainingLengthMm => targetLengthMm - usedLengthMm;

  double get selectedPitchMm => pitchForSize(selectedSizeMm);

  bool get isOverfilled => remainingLengthMm < -_epsilonMm;

  bool get isFull => remainingLengthMm.abs() <= _epsilonMm;

  int get remainingCount {
    return ((math.max(0, remainingLengthMm) + _epsilonMm) / selectedPitchMm)
        .floor()
        .clamp(0, 99)
        .toInt();
  }

  int get remainingMm => math.max(0, remainingLengthMm).round();

  int get overCount {
    return ((remainingLengthMm.abs() - _epsilonMm) / selectedPitchMm)
        .ceil()
        .clamp(1, 99)
        .toInt();
  }

  static BraceletCapacity fromSlots({
    required double wristCm,
    required int selectedSizeMm,
    required List<BraceletSlot> slots,
    required Map<String, CatalogItem> itemById,
  }) {
    return BraceletCapacity(
      targetLengthMm: targetLengthForWrist(wristCm),
      usedLengthMm: usedLengthForSlots(slots, itemById),
      selectedSizeMm: selectedSizeMm,
    );
  }

  static double targetLengthForWrist(double wristCm) {
    final safeWristCm =
        wristCm.isFinite ? wristCm.clamp(12.0, 30.0).toDouble() : 21.0;
    return safeWristCm * 10;
  }

  static double pitchForSize(int sizeMm) {
    final safeSizeMm = math.max(4, sizeMm);
    return safeSizeMm.toDouble();
  }

  static double usedLengthForSlots(
    List<BraceletSlot> slots,
    Map<String, CatalogItem> itemById,
  ) {
    var usedLength = 0.0;
    for (final slot in slots) {
      usedLength += slotLength(slot, itemById);
    }
    return usedLength;
  }

  static double slotLength(
    BraceletSlot slot,
    Map<String, CatalogItem> itemById,
  ) {
    if (slot.isPendant) {
      return 0;
    }
    final item = itemById[slot.itemId];
    if (item?.category == CatalogCategory.spacer) {
      return slot.sizeMm * 0.46 + 1.2;
    }
    return pitchForSize(slot.sizeMm);
  }
}
