/// Service d'export d'une [Appearance] en code Dart exécutable.
library;

import '../../../models/native_component_config.dart';
import '../../../models/registry.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../theme/appearance.dart';
import 'dart_codegen_context.dart';

abstract final class DartCodeExporter {
  /// Génère le code Dart complet enregistrant le composant racine dans `_registry`.
  static String export({
    required Appearance appearance,
    required Registry registry,
    String? componentId,
    String? componentLabel,
    bool decomposeComponents = false,
  }) {
    final resolved = _resolveExportRoot(
      appearance: appearance,
      componentId: componentId,
      componentLabel: componentLabel,
    );

    final context = DartCodegenContext(
      appearance: appearance,
      registry: registry,
      rootComponentId: resolved.singleComponentId,
      rootInstanceVariable: 'id',
      decomposeComponents: decomposeComponents,
    );

    final String builderExpression;
    if (resolved.singleComponentId case final rootId?) {
      builderExpression = context.generateComponentWidget(
        rootId,
        slotType: resolved.slotTypes[rootId],
        label: resolved.label,
        indent: 4,
      );
    } else {
      final slotEntries = <String>[
        for (final id in resolved.multipleComponentIds)
          context.generateBuilderSlot(
            id,
            slotType: resolved.slotTypes[id],
            indent: 8,
          ),
      ];
      final placementsCode = context.formatMap({
        'SuperLayoutZone.center': context.formatList([
          for (final id in resolved.multipleComponentIds)
            context.formatString(id),
        ], indent: 10),
      }, indent: 8);
      final configCode = context.formatCall(
        'const SuperLayoutConfig',
        const [],
        {'placements': placementsCode},
        indent: 6,
        forceMultiline: true,
      );
      builderExpression = context.formatCall(
        'SuperLayout',
        const [],
        {
          'id': 'id',
          'label': context.formatString(resolved.label),
          'config': configCode,
          if (slotEntries.isNotEmpty)
            'slots': context.formatList(
              slotEntries,
              indent: 6,
              forceMultiline: true,
            ),
        },
        indent: 4,
        forceMultiline: true,
      );
    }

    final rootOpts = resolved.singleComponentId != null
        ? registry.exportOptionsFor(resolved.singleComponentId!)
        : (componentId != null ? registry.exportOptionsFor(componentId) : null);
    final effectiveRootRegId =
        (rootOpts != null && rootOpts.componentName.trim().isNotEmpty)
        ? rootOpts.componentName.trim()
        : resolved.registrationId;
    final rootCtor =
        (rootOpts != null &&
            rootOpts.generateComponentOnExport &&
            !rootOpts.forceComponentOnExport)
        ? 'RegisteredComponent.composable'
        : 'RegisteredComponent';

    final registeredComponentCode = context.formatCall(
      rootCtor,
      const [],
      {
        'label': context.formatString(resolved.label),
        'isAvailable': '(context) {\n      return true;\n    }',
        'instanceBuilder': '(_, id) => $builderExpression',
      },
      indent: 2,
      forceMultiline: true,
    );

    final mainBlock =
        '_registry.registerComponent(\n'
        '  ${context.formatString(effectiveRootRegId)},\n'
        '  $registeredComponentCode,\n'
        ');\n';

    if (context.extractedSubComponents.isEmpty) {
      return mainBlock;
    }

    // Génère récursivement les sous-composants extraits (des feuilles vers le parent)
    final subBlocks = <String>[];
    final visitedSubIds = <String>{
      if (resolved.singleComponentId != null) resolved.singleComponentId!,
    };

    void generateSubComponents(
      List<
        ({
          String id,
          String registrationId,
          String label,
          String? slotType,
          bool forceComponentOnExport,
        })
      >
      items,
    ) {
      for (final sub in items) {
        if (!visitedSubIds.add(sub.id)) continue;
        final subContext = DartCodegenContext(
          appearance: appearance,
          registry: registry,
          rootComponentId: sub.id,
          rootInstanceVariable: 'id',
          decomposeComponents: decomposeComponents,
        );
        final subExpr = subContext.generateComponentWidget(
          sub.id,
          slotType: sub.slotType,
          label: sub.label,
          indent: 4,
        );
        if (subContext.extractedSubComponents.isNotEmpty) {
          generateSubComponents(subContext.extractedSubComponents);
        }
        final subCtor = sub.forceComponentOnExport
            ? 'RegisteredComponent'
            : 'RegisteredComponent.composable';
        final subRegCode = subContext.formatCall(
          subCtor,
          const [],
          {
            'label': subContext.formatString(sub.label),
            'isAvailable': '(context) {\n      return true;\n    }',
            'instanceBuilder': '(_, id) => $subExpr',
          },
          indent: 2,
          forceMultiline: true,
        );
        subBlocks.add(
          '_registry.registerComponent(\n'
          '  ${subContext.formatString(sub.registrationId)},\n'
          '  $subRegCode,\n'
          ');\n',
        );
      }
    }

    generateSubComponents(context.extractedSubComponents);
    return [...subBlocks, mainBlock].join('\n');
  }

