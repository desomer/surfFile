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
    this.rowItem,
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

  /// Élément JSON en mémoire de la ligne courante lors d'une évaluation par ligne
  /// (permet une lecture synchrone rapide des champs locaux de la ligne).
  final Object? rowItem;

  /// Registre des valeurs runtime des composants actuellement montés.
  final ComponentRuntimeValueRegistry valueRegistry;
}

typedef _ResolvedValue = ({Object? value, bool isValid, bool found});

/// Évaluateur asynchrone (avec chemin rapide synchrone) des [BehaviorValidator].
abstract final class BehaviorValidatorEvaluator {
  static const Set<String> _truthyStrings = {'true', '1', 'yes', 'oui'};
  static const Set<String> _falsyStrings = {'false', '0', 'no', 'non'};

  /// Tente d'évaluer [validator] de manière purement synchrone à partir du cache
  /// et des valeurs runtime en mémoire ; retourne `null` si une lecture
  /// asynchrone (repository non chargé ou attribut calculé) est nécessaire.
  static bool? tryEvaluateSync(
    BehaviorValidator validator,
    BehaviorValidationContext ctx,
  ) {
    switch (validator) {
      case AllBehaviorValidator():
        for (final child in validator.validators) {
          final res = tryEvaluateSync(child, ctx);
          if (res == null) return null;
          if (!res) return false;
        }
        return true;
      case AnyBehaviorValidator():
        for (final child in validator.validators) {
          final res = tryEvaluateSync(child, ctx);
          if (res == null) return null;
          if (res) return true;
        }
        return false;
      case NotBehaviorValidator():
        final res = tryEvaluateSync(validator.validator, ctx);
        return res == null ? null : !res;
      case ValueBehaviorValidator():
        final resolved = _tryResolveValueSync(validator, ctx);
        if (resolved == null) return null;
        final expected = _tryResolveExpectedSync(validator, ctx);
        if (expected == null) return null;
        return _evaluateOperator(
          validator.operator,
          resolved,
          expected.value,
          caseSensitive: validator.caseSensitive,
        );
      default:
        return false;
    }
  }

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
        final expected = await _resolveExpectedValue(validator, ctx);
        return _evaluateOperator(
          validator.operator,
          resolved,
          expected,
          caseSensitive: validator.caseSensitive,
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

  static _ResolvedValue? _tryResolveValueSync(
    ValueBehaviorValidator validator,
    BehaviorValidationContext ctx,
  ) {
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
        return _tryResolveFromAppearanceSync(ctx.componentId, ctx);

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
        return _tryResolveFromAppearanceSync(targetId, ctx);

      case BehaviorValueSource.binding:
        final binding = validator.binding;
        if (binding == null) {
          return (value: null, isValid: false, found: false);
        }
        return _tryReadBindingValueSync(
          binding,
          ctx,
          allowCollectionFallback: true,
        );
    }
  }

  static Future<Object?> _resolveExpectedValue(
    ValueBehaviorValidator validator,
    BehaviorValidationContext ctx,
  ) async {
    if (!validator.operator.requiresValue) return null;
    if (validator.hasExpectedComponent) {
      final expectedId = validator.expectedComponentId!.trim();
      final scopeKey = ComponentRuntimeValueRegistry.scopeKeyOf(ctx.listScope);
      final entry = ctx.valueRegistry.resolve(
        expectedId,
        preferredScopeKey: scopeKey,
      );
      if (entry != null) return entry.readValue();
      final fallback = await _resolveFromAppearance(expectedId, ctx);
      return fallback.value;
    }
    if (validator.hasExpectedBinding) {
      final resolved = await _readBindingValue(
        validator.expectedBinding!,
        ctx,
        allowCollectionFallback: true,
      );
      return resolved.value;
    }
    return validator.expectedValue;
  }

  static ({Object? value})? _tryResolveExpectedSync(
    ValueBehaviorValidator validator,
    BehaviorValidationContext ctx,
  ) {
    if (!validator.operator.requiresValue) return (value: null);
    if (validator.hasExpectedComponent) {
      final expectedId = validator.expectedComponentId!.trim();
      final scopeKey = ComponentRuntimeValueRegistry.scopeKeyOf(ctx.listScope);
      final entry = ctx.valueRegistry.resolve(
        expectedId,
        preferredScopeKey: scopeKey,
      );
      if (entry != null) return (value: entry.readValue());
      final fallback = _tryResolveFromAppearanceSync(expectedId, ctx);
      if (fallback == null) return null;
      return (value: fallback.value);
    }
    if (validator.hasExpectedBinding) {
      final resolved = _tryReadBindingValueSync(
        validator.expectedBinding!,
        ctx,
        allowCollectionFallback: true,
      );
      if (resolved == null) return null;
      return (value: resolved.value);
    }
    return (value: validator.expectedValue);
  }

