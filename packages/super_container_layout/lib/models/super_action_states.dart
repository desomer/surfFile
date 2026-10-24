part of 'super_action_config.dart';

enum ActionStateProperty {
  content('Type et variante', [
    'kind',
    'variant',
    'iconPosition',
    'iconSpacing',
  ]),
  textLabel('Libellé', ['label'], SuperActionProperty.label),
  tooltip('Infobulle', ['tooltip'], SuperActionProperty.tooltip),
  icon('Icône', ['icon'], SuperActionProperty.icon),
  enabled('Activation', ['enabled'], SuperActionProperty.enabled),
  fontFamily('Police', ['fontFamily'], SuperActionProperty.fontFamily),
  fontSize('Taille du texte', ['fontSize'], SuperActionProperty.fontSize),
  iconSize('Taille de l’icône', ['iconSize'], SuperActionProperty.iconSize),
  fontWeight('Graisse', ['fontWeight'], SuperActionProperty.fontWeight),
  italic('Italique', ['italic'], SuperActionProperty.italic),
  color('Couleur du contenu', ['color'], SuperActionProperty.color),
  iconColor('Couleur de l’icône', ['iconColor'], SuperActionProperty.iconColor),
  backgroundColor('Couleur de fond', [
    'backgroundColor',
  ], SuperActionProperty.backgroundColor),
  borderColor('Couleur de bordure', [
    'borderColor',
  ], SuperActionProperty.borderColor),
  radius('Rayon', ['radius'], SuperActionProperty.radius),
  borderWidth('Épaisseur de bordure', [
    'borderWidth',
  ], SuperActionProperty.borderWidth),
  elevation('Élévation', ['elevation'], SuperActionProperty.elevation),
  padding('Marges internes', ['horizontalPadding', 'verticalPadding']),
  textAlign('Alignement', ['textAlign'], SuperActionProperty.textAlign),
  letterSpacing('Espacement des lettres', ['letterSpacing']),
  style('Style de surface', ['style']);

  const ActionStateProperty(this.label, this.keys, [this.bindingProperty]);

  final String label;
  final List<String> keys;
  final SuperActionProperty? bindingProperty;
}

@immutable
class ActionConfigOverride {
  ActionConfigOverride({
    SuperActionConfig config = const SuperActionConfig(),
    Set<ActionStateProperty> properties = const {},
  }) : config = _actionStateLeaf(config),
       properties = Set.unmodifiable(properties);

  final SuperActionConfig config;
  final Set<ActionStateProperty> properties;
  bool get isEmpty => properties.isEmpty;

  ActionConfigOverride copyWith({
    SuperActionConfig? config,
    Set<ActionStateProperty>? properties,
    bool clearProperties = false,
  }) => ActionConfigOverride(
    config: config ?? this.config,
    properties: clearProperties ? const {} : properties ?? this.properties,
  );

  ActionConfigOverride edited(SuperActionConfig next) {
    final leaf = _actionStateLeaf(next);
    final before = config.toJson();
    final after = leaf.toJson();
    return ActionConfigOverride(
      config: leaf,
      properties: {
        ...properties,
        for (final property in ActionStateProperty.values)
          if (property.keys.any(
                (key) => !_sameActionStateValue(before[key], after[key]),
              ) ||
              (property.bindingProperty != null &&
                  config.propertyBindings[property.bindingProperty] !=
                      leaf.propertyBindings[property.bindingProperty]))
            property,
      },
    );
  }

