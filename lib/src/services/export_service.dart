import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

class BraceletExportResult {
  const BraceletExportResult({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

class ExportService {
  Future<BraceletExportResult> capturePng(
    GlobalKey boundaryKey, {
    String fileName = 'bracelet-design',
    double pixelRatio = 5,
  }) async {
    final context = boundaryKey.currentContext;
    if (context == null) {
      throw StateError('Export boundary is not mounted.');
    }
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Export boundary is not ready.');
    }

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List();
    if (bytes == null) {
      throw StateError('Unable to encode PNG.');
    }

    return BraceletExportResult(fileName: '$fileName.png', bytes: bytes);
  }

  Future<void> sharePng(
    BraceletExportResult result, {
    required Rect sharePositionOrigin,
  }) async {
    await Share.shareXFiles(
      [
        XFile.fromData(
          result.bytes,
          mimeType: 'image/png',
          name: result.fileName,
        ),
      ],
      text: '我的水晶手鍊設計',
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
