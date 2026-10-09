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

  /// Distance minimale (px logiques) entre le début du glissement et le dépôt
  /// pour qu'un glisser interne soit pris en compte.
  static const dropMargin = 24.0;

  static List<String>? _dragSources;
  static Offset? _dragOrigin;

  static Future<void> startDrag(List<String> paths, {Offset? origin}) async {
    _dragSources = paths;
    _dragOrigin = origin;
    try {
      await channel.invokeMethod<void>('startDrag', paths);
    } finally {
      _dragSources = null;
      _dragOrigin = null;
    }
  }

  static String _key(String path) {
    var value = path.replaceAll('\\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value.toLowerCase();
  }

  /// Vrai si le dépôt doit être ignoré silencieusement : glisser interne lâché
  /// trop près de son point de départ ou sur l'un des éléments glissés.
  static bool ignoresInternalDrop(Offset position, String? destination) {
    final sources = _dragSources;
    if (sources == null) return false;
    final origin = _dragOrigin;
    if (origin != null && (position - origin).distance < dropMargin) {
      return true;
    }
    if (destination == null) return false;
    final target = _key(destination);
    return sources.any((source) => _key(source) == target);
  }

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
