/// Construction et ouverture du menu contextuel hiérarchique pour [EditorSlotState].
part of 'editor_slot.dart';

Future<void> _executeSlotMenuSelection(Object? selected) async {
  if (selected is EditorSlotState) {
    if (selected.mounted) {
      await selected.openEditor();
    }
  } else if (selected is Future<void> Function()) {
    await selected();
  }
}

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
    if (element is SliverMultiBoxAdaptorElement) {
      return;
    }
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

class _LazySlotMoreMenuButton extends StatefulWidget {
  const _LazySlotMoreMenuButton({
    required this.slot,
    required this.wrapActions,
    required this.wrapChildrenActions,
    required this.canEditWithAi,
    required this.canExportContent,
    required this.canConfigureAsComponent,
    required this.buttonStyle,
    required this.onSelect,
  });

  final EditorSlotState slot;
  final List<EditorSlotWrapAction> wrapActions;
  final List<EditorSlotWrapAction> wrapChildrenActions;
  final bool canEditWithAi;
  final bool canExportContent;
  final bool canConfigureAsComponent;
  final ButtonStyle buttonStyle;
  final void Function(Object selection) onSelect;

  @override
  State<_LazySlotMoreMenuButton> createState() =>
      _LazySlotMoreMenuButtonState();
}

class _LazySlotMoreMenuButtonState extends State<_LazySlotMoreMenuButton> {
  final _controller = MenuController();
  List<Widget>? _menuChildren;