  SuperActionConfig apply(SuperActionConfig base) {
    final bindings = Map<SuperActionProperty, JsonTextBinding>.of(
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
    bool has(ActionStateProperty property) => properties.contains(property);
    final content = has(ActionStateProperty.content) ? config : base;
    final pad = has(ActionStateProperty.padding) ? config : base;
    final result = SuperActionConfig(
      kind: content.kind,
      variant: content.variant,
      iconPosition: content.iconPosition,
      iconSpacing: content.iconSpacing,
      label: has(ActionStateProperty.textLabel) ? config.label : base.label,
      tooltip: has(ActionStateProperty.tooltip) ? config.tooltip : base.tooltip,
      icon: has(ActionStateProperty.icon) ? config.icon : base.icon,
      enabled: has(ActionStateProperty.enabled) ? config.enabled : base.enabled,
      fontFamily: has(ActionStateProperty.fontFamily)
          ? config.fontFamily
          : base.fontFamily,
      fontSize: has(ActionStateProperty.fontSize)
          ? config.fontSize
          : base.fontSize,
      iconSize: has(ActionStateProperty.iconSize)
          ? config.iconSize
          : base.iconSize,
      fontWeight: has(ActionStateProperty.fontWeight)
          ? config.fontWeight
          : base.fontWeight,
      italic: has(ActionStateProperty.italic) ? config.italic : base.italic,
      color: has(ActionStateProperty.color) ? config.color : base.color,
      iconColor: has(ActionStateProperty.iconColor)
          ? config.iconColor
          : base.iconColor,
      backgroundColor: has(ActionStateProperty.backgroundColor)
          ? config.backgroundColor
          : base.backgroundColor,
      borderColor: has(ActionStateProperty.borderColor)
          ? config.borderColor
          : base.borderColor,
      radius: has(ActionStateProperty.radius) ? config.radius : base.radius,
      borderWidth: has(ActionStateProperty.borderWidth)
          ? config.borderWidth
          : base.borderWidth,
      elevation: has(ActionStateProperty.elevation)
          ? config.elevation
          : base.elevation,
      horizontalPadding: pad.horizontalPadding,
      verticalPadding: pad.verticalPadding,
      textAlign: has(ActionStateProperty.textAlign)
          ? config.textAlign
          : base.textAlign,
      letterSpacing: has(ActionStateProperty.letterSpacing)
          ? config.letterSpacing
          : base.letterSpacing,
      style: has(ActionStateProperty.style) ? config.style : base.style,
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

  factory ActionConfigOverride.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any((key) => key != 'config' && key != 'properties') ||
        value['properties'] is! List) {
      throw const FormatException('Invalid Action override.');
    }
    final properties = <ActionStateProperty>{};
    for (final name in value['properties'] as List) {
      final property = ActionStateProperty.values
          .where((property) => property.name == name)
          .firstOrNull;
      if (property == null || !properties.add(property)) {
        throw const FormatException('Invalid Action override property.');
      }
    }
    return ActionConfigOverride(
      config: _readActionStateLeaf(value['config']),
      properties: properties,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ActionConfigOverride &&
      config == other.config &&
      setEquals(properties, other.properties);

  @override
  int get hashCode => Object.hash(config, Object.hashAllUnordered(properties));
}

@immutable
class ActionConfigStates {
  ActionConfigStates({
    this.binding,
    Map<String, SuperActionConfig> named = const {},
    Map<String, Set<ActionStateProperty>> namedProperties = const {},
    this.hover,
    this.selected,
    Map<AutomaticState, ActionConfigOverride> automatic = const {},
    List<String>? order,
  }) : named = Map.unmodifiable({
         for (final entry in named.entries)
           _actionStateName(entry.key): _actionStateLeaf(entry.value),
       }),
       automatic = Map.unmodifiable(automatic),
       namedProperties = Map.unmodifiable({
         for (final name in named.keys)
           name: Set<ActionStateProperty>.unmodifiable(
             namedProperties[name] ?? {},
           ),
       }),
       order = List.unmodifiable(
         _actionStateOrder(named.keys, order, automatic.keys),
       ) {
    binding?.validate();
    if (namedProperties.keys.any((name) => !named.containsKey(name))) {
      throw const FormatException('Unknown named Action override.');
    }
    if (automatic.keys.any(
      (s) => s == AutomaticState.hover || s == AutomaticState.selected,
    )) {
      throw const FormatException('Duplicate automatic Action state.');
    }
  }

  static const hoverKey = '\u0000hover';
  static const selectedKey = '\u0000selected';

  final JsonTextBinding? binding;
  final Map<String, SuperActionConfig> named;
  final Map<String, Set<ActionStateProperty>> namedProperties;
  final ActionConfigOverride? hover;
  final ActionConfigOverride? selected;
  final Map<AutomaticState, ActionConfigOverride> automatic;
  final List<String> order;

  ActionConfigStates copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<String, SuperActionConfig>? named,
    Map<String, Set<ActionStateProperty>>? namedProperties,
    bool clearNamed = false,
    ActionConfigOverride? hover,
    bool clearHover = false,
    ActionConfigOverride? selected,
    bool clearSelected = false,
    Map<AutomaticState, ActionConfigOverride>? automatic,
    List<String>? order,
    bool clearOrder = false,
  }) {
    final nextNamed = clearNamed
        ? <String, SuperActionConfig>{}
        : named ?? this.named;
    return ActionConfigStates(
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
                this.order
                    .where(
                      (key) =>
                          key == hoverKey ||
                          key == selectedKey ||
                          (automatic ?? this.automatic).keys.any(
                            (s) => s.key == key,
                          ) ||
                          nextNamed.containsKey(key),
                    )
                    .toList(),
    );
  }

  SuperActionConfig resolve(
    SuperActionConfig base, {
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
        result = ActionConfigOverride(
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

  void _validateAgainst(SuperActionConfig base) {
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

  factory ActionConfigStates.fromJson(Object? value) {
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
      throw const FormatException('Invalid Action states.');
    }
    final named = <String, SuperActionConfig>{};
    for (final entry in (value['named'] as Map).entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid Action state name.');
      }
      named[_actionStateName(entry.key as String)] = _readActionStateLeaf(
        entry.value,
      );
    }
    try {
      return ActionConfigStates(
        binding: value['binding'] == null
            ? null
            : JsonTextBinding.fromJson(value['binding']),
        named: named,
        namedProperties: _readActionNamedProperties(
          value['namedProperties'],
          named,
        ),
        hover: value.containsKey('hover')
            ? ActionConfigOverride.fromJson(value['hover'])
            : null,
        selected: value.containsKey('selected')
            ? ActionConfigOverride.fromJson(value['selected'])
            : null,
        automatic: _readActionAutomatic(value['automatic']),
        order: (value['order'] as List?)?.cast<String>(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid Action states.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ActionConfigStates &&
      binding == other.binding &&
      mapEquals(named, other.named) &&
      namedProperties.length == other.namedProperties.length &&
      namedProperties.entries.every(
        (e) => setEquals(e.value, other.namedProperties[e.key]),
      ) &&
      hover == other.hover &&
      selected == other.selected &&
      mapEquals(automatic, other.automatic) &&
      listEquals(order, other.order);

  @override
  int get hashCode => Object.hash(
    binding,
    Object.hashAllUnordered(
      named.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      namedProperties.entries.map(
        (e) => Object.hash(e.key, Object.hashAllUnordered(e.value)),
      ),
    ),
    hover,
    selected,
    Object.hashAllUnordered(
      automatic.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAll(order),
  );
}

Map<String, Set<ActionStateProperty>> _readActionNamedProperties(
  Object? value,
  Map<String, SuperActionConfig> named,
) {
  if (value == null) return {};
  if (value is! Map || value.keys.any((key) => !named.containsKey(key))) {
    throw const FormatException('Invalid named Action overrides.');
  }
  return {
    for (final entry in value.entries)
      entry.key as String: ActionConfigOverride.fromJson({
        'config': named[entry.key]!.toJson(),
        'properties': entry.value,
      }).properties,
  };
}

Map<AutomaticState, ActionConfigOverride> _readActionAutomatic(Object? value) {
  if (value == null) return {};
  if (value is! Map) {
    throw const FormatException('Invalid automatic Action states.');
  }
  return {
    for (final entry in value.entries)
      (AutomaticState.values
                  .where(
                    (s) =>
                        s.name == entry.key &&
                        s != AutomaticState.hover &&
                        s != AutomaticState.selected,
                  )
                  .firstOrNull ??
              (throw const FormatException('Unknown automatic Action state.'))):
          ActionConfigOverride.fromJson(entry.value),
  };
}

SuperActionConfig _actionStateLeaf(SuperActionConfig config) {
  if (config.states != null) {
    throw const FormatException('Action states cannot contain nested states.');
  }
  return config.copyWith(
    propertyBindings: Map.unmodifiable(config.propertyBindings),
  );
}

SuperActionConfig _readActionStateLeaf(Object? value) {
  if (value is! Map || value.containsKey('states')) {
    throw const FormatException('Invalid or nested Action state.');
  }
  return _actionStateLeaf(SuperActionConfig.fromJson(value));
}

String _actionStateName(String name) {
  if (name.isEmpty ||
      name.trim() != name ||
      name.contains('\u0000') ||
      {
        'default',
        'selected',
        'hover',
        'hovered',
        'par défaut',
        'par defaut',
        'sélectionné',
        'selectionne',
        'survol',
      }.contains(name.toLowerCase())) {
    throw const FormatException('Empty or reserved Action state name.');
  }
  return name;
}

List<String> _actionStateOrder(
  Iterable<String> names,
  List<String>? order,
  Iterable<AutomaticState> automatic,
) {
  final defaults = [
    ...names,
    ActionConfigStates.hoverKey,
    ActionConfigStates.selectedKey,
    ...automatic.map((s) => s.key),
  ];
  if (order == null) return defaults;
  if (order.toSet().length != order.length ||
      order.any((key) => !defaults.contains(key))) {
    throw const FormatException('Invalid Action state order.');
  }
  return [...order, ...defaults.where((key) => !order.contains(key))];
}

bool _sameActionStateValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && _sameActionStateValue(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable.generate(a.length)
            .every((i) => _sameActionStateValue(a[i], b[i]));
  }
  return a == b;
}

int _hashActionStateValue(Object? v) {
  if (v is Map) {
    return Object.hashAllUnordered(
      v.entries.map((e) => Object.hash(e.key, _hashActionStateValue(e.value))),
    );
  }
  if (v is List) {
    return Object.hashAll(v.map(_hashActionStateValue));
  }
  return v.hashCode;
}
