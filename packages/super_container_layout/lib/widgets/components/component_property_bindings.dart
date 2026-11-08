/// Parseurs et mixin générique d'observation des liaisons de propriétés JSON (`propertyBindings`).
///
/// Mutualise la résolution via [JsonListScope.resolveSelected], la lecture synchrone/asynchrone
/// depuis [JsonRepositoryStore] et la validation des types liés (`Color`, `double`, `FontWeight`,
/// `bool`, `TextAlign`, `String`, icônes et polices) pour `SuperValue`, `SuperAction`,
/// `SuperIndicator` et `SuperSeparator`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/json_text_binding.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_store.dart';

/// Parseurs typés partagés pour convertir une valeur JSON brute en propriété de composant.
abstract final class BoundPropertyParsers {
  /// Valide une chaîne de caractères (et vérifie qu'elle n'est pas vide si [nonEmptyTrimmed] vaut `true`).
  static String parseString(
    String propertyName,
    Object? value, {
    bool nonEmptyTrimmed = false,
  }) {
    if (value is! String || (nonEmptyTrimmed && value.trim().isEmpty)) {
      throw FormatException(
        'La valeur liée à $propertyName doit être un texte valide.',
      );
    }
    return value;
  }

  /// Valide un identifiant d'icône (autorise `null` ou chaîne vide pour « aucune icône »).
  static String parseIcon(Object? value, bool Function(String) isKnown) {
    if (value == null || (value is String && value.trim().isEmpty)) {
      return '';
    }
    if (value is! String || !isKnown(value)) {
      throw const FormatException(
        'L’icône liée doit être un identifiant d’icône valide.',
      );
    }
    return value.trim();
  }

  /// Valide un booléen d'activation (`enabled`).
  static bool parseEnabled(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      return switch (value.trim().toLowerCase()) {
        'true' || '1' || 'yes' || 'oui' => true,
        'false' || '0' || 'no' || 'non' => false,
        _ => throw const FormatException(
          'L’état activé lié doit être un booléen (true/false).',
        ),
      };
    }
    throw const FormatException(
      'L’état activé lié doit être un booléen ou un texte.',
    );
  }

  /// Valide une couleur ARGB entière ou hexadécimale (`#RRGGBB` / `#AARRGGBB`).
  static Color parseColor(Object? value) {
    if (value is int && value >= 0 && value <= 0xFFFFFFFF) {
      return Color(value);
    }
    if (value is String) {
      final hex = value.trim().replaceFirst(RegExp(r'^#'), '');
      if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
        return Color(0xFF000000 | int.parse(hex, radix: 16));
      }
      if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    throw const FormatException(
      'La couleur liée doit être un entier ARGB ou un hexadécimal RGB/ARGB.',
    );
  }

  /// Valide un nombre flottant strictement positif (`> 0`).
  static double parsePositiveDouble(
    Object? value, {
    String errorMessage = 'La taille liée doit être un nombre positif.',
  }) {
    final number = value is num
        ? value.toDouble()
        : value is String
        ? double.tryParse(value.trim().replaceAll(',', '.'))
        : null;
    if (number == null || !number.isFinite || number <= 0) {
      throw FormatException(errorMessage);
    }
    return number;
  }

  /// Valide un nombre flottant positif ou nul (`>= 0`).
  static double parseNonNegativeDouble(
    Object? value, {
    String errorMessage =
        'La dimension liée doit être un nombre positif ou nul.',
  }) {
    final number = value is num
        ? value.toDouble()
        : value is String
        ? double.tryParse(value.trim().replaceAll(',', '.'))
        : null;
    if (number == null || !number.isFinite || number < 0) {
      throw FormatException(errorMessage);
    }
    return number;
  }

  /// Valide une graisse typographique (`normal`, `bold`, `100`..`900`, `w100`..`w900`).
  static FontWeight parseFontWeight(Object? value) {
    final weight = switch (value) {
      int weightValue =>
        FontWeight.values
            .where((weight) => weight.value == weightValue)
            .firstOrNull,
      String text => switch (text.trim().toLowerCase()) {
        'normal' => FontWeight.w400,
        'bold' => FontWeight.w700,
        final v when RegExp(r'^(?:w)?[1-9]00$').hasMatch(v) =>
          FontWeight.values
              .where(
                (weight) => weight.value == int.parse(v.replaceFirst('w', '')),
              )
              .firstOrNull,
        _ => null,
      },
      _ => null,
    };
    if (weight == null) {
      throw const FormatException(
        'La graisse liée doit être normal, bold ou une valeur 100–900.',
      );
    }
    return weight;
  }

  /// Valide un booléen de style italique (`true`/`false` ou `italic`/`normal`).
  static bool parseItalic(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      return switch (value.trim().toLowerCase()) {
        'true' || 'italic' => true,
        'false' || 'normal' => false,
        _ => throw const FormatException(
          'Le style italique lié doit être true/false ou italic/normal.',
        ),
      };
    }
    throw const FormatException(
      'Le style italique lié doit être un booléen ou un texte.',
    );
  }

  /// Valide un alignement de texte ([TextAlign]).
  static TextAlign parseTextAlign(Object? value) {
    if (value is String) {
      final align = TextAlign.values
          .where((candidate) => candidate.name == value.trim().toLowerCase())
          .firstOrNull;
      if (align != null) return align;
    }
    throw const FormatException(
      'L’alignement lié doit être start, end, left, right, center ou justify.',
    );
  }
}

