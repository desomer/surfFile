// Surcharges conditionnelles d'états ([IndicatorConfigStates]) pour un [SuperIndicator].
//
// Permet de modifier sélectivement des groupes de propriétés ([IndicatorStateProperty])
// au survol (`hover`), à la sélection de ligne (`selected`), sur état automatique
// ou sur état métier nommé lié à un repository JSON.
part of 'super_indicator_config.dart';

/// Groupes de propriétés de [SuperIndicatorConfig] surchargeables par état.
enum IndicatorStateProperty {
  content('Disposition', ['iconPosition', 'iconSpacing']),
  icon('Icône', ['icon'], SuperIndicatorProperty.icon),
  textLabel('Libellé', ['label'], SuperIndicatorProperty.label),
  tooltip('Infobulle', ['tooltip'], SuperIndicatorProperty.tooltip),
  enabled('Activation', ['enabled'], SuperIndicatorProperty.enabled),
  fontFamily('Police', ['fontFamily'], SuperIndicatorProperty.fontFamily),
  fontSize('Taille du texte', ['fontSize'], SuperIndicatorProperty.fontSize),
  iconSize('Taille de l’icône', ['iconSize'], SuperIndicatorProperty.iconSize),
  fontWeight('Graisse', ['fontWeight'], SuperIndicatorProperty.fontWeight),
  italic('Italique', ['italic'], SuperIndicatorProperty.italic),
  color('Couleur du contenu', ['color'], SuperIndicatorProperty.color),
  iconColor('Couleur de l’icône', [
    'iconColor',
  ], SuperIndicatorProperty.iconColor),
  backgroundColor('Couleur de fond', [
    'backgroundColor',
  ], SuperIndicatorProperty.backgroundColor),
  borderColor('Couleur de bordure', [
    'borderColor',
  ], SuperIndicatorProperty.borderColor),
  radius('Rayon', ['radius'], SuperIndicatorProperty.radius),
  borderWidth('Épaisseur de bordure', [
    'borderWidth',
  ], SuperIndicatorProperty.borderWidth),
  elevation('Élévation', ['elevation'], SuperIndicatorProperty.elevation),
  padding('Marges internes', ['horizontalPadding', 'verticalPadding']),
  textAlign('Alignement', ['textAlign'], SuperIndicatorProperty.textAlign),
  letterSpacing('Espacement des lettres', ['letterSpacing']),
  style('Style de surface', ['style']);

  const IndicatorStateProperty(this.label, this.keys, [this.bindingProperty]);

  final String label;
  final List<String> keys;
  final SuperIndicatorProperty? bindingProperty;
}

/// Surcharge partielle d'un [SuperIndicatorConfig] associée à une liste explicite de [IndicatorStateProperty].
@immutable
class IndicatorConfigOverride {
  IndicatorConfigOverride({
    SuperIndicatorConfig config = const SuperIndicatorConfig(),
    Set<IndicatorStateProperty> properties = const {},
  }) : config = _indicatorStateLeaf(config),
       properties = Set.unmodifiable(properties);

  final SuperIndicatorConfig config;
  final Set<IndicatorStateProperty> properties;
  bool get isEmpty => properties.isEmpty;

  IndicatorConfigOverride copyWith({
    SuperIndicatorConfig? config,
    Set<IndicatorStateProperty>? properties,
    bool clearProperties = false,
  }) => IndicatorConfigOverride(
    config: config ?? this.config,
    properties: clearProperties ? const {} : properties ?? this.properties,
  );

