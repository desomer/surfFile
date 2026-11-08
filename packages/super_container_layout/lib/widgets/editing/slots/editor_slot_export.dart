/// Inspection du graphe vivant et opérations d'export JSON/Dart ainsi que d'ouverture IA pour [EditorSlotState].
part of 'editor_slot.dart';

/// Méthodes d'inspection du sous-arbre vivant et d'export de contenu pour [EditorSlotState].
extension _EditorSlotExportExtension on EditorSlotState {
  String? get _parentComponentIdForAi {
    final selfCanonical = VibeChatScope.canonicalizeId(effectiveComponentId);
    EditorSlotState? ancestor = context
        .findAncestorStateOfType<EditorSlotState>();
    while (ancestor != null) {
      if (ancestor.canEdit) {
        final candidate = VibeChatScope.canonicalizeId(
          ancestor.effectiveComponentId,
        );
        if (candidate.isNotEmpty &&
            candidate != 'component' &&
            candidate != selfCanonical) {
          return candidate;
        }
      }
      ancestor = ancestor.context.findAncestorStateOfType<EditorSlotState>();
    }
    return null;
  }

  VibeChatScope _buildAiScope() {
    final zId = widget.zoneId;
    final parentId = _parentComponentIdForAi;
    if (zId != null && zId.isNotEmpty) {
      final parentLabel = widget.menuSubtitle?.call()?.trim();
      return VibeChatScope(
        componentId: effectiveComponentId,
        label: (parentLabel != null && parentLabel.isNotEmpty)
            ? parentLabel
            : titleLabel,
        zoneId: zId,
        zoneLabel: label,
        parentComponentId: parentId,
      );
    }
    return VibeChatScope(
      componentId: effectiveComponentId,
      label: titleLabel,
      parentComponentId: parentId,
    );
  }

  bool get _canEditWithAi =>
      canEdit && AppearanceScope.controllerOf(context) != null;

  bool get _canExportContent {
    final registry = SuperApp.maybeOf(context)?.registry;
    final appearance = AppearanceScope.controllerOf(context);
    final config =
        appearance?.value.components[effectiveComponentId] ??
        registry?.componentConfigById[effectiveComponentId]?.value;
    return canEdit &&
        widget.eventComponentType != 'renderer' &&
        widget.identity is! AppearanceSlot &&
        appearance != null &&
        registry != null &&
        config is! SuperRendererConfig;
  }

  bool get _canConfigureAsComponent =>
      canEdit &&
      widget.zoneId == null &&
      widget.eventComponentType != 'renderer' &&
      widget.identity is! AppearanceSlot &&
      SuperApp.maybeOf(context)?.registry != null;

  Future<void> _openConfigureAsDialog() async {
    if (!mounted) return;
    final registry = SuperApp.maybeOf(context)?.registry;
    if (registry == null) return;
    final id = effectiveComponentId;
    final scope = RegisteredComponentScope.directOf(context);
    final existing =
        registry.exportOptionsFor(id) ??
        (scope != null
            ? ComponentExportOptions(
                componentName: scope.componentKey,
                generateComponentOnExport: true,
                forceComponentOnExport: !scope.composable,
              )
            : null);
    final result = await showComponentExportConfigDialog(
      context: context,
      componentId: id,
      defaultLabel: titleLabel,
      initialOptions: existing,
      target: context,
    );
    if (result != null && mounted) {
      registry.setExportOptions(id, result);
      if (scope != null && scope.componentKey != id) {
        registry.setExportOptions(scope.componentKey, result);
      }
      _refreshState();
    }
  }

