/// Fenêtre d'édition complète d'un composant [SuperAction].
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/automatic_state.dart';
import '../../../models/super_action_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../components/super_action.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../icons/material_icon_picker.dart';
import '../styles/style_editor_panel.dart';
import 'shared/component_state_editor_host.dart';
import 'shared/component_typography_controls.dart';
import 'shared/editor_color_fields.dart';
import 'shared/editor_segmented_field.dart';
import 'shared/surface_quick_controls_section.dart';

final _actionStateAdapter =
    ComponentStateAdapter<
      SuperActionConfig,
      ActionConfigStates,
      ActionConfigOverride,
      ActionStateProperty
    >(
      stateKeyPrefix: 'super-action-state',
      emptyStates: ActionConfigStates.new,
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
      createOverride: (config, [properties]) => ActionConfigOverride(
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
          ActionConfigStates(named: {name: const SuperActionConfig()});
          return null;
        } on FormatException catch (e) {
          return e.message;
        }
      },
      propertyLabels: {
        for (final property in ActionStateProperty.values)
          property: property.label,
      },
      validateRoot: (root, _) => root.validate(),
    );

/// Ouvre la boîte de dialogue d'édition d'un [SuperActionConfig].
Future<SuperActionConfig?> showSuperActionEditor({
  required BuildContext context,
  required SuperActionConfig config,
  required List<String> availableFontFamilies,
  bool allowBinding = true,
  ValueChanged<SuperActionConfig>? onPreviewChanged,
  String? activeState,
  String? stateError,
  bool isHovered = false,
  bool isSelected = false,
  bool allowContentHover = false,
  Set<AutomaticState> activeAutomatic = const {},
}) => showStatefulComponentEditorDialog(
  context: context,
  config: config,
  adapter: _actionStateAdapter,
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
  }) => _SuperActionEditor(
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

class _SuperActionEditor extends StatefulWidget {
  const _SuperActionEditor({
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
  final SuperActionConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding;
  final ValueChanged<SuperActionConfig>? onPreviewChanged;
  final Widget? header;
  final SuperActionConfig Function(SuperActionConfig config)? onSave;

  @override
  State<_SuperActionEditor> createState() => _SuperActionEditorState();
}

class _SuperActionEditorState extends State<_SuperActionEditor>
    with ComponentLeafFormMixin<_SuperActionEditor, SuperActionConfig> {
  late SuperActionConfig _draft;

  @override
  String get settingKeyPrefix => 'super-action-setting';

  @override
  String get invalidConfigMessage => 'Réglages de l’action invalides.';

  @override
  ValueChanged<SuperActionConfig>? get onPreviewChangedCallback =>
      widget.onPreviewChanged;

  @override
  SuperActionConfig Function(SuperActionConfig leaf)? get onSaveCallback =>
      widget.onSave;

  @override
  void initState() {
    super.initState();
    _draft = widget.config;
    fields = {
      'label': TextEditingController(text: _draft.label),
      'tooltip': TextEditingController(text: _draft.tooltip),
      'fontSize': TextEditingController(
        text: _draft.fontSize?.toString() ?? '',
      ),
      'iconSize': TextEditingController(
        text: _draft.iconSize?.toString() ?? '',
      ),
      'iconSpacing': TextEditingController(
        text: _draft.iconSpacing.toString(),
      ),
      'letterSpacing': TextEditingController(
        text: _draft.letterSpacing?.toString() ?? '',
      ),
      'color': TextEditingController(text: formatEditorColorHex(_draft.color)),
      'iconColor': TextEditingController(
        text: formatEditorColorHex(_draft.iconColor),
      ),
      'backgroundColor': TextEditingController(
        text: formatEditorColorHex(_draft.backgroundColor),
      ),
      'borderColor': TextEditingController(
        text: formatEditorColorHex(_draft.borderColor),
      ),
      'radius': TextEditingController(text: _draft.radius?.toString() ?? ''),
      'borderWidth': TextEditingController(
        text: _draft.borderWidth?.toString() ?? '',
      ),
      'elevation': TextEditingController(
        text: _draft.elevation?.toString() ?? '',
      ),
      'horizontalPadding': TextEditingController(
        text: _draft.horizontalPadding?.toString() ?? '',
      ),
      'verticalPadding': TextEditingController(
        text: _draft.verticalPadding?.toString() ?? '',
      ),
    };
  }

  @override
  SuperActionConfig buildConfiguration() {
    if (_draft.fontFamily != null &&
        !widget.availableFontFamilies.contains(_draft.fontFamily)) {
      throw const FormatException('Choisissez une police disponible.');
    }

    final fontSize = numberField('fontSize');
    final iconSize = numberField('iconSize');
    final iconSpacing = numberField('iconSpacing', allowZero: true) ?? 8;
    final letterSpacing = numberField(
      'letterSpacing',
      allowZero: true,
      allowNegative: true,
    );
    final radius = numberField('radius', allowZero: true);
    final borderWidth = numberField('borderWidth', allowZero: true);
    final elevation = numberField('elevation', allowZero: true);
    final horizontalPadding = numberField('horizontalPadding', allowZero: true);
    final verticalPadding = numberField('verticalPadding', allowZero: true);
    final color = colorField('color');
    final iconColor = colorField('iconColor');
    final backgroundColor = colorField('backgroundColor');
    final borderColor = colorField('borderColor');

    return _draft.copyWith(
      label: fields['label']!.text,
      tooltip: fields['tooltip']!.text,
      fontSize: fontSize,
      inheritFontSize: fontSize == null,
      iconSize: iconSize,
      inheritIconSize: iconSize == null,
      iconSpacing: iconSpacing,
      letterSpacing: letterSpacing,
      inheritLetterSpacing: letterSpacing == null,
      color: color,
      inheritColor: color == null,
      iconColor: iconColor,
      inheritIconColor: iconColor == null,
      backgroundColor: backgroundColor,
      inheritBackgroundColor: backgroundColor == null,
      borderColor: borderColor,
      inheritBorderColor: borderColor == null,
      radius: radius,
      inheritRadius: radius == null,
      borderWidth: borderWidth,
      inheritBorderWidth: borderWidth == null,
      elevation: elevation,
      inheritElevation: elevation == null,
      horizontalPadding: horizontalPadding,
      inheritHorizontalPadding: horizontalPadding == null,
      verticalPadding: verticalPadding,
      inheritVerticalPadding: verticalPadding == null,
    )..validate();
  }

  EditablePropertyBindingScope<SuperActionProperty> get _bindingScope =>
      EditablePropertyBindingScope<SuperActionProperty>(
        context: context,
        componentPrefix: 'super-action',
        allowBinding: widget.allowBinding,
        repositories: widget.repositories,
        listScope: widget.listScope,
        bindings: _draft.propertyBindings,
        onBindingsChanged: (bindings) =>
            setState(() => _draft = _draft.copyWith(propertyBindings: bindings)),
      );

  Widget _withBinding(
    SuperActionProperty property,
    String label,
    Widget child,
  ) => _bindingScope.wrap(property, label, child);

  Widget _colorSetting({
    required String fieldKey,
    required String label,
    required Color fallbackColor,
    required SuperActionProperty property,
  }) => BoundHexColorField(
    controller: fields[fieldKey]!,
    label: label,
    fallbackColor: fallbackColor,
    pickerKey: ValueKey('super-action-color-picker-$fieldKey'),
    fieldKey: ValueKey('super-action-setting-$fieldKey'),
    inheritButtonKey: ValueKey('super-action-inherit-$fieldKey'),
    onChanged: () => setState(() {}),
    wrapField: (field) => _withBinding(property, label.toLowerCase(), field),
  );

  Widget _preview(bool unavailable) {
    SuperActionConfig previewConfig;
    try {
      previewConfig = buildConfiguration();
    } on Object {
      previewConfig = _draft.copyWith(
        label: fields['label']!.text,
        tooltip: fields['tooltip']!.text,
      );
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
    return ComponentEditorPreviewCard(
      cardKey: const ValueKey('super-action-preview'),
      child: buildSuperActionVisual(
        context: context,
        config: previewConfig,
        textStyle: style,
        onPressed: () {},
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
      dialogKey: const ValueKey('super-action-settings'),
      initialTab: widget.initialTab,
      dimensionDelegate: delegate,
      onWidthChanged: widget.onWidthChanged,
      liveError: liveError,
      liveErrorKey: const ValueKey('super-action-live-error'),
      onApply: handleApply,
      propertiesBuilder: (context, dense, onDenseChanged) => Form(
        key: formKey,
        onChanged: () => setState(() {}),
        child: StyleEditorPanel(
          label: delegate?.editableLabel ?? 'Configurer l’action',
          onLabelChanged: delegate?.onLabelChanged,
          dense: dense,
          onDenseChanged: onDenseChanged,
          preview: _preview(unavailable),
          sections: [
            if (widget.header != null)
              StyleEditorSection(
                id: 'action-states',
                title: 'États',
                icon: Icons.layers_outlined,
                child: widget.header!,
              ),
            StyleEditorSection(
              id: 'action-content',
              title: 'Contenu et type de bouton',
              icon: Icons.smart_button_outlined,
              tag: 'kind · variant · label · icon',
              child: buildEditorFieldGroup([
                EditorSegmentedField.actionKind(
                  buttonKey: const ValueKey('super-action-setting-kind'),
                  value: _draft.kind,
                  onChanged: (kind) =>
                      setState(() => _draft = _draft.copyWith(kind: kind)),
                ),
                DropdownButtonFormField<SuperActionVariant?>(
                  isExpanded: true,
                  key: const ValueKey('super-action-setting-variant'),
                  initialValue: _draft.variant,
                  decoration: const InputDecoration(
                    labelText: 'Style / variante du bouton',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Automatique (selon contexte)'),
                    ),
                    DropdownMenuItem(
                      value: SuperActionVariant.filled,
                      child: Text('Filled (plein)'),
                    ),
                    DropdownMenuItem(
                      value: SuperActionVariant.tonal,
                      child: Text('Tonal (secondaire)'),
                    ),
                    DropdownMenuItem(
                      value: SuperActionVariant.elevated,
                      child: Text('Elevated (élevé)'),
                    ),
                    DropdownMenuItem(
                      value: SuperActionVariant.outlined,
                      child: Text('Outlined (contour)'),
                    ),
                    DropdownMenuItem(
                      value: SuperActionVariant.text,
                      child: Text('Text (sans fond)'),
                    ),
                    DropdownMenuItem(
                      value: SuperActionVariant.icon,
                      child: Text('Icon Button'),
                    ),
                    DropdownMenuItem(
                      value: SuperActionVariant.surface,
                      child: Text('Surface personnalisée (ContainerStyle)'),
                    ),
                  ],
                  onChanged: (variant) {
                    setState(
                      () => _draft = variant == null
                          ? _draft.copyWith(inheritVariant: true)
                          : _draft.copyWith(variant: variant),
                    );
                  },
                ),
                if (_draft.kind.hasText)
                  _withBinding(
                    SuperActionProperty.label,
                    'le libellé',
                    buildSettingField('label', 'Libellé du bouton'),
                  ),
                if (_draft.kind.hasIcon)
                  _withBinding(
                    SuperActionProperty.icon,
                    'l’icône',
                    MaterialIconPickerField(
                      key: const ValueKey('super-action-setting-icon'),
                      label: 'Icône',
                      nullable: true,
                      value: _draft.icon.trim().isEmpty
                          ? null
                          : (SuperActionIcons.isKnown(_draft.icon)
                                ? _draft.icon
                                : 'touch_app'),
                      onChanged: (icon) => setState(
                        () => _draft = _draft.copyWith(icon: icon ?? ''),
                      ),
                    ),
                  ),
                if (_draft.kind == SuperActionKind.textAndIcon)
                  EditorSegmentedField.actionIconPosition(
                    buttonKey: const ValueKey(
                      'super-action-setting-iconPosition',
                    ),
                    value: _draft.iconPosition,
                    onChanged: (pos) => setState(
                      () => _draft = _draft.copyWith(iconPosition: pos),
                    ),
                  ),
                _withBinding(
                  SuperActionProperty.tooltip,
                  'l’infobulle',
                  buildSettingField('tooltip', 'Infobulle (tooltip)'),
                ),
              ]),
            ),
            StyleEditorSection(
              id: 'action-behavior',
              title: 'Comportement',
              icon: Icons.tune,
              tag: 'enabled',
              child: buildEditorFieldGroup([
                _withBinding(
                  SuperActionProperty.enabled,
                  'l’activation',
                  EditorSwitchTile(
                    tileKey: const ValueKey('super-action-setting-enabled'),
                    title: 'Activé',
                    value: _draft.enabled,
                    onChanged: (value) =>
                        setState(() => _draft = _draft.copyWith(enabled: value)),
                  ),
                ),
              ]),
            ),
            StyleEditorSection(
              id: 'action-typography',
              title: 'Typographie et icône',
              icon: Icons.font_download_outlined,
              tag: 'TextStyle · Icon',
              child: buildEditorFieldGroup(
                buildComponentTypographyFields(
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
                  fontFamilyProperty: SuperActionProperty.fontFamily,
                  fontSizeField: buildSettingField(
                    'fontSize',
                    'Taille de police (vide = thème)',
                    numeric: true,
                  ),
                  fontSizeProperty: SuperActionProperty.fontSize,
                  afterFontSize: [
                    _withBinding(
                      SuperActionProperty.iconSize,
                      'la taille de l’icône',
                      buildSettingField(
                        'iconSize',
                        'Taille de l’icône (vide = thème)',
                        numeric: true,
                      ),
                    ),
                    if (_draft.kind == SuperActionKind.textAndIcon)
                      buildSettingField(
                        'iconSpacing',
                        'Espacement icône / texte (px)',
                        numeric: true,
                        allowZero: true,
                      ),
                  ],
                  fontWeight: _draft.fontWeight,
                  onFontWeightChanged: (weight) => setState(
                    () => _draft = _draft.copyWith(
                      fontWeight: weight,
                      inheritFontWeight: weight == null,
                    ),
                  ),
                  fontWeightProperty: SuperActionProperty.fontWeight,
                  italic: _draft.italic,
                  onItalicChanged: ({required italic, required inherit}) =>
                      setState(
                        () => _draft = _draft.copyWith(
                          italic: italic,
                          inheritItalic: inherit,
                        ),
                      ),
                  italicProperty: SuperActionProperty.italic,
                  textAlign: _draft.textAlign,
                  onTextAlignChanged: (align) =>
                      setState(() => _draft = _draft.copyWith(textAlign: align)),
                  textAlignProperty: SuperActionProperty.textAlign,
                  letterSpacingField: buildSettingField(
                    'letterSpacing',
                    'Espacement des lettres (px)',
                    numeric: true,
                    allowZero: true,
                    allowNegative: true,
                  ),
                ),
              ),
            ),
            StyleEditorSection(
              id: 'action-colors-shape',
              title: 'Couleurs et forme du bouton',
              icon: Icons.palette_outlined,
              tag: 'color · background · border · radius',
              child: buildEditorFieldGroup([
                _colorSetting(
                  fieldKey: 'color',
                  label: 'Couleur du texte / contenu',
                  fallbackColor: widget.textStyle.color ?? scheme.onPrimary,
                  property: SuperActionProperty.color,
                ),
                if (_draft.kind.hasIcon)
                  _colorSetting(
                    fieldKey: 'iconColor',
                    label: 'Couleur de l’icône',
                    fallbackColor: _draft.color ?? scheme.onPrimary,
                    property: SuperActionProperty.iconColor,
                  ),
                _colorSetting(
                  fieldKey: 'backgroundColor',
                  label: 'Couleur de fond',
                  fallbackColor: scheme.primary,
                  property: SuperActionProperty.backgroundColor,
                ),
                _colorSetting(
                  fieldKey: 'borderColor',
                  label: 'Couleur de bordure',
                  fallbackColor: scheme.outline,
                  property: SuperActionProperty.borderColor,
                ),
                ...buildComponentBoxDimensionFields(
                  bindingScope: _bindingScope,
                  buildField: buildSettingField,
                  radiusProperty: SuperActionProperty.radius,
                  borderWidthProperty: SuperActionProperty.borderWidth,
                  elevationProperty: SuperActionProperty.elevation,
                ),
              ]),
            ),
            buildSurfaceQuickControlsSection(
              sectionId: 'action-surface',
              componentPrefix: 'super-action',
              style: _draft.style,
              onStyleChanged: (style) =>
                  setState(() => _draft = _draft.copyWith(style: style)),
            ),
          ],
        ),
      ),
    );
  }
}
