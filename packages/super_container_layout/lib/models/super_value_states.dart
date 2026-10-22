part of 'super_value_config.dart';

/// Dependent input settings are atomic. Each bindable property also carries
/// its own entry in [SuperValueConfig.propertyBindings], including its removal.
enum ValueStateProperty {
  content('Contenu et champ', [
    'mode',
    'kind',
    'initialText',
    'initialBool',
    'obscureText',
    'minLines',
    'maxLines',
    'field',
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

  final String label;
  final List<String> keys;
  final SuperValueProperty? bindingProperty;
}

@immutable
class ValueConfigOverride {
  ValueConfigOverride({
    SuperValueConfig config = const SuperValueConfig(),
    Set<ValueStateProperty> properties = const {},
  }) : config = _valueStateLeaf(config),
       properties = Set.unmodifiable(properties);

  final SuperValueConfig config;
  final Set<ValueStateProperty> properties;
  bool get isEmpty => properties.isEmpty;

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
    final before = config.toJson();
    final after = leaf.toJson();
    return ValueConfigOverride(
      config: leaf,
      properties: {
        ...properties,
        for (final property in ValueStateProperty.values)
          if (property.keys.any(
                (key) => !_sameValueStateValue(before[key], after[key]),
              ) ||
              (property.bindingProperty != null &&
                  config.propertyBindings[property.bindingProperty] !=
                      leaf.propertyBindings[property.bindingProperty]))
            property,
      },
    );
  }

  SuperValueConfig apply(SuperValueConfig base) {
    final bindings = Map<SuperValueProperty, JsonTextBinding>.of(
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
    bool has(ValueStateProperty property) => properties.contains(property);
    final content = has(ValueStateProperty.content) ? config : base;
    final interaction = has(ValueStateProperty.enabled) ? config : base;
    final result = SuperValueConfig(
      mode: content.mode,
      kind: content.kind,
      initialText: content.initialText,
      initialBool: content.initialBool,
      obscureText: content.obscureText,
      minLines: content.minLines,
      maxLines: content.maxLines,
      field: content.field,
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
    );
    result._validateLeaf();
    return result;
  }

  Map<String, Object?> toJson() => {
    'config': config.toJson(),
    'properties': properties.map((p) => p.name).toList()..sort(),
  };

  factory ValueConfigOverride.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any((key) => key != 'config' && key != 'properties') ||
        value['properties'] is! List) {
      throw const FormatException('Invalid Value override.');
    }
    final properties = <ValueStateProperty>{};
    for (final name in value['properties'] as List) {
      final property = ValueStateProperty.values
          .where((property) => property.name == name)
          .firstOrNull;
      if (property == null || !properties.add(property)) {
        throw const FormatException('Invalid Value override property.');
      }
    }
    return ValueConfigOverride(
      config: _readValueStateLeaf(value['config']),
      properties: properties,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ValueConfigOverride &&
      config == other.config &&
      setEquals(properties, other.properties);

  @override
  int get hashCode => Object.hash(config, Object.hashAllUnordered(properties));
}

@immutable
class ValueConfigStates {
  ValueConfigStates({
    this.binding,
    Map<String, SuperValueConfig> named = const {},
    Map<String, Set<ValueStateProperty>> namedProperties = const {},
    this.hover,
    this.selected,
    Map<AutomaticState, ValueConfigOverride> automatic = const {},
    List<String>? order,
  }) : named = Map.unmodifiable({
         for (final entry in named.entries)
           _valueStateName(entry.key): _valueStateLeaf(entry.value),
       }),
       automatic = Map.unmodifiable(automatic),
       namedProperties = Map.unmodifiable({
         for (final name in named.keys)
           name: Set<ValueStateProperty>.unmodifiable(
             namedProperties[name] ?? {},
           ),
       }),
       order = List.unmodifiable(
         _valueStateOrder(named.keys, order, automatic.keys),
       ) {
    binding?.validate();
    if (namedProperties.keys.any((name) => !named.containsKey(name))) {
      throw const FormatException('Unknown named Value override.');
    }
    if (automatic.keys.any(
      (s) => s == AutomaticState.hover || s == AutomaticState.selected,
    )) {
      throw const FormatException('Duplicate automatic Value state.');
    }
  }

  static const hoverKey = '\u0000hover';
  static const selectedKey = '\u0000selected';

  final JsonTextBinding? binding;
  final Map<String, SuperValueConfig> named;
  final Map<String, Set<ValueStateProperty>> namedProperties;
  final ValueConfigOverride? hover;
  final ValueConfigOverride? selected;
  final Map<AutomaticState, ValueConfigOverride> automatic;
  final List<String> order;

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

  SuperValueConfig resolve(
    SuperValueConfig base, {
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
        result = ValueConfigOverride(
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

  void _validateAgainst(SuperValueConfig base) {
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

  factory ValueConfigStates.fromJson(Object? value) {
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
      throw const FormatException('Invalid Value states.');
    }
    final named = <String, SuperValueConfig>{};
    for (final entry in (value['named'] as Map).entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid Value state name.');
      }
      named[_valueStateName(entry.key as String)] = _readValueStateLeaf(
        entry.value,
      );
    }
    try {
      return ValueConfigStates(
        binding: value['binding'] == null
            ? null
            : JsonTextBinding.fromJson(value['binding']),
        named: named,
        namedProperties: _readValueNamedProperties(
          value['namedProperties'],
          named,
        ),
        hover: value.containsKey('hover')
            ? ValueConfigOverride.fromJson(value['hover'])
            : null,
        selected: value.containsKey('selected')
            ? ValueConfigOverride.fromJson(value['selected'])
            : null,
        automatic: _readValueAutomatic(value['automatic']),
        order: (value['order'] as List?)?.cast<String>(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid Value states.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ValueConfigStates &&
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

Map<String, Set<ValueStateProperty>> _readValueNamedProperties(
  Object? value,
  Map<String, SuperValueConfig> named,
) {
  if (value == null) return {};
  if (value is! Map || value.keys.any((key) => !named.containsKey(key))) {
    throw const FormatException('Invalid named Value overrides.');
  }
  return {
    for (final entry in value.entries)
      entry.key as String: ValueConfigOverride.fromJson({
        'config': named[entry.key]!.toJson(),
        'properties': entry.value,
      }).properties,
  };
}

Map<AutomaticState, ValueConfigOverride> _readValueAutomatic(Object? value) {
  if (value == null) return {};
  if (value is! Map) {
    throw const FormatException('Invalid automatic Value states.');
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
              (throw const FormatException('Unknown automatic Value state.'))):
          ValueConfigOverride.fromJson(entry.value),
  };
}

SuperValueConfig _valueStateLeaf(SuperValueConfig config) {
  if (config.states != null) {
    throw const FormatException('Value states cannot contain nested states.');
  }
  return config.copyWith(
    propertyBindings: Map.unmodifiable(config.propertyBindings),
  );
}

SuperValueConfig _readValueStateLeaf(Object? value) {
  if (value is! Map<String, dynamic> || value.containsKey('states')) {
    throw const FormatException('Invalid or nested Value state.');
  }
  return _valueStateLeaf(SuperValueConfig.fromJson(value));
}

String _valueStateName(String name) {
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
    throw const FormatException('Empty or reserved Value state name.');
  }
  return name;
}

List<String> _valueStateOrder(
  Iterable<String> names,
  List<String>? order,
  Iterable<AutomaticState> automatic,
) {
  final defaults = [
    ...names,
    ValueConfigStates.hoverKey,
    ValueConfigStates.selectedKey,
    ...automatic.map((s) => s.key),
  ];
  if (order == null) return defaults;
  if (order.toSet().length != order.length ||
      order.any((key) => !defaults.contains(key))) {
    throw const FormatException('Invalid Value state order.');
  }
  return [...order, ...defaults.where((key) => !order.contains(key))];
}

bool _sameValueStateValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && _sameValueStateValue(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable.generate(a.length)
            .every((i) => _sameValueStateValue(a[i], b[i]));
  }
  return a == b;
}
