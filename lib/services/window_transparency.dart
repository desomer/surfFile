import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

class WindowTransparency {
  static const channel = MethodChannel('surf_file/window_transparency');
  static Future<void>? _initialization;

  static Future<void> apply(double opacity) async {
    if (!Platform.isWindows) return;
    _initialization ??= Window.initialize();
    await _initialization;
    await Window.setEffect(
      effect: WindowEffect.transparent,
      color: Colors.transparent,
    );
    await channel.invokeMethod<void>('setOpacity', {'opacity': opacity});
  }
}
