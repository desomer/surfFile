/// Service de persistance asynchrone ([AppearanceStore]) de l'apparence dans `SharedPreferences`.
///
/// Gère la file d'écriture sérialisée sous la clé `appearance.v1`, le contrôleur
/// persistant ([PersistentAppearanceController]) et la portée [AppearanceServicesScope].
library;

import 'dart:async' show Timer, unawaited;
import 'dart:convert';
import 'dart:isolate' show Isolate;

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/json_numbers.dart';
import '../../theme/appearance.dart';
import '../pages/editor_page_graph.dart';
import 'appearance_codec.dart';
import 'paged_file_appearance_store.dart';


Map<String, dynamic> _decodeJsonMapInIsolate(String text) {
  final json = jsonDecode(text);
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Invalid appearance document.');
  }
  return json;
}

String _normalizeAndEncodeJsonMapInIsolate(Map<String, Object?> rawJson) =>
    jsonEncode(JsonNumbers.normalizeMap(rawJson));

({Map<String, dynamic> raw, String normalized})
_decodeAndNormalizeJsonMapInIsolate(String encoded) {
  final decoded = _decodeJsonMapInIsolate(encoded);
  final normalized = jsonEncode(JsonNumbers.normalize(decoded));
  return (raw: decoded, normalized: normalized);
}

/// Service de lecture et d'écriture persistante du document d'apparence dans `SharedPreferences`.
class AppearanceStore {
  AppearanceStore({
    this.key = 'super_container_layout.appearance',
    this.codec = const AppearanceCodec(),
    this.isolateThresholdBytes = defaultIsolateThresholdBytes,
    this.isolateThresholdEntries = defaultIsolateThresholdEntries,
  });

  /// Taille minimale (en caractères UTF-16) à partir de laquelle `load` et
  /// `saveEncoded` exécutent le parsing/normalisation JSON dans un `Isolate`.
  static const int defaultIsolateThresholdBytes = 32 * 1024;

  /// Nombre cumulé minimum d'entrées (`styles + components + behaviors`) à
  /// partir duquel `save` déporte la normalisation et l'encodage en `Isolate`.
  static const int defaultIsolateThresholdEntries = 40;

  final String key;
  final AppearanceCodec codec;
  final int isolateThresholdBytes;
  final int isolateThresholdEntries;
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

    final Appearance result;
    if (stored.length >= isolateThresholdBytes) {
      final decoded = await Isolate.run(
        () => _decodeJsonMapInIsolate(stored),
      );
      result = codec.fromJson(decoded);
    } else {
      result = codec.decode(stored);
    }
    codec.restoreAdditional(stored);
    if (codec.needsMigration(stored)) await save(result);
    return result;
  }

  Future<void> save(Appearance appearance) async {
    final entryCount =
        appearance.styles.length +
        appearance.components.length +
        appearance.behaviors.length;
    final String encoded;
    if (entryCount >= isolateThresholdEntries) {
      final rawJson = codec.toJson(appearance);
      encoded = await Isolate.run(
        () => _normalizeAndEncodeJsonMapInIsolate(rawJson),
      );
    } else {
      encoded = codec.encode(appearance);
    }
    if (runtimeType == AppearanceStore) {
      await _writeEncoded(encoded);
      return;
    }
    await saveEncoded(encoded);
  }

  Future<void> saveEncoded(String encoded) async {
    final String normalized;
    if (encoded.length >= isolateThresholdBytes) {
      final parsed = await Isolate.run(
        () => _decodeAndNormalizeJsonMapInIsolate(encoded),
      );
      codec.fromJson(parsed.raw);
      normalized = parsed.normalized;
    } else {
      final decoded = _decodeJsonMapInIsolate(encoded);
      codec.fromJson(decoded);
      normalized = jsonEncode(JsonNumbers.normalize(decoded));
    }
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
  bool _hydrating = false;
  EditorPageAppearanceSlice? _activeHydrationSlice;
  int _epoch = 0;
  final Map<String, Future<void>> _inFlightPageLoads = <String, Future<void>>{};

  /// Indique si une hydratation passive de page à la demande est en cours.
  bool get isHydrating => _hydrating;

  /// Tranche en cours d'hydratation (utilisée par l'historique pour enrichir les snapshots sans créer d'étape Undo).
  EditorPageAppearanceSlice? get activeHydrationSlice => _activeHydrationSlice;

  /// Indique si la page [pageId] est déjà chargée en mémoire (toujours `true` pour les stores monolithiques).
  bool isPageLoaded(String pageId) => switch (store) {
    final PagedFileAppearanceStore paged => paged.isPageLoaded(pageId),
    _ => true,
  };

  /// Charge à la demande les données persistées de [pageId] sans déclencher d'écriture disque.
  Future<void> ensurePageLoaded(String pageId) {
    final currentStore = store;
    if (currentStore is! PagedFileAppearanceStore) {
      return Future<void>.value();
    }
    final trimmed = pageId.trim();
    if (trimmed.isEmpty || currentStore.isPageLoaded(trimmed)) {
      return Future<void>.value();
    }
    final inFlight = _inFlightPageLoads[trimmed];
    if (inFlight != null) return inFlight;

    final future = _hydratePage(currentStore, trimmed, _epoch);
    _inFlightPageLoads[trimmed] = future;
    return future.whenComplete(() {
      if (identical(_inFlightPageLoads[trimmed], future)) {
        _inFlightPageLoads.remove(trimmed);
      }
    });
  }

  Future<void> _hydratePage(
    PagedFileAppearanceStore paged,
    String pageId,
    int epoch,
  ) async {
    final slice = await paged.loadPage(pageId);
    if (_disposed || epoch != _epoch || slice.isEmpty) return;
    _hydrating = true;
    _activeHydrationSlice = slice;
    try {
      final merged = store.codec.prepare(slice.mergeInto(value));
      validateAppearance?.call(merged);
      super.value = merged;
    } finally {
      _activeHydrationSlice = null;
      _hydrating = false;
    }
  }

  /// Charge à la demande toutes les pages déclarées dans `value.pageCatalog`.
  Future<void> ensureAllPagesLoaded() async {
    if (store is! PagedFileAppearanceStore) return;
    final ids = [for (final page in value.pageCatalog.pages) page.id];
    for (final id in ids) {
      await ensurePageLoaded(id);
    }
  }

  Future<void> restore() async {
    _epoch++;
    _inFlightPageLoads.clear();
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
    _epoch++;
    _inFlightPageLoads.clear();
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
