import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis, Offset, Rect;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Element,
        IconData,
        InheritedWidget,
        PointerDownEvent,
        PointerEvent,
        StatefulElement,
        WidgetsBinding;

import '../../editing/slots/editor_slot.dart' show EditorSlotState;

/// Selection ancestry shared by native page regions and nested layouts.
class LayoutSelectionScope extends InheritedWidget {
  const LayoutSelectionScope({
    required this.path,
    required this.owner,
    this.isSlotScope = false,
    required super.child,
    super.key,
  });

  final List<String> path;
  final Object owner;
  final bool isSlotScope;

  static LayoutSelectionScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayoutSelectionScope>();

  @override
  bool updateShouldNotify(LayoutSelectionScope oldWidget) =>
      !listEquals(path, oldWidget.path) ||
      owner != oldWidget.owner ||
      isSlotScope != oldWidget.isSlotScope;
}

class LayoutFocus {
  const LayoutFocus(this.context);

  final BuildContext context;
}

class LayoutAxisAction {
  const LayoutAxisAction({
    required this.zoneLabel,
    required this.axis,
    required this.onToggle,
    this.onEditFlow,
    this.flowTooltip,
  });

  final String zoneLabel;
  final Axis axis;
  final VoidCallback onToggle;
  final Future<void> Function()? onEditFlow;
  final String? flowTooltip;
}

/// Node in the hierarchy tree under a breadcrumb segment in `StyleEditBanner`.
class LayoutSelectionNode {
  const LayoutSelectionNode({
    this.id,
    required this.label,
    required this.path,
    this.icon,
    this.children = const [],
    this.onSelect,
    this.onContextMenu,
    this.targetContext,
  });

  /// Stable technical identifier of this node (slot id, zone id, or component id).
  final String? id;
  final String label;
  final List<String> path;
  final IconData? icon;
  final List<LayoutSelectionNode> children;
  final VoidCallback? onSelect;
  final ValueChanged<Offset>? onContextMenu;
  final BuildContext? Function()? targetContext;
}

/// Chemin des zones sélectionnées (parent > ... > enfant) dans les dispositions
/// imbriquées, affiché par la bannière du mode édition.
///
/// Chaque disposition visible déclare son chemin ; le plus profond l'emporte.
class LayoutSelection {
  const LayoutSelection._();

  /// Noms des zones sélectionnées, de la plus englobante à la plus profonde.
  static final path = ValueNotifier<List<String>>(const []);
  static final axisAction = ValueNotifier<LayoutAxisAction?>(null);
  static final focus = ValueNotifier<LayoutFocus?>(null);

  /// Identifiant technique du noeud/slot actuellement survolé via le path ou l'arbre.
  static final highlightedSlotId = ValueNotifier<String?>(null);
  static PointerEvent? _pointer;

  /// The deepest selection listener claims each pointer event first.
  static bool claimPointer(PointerDownEvent event) {
    final original = event.original ?? event;
    if (identical(original, _pointer)) return false;
    _pointer = original;
    return true;
  }

  /// Free screen area while an editor dialog is docked.
  static final editorViewport = ValueNotifier<Rect?>(null);

  /// Global screen bounds of the active `StyleEditBanner`, if mounted.
  static Rect? Function()? bannerBounds;

  static final _reported = <Object, List<String>>{};
  static final _axisActions = <Object, LayoutAxisAction>{};
  static final _focusTargets = <Object, LayoutFocus>{};
  static final _clears = <Object, VoidCallback>{};
  static final _targets =
      <
        Object,
        ({
          String? id,
          List<String> path,
          ValueChanged<String?> select,
          Object? parent,
          bool delegateToParent,
        })
      >{};
  static final _slotSelectors = <Object, ValueChanged<String>>{};
  static final _selectedSlotIds = <Object, String? Function()>{};
  static final _deselects = <Object, VoidCallback>{};
  static final _treeBuilders = <Object, List<LayoutSelectionNode> Function()>{};
  static final _contextMenus = <Object, ValueChanged<Offset>>{};
  static final _targetContexts = <Object, BuildContext? Function()>{};
  static Object? _activeOwner;
  static List<String> _leafSuffix = const [];
  static List<String> _leafIds = const [];
  static LayoutFocus? _leafFocus;
  static bool _preserveLeafOnNextReport = false;
  static bool _activating = false;

