/// Fenêtre d'édition complète d'un composant [SuperIndicator].
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/automatic_state.dart';
import '../../../models/super_indicator_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../components/super_indicator.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../icons/material_icon_picker.dart';
import '../styles/style_editor_panel.dart';
import 'shared/component_state_editor_host.dart';
import 'shared/component_typography_controls.dart';
import 'shared/editor_color_fields.dart';
import 'shared/surface_quick_controls_section.dart';

final _indicatorStateAdapter =
    ComponentStateAdapter<
      SuperIndicatorConfig,
      IndicatorConfigStates,
      IndicatorConfigOverride,
      IndicatorStateProperty
    >(
      stateKeyPrefix: 'super-indicator-state',
      emptyStates: IndicatorConfigStates.new,
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
      createOverride: (config, [properties]) => IndicatorConfigOverride(
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
          IndicatorConfigStates(named: {name: const SuperIndicatorConfig()});
          return null;
        } on FormatException catch (e) {
          return e.message;
        }
      },
      propertyLabels: {
        for (final property in IndicatorStateProperty.values)
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
        AutomaticState.disabled,
      },
    );

/// Ouvre la boîte de dialogue d'édition d'un [SuperIndicatorConfig] avec gestion
/// complète des états standards (`hover`, `selected`, `contentHover`, `disabled`),
/// des états métier personnalisés (`named`) et des liaisons JSON.
Future<SuperIndicatorConfig?> showSuperIndicatorEditor({
  required BuildContext context,
  required SuperIndicatorConfig config,
  required List<String> availableFontFamilies,
  bool allowBinding = true,
  ValueChanged<SuperIndicatorConfig>? onPreviewChanged,
  String? activeState,
  String? stateError,
  bool isHovered = false,
  bool isSelected = false,
  bool allowContentHover = false,
  Set<AutomaticState> activeAutomatic = const {},
}) => showStatefulComponentEditorDialog(
  context: context,
  config: config,
  adapter: _indicatorStateAdapter,
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
  }) => _SuperIndicatorEditor(
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

class _SuperIndicatorEditor extends StatefulWidget {
  const _SuperIndicatorEditor({
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
  final SuperIndicatorConfig config;
  final List<String> availableFontFamilies;
  final TextStyle textStyle;
  final ValueChanged<double> onWidthChanged;
  final JsonRepositoryStore? repositories;
  final JsonListScope? listScope;
  final bool allowBinding;
  final ValueChanged<SuperIndicatorConfig>? onPreviewChanged;
  final Widget? header;
  final SuperIndicatorConfig Function(SuperIndicatorConfig config)? onSave;

  @override
  State<_SuperIndicatorEditor> createState() => _SuperIndicatorEditorState();
}

class _SuperIndicatorEditorState extends State<_SuperIndicatorEditor>
    implements ComponentLeafCapable<SuperIndicatorConfig> {
  final _form = GlobalKey<FormState>();
  late SuperIndicatorConfig _draft;
  late final Map<String, TextEditingController> _fields;
  SuperIndicatorConfig? _lastPreview;
  String? _liveError;

  @override
  void initState() {
    super.initState();
    _draft = widget.config;
    _fields = {
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
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  SuperIndicatorConfig? capture() {
    if (!_form.currentState!.validate()) return null;
    try {
      return _configuration();
    } on FormatException catch (e) {
      setState(() => _liveError = e.message);
    } on ArgumentError {
      setState(() => _liveError = 'Réglages de l’indicateur invalides.');
    }
    return null;
  }

  SuperIndicatorConfig _configuration() {
    double? number(
      String key, {
      bool allowZero = false,
      bool allowNegative = false,
    }) => parseEditorNumberField(
      _fields[key]!.text,
      allowZero: allowZero,
      allowNegative: allowNegative,
    );

    Color? colorField(String key) => parseEditorColorHex(_fields[key]!.text);

    if (_draft.fontFamily != null &&
        !widget.availableFontFamilies.contains(_draft.fontFamily)) {
      throw const FormatException('Choisissez une police disponible.');
    }

    final fontSize = number('fontSize');
    final iconSize = number('iconSize');
    final iconSpacing = number('iconSpacing', allowZero: true) ?? 6;
    final letterSpacing = number(
      'letterSpacing',
      allowZero: true,
      allowNegative: true,
    );
    final radius = number('radius', allowZero: true);
    final borderWidth = number('borderWidth', allowZero: true);
    final elevation = number('elevation', allowZero: true);
    final horizontalPadding = number('horizontalPadding', allowZero: true);
    final verticalPadding = number('verticalPadding', allowZero: true);
    final color = colorField('color');
    final iconColor = colorField('iconColor');
    final backgroundColor = colorField('backgroundColor');
    final borderColor = colorField('borderColor');

    final result = _draft.copyWith(
      label: _fields['label']!.text,
      tooltip: _fields['tooltip']!.text,
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
    );
    result.validate();
    return result;
  }

  void _schedulePreview() {
    if (widget.onPreviewChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      try {
        final config = _configuration();
        if (_liveError != null) setState(() => _liveError = null);
        if (_lastPreview != config) {
          _lastPreview = config;
          widget.onPreviewChanged!(config);
        }
      } on FormatException catch (error) {
        if (_liveError != error.message) {
          setState(() => _liveError = error.message);
        }
      } on ArgumentError {
        const message = 'Réglages de l’indicateur invalides.';
        if (_liveError != message) setState(() => _liveError = message);
      }
    });
  }

  Widget _field(
    String key,
    String label, {
    bool numeric = false,
    bool allowZero = false,
    bool allowNegative = false,
    bool colorHex = false,
  }) => buildEditorSettingTextField(
    fieldKey: ValueKey('super-indicator-setting-$key'),
    controller: _fields[key]!,
    label: label,
    numeric: numeric,
    allowZero: allowZero,
    allowNegative: allowNegative,
    colorHex: colorHex,
  );

  EditablePropertyBindingScope<SuperIndicatorProperty> get _bindingScope =>
      EditablePropertyBindingScope<SuperIndicatorProperty>(
        context: context,
        componentPrefix: 'super-indicator',
        allowBinding: widget.allowBinding,
        repositories: widget.repositories,
        listScope: widget.listScope,
        bindings: _draft.propertyBindings,
        onBindingsChanged: (bindings) =>
            setState(() => _draft = _draft.copyWith(propertyBindings: bindings)),
      );

  Widget _withBinding(
    SuperIndicatorProperty property,
    String label,
    Widget child,
  ) => _bindingScope.wrap(property, label, child);

  Widget _colorSetting({
    required String fieldKey,
    required String label,
    required Color fallbackColor,
    required SuperIndicatorProperty property,
  }) => BoundHexColorField(
    controller: _fields[fieldKey]!,
    label: label,
    fallbackColor: fallbackColor,
    pickerKey: ValueKey('super-indicator-color-picker-$fieldKey'),
    fieldKey: ValueKey('super-indicator-setting-$fieldKey'),
    inheritButtonKey: ValueKey('super-indicator-inherit-$fieldKey'),
    onChanged: () => setState(() {}),
    wrapField: (field) => _withBinding(property, label.toLowerCase(), field),
  );

  Widget _preview(bool unavailable) {
    SuperIndicatorConfig previewConfig;
    try {
      previewConfig = _configuration();
    } on Object {
      previewConfig = _draft.copyWith(
        label: _fields['label']!.text,
        tooltip: _fields['tooltip']!.text,
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
      cardKey: const ValueKey('super-indicator-preview'),
      child: buildSuperIndicatorVisual(
        context: context,
        config: previewConfig,
        textStyle: style,
      ),
    );
  }

  bool _handleApply() {
    if (_form.currentState != null && !_form.currentState!.validate()) {
      return false;
    }
    SuperIndicatorConfig result;
    try {
      final leaf = _configuration();
      result = widget.onSave?.call(leaf) ?? leaf;
    } on FormatException catch (e) {
      setState(() => _liveError = e.message);
      return false;
    } on ArgumentError {
      setState(() => _liveError = 'Combinaison de propriétés invalide.');
      return false;
    }
    Navigator.of(context).pop(result);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    _schedulePreview();
    final fonts = widget.availableFontFamilies.toSet().toList();
    final unavailable =
        _draft.fontFamily != null && !fonts.contains(_draft.fontFamily);
    final scheme = Theme.of(context).colorScheme;
    final delegate = widget.dimensionDelegate;

    return EditorStyleWizardDialog(
      dialogKey: const ValueKey('super-indicator-settings'),
      initialTab: widget.initialTab,
      dimensionDelegate: delegate,
      onWidthChanged: widget.onWidthChanged,
      liveError: _liveError,
      liveErrorKey: const ValueKey('super-indicator-live-error'),
      onApply: _handleApply,
      propertiesBuilder: (context, dense, onDenseChanged) => Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: StyleEditorPanel(
          label: delegate?.editableLabel ?? 'Configurer l’indicateur',
          onLabelChanged: delegate?.onLabelChanged,
          dense: dense,
          onDenseChanged: onDenseChanged,
          preview: _preview(unavailable),
          sections: [
            if (widget.header != null)
              StyleEditorSection(
                id: 'indicator-states',
                title: 'États',
                icon: Icons.layers_outlined,
                child: widget.header!,
              ),
            StyleEditorSection(
              id: 'indicator-content',
              title: 'Icône et contenu',
              icon: Icons.adjust_outlined,
              tag: 'icon · label · tooltip',
              child: buildEditorFieldGroup([
                _withBinding(
                  SuperIndicatorProperty.icon,
                  'l’icône',
                  MaterialIconPickerField(
                    key: const ValueKey('super-indicator-setting-icon'),
                    label: 'Icône',
                    nullable: true,
                    value: _draft.icon.trim().isEmpty
                        ? null
                        : (SuperIndicatorIcons.isKnown(_draft.icon)
                              ? _draft.icon
                              : 'info'),
                    onChanged: (icon) => setState(
                      () => _draft = _draft.copyWith(icon: icon ?? ''),
                    ),
                  ),
                ),
                _withBinding(
                  SuperIndicatorProperty.iconSize,
                  'la taille de l’icône',
                  _field(
                    'iconSize',
                    'Taille de l’icône (vide = 24 px)',
                    numeric: true,
                  ),
                ),
                _withBinding(
                  SuperIndicatorProperty.label,
                  'le libellé',
                  _field('label', 'Libellé optionnel (badge / statut)'),
                ),
                const Text(
                  'Position de l’icône',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                SegmentedButton<SuperIndicatorIconPosition>(
                  key: const ValueKey('super-indicator-setting-iconPosition'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: SuperIndicatorIconPosition.leading,
                      tooltip: 'Début (avant le texte)',
                      icon: Icon(Icons.first_page, size: 16),
                      label: Text(
                        'Début (avant le texte)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ButtonSegment(
                      value: SuperIndicatorIconPosition.trailing,
                      tooltip: 'Fin (après le texte)',
                      icon: Icon(Icons.last_page, size: 16),
                      label: Text(
                        'Fin (après le texte)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  selected: {_draft.iconPosition},
                  onSelectionChanged: (selected) {
                    if (selected.isNotEmpty) {
                      setState(
                        () => _draft = _draft.copyWith(
                          iconPosition: selected.first,
                        ),
                      );
                    }
                  },
                ),
                _field(
                  'iconSpacing',
                  'Espacement icône / texte (px)',
                  numeric: true,
                  allowZero: true,
                ),
                _withBinding(
                  SuperIndicatorProperty.tooltip,
                  'l’infobulle',
                  _field('tooltip', 'Infobulle (tooltip)'),
                ),
              ]),
            ),
            StyleEditorSection(
              id: 'indicator-behavior',
              title: 'Comportement',
              icon: Icons.tune,
              tag: 'enabled',
              child: buildEditorFieldGroup([
                _withBinding(
                  SuperIndicatorProperty.enabled,
                  'l’activation',
                  SwitchListTile(
                    key: const ValueKey('super-indicator-setting-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activé'),
                    value: _draft.enabled,
                    onChanged: (value) =>
                        setState(() => _draft = _draft.copyWith(enabled: value)),
                  ),
                ),
              ]),
            ),
            StyleEditorSection(
              id: 'indicator-colors-shape',
              title: 'Couleurs et badge',
              icon: Icons.palette_outlined,
              tag: 'iconColor · background · border · radius',
              child: buildEditorFieldGroup([
                _colorSetting(
                  fieldKey: 'iconColor',
                  label: 'Couleur de l’icône',
                  fallbackColor: _draft.color ?? scheme.primary,
                  property: SuperIndicatorProperty.iconColor,
                ),
                _colorSetting(
                  fieldKey: 'color',
                  label: 'Couleur du texte / contenu',
                  fallbackColor: widget.textStyle.color ?? scheme.onSurface,
                  property: SuperIndicatorProperty.color,
                ),
                _colorSetting(
                  fieldKey: 'backgroundColor',
                  label: 'Couleur de fond (badge)',
                  fallbackColor: scheme.secondaryContainer,
                  property: SuperIndicatorProperty.backgroundColor,
                ),
                _colorSetting(
                  fieldKey: 'borderColor',
                  label: 'Couleur de bordure',
                  fallbackColor: scheme.outline,
                  property: SuperIndicatorProperty.borderColor,
                ),
                ...buildComponentBoxDimensionFields(
                  bindingScope: _bindingScope,
                  buildField: _field,
                  radiusProperty: SuperIndicatorProperty.radius,
                  borderWidthProperty: SuperIndicatorProperty.borderWidth,
                  elevationProperty: SuperIndicatorProperty.elevation,
                  radiusLabel: 'Rayon des coins (vide = aucun / thème)',
                  borderWidthLabel: 'Épaisseur de bordure (vide = aucune)',
                  elevationLabel: 'Élévation (vide = aucune)',
                ),
              ]),
            ),
            StyleEditorSection(
              id: 'indicator-typography',
              title: 'Typographie et alignement',
              icon: Icons.font_download_outlined,
              tag: 'TextStyle · Align',
              child: buildEditorFieldGroup([
                if (unavailable)
                  Text(
                    'Police indisponible : ${_draft.fontFamily}. Choisissez une police disponible.',
                    style: TextStyle(color: scheme.error),
                  ),
                _withBinding(
                  SuperIndicatorProperty.fontFamily,
                  'la police',
                  ComponentFontFamilyField(
                    settingPrefix: 'super-indicator-setting',
                    fontFamily: _draft.fontFamily,
                    availableFontFamilies: fonts,
                    onChanged: (font) => setState(
                      () => _draft = _draft.copyWith(
                        fontFamily: font,
                        inheritFontFamily: font == null || font.isEmpty,
                      ),
                    ),
                  ),
                ),
                _withBinding(
                  SuperIndicatorProperty.fontSize,
                  'la taille de police',
                  _field(
                    'fontSize',
                    'Taille de police (vide = thème)',
                    numeric: true,
                  ),
                ),
                _withBinding(
                  SuperIndicatorProperty.fontWeight,
                  'la graisse',
                  ComponentFontWeightField(
                    fontWeight: _draft.fontWeight,
                    onChanged: (weight) => setState(
                      () => _draft = _draft.copyWith(
                        fontWeight: weight,
                        inheritFontWeight: weight == null,
                      ),
                    ),
                  ),
                ),
                _withBinding(
                  SuperIndicatorProperty.italic,
                  'le style italique',
                  ComponentItalicSegmentField(
                    settingPrefix: 'super-indicator-setting',
                    italic: _draft.italic,
                    onChanged: ({required italic, required inherit}) =>
                        setState(
                          () => _draft = _draft.copyWith(
                            italic: italic,
                            inheritItalic: inherit,
                          ),
                        ),
                  ),
                ),
                _withBinding(
                  SuperIndicatorProperty.textAlign,
                  'l’alignement',
                  ComponentTextAlignSegmentField(
                    settingPrefix: 'super-indicator-setting',
                    textAlign: _draft.textAlign,
                    onChanged: (align) => setState(
                      () => _draft = _draft.copyWith(textAlign: align),
                    ),
                  ),
                ),
                _field(
                  'letterSpacing',
                  'Espacement des lettres (px)',
                  numeric: true,
                  allowZero: true,
                  allowNegative: true,
                ),
              ]),
            ),
            buildSurfaceQuickControlsSection(
              sectionId: 'indicator-surface',
              componentPrefix: 'super-indicator',
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
