/// Service de persistance asynchrone ([AppearanceStore]) de l'apparence dans `SharedPreferences`.
///
/// Gère la file d'écriture sérialisée sous la clé `appearance.v1`, le contrôleur
/// persistant ([PersistentAppearanceController]) et la portée [AppearanceServicesScope].
library;

import 'dart:async' show Timer, unawaited;
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/json_numbers.dart';
import '../../theme/appearance.dart';
import 'appearance_codec.dart';


/// Service de lecture et d'écriture persistante du document d'apparence dans `SharedPreferences`.
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
    if (runtimeType == AppearanceStore) {
      await _writeEncoded(encoded);
      return;
    }
    await saveEncoded(encoded);
  }

  Future<void> saveEncoded(String encoded) async {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid appearance document.');
    }
    codec.fromJson(decoded);
    final normalized = jsonEncode(JsonNumbers.normalize(decoded));
    await _writeEncoded(normalized);
  }

  Future<void> _writeEncoded(String normalized) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(key, normalized)) {
      throw StateError('Appearance save failed.');
    }
  }
}

/// Portée `InheritedWidget` exposant le [AppearanceCodec] et les callbacks de persistance à l'arbre de widgets.
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

/// Contrôleur `ValueNotifier` d'apparence synchronisé automatiquement avec un [AppearanceStore].
class PersistentAppearanceController extends ValueNotifier<Appearance> {
  PersistentAppearanceController(
    this.store,
    this.onSaveError, {
    this.validateAppearance,
    Duration? persistDelay,
  }) : persistDelay =
           persistDelay ??
           (_isTestBinding
               ? Duration.zero
               : const Duration(milliseconds: 250)),
       super(store.codec.defaults) {
    store.codec.additionalPreferences?.addListener(persist);
  }

  static bool get _isTestBinding =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  final AppearanceStore store;
  final void Function(Object error) onSaveError;
  final void Function(Appearance appearance)? validateAppearance;

  /// Délai de regroupement avant l'encodage JSON et l'écriture dans le store
  /// lors des modifications continues (glisser-déposer, curseurs).
  final Duration persistDelay;

  Future<void> _pending = Future.value();
  Timer? _debounceTimer;
  bool _dirty = false;
  bool _disposed = false;

  /// Termine les écritures en attente en déclenchant immédiatement tout
  /// enregistrement différé par debounce.
  Future<void> get saved => flush();
  bool _restoring = false;
  Future<void> restore() async {
    _restoring = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _dirty = false;
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

  /// Met à jour l'apparence affichée en direct (par ex. durant le streaming Vibe IA)
  /// sans déclencher d'écriture intermédiaire dans [store].
  void setPreviewValue(Appearance appearance) {
    final next = store.codec.prepare(appearance);
    validateAppearance?.call(next);
    super.value = next;
  }

  void reset() {
    store.codec.resetAdditional();
    value = store.codec.defaults;
  }

  /// Planifie une sauvegarde différée afin d'éviter de sérialiser le document
  /// complet à chaque frame lors d'un redimensionnement ou d'un curseur.
  void persist() {
    if (_restoring || _disposed) return;
    _dirty = true;
    _debounceTimer?.cancel();
    if (persistDelay <= Duration.zero) {
      _flushNow();
      return;
    }
    _debounceTimer = Timer(persistDelay, _flushNow);
  }

  /// Force immédiatement l'encodage et l'écriture de toute modification en attente.
  Future<void> flush() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_dirty && !_restoring) {
      _flushNow();
    }
    return _pending;
  }

  void _flushNow() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_restoring || !_dirty) return;
    _dirty = false;
    final snapshot = value;
    _pending = _pending.then((_) async {
      try {
        await store.save(snapshot);
      } catch (error) {
        onSaveError(error);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_dirty && !_restoring) {
      unawaited(flush());
    }
    _disposed = true;
    store.codec.additionalPreferences?.removeListener(persist);
    super.dispose();
  }
}
