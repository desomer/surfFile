part of 'super_text_config.dart';

/// Dependent input settings are atomic. Each bindable property also carries
/// its own entry in [SuperTextConfig.propertyBindings], including its removal.
enum TextStateProperty {
  content('Contenu et champ', [
    'mode',
    'initialText',
    'obscureText',
    'minLines',
    'maxLines',
    'field',
  ]),
  textLabel('Libellé', ['label'], SuperTextProperty.label),
  placeholder('Placeholder', ['placeholder'], SuperTextProperty.placeholder),
  enabled('Activation et lecture seule', ['enabled', 'readOnly']),
  fontFamily('Police', ['fontFamily'], SuperTextProperty.fontFamily),
  fontSize('Taille du texte', ['fontSize'], SuperTextProperty.fontSize),
  fontWeight('Graisse', ['fontWeight'], SuperTextProperty.fontWeight),
  italic('Italique', ['italic'], SuperTextProperty.italic),
  color('Couleur', ['color'], SuperTextProperty.color),
  textAlign('Alignement', ['textAlign'], SuperTextProperty.textAlign),
  lineHeight('Interligne', ['lineHeight']),
  letterSpacing('Espacement des lettres', ['letterSpacing']),
  binding('Liaison du contenu', ['binding']);

  const TextStateProperty(this.label, this.keys, [this.bindingProperty]);

  final String label;
  final List<String> keys;
  final SuperTextProperty? bindingProperty;
}

@immutable
class TextConfigOverride {
  TextConfigOverride({
    SuperTextConfig config = const SuperTextConfig(),
    Set<TextStateProperty> properties = const {},
  }) : config = _textStateLeaf(config),
       properties = Set.unmodifiable(properties);

  final SuperTextConfig config;
  final Set<TextStateProperty> properties;
  bool get isEmpty => properties.isEmpty;

  TextConfigOverride copyWith({
    SuperTextConfig? config,
    Set<TextStateProperty>? properties,
    bool clearProperties = false,
  }) => TextConfigOverride(
    config: config ?? this.config,
    properties: clearProperties ? const {} : properties ?? this.properties,
  );

  TextConfigOverride edited(SuperTextConfig next) {
    final leaf = _textStateLeaf(next);
    final before = config.toJson();
    final after = leaf.toJson();
    return TextConfigOverride(
      config: leaf,
      properties: {
        ...properties,
        for (final property in TextStateProperty.values)
          if (property.keys.any(
                (key) => !_sameTextStateValue(before[key], after[key]),
              ) ||
              (property.bindingProperty != null &&
                  config.propertyBindings[property.bindingProperty] !=
                      leaf.propertyBindings[property.bindingProperty]))
            property,
      },
    );
  }

  SuperTextConfig apply(SuperTextConfig base) {
    final bindings = Map<SuperTextProperty, JsonTextBinding>.of(
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
    bool has(TextStateProperty property) => properties.contains(property);
    final content = has(TextStateProperty.content) ? config : base;
    final interaction = has(TextStateProperty.enabled) ? config : base;
    final result = SuperTextConfig(
      mode: content.mode,
      initialText: content.initialText,
      obscureText: content.obscureText,
      minLines: content.minLines,
      maxLines: content.maxLines,
      field: content.field,
      label: has(TextStateProperty.textLabel) ? config.label : base.label,
      placeholder: has(TextStateProperty.placeholder)
          ? config.placeholder
          : base.placeholder,
      enabled: interaction.enabled,
      readOnly: interaction.readOnly,
      fontFamily: has(TextStateProperty.fontFamily)
          ? config.fontFamily
          : base.fontFamily,
      fontSize: has(TextStateProperty.fontSize)
          ? config.fontSize
          : base.fontSize,
      fontWeight: has(TextStateProperty.fontWeight)
          ? config.fontWeight
          : base.fontWeight,
      italic: has(TextStateProperty.italic) ? config.italic : base.italic,
      color: has(TextStateProperty.color) ? config.color : base.color,
      textAlign: has(TextStateProperty.textAlign)
          ? config.textAlign
          : base.textAlign,
      lineHeight: has(TextStateProperty.lineHeight)
          ? config.lineHeight
          : base.lineHeight,
      letterSpacing: has(TextStateProperty.letterSpacing)
          ? config.letterSpacing
          : base.letterSpacing,
      binding: has(TextStateProperty.binding) ? config.binding : base.binding,
      propertyBindings: Map.unmodifiable(bindings),
    );
    result._validateLeaf();
    return result;
  }

  Map<String, Object?> toJson() => {
    'config': config.toJson(),
    'properties': properties.map((p) => p.name).toList()..sort(),
  };

  factory TextConfigOverride.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any((key) => key != 'config' && key != 'properties') ||
        value['properties'] is! List) {
      throw const FormatException('Invalid Text override.');
    }
    final properties = <TextStateProperty>{};
    for (final name in value['properties'] as List) {
      final property = TextStateProperty.values
          .where((property) => property.name == name)
          .firstOrNull;
      if (property == null || !properties.add(property)) {
        throw const FormatException('Invalid Text override property.');
      }
    }
    return TextConfigOverride(
      config: _readTextStateLeaf(value['config']),
      properties: properties,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextConfigOverride &&
      config == other.config &&
      setEquals(properties, other.properties);

  @override
  int get hashCode => Object.hash(config, Object.hashAllUnordered(properties));
}

@immutable
class TextConfigStates {
  TextConfigStates({
    this.binding,
    Map<String, SuperTextConfig> named = const {},
    Map<String, Set<TextStateProperty>> namedProperties = const {},
    this.hover,
    this.selected,
    Map<AutomaticState, TextConfigOverride> automatic = const {},
    List<String>? order,
  }) : named = Map.unmodifiable({
         for (final entry in named.entries)
           _textStateName(entry.key): _textStateLeaf(entry.value),
       }),
       automatic = Map.unmodifiable(automatic),
       namedProperties = Map.unmodifiable({
         for (final name in named.keys)
           name: Set<TextStateProperty>.unmodifiable(
             namedProperties[name] ?? {},
           ),
       }),
       order = List.unmodifiable(
         _textStateOrder(named.keys, order, automatic.keys),
       ) {
    binding?.validate();
    if (namedProperties.keys.any((name) => !named.containsKey(name))) {
      throw const FormatException('Unknown named Text override.');
    }
    if (automatic.keys.any(
      (s) => s == AutomaticState.hover || s == AutomaticState.selected,
    )) {
      throw const FormatException('Duplicate automatic Text state.');
    }
  }

