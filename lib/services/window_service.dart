import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowService {
  static const Size compactSize = Size(420, 280);
  static const Size fullSize = Size(1000, 700);
  static const Size minSize = Size(360, 240);

  static bool _isCompact = false;
  static bool _isAlwaysOnTop = false;

  static bool get isCompact => _isCompact;
  static bool get isAlwaysOnTop => _isAlwaysOnTop;

  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static Future<void> initialize() async {
    if (!isDesktop) return;

    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: fullSize,
      minimumSize: minSize,
      center: true,
      backgroundColor: Colors.white,
      skipTaskbar: false,
      title: 'Technical Challenge',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  static Future<void> setCompactMode({bool alwaysOnTop = false}) async {
    if (!isDesktop) return;

    _isCompact = true;
    _isAlwaysOnTop = alwaysOnTop;

    // Normal window titlebar (with minimize, maximize, close buttons)
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setMinimumSize(compactSize);
    await windowManager.setSize(compactSize);
    await windowManager.setAlwaysOnTop(alwaysOnTop);
  }

  static Future<void> setFullMode() async {
    if (!isDesktop) return;

    _isCompact = false;
    _isAlwaysOnTop = false;

    await windowManager.setSkipTaskbar(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMinimumSize(minSize);
    await windowManager.setSize(fullSize);
    await windowManager.center();
  }

  static Future<void> toggleAlwaysOnTop() async {
    if (!isDesktop) return;

    _isAlwaysOnTop = !_isAlwaysOnTop;
    await windowManager.setAlwaysOnTop(_isAlwaysOnTop);
  }
}
