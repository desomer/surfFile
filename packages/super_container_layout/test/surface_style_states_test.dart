import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';


void main() {
  test(
    'legacy named surfaces start empty and inherit until explicitly overridden',
    () {
      final states = SurfaceStyleStates(
        named: {'ready': const ContainerStyle(color: Colors.red, padding: 12)},
      );
      const base = ContainerStyle(color: Colors.blue, padding: 4);
      final legacy = states.toJson()..remove('namedProperties');
      final migrated = SurfaceStyleStates.fromJson(legacy);
      expect(migrated.namedProperties['ready'], isEmpty);
      expect(migrated.resolve(base, name: 'ready').padding, 4);
      final properties = <SurfaceStyleProperty>{SurfaceStyleProperty.padding};
      final configured = migrated.copyWith(
        namedProperties: {'ready': properties},
      );
      properties.clear();
      final result = configured.resolve(base, name: 'ready');
      expect(result.padding, 12);
      expect(result.color!.toARGB32(), Colors.blue.toARGB32());
      final decoded = SurfaceStyleStates.fromJson(
        jsonDecode(jsonEncode(configured.toJson())),
      );
      expect(decoded, configured);
      expect(
        () => decoded.namedProperties['ready']!.clear(),
        throwsUnsupportedError,
      );
      expect(configured.copyWith(named: {}).namedProperties, isEmpty);
      expect(
        () => SurfaceStyleStates.fromJson({
          ...legacy,
          'namedProperties': {
            'ready': ['unknown'],
          },
        }),
        throwsFormatException,
      );
      expect(
        () => SurfaceStyleStates.fromJson({
          ...legacy,
          'namedProperties': {'missing': []},
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'hover and selected follow persisted priority including JSON states',
    () {
      final states = SurfaceStyleStates(
        named: {'ready': const ContainerStyle(color: Colors.green, padding: 4)},
        namedProperties: {
          'ready': {
            SurfaceStyleProperty.background,
            SurfaceStyleProperty.padding,
          },
        },
        hover: SelectedSurfaceStyle(
          style: const ContainerStyle(color: Colors.red, padding: 0),
          properties: {
            SurfaceStyleProperty.background,
            SurfaceStyleProperty.padding,
          },
        ),
        selected: SelectedSurfaceStyle(
          style: const ContainerStyle(color: Colors.blue),
          properties: {SurfaceStyleProperty.background},
        ),
      );
      const base = ContainerStyle(color: Colors.grey, padding: 10);
      expect(states.order, [
        'ready',
        SurfaceStyleStates.hoverKey,
        SurfaceStyleStates.selectedKey,
      ]);
      expect(
        states.resolve(base, name: 'ready', isHovered: true).color,
        const Color(0xFFF44336),
      );
      expect(
        states
            .resolve(base, name: 'ready', isHovered: true, isSelected: true)
            .color,
        const Color(0xFF2196F3),
      );
      expect(
        states
            .resolve(base, name: 'ready', isHovered: true, isSelected: true)
            .padding,
        0,
      );
      final reordered = states.copyWith(
        order: [
          'ready',
          SurfaceStyleStates.selectedKey,
          SurfaceStyleStates.hoverKey,
        ],
      );
      expect(
        reordered
            .resolve(base, name: 'ready', isHovered: true, isSelected: true)
            .color,
        const Color(0xFFF44336),
      );
      final restored = SurfaceStyleStates.fromJson(
        jsonDecode(jsonEncode(reordered.toJson())),
      );
      expect(restored, reordered);
      expect(restored.hashCode, reordered.hashCode);
      expect(
        states
            .copyWith(
              order: [
                SurfaceStyleStates.hoverKey,
                'ready',
                SurfaceStyleStates.selectedKey,
              ],
            )
            .resolve(base, name: 'ready', isHovered: true)
            .color,
        const Color(0xFF4CAF50),
      );
      for (final order in [
        ['missing'],
        [SurfaceStyleStates.hoverKey, SurfaceStyleStates.hoverKey],
      ]) {
        expect(() => states.copyWith(order: order), throwsFormatException);
      }
      final legacy = {...states.toJson()}..remove('order');
      expect(SurfaceStyleStates.fromJson(legacy).order, states.order);
      expect(states.copyWith(clearHover: true).hover, isNull);
    },
  );

  test('JSON styles inherit unspecified groups and selected properties layer explicitly', () {
    final selected = SelectedSurfaceStyle(
      style: const ContainerStyle(
        color: null,
        radius: 0,
        opacity: 0,
        hoverEffect: false,
      ),
      properties: {
        SurfaceStyleProperty.background,
        SurfaceStyleProperty.corners,
        SurfaceStyleProperty.hover,
        SurfaceStyleProperty.opacity,
      },
    );
    final states = SurfaceStyleStates(
      named: {
        'late': const ContainerStyle(
          color: Colors.red,
          radius: 12,
          padding: 8,
          borderWidth: 2,
          hoverEffect: true,
        ),
      },
      selected: selected,
      namedProperties: {
        'late': {
          SurfaceStyleProperty.background,
          SurfaceStyleProperty.corners,
          SurfaceStyleProperty.padding,
          SurfaceStyleProperty.border,
          SurfaceStyleProperty.hover,
        },
      },
    );
    final base = ContainerStyle(
      color: Colors.blue,
      padding: 20,
      states: states,
    );
    expect(states.resolve(base, name: 'late').padding, 8);
    expect(states.resolve(base, name: 'unknown').color, Colors.blue);
    final active = states.resolve(base, name: 'late', isSelected: true);
    expect(active.color, isNull);
    expect(active.radius, 0);
    expect(active.opacity, 0);
    expect(active.hoverEffect, isFalse);
    expect(active.borderWidth, 2);
    expect(active.padding, 8);
    expect(active.states, isNull);
    expect(base.copyWith(padding: 24).states, same(states));
    expect(
      states.resolve(base.copyWith(color: Colors.green), name: 'late').color,
      const Color(0xFFF44336),
    );
  });

  test('state configuration round trips in appearances and style copies', () {
    final style = ContainerStyle(
      states: SurfaceStyleStates(
        binding: const JsonTextBinding(path: 'items[?].status'),
        named: {'ready': const ContainerStyle(color: Colors.green, padding: 4)},
        selected: SelectedSurfaceStyle(
          style: const ContainerStyle(borderWidth: 2),
          properties: {SurfaceStyleProperty.border},
        ),
      ),
    );
    const codec = AppearanceCodec();
    final restored = codec.decode(
      codec.encode(Appearance(styles: {'card': style})),
    );
    expect(
      jsonDecode(jsonEncode(restored.styles['card']!.toJson())),
      jsonDecode(jsonEncode(style.toJson())),
    );
    expect(
      style.withLookOf(const ContainerStyle(radius: 4)).states,
      same(style.states),
    );
    expect(
      ContainerStyle.fromJson(const ContainerStyle().toJson()).states,
      isNull,
    );
    expect(() => style.states!.named.clear(), throwsUnsupportedError);
    expect(restored.styles['card']!.states, style.states);
    expect(restored.styles['card']!.states.hashCode, style.states.hashCode);
    const defaultCodec = DefaultAppearanceCodec();
    expect(
      defaultCodec
          .decode(
            defaultCodec.encode(DefaultAppearance(styles: {'card': style})),
          )
          .styles['card']!
          .states,
      style.states,
    );
  });

  test(
    'invalid names, nested definitions and invalid selection properties fail',
    () {
      for (final name in [
        '',
        '  ',
        ' selected ',
        'Par défaut',
        'Sélectionné',
        '\u0000selected',
      ]) {
        expect(
          () => SurfaceStyleStates(named: {name: const ContainerStyle()}),
          throwsFormatException,
        );
      }
      final recursive = ContainerStyle(states: SurfaceStyleStates());
      expect(
        () => SurfaceStyleStates(named: {'a': recursive}),
        throwsFormatException,
      );
      expect(
        () => SelectedSurfaceStyle(style: recursive),
        throwsFormatException,
      );
      expect(
        () => SurfaceStyleStates.fromJson({
          'named': {'a': recursive.toJson()},
        }),
        throwsFormatException,
      );
      expect(
        () => SelectedSurfaceStyle.fromJson({
          'style': const ContainerStyle().toJson(),
          'properties': ['invalid'],
        }),
        throwsFormatException,
      );
    },
  );

  test('editing selected values records only changed property groups', () {
    final selected = SelectedSurfaceStyle(
      style: const ContainerStyle(color: Colors.blue, radius: 8),
    ).edited(const ContainerStyle(color: Colors.blue, radius: 0));
    expect(selected.properties, {SurfaceStyleProperty.corners});
    expect(
      selected.apply(const ContainerStyle(color: Colors.red, radius: 12)).color,
      const Color(0xFFF44336),
    );
    expect(selected.apply(const ContainerStyle(radius: 12)).radius, 0);
  });
}
