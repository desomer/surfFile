part of 'container_style.dart';

/// Related fields share an override switch to keep uniform/independent values
/// and nullable decorations coherent.
enum SurfaceStyleProperty {
  background('Fond', ['color', 'fill']),
  corners('Coins', ['radius', 'radii']),
  border('Bordure', [
    'borderWidth',
    'borderWidths',
    'borderColor',
    'borderLine',
  ]),
  shadow('Ombre', ['elevation', 'shadowOpacity', 'shadow']),
  innerShadow('Ombre intérieure', ['innerShadow']),
  neon('Néon', ['neon']),
  padding('Espacement intérieur', ['padding', 'paddingInsets']),
  margin('Marge extérieure', ['margin', 'marginInsets']),
  designSystem('Système de design', ['designSystem']),
  interaction('Interaction', ['interactionEffect']),
  hover('Survol', ['hoverEffect', 'hoverTint', 'hoverColor']),
  opacity('Opacité', ['opacity']),
  blur('Flou', ['backdropBlur']),
  pattern('Motif', ['pattern', 'patternOpacity']),
  transform('Transformation', ['transform']);

  const SurfaceStyleProperty(this.label, this.keys);
  final String label;
  final List<String> keys;
}

@immutable
class SelectedSurfaceStyle {
  SelectedSurfaceStyle({
    ContainerStyle style = const ContainerStyle(),
    Set<SurfaceStyleProperty> properties = const {},
  }) : style = _leaf(style),
       properties = Set.unmodifiable(properties);

  final ContainerStyle style;
  final Set<SurfaceStyleProperty> properties;
  bool get isEmpty => properties.isEmpty;

  SelectedSurfaceStyle edited(ContainerStyle next) {
    final before = style.toJson();
    final after = next.toJson();
    return SelectedSurfaceStyle(
      style: next.copyWith(clearStates: true),
      properties: {
        ...properties,
        for (final property in SurfaceStyleProperty.values)
          if (property.keys.any(
            (key) => !_sameStyleValue(before[key], after[key]),
          ))
            property,
      },
    );
  }

  ContainerStyle apply(ContainerStyle base) {
    final source = style.toJson();
    final json = base.copyWith(clearStates: true).toJson();
    // Absent optional keys mean an explicit reset, not inheritance.
    for (final property in properties) {
      for (final key in property.keys) {
        if (source.containsKey(key)) {
          json[key] = source[key];
        } else {
          json.remove(key);
        }
      }
    }
    return ContainerStyle.fromJson(json);
  }

  Map<String, Object?> toJson() => {
    'style': style.toJson(),
    'properties': properties.map((p) => p.name).toList()..sort(),
  };

  @override
  bool operator ==(Object other) =>
      other is SelectedSurfaceStyle &&
      _sameStyleValue(toJson(), other.toJson());

  @override
  int get hashCode => _styleValueHash(toJson());

  factory SelectedSurfaceStyle.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any((key) => key != 'style' && key != 'properties') ||
        value['style'] is! Map ||
        value['properties'] is! List) {
      throw const FormatException('Style sélectionné invalide.');
    }
    final properties = <SurfaceStyleProperty>{};
    for (final name in value['properties'] as List) {
      final property = SurfaceStyleProperty.values
          .where((p) => p.name == name)
          .firstOrNull;
      if (property == null || !properties.add(property)) {
        throw const FormatException('Propriété de sélection invalide.');
      }
    }
    return SelectedSurfaceStyle(
      style: _readLeaf(value['style']),
      properties: properties,
    );
  }
}

@immutable
class SurfaceStyleStates {
  SurfaceStyleStates({
    this.binding,
    Map<String, ContainerStyle> named = const {},
    this.selected,
    this.hover,
    List<String>? order,
  }) : named = Map.unmodifiable({
         for (final entry in named.entries)
           _name(entry.key): _leaf(entry.value),
       }),
       order = List.unmodifiable(_stateOrder(named.keys, order)) {
    binding?.validate();
  }

  final JsonTextBinding? binding;
  final Map<String, ContainerStyle> named;
  final SelectedSurfaceStyle? selected;
  final SelectedSurfaceStyle? hover;
  final List<String> order;
  static const hoverKey = '\u0000hover';
  static const selectedKey = '\u0000selected';
  bool get hasSelected => selected?.isEmpty == false;

