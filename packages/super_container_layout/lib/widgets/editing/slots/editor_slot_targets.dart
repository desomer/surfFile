/// Collecte de la chaîne d'édition, des actions contextuelles, des cibles de comportements/données et résolution d'instance pour [EditorSlotState].
part of 'editor_slot.dart';

EditorSlotState? _resolveEditorSlotFromContext(
  BuildContext? targetContext, {
  String? preferredId,
}) {
  if (targetContext is! Element || !targetContext.mounted) return null;
  if (targetContext is StatefulElement &&
      targetContext.state is EditorSlotState) {
    final state = targetContext.state as EditorSlotState;
    if (state.canEdit) return state;
  }
  final candidates = <EditorSlotState>[];
  void visit(Element element) {
    if (element is StatefulElement && element.state is EditorSlotState) {
      final state = element.state as EditorSlotState;
      if (state.canEdit) {
        candidates.add(state);
        return;
      }
    }
    element.visitChildren(visit);
  }

  targetContext.visitChildElements(visit);
  if (candidates.isNotEmpty) {
    final focusCtx = LayoutSelection.focus.value?.context;
    final targetId = preferredId ?? LayoutSelection.activeLeafId;
    for (final state in candidates) {
      if (focusCtx != null && identical(state.context, focusCtx)) {
        return state;
      }
    }
    if (targetId != null && targetId.isNotEmpty) {
      for (final state in candidates) {
        if (state.effectiveComponentId == targetId) {
          return state;
        }
      }
    }
    for (final state in candidates) {
      if (LayoutSelection.isAncestorOfFocus(state.context)) {
        return state;
      }
    }
    return candidates.first;
  }
  return targetContext.findAncestorStateOfType<EditorSlotState>();
}

Future<void> _openEditorMenuFromContext(
  BuildContext? targetContext,
  Offset globalPosition,
) async {
  if (targetContext is! Element || !targetContext.mounted) return;
  if (targetContext is StatefulElement &&
      targetContext.state is EditorSlotState) {
    final state = targetContext.state as EditorSlotState;
    if (state.canEdit) {
      await state.openMenu(globalPosition, selectTarget: false);
      return;
    }
  }
  EditorSlotState? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is EditorSlotState) {
      final state = element.state as EditorSlotState;
      if (state.canEdit) {
        found = state;
        return;
      }
    }
    element.visitChildren(visit);
  }

  targetContext.visitChildElements(visit);
  if (found != null) {
    await found!.openMenu(globalPosition, selectTarget: false);
    return;
  }
  await targetContext.findAncestorStateOfType<EditorSlotState>()?.openMenu(
    globalPosition,
    actions: EditorSlotAction.of(targetContext),
    targetContext: targetContext,
    selectTarget: false,
  );
}

/// Méthodes de renommage et de collecte des cibles hiérarchiques pour [EditorSlotState].
extension _EditorSlotTargetsExtension on EditorSlotState {
  /// Identifiant stable portant l'usage déclaré, ou `null` pour une zone ou
  /// une instance sans identifiant technique.
  String? get _usageComponentId {
    if (widget.zoneId != null) return null;
    final id = widget.id;
    if (id != null && id.isNotEmpty) return id;
    final instanceId = _instance?.id;
    if (instanceId != null && instanceId.isNotEmpty) return instanceId;
    return null;
  }

