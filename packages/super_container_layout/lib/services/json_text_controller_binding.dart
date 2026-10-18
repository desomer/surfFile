import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/json_text_binding.dart';
import 'json_repository_store.dart';

/// Runtime data stays here, never in appearance preferences or editor history.
class JsonTextControllerBinding extends ChangeNotifier {
  JsonTextControllerBinding({
    required this.store,
    required this.binding,
    required this.controller,
    this.onChanged,
  }) {
    controller.addListener(_edited);
    store.addListener(_repositoryChanged);
    reload();
  }

  final JsonRepositoryStore store;
  final JsonTextBinding binding;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
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

  Future<void> reload() async {
    final generation = ++_generation;
    loading = true;
    if (!dirty) error = null;
    _notify();
    try {
      final result = await store.readAttribute(binding);
      if (_disposed || generation != _generation) return;
      if (dirty) {
        if (result.value != _expected) {
          _failure(
            'Conflit sur l’attribut lié. Conservez votre saisie puis rechargez.',
          );
        }
        return;
      }
      _expected = result.value;
      _saved = result.text;
      _queuedText = result.text;
      _ready = true;
      _applying = true;
      if (controller.text != result.text) {
        controller.value = TextEditingValue(
          text: result.text,
          selection: TextSelection.collapsed(offset: result.text.length),
        );
        onChanged?.call(result.text);
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
    flush();
    _disposed = true;
    _generation++;
    _timer?.cancel();
    controller.removeListener(_edited);
    store.removeListener(_repositoryChanged);
    super.dispose();
  }
}
