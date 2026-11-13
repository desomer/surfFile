/// Bannière du mode édition ([StyleEditBanner]) et panneau latéral Vibe IA.
library;

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

/// Pastille déplaçable, initialement en haut au centre par défaut.
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
    this.initialAlignment,
    super.key,
  });

  /// Navigateur de l'application, où s'ouvre la boîte d'import / export : la
  /// bannière est au-dessus de lui. Sans lui, celui du contexte est utilisé.
  final GlobalKey<NavigatorState>? navigatorKey;
  final Future<void> Function()? onManagePages;
  final Future<String> Function(String prompt)? aiResponseGenerator;
  final void Function(Appearance appearance)? validateAppearance;

  /// Position initiale dans l'espace disponible ; `null` conserve le haut.
  final Alignment? initialAlignment;

  @override
  State<StyleEditBanner> createState() => _StyleEditBannerState();
}

class _StyleEditBannerState extends State<StyleEditBanner> {
  final _bannerKey = GlobalKey();
  _BannerLayout _layout = _BannerLayout(null);
  _VibeChatLayout _chatLayout = _VibeChatLayout(null);
  bool _chatOpen = false;
  VibeChatScope? _chatScope;
  final _chevronKeys = <int, GlobalKey>{};
  ({
    int chevronIndex,
    List<String> prefix,
    Rect anchor,
    List<LayoutSelectionNode> nodes,
  })?
  _treePopup;