  static _ResolvedValue? _tryResolveFromAppearanceSync(
    String componentId,
    BehaviorValidationContext ctx,
  ) {
    final config = ctx.appearance?.components[componentId];
    if (config == null) {
      return (value: null, isValid: false, found: false);
    }
    switch (config) {
      case SuperValueConfig(:final binding?):
        return _tryReadBindingValueSync(
          binding,
          ctx,
          allowStringList:
              config.kind.isChoice && config.choice.variant.isMultiple,
        );
      case SuperListViewConfig(:final binding?):
      case SuperTableConfig(:final binding?):
        final store = ctx.repositoryStore;
        if (store == null) return (value: null, isValid: false, found: false);
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
          final cached = store.peekArray(resolved.repositoryId!, resolved.path);
          if (cached != null) {
            return (value: cached, isValid: true, found: true);
          }
          return null;
        } on FormatException {
          return (value: null, isValid: false, found: false);
        }
      case SuperTreeViewConfig(:final binding?):
        final store = ctx.repositoryStore;
        if (store == null) return (value: null, isValid: false, found: false);
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
          final cached = store.peekTreeNodes(
            resolved.repositoryId!,
            resolved.path,
          );
          if (cached != null) {
            return (value: cached.nodes, isValid: true, found: true);
          }
          return null;
        } on FormatException {
          return (value: null, isValid: false, found: false);
        }
      default:
        return (value: null, isValid: false, found: false);
    }
  }

  /// Tente de lire un champ relatif directement depuis [ctx.rowItem] en mémoire.
  static _ResolvedValue? _tryReadFromRowItem(
    JsonTextBinding binding,
    BehaviorValidationContext ctx,
  ) {
    final rowItem = ctx.rowItem;
    if (rowItem == null) return null;
    final scope = ctx.listScope;
    if (binding.repositoryId != null &&
        scope?.repositoryId != null &&
        binding.repositoryId != scope!.repositoryId) {
      return null;
    }
    final rawPath = binding.path.trim();
    if (rawPath.isEmpty || JsonTextBinding.isCalculatedPath(rawPath)) {
      return null;
    }
    String? relativePath;
    if (rawPath == '.') {
      return (value: rowItem, isValid: true, found: true);
    }
    final template = scope?.arrayTemplate ?? scope?.treeTemplatePath;
    if (template != null && template.isNotEmpty) {
      final wildcardPrefix = '$template[?]';
      if (rawPath == wildcardPrefix) {
        return (value: rowItem, isValid: true, found: true);
      }
      if (rawPath.startsWith('$wildcardPrefix.')) {
        relativePath = rawPath.substring(wildcardPrefix.length + 1);
      }
    }
    if (relativePath == null &&
        binding.repositoryId == null &&
        !rawPath.contains('[?]') &&
        !rawPath.startsWith('@') &&
        (template == null ||
            (rawPath != template &&
                !rawPath.startsWith('$template.') &&
                !rawPath.startsWith('$template[')))) {
      relativePath = rawPath;
    }
    if (relativePath == null || relativePath.isEmpty) return null;
    try {
      final value = JsonAttributePath(relativePath).readNode(rowItem);
      return (value: value, isValid: true, found: true);
    } on FormatException {
      return null;
    }
  }

  static _ResolvedValue? _tryReadBindingValueSync(
    JsonTextBinding binding,
    BehaviorValidationContext ctx, {
    bool allowStringList = true,
    bool allowCollectionFallback = false,
  }) {
    final fromRow = _tryReadFromRowItem(binding, ctx);
    if (fromRow != null) return fromRow;

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
      final repoId = resolved.repositoryId;
      if (allowCollectionFallback &&
          repoId != null &&
          repoId.isNotEmpty &&
          !JsonTextBinding.isCalculatedPath(resolved.path)) {
        final docEntry = store.peekDocument(repoId);
        if (docEntry != null) {
          final node = JsonAttributePath(resolved.path).readNode(
            docEntry.document,
          );
          return (value: node, isValid: true, found: true);
        }
      }
      return null;
    } on FormatException {
      return (value: null, isValid: false, found: false);
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
    final fromRow = _tryReadFromRowItem(binding, ctx);
    if (fromRow != null) return fromRow;

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
    Object? expected, {
    bool caseSensitive = true,
  }) {
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
        return _valuesEqual(value, expected, caseSensitive: caseSensitive);
      case BehaviorValidatorOperator.notEquals:
        return !_valuesEqual(value, expected, caseSensitive: caseSensitive);
      case BehaviorValidatorOperator.contains:
        if (value is Iterable) {
          return value.any(
            (item) => _valuesEqual(
              item,
              expected,
              caseSensitive: caseSensitive,
            ),
          );
        }
        if (value == null || expected == null) return false;
        final haystack = value.toString();
        final needle = expected.toString();
        return caseSensitive
            ? haystack.contains(needle)
            : haystack.toLowerCase().contains(needle.toLowerCase());
      case BehaviorValidatorOperator.startsWith:
        if (value == null || expected == null) return false;
        final haystack = value.toString();
        final prefix = expected.toString();
        return caseSensitive
            ? haystack.startsWith(prefix)
            : haystack.toLowerCase().startsWith(prefix.toLowerCase());
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
        if (value == null || expected == null) return false;
        final pattern = expected.toString();
        if (pattern.isEmpty) return false;
        try {
          return RegExp(
            pattern,
            caseSensitive: caseSensitive,
          ).hasMatch(value.toString());
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

  static bool _valuesEqual(
    Object? a,
    Object? b, {
    bool caseSensitive = true,
  }) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a is num && b is num) return a == b;
    if (a is bool && b is bool) return a == b;
    if (a is String && b is String) {
      return caseSensitive ? a == b : a.toLowerCase() == b.toLowerCase();
    }

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
        if (!_valuesEqual(a[i], b[i], caseSensitive: caseSensitive)) {
          return false;
        }
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key) ||
            !_valuesEqual(
              entry.value,
              b[entry.key],
              caseSensitive: caseSensitive,
            )) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }
}
