import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;

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
}

