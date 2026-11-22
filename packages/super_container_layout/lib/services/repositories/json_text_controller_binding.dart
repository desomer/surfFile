/// Synchronisation bidirectionnelle ([JsonTextControllerBinding]) entre un `TextEditingController` et un repository JSON.
///
/// Écoute un [JsonTextBinding] (résolu via [JsonListScope]) pour mettre à jour
/// le champ texte et répercute les saisies modifiables dans le document JSON.
library;

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../models/json_text_binding.dart';
import '../diagnostics/debug_entry.dart';
import '../inspection/vibe_debug_capture.dart';
import 'js_calculated_attribute_runtime.dart';
import 'json_repository_store.dart';

/// Runtime data stays here, never in appearance preferences or editor history.
class JsonTextControllerBinding extends ChangeNotifier {
  /// Temporisation anti-rebond par défaut avant l'écriture automatique.
  static const Duration defaultDebounceDuration = Duration(milliseconds: 350);

  JsonTextControllerBinding({
    required this.store,
    required this.binding,
    required this.controller,
    this.componentId,
    this.onChanged,
    this.asBool = false,
    this.asStringList = false,
    this.requireString = false,
    Duration debounceDuration = defaultDebounceDuration,
    bool saveOnBlurOnly = false,
    this.toStorageText,
    this.toDisplayText,
    this.validateText,
  }) : _debounceDuration = debounceDuration < Duration.zero
           ? Duration.zero
           : debounceDuration,
       // Le champ reste privé pour passer obligatoirement par configureTiming().
       // ignore: prefer_initializing_formals
       _saveOnBlurOnly = saveOnBlurOnly {
    store.registerBindings(this, [binding.repositoryId]);
    controller.addListener(_edited);
    store.addListener(_repositoryChanged);
    if (!isReadOnly) {
      store.addFlusher(
        flush,
        pendingError: () {
          final validationError = _validationErrorOf(controller.text);
          if (validationError != null &&
              (_ready || controller.text.isNotEmpty)) {
            return validationError;
          }
          if (!dirty && (_ready || controller.text.isEmpty)) {
            return null;
          }
          return error ?? 'Une saisie liée n’a pas pu être enregistrée.';
        },
      );
    }
    if (!store.hasActiveMutations) {
      _seedFromCache();
    }
    if (!_ready) {
      reload();
    }
  }

  final JsonRepositoryStore store;
  final JsonTextBinding binding;
  final TextEditingController controller;
  final String? componentId;
  final ValueChanged<String>? onChanged;
  final bool asBool;
  final bool asStringList;

  /// Rejects non-text attributes for code editors; null remains an empty field.
  final bool requireString;

  /// Vrai lorsque le chemin contient un segment calculé et ne peut pas être écrit.
  bool get isReadOnly => JsonTextBinding.isCalculatedPath(binding.path);

  String? error;
  bool loading = true;
  bool saving = false;
  Duration _debounceDuration;
  bool _saveOnBlurOnly;
  String Function(String displayText)? toStorageText;
  String Function(String storageText)? toDisplayText;
  String? Function(String storageText, String displayText)? validateText;

  /// Temporisation anti-rebond actuelle avant écriture automatique dans le repository.
  Duration get debounceDuration => _debounceDuration;

  /// Indique si l'écriture automatique pendant la frappe est désactivée au profit
  /// d'un enregistrement uniquement à la perte de focus.
  bool get saveOnBlurOnly => _saveOnBlurOnly;

  /// Met à jour dynamiquement le délai anti-rebond et le mode d'enregistrement
  /// sans réinitialiser ni recharger la liaison.
  void configureTiming({Duration? debounceDuration, bool? saveOnBlurOnly}) {
    final nextDuration = debounceDuration == null
        ? _debounceDuration
        : (debounceDuration < Duration.zero ? Duration.zero : debounceDuration);
    final nextBlurOnly = saveOnBlurOnly ?? _saveOnBlurOnly;
    if (nextDuration == _debounceDuration && nextBlurOnly == _saveOnBlurOnly) {
      return;
    }
    _debounceDuration = nextDuration;
    _saveOnBlurOnly = nextBlurOnly;
    if (_saveOnBlurOnly) {
      _timer?.cancel();
    } else if (_timer?.isActive == true) {
      _timer?.cancel();
      _timer = Timer(_debounceDuration, flush);
    }
  }

