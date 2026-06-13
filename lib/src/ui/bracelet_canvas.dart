import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/bracelet_capacity.dart';
import '../models/bracelet_design.dart';
import '../models/catalog_item.dart';
import 'bead_painter.dart';
import 'drag_payload.dart';

const _ringRadiusFactor = 0.36;
const _ringStartAngle = -math.pi / 2;
const _visualBaselineSizeMm = 6;

Size braceletCanvasVisualSizeFor(
  int sizeMm,
  CatalogCategory category, {
  double? targetExtent,
}) {
  final base = switch (category) {
    CatalogCategory.bead => 16.0 + sizeMm * 2.2,
    CatalogCategory.spacer => 14.0 + sizeMm * 2.0,
    CatalogCategory.pendant => 24.0 + sizeMm * 2.6,
  };
  if (targetExtent == null || category == CatalogCategory.pendant) {
    final side = base.clamp(30.0, 60.0).toDouble();
    return Size.square(side);
  }

  if (category == CatalogCategory.spacer) {
    final tangent = (targetExtent * 0.92).clamp(7.0, 30.0);
    final radial = (targetExtent * 2.05).clamp(14.0, 58.0);
    return Size(radial.toDouble(), tangent.toDouble());
  }

  final side = (targetExtent * 0.96).clamp(12.0, 72.0);
  return Size.square(side.toDouble());
}

double _tangentExtent(Size size, CatalogCategory category) {
  return category == CatalogCategory.spacer ? size.height : size.width;
}

double _visualExtentFor(
  int sizeMm,
  CatalogCategory category,
  double targetPitch,
) {
  final lengthMm = category == CatalogCategory.spacer
      ? sizeMm * 0.46 + 1.2
      : BraceletCapacity.pitchForSize(sizeMm);
  return targetPitch * (lengthMm / _visualBaselineSizeMm);
}

class BraceletCanvas extends StatefulWidget {
  const BraceletCanvas({
    super.key,
    required this.design,
    required this.catalogById,
    required this.targetSlotCount,
    required this.onDropPayload,
    required this.onSelectSlot,
    required this.onRemoveSlot,
    required this.onMoveSlot,
    this.selectedSlotIndex,
  });

  final BraceletDesign design;
  final Map<String, CatalogItem> catalogById;
  final int targetSlotCount;
  final int? selectedSlotIndex;
  final void Function(CatalogDragPayload payload, int? ringSlot) onDropPayload;
  final ValueChanged<int?> onSelectSlot;
  final ValueChanged<int> onRemoveSlot;
  final void Function(int fromIndex, int targetRingPosition) onMoveSlot;

  @override
  State<BraceletCanvas> createState() => _BraceletCanvasState();
}

class _BraceletCanvasState extends State<BraceletCanvas> {
  final _paintKey = GlobalKey();
  final _assetImages = <String, ui.Image>{};
  final _loadingAssets = <String>{};
  int? _hoverRingSlot;
  int? _draggingSlotIndex;
  Offset? _dragLocal;
  bool _dragWillRemove = false;

  @override
  void initState() {
    super.initState();
    _loadVisibleAssetImages();
  }