  Rect? _bannerRect() {
    if (!mounted) return null;
    final box = _bannerKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Offset _menuPositionForBanner(Offset position) {
    final rect = _bannerRect();
    if (rect == null) return position;
    final viewSize = MediaQuery.maybeSizeOf(context);
    final spaceAbove = rect.top;
    final spaceBelow = viewSize == null
        ? double.infinity
        : viewSize.height - rect.bottom;
    final dy = spaceBelow >= spaceAbove || spaceBelow >= 220
        ? math.max(position.dy, rect.bottom + 6)
        : math.min(position.dy, rect.top - 6);
    return Offset(position.dx, dy);
  }

  bool _openScopedChat(VibeChatScope scope) {
    if (!mounted || AppearanceScope.controllerOf(context) == null) return false;
    setState(() {
      _chatScope = scope;
      if (!_chatOpen) {
        _chatOpen = true;
        _chatLayout = _newChatLayout(
          null,
          LayoutSelection.editorViewport.value,
        );
      }
    });
    return true;
  }

  _VibeChatLayout _newChatLayout(Offset? position, Rect? available) =>
      _VibeChatLayout(
        position,
        available: available,
        banner: widget.initialAlignment == null ? null : _layout,
      );

  @override
  void initState() {
    super.initState();
    _layout = _BannerLayout(
      null,
      available: LayoutSelection.editorViewport.value,
      initialAlignment: widget.initialAlignment,
    );
    LayoutSelection.bannerBounds = _bannerRect;
    VibeChatScope.onOpenRequested = _openScopedChat;
    LayoutSelection.editorViewport.addListener(_reposition);
    LayoutSelection.path.addListener(_onPathChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.aiResponseGenerator != null) return;
      if (dotenv.isInitialized &&
          (dotenv.env['GEMINI_API_KEY'] ?? '').trim().isNotEmpty) {
        unawaited(VibeChatDialog.warmUp(DefaultAssetBundle.of(context)));
      }
    });
  }

  @override
  void didUpdateWidget(StyleEditBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAlignment != widget.initialAlignment) {
      _layout = _BannerLayout(
        null,
        available: LayoutSelection.editorViewport.value,
        initialAlignment: widget.initialAlignment,
      );
      _chatLayout = _newChatLayout(
        _chatLayout.position,
        LayoutSelection.editorViewport.value,
      );
    }
  }

  void _onPathChanged() {
    final popup = _treePopup;
    if (popup == null) return;
    final current = LayoutSelection.path.value;
    if (current.length < popup.prefix.length ||
        !listEquals(current.take(popup.prefix.length).toList(), popup.prefix)) {
      LayoutSelection.highlightNode(null);
      setState(() => _treePopup = null);
    }
  }

  void _toggleTreePopup(int chevronIndex, List<String> prefix) {
    EditorSlotState.closeActiveMenu();
    LayoutSelection.highlightNode(null);
    if (_treePopup?.chevronIndex == chevronIndex) {
      setState(() => _treePopup = null);
      return;
    }
    final nodes = LayoutSelection.childrenOf(prefix);
    if (nodes.isEmpty) return;
    final chevronBox = _chevronKeys[chevronIndex]?.currentContext
        ?.findRenderObject();
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

  void _reposition() {
    if (_treePopup != null) {
      LayoutSelection.highlightNode(null);
    }
    setState(() {
      _treePopup = null;
      _layout = _BannerLayout(
        _layout.position,
        available: LayoutSelection.editorViewport.value,
        initialAlignment: widget.initialAlignment,
      );
      _chatLayout = _newChatLayout(
        _chatLayout.position,
        LayoutSelection.editorViewport.value,
      );
    });
  }

  @override
  void dispose() {
    if (_treePopup != null) {
      LayoutSelection.highlightNode(null);
    }
    if (identical(LayoutSelection.bannerBounds, _bannerRect)) {
      LayoutSelection.bannerBounds = null;
    }
    if (identical(VibeChatScope.onOpenRequested, _openScopedChat)) {
      VibeChatScope.onOpenRequested = null;
    }
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
        key: _bannerKey,
        onPanUpdate: (details) {
          EditorSlotState.closeActiveMenu();
          if (_treePopup != null) {
            LayoutSelection.highlightNode(null);
          }
          setState(() {
            _treePopup = null;
            _layout = _BannerLayout(
              _layout.resolvedPosition + details.delta,
              available: available,
              initialAlignment: widget.initialAlignment,
            );
            _chatLayout = _newChatLayout(_chatLayout.position, available);
          });
        },
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
                      _chatScope = null;
                      if (_chatOpen) {
                        _chatLayout = _newChatLayout(null, available);
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
                                        onHover: (hovered) =>
                                            LayoutSelection.highlightPath(
                                              hovered
                                                  ? path.sublist(0, index + 1)
                                                  : null,
                                            ),
                                        onTap: () {
                                          LayoutSelection.highlightPath(null);
                                          EditorSlotState.closeActiveMenu();
                                          if (_treePopup != null) {
                                            setState(() => _treePopup = null);
                                          }
                                          LayoutSelection.toggle(
                                            path.sublist(0, index + 1),
                                          );
                                        },
                                        onSecondaryTap: (position) {
                                          LayoutSelection.highlightPath(null);
                                          EditorSlotState.closeActiveMenu();
                                          if (_treePopup != null) {
                                            setState(() => _treePopup = null);
                                          }
                                          LayoutSelection.openContextMenu(
                                            path.sublist(0, index + 1),
                                            _menuPositionForBanner(position),
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
    final popupChild = popup == null
        ? null
        : _PathTreeDialog(
            parentLabel: popup.prefix.last,
            nodes: popup.nodes,
            currentPath: LayoutSelection.path.value,
            onClose: () {
              LayoutSelection.highlightNode(null);
              setState(() => _treePopup = null);
            },
            onSelectNode: (node) {
              LayoutSelection.highlightNode(null);
              EditorSlotState.closeActiveMenu();
              setState(() => _treePopup = null);
              if (node.onSelect != null) {
                node.onSelect!();
              } else {
                LayoutSelection.select(node.path);
              }
            },
            onContextMenuNode: (node, position) {
              LayoutSelection.highlightNode(null);
              EditorSlotState.closeActiveMenu();
              setState(() => _treePopup = null);
              final targetPosition = _menuPositionForBanner(position);
              if (node.onContextMenu != null) {
                node.onContextMenu!(targetPosition);
              } else {
                LayoutSelection.openContextMenu(node.path, targetPosition);
              }
            },
          );
    final chatChild = !showChat
        ? null
        : LayoutBuilder(
            builder: (context, constraints) {
              final fullHeight = _chatLayout.unreservedHeight;
              if (fullHeight == null) {
                throw StateError('La hauteur disponible du chat est inconnue.');
              }
              final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final minimumContentHeight = 320.0 * math.max(1.0, textScale);
              final contentHeight = widget.initialAlignment == null
                  ? constraints.maxHeight
                  : math.min(
                      fullHeight,
                      math.max(constraints.maxHeight, minimumContentHeight),
                    );
              return SingleChildScrollView(
                key: const ValueKey('style-edit-banner-chat-viewport'),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: contentHeight,
                  child: VibeChatDialog(
                    registry: SuperApp.maybeOf(context)?.registry,
                    controller: appearance,
                    codec: codec,
                    scope: _chatScope,
                    onScopeChanged: (scope) =>
                        setState(() => _chatScope = scope),
                    onClose: () => setState(() {
                      _chatOpen = false;
                      _chatScope = null;
                    }),
                    onDrag: (delta) => setState(
                      () => _chatLayout = _newChatLayout(
                        _chatLayout.resolvedPosition + delta,
                        available,
                      ),
                    ),
                    generate: widget.aiResponseGenerator ?? callGemini,
                    validateAppearance: widget.validateAppearance,
                  ),
                ),
              );
            },
          );
    return Stack(
      children: [
        if (popup != null)
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('style-edit-banner-tree-barrier'),
              behavior: HitTestBehavior.translucent,
              onTap: () {
                LayoutSelection.highlightNode(null);
                setState(() => _treePopup = null);
              },
            ),
          ),
        CustomMultiChildLayout(
          delegate: _BannerOverlayLayout(
            banner: _layout,
            chat: _chatLayout,
            popup: popup == null
                ? null
                : _TreePopupLayout(anchor: popup.anchor, available: available),
          ),
          children: [
            LayoutId(id: _BannerOverlayChild.banner, child: banner),
            if (widget.initialAlignment == null && popupChild != null)
              LayoutId(id: _BannerOverlayChild.popup, child: popupChild),
            if (chatChild != null)
              LayoutId(
                id: _BannerOverlayChild.chat,
                key: const ValueKey('style-edit-banner-chat-layout'),
                child: chatChild,
              ),
            if (widget.initialAlignment != null && popupChild != null)
              LayoutId(id: _BannerOverlayChild.popup, child: popupChild),
          ],
        ),
      ],
    );
  }
}