  /// The container currently owning the deepest reported selection path.
  static Object? get activeOwner => _activeOwner;

  /// Whether a deeper leaf `EditorSlot` inside the selected slot is currently active.
  static bool get hasLeafSuffix => _leafSuffix.isNotEmpty;

  /// Whether [context] is the currently selected leaf `EditorSlot`.
  static bool isLeafFocus(BuildContext context) =>
      _leafSuffix.isNotEmpty && identical(focus.value?.context, context);

  /// Whether [context] is an ancestor element of the current selection focus.
  static bool isAncestorOfFocus(BuildContext context) {
    final focusCtx = focus.value?.context;
    if (focusCtx == null ||
        !focusCtx.mounted ||
        !context.mounted ||
        identical(focusCtx, context)) {
      return false;
    }
    var found = false;
    try {
      focusCtx.visitAncestorElements((element) {
        if (identical(element, context)) {
          found = true;
          return false;
        }
        return true;
      });
    } catch (_) {
      return false;
    }
    return found;
  }

  /// Whether [owner] currently has a non-empty reported path.
  static bool isReported(Object owner) => _reported.containsKey(owner);

  static bool _isAncestor(Object candidate, Object ofOwner) {
    var parent = _targets[ofOwner]?.parent;
    while (parent != null) {
      if (identical(parent, candidate)) return true;
      parent = _targets[parent]?.parent;
    }
    return false;
  }

  static void _removeReported(Object owner) {
    _clears.remove(owner);
    _axisActions.remove(owner);
    _focusTargets.remove(owner);
    _reported.remove(owner);
  }

  static void _syncReported() {
    var best = const <String>[];
    Object? bestOwner;
    for (final entry in _reported.entries) {
      if (entry.value.length >= best.length) {
        best = entry.value;
        bestOwner = entry.key;
      }
    }
    _activeOwner = bestOwner;
    final fullPath = best.isEmpty || _leafSuffix.isEmpty
        ? best
        : List<String>.unmodifiable([...best, ..._leafSuffix]);
    if (!listEquals(path.value, fullPath)) path.value = fullPath;
    axisAction.value = _axisActions[bestOwner];
    if (_leafSuffix.isNotEmpty) {
      final resolvedLeafSlot = resolveSlotForPath(fullPath);
      focus.value =
          _leafFocus ??
          (resolvedLeafSlot != null && resolvedLeafSlot.mounted
              ? LayoutFocus(resolvedLeafSlot.context)
              : _focusTargets[bestOwner]);
    } else {
      focus.value = _focusTargets[bestOwner];
    }
  }

  /// Appends deeper leaf `EditorSlot` labels below the active container's slot.
  static void setLeafSuffix(
    List<String> labels, {
    BuildContext? focusContext,
    List<String>? ids,
  }) {
    final nextFocus = focusContext == null ? null : LayoutFocus(focusContext);
    final nextIds = ids == null || labels.isEmpty
        ? const <String>[]
        : List<String>.unmodifiable(ids);
    _preserveLeafOnNextReport = labels.isNotEmpty;
    if (listEquals(_leafSuffix, labels) &&
        listEquals(_leafIds, nextIds) &&
        _leafFocus?.context == nextFocus?.context) {
      return;
    }
    _leafSuffix = labels.isEmpty ? const [] : List.unmodifiable(labels);
    _leafIds = nextIds;
    _leafFocus = labels.isEmpty ? null : nextFocus;
    _syncReported();
  }

