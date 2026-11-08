/// Définition des états automatiques ([AutomaticState]) évalués par les surfaces et composants.
///
/// Permet de déclencher des surcharges de style ou de configuration sur
/// `contentHover`, `focused`, `disabled` et `readOnly`, et gère leur encodage
/// dans les listes de priorité d'états (`order`).
library;

import 'package:flutter/foundation.dart'
    show immutable, listEquals, mapEquals, setEquals;

import 'component_config.dart';
import 'json_text_binding.dart';

/// Contrat d'une propriété d'état surchargeable sur un [ComponentConfig].
abstract interface class ComponentStateProperty<B extends Enum> implements Enum {
  /// Libellé lisible affiché dans l'éditeur d'états.
  String get label;

  /// Clés JSON de la configuration associées à ce groupe de propriété.
  List<String> get keys;

  /// Propriété de liaison JSON associée, le cas échéant.
  B? get bindingProperty;
}

/// Classe de base immuable d'une surcharge partielle de [ComponentConfig] pour un état.
@immutable
abstract class ComponentConfigOverrideBase<
  C extends ComponentConfig,
  P extends ComponentStateProperty<B>,
  B extends Enum
> {
  ComponentConfigOverrideBase({
    required this.config,
    Set<P> properties = const {},
  }) : properties = Set.unmodifiable(properties);

  final C config;
  final Set<P> properties;
  bool get isEmpty => properties.isEmpty;

  /// Applique cette surcharge partielle sur la configuration [base].
  C apply(C base);

  /// Calcule l'ensemble des propriétés modifiées entre [config] et [leaf].
  Set<P> computeEditedProperties(
    C leaf,
    Iterable<P> allProperties,
    Map<B, JsonTextBinding> Function(C) bindingsOf,
  ) {
    final before = config.toJson();
    final after = leaf.toJson();
    final currentBindings = bindingsOf(config);
    final nextBindings = bindingsOf(leaf);
    return {
      ...properties,
      for (final property in allProperties)
        if (property.keys.any(
              (key) => !ComponentStateHelpers.sameJsonValue(
                before[key],
                after[key],
              ),
            ) ||
            (property.bindingProperty != null &&
                currentBindings[property.bindingProperty] !=
                    nextBindings[property.bindingProperty]))
          property,
    };
  }

  /// Fusionne les `propertyBindings` de [base] avec ceux surchargés dans [config].
  Map<B, JsonTextBinding> mergePropertyBindings(
    C base,
    Map<B, JsonTextBinding> Function(C) bindingsOf,
  ) {
    final bindings = Map<B, JsonTextBinding>.of(bindingsOf(base));
    final overrideBindings = bindingsOf(config);
    for (final property in properties) {
      final target = property.bindingProperty;
      if (target != null) {
        final binding = overrideBindings[target];
        if (binding == null) {
          bindings.remove(target);
        } else {
          bindings[target] = binding;
        }
      }
    }
    return bindings;
  }

  Map<String, Object?> toJson() => {
    'config': config.toJson(),
    'properties': properties.map((p) => p.name).toList()..sort(),
  };

  Map<String, Object?> toCompactJson() => {
    'config': config.toCompactJson(),
    'properties': properties.map((p) => p.name).toList()..sort(),
  };

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is ComponentConfigOverrideBase<C, P, B> &&
      config == other.config &&
      setEquals(properties, other.properties);

  @override
  int get hashCode => Object.hash(config, Object.hashAllUnordered(properties));
}

/// Classe de base immuable d'une collection d'états (`named`, `hover`, `selected`, `automatic`).
@immutable
abstract class ComponentConfigStatesBase<
  C extends ComponentConfig,
  P extends ComponentStateProperty<B>,
  B extends Enum,
  O extends ComponentConfigOverrideBase<C, P, B>
