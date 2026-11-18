/// Barre, positionnement et dialogue des contrôles de zoom du canevas.
library;

import 'package:material_ui/material_ui.dart';

import '../components/shared/editor_number_field.dart';
import '../history/editor_history.dart';
import 'editor_zoom.dart';

/// Contenu des boutons de contrôle du zoom affiché dans la barre d'édition.
class EditorZoomToolbarContent extends StatelessWidget {
  const EditorZoomToolbarContent({
    required this.scale,
    required this.onScaleChanged,
    required this.onDrag,
    this.onOpenOptions,
    super.key,
  });

  final double scale;
  final ValueChanged<double> onScaleChanged;
  final GestureDragUpdateCallback onDrag;

  /// Action personnalisée d'ouverture des options de zoom.
  /// Par défaut, ouvre [showEditorZoomOptionsDialog] pour le contrôleur courant.
  final VoidCallback? onOpenOptions;

  @override
  Widget build(BuildContext context) {
    Widget handle = GestureDetector(
      key: const ValueKey('editor-zoom-toolbar-drag'),
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onDrag,
      child: const SizedBox(
        width: 36,
        height: 36,
        child: Icon(Icons.drag_indicator, size: 20),
      ),
    );
    handle = MouseRegion(cursor: SystemMouseCursors.move, child: handle);
    final hasOverlay = Overlay.maybeOf(context) != null;
    if (hasOverlay) {
      handle = Tooltip(message: 'Déplacer la barre de zoom', child: handle);
    }
    Widget optionsButton = SizedBox(
      width: 32,
      height: 36,
      child: IconButton(
        key: const ValueKey('editor-zoom-options-button'),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        icon: const Icon(Icons.tune),
        onPressed:
            onOpenOptions ??
            () {
              final controller = EditorZoomScope.controllerOf(context);
              if (controller != null) {
                showEditorZoomOptionsDialog(context, controller: controller);
              }
            },
      ),
    );
    if (hasOverlay) {
      optionsButton = Tooltip(message: 'Options du zoom', child: optionsButton);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        handle,
        const Icon(Icons.zoom_in, size: 18),
        SizedBox(
          width: 120,
          height: 36,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: EditorHistorySlider(
              sliderKey: const ValueKey('editor-zoom-slider'),
              showValue: false,
              integer: true,
              valueScale: 100,
              divisions: 300,
              min: EditorZoom.minScale,
              max: EditorZoom.maxScale,
              value: scale.clamp(EditorZoom.minScale, EditorZoom.maxScale),
              onChanged: onScaleChanged,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: EditorNumberField(
            key: const ValueKey('editor-zoom-percentage'),
            value: scale,
            min: EditorZoom.minScale,
            max: EditorZoom.maxScale,
            integer: true,
            scale: 100,
            unit: '%',
            onChanged: onScaleChanged,
          ),
        ),
        Padding(padding: const EdgeInsets.only(right: 4), child: optionsButton),
      ],
    );
  }
}

/// Disposition adaptative de la barre d'outils de zoom en mode édition.
class ZoomToolbarLayout extends SingleChildLayoutDelegate {
  ZoomToolbarLayout(this.position, {this.available})
    : resolvedPosition = position ?? Offset.zero;

  final Offset? position;
  final Rect? available;
  Offset resolvedPosition;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = available ?? (Offset.zero & size);
    final desired =
        position ??
        Offset(
          bounds.right - childSize.width - 16,
          bounds.bottom - childSize.height - 12,
        );
    final minX = bounds.left;
    final maxX = (bounds.right - childSize.width).clamp(minX, double.infinity);
    final minY = bounds.top;
    final maxY = (bounds.bottom - childSize.height).clamp(
      minY,
      double.infinity,
    );
    resolvedPosition = Offset(
      desired.dx.clamp(minX, maxX),
      desired.dy.clamp(minY, maxY),
    );
    return resolvedPosition;
  }

  @override
  bool shouldRelayout(ZoomToolbarLayout oldDelegate) =>
      position != oldDelegate.position || available != oldDelegate.available;
}

/// Ouvre la boîte de dialogue de configuration des options du zoom en mode édition.
Future<void> showEditorZoomOptionsDialog(
  BuildContext context, {
  EditorZoomController? controller,
}) async {
  final resolved = controller ?? EditorZoomScope.controllerOf(context);
  if (resolved == null || resolved.disposed) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => EditorZoomOptionsDialog(controller: resolved),
  );
}

