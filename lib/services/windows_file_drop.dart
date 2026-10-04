import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum WindowsDropKind { entered, updated, exited, drop, error }

class WindowsDropEvent {
  const WindowsDropEvent(
    this.kind, {
    this.position = Offset.zero,
    this.paths = const [],
    this.error,
  });

  final WindowsDropKind kind;
  final Offset position;
  final List<String> paths;
  final String? error;
}

class WindowsFileDrop {
  const WindowsFileDrop._();

  static const channel = MethodChannel('surf_file/external_drop');
  static final events = ValueNotifier<WindowsDropEvent?>(null);
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      final kind = WindowsDropKind.values.byName(call.method);
      switch (kind) {
        case WindowsDropKind.entered:
        case WindowsDropKind.updated:
          final coordinates = call.arguments;
          if (coordinates is! List ||
              coordinates.length != 2 ||
              coordinates.any((value) => value is! num)) {
            throw const FormatException('Coordonnées de dépôt invalides.');
          }
          events.value = WindowsDropEvent(
            kind,
            position: Offset(
              (coordinates[0] as num).toDouble(),
              (coordinates[1] as num).toDouble(),
            ),
          );
        case WindowsDropKind.drop:
          final payload = call.arguments;
          if (payload is! Map ||
              payload['x'] is! num ||
              payload['y'] is! num ||
              payload['paths'] is! List) {
            throw const FormatException('Dépôt de fichiers invalide.');
          }
          events.value = WindowsDropEvent(
            kind,
            position: Offset(
              (payload['x'] as num).toDouble(),
              (payload['y'] as num).toDouble(),
            ),
            paths: (payload['paths'] as List).cast<String>().toList(),
          );
        case WindowsDropKind.exited:
          events.value = WindowsDropEvent(kind);
        case WindowsDropKind.error:
          events.value = WindowsDropEvent(kind, error: call.arguments as String);
      }
    });
  }
}
