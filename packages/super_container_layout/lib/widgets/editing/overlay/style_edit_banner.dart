import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/ai/call_gemini.dart';
import 'package:super_container_layout/services/appearance/appearance_store.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/widgets/appearance/appearance_transfer_dialog.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_chat_dialog.dart';
import 'package:super_container_layout/widgets/editing/history/editor_history.dart';
import 'package:super_container_layout/widgets/editing/repositories/json_repository_manager.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';
import 'package:super_container_layout/widgets/components/super_layout/layout_selection.dart';

/// Pastille deplacable, initialement en haut au centre du mode edition.
///
/// Peut être placée au-dessus du [Navigator] (ex. `MaterialApp.builder`) :
/// elle fournit alors son propre [Overlay] pour l'info-bulle du bouton.
/// Sa frontière sémantique sépare cet overlay de celui du navigateur.
class StyleEditBanner extends StatefulWidget {
  const StyleEditBanner({
    this.navigatorKey,
    this.onManagePages,
    this.aiResponseGenerator,
    this.validateAppearance,
    super.key,
  });

  /// Navigateur de l'application, où s'ouvre la boîte d'import / export : la
  /// bannière est au-dessus de lui. Sans lui, celui du contexte est utilisé.
  final GlobalKey<NavigatorState>? navigatorKey;
  final Future<void> Function()? onManagePages;
  final Future<String> Function(String prompt)? aiResponseGenerator;
  final void Function(Appearance appearance)? validateAppearance;

  @override
  State<StyleEditBanner> createState() => _StyleEditBannerState();
}

class _StyleEditBannerState extends State<StyleEditBanner> {
  _BannerLayout _layout = _BannerLayout(null);
  _VibeChatLayout _chatLayout = _VibeChatLayout(null);
  bool _chatOpen = false;
  final _chevronKeys = <int, GlobalKey>{};
  ({
    int chevronIndex,
    List<String> prefix,
    Rect anchor,
    List<LayoutSelectionNode> nodes,
  })?
  _treePopup;

  @override
  void initState() {
    super.initState();
    _layout = _BannerLayout(
      null,
      available: LayoutSelection.editorViewport.value,
    );
    LayoutSelection.editorViewport.addListener(_reposition);
    LayoutSelection.path.addListener(_onPathChanged);
  }

  void _onPathChanged() {
    final popup = _treePopup;
    if (popup == null) return;
    final current = LayoutSelection.path.value;
    if (current.length < popup.prefix.length ||
        !listEquals(current.take(popup.prefix.length).toList(), popup.prefix)) {
      setState(() => _treePopup = null);
    }
  }

  void _toggleTreePopup(int chevronIndex, List<String> prefix) {
    if (_treePopup?.chevronIndex == chevronIndex) {
      setState(() => _treePopup = null);
      return;
    }
    final nodes = LayoutSelection.childrenOf(prefix);
    if (nodes.isEmpty) return;
    final chevronBox =
        _chevronKeys[chevronIndex]?.currentContext?.findRenderObject();
    final bannerRoot = context.findRenderObject();
    var anchor = Rect.zero;
    if (chevronBox is RenderBox &&
        chevronBox.hasSize &&
        bannerRoot is RenderBox &&
        bannerRoot.hasSize) {
      anchor = MatrixUtils.transformRect(
        chevronBox.getTransformTo(bannerRoot),
        Offset.zero & chevronBox.size,
      );
    }
    setState(() {
      _treePopup = (
        chevronIndex: chevronIndex,
        prefix: List.unmodifiable(prefix),
        anchor: anchor,
        nodes: nodes,
      );
    });
  }

  void _reposition() => setState(() {
    _treePopup = null;
    _layout = _BannerLayout(
      _layout.position,
      available: LayoutSelection.editorViewport.value,
    );
    _chatLayout = _VibeChatLayout(
      _chatLayout.position,
      available: LayoutSelection.editorViewport.value,
    );
  });