/// Boîte de dialogue permettant de configurer toutes les options de zoom et de
/// cadrage automatique du mode édition ([EditorZoomOptions]).
class EditorZoomOptionsDialog extends StatelessWidget {
  /// Crée la boîte de dialogue d'options de zoom liée à [controller].
  const EditorZoomOptionsDialog({required this.controller, super.key});

  /// Contrôleur de zoom dont les options sont modifiées en direct.
  final EditorZoomController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      key: const ValueKey('editor-zoom-options-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: ValueListenableBuilder<EditorZoomOptions>(
          valueListenable: controller.options,
          builder: (context, options, _) {
            void update(EditorZoomOptions next) {
              controller.options.value = next;
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Icon(Icons.zoom_in_map, color: colors.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Options du zoom en mode édition',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: controller.scale,
                        builder: (context, currentScale, _) {
                          final button = FilledButton.tonalIcon(
                            key: const ValueKey('zoom-option-reset-100'),
                            onPressed: controller.resetZoom,
                            icon: const Icon(
                              Icons.center_focus_strong,
                              size: 16,
                            ),
                            label: Text(
                              '100% (${(currentScale * 100).round()}%)',
                            ),
                          );
                          return Overlay.maybeOf(context) != null
                              ? Tooltip(
                                  message: 'Réinitialiser le zoom (Échap)',
                                  child: button,
                                )
                              : button;
                        },
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        key: const ValueKey('zoom-option-close'),
                        tooltip: 'Fermer',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader(
                          icon: Icons.aspect_ratio,
                          title: 'Grands éléments & Clic droit',
                          color: colors.primary,
                        ),
                        SwitchListTile(
                          key: const ValueKey(
                            'zoom-option-skip-large-right-click',
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Ne pas zoomer sur les grands éléments au clic droit',
                          ),
                          subtitle: const Text(
                            'Garde la vue actuelle sans zoomer, dézoomer ni décaler '
                            'l’écran lorsque l’élément occupe une grande partie de l’écran.',
                          ),
                          value: options.skipLargeElementsOnRightClick,
                          onChanged: (value) => update(
                            options.copyWith(
                              skipLargeElementsOnRightClick: value,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-skip-large-dialog'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Ne pas dézoomer les grands éléments à l’ouverture des propriétés',
                          ),
                          subtitle: const Text(
                            'Évite de réduire toute la page lorsqu’une fenêtre de propriétés '
                            'est ouverte sur un élément couvrant l’écran.',
                          ),
                          value: options.skipLargeElementsOnDialog,
                          onChanged: (value) => update(
                            options.copyWith(skipLargeElementsOnDialog: value),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Seuil de taille maximale de l’élément',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(options.largeElementViewportThreshold * 100).round()}% de l’écran',
                                    key: const ValueKey(
                                      'zoom-option-large-threshold-label',
                                    ),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              EditorHistorySlider(
                                sliderKey: const ValueKey(
                                  'zoom-option-large-threshold-slider',
                                ),
                                valueScale: 100,
                                integer: true,
                                unit: '%',
                                min: 0.30,
                                max: 1.00,
                                divisions: 70,
                                value: options.largeElementViewportThreshold
                                    .clamp(0.30, 1.00),
                                onChanged:
                                    options.skipLargeElementsOnRightClick ||
                                        options.skipLargeElementsOnDialog
                                    ? (value) => update(
                                        options.copyWith(
                                          largeElementViewportThreshold: value,
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 16),
                        _SectionHeader(
                          icon: Icons.touch_app_outlined,
                          title: 'Déclencheurs du zoom automatique',
                          color: colors.primary,
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-right-click'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text('Zoom automatique au clic droit'),
                          subtitle: const Text(
                            'Recadre et zoome sur le composant ciblé à côté du menu contextuel.',
                          ),
                          value: options.zoomOnRightClick,
                          onChanged: (value) =>
                              update(options.copyWith(zoomOnRightClick: value)),
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-hover'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Zoom automatique au survol du menu / arbre',
                          ),
                          subtitle: const Text(
                            'Recadre la vue lors du survol des entrées du menu contextuel ou de la hiérarchie.',
                          ),
                          value: options.zoomOnHover,
                          onChanged: (value) =>
                              update(options.copyWith(zoomOnHover: value)),
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-selection'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Zoom automatique lors de la sélection',
                          ),
                          subtitle: const Text(
                            'Zoome sur la zone ou le composant sélectionné par clic ou double-clic sur le canevas.',
                          ),
                          value: options.zoomOnSelection,
                          onChanged: (value) =>
                              update(options.copyWith(zoomOnSelection: value)),
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-editor-dialog'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Recadrage avec les fenêtres d’édition',
                          ),
                          subtitle: const Text(
                            'Centre le composant édité dans l’espace libre à côté des fenêtres de propriétés.',
                          ),
                          value: options.zoomOnEditorDialog,
                          onChanged: (value) => update(
                            options.copyWith(zoomOnEditorDialog: value),
                          ),
                        ),
                        SwitchListTile(
                          key: const ValueKey(
                            'zoom-option-reset-on-dialog-exit',
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text(
                            'Retour au zoom et à la position initiale après la saisie des propriétés',
                          ),
                          subtitle: const Text(
                            'Rétablit le zoom et la position d’avant l’ouverture à la fermeture d’une fenêtre de propriétés.',
                          ),
                          value: options.resetZoomOnDialogExit,
                          onChanged: (value) => update(
                            options.copyWith(resetZoomOnDialogExit: value),
                          ),
                        ),
                        const Divider(height: 16),
                        _SectionHeader(
                          icon: Icons.tune,
                          title: 'Échelle et animation',
                          color: colors.primary,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Niveau de zoom automatique maximum',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(options.maxScale * 100).round()}%',
                                    key: const ValueKey(
                                      'zoom-option-max-scale-label',
                                    ),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              EditorHistorySlider(
                                sliderKey: const ValueKey(
                                  'zoom-option-max-scale-slider',
                                ),
                                valueScale: 100,
                                integer: true,
                                unit: '%',
                                min: 1.5,
                                max: EditorZoom.maxScale,
                                divisions: 250,
                                value: options.maxScale.clamp(
                                  1.5,
                                  EditorZoom.maxScale,
                                ),
                                onChanged: (value) =>
                                    update(options.copyWith(maxScale: value)),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Échelle minimale de dézoom (fenêtres d’édition)',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(options.minDialogScale * 100).round()}%',
                                    key: const ValueKey(
                                      'zoom-option-min-dialog-scale-label',
                                    ),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              EditorHistorySlider(
                                sliderKey: const ValueKey(
                                  'zoom-option-min-dialog-scale-slider',
                                ),
                                valueScale: 100,
                                integer: true,
                                unit: '%',
                                min: 0.30,
                                max: 1.00,
                                divisions: 70,
                                value: options.minDialogScale.clamp(0.30, 1.00),
                                onChanged: (value) => update(
                                  options.copyWith(minDialogScale: value),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Surface cible de l’élément à l’écran',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(options.targetScreenAreaFraction * 100).round()}%',
                                    key: const ValueKey(
                                      'zoom-option-target-area-label',
                                    ),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              EditorHistorySlider(
                                sliderKey: const ValueKey(
                                  'zoom-option-target-area-slider',
                                ),
                                valueScale: 100,
                                integer: true,
                                unit: '%',
                                min: 0.15,
                                max: 0.75,
                                divisions: 60,
                                value: options.targetScreenAreaFraction.clamp(
                                  0.15,
                                  0.75,
                                ),
                                onChanged: (value) => update(
                                  options.copyWith(
                                    targetScreenAreaFraction: value,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          key: const ValueKey('zoom-option-animate'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text('Animer les transitions de zoom'),
                          subtitle: Text(
                            options.animateTransitions
                                ? 'Durée : ${options.animationDurationMs} ms'
                                : 'Transitions instantanées',
                          ),
                          value: options.animateTransitions,
                          onChanged: (value) => update(
                            options.copyWith(animateTransitions: value),
                          ),
                        ),
                        if (options.animateTransitions)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                            child: EditorHistorySlider(
                              sliderKey: const ValueKey(
                                'zoom-option-animation-duration-slider',
                              ),
                              integer: true,
                              unit: 'ms',
                              min: 50,
                              max: 600,
                              divisions: 11,
                              value: options.animationDurationMs
                                  .toDouble()
                                  .clamp(50, 600),
                              onChanged: (value) => update(
                                options.copyWith(
                                  animationDurationMs: value.round(),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('zoom-option-restore-defaults'),
                        onPressed: options == const EditorZoomOptions()
                            ? null
                            : () => update(const EditorZoomOptions()),
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Valeurs par défaut'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Terminé'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
