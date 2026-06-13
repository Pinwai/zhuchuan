import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/catalog_item.dart';

Color colorFromHex(String value) {
  final normalized = value.replaceFirst('#', '');
  final withAlpha = normalized.length == 6 ? 'FF$normalized' : normalized;
  return Color(int.parse(withAlpha, radix: 16));
}

List<Color> paletteFor(CatalogItem item) {
  final colors = item.hexColors.map(colorFromHex).toList();
  if (colors.length >= 3) {
    return colors;
  }
  if (colors.length == 2) {
    return [colors.first, colors.last, Colors.white];
  }
  if (colors.length == 1) {
    return [colors.first, colors.first, Colors.white];
  }
  return const [Color(0xFFECEFF4), Color(0xFF8F98A3), Colors.white];
}

class BeadSwatch extends StatelessWidget {
  const BeadSwatch({
    super.key,
    required this.item,
    required this.sizeMm,
    this.selected = false,
    this.showShadow = true,
  });

  final CatalogItem item;
  final int sizeMm;
  final bool selected;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    if (item.category == CatalogCategory.bead &&
        item.imageAsset.startsWith('assets/')) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final bead = CustomPaint(
            painter: _PhotoBeadFramePainter(showShadow: showShadow),
            foregroundPainter: _PhotoBeadSelectionPainter(selected: selected),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ClipOval(
                child: Image.asset(
                  item.imageAsset,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) {
                    return CustomPaint(
                      painter: BeadVisualPainter(
                        item: item.copyWith(
                          imageAsset: 'procedural://${item.id}',
                        ),
                        sizeMm: sizeMm,
                        showShadow: false,
                      ),
                      child: const SizedBox.expand(),
                    );
                  },
                ),
              ),
            ),
          );

          if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
            return bead;
          }
          final side = math.min(constraints.maxWidth, constraints.maxHeight);
          if (side <= 0) {
            return const SizedBox.shrink();
          }
          return Center(
            child: SizedBox.square(
              dimension: side,
              child: bead,
            ),
          );
        },
      );
    }

    return CustomPaint(
      painter: BeadVisualPainter(
        item: item,
        sizeMm: sizeMm,
        selected: selected,
        showShadow: showShadow,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class BeadVisualPainter extends CustomPainter {
  const BeadVisualPainter({
    required this.item,
    required this.sizeMm,
    this.selected = false,
    this.showShadow = true,
    this.sourceImage,
    this.visualPaddingFactor = 0.08,
  });

  final CatalogItem item;
  final int sizeMm;
  final bool selected;
  final bool showShadow;
  final ui.Image? sourceImage;
  final double visualPaddingFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final padding = side * visualPaddingFactor;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = switch (item.category) {
      CatalogCategory.spacer => Rect.fromCenter(
          center: center,
          width: math.max(1, size.width - padding * 2),
          height: math.max(1, size.height - padding * 2),
        ),
      CatalogCategory.bead || CatalogCategory.pendant => Rect.fromCenter(
          center: center,
          width: side - padding * 2,
          height: side - padding * 2,
        ),
    };

    if (showShadow) {
      _drawShadow(canvas, rect);
    }

    switch (item.category) {
      case CatalogCategory.bead:
        final image = sourceImage;
        if (image != null) {
          _drawPhotoBead(canvas, rect, image);
        } else {
          _drawRoundBead(canvas, rect);
        }
        break;
      case CatalogCategory.spacer:
        _drawSpacer(canvas, rect);
        break;
      case CatalogCategory.pendant:
        _drawPendant(canvas, rect);
        break;
    }

    if (selected) {
      canvas.drawCircle(
        rect.center,
        rect.width / 2 + 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xFF52A8FF),
      );
    }
  }

  void _drawShadow(Canvas canvas, Rect rect) {
    canvas.drawOval(
      Rect.fromCenter(
        center: rect.center + Offset(rect.width * 0.08, rect.height * 0.16),
        width: rect.width * 0.86,
        height: rect.height * 0.26,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  void _drawRoundBead(Canvas canvas, Rect rect) {
    final colors = paletteFor(item);
    final circle = Path()..addOval(rect);
    final fill = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.42, -0.52),
        radius: 1.05,
        colors: [
          colors.last.withValues(alpha: 0.96),
          colors.first.withValues(alpha: 0.98),
          colors[1].withValues(alpha: 0.98),
        ],
        stops: const [0, 0.42, 1],
      ).createShader(rect);

    canvas.drawPath(circle, fill);
    _drawTexture(canvas, rect, circle, colors);
    _drawBeadHole(canvas, rect);
    _drawGloss(canvas, rect);
  }

  void _drawPhotoBead(Canvas canvas, Rect rect, ui.Image image) {
    final circle = Path()..addOval(rect);
    final source = _coverSourceRect(
      Size(image.width.toDouble(), image.height.toDouble()),
      rect.size,
    );
    canvas.save();
    canvas.clipPath(circle);
    canvas.drawImageRect(
      image,
      source,
      rect,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, rect.width * 0.035)
        ..color = Colors.white.withValues(alpha: 0.42),
    );
    canvas.drawArc(
      rect.deflate(rect.width * 0.05),
      -0.28,
      1.35,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.03
        ..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  Rect _coverSourceRect(Size sourceSize, Size targetSize) {
    final sourceRatio = sourceSize.width / sourceSize.height;
    final targetRatio = targetSize.width / targetSize.height;
    if (sourceRatio > targetRatio) {
      final width = sourceSize.height * targetRatio;
      final left = (sourceSize.width - width) / 2;
      return Rect.fromLTWH(left, 0, width, sourceSize.height);
    }
    final height = sourceSize.width / targetRatio;
    final top = (sourceSize.height - height) / 2;
    return Rect.fromLTWH(0, top, sourceSize.width, height);
  }

  void _drawSpacer(Canvas canvas, Rect rect) {
    final colors = paletteFor(item);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: rect.center,
        width: rect.width * 0.98,
        height: rect.height * 0.76,
      ),
      Radius.circular(rect.height * 0.34),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.last, colors.first, colors[1]],
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    final channel = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: body.outerRect.center,
        width: math.max(2, body.outerRect.width * 0.16),
        height: body.outerRect.height * 0.72,
      ),
      Radius.circular(body.outerRect.width * 0.08),
    );
    canvas.drawRRect(
      channel,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.24),
            Colors.white.withValues(alpha: 0.36),
            Colors.black.withValues(alpha: 0.18),
          ],
        ).createShader(channel.outerRect),
    );
  }

  void _drawPendant(Canvas canvas, Rect rect) {
    final colors = paletteFor(item);
    final bailRect = Rect.fromCircle(
      center: rect.topCenter + Offset(0, rect.height * 0.16),
      radius: rect.width * 0.15,
    );
    canvas.drawOval(
      bailRect,
      Paint()
        ..shader = LinearGradient(
          colors: [colors.last, colors.first, colors[1]],
        ).createShader(bailRect),
    );
    canvas.drawOval(
      bailRect.deflate(rect.width * 0.06),
      Paint()..color = const Color(0xFF161719),
    );

    final body = Path();
    if (item.name.contains('愛心')) {
      final cx = rect.center.dx;
      final cy = rect.center.dy + rect.height * 0.08;
      final r = rect.width * 0.22;
      body
        ..moveTo(cx, cy + r * 1.8)
        ..cubicTo(cx - r * 2.4, cy + r * 0.4, cx - r * 1.7, cy - r, cx, cy)
        ..cubicTo(
          cx + r * 1.7,
          cy - r,
          cx + r * 2.4,
          cy + r * 0.4,
          cx,
          cy + r * 1.8,
        )
        ..close();
    } else {
      body
        ..moveTo(rect.center.dx, rect.top + rect.height * 0.24)
        ..quadraticBezierTo(
          rect.right,
          rect.center.dy,
          rect.center.dx,
          rect.bottom - rect.height * 0.08,
        )
        ..quadraticBezierTo(
          rect.left,
          rect.center.dy,
          rect.center.dx,
          rect.top + rect.height * 0.24,
        )
        ..close();
    }

    canvas.drawPath(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 1.1,
          colors: [colors.last, colors.first, colors[1]],
        ).createShader(rect),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.45),
    );
    _drawGloss(canvas, rect.deflate(rect.width * 0.12));
  }

  void _drawBeadHole(Canvas canvas, Rect rect) {
    final outer = Rect.fromCircle(
      center: rect.topCenter + Offset(0, rect.height * 0.15),
      radius: rect.width * 0.12,
    );
    canvas.drawOval(
      outer,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.white.withValues(alpha: 0.45),
          ],
        ).createShader(outer),
    );
    canvas.drawOval(
      outer.deflate(rect.width * 0.045),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final channel = Rect.fromCenter(
      center: rect.center + Offset(0, rect.height * 0.08),
      width: rect.width * 0.16,
      height: rect.height * 0.72,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(channel, Radius.circular(channel.width / 2)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.42),
            Colors.white.withValues(alpha: 0.06),
            Colors.black.withValues(alpha: 0.08),
          ],
        ).createShader(channel),
    );
  }

  void _drawGloss(Canvas canvas, Rect rect) {
    final highlight = Rect.fromLTWH(
      rect.left + rect.width * 0.2,
      rect.top + rect.height * 0.13,
      rect.width * 0.28,
      rect.height * 0.2,
    );
    canvas.drawOval(
      highlight,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    canvas.drawArc(
      rect.deflate(rect.width * 0.08),
      -0.25,
      1.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.035
        ..color = Colors.white.withValues(alpha: 0.22),
    );
  }

  void _drawTexture(
    Canvas canvas,
    Rect rect,
    Path clipPath,
    List<Color> colors,
  ) {
    canvas.save();
    canvas.clipPath(clipPath);
    final seed = item.id.hashCode.abs();
    final accent = colors.length > 2 ? colors[2] : Colors.white;
    final dark = colors[1].withValues(alpha: 0.55);

    switch (item.texture) {
      case 'speckle':
        for (var i = 0; i < 16; i += 1) {
          final angle = (seed + i * 47) % 360 * math.pi / 180;
          final distance = rect.width * (0.08 + ((seed + i * 13) % 32) / 100);
          canvas.drawCircle(
            rect.center + Offset(math.cos(angle), math.sin(angle)) * distance,
            rect.width * (0.018 + (i % 3) * 0.006),
            Paint()..color = accent.withValues(alpha: 0.65),
          );
        }
        break;
      case 'needle':
        for (var i = 0; i < 9; i += 1) {
          final y = rect.top + rect.height * (0.18 + i * 0.075);
          canvas.drawLine(
            Offset(rect.left + rect.width * 0.12, y),
            Offset(rect.right - rect.width * (0.08 + (i % 4) * 0.05), y + 8),
            Paint()
              ..color = dark
              ..strokeWidth = 1.2,
          );
        }
        break;
      case 'band':
      case 'wave':
        for (var i = 0; i < 5; i += 1) {
          final y = rect.top + rect.height * (0.24 + i * 0.12);
          final path = Path()
            ..moveTo(rect.left, y)
            ..quadraticBezierTo(
              rect.center.dx,
              y + (i.isEven ? 10 : -10),
              rect.right,
              y + (i.isEven ? -4 : 4),
            );
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = dark,
          );
        }
        break;
      case 'flash':
        final path = Path()
          ..moveTo(rect.left + rect.width * 0.1, rect.bottom)
          ..lineTo(rect.right - rect.width * 0.18, rect.top)
          ..lineTo(rect.right, rect.top + rect.height * 0.22)
          ..lineTo(rect.left + rect.width * 0.28, rect.bottom)
          ..close();
        canvas.drawPath(path, Paint()..color = accent.withValues(alpha: 0.38));
        break;
      case 'moss':
      case 'flower':
        for (var i = 0; i < 8; i += 1) {
          final x = rect.left + rect.width * (0.18 + (i % 4) * 0.18);
          final y = rect.top + rect.height * (0.28 + (i ~/ 4) * 0.24);
          canvas.drawCircle(
            Offset(x, y),
            rect.width * 0.04,
            Paint()..color = dark.withValues(alpha: 0.7),
          );
          canvas.drawCircle(
            Offset(x + rect.width * 0.05, y + rect.height * 0.03),
            rect.width * 0.025,
            Paint()..color = accent.withValues(alpha: 0.62),
          );
        }
        break;
      case 'crack':
        for (var i = 0; i < 6; i += 1) {
          final start = Offset(
            rect.left + rect.width * (0.12 + i * 0.12),
            rect.top + rect.height * ((i % 2 == 0) ? 0.18 : 0.32),
          );
          canvas.drawLine(
            start,
            start + Offset(rect.width * 0.28, rect.height * 0.26),
            Paint()
              ..color = dark.withValues(alpha: 0.75)
              ..strokeWidth = 1,
          );
        }
        break;
      case 'facet':
        for (var i = 0; i < 6; i += 1) {
          final x = rect.left + rect.width * (0.2 + i * 0.1);
          canvas.drawLine(
            Offset(x, rect.top + rect.height * 0.12),
            Offset(x + rect.width * 0.08, rect.bottom - rect.height * 0.12),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.18)
              ..strokeWidth = 1,
          );
        }
        break;
      case 'glow':
      case 'gradient':
      case 'mist':
      case 'clear':
      case 'solid':
      case 'metal':
      case 'pearl':
      default:
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BeadVisualPainter oldDelegate) {
    return oldDelegate.item != item ||
        oldDelegate.sizeMm != sizeMm ||
        oldDelegate.selected != selected ||
        oldDelegate.showShadow != showShadow ||
        oldDelegate.sourceImage != sourceImage ||
        oldDelegate.visualPaddingFactor != visualPaddingFactor;
  }
}

class _PhotoBeadFramePainter extends CustomPainter {
  const _PhotoBeadFramePainter({
    required this.showShadow,
  });

  final bool showShadow;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side - 8,
      height: side - 8,
    );
    if (showShadow) {
      canvas.drawOval(
        Rect.fromCenter(
          center: rect.center + Offset(rect.width * 0.08, rect.height * 0.16),
          width: rect.width * 0.86,
          height: rect.height * 0.26,
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.32)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PhotoBeadFramePainter oldDelegate) {
    return oldDelegate.showShadow != showShadow;
  }
}

class _PhotoBeadSelectionPainter extends CustomPainter {
  const _PhotoBeadSelectionPainter({
    required this.selected,
  });

  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side - 8,
      height: side - 8,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.32),
    );
    if (!selected) {
      return;
    }
    canvas.drawCircle(
      rect.center,
      rect.width / 2 + 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = const Color(0xFF52A8FF),
    );
  }

  @override
  bool shouldRepaint(covariant _PhotoBeadSelectionPainter oldDelegate) {
    return oldDelegate.selected != selected;
  }
}
