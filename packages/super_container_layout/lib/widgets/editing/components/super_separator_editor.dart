/// Fenêtre d'édition complète d'un composant [SuperSeparator].
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/automatic_state.dart';
import '../../../models/super_separator_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../components/super_separator.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../styles/style_editor_panel.dart';
import 'shared/component_state_editor_host.dart';
import 'shared/component_typography_controls.dart';
import 'shared/editor_color_fields.dart';
import 'shared/editor_segmented_field.dart';

final _separatorStateAdapter =
    ComponentStateAdapter<
      SuperSeparatorConfig,
      SeparatorConfigStates,
      SeparatorConfigOverride,
      SeparatorStateProperty
    >(
      stateKeyPrefix: 'super-separator-state',
      emptyStates: SeparatorConfigStates.new,
      getStates: (root) => root.states,
      withStates: (root, states) =>
          root.copyWith(states: states, clearStates: states == null),
      clearStates: (config) => config.copyWith(clearStates: true),
      getNamed: (s) => s.named,
      getNamedProperties: (s) => s.namedProperties,
      getHover: (s) => s.hover,
      getSelected: (s) => s.selected,
      getAutomatic: (s) => s.automatic,
      getOrder: (s) => s.order,
      getBinding: (s) => s.binding,
      copyStates: (
        s, {
        named,
        namedProperties,
        hover,
        clearHover = false,
        selected,
        clearSelected = false,
        automatic,
        order,
        binding,
        clearBinding = false,
      }) => s.copyWith(
        named: named,
        namedProperties: namedProperties,
        hover: hover,
        clearHover: clearHover,
        selected: selected,
        clearSelected: clearSelected,
        automatic: automatic,
        order: order,
        binding: binding,
        clearBinding: clearBinding,
      ),
      createOverride: (config, [properties]) => SeparatorConfigOverride(
        config: config,
        properties: properties ?? const {},
      ),
      getOverrideConfig: (override) => override.config,
      getOverrideProperties: (override) => override.properties,
      editOverride: (previous, nextLeaf) => previous.edited(nextLeaf),
      resolvePreview: (
        states,
        root, {
        name,
        required isHovered,
        required isSelected,
        required activeStates,
      }) => states.resolve(
        root,
        name: name,
        isHovered: isHovered,
        isSelected: isSelected,
        activeStates: activeStates,
      ),
      validateName: (name) {
        try {
          SeparatorConfigStates(named: {name: const SuperSeparatorConfig()});
          return null;
        } on FormatException catch (e) {
          return e.message;
        }
      },
      propertyLabels: {
        for (final property in SeparatorStateProperty.values)
          property: property.label,
      },
      validateRoot: (root, _) => root.validate(),
      allowSelectedWhenAlreadyConfigured: true,
      availableStatesBuilder: ({
        required leaf,
        required states,
        required allowSelected,
        required allowContentHover,
      }) => {
        AutomaticState.hover,
        if (allowSelected) AutomaticState.selected,
        if (allowContentHover ||
            states.automatic.containsKey(AutomaticState.contentHover))
          AutomaticState.contentHover,
      },
    );

/// Ouvre la boîte de dialogue d'édition d'un [SuperSeparatorConfig] avec gestion
/// complète des états standards (`hover`, `selected`, `contentHover`),
/// des états métier personnalisés (`named`) et des liaisons JSON.
Future<SuperSeparatorConfig?> showSuperSeparatorEditor({
  required BuildContext context,
  required SuperSeparatorConfig config,
  required List<String> availableFontFamilies,
  bool allowBinding = true,
  ValueChanged<SuperSeparatorConfig>? onPreviewChanged,
  String? activeState,
  String? stateError,
  bool isHovered = false,
  bool isSelected = false,
  bool allowContentHover = false,
  Set<AutomaticState> activeAutomatic = const {},
}) => showStatefulComponentEditorDialog(
  context: context,
  config: config,
  adapter: _separatorStateAdapter,
  allowBinding: allowBinding,
  onPreviewChanged: onPreviewChanged,
  activeState: activeState,
  stateError: stateError,
  isHovered: isHovered,
  isSelected: isSelected,
  allowContentHover: allowContentHover,
  activeAutomatic: activeAutomatic,
  leafBuilder: ({
    required key,
    required initialTab,
    required dimensionDelegate,
    required config,
    required onWidthChanged,
    required repositories,
    required listScope,
    required textStyle,
    required onPreviewChanged,
    required onSave,
    required header,
  }) => _SuperSeparatorEditor(
    key: key,
    initialTab: initialTab,
    dimensionDelegate: dimensionDelegate,
    config: config,
    availableFontFamilies: availableFontFamilies,
    textStyle: textStyle,
    onWidthChanged: onWidthChanged,
    repositories: repositories,
    listScope: listScope,
    allowBinding: allowBinding,
    onPreviewChanged: onPreviewChanged,
    onSave: onSave,
    header: header,
  ),
);

