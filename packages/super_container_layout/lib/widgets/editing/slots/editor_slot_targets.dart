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
  Future<void> _promptRename() async {
    final currentLabel = titleLabel;
    final text = TextEditingController(text: currentLabel);
    final form = GlobalKey<FormState>();
    try {
      final value = await showEditorDialog<String>(
        context: context,
        target: context,
        builder: (dialogContext) {
          void save() {
            if (form.currentState!.validate()) {
              Navigator.of(dialogContext).pop(text.text.trim());
            }
          }

          return AlertDialog(
            title: const Text('Renommer le composant'),
            content: Form(
              key: form,
              child: TextFormField(
                key: const ValueKey('style-menu-rename-input'),
                controller: text,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Le nom ne peut pas être vide.'
                    : null,
                onFieldSubmitted: (_) => save(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                key: const ValueKey('style-menu-rename-save'),
                onPressed: save,
                child: const Text('Renommer'),
              ),
            ],
          );
        },
      );
      if (value != null && value != currentLabel && mounted) {
        _renameLabel(value);
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
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
    final registry = SuperApp.maybeOf(context)?.registry;
    EditorSlotState? state = this;
    while (state != null) {
      if (SuperApp.maybeOf(state.context)?.registry != registry) break;
      final identity = state.widget.identity;
      if (state.canEdit && (identity == null || identities.add(identity))) {
        chain.add(state);
      }
      state = state.context.findAncestorStateOfType<EditorSlotState>();
    }
    return chain;
  }

  Map<EditorSlotState, List<EditorSlotAction>> _inlineActionsByState(
    List<EditorSlotState> chain,
    List<EditorSlotAction> provided,
  ) {
    final result = <EditorSlotState, List<EditorSlotAction>>{};
    if (chain.isEmpty) return result;
    final ancestors = <EditorSlotAction>{};
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditorSlotAction && widget.inline) ancestors.add(widget);
      return true;
    });
    final below = [
      for (final action in provided)
        if (action.inline && !ancestors.contains(action)) action,
    ];
    if (below.isNotEmpty) result[chain.first] = below;
    EditorSlotState? current = chain.contains(this) ? this : null;
    final claimed = <EditorSlotState>{if (below.isNotEmpty) chain.first};
    context.visitAncestorElements((element) {
      final inherited = element.widget;
      if (element is StatefulElement) {
        final state = element.state;
        if (state is EditorSlotState && chain.contains(state)) {
          current = state;
        }
      } else if (inherited is EditorSlotAction &&
          inherited.enabled &&
          inherited.inline) {
        final owner = current ?? chain.first;
        if (claimed.add(owner)) (result[owner] ??= []).add(inherited);
      }
      return true;
    });
    return result;
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