  List<Widget> _buildMenuChildren() {
    final state = widget.slot;
    final onSelect = widget.onSelect;
    final extractableTargets = state.mounted && state.canEdit
        ? collectExtractableTargetsFromSlot(state)
        : const <ExtractableComponentTarget>[];
    return [
      if (widget.canConfigureAsComponent)
        MenuItemButton(
          key: ValueKey('style-menu-configure-as-${state.label}'),
          leadingIcon: const Icon(Icons.settings_suggest_outlined),
          onPressed: () => onSelect(state._openConfigureAsDialog),
          child: const Text('Configure as...'),
        ),
      if (widget.canExportContent)
        MenuItemButton(
          key: ValueKey('style-menu-export-${state.label}'),
          leadingIcon: const Icon(Icons.upload),
          onPressed: () => onSelect(state._exportContent),
          child: const Text('Exporter le contenu...'),
        ),
      if (widget.wrapActions.isNotEmpty)
        SubmenuButton(
          leadingIcon: const Icon(Icons.wrap_text),
          menuChildren: [
            for (final action in widget.wrapActions)
              MenuItemButton(
                leadingIcon: Icon(action.icon),
                onPressed: () => onSelect(action.onSelected),
                child: Text(action.label),
              ),
          ],
          child: const Text('Envelopper dans…'),
        ),
      if (widget.wrapChildrenActions.isNotEmpty)
        SubmenuButton(
          leadingIcon: const Icon(Icons.wrap_text),
          menuChildren: [
            for (final action in widget.wrapChildrenActions)
              MenuItemButton(
                leadingIcon: Icon(action.icon),
                onPressed: () => onSelect(action.onSelected),
                child: Text(action.label),
              ),
          ],
          child: const Text('Envelopper les enfants dans…'),
        ),
      if (extractableTargets.isNotEmpty)
        MenuItemButton(
          key: ValueKey('style-menu-extract-super-values-${state.label}'),
          leadingIcon: const Icon(Icons.data_object),
          onPressed: () => onSelect(() async {
            if (!state.mounted) return;
            final latest = collectExtractableTargetsFromSlot(state);
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
      if (widget.canEditWithAi)
        MenuItemButton(
          key: ValueKey('style-menu-ai-${state.label}'),
          leadingIcon: const Icon(Icons.auto_awesome_outlined),
          onPressed: () => onSelect(state._openAiWithScope),
          child: const Text('Modifier avec l’IA…'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final children = _menuChildren;
    return MenuAnchor(
      controller: _controller,
      consumeOutsideTap: true,
      menuChildren: children ?? const [SizedBox.shrink()],
      builder: (context, controller, child) => IconButton(
        key: ValueKey('style-menu-more-${widget.slot.label}'),
        tooltip: 'Autres options',
        icon: const Icon(Icons.more_vert),
        style: widget.buttonStyle,
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
            return;
          }
          if (_menuChildren == null) {
            setState(() => _menuChildren = _buildMenuChildren());
          }
          controller.open();
        },
      ),
    );
  }
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
    List<EditorSlotAction> stateInlineActions, {
    LayoutAxisAction? axis,
  }) {
    final resolvedAxis = axis ?? state.widget.axisAction?.call();
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
          (resolvedAxis?.scrollable ?? false) ||
          actions.any((action) => action.scrollable) ||
          _hasScrollableOverflow(state.context),
      fixedHeight:
          state.widget.fixedHeight ||
          (resolvedAxis?.fixedHeight ?? false) ||
          actions.any((action) => action.fixedHeight),
      fixedWidth:
          state.widget.fixedWidth ||
          (resolvedAxis?.fixedWidth ?? false) ||
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
    ({String componentName, bool composable})? composedComponent,
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
        if (composedComponent != null) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: composedComponent.composable
                ? 'Composant composé : ${composedComponent.componentName}'
                : 'Composant forcé : ${composedComponent.componentName}',
            child: Container(
              key: ValueKey('style-menu-composed-indicator-$suffix'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: composedComponent.composable
                    ? EditorComposedComponentBadgePainter.composedPrimary
                          .withValues(alpha: 0.16)
                    : EditorComposedComponentBadgePainter.forcedPrimary
                          .withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: composedComponent.composable
                      ? EditorComposedComponentBadgePainter.composedPrimary
                      : EditorComposedComponentBadgePainter.forcedPrimary,
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    composedComponent.composable
                        ? Icons.extension_outlined
                        : Icons.widgets_outlined,
                    size: 11,
                    color: composedComponent.composable
                        ? EditorComposedComponentBadgePainter.composedPrimary
                        : EditorComposedComponentBadgePainter.forcedPrimary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    composedComponent.componentName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: composedComponent.composable
                          ? EditorComposedComponentBadgePainter.composedPrimary
                          : EditorComposedComponentBadgePainter.forcedPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    VoidCallback? onTap,
  }) {
    Widget content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      ),
    );
    if (onTap != null) {
      content = InkWell(onTap: onTap, child: content);
    }
    return MouseRegion(
      onEnter: (event) {
        if (!target.mounted ||
            !(StyleEditScope.maybeReadOf(target.context)?.value ?? false)) {
          return;
        }
        final initialPos = EditorSlotState._menuInitialPointerPosition;
        if (initialPos != null &&
            (event.position - initialPos).distance <= 1.0) {
          return;
        }
        EditorSlotState._menuInitialPointerPosition = null;
        EditorSlotState._menuHoveredTarget = target;
        EditorSlotState._refreshHoveredTarget();
      },
      onHover: (event) {
        if (!target.mounted ||
            !(StyleEditScope.maybeReadOf(target.context)?.value ?? false)) {
          return;
        }
        final initialPos = EditorSlotState._menuInitialPointerPosition;
        if (initialPos != null) {
          if ((event.position - initialPos).distance <= 1.0) {
            return;
          }
          EditorSlotState._menuInitialPointerPosition = null;
        }
        if (!identical(EditorSlotState._menuHoveredTarget, target)) {
          EditorSlotState._menuHoveredTarget = target;
          EditorSlotState._refreshHoveredTarget();
        }
      },
      onExit: (_) {
        EditorSlotState._menuInitialPointerPosition = null;
        if (!EditorSlotState._menuOpen &&
            identical(EditorSlotState._menuHoveredTarget, target)) {
          EditorSlotState._menuHoveredTarget = null;
          EditorSlotState._refreshHoveredTarget();
        }
      },
      child: content,
    );
  }

  List<PopupMenuEntry<Object>> _buildSlotMenuItems({
    required BuildContext hostContext,
    required void Function(Object selection) onSelect,
    required bool interceptItemTap,
    List<EditorSlotAction>? actions,
    ({
      List<EditorSlotState> chain,
      List<EditorSlotAction> extraActions,
      Map<EditorSlotState, List<EditorSlotAction>> inlineActions,
      List<(int, Object)> entries,
    })?
    precomputedAncestry,
  }) {
    if (!mounted) return const [];
    final ancestry = precomputedAncestry ?? _collectMenuAncestry(actions);
    final extraActions = ancestry.extraActions;
    final inlineActions = ancestry.inlineActions;
    final entries = ancestry.entries;
    final hasMenuActions = extraActions.any((action) => !action.inline);
    final hasInsertions = _hasInsertionLevels(actions);
    // Inline actions only render inside an editable entry, never on their own.
    if (entries.isEmpty && !hasMenuActions && !hasInsertions) {
      return const [];
    }
    final theme = Theme.of(hostContext);
    final colors = theme.colorScheme;
    Future<void> openContextualAdd() async {
      if (!mounted) return;
      final latest = _insertionLevels(actions);
      if (latest.isEmpty) return;
      await showContextualAddWizard(context, latest, target: context);
    }

    Future<void> openBehaviorWizard() async {
      if (!mounted) return;
      final behaviorTargets = _behaviorTargets(entries);
      await showComponentBehaviorWizard(
        context: context,
        targets: behaviorTargets,
        target: context,
      );
    }

    Future<void> openDataWizard() async {
      if (!mounted) return;
      final dataTargets = _dataTargets(entries);
      await showComponentDataWizard(
        context: context,
        targets: dataTargets,
        target: context,
      );
    }

    final defaultInsertAction = hasInsertions
        ? openContextualAdd
        : openBehaviorWizard;
    return [
      if (hasInsertions || canEdit) ...[
        PopupMenuItem<Future<void> Function()>(
          height: 28,
          key: const ValueKey('style-menu-insert'),
          value: defaultInsertAction,
          padding: EdgeInsets.zero,
          child: _menuHover(
            this,
            minHeight: 28,
            onTap: interceptItemTap
                ? () => onSelect(defaultInsertAction)
                : null,
            Row(
              children: [
                if (hasInsertions) ...[
                  Expanded(
                    flex: 5,
                    child: Tooltip(
                      message: 'Ajouter un composant',
                      child: InkWell(
                        key: const ValueKey('style-menu-insert-component'),
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => onSelect(openContextualAdd),
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
                                  style: theme.textTheme.labelLarge,
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
                      onTap: () => onSelect(openBehaviorWizard),
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
                                style: theme.textTheme.labelLarge,
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
                      onTap: () => onSelect(openDataWizard),
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
                                style: theme.textTheme.labelLarge,
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
            onTap: interceptItemTap ? () => onSelect(action.onEdit) : null,
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
                    style: _menuIconButtonStyle(hostContext, destructive: true),
                    onPressed: () => onSelect(remove),
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
              onTap: interceptItemTap ? () => onSelect(entry.onSelected) : null,
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
          () {
            final stateEditing =
                StyleEditScope.maybeReadOf(state.context)?.value ?? false;
            final axisAction = state.widget.axisAction?.call();
            final stateInlineActions =
                inlineActions[state] ?? const <EditorSlotAction>[];
            final rowEnabled =
                state.widget.onEdit != null || stateInlineActions.isNotEmpty;
            final wrapActions = [
              for (final action in stateInlineActions) ...action.wrapActions,
            ];
            final wrapChildrenActions = stateEditing
                ? state.widget.wrapChildrenActions
                : const <EditorSlotWrapAction>[];
            final canEditWithAi = state._canEditWithAi;
            final canExportContent = state._canExportContent;
            final canConfigureAsComponent = state._canConfigureAsComponent;
            final showMoreButton =
                wrapActions.isNotEmpty ||
                wrapChildrenActions.isNotEmpty ||
                canEditWithAi ||
                canExportContent ||
                canConfigureAsComponent ||
                (state.canEdit && hasExtractableTargetsInSlot(state));
            return PopupMenuItem<EditorSlotState>(
              height: 40,
              key: ValueKey('style-menu-${state.label}'),
              enabled: rowEnabled,
              value: state,
              padding: EdgeInsets.zero,
              child: _menuHover(
                state,
                onTap: interceptItemTap && rowEnabled
                    ? () => onSelect(state)
                    : null,
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
                                stateInlineActions,
                                axis: axisAction,
                              );
                              return _menuTitle(
                                state.titleLabel,
                                destination: state.widget.onEdit == null
                                    ? null
                                    : state.widget.menuDestination,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                tooltip:
                                    state.widget.menuTooltip?.call() ??
                                    axisAction?.flowTooltip,
                                tooltipKey: ValueKey(
                                  'style-menu-tooltip-${state.label}',
                                ),
                                scrollable: indicators.scrollable,
                                fixedHeight: indicators.fixedHeight,
                                fixedWidth: indicators.fixedWidth,
                                composedComponent: state.composedComponentInfo,
                                indicatorKeySuffix: state.label,
                              );
                            }(),
                            if ((state.widget.menuSubtitle?.call() ??
                                    (stateEditing && axisAction != null
                                        ? axisAction.zoneLabel
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
                                    ? ValueKey('style-menu-zone-${state.label}')
                                    : null,
                                style: theme.textTheme.labelSmall?.copyWith(
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
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                          ],
                        ),
                      ),
                      if (stateEditing && axisAction != null) ...[
                        ZoneAxisButton(
                          key: ValueKey('style-menu-axis-${state.label}'),
                          action: LayoutAxisAction(
                            zoneLabel: axisAction.zoneLabel,
                            axis: axisAction.axis,
                            onToggle: () => onSelect(() async {
                              if (state.mounted) {
                                state.widget.axisAction!().onToggle();
                              }
                            }),
                          ),
                        ),
                        if (axisAction.onEditFlow case final editFlow?)
                          IconButton(
                            key: ValueKey(
                              'style-menu-zone-flow-${state.label}',
                            ),
                            tooltip:
                                axisAction.flowTooltip ??
                                'Taille et flux de la zone ${axisAction.zoneLabel}',
                            icon: const Icon(Icons.straighten),
                            style: _menuIconButtonStyle(hostContext),
                            onPressed: () => onSelect(() async {
                              if (state.mounted) {
                                await EditorWizardNavigation.openWithTab(
                                  EditorWizardTab.dimensions,
                                  editFlow,
                                );
                              }
                            }),
                          ),
                      ],
                      if (stateEditing && state._canRename)
                        IconButton(
                          key: ValueKey('style-menu-rename-${state.label}'),
                          tooltip: 'Renommer',
                          icon: const Icon(Icons.drive_file_rename_outline),
                          style: _menuIconButtonStyle(hostContext),
                          onPressed: () => onSelect(() async {
                            if (state.mounted) {
                              await state._promptRename();
                            }
                          }),
                        ),
                      for (final action in stateInlineActions) ...[
                        if (action.showEdit)
                          IconButton(
                            key: ValueKey('style-menu-size-${action.label}'),
                            tooltip: action.tooltip ?? action.label,
                            icon: const Icon(Icons.straighten),
                            style: _menuIconButtonStyle(hostContext),
                            onPressed: () => onSelect(() async {
                              if (state.mounted &&
                                  state.widget.onEdit != null &&
                                  action.dimensionDelegateBuilder != null &&
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
                                  delegate: action.dimensionDelegateBuilder
                                      ?.call(),
                                );
                              }
                            }),
                          ),
                        if (action.onRemove case final remove?)
                          IconButton(
                            key: ValueKey('style-menu-remove-${action.label}'),
                            tooltip: 'Supprimer le slot',
                            icon: const Icon(Icons.delete_outline),
                            style: _menuIconButtonStyle(
                              hostContext,
                              destructive: true,
                            ),
                            onPressed: () => onSelect(remove),
                          ),
                      ],
                      if (state.widget.onRemoveChild != null &&
                          stateEditing &&
                          !state._hasNestedEditableTarget)
                        IconButton(
                          key: ValueKey(
                            'style-menu-remove-child-${state.label}',
                          ),
                          tooltip: 'Supprimer le composant enfant',
                          icon: const Icon(Icons.delete_outline),
                          style: _menuIconButtonStyle(
                            hostContext,
                            destructive: true,
                          ),
                          onPressed: () =>
                              onSelect(state.widget.onRemoveChild!),
                        ),
                      if (stateEditing && state.widget.onAdd != null)
                        IconButton(
                          key: ValueKey('style-menu-add-${state.label}'),
                          tooltip: 'Ajouter un slot',
                          icon: const Icon(Icons.add),
                          style: _menuIconButtonStyle(hostContext),
                          onPressed: () => onSelect(state.widget.onAdd!),
                        ),
                      if (showMoreButton)
                        _LazySlotMoreMenuButton(
                          slot: state,
                          wrapActions: wrapActions,
                          wrapChildrenActions: wrapChildrenActions,
                          canEditWithAi: canEditWithAi,
                          canExportContent: canExportContent,
                          canConfigureAsComponent: canConfigureAsComponent,
                          buttonStyle: _menuIconButtonStyle(hostContext),
                          onSelect: onSelect,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }(),
      ],
    ];
  }

  Future<void> _openSlotMenu(
    Offset globalPosition, {
    List<EditorSlotAction>? actions,
    BuildContext? targetContext,
    bool selectTarget = true,
  }) async {
    if (!mounted ||
        !(StyleEditScope.maybeReadOf(context)?.value ?? true) ||
        EditorZoom.suppressContextMenu ||
        (EditorZoomScope.controllerOf(context)?.suppressContextMenu ?? false)) {
      return;
    }
    if (selectTarget &&
        ((EditorSlotState._menuOpen && EditorSlotState._openingMenuThisTurn) ||
            EditorSlotState._pinnedUpdatedThisTurn)) {
      return;
    }
    final ancestry = _collectMenuAncestry(actions);
    final chain = ancestry.chain;
    final origin = targetContext ?? context;
    final zoomController = EditorZoomScope.controllerOf(context);
    if (selectTarget) {
      zoomController?.beginRightClickSelection();
      try {
        final callbacks = <VoidCallback>[];
        if (origin is Element) {
          final chainSet = chain.toSet();
          final slotStates = <EditorSlotState>[];
          var foundSlotBoundary = false;

          void visitElement(Element element) {
            if (element is StatefulElement) {
              final state = element.state;
              if (state is EditorSlotState && chainSet.contains(state)) {
                if (!foundSlotBoundary) {
                  if (state.widget.onContextMenu != null) {
                    foundSlotBoundary = true;
                  } else {
                    slotStates.add(state);
                  }
                }
                if ((StyleEditScope.maybeReadOf(state.context)?.value ??
                        false) &&
                    state.widget.onContextMenu != null) {
                  final onContextMenu = state.widget.onContextMenu!;
                  callbacks.add(() => onContextMenu(globalPosition));
                }
              }
            } else {
              final widget = element.widget;
              if (!foundSlotBoundary &&
                  ((widget is EditorSlotAction &&
                          widget.enabled &&
                          widget.onSelect != null) ||
                      widget is LayoutSelectionScope)) {
                foundSlotBoundary = true;
              }
              if (widget is EditorSlotAction &&
                  widget.enabled &&
                  widget.onSelect != null &&
                  (StyleEditScope.maybeReadOf(element)?.value ?? false)) {
                callbacks.add(widget.onSelect!);
              }
            }
          }

          visitElement(origin);
          origin.visitAncestorElements((element) {
            visitElement(element);
            return true;
          });
          for (final callback in callbacks.reversed) {
            callback();
          }
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
        } else {
          for (final state in chain) {
            if ((StyleEditScope.maybeReadOf(state.context)?.value ?? false) &&
                state.widget.onContextMenu != null) {
              final onContextMenu = state.widget.onContextMenu!;
              callbacks.add(() => onContextMenu(globalPosition));
            }
          }
          for (final callback in callbacks.reversed) {
            callback();
          }
        }
      } finally {
        zoomController?.endRightClickSelection();
      }
    }
    if (!mounted) return;
    final overlayState = Overlay.of(context);
    final pinnedHost = _PinnedContextMenuHost.maybeOf(overlayState);
    if (pinnedHost != null && pinnedHost.isPinned) {
      EditorSlotState._pinnedUpdatedThisTurn = true;
      scheduleMicrotask(() {
        EditorSlotState._pinnedUpdatedThisTurn = false;
      });
      pinnedHost.updateTarget(
        target: this,
        actions: actions,
        targetContext: targetContext,
      );
      return;
    }
    final navigator = Navigator.of(context);
    final items = _buildSlotMenuItems(
      hostContext: context,
      onSelect: (selection) {
        if (navigator.mounted) {
          navigator.pop<Object>(selection);
        }
      },
      interceptItemTap: false,
      actions: actions,
      precomputedAncestry: ancestry,
    );
    if (items.isEmpty) return;
    final overlay = overlayState.context.findRenderObject()! as RenderBox;
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
          Rect? contentBounds;
          if (zoomOptions != null &&
              zoomOptions.skipLargeElementsOnRightClick &&
              zoomController != null) {
            contentBounds = zoomController.targetBounds(candidate);
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
            if (contentBounds == null &&
                zoomOptions != null &&
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
    await _presentUnpinnedSlotMenu(
      overlayState: overlayState,
      navigator: navigator,
      position: position,
      menuConstraints: menuConstraints,
      bannerLocal: bannerLocal,
      avoidRectResolver: selectTarget ? resolveAvoidRect : null,
      globalPointerPosition: globalPosition,
      initiallyDragged: false,
      instantOpen: false,
      selectTarget: selectTarget,
      items: items,
      actions: actions,
      targetContext: targetContext,
    );
  }

  Future<void> _openUnpinnedFromPin({
    required Offset position,
    required BoxConstraints constraints,
    List<EditorSlotAction>? actions,
    BuildContext? targetContext,
  }) async {
    if (!mounted || !(StyleEditScope.maybeReadOf(context)?.value ?? true)) {
      return;
    }
    final navigator = Navigator.of(context);
    final overlayState = Overlay.of(context);
    final items = _buildSlotMenuItems(
      hostContext: context,
      onSelect: (selection) {
        if (navigator.mounted) {
          navigator.pop<Object>(selection);
        }
      },
      interceptItemTap: false,
      actions: actions,
    );
    if (items.isEmpty) return;
    await _presentUnpinnedSlotMenu(
      overlayState: overlayState,
      navigator: navigator,
      position: position,
      menuConstraints: constraints,
      bannerLocal: null,
      avoidRectResolver: null,
      globalPointerPosition: null,
      initiallyDragged: true,
      instantOpen: true,
      selectTarget: false,
      items: items,
      actions: actions,
      targetContext: targetContext,
    );
  }

  Future<void> _presentUnpinnedSlotMenu({
    required OverlayState overlayState,
    required NavigatorState navigator,
    required Offset position,
    required BoxConstraints menuConstraints,
    required Rect? bannerLocal,
    required Rect? Function()? avoidRectResolver,
    required Offset? globalPointerPosition,
    required bool initiallyDragged,
    required bool instantOpen,
    required bool selectTarget,
    required List<PopupMenuEntry<Object>> items,
    required List<EditorSlotAction>? actions,
    required BuildContext? targetContext,
  }) async {
    final colors = Theme.of(context).colorScheme;
    final overlayThemes = InheritedTheme.capture(
      from: context,
      to: overlayState.context,
    );
    if (EditorSlotState._menuOpen) {
      if (EditorSlotState._openingMenuThisTurn && selectTarget) return;
      EditorSlotState.closeActiveMenu();
      if (!mounted) return;
    }
    final hostRoute = ModalRoute.of(context);
    final generation = ++EditorSlotState._menuGeneration;
    EditorSlotState._menuOpen = true;
    EditorSlotState._openingMenuThisTurn = true;
    EditorSlotState._menuInitialPointerPosition = globalPointerPosition;
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
      EditorSlotState._menuInitialPointerPosition = null;
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
    Offset? pinnedAt;
    Object? selected;
    try {
      selected = await _showEditorContextMenuDialog<Object>(
        context: context,
        initialPosition: position,
        initiallyDragged: initiallyDragged,
        instantOpen: instantOpen,
        bannerLocal: bannerLocal,
        avoidRectResolver: avoidRectResolver,
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
        onPinRequested: (resolvedPosition) => pinnedAt = resolvedPosition,
        items: items,
      );
    } finally {
      if (EditorSlotState._menuGeneration == generation) {
        _ownsOpenMenu = false;
        EditorSlotState._menuOpen = false;
        EditorSlotState._openingMenuThisTurn = false;
        EditorSlotState._menuInitialPointerPosition = null;
        EditorSlotState._activeMenuRoute = null;
        EditorSlotState._dismissActiveMenu = null;
        EditorSlotState._menuHoveredTarget = null;
        EditorSlotState._refreshHoveredTarget();
      } else {
        _ownsOpenMenu = false;
      }
    }
    if (!mounted) return;
    if (pinnedAt case final resolvedPos?) {
      if (!overlayState.mounted) return;
      _PinnedContextMenuHost.of(overlayState).pin(
        target: this,
        position: resolvedPos,
        constraints: menuConstraints,
        themes: overlayThemes,
        actions: actions,
        targetContext: targetContext != null && targetContext.mounted
            ? targetContext
            : null,
      );
      return;
    }
    await _executeSlotMenuSelection(selected);
  }
}
