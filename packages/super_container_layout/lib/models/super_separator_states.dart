// Surcharges conditionnelles d'états ([SeparatorConfigStates]) pour un [SuperSeparator].
//
// Permet de modifier sélectivement des groupes de propriétés ([SeparatorStateProperty])
// au survol (`hover`), à la sélection de ligne (`selected`), sur état automatique
// ou sur état métier nommé lié à un repository JSON.
part of 'super_separator_config.dart';

/// Groupes de propriétés de [SuperSeparatorConfig] surchargeables par état.
enum SeparatorStateProperty {
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

  final String label;
  final List<String> keys;
  final SuperSeparatorProperty? bindingProperty;
}

/// Surcharge partielle d'un [SuperSeparatorConfig] associée à une liste explicite de [SeparatorStateProperty].
@immutable
class SeparatorConfigOverride {
  SeparatorConfigOverride({
    SuperSeparatorConfig config = const SuperSeparatorConfig(),
    Set<SeparatorStateProperty> properties = const {},
  }) : config = _separatorStateLeaf(config),
       properties = Set.unmodifiable(properties);

  final SuperSeparatorConfig config;
  final Set<SeparatorStateProperty> properties;
  bool get isEmpty => properties.isEmpty;

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
    final before = config.toJson();
    final after = leaf.toJson();
    return SeparatorConfigOverride(
      config: leaf,
      properties: {
        ...properties,
        for (final property in SeparatorStateProperty.values)
          if (property.keys.any(
                (key) => !ComponentStateHelpers.sameJsonValue(
                  before[key],
                  after[key],
                ),
              ) ||
              (property.bindingProperty != null &&
                  config.propertyBindings[property.bindingProperty] !=
                      leaf.propertyBindings[property.bindingProperty]))
            property,
      },
    );
  }

  SuperSeparatorConfig apply(SuperSeparatorConfig base) {
    final bindings = Map<SuperSeparatorProperty, JsonTextBinding>.of(
      base.propertyBindings,
    );
    for (final property in properties) {
      if (property == SeparatorStateProperty.indents) {
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
      } else if (property.bindingProperty case final target?) {
        final binding = config.propertyBindings[target];
        if (binding == null) {
          bindings.remove(target);
        } else {
          bindings[target] = binding;
        }
      }
    }
    bool has(SeparatorStateProperty property) => properties.contains(property);
    final content = has(SeparatorStateProperty.content) ? config : base;
    final indents = has(SeparatorStateProperty.indents) ? config : base;
    final result = SuperSeparatorConfig(
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
    );
    result._validateLeaf();
    return result;
  }

  Map<String, Object?> toJson() => {
    'config': config.toJson(),
    'properties': properties.map((p) => p.name).toList()..sort(),
  };

  Map<String, Object?> toCompactJson() => {
    'config': config.toCompactJson(),
    'properties': properties.map((p) => p.name).toList()..sort(),
  };

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

  @override
  bool operator ==(Object other) =>
      other is SeparatorConfigOverride &&
      config == other.config &&
      setEquals(properties, other.properties);

  @override
  int get hashCode => Object.hash(config, Object.hashAllUnordered(properties));
}

/// Collection des surcharges d'états (`named`, `hover`, `selected`, `automatic`) d'un [SuperSeparatorConfig].
@immutable
class SeparatorConfigStates {
  SeparatorConfigStates({
    this.binding,
    Map<String, SuperSeparatorConfig> named = const {},
    Map<String, Set<SeparatorStateProperty>> namedProperties = const {},
    this.hover,
    this.selected,
    Map<AutomaticState, SeparatorConfigOverride> automatic = const {},
    List<String>? order,
  }) : named = Map.unmodifiable({
         for (final entry in named.entries)
           _separatorStateName(entry.key): _separatorStateLeaf(entry.value),
       }),
       automatic = Map.unmodifiable(automatic),
       namedProperties = Map.unmodifiable({
         for (final name in named.keys)
           name: Set<SeparatorStateProperty>.unmodifiable(
             namedProperties[name] ?? {},
           ),
       }),
       order = List.unmodifiable(
         ComponentStateHelpers.normalizeStateOrder(
           named.keys,
           order,
           automatic.keys,
           'Separator',
         ),
       ) {
    binding?.validate();
    if (namedProperties.keys.any((name) => !named.containsKey(name))) {
      throw const FormatException('Unknown named Separator override.');
    }
    if (automatic.keys.any(
      (s) => s == AutomaticState.hover || s == AutomaticState.selected,
    )) {
      throw const FormatException('Duplicate automatic Separator state.');
    }
  }