  Future<void> _promptRename() async {
    final currentLabel = titleLabel;
    final usageId = _usageComponentId;
    final appearance = usageId == null
        ? null
        : AppearanceScope.controllerOf(context);
    final result = await showComponentRenameDialog(
      context: context,
      target: context,
      initialLabel: currentLabel,
      initialUsage: appearance?.value.usageFor(usageId!),
      showUsage: appearance != null,
    );
    if (result == null || !mounted) return;
    final renamed = result.label != currentLabel;
    final usageChanged =
        appearance != null &&
        result.usage != appearance.value.usageFor(usageId!);
    if (!renamed && !usageChanged) return;
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      if (renamed) _renameLabel(result.label);
      if (usageChanged) {
        appearance.value = appearance.value.withUsage(usageId, result.usage);
      }
    } finally {
      history?.commitTransaction();
    }
  }

  bool get _hasNestedEditableTarget {
    var found = false;
    void visit(Element element) {
      if (found) return;
      if (element is StatefulElement &&
          element.state is EditorSlotState &&
          (element.state as EditorSlotState).canEdit) {
        found = true;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  List<EditorSlotState> _computeEditableChain() {
    final chain = <EditorSlotState>[];
    final identities = <Object>{};
    final registry = context
        .getInheritedWidgetOfExactType<SuperAppScope>()
        ?.app
        .registry;
    void record(EditorSlotState state) {
      final identity = state.widget.identity;
      if (state.canEdit && (identity == null || identities.add(identity))) {
        chain.add(state);
      }
    }

    record(this);
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is EditorSlotState) {
        final state = element.state as EditorSlotState;
        final stateRegistry = state.context
            .getInheritedWidgetOfExactType<SuperAppScope>()
            ?.app
            .registry;
        if (!identical(stateRegistry, registry)) return false;
        record(state);
      }
      return true;
    });
    return chain;
  }

  ({
    List<EditorSlotState> chain,
    List<EditorSlotAction> extraActions,
    Map<EditorSlotState, List<EditorSlotAction>> inlineActions,
    List<(int, Object)> entries,
  })
  _collectMenuAncestry(List<EditorSlotAction>? providedActions) {
    final chain = <EditorSlotState>[];
    final chainSet = <EditorSlotState>{};
    final identities = <Object>{};
    final registry = context
        .getInheritedWidgetOfExactType<SuperAppScope>()
        ?.app
        .registry;
    final inlineAncestors = <EditorSlotAction>{};
    final collectedExtraActions = <EditorSlotAction>[];
    var hasExtraInline = false;
    final rawAncestors = <Object>[];

    void recordSlot(EditorSlotState state) {
      final identity = state.widget.identity;
      if (state.canEdit && (identity == null || identities.add(identity))) {
        chain.add(state);
        chainSet.add(state);
      }
    }

    recordSlot(this);
    var crossedRegistry = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditorSlotAction) {
        if (widget.inline) inlineAncestors.add(widget);
        if (widget.enabled) {
          if (providedActions == null && (!widget.inline || !hasExtraInline)) {
            collectedExtraActions.add(widget);
          }
          if (widget.inline) hasExtraInline = true;
          rawAncestors.add(widget);
        }
      } else if (widget is EditorContextMenuEntry && widget.enabled) {
        rawAncestors.add(widget);
      } else if (!crossedRegistry &&
          element is StatefulElement &&
          element.state is EditorSlotState) {
        final state = element.state as EditorSlotState;
        final stateRegistry = state.context
            .getInheritedWidgetOfExactType<SuperAppScope>()
            ?.app
            .registry;
        if (!identical(stateRegistry, registry)) {
          crossedRegistry = true;
        } else {
          recordSlot(state);
          rawAncestors.add(state);
        }
      }
      return true;
    });

    final extraActions = providedActions != null
        ? [
            for (final action in providedActions)
              if (action.enabled) action,
          ]
        : collectedExtraActions;

    final inlineActions = <EditorSlotState, List<EditorSlotAction>>{};
    final entries = <(int, Object)>[
      if (chainSet.contains(this)) (chain.indexOf(this), this),
    ];

    if (chain.isNotEmpty) {
      final below = [
        for (final action in extraActions)
          if (action.inline && !inlineAncestors.contains(action)) action,
      ];
      if (below.isNotEmpty) inlineActions[chain.first] = below;
      EditorSlotState? current = chainSet.contains(this) ? this : null;
      final claimed = <EditorSlotState>{if (below.isNotEmpty) chain.first};
      for (final node in rawAncestors) {
        if (node is EditorSlotState) {
          if (chainSet.contains(node)) {
            current = node;
            entries.add((entries.length, node));
          }
        } else if (node is EditorContextMenuEntry) {
          entries.add((entries.length, node));
        } else if (node is EditorSlotAction && node.inline) {
          final owner = current ?? chain.first;
          if (claimed.add(owner)) (inlineActions[owner] ??= []).add(node);
        }
      }
    } else {
      for (final node in rawAncestors) {
        if (node is EditorContextMenuEntry) {
          entries.add((entries.length, node));
        }
      }
    }

    return (
      chain: chain,
      extraActions: extraActions,
      inlineActions: inlineActions,
      entries: entries,
    );
  }

  /// Indique rapidement si au moins un niveau d'ajout contextuel existe sans
  /// construire les aperçus de placement de tous les ancêtres.
  bool _hasInsertionLevels(List<EditorSlotAction>? provided) {
    if (provided != null) {
      for (final action in provided) {
        if (action.enabled && action.insertion != null) return true;
      }
    }
    var found = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditorSlotAction &&
          widget.enabled &&
          widget.insertion != null) {
        found = true;
        return false;
      }
      if (widget is EditorAddZones && widget.enabled) {
        if (widget.zones().isNotEmpty) {
          found = true;
          return false;
        }
      }
      return true;
    });
    return found;
  }

  /// Contextual addition levels, from the clicked element to its outermost
  /// editable parent: positions around elements and zones of containers.
  /// [provided] holds actions found below this slot.
  List<ContextualAddLevel> _insertionLevels(List<EditorSlotAction>? provided) {
    final seen = Set<Object>.identity();
    final levels = <ContextualAddLevel>[];
    void collect(Widget widget) {
      if (!seen.add(widget)) return;
      if (widget is EditorSlotAction &&
          widget.enabled &&
          widget.insertion != null) {
        levels.add(widget.insertion!);
      } else if (widget is EditorAddZones) {
        if (widget.group() case final group?) levels.add(group);
      }
    }

    provided?.forEach(collect);
    context.visitAncestorElements((element) {
      collect(element.widget);
      return true;
    });
    return levels;
  }

  List<BehaviorTargetElement> _behaviorTargets(List<(int, Object)> entries) {
    final targets = <BehaviorTargetElement>[];
    final titles = <String, int>{};
    String unique(String title) {
      final count = titles[title] = (titles[title] ?? 0) + 1;
      return switch (count) {
        1 => title,
        2 => '$title (parent)',
        _ => '$title (parent ${count - 1})',
      };
    }

    final appearance = AppearanceScope.controllerOf(context)?.value;

    for (final (index, entry) in entries) {
      if (entry is EditorSlotState) {
        final id = entry.effectiveComponentId;
        final existing = appearance?.behaviorsFor(id) ?? const [];
        targets.add(
          BehaviorTargetElement(
            id: id,
            label: unique(entry.label),
            slot: entry,
            icon:
                entry.widget.menuIcon ??
                entry.componentLabel?.menuIcon ??
                (index == 0 ? Icons.widgets_outlined : Icons.folder_outlined),
            depth: index,
            existingBehaviors: existing,
          ),
        );
      }
    }

    if (targets.isEmpty) {
      final id = effectiveComponentId;
      final existing = appearance?.behaviorsFor(id) ?? const [];
      targets.add(
        BehaviorTargetElement(
          id: id,
          label: label,
          slot: this,
          icon:
              widget.menuIcon ??
              componentLabel?.menuIcon ??
              Icons.widgets_outlined,
          depth: 0,
          existingBehaviors: existing,
        ),
      );
    }

    return targets;
  }

  List<DataTargetElement> _dataTargets(List<(int, Object)> entries) {
    final targets = <DataTargetElement>[];
    final titles = <String, int>{};
    String unique(String title) {
      final count = titles[title] = (titles[title] ?? 0) + 1;
      return switch (count) {
        1 => title,
        2 => '$title (parent)',
        _ => '$title (parent ${count - 1})',
      };
    }

    for (final (index, entry) in entries) {
      if (entry is EditorSlotState && entry.mounted) {
        final id = entry.effectiveComponentId;
        targets.add(
          DataTargetElement(
            id: id,
            label: unique(entry.label),
            slot: entry,
            icon:
                entry.widget.menuIcon ??
                entry.componentLabel?.menuIcon ??
                (index == 0 ? Icons.widgets_outlined : Icons.folder_outlined),
            depth: index,
            extractableTargets: collectExtractableTargetsFromSlot(entry),
            recurringGroups: detectRecurringBlockGroups(entry),
            existingBindings: collectExistingBindingsFromSlot(entry),
          ),
        );
      }
    }

    if (targets.isEmpty && mounted) {
      final id = effectiveComponentId;
      targets.add(
        DataTargetElement(
          id: id,
          label: label,
          slot: this,
          icon:
              widget.menuIcon ??
              componentLabel?.menuIcon ??
              Icons.widgets_outlined,
          depth: 0,
          extractableTargets: collectExtractableTargetsFromSlot(this),
          recurringGroups: detectRecurringBlockGroups(this),
          existingBindings: collectExistingBindingsFromSlot(this),
        ),
      );
    }

    return targets;
  }
}