  @override
  void didUpdateWidget(covariant BraceletCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.design != widget.design ||
        oldWidget.catalogById != widget.catalogById) {
      _loadVisibleAssetImages();
    }
  }

  @override
  void dispose() {
    for (final image in _assetImages.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<CatalogDragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (details) {
        setState(() {
          _hoverRingSlot = _ringSlotFromGlobal(details.offset);
        });
      },
      onLeave: (_) {
        setState(() {
          _hoverRingSlot = null;
        });
      },
      onAcceptWithDetails: (details) {
        final ringSlot = _ringSlotFromGlobal(details.offset);
        setState(() {
          _hoverRingSlot = null;
        });
        widget.onDropPayload(details.data, ringSlot);
      },
      builder: (context, candidates, rejected) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final ringSlot = _ringSlotFromLocal(details.localPosition);
            if (ringSlot == null) {
              widget.onSelectSlot(null);
              return;
            }
            widget.onSelectSlot(_originalIndexForRegularPosition(ringSlot));
          },
          onPanStart: (details) {
            final slotIndex = _slotIndexFromLocal(details.localPosition);
            if (slotIndex == null) {
              return;
            }
            final willRemove = _isRemoveDropLocal(details.localPosition);
            setState(() {
              _draggingSlotIndex = slotIndex;
              _dragLocal = details.localPosition;
              _dragWillRemove = willRemove;
              _hoverRingSlot = willRemove
                  ? null
                  : _ringInsertPositionFromLocal(details.localPosition);
            });
            widget.onSelectSlot(slotIndex);
          },
          onPanUpdate: (details) {
            if (_draggingSlotIndex == null) {
              return;
            }
            final willRemove = _isRemoveDropLocal(details.localPosition);
            setState(() {
              _dragLocal = details.localPosition;
              _dragWillRemove = willRemove;
              _hoverRingSlot = willRemove
                  ? null
                  : _ringInsertPositionFromLocal(details.localPosition);
            });
          },
          onPanCancel: _clearSlotDrag,
          onPanEnd: (_) {
            final slotIndex = _draggingSlotIndex;
            final shouldRemove = _dragWillRemove;
            final dropLocal = _dragLocal;
            final targetRingPosition = dropLocal == null || shouldRemove
                ? null
                : _ringInsertPositionFromLocal(dropLocal);
            _clearSlotDrag();
            if (slotIndex != null && shouldRemove) {
              widget.onRemoveSlot(slotIndex);
            } else if (slotIndex != null && targetRingPosition != null) {
              widget.onMoveSlot(slotIndex, targetRingPosition);
            }
          },
          child: CustomPaint(
            key: _paintKey,
            painter: _BraceletPainter(
              design: widget.design,
              catalogById: widget.catalogById,
              assetImages: Map.unmodifiable(_assetImages),
              targetSlotCount: widget.targetSlotCount,
              selectedSlotIndex: widget.selectedSlotIndex,
              hoverRingSlot: _hoverRingSlot,
              draggingSlotIndex: _draggingSlotIndex,
              dragLocal: _dragLocal,
              dragWillRemove: _dragWillRemove,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  void _clearSlotDrag() {
    if (_draggingSlotIndex == null && _dragLocal == null) {
      return;
    }
    setState(() {
      _draggingSlotIndex = null;
      _dragLocal = null;
      _dragWillRemove = false;
      _hoverRingSlot = null;
    });
  }

  void _loadVisibleAssetImages() {
    final assets = widget.design.slots
        .map((slot) => widget.catalogById[slot.itemId]?.imageAsset)
        .whereType<String>()
        .where((asset) => asset.startsWith('assets/'))
        .toSet();
    for (final asset in assets) {
      if (_assetImages.containsKey(asset) || _loadingAssets.contains(asset)) {
        continue;
      }
      _loadingAssets.add(asset);
      unawaited(_loadAssetImage(asset));
    }
  }

  Future<void> _loadAssetImage(String asset) async {
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _assetImages[asset] = frame.image;
        _loadingAssets.remove(asset);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      debugPrint('Unable to load bead asset $asset: $error');
      setState(() {
        _loadingAssets.remove(asset);
      });
    }
  }

  int? _ringSlotFromGlobal(Offset global) {
    final context = _paintKey.currentContext;
    if (context == null) {
      return null;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return null;
    }
    return _ringSlotFromLocal(box.globalToLocal(global));
  }

  int? _ringSlotFromLocal(Offset local) {
    final context = _paintKey.currentContext;
    if (context == null) {
      return null;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * _ringRadiusFactor;
    final distance = (local - center).distance;
    if (distance < radius * 0.48 || distance > radius * 1.65) {
      return null;
    }
    final layout = _RingLayout.build(
      design: widget.design,
      catalogById: widget.catalogById,
      radius: radius,
      targetSlotCount: widget.targetSlotCount,
    );
    return layout.positionForLocal(local, center);
  }

  int? _ringInsertPositionFromLocal(Offset local) {
    final context = _paintKey.currentContext;
    if (context == null) {
      return null;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * _ringRadiusFactor;
    final distance = (local - center).distance;
    if (distance < radius * 0.44 || distance > radius * 1.34) {
      return null;
    }
    final layout = _RingLayout.build(
      design: widget.design,
      catalogById: widget.catalogById,
      radius: radius,
      targetSlotCount: widget.targetSlotCount,
    );
    return layout.insertPositionForLocal(local, center);
  }

  int? _slotIndexFromLocal(Offset local) {
    final context = _paintKey.currentContext;
    if (context == null) {
      return null;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * _ringRadiusFactor;
    final layout = _RingLayout.build(
      design: widget.design,
      catalogById: widget.catalogById,
      radius: radius,
      targetSlotCount: widget.targetSlotCount,
    );
    for (final entry in layout.entries) {
      final point = center +
          Offset(math.cos(entry.angle), math.sin(entry.angle)) * radius;
      final hitRadius =
          math.max(24.0, math.max(entry.size.width, entry.size.height) * 0.9);
      if ((local - point).distance <= hitRadius) {
        return entry.indexed.index;
      }
    }
    return null;
  }

  bool _isRemoveDropLocal(Offset local) {
    final context = _paintKey.currentContext;
    if (context == null) {
      return false;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return false;
    }
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * _ringRadiusFactor;
    final outsideCanvas = local.dx < -12 ||
        local.dy < -12 ||
        local.dx > size.width + 12 ||
        local.dy > size.height + 12;
    return outsideCanvas || (local - center).distance > radius * 1.26;
  }

  int? _originalIndexForRegularPosition(int ringPosition) {
    var regularPosition = 0;
    for (var i = 0; i < widget.design.slots.length; i += 1) {
      if (widget.design.slots[i].isPendant) {
        continue;
      }
      if (regularPosition == ringPosition) {
        return i;
      }
      regularPosition += 1;
    }
    return null;
  }
}

class _IndexedSlot {
  const _IndexedSlot({
    required this.index,
    required this.slot,
  });

  final int index;
  final BraceletSlot slot;
}

class _LayoutEntry {
  const _LayoutEntry({
    required this.indexed,
    required this.item,
    required this.startDistance,
    required this.centerDistance,
    required this.endDistance,
    required this.angle,
    required this.size,
  });

  final _IndexedSlot indexed;
  final CatalogItem item;
  final double startDistance;
  final double centerDistance;
  final double endDistance;
  final double angle;
  final Size size;
}

class _RingLayout {
  const _RingLayout({
    required this.entries,
    required this.radius,
    required this.circumference,
    required this.targetPitch,
    required this.usedDistance,
    required this.remainingDistance,
  });

  final List<_LayoutEntry> entries;
  final double radius;
  final double circumference;
  final double targetPitch;
  final double usedDistance;
  final double remainingDistance;

  bool get isOverfilled => remainingDistance <= 0.5 && usedDistance > 0;

  double get remainingStartAngle =>
      _ringStartAngle + usedDistance / math.max(1, radius);

  double get remainingSweep => remainingDistance / math.max(1, radius);

  static _RingLayout build({
    required BraceletDesign design,
    required Map<String, CatalogItem> catalogById,
    required double radius,
    required int targetSlotCount,
  }) {
    return buildFromIndexedSlots(
      indexedSlots: [
        for (var i = 0; i < design.slots.length; i += 1)
          _IndexedSlot(index: i, slot: design.slots[i]),
      ],
      catalogById: catalogById,
      radius: radius,
      targetSlotCount: targetSlotCount,
    );
  }

  static _RingLayout buildFromIndexedSlots({
    required List<_IndexedSlot> indexedSlots,
    required Map<String, CatalogItem> catalogById,
    required double radius,
    required int targetSlotCount,
  }) {
    final regularSlots = indexedSlots
        .where((indexed) => !indexed.slot.isPendant)
        .toList(growable: false);
    final circumference = math.pi * 2 * radius;
    final targetPitch = circumference / math.max(1, targetSlotCount);
    final rawEntries = <({
      double extent,
      _IndexedSlot indexed,
      CatalogItem item,
      Size size
    })>[];
    var rawTotal = 0.0;
    for (final indexed in regularSlots) {
      final item = catalogById[indexed.slot.itemId];
      if (item == null) {
        continue;
      }
      final extent = _visualExtentFor(
        indexed.slot.sizeMm,
        item.category,
        targetPitch,
      );
      final size = braceletCanvasVisualSizeFor(
        indexed.slot.sizeMm,
        item.category,
        targetExtent: extent,
      );
      rawTotal += extent;
      rawEntries
          .add((extent: extent, indexed: indexed, item: item, size: size));
    }

    final fitScale = rawTotal > circumference && rawTotal > 0
        ? circumference / rawTotal
        : 1.0;
    final entries = <_LayoutEntry>[];
    var cursor = 0.0;
    for (final raw in rawEntries) {
      final extent = raw.extent * fitScale;
      final size = Size(raw.size.width * fitScale, raw.size.height * fitScale);
      final centerDistance = cursor + extent / 2;
      entries.add(
        _LayoutEntry(
          indexed: raw.indexed,
          item: raw.item,
          startDistance: cursor,
          centerDistance: centerDistance,
          endDistance: cursor + extent,
          angle: _ringStartAngle + centerDistance / radius,
          size: size,
        ),
      );
      cursor += extent;
    }

    return _RingLayout(
      entries: entries,
      radius: radius,
      circumference: circumference,
      targetPitch: targetPitch,
      usedDistance: cursor,
      remainingDistance: math.max(0, circumference - cursor),
    );
  }

  int? positionForLocal(Offset local, Offset center) {
    if (entries.isEmpty) {
      return 0;
    }
    final distance = _distanceForLocal(local, center);
    for (var i = 0; i < entries.length; i += 1) {
      final entry = entries[i];
      final pad =
          math.max(4, _tangentExtent(entry.size, entry.item.category) * 0.18);
      if (distance >= entry.startDistance - pad &&
          distance <= entry.endDistance + pad) {
        return i;
      }
    }
    return entries.length;
  }

  int insertPositionForLocal(Offset local, Offset center) {
    if (entries.isEmpty) {
      return 0;
    }
    final distance = _distanceForLocal(local, center);
    for (var i = 0; i < entries.length; i += 1) {
      if (distance < entries[i].centerDistance) {
        return i;
      }
    }
    return entries.length;
  }

  double _distanceForLocal(Offset local, Offset center) {
    final rawAngle = math.atan2(local.dy - center.dy, local.dx - center.dx);
    return ((rawAngle - _ringStartAngle + math.pi * 2) % (math.pi * 2)) *
        radius;
  }

  Offset pointForPosition(Offset center, int position) {
    if (entries.isEmpty) {
      return center +
          Offset(math.cos(_ringStartAngle), math.sin(_ringStartAngle)) * radius;
    }
    if (position >= 0 && position < entries.length) {
      final angle = entries[position].angle;
      return center + Offset(math.cos(angle), math.sin(angle)) * radius;
    }
    final distance = math.min(circumference, usedDistance + targetPitch / 2);
    final angle = _ringStartAngle + distance / radius;
    return center + Offset(math.cos(angle), math.sin(angle)) * radius;
  }
}

class _BraceletPainter extends CustomPainter {
  const _BraceletPainter({
    required this.design,
    required this.catalogById,
    required this.assetImages,
    required this.targetSlotCount,
    required this.selectedSlotIndex,
    required this.hoverRingSlot,
    required this.draggingSlotIndex,
    required this.dragLocal,
    required this.dragWillRemove,
  });

  final BraceletDesign design;
  final Map<String, CatalogItem> catalogById;
  final Map<String, ui.Image> assetImages;
  final int targetSlotCount;
  final int? selectedSlotIndex;
  final int? hoverRingSlot;
  final int? draggingSlotIndex;
  final Offset? dragLocal;
  final bool dragWillRemove;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * _ringRadiusFactor;
    final previewSlots = _previewIndexedSlots();
    final pendantSlots = <_IndexedSlot>[];
    final displaySlots = previewSlots ??
        [
          for (var i = 0; i < design.slots.length; i += 1)
            _IndexedSlot(index: i, slot: design.slots[i]),
        ];
    for (final indexed in displaySlots) {
      if (indexed.slot.isPendant) {
        pendantSlots.add(indexed);
      }
    }
    final layout = _RingLayout.buildFromIndexedSlots(
      indexedSlots: displaySlots,
      catalogById: catalogById,
      radius: radius,
      targetSlotCount: targetSlotCount,
    );
    final hoverSlot = previewSlots == null
        ? hoverRingSlot
        : _adjustedRingPositionForDrag(hoverRingSlot);

    _drawBackground(canvas, size, center, radius);
    if (layout.entries.isEmpty) {
      _drawEmptySlots(canvas, center, radius, targetSlotCount);
    } else {
      _drawRemainingGap(canvas, center, radius, layout);
    }
    if (hoverSlot != null) {
      _drawHover(canvas, center, layout, hoverSlot);
    }

    for (final entry in layout.entries) {
      final indexed = entry.indexed;
      final item = entry.item;
      final isDragging = draggingSlotIndex == indexed.index;
      final angle = entry.angle;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      _drawItem(
        canvas,
        item,
        indexed.slot.sizeMm,
        Rect.fromCenter(
          center: point,
          width: entry.size.width,
          height: entry.size.height,
        ),
        selected: selectedSlotIndex == indexed.index || isDragging,
        rotationRadians: item.category == CatalogCategory.spacer ? angle : 0,
        opacity: isDragging && dragLocal != null ? 0.2 : 1,
      );
    }

    for (var i = 0; i < pendantSlots.length; i += 1) {
      final indexed = pendantSlots[i];
      final item = catalogById[indexed.slot.itemId];
      if (item == null) {
        continue;
      }
      final xOffset = (i - (pendantSlots.length - 1) / 2) * 36;
      final anchor = center + Offset(xOffset, radius + 6);
      final side = braceletCanvasVisualSizeFor(
            indexed.slot.sizeMm,
            item.category,
          ).width *
          1.18;
      final rect = Rect.fromCenter(
        center: anchor + Offset(0, side * 0.52),
        width: side,
        height: side,
      );
      canvas.drawLine(
        anchor,
        rect.topCenter + const Offset(0, 4),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.42)
          ..strokeWidth = 1.4,
      );
      _drawItem(
        canvas,
        item,
        indexed.slot.sizeMm,
        rect,
        selected: selectedSlotIndex == indexed.index,
      );
    }

    final dragPoint = dragLocal;
    if (dragPoint != null && draggingSlotIndex != null) {
      _drawRemoveDragHint(canvas, center, dragPoint, dragWillRemove);
      _drawDragPreview(canvas, layout, dragPoint, draggingSlotIndex!);
    }
  }

  List<_IndexedSlot>? _previewIndexedSlots() {
    final draggedIndex = draggingSlotIndex;
    final targetPosition = hoverRingSlot;
    if (draggedIndex == null ||
        targetPosition == null ||
        dragLocal == null ||
        dragWillRemove ||
        draggedIndex < 0 ||
        draggedIndex >= design.slots.length ||
        design.slots[draggedIndex].isPendant) {
      return null;
    }

    final slots = [
      for (var i = 0; i < design.slots.length; i += 1)
        _IndexedSlot(index: i, slot: design.slots[i]),
    ];
    final sourceRingPosition =
        _regularPositionForOriginalIndex(slots, draggedIndex);
    if (sourceRingPosition == null) {
      return null;
    }

    var insertRingPosition = targetPosition;
    if (sourceRingPosition < targetPosition) {
      insertRingPosition -= 1;
    }

    final fromIndex = slots.indexWhere((slot) => slot.index == draggedIndex);
    if (fromIndex == -1) {
      return null;
    }
    final movingSlot = slots.removeAt(fromIndex);
    final insertAt = _insertIndexForRegularPosition(slots, insertRingPosition);
    slots.insert(insertAt, movingSlot);
    return slots;
  }

  int? _adjustedRingPositionForDrag(int? position) {
    final draggedIndex = draggingSlotIndex;
    if (position == null || draggedIndex == null) {
      return position;
    }
    final sourceRingPosition = _regularPositionForOriginalIndex(
      [
        for (var i = 0; i < design.slots.length; i += 1)
          _IndexedSlot(index: i, slot: design.slots[i]),
      ],
      draggedIndex,
    );
    if (sourceRingPosition == null) {
      return position;
    }
    return sourceRingPosition < position ? position - 1 : position;
  }

  int _insertIndexForRegularPosition(
    List<_IndexedSlot> slots,
    int? position,
  ) {
    if (position == null) {
      return _insertIndexBeforePendants(slots);
    }
    var regularPosition = 0;
    for (var i = 0; i < slots.length; i += 1) {
      if (slots[i].slot.isPendant) {
        return i;
      }
      if (regularPosition >= position) {
        return i;
      }
      regularPosition += 1;
    }
    return slots.length;
  }

  int _insertIndexBeforePendants(List<_IndexedSlot> slots) {
    final index = slots.indexWhere((slot) => slot.slot.isPendant);
    return index == -1 ? slots.length : index;
  }

  int? _regularPositionForOriginalIndex(
    List<_IndexedSlot> slots,
    int originalIndex,
  ) {
    var regularPosition = 0;
    for (final indexed in slots) {
      if (indexed.slot.isPendant) {
        continue;
      }
      if (indexed.index == originalIndex) {
        return regularPosition;
      }
      regularPosition += 1;
    }
    return null;
  }

  void _drawBackground(Canvas canvas, Size size, Offset center, double radius) {
    final outerRect = Rect.fromCircle(center: center, radius: radius * 1.36);
    canvas.drawCircle(
      center,
      radius * 1.36,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF2A2D31).withValues(alpha: 0.9),
            const Color(0xFF1A1B1E),
            const Color(0xFF111214),
          ],
        ).createShader(outerRect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.08),
    );
    canvas.drawCircle(
      center,
      radius * 0.56,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.04),
    );
  }

  void _drawEmptySlots(
    Canvas canvas,
    Offset center,
    double radius,
    int ringCount,
  ) {
    for (var i = 0; i < ringCount; i += 1) {
      final angle = -math.pi / 2 + i * math.pi * 2 / ringCount;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        point,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.1),
      );
    }
  }

  void _drawHover(
    Canvas canvas,
    Offset center,
    _RingLayout layout,
    int slot,
  ) {
    final point = layout.pointForPosition(center, slot);
    canvas.drawCircle(
      point,
      24,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF52A8FF).withValues(alpha: 0.9),
    );
  }

  void _drawRemoveDragHint(
    Canvas canvas,
    Offset center,
    Offset dragPoint,
    bool willRemove,
  ) {
    final color = willRemove
        ? const Color(0xFFFF5A66)
        : Colors.white.withValues(alpha: 0.45);
    canvas.drawLine(
      center,
      dragPoint,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: willRemove ? 0.32 : 0.16),
    );
    canvas.drawCircle(
      dragPoint,
      willRemove ? 24 : 18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = willRemove ? 2.4 : 1.6
        ..color = color,
    );
    if (willRemove) {
      canvas.drawLine(
        dragPoint + const Offset(-7, -7),
        dragPoint + const Offset(7, 7),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      canvas.drawLine(
        dragPoint + const Offset(7, -7),
        dragPoint + const Offset(-7, 7),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  void _drawDragPreview(
    Canvas canvas,
    _RingLayout layout,
    Offset dragPoint,
    int slotIndex,
  ) {
    for (final entry in layout.entries) {
      if (entry.indexed.index != slotIndex) {
        continue;
      }
      final previewSize = Size(
        entry.size.width * 1.08,
        entry.size.height * 1.08,
      );
      _drawItem(
        canvas,
        entry.item,
        entry.indexed.slot.sizeMm,
        Rect.fromCenter(
          center: dragPoint,
          width: previewSize.width,
          height: previewSize.height,
        ),
        selected: true,
        rotationRadians:
            entry.item.category == CatalogCategory.spacer ? entry.angle : 0,
      );
      return;
    }
  }

  void _drawRemainingGap(
    Canvas canvas,
    Offset center,
    double radius,
    _RingLayout layout,
  ) {
    if (layout.remainingDistance <= layout.targetPitch * 0.28) {
      return;
    }
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      layout.remainingStartAngle,
      layout.remainingSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5
        ..color = const Color(0xFF52A8FF).withValues(alpha: 0.38),
    );

    final count = (layout.remainingDistance / layout.targetPitch).floor();
    for (var i = 0; i < count; i += 1) {
      final distance = layout.usedDistance + layout.targetPitch * (i + 0.5);
      if (distance >= layout.circumference) {
        break;
      }
      final angle = _ringStartAngle + distance / radius;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        point,
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF52A8FF).withValues(alpha: 0.5),
      );
    }
  }

  void _drawItem(
    Canvas canvas,
    CatalogItem item,
    int sizeMm,
    Rect rect, {
    required bool selected,
    double rotationRadians = 0,
    double opacity = 1,
  }) {
    if (opacity < 1) {
      canvas.saveLayer(
        rect.inflate(10),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    if (rotationRadians != 0) {
      canvas.rotate(rotationRadians);
    }
    canvas.translate(-rect.width / 2, -rect.height / 2);
    BeadVisualPainter(
      item: item,
      sizeMm: sizeMm,
      selected: selected,
      showShadow: true,
      sourceImage: item.imageAsset.startsWith('assets/')
          ? assetImages[item.imageAsset]
          : null,
      visualPaddingFactor: item.category == CatalogCategory.bead ? 0.02 : 0.04,
    ).paint(canvas, rect.size);
    canvas.restore();
    if (opacity < 1) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BraceletPainter oldDelegate) {
    return oldDelegate.design != design ||
        oldDelegate.catalogById != catalogById ||
        oldDelegate.assetImages != assetImages ||
        oldDelegate.targetSlotCount != targetSlotCount ||
        oldDelegate.selectedSlotIndex != selectedSlotIndex ||
        oldDelegate.hoverRingSlot != hoverRingSlot ||
        oldDelegate.draggingSlotIndex != draggingSlotIndex ||
        oldDelegate.dragLocal != dragLocal ||
        oldDelegate.dragWillRemove != dragWillRemove;
  }
}
