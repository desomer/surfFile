import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/super_text_config.dart';
import 'package:super_container_layout/models/super_text_field_config.dart';

void main() {
  test(
    'legacy named Text states start empty and explicit masks persist immutably',
    () {
      final states = TextConfigStates(
        named: {
          'ready': const SuperTextConfig(initialText: 'Ready', fontSize: 24),
        },
      );
      const base = SuperTextConfig(initialText: 'Default', fontSize: 16);
      expect(states.resolve(base, name: 'ready'), base);
      final legacy = states.toJson()..remove('namedProperties');
      final migrated = TextConfigStates.fromJson(legacy);
      expect(migrated.namedProperties['ready'], isEmpty);
      expect(migrated.resolve(base, name: 'ready'), base);
      final properties = <TextStateProperty>{TextStateProperty.fontSize};
      final configured = states.copyWith(
        namedProperties: {'ready': properties},
      );
      properties.clear();
      expect(configured.resolve(base, name: 'ready').fontSize, 24);
      expect(configured.resolve(base, name: 'ready').initialText, 'Default');
      final decoded = TextConfigStates.fromJson(
        jsonDecode(jsonEncode(configured.toJson())),
      );
      expect(decoded, configured);
      expect(decoded.hashCode, configured.hashCode);
      expect(
        () => decoded.namedProperties['ready']!.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => TextConfigStates.fromJson({
          ...legacy,
          'namedProperties': {
            'ready': ['unknown'],
          },
        }),
        throwsFormatException,
      );
      expect(
        () => TextConfigStates.fromJson({
          ...legacy,
          'namedProperties': {'missing': []},
        }),
        throwsFormatException,
      );
      expect(configured.copyWith(named: {}).namedProperties, isEmpty);
      final cleared = configured.copyWith(namedProperties: {'ready': {}});
      expect(
        cleared.resolve(base.copyWith(fontSize: 18), name: 'ready').fontSize,
        18,
      );
    },
  );

  const base = SuperTextConfig(
    initialText: 'base',
    label: 'Base',
    fontSize: 16,
    color: Color(0xFF9E9E9E),
    italic: true,
    letterSpacing: 2,
  );
  const binding = JsonTextBinding(path: 'status');

  test('legacy const constructor and absent states retain their codec', () {
    const legacy = SuperTextConfig();
    expect(legacy.states, isNull);
    expect(legacy.toJson().containsKey('states'), isFalse);
    expect(SuperTextConfig.fromJson(legacy.toJson()), legacy);
    expect(legacy.copyWith(label: 'changed').states, isNull);
    expect(() => legacy.validate(), returnsNormally);
  });

  test(
    'named states inherit unchecked properties and follow persisted order',
    () {
      final states = TextConfigStates(
        binding: binding,
        named: {
          'ready': const SuperTextConfig(label: 'Ready', color: Colors.green),
        },
        namedProperties: {
          'ready': {TextStateProperty.textLabel, TextStateProperty.color},
        },
        hover: TextConfigOverride(
          config: const SuperTextConfig(color: Colors.red, letterSpacing: 0),
          properties: {
            TextStateProperty.color,
            TextStateProperty.letterSpacing,
          },
        ),
        selected: TextConfigOverride(
          config: const SuperTextConfig(color: Colors.blue),
          properties: {TextStateProperty.color},
        ),
      );
      final configured = base.copyWith(states: states);
      expect(states.order, [
        'ready',
        TextConfigStates.hoverKey,
        TextConfigStates.selectedKey,
      ]);
      expect(states.resolve(configured).states, isNull);
      expect(states.resolve(configured, name: 'missing'), base);
      final named = states.resolve(configured, name: 'ready');
      expect(named.fontSize, 16);
      expect(named.initialText, 'base');
      expect(named.label, 'Ready');
      expect(named.states, isNull);
      final active = states.resolve(
        configured,
        name: 'ready',
        isHovered: true,
        isSelected: true,
      );
      expect(active.color, Colors.blue);
      expect(active.letterSpacing, 0);
      expect(active.label, 'Ready');
      final hoverLast = states.copyWith(
        order: [
          'ready',
          TextConfigStates.selectedKey,
          TextConfigStates.hoverKey,
        ],
      );
      expect(
        hoverLast
            .resolve(base, name: 'ready', isHovered: true, isSelected: true)
            .color,
        Colors.red,
      );
      final namedLast = states.copyWith(
        order: [
          TextConfigStates.hoverKey,
          TextConfigStates.selectedKey,
          'ready',
        ],
      );
      expect(
        namedLast.resolve(
          base,
          name: 'ready',
          isHovered: true,
          isSelected: true,
        ),
        named.copyWith(letterSpacing: 0),
      );
      expect(configured.copyWith(label: 'new').states, same(states));
      expect(configured.copyWith(clearStates: true), base);
    },
  );

  test('all nullable styles, false and zero are explicit resets', () {
    final source = base.copyWith(
      fontFamily: 'Roboto',
      fontWeight: FontWeight.bold,
      lineHeight: 2,
      binding: binding,
      enabled: false,
      readOnly: true,
    );
    final override = TextConfigOverride(
      config: const SuperTextConfig(italic: false, letterSpacing: 0),
      properties: TextStateProperty.values.toSet(),
    );
    final result = override.apply(source);
    expect(result, const SuperTextConfig(italic: false, letterSpacing: 0));
    expect(result.binding, isNull);
    expect(result.enabled, isTrue);
    expect(result.readOnly, isFalse);
    expect(result.fontFamily, isNull);
    expect(result.fontSize, isNull);
    expect(result.fontWeight, isNull);
    expect(result.color, isNull);
    expect(result.lineHeight, isNull);
  });

  test(
    'every field is covered by a typed group and edited accumulates groups',
    () {
      const full = SuperTextConfig(
        mode: SuperTextMode.input,
        initialText: 'hello',
        label: 'Label',
        placeholder: 'Hint',
        enabled: false,
        readOnly: true,
        minLines: 2,
        maxLines: 4,
        fontFamily: 'Roboto',
        fontSize: 20,
        fontWeight: FontWeight.bold,
        italic: true,
        color: Colors.red,
        textAlign: TextAlign.center,
        lineHeight: 1.5,
        letterSpacing: 3,
        binding: binding,
        propertyBindings: {
          SuperTextProperty.label: binding,
          SuperTextProperty.placeholder: binding,
          SuperTextProperty.fontFamily: binding,
          SuperTextProperty.fontSize: binding,
          SuperTextProperty.fontWeight: binding,
          SuperTextProperty.italic: binding,
          SuperTextProperty.color: binding,
          SuperTextProperty.textAlign: binding,
        },
        field: SuperTextFieldConfig(
          keyboard: TextFieldKeyboard.multiline,
          action: TextFieldAction.newline,
          horizontalPadding: 0,
        ),
      );
      final edited = TextConfigOverride().edited(full);
      expect(edited.properties, TextStateProperty.values.toSet());
      expect(edited.apply(base), full);
      expect(edited.config, full);
      expect(edited.isEmpty, isFalse);
      expect(TextConfigOverride().isEmpty, isTrue);
      expect(
        edited.edited(const SuperTextConfig()).properties,
        TextStateProperty.values.toSet(),
      );
      expect(edited.copyWith(clearProperties: true).isEmpty, isTrue);
      expect(
        TextConfigOverride()
            .edited(const SuperTextConfig(obscureText: true))
            .properties,
        {TextStateProperty.content},
      );
      expect(
        TextConfigOverride()
            .edited(
              const SuperTextConfig(field: SuperTextFieldConfig(radius: 0)),
            )
            .properties,
        {TextStateProperty.content},
      );
      for (final property in TextStateProperty.values) {
        expect(property.label, isNotEmpty);
      }
    },
  );

  test('each property binding follows only its corresponding group', () {
    final allBindings = {
      for (final property in SuperTextProperty.values) property: binding,
    };
    final bound = base.copyWith(propertyBindings: allBindings);
    for (final property in TextStateProperty.values) {
      final target = property.bindingProperty;
      if (target == null) continue;
      final reset = TextConfigOverride(properties: {property}).apply(bound);
      expect(reset.propertyBindings.containsKey(target), isFalse);
      expect(reset.propertyBindings.length, allBindings.length - 1);
      final next = const SuperTextConfig().copyWith(
        propertyBindings: {target: binding},
      );
      final edit = TextConfigOverride().edited(next);
      expect(edit.properties, {property});
      expect(edit.apply(base).propertyBindings, {target: binding});
    }
    expect(
      TextConfigOverride(properties: {TextStateProperty.enabled})
          .apply(bound)
          .propertyBindings,
      allBindings,
    );
  });

  test(
    'input content group keeps password and multiline validation atomic',
    () {
      const multiline = SuperTextConfig(
        mode: SuperTextMode.input,
        initialText: 'multiline',
        minLines: 2,
        maxLines: 4,
        field: SuperTextFieldConfig(
          keyboard: TextFieldKeyboard.multiline,
          action: TextFieldAction.newline,
        ),
      );
      const password = SuperTextConfig(
        mode: SuperTextMode.input,
        obscureText: true,
        field: SuperTextFieldConfig(
          keyboard: TextFieldKeyboard.text,
          suffix: TextFieldSuffix.visibility,
        ),
      );
      final states = TextConfigStates(
        named: {'secret': password, 'multiple': multiline},
        hover: TextConfigOverride(
          config: multiline,
          properties: {TextStateProperty.content},
        ),
        selected: TextConfigOverride(
          config: password,
          properties: {TextStateProperty.content},
        ),
      );
      expect(() => base.copyWith(states: states).validate(), returnsNormally);
      for (final name in <String?>[null, ...states.named.keys]) {
        expect(
          states.resolve(const SuperTextConfig(), name: name, isHovered: true),
          multiline,
        );
        expect(
          states.resolve(
            const SuperTextConfig(),
            name: name,
            isHovered: true,
            isSelected: true,
          ),
          password,
        );
      }
      expect(password.toJson().containsKey('initialText'), isFalse);
      expect(SuperTextConfig.fromJson(password.toJson()), password);
    },
  );

  test('validate checks base, named and both override configurations', () {
    final invalids = [
      const SuperTextConfig(fontSize: 0),
      const SuperTextConfig(minLines: 2),
      const SuperTextConfig(obscureText: true, initialText: 'secret'),
      const SuperTextConfig(
        field: SuperTextFieldConfig(action: TextFieldAction.newline),
      ),
      const SuperTextConfig(field: SuperTextFieldConfig(radius: -1)),
    ];
    for (final invalid in invalids) {
      expect(
        () => invalid.validate(),
        throwsA(anyOf(isArgumentError, isFormatException)),
      );
      for (final states in [
        TextConfigStates(named: {'bad': invalid}),
        TextConfigStates(hover: TextConfigOverride(config: invalid)),
        TextConfigStates(selected: TextConfigOverride(config: invalid)),
      ]) {
        final config = base.copyWith(states: states);
        expect(
          () => config.validate(),
          throwsA(anyOf(isArgumentError, isFormatException)),
        );
        expect(
          () => config.toJson(),
          throwsA(anyOf(isArgumentError, isFormatException)),
        );
      }
    }
  });

  test('states and overrides round trip with value equality and hash', () {
    final states = TextConfigStates(
      binding: binding,
      named: {
        'ready': base,
        'done': const SuperTextConfig(label: 'Done'),
      },
      hover: TextConfigOverride(
        config: const SuperTextConfig(color: Color(0xFF2196F3)),
        properties: {TextStateProperty.color, TextStateProperty.textLabel},
      ),
      selected: TextConfigOverride(
        config: const SuperTextConfig(fontSize: 22),
        properties: {TextStateProperty.fontSize},
      ),
      order: [TextConfigStates.selectedKey, 'done'],
    );
    final config = base.copyWith(states: states);
    final restored = SuperTextConfig.fromJson(
      jsonDecode(jsonEncode(config.toJson())),
    );
    expect(restored, config);
    expect(restored.hashCode, config.hashCode);
    expect(restored.states, states);
    expect(restored.states.hashCode, states.hashCode);
    expect(restored.states!.hover, states.hover);
    expect(restored.states!.hover.hashCode, states.hover.hashCode);
    final reverse = TextConfigOverride(
      config: states.hover!.config,
      properties: {TextStateProperty.textLabel, TextStateProperty.color},
    );
    expect(reverse, states.hover);
    expect(reverse.hashCode, states.hover.hashCode);
    expect(
      states.copyWith(binding: const JsonTextBinding(path: 'other')),
      isNot(states),
    );
    expect(states.copyWith(clearHover: true), isNot(states));
    expect(states.copyWith(clearSelected: true), isNot(states));
    expect(states.copyWith(clearNamed: true), isNot(states));
    expect(states.copyWith(clearOrder: true), isNot(states));
    final legacy = states.toJson()..remove('order');
    expect(TextConfigStates.fromJson(legacy).order, [
      'ready',
      'done',
      TextConfigStates.hoverKey,
      TextConfigStates.selectedKey,
    ]);
  });

  test('collections are immutable snapshots and copy clear flags win', () {
    final bindings = {SuperTextProperty.color: binding};
    final named = {'ready': base.copyWith(propertyBindings: bindings)};
    final properties = {TextStateProperty.color};
    final order = ['ready'];
    final override = TextConfigOverride(
      config: named['ready']!,
      properties: properties,
    );
    final states = TextConfigStates(
      binding: binding,
      named: named,
      hover: override,
      selected: override,
      order: order,
    );
    named.clear();
    bindings.clear();
    properties.clear();
    order.clear();
    expect(states.named.length, 1);
    expect(states.named['ready']!.propertyBindings.length, 1);
    expect(override.config.propertyBindings.length, 1);
    expect(override.properties, {TextStateProperty.color});
    expect(states.order.first, 'ready');
    expect(() => states.named.clear(), throwsUnsupportedError);
    expect(() => states.order.clear(), throwsUnsupportedError);
    expect(
      () => states.named['ready']!.propertyBindings.clear(),
      throwsUnsupportedError,
    );
    expect(() => override.properties.clear(), throwsUnsupportedError);
    final cleared = states.copyWith(
      binding: binding,
      clearBinding: true,
      named: {'other': base},
      clearNamed: true,
      hover: override,
      clearHover: true,
      selected: override,
      clearSelected: true,
      order: ['ready'],
      clearOrder: true,
    );
    expect(cleared.binding, isNull);
    expect(cleared.named, isEmpty);
    expect(cleared.hover, isNull);
    expect(cleared.selected, isNull);
    expect(cleared.order, [
      TextConfigStates.hoverKey,
      TextConfigStates.selectedKey,
    ]);
    final changed = states.copyWith(named: {'other': base});
    expect(changed.order, [
      TextConfigStates.hoverKey,
      TextConfigStates.selectedKey,
      'other',
    ]);
  });

  test('nested states are rejected in constructors, edited and codecs', () {
    final nested = base.copyWith(states: TextConfigStates());
    expect(
      () => TextConfigStates(named: {'bad': nested}),
      throwsFormatException,
    );
    expect(() => TextConfigOverride(config: nested), throwsFormatException);
    expect(() => TextConfigOverride().edited(nested), throwsFormatException);
    for (final states in [
      {
        'named': {'bad': nested.toJson()},
      },
      {
        'named': {
          'bad': {...base.toJson(), 'states': null},
        },
      },
      {
        'named': {},
        'hover': {'config': nested.toJson(), 'properties': []},
      },
      {
        'named': {},
        'selected': {
          'config': {...base.toJson(), 'states': null},
          'properties': [],
        },
      },
    ]) {
      expect(() => TextConfigStates.fromJson(states), throwsFormatException);
    }
  });

  test('reserved names, unknown keys, types, duplicate order and properties reject', () {
    for (final name in [
      '',
      ' ',
      ' ready',
      'ready ',
      '\u0000hover',
      'DEFAULT',
      'Selected',
      'Hover',
      'Hovered',
      'Par défaut',
      'par defaut',
      'Sélectionné',
      'selectionne',
      'survol',
    ]) {
      expect(
        () => TextConfigStates(named: {name: base}),
        throwsFormatException,
      );
      expect(
        () => TextConfigStates.fromJson({
          'named': {name: base.toJson()},
        }),
        throwsFormatException,
      );
    }
    for (final value in <Object?>[
      null,
      [],
      {},
      {'named': []},
      {
        'named': {1: base.toJson()},
      },
      {'named': {}, 'extra': true},
      {'named': {}, 'order': null},
      {
        'named': {},
        'order': [1],
      },
      {
        'named': {},
        'order': ['missing'],
      },
      {
        'named': {},
        'order': [TextConfigStates.hoverKey, TextConfigStates.hoverKey],
      },
      {'named': {}, 'hover': null},
      {'named': {}, 'selected': []},
      {
        'named': {},
        'binding': {'path': ''},
      },
    ]) {
      expect(() => TextConfigStates.fromJson(value), throwsFormatException);
    }
    for (final value in <Object?>[
      null,
      {},
      {'config': base.toJson()},
      {'config': base.toJson(), 'properties': null},
      {
        'config': base.toJson(),
        'properties': ['missing'],
      },
      {
        'config': base.toJson(),
        'properties': ['color', 'color'],
      },
      {
        'config': base.toJson(),
        'properties': [1],
      },
      {'config': base.toJson(), 'properties': [], 'extra': 1},
    ]) {
      expect(() => TextConfigOverride.fromJson(value), throwsFormatException);
    }
    expect(() => TextConfigStates(order: ['unknown']), throwsFormatException);
    expect(
      () => SuperTextConfig.fromJson({
        ...base.toJson(),
        'states': {
          'named': {
            'bad': {'fontSize': 0},
          },
        },
      }),
      throwsFormatException,
    );
  });
}
