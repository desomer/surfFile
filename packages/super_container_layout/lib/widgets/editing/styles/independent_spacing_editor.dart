import 'package:material_ui/material_ui.dart';

import 'style_editor_panel.dart';

class IndependentSpacingEditor extends StatelessWidget {
  const IndependentSpacingEditor({
    required this.label,
    required this.value,
    required this.sides,
    required this.max,
    required this.onChanged,
    this.unit = ' px',
    this.keyPrefix = 'spacing',
    this.sliderKey,
    this.independentKey,
    this.sideKeyPrefix,
    this.sideKeySuffix = '',
    super.key,
  });

  final String label;
  final double value;
  final EdgeInsets? sides;
  final double max;
  final String unit;
  final String keyPrefix;
  final Key? sliderKey;
  final Key? independentKey;
  final String? sideKeyPrefix;
  final String sideKeySuffix;
  final void Function(double value, EdgeInsets? sides) onChanged;

  static const _sideLabels = ['Haut', 'Droite', 'Bas', 'Gauche'];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (sides == null)
        StyleSliderField(
          label: label,
          value: value,
          min: 0,
          max: max,
          unit: unit,
          sliderKey: sliderKey ?? ValueKey('$keyPrefix-slider'),
          onChanged: (next) => onChanged(next, null),
        ),
      StyleSwitchField(
        key: independentKey ?? ValueKey('$keyPrefix-independent'),
        title: 'Côtés indépendants',
        value: sides != null,
        onChanged: (independent) =>
            onChanged(value, independent ? EdgeInsets.all(value) : null),
      ),
      if (sides != null) ...[
        StylePair(_sideSlider(0, sides!.top), _sideSlider(1, sides!.right)),
        StylePair(_sideSlider(2, sides!.bottom), _sideSlider(3, sides!.left)),
      ],
    ],
  );

  Widget _sideSlider(int index, double sideValue) => StyleSliderField(
    label: _sideLabels[index],
    value: sideValue,
    min: 0,
    max: max,
    unit: unit,
    sliderKey: ValueKey(
      '${sideKeyPrefix ?? keyPrefix}-side-$index$sideKeySuffix',
    ),
    onChanged: (next) {
      final current = sides!;
      final nextSides = switch (index) {
        0 => EdgeInsets.fromLTRB(
          current.left,
          next,
          current.right,
          current.bottom,
        ),
        1 => EdgeInsets.fromLTRB(
          current.left,
          current.top,
          next,
          current.bottom,
        ),
        2 => EdgeInsets.fromLTRB(
          current.left,
          current.top,
          current.right,
          next,
        ),
        _ => EdgeInsets.fromLTRB(
          next,
          current.top,
          current.right,
          current.bottom,
        ),
      };
      onChanged(value, nextSides);
    },
  );
}
