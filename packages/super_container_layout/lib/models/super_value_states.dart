// Surcharges conditionnelles d'états ([ValueConfigStates]) pour un [SuperValue].
//
// Applique des surcharges partielles ([ValueConfigOverride]) par groupes de
// propriétés selon les états `hover`, `selected`, `automatic` et `named`.
part of 'super_value_config.dart';

/// Dependent input settings are atomic. Each bindable property also carries
/// its own entry in [SuperValueConfig.propertyBindings], including its removal.
enum ValueStateProperty implements ComponentStateProperty<SuperValueProperty> {
  content('Contenu et champ', [
    'mode',
    'kind',
    'initialText',
    'initialBool',
    'obscureText',
    'minLines',
    'maxLines',
    'field',
    'choice',
  ]),
  textLabel('Libellé', ['label'], SuperValueProperty.label),
  placeholder('Placeholder', ['placeholder'], SuperValueProperty.placeholder),
  enabled('Activation et lecture seule', ['enabled', 'readOnly']),
  fontFamily('Police', ['fontFamily'], SuperValueProperty.fontFamily),
  fontSize('Taille du texte', ['fontSize'], SuperValueProperty.fontSize),
  fontWeight('Graisse', ['fontWeight'], SuperValueProperty.fontWeight),
  italic('Italique', ['italic'], SuperValueProperty.italic),
  color('Couleur', ['color'], SuperValueProperty.color),
  textAlign('Alignement', ['textAlign'], SuperValueProperty.textAlign),
  lineHeight('Interligne', ['lineHeight']),
  letterSpacing('Espacement des lettres', ['letterSpacing']),
  binding('Liaison du contenu', ['binding']);

  const ValueStateProperty(this.label, this.keys, [this.bindingProperty]);

  @override
  final String label;
  @override
  final List<String> keys;
  @override
  final SuperValueProperty? bindingProperty;
}

/// Surcharge partielle d'un [SuperValueConfig] appliquée lorsqu'un état est actif.
@immutable
class ValueConfigOverride
    extends
        ComponentConfigOverrideBase<
          SuperValueConfig,
          ValueStateProperty,
          SuperValueProperty
        > {
  ValueConfigOverride({
    SuperValueConfig config = const SuperValueConfig(),
    super.properties,
  }) : super(config: _valueStateLeaf(config));

  ValueConfigOverride copyWith({
    SuperValueConfig? config,
    Set<ValueStateProperty>? properties,
    bool clearProperties = false,
  }) => ValueConfigOverride(
    config: config ?? this.config,
    properties: clearProperties ? const {} : properties ?? this.properties,
  );

  ValueConfigOverride edited(SuperValueConfig next) {
    final leaf = _valueStateLeaf(next);
    return ValueConfigOverride(
      config: leaf,
      properties: computeEditedProperties(
        leaf,
        ValueStateProperty.values,
        (c) => c.propertyBindings,
      ),
    );
  }

  @override
  SuperValueConfig apply(SuperValueConfig base) {
    final bindings = mergePropertyBindings(base, (c) => c.propertyBindings);
    bool has(ValueStateProperty property) => properties.contains(property);
    final content = has(ValueStateProperty.content) ? config : base;
    final interaction = has(ValueStateProperty.enabled) ? config : base;
    return SuperValueConfig(
      mode: content.mode,
      kind: content.kind,
      initialText: content.initialText,
      initialBool: content.initialBool,
      obscureText: content.obscureText,
      minLines: content.minLines,
      maxLines: content.maxLines,
      field: content.field,
      choice: content.choice,
      label: has(ValueStateProperty.textLabel) ? config.label : base.label,
      placeholder: has(ValueStateProperty.placeholder)
          ? config.placeholder
          : base.placeholder,
      enabled: interaction.enabled,
      readOnly: interaction.readOnly,
      fontFamily: has(ValueStateProperty.fontFamily)
          ? config.fontFamily
          : base.fontFamily,
      fontSize: has(ValueStateProperty.fontSize)
          ? config.fontSize
          : base.fontSize,
      fontWeight: has(ValueStateProperty.fontWeight)
          ? config.fontWeight
          : base.fontWeight,
      italic: has(ValueStateProperty.italic) ? config.italic : base.italic,
      color: has(ValueStateProperty.color) ? config.color : base.color,
      textAlign: has(ValueStateProperty.textAlign)
          ? config.textAlign
          : base.textAlign,
      lineHeight: has(ValueStateProperty.lineHeight)
          ? config.lineHeight
          : base.lineHeight,
      letterSpacing: has(ValueStateProperty.letterSpacing)
          ? config.letterSpacing
          : base.letterSpacing,
      binding: has(ValueStateProperty.binding) ? config.binding : base.binding,
      propertyBindings: Map.unmodifiable(bindings),
    ).._validateLeaf();
  }

  factory ValueConfigOverride.fromJson(Object? value) {
    final properties = ComponentStateHelpers.parseOverrideProperties(
      value,
      ValueStateProperty.values,
      'Value',
    );
    return ValueConfigOverride(
      config: _readValueStateLeaf((value as Map)['config']),
      properties: properties,
    );
  }
}

