import 'dart:math' as math;

class BraceletSlot {
  BraceletSlot({
    required this.itemId,
    required this.sizeMm,
    required this.isPendant,
    String? instanceId,
  }) : instanceId =
            instanceId ?? '${DateTime.now().microsecondsSinceEpoch}-$itemId';

  final String instanceId;
  final String itemId;
  final int sizeMm;
  final bool isPendant;

  BraceletSlot copyWith({
    String? itemId,
    int? sizeMm,
    bool? isPendant,
    String? instanceId,
  }) {
    return BraceletSlot(
      instanceId: instanceId ?? this.instanceId,
      itemId: itemId ?? this.itemId,
      sizeMm: sizeMm ?? this.sizeMm,
      isPendant: isPendant ?? this.isPendant,
    );
  }

  factory BraceletSlot.fromJson(Map<String, dynamic> json) {
    return BraceletSlot(
      instanceId: json['instanceId'] as String?,
      itemId: json['itemId'] as String,
      sizeMm: json['sizeMm'] as int,
      isPendant: json['isPendant'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'instanceId': instanceId,
      'itemId': itemId,
      'sizeMm': sizeMm,
      'isPendant': isPendant,
    };
  }
}

class BraceletDesign {
  BraceletDesign({
    required this.id,
    required this.title,
    required this.wristCm,
    required this.selectedSizeMm,
    required this.slots,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String title;
  final double wristCm;
  final int selectedSizeMm;
  final List<BraceletSlot> slots;
  final DateTime updatedAt;

  static const latestId = 'local-latest';

  static BraceletDesign empty() {
    return BraceletDesign(
      id: latestId,
      title: '水晶',
      wristCm: 21,
      selectedSizeMm: 6,
      slots: const [],
    );
  }

  int get regularSlotCount {
    return slots.where((slot) => !slot.isPendant).length;
  }

  int get pendantSlotCount {
    return slots.where((slot) => slot.isPendant).length;
  }

  static int estimateSlotCount(double wristCm, int sizeMm) {
    final safeWristCm =
        wristCm.isFinite ? wristCm.clamp(12.0, 30.0).toDouble() : 21.0;
    final safeSizeMm = math.max(4, sizeMm);
    final wristMm = safeWristCm * 10;
    return (wristMm / safeSizeMm).floor().clamp(10, 60).toInt();
  }

  BraceletDesign copyWith({
    String? id,
    String? title,
    double? wristCm,
    int? selectedSizeMm,
    List<BraceletSlot>? slots,
    DateTime? updatedAt,
  }) {
    return BraceletDesign(
      id: id ?? this.id,
      title: title ?? this.title,
      wristCm: wristCm ?? this.wristCm,
      selectedSizeMm: selectedSizeMm ?? this.selectedSizeMm,
      slots: slots ?? this.slots,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  factory BraceletDesign.fromJson(Map<String, dynamic> json) {
    return BraceletDesign(
      id: json['id'] as String,
      title: json['title'] as String,
      wristCm: (json['wristCm'] as num).toDouble(),
      selectedSizeMm: json['selectedSizeMm'] as int,
      slots: (json['slots'] as List<dynamic>)
          .map((value) => BraceletSlot.fromJson(value as Map<String, dynamic>))
          .toList(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'wristCm': wristCm,
      'selectedSizeMm': selectedSizeMm,
      'slots': slots.map((slot) => slot.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
