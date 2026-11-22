/// Service de création de ligne dans un tableau JSON ([RepositoryArrayCreationService])
/// combinant le JSON Schema associé au repository et les valeurs par défaut
/// déclarées sur les composants `SuperValue` via [CreationDefaultAction].
library;

import '../../models/behaviours/creation_default_action.dart';
import '../../models/component_config.dart';
import '../../models/json_text_binding.dart';
import '../../models/native_component_config.dart';
import '../../models/scaffold_page_config.dart';
import '../../models/super_conditional_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_list_view_config.dart';
import '../../models/super_tab_config.dart';
import '../../models/super_table_config.dart';
import '../../models/super_tree_view_config.dart';
import '../../models/super_value_config.dart';
import '../../theme/appearance.dart';
import 'json_repository_store.dart';
import 'json_schema_field_resolver.dart';

/// Construit et insère une nouvelle ligne de tableau à partir du JSON Schema
/// du repository et des comportements [CreationDefaultAction] de l'[Appearance].
abstract final class RepositoryArrayCreationService {
  /// Normalise un chemin modèle de tableau en remplaçant les indices numériques
  /// éventuels par `[?]`.
  static String normalizeArrayTemplatePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return '';
    try {
      final parsed = JsonAttributePath(trimmed);
      final buffer = StringBuffer();
      for (final step in parsed.steps) {
        if (step.key != null) {
          if (buffer.isNotEmpty) buffer.write('.');
          buffer.write(step.key);
        } else {
          buffer.write('[?]');
        }
      }
      return buffer.toString();
    } on FormatException {
      return trimmed;
    }
  }

  /// Collecte les valeurs par défaut (`relativeFieldPath -> value`) définies par
  /// des [CreationDefaultAction] actifs sur les `SuperValue` ciblant le tableau
  /// [arrayTemplatePath] du repository [repositoryId].
  static Map<String, Object?> collectCreationDefaults(
    Appearance appearance, {
    required String repositoryId,
    required String arrayTemplatePath,
  }) {
    final targetRepo = repositoryId.trim();
    final targetArray = normalizeArrayTemplatePath(arrayTemplatePath);
    if (targetRepo.isEmpty || targetArray.isEmpty) {
      return const <String, Object?>{};
    }

    final collected = <String, Object?>{};
    final visitedFromRoot = <String>{};

    void visit(
      String id, {
      String? inheritedRepoId,
      String? inheritedArrayTemplate,
      Set<String>? branchSeen,
    }) {
      visitedFromRoot.add(id);
      final seen = branchSeen ?? <String>{};
      if (!seen.add(id)) return;

      final config = appearance.components[id];
      for (final behavior in appearance.behaviorsFor(id)) {
        if (!behavior.enabled) continue;
        final action = behavior.action;
        if (action is! CreationDefaultAction) continue;

        final JsonTextBinding? effectiveBinding =
            action.binding ??
            (config is SuperValueConfig ? config.binding : null);
        if (effectiveBinding == null) continue;

        final rawRepo = effectiveBinding.repositoryId?.trim() ?? '';
        final effectiveRepo = rawRepo.isNotEmpty ? rawRepo : inheritedRepoId;
        if (effectiveRepo != targetRepo) continue;

        final relativePath = _extractRelativeFieldPath(
          bindingPath: effectiveBinding.path,
          targetArrayTemplate: targetArray,
          inheritedArrayTemplate: inheritedArrayTemplate,
        );
        if (relativePath != null) {
          collected[relativePath] = action.defaultValue;
        }
      }

      String? childRepo = inheritedRepoId;
      String? childArray = inheritedArrayTemplate;
      switch (config) {
        case final SuperListViewConfig list:
          final r = list.binding?.repositoryId?.trim() ?? '';
          if (r.isNotEmpty) childRepo = r;
          final p = list.binding?.path.trim() ?? '';
          if (p.isNotEmpty && !JsonTextBinding.isCalculatedPath(p)) {
            childArray = normalizeArrayTemplatePath(p);
          }
        case final SuperTableConfig table:
          final r = table.binding?.repositoryId?.trim() ?? '';
          if (r.isNotEmpty) childRepo = r;
          final p = table.binding?.path.trim() ?? '';
          if (p.isNotEmpty && !JsonTextBinding.isCalculatedPath(p)) {
            childArray = normalizeArrayTemplatePath(p);
          }
        case final SuperTreeViewConfig tree:
          final r = tree.binding?.repositoryId?.trim() ?? '';
          if (r.isNotEmpty) childRepo = r;
          final p = tree.binding?.path.trim() ?? '';
          if (p.isNotEmpty && !JsonTextBinding.isCalculatedPath(p)) {
            childArray = normalizeArrayTemplatePath(p);
          }
        case final SuperTabConfig tab:
          if (tab.mode == SuperTabMode.dynamic) {
            final r = tab.binding?.repositoryId?.trim() ?? '';
            if (r.isNotEmpty) childRepo = r;
            final p = tab.binding?.path.trim() ?? '';
            if (p.isNotEmpty && !JsonTextBinding.isCalculatedPath(p)) {
              childArray = normalizeArrayTemplatePath(p);
            }
          }
        default:
          break;
      }

      for (final childId in _childrenOfComponent(config)) {
        visit(
          childId,
          inheritedRepoId: childRepo,
          inheritedArrayTemplate: childArray,
          branchSeen: seen,
        );
      }
      seen.remove(id);
    }

    // Commence par les conteneurs racines pour propager l'héritage de liste/table.
    final roots = <String>[
      for (final page in appearance.pageCatalog.pages) page.id,
      if (appearance.components.containsKey('root')) 'root',
      if (appearance.components.containsKey('mainLayout')) 'mainLayout',
      ...appearance.components.keys,
    ];
    for (final rootId in roots) {
      if (!visitedFromRoot.contains(rootId) &&
          appearance.components.containsKey(rootId)) {
        visit(rootId);
      }
    }

    return collected;
  }

  /// Construit le nouvel élément à insérer dans [arrayTemplatePath] :
  /// 1. à partir du JSON Schema associé à [repositoryId] ;
  /// 2. sinon à partir d'une copie vierge de `existingItems.last` ou `{}` ;
  /// 3. puis en appliquant les valeurs par défaut [CreationDefaultAction] de [appearance].
  static Future<Object?> buildNewRow({
    required JsonRepositoryStore store,
    required String repositoryId,
    required String arrayTemplatePath,
    Appearance? appearance,
    List<Object?>? existingItems,
  }) async {
    Map<String, Object?>? schema;
    try {
      schema = await store.readJsonSchema(repositoryId);
    } on FormatException {
      schema = null;
    }

    final normalizedArray = normalizeArrayTemplatePath(arrayTemplatePath);
    Object? row = JsonSchemaFieldResolver.buildDefaultArrayItem(
      schema,
      normalizedArray,
    );

    if (row == null) {
      if (existingItems != null && existingItems.isNotEmpty) {
        row = JsonRepositoryStore.blank(existingItems.last);
      } else {
        row = <String, dynamic>{};
      }
    }

    if (appearance == null) return row;
    final defaults = collectCreationDefaults(
      appearance,
      repositoryId: repositoryId,
      arrayTemplatePath: normalizedArray,
    );
    if (defaults.isEmpty) return row;

    for (final entry in defaults.entries) {
      final relativePath = entry.key;
      final fullItemFieldPath = relativePath.isEmpty
          ? '$normalizedArray[?]'
          : '$normalizedArray[?].$relativePath';
      final fieldNode = JsonSchemaFieldResolver.resolveSchemaNode(
        schema,
        fullItemFieldPath,
      );
      final coerced = _coerceToSchemaType(entry.value, fieldNode);
      if (relativePath.isEmpty) {
        row = coerced;
      } else if (row is Map) {
        row = _updatedNestedMap(row, relativePath, coerced);
      }
    }
    return row;
  }

  /// Insère une nouvelle ligne construite depuis le schéma et les valeurs par
  /// défaut des `SuperValue`s, et sélectionne éventuellement la ligne ajoutée.
  static Future<int> appendSchemaRow({
    required JsonRepositoryStore store,
    required String repositoryId,
    required String concreteArrayPath,
    required String arrayTemplatePath,
    Appearance? appearance,
    List<int> parentIndices = const <int>[],
    int? expectedLength,
    String? componentId,
    bool selectCreated = true,
  }) async {
    await store.flushBindings();
    final existing = await store.readArray(repositoryId, concreteArrayPath);
    final newItem = await buildNewRow(
      store: store,
      repositoryId: repositoryId,
      arrayTemplatePath: arrayTemplatePath,
      appearance: appearance,
      existingItems: existing,
    );
    final count = await store.appendArrayItem(
      repositoryId,
      concreteArrayPath,
      expectedLength: expectedLength ?? existing.length,
      componentId: componentId,
      initialItem: newItem,
    );
    if (selectCreated && count > 0) {
      store
          .bindingOf(repositoryId)
          .array(normalizeArrayTemplatePath(arrayTemplatePath))
          .select(parentIndices, count - 1);
    }
    return count;
  }

  static String? _extractRelativeFieldPath({
    required String bindingPath,
    required String targetArrayTemplate,
    required String? inheritedArrayTemplate,
  }) {
    final normalized = normalizeArrayTemplatePath(bindingPath);
    if (normalized.isEmpty || JsonTextBinding.isCalculatedPath(normalized)) {
      return null;
    }
    final elementPrefix = '$targetArrayTemplate[?]';
    if (normalized == elementPrefix) {
      return '';
    }
    if (normalized.startsWith('$elementPrefix.')) {
      return normalized.substring(elementPrefix.length + 1);
    }
    if (inheritedArrayTemplate != null &&
        inheritedArrayTemplate == targetArrayTemplate &&
        !normalized.contains('[?]')) {
      return normalized;
    }
    return null;
  }

  static Object? _coerceToSchemaType(
    Object? rawValue,
    Map<String, Object?>? fieldNode,
  ) {
    if (rawValue == null || fieldNode == null) return rawValue;
    final rawType = fieldNode['type'];
    String? primaryType;
    if (rawType is String) {
      primaryType = rawType;
    } else if (rawType is List) {
      for (final candidate in rawType) {
        if (candidate is String && candidate != 'null') {
          primaryType = candidate;
          break;
        }
      }
    }
    if (primaryType == null) return rawValue;
    if (rawValue is String) {
      final trimmed = rawValue.trim();
      switch (primaryType) {
        case 'integer':
          return int.tryParse(trimmed) ?? rawValue;
        case 'number':
          return num.tryParse(trimmed.replaceAll(',', '.')) ?? rawValue;
        case 'boolean':
          final lower = trimmed.toLowerCase();
          if (lower == 'true' || lower == '1' || lower == 'oui') return true;
          if (lower == 'false' || lower == '0' || lower == 'non') return false;
          return rawValue;
      }
    }
    return rawValue;
  }

  static Map<String, dynamic> _updatedNestedMap(
    Map<dynamic, dynamic> source,
    String dottedPath,
    Object? value,
  ) {
    final copy = <String, dynamic>{
      for (final entry in source.entries) entry.key.toString(): entry.value,
    };
    _writeNestedField(copy, dottedPath, value);
    return copy;
  }

  static void _writeNestedField(
    Map<String, dynamic> target,
    String dottedPath,
    Object? value,
  ) {
    final parts = dottedPath.split('.');
    Map<String, dynamic> current = target;
    for (var i = 0; i < parts.length - 1; i++) {
      final key = parts[i];
      final next = current[key];
      if (next is Map) {
        final cloned = <String, dynamic>{
          for (final entry in next.entries) entry.key.toString(): entry.value,
        };
        current[key] = cloned;
        current = cloned;
      } else {
        final created = <String, dynamic>{};
        current[key] = created;
        current = created;
      }
    }
    current[parts.last] = value;
  }

  static Iterable<String> _childrenOfComponent(ComponentConfig? component) {
    if (component == null) return const <String>[];
    return switch (component) {
      final SuperLayoutConfig layout => layout.placedSlotIds,
      final SuperListViewConfig list => list.template.placedSlotIds,
      final SuperTabConfig tab => tab.placedSlotIds,
      final SuperConditionalConfig cond => cond.placedSlotIds,
      final SuperTreeViewConfig tree => tree.placedSlotIds,
      final SuperTableConfig table => table.placedSlotIds,
      final NativeComponentConfig native => native.placements.values.expand(
        (ids) => ids,
      ),
      final ScaffoldPageConfig scaffold =>
        scaffold.native.placements.values.expand((ids) => ids),
      _ => const <String>[],
    };
  }
}
