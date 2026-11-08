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
      const Text(
        'Système de design (Surface)',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      SegmentedButton<DesignSystem>(
        key: ValueKey('$settingPrefix-designSystem'),
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: const [
          ButtonSegment(
            value: DesignSystem.material,
            tooltip: 'Material',
            icon: Icon(Icons.layers_outlined, size: 16),
            label: Text('Material', overflow: TextOverflow.ellipsis),
          ),
          ButtonSegment(
            value: DesignSystem.liquidGlass,
            tooltip: 'Liquid Glass',
            icon: Icon(Icons.blur_on, size: 16),
            label: Text('Liquid Glass', overflow: TextOverflow.ellipsis),
          ),
          ButtonSegment(
            value: DesignSystem.neumorphism,
            tooltip: 'Neumorphism',
            icon: Icon(Icons.wb_twilight, size: 16),
            label: Text('Neumorphism', overflow: TextOverflow.ellipsis),
          ),
        ],
        selected: {style.designSystem},
        onSelectionChanged: (selected) {
          if (selected.isNotEmpty) {
            onStyleChanged(style.copyWith(designSystem: selected.first));
          }
        },
      ),
      const Text(
        'Effet d’interaction (Surface)',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      SegmentedButton<InteractionEffect>(
        key: ValueKey('$settingPrefix-interactionEffect'),
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: [
          for (final effect in InteractionEffect.values)
            ButtonSegment<InteractionEffect>(
              value: effect,
              tooltip: effect.label,
              icon: Icon(
                switch (effect) {
                  InteractionEffect.ripple => Icons.touch_app_outlined,
                  InteractionEffect.pressed => Icons.compress,
                  InteractionEffect.elevation => Icons.trending_up,
                },
                size: 16,
              ),
              label: Text(effect.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        selected: {style.interactionEffect},
        onSelectionChanged: (selected) {
          if (selected.isNotEmpty) {
            onStyleChanged(style.copyWith(interactionEffect: selected.first));
          }
        },
      ),
      SwitchListTile(
        key: ValueKey('$settingPrefix-hoverEffect'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Voile au survol (Surface)'),
        value: style.hoverEffect,
        onChanged: (value) => onStyleChanged(style.copyWith(hoverEffect: value)),
      ),
      SwitchListTile(
        key: ValueKey('$settingPrefix-neon'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Effet néon'),
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
