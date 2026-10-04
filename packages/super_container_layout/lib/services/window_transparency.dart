import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

class WindowTransparency {
  static const channel = MethodChannel('surf_file/window_transparency');
  static Future<void>? _initialization;

  static Future<void> apply(
    double opacity, {
    WindowEffect effect = WindowEffect.transparent,
    bool dark = false,
  }) async {
    if (!Platform.isWindows) return;
    _initialization ??= Window.initialize();
    await _initialization;
    await Window.setEffect(
      effect: isSupported(effect) ? effect : WindowEffect.transparent,
      color: Colors.transparent,
      dark: dark,
    );
    await channel.invokeMethod<void>('setOpacity', {'opacity': opacity});
  }

  /// Effets de flutter_acrylic disponibles sur la plateforme courante.
  static bool isSupported(WindowEffect effect) => switch (effect) {
    WindowEffect.disabled ||
    WindowEffect.solid ||
    WindowEffect.transparent => Platform.isWindows || Platform.isLinux,
    WindowEffect.aero ||
    WindowEffect.acrylic ||
    WindowEffect.mica ||
    WindowEffect.tabbed => Platform.isWindows,
    _ => Platform.isMacOS,
  };

  static String label(WindowEffect effect) => switch (effect) {
    WindowEffect.disabled => 'Désactivé (fond par défaut)',
    WindowEffect.solid => 'Couleur unie',
    WindowEffect.transparent => 'Transparent',
    WindowEffect.aero => 'Aero (flou Windows 7)',
    WindowEffect.acrylic => 'Acrylique (Windows 10 1803+)',
    WindowEffect.mica => 'Mica (Windows 11)',
    WindowEffect.tabbed => 'Mica à onglets (Windows 11 22523+)',
    WindowEffect.titlebar => 'Barre de titre (macOS)',
    WindowEffect.selection => 'Sélection (macOS)',
    WindowEffect.menu => 'Menu (macOS)',
    WindowEffect.popover => 'Popover (macOS)',
    WindowEffect.sidebar => 'Barre latérale (macOS)',
    WindowEffect.headerView => 'En-tête (macOS)',
    WindowEffect.sheet => 'Feuille (macOS)',
    WindowEffect.windowBackground => 'Fond de fenêtre (macOS)',
    WindowEffect.hudWindow => 'HUD (macOS)',
    WindowEffect.fullScreenUI => 'Plein écran (macOS)',
    WindowEffect.toolTip => 'Info-bulle (macOS)',
    WindowEffect.contentBackground => 'Fond de contenu (macOS)',
    WindowEffect.underWindowBackground => 'Sous la fenêtre (macOS)',
    WindowEffect.underPageBackground => 'Sous la page (macOS)',
  };
}
