import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/super_layout_config.dart';
import '../theme/appearance.dart';
import '../theme/container_style.dart';

/// Override this codec to retain application-owned preferences and migrations.
class AppearanceCodec {
  const AppearanceCodec();
  String get format => 'super_container_layout.appearance';
  int get schemaVersion => 1;
  Set<String> get additionalKeys => const {};
  Appearance get defaults => Appearance();
  bool needsMigration(String text) => false;
  String encode(Appearance appearance) => jsonEncode(toJson(appearance));
  Appearance decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) throw const FormatException('Invalid appearance document.');
    return fromJson(json);
  }
  Map<String, Object?> toJson(Appearance a) => {
    'version': schemaVersion,
    'mode': a.mode.name, 'accent': a.accent.toARGB32(),
    'backgroundOpacity': a.backgroundOpacity, 'windowOpacity': a.windowOpacity,
    'windowEffect': a.windowEffect.name,
    'styles': {for (final entry in a.styles.entries) entry.key: entry.value.toJson()},
    'layouts': {for (final entry in a.layouts.entries) entry.key: entry.value.toJson()},
  };
  Appearance fromJson(Map<String, dynamic> json) {
    if (json['version'] != schemaVersion) throw const FormatException('Unsupported appearance version.');
    final known = {'version', 'mode', 'accent', 'backgroundOpacity', 'windowOpacity', 'windowEffect', 'styles', 'layouts', ...additionalKeys};
    if (json.keys.any((key) => !known.contains(key))) throw const FormatException('Unknown appearance preference.');
    double number(String key, double fallback, double min, double max) {
      final value = json[key] ?? fallback;
      if (value is! num || !value.isFinite || value < min || value > max) throw FormatException('Invalid "$key".');
      return value.toDouble();
    }
    final mode = ThemeMode.values.where((v) => v.name == json['mode']).firstOrNull;
    final effect = WindowEffect.values.where((v) => v.name == (json['windowEffect'] ?? 'transparent')).firstOrNull;
    final accent = json['accent'] ?? 0xFF5268D9;
    if (mode == null || effect == null || accent is! int || accent < 0 || accent > 0xFFFFFFFF) {
      throw const FormatException('Invalid theme or window preferences.');
    }
    Map<String, dynamic> entries(String key) {
      final value = json[key];
      if (value is! Map<String, dynamic> || value.keys.any((id) => id.trim().isEmpty) ||
          value.values.any((v) => v is! Map<String, dynamic>)) {
        throw FormatException('Invalid "$key" map.');
      }
      return value;
    }
    return Appearance(
      mode: mode, accent: Color(accent),
      windowEffect: effect,
      backgroundOpacity: number('backgroundOpacity', 1, 0, 1),
      windowOpacity: number('windowOpacity', 1, .2, 1),
      styles: {for (final entry in entries('styles').entries) entry.key: ContainerStyle.fromJson(entry.value)},
      layouts: {for (final entry in entries('layouts').entries) entry.key: SuperLayoutConfig.fromJson(entry.value)},
    );
  }
  Map<String, Object?> normalizeTransfer(Map<String, dynamic> data, int version) {
    if (version != schemaVersion) throw const FormatException('Unsupported export version.');
    final known = toJson(defaults).keys.toSet()..remove('version');
    if (data.keys.any((key) => !known.contains(key))) throw const FormatException('Unknown export preference.');
    return Map<String, Object?>.from(data);
  }
  Object? mergeTransferValue(String key, Object? current, Object? imported, int sourceVersion) => imported;
}

class AppearanceStore {
  AppearanceStore({this.key = 'super_container_layout.appearance', this.codec = const AppearanceCodec()});
  final String key;
  final AppearanceCodec codec;
  static const version = 1;
  static String encode(Appearance appearance) => const AppearanceCodec().encode(appearance);
  static Appearance decode(String text) => const AppearanceCodec().decode(text);
  Future<Appearance> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.get(key);
    if (stored == null) return codec.defaults;
    if (stored is! String) throw const FormatException('Invalid stored appearance.');
    final result = codec.decode(stored);
    if (codec.needsMigration(stored)) await save(result);
    return result;
  }

  Future<void> save(Appearance appearance) async {
    final encoded = codec.encode(appearance);
    codec.decode(encoded);
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(key, encoded)) throw StateError('Appearance save failed.');
  }
}

class AppearanceServicesScope extends InheritedWidget {
  const AppearanceServicesScope({required this.codec, required super.child, super.key});
  final AppearanceCodec codec;
  static AppearanceCodec codecOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceServicesScope>()?.codec ?? const AppearanceCodec();
  @override
  bool updateShouldNotify(AppearanceServicesScope oldWidget) => codec != oldWidget.codec;
}

class PersistentAppearanceController extends ValueNotifier<Appearance> {
  PersistentAppearanceController(this.store, this.onSaveError) : super(store.codec.defaults);
  final AppearanceStore store;
  final void Function(Object error) onSaveError;
  Future<void> _pending = Future.value();
  Future<void> get saved => _pending;
  Future<void> restore() async { super.value = await store.load(); }
  @override
  set value(Appearance appearance) {
    super.value = appearance;
    _pending = _pending.then((_) async {
      try { await store.save(appearance); }
      catch (error) { onSaveError(error); }
    });
  }
}
