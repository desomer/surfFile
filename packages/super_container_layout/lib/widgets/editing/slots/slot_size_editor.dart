import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart';
import '../../super_layout/slot_implementation.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../history/editor_history.dart';
import '../styles/independent_spacing_editor.dart';

typedef SlotSizeGeometry = ({Size layout, Rect zone, Rect slot});

Future<void> showSlotSizeEditor({
  required BuildContext context,
  required SlotImplementation slot,
  required SlotSizeConstraints? saved,
  required Size? legacy,
  required Listenable changes,
  required SlotSizeGeometry? Function() measure,
  required void Function(SlotSizeConstraints dimensions, bool useLegacyPixels)
  onApply,
  required VoidCallback onRestore,
  BuildContext? target,
  String? initialLabel,
  ValueChanged<String>? onLabelChanged,
}) async {
  final history = EditorHistoryScope.controllerOf(context);
  history?.beginTransaction();
  var transactionCompleted = false;
  final label = ValueNotifier(initialLabel ?? slot.label);
  final fields = {
    'min-width': (saved?.minWidth, 'Largeur minimale'),
    'min-height': (saved?.minHeight, 'Hauteur minimale'),
    'preferred-width': (
      saved?.preferredWidth ??
          ((saved == null || !saved.hasSizeConstraints) && legacy != null
              ? legacy.width.isFinite
                    ? SlotDimension(legacy.width, SlotSizeUnit.pixels)
                    : null
              : null),
      'Largeur préférée',
    ),
    'preferred-height': (
      saved?.preferredHeight ??
          ((saved == null || !saved.hasSizeConstraints) && legacy != null
              ? legacy.height.isFinite
                    ? SlotDimension(legacy.height, SlotSizeUnit.pixels)
                    : null
              : null),
      'Hauteur préférée',
    ),
    'max-width': (saved?.maxWidth, 'Largeur maximale'),
    'max-height': (saved?.maxHeight, 'Hauteur maximale'),
  };
  final controllers = {
    for (final entry in fields.entries)
      entry.key: TextEditingController(
        text: entry.value.$1?.value.toString() ?? '',
      ),
  };
  final units = {
    for (final entry in fields.entries)
      entry.key: ValueNotifier(entry.value.$1?.unit ?? SlotSizeUnit.pixels),
  };
  final percentBasis = ValueNotifier(
    saved?.percentBasis ?? SlotPercentBasis.layout,
  );
  final sliderGroup = ValueNotifier('preferred');
  final padding = ValueNotifier(saved?.padding ?? 0.0);
  final paddingInsets = ValueNotifier(saved?.paddingInsets);
  var percentBasisChanged = false;
  final form = GlobalKey<FormState>();
  String? validate(String? text) {
    if ((text ?? '').trim().isEmpty) return null;
    final value = double.tryParse(text!.replaceAll(',', '.'));
    return value != null && value.isFinite && value >= 0
        ? null
        : 'Saisissez une dimension positive en pixels ou en %.';
  }

  SlotSizeConstraints readDimensions() {
    SlotDimension? dimension(String key) {
      final text = controllers[key]!.text.trim();
      if (text.isEmpty) return null;
      return SlotDimension(
        double.parse(text.replaceAll(',', '.')),
        units[key]!.value,
      );
    }

    return SlotSizeConstraints(
      minWidth: dimension('min-width'),
      minHeight: dimension('min-height'),
      preferredWidth: dimension('preferred-width'),
      preferredHeight: dimension('preferred-height'),
      maxWidth: dimension('max-width'),
      maxHeight: dimension('max-height'),
      padding: padding.value,
      paddingInsets: paddingInsets.value,
      percentBasis: percentBasis.value,
    );
  }

  String? boundsError() {
    if (controllers.values.any((c) => validate(c.text) != null)) return null;
    final geometry = measure();
    final basis = percentBasis.value == SlotPercentBasis.layout
        ? geometry?.layout
        : geometry?.zone.size;
    final dimensions = readDimensions();
    for (final (minimum, maximum, extent, label) in [
      (dimensions.minWidth, dimensions.maxWidth, basis?.width, 'largeur'),
      (dimensions.minHeight, dimensions.maxHeight, basis?.height, 'hauteur'),
    ]) {
      if (minimum != null &&
          maximum != null &&
          (extent != null || minimum.unit == maximum.unit) &&
          minimum.resolve(extent ?? 100) > maximum.resolve(extent ?? 100)) {
        return 'La $label minimale dépasse la $label maximale.';
      }
    }
    return null;
  }

  var lastPreview = readDimensions();
  void applyDimensions(SlotSizeConstraints dimensions) {
    onApply(dimensions, saved == null && !percentBasisChanged);
  }

  void preview() {
    if (!context.mounted ||
        controllers.values.any(
          (controller) => validate(controller.text) != null,
        ) ||
        boundsError() != null) {
      return;
    }
    final dimensions = readDimensions();
    if (dimensions == lastPreview) return;
    lastPreview = dimensions;
    applyDimensions(dimensions);
  }

  for (final controller in controllers.values) {
    controller.addListener(preview);
  }
  for (final unit in units.values) {
    unit.addListener(preview);
  }
  padding.addListener(preview);
  paddingInsets.addListener(preview);
  percentBasis.addListener(preview);
  final layoutSize = context.size ?? Size.zero;

  try {
    final result = await showEditorDialog<SlotSizeConstraints>(
      context: context,
      target: target ?? context,
      barrierColor: Colors.transparent,
      builder: (context) => AlertDialog(
        title: ValueListenableBuilder<String>(
          valueListenable: label,
          builder: (context, value, _) => EditorDialogHeader(
            label: 'Taille et marge préférées : $value',
            editableLabel: onLabelChanged == null ? null : value,
            onLabelChanged: onLabelChanged == null
                ? null
                : (value) {
                    label.value = value;
                    onLabelChanged(value);
                  },
          ),
        ),
        content: SizedBox(
          width: 560,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  ...controllers.values,
                  ...units.values,
                  padding,
                  paddingInsets,
                  percentBasis,
                  sliderGroup,
                  changes,
                ]),
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Base de calcul des pourcentages'),
                    ValueListenableBuilder<SlotPercentBasis>(
                      valueListenable: percentBasis,
                      builder: (context, value, _) =>
                          DropdownButton<SlotPercentBasis>(
                            key: const ValueKey('slot-percent-basis'),
                            isExpanded: true,
                            value: value,
                            onChanged: (basis) {
                              if (basis != null) {
                                percentBasisChanged = true;
                                percentBasis.value = basis;
                              }
                            },
                            items: const [
                              DropdownMenuItem(
                                value: SlotPercentBasis.zone,
                                child: Text('Espace disponible de la zone'),
                              ),
                              DropdownMenuItem(
                                value: SlotPercentBasis.layout,
                                child: Text('Toute la place du layout'),
                              ),
                            ],
                          ),
                    ),
                    _SlotSizePreview(
                      measure: measure,
                      dimensions:
                          controllers.values.any(
                            (c) => validate(c.text) != null,
                          )
                          ? lastPreview
                          : readDimensions(),
                    ),
                    if (boundsError() case final error?)
                      Text(
                        error,
                        key: const ValueKey('slot-bounds-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (group, label) in [
                          ('min', 'Min'),
                          ('preferred', 'Préférée'),
                          ('max', 'Max'),
                        ])
                          ChoiceChip(
                            key: ValueKey('slot-slider-group-$group'),
                            label: Text(label),
                            selected: sliderGroup.value == group,
                            onSelected: (_) => sliderGroup.value = group,
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              const Text('Largeur'),
                              _slotDimensionSlider(
                                '${sliderGroup.value}-width',
                                controllers,
                                units,
                                layoutSize,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            const Text('Hauteur'),
                            SizedBox(
                              height: 120,
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: _slotDimensionSlider(
                                  '${sliderGroup.value}-height',
                                  controllers,
                                  units,
                                  layoutSize,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    for (final entry in fields.entries) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('slot-${entry.key}'),
                              controller: controllers[entry.key],
                              decoration: InputDecoration(
                                labelText: entry.value.$2,
                                hintText: entry.key.startsWith('max')
                                    ? 'Sans limite'
                                    : entry.key.startsWith('min')
                                    ? 'Aucune'
                                    : 'Auto',
                                suffixIcon: IconButton(
                                  key: ValueKey('slot-clear-${entry.key}'),
                                  tooltip:
                                      'Effacer ${entry.value.$2.toLowerCase()}',
                                  onPressed:
                                      controllers[entry.key]!.text.isEmpty
                                      ? null
                                      : controllers[entry.key]!.clear,
                                  icon: const Icon(Icons.clear),
                                ),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: validate,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ValueListenableBuilder<SlotSizeUnit>(
                            valueListenable: units[entry.key]!,
                            builder: (context, unit, _) =>
                                DropdownButton<SlotSizeUnit>(
                                  key: ValueKey('slot-unit-${entry.key}'),
                                  value: unit,
                                  onChanged: (value) {
                                    if (value != null) {
                                      units[entry.key]!.value = value;
                                    }
                                  },
                                  items: const [
                                    DropdownMenuItem(
                                      value: SlotSizeUnit.pixels,
                                      child: Text('px'),
                                    ),
                                    DropdownMenuItem(
                                      value: SlotSizeUnit.percent,
                                      child: Text('%'),
                                    ),
                                  ],
                                ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    _SlotPaddingCard(
                      child: IndependentSpacingEditor(
                        label: 'Marge uniforme',
                        value: padding.value,
                        sides: paddingInsets.value,
                        max: SlotSizeConstraints.maxPadding,
                        keyPrefix: 'slot-padding',
                        sliderKey: const ValueKey('slot-padding'),
                        independentKey: const ValueKey(
                          'slot-padding-independent',
                        ),
                        onChanged: (value, sides) {
                          padding.value = value;
                          paddingInsets.value = sides;
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const SlotSizeConstraints()),
            child: const Text('Taille et marge par défaut'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate() || boundsError() != null) {
                return;
              }
              Navigator.of(context).pop(readDimensions());
            },
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
    if (result == null && context.mounted) {
      onRestore();
      history?.cancelTransaction();
    } else if (result != null && context.mounted) {
      applyDimensions(result);
      history?.commitTransaction();
    } else {
      history?.commitTransaction();
    }
    transactionCompleted = true;
  } finally {
    if (!transactionCompleted) history?.commitTransaction();
    for (final controller in controllers.values) {
      controller.removeListener(preview);
    }
    for (final unit in units.values) {
      unit.removeListener(preview);
    }
    percentBasis.removeListener(preview);
    padding.removeListener(preview);
    paddingInsets.removeListener(preview);
    // Le dialogue peut encore terminer son animation de fermeture.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      for (final unit in units.values) {
        unit.dispose();
      }
      percentBasis.dispose();
      padding.dispose();
      paddingInsets.dispose();
      sliderGroup.dispose();
      label.dispose();
    });
  }
}

class _SlotPaddingCard extends StatelessWidget {
  const _SlotPaddingCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('slot-padding-card'),
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.padding, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Marge autour du contenu',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

Widget _slotDimensionSlider(
  String key,
  Map<String, TextEditingController> controllers,
  Map<String, ValueNotifier<SlotSizeUnit>> units,
  Size layoutSize,
) {
  final value = double.tryParse(
    controllers[key]!.text.trim().replaceAll(',', '.'),
  );
  final percent = units[key]!.value == SlotSizeUnit.percent;
  final extent = key.endsWith('width') ? layoutSize.width : layoutSize.height;
  final baseMax = percent ? 100.0 : (extent > 0 ? extent : 1000.0);
  final max = value != null && value.isFinite && value > baseMax
      ? value
      : baseMax;
  return Slider(
    key: ValueKey('slot-slider-$key'),
    value: value != null && value.isFinite ? value.clamp(0, max) : 0,
    max: max,
    label: value == null
        ? key.startsWith('max')
              ? 'Sans limite'
              : key.startsWith('min')
              ? 'Aucune'
              : 'Auto'
        : '$value ${percent ? '%' : 'px'}',
    semanticFormatterCallback: (value) =>
        '${key.endsWith('width') ? 'Largeur' : 'Hauteur'} : '
        '${value.round()} ${percent ? '%' : 'px'}',
    onChanged: (value) => controllers[key]!.text = value.round().toString(),
  );
}

class _SlotSizePreview extends StatefulWidget {
  const _SlotSizePreview({required this.measure, required this.dimensions});

  final ({Size layout, Rect zone, Rect slot})? Function() measure;
  final SlotSizeConstraints dimensions;

  @override
  State<_SlotSizePreview> createState() => _SlotSizePreviewState();
}

class _SlotSizePreviewState extends State<_SlotSizePreview> {
  ({Size layout, Rect zone, Rect slot})? geometry;

  @override
  void initState() {
    super.initState();
    geometry = widget.measure();
    refresh();
  }

  @override
  void didUpdateWidget(_SlotSizePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    refresh();
  }

  void refresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = widget.measure();
      if (next != geometry) setState(() => geometry = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final measured = geometry;
    if (measured == null || measured.layout.isEmpty) {
      return const Text(
        'Preview indisponible : géométrie du slot non mesurable.',
      );
    }
    final colors = Theme.of(context).colorScheme;
    final basis = widget.dimensions.percentBasis == SlotPercentBasis.layout
        ? measured.layout
        : measured.zone.size;
    String dimension(SlotDimension? value, double extent) => value == null
        ? 'Auto'
        : '${value.resolve(extent).toStringAsFixed(1)} px';
    return Column(
      children: [
        const Text('Layout / zone / slot'),
        SizedBox(
          height: 150,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = (constraints.maxWidth / measured.layout.width)
                  .clamp(0.0, 150 / measured.layout.height);
              Rect scaled(Rect rect) => Rect.fromLTWH(
                rect.left * scale,
                rect.top * scale,
                rect.width * scale,
                rect.height * scale,
              );
              return Center(
                child: SizedBox(
                  width: measured.layout.width * scale,
                  height: measured.layout.height * scale,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          key: const ValueKey('slot-preview-layout'),
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.outline),
                          ),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: scaled(measured.zone),
                        child: DecoratedBox(
                          key: const ValueKey('slot-preview-zone'),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer.withValues(
                              alpha: .4,
                            ),
                            border: Border.all(color: colors.secondary),
                          ),
                        ),
                      ),
                      for (final (name, width, height) in [
                        (
                          'min',
                          widget.dimensions.minWidth,
                          widget.dimensions.minHeight,
                        ),
                        (
                          'max',
                          widget.dimensions.maxWidth,
                          widget.dimensions.maxHeight,
                        ),
                      ])
                        if (width != null || height != null)
                          Positioned.fromRect(
                            rect: scaled(
                              Rect.fromLTWH(
                                measured.slot.left,
                                measured.slot.top,
                                (width?.resolve(basis.width) ??
                                        measured.slot.width)
                                    .clamp(0, measured.layout.width),
                                (height?.resolve(basis.height) ??
                                        measured.slot.height)
                                    .clamp(0, measured.layout.height),
                              ),
                            ),
                            child: CustomPaint(
                              key: ValueKey('slot-preview-$name'),
                              painter: _SlotSizeBoundsPainter(colors.tertiary),
                            ),
                          ),
                      Positioned.fromRect(
                        rect: scaled(measured.slot),
                        child: DecoratedBox(
                          key: const ValueKey('slot-preview-slot'),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .25),
                            border: Border.all(color: colors.primary, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Text(
          'Préférée : ${dimension(widget.dimensions.preferredWidth, basis.width)}'
          ' × ${dimension(widget.dimensions.preferredHeight, basis.height)}',
        ),
        Text(
          'Effective : ${measured.slot.width.toStringAsFixed(1)}'
          ' × ${measured.slot.height.toStringAsFixed(1)} px',
          key: const ValueKey('slot-preview-effective'),
        ),
        Text(
          'Marge autour du contenu : '
          '${widget.dimensions.contentPadding}',
        ),
        if (widget.dimensions.minWidth != null ||
            widget.dimensions.minHeight != null ||
            widget.dimensions.maxWidth != null ||
            widget.dimensions.maxHeight != null)
          const Text('Pointillés : limites min / max'),
      ],
    );
  }
}

class _SlotSizeBoundsPainter extends CustomPainter {
  const _SlotSizeBoundsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    void dashed(Offset start, Offset end) {
      final length = (end - start).distance;
      if (length == 0) return;
      final direction = (end - start) / length;
      for (var position = 0.0; position < length; position += 8) {
        canvas.drawLine(
          start + direction * position,
          start + direction * (position + 4).clamp(0, length),
          paint,
        );
      }
    }

    dashed(Offset.zero, Offset(size.width, 0));
    dashed(Offset(size.width, 0), Offset(size.width, size.height));
    dashed(Offset(size.width, size.height), Offset(0, size.height));
    dashed(Offset(0, size.height), Offset.zero);
  }

  @override
  bool shouldRepaint(_SlotSizeBoundsPainter oldDelegate) =>
      color != oldDelegate.color;
}
