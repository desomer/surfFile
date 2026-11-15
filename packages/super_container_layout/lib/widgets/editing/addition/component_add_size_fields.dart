/// Brouillon et champs de taille utilisés pendant le placement d’un composant.
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart';

/// Brouillon éditable des dimensions optionnelles d’un nouveau slot.
class ComponentAddSizeDraft {
  /// Crée les contrôleurs avec les unités et la base de pourcentage par défaut.
  ComponentAddSizeDraft();

  /// Dimensions et libellés présentés par le formulaire.
  static const fields = [
    ('preferredWidth', 'Largeur préférée'),
    ('preferredHeight', 'Hauteur préférée'),
    ('minWidth', 'Largeur min'),
    ('minHeight', 'Hauteur min'),
    ('maxWidth', 'Largeur max'),
    ('maxHeight', 'Hauteur max'),
  ];

  /// Contrôleurs de saisie, détenus et libérés par le wizard.
  final controllers = {
    for (final (key, _) in fields) key: TextEditingController(),
  };

  /// Unité choisie pour chaque dimension.
  final units = {for (final (key, _) in fields) key: SlotSizeUnit.pixels};

  /// Référence des valeurs en pourcentage.
  SlotPercentBasis basis = SlotPercentBasis.zone;

  /// Libère les contrôleurs possédés par ce brouillon.
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  /// Parse une dimension, ou lève [FormatException] si sa valeur est invalide.
  SlotDimension? dimension(String key) {
    final text = controllers[key]!.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value < 0) {
      throw const FormatException('Nombre positif attendu.');
    }
    if (units[key] == SlotSizeUnit.percent && value > 100) {
      throw const FormatException('Pourcentage entre 0 et 100 attendu.');
    }
    return SlotDimension(value, units[key]!);
  }

  /// Message d’erreur de saisie, ou `null` si les contraintes sont cohérentes.
  String? get error {
    try {
      final value = this.value;
      for (final (min, max, name) in [
        (value.minWidth, value.maxWidth, 'largeur'),
        (value.minHeight, value.maxHeight, 'hauteur'),
      ]) {
        if (min != null &&
            max != null &&
            min.unit == max.unit &&
            min.value > max.value) {
          return 'La $name minimale dépasse la maximale.';
        }
      }
      return null;
    } on FormatException catch (error) {
      return 'Taille invalide : ${error.message}';
    }
  }

  /// Contraintes de slot encodées par les valeurs actuelles.
  SlotSizeConstraints get value => SlotSizeConstraints(
    preferredWidth: dimension('preferredWidth'),
    preferredHeight: dimension('preferredHeight'),
    minWidth: dimension('minWidth'),
    minHeight: dimension('minHeight'),
    maxWidth: dimension('maxWidth'),
    maxHeight: dimension('maxHeight'),
    percentBasis: basis,
  );

  /// Résumé lisible des dimensions renseignées.
  String describe() {
    final parts = [
      for (final (key, label) in fields)
        if (controllers[key]!.text.trim().isNotEmpty)
          '$label ${controllers[key]!.text.trim()}'
              '${units[key] == SlotSizeUnit.percent ? ' %' : ' px'}',
    ];
    if (parts.isEmpty) return 'Aucune contrainte';
    final percent = units.values.contains(SlotSizeUnit.percent);
    return [
      ...parts,
      if (percent)
        basis == SlotPercentBasis.zone ? '% de la zone' : '% du layout',
    ].join(', ');
  }
}

/// Formulaire des dimensions optionnelles de la zone de placement.
class ComponentAddSizeFields extends StatelessWidget {
  /// Crée le formulaire sans prendre possession du brouillon ou contrôleurs.
  const ComponentAddSizeFields({
    required this.keyPrefix,
    required this.draft,
    required this.onChanged,
    super.key,
  });

  /// Préfixe des clés de compatibilité des champs.
  final String keyPrefix;

  /// Brouillon édité par le wizard.
  final ComponentAddSizeDraft draft;

  /// Notifie le wizard qu’une valeur a changé.
  final VoidCallback onChanged;

  Widget _field(String key, String label) => Row(
    children: [
      Expanded(
        child: TextField(
          key: ValueKey('$keyPrefix-add-size-$key'),
          controller: draft.controllers[key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(isDense: true, labelText: label),
          onChanged: (_) => onChanged(),
        ),
      ),
      const SizedBox(width: 6),
      SegmentedButton<SlotSizeUnit>(
        key: ValueKey('$keyPrefix-add-size-unit-$key'),
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
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
        selected: {draft.units[key]!},
        onSelectionChanged: (selected) {
          if (selected.isEmpty) return;
          draft.units[key] = selected.first;
          onChanged();
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < ComponentAddSizeDraft.fields.length; i += 2)
        Row(
          children: [
            Expanded(
              child: _field(
                ComponentAddSizeDraft.fields[i].$1,
                ComponentAddSizeDraft.fields[i].$2,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(
                ComponentAddSizeDraft.fields[i + 1].$1,
                ComponentAddSizeDraft.fields[i + 1].$2,
              ),
            ),
          ],
        ),
      if (draft.units.values.contains(SlotSizeUnit.percent))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SegmentedButton<SlotPercentBasis>(
            key: ValueKey('$keyPrefix-add-size-basis'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: SlotPercentBasis.zone,
                tooltip: '% de la zone',
                icon: Icon(Icons.crop_free, size: 16),
                label: Text('% de la zone'),
              ),
              ButtonSegment(
                value: SlotPercentBasis.layout,
                tooltip: '% du layout',
                icon: Icon(Icons.aspect_ratio, size: 16),
                label: Text('% du layout'),
              ),
            ],
            selected: {draft.basis},
            onSelectionChanged: (value) {
              draft.basis = value.single;
              onChanged();
            },
          ),
        ),
    ],
  );
}
