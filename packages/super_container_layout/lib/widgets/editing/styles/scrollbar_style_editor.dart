import 'package:material_ui/material_ui.dart';

import '../../../models/scrollbar_style_config.dart';
import '../../components/super_layout/slot_implementation.dart'
    show ZoneScrollableViewport;
import '../dialogs/editor_dialog.dart';
import '../history/editor_history.dart';
import 'container_style_editor.dart' show styleColorTile;

/// Ouvre l'éditeur dédié de [ScrollbarStyleConfig] pour styler la `ScrollBar`
/// d'une zone en défilement automatique.
///
/// Applique les changements en temps réel via [onChanged] pour prévisualiser
/// sur la zone, et restaure la configuration initiale si l'utilisateur annule.
Future<void> showScrollbarStyleEditor({
  required BuildContext context,
  required ScrollbarStyleConfig initialValue,
  required ValueChanged<ScrollbarStyleConfig> onChanged,
  Axis axis = Axis.vertical,
  String title = 'Style de la barre de défilement',
  String keyPrefix = 'scrollbar-style',
}) async {
  final initial = initialValue;
  final draft = ValueNotifier<ScrollbarStyleConfig>(initialValue);
  try {
    final confirmed =
        await showEditorDialog<bool>(
          context: context,
          target: context,
          barrierDismissible: true,
          barrierColor: Colors.transparent,
          builder: (dialogContext) => AlertDialog(
            key: ValueKey('$keyPrefix-dialog'),
            title: Text(title),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: ValueListenableBuilder<ScrollbarStyleConfig>(
                  valueListenable: draft,
                  builder: (context, style, _) => ScrollbarStyleEditor(
                    keyPrefix: keyPrefix,
                    axis: axis,
                    style: style,
                    onChanged: (next) {
                      draft.value = next;
                      onChanged(next);
                    },
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                key: ValueKey('$keyPrefix-reset'),
                onPressed: () {
                  const reset = ScrollbarStyleConfig();
                  draft.value = reset;
                  onChanged(reset);
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
    }
  } finally {
    draft.dispose();
  }
}

/// Formulaire d'édition de [ScrollbarStyleConfig] avec aperçu interactif.
class ScrollbarStyleEditor extends StatelessWidget {
  const ScrollbarStyleEditor({
    required this.style,
    required this.onChanged,
    this.axis = Axis.vertical,
    this.keyPrefix = 'scrollbar-style',
    super.key,
  });

  final ScrollbarStyleConfig style;
  final ValueChanged<ScrollbarStyleConfig> onChanged;
  final Axis axis;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScrollbarPreview(
          key: ValueKey('$keyPrefix-preview'),
          axis: axis,
          style: style,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: ValueKey('$keyPrefix-thumb-visibility'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Toujours afficher le curseur',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: const Text(
            'Maintient la barre visible même hors défilement.',
            style: TextStyle(fontSize: 11),
          ),
          value: style.thumbVisibility,
          onChanged: (v) => onChanged(style.copyWith(thumbVisibility: v)),
        ),
        SwitchListTile(
          key: ValueKey('$keyPrefix-track-visibility'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Afficher la piste (track)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: const Text(
            'Dessine le rail en arrière-plan du curseur.',
            style: TextStyle(fontSize: 11),
          ),
          value: style.trackVisibility,
          onChanged: (v) => onChanged(style.copyWith(trackVisibility: v)),
        ),
        SwitchListTile(
          key: ValueKey('$keyPrefix-interactive'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Curseur interactif',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: const Text(
            'Permet de faire glisser la barre à la souris ou au doigt.',
            style: TextStyle(fontSize: 11),
          ),
          value: style.interactive,
          onChanged: (v) => onChanged(style.copyWith(interactive: v)),
        ),
        const SizedBox(height: 8),
        Text(
          'Position de la barre',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ScrollbarSide>(
            key: ValueKey('$keyPrefix-side'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              for (final option in ScrollbarSide.values)
                ButtonSegment<ScrollbarSide>(
                  value: option,
                  tooltip: option.labelForAxis(axis),
                  icon: Icon(
                    switch ((axis, option)) {
                      (_, ScrollbarSide.auto) => Icons.hdr_auto_outlined,
                      (Axis.vertical, ScrollbarSide.start) =>
                        Icons.align_horizontal_left,
                      (Axis.vertical, ScrollbarSide.end) =>
                        Icons.align_horizontal_right,
                      (Axis.horizontal, ScrollbarSide.start) =>
                        Icons.align_vertical_top,
                      (Axis.horizontal, ScrollbarSide.end) =>
                        Icons.align_vertical_bottom,
                    },
                    size: 16,
                  ),
                  label: Text(
                    option.labelForAxis(axis),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            selected: {style.side},
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) {
                onChanged(style.copyWith(side: selected.first));
              }
            },
          ),
        ),
        const Divider(height: 24),
        _ScrollbarSlider(
          sliderKey: ValueKey('$keyPrefix-thickness'),
          label: 'Épaisseur',
          value: style.thickness,
          min: ScrollbarStyleConfig.minThickness,
          max: ScrollbarStyleConfig.maxThickness,
          onChanged: (v) =>
              onChanged(style.copyWith(thickness: v.roundToDouble())),
        ),
        _ScrollbarSlider(
          sliderKey: ValueKey('$keyPrefix-radius'),
          label: 'Rayon d’arrondi',
          value: style.radius,
          min: 0,
          max: ScrollbarStyleConfig.maxRadius,
          onChanged: (v) =>
              onChanged(style.copyWith(radius: v.roundToDouble())),
        ),
        _ScrollbarSlider(
          sliderKey: ValueKey('$keyPrefix-main-axis-margin'),
          label: 'Marge longitudinale (extrémités)',
          value: style.mainAxisMargin,
          min: 0,
          max: ScrollbarStyleConfig.maxMainAxisMargin,
          onChanged: (v) =>
              onChanged(style.copyWith(mainAxisMargin: v.roundToDouble())),
        ),
        _ScrollbarSlider(
          sliderKey: ValueKey('$keyPrefix-cross-axis-margin'),
          label: 'Marge latérale (bord)',
          value: style.crossAxisMargin,
          min: 0,
          max: ScrollbarStyleConfig.maxCrossAxisMargin,
          onChanged: (v) =>
              onChanged(style.copyWith(crossAxisMargin: v.roundToDouble())),
        ),
        const Divider(height: 24),
        _ColorControlRow(
          tileKey: ValueKey('$keyPrefix-thumb-color'),
          resetKey: ValueKey('$keyPrefix-thumb-color-reset'),
          label: 'Couleur du curseur',
          color:
              style.thumbColor ?? colors.onSurfaceVariant.withValues(alpha: .45),
          hasCustomColor: style.thumbColor != null,
          onChanged: (color) => onChanged(style.copyWith(thumbColor: color)),
          onReset: () => onChanged(style.copyWith(clearThumbColor: true)),
        ),
        _ColorControlRow(
          tileKey: ValueKey('$keyPrefix-track-color'),
          resetKey: ValueKey('$keyPrefix-track-color-reset'),
          label: 'Couleur de la piste',
          color:
              style.trackColor ??
              colors.surfaceContainerHighest.withValues(alpha: .35),
          hasCustomColor: style.trackColor != null,
          onChanged: (color) => onChanged(style.copyWith(trackColor: color)),
          onReset: () => onChanged(style.copyWith(clearTrackColor: true)),
        ),
        _ColorControlRow(
          tileKey: ValueKey('$keyPrefix-track-border-color'),
          resetKey: ValueKey('$keyPrefix-track-border-color-reset'),
          label: 'Bordure de la piste',
          color:
              style.trackBorderColor ??
              colors.outlineVariant.withValues(alpha: .5),
          hasCustomColor: style.trackBorderColor != null,
          onChanged: (color) =>
              onChanged(style.copyWith(trackBorderColor: color)),
          onReset: () => onChanged(style.copyWith(clearTrackBorderColor: true)),
        ),
      ],
    );
  }
}

class _ScrollbarPreview extends StatelessWidget {
  const _ScrollbarPreview({
    required this.axis,
    required this.style,
    super.key,
  });

  final Axis axis;
  final ScrollbarStyleConfig style;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items = [
      for (var i = 1; i <= 6; i++)
        Container(
          width: axis == Axis.horizontal ? 110 : double.infinity,
          height: axis == Axis.vertical ? 34 : double.infinity,
          margin: EdgeInsets.only(
            bottom: axis == Axis.vertical && i < 6 ? 6 : 0,
            right: axis == Axis.horizontal && i < 6 ? 6 : 0,
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.secondaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Élément $i',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.onSecondaryContainer,
            ),
          ),
        ),
    ];
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ZoneScrollableViewport(
        axis: axis,
        showScrollbar: true,
        scrollbarStyle: style,
        padding: const EdgeInsets.all(10),
        child: axis == Axis.horizontal
            ? Row(mainAxisSize: MainAxisSize.min, children: items)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items,
              ),
      ),
    );
  }
}

class _ScrollbarSlider extends StatelessWidget {
  const _ScrollbarSlider({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final formatted = value == value.roundToDouble()
        ? '${value.round()} px'
        : '${value.toStringAsFixed(1)} px';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                formatted,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
        EditorHistorySlider(
          key: sliderKey,
          min: min,
          max: max,
          value: value.clamp(min, max),
          label: formatted,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorControlRow extends StatelessWidget {
  const _ColorControlRow({
    required this.tileKey,
    required this.resetKey,
    required this.label,
    required this.color,
    required this.hasCustomColor,
    required this.onChanged,
    required this.onReset,
  });

  final Key tileKey;
  final Key resetKey;
  final String label;
  final Color color;
  final bool hasCustomColor;
  final ValueChanged<Color> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: styleColorTile(
          label,
          color,
          onChanged,
          key: tileKey,
          dense: true,
          onClear: onReset,
        ),
      ),
      if (hasCustomColor)
        IconButton(
          key: resetKey,
          tooltip: 'Couleur par défaut',
          icon: const Icon(Icons.restart_alt, size: 18),
          onPressed: onReset,
        ),
    ],
  );
}