  static void register(
    Object owner,
    List<String> path,
    ValueChanged<String?> select, {
    String? id,
    Object? parent,
    ValueChanged<String>? selectSlot,
    String? Function()? selectedSlotId,
    VoidCallback? onDeselect,
    bool delegateToParent = false,
    List<LayoutSelectionNode> Function()? treeBuilder,
    ValueChanged<Offset>? onContextMenu,
    BuildContext? Function()? targetContext,
  }) {
    if (onDeselect == null) {
      _deselects.remove(owner);
    } else {
      _deselects[owner] = onDeselect;
    }
    if (selectSlot == null) {
      _slotSelectors.remove(owner);
    } else {
      _slotSelectors[owner] = selectSlot;
    }
    if (selectedSlotId == null) {
      _selectedSlotIds.remove(owner);
    } else {
      _selectedSlotIds[owner] = selectedSlotId;
    }
    if (treeBuilder == null) {
      _treeBuilders.remove(owner);
    } else {
      _treeBuilders[owner] = treeBuilder;
    }
    if (onContextMenu == null) {
      _contextMenus.remove(owner);
    } else {
      _contextMenus[owner] = onContextMenu;
    }
    if (targetContext == null) {
      _targetContexts.remove(owner);
    } else {
      _targetContexts[owner] = targetContext;
    }
    _targets[owner] = (
      id: id,
      path: List.unmodifiable(path),
      select: select,
      parent: parent,
      delegateToParent: delegateToParent,
    );
  }

  static void unregister(Object owner) {
    _targets.remove(owner);
    _slotSelectors.remove(owner);
    _selectedSlotIds.remove(owner);
    _deselects.remove(owner);
    _treeBuilders.remove(owner);
    _contextMenus.remove(owner);
    _targetContexts.remove(owner);
  }

  /// Extracts nested selectable `LayoutSelectionNode`s from a slot's widget
  /// subtree (nested layouts, native editors, or deeper `EditorSlot`s).
  static List<LayoutSelectionNode> childrenFromContext(
    BuildContext? slotContext,
    List<String> slotPath,
    VoidCallback selectSlot, {
    Object? ignoreOwner,
  }) {
    if (slotContext is! Element || !slotContext.mounted) return const [];
    final result = <LayoutSelectionNode>[];
    EditorSlotState? rootSlotState;

    List<LayoutSelectionNode> visitElement(
      Element element,
      List<String> parentPath,
      List<String> parentLeafIds,
    ) {
      if (element is StatefulElement) {
        final state = element.state;
        if (!identical(state, ignoreOwner) && _targets.containsKey(state)) {
          final target = _targets[state]!;
          final builder = _treeBuilders[state];
          final children = builder != null
              ? builder()
              : const <LayoutSelectionNode>[];
          if (listEquals(target.path, parentPath) ||
              (parentPath.isNotEmpty &&
                  target.path.isNotEmpty &&
                  target.path.last == parentPath.last &&
                  target.path.length == parentPath.length)) {
            return children;
          }
          return [
            LayoutSelectionNode(
              id: target.id,
              label: target.path.isNotEmpty ? target.path.last : 'Layout',
              path: target.path,
              children: children,
              onSelect: () => target.select(null),
              onContextMenu:
                  _contextMenus[state] ??
                  (position) =>
                      EditorSlotState.openMenuFromContext(element, position),
              targetContext: _targetContexts[state] ?? () => element,
            ),
          ];
        }
        if (state is EditorSlotState &&
            state.canEdit &&
            state.widget.onContextMenu == null) {
          if (rootSlotState == null) {
            rootSlotState = state;
          } else {
            final nodePath = List<String>.unmodifiable([
              ...parentPath,
              state.label,
            ]);
            final nodeLeafIds = List<String>.unmodifiable([
              ...parentLeafIds,
              state.effectiveComponentId,
            ]);
            final leafLabels = nodePath.sublist(slotPath.length);
            final grandChildren = <LayoutSelectionNode>[];
            element.visitChildElements((child) {
              grandChildren.addAll(visitElement(child, nodePath, nodeLeafIds));
            });
            return [
              LayoutSelectionNode(
                id: state.effectiveComponentId,
                label: state.label,
                path: nodePath,
                icon: state.widget.menuIcon ?? state.componentLabel?.menuIcon,
                children: grandChildren,
                onSelect: () {
                  selectSlot();
                  setLeafSuffix(
                    leafLabels,
                    focusContext: state.context,
                    ids: nodeLeafIds,
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    setLeafSuffix(
                      leafLabels,
                      focusContext: state.mounted ? state.context : null,
                      ids: nodeLeafIds,
                    );
                  });
                },
                onContextMenu: (position) =>
                    state.openMenu(position, selectTarget: false),
                targetContext: () => state.context,
              ),
            ];
          }
        }
      }
      final nodes = <LayoutSelectionNode>[];
      element.visitChildElements((child) {
        nodes.addAll(visitElement(child, parentPath, parentLeafIds));
      });
      return nodes;
    }