  static const hoverKey = ComponentStateHelpers.hoverKey;
  static const selectedKey = ComponentStateHelpers.selectedKey;

  final JsonTextBinding? binding;
  final Map<String, SuperSeparatorConfig> named;
  final Map<String, Set<SeparatorStateProperty>> namedProperties;
  final SeparatorConfigOverride? hover;
  final SeparatorConfigOverride? selected;
  final Map<AutomaticState, SeparatorConfigOverride> automatic;
  final List<String> order;

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

  SuperSeparatorConfig resolve(
    SuperSeparatorConfig base, {
    String? name,
    bool isHovered = false,
    bool isSelected = false,
    Set<AutomaticState> activeStates = const {},
  }) {
    var result = base.copyWith(clearStates: true);
    for (final key in order) {
      if (key == hoverKey) {
        if (isHovered && hover != null) result = hover!.apply(result);
      } else if (key == selectedKey) {
        if (isSelected && selected != null) result = selected!.apply(result);
      } else if (key == name) {
        result = SeparatorConfigOverride(
          config: named[key]!,
          properties: namedProperties[key]!,
        ).apply(result);
      } else if (AutomaticState.fromKey(key) case final state?) {
        if (activeStates.contains(state)) {
          result = automatic[state]?.apply(result) ?? result;
        }
      }
    }
    return result;
  }

  void _validateAgainst(SuperSeparatorConfig base) {
    binding?.validate();
    for (final config in named.values) {
      config._validateLeaf();
    }
    hover?.config._validateLeaf();
    selected?.config._validateLeaf();
    for (final value in automatic.values) {
      value.config._validateLeaf();
    }
    for (final name in <String?>[null, ...named.keys]) {
      for (final isHovered in [false, true]) {
        for (final isSelected in [false, true]) {
          for (var mask = 0; mask < (1 << automatic.length); mask++) {
            resolve(
              base,
              name: name,
              isHovered: isHovered,
              isSelected: isSelected,
              activeStates: {
                for (var i = 0; i < automatic.length; i++)
                  if (mask & (1 << i) != 0) automatic.keys.elementAt(i),
              },
            )._validateLeaf();
          }
        }
      }
    }
  }

  Map<String, Object?> toJson() => {
    if (binding != null) 'binding': binding!.toJson(),
    'named': {
      for (final entry in named.entries) entry.key: entry.value.toJson(),
    },
    'namedProperties': {
      for (final entry in namedProperties.entries)
        entry.key: entry.value.map((p) => p.name).toList()..sort(),
    },
    if (hover != null) 'hover': hover!.toJson(),
    if (selected != null) 'selected': selected!.toJson(),
    if (automatic.isNotEmpty)
      'automatic': {
        for (final entry in automatic.entries)
          entry.key.name: entry.value.toJson(),
      },
    'order': order,
  };