> {
  ComponentConfigStatesBase({
    required String context,
    required C Function(C) toLeaf,
    this.binding,
    Map<String, C> named = const {},
    Map<String, Set<P>> namedProperties = const {},
    this.hover,
    this.selected,
    Map<AutomaticState, O> automatic = const {},
    List<String>? order,
  }) : named = Map.unmodifiable({
         for (final entry in named.entries)
           ComponentStateHelpers.validateStateName(entry.key, context): toLeaf(
             entry.value,
           ),
       }),
       automatic = Map.unmodifiable(automatic),
       namedProperties = Map.unmodifiable({
         for (final name in named.keys)
           name: Set<P>.unmodifiable(namedProperties[name] ?? {}),
       }),
       order = List.unmodifiable(
         ComponentStateHelpers.normalizeStateOrder(
           named.keys,
           order,
           automatic.keys,
           context,
         ),
       ) {
    binding?.validate();
    if (namedProperties.keys.any((name) => !named.containsKey(name))) {
      throw FormatException('Unknown named $context override.');
    }
    if (automatic.keys.any(
      (s) => s == AutomaticState.hover || s == AutomaticState.selected,
    )) {
      throw FormatException('Duplicate automatic $context state.');
    }
  }

  final JsonTextBinding? binding;
  final Map<String, C> named;
  final Map<String, Set<P>> namedProperties;
  final O? hover;
  final O? selected;
  final Map<AutomaticState, O> automatic;
  final List<String> order;

  /// Retourne une copie de [base] sans `states`.
  C clearStatesOf(C base);

  /// Construit une instance d'override typée pour un état nommé.
  O buildOverride(C config, Set<P> properties);

  /// Résout la configuration effective selon les états actifs et leur ordre de priorité.
  C resolve(
    C base, {
    String? name,
    bool isHovered = false,
    bool isSelected = false,
    Set<AutomaticState> activeStates = const {},
  }) {
    var result = clearStatesOf(base);
    for (final key in order) {
      if (key == ComponentStateHelpers.hoverKey) {
        if (isHovered && hover != null) result = hover!.apply(result);
      } else if (key == ComponentStateHelpers.selectedKey) {
        if (isSelected && selected != null) result = selected!.apply(result);
      } else if (key == name) {
        result = buildOverride(
          named[key]!,
          namedProperties[key]!,
        ).apply(result);
      } else if (AutomaticState.fromKey(key) case final state?) {
        if (activeStates.contains(state)) {
          result = automatic[state]?.apply(result) ?? result;
        }
      }
    }
    return result;
  }

  /// Valide la cohérence de chaque surcharge et de toutes leurs combinaisons sur [base].
  void validateStatesAgainst(C base, void Function(C) validateLeaf) {
    binding?.validate();
    for (final config in named.values) {
      validateLeaf(config);
    }
    if (hover != null) validateLeaf(hover!.config);
    if (selected != null) validateLeaf(selected!.config);
    for (final value in automatic.values) {
      validateLeaf(value.config);
    }
    for (final name in <String?>[null, ...named.keys]) {
      for (final isHovered in [false, true]) {
        for (final isSelected in [false, true]) {
          for (var mask = 0; mask < (1 << automatic.length); mask++) {
            validateLeaf(
              resolve(
                base,
                name: name,
                isHovered: isHovered,
                isSelected: isSelected,
                activeStates: {
                  for (var i = 0; i < automatic.length; i++)
                    if (mask & (1 << i) != 0) automatic.keys.elementAt(i),
                },
              ),
            );
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

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is ComponentConfigStatesBase<C, P, B, O> &&
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

/// États automatiques gérés nativement par le moteur d'exécution.
enum AutomaticState {
  hover('Hover', 'Survol du composant'),
  selected('Sélectionné', 'ListView sélectionné'),
  contentHover('Content survolé', 'Content survolé'),
  focused('Focus', 'Focus du champ'),
  disabled('Désactivé', 'Champ désactivé'),
  readOnly('Lecture seule', 'Champ en lecture seule');

  const AutomaticState(this.label, this.description);
  final String label;
  final String description;
  String get key => '\u0000$name';

  static final Map<String, AutomaticState> _byKey = {
    for (final value in values) value.key: value,
  };

  static AutomaticState? fromKey(String? key) =>
      key == null ? null : _byKey[key];
}

/// Shared state validation, serialization, equality, and hash helpers for
/// component state overrides and collections.
abstract final class ComponentStateHelpers {
  static const hoverKey = '\u0000hover';
  static const selectedKey = '\u0000selected';

  static const _reservedNames = {
    'default',
    'selected',
    'hover',
    'hovered',
    'par défaut',
    'par defaut',
    'sélectionné',
    'selectionne',
    'survol',
  };

  static String validateStateName(String name, String context) {
    if (name.isEmpty ||
        name.trim() != name ||
        name.contains('\u0000') ||
        _reservedNames.contains(name.toLowerCase())) {
      throw FormatException('Empty or reserved $context state name.');
    }
    return name;
  }

  static List<String> normalizeStateOrder(
    Iterable<String> names,
    List<String>? order,
    Iterable<AutomaticState> automatic,
    String context,
  ) {
    final defaults = [
      ...names,
      hoverKey,
      selectedKey,
      ...automatic.map((s) => s.key),
    ];
    if (order == null) return defaults;
    if (order.toSet().length != order.length ||
        order.any((key) => !defaults.contains(key))) {
      throw FormatException('Invalid $context state order.');
    }
    return [...order, ...defaults.where((key) => !order.contains(key))];
  }

  static List<String> filterCopiedOrder(
    List<String> currentOrder,
    Iterable<AutomaticState> automaticKeys,
    Map<String, Object?> nextNamed,
  ) => currentOrder
      .where(
        (key) =>
            key == hoverKey ||
            key == selectedKey ||
            automaticKeys.any((s) => s.key == key) ||
            nextNamed.containsKey(key),
      )
      .toList();

  static bool sameJsonValue(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && sameJsonValue(a[key], b[key]),
          );
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          Iterable.generate(a.length)
              .every((i) => sameJsonValue(a[i], b[i]));
    }
    return a == b;
  }

  static int hashJsonValue(Object? v) {
    if (v is Map) {
      return Object.hashAllUnordered(
        v.entries.map((e) => Object.hash(e.key, hashJsonValue(e.value))),
      );
    }
    if (v is List) {
      return Object.hashAll(v.map(hashJsonValue));
    }
    return v.hashCode;
  }

  static Set<P> parseOverrideProperties<P extends Enum>(
    Object? value,
    Iterable<P> values,
    String context,
  ) {
    if (value is! Map ||
        value.keys.any((key) => key != 'config' && key != 'properties') ||
        value['properties'] is! List) {
      throw FormatException('Invalid $context override.');
    }
    final properties = <P>{};
    for (final name in value['properties'] as List) {
      final property = values
          .where((property) => property.name == name)
          .firstOrNull;
      if (property == null || !properties.add(property)) {
        throw FormatException('Invalid $context override property.');
      }
    }
    return properties;
  }

  static Map<AutomaticState, O> readAutomaticStates<O>(
    Object? value,
    O Function(Object?) parseOverride,
    String context,
  ) {
    if (value == null) return {};
    if (value is! Map) {
      throw FormatException('Invalid automatic $context states.');
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
                (throw FormatException('Unknown automatic $context state.'))):
            parseOverride(entry.value),
    };
  }

  static bool equalsStateCollection<C, P, O>({
    required Object? bindingA,
    required Object? bindingB,
    required Map<String, C> namedA,
    required Map<String, C> namedB,
    required Map<String, Set<P>> propsA,
    required Map<String, Set<P>> propsB,
    required O? hoverA,
    required O? hoverB,
    required O? selectedA,
    required O? selectedB,
    required Map<AutomaticState, O> autoA,
    required Map<AutomaticState, O> autoB,
    required List<String> orderA,
    required List<String> orderB,
  }) =>
      bindingA == bindingB &&
      mapEquals(namedA, namedB) &&
      propsA.length == propsB.length &&
      propsA.entries.every((e) => setEquals(e.value, propsB[e.key])) &&
      hoverA == hoverB &&
      selectedA == selectedB &&
      mapEquals(autoA, autoB) &&
      listEquals(orderA, orderB);

  static int hashStateCollection<C, P, O>(
    Object? binding,
    Map<String, C> named,
    Map<String, Set<P>> namedProperties,
    O? hover,
    O? selected,
    Map<AutomaticState, O> automatic,
    List<String> order,
  ) => Object.hash(
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

  /// Garantit qu'une configuration d'état ne contient pas elle-même de sous-états.
  static C ensureStateLeaf<C>(
    C config, {
    required Object? states,
    required C Function(C) normalize,
    required String context,
  }) {
    if (states != null) {
      throw FormatException('$context states cannot contain nested states.');
    }
    return normalize(config);
  }

  /// Lit et valide une configuration feuille d'état depuis une Map JSON.
  static C readStateLeaf<C>(
    Object? value, {
    required C Function(Object?) fromJson,
    required C Function(C) toLeaf,
    required String context,
  }) {
    if (value is! Map || value.containsKey('states')) {
      throw FormatException('Invalid or nested $context state.');
    }
    return toLeaf(fromJson(value));
  }

  /// Désérialise une instance de [ComponentConfigStatesBase] depuis une Map JSON.
  static S parseStatesJson<
    C extends ComponentConfig,
    P extends ComponentStateProperty<B>,
    B extends Enum,
    O extends ComponentConfigOverrideBase<C, P, B>,
    S
  >({
    required Object? value,
    required String context,
    required C Function(Object?) readLeaf,
    required O Function(Object?) parseOverride,
    required S Function({
      JsonTextBinding? binding,
      required Map<String, C> named,
      required Map<String, Set<P>> namedProperties,
      O? hover,
      O? selected,
      required Map<AutomaticState, O> automatic,
      List<String>? order,
    })
    build,
  }) {
    if (value is! Map ||
        value.keys.any(
          (key) => !const {
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
      throw FormatException('Invalid $context states.');
    }
    final named = <String, C>{};
    for (final entry in (value['named'] as Map).entries) {
      if (entry.key is! String) {
        throw FormatException('Invalid $context state name.');
      }
      named[validateStateName(entry.key as String, context)] = readLeaf(
        entry.value,
      );
    }
    final rawProps = value['namedProperties'];
    final namedProperties = <String, Set<P>>{};
    if (rawProps != null) {
      if (rawProps is! Map ||
          rawProps.keys.any((key) => !named.containsKey(key))) {
        throw FormatException('Invalid named $context overrides.');
      }
      for (final entry in rawProps.entries) {
        namedProperties[entry.key as String] = parseOverride({
          'config': named[entry.key]!.toJson(),
          'properties': entry.value,
        }).properties;
      }
    }
    try {
      return build(
        binding: value['binding'] == null
            ? null
            : JsonTextBinding.fromJson(value['binding']),
        named: named,
        namedProperties: namedProperties,
        hover: value.containsKey('hover')
            ? parseOverride(value['hover'])
            : null,
        selected: value.containsKey('selected')
            ? parseOverride(value['selected'])
            : null,
        automatic: readAutomaticStates(value['automatic'], parseOverride, context),
        order: (value['order'] as List?)?.cast<String>(),
      );
    } on ArgumentError {
      throw FormatException('Invalid $context states.');
    }
  }
}

