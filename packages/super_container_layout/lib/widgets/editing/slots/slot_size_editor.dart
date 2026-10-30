import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart';
import '../../components/super_layout/slot_implementation.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../history/editor_history.dart';
import '../styles/independent_spacing_editor.dart';

typedef SlotSizeGeometry = ({Size layout, Rect zone, Rect slot});

/// Délégué d'édition des contraintes de taille et marge d'un slot pour
/// l'onglet « Taille et marge » du wizard unifié.
class SlotSizeDimensionDelegate extends EditorDimensionDelegate {
  SlotSizeDimensionDelegate({
    required this.context,
    required this.slot,
    required this.saved,
    required this.legacy,
    required this.changes,
    required this.measure,
    required this._onApply,
    required this._onRestore,
    String? initialLabel,
    this._onLabelChanged,
  }) : label = ValueNotifier(initialLabel ?? slot.label),
       percentBasis = ValueNotifier(
         saved?.percentBasis ?? SlotPercentBasis.layout,
       ),
       sliderGroup = ValueNotifier('preferred'),
       padding = ValueNotifier(saved?.padding ?? 0.0),
       paddingInsets = ValueNotifier(saved?.paddingInsets),
       fitContent = ValueNotifier<bool?>(saved?.fitContent),
       layoutSize = context.size ?? Size.zero {
    fields = {
      'min-width': (saved?.minWidth, 'Largeur minimale'),
      'min-height': (saved?.minHeight, 'Hauteur minimale'),
      'preferred-width': (
        saved?.preferredWidth ??
            ((saved == null || !saved!.hasSizeConstraints) && legacy != null
                ? legacy!.width.isFinite
                      ? SlotDimension(legacy!.width, SlotSizeUnit.pixels)
                      : null
                : null),
        'Largeur préférée',
      ),
      'preferred-height': (
        saved?.preferredHeight ??
            ((saved == null || !saved!.hasSizeConstraints) && legacy != null
                ? legacy!.height.isFinite
                      ? SlotDimension(legacy!.height, SlotSizeUnit.pixels)
                      : null
                : null),
        'Hauteur préférée',
      ),
      'max-width': (saved?.maxWidth, 'Largeur maximale'),
      'max-height': (saved?.maxHeight, 'Hauteur maximale'),
    };
    controllers = {
      for (final entry in fields.entries)
        entry.key: TextEditingController(
          text: entry.value.$1?.value.toString() ?? '',
        ),
    };
    units = {
      for (final entry in fields.entries)
        entry.key: ValueNotifier(entry.value.$1?.unit ?? SlotSizeUnit.pixels),
    };
    _lastPreview = readDimensions();
    for (final controller in controllers.values) {
      controller.addListener(_preview);
    }
    for (final unit in units.values) {
      unit.addListener(_preview);
    }
    padding.addListener(_preview);
    paddingInsets.addListener(_preview);
    percentBasis.addListener(_preview);
    fitContent.addListener(_preview);
  }

  final BuildContext context;
  final SlotImplementation slot;
  final SlotSizeConstraints? saved;
  final Size? legacy;
  final Listenable changes;
  final SlotSizeGeometry? Function() measure;
  final void Function(SlotSizeConstraints dimensions, bool useLegacyPixels)
  _onApply;
  final VoidCallback _onRestore;
  final ValueChanged<String>? _onLabelChanged;
  final ValueNotifier<String> label;
  late final Map<String, (SlotDimension?, String)> fields;
  late final Map<String, TextEditingController> controllers;
  late final Map<String, ValueNotifier<SlotSizeUnit>> units;
  final ValueNotifier<SlotPercentBasis> percentBasis;
  final ValueNotifier<String> sliderGroup;
  final ValueNotifier<double> padding;
  final ValueNotifier<EdgeInsets?> paddingInsets;
  final ValueNotifier<bool?> fitContent;
  final Size layoutSize;
  final GlobalKey<FormState> form = GlobalKey<FormState>();

  late SlotSizeConstraints _lastPreview;
  bool percentBasisChanged = false;
  bool _dirty = false;
  SlotSizeConstraints? _explicitResult;

  @override
  String get title => 'Taille et marge préférées : ${label.value}';

  @override
  ValueListenable<String>? get labelListenable => label;

  @override
  String? get editableLabel => _onLabelChanged == null ? null : label.value;

  @override
  ValueChanged<String>? get onLabelChanged => _onLabelChanged == null
      ? null
      : (value) {
          label.value = value;
          _onLabelChanged(value);
        };

  @override
  void syncLabel(String value) {
    if (label.value != value) label.value = value;
  }