enum _BannerOverlayChild { banner, chat, popup }

class _BannerOverlayLayout extends MultiChildLayoutDelegate {
  _BannerOverlayLayout({
    required this.banner,
    required this.chat,
    required this.popup,
  });

  final _BannerLayout banner;
  final _VibeChatLayout chat;
  final _TreePopupLayout? popup;

  @override
  void performLayout(Size size) {
    final constraints = BoxConstraints.tight(size);
    // Des contraintes souples propagent les changements de taille au chat.
    layoutChild(_BannerOverlayChild.banner, constraints.loosen());
    positionChild(_BannerOverlayChild.banner, Offset.zero);
    if (hasChild(_BannerOverlayChild.chat)) {
      final chatSize = layoutChild(
        _BannerOverlayChild.chat,
        chat.getConstraintsForChild(constraints),
      );
      positionChild(
        _BannerOverlayChild.chat,
        chat.getPositionForChild(size, chatSize),
      );
    }
    if (popup case final popup?) {
      final popupSize = layoutChild(
        _BannerOverlayChild.popup,
        popup.getConstraintsForChild(constraints),
      );
      positionChild(
        _BannerOverlayChild.popup,
        popup.getPositionForChild(size, popupSize),
      );
    }
  }

  @override
  bool shouldRelayout(_BannerOverlayLayout oldDelegate) =>
      banner != oldDelegate.banner ||
      chat != oldDelegate.chat ||
      popup != oldDelegate.popup;
}

class _BannerLayout extends SingleChildLayoutDelegate {
  _BannerLayout(this.position, {this.available, this.initialAlignment})
    : resolvedPosition = position ?? Offset.zero;

  final Offset? position;
  Offset resolvedPosition;
  Size? resolvedSize;
  final Rect? available;
  final Alignment? initialAlignment;

  Rect? get resolvedBounds {
    final size = resolvedSize;
    return size == null ? null : resolvedPosition & size;
  }

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
    resolvedSize = childSize;
    final bounds =
        available?.intersect(Offset.zero & size) ?? (Offset.zero & size);
    final desired =
        position ??
        (initialAlignment?.inscribe(childSize, bounds.deflate(8)).topLeft ??
            Offset((size.width - childSize.width) / 2, 8));
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
      position != oldDelegate.position ||
      available != oldDelegate.available ||
      initialAlignment != oldDelegate.initialAlignment;
}

class _VibeChatLayout extends SingleChildLayoutDelegate {
  _VibeChatLayout(this.position, {this.available, this.banner})
    : resolvedPosition = position ?? Offset.zero;

  final Offset? position;
  Offset resolvedPosition;
  final Rect? available;
  final _BannerLayout? banner;
  double? unreservedHeight;

  Rect _bounds(Size size) =>
      available?.intersect(Offset.zero & size) ?? (Offset.zero & size);

