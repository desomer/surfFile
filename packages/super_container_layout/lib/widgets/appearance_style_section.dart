import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/container_style_editor.dart';
import 'package:super_container_layout/widgets/style_editor_panel.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/neon_style.dart';
import 'package:super_container_layout/services/window_transparency.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;

import '../theme/appearance.dart';

/// Edits an injected slot without owning an application catalog.
class AppearanceStyleSection extends StatelessWidget {
  const AppearanceStyleSection(this.slot, {this.defaults, super.key});
  final AppearanceSlot slot;
  final Appearance Function()? defaults;
  @override
  Widget build(BuildContext context) {
    final controller = AppearanceScope.controllerOf(context);
    if (controller == null) {
      throw StateError('Appearance controller unavailable.');
    }
    final a = controller.value;
    final style = slot.read(a);
    final scheme = Theme.of(context).colorScheme;
    final background = slot.role == AppearanceSurfaceRole.applicationBackground;
    final color =
        style.color ??
        (background
            ? scheme.surface
            : slot.isSelectedVariant
            ? scheme.primaryContainer
            : scheme.brightness == Brightness.dark
            ? scheme.surfaceContainerLow
            : Colors.white);
    void update(ContainerStyle value) =>
        controller.value = slot.write(controller.value, value);
    ContainerStyle current() => slot.read(controller.value);
    final shape = slot.editShape;
    return AlertDialog(
      title: Text(slot.label),
      content: SizedBox(
        width: 1020,
        height: 620,
        child: ContainerStyleEditor(
          label: slot.label,
          collapsible: false,
          style: style,
          onStyle: update,
          extended: slot.extendedLook,
          value: style.fill,
          solidColor: color,
          radius: style.radius,
          borderWidth: style.borderWidth,
          borderColor: style.borderColor ?? scheme.outlineVariant,
          elevation: style.elevation,
          shadowOpacity: style.shadowOpacity,
          opacity: background ? a.backgroundOpacity : 1,
          neon: style.neon ?? const NeonStyle(),
          accent: a.accent,
          designSystem: style.designSystem,
          onDesignSystemChanged: shape
              ? (value) => update(value.apply(current()))
              : null,
          interactionEffect: style.interactionEffect,
          onInteractionEffectChanged: (value) =>
              update(current().copyWith(interactionEffect: value)),
          hoverEffect: style.hoverEffect,
          onHoverEffectChanged: (value) =>
              update(current().copyWith(hoverEffect: value)),
          hoverTint: style.hoverTint,
          hoverColor: style.hoverColor,
          onHoverTintChanged: (value) =>
              update(current().copyWith(hoverTint: value)),
          onHoverColorChanged: (value) =>
              update(current().copyWith(hoverColor: value)),
          onChanged: (value) => update(current().copyWith(fill: value)),
          onSolidColorChanged: (value) =>
              update(current().copyWith(color: value)),
          onRadiusChanged: shape
              ? (value) => update(current().copyWith(radius: value))
              : null,
          onBorderWidthChanged: (value) =>
              update(current().copyWith(borderWidth: value)),
          onBorderColorChanged: (value) =>
              update(current().copyWith(borderColor: value)),
          onResetBorderColor: () =>
              update(current().copyWith(resetBorderColor: true)),
          onElevationChanged: shape
              ? (value) => update(current().copyWith(elevation: value))
              : null,
          onShadowOpacityChanged: shape
              ? (value) => update(current().copyWith(shadowOpacity: value))
              : null,
          onNeonChanged: (value) => update(current().copyWith(neon: value)),
          onResetColor: () => update(current().copyWith(resetColor: true)),
          onReset: () => controller.value = defaults == null
              ? slot.reset(controller.value)
              : controller.value.withStyle(slot.name, defaults!().styles[slot.name]),
          extraSections: [
            if (background)
              StyleEditorSection(
                id: 'window',
                title: 'Fenêtre',
                tag: 'windowEffect',
                icon: Icons.window_outlined,
                count: 2,
                child: Column(
                  children: [
                    Text(
                      'Opacité du fond : ${a.backgroundOpacity.toStringAsFixed(1)}',
                    ),
                    Slider(
                      key: const ValueKey('Opacité du fond'),
                      value: a.backgroundOpacity,
                      onChanged: (value) => controller.value = controller.value
                          .copyWith(backgroundOpacity: value),
                    ),
                    DropdownButtonFormField<WindowEffect>(
                      isExpanded: true,
                      key: const ValueKey('window-effect'),
                      initialValue: a.windowEffect,
                      decoration: const InputDecoration(
                        labelText: 'Effet de la fenêtre',
                      ),
                      items: [
                        for (final effect in WindowEffect.values)
                          DropdownMenuItem(
                            value: effect,
                            enabled: WindowTransparency.isSupported(effect),
                            child: Text(
                              WindowTransparency.label(effect),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          controller.value = controller.value.copyWith(
                            windowEffect: value,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Retour'),
        ),
      ],
    );
  }
}
