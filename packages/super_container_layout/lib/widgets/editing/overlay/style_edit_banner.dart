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

  @override
  void initState() {
    super.initState();
    _layout = _BannerLayout(
      null,
      available: LayoutSelection.editorViewport.value,
    );
    LayoutSelection.editorViewport.addListener(_reposition);
  }

  void _reposition() => setState(() {
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
        onPanUpdate: (details) => setState(
          () => _layout = _BannerLayout(
            _layout.resolvedPosition + details.delta,
            available: available,
          ),
        ),
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
                                        Icon(
                                          Icons.chevron_right,
                                          size: 16,
                                          color: scheme.onPrimary.withValues(
                                            alpha: .7,
                                          ),
                                        ),
                                      _PathSegment(
                                        key: ValueKey(
                                          'style-edit-banner-path-$index',
                                        ),
                                        label: label,
                                        current: index == path.length - 1,
                                        onTap: () => LayoutSelection.toggle(
                                          path.sublist(0, index + 1),
                                        ),
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
    if (!_chatOpen || appearance == null) return banner;
    return Stack(
      children: [
        banner,
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