  /// Configurations, styles et comportements vivants de ce slot et de ses descendants declares en code.
  ({
    Map<String, ComponentConfig> configs,
    Map<String, ContainerStyle> styles,
    Map<String, List<ComponentBehavior>> behaviors,
  })
  _liveGraph() {
    final configs = <String, ComponentConfig>{};
    final styles = <String, ContainerStyle>{};
    final behaviors = <String, List<ComponentBehavior>>{};
    final visitedSlots = <String>{};

    void inspectWidget(Widget? candidate, {String? slotId}) {
      if (candidate == null) return;
      if (candidate is RegisteredComponentScope) {
        if (slotId != null && slotId.isNotEmpty) {
          final reg = SuperApp.maybeOf(context)?.registry;
          if (reg != null && reg.exportOptionsFor(slotId) == null) {
            reg.setExportOptions(
              slotId,
              ComponentExportOptions(
                componentName: candidate.componentKey,
                generateComponentOnExport: true,
                forceComponentOnExport: !candidate.composable,
              ),
            );
          }
        }
        inspectWidget(candidate.child, slotId: slotId);
        return;
      }
      if (candidate is SlotImplementation) {
        final effectiveSlotId = slotId ?? candidate.id;
        if (!visitedSlots.add('$effectiveSlotId:${candidate.hashCode}')) return;
        try {
          if (candidate is BuilderSlot) {
            inspectWidget(candidate.builder(context), slotId: effectiveSlotId);
          } else if (candidate is InstanceSlot) {
            inspectWidget(candidate.component, slotId: effectiveSlotId);
          }
        } on Object {
          // Ignore les builders dependant d'un InheritedWidget absent hors branche.
        }
        return;
      }
      if (candidate is EditableSurface) {
        final targetId = slotId ?? candidate.id ?? candidate.slot?.name;
        if (targetId != null && targetId.isNotEmpty) {
          styles.putIfAbsent(targetId, () => candidate.style);
          if (candidate.behaviours case final list? when list.isNotEmpty) {
            behaviors.putIfAbsent(targetId, () => list);
          }
          if (candidate.child != null) {
            final childId = '$targetId:child';
            configs.putIfAbsent(
              targetId,
              () => NativeComponentConfig(
                placements: {
                  'child': [childId],
                },
              ),
            );
            inspectWidget(candidate.child, slotId: childId);
          }
        }
        return;
      }
      if (candidate is SuperLayout) {
        final targetId = (candidate.id != null && candidate.id!.isNotEmpty)
            ? candidate.id!
            : slotId;
        if (targetId != null && targetId.isNotEmpty) {
          configs.putIfAbsent(targetId, () => candidate.config);
          if (slotId != null && slotId.isNotEmpty && slotId != targetId) {
            configs.putIfAbsent(slotId, () => candidate.config);
          }
          if (candidate.behaviours case final list? when list.isNotEmpty) {
            behaviors.putIfAbsent(targetId, () => list);
            if (slotId != null && slotId.isNotEmpty && slotId != targetId) {
              behaviors.putIfAbsent(slotId, () => list);
            }
          }
        }
        for (final slot in candidate.slots) {
          inspectWidget(slot, slotId: slot.id);
        }
        return;
      }
      if (candidate is SuperTab) {
        final targetId = candidate.id.isNotEmpty ? candidate.id : slotId;
        final tabCfg = candidate.config ?? SuperTabConfig();
        if (targetId != null && targetId.isNotEmpty) {
          configs.putIfAbsent(targetId, () => tabCfg);
          if (slotId != null && slotId.isNotEmpty && slotId != targetId) {
            configs.putIfAbsent(slotId, () => tabCfg);
          }
          if (candidate.behaviours case final list? when list.isNotEmpty) {
            behaviors.putIfAbsent(targetId, () => list);
            if (slotId != null && slotId.isNotEmpty && slotId != targetId) {
              behaviors.putIfAbsent(slotId, () => list);
            }
          }
        }
        for (final slot in candidate.slots) {
          inspectWidget(slot, slotId: slot.id);
        }
        return;
      }
      if (candidate is SuperTreeView) {
        final targetId = candidate.id.isNotEmpty ? candidate.id : slotId;
        final treeCfg = candidate.config ?? SuperTreeViewConfig();
        if (targetId != null && targetId.isNotEmpty) {
          configs.putIfAbsent(targetId, () => treeCfg);
          if (slotId != null && slotId.isNotEmpty && slotId != targetId) {
            configs.putIfAbsent(slotId, () => treeCfg);
          }
          if (candidate.templateStyle != const ContainerStyle()) {
            styles.putIfAbsent(
              candidate.itemId ?? treeCfg.itemId ?? targetId,
              () => candidate.templateStyle,
            );
          }
          if (candidate.behaviours case final list? when list.isNotEmpty) {
            behaviors.putIfAbsent(targetId, () => list);
            if (slotId != null && slotId.isNotEmpty && slotId != targetId) {
              behaviors.putIfAbsent(slotId, () => list);
            }
          }
        }
        if (candidate.header != null) {
          inspectWidget(candidate.header, slotId: 'header');
        }
        for (final (i, h) in candidate.headers.indexed) {
          inspectWidget(h, slotId: 'header:$i');
        }
        if (candidate.data != null) {
          inspectWidget(candidate.data, slotId: 'data');
        }
        for (final (i, d) in candidate.datas.indexed) {
          inspectWidget(d, slotId: 'data:$i');
        }
        for (final slot in candidate.slots) {
          inspectWidget(slot, slotId: slot.id);
        }
        return;
      }
      if (candidate is SuperTable) {
        final targetId = candidate.id.isNotEmpty ? candidate.id : slotId;
        final tableCfg = candidate.config ?? SuperTableConfig();
        if (targetId != null && targetId.isNotEmpty) {
          configs.putIfAbsent(targetId, () => tableCfg);
          if (slotId != null && slotId.isNotEmpty && slotId != targetId) {
            configs.putIfAbsent(slotId, () => tableCfg);
          }
          if (candidate.templateStyle != const ContainerStyle()) {
            styles.putIfAbsent(
              candidate.itemId ?? tableCfg.itemId ?? targetId,
              () => candidate.templateStyle,
            );
          }
          if (candidate.behaviours case final list? when list.isNotEmpty) {
            behaviors.putIfAbsent(targetId, () => list);
            if (slotId != null && slotId.isNotEmpty && slotId != targetId) {
              behaviors.putIfAbsent(slotId, () => list);
            }
          }
        }
        for (final slot in candidate.slots) {
          inspectWidget(slot, slotId: slot.id);
        }
        return;
      }
      if (candidate is SuperListView) {
        final targetId = candidate.id.isNotEmpty ? candidate.id : slotId;
        final listCfg = candidate.config.copyWith(template: candidate.template);
        if (targetId != null && targetId.isNotEmpty) {
          configs.putIfAbsent(targetId, () => listCfg);
          if (slotId != null && slotId.isNotEmpty && slotId != targetId) {
            configs.putIfAbsent(slotId, () => listCfg);
          }
          if (candidate.templateStyle != const ContainerStyle()) {
            styles.putIfAbsent(
              candidate.itemId ?? listCfg.itemId ?? targetId,
              () => candidate.templateStyle,
            );
          }
          if (candidate.behaviours case final list? when list.isNotEmpty) {
            behaviors.putIfAbsent(targetId, () => list);
            if (slotId != null && slotId.isNotEmpty && slotId != targetId) {
              behaviors.putIfAbsent(slotId, () => list);
            }
          }
        }
        for (final slot in candidate.slots) {
          inspectWidget(slot, slotId: slot.id);
        }
        return;
      }
      if (candidate is SuperComponent) {
        final comp = candidate as SuperComponent<ComponentConfig?>;
        final compConfig = comp.config;
        final compId = comp.id;
        if (compConfig != null) {
          if (compId != null && compId.isNotEmpty) {
            configs.putIfAbsent(compId, () => compConfig);
          }
          if (slotId != null && slotId.isNotEmpty) {
            configs.putIfAbsent(slotId, () => compConfig);
          }
        }
        if (comp.behaviours case final list? when list.isNotEmpty) {
          if (compId != null && compId.isNotEmpty) {
            behaviors.putIfAbsent(compId, () => list);
          }
          if (slotId != null && slotId.isNotEmpty) {
            behaviors.putIfAbsent(slotId, () => list);
          }
        }
      }
    }

    if (widget.exportConfig case final read?) {
      final cfg = read();
      final isSyntheticProvidedChild =
          cfg is NativeComponentConfig &&
          cfg.placements['child']?.length == 1 &&
          cfg.placements['child']!.single == '__provided-child';
      if (!isSyntheticProvidedChild) {
        configs[effectiveComponentId] = cfg;
      }
    }
    if (widget.behaviors case final list? when list.isNotEmpty) {
      behaviors[effectiveComponentId] = list;
    }

    void visit(Element element) {
      if (element.widget case final ProvidedSlotScope scope) {
        for (final slot in scope.slots) {
          inspectWidget(slot, slotId: slot.id);
        }
      }
      if (element is StatefulElement && element.state is EditableSurfaceState) {
        final surface = element.state as EditableSurfaceState;
        final surfaceId = surface.extractableId;
        if (surfaceId.isNotEmpty) {
          styles.putIfAbsent(surfaceId, () => surface.style);
          if (surface.widget.child != null) {
            final childId = '$surfaceId:child';
            configs.putIfAbsent(
              surfaceId,
              () => NativeComponentConfig(
                placements: {
                  'child': [childId],
                },
              ),
            );
            inspectWidget(surface.widget.child, slotId: childId);
          } else {
            configs.removeWhere((key, value) {
              if (key != surfaceId || value is! NativeComponentConfig) {
                return false;
              }
              final placed = value.placements['child'];
              return placed != null &&
                  placed.length == 1 &&
                  placed.single == '__provided-child';
            });
          }
        }
      }
      if (element is StatefulElement && element.state is EditorSlotState) {
        final slot = element.state as EditorSlotState;
        if (slot.widget.zoneId == null) {
          final id = slot.effectiveComponentId;
          final inheritedSlotId = slot._instance?.id;
          final directScope = RegisteredComponentScope.directOf(slot.context);
          if (directScope != null) {
            final reg = SuperApp.maybeOf(context)?.registry;
            if (reg != null) {
              if (reg.exportOptionsFor(id) == null) {
                reg.setExportOptions(
                  id,
                  ComponentExportOptions(
                    componentName: directScope.componentKey,
                    generateComponentOnExport: true,
                    forceComponentOnExport: !directScope.composable,
                  ),
                );
              }
              if (inheritedSlotId != null &&
                  inheritedSlotId.isNotEmpty &&
                  reg.exportOptionsFor(inheritedSlotId) == null) {
                reg.setExportOptions(
                  inheritedSlotId,
                  ComponentExportOptions(
                    componentName: directScope.componentKey,
                    generateComponentOnExport: true,
                    forceComponentOnExport: !directScope.composable,
                  ),
                );
              }
            }
          }
          if (slot.widget.exportConfig case final read?) {
            final cfg = read();
            final isSyntheticProvidedChild =
                cfg is NativeComponentConfig &&
                cfg.placements['child']?.length == 1 &&
                cfg.placements['child']!.single == '__provided-child';
            if (!isSyntheticProvidedChild) {
              configs.putIfAbsent(id, () => cfg);
              if (inheritedSlotId != null &&
                  inheritedSlotId.isNotEmpty &&
                  inheritedSlotId != id) {
                configs.putIfAbsent(inheritedSlotId, () => cfg);
              }
            }
          }
          if (slot.widget.behaviors case final list? when list.isNotEmpty) {
            behaviors.putIfAbsent(id, () => list);
            if (inheritedSlotId != null &&
                inheritedSlotId.isNotEmpty &&
                inheritedSlotId != id) {
              behaviors.putIfAbsent(inheritedSlotId, () => list);
            }
          }
        }
      }
      element.visitChildren(visit);
    }

    context.visitAncestorElements((ancestor) {
      if (ancestor.widget case final ProvidedSlotScope scope) {
        for (final slot in scope.slots) {
          inspectWidget(slot, slotId: slot.id);
        }
      }
      return true;
    });
    context.visitChildElements(visit);

    // Inspecte egalement les RegisteredComponent references via slotTypes (meme dans des onglets non montes).
    final registry = SuperApp.maybeOf(context)?.registry;
    if (registry != null) {
      for (var changed = true; changed;) {
        changed = false;
        final currentConfigs = configs.values.toList();
        for (final cfg in currentConfigs) {
          final slotTypes = switch (cfg) {
            SuperLayoutConfig() => cfg.slotTypes,
            SuperTabConfig() => cfg.slotTypes,
            SuperTreeViewConfig() => cfg.slotTypes,
            SuperTableConfig() => cfg.slotTypes,
            SuperListViewConfig() => cfg.template.slotTypes,
            NativeComponentConfig() => cfg.slotTypes,
            _ => const <String, String>{},
          };
          for (final entry in slotTypes.entries) {
            final slotId = entry.key;
            final type = entry.value;
            final regKey = type.startsWith('component:')
                ? type.substring('component:'.length)
                : type;
            final registered = registry.components[regKey];
            if (registered != null &&
                !configs.containsKey(slotId) &&
                !styles.containsKey(slotId)) {
              try {
                final built = registered.instanceBuilder != null
                    ? registered.instanceBuilder!(context, slotId)
                    : registered.builder(context);
                inspectWidget(built, slotId: slotId);
                if (configs.containsKey(slotId) || styles.containsKey(slotId)) {
                  changed = true;
                }
              } on Object {
                // Ignore les builders dependant d'un InheritedWidget absent hors branche.
              }
            }
          }
        }
      }
    }

    return (configs: configs, styles: styles, behaviors: behaviors);
  }

