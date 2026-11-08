/// Construction et ouverture du menu contextuel hiérarchique pour [EditorSlotState].
part of 'editor_slot.dart';

EditorSlotAction? _findDirectInlineAction(BuildContext context) {
  if (context is! Element || !context.mounted) return null;
  EditorSlotAction? found;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is EditorSlotAction && widget.inline) {
      found = widget;
      return false;
    }
    if (widget is EditorSlot) {
      return false;
    }
    return true;
  });
  return found;
}

bool _hasScrollableOverflow(BuildContext context) {
  if (context is! Element || !context.mounted) return false;
  var found = false;
  void visit(Element element) {
    if (found) return;
    if (element is StatefulElement) {
      final state = element.state;
      if (state is EditorSlotState && !identical(element, context)) {
        return;
      }
      if (state is ScrollableState) {
        final position = state.position;
        if (position.hasContentDimensions &&
            position.maxScrollExtent > position.minScrollExtent) {
          found = true;
          return;
        }
      }
    }
    element.visitChildren(visit);
  }

  context.visitChildElements(visit);
  return found;
}

/// Méthodes de construction et d'ouverture du menu contextuel de [EditorSlotState].
extension _EditorSlotMenuExtension on EditorSlotState {
  Widget _menuIconBadge(
    IconData icon, {
    required Color background,
    required Color foreground,
  }) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 19, color: foreground),
  );

  Widget _menuIndicatorIcon(
    IconData icon, {
    required String tooltip,
    int quarterTurns = 0,
    Key? key,
  }) {
    Widget iconWidget = Icon(
      icon,
      key: key,
      size: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    if (quarterTurns != 0) {
      iconWidget = RotatedBox(quarterTurns: quarterTurns, child: iconWidget);
    }
    return Tooltip(message: tooltip, child: iconWidget);
  }

  ({bool scrollable, bool fixedHeight, bool fixedWidth}) _resolveSlotIndicators(
    EditorSlotState state,
    List<EditorSlotAction> stateInlineActions,
  ) {
    final axis = state.widget.axisAction?.call();
    final directInline = _findDirectInlineAction(state.context);
    final isZone =
        state.widget.zoneId != null || state.widget.axisAction != null;
    final actions = <EditorSlotAction>{
      if (!isZone) ...stateInlineActions,
      ?directInline,
    };
    return (
      scrollable:
          state.widget.scrollable ||
          (axis?.scrollable ?? false) ||
          actions.any((action) => action.scrollable) ||
          _hasScrollableOverflow(state.context),
      fixedHeight:
          state.widget.fixedHeight ||
          (axis?.fixedHeight ?? false) ||
          actions.any((action) => action.fixedHeight),
      fixedWidth:
          state.widget.fixedWidth ||
          (axis?.fixedWidth ?? false) ||
          actions.any((action) => action.fixedWidth),
    );
  }

  Widget _menuTitle(
    String label, {
    required EditorMenuDestination? destination,
    TextStyle? style,
    String? tooltip,
    Key? tooltipKey,
    bool scrollable = false,
    bool fixedHeight = false,
    bool fixedWidth = false,
    String? indicatorKeySuffix,
  }) {
    final textWidget = Text(
      label,
      style: style ?? Theme.of(context).textTheme.titleSmall,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    final resolvedTooltip = tooltip?.trim();
    final richTooltip = resolvedTooltip != null && resolvedTooltip.isNotEmpty
        ? buildEditorTooltipRichMessage(resolvedTooltip)
        : null;
    final suffix = indicatorKeySuffix ?? label;
    return Row(
      children: [
        if (destination != null) ...[
          _menuIndicatorIcon(
            destination == EditorMenuDestination.style
                ? Icons.palette_outlined
                : Icons.settings_outlined,
            tooltip: destination == EditorMenuDestination.style
                ? 'Ouvre le style'
                : 'Ouvre les paramètres',
          ),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: resolvedTooltip != null && resolvedTooltip.isNotEmpty
              ? Tooltip(
                  key: tooltipKey,
                  message: richTooltip == null ? resolvedTooltip : null,
                  richMessage: richTooltip,
                  ignorePointer: true,
                  child: textWidget,
                )
              : textWidget,
        ),
        if (scrollable) ...[
          const SizedBox(width: 4),
          _menuIndicatorIcon(
            EditorSlot.scrollIndicatorIcon,
            tooltip: 'Scroll activé',
            key: ValueKey('style-menu-scroll-indicator-$suffix'),
          ),
        ],
        if (fixedHeight) ...[
          const SizedBox(width: 4),
          _menuIndicatorIcon(
            EditorSlot.fixedHeightIndicatorIcon,
            tooltip: 'Hauteur fixe',
            key: ValueKey('style-menu-fixed-height-indicator-$suffix'),
          ),
        ],
        if (fixedWidth) ...[
          const SizedBox(width: 4),
          _menuIndicatorIcon(
            EditorSlot.fixedHeightIndicatorIcon,
            tooltip: 'Largeur fixe',
            quarterTurns: 1,
            key: ValueKey('style-menu-fixed-width-indicator-$suffix'),
          ),
        ],
      ],
    );
  }

  ButtonStyle _menuIconButtonStyle(
    BuildContext context, {
    bool destructive = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return IconButton.styleFrom(
      foregroundColor: destructive ? colors.error : colors.onSurfaceVariant,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      minimumSize: const Size.square(36),
    );
  }

  Widget _menuHover(
    EditorSlotState target,
    Widget child, {
    double minHeight = 40,
  }) => Builder(
    builder: (menuContext) {
      EditorSlotState._activeMenuRoute ??= ModalRoute.of(menuContext);
      return MouseRegion(
        onEnter: (_) {
          if (!target.mounted ||
              !(StyleEditScope.controllerOf(target.context)?.value ?? false)) {
            return;
          }
          EditorSlotState._menuHoveredTarget = target;
          EditorSlotState._refreshHoveredTarget();
        },
        onExit: (_) {
          if (!EditorSlotState._menuOpen &&
              identical(EditorSlotState._menuHoveredTarget, target)) {
            EditorSlotState._menuHoveredTarget = null;
            EditorSlotState._refreshHoveredTarget();
          }
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ),
      );
    },
  );

  Future<void> _openSlotMenu(
    Offset globalPosition, {
    List<EditorSlotAction>? actions,
    BuildContext? targetContext,
    bool selectTarget = true,
  }) async {
    if (!mounted ||
        !(StyleEditScope.controllerOf(context)?.value ?? true) ||
        EditorZoom.suppressContextMenu ||
        (EditorZoomScope.controllerOf(context)?.suppressContextMenu ?? false)) {
      return;
    }
    final chain = editableChain;
    final origin = targetContext ?? context;
    final zoomController = EditorZoomScope.controllerOf(context);
    if (selectTarget) {
      zoomController?.beginRightClickSelection();
      try {
        final callbacks = <VoidCallback>[];
        if (origin is Element) {
          void collectElement(Element element) {
            if (element is StatefulElement) {
              final state = element.state;
              if (state is EditorSlotState &&
                  chain.contains(state) &&
                  (StyleEditScope.controllerOf(state.context)?.value ??
                      false) &&
                  state.widget.onContextMenu != null) {
                final onContextMenu = state.widget.onContextMenu!;
                callbacks.add(() => onContextMenu(globalPosition));
              }
            } else {
              final widget = element.widget;
              if (widget is EditorSlotAction &&
                  widget.enabled &&
                  widget.onSelect != null &&
                  (StyleEditScope.controllerOf(element)?.value ?? false)) {
                callbacks.add(widget.onSelect!);
              }
            }
          }

          collectElement(origin);
          origin.visitAncestorElements((element) {
            collectElement(element);
            return true;
          });
        } else {
          for (final state in chain) {
            if ((StyleEditScope.controllerOf(state.context)?.value ?? false) &&
                state.widget.onContextMenu != null) {
              final onContextMenu = state.widget.onContextMenu!;
              callbacks.add(() => onContextMenu(globalPosition));
            }
          }
        }
        for (final callback in callbacks.reversed) {
          callback();
        }
        if (origin is Element) {
          final slotStates = <EditorSlotState>[];
          var foundSlotBoundary = false;
          void collectLeaf(Element element) {
            if (foundSlotBoundary) return;
            if (element is StatefulElement) {
              final state = element.state;
              if (state is EditorSlotState && chain.contains(state)) {
                if (state.widget.onContextMenu != null) {
                  foundSlotBoundary = true;
                  return;
                }
                slotStates.add(state);
              }
            } else {
              final widget = element.widget;
              if ((widget is EditorSlotAction &&
                      widget.enabled &&
                      widget.onSelect != null) ||
                  widget is LayoutSelectionScope) {
                foundSlotBoundary = true;
              }
            }
          }

          collectLeaf(origin);
          origin.visitAncestorElements((element) {
            collectLeaf(element);
            return !foundSlotBoundary;
          });
          if (slotStates.length > 1) {
            final deepestLeaf = slotStates.first;
            final leaves = [
              for (final state in slotStates.reversed.skip(1)) state.label,
            ];
            final leafIds = [
              for (final state in slotStates.reversed.skip(1))
                state.effectiveComponentId,
            ];
            LayoutSelection.setLeafSuffix(
              leaves,
              focusContext: deepestLeaf.context,
              ids: leafIds,
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                zoomController?.beginRightClickSelection();
                try {
                  LayoutSelection.setLeafSuffix(
                    leaves,
                    focusContext: deepestLeaf.mounted
                        ? deepestLeaf.context
                        : null,
                    ids: leafIds,
                  );
                } finally {
                  zoomController?.endRightClickSelection();
                }
              }
            });
          } else if (slotStates.length == 1) {
            final leaf = slotStates.first;
            if (!LayoutSelection.isSelectedSlotContext(leaf.context)) {
              LayoutSelection.updateActiveFocus(
                leaf.context,
                id: leaf.effectiveComponentId,
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && leaf.mounted) {
                  zoomController?.beginRightClickSelection();
                  try {
                    LayoutSelection.updateActiveFocus(
                      leaf.context,
                      id: leaf.effectiveComponentId,
                    );
                  } finally {
                    zoomController?.endRightClickSelection();
                  }
                }
              });
            }
          }
        }
      } finally {
        zoomController?.endRightClickSelection();
      }
    }
    final extraActions = [
      for (final action in actions ?? EditorSlotAction.of(context))
        if (action.enabled) action,
    ];
    final inlineActions = _inlineActionsByState(chain, extraActions);
    final entries = <(int, Object)>[
      if (chain.contains(this)) (chain.indexOf(this), this),
    ];
    context.visitAncestorElements((element) {
      final inherited = element.widget;
      if (inherited is EditorContextMenuEntry && inherited.enabled) {
        entries.add((entries.length, inherited));
      } else if (element is StatefulElement) {
        final state = element.state;
        if (state is EditorSlotState && chain.contains(state)) {
          entries.add((entries.length, state));
        }
      }
      return true;
    });
    final hasMenuActions = extraActions.any((action) => !action.inline);
    final insertions = _insertionLevels(actions);
    final behaviorTargets = _behaviorTargets(entries);
    final dataTargets = _dataTargets(entries);
    // Inline actions only render inside an editable entry, never on their own.
    if (entries.isEmpty && !hasMenuActions && insertions.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final bannerGlobalRect = LayoutSelection.bannerBounds?.call();
    final bannerLocal = bannerGlobalRect == null
        ? null
        : Rect.fromPoints(
            overlay.globalToLocal(bannerGlobalRect.topLeft),
            overlay.globalToLocal(bannerGlobalRect.bottomRight),
          );
    Rect? resolveAvoidRect() {
      if (!selectTarget) return null;
      final zoomOptions = zoomController?.options.value;
      if (zoomOptions != null && !zoomOptions.zoomOnRightClick) {
        return null;
      }
      final overlayRect = Offset.zero & overlay.size;
      final candidateContexts = <BuildContext>[
        ?targetContext,
        context,
        ?LayoutSelection.focus.value?.context,
      ];
      Rect? fallbackRect;
      for (final candidate in candidateContexts) {
        if (!candidate.mounted) continue;
        final box = candidate.findRenderObject();
        if (box is RenderBox &&
            box.attached &&
            box.hasSize &&
            !box.size.isEmpty) {
          if (zoomOptions != null &&
              zoomOptions.skipLargeElementsOnRightClick &&
              zoomController != null) {
            final contentBounds = zoomController.targetBounds(candidate);
            if (contentBounds != null &&
                zoomOptions.isElementTooLarge(contentBounds, overlay.size)) {
              return null;
            }
          }
          final rect = Rect.fromPoints(
            overlay.globalToLocal(box.localToGlobal(Offset.zero)),
            overlay.globalToLocal(
              box.localToGlobal(box.size.bottomRight(Offset.zero)),
            ),
          ).intersect(overlayRect);
          if (!rect.isEmpty && rect.isFinite) {
            if (zoomOptions != null &&
                zoomOptions.skipLargeElementsOnRightClick &&
                zoomOptions.isElementTooLarge(rect, overlay.size)) {
              return null;
            }
            fallbackRect ??= rect;
            if (rect.width < overlay.size.width * .92 ||
                rect.height < overlay.size.height * .92) {
              return rect;
            }
          }
        }
      }
      return fallbackRect;
    }

    var menuConstraints = const BoxConstraints(minWidth: 420, maxWidth: 620);
    if (!selectTarget && bannerLocal != null) {
      final spaceAbove = bannerLocal.top;
      final spaceBelow = overlay.size.height - bannerLocal.bottom;
      if (spaceBelow >= spaceAbove || spaceBelow >= 220) {
        final minTop = bannerLocal.bottom + 6;
        final maxHeight = math.max(120.0, overlay.size.height - minTop - 8);
        menuConstraints = BoxConstraints(
          minWidth: 420,
          maxWidth: 620,
          maxHeight: maxHeight,
        );
      } else {
        final maxBottom = bannerLocal.top - 6;
        final bottomEdge = math.min(position.dy, maxBottom);
        final maxHeight = math.max(120.0, bottomEdge - 8);
        menuConstraints = BoxConstraints(
          minWidth: 420,
          maxWidth: 620,
          maxHeight: maxHeight,
        );
      }
    }
    final colors = Theme.of(context).colorScheme;
    if (EditorSlotState._menuOpen) {
      if (EditorSlotState._openingMenuThisTurn && selectTarget) return;
      EditorSlotState.closeActiveMenu();
      if (!mounted) return;
    }
    final navigator = Navigator.of(context);
    final hostRoute = ModalRoute.of(context);
    final generation = ++EditorSlotState._menuGeneration;
    EditorSlotState._menuOpen = true;
    EditorSlotState._openingMenuThisTurn = true;
    EditorSlotState._activeMenuRoute = null;
    _ownsOpenMenu = true;
    scheduleMicrotask(() {
      if (EditorSlotState._menuGeneration == generation) {
        EditorSlotState._openingMenuThisTurn = false;
      }
    });
    EditorSlotState._dismissActiveMenu = () {
      if (EditorSlotState._menuGeneration != generation) return;
      EditorSlotState._menuGeneration++;
      _ownsOpenMenu = false;
      EditorSlotState._menuOpen = false;
      EditorSlotState._openingMenuThisTurn = false;
      final route = EditorSlotState._activeMenuRoute;
      EditorSlotState._activeMenuRoute = null;
      EditorSlotState._dismissActiveMenu = null;
      EditorSlotState._menuHoveredTarget = null;
      EditorSlotState._refreshHoveredTarget();
      if (!navigator.mounted) return;
      if (route != null) {
        if (route.isActive) {
          navigator.removeRoute(route);
        }
      } else if (hostRoute != null
          ? !hostRoute.isCurrent
          : navigator.canPop()) {
        navigator.pop();
      }
    };
    Object? selected;
    try {
      selected = await _showEditorContextMenuDialog<Object>(
        context: context,
        initialPosition: position,
        bannerLocal: bannerLocal,
        avoidRectResolver: selectTarget ? resolveAvoidRect : null,
        constraints: menuConstraints,
        color: colors.surfaceContainerHigh.withAlpha(240),
        surfaceTintColor: Colors.transparent,
        shadowColor: colors.shadow.withValues(alpha: .18),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        onRouteCreated: (route) => EditorSlotState._activeMenuRoute = route,
        items: [
          if (insertions.isNotEmpty || canEdit) ...[
            PopupMenuItem<Future<void> Function()>(
              height: 28,
              key: const ValueKey('style-menu-insert'),
              value: insertions.isNotEmpty
                  ? () => showContextualAddWizard(
                      context,
                      insertions,
                      target: context,
                    )
                  : () => showComponentBehaviorWizard(
                      context: context,
                      targets: behaviorTargets,
                      target: context,
                    ),
              padding: EdgeInsets.zero,
              child: _menuHover(
                this,
                minHeight: 28,
                Row(
                  children: [
                    if (insertions.isNotEmpty) ...[
                      Expanded(
                        flex: 5,
                        child: Tooltip(
                          message: 'Ajouter un composant',
                          child: InkWell(
                            key: const ValueKey('style-menu-insert-component'),
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => Navigator.of(context)
                                .pop<Future<void> Function()>(
                                  () => showContextualAddWizard(
                                    context,
                                    insertions,
                                    target: context,
                                  ),
                                ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 3,
                                horizontal: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: colors.primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.add,
                                      size: 14,
                                      color: colors.onPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: _menuTitle(
                                      'Composant…',
                                      destination: null,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      flex: 5,
                      child: Tooltip(
                        message: 'Ajouter un comportement',
                        child: InkWell(
                          key: const ValueKey('style-menu-behavior'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () =>
                              Navigator.of(context)
                                  .pop<Future<void> Function()>(
                                    () => showComponentBehaviorWizard(
                                      context: context,
                                      targets: behaviorTargets,
                                      target: context,
                                    ),
                                  ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 3,
                              horizontal: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: colors.tertiary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.bolt,
                                    size: 14,
                                    color: colors.onTertiary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: _menuTitle(
                                    'Comportement…',
                                    destination: null,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 5,
                      child: Tooltip(
                        message: 'Extraire ou gérer les données JSON',
                        child: InkWell(
                          key: const ValueKey('style-menu-data'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => Navigator.of(context)
                              .pop<Future<void> Function()>(
                                () => showComponentDataWizard(
                                  context: context,
                                  targets: dataTargets,
                                  target: context,
                                ),
                              ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 3,
                              horizontal: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: colors.secondary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.data_object,
                                    size: 14,
                                    color: colors.onSecondary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: _menuTitle(
                                    'Donnée…',
                                    destination: null,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasMenuActions || entries.isNotEmpty)
              const PopupMenuDivider(height: 8),
          ],
          for (final (actionIndex, action)
              in extraActions.where((action) => !action.inline).indexed) ...[
            if (actionIndex > 0) const PopupMenuDivider(height: 4),
            PopupMenuItem<Future<void> Function()>(
              height: 40,
              value: action.onEdit,
              padding: EdgeInsets.zero,
              child: _menuHover(
                this,
                Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    _menuIconBadge(
                      Icons.tune_rounded,
                      background: colors.tertiaryContainer,
                      foreground: colors.onTertiaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _menuTitle(
                        action.label,
                        destination: action.destination,
                        tooltip: action.tooltip,
                        tooltipKey: ValueKey(
                          'style-menu-action-tooltip-${action.label}',
                        ),
                        scrollable: action.scrollable,
                        fixedHeight: action.fixedHeight,
                        fixedWidth: action.fixedWidth,
                      ),
                    ),
                    if (action.onRemove case final remove?)
                      IconButton(
                        key: ValueKey('style-menu-remove-${action.label}'),
                        tooltip: 'Supprimer le slot',
                        icon: const Icon(Icons.delete_outline),
                        style: _menuIconButtonStyle(context, destructive: true),
                        onPressed: () => Navigator.of(context).pop(remove),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (hasMenuActions && entries.isNotEmpty)
            const PopupMenuDivider(height: 4),
          for (final (entryIndex, (index, entry)) in entries.indexed) ...[
            if (entryIndex > 0) const PopupMenuDivider(height: 4),
            if (entry is EditorContextMenuEntry)
              PopupMenuItem<Future<void> Function()>(
                height: 40,
                key: ValueKey('style-menu-entry-${entry.label}'),
                value: entry.onSelected,
                padding: EdgeInsets.zero,
                child: _menuHover(
                  this,
                  Padding(
                    padding: EdgeInsets.only(left: _defaultIndent * index),
                    child: Row(
                      children: [
                        _menuIconBadge(
                          Icons.subdirectory_arrow_left,
                          background: colors.secondaryContainer,
                          foreground: colors.onSecondaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _menuTitle(
                            entry.label,
                            destination: entry.destination,
                            tooltip: entry.tooltip,
                            tooltipKey: ValueKey(
                              'style-menu-entry-tooltip-${entry.label}',
                            ),
                            scrollable: entry.scrollable,
                            fixedHeight: entry.fixedHeight,
                            fixedWidth: entry.fixedWidth,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (entry case final EditorSlotState state when state.mounted)
              PopupMenuItem<EditorSlotState>(
                height: 40,
                key: ValueKey('style-menu-${state.label}'),
                enabled: state.widget.onEdit != null,
                value: state,
                padding: EdgeInsets.zero,
                child: _menuHover(
                  state,
                  Padding(
                    padding: EdgeInsets.only(left: _defaultIndent * index),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        _menuIconBadge(
                          state.widget.menuIcon ??
                              state.componentLabel?.menuIcon ??
                              (index == 0
                                  ? Icons.brush_outlined
                                  : Icons.subdirectory_arrow_left),
                          background: colors.primaryContainer,
                          foreground: colors.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              () {
                                final indicators = _resolveSlotIndicators(
                                  state,
                                  inlineActions[state] ??
                                      const <EditorSlotAction>[],
                                );
                                return _menuTitle(
                                  state.titleLabel,
                                  destination: state.widget.onEdit == null
                                      ? null
                                      : state.widget.menuDestination,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  tooltip:
                                      state.widget.menuTooltip?.call() ??
                                      state.widget.axisAction
                                          ?.call()
                                          .flowTooltip,
                                  tooltipKey: ValueKey(
                                    'style-menu-tooltip-${state.label}',
                                  ),
                                  scrollable: indicators.scrollable,
                                  fixedHeight: indicators.fixedHeight,
                                  fixedWidth: indicators.fixedWidth,
                                  indicatorKeySuffix: state.label,
                                );
                              }(),
                              if ((state.widget.menuSubtitle?.call() ??
                                      ((StyleEditScope.controllerOf(
                                                    state.context,
                                                  )?.value ??
                                                  false) &&
                                              state.widget.axisAction != null
                                          ? state.widget.axisAction!().zoneLabel
                                          : state.widget.menuType ??
                                                (state.widget.menuTitle == null
                                                    ? null
                                                    : state.widget.label)))
                                  case final subtitle?
                                  when subtitle != state.titleLabel &&
                                      !(state.widget.menuSubtitle == null &&
                                          state.widget.menuType != null &&
                                          state.widget.menuTitle != null &&
                                          subtitle == state.widget.label))
                                Text(
                                  subtitle,
                                  key:
                                      state.widget.menuSubtitle != null ||
                                          (state.widget.menuType == null &&
                                              state.widget.menuTitle == null)
                                      ? ValueKey(
                                          'style-menu-zone-${state.label}',
                                        )
                                      : null,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              if (state.widget.menuSubtitle == null &&
                                  state.widget.menuType != null &&
                                  state.widget.menuTitle != null &&
                                  state.widget.label != null &&
                                  state.widget.label != state.titleLabel)
                                Text(
                                  state.widget.label!,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                            ],
                          ),
                        ),
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state.widget.axisAction != null) ...[
                          ZoneAxisButton(
                            key: ValueKey('style-menu-axis-${state.label}'),
                            action: LayoutAxisAction(
                              zoneLabel: state.widget.axisAction!().zoneLabel,
                              axis: state.widget.axisAction!().axis,
                              onToggle: () =>
                                  Navigator.of(context)
                                      .pop<Future<void> Function()>(() async {
                                        if (state.mounted) {
                                          state.widget
                                              .axisAction!()
                                              .onToggle();
                                        }
                                      }),
                            ),
                          ),
                          if (state.widget.axisAction!().onEditFlow
                              case final editFlow?)
                            IconButton(
                              key: ValueKey(
                                'style-menu-zone-flow-${state.label}',
                              ),
                              tooltip:
                                  state.widget.axisAction!().flowTooltip ??
                                  'Taille et flux de la zone ${state.widget.axisAction!().zoneLabel}',
                              icon: const Icon(Icons.straighten),
                              style: _menuIconButtonStyle(context),
                              onPressed: () => Navigator.of(context)
                                  .pop<Future<void> Function()>(() async {
                                    if (state.mounted) {
                                      await EditorWizardNavigation.openWithTab(
                                        EditorWizardTab.dimensions,
                                        editFlow,
                                      );
                                    }
                                  }),
                            ),
                        ],
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state._canRename)
                          IconButton(
                            key: ValueKey('style-menu-rename-${state.label}'),
                            tooltip: 'Renommer',
                            icon: const Icon(Icons.drive_file_rename_outline),
                            style: _menuIconButtonStyle(context),
                            onPressed: () =>
                                Navigator.of(context)
                                    .pop<Future<void> Function()>(() async {
                                      if (state.mounted) {
                                        await state._promptRename();
                                      }
                                    }),
                          ),
                        for (final action
                            in inlineActions[state] ??
                                const <EditorSlotAction>[]) ...[
                          if (action.showEdit)
                            IconButton(
                              key: ValueKey('style-menu-size-${action.label}'),
                              tooltip: action.tooltip ?? action.label,
                              icon: const Icon(Icons.straighten),
                              style: _menuIconButtonStyle(context),
                              onPressed: () => Navigator.of(context)
                                  .pop<Future<void> Function()>(() async {
                                    if (state.mounted &&
                                        state.widget.onEdit != null &&
                                        EditorWizardNavigation.findDirectSlotSizeAction(
                                              state.context,
                                            )?.label ==
                                            action.label) {
                                      await state.openEditor(
                                        initialTab: EditorWizardTab.dimensions,
                                        dimensionDelegate: action
                                            .dimensionDelegateBuilder
                                            ?.call(),
                                      );
                                    } else {
                                      await EditorWizardNavigation.openWithTab(
                                        EditorWizardTab.dimensions,
                                        action.onEdit,
                                        delegate: action
                                            .dimensionDelegateBuilder
                                            ?.call(),
                                      );
                                    }
                                  }),
                            ),
                          if (action.onRemove case final remove?)
                            IconButton(
                              key: ValueKey(
                                'style-menu-remove-${action.label}',
                              ),
                              tooltip: 'Supprimer le slot',
                              icon: const Icon(Icons.delete_outline),
                              style: _menuIconButtonStyle(
                                context,
                                destructive: true,
                              ),
                              onPressed: () =>
                                  Navigator.of(context).pop(remove),
                            ),
                        ],
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state.widget.onRemoveChild != null &&
                            !state._hasNestedEditableTarget)
                          IconButton(
                            key: ValueKey(
                              'style-menu-remove-child-${state.label}',
                            ),
                            tooltip: 'Supprimer le composant enfant',
                            icon: const Icon(Icons.delete_outline),
                            style: _menuIconButtonStyle(
                              context,
                              destructive: true,
                            ),
                            onPressed: () => Navigator.of(context)
                                .pop<Future<void> Function()>(
                                  state.widget.onRemoveChild,
                                ),
                          ),
                        if ((StyleEditScope.controllerOf(state.context)
                                    ?.value ??
                                false) &&
                            state.widget.onAdd != null)
                          IconButton(
                            key: ValueKey('style-menu-add-${state.label}'),
                            tooltip: 'Ajouter un slot',
                            icon: const Icon(Icons.add),
                            style: _menuIconButtonStyle(context),
                            onPressed: () =>
                                Navigator.of(context).pop(state.widget.onAdd),
                          ),
                        if ((
                              [
                                for (final action
                                    in inlineActions[state] ??
                                        const <EditorSlotAction>[])
                                  ...action.wrapActions,
                              ],
                              (StyleEditScope.controllerOf(state.context)
                                          ?.value ??
                                      false)
                                  ? state.widget.wrapChildrenActions
                                  : const <EditorSlotWrapAction>[],
                              state.canEdit
                                  ? collectExtractableTargetsFromSlot(state)
                                  : const <ExtractableComponentTarget>[],
                              state._canEditWithAi,
                            )
                            case (
                              final wrapActions,
                              final wrapChildrenActions,
                              final extractableTargets,
                              final canEditWithAi,
                            )
                            when wrapActions.isNotEmpty ||
                                wrapChildrenActions.isNotEmpty ||
                                extractableTargets.isNotEmpty ||
                                canEditWithAi ||
                                state._canExportContent ||
                                state._canConfigureAsComponent)
                          MenuAnchor(
                            consumeOutsideTap: true,
                            menuChildren: [
                              if (state._canConfigureAsComponent)
                                MenuItemButton(
                                  key: ValueKey(
                                    'style-menu-configure-as-${state.label}',
                                  ),
                                  leadingIcon: const Icon(
                                    Icons.settings_suggest_outlined,
                                  ),
                                  onPressed: () => Navigator.of(context)
                                      .pop<Future<void> Function()>(
                                        state._openConfigureAsDialog,
                                      ),
                                  child: const Text('Configure as...'),
                                ),
                              if (state._canExportContent)
                                MenuItemButton(
                                  key: ValueKey(
                                    'style-menu-export-${state.label}',
                                  ),
                                  leadingIcon: const Icon(Icons.upload),
                                  onPressed: () => Navigator.of(context)
                                      .pop<Future<void> Function()>(
                                        state._exportContent,
                                      ),
                                  child: const Text('Exporter le contenu...'),
                                ),
                              if (wrapActions.isNotEmpty)
                                SubmenuButton(
                                  leadingIcon: const Icon(Icons.wrap_text),
                                  menuChildren: [
                                    for (final action in wrapActions)
                                      MenuItemButton(
                                        leadingIcon: Icon(action.icon),
                                        onPressed: () => Navigator.of(context)
                                            .pop<Future<void> Function()>(
                                              action.onSelected,
                                            ),
                                        child: Text(action.label),
                                      ),
                                  ],
                                  child: const Text('Envelopper dans…'),
                                ),
                              if (wrapChildrenActions.isNotEmpty)
                                SubmenuButton(
                                  leadingIcon: const Icon(Icons.wrap_text),
                                  menuChildren: [
                                    for (final action in wrapChildrenActions)
                                      MenuItemButton(
                                        leadingIcon: Icon(action.icon),
                                        onPressed: () => Navigator.of(context)
                                            .pop<Future<void> Function()>(
                                              action.onSelected,
                                            ),
                                        child: Text(action.label),
                                      ),
                                  ],
                                  child: const Text(
                                    'Envelopper les enfants dans…',
                                  ),
                                ),
                              if (extractableTargets.isNotEmpty)
                                MenuItemButton(
                                  key: ValueKey(
                                    'style-menu-extract-super-values-${state.label}',
                                  ),
                                  leadingIcon: const Icon(Icons.data_object),
                                  onPressed: () => Navigator.of(context)
                                      .pop<Future<void> Function()>(() async {
                                        if (!state.mounted) return;
                                        final latest =
                                            collectExtractableTargetsFromSlot(
                                              state,
                                            );
                                        if (latest.isEmpty) return;
                                        await SuperValueJsonExtractDialog.show(
                                          state.context,
                                          targets: latest,
                                          sourceLabel: state.titleLabel,
                                          target: state.context,
                                          rootSlot: state,
                                        );
                                      }),
                                  child: const Text('Extraire & lier en JSON…'),
                                ),
                              if (canEditWithAi)
                                MenuItemButton(
                                  key: ValueKey('style-menu-ai-${state.label}'),
                                  leadingIcon: const Icon(
                                    Icons.auto_awesome_outlined,
                                  ),
                                  onPressed: () => Navigator.of(context)
                                      .pop<Future<void> Function()>(
                                        state._openAiWithScope,
                                      ),
                                  child: const Text('Modifier avec l’IA…'),
                                ),
                            ],
                            builder: (context, controller, child) => IconButton(
                              key: ValueKey('style-menu-more-${state.label}'),
                              tooltip: 'Autres options',
                              icon: const Icon(Icons.more_vert),
                              style: _menuIconButtonStyle(context),
                              onPressed: () => controller.isOpen
                                  ? controller.close()
                                  : controller.open(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      );
    } finally {
      if (EditorSlotState._menuGeneration == generation) {
        _ownsOpenMenu = false;
        EditorSlotState._menuOpen = false;
        EditorSlotState._openingMenuThisTurn = false;
        EditorSlotState._activeMenuRoute = null;
        EditorSlotState._dismissActiveMenu = null;
        EditorSlotState._menuHoveredTarget = null;
        EditorSlotState._refreshHoveredTarget();
      } else {
        _ownsOpenMenu = false;
      }
    }
    if (!mounted) return;
    if (selected is EditorSlotState && selected.mounted) {
      await selected.openEditor();
    } else if (selected is Future<void> Function()) {
      await selected();
    }
  }
}