  Map<String, Object?> toCompactJson() => {
    if (binding != null) 'binding': binding!.toCompactJson(),
    'named': {
      for (final entry in named.entries) entry.key: entry.value.toCompactJson(),
    },
    if (namedProperties.values.any((s) => s.isNotEmpty))
      'namedProperties': {
        for (final entry in namedProperties.entries)
          entry.key: entry.value.map((p) => p.name).toList()..sort(),
      },
    if (hover != null) 'hover': hover!.toCompactJson(),
    if (selected != null) 'selected': selected!.toCompactJson(),
    if (automatic.isNotEmpty)
      'automatic': {
        for (final entry in automatic.entries)
          entry.key.name: entry.value.toCompactJson(),
      },
    'order': order,
  };

  factory SeparatorConfigStates.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any(
          (key) => !{
            'binding',
            'named',
            'namedProperties',
            'hover',
            'selected',
            'automatic',
            'order',
          }.contains(key),
        ) ||
        value['named'] is! Map ||
        (value.containsKey('order') &&
            (value['order'] is! List ||
                (value['order'] as List).any((key) => key is! String)))) {
      throw const FormatException('Invalid Separator states.');
    }
    final named = <String, SuperSeparatorConfig>{};
    for (final entry in (value['named'] as Map).entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid Separator state name.');
      }
      named[_separatorStateName(entry.key as String)] = _readSeparatorStateLeaf(
        entry.value,
      );
    }
    try {
      return SeparatorConfigStates(
        binding: value['binding'] == null
            ? null
            : JsonTextBinding.fromJson(value['binding']),
        named: named,
        namedProperties: _readSeparatorNamedProperties(
          value['namedProperties'],
          named,
        ),
        hover: value.containsKey('hover')
            ? SeparatorConfigOverride.fromJson(value['hover'])
            : null,
        selected: value.containsKey('selected')
            ? SeparatorConfigOverride.fromJson(value['selected'])
            : null,
        automatic: _readSeparatorAutomatic(value['automatic']),
        order: (value['order'] as List?)?.cast<String>(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid Separator states.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SeparatorConfigStates &&
      ComponentStateHelpers.equalsStateCollection(
        bindingA: binding,
        bindingB: other.binding,
        namedA: named,
        namedB: other.named,
        propsA: namedProperties,
        propsB: other.namedProperties,
        hoverA: hover,
        hoverB: other.hover,
        selectedA: selected,
        selectedB: other.selected,
        autoA: automatic,
        autoB: other.automatic,
        orderA: order,
        orderB: other.order,
      );

  @override
  int get hashCode => ComponentStateHelpers.hashStateCollection(
    binding,
    named,
    namedProperties,
    hover,
    selected,
    automatic,
    order,
  );
}

Map<String, Set<SeparatorStateProperty>> _readSeparatorNamedProperties(
  Object? value,
  Map<String, SuperSeparatorConfig> named,
) {
  if (value == null) return {};
  if (value is! Map || value.keys.any((key) => !named.containsKey(key))) {
    throw const FormatException('Invalid named Separator overrides.');
  }
  return {
    for (final entry in value.entries)
      entry.key as String: SeparatorConfigOverride.fromJson({
        'config': named[entry.key]!.toJson(),
        'properties': entry.value,
      }).properties,
  };
}

Map<AutomaticState, SeparatorConfigOverride> _readSeparatorAutomatic(
  Object? value,
) => ComponentStateHelpers.readAutomaticStates(
  value,
  SeparatorConfigOverride.fromJson,
  'Separator',
);

SuperSeparatorConfig _separatorStateLeaf(SuperSeparatorConfig config) {
  if (config.states != null) {
    throw const FormatException(
      'Separator states cannot contain nested states.',
    );
  }
  return config.copyWith(
    propertyBindings: Map.unmodifiable(config.propertyBindings),
  );
}

SuperSeparatorConfig _readSeparatorStateLeaf(Object? value) {
  if (value is! Map || value.containsKey('states')) {
    throw const FormatException('Invalid or nested Separator state.');
  }
  return _separatorStateLeaf(SuperSeparatorConfig.fromJson(value));
}

String _separatorStateName(String name) =>
    ComponentStateHelpers.validateStateName(name, 'Separator');
