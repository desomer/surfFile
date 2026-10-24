

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/appearance.dart';
import 'appearance_codec.dart';


class AppearanceStore {
  AppearanceStore({
    this.key = 'super_container_layout.appearance',
    this.codec = const AppearanceCodec(),
  });
  final String key;
  final AppearanceCodec codec;
  static const version = 1;
  static String encode(Appearance appearance) =>
      const AppearanceCodec().encode(appearance);
  static Appearance decode(String text) => const AppearanceCodec().decode(text);
  Future<Appearance> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.get(key);
    if (stored == null) {
      codec.resetAdditional();
      return codec.defaults;
    }
    if (stored is! String) {
      throw const FormatException('Invalid stored appearance.');
    }
    // print('Stored appearance: $stored');

    // var rawJson = jsonDecode(stored);
    // final prettyJson = JsonEncoder.withIndent('  ').convert(rawJson);
    // print('Raw JSON: $prettyJson');

    final result = codec.decode(stored);
    codec.restoreAdditional(stored);
    if (codec.needsMigration(stored)) await save(result);
    return result;
  }

  Future<void> save(Appearance appearance) async {
    final encoded = codec.encode(appearance);
    await saveEncoded(encoded);
  }

  Future<void> saveEncoded(String encoded) async {
    codec.decode(encoded);
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(key, encoded)) {
      throw StateError('Appearance save failed.');
    }
  }
}

class AppearanceServicesScope extends InheritedWidget {
  const AppearanceServicesScope({
    required this.codec,
    required super.child,
    super.key,
  });
  final AppearanceCodec codec;
  static AppearanceCodec codecOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppearanceServicesScope>()
          ?.codec ??
      const AppearanceCodec();
  @override
  bool updateShouldNotify(AppearanceServicesScope oldWidget) =>
      codec != oldWidget.codec;
}

class PersistentAppearanceController extends ValueNotifier<Appearance> {
  PersistentAppearanceController(
    this.store,
    this.onSaveError, {
    this.validateAppearance,
  }) : super(store.codec.defaults) {
    store.codec.additionalPreferences?.addListener(persist);
  }
  final AppearanceStore store;
  final void Function(Object error) onSaveError;
  final void Function(Appearance appearance)? validateAppearance;
  Future<void> _pending = Future.value();
  Future<void> get saved => _pending;
  bool _restoring = false;
  Future<void> restore() async {
    _restoring = true;
    try {
      final next = await store.load();
      validateAppearance?.call(next);
      super.value = next;
    } finally {
      _restoring = false;
    }
  }

  @override
  set value(Appearance appearance) {
    final next = store.codec.prepare(appearance);
    validateAppearance?.call(next);
    super.value = next;
    persist();
  }

  void reset() {
    store.codec.resetAdditional();
    value = store.codec.defaults;
  }

  void persist() {
    if (_restoring) return;
    final String encoded;
    try {
      encoded = store.codec.encode(value);
    } catch (error) {
      onSaveError(error);
      return;
    }
    _pending = _pending.then((_) async {
      try {
        await store.saveEncoded(encoded);
      } catch (error) {
        onSaveError(error);
      }
    });
  }

  @override
  void dispose() {
    store.codec.additionalPreferences?.removeListener(persist);
    super.dispose();
  }
}
