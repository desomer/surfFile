// Surcharges conditionnelles d'états ([SeparatorConfigStates]) pour un [SuperSeparator].
//
// Permet de modifier sélectivement des groupes de propriétés ([SeparatorStateProperty])
// au survol (`hover`), à la sélection de ligne (`selected`), sur état automatique
// ou sur état métier nommé lié à un repository JSON.
part of 'super_separator_config.dart';

/// Groupes de propriétés de [SuperSeparatorConfig] surchargeables par état.
enum SeparatorStateProperty
    implements ComponentStateProperty<SuperSeparatorProperty> {
  content('Type et orientation', [
    'kind',
    'axis',
    'lineStyle',
    'labelPosition',
    'labelSpacing',
  ]),
  extent('Taille / espace', ['extent'], SuperSeparatorProperty.extent),
  thickness('Épaisseur du trait', [
    'thickness',
  ], SuperSeparatorProperty.thickness),
  indents('Retraits (indent / endIndent)', ['indent', 'endIndent']),
  lineColor('Couleur du trait', [
    'lineColor',
  ], SuperSeparatorProperty.lineColor),
  textLabel('Libellé', ['label'], SuperSeparatorProperty.label),
  fontFamily('Police', ['fontFamily'], SuperSeparatorProperty.fontFamily),
  fontSize('Taille du texte', ['fontSize'], SuperSeparatorProperty.fontSize),
  fontWeight('Graisse', ['fontWeight'], SuperSeparatorProperty.fontWeight),
  italic('Italique', ['italic'], SuperSeparatorProperty.italic),
  color('Couleur du texte', ['color'], SuperSeparatorProperty.color),
  letterSpacing('Espacement des lettres', ['letterSpacing']);

  const SeparatorStateProperty(this.label, this.keys, [this.bindingProperty]);

  @override
  final String label;
  @override
  final List<String> keys;
  @override
  final SuperSeparatorProperty? bindingProperty;
}

/// Surcharge partielle d'un [SuperSeparatorConfig] associée à une liste explicite de [SeparatorStateProperty].
@immutable
class SeparatorConfigOverride
    extends
        ComponentConfigOverrideBase<
          SuperSeparatorConfig,
          SeparatorStateProperty,
          SuperSeparatorProperty
        > {
  SeparatorConfigOverride({
    SuperSeparatorConfig config = const SuperSeparatorConfig(),
    super.properties,
  }) : super(config: _separatorStateLeaf(config));

  SeparatorConfigOverride copyWith({
    SuperSeparatorConfig? config,
    Set<SeparatorStateProperty>? properties,
    bool clearProperties = false,
  }) => SeparatorConfigOverride(
    config: config ?? this.config,
    properties: clearProperties ? const {} : properties ?? this.properties,
  );

  SeparatorConfigOverride edited(SuperSeparatorConfig next) {
    final leaf = _separatorStateLeaf(next);
    return SeparatorConfigOverride(
      config: leaf,
      properties: computeEditedProperties(
        leaf,
        SeparatorStateProperty.values,
        (c) => c.propertyBindings,
      ),
    );
  }

  @override
  SuperSeparatorConfig apply(SuperSeparatorConfig base) {
    final bindings = mergePropertyBindings(base, (c) => c.propertyBindings);
    if (properties.contains(SeparatorStateProperty.indents)) {
      for (final p in const [
        SuperSeparatorProperty.indent,
        SuperSeparatorProperty.endIndent,
      ]) {
        final binding = config.propertyBindings[p];
        if (binding == null) {
          bindings.remove(p);
        } else {
          bindings[p] = binding;
        }
      }
    }
    bool has(SeparatorStateProperty property) => properties.contains(property);
    final content = has(SeparatorStateProperty.content) ? config : base;
    final indents = has(SeparatorStateProperty.indents) ? config : base;
    return SuperSeparatorConfig(
      kind: content.kind,
      axis: content.axis,
      lineStyle: content.lineStyle,
      labelPosition: content.labelPosition,
      labelSpacing: content.labelSpacing,
      extent: has(SeparatorStateProperty.extent) ? config.extent : base.extent,
      thickness: has(SeparatorStateProperty.thickness)
          ? config.thickness
          : base.thickness,
      indent: indents.indent,
      endIndent: indents.endIndent,
      lineColor: has(SeparatorStateProperty.lineColor)
          ? config.lineColor
          : base.lineColor,
      label: has(SeparatorStateProperty.textLabel) ? config.label : base.label,
      fontFamily: has(SeparatorStateProperty.fontFamily)
          ? config.fontFamily
          : base.fontFamily,
      fontSize: has(SeparatorStateProperty.fontSize)
          ? config.fontSize
          : base.fontSize,
      fontWeight: has(SeparatorStateProperty.fontWeight)
          ? config.fontWeight
          : base.fontWeight,
      italic: has(SeparatorStateProperty.italic) ? config.italic : base.italic,
      color: has(SeparatorStateProperty.color) ? config.color : base.color,
      letterSpacing: has(SeparatorStateProperty.letterSpacing)
          ? config.letterSpacing
          : base.letterSpacing,
      propertyBindings: Map.unmodifiable(bindings),
    ).._validateLeaf();
  }

  factory SeparatorConfigOverride.fromJson(Object? value) {
    final properties = ComponentStateHelpers.parseOverrideProperties(
      value,
      SeparatorStateProperty.values,
      'Separator',
    );
    return SeparatorConfigOverride(
      config: _readSeparatorStateLeaf((value as Map)['config']),
      properties: properties,
    );
  }
}