    slotContext.visitChildElements((child) {
      result.addAll(visitElement(child, slotPath, const []));
    });
    return result;
  }

  static bool _isSameOrAncestorContext(
    BuildContext? ancestor,
    BuildContext? descendant,
  ) {
    if (ancestor == null ||
        descendant == null ||
        !ancestor.mounted ||
        !descendant.mounted) {
      return false;
    }
    if (identical(ancestor, descendant)) return true;
    var found = false;
    try {
      descendant.visitAncestorElements((element) {
        if (identical(element, ancestor)) {
          found = true;
          return false;
        }
        return true;
      });
    } catch (_) {
      return false;
    }
    return found;
  }

  static bool _isNodeActive(
    LayoutSelectionNode node, {
    Object? owner,
    BuildContext? focusContext,
    List<String>? leafIds,
  }) {
    final effectiveFocusCtx =
        focusContext ??
        _leafFocus?.context ??
        focus.value?.context ??
        _focusTargets[_activeOwner]?.context;
    final nodeCtx = node.targetContext?.call();
    if (_isSameOrAncestorContext(nodeCtx, effectiveFocusCtx)) {
      return true;
    }
    if (node.id != null) {
      final ownerSlotId = owner == null
          ? null
          : _selectedSlotIds[owner]?.call();
      if (ownerSlotId != null && node.id == ownerSlotId) {
        return true;
      }
      final effectiveLeafIds = leafIds ?? _leafIds;
      if (effectiveLeafIds.contains(node.id)) {
        return true;
      }
    }
    for (final child in node.children) {
      if (_isNodeActive(
        child,
        owner: owner,
        focusContext: focusContext,
        leafIds: leafIds,
      )) {
        return true;
      }
    }
    return false;
  }

  /// Whether [node] is the currently selected node in the hierarchy.
  static bool isNodeSelected(
    LayoutSelectionNode node,
    List<String> currentPath,
  ) {
    if (!listEquals(node.path, currentPath)) return false;
    final effectiveFocusCtx =
        _leafFocus?.context ??
        focus.value?.context ??
        _focusTargets[_activeOwner]?.context;
    final nodeCtx = node.targetContext?.call();
    if (nodeCtx != null && effectiveFocusCtx != null) {
      if (_isSameOrAncestorContext(nodeCtx, effectiveFocusCtx) ||
          _isSameOrAncestorContext(effectiveFocusCtx, nodeCtx)) {
        return true;
      }
    }
    if (node.id != null) {
      if (_leafIds.isNotEmpty) {
        return node.id == _leafIds.last;
      }
      for (final owner in _activeAncestryOwners()) {
        final slotId = _selectedSlotIds[owner]?.call();
        if (slotId != null) {
          return node.id == slotId;
        }
      }
    }
    return true;
  }

  /// Whether [node] lies on the active selection branch for [currentPath].
  static bool isNodeInActiveBranch(
    LayoutSelectionNode node,
    List<String> currentPath,
  ) {
    if (currentPath.length < node.path.length ||
        !listEquals(currentPath.take(node.path.length).toList(), node.path)) {
      return false;
    }
    if (listEquals(node.path, currentPath)) {
      return isNodeSelected(node, currentPath);
    }
    return _isNodeActive(node);
  }

  static LayoutSelectionNode? _findNode(
    List<LayoutSelectionNode> nodes,
    List<String> targetPath, {
    Object? owner,
    BuildContext? focusContext,
    List<String>? leafIds,
  }) {
    LayoutSelectionNode? firstMatch;
    for (final node in nodes) {
      if (listEquals(node.path, targetPath)) {
        if (_isNodeActive(
          node,
          owner: owner,
          focusContext: focusContext,
          leafIds: leafIds,
        )) {
          return node;
        }
        firstMatch ??= node;
      }
      if (_findNode(
            node.children,
            targetPath,
            owner: owner,
            focusContext: focusContext,
            leafIds: leafIds,
          )
          case final found?) {
        if (_isNodeActive(
          node,
          owner: owner,
          focusContext: focusContext,
          leafIds: leafIds,
        )) {
          return found;
        }
        firstMatch ??= found;
      }
    }
    return firstMatch;
  }

  static List<Object> _activeAncestryOwners() {
    final result = <Object>[];
    var current = _activeOwner;
    while (current != null) {
      result.add(current);
      current = _targets[current]?.parent;
    }
    return result;
  }

  static List<Object> _candidateOwners() {
    final result = _activeAncestryOwners();
    for (final owner in _targets.keys.toList().reversed) {
      if (!result.contains(owner)) result.add(owner);
    }
    return result;
  }

  /// Opens the context menu of the element at [prefix] at [globalPosition]
  /// without altering the currently displayed selection path.
  static void openContextMenu(List<String> prefix, Offset globalPosition) {
    if (prefix.isEmpty) return;
    final activeOwners = _activeAncestryOwners();
    final fallbackOwners = [
      for (final owner in _targets.keys.toList().reversed)
        if (!activeOwners.contains(owner)) owner,
    ];

    bool tryOpenForOwners(List<Object> group) {
      for (final owner in group) {
        final target = _targets[owner];
        final openMenu = _contextMenus[owner];
        if (target != null &&
            !target.delegateToParent &&
            openMenu != null &&
            listEquals(target.path, prefix)) {
          openMenu(globalPosition);
          return true;
        }
      }

      for (final owner in group) {
        final target = _targets[owner];
        final builder = _treeBuilders[owner];
        if (target == null || builder == null) continue;
        if (prefix.length > target.path.length &&
            listEquals(prefix.take(target.path.length).toList(), target.path)) {
          final roots = builder();
          if (_findNode(roots, prefix, owner: owner) case final node?
              when node.onContextMenu != null) {
            node.onContextMenu!(globalPosition);
            return true;
          }
        }
      }

      for (final owner in group) {
        final target = _targets[owner];
        final openMenu = _contextMenus[owner];
        if (target != null &&
            openMenu != null &&
            listEquals(target.path, prefix)) {
          openMenu(globalPosition);
          return true;
        }
      }
      return false;
    }

    if (tryOpenForOwners(activeOwners)) return;
    tryOpenForOwners(fallbackOwners);
  }

  /// Resolves the [LayoutSelectionNode] corresponding to [prefix] in the
  /// selection hierarchy, preferring the active selection branch and ID.
  static LayoutSelectionNode? resolveNodeForPath(List<String> prefix) {
    if (prefix.isEmpty) return null;
    final activeOwners = _activeAncestryOwners();
    final fallbackOwners = [
      for (final owner in _targets.keys.toList().reversed)
        if (!activeOwners.contains(owner)) owner,
    ];
    for (final group in [activeOwners, fallbackOwners]) {
      for (final owner in group) {
        final target = _targets[owner];
        final builder = _treeBuilders[owner];
        if (target == null || builder == null) continue;
        if (prefix.length > target.path.length &&
            listEquals(prefix.take(target.path.length).toList(), target.path)) {
          final roots = builder();
          if (_findNode(roots, prefix, owner: owner) case final node?) {
            return node;
          }
        }
      }
    }
    return null;
  }

  /// Resolves the [EditorSlotState] corresponding to [prefix] in the selection
  /// hierarchy, or `null` if none matches.
  static EditorSlotState? resolveSlotForPath(List<String> prefix) {
    if (prefix.isEmpty) return null;
    final activeOwners = _activeAncestryOwners();
    final fallbackOwners = [
      for (final owner in _targets.keys.toList().reversed)
        if (!activeOwners.contains(owner)) owner,
    ];

    EditorSlotState? resolveInGroup(List<Object> group) {
      // 1. Direct match on a non-delegating registered container's root path.
      for (final owner in group) {
        final target = _targets[owner];
        final getCtx = _targetContexts[owner];
        if (target != null &&
            !target.delegateToParent &&
            listEquals(target.path, prefix)) {
          final ctx =
              getCtx?.call() ?? (owner is StatefulElement ? owner : null);
          if (EditorSlotState.resolveFromContext(ctx) case final slot?) {
            return slot;
          }
        }
      }

      // 2. Match a zone, region, or slot inside an ancestor container's tree.
      for (final owner in group) {
        final target = _targets[owner];
        final builder = _treeBuilders[owner];
        if (target == null || builder == null) continue;
        if (prefix.length > target.path.length &&
            listEquals(prefix.take(target.path.length).toList(), target.path)) {
          final roots = builder();
          if (_findNode(roots, prefix, owner: owner) case final node?) {
            final ctx = node.targetContext?.call();
            if (EditorSlotState.resolveFromContext(ctx) case final slot?) {
              return slot;
            }
          }
        }
      }

      // 3. Fallback on delegating container root path.
      for (final owner in group) {
        final target = _targets[owner];
        final getCtx = _targetContexts[owner];
        if (target != null && listEquals(target.path, prefix)) {
          final ctx = getCtx?.call();
          if (EditorSlotState.resolveFromContext(ctx) case final slot?) {
            return slot;
          }
        }
      }
      return null;
    }

    return resolveInGroup(activeOwners) ?? resolveInGroup(fallbackOwners);
  }

  /// Highlights the component at [prefix] with the editor overlay outline, or
  /// clears the highlight when [prefix] is `null`.
  static void highlightPath(List<String>? prefix) {
    if (prefix == null || prefix.isEmpty) {
      highlightedSlotId.value = null;
      EditorSlotState.clearHighlightedTarget();
      return;
    }
    final node = resolveNodeForPath(prefix);
    highlightedSlotId.value = node?.id;
    final fromNode = node == null
        ? null
        : EditorSlotState.resolveFromContext(node.targetContext?.call());
    EditorSlotState.setHighlightedTarget(
      fromNode ?? resolveSlotForPath(prefix),
    );
  }

  /// Highlights [node] with the editor overlay outline, or clears the highlight
  /// when [node] is `null`.
  static void highlightNode(LayoutSelectionNode? node) {
    if (node == null) {
      highlightedSlotId.value = null;
      EditorSlotState.clearHighlightedTarget();
      return;
    }
    highlightedSlotId.value = node.id;
    final fromCtx = EditorSlotState.resolveFromContext(
      node.targetContext?.call(),
    );
    EditorSlotState.setHighlightedTarget(
      fromCtx ?? resolveSlotForPath(node.path),
    );
  }

  /// Returns the complete tree of selectable children under [prefix].
  static List<LayoutSelectionNode> childrenOf(List<String> prefix) {
    if (prefix.isEmpty) return const [];

    final activeOwners = _activeAncestryOwners();
    final fallbackOwners = [
      for (final owner in _targets.keys.toList().reversed)
        if (!activeOwners.contains(owner)) owner,
    ];

    for (final group in [activeOwners, fallbackOwners]) {
      // 1. Direct match on a registered container's root path.
      for (final owner in group) {
        final target = _targets[owner];
        final builder = _treeBuilders[owner];
        if (target != null &&
            builder != null &&
            listEquals(target.path, prefix)) {
          final built = builder();
          if (built.isNotEmpty) return built;
        }
      }

      // 2. Match a zone, region, or slot inside an ancestor container's tree.
      for (final owner in group) {
        final target = _targets[owner];
        final builder = _treeBuilders[owner];
        if (target == null || builder == null) continue;
        if (prefix.length > target.path.length &&
            listEquals(prefix.take(target.path.length).toList(), target.path)) {
          final roots = builder();
          if (_findNode(roots, prefix, owner: owner) case final node?) {
            return node.children;
          }
        }
      }
    }

    // 3. Fallback from reported path segments (e.g. standalone registered paths).
    final currentPath = path.value;
    if (currentPath.length > prefix.length &&
        listEquals(currentPath.take(prefix.length).toList(), prefix)) {
      LayoutSelectionNode buildChain(int index) {
        final segmentPath = List<String>.unmodifiable(
          currentPath.sublist(0, index + 1),
        );
        return LayoutSelectionNode(
          label: currentPath[index],
          path: segmentPath,
          onSelect: () => select(segmentPath),
          onContextMenu: (position) => openContextMenu(segmentPath, position),
          children: index + 1 < currentPath.length
              ? [buildChain(index + 1)]
              : const [],
        );
      }

      return [buildChain(prefix.length)];
    }

    return const [];
  }

  /// Clears descendants by identity, including inactive layouts with saved
  /// zone or slot selections.
  static void deselectDescendants(Object owner) {
    _leafSuffix = const [];
    _leafIds = const [];
    _leafFocus = null;
    var removedReported = false;
    for (final entry in _targets.entries.toList()) {
      if (_isAncestor(owner, entry.key)) {
        if (_reported.containsKey(entry.key)) {
          _removeReported(entry.key);
          removedReported = true;
        }
        _deselects[entry.key]?.call();
      }
    }
    if (removedReported) _syncReported();
  }

  /// Activates [owner], clearing its descendants as well as any previously
  /// active non-ancestor containers and removing stale ancestor reports.
  static void activate(Object owner) {
    _leafSuffix = const [];
    _leafIds = const [];
    _leafFocus = null;
    _activeOwner = owner;
    var changed = false;
    _activating = true;
    try {
      for (final entry in _targets.entries.toList()) {
        final other = entry.key;
        if (identical(other, owner)) continue;
        if (_isAncestor(owner, other)) {
          if (_reported.containsKey(other)) {
            _removeReported(other);
            changed = true;
          }
          _deselects[other]?.call();
        } else if (!_isAncestor(other, owner)) {
          if (_reported.containsKey(other)) {
            _removeReported(other);
            changed = true;
            _deselects[other]?.call();
          }
        } else if (_reported.containsKey(other)) {
          _removeReported(other);
          changed = true;
        }
      }
    } finally {
      _activating = false;
    }
    if (changed && _reported.isNotEmpty) _syncReported();
  }

  static bool _canParentHandlePrefix(Object? parent, List<String> prefix) {
    if (parent == null) return false;
    final target = _targets[parent];
    if (target == null) return false;
    final length = target.path.length;
    if (!listEquals(prefix.take(length).toList(), target.path)) return false;
    if (prefix.length == length + 2 && _slotSelectors.containsKey(parent)) {
      return true;
    }
    if (prefix.length == length || prefix.length == length + 1) {
      return true;
    }
    return false;
  }

  /// Bascule le segment courant, ou selectionne un segment parent.
  static void toggle(List<String> prefix) {
    if (!listEquals(prefix, path.value)) {
      select(prefix);
      return;
    }
    if (_leafSuffix.isNotEmpty && prefix.length > 1) {
      final newLen = _leafSuffix.length - 1;
      _leafSuffix = _leafSuffix.sublist(0, newLen);
      if (_leafIds.length > newLen) {
        _leafIds = _leafIds.sublist(0, newLen);
      }
      _leafFocus = null;
      _syncReported();
      return;
    }
    Object? active;
    for (final entry in _reported.entries) {
      if (listEquals(entry.value, prefix)) active = entry.key;
    }
    final target = _targets[active];
    if (target == null) return;
    if (prefix.length > target.path.length) {
      select(prefix.sublist(0, prefix.length - 1));
    } else if (target.delegateToParent &&
        target.parent != null &&
        prefix.length > 1) {
      select(prefix.sublist(0, prefix.length - 1));
    } else {
      _deselects[active]?.call();
    }
  }

  /// Active la disposition du segment, et sa zone si le segment en est une.
  static void select(List<String> prefix) {
    final savedFocusCtx =
        _leafFocus?.context ??
        focus.value?.context ??
        _focusTargets[_activeOwner]?.context;
    final savedLeafIds = _leafIds;
    _leafSuffix = const [];
    _leafIds = const [];
    _leafFocus = null;
    Object? active;
    var depth = -1;
    for (final entry in _reported.entries) {
      if (entry.value.length >= depth) {
        active = entry.key;
        depth = entry.value.length;
      }
    }
    // Les libelles peuvent etre identiques : preferer les ancetres de la
    // disposition active aux autres instances portant le meme nom.
    while (active != null) {
      final target = _targets[active];
      if (target == null) break;
      final length = target.path.length;
      if (prefix.length == length + 2 &&
          _slotSelectors.containsKey(active) &&
          listEquals(prefix.take(length).toList(), target.path)) {
        final builder = _treeBuilders[active];
        if (builder != null) {
          if (_findNode(
                builder(),
                prefix,
                owner: active,
                focusContext: savedFocusCtx,
                leafIds: savedLeafIds,
              )
              case final node? when node.onSelect != null) {
            node.onSelect!();
            return;
          }
        }
        target.select(prefix[length]);
        _slotSelectors[active]!(prefix.last);
        return;
      }
      if ((prefix.length == length || prefix.length == length + 1) &&
          !(prefix.length == length &&
              target.delegateToParent &&
              _canParentHandlePrefix(target.parent, prefix)) &&
          listEquals(prefix.take(length).toList(), target.path)) {
        target.select(prefix.length == length ? null : prefix.last);
        return;
      }
      active = target.parent;
    }
    for (final entry in _targets.entries.toList().reversed) {
      final target = entry.value;
      final length = target.path.length;
      if (prefix.length == length + 2 &&
          _slotSelectors.containsKey(entry.key) &&
          listEquals(prefix.take(length).toList(), target.path)) {
        final builder = _treeBuilders[entry.key];
        if (builder != null) {
          if (_findNode(
                builder(),
                prefix,
                owner: entry.key,
                focusContext: savedFocusCtx,
                leafIds: savedLeafIds,
              )
              case final node? when node.onSelect != null) {
            node.onSelect!();
            return;
          }
        }
        target.select(prefix[length]);
        _slotSelectors[entry.key]!(prefix.last);
        return;
      }
      if ((prefix.length == length || prefix.length == length + 1) &&
          !(prefix.length == length &&
              target.delegateToParent &&
              _canParentHandlePrefix(target.parent, prefix)) &&
          listEquals(prefix.take(length).toList(), target.path)) {
        target.select(prefix.length == length ? null : prefix.last);
        return;
      }
    }
    // Fallback for deeper leaf nodes registered via treeBuilder
    for (final owner in _candidateOwners()) {
      final target = _targets[owner];
      final builder = _treeBuilders[owner];
      if (target == null || builder == null) continue;
      if (prefix.length > target.path.length &&
          listEquals(prefix.take(target.path.length).toList(), target.path)) {
        if (_findNode(
              builder(),
              prefix,
              owner: owner,
              focusContext: savedFocusCtx,
              leafIds: savedLeafIds,
            )
            case final node? when node.onSelect != null) {
          node.onSelect!();
          return;
        }
      }
    }
  }

  /// Désélectionne les dispositions dont le chemin prolonge [prefix] : le
  /// niveau désigné devient le plus profond. Les autres sont inchangées.
  static void cut(List<String> prefix) {
    for (final MapEntry(:key, :value) in [..._reported.entries]) {
      if (value.length > prefix.length &&
          listEquals(value.sublist(0, prefix.length), prefix)) {
        _clears[key]?.call();
      }
    }
  }

  /// La disposition [owner] déclare son chemin ; vide, elle se retire. [clear]
  /// désélectionne ses zones.
  static void report(
    Object owner,
    List<String> value, {
    VoidCallback? clear,
    LayoutAxisAction? axis,
    BuildContext? focusContext,
  }) {
    final previous = _reported[owner];
    if (value.isEmpty) {
      _clears.remove(owner);
      _axisActions.remove(owner);
      _focusTargets.remove(owner);
      if (_reported.remove(owner) == null) return;
      if (identical(_activeOwner, owner)) {
        _leafSuffix = const [];
        _leafIds = const [];
        _leafFocus = null;
        _preserveLeafOnNextReport = false;
      }
      if (_activating) return;
    } else {
      if (!listEquals(previous, value)) {
        if (_preserveLeafOnNextReport) {
          _preserveLeafOnNextReport = false;
        } else {
          _leafSuffix = const [];
          _leafIds = const [];
          _leafFocus = null;
        }
      }
      if (clear != null) _clears[owner] = clear;
      if (focusContext == null) {
        _focusTargets.remove(owner);
      } else {
        _focusTargets[owner] = LayoutFocus(focusContext);
      }
      if (axis == null) {
        _axisActions.remove(owner);
      } else {
        _axisActions[owner] = axis;
      }
      // Réinsérée en dernier : à profondeur égale, la plus récente l'emporte.
      if (!listEquals(previous, value)) _reported.remove(owner);
      _reported[owner] = value;
    }
    _syncReported();
  }
}