  @override
  void dispose() {
    LayoutSelection.editorViewport.removeListener(_reposition);
    LayoutSelection.path.removeListener(_onPathChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: Overlay.maybeOf(context) == null
        ? Overlay.wrap(child: Builder(builder: _buildBanner))
        : _buildBanner(context),
  );

  Widget _buildBanner(BuildContext context) {
    final editMode = StyleEditScope.controllerOf(context);
    if (editMode == null || !editMode.value) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final appearance = AppearanceScope.controllerOf(context);
    final codec = AppearanceServicesScope.codecOf(context);
    final available = LayoutSelection.editorViewport.value;
    final banner = CustomSingleChildLayout(
      delegate: _layout,
      child: GestureDetector(
        onPanUpdate: (details) => setState(() {
          _treePopup = null;
          _layout = _BannerLayout(
            _layout.resolvedPosition + details.delta,
            available: available,
          );
        }),
        child: Material(
          key: const ValueKey('style-edit-banner'),
          color: scheme.primary,
          elevation: 6,
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('style-edit-banner-close'),
                  tooltip: 'Quitter le mode édition',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: scheme.onPrimary,
                  icon: const Icon(Icons.close),
                  onPressed: () => editMode.value = false,
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: Row(
                    key: const ValueKey('style-edit-banner-drag'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.drag_indicator,
                        size: 16,
                        color: scheme.onPrimary,
                      ),
                      // const SizedBox(width: 8),
                      Text(
                        'Mode édition',
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (EditorHistoryScope.controllerOf(context)
                    case final history?)
                  ListenableBuilder(
                    listenable: history,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const ValueKey('style-edit-banner-undo'),
                          tooltip: 'Annuler (Ctrl+Z)',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          color: scheme.onPrimary,
                          onPressed: history.canUndo ? history.undo : null,
                          icon: const Icon(Icons.undo),
                        ),
                        IconButton(
                          key: const ValueKey('style-edit-banner-redo'),
                          tooltip: 'Rétablir (Ctrl+Y)',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          color: scheme.onPrimary,
                          onPressed: history.canRedo ? history.redo : null,
                          icon: const Icon(Icons.redo),
                        ),
                      ],
                    ),
                  ),
                if (widget.onManagePages != null)
                  IconButton(
                    key: const ValueKey('style-edit-banner-pages'),
                    tooltip: 'Gérer les pages',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: scheme.onPrimary,
                    icon: const Icon(Icons.web_stories_outlined),
                    onPressed: widget.onManagePages,
                  ),
                IconButton(
                  key: const ValueKey('style-edit-banner-repository'),
                  tooltip: 'Repository',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: scheme.onPrimary,
                  icon: const Icon(Icons.storage_outlined),
                  onPressed: () {
                    final target =
                        widget.navigatorKey?.currentContext ?? context;
                    JsonRepositoryManager.show(target);
                  },
                ),
                if (appearance != null)
                  IconButton(
                    key: const ValueKey('style-edit-banner-ai'),
                    tooltip: 'Générer un écran avec l’IA',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: scheme.onPrimary,
                    isSelected: _chatOpen,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    onPressed: () => setState(() {
                      _chatOpen = !_chatOpen;
                      if (_chatOpen) {
                        _chatLayout = _VibeChatLayout(
                          null,
                          available: available,
                        );
                      }
                    }),
                  ),
                if (AppearanceScope.controllerOf(context)
                    case final appearance?)
                  IconButton(
                    key: const ValueKey('style-edit-banner-transfer'),
                    tooltip: 'Importer / exporter le style et la disposition',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: scheme.onPrimary,
                    icon: const Icon(Icons.import_export),
                    onPressed: () {
                      final target =
                          widget.navigatorKey?.currentContext ?? context;
                      if (Navigator.maybeOf(target) == null) return;
                      AppearanceTransferDialog.show(target, appearance);
                    },
                  ),

                // Dispositions et zones sélectionnées : parent > ... > enfant.
                Flexible(
                  child: ValueListenableBuilder<List<String>>(
                    valueListenable: LayoutSelection.path,
                    builder: (context, path, _) => path.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              // Le plus profond reste visible quand le chemin
                              // dépasse la largeur.
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                child: Row(
                                  key: const ValueKey('style-edit-banner-path'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final (index, label)
                                        in path.indexed) ...[
                                      if (index > 0)
                                        _PathChevron(
                                          key: _chevronKeys.putIfAbsent(
                                            index - 1,
                                            GlobalKey.new,
                                          ),
                                          valueKey: ValueKey(
                                            'style-edit-banner-chevron-${index - 1}',
                                          ),
                                          active:
                                              _treePopup?.chevronIndex ==
                                              index - 1,
                                          onTap: () => _toggleTreePopup(
                                            index - 1,
                                            path.sublist(0, index),
                                          ),
                                        ),
                                      _PathSegment(
                                        key: ValueKey(
                                          'style-edit-banner-path-$index',
                                        ),
                                        label: label,
                                        current: index == path.length - 1,
                                        onTap: () {
                                          if (_treePopup != null) {
                                            setState(() => _treePopup = null);
                                          }
                                          LayoutSelection.toggle(
                                            path.sublist(0, index + 1),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 4),
                // ValueListenableBuilder<LayoutAxisAction?>(
                //   valueListenable: LayoutSelection.axisAction,
                //   builder: (context, action, _) => action == null
                //       ? const SizedBox.shrink()
                //       : ZoneAxisButton(
                //           key: const ValueKey('style-edit-banner-axis'),
                //           action: action,
                //           color: scheme.onPrimary,
                //         ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
    final showChat = _chatOpen && appearance != null;
    final popup = _treePopup;
    if (!showChat && popup == null) return banner;
    return Stack(
      children: [
        if (popup != null)
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('style-edit-banner-tree-barrier'),
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _treePopup = null),
            ),
          ),
        banner,
        if (popup != null)
          CustomSingleChildLayout(
            delegate: _TreePopupLayout(
              anchor: popup.anchor,
              available: available,
            ),
            child: _PathTreeDialog(
              parentLabel: popup.prefix.last,
              nodes: popup.nodes,
              currentPath: LayoutSelection.path.value,
              onClose: () => setState(() => _treePopup = null),
              onSelectNode: (node) {
                setState(() => _treePopup = null);
                if (node.onSelect != null) {
                  node.onSelect!();
                } else {
                  LayoutSelection.select(node.path);
                }
              },
            ),
          ),
        if (showChat)
          CustomSingleChildLayout(
            delegate: _chatLayout,
            child: VibeChatDialog(
              registry: SuperApp.maybeOf(context)?.registry,
              controller: appearance,
              codec: codec,
              onClose: () => setState(() => _chatOpen = false),
              onDrag: (delta) => setState(
                () => _chatLayout = _VibeChatLayout(
                  _chatLayout.resolvedPosition + delta,
                  available: available,
                ),
              ),
              generate: widget.aiResponseGenerator ?? callGemini,
              validateAppearance: widget.validateAppearance,
            ),
          ),
      ],
    );
  }
}

class _BannerLayout extends SingleChildLayoutDelegate {
  _BannerLayout(this.position, {this.available})
    : resolvedPosition = position ?? Offset.zero;

  final Offset? position;
  Offset resolvedPosition;
  final Rect? available;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      available == null
      ? constraints.loosen()
      : constraints.loosen().enforce(
          BoxConstraints(
            maxWidth: available!.width,
            maxHeight: available!.height,
          ),
        );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final desired = position ?? Offset((size.width - childSize.width) / 2, 8);
    final bounds =
        available?.intersect(Offset.zero & size) ?? (Offset.zero & size);
    resolvedPosition = Offset(
      desired.dx.clamp(
        bounds.left,
        (bounds.right - childSize.width).clamp(bounds.left, double.infinity),
      ),
      desired.dy.clamp(
        bounds.top,
        (bounds.bottom - childSize.height).clamp(bounds.top, double.infinity),
      ),
    );
    return resolvedPosition;
  }

  @override
  bool shouldRelayout(_BannerLayout oldDelegate) =>
      position != oldDelegate.position || available != oldDelegate.available;
}

class _VibeChatLayout extends SingleChildLayoutDelegate {
  _VibeChatLayout(this.position, {this.available})
    : resolvedPosition = position ?? Offset.zero;

  final Offset? position;
  Offset resolvedPosition;
  final Rect? available;

  Rect _bounds(Size size) =>
      available?.intersect(Offset.zero & size) ?? (Offset.zero & size);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final bounds = _bounds(constraints.biggest);
    return BoxConstraints.tightFor(
      width: bounds.width.clamp(0.0, 440.0),
      height: bounds.height.clamp(0.0, 600.0),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = _bounds(size);
    final desired =
        position ??
        Offset(
          bounds.right - childSize.width - 16,
          bounds.bottom - childSize.height - 16,
        );
    resolvedPosition = Offset(
      desired.dx.clamp(
        bounds.left,
        (bounds.right - childSize.width).clamp(bounds.left, double.infinity),
      ),
      desired.dy.clamp(
        bounds.top,
        (bounds.bottom - childSize.height).clamp(bounds.top, double.infinity),
      ),
    );
    return resolvedPosition;
  }

  @override
  bool shouldRelayout(_VibeChatLayout oldDelegate) =>
      position != oldDelegate.position || available != oldDelegate.available;
}

/// Chevron cliquable entre deux segments du chemin pour afficher l'arbre
/// complet des enfants du segment parent.
class _PathChevron extends StatelessWidget {
  const _PathChevron({
    required this.valueKey,
    required this.active,
    required this.onTap,
    super.key,
  });

  final Key valueKey;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;
    final radius = BorderRadius.circular(5);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        key: valueKey,
        onTap: onTap,
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: .18) : color.withValues(alpha: .08),
            borderRadius: radius,
            border: Border.all(
              color: active ? color : color.withValues(alpha: .55),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              active ? Icons.expand_more : Icons.chevron_right,
              size: 14,
              color: active ? color : color.withValues(alpha: .9),
            ),
          ),
        ),
      ),
    );
  }
}

