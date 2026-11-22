/// Évaluateur runtime des validateurs de comportements ([BehaviorValidatorEvaluator]).
///
/// Évalue les validateurs simples ([ValueBehaviorValidator]) et composites
/// ([AllBehaviorValidator], [AnyBehaviorValidator], [NotBehaviorValidator])
/// avant l'exécution d'une [BehaviorAction] dans [BehaviorDispatcher].
library;

import 'dart:io' show FileSystemException;

import 'package:material_ui/material_ui.dart';

import '../../models/behaviours/behavior_event.dart';
import '../../models/behaviours/behavior_validator.dart';
import '../../models/json_text_binding.dart';
import '../../models/super_list_view_config.dart';
import '../../models/super_table_config.dart';
import '../../models/super_tree_view_config.dart';
import '../../models/super_value_config.dart';
import '../../theme/appearance.dart';
import '../repositories/json_list_scope.dart';
import '../repositories/json_repository_store.dart';
import 'component_runtime_value_registry.dart';

/// Contexte d'évaluation transmis à [BehaviorValidatorEvaluator.evaluate].
@immutable
class BehaviorValidationContext {
  /// Crée un contexte d'évaluation pour un événement sur un composant donné.
  BehaviorValidationContext({
    required this.context,
    required this.componentId,
    required this.componentType,
    required this.event,
    this.executionData = const {},
    this.appearance,
    this.repositoryStore,
    this.listScope,
    ComponentRuntimeValueRegistry? valueRegistry,
  }) : valueRegistry = valueRegistry ?? ComponentRuntimeValueRegistry.instance;

  /// Contexte Flutter du composant déclencheur.
  final BuildContext context;

  /// Identifiant technique du composant déclencheur.
  final String componentId;

  /// Type du composant déclencheur (`'value'`, `'action'`, `'listView'`, etc.).
  final String componentType;

  /// Événement déclencheur en cours de traitement.
  final BehaviorEvent event;

  /// Données runtime capturées par l'événement (ex. `'value'`, `'previousValue'`).
  final Map<String, Object?> executionData;

  /// Apparence active, utilisée en repli pour inspecter `Appearance.components`.
  final Appearance? appearance;

  /// Store des repositories JSON actif, utilisé pour lire les liaisons.
  final JsonRepositoryStore? repositoryStore;

  /// Portée de ligne de liste ou d'arbre courante, ou `null` hors collection.
  final JsonListScope? listScope;

  /// Registre des valeurs runtime des composants actuellement montés.
  final ComponentRuntimeValueRegistry valueRegistry;
}

typedef _ResolvedValue = ({Object? value, bool isValid, bool found});

/// Évaluateur asynchrone des [BehaviorValidator].
abstract final class BehaviorValidatorEvaluator {
  static const Set<String> _truthyStrings = {'true', '1', 'yes', 'oui'};
  static const Set<String> _falsyStrings = {'false', '0', 'no', 'non'};

  /// Évalue récursivement [validator] dans le contexte [ctx].
  static Future<bool> evaluate(
    BehaviorValidator validator,
    BehaviorValidationContext ctx,
  ) async {
    switch (validator) {
      case AllBehaviorValidator():
        for (final child in validator.validators) {
          if (!await evaluate(child, ctx)) return false;
        }
        return true;
      case AnyBehaviorValidator():
        for (final child in validator.validators) {
          if (await evaluate(child, ctx)) return true;
        }
        return false;
      case NotBehaviorValidator():
        return !await evaluate(validator.validator, ctx);
      case ValueBehaviorValidator():
        final resolved = await _resolveValue(validator, ctx);
        return _evaluateOperator(
          validator.operator,
          resolved,
          validator.expectedValue,
        );
      default:
        debugPrint(
          'BehaviorValidatorEvaluator: type de validateur non géré (${validator.runtimeType}).',
        );
        return false;
    }
  }

  /// Indique si [value] est considérée comme vide selon la sémantique GenUI.
  ///
  /// Les nombres (y compris `0`) et les booléens non nuls ne sont jamais vides.
  static bool isEmptyValue(Object? value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    if (value is Iterable) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    return false;
  }