  Rect _chatBounds(Size size) {
    final bounds = _bounds(size);
    // Le layout commun calcule d'abord la géométrie de la bannière.
    final bannerBounds = banner?.resolvedBounds?.intersect(bounds);
    if (bannerBounds == null || bannerBounds.isEmpty) return bounds;
    final width = math.min(bounds.width, 440.0);
    final height = math.min(bounds.height, 600.0);
    final left = (bounds.right - width - 16).clamp(
      bounds.left,
      bounds.right - width,
    );
    final top = (bounds.bottom - height - 16).clamp(
      bounds.top,
      bounds.bottom - height,
    );
    if (!Rect.fromLTWH(left, top, width, height).overlaps(bannerBounds)) {
      return bounds;
    }

    final aboveBottom = math.max(bounds.top, bannerBounds.top - 8);
    final belowTop = math.min(bounds.bottom, bannerBounds.bottom + 8);
    final aboveHeight = aboveBottom - bounds.top;
    final belowHeight = bounds.bottom - belowTop;
    if (aboveHeight == 0 && belowHeight == 0) return bounds;
    if (aboveHeight >= height || aboveHeight >= belowHeight) {
      return Rect.fromLTRB(bounds.left, bounds.top, bounds.right, aboveBottom);
    }
    return Rect.fromLTRB(bounds.left, belowTop, bounds.right, bounds.bottom);
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    unreservedHeight = _bounds(constraints.biggest).height.clamp(0.0, 600.0);
    final bounds = _chatBounds(constraints.biggest);
    return BoxConstraints.tightFor(
      width: bounds.width.clamp(0.0, 440.0),
      height: bounds.height.clamp(0.0, 600.0),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = _bounds(size);
    final chatBounds = _chatBounds(size);
    final placementBounds = position == null ? chatBounds : bounds;
    final desired =
        position ??
        Offset(
          chatBounds.right - childSize.width - 16,
          chatBounds.bottom - childSize.height - 16,
        );
    resolvedPosition = Offset(
      desired.dx.clamp(
        placementBounds.left,
        (placementBounds.right - childSize.width).clamp(
          placementBounds.left,
          double.infinity,
        ),
      ),
      desired.dy.clamp(
        placementBounds.top,
        (placementBounds.bottom - childSize.height).clamp(
          placementBounds.top,
          double.infinity,
        ),
      ),
    );
    return resolvedPosition;
  }

  @override
  bool shouldRelayout(_VibeChatLayout oldDelegate) =>
      position != oldDelegate.position ||
      available != oldDelegate.available ||
      banner != oldDelegate.banner;
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
            color: active
                ? color.withValues(alpha: .18)
                : color.withValues(alpha: .08),
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
      minWidth: math.min(400.0, bounds.width),
      maxWidth: bounds.width.clamp(0.0, 800.0),
      maxHeight: bounds.height.clamp(0.0, 560.0),
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
    this.onContextMenuNode,
  });

  final String parentLabel;
  final List<LayoutSelectionNode> nodes;
  final List<String> currentPath;
  final VoidCallback onClose;
  final ValueChanged<LayoutSelectionNode> onSelectNode;
  final void Function(LayoutSelectionNode node, Offset globalPosition)?
  onContextMenuNode;

  List<Widget> _buildNodes(
    BuildContext context,
    List<LayoutSelectionNode> items,
    int depth, [
    Map<String, int>? keyCounts,
  ]) {
    final counts = keyCounts ?? <String, int>{};
    final scheme = Theme.of(context).colorScheme;
    final widgets = <Widget>[];
    for (final node in items) {
      final isSelected = LayoutSelection.isNodeSelected(node, currentPath);
      final isActiveBranch = LayoutSelection.isNodeInActiveBranch(
        node,
        currentPath,
      );
      final baseKey = 'style-edit-banner-tree-node-${node.path.join("/")}';
      final occurrence = counts.update(
        baseKey,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      widgets.add(
        MouseRegion(
          onEnter: (_) => LayoutSelection.highlightNode(node),
          child: InkWell(
            key: occurrence == 0
                ? ValueKey(baseKey)
                : ValueKey('$baseKey#$occurrence'),
            onTap: () => onSelectNode(node),
            onSecondaryTapUp: onContextMenuNode == null
                ? null
                : (details) => onContextMenuNode!(node, details.globalPosition),
            child: ColoredBox(
              color: isSelected
                  ? scheme.primaryContainer.withValues(alpha: .55)
                  : Colors.transparent,
              child: Padding(
                padding: EdgeInsets.fromLTRB(8.0 + depth * 7.0, 6, 12, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (depth > 0) ...[
                      Icon(
                        Icons.subdirectory_arrow_right,
                        size: 13,
                        color: scheme.onSurfaceVariant.withValues(alpha: .7),
                      ),
                      const SizedBox(width: 2),
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
        ),
      );
      if (node.children.isNotEmpty) {
        widgets.addAll(_buildNodes(context, node.children, depth + 1, counts));
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onExit: (_) => LayoutSelection.highlightNode(null),
      child: Material(
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
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: .5),
              ),
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
    this.onHover,
    this.onSecondaryTap,
    super.key,
  });

  final String label;
  final bool current;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final ValueChanged<Offset>? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;
    return MouseRegion(
      onEnter: onHover == null ? null : (_) => onHover!(true),
      onExit: onHover == null ? null : (_) => onHover!(false),
      child: InkWell(
        onTap: onTap,
        onSecondaryTapUp: onSecondaryTap == null
            ? null
            : (details) => onSecondaryTap!(details.globalPosition),
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
      ),
    );
  }
}
