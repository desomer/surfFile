/// Contrôles d'édition de propriétés déclaratives ([buildNativePropertyControl])
/// et délégué de dimensionnement de flux ([NativeRegionFlowDimensionDelegate])
/// utilisés par la boîte de dialogue de configuration de `NativeComponentEditor`.
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/json_syntax.dart';
import '../../../../models/native_component_config.dart';
import '../../../../models/native_property_descriptor.dart';
import '../../dialogs/editor_tabbed_wizard.dart';
import '../../styles/container_style_editor.dart' show styleColorTile;
import '../../history/editor_history.dart';
import '../native_shape_editor.dart';

/// Construit le contrôle d'édition adapté à un [NativePropertyDescriptor]
/// (booléen, couleur, nombre, sélection par segments/liste déroulante ou forme).
Widget buildNativePropertyControl({
  required BuildContext context,
  required String keyPrefix,
  required NativeComponentConfig config,
  required NativePropertyDescriptor descriptor,
  required ValueChanged<NativeComponentConfig> onChanged,
}) {
  final propKey = ValueKey('$keyPrefix-prop-${descriptor.id}');
  final resetKey = ValueKey('$keyPrefix-prop-reset-${descriptor.id}');
  final hasCustomValue = config.property(descriptor.id) != null;

  Widget? resetButton() => descriptor.nullable && hasCustomValue
      ? IconButton(
          key: resetKey,
          tooltip: 'Par défaut (Thème)',
          icon: const Icon(Icons.restart_alt, size: 18),
          onPressed: () =>
              onChanged(config.withProperty(descriptor.id, null)),
        )
      : null;

  return switch (descriptor.editorType) {
    NativePropertyEditorType.bool => SwitchListTile(
      key: propKey,
      title: Text(descriptor.label),
      subtitle: descriptor.subtitle != null ? Text(descriptor.subtitle!) : null,
      secondary: resetButton(),
      value:
          config.boolProperty(descriptor.id) ??
          (descriptor.defaultValue is bool
              ? descriptor.defaultValue as bool
              : false),
      onChanged: (value) =>
          onChanged(config.withProperty(descriptor.id, value)),
    ),
    NativePropertyEditorType.color => Row(
      children: [
        Expanded(
          child: styleColorTile(
            descriptor.label,
            config.colorProperty(descriptor.id) ??
                (descriptor.defaultValue != null
                    ? JsonColor.parse(descriptor.defaultValue, descriptor.id)
                    : Theme.of(context).colorScheme.primary),
            (color) => onChanged(config.withProperty(descriptor.id, color)),
            key: propKey,
            dense: true,
            onClear: descriptor.nullable
                ? () => onChanged(config.withProperty(descriptor.id, null))
                : null,
          ),
        ),
        ?resetButton(),
      ],
    ),
    NativePropertyEditorType.number => () {
      final min = descriptor.min ?? 0.0;
      final max = descriptor.max ?? 100.0;
      final current = config.doubleProperty(descriptor.id);
      final fallback = (descriptor.defaultValue as num?)?.toDouble() ?? min;
      final effective = current ?? fallback;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    current == null
                        ? '${descriptor.label} (Auto)'
                        : descriptor.label,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                ?resetButton(),
              ],
            ),
            if (descriptor.subtitle != null)
              Text(
                descriptor.subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            EditorHistorySlider(
              sliderKey: propKey,
              value: effective,
              min: min,
              max: max,
              divisions: descriptor.divisions,
              allowAboveMax: descriptor.allowsExtendedNumber,
              allowBelowMin: descriptor.allowsExtendedNumber && min < 0,
              onChanged: (value) =>
                  onChanged(config.withProperty(descriptor.id, value)),
            ),
          ],
        ),
      );
    }(),
    NativePropertyEditorType.select => () {
      final effectiveValue =
          config.stringProperty(descriptor.id) ??
          (!descriptor.nullable && descriptor.defaultValue is String
              ? descriptor.defaultValue as String
              : null);
      final totalOptions =
          descriptor.options.length + (descriptor.nullable ? 1 : 0);
      IconData optionIcon(String? val) => switch (val) {
        null => Icons.hdr_auto_outlined,
        'none' => Icons.block,
        'hardEdge' => Icons.crop_sharp,
        'antiAlias' => Icons.blur_linear,
        'antiAliasWithSaveLayer' => Icons.layers_outlined,
        'light' => Icons.light_mode_outlined,
        'dark' => Icons.dark_mode_outlined,
        'fixed' => Icons.push_pin_outlined,
        'shifting' => Icons.swap_horiz,
        'spread' => Icons.space_bar,
        'centered' => Icons.format_align_center,
        'linear' => Icons.view_headline,
        'click' => Icons.touch_app_outlined,
        'basic' => Icons.mouse_outlined,
        'defer' => Icons.subdirectory_arrow_right,
        'chevron' => Icons.expand_more,
        'arrow' => Icons.arrow_downward,
        'plusMinus' => Icons.add,
        'triangle' => Icons.arrow_drop_down,
        'trailing' => Icons.last_page,
        'leading' => Icons.first_page,
        'standard' => Icons.crop_16_9,
        'singleChildScrollView' => Icons.swap_vert,
        'customScrollView' => Icons.view_day_outlined,
        'vertical' => Icons.swap_vert,
        'horizontal' => Icons.swap_horiz,
        _ => Icons.tune,
      };
      if (totalOptions <= 5) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              Text(
                descriptor.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (descriptor.subtitle != null)
                Text(
                  descriptor.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              SegmentedButton<String?>(
                key: propKey,
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: [
                  if (descriptor.nullable)
                    ButtonSegment<String?>(
                      value: null,
                      tooltip: 'Par défaut (Thème)',
                      icon: Flexible(
                        flex: 0,
                        child: Icon(optionIcon(null), size: 14),
                      ),
                      label: const Text(
                        'Par défaut (Thème)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  for (final option in descriptor.options)
                    ButtonSegment<String?>(
                      value: option.value,
                      tooltip: option.label,
                      icon: Flexible(
                        flex: 0,
                        child: Icon(optionIcon(option.value), size: 14),
                      ),
                      label: Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                selected: {effectiveValue},
                onSelectionChanged: (selected) {
                  final value = selected.first;
                  onChanged(
                    config.withProperty(
                      descriptor.id,
                      !descriptor.nullable && value == descriptor.defaultValue
                          ? null
                          : value,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: DropdownButtonFormField<String?>(
          key: propKey,
          isExpanded: true,
          initialValue: effectiveValue,
          decoration: InputDecoration(
            labelText: descriptor.label,
            helperText: descriptor.subtitle,
            isDense: true,
          ),
          items: [
            if (descriptor.nullable)
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Par défaut (Thème)'),
              ),
            for (final option in descriptor.options)
              DropdownMenuItem<String?>(
                value: option.value,
                child: Text(option.label),
              ),
          ],
          onChanged: (value) => onChanged(
            config.withProperty(
              descriptor.id,
              !descriptor.nullable && value == descriptor.defaultValue
                  ? null
                  : value,
            ),
          ),
        ),
      );
    }(),
    NativePropertyEditorType.shape => () {
      final currentShape = config.shapeProperty(descriptor.id);
      return ListTile(
        key: propKey,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: const Icon(Icons.rounded_corner, size: 20),
        title: Text(descriptor.label),
        subtitle: Text(
          currentShape?.summary ??
              (descriptor.subtitle ?? 'Par défaut (Thème)'),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [?resetButton(), const Icon(Icons.tune, size: 18)],
        ),
        onTap: () => showNativeShapeEditor(
          context: context,
          title: descriptor.label,
          initialValue: currentShape,
          keyPrefix: '$keyPrefix-shape-${descriptor.id}',
          onChanged: (nextShape) =>
              onChanged(config.withProperty(descriptor.id, nextShape)),
        ),
      );
    }(),
  };
}

/// Délégué d'onglet « Dimensions » pour éditer le flux flex ([ZoneFlowConfig])
/// et la taille d'une région de composant natif.
class NativeRegionFlowDimensionDelegate extends EditorDimensionDelegate {
  /// Crée un [NativeRegionFlowDimensionDelegate].
  NativeRegionFlowDimensionDelegate({
    required this.title,
    required this.onRestore,
    required this.onReset,
    required this.builder,
  });

  @override
  final String title;

  /// Callback restaurant la configuration initiale en cas d'annulation.
  final VoidCallback onRestore;

  /// Callback réinitialisant le flux et la taille de la région à leurs valeurs par défaut.
  final VoidCallback onReset;

  /// Constructeur du contenu du panneau de paramètres de flux.
  final WidgetBuilder builder;

  @override
  double get contentWidth => 400;

  @override
  void restore() => onRestore();

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  List<Widget> buildExtraActions(
    BuildContext context, {
    required VoidCallback onResetAndClose,
  }) => [TextButton(onPressed: onReset, child: const Text('Réinitialiser'))];
}