/// Collection des surcharges d'états (`named`, `hover`, `selected`, `automatic`) d'un [SuperSeparatorConfig].
@immutable
class SeparatorConfigStates
    extends
        ComponentConfigStatesBase<
          SuperSeparatorConfig,
          SeparatorStateProperty,
          SuperSeparatorProperty,
          SeparatorConfigOverride
        > {
  SeparatorConfigStates({
    super.binding,
    super.named,
    super.namedProperties,
    super.hover,
    super.selected,
    super.automatic,
    super.order,
  }) : super(context: 'Separator', toLeaf: _separatorStateLeaf);

  static const hoverKey = ComponentStateHelpers.hoverKey;
  static const selectedKey = ComponentStateHelpers.selectedKey;

  @override
  SuperSeparatorConfig clearStatesOf(SuperSeparatorConfig base) =>
      base.copyWith(clearStates: true);

  @override
  SeparatorConfigOverride buildOverride(
    SuperSeparatorConfig config,
    Set<SeparatorStateProperty> properties,
  ) => SeparatorConfigOverride(config: config, properties: properties);

  SeparatorConfigStates copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<String, SuperSeparatorConfig>? named,
    Map<String, Set<SeparatorStateProperty>>? namedProperties,
    bool clearNamed = false,
    SeparatorConfigOverride? hover,
    bool clearHover = false,
    SeparatorConfigOverride? selected,
    bool clearSelected = false,
    Map<AutomaticState, SeparatorConfigOverride>? automatic,
    List<String>? order,
    bool clearOrder = false,
  }) {
    final nextNamed = clearNamed
        ? <String, SuperSeparatorConfig>{}
        : named ?? this.named;
    return SeparatorConfigStates(
      binding: clearBinding ? null : binding ?? this.binding,
      named: nextNamed,
      namedProperties:
          namedProperties ??
          {
            for (final name in nextNamed.keys)
              name: this.namedProperties[name] ?? {},
          },
      hover: clearHover ? null : hover ?? this.hover,
      selected: clearSelected ? null : selected ?? this.selected,
      automatic: automatic ?? this.automatic,
      order: clearOrder
          ? null
          : order ??
                ComponentStateHelpers.filterCopiedOrder(
                  this.order,
                  (automatic ?? this.automatic).keys,
                  nextNamed,
                ),
    );
  }

  void _validateAgainst(SuperSeparatorConfig base) =>
      validateStatesAgainst(base, (c) => c._validateLeaf());

  factory SeparatorConfigStates.fromJson(Object? value) =>
      ComponentStateHelpers.parseStatesJson(
        value: value,
        context: 'Separator',
        readLeaf: _readSeparatorStateLeaf,
        parseOverride: SeparatorConfigOverride.fromJson,
        build: SeparatorConfigStates.new,
      );
}

SuperSeparatorConfig _separatorStateLeaf(SuperSeparatorConfig config) =>
    ComponentStateHelpers.ensureStateLeaf(
      config,
      states: config.states,
      normalize: (c) => c.copyWith(
        propertyBindings: Map.unmodifiable(c.propertyBindings),
      ),
      context: 'Separator',
    );

SuperSeparatorConfig _readSeparatorStateLeaf(Object? value) =>
    ComponentStateHelpers.readStateLeaf(
      value,
      fromJson: SuperSeparatorConfig.fromJson,
      toLeaf: _separatorStateLeaf,
      context: 'Separator',
    );