class _TreePopupLayout extends SingleChildLayoutDelegate {
  const _TreePopupLayout({required this.anchor, this.available});

  final Rect anchor;
  final Rect? available;

  Rect _bounds(Size size) =>
      available?.intersect(Offset.zero & size) ?? (Offset.zero & size);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final bounds = _bounds(constraints.biggest);
    return BoxConstraints(
      minWidth: math.min(200.0, bounds.width),
      maxWidth: bounds.width.clamp(0.0, 340.0),
      maxHeight: bounds.height.clamp(0.0, 360.0),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = _bounds(size);
    final maxLeft = math.max(bounds.left, bounds.right - childSize.width);
    final dx = anchor.left.clamp(bounds.left, maxLeft);
    final belowTop = anchor.bottom + 6;
    final fitsBelow = belowTop + childSize.height <= bounds.bottom;
    final spaceAbove = anchor.top - bounds.top;
    final spaceBelow = bounds.bottom - anchor.bottom;
    final desiredDy = !fitsBelow && spaceAbove > spaceBelow
        ? anchor.top - childSize.height - 6
        : belowTop;
    final maxTop = math.max(bounds.top, bounds.bottom - childSize.height);
    final dy = desiredDy.clamp(bounds.top, maxTop);
    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_TreePopupLayout oldDelegate) =>
      anchor != oldDelegate.anchor || available != oldDelegate.available;
}