  EditorFragmentExport _buildContentExportImpl() {
    final live = _liveGraph();
    return EditorPageGraph.export(
      appearance: AppearanceScope.controllerOf(context)!.value,
      registry: SuperApp.maybeOf(context)!.registry!,
      componentId: effectiveComponentId,
      zoneId: widget.zoneId,
      registryType: widget.menuType,
      liveConfigs: live.configs,
      liveStyles: live.styles,
      liveBehaviors: live.behaviors,
    );
  }

  String _buildDartContentExportImpl([
    EditorFragmentExport? export,
    bool decomposeComponents = false,
  ]) {
    final fragment = export ?? buildContentExport();
    return DartCodeExporter.export(
      appearance: fragment.appearance,
      registry: SuperApp.maybeOf(context)!.registry!,
      componentId: effectiveComponentId,
      componentLabel: label,
      decomposeComponents: decomposeComponents,
    );
  }

  Future<void> _exportContent() async {
    final controller = AppearanceScope.controllerOf(context);
    final registry = SuperApp.maybeOf(context)?.registry;
    if (controller == null || registry == null) return;
    ValueNotifier<Appearance>? fragment;
    try {
      final export = buildContentExport();
      final exportId = effectiveComponentId;
      final exportLabel = label;
      fragment = ValueNotifier(export.appearance);
      final codec = AppearanceServicesScope.codecOf(context);
      await showEditorDialog<void>(
        context: context,
        builder: (_) => AppearanceTransferDialog(
          controller: fragment!,
          codec: codec,
          allowImport: false,
          dartExportWithOptionsBuilder:
              (appearance, {required decomposeComponents}) =>
                  DartCodeExporter.export(
                    appearance: appearance,
                    registry: registry,
                    componentId: exportId,
                    componentLabel: exportLabel,
                    decomposeComponents: decomposeComponents,
                  ),
          notice: export.omitted.isEmpty
              ? null
              : 'Widgets fournis par le code Dart, non exportables et retirés '
                    ': ${export.omitted.join(', ')}.',
        ),
      );
    } on FormatException catch (error) {
      if (mounted) {
        await showEditorDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export impossible'),
            content: Text(error.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          ),
        );
      }
    } finally {
      fragment?.dispose();
    }
  }

  Future<void> _openAiWithScope() async {
    if (!mounted) return;
    await VibeChatDialog.showScoped(context, aiScope);
  }
}
