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
      fontSize: has(TextStateProperty.fontSize) ? config.fontSize : base.fontSize,
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
  int get hashCode =>
      Object.hash(config, Object.hashAllUnordered(properties));
}

@immutable
class TextConfigStates {
  TextConfigStates({
    this.binding,
    Map<String, SuperTextConfig> named = const {},
    this.hover,
    this.selected,
    List<String>? order,
  }) : named = Map.unmodifiable({
         for (final entry in named.entries)
           _textStateName(entry.key): _textStateLeaf(entry.value),
       }),
       order = List.unmodifiable(_textStateOrder(named.keys, order)) {
    binding?.validate();
  }

  static const hoverKey = '\u0000hover';
  static const selectedKey = '\u0000selected';

  final JsonTextBinding? binding;
  final Map<String, SuperTextConfig> named;
  final TextConfigOverride? hover;
  final TextConfigOverride? selected;
  final List<String> order;

  TextConfigStates copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<String, SuperTextConfig>? named,
    bool clearNamed = false,
    TextConfigOverride? hover,
    bool clearHover = false,
    TextConfigOverride? selected,
    bool clearSelected = false,
    List<String>? order,
    bool clearOrder = false,
  }) {
    final nextNamed = clearNamed ? <String, SuperTextConfig>{} : named ?? this.named;
    return TextConfigStates(
      binding: clearBinding ? null : binding ?? this.binding,
      named: nextNamed,
      hover: clearHover ? null : hover ?? this.hover,
      selected: clearSelected ? null : selected ?? this.selected,
      order: clearOrder
          ? null
          : order ??
                this.order.where((key) =>
                    key == hoverKey ||
                    key == selectedKey ||
                    nextNamed.containsKey(key)).toList(),
    );
  }

  SuperTextConfig resolve(
    SuperTextConfig base, {
    String? name,
    bool isHovered = false,
    bool isSelected = false,
  }) {
    var result = base.copyWith(clearStates: true);
    for (final key in order) {
      if (key == hoverKey) {
        if (isHovered && hover != null) result = hover!.apply(result);
      } else if (key == selectedKey) {
        if (isSelected && selected != null) result = selected!.apply(result);
      } else if (key == name) {
        result = named[key]!;
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
    for (final name in <String?>[null, ...named.keys]) {
      for (final isHovered in [false, true]) {
        for (final isSelected in [false, true]) {
          resolve(
            base,
            name: name,
            isHovered: isHovered,
            isSelected: isSelected,
          )._validateLeaf();
        }
      }
    }
  }

  Map<String, Object?> toJson() => {
    if (binding != null) 'binding': binding!.toJson(),
    'named': {for (final entry in named.entries) entry.key: entry.value.toJson()},
    if (hover != null) 'hover': hover!.toJson(),
    if (selected != null) 'selected': selected!.toJson(),
    'order': order,
  };

  factory TextConfigStates.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any((key) =>
            !{'binding', 'named', 'hover', 'selected', 'order'}.contains(key)) ||
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
      named[_textStateName(entry.key as String)] = _readTextStateLeaf(entry.value);
    }
    try {
      return TextConfigStates(
        binding: value['binding'] == null
            ? null
            : JsonTextBinding.fromJson(value['binding']),
        named: named,
        hover: value.containsKey('hover')
            ? TextConfigOverride.fromJson(value['hover'])
            : null,
        selected: value.containsKey('selected')
            ? TextConfigOverride.fromJson(value['selected'])
            : null,
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
      hover == other.hover &&
      selected == other.selected &&
      listEquals(order, other.order);

  @override
  int get hashCode => Object.hash(
    binding,
    Object.hashAllUnordered(named.entries.map((e) => Object.hash(e.key, e.value))),
    hover,
    selected,
    Object.hashAll(order),
  );
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

List<String> _textStateOrder(Iterable<String> names, List<String>? order) {
  final defaults = [
    ...names,
    TextConfigStates.hoverKey,
    TextConfigStates.selectedKey,
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
        a.keys.every((key) =>
            b.containsKey(key) && _sameTextStateValue(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable.generate(a.length).every((i) => _sameTextStateValue(a[i], b[i]));
  }
  return a == b;
}