/// Mixin gérant la résolution, le cache et l'écoute réactive des `propertyBindings`
/// d'un composant (`SuperValue`, `SuperAction`, `SuperIndicator`, `SuperSeparator`).
mixin ComponentPropertyBindingsMixin<W extends StatefulWidget, P extends Enum>
    on State<W> {
  /// Valeurs résolues et validées pour chaque propriété liée.
  Map<P, Object> boundPropertyValues = const {};

  /// Erreurs de résolution ou de format par propriété liée.
  Map<P, String> propertyBindingErrors = const {};

  List<JsonArrayBinding> _propertySelections = const [];
  Map<P, JsonTextBinding> _activePropertyBindings = const {};
  Map<P, JsonTextBinding>? _requestedPropertyBindings;
  JsonRepositoryStore? _requestedPropertyStore;
  String? _requestedPropertyRepositoryId;
  String? _requestedPropertyNodePath;
  List<int> _requestedPropertyIndices = const [];
  bool _requestedPropertyPlaceholder = false;
  bool _refreshPropertyBindings = true;
  int _propertyBindingGeneration = 0;

  /// Liste des familles de polices autorisées pour valider la propriété `fontFamily`.
  List<String> get availableComponentFontFamilies;

  /// Convertit et valide la valeur brute lue dans le repository pour [property].
  Object parseBoundProperty(P property, Object? value);

  /// Indique si [property] correspond à une famille de police devant être vérifiée
  /// vis-à-vis de [availableComponentFontFamilies].
  bool isFontFamilyProperty(P property) => property.name == 'fontFamily';

  void _listenPropertySelections(List<JsonArrayBinding> selections) {
    if (listEquals(_propertySelections, selections)) return;
    for (final selection in _propertySelections) {
      selection.removeListener(_propertySelectionChanged);
    }
    _propertySelections = selections;
    for (final selection in selections) {
      selection.addListener(_propertySelectionChanged);
    }
  }

  void _propertySelectionChanged() {
    _refreshPropertyBindings = true;
    if (mounted) setState(() {});
  }

  void _propertyStoreChanged() {
    final store = _requestedPropertyStore;
    if (!mounted || store == null || _activePropertyBindings.isEmpty) return;
    final generation = ++_propertyBindingGeneration;
    unawaited(
      _loadPropertyBindings(_activePropertyBindings, store, generation),
    );
  }

  /// Observe et synchronise la carte [bindings] avec [scope] et [store].
  void observePropertyBindings(
    Map<P, JsonTextBinding> bindings,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final sameBindingContext =
        mapEquals(_requestedPropertyBindings, bindings) &&
        identical(_requestedPropertyStore, store) &&
        _requestedPropertyRepositoryId == scope?.repositoryId &&
        _requestedPropertyNodePath == scope?.nodePath &&
        listEquals(_requestedPropertyIndices, scope?.indices ?? const []) &&
        _requestedPropertyPlaceholder == (scope?.placeholder ?? false);
    if (!_refreshPropertyBindings && sameBindingContext) {
      return;
    }
    _refreshPropertyBindings = false;
    _requestedPropertyBindings = Map.of(bindings);
    if (!identical(_requestedPropertyStore, store)) {
      _requestedPropertyStore?.unregisterBindings(this);
      _requestedPropertyStore?.removeListener(_propertyStoreChanged);
      store?.addListener(_propertyStoreChanged);
      _requestedPropertyStore = store;
    }
    _requestedPropertyRepositoryId = scope?.repositoryId;
    _requestedPropertyNodePath = scope?.nodePath;
    _requestedPropertyIndices = List.of(scope?.indices ?? const []);
    _requestedPropertyPlaceholder = scope?.placeholder ?? false;
    final generation = ++_propertyBindingGeneration;
    propertyBindingErrors = const {};
    if (bindings.isEmpty || (scope?.placeholder ?? false)) {
      store?.unregisterBindings(this);
      boundPropertyValues = const {};
      _activePropertyBindings = const {};
      _listenPropertySelections(const []);
      return;
    }

    store?.registerBindings(this, [
      for (final b in bindings.values) b.repositoryId ?? scope?.repositoryId,
    ]);

    final selections = <JsonArrayBinding>[];
    final resolved = <P, JsonTextBinding>{};
    final errors = <P, String>{};
    for (final entry in bindings.entries) {
      try {
        final result = JsonListScope.resolveSelected(entry.value, scope, store);
        selections.addAll(result.arrays);
        if (result.binding != null) resolved[entry.key] = result.binding!;
      } on FormatException catch (error) {
        errors[entry.key] = error.message;
      }
    }
    _listenPropertySelections(selections.toSet().toList());
    _activePropertyBindings = Map.of(resolved);
    propertyBindingErrors = errors;
    if (resolved.isEmpty) {
      boundPropertyValues = const {};
      return;
    }
    if (store == null) {
      boundPropertyValues = const {};
      propertyBindingErrors = {
        ...propertyBindingErrors,
        for (final property in resolved.keys)
          property: 'Service de repositories indisponible.',
      };
      return;
    }
    final syncedValues = <P, Object>{
      for (final entry in boundPropertyValues.entries)
        if (resolved.containsKey(entry.key)) entry.key: entry.value,
    };
    for (final entry in resolved.entries) {
      final cached = store.peekAttribute(entry.value);
      if (cached == null) continue;
      try {
        final value = parseBoundProperty(entry.key, cached.value);
        if (isFontFamilyProperty(entry.key) &&
            availableComponentFontFamilies.isNotEmpty &&
            !availableComponentFontFamilies.contains(value)) {
          continue;
        }
        syncedValues[entry.key] = value;
      } on FormatException {
        // L'erreur sera signalée par _loadPropertyBindings.
      }
    }
    boundPropertyValues = syncedValues;
    unawaited(_loadPropertyBindings(resolved, store, generation));
  }

  Future<void> _loadPropertyBindings(
    Map<P, JsonTextBinding> bindings,
    JsonRepositoryStore store,
    int generation,
  ) async {
    final values = <P, Object>{};
    final errors = Map<P, String>.of(propertyBindingErrors);
    final entries = bindings.entries.toList();
    final outcomes = await Future.wait([
      for (final entry in entries)
        () async {
          try {
            final result = await store.readAttribute(entry.value);
            final value = parseBoundProperty(entry.key, result.value);
            if (isFontFamilyProperty(entry.key) &&
                availableComponentFontFamilies.isNotEmpty &&
                !availableComponentFontFamilies.contains(value)) {
              throw FormatException(
                'La police liée « $value » n’est pas disponible.',
              );
            }
            return (property: entry.key, value: value, error: null);
          } on FormatException catch (error) {
            return (property: entry.key, value: null, error: error.message);
          } on FileSystemException {
            return (
              property: entry.key,
              value: null,
              error: 'Impossible de lire le repository lié.',
            );
          }
        }(),
    ]);
    if (!mounted || generation != _propertyBindingGeneration) return;
    for (final outcome in outcomes) {
      if (outcome.error != null) {
        errors[outcome.property] = outcome.error!;
      } else if (outcome.value != null) {
        values[outcome.property] = outcome.value!;
        errors.remove(outcome.property);
      }
    }
    if (mapEquals(boundPropertyValues, values) &&
        mapEquals(propertyBindingErrors, errors)) {
      return;
    }
    setState(() {
      boundPropertyValues = values;
      propertyBindingErrors = errors;
    });
  }

  /// Libère les abonnements aux sélections et au [JsonRepositoryStore].
  void disposePropertyBindings() {
    _propertyBindingGeneration++;
    _listenPropertySelections(const []);
    _requestedPropertyStore?.unregisterBindings(this);
    _requestedPropertyStore?.removeListener(_propertyStoreChanged);
    _requestedPropertyStore = null;
  }
}