class _PathTreeDialog extends StatelessWidget {
  const _PathTreeDialog({
    required this.parentLabel,
    required this.nodes,
    required this.currentPath,
    required this.onClose,
    required this.onSelectNode,
  });

  final String parentLabel;
  final List<LayoutSelectionNode> nodes;
  final List<String> currentPath;
  final VoidCallback onClose;
  final ValueChanged<LayoutSelectionNode> onSelectNode;

  List<Widget> _buildNodes(
    BuildContext context,
    List<LayoutSelectionNode> items,
    int depth,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final widgets = <Widget>[];
    for (final node in items) {
      final isSelected = listEquals(node.path, currentPath);
      final isActiveBranch =
          currentPath.length >= node.path.length &&
          listEquals(currentPath.take(node.path.length).toList(), node.path);
      widgets.add(
        InkWell(
          key: ValueKey('style-edit-banner-tree-node-${node.path.join("/")}'),
          onTap: () => onSelectNode(node),
          child: ColoredBox(
            color: isSelected
                ? scheme.primaryContainer.withValues(alpha: .55)
                : Colors.transparent,
            child: Padding(
              padding: EdgeInsets.fromLTRB(10.0 + depth * 16.0, 6, 12, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (depth > 0) ...[
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 14,
                      color: scheme.onSurfaceVariant.withValues(alpha: .7),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    node.icon ??
                        (node.children.isNotEmpty
                            ? Icons.account_tree_outlined
                            : Icons.widgets_outlined),
                    size: 16,
                    color: isSelected || isActiveBranch
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      node.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected || isActiveBranch
                            ? scheme.primary
                            : scheme.onSurface,
                        fontWeight: isSelected || isActiveBranch
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (node.children.isNotEmpty) {
        widgets.addAll(_buildNodes(context, node.children, depth + 1));
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('style-edit-banner-tree-dialog'),
      color: scheme.surfaceContainerHigh,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_tree, size: 15, color: scheme.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      parentLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const ValueKey('style-edit-banner-tree-close'),
                    visualDensity: VisualDensity.compact,
                    iconSize: 15,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .5)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildNodes(context, nodes, 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un niveau du chemin : un clic active sa disposition et, le cas echeant,
/// la zone designee.
class _PathSegment extends StatelessWidget {
  const _PathSegment({
    required this.label,
    required this.current,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: current ? color : color.withValues(alpha: .85),
            fontWeight: current ? FontWeight.w700 : FontWeight.normal,
            decoration: onTap == null ? null : TextDecoration.underline,
            decorationColor: color.withValues(alpha: .6),
          ),
        ),
      ),
    );
  }
}