  SurfaceStyleStates copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<String, ContainerStyle>? named,
    SelectedSurfaceStyle? selected,
    bool clearSelected = false,
    SelectedSurfaceStyle? hover,
    bool clearHover = false,
    List<String>? order,
  }) => SurfaceStyleStates(
    binding: clearBinding ? null : binding ?? this.binding,
    named: named ?? this.named,
    selected: clearSelected ? null : selected ?? this.selected,
    hover: clearHover ? null : hover ?? this.hover,
    order:
        order ??
        this.order
            .where(
              (key) =>
                  key == hoverKey ||
                  key == selectedKey ||
                  (named ?? this.named).containsKey(key),
            )
            .toList(),
  );

  ContainerStyle resolve(
    ContainerStyle base, {
    String? name,
    bool isSelected = false,
    bool isHovered = false,
  }) {
    var active = base.copyWith(clearStates: true);
    for (final key in order) {
      if (key == hoverKey) {
        if (isHovered && hover != null) active = hover!.apply(active);
      } else if (key == selectedKey) {
        if (isSelected && hasSelected) active = selected!.apply(active);
      } else if (key == name) {
        active = named[key]!;
      }
    }
    return active;
  }

  Map<String, Object?> toJson() => {
    if (binding != null) 'binding': binding!.toJson(),
    'named': {for (final e in named.entries) e.key: e.value.toJson()},
    if (selected != null) 'selected': selected!.toJson(),
    if (hover != null) 'hover': hover!.toJson(),
    'order': order,
  };

  factory SurfaceStyleStates.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any(
          (key) =>
              !{'binding', 'named', 'selected', 'hover', 'order'}.contains(key),
        ) ||
        value['named'] is! Map ||
        (value.containsKey('order') &&
            (value['order'] is! List ||
                (value['order'] as List).any((key) => key is! String)))) {
      throw const FormatException('États de surface invalides.');
    }
    final named = <String, ContainerStyle>{};
    for (final entry in (value['named'] as Map).entries) {
      if (entry.key is! String) {
        throw const FormatException('Nom d’état invalide.');
      }
      named[_name(entry.key as String)] = _readLeaf(entry.value);
    }
    return SurfaceStyleStates(
      binding: value['binding'] == null
          ? null
          : JsonTextBinding.fromJson(value['binding']),
      named: named,
      selected: value['selected'] == null
          ? null
          : SelectedSurfaceStyle.fromJson(value['selected']),
      hover: value['hover'] == null
          ? null
          : SelectedSurfaceStyle.fromJson(value['hover']),
      order: (value['order'] as List?)?.cast<String>(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SurfaceStyleStates && _sameStyleValue(toJson(), other.toJson());

  @override
  int get hashCode => _styleValueHash(toJson());
}

String _name(String name) {
  if (name.trim().isEmpty ||
      name.contains('\u0000') ||
      name.trim() != name ||
      {
        'par défaut',
        'par defaut',
        'sélectionné',
        'selectionne',
        'hover',
        'survol',
      }.contains(name.toLowerCase())) {
    throw const FormatException('Nom d’état vide ou réservé.');
  }

  return name;
}

List<String> _stateOrder(Iterable<String> names, List<String>? order) {
  final defaults = [
    ...names,
    SurfaceStyleStates.hoverKey,
    SurfaceStyleStates.selectedKey,
  ];
  if (order == null) return defaults;
  if (order.toSet().length != order.length ||
      order.any((key) => !defaults.contains(key))) {
    throw const FormatException('Ordre des états invalide.');
  }
  return [...order, ...defaults.where((key) => !order.contains(key))];
}

bool _sameStyleValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && _sameStyleValue(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable.generate(a.length).every((i) => _sameStyleValue(a[i], b[i]));
  }
  return a == b;
}

int _styleValueHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map((e) => Object.hash(e.key, _styleValueHash(e.value))),
    );
  }
  if (value is List) return Object.hashAll(value.map(_styleValueHash));
  return value.hashCode;
}

ContainerStyle _leaf(ContainerStyle style) {
  if (style.states != null) {
    throw const FormatException(
      'Les styles d’état ne peuvent pas contenir des états.',
    );
  }
  return style;
}

ContainerStyle _readLeaf(Object? value) {
  if (value is! Map || value.containsKey('states')) {
    throw const FormatException('Style d’état invalide ou imbriqué.');
  }
  return ContainerStyle.fromJson(value);
}