  static Future<_ResolvedValue> _resolveValue(
    ValueBehaviorValidator validator,
    BehaviorValidationContext ctx,
  ) async {
    final scopeKey = ComponentRuntimeValueRegistry.scopeKeyOf(ctx.listScope);

    switch (validator.source) {
      case BehaviorValueSource.self:
        final entry = ctx.valueRegistry.resolve(
          ctx.componentId,
          preferredScopeKey: scopeKey,
        );
        if (ctx.executionData.containsKey('value')) {
          final isValid = ctx.executionData['isValid'] is bool
              ? ctx.executionData['isValid'] as bool
              : (entry?.readIsValid?.call() ?? true);
          return (
            value: ctx.executionData['value'],
            isValid: isValid,
            found: true,
          );
        }
        if (entry != null) {
          return (
            value: entry.readValue(),
            isValid: entry.readIsValid?.call() ?? true,
            found: true,
          );
        }
        return _resolveFromAppearance(ctx.componentId, ctx);

      case BehaviorValueSource.component:
        final targetId = validator.targetComponentId?.trim() ?? '';
        if (targetId.isEmpty) {
          return (value: null, isValid: false, found: false);
        }
        final entry = ctx.valueRegistry.resolve(
          targetId,
          preferredScopeKey: scopeKey,
        );
        if (entry != null) {
          return (
            value: entry.readValue(),
            isValid: entry.readIsValid?.call() ?? true,
            found: true,
          );
        }
        final fallback = await _resolveFromAppearance(targetId, ctx);
        if (!fallback.found) {
          debugPrint(
            'BehaviorValidatorEvaluator: composant cible "$targetId" introuvable '
            '(ni monté dans le registre runtime ni lié dans Appearance.components).',
          );
        }
        return fallback;

      case BehaviorValueSource.binding:
        final binding = validator.binding;
        if (binding == null) {
          return (value: null, isValid: false, found: false);
        }
        return _readBindingValue(binding, ctx, allowCollectionFallback: true);
    }
  }

  static Future<_ResolvedValue> _resolveFromAppearance(
    String componentId,
    BehaviorValidationContext ctx,
  ) async {
    final config = ctx.appearance?.components[componentId];
    if (config == null) {
      return (value: null, isValid: false, found: false);
    }

    switch (config) {
      case SuperValueConfig(:final binding?):
        return _readBindingValue(
          binding,
          ctx,
          allowStringList:
              config.kind.isChoice && config.choice.variant.isMultiple,
        );
      case SuperListViewConfig(:final binding?):
        return _readArrayBindingValue(binding, ctx);
      case SuperTableConfig(:final binding?):
        return _readArrayBindingValue(binding, ctx);
      case SuperTreeViewConfig(:final binding?):
        return _readTreeBindingValue(binding, ctx);
      default:
        return (value: null, isValid: false, found: false);
    }
  }

  static Future<_ResolvedValue> _readBindingValue(
    JsonTextBinding binding,
    BehaviorValidationContext ctx, {
    bool allowStringList = true,
    bool allowCollectionFallback = false,
  }) async {
    final store = ctx.repositoryStore;
    if (store == null) {
      return (value: null, isValid: false, found: false);
    }
    try {
      final selected = JsonListScope.resolveSelected(
        binding,
        ctx.listScope,
        store,
      );
      final resolved = selected.binding;
      if (resolved == null) {
        return (value: null, isValid: true, found: true);
      }
      final cached = store.peekAttribute(
        resolved,
        allowStringList: allowStringList,
      );
      if (cached != null) {
        return (value: cached.value, isValid: true, found: true);
      }
      try {
        final attr = await store.readAttribute(
          resolved,
          allowStringList: allowStringList,
        );
        return (value: attr.value, isValid: true, found: true);
      } on FormatException {
        if (!allowCollectionFallback) rethrow;
        return await _readNodeFallback(resolved, store);
      }
    } on FormatException catch (error) {
      debugPrint(
        'BehaviorValidatorEvaluator: erreur de lecture de liaison "${binding.path}" : ${error.message}',
      );
      return (value: null, isValid: false, found: false);
    } on FileSystemException catch (error) {
      debugPrint(
        'BehaviorValidatorEvaluator: erreur fichier lors de la lecture "${binding.path}" : ${error.message}',
      );
      return (value: null, isValid: false, found: false);
    }
  }

  static Future<_ResolvedValue> _readNodeFallback(
    JsonTextBinding resolved,
    JsonRepositoryStore store,
  ) async {
    final repoId = resolved.repositoryId;
    if (repoId == null || repoId.isEmpty) {
      return (value: null, isValid: false, found: false);
    }
    try {
      final cachedArray = store.peekArray(repoId, resolved.path);
      if (cachedArray != null) {
        return (value: cachedArray, isValid: true, found: true);
      }
      if (!JsonTextBinding.isCalculatedPath(resolved.path)) {
        final doc =
            store.peekDocument(repoId)?.document ??
            await store.readDocument(repoId);
        final node = JsonAttributePath(resolved.path).readNode(doc);
        return (value: node, isValid: true, found: true);
      }
      final items = await store.readArray(repoId, resolved.path);
      return (value: items, isValid: true, found: true);
    } on FormatException {
      return (value: null, isValid: false, found: false);
    } on FileSystemException {
      return (value: null, isValid: false, found: false);
    }
  }

