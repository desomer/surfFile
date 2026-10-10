part of '../super_layout.dart';

extension _SuperLayoutSlotSizeEditor on SuperLayoutState {
  Future<void> _editSlotPreferredSize(SlotImplementation slot) async {
    final config = _config.value;
    final saved = config.slotSizeConstraints[slot.id];
    final legacy = config.slotPreferredSizes.containsKey(slot.id)
        ? config.slotPreferredSizes[slot.id]
        : slot.preferredSize;
    final fields = {
      'min-width': (saved?.minWidth, 'Largeur minimale'),
      'min-height': (saved?.minHeight, 'Hauteur minimale'),
      'preferred-width': (
        saved?.preferredWidth ??
            (saved == null && legacy != null
                ? SlotDimension(legacy.width, SlotSizeUnit.pixels)
                : null),
        'Largeur préférée',
      ),
      'preferred-height': (
        saved?.preferredHeight ??
            (saved == null && legacy != null
                ? SlotDimension(legacy.height, SlotSizeUnit.pixels)
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
      saved?.percentBasis ?? SlotPercentBasis.zone,
    );
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
        percentBasis: percentBasis.value,
      );
    }

    var lastPreview = readDimensions();
    void preview() {
      if (!mounted ||
          controllers.values.any(
            (controller) => validate(controller.text) != null,
          )) {
        return;
      }
      final dimensions = readDimensions();
      if (dimensions == lastPreview) return;
      lastPreview = dimensions;
      _applySlotDimensions(slot, dimensions);
    }

    for (final controller in controllers.values) {
      controller.addListener(preview);
    }
    for (final unit in units.values) {
      unit.addListener(preview);
    }
    percentBasis.addListener(preview);
    final layoutSize = this.context.size ?? Size.zero;

    try {
      final result = await showDialog<SlotSizeConstraints>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (context) => AlertDialog(
          title: Text('Tailles du slot : ${slot.label}'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    ...controllers.values,
                    ...units.values,
                    percentBasis,
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
                              value: value,
                              onChanged: (basis) {
                                if (basis != null) percentBasis.value = basis;
                              },
                              items: const [
                                DropdownMenuItem(
                                  value: SlotPercentBasis.zone,
                                  child: Text('Espace disponible de la zone'),
                                ),
                                DropdownMenuItem(
                                  value: SlotPercentBasis.layout,
                                  child: Text('Tout le SuperLayout'),
                                ),
                              ],
                            ),
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
                        Builder(
                          builder: (context) {
                            final key = entry.key;
                            final value = double.tryParse(
                              controllers[key]!.text.trim().replaceAll(
                                ',',
                                '.',
                              ),
                            );
                            final percent =
                                units[key]!.value == SlotSizeUnit.percent;
                            final extent = key.endsWith('width')
                                ? layoutSize.width
                                : layoutSize.height;
                            final baseMax = percent
                                ? 100.0
                                : (extent > 1000 ? extent : 1000.0);
                            final max =
                                value != null &&
                                    value.isFinite &&
                                    value > baseMax
                                ? value
                                : baseMax;
                            return Slider(
                              key: ValueKey('slot-slider-$key'),
                              value: value != null && value.isFinite
                                  ? value.clamp(0, max)
                                  : 0,
                              max: max,
                              label: '${value ?? 0} ${percent ? '%' : 'px'}',
                              onChanged: (value) {
                                controllers[key]!.text = value
                                    .round()
                                    .toString();
                              },
                            );
                          },
                        ),
                      ],
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
              child: const Text('Taille automatique'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.of(context).pop(readDimensions());
              },
              child: const Text('Appliquer'),
            ),
          ],
        ),
      );
      if (mounted) {
        if (result != null) {
          _applySlotDimensions(slot, result);
        } else {
          final current = _config.value;
          _update(
            current.copyWith(
              slotPreferredSizes: {...current.slotPreferredSizes}
                ..remove(slot.id)
                ..addAll({
                  if (config.slotPreferredSizes.containsKey(slot.id))
                    slot.id: config.slotPreferredSizes[slot.id],
                }),
              slotSizeConstraints: {...current.slotSizeConstraints}
                ..remove(slot.id)
                ..addAll({if (saved != null) slot.id: saved}),
            ),
          );
        }
      }
    } finally {
      for (final controller in controllers.values) {
        controller.removeListener(preview);
      }
      for (final unit in units.values) {
        unit.removeListener(preview);
      }
      percentBasis.removeListener(preview);
      // Le dialogue peut encore terminer son animation de fermeture.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final controller in controllers.values) {
          controller.dispose();
        }
        for (final unit in units.values) {
          unit.dispose();
        }
        percentBasis.dispose();
      });
    }
  }

  void _applySlotDimensions(
    SlotImplementation slot,
    SlotSizeConstraints result,
  ) {
    final current = _config.value;
    if (result.minWidth == null &&
        result.minHeight == null &&
        result.maxWidth == null &&
        result.maxHeight == null &&
        result.preferredWidth == null &&
        result.preferredHeight == null) {
      _update(
        current
            .withSlotPreferredSize(slot.id, null)
            .copyWith(
              slotSizeConstraints: {...current.slotSizeConstraints}
                ..remove(slot.id),
            ),
      );
    } else if (result.minWidth == null &&
        result.minHeight == null &&
        result.maxWidth == null &&
        result.maxHeight == null &&
        result.preferredWidth?.unit == SlotSizeUnit.pixels &&
        result.preferredHeight?.unit == SlotSizeUnit.pixels &&
        result.percentBasis == SlotPercentBasis.zone &&
        result.preferredWidth!.value > 0 &&
        result.preferredHeight!.value > 0) {
      _update(
        current
            .withSlotPreferredSize(
              slot.id,
              Size(result.preferredWidth!.value, result.preferredHeight!.value),
            )
            .copyWith(
              slotSizeConstraints: {...current.slotSizeConstraints}
                ..remove(slot.id),
            ),
      );
    } else {
      _update(
        current
            .copyWith(
              slotPreferredSizes: {...current.slotPreferredSizes}
                ..remove(slot.id),
            )
            .copyWith(
              slotSizeConstraints: {
                ...current.slotSizeConstraints,
                slot.id: result,
              },
            ),
      );
    }
  }
}