  static String _cleanRegistrationId(String rawId) {
    final trimmed = rawId.trim();
    final stripped = trimmed.replaceFirst(RegExp(r'-(?:i|[0-9]+)$'), '');
    return stripped.isNotEmpty ? stripped : trimmed;
  }

  static ({
    String registrationId,
    String label,
    String? singleComponentId,
    List<String> multipleComponentIds,
    Map<String, String> slotTypes,
  })
  _resolveExportRoot({
    required Appearance appearance,
    String? componentId,
    String? componentLabel,
  }) {
    final homeId = appearance.pageCatalog.homePageId ?? 'root';
    final homePage = appearance.pageCatalog.pages
        .where((p) => p.id == homeId)
        .firstOrNull;
    final homeConfig = appearance.components[homeId];

    // Cas standard de EditorPageGraph.export sur un composant ou une zone :
    // une ScaffoldPageConfig synthétique (__export_root) porte les cibles dans body.
    if (homeConfig is ScaffoldPageConfig &&
        homeId.startsWith('__export_root')) {
      final bodyIds =
          homeConfig.placements[ScaffoldPageRegion.body] ?? const [];
      if (bodyIds.length == 1) {
        final targetId = bodyIds.single;
        final effectiveRegId = _cleanRegistrationId(
          (componentId != null && componentId.trim().isNotEmpty)
              ? componentId.trim()
              : targetId,
        );
        final effectiveLabel =
            (componentLabel != null && componentLabel.trim().isNotEmpty)
            ? componentLabel.trim()
            : (homePage?.name ?? effectiveRegId);
        return (
          registrationId: effectiveRegId,
          label: effectiveLabel,
          singleComponentId: targetId,
          multipleComponentIds: const [],
          slotTypes: homeConfig.slotTypes,
        );
      }
      if (bodyIds.isNotEmpty) {
        final effectiveRegId = _cleanRegistrationId(
          (componentId != null && componentId.trim().isNotEmpty)
              ? componentId.trim()
              : (homePage?.name ?? 'export'),
        );
        final effectiveLabel =
            (componentLabel != null && componentLabel.trim().isNotEmpty)
            ? componentLabel.trim()
            : effectiveRegId;
        return (
          registrationId: effectiveRegId,
          label: effectiveLabel,
          singleComponentId: null,
          multipleComponentIds: bodyIds,
          slotTypes: homeConfig.slotTypes,
        );
      }
    }

    if (componentId != null &&
        (appearance.components.containsKey(componentId) ||
            appearance.styles.containsKey(componentId))) {
      final effectiveLabel =
          (componentLabel != null && componentLabel.trim().isNotEmpty)
          ? componentLabel.trim()
          : componentId;
      return (
        registrationId: _cleanRegistrationId(componentId),
        label: effectiveLabel,
        singleComponentId: componentId,
        multipleComponentIds: const [],
        slotTypes: const {},
      );
    }

    // Cas d'une page complète ou d'une apparence autonome.
    if (homeConfig is ScaffoldPageConfig) {
      final bodyIds =
          homeConfig.placements[ScaffoldPageRegion.body] ?? const [];
      if (bodyIds.length == 1) {
        final single = bodyIds.single;
        return (
          registrationId: _cleanRegistrationId(componentId ?? single),
          label: componentLabel ?? homePage?.name ?? single,
          singleComponentId: single,
          multipleComponentIds: const [],
          slotTypes: homeConfig.slotTypes,
        );
      }
      return (
        registrationId: _cleanRegistrationId(componentId ?? homeId),
        label: componentLabel ?? homePage?.name ?? homeId,
        singleComponentId: null,
        multipleComponentIds: bodyIds,
        slotTypes: homeConfig.slotTypes,
      );
    }

    if (homeConfig is NativeComponentConfig) {
      final bodyIds = homeConfig.placements['body'] ?? const [];
      if (bodyIds.length == 1) {
        final single = bodyIds.single;
        return (
          registrationId: _cleanRegistrationId(componentId ?? single),
          label: componentLabel ?? homePage?.name ?? single,
          singleComponentId: single,
          multipleComponentIds: const [],
          slotTypes: homeConfig.slotTypes,
        );
      }
      if (bodyIds.isNotEmpty) {
        return (
          registrationId: _cleanRegistrationId(componentId ?? homeId),
          label: componentLabel ?? homePage?.name ?? homeId,
          singleComponentId: null,
          multipleComponentIds: bodyIds,
          slotTypes: homeConfig.slotTypes,
        );
      }
    }

    final firstId = appearance.components.keys.firstOrNull ?? 'export';
    return (
      registrationId: _cleanRegistrationId(componentId ?? firstId),
      label: componentLabel ?? firstId,
      singleComponentId: firstId,
      multipleComponentIds: const [],
      slotTypes: const {},
    );
  }
}