  /// Met à jour dynamiquement les transformations d'affichage/stockage et le
  /// validateur sans recréer la liaison.
  void configureTransform({
    String Function(String displayText)? toStorageText,
    String Function(String storageText)? toDisplayText,
    String? Function(String storageText, String displayText)? validateText,
  }) {
    final hadDisplay = this.toDisplayText != null;
    this.toStorageText = toStorageText;
    this.toDisplayText = toDisplayText;
    this.validateText = validateText;
    if (!hadDisplay && toDisplayText != null && _ready && !dirty && !_disposed) {
      final expectedDisplay = _displayOf(_saved);
      if (controller.text != expectedDisplay) {
        final gen = _generation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_disposed || gen != _generation || !_ready || dirty) return;
          final nextDisplay = _displayOf(_saved);
          if (controller.text != nextDisplay) {
            _applying = true;
            controller.value = TextEditingValue(
              text: nextDisplay,
              selection: TextSelection.collapsed(offset: nextDisplay.length),
            );
            _observed = controller.text;
            _savedDisplay = controller.text;
            _applying = false;
          }
        });
      }
    }
  }

  String _storageOf(String displayText) =>
      toStorageText?.call(displayText) ?? displayText;

  String _displayOf(String storageText) =>
      toDisplayText?.call(storageText) ?? storageText;

  String? _validationErrorOf(String displayText) {
    final validator = validateText;
    if (validator == null) return null;
    return validator(_storageOf(displayText), displayText);
  }

  bool _disposed = false;
  bool _applying = false;
  bool _writing = false;
  bool _ready = false;
  bool _wasComposing = false;
  Object? _expected;
  String _saved = '';
  String _savedDisplay = '';
  String _queuedText = '';
  String? _failedText;
  int _queuedWrites = 0;
  String _observed = '';
  Timer? _timer;
  int _generation = 0;
  Future<void> _writes = Future.value();
  bool get dirty =>
      !isReadOnly &&
      _ready &&
      ((controller.text != _savedDisplay &&
              _storageOf(controller.text) != _saved) ||
          _queuedWrites > 0);

  /// Met à jour le texte affiché du contrôleur (ex. reformatage au focus/blur)
  /// sans déclencher d'écriture parasite ni modifier l'état `dirty`.
  void syncFormattedText(TextEditingValue nextValue) {
    if (_disposed) return;
    final wasDirty = dirty;
    _applying = true;
    controller.value = nextValue;
    _observed = controller.text;
    if (!wasDirty) {
      _savedDisplay = controller.text;
    }
    _applying = false;
  }

  /// Vrai lorsqu'une saisie locale ou une écriture en file doit être vidée
  /// avant de détacher ce contrôleur.
  bool get hasPendingWrite => dirty || _queuedWrites > 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _failure(
    String message, {
    DebugErrorCategory category = DebugErrorCategory.binding,
    DebugSeverity? severity,
    Object? stackTrace,
  }) {
    error = message;
    store.reportBindingError(
      message,
      category: category,
      severity: severity ?? category.defaultSeverity,
      componentId: componentId,
      source: 'JsonTextControllerBinding(${binding.path})',
      stackTrace: stackTrace,
    );
    _notify();
  }

  void _syncInputValidationDiagnostic(String? validationError) {
    final targetId = componentId ?? binding.path;
    VibeDebugCapture.syncComponentDiagnostic(
      componentId: targetId,
      sourceKey: 'binding_input_validation:${binding.path}',
      active: validationError != null,
      category: DebugErrorCategory.userInput,
      severity: DebugSeverity.warning,
      message: validationError,
      source: 'JsonTextControllerBinding.validation',
    );
  }

  void _seedFromCache() {
    final cached = store.peekAttribute(
      binding,
      allowStringList: asStringList,
    );
    if (cached == null) return;
    if (asBool && cached.value != null && cached.value is! bool) return;
    if (asStringList &&
        cached.value != null &&
        cached.value is! String &&
        cached.value is! List) {
      return;
    }
    if (requireString && cached.value != null && cached.value is! String) {
      return;
    }
    final resolvedText = asBool
        ? (cached.value == true ? 'true' : 'false')
        : cached.text;
    final displayText = _displayOf(resolvedText);
    _expected = cached.value;
    _saved = resolvedText;
    _savedDisplay = displayText;
    _queuedText = resolvedText;
    _ready = true;
    loading = false;
    _applying = true;
    if (controller.text != displayText) {
      controller.value = TextEditingValue(
        text: displayText,
        selection: TextSelection.collapsed(offset: displayText.length),
      );
    }
    _observed = controller.text;
    _applying = false;
  }

  Future<void> reload({bool showLoading = true}) async {
    final generation = ++_generation;
    final nextLoading = showLoading && !_ready;
    final nextError = dirty ? error : null;
    if (loading != nextLoading || error != nextError) {
      loading = nextLoading;
      error = nextError;
      _notify();
    }
    var changed = false;
    var failed = false;
    try {
      final result = await store.readAttribute(
        binding,
        allowStringList: asStringList,
      );
      if (_disposed || generation != _generation) return;
      if (asBool && result.value != null && result.value is! bool) {
        throw const FormatException('L’attribut lié doit être un booléen.');
      }
      if (asStringList &&
          result.value != null &&
          result.value is! String &&
          result.value is! List) {
        throw const FormatException(
          'L’attribut lié doit être un tableau ou une chaîne.',
        );
      }
      if (requireString && result.value != null && result.value is! String) {
        throw const FormatException(
          'L’attribut lié doit être une chaîne de texte.',
        );
      }
      final resolvedText = asBool
          ? (result.value == true ? 'true' : 'false')
          : result.text;
      final displayText = _displayOf(resolvedText);
      if (dirty) {
        if (!JsonRepositoryStore.jsonEquals(result.value, _expected)) {
          failed = true;
          loading = false;
          _failure(
            'Conflit sur l’attribut lié. Conservez votre saisie puis rechargez.',
          );
        }
        return;
      }
      _expected = result.value;
      _saved = resolvedText;
      _savedDisplay = displayText;
      _queuedText = resolvedText;
      _ready = true;
      _applying = true;
      if (controller.text != displayText) {
        controller.value = TextEditingValue(
          text: displayText,
          selection: TextSelection.collapsed(offset: displayText.length),
        );
        onChanged?.call(resolvedText);
        changed = true;
      }
      _observed = controller.text;
      _applying = false;
    } on FormatException catch (exception, stack) {
      if (!_disposed && generation == _generation) {
        failed = true;
        loading = false;
        final isJs = exception is JsCalculationException;
        _failure(
          exception.message,
          category: isJs
              ? DebugErrorCategory.javascript
              : DebugErrorCategory.binding,
          severity: isJs ? DebugSeverity.critical : DebugSeverity.error,
          stackTrace: stack,
        );
      }
    } on FileSystemException {
      if (!_disposed && generation == _generation) {
        failed = true;
        loading = false;
        _failure('Impossible de lire le repository lié.');
      }
    } finally {
      if (!_disposed && generation == _generation && !failed) {
        if (loading) {
          loading = false;
          changed = true;
        }
        if (changed) _notify();
      }
    }
  }

  void _repositoryChanged() {
    if (_writing || _disposed) return;
    if (!dirty &&
        _ready &&
        error == null &&
        !loading &&
        !store.hasActiveMutations) {
      final cached = store.peekAttribute(
        binding,
        allowStringList: asStringList,
      );
      if (cached != null &&
          (!asBool || cached.value == null || cached.value is bool) &&
          (!asStringList ||
              cached.value == null ||
              cached.value is String ||
              cached.value is List) &&
          (!requireString ||
              cached.value == null ||
              cached.value is String)) {
        final resolvedText = asBool
            ? (cached.value == true ? 'true' : 'false')
            : cached.text;
        final displayText = _displayOf(resolvedText);
        if (JsonRepositoryStore.jsonEquals(cached.value, _expected) &&
            (resolvedText == _saved || controller.text == displayText)) {
          return;
        }
      }
    }
    reload();
  }

  void _restoreReadOnlyValue() {
    _timer?.cancel();
    final displayText = _displayOf(_saved);
    if (_ready && controller.text != displayText) {
      _applying = true;
      controller.value = TextEditingValue(
        text: displayText,
        selection: TextSelection.collapsed(offset: displayText.length),
      );
      _applying = false;
    }
    _observed = controller.text;
  }

  void _edited() {
    if (_applying || _disposed) return;
    if (isReadOnly) {
      _restoreReadOnlyValue();
      return;
    }
    final composing = !controller.value.composing.isCollapsed;
    final committed = _wasComposing && !composing;
    _wasComposing = composing;
    if (controller.text == _observed && !committed) return;
    _observed = controller.text;
    if (!_ready) {
      _failure(
        'Repository non chargé : la saisie ne peut pas être enregistrée.',
      );
      return;
    }
    _timer?.cancel();
    error = null;
    _failedText = null;
    if (composing) return;
    final validationError = _validationErrorOf(controller.text);
    _syncInputValidationDiagnostic(validationError);
    if (validationError != null) {
      _notify();
      return;
    }
    if (_saveOnBlurOnly) {
      _notify();
      return;
    }
    _timer = Timer(_debounceDuration, flush);
    _notify();
  }

  /// Captures this binding's target/text, including when the widget is removed.
  Future<void> flush() {
    _timer?.cancel();
    if (isReadOnly) {
      _restoreReadOnlyValue();
      return _writes;
    }
    if (!_ready) {
      return _writes;
    }
    final validationError = _validationErrorOf(controller.text);
    _syncInputValidationDiagnostic(validationError);
    if (validationError != null) {
      return _writes;
    }
    final text = _storageOf(controller.text);
    if ((text == _queuedText && error == null) ||
        (error != null && text == _failedText)) {
      return _writes;
    }
    _queuedText = text;
    _queuedWrites++;
    _writes = _writes.then((_) async {
      saving = true;
      _writing = true;
      _notify();
      try {
        final result = await store.writeAttribute(
          binding,
          text,
          expectedValue: _expected,
          asBool: asBool,
          asStringList: asStringList,
          componentId: componentId,
        );
        _expected = result.value;
        _saved = text;
        _savedDisplay = controller.text;
        _failedText = null;
        error = null;
      } on FormatException catch (exception) {
        _failedText = text;
        _failure(exception.message);
      } on FileSystemException {
        _failedText = text;
        _failure('Impossible d’enregistrer le repository lié.');
      } finally {
        _queuedWrites--;
        if (error != null && _queuedWrites == 0) _queuedText = _saved;
        saving = false;
        _writing = false;
        _notify();
      }
    });
    return _writes;
  }

  /// Explicit retry discards the local draft, never does so on notifications.
  Future<void> discardAndReload() async {
    _timer?.cancel();
    _failedText = null;
    await _writes;
    if (_disposed) return;
    _ready = false;
    await reload();
  }

  @override
  void dispose() {
    store.unregisterBindings(this);
    if (!isReadOnly) {
      store.removeFlusher(flush);
      if (_ready &&
          _validationErrorOf(controller.text) == null &&
          !(error != null && _storageOf(controller.text) == _failedText)) {
        flush();
      }
    } else {
      _restoreReadOnlyValue();
    }
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _syncInputValidationDiagnostic(null);
    controller.removeListener(_edited);
    store.removeListener(_repositoryChanged);
    super.dispose();
  }
}
