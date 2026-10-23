import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/json_text_binding.dart';
import '../repositories/json_list_scope.dart';
import '../repositories/json_repository_binding.dart';
import '../repositories/json_repository_store.dart';

/// Read-only runtime binding for a surface state's name.
///
/// Resolves wildcard paths through [JsonListScope.resolveSelected], reads
/// the resulting attribute from [JsonRepositoryStore], and notifies listeners
/// when either the repository or a required array selection changes.
///
/// Call [reconfigure] when the store, binding, scope, or placeholder status
/// changes. A placeholder deliberately performs no resolution or repository
/// read. This binding never writes to the store or reports errors globally.
class SurfaceStateBinding extends ChangeNotifier {
  SurfaceStateBinding({
    required JsonRepositoryStore? store,
    required JsonTextBinding binding,
    JsonListScope? scope,
    bool placeholder = false,
  }) : this._(store, binding, scope, placeholder);

  SurfaceStateBinding._(
    this._store,
    this._binding,
    this._scope,
    this._placeholder,
  ) {
    _store?.addListener(_storeChanged);
    _refresh();
  }

  JsonRepositoryStore? _store;
  JsonTextBinding _binding;
  JsonListScope? _scope;
  bool _placeholder;
  final Set<JsonArrayBinding> _arrays = {};
  bool _disposed = false;
  int _generation = 0;

  /// The state name when the attribute contains a string; otherwise `null`.
  String? stateName;

  /// A safe, local diagnostic for this binding; never reported globally.
  String? error;

  /// Whether the current concrete attribute is being read.
  bool loading = false;

  /// Replaces the runtime inputs and resolves/reads the new target.
  ///
  /// In-flight reads for the previous configuration are ignored.
  void reconfigure({
    required JsonRepositoryStore? store,
    required JsonTextBinding binding,
    JsonListScope? scope,
    bool placeholder = false,
  }) {
    if (_disposed) return;
    final storeChanged = !identical(_store, store);
    final inputChanged =
        storeChanged ||
        _binding != binding ||
        _placeholder != placeholder ||
        _scope?.repositoryId != scope?.repositoryId ||
        _scope?.placeholder != scope?.placeholder ||
        !listEquals(_scope?.indices, scope?.indices);
    if (storeChanged) {
      _store?.removeListener(_storeChanged);
      _store = store;
      _store?.addListener(_storeChanged);
    }
    _binding = binding;
    _scope = scope;
    _placeholder = placeholder;
    // Selection-only scope updates keep the current state and pending read.
    if (inputChanged) _refresh();
  }

  void _storeChanged() => _refresh();

  void _arrayChanged() => _refresh();

  void _detachArrays() {
    for (final array in _arrays) {
      array.removeListener(_arrayChanged);
    }
    _arrays.clear();
  }

  void _setArrays(Iterable<JsonArrayBinding> arrays) {
    for (final array in _arrays) {
      if (!arrays.contains(array)) array.removeListener(_arrayChanged);
    }
    final next = arrays.toSet();
    for (final array in next) {
      if (!_arrays.contains(array)) array.addListener(_arrayChanged);
    }
    _arrays
      ..clear()
      ..addAll(next);
  }

  void _refresh() {
    if (_disposed) return;
    final generation = ++_generation;
    _detachArrays();
    stateName = null;
    error = null;

    if (_placeholder || (_scope?.placeholder ?? false)) {
      loading = false;
      notifyListeners();
      return;
    }
    final store = _store;
    if (store == null) {
      loading = false;
      error = 'Repository service unavailable.';
      notifyListeners();
      return;
    }

    late final JsonSelectedBinding resolved;
    try {
      resolved = JsonListScope.resolveSelected(_binding, _scope, store);
    } on FormatException catch (exception) {
      loading = false;
      error = exception.message;
      notifyListeners();
      return;
    }

    _setArrays(resolved.arrays);
    final concrete = resolved.binding;
    if (concrete == null) {
      loading = false;
      notifyListeners();
      return;
    }

    loading = true;
    notifyListeners();
    _read(store, concrete, generation);
  }

  Future<void> _read(
    JsonRepositoryStore store,
    JsonTextBinding binding,
    int generation,
  ) async {
    try {
      final result = await store.readAttribute(binding);
      if (_disposed || generation != _generation) return;
      final value = result.value;
      if (value == null) {
        stateName = null;
      } else if (value is String) {
        stateName = value;
      } else {
        error = 'Surface state name must be a string.';
      }
    } on FormatException catch (exception) {
      if (!_disposed && generation == _generation) {
        error = exception.message;
      }
    } on FileSystemException {
      if (!_disposed && generation == _generation) {
        error = 'Unable to read the surface state from its repository.';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _store?.removeListener(_storeChanged);
    _detachArrays();
    super.dispose();
  }
}