  static Future<_ResolvedValue> _readArrayBindingValue(
    JsonTextBinding binding,
    BehaviorValidationContext ctx,
  ) async {
    final store = ctx.repositoryStore;
    if (store == null) {
      return (value: null, isValid: false, found: false);
    }
    try {
      final selected = JsonListScope.resolveSelected(
        binding,
        ctx.listScope,
        store,
      );
      final resolved = selected.binding;
      if (resolved == null) {
        return (value: const <Object?>[], isValid: true, found: true);
      }
      final repoId = resolved.repositoryId!;
      final cached = store.peekArray(repoId, resolved.path);
      if (cached != null) {
        return (value: cached, isValid: true, found: true);
      }
      final items = await store.readArray(repoId, resolved.path);
      return (value: items, isValid: true, found: true);
    } on FormatException catch (error) {
      debugPrint(
        'BehaviorValidatorEvaluator: erreur de lecture du tableau "${binding.path}" : ${error.message}',
      );
      return (value: null, isValid: false, found: false);
    } on FileSystemException {
      return (value: null, isValid: false, found: false);
    }
  }

  static Future<_ResolvedValue> _readTreeBindingValue(
    JsonTextBinding binding,
    BehaviorValidationContext ctx,
  ) async {
    final store = ctx.repositoryStore;
    if (store == null) {
      return (value: null, isValid: false, found: false);
    }
    try {
      final selected = JsonListScope.resolveSelected(
        binding,
        ctx.listScope,
        store,
      );
      final resolved = selected.binding;
      if (resolved == null) {
        return (value: const <Object?>[], isValid: true, found: true);
      }
      final repoId = resolved.repositoryId!;
      final cached = store.peekTreeNodes(repoId, resolved.path);
      if (cached != null) {
        return (value: cached.nodes, isValid: true, found: true);
      }
      return await _readNodeFallback(resolved, store);
    } on FormatException catch (error) {
      debugPrint(
        'BehaviorValidatorEvaluator: erreur de lecture de l’arbre "${binding.path}" : ${error.message}',
      );
      return (value: null, isValid: false, found: false);
    } on FileSystemException {
      return (value: null, isValid: false, found: false);
    }
  }

  static bool _evaluateOperator(
    BehaviorValidatorOperator op,
    _ResolvedValue resolved,
    Object? expected,
  ) {
    final value = resolved.value;
    switch (op) {
      case BehaviorValidatorOperator.isEmpty:
        return isEmptyValue(value);
      case BehaviorValidatorOperator.isFill:
        return !isEmptyValue(value);
      case BehaviorValidatorOperator.isTrue:
        return value == true ||
            (value is String &&
                _truthyStrings.contains(value.trim().toLowerCase()));
      case BehaviorValidatorOperator.isFalse:
        return value == false ||
            (value is String &&
                _falsyStrings.contains(value.trim().toLowerCase()));
      case BehaviorValidatorOperator.isValid:
        return resolved.found && resolved.isValid;
      case BehaviorValidatorOperator.isInvalid:
        return !resolved.found || !resolved.isValid;
      case BehaviorValidatorOperator.equals:
        return _valuesEqual(value, expected);
      case BehaviorValidatorOperator.notEquals:
        return !_valuesEqual(value, expected);
      case BehaviorValidatorOperator.contains:
        if (value is Iterable) {
          return value.any((item) => _valuesEqual(item, expected));
        }
        if (value == null || expected == null) return false;
        return value.toString().contains(expected.toString());
      case BehaviorValidatorOperator.startsWith:
        if (value == null || expected == null) return false;
        return value.toString().startsWith(expected.toString());
      case BehaviorValidatorOperator.greaterThan:
        final left = _tryParseNum(value);
        final right = _tryParseNum(expected);
        if (left == null || right == null) return false;
        return left > right;
      case BehaviorValidatorOperator.lessThan:
        final left = _tryParseNum(value);
        final right = _tryParseNum(expected);
        if (left == null || right == null) return false;
        return left < right;
      case BehaviorValidatorOperator.matchesRegex:
        if (value == null || expected is! String || expected.isEmpty) {
          return false;
        }
        try {
          return RegExp(expected).hasMatch(value.toString());
        } on FormatException {
          return false;
        }
    }
  }

  static num? _tryParseNum(Object? value) {
    if (value is num) return value.isFinite ? value : null;
    if (value is String) {
      final parsed = num.tryParse(value.trim());
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }

  static bool _valuesEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a is num && b is num) return a == b;
    if (a is bool && b is bool) return a == b;
    if (a is String && b is String) return a == b;

    if (a is num && b is String) {
      final parsed = _tryParseNum(b);
      return parsed != null && a == parsed;
    }
    if (a is String && b is num) {
      final parsed = _tryParseNum(a);
      return parsed != null && parsed == b;
    }

    if (a is bool && b is String) {
      final normalized = b.trim().toLowerCase();
      if (normalized == 'true') return a;
      if (normalized == 'false') return !a;
      return false;
    }
    if (a is String && b is bool) {
      final normalized = a.trim().toLowerCase();
      if (normalized == 'true') return b;
      if (normalized == 'false') return !b;
      return false;
    }

    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_valuesEqual(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key) ||
            !_valuesEqual(entry.value, b[entry.key])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }
}
