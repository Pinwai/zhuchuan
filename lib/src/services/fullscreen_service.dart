import 'fullscreen_service_stub.dart'
    if (dart.library.html) 'fullscreen_service_web.dart' as platform;

class FullscreenService {
  const FullscreenService();

  bool get isSupported => platform.isFullscreenSupported;

  Future<void> toggle() => platform.toggleFullscreen();
}
