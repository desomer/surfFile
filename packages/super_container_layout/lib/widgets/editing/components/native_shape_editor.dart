/// Éditeur visuel d'une forme de bordure Material ([NativeShapeConfig]).
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/native_shape_config.dart';
import '../../../theme/style_extras.dart' show Quad;
import '../dialogs/editor_dialog.dart';
import '../styles/container_style_editor.dart' show styleColorTile;
import '../history/editor_history.dart';
import 'shared/editor_segmented_field.dart';

/// Ouvre l'éditeur dédié de [NativeShapeConfig] (`ShapeBorder` Flutter).
///
/// Renvoie la configuration appliquée, ou `null` si l'utilisateur a annulé.
/// Si l'utilisateur clique sur `Supprimer la forme` / `Réinitialiser` puis
/// applique, [onCleared] (ou la valeur retournée) met à jour l'appelant.
Future<void> showNativeShapeEditor({
  required BuildContext context,
  required String title,
  required NativeShapeConfig? initialValue,
  required ValueChanged<NativeShapeConfig?> onChanged,
  String keyPrefix = 'native-shape',
}) async {
  final initial = initialValue;
  final draft = ValueNotifier<NativeShapeConfig>(
    initialValue ?? const NativeShapeConfig(radius: 16),
  );
  var resetToDefault = false;
  try {
    final confirmed =
        await showEditorDialog<bool>(
          context: context,
          target: context,
          builder: (dialogContext) => AlertDialog(
            key: ValueKey('$keyPrefix-dialog'),
            title: Text(title),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: ValueListenableBuilder<NativeShapeConfig>(
                  valueListenable: draft,
                  builder: (context, shape, _) {
                    void update(NativeShapeConfig next) {
                      resetToDefault = false;
                      draft.value = next;
                      onChanged(next);
                    }

                    final colors = Theme.of(context).colorScheme;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 64,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: 0.4,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            key: ValueKey('$keyPrefix-preview'),
                            color: colors.primaryContainer,
                            elevation: 2,
                            shape: shape.toShapeBorder(colorScheme: colors),
                            clipBehavior: Clip.antiAlias,
                            child: Center(
                              child: Text(
                                shape.summary,
                                style: TextStyle(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        EditorSegmentedField<NativeShapeKind>(
                          buttonKey: ValueKey('$keyPrefix-kind'),
                          label: 'Type de forme (ShapeBorder)',
                          spacing: 6,
                          value: shape.kind,
                          options: [
                            for (final kind in NativeShapeKind.values)
                              EditorSegmentOption<NativeShapeKind>(
                                value: kind,
                                label: kind.label,
                                iconSize: 14,
                                flexibleIcon: true,
                                icon: switch (kind) {
                                  NativeShapeKind.rounded =>
                                    Icons.rounded_corner,
                                  NativeShapeKind.continuous =>
                                    Icons.crop_square,
                                  NativeShapeKind.beveled => Icons.content_cut,
                                  NativeShapeKind.stadium =>
                                    Icons.stadium_outlined,
                                  NativeShapeKind.linear =>
                                    Icons.horizontal_rule,
                                },
                              ),
                          ],
                          onChanged: (kind) =>
                              update(shape.copyWith(kind: kind)),
                        ),
                        if (shape.kind.supportsCornerRadius) ...[
                          const SizedBox(height: 8),
                          EditorSwitchTile(
                            tileKey: ValueKey('$keyPrefix-independent-corners'),
                            title: 'Coins indépendants',
                            subtitle: 'Rayon distinct par angle (ex: arrondir uniquement le bas)',
                            value: shape.radii != null,
                            onChanged: (independent) => update(
                              shape.copyWith(
                                radii: independent
                                    ? Quad.all(shape.radius)
                                    : null,
                                clearRadii: !independent,
                              ),
                            ),
                          ),
                          if (shape.radii == null)
                            _ShapeSlider(
                              sliderKey: ValueKey('$keyPrefix-radius'),
                              label: 'Rayon des coins',
                              value: shape.radius,
                              max: NativeShapeConfig.maxRadius,
                              onChanged: (v) =>
                                  update(shape.copyWith(radius: v)),
                            )
                          else ...[
                            _ShapeSlider(
                              sliderKey: ValueKey('$keyPrefix-corner-0'),
                              label: 'Haut gauche',
                              value: shape.radii!.top,
                              max: NativeShapeConfig.maxRadius,
                              onChanged: (v) => update(
                                shape.copyWith(
                                  radii: shape.radii!.withAt(0, v),
                                ),
                              ),
                            ),
                            _ShapeSlider(
                              sliderKey: ValueKey('$keyPrefix-corner-1'),
                              label: 'Haut droit',
                              value: shape.radii!.right,
                              max: NativeShapeConfig.maxRadius,
                              onChanged: (v) => update(
                                shape.copyWith(
                                  radii: shape.radii!.withAt(1, v),
                                ),
                              ),
                            ),
                            _ShapeSlider(
                              sliderKey: ValueKey('$keyPrefix-corner-2'),
                              label: 'Bas droit',
                              value: shape.radii!.bottom,
                              max: NativeShapeConfig.maxRadius,
                              onChanged: (v) => update(
                                shape.copyWith(
                                  radii: shape.radii!.withAt(2, v),
                                ),
                              ),
                            ),
                            _ShapeSlider(
                              sliderKey: ValueKey('$keyPrefix-corner-3'),
                              label: 'Bas gauche',
                              value: shape.radii!.left,
                              max: NativeShapeConfig.maxRadius,
                              onChanged: (v) => update(
                                shape.copyWith(
                                  radii: shape.radii!.withAt(3, v),
                                ),
                              ),
                            ),
                          ],
                        ],
                        if (shape.kind == NativeShapeKind.linear) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Côtés actifs',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilterChip(
                                key: ValueKey('$keyPrefix-side-bottom'),
                                label: const Text('Bas'),
                                selected: shape.bottom,
                                onSelected: (v) =>
                                    update(shape.copyWith(bottom: v)),
                              ),
                              FilterChip(
                                key: ValueKey('$keyPrefix-side-top'),
                                label: const Text('Haut'),
                                selected: shape.top,
                                onSelected: (v) =>
                                    update(shape.copyWith(top: v)),
                              ),
                              FilterChip(
                                key: ValueKey('$keyPrefix-side-left'),
                                label: const Text('Gauche'),
                                selected: shape.left,
                                onSelected: (v) =>
                                    update(shape.copyWith(left: v)),
                              ),
                              FilterChip(
                                key: ValueKey('$keyPrefix-side-right'),
                                label: const Text('Droite'),
                                selected: shape.right,
                                onSelected: (v) =>
                                    update(shape.copyWith(right: v)),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 24),
                        _ShapeSlider(
                          sliderKey: ValueKey('$keyPrefix-border-width'),
                          label: 'Épaisseur de la bordure',
                          value: shape.borderWidth,
                          max: NativeShapeConfig.maxBorderWidth,
                          divisions: 32,
                          onChanged: (v) =>
                              update(shape.copyWith(borderWidth: v)),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: styleColorTile(
                                'Couleur de la bordure',
                                shape.borderColor ?? colors.outline,
                                (color) =>
                                    update(shape.copyWith(borderColor: color)),
                                key: ValueKey('$keyPrefix-border-color'),
                                dense: true,
                                onClear: () => update(
                                  shape.copyWith(clearBorderColor: true),
                                ),
                              ),
                            ),
                            if (shape.borderColor != null)
                              IconButton(
                                key: ValueKey('$keyPrefix-border-color-reset'),
                                tooltip: 'Couleur par défaut',
                                icon: const Icon(Icons.restart_alt, size: 18),
                                onPressed: () => update(
                                  shape.copyWith(clearBorderColor: true),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                key: ValueKey('$keyPrefix-reset'),
                onPressed: () {
                  resetToDefault = true;
                  draft.value = const NativeShapeConfig();
                  onChanged(null);
                },
                child: const Text('Réinitialiser'),
              ),
              TextButton(
                key: ValueKey('$keyPrefix-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                key: ValueKey('$keyPrefix-apply'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Appliquer'),
              ),
            ],
          ),
        ) ==
        true;
    if (!confirmed) {
      onChanged(initial);
    } else if (!resetToDefault && initial == null) {
      onChanged(draft.value);
    }
  } finally {
    draft.dispose();
  }
}

class _ShapeSlider extends StatelessWidget {
  const _ShapeSlider({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.divisions = 64,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        EditorHistorySlider(
          sliderKey: sliderKey,
          unit: 'px',
          value: value,
          allowAboveMax: true,
          min: 0,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
