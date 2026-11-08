/// Section réutilisable des effets et réglages rapides de surface
/// ([ContainerStyle]) partagée entre `SuperAction` et `SuperIndicator`.
library;

import 'package:material_ui/material_ui.dart';

import '../../../../theme/container_style.dart';
import '../../../../theme/design_system.dart';
import '../../../../theme/interaction_effect.dart';
import '../../../../theme/neon_style.dart';
import '../../styles/style_editor_panel.dart';
import 'editor_color_fields.dart';
import 'editor_segmented_field.dart';

/// Construit la [StyleEditorSection] « Effets et surface avancés » permettant
/// de régler `designSystem`, `interactionEffect`, `hoverEffect` et `neon`.
StyleEditorSection buildSurfaceQuickControlsSection({
  required String sectionId,
  required String componentPrefix,
  required ContainerStyle style,
  required ValueChanged<ContainerStyle> onStyleChanged,
}) {
  final settingPrefix = '$componentPrefix-setting';
  return StyleEditorSection(
    id: sectionId,
    title: 'Effets et surface avancés',
    icon: Icons.auto_fix_high_outlined,
    tag: 'ContainerStyle',
    child: buildEditorFieldGroup([
      EditorSegmentedField<DesignSystem>(
        buttonKey: ValueKey('$settingPrefix-designSystem'),
        label: 'Système de design (Surface)',
        value: style.designSystem,
        options: const [
          EditorSegmentOption(
            value: DesignSystem.material,
            label: 'Material',
            icon: Icons.layers_outlined,
          ),
          EditorSegmentOption(
            value: DesignSystem.liquidGlass,
            label: 'Liquid Glass',
            icon: Icons.blur_on,
          ),
          EditorSegmentOption(
            value: DesignSystem.neumorphism,
            label: 'Neumorphism',
            icon: Icons.wb_twilight,
          ),
        ],
        onChanged: (ds) => onStyleChanged(style.copyWith(designSystem: ds)),
      ),
      EditorSegmentedField<InteractionEffect>(
        buttonKey: ValueKey('$settingPrefix-interactionEffect'),
        label: 'Effet d’interaction (Surface)',
        value: style.interactionEffect,
        options: [
          for (final effect in InteractionEffect.values)
            EditorSegmentOption<InteractionEffect>(
              value: effect,
              label: effect.label,
              icon: switch (effect) {
                InteractionEffect.ripple => Icons.touch_app_outlined,
                InteractionEffect.pressed => Icons.compress,
                InteractionEffect.elevation => Icons.trending_up,
              },
            ),
        ],
        onChanged: (effect) =>
            onStyleChanged(style.copyWith(interactionEffect: effect)),
      ),
      EditorSwitchTile(
        tileKey: ValueKey('$settingPrefix-hoverEffect'),
        title: 'Voile au survol (Surface)',
        value: style.hoverEffect,
        onChanged: (value) => onStyleChanged(style.copyWith(hoverEffect: value)),
      ),
      EditorSwitchTile(
        tileKey: ValueKey('$settingPrefix-neon'),
        title: 'Effet néon',
        value: style.neon?.enabled ?? false,
        onChanged: (enabled) => onStyleChanged(
          style.copyWith(
            neon: (style.neon ?? const NeonStyle()).copyWith(enabled: enabled),
          ),
        ),
      ),
      if (style != const ContainerStyle())
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: ValueKey('$componentPrefix-reset-surface'),
            onPressed: () => onStyleChanged(const ContainerStyle()),
            child: const Text('Réinitialiser la surface avancée'),
          ),
        ),
    ]),
  );
}
