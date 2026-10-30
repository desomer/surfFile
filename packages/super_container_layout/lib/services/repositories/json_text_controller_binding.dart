import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../models/json_text_binding.dart';
import 'json_repository_store.dart';

/// Runtime data stays here, never in appearance preferences or editor history.
class JsonTextControllerBinding extends ChangeNotifier {
  JsonTextControllerBinding({
    required this.store,
    required this.binding,
    required this.controller,
    this.onChanged,
    this.asBool = false,
  }) {
    store.registerBindings(this, [binding.repositoryId]);
    controller.addListener(_edited);
    store.addListener(_repositoryChanged);
    store.addFlusher(flush);
    _seedFromCache();
    reload();
  }

  final JsonRepositoryStore store;
  final JsonTextBinding binding;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool asBool;
  String? error;
  bool loading = true;
  bool saving = false;
  bool _disposed = false;
  bool _applying = false;
  bool _writing = false;
  bool _ready = false;
  bool _wasComposing = false;
  Object? _expected;
  String _saved = '';
  String _queuedText = '';
  int _queuedWrites = 0;
  String _observed = '';
  Timer? _timer;
  int _generation = 0;
  Future<void> _writes = Future.value();
  bool get dirty => _ready && (controller.text != _saved || _queuedWrites > 0);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _failure(String message) {
    error = message;
    store.reportBindingError(message);
    _notify();
  }

  void _seedFromCache() {
    final cached = store.peekAttribute(binding);
    if (cached == null) return;
    if (asBool && cached.value != null && cached.value is! bool) return;
    final resolvedText = asBool
        ? (cached.value == true ? 'true' : 'false')
        : cached.text;
    _expected = cached.value;
    _saved = resolvedText;
    _queuedText = resolvedText;
    _ready = true;
    loading = false;
    _applying = true;
    if (controller.text != resolvedText) {
      controller.value = TextEditingValue(
        text: resolvedText,
        selection: TextSelection.collapsed(offset: resolvedText.length),
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
    try {
      final result = await store.readAttribute(binding);
      if (_disposed || generation != _generation) return;
      if (asBool && result.value != null && result.value is! bool) {
        throw const FormatException('L’attribut lié doit être un booléen.');
      }
      final resolvedText = asBool
          ? (result.value == true ? 'true' : 'false')
          : result.text;
      if (dirty) {
        if (result.value != _expected) {
          _failure(
            'Conflit sur l’attribut lié. Conservez votre saisie puis rechargez.',
          );
        }
        return;
      }
      _expected = result.value;
      _saved = resolvedText;
      _queuedText = resolvedText;
      _ready = true;
      _applying = true;
      if (controller.text != resolvedText) {
        controller.value = TextEditingValue(
          text: resolvedText,
          selection: TextSelection.collapsed(offset: resolvedText.length),
        );
        onChanged?.call(resolvedText);
      }
      _observed = controller.text;
      _applying = false;
    } on FormatException catch (exception) {
      if (!_disposed && generation == _generation) _failure(exception.message);
    } on FileSystemException {
      if (!_disposed && generation == _generation) {
        _failure('Impossible de lire le repository lié.');
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void _repositoryChanged() {
    if (!_writing) reload();
  }

  void _edited() {
    if (_applying || _disposed) return;
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
    if (composing) return;
    _timer = Timer(const Duration(milliseconds: 350), flush);
    _notify();
  }

  /// Captures this binding's target/text, including when the widget is removed.
  Future<void> flush() {
    _timer?.cancel();
    if (!_ready || (controller.text == _queuedText && error == null)) {
      return _writes;
    }
    final text = controller.text;
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
        );
        _expected = result.value;
        _saved = text;
        error = null;
      } on FormatException catch (exception) {
        _failure(exception.message);
      } on FileSystemException {
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
    await _writes;
    if (_disposed) return;
    _ready = false;
    await reload();
  }

  @override
  void dispose() {
    store.unregisterBindings(this);
    store.removeFlusher(flush);
    flush();
    _disposed = true;
    _generation++;
    _timer?.cancel();
    controller.removeListener(_edited);
    store.removeListener(_repositoryChanged);
    super.dispose();
  }
}
