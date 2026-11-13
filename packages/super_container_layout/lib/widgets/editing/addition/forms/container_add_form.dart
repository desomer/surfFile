/// Formulaire de configuration initiale ([ContainerAddForm]) lors de l'ajout d'une `Card` ou d'un [IterableContent].
library;

import 'package:material_ui/material_ui.dart';

import '../../../../theme/container_style.dart';
import '../../styles/container_style_editor.dart' show styleColorTile;
import '../../history/editor_history.dart';

/// Formulaire de paramétrage initial d'une `Card` ou d'un [IterableContent] dans l'assistant d'ajout.
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
        child: EditorHistorySlider(
          sliderKey: ValueKey('add-container-$key'),
          value: value,
          allowAboveMax: true,
          max: max,
          divisions: max.round(),
          label: value.toStringAsFixed(2),
          onChanged: onChanged,
        ),
      ),
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
        onClear: () => onChanged(draft.copyWith(resetColor: true)),
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
