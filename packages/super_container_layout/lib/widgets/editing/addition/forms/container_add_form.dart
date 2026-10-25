import 'package:material_ui/material_ui.dart';

import '../../../../theme/container_style.dart';
import '../../styles/container_style_editor.dart' show styleColorTile;

class ContainerAddForm extends StatelessWidget {
  const ContainerAddForm({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final ContainerStyle draft;
  final ValueChanged<ContainerStyle> onChanged;

  Widget _slider(
    String key,
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
  ) => Row(
    children: [
      SizedBox(width: 130, child: Text(label)),
      Expanded(
        child: Slider(
          key: ValueKey('add-container-$key'),
          value: value.clamp(0, max).toDouble(),
          max: max,
          divisions: max.round(),
          label: value.toStringAsFixed(0),
          onChanged: onChanged,
        ),
      ),
      SizedBox(width: 32, child: Text(value.toStringAsFixed(0))),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      styleColorTile(
        'Couleur de fond',
        draft.color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        (color) => onChanged(draft.copyWith(color: color)),
        key: const ValueKey('add-container-color'),
        dense: true,
      ),
      _slider(
        'radius',
        'Rayon',
        draft.radius,
        48,
        (value) => onChanged(draft.copyWith(radius: value)),
      ),
      _slider(
        'border',
        'Bordure',
        draft.borderWidth,
        8,
        (value) => onChanged(draft.copyWith(borderWidth: value)),
      ),
      _slider(
        'padding',
        'Marge intérieure',
        draft.padding,
        ContainerStyle.maxSpacing,
        (value) => onChanged(draft.copyWith(padding: value)),
      ),
      _slider(
        'margin',
        'Marge extérieure',
        draft.margin,
        ContainerStyle.maxSpacing,
        (value) => onChanged(draft.copyWith(margin: value)),
      ),
      _slider(
        'elevation',
        'Élévation',
        draft.elevation,
        24,
        (value) => onChanged(draft.copyWith(elevation: value)),
      ),
    ],
  );
}
