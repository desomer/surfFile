/// Contrôles de typographie et d'alignement réutilisables entre les éditeurs
/// de composants (`SuperAction`, `SuperValue`, `SuperIndicator`,
/// `SuperSeparator`).
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';

import '../../../../services/fonts/dynamic_font_models.dart';
import '../../../appearance/dynamic_font_scope.dart';
import 'editor_color_fields.dart';
import 'editor_segmented_field.dart';

/// Retourne la liste effective des polices disponibles dans un éditeur,
/// en fusionnant [base] avec les polices chargées dynamiquement via [DynamicFontScope].
List<String> resolveEditorAvailableFontFamilies(
  BuildContext context,
  List<String> base, {
  bool listen = true,
}) {
  final manager = listen
      ? DynamicFontScope.maybeOf(context)
      : DynamicFontScope.readOf(context);
  final merged = manager == null
      ? base
      : manager.effectiveAvailableFontFamilies(base);
  return merged.toSet().toList();
}

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
    final fonts = resolveEditorAvailableFontFamilies(
      context,
      availableFontFamilies,
    );
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
  Widget build(BuildContext context) => EditorSegmentedField<String>(
    buttonKey: ValueKey('$settingPrefix-italic'),
    label: 'Style de police',
    value: italic == null
        ? 'inherit'
        : italic!
        ? 'italic'
        : 'normal',
    options: const [
      EditorSegmentOption(
        value: 'inherit',
        label: 'Style du parent',
        icon: Icons.hdr_auto_outlined,
      ),
      EditorSegmentOption(
        value: 'normal',
        label: 'Normal',
        icon: Icons.text_format,
      ),
      EditorSegmentOption(
        value: 'italic',
        label: 'Italique',
        icon: Icons.format_italic,
      ),
    ],
    onChanged: (value) =>
        onChanged(italic: value == 'italic', inherit: value == 'inherit'),
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
  Widget build(BuildContext context) => EditorSegmentedField<TextAlign>(
    buttonKey: ValueKey('$settingPrefix-textAlign'),
    label: 'Alignement',
    value: textAlign,
    options: [
      for (final align in TextAlign.values)
        EditorSegmentOption<TextAlign>(
          value: align,
          tooltip: align.name,
          icon: switch (align) {
            TextAlign.left => Icons.format_align_left,
            TextAlign.right => Icons.format_align_right,
            TextAlign.center => Icons.format_align_center,
            TextAlign.justify => Icons.format_align_justify,
            TextAlign.start => Icons.align_horizontal_left,
            TextAlign.end => Icons.align_horizontal_right,
          },
        ),
    ],
    onChanged: onChanged,
  );
}

/// Construit la liste complète des contrôles de typographie (alerte de police
/// indisponible, famille de police, taille de police, contrôles d'icône
/// optionnels, graisse, italique, alignement optionnel et espacement des lettres).
List<Widget> buildComponentTypographyFields<TProperty extends Enum>({
  required BuildContext context,
  required String settingPrefix,
  required EditablePropertyBindingScope<TProperty> bindingScope,
  required List<String> availableFontFamilies,
  required String? fontFamily,
  required ValueChanged<String?> onFontFamilyChanged,
  required TProperty fontFamilyProperty,
  required Widget fontSizeField,
  required TProperty fontSizeProperty,
  required FontWeight? fontWeight,
  required ValueChanged<FontWeight?> onFontWeightChanged,
  required TProperty fontWeightProperty,
  required bool? italic,
  required void Function({required bool italic, required bool inherit})
  onItalicChanged,
  required TProperty italicProperty,
  List<Widget> afterFontSize = const [],
  TextAlign? textAlign,
  ValueChanged<TextAlign>? onTextAlignChanged,
  TProperty? textAlignProperty,
  List<Widget> beforeLetterSpacing = const [],
  Widget? letterSpacingField,
}) {
  final fontManager = DynamicFontScope.maybeOf(context);
  final effectiveAvailable = fontManager == null
      ? availableFontFamilies
      : fontManager.effectiveAvailableFontFamilies(availableFontFamilies);
  final fonts = effectiveAvailable.toSet().toList();
  final unavailable = fontFamily != null && !fonts.contains(fontFamily);
  final scheme = Theme.of(context).colorScheme;
  final fontStatus = fontFamily != null && fontManager != null
      ? fontManager.statusOf(fontFamily)
      : null;
  final isDownloading = fontStatus == DynamicFontStatus.loading;
  final isRetry =
      fontFamily != null &&
      fontManager != null &&
      fontManager.hasAttempted(fontFamily) &&
      (fontStatus == DynamicFontStatus.failed ||
          fontStatus == DynamicFontStatus.notFound);
  return [
    if (unavailable)
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              isDownloading
                  ? 'Téléchargement de la police « $fontFamily »...'
                  : 'Police indisponible : $fontFamily. Choisissez une police disponible.',
              style: TextStyle(
                color: isDownloading ? scheme.primary : scheme.error,
              ),
            ),
          ),
          if (fontManager != null) ...[
            const SizedBox(width: 8),
            if (isDownloading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              OutlinedButton.icon(
                key: ValueKey('$settingPrefix-download-font'),
                onPressed: () {
                  unawaited(
                    fontManager.ensureFontLoaded(fontFamily, forceRetry: true),
                  );
                },
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: Icon(
                  isRetry ? Icons.refresh : Icons.download_outlined,
                  size: 16,
                ),
                label: Text(isRetry ? 'Réessayer' : 'Télécharger'),
              ),
          ],
        ],
      ),
    bindingScope.wrap(
      fontFamilyProperty,
      'la police',
      ComponentFontFamilyField(
        settingPrefix: settingPrefix,
        fontFamily: fontFamily,
        availableFontFamilies: fonts,
        onChanged: onFontFamilyChanged,
      ),
    ),
    bindingScope.wrap(fontSizeProperty, 'la taille de police', fontSizeField),
    ...afterFontSize,
    bindingScope.wrap(
      fontWeightProperty,
      'la graisse',
      ComponentFontWeightField(
        fontWeight: fontWeight,
        onChanged: onFontWeightChanged,
      ),
    ),
    bindingScope.wrap(
      italicProperty,
      'le style italique',
      ComponentItalicSegmentField(
        settingPrefix: settingPrefix,
        italic: italic,
        onChanged: onItalicChanged,
      ),
    ),
    if (textAlign != null &&
        onTextAlignChanged != null &&
        textAlignProperty != null)
      bindingScope.wrap(
        textAlignProperty,
        'l’alignement',
        ComponentTextAlignSegmentField(
          settingPrefix: settingPrefix,
          textAlign: textAlign,
          onChanged: onTextAlignChanged,
        ),
      ),
    ...beforeLetterSpacing,
    ?letterSpacingField,
  ];
}