  static const hoverKey = '\u0000hover';
  static const selectedKey = '\u0000selected';

  final JsonTextBinding? binding;
  final Map<String, SuperTextConfig> named;
  final Map<String, Set<TextStateProperty>> namedProperties;
  final TextConfigOverride? hover;
  final TextConfigOverride? selected;
  final Map<AutomaticState, TextConfigOverride> automatic;
  final List<String> order;

  TextConfigStates copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<String, SuperTextConfig>? named,
    Map<String, Set<TextStateProperty>>? namedProperties,
    bool clearNamed = false,
    TextConfigOverride? hover,
    bool clearHover = false,
    TextConfigOverride? selected,
    bool clearSelected = false,
    Map<AutomaticState, TextConfigOverride>? automatic,
    List<String>? order,
    bool clearOrder = false,
  }) {
    final nextNamed = clearNamed
        ? <String, SuperTextConfig>{}
        : named ?? this.named;
    return TextConfigStates(
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

  SuperTextConfig resolve(
    SuperTextConfig base, {
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
        result = TextConfigOverride(
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

  void _validateAgainst(SuperTextConfig base) {
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

  factory TextConfigStates.fromJson(Object? value) {
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
      throw const FormatException('Invalid Text states.');
    }
    final named = <String, SuperTextConfig>{};
    for (final entry in (value['named'] as Map).entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid Text state name.');
      }
      named[_textStateName(entry.key as String)] = _readTextStateLeaf(
        entry.value,
      );
    }
    try {
      return TextConfigStates(
        binding: value['binding'] == null
            ? null
            : JsonTextBinding.fromJson(value['binding']),
        named: named,
        namedProperties: _readTextNamedProperties(
          value['namedProperties'],
          named,
        ),
        hover: value.containsKey('hover')
            ? TextConfigOverride.fromJson(value['hover'])
            : null,
        selected: value.containsKey('selected')
            ? TextConfigOverride.fromJson(value['selected'])
            : null,
        automatic: _readTextAutomatic(value['automatic']),
        order: (value['order'] as List?)?.cast<String>(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid Text states.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TextConfigStates &&
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

Map<String, Set<TextStateProperty>> _readTextNamedProperties(
  Object? value,
  Map<String, SuperTextConfig> named,
) {
  if (value == null) return {};
  if (value is! Map || value.keys.any((key) => !named.containsKey(key))) {
    throw const FormatException('Invalid named Text overrides.');
  }
  return {
    for (final entry in value.entries)
      entry.key as String: TextConfigOverride.fromJson({
        'config': named[entry.key]!.toJson(),
        'properties': entry.value,
      }).properties,
  };
}

Map<AutomaticState, TextConfigOverride> _readTextAutomatic(Object? value) {
  if (value == null) return {};
  if (value is! Map) {
    throw const FormatException('Invalid automatic Text states.');
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
              (throw const FormatException('Unknown automatic Text state.'))):
          TextConfigOverride.fromJson(entry.value),
  };
}

SuperTextConfig _textStateLeaf(SuperTextConfig config) {
  if (config.states != null) {
    throw const FormatException('Text states cannot contain nested states.');
  }
  return config.copyWith(
    propertyBindings: Map.unmodifiable(config.propertyBindings),
  );
}

SuperTextConfig _readTextStateLeaf(Object? value) {
  if (value is! Map<String, dynamic> || value.containsKey('states')) {
    throw const FormatException('Invalid or nested Text state.');
  }
  return _textStateLeaf(SuperTextConfig.fromJson(value));
}

String _textStateName(String name) {
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
    throw const FormatException('Empty or reserved Text state name.');
  }
  return name;
}

List<String> _textStateOrder(
  Iterable<String> names,
  List<String>? order,
  Iterable<AutomaticState> automatic,
) {
  final defaults = [
    ...names,
    TextConfigStates.hoverKey,
    TextConfigStates.selectedKey,
    ...automatic.map((s) => s.key),
  ];
  if (order == null) return defaults;
  if (order.toSet().length != order.length ||
      order.any((key) => !defaults.contains(key))) {
    throw const FormatException('Invalid Text state order.');
  }
  return [...order, ...defaults.where((key) => !order.contains(key))];
}

bool _sameTextStateValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && _sameTextStateValue(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable.generate(a.length)
            .every((i) => _sameTextStateValue(a[i], b[i]));
  }
  return a == b;
}