/// Collection des surcharges d'états (`named`, `hover`, `selected`, `automatic`) d'un [SuperValueConfig].
@immutable
class ValueConfigStates
    extends
        ComponentConfigStatesBase<
          SuperValueConfig,
          ValueStateProperty,
          SuperValueProperty,
          ValueConfigOverride
        > {
  ValueConfigStates({
    super.binding,
    super.named,
    super.namedProperties,
    super.hover,
    super.selected,
    super.automatic,
    super.order,
  }) : super(context: 'Value', toLeaf: _valueStateLeaf);

  static const hoverKey = ComponentStateHelpers.hoverKey;
  static const selectedKey = ComponentStateHelpers.selectedKey;

  @override
  SuperValueConfig clearStatesOf(SuperValueConfig base) =>
      base.copyWith(clearStates: true);

  @override
  ValueConfigOverride buildOverride(
    SuperValueConfig config,
    Set<ValueStateProperty> properties,
  ) => ValueConfigOverride(config: config, properties: properties);

  ValueConfigStates copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<String, SuperValueConfig>? named,
    Map<String, Set<ValueStateProperty>>? namedProperties,
    bool clearNamed = false,
    ValueConfigOverride? hover,
    bool clearHover = false,
    ValueConfigOverride? selected,
    bool clearSelected = false,
    Map<AutomaticState, ValueConfigOverride>? automatic,
    List<String>? order,
    bool clearOrder = false,
  }) {
    final nextNamed = clearNamed
        ? <String, SuperValueConfig>{}
        : named ?? this.named;
    return ValueConfigStates(
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

  void _validateAgainst(SuperValueConfig base) =>
      validateStatesAgainst(base, (c) => c._validateLeaf());

  factory ValueConfigStates.fromJson(Object? value) =>
      ComponentStateHelpers.parseStatesJson(
        value: value,
        context: 'Value',
        readLeaf: _readValueStateLeaf,
        parseOverride: ValueConfigOverride.fromJson,
        build: ValueConfigStates.new,
      );
}

SuperValueConfig _valueStateLeaf(SuperValueConfig config) =>
    ComponentStateHelpers.ensureStateLeaf(
      config,
      states: config.states,
      normalize: (c) => c.copyWith(
        propertyBindings: Map.unmodifiable(c.propertyBindings),
      ),
      context: 'Value',
    );

SuperValueConfig _readValueStateLeaf(Object? value) =>
    ComponentStateHelpers.readStateLeaf(
      value,
      fromJson: SuperValueConfig.fromJson,
      toLeaf: _valueStateLeaf,
      context: 'Value',
    );
