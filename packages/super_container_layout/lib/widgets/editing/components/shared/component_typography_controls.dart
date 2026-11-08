/// Contrôles de typographie et d'alignement réutilisables entre les éditeurs
/// de composants (`SuperAction`, `SuperValue`, `SuperIndicator`,
/// `SuperSeparator`).
library;

import 'package:material_ui/material_ui.dart';

/// Sélecteur de famille de police avec message d'avertissement lorsque la
/// police configurée n'est pas disponible dans [availableFontFamilies].
class ComponentFontFamilyField extends StatelessWidget {
  /// Crée un [ComponentFontFamilyField].
  const ComponentFontFamilyField({
    required this.settingPrefix,
    required this.fontFamily,
    required this.availableFontFamilies,
    required this.onChanged,
    this.defaultLabel = 'Police du thème',
    super.key,
  });

  final String settingPrefix;
  final String? fontFamily;
  final List<String> availableFontFamilies;
  final ValueChanged<String?> onChanged;
  final String defaultLabel;

  @override
  Widget build(BuildContext context) {
    final fonts = availableFontFamilies.toSet().toList();
    final unavailable = fontFamily != null && !fonts.contains(fontFamily);
    return DropdownButtonFormField<String>(
      isExpanded: true,
      key: ValueKey('$settingPrefix-fontFamily-$fontFamily'),
      initialValue: unavailable ? null : fontFamily,
      hint: Text(defaultLabel),
      items: [
        DropdownMenuItem(value: '', child: Text(defaultLabel)),
        for (final font in fonts)
          DropdownMenuItem(value: font, child: Text(font)),
      ],
      onChanged: onChanged,
      validator: (_) =>
          unavailable ? 'Choisissez une police disponible.' : null,
    );
  }
}

/// Sélecteur de graisse (`FontWeight`) avec option d'héritage du thème/parent.
class ComponentFontWeightField extends StatelessWidget {
  /// Crée un [ComponentFontWeightField].
  const ComponentFontWeightField({
    required this.fontWeight,
    required this.onChanged,
    this.defaultLabel = 'Graisse du thème',
    this.decorationLabel = 'Graisse',
    super.key,
  });

  final FontWeight? fontWeight;
  final ValueChanged<FontWeight?> onChanged;
  final String defaultLabel;
  final String? decorationLabel;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<FontWeight>(
    isExpanded: true,
    initialValue: fontWeight,
    decoration: decorationLabel != null
        ? InputDecoration(labelText: decorationLabel)
        : const InputDecoration(),
    hint: Text(defaultLabel),
    items: [
      DropdownMenuItem<FontWeight>(value: null, child: Text(defaultLabel)),
      for (final weight in FontWeight.values)
        DropdownMenuItem(value: weight, child: Text('${weight.value}')),
    ],
    onChanged: onChanged,
  );
}

/// Sélecteur segmenté à 3 états (`Style du parent`, `Normal`, `Italique`).
class ComponentItalicSegmentField extends StatelessWidget {
  /// Crée un [ComponentItalicSegmentField].
  const ComponentItalicSegmentField({
    required this.settingPrefix,
    required this.italic,
    required this.onChanged,
    super.key,
  });

  final String settingPrefix;
  final bool? italic;
  final void Function({required bool italic, required bool inherit}) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 4,
    children: [
      const Text(
        'Style de police',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      SegmentedButton<String>(
        key: ValueKey('$settingPrefix-italic'),
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: const [
          ButtonSegment(
            value: 'inherit',
            tooltip: 'Style du parent',
            icon: Icon(Icons.hdr_auto_outlined, size: 16),
            label: Text('Style du parent', overflow: TextOverflow.ellipsis),
          ),
          ButtonSegment(
            value: 'normal',
            tooltip: 'Normal',
            icon: Icon(Icons.text_format, size: 16),
            label: Text('Normal', overflow: TextOverflow.ellipsis),
          ),
          ButtonSegment(
            value: 'italic',
            tooltip: 'Italique',
            icon: Icon(Icons.format_italic, size: 16),
            label: Text('Italique', overflow: TextOverflow.ellipsis),
          ),
        ],
        selected: {
          italic == null
              ? 'inherit'
              : italic!
              ? 'italic'
              : 'normal',
        },
        onSelectionChanged: (selected) {
          if (selected.isEmpty) return;
          final value = selected.first;
          onChanged(italic: value == 'italic', inherit: value == 'inherit');
        },
      ),
    ],
  );
}

/// Sélecteur segmenté d'alignement horizontal du texte ([TextAlign]).
class ComponentTextAlignSegmentField extends StatelessWidget {
  /// Crée un [ComponentTextAlignSegmentField].
  const ComponentTextAlignSegmentField({
    required this.settingPrefix,
    required this.textAlign,
    required this.onChanged,
    super.key,
  });

  final String settingPrefix;
  final TextAlign textAlign;
  final ValueChanged<TextAlign> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 4,
    children: [
      const Text(
        'Alignement',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      SegmentedButton<TextAlign>(
        key: ValueKey('$settingPrefix-textAlign'),
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: [
          for (final align in TextAlign.values)
            ButtonSegment<TextAlign>(
              value: align,
              tooltip: align.name,
              icon: Icon(
                switch (align) {
                  TextAlign.left => Icons.format_align_left,
                  TextAlign.right => Icons.format_align_right,
                  TextAlign.center => Icons.format_align_center,
                  TextAlign.justify => Icons.format_align_justify,
                  TextAlign.start => Icons.align_horizontal_left,
                  TextAlign.end => Icons.align_horizontal_right,
                },
                size: 16,
              ),
            ),
        ],
        selected: {textAlign},
        onSelectionChanged: (selected) {
          if (selected.isNotEmpty) {
            onChanged(selected.first);
          }
        },
      ),
    ],
  );
}
