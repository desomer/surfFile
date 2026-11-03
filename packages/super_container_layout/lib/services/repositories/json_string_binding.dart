/// Lecture réactive et sans écriture d'un texte issu d'un repository JSON.
/// Partagée par les états de surface et les info-bulles des composants.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/json_text_binding.dart';
import 'json_list_scope.dart';
import 'json_repository_binding.dart';
import 'json_repository_store.dart';

/// Lecteur réactif d'une chaîne JSON, sans écriture.
///
/// Resolves wildcard paths through [JsonListScope.resolveSelected], reads
/// the resulting attribute from [JsonRepositoryStore], and notifies listeners
/// when either the repository or a required array selection changes.
///
/// Call [reconfigure] when the store, binding, scope, or placeholder status
/// changes. A placeholder deliberately performs no resolution or repository
/// read. This binding never writes to the store or reports errors globally.
class JsonStringBinding extends ChangeNotifier {
  JsonStringBinding({
    required JsonRepositoryStore? store,
    required JsonTextBinding binding,
    JsonListScope? scope,
    bool placeholder = false,
    String typeError = 'La valeur liée doit être un texte.',
    String readError = 'Impossible de lire le repository lié.',
    String missingStoreError = 'Service de repositories indisponible.',
  }) : this._(
         store,
         binding,
         scope,
         placeholder,
         typeError,
         readError,
         missingStoreError,
       );

  JsonStringBinding._(
    this._store,
    this._binding,
    this._scope,
    this._placeholder,
    this.typeError,
    this.readError,
    this.missingStoreError,
  ) {
    _store?.addListener(_storeChanged);
    _refresh();
  }

  /// Diagnostics adaptés au consommateur.
  final String typeError;
  final String readError;
  final String missingStoreError;

  JsonRepositoryStore? _store;
  JsonTextBinding _binding;
  JsonListScope? _scope;
  bool _placeholder;
  final Set<JsonArrayBinding> _arrays = {};
  bool _disposed = false;
  int _generation = 0;

  /// Texte résolu, ou `null` si la valeur est absente.
  String? value;

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
        _scope?.nodePath != scope?.nodePath ||
        _scope?.treeTemplatePath != scope?.treeTemplatePath ||
        !listEquals(_scope?.indices, scope?.indices);
    if (storeChanged) {
      _store?.unregisterBindings(this);
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
    value = null;
    error = null;

    if (_placeholder || (_scope?.placeholder ?? false)) {
      _store?.unregisterBindings(this);
      loading = false;
      notifyListeners();
      return;
    }
    final store = _store;
    if (store == null) {
      loading = false;
      error = missingStoreError;
      notifyListeners();
      return;
    }

    store.registerBindings(this, [
      _binding.repositoryId ?? _scope?.repositoryId,
    ]);

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

    final cached = store.peekAttribute(concrete);
    if (cached != null) {
      final raw = cached.value;
      if (raw == null) {
        value = null;
      } else if (raw is String) {
        value = raw;
      } else {
        error = typeError;
      }
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
      final raw = result.value;
      if (raw == null) {
        value = null;
      } else if (raw is String) {
        value = raw;
      } else {
        error = typeError;
      }
    } on FormatException catch (exception) {
      if (!_disposed && generation == _generation) {
        error = exception.message;
      }
    } on FileSystemException {
      if (!_disposed && generation == _generation) {
        error = readError;
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
    _store?.unregisterBindings(this);
    _store?.removeListener(_storeChanged);
    _detachArrays();
    super.dispose();
  }
}
