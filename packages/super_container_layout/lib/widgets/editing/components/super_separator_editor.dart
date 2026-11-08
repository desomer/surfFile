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
    implements ComponentLeafCapable<SuperSeparatorConfig> {
  final _form = GlobalKey<FormState>();
  late SuperSeparatorConfig _draft;
  late final Map<String, TextEditingController> _fields;
  SuperSeparatorConfig? _lastPreview;
  String? _liveError;

  @override
  void initState() {
    super.initState();
    _draft = widget.config;
    _fields = {
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
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  SuperSeparatorConfig? capture() {
    if (!_form.currentState!.validate()) return null;
    try {
      return _configuration();
    } on FormatException catch (e) {
      setState(() => _liveError = e.message);
    } on ArgumentError {
      setState(() => _liveError = 'Réglages du séparateur invalides.');
    }
    return null;
  }

  SuperSeparatorConfig _configuration() {
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

    final extent = number('extent', allowZero: true) ?? 16;
    final thickness = number('thickness') ?? 1;
    final indent = number('indent', allowZero: true) ?? 0;
    final endIndent = number('endIndent', allowZero: true) ?? 0;
    final labelSpacing = number('labelSpacing', allowZero: true) ?? 8;
    final fontSize = number('fontSize');
    final letterSpacing = number(
      'letterSpacing',
      allowZero: true,
      allowNegative: true,
    );
    final lineColor = colorField('lineColor');
    final color = colorField('color');

    final result = _draft.copyWith(
      label: _fields['label']!.text,
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
        const message = 'Réglages du séparateur invalides.';
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
    fieldKey: ValueKey('super-separator-setting-$key'),
    controller: _fields[key]!,
    label: label,
    numeric: numeric,
    allowZero: allowZero,
    allowNegative: allowNegative,
    colorHex: colorHex,
  );

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
    controller: _fields[fieldKey]!,
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
      previewConfig = _configuration();
    } on Object {
      previewConfig = _draft.copyWith(label: _fields['label']!.text);
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

  bool _handleApply() {
    if (_form.currentState != null && !_form.currentState!.validate()) {
      return false;
    }
    SuperSeparatorConfig result;
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
      dialogKey: const ValueKey('super-separator-settings'),
      initialTab: widget.initialTab,
      dimensionDelegate: delegate,
      onWidthChanged: widget.onWidthChanged,
      liveError: _liveError,
      liveErrorKey: const ValueKey('super-separator-live-error'),
      onApply: _handleApply,
      propertiesBuilder: (context, dense, onDenseChanged) => Form(
        key: _form,
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
                const Text(
                  'Type de composant',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                SegmentedButton<SuperSeparatorKind>(
                  key: const ValueKey('super-separator-setting-kind'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: SuperSeparatorKind.divider,
                      tooltip: 'Trait de séparation (Divider)',
                      icon: Icon(Icons.horizontal_rule, size: 16),
                      label: Text(
                        'Divider (trait)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ButtonSegment(
                      value: SuperSeparatorKind.spacer,
                      tooltip: 'Espace vide (Spacer)',
                      icon: Icon(Icons.space_bar, size: 16),
                      label: Text(
                        'Spacer (espace)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  selected: {_draft.kind},
                  onSelectionChanged: (selected) {
                    if (selected.isNotEmpty) {
                      setState(
                        () => _draft = _draft.copyWith(kind: selected.first),
                      );
                    }
                  },
                ),
                const Text(
                  'Orientation',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                SegmentedButton<Axis>(
                  key: const ValueKey('super-separator-setting-axis'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: Axis.horizontal,
                      tooltip: 'Horizontal',
                      icon: Icon(Icons.swap_horiz, size: 16),
                      label: Text('Horizontal', overflow: TextOverflow.ellipsis),
                    ),
                    ButtonSegment(
                      value: Axis.vertical,
                      tooltip: 'Vertical',
                      icon: Icon(Icons.swap_vert, size: 16),
                      label: Text('Vertical', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  selected: {_draft.axis},
                  onSelectionChanged: (selected) {
                    if (selected.isNotEmpty) {
                      setState(
                        () => _draft = _draft.copyWith(axis: selected.first),
                      );
                    }
                  },
                ),
                _withBinding(
                  SuperSeparatorProperty.extent,
                  'la taille / l’espace',
                  _field(
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
                        _field(
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
                        _field(
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
                  const Text(
                    'Style du trait',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  SegmentedButton<SuperSeparatorLineStyle>(
                    key: const ValueKey('super-separator-setting-lineStyle'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: SuperSeparatorLineStyle.solid,
                        tooltip: 'Continu',
                        icon: Icon(Icons.horizontal_rule, size: 16),
                        label: Text('Continu', overflow: TextOverflow.ellipsis),
                      ),
                      ButtonSegment(
                        value: SuperSeparatorLineStyle.dashed,
                        tooltip: 'Tireté',
                        icon: Icon(Icons.power_input, size: 16),
                        label: Text('Tireté', overflow: TextOverflow.ellipsis),
                      ),
                      ButtonSegment(
                        value: SuperSeparatorLineStyle.dotted,
                        tooltip: 'Pointillé',
                        icon: Icon(Icons.more_horiz, size: 16),
                        label: Text(
                          'Pointillé',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    selected: {_draft.lineStyle},
                    onSelectionChanged: (selected) {
                      if (selected.isNotEmpty) {
                        setState(
                          () => _draft = _draft.copyWith(
                            lineStyle: selected.first,
                          ),
                        );
                      }
                    },
                  ),
                  _withBinding(
                    SuperSeparatorProperty.thickness,
                    'l’épaisseur du trait',
                    _field(
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
                  _field('label', 'Libellé optionnel (vide = sans texte)'),
                ),
                const Text(
                  'Position du libellé',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                SegmentedButton<SuperSeparatorLabelPosition>(
                  key: const ValueKey('super-separator-setting-labelPosition'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: SuperSeparatorLabelPosition.start,
                      tooltip: 'Début',
                      icon: Icon(Icons.align_horizontal_left, size: 16),
                      label: Text('Début', overflow: TextOverflow.ellipsis),
                    ),
                    ButtonSegment(
                      value: SuperSeparatorLabelPosition.center,
                      tooltip: 'Centre',
                      icon: Icon(Icons.align_horizontal_center, size: 16),
                      label: Text('Centre', overflow: TextOverflow.ellipsis),
                    ),
                    ButtonSegment(
                      value: SuperSeparatorLabelPosition.end,
                      tooltip: 'Fin',
                      icon: Icon(Icons.align_horizontal_right, size: 16),
                      label: Text('Fin', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  selected: {_draft.labelPosition},
                  onSelectionChanged: (selected) {
                    if (selected.isNotEmpty) {
                      setState(
                        () => _draft = _draft.copyWith(
                          labelPosition: selected.first,
                        ),
                      );
                    }
                  },
                ),
                _field(
                  'labelSpacing',
                  'Espacement trait / libellé (px)',
                  numeric: true,
                  allowZero: true,
                ),
                if (unavailable)
                  Text(
                    'Police indisponible : ${_draft.fontFamily}. Choisissez une police disponible.',
                    style: TextStyle(color: scheme.error),
                  ),
                _withBinding(
                  SuperSeparatorProperty.fontFamily,
                  'la police',
                  ComponentFontFamilyField(
                    settingPrefix: 'super-separator-setting',
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
                  SuperSeparatorProperty.fontSize,
                  'la taille de police',
                  _field(
                    'fontSize',
                    'Taille de police (vide = thème)',
                    numeric: true,
                  ),
                ),
                _withBinding(
                  SuperSeparatorProperty.fontWeight,
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
                  SuperSeparatorProperty.italic,
                  'le style italique',
                  ComponentItalicSegmentField(
                    settingPrefix: 'super-separator-setting',
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
                _colorSetting(
                  fieldKey: 'color',
                  label: 'Couleur du libellé',
                  fallbackColor:
                      widget.textStyle.color ?? scheme.onSurfaceVariant,
                  property: SuperSeparatorProperty.color,
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
          ],
        ),
      ),
    );
  }
}