  IndicatorConfigOverride edited(SuperIndicatorConfig next) {
    final leaf = _indicatorStateLeaf(next);
    final before = config.toJson();
    final after = leaf.toJson();
    return IndicatorConfigOverride(
      config: leaf,
      properties: {
        ...properties,
        for (final property in IndicatorStateProperty.values)
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

  SuperIndicatorConfig apply(SuperIndicatorConfig base) {
    final bindings = Map<SuperIndicatorProperty, JsonTextBinding>.of(
      base.propertyBindings,
    );
    for (final property in properties) {
      final target = property.bindingProperty;
      if (target != null) {
        final binding = config.propertyBindings[target];
        if (binding == null) {
          bindings.remove(target);
        } else {
          bindings[target] = binding;
        }
      }
    }
    bool has(IndicatorStateProperty property) => properties.contains(property);
    final content = has(IndicatorStateProperty.content) ? config : base;
    final pad = has(IndicatorStateProperty.padding) ? config : base;
    final result = SuperIndicatorConfig(
      iconPosition: content.iconPosition,
      iconSpacing: content.iconSpacing,
      icon: has(IndicatorStateProperty.icon) ? config.icon : base.icon,
      label: has(IndicatorStateProperty.textLabel) ? config.label : base.label,
      tooltip: has(IndicatorStateProperty.tooltip)
          ? config.tooltip
          : base.tooltip,
      enabled: has(IndicatorStateProperty.enabled)
          ? config.enabled
          : base.enabled,
      fontFamily: has(IndicatorStateProperty.fontFamily)
          ? config.fontFamily
          : base.fontFamily,
      fontSize: has(IndicatorStateProperty.fontSize)
          ? config.fontSize
          : base.fontSize,
      iconSize: has(IndicatorStateProperty.iconSize)
          ? config.iconSize
          : base.iconSize,
      fontWeight: has(IndicatorStateProperty.fontWeight)
          ? config.fontWeight
          : base.fontWeight,
      italic: has(IndicatorStateProperty.italic) ? config.italic : base.italic,
      color: has(IndicatorStateProperty.color) ? config.color : base.color,
      iconColor: has(IndicatorStateProperty.iconColor)
          ? config.iconColor
          : base.iconColor,
      backgroundColor: has(IndicatorStateProperty.backgroundColor)
          ? config.backgroundColor
          : base.backgroundColor,
      borderColor: has(IndicatorStateProperty.borderColor)
          ? config.borderColor
          : base.borderColor,
      radius: has(IndicatorStateProperty.radius) ? config.radius : base.radius,
      borderWidth: has(IndicatorStateProperty.borderWidth)
          ? config.borderWidth
          : base.borderWidth,
      elevation: has(IndicatorStateProperty.elevation)
          ? config.elevation
          : base.elevation,
      horizontalPadding: pad.horizontalPadding,
      verticalPadding: pad.verticalPadding,
      textAlign: has(IndicatorStateProperty.textAlign)
          ? config.textAlign
          : base.textAlign,
      letterSpacing: has(IndicatorStateProperty.letterSpacing)
          ? config.letterSpacing
          : base.letterSpacing,
      style: has(IndicatorStateProperty.style) ? config.style : base.style,
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

  factory IndicatorConfigOverride.fromJson(Object? value) {
    final properties = ComponentStateHelpers.parseOverrideProperties(
      value,
      IndicatorStateProperty.values,
      'Indicator',
    );
    return IndicatorConfigOverride(
      config: _readIndicatorStateLeaf((value as Map)['config']),
      properties: properties,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IndicatorConfigOverride &&
      config == other.config &&
      setEquals(properties, other.properties);

  @override
  int get hashCode => Object.hash(config, Object.hashAllUnordered(properties));
}

/// Collection des surcharges d'états (`named`, `hover`, `selected`, `automatic`) d'un [SuperIndicatorConfig].
@immutable
class IndicatorConfigStates {
  IndicatorConfigStates({
    this.binding,
    Map<String, SuperIndicatorConfig> named = const {},
    Map<String, Set<IndicatorStateProperty>> namedProperties = const {},
    this.hover,
    this.selected,
    Map<AutomaticState, IndicatorConfigOverride> automatic = const {},
    List<String>? order,
  }) : named = Map.unmodifiable({
         for (final entry in named.entries)
           _indicatorStateName(entry.key): _indicatorStateLeaf(entry.value),
       }),
       automatic = Map.unmodifiable(automatic),
       namedProperties = Map.unmodifiable({
         for (final name in named.keys)
           name: Set<IndicatorStateProperty>.unmodifiable(
             namedProperties[name] ?? {},
           ),
       }),
       order = List.unmodifiable(
         ComponentStateHelpers.normalizeStateOrder(
           named.keys,
           order,
           automatic.keys,
           'Indicator',
         ),
       ) {
    binding?.validate();
    if (namedProperties.keys.any((name) => !named.containsKey(name))) {
      throw const FormatException('Unknown named Indicator override.');
    }
    if (automatic.keys.any(
      (s) => s == AutomaticState.hover || s == AutomaticState.selected,
    )) {
      throw const FormatException('Duplicate automatic Indicator state.');
    }
  }

  static const hoverKey = ComponentStateHelpers.hoverKey;
  static const selectedKey = ComponentStateHelpers.selectedKey;

  final JsonTextBinding? binding;
  final Map<String, SuperIndicatorConfig> named;
  final Map<String, Set<IndicatorStateProperty>> namedProperties;
  final IndicatorConfigOverride? hover;
  final IndicatorConfigOverride? selected;
  final Map<AutomaticState, IndicatorConfigOverride> automatic;
  final List<String> order;

  IndicatorConfigStates copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<String, SuperIndicatorConfig>? named,
    Map<String, Set<IndicatorStateProperty>>? namedProperties,
    bool clearNamed = false,
    IndicatorConfigOverride? hover,
    bool clearHover = false,
    IndicatorConfigOverride? selected,
    bool clearSelected = false,
    Map<AutomaticState, IndicatorConfigOverride>? automatic,
    List<String>? order,
    bool clearOrder = false,
  }) {
    final nextNamed = clearNamed
        ? <String, SuperIndicatorConfig>{}
        : named ?? this.named;
    return IndicatorConfigStates(
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

  SuperIndicatorConfig resolve(
    SuperIndicatorConfig base, {
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
        result = IndicatorConfigOverride(
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

  void _validateAgainst(SuperIndicatorConfig base) {
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

  factory IndicatorConfigStates.fromJson(Object? value) {
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
      throw const FormatException('Invalid Indicator states.');
    }
    final named = <String, SuperIndicatorConfig>{};
    for (final entry in (value['named'] as Map).entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid Indicator state name.');
      }
      named[_indicatorStateName(entry.key as String)] = _readIndicatorStateLeaf(
        entry.value,
      );
    }
    try {
      return IndicatorConfigStates(
        binding: value['binding'] == null
            ? null
            : JsonTextBinding.fromJson(value['binding']),
        named: named,
        namedProperties: _readIndicatorNamedProperties(
          value['namedProperties'],
          named,
        ),
        hover: value.containsKey('hover')
            ? IndicatorConfigOverride.fromJson(value['hover'])
            : null,
        selected: value.containsKey('selected')
            ? IndicatorConfigOverride.fromJson(value['selected'])
            : null,
        automatic: _readIndicatorAutomatic(value['automatic']),
        order: (value['order'] as List?)?.cast<String>(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid Indicator states.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is IndicatorConfigStates &&
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

Map<String, Set<IndicatorStateProperty>> _readIndicatorNamedProperties(
  Object? value,
  Map<String, SuperIndicatorConfig> named,
) {
  if (value == null) return {};
  if (value is! Map || value.keys.any((key) => !named.containsKey(key))) {
    throw const FormatException('Invalid named Indicator overrides.');
  }
  return {
    for (final entry in value.entries)
      entry.key as String: IndicatorConfigOverride.fromJson({
        'config': named[entry.key]!.toJson(),
        'properties': entry.value,
      }).properties,
  };
}

Map<AutomaticState, IndicatorConfigOverride> _readIndicatorAutomatic(
  Object? value,
) => ComponentStateHelpers.readAutomaticStates(
  value,
  IndicatorConfigOverride.fromJson,
  'Indicator',
);

SuperIndicatorConfig _indicatorStateLeaf(SuperIndicatorConfig config) {
  if (config.states != null) {
    throw const FormatException(
      'Indicator states cannot contain nested states.',
    );
  }
  return config.copyWith(
    propertyBindings: Map.unmodifiable(config.propertyBindings),
  );
}

SuperIndicatorConfig _readIndicatorStateLeaf(Object? value) {
  if (value is! Map || value.containsKey('states')) {
    throw const FormatException('Invalid or nested Indicator state.');
  }
  return _indicatorStateLeaf(SuperIndicatorConfig.fromJson(value));
}

String _indicatorStateName(String name) =>
    ComponentStateHelpers.validateStateName(name, 'Indicator');