  String? validateField(String? text) {
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
      fitContent: fitContent.value,
    );
  }

  String? boundsError() {
    if (controllers.values.any((c) => validateField(c.text) != null)) {
      return null;
    }
    final geometry = measure();
    final basis = percentBasis.value == SlotPercentBasis.layout
        ? geometry?.layout
        : geometry?.zone.size;
    final dimensions = readDimensions();
    for (final (minimum, maximum, extent, axisLabel) in [
      (dimensions.minWidth, dimensions.maxWidth, basis?.width, 'largeur'),
      (dimensions.minHeight, dimensions.maxHeight, basis?.height, 'hauteur'),
    ]) {
      if (minimum != null &&
          maximum != null &&
          (extent != null || minimum.unit == maximum.unit) &&
          minimum.resolve(extent ?? 100) > maximum.resolve(extent ?? 100)) {
        return 'La $axisLabel minimale dépasse la $axisLabel maximale.';
      }
    }
    return null;
  }

  void applyDimensions(SlotSizeConstraints dimensions) {
    _onApply(dimensions, saved == null && !percentBasisChanged);
  }

  void _preview() {
    if (!context.mounted ||
        controllers.values.any(
          (controller) => validateField(controller.text) != null,
        ) ||
        boundsError() != null) {
      return;
    }
    final dimensions = readDimensions();
    if (dimensions == _lastPreview) return;
    _lastPreview = dimensions;
    _dirty = true;
    _explicitResult = null;
    applyDimensions(dimensions);
  }

  void resetToDefault() {
    _explicitResult = const SlotSizeConstraints();
    _dirty = true;
    for (final controller in controllers.values) {
      controller.removeListener(_preview);
      controller.clear();
      controller.addListener(_preview);
    }
    padding.value = 0.0;
    paddingInsets.value = null;
    fitContent.value = null;
    _lastPreview = const SlotSizeConstraints();
    applyDimensions(const SlotSizeConstraints());
  }

  @override
  bool validate() {
    final formValid = form.currentState?.validate() ?? true;
    final fieldsValid = controllers.values.every(
      (c) => validateField(c.text) == null,
    );
    if (!fieldsValid && form.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        form.currentState?.validate();
      });
    }
    return formValid && fieldsValid && boundsError() == null;
  }

  @override
  void apply({bool force = false}) {
    if (!context.mounted) return;
    if (_explicitResult != null) {
      applyDimensions(_explicitResult!);
    } else if (_dirty || force) {
      applyDimensions(readDimensions());
    }
  }

  @override
  void restore() {
    if (context.mounted) {
      _onRestore();
    }
  }

  @override
  List<Widget> buildExtraActions(
    BuildContext context, {
    required VoidCallback onResetAndClose,
  }) => [
    TextButton(
      onPressed: () {
        resetToDefault();
        onResetAndClose();
      },
      child: const Text('Taille et marge par défaut'),
    ),
  ];

  @override
  Widget buildContent(BuildContext context) => Form(
    key: form,
    child: ListenableBuilder(
      listenable: Listenable.merge([
        ...controllers.values,
        ...units.values,
        padding,
        paddingInsets,
        percentBasis,
        fitContent,
        sliderGroup,
        changes,
      ]),
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(' Occupation sur l’axe principal (flex)'),
          ValueListenableBuilder<bool?>(
            valueListenable: fitContent,
            builder: (context, value, _) => SegmentedButton<bool?>(
              key: const ValueKey('slot-fit-content'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment<bool?>(
                  value: null,
                  tooltip: 'Auto (selon le flux de la zone)',
                  icon: Flexible(
                    flex: 0,
                    child: Icon(Icons.hdr_auto_outlined, size: 14),
                  ),
                  label: Text(
                    'Auto (selon le flux de la zone)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment<bool?>(
                  value: true,
                  tooltip: 'Taille du contenu (flex : 0)',
                  icon: Flexible(
                    flex: 0,
                    child: Icon(Icons.fit_screen_outlined, size: 14),
                  ),
                  label: Text(
                    'Taille du contenu (flex : 0)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment<bool?>(
                  value: false,
                  tooltip: 'Remplir l’espace (flex : 1)',
                  icon: Flexible(
                    flex: 0,
                    child: Icon(Icons.open_in_full, size: 14),
                  ),
                  label: Text(
                    'Remplir l’espace (flex : 1)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {value},
              onSelectionChanged: (selected) =>
                  fitContent.value = selected.first,
            ),
          ),
          const SizedBox(height: 8),
          const Text('Base de calcul des pourcentages'),
          ValueListenableBuilder<SlotPercentBasis>(
            valueListenable: percentBasis,
            builder: (context, value, _) => SegmentedButton<SlotPercentBasis>(
              key: const ValueKey('slot-percent-basis'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: SlotPercentBasis.zone,
                  tooltip: 'Espace disponible de la zone',
                  icon: Icon(Icons.crop_free, size: 16),
                  label: Text(
                    'Espace disponible de la zone',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: SlotPercentBasis.layout,
                  tooltip: 'Toute la place du layout',
                  icon: Icon(Icons.aspect_ratio, size: 16),
                  label: Text(
                    'Toute la place du layout',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {value},
              onSelectionChanged: (selected) {
                if (selected.isNotEmpty) {
                  percentBasisChanged = true;
                  percentBasis.value = selected.first;
                }
              },
            ),
          ),
          _SlotSizePreview(
            measure: measure,
            dimensions:
                controllers.values.any((c) => validateField(c.text) != null)
                ? _lastPreview
                : readDimensions(),
          ),
          if (boundsError() case final error?)
            Text(
              error,
              key: const ValueKey('slot-bounds-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            spacing: 8,
            children: [
              for (final (group, groupLabel) in [
                ('min', 'Min'),
                ('preferred', 'Préférée'),
                ('max', 'Max'),
              ])
                ChoiceChip(
                  key: ValueKey('slot-slider-group-$group'),
                  label: Text(groupLabel),
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
                        tooltip: 'Effacer ${entry.value.$2.toLowerCase()}',
                        onPressed: controllers[entry.key]!.text.isEmpty
                            ? null
                            : controllers[entry.key]!.clear,
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: validateField,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<SlotSizeUnit>(
                  valueListenable: units[entry.key]!,
                  builder: (context, unit, _) => SegmentedButton<SlotSizeUnit>(
                    key: ValueKey('slot-unit-${entry.key}'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: SlotSizeUnit.pixels,
                        tooltip: 'Pixels (px)',
                        icon: Icon(Icons.straighten, size: 14),
                        label: Text('px'),
                      ),
                      ButtonSegment(
                        value: SlotSizeUnit.percent,
                        tooltip: 'Pourcentage (%)',
                        icon: Icon(Icons.percent, size: 14),
                        label: Text('%'),
                      ),
                    ],
                    selected: {unit},
                    onSelectionChanged: (selected) {
                      if (selected.isNotEmpty) {
                        units[entry.key]!.value = selected.first;
                      }
                    },
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
              independentKey: const ValueKey('slot-padding-independent'),
              onChanged: (value, sides) {
                padding.value = value;
                paddingInsets.value = sides;
              },
            ),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.removeListener(_preview);
    }
    for (final unit in units.values) {
      unit.removeListener(_preview);
    }
    percentBasis.removeListener(_preview);
    padding.removeListener(_preview);
    paddingInsets.removeListener(_preview);
    fitContent.removeListener(_preview);
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
      fitContent.dispose();
      sliderGroup.dispose();
      label.dispose();
    });
  }
}

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
  // Si le slot possède un composant enfant avec un éditeur de propriétés,
  // ouvre le wizard unifié à 2 onglets positionné sur « Taille et marge ».
  final childEditor = EditorWizardNavigation.findDirectChildEditorSlot(target);
  final delegate = SlotSizeDimensionDelegate(
    context: context,
    slot: slot,
    saved: saved,
    legacy: legacy,
    changes: changes,
    measure: measure,
    onApply: onApply,
    onRestore: onRestore,
    initialLabel: initialLabel,
    onLabelChanged: onLabelChanged,
  );
  if (childEditor != null && childEditor.mounted) {
    await EditorWizardNavigation.openWithTab(
      EditorWizardTab.dimensions,
      childEditor.openEditor,
      delegate: delegate,
    );
    return;
  }

  final history = EditorHistoryScope.controllerOf(context);
  history?.beginTransaction();
  var transactionCompleted = false;
  try {
    final result = await showEditorDialog<SlotSizeConstraints>(
      context: context,
      target: target ?? context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        titlePadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EditorWizardTabBar(
              selectedTab: EditorWizardTab.dimensions,
              propertiesEnabled: false,
              dimensionsEnabled: true,
              onTabSelected: (_) {},
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<String>(
              valueListenable: delegate.label,
              builder: (context, value, _) => EditorDialogHeader(
                label: 'Taille et marge préférées : $value',
                editableLabel: delegate.editableLabel,
                onLabelChanged: delegate.onLabelChanged,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: delegate.buildContent(dialogContext)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(const SlotSizeConstraints()),
            child: const Text('Taille et marge par défaut'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (!delegate.validate()) {
                return;
              }
              Navigator.of(dialogContext).pop(delegate.readDimensions());
            },
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
    if (result == null && context.mounted) {
      delegate.restore();
      history?.cancelTransaction();
    } else if (result != null && context.mounted) {
      delegate.applyDimensions(result);
      history?.commitTransaction();
    } else {
      history?.commitTransaction();
    }
    transactionCompleted = true;
  } finally {
    if (!transactionCompleted) history?.commitTransaction();
    delegate.dispose();
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
