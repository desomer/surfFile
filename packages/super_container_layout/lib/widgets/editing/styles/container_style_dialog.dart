import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';

import '../../../services/window_transparency.dart';
import '../../../theme/appearance.dart';
import '../../../theme/appearance_slot.dart';
import '../../../theme/container_style.dart';
import '../../../theme/neon_style.dart';
import 'container_style_editor.dart';
import '../dialogs/editor_dialog.dart';
import '../history/editor_history.dart';
import 'style_editor_panel.dart';

/// The shared style editor dialog used by [EditableSurface].
class ContainerStyleDialog {
  const ContainerStyleDialog._();

  static Future<bool?> show({
    required BuildContext context,
    required String label,
    required AppearanceSlot? slot,
    required Color fallbackColor,
    required Color borderColor,
    required ValueNotifier<Appearance>? appearance,
    required ValueListenable<ContainerStyle> localStyle,
    required ContainerStyle Function() currentStyle,
    required void Function(ContainerStyle style, AppearanceSlot? slot)
    onStyleChanged,
    required void Function(AppearanceSlot? slot) onReset,
    required ValueChanged<String> onLabelChanged,
  }) async {
    final accent = AppearanceScope.of(context).accent;
    final shape = slot?.editShape ?? true;
    final extended = slot?.extendedLook ?? true;
    final standardSlot = slot?.standard;
    final selectedSlot = standardSlot?.selectedVariant;
    final colors = Theme.of(context).colorScheme;
    var editSlot = slot;
    final tabbed = selectedSlot != null;
    var dense = StyleEditorPanel.preferredDense;
    final dockWidth = ValueNotifier(dense ? 680.0 : 1080.0);
    bool? confirmed;
    try {
      confirmed = await showEditorDialog<bool>(
        context: context,
        target: context,
        preferredWidth: dockWidth,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) {
            final screen = MediaQuery.sizeOf(context);
            final width = math.min(dense ? 680.0 : 1080.0, screen.width - 96);
            final height = math.max(
              320.0,
              math.min(680.0, screen.height - 260),
            );
            return AlertDialog(
              insetPadding: const EdgeInsets.all(24),
              constraints: BoxConstraints(maxWidth: width + 48),
              content: SizedBox(
                width: width,
                height: height,
                child: StatefulBuilder(
                  builder: (context, setTab) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (tabbed) ...[
                        DefaultTabController(
                          length: 2,
                          initialIndex: editSlot == selectedSlot ? 1 : 0,
                          child: TabBar(
                            key: const ValueKey('style-editor-tabs'),
                            onTap: (index) => setTab(
                              () => editSlot = index == 1
                                  ? selectedSlot
                                  : standardSlot,
                            ),
                            tabs: const [
                              Tab(text: 'Standard'),
                              Tab(text: 'Sélectionné'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Expanded(
                        child: ListenableBuilder(
                          key: ValueKey(editSlot),
                          listenable: appearance ?? localStyle,
                          builder: (context, _) {
                            final targetSlot = editSlot;
                            final style =
                                targetSlot != null && appearance != null
                                ? targetSlot.read(appearance.value)
                                : currentStyle();
                            final fallback = targetSlot == slot
                                ? fallbackColor
                                : targetSlot!.isSelectedVariant
                                ? colors.primaryContainer
                                : colors.surfaceContainerLow;
                            final border = targetSlot == slot
                                ? borderColor
                                : colors.primary;
                            void update(ContainerStyle value) =>
                                onStyleChanged(value, targetSlot);
                            return ContainerStyleEditor(
                              label: label,
                              onLabelChanged: onLabelChanged,
                              collapsible: false,
                              dense: dense,
                              onDenseChanged: (value) => setDialog(() {
                                dense = value;
                                dockWidth.value = value ? 680 : 1080;
                              }),
                              style: style,
                              onStyle: update,
                              extended: extended,
                              value: style.fill,
                              solidColor: style.color ?? fallback,
                              radius: style.radius,
                              borderWidth: style.borderWidth,
                              borderColor: style.borderColor ?? border,
                              elevation: style.elevation,
                              shadowOpacity: style.shadowOpacity,
                              opacity:
                                  slot?.role ==
                                      AppearanceSurfaceRole
                                          .applicationBackground
                                  ? appearance!.value.backgroundOpacity
                                  : 1,
                              neon: style.neon ?? const NeonStyle(),
                              accent: accent,
                              onChanged: (value) =>
                                  update(style.copyWith(fill: value)),
                              onSolidColorChanged: (value) =>
                                  update(style.copyWith(color: value)),
                              onRadiusChanged: shape
                                  ? (value) =>
                                        update(style.copyWith(radius: value))
                                  : null,
                              onBorderWidthChanged: (value) => update(
                                style.copyWith(borderWidth: value),
                              ),
                              onBorderColorChanged: (value) =>
                                  update(style.copyWith(borderColor: value)),
                              onResetBorderColor: () => update(
                                style.copyWith(resetBorderColor: true),
                              ),
                              onElevationChanged: shape
                                  ? (value) =>
                                        update(style.copyWith(elevation: value))
                                  : null,
                              onShadowOpacityChanged: shape
                                  ? (value) => update(
                                      style.copyWith(shadowOpacity: value),
                                    )
                                  : null,
                              padding: style.padding,
                              margin: style.margin,
                              onPaddingChanged: (value) =>
                                  update(style.copyWith(padding: value)),
                              onMarginChanged: (value) =>
                                  update(style.copyWith(margin: value)),
                              onNeonChanged: (value) =>
                                  update(style.copyWith(neon: value)),
                              hoverEffect: style.hoverEffect,
                              onHoverEffectChanged: (value) => update(
                                style.copyWith(hoverEffect: value),
                              ),
                              hoverTint: style.hoverTint,
                              hoverColor: style.hoverColor,
                              onHoverTintChanged: (value) => update(
                                style.copyWith(hoverTint: value),
                              ),
                              onHoverColorChanged: (value) =>
                                  update(style.copyWith(hoverColor: value)),
                              interactionEffect: style.interactionEffect,
                              onInteractionEffectChanged: (value) => update(
                                style.copyWith(interactionEffect: value),
                              ),
                              designSystem: style.designSystem,
                              onDesignSystemChanged: shape
                                  ? (value) => update(value.apply(style))
                                  : null,
                              onResetColor: () =>
                                  update(style.copyWith(resetColor: true)),
                              onReset: () => onReset(targetSlot),
                              extraSections: [
                                if (slot?.role ==
                                    AppearanceSurfaceRole.applicationBackground)
                                  StyleEditorSection(
                                    id: 'window',
                                    title: 'Fenêtre',
                                    tag: 'windowEffect',
                                    icon: Icons.window_outlined,
                                    count: 2,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          'Opacité du fond : '
                                          '${appearance!.value.backgroundOpacity.toStringAsFixed(1)}',
                                        ),
                                        EditorHistorySlider(
                                          key: const ValueKey(
                                            'Opacité du fond',
                                          ),
                                          value: appearance
                                              .value
                                              .backgroundOpacity,
                                          onChanged: (value) =>
                                              appearance.value = appearance
                                                  .value
                                                  .copyWith(
                                                    backgroundOpacity: value,
                                                  ),
                                        ),
                                        const SizedBox(height: 8),
                                        DropdownButtonFormField<WindowEffect>(
                                          key: const ValueKey('window-effect'),
                                          initialValue:
                                              appearance.value.windowEffect,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Effet de la fenêtre',
                                            helperText:
                                                'Visible à travers le fond : baissez son opacité.',
                                          ),
                                          items: [
                                            for (final effect
                                                in WindowEffect.values)
                                              DropdownMenuItem(
                                                value: effect,
                                                enabled:
                                                    WindowTransparency.isSupported(
                                                      effect,
                                                    ),
                                                child: Text(
                                                  WindowTransparency.label(
                                                    effect,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      WindowTransparency.isSupported(
                                                        effect,
                                                      )
                                                      ? null
                                                      : TextStyle(
                                                          color: Theme.of(
                                                            context,
                                                          ).disabledColor,
                                                        ),
                                                ),
                                              ),
                                          ],
                                          onChanged: (value) =>
                                              appearance.value = appearance
                                                  .value
                                                  .copyWith(
                                                    windowEffect: value,
                                                  ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Appliquer'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      dockWidth.dispose();
    }
    return confirmed;
  }
}
