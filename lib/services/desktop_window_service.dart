import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// Sets up the desktop window: title, minimum size, and remembers the last
/// window size / maximised state between launches.
///
/// Only does anything on Windows, Linux and macOS. On mobile/web it is a no-op.
class DesktopWindowService with WindowListener {
  DesktopWindowService._();
  static final DesktopWindowService instance = DesktopWindowService._();

  static const Size minimumWindowSize = Size(800, 560);
  static const Size defaultWindowSize = Size(1280, 800);

  static const _kWidth = 'window_width';
  static const _kHeight = 'window_height';
  static const _kMaximized = 'window_maximized';

  Box<dynamic>? _settings;
  Timer? _saveDebounce;

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> init(Box<dynamic> settings, {required String title}) async {
    if (!isDesktop) return;
    _settings = settings;

    await windowManager.ensureInitialized();

    var size = defaultWindowSize;
    final w = (settings.get(_kWidth) as num?)?.toDouble();
    final h = (settings.get(_kHeight) as num?)?.toDouble();
    // Ignore obviously bad saved values (e.g. from a disconnected monitor).
    if (w != null && h != null && w >= 800 && h >= 560 && w <= 7680 && h <= 4320) {
      size = Size(w, h);
    }
    final wasMaximized = settings.get(_kMaximized, defaultValue: false) == true;

    final options = WindowOptions(
      size: size,
      minimumSize: minimumWindowSize,
      center: true,
      title: title.trim().isEmpty ? 'Billit' : title,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      if (wasMaximized) await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(this);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      final settings = _settings;
      if (settings == null) return;
      try {
        final maximized = await windowManager.isMaximized();
        await settings.put(_kMaximized, maximized);
        if (!maximized) {
          final size = await windowManager.getSize();
          await settings.put(_kWidth, size.width);
          await settings.put(_kHeight, size.height);
        }
      } catch (_) {
        // Remembering the window size is best-effort only.
      }
    });
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMaximize() => _scheduleSave();

  @override
  void onWindowUnmaximize() => _scheduleSave();
}