class _SuperSeparatorEditor extends StatefulWidget {
  const _SuperSeparatorEditor({
    required this.initialTab,
    required this.dimensionDelegate,
    required this.config,
    required this.availableFontFamilies,
    required this.textStyle,
    required this.onWidthChanged,
    required this.repositories,
    required this.listScope,
    required this.allowBinding,
    required this.onPreviewChanged,
    this.header,
    this.onSave,
    super.key,
  });

  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;
  final SuperSeparatorConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding;
  final ValueChanged<SuperSeparatorConfig>? onPreviewChanged;
  final Widget? header;
  final SuperSeparatorConfig Function(SuperSeparatorConfig config)? onSave;

  @override
  State<_SuperSeparatorEditor> createState() => _SuperSeparatorEditorState();
}

class _SuperSeparatorEditorState extends State<_SuperSeparatorEditor>
    with ComponentLeafFormMixin<_SuperSeparatorEditor, SuperSeparatorConfig> {
  late SuperSeparatorConfig _draft;

  @override
  String get settingKeyPrefix => 'super-separator-setting';

  @override
  String get invalidConfigMessage => 'Réglages du séparateur invalides.';

  @override
  ValueChanged<SuperSeparatorConfig>? get onPreviewChangedCallback =>
      widget.onPreviewChanged;

  @override
  SuperSeparatorConfig Function(SuperSeparatorConfig leaf)?
  get onSaveCallback => widget.onSave;

  @override
  void initState() {
    super.initState();
    _draft = widget.config;
    fields = {
      'label': TextEditingController(text: _draft.label),
      'extent': TextEditingController(text: _draft.extent.toString()),
      'thickness': TextEditingController(text: _draft.thickness.toString()),
      'indent': TextEditingController(text: _draft.indent.toString()),
      'endIndent': TextEditingController(text: _draft.endIndent.toString()),
      'labelSpacing': TextEditingController(
        text: _draft.labelSpacing.toString(),
      ),
      'fontSize': TextEditingController(
        text: _draft.fontSize?.toString() ?? '',
      ),
      'letterSpacing': TextEditingController(
        text: _draft.letterSpacing?.toString() ?? '',
      ),
      'lineColor': TextEditingController(
        text: formatEditorColorHex(_draft.lineColor),
      ),
      'color': TextEditingController(text: formatEditorColorHex(_draft.color)),
    };
  }

  @override
  SuperSeparatorConfig buildConfiguration() {
    if (_draft.fontFamily != null &&
        !widget.availableFontFamilies.contains(_draft.fontFamily)) {
      throw const FormatException('Choisissez une police disponible.');
    }

    final extent = numberField('extent', allowZero: true) ?? 16;
    final thickness = numberField('thickness') ?? 1;
    final indent = numberField('indent', allowZero: true) ?? 0;
    final endIndent = numberField('endIndent', allowZero: true) ?? 0;
    final labelSpacing = numberField('labelSpacing', allowZero: true) ?? 8;
    final fontSize = numberField('fontSize');
    final letterSpacing = numberField(
      'letterSpacing',
      allowZero: true,
      allowNegative: true,
    );
    final lineColor = colorField('lineColor');
    final color = colorField('color');

    return _draft.copyWith(
      label: fields['label']!.text,
      extent: extent,
      thickness: thickness,
      indent: indent,
      endIndent: endIndent,
      labelSpacing: labelSpacing,
      fontSize: fontSize,
      inheritFontSize: fontSize == null,
      letterSpacing: letterSpacing,
      inheritLetterSpacing: letterSpacing == null,
      lineColor: lineColor,
      inheritLineColor: lineColor == null,
      color: color,
      inheritColor: color == null,
    )..validate();
  }

  EditablePropertyBindingScope<SuperSeparatorProperty> get _bindingScope =>
      EditablePropertyBindingScope<SuperSeparatorProperty>(
        context: context,
        componentPrefix: 'super-separator',
        allowBinding: widget.allowBinding,
        repositories: widget.repositories,
        listScope: widget.listScope,
        bindings: _draft.propertyBindings,
        onBindingsChanged: (bindings) =>
            setState(() => _draft = _draft.copyWith(propertyBindings: bindings)),
      );

  Widget _withBinding(
    SuperSeparatorProperty property,
    String label,
    Widget child,
  ) => _bindingScope.wrap(property, label, child);

  Widget _colorSetting({
    required String fieldKey,
    required String label,
    required Color fallbackColor,
    required SuperSeparatorProperty property,
  }) => BoundHexColorField(
    controller: fields[fieldKey]!,
    label: label,
    fallbackColor: fallbackColor,
    pickerKey: ValueKey('super-separator-color-picker-$fieldKey'),
    fieldKey: ValueKey('super-separator-setting-$fieldKey'),
    inheritButtonKey: ValueKey('super-separator-inherit-$fieldKey'),
    onChanged: () => setState(() {}),
    wrapField: (field) => _withBinding(property, label.toLowerCase(), field),
  );

  Widget _preview(bool unavailable) {
    SuperSeparatorConfig previewConfig;
    try {
      previewConfig = buildConfiguration();
    } on Object {
      previewConfig = _draft.copyWith(label: fields['label']!.text);
    }
    final style = widget.textStyle.copyWith(
      fontFamily: unavailable ? null : previewConfig.fontFamily,
      fontSize: previewConfig.fontSize,
      fontWeight: previewConfig.fontWeight,
      fontStyle: previewConfig.italic == null
          ? null
          : previewConfig.italic!
          ? FontStyle.italic
          : FontStyle.normal,
      color: previewConfig.color,
      letterSpacing: previewConfig.letterSpacing,
    );
    final scheme = Theme.of(context).colorScheme;
    final isHorizontal = previewConfig.axis == Axis.horizontal;
    return Card(
      key: const ValueKey('super-separator-preview'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Aperçu', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              height: isHorizontal ? 100 : 120,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Center(
                child: SizedBox(
                  width: isHorizontal ? double.infinity : null,
                  height: isHorizontal ? null : double.infinity,
                  child: buildSuperSeparatorVisual(
                    context: context,
                    config: previewConfig,
                    textStyle: style,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    schedulePreview();
    final fonts = widget.availableFontFamilies.toSet().toList();
    final unavailable =
        _draft.fontFamily != null && !fonts.contains(_draft.fontFamily);
    final scheme = Theme.of(context).colorScheme;
    final delegate = widget.dimensionDelegate;

    return EditorStyleWizardDialog(
      dialogKey: const ValueKey('super-separator-settings'),
      initialTab: widget.initialTab,
      dimensionDelegate: delegate,
      onWidthChanged: widget.onWidthChanged,
      liveError: liveError,
      liveErrorKey: const ValueKey('super-separator-live-error'),
      onApply: handleApply,
      propertiesBuilder: (context, dense, onDenseChanged) => Form(
        key: formKey,
        onChanged: () => setState(() {}),
        child: StyleEditorPanel(
          label: delegate?.editableLabel ?? 'Configurer le séparateur',
          onLabelChanged: delegate?.onLabelChanged,
          dense: dense,
          onDenseChanged: onDenseChanged,
          preview: _preview(unavailable),
          sections: [
            if (widget.header != null)
              StyleEditorSection(
                id: 'separator-states',
                title: 'États',
                icon: Icons.layers_outlined,
                child: widget.header!,
              ),
            StyleEditorSection(
              id: 'separator-content',
              title: 'Type, orientation et dimensions',
              icon: Icons.horizontal_rule,
              tag: 'kind · axis · extent · indent',
              child: buildEditorFieldGroup([
                EditorSegmentedField.separatorKind(
                  buttonKey: const ValueKey('super-separator-setting-kind'),
                  value: _draft.kind,
                  onChanged: (kind) =>
                      setState(() => _draft = _draft.copyWith(kind: kind)),
                ),
                EditorSegmentedField.axis(
                  buttonKey: const ValueKey('super-separator-setting-axis'),
                  value: _draft.axis,
                  onChanged: (axis) =>
                      setState(() => _draft = _draft.copyWith(axis: axis)),
                ),
                _withBinding(
                  SuperSeparatorProperty.extent,
                  'la taille / l’espace',
                  buildSettingField(
                    'extent',
                    _draft.axis == Axis.horizontal
                        ? 'Hauteur / espace total (px)'
                        : 'Largeur / espace total (px)',
                    numeric: true,
                    allowZero: true,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _withBinding(
                        SuperSeparatorProperty.indent,
                        'le retrait de début',
                        buildSettingField(
                          'indent',
                          'Retrait début (indent px)',
                          numeric: true,
                          allowZero: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _withBinding(
                        SuperSeparatorProperty.endIndent,
                        'le retrait de fin',
                        buildSettingField(
                          'endIndent',
                          'Retrait fin (endIndent px)',
                          numeric: true,
                          allowZero: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ]),
            ),
            if (_draft.kind.isDivider)
              StyleEditorSection(
                id: 'separator-line',
                title: 'Style et couleur du trait',
                icon: Icons.line_style,
                tag: 'lineStyle · thickness · lineColor',
                child: buildEditorFieldGroup([
                  EditorSegmentedField<SuperSeparatorLineStyle>(
                    buttonKey: const ValueKey(
                      'super-separator-setting-lineStyle',
                    ),
                    label: 'Style du trait',
                    value: _draft.lineStyle,
                    options: const [
                      EditorSegmentOption(
                        value: SuperSeparatorLineStyle.solid,
                        label: 'Continu',
                        icon: Icons.horizontal_rule,
                      ),
                      EditorSegmentOption(
                        value: SuperSeparatorLineStyle.dashed,
                        label: 'Tireté',
                        icon: Icons.power_input,
                      ),
                      EditorSegmentOption(
                        value: SuperSeparatorLineStyle.dotted,
                        label: 'Pointillé',
                        icon: Icons.more_horiz,
                      ),
                    ],
                    onChanged: (lineStyle) => setState(
                      () => _draft = _draft.copyWith(lineStyle: lineStyle),
                    ),
                  ),
                  _withBinding(
                    SuperSeparatorProperty.thickness,
                    'l’épaisseur du trait',
                    buildSettingField(
                      'thickness',
                      'Épaisseur du trait (px)',
                      numeric: true,
                    ),
                  ),
                  _colorSetting(
                    fieldKey: 'lineColor',
                    label: 'Couleur du trait',
                    fallbackColor: scheme.outlineVariant,
                    property: SuperSeparatorProperty.lineColor,
                  ),
                ]),
              ),
            StyleEditorSection(
              id: 'separator-label-typography',
              title: 'Libellé et typographie',
              icon: Icons.text_fields,
              tag: 'label · labelPosition · TextStyle',
              child: buildEditorFieldGroup([
                _withBinding(
                  SuperSeparatorProperty.label,
                  'le libellé',
                  buildSettingField(
                    'label',
                    'Libellé optionnel (vide = sans texte)',
                  ),
                ),
                EditorSegmentedField<SuperSeparatorLabelPosition>(
                  buttonKey: const ValueKey(
                    'super-separator-setting-labelPosition',
                  ),
                  label: 'Position du libellé',
                  value: _draft.labelPosition,
                  options: const [
                    EditorSegmentOption(
                      value: SuperSeparatorLabelPosition.start,
                      label: 'Début',
                      icon: Icons.align_horizontal_left,
                    ),
                    EditorSegmentOption(
                      value: SuperSeparatorLabelPosition.center,
                      label: 'Centre',
                      icon: Icons.align_horizontal_center,
                    ),
                    EditorSegmentOption(
                      value: SuperSeparatorLabelPosition.end,
                      label: 'Fin',
                      icon: Icons.align_horizontal_right,
                    ),
                  ],
                  onChanged: (pos) => setState(
                    () => _draft = _draft.copyWith(labelPosition: pos),
                  ),
                ),
                buildSettingField(
                  'labelSpacing',
                  'Espacement trait / libellé (px)',
                  numeric: true,
                  allowZero: true,
                ),
                ...buildComponentTypographyFields(
                  context: context,
                  settingPrefix: settingKeyPrefix,
                  bindingScope: _bindingScope,
                  availableFontFamilies: fonts,
                  fontFamily: _draft.fontFamily,
                  onFontFamilyChanged: (font) => setState(
                    () => _draft = _draft.copyWith(
                      fontFamily: font,
                      inheritFontFamily: font == null || font.isEmpty,
                    ),
                  ),
                  fontFamilyProperty: SuperSeparatorProperty.fontFamily,
                  fontSizeField: buildSettingField(
                    'fontSize',
                    'Taille de police (vide = thème)',
                    numeric: true,
                  ),
                  fontSizeProperty: SuperSeparatorProperty.fontSize,
                  fontWeight: _draft.fontWeight,
                  onFontWeightChanged: (weight) => setState(
                    () => _draft = _draft.copyWith(
                      fontWeight: weight,
                      inheritFontWeight: weight == null,
                    ),
                  ),
                  fontWeightProperty: SuperSeparatorProperty.fontWeight,
                  italic: _draft.italic,
                  onItalicChanged: ({required italic, required inherit}) =>
                      setState(
                        () => _draft = _draft.copyWith(
                          italic: italic,
                          inheritItalic: inherit,
                        ),
                      ),
                  italicProperty: SuperSeparatorProperty.italic,
                  beforeLetterSpacing: [
                    _colorSetting(
                      fieldKey: 'color',
                      label: 'Couleur du libellé',
                      fallbackColor:
                          widget.textStyle.color ?? scheme.onSurfaceVariant,
                      property: SuperSeparatorProperty.color,
                    ),
                  ],
                  letterSpacingField: buildSettingField(
                    'letterSpacing',
                    'Espacement des lettres (px)',
                    numeric: true,
                    allowZero: true,
                    allowNegative: true,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
