import 'dart:js_interop';

import 'package:web/web.dart' as web;

const isFullscreenSupported = true;

Future<void> toggleFullscreen() async {
  final document = web.document;
  if (document.fullscreenElement != null) {
    await document.exitFullscreen().toDart;
    return;
  }

  final element = document.documentElement;
  if (element == null) {
    throw UnsupportedError('Fullscreen element is not available.');
  }
  await element.requestFullscreen().toDart;
}
