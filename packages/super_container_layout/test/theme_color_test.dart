import 'dart:convert';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/components/shared/editor_color_fields.dart';

void main() {
  const primary = ThemeColor(ThemeColorRole.primary);
  const onPrimary = ThemeColor(ThemeColorRole.onPrimary);
  final light = ColorScheme.fromSeed(seedColor: Colors.indigo);
  final dark = ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  );

  test('all Material 3 roles round-trip without a captured ARGB value', () {
    for (final role in ThemeColorRole.values) {
      final color = ThemeColor(role);
      color.validate();
      expect(JsonColor.parse(JsonColor.toJson(color)), color);
      expect(JsonColor.parse(JsonColor.toHex(color)), color);
      expect(color.toCompactJson(), 'theme:${role.name}');
      expect(resolveThemeColor(color, light), role.resolve(light));
      expect(resolveThemeColor(color, dark), role.resolve(dark));
      expect(color.copyWith(), color);
    }
    expect(primary, isNot(onPrimary));
    expect(primary.hashCode, primary.copyWith().hashCode);
    expect(primary, isNot(const Color(0x00000000)));
    expect(primary.toARGB32, throwsStateError);
    expect(() => JsonColor.parse('theme:notARole'), throwsFormatException);
    expect(() => JsonColor.parse('theme:'), throwsFormatException);
    expect(JsonColor.toJson(const Color(0x80123456)), 0x80123456);
    expect(JsonColor.toHex(const Color(0x80123456)), '#80123456');
  });

  test(
    'surface fills, shadows and neon preserve references in both codecs',
    () {
      const style = ContainerStyle(
        color: primary,
        borderColor: onPrimary,
        hoverColor: ThemeColor(ThemeColorRole.tertiary),
        fill: ContainerFill(
          type: FillType.linear,
          start: primary,
          end: onPrimary,
        ),
        neon: NeonStyle(enabled: true, color: primary),
        shadow: ShadowSpec(color: onPrimary),
        innerShadow: ShadowSpec(color: primary),
      );
      for (final json in [style.toJson(), style.toCompactJson()]) {
        final restored = ContainerStyle.fromJson(jsonDecode(jsonEncode(json)));
        expect(restored, style);
        expect(restored.hashCode, style.hashCode);
        expect(restored.resolveThemeColors(dark).color, dark.primary);
        expect(restored.resolveThemeColors(dark).fill.end, dark.onPrimary);
        expect(restored.resolveThemeColors(dark).shadow!.color, dark.onPrimary);
        expect(restored.resolveThemeColors(dark).neon!.color, dark.primary);
        expect(restored.color, primary);
      }
      expect(style, isNot(style.copyWith(color: onPrimary)));
      expect(style.fill, isNot(style.fill.copyWith(start: onPrimary)));
      expect(style.neon, isNot(style.neon!.copyWith(color: onPrimary)));
      expect(style.shadow, isNot(style.shadow!.copyWith(color: primary)));
    },
  );

  test(
    'standard component and input configurations retain theme references',
    () {
      final factories = <ComponentConfig Function(Object?)>[
        (json) => SuperValueConfig.fromJson(json),
        (json) => SuperActionConfig.fromJson(json),
        (json) => SuperIndicatorConfig.fromJson(json),
        (json) => SuperSeparatorConfig.fromJson(json),
      ];
      for (final factory in factories) {
        final config = factory({'color': 'theme:primary'});
        config.validate();
        expect(config.toJson()['color'], 'theme:primary');
        expect(
          factory(config.toJson()).toCompactJson()['color'],
          'theme:primary',
        );
        expect(
          factory(config.toCompactJson()).toJson()['color'],
          'theme:primary',
        );
      }
      final field = SuperTextFieldConfig.fromJson({
        'fillColor': 'theme:surfaceContainer',
        'focusBorderColor': 'theme:primary',
      });
      expect(field.toJson()['fillColor'], 'theme:surfaceContainer');
      expect(
        SuperTextFieldConfig.fromJson(field.toCompactJson()).focusBorderColor,
        primary,
      );
      final native = NativeComponentConfig(
        properties: {'backgroundColor': primary},
      );
      expect(
        NativeComponentConfig.fromJson(native.toJson())
            .colorProperty('backgroundColor'),
        primary,
      );
      const scrollbar = ScrollbarStyleConfig(thumbColor: primary);
      expect(
        ScrollbarStyleConfig.fromJson(scrollbar.toJson()).thumbColor,
        primary,
      );
    },
  );

  test(
    'editor hex fields also accept, validate and preserve semantic roles',
    () {
      expect(formatEditorColorHex(primary), 'theme:primary');
      expect(parseEditorColorHex(' theme:primary '), primary);
      expect(isEditorColorValue('theme:notARole'), isFalse);
      expect(
        () => parseEditorColorHex('theme:notARole'),
        throwsFormatException,
      );
      expect(formatEditorColorHex(const Color(0xFF123456)), 'ff123456');
      expect(parseEditorColorHex('ff123456'), const Color(0xFF123456));
      expect(parseEditorColorHex(''), isNull);
    },
  );

  test('Dart export keeps the semantic constructor', () {
    final context = DartCodegenContext(
      appearance: Appearance(),
      registry: Registry(),
    );
    expect(
      context.formatColor(primary, includeConst: true),
      'const ThemeColor(ThemeColorRole.primary)',
    );
  });

  test('appearance persistence and Vibe patches preserve semantic references', () {
    final appearance = Appearance(
      styles: const {'card': ContainerStyle(color: primary)},
      components: const {
        'value': SuperValueConfig(color: onPrimary),
      },
    );
    const codec = AppearanceCodec();
    final restored = codec.decode(codec.encode(appearance));
    expect(restored.styles['card']!.color, primary);
    expect(restored.valueComponent('value').color, onPrimary);
    final exported = AppearanceTransfer.exportAi(restored);
    final imported = AppearanceTransfer.import(
      Appearance(),
      exported,
      {TransferGroup.styles, TransferGroup.layouts},
    );
    expect(imported.styles['card']!.color, primary);
    expect(imported.valueComponent('value').color, onPrimary);
    final patched = AppearanceTransfer.applyVibe(imported, jsonEncode({
      'styles': {'card': {'borderColor': 'theme:outline'}},
    }));
    expect(patched.styles['card']!.color, primary);
    expect(patched.styles['card']!.borderColor,
        const ThemeColor(ThemeColorRole.outline));
    expect(() => Appearance(accent: primary), throwsArgumentError);
    expect(() => codec.decode('{"accent":"theme:primary"}'), throwsFormatException);
  });

  test(
    'background roles use requested brightness without a theme feedback loop',
    () {
      final appearance = Appearance(
        accent: Colors.indigo,
        styles: const {'background': ContainerStyle(color: primary)},
      );
      final theme = appearance.theme(Brightness.light);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.surface, theme.colorScheme.primary);
    },
  );

  Widget host(ColorScheme scheme, Widget child, {double width = 320}) =>
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorScheme: scheme),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );

  testWidgets('theme editor searches roles and preserves selection and reset', (
    tester,
  ) async {
    Color color = primary;
    var cleared = false;
    Widget editor() => StatefulBuilder(
      builder: (context, setState) => styleColorTile(
        'Couleur',
        color,
        (value) => setState(() => color = value),
        key: const ValueKey('test-color'),
        onClear: () => cleared = true,
      ),
    );
    await tester.pumpWidget(host(light, editor(), width: 280));
    expect(find.text('ColorScheme.primary'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('test-color')));
    await tester.pumpAndSettle();
    expect(find.text('Thème'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'surfaceContainerHigh');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('theme-color-surfaceContainerHigh')),
    );
    await tester.pumpAndSettle();
    expect(color, const ThemeColor(ThemeColorRole.surfaceContainerHigh));
    expect(find.text('ColorScheme.surfaceContainerHigh'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('test-color')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test-color')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'surfaceContainerHigh');
    await tester.tap(find.byKey(const ValueKey('test-color-clear')));
    expect(cleared, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom colors and opacity remain available', (tester) async {
    Color color = primary;
    await tester.pumpWidget(
      host(
        light,
        StatefulBuilder(
          builder: (context, setState) => styleColorTile(
            'Couleur',
            color,
            (value) => setState(() => color = value),
            key: const ValueKey('custom-color'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('custom-color')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personnalisée'));
    await tester.pumpAndSettle();
    expect(color, light.primary);
    final picker = tester.widget<ColorPicker>(find.byType(ColorPicker));
    expect(picker.enableOpacity, isTrue);
    picker.onColorChanged(const Color(0x80123456));
    await tester.pumpAndSettle();
    expect(color, const Color(0x80123456));
    expect(find.text('#80123456'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dense in [false, true]) {
    testWidgets('expanded color editor fits 240 px (dense: $dense)', (tester) async {
      await tester.pumpWidget(host(
        light,
        styleColorTile(
          'Une propriété de couleur avec un libellé long',
          primary,
          (_) {},
          key: const ValueKey('narrow-color'),
          dense: dense,
          onClear: () {},
        ),
        width: 240,
      ));
      await tester.tap(find.byKey(const ValueKey('narrow-color')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('bound hex fields validate a selected theme role', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(host(light, StatefulBuilder(
      builder: (context, setState) => Form(
        key: form,
        child: BoundHexColorField(
          controller: controller,
          label: 'Couleur liée',
          fallbackColor: light.primary,
          pickerKey: const ValueKey('bound-color'),
          fieldKey: const ValueKey('bound-hex'),
          inheritButtonKey: const ValueKey('inherit-color'),
          onChanged: () => setState(() {}),
        ),
      ),
    )));
    await tester.tap(find.byKey(const ValueKey('bound-color')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thème'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-color-onPrimary')));
    await tester.pumpAndSettle();
    expect(controller.text, 'theme:onPrimary');
    expect(form.currentState!.validate(), isTrue);
    expect(parseEditorColorHex(controller.text), onPrimary);
    await tester.tap(find.byKey(const ValueKey('bound-color-clear')));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('input state colors resolve before Material paints them', (tester) async {
    const config = SuperValueConfig(
      mode: SuperValueMode.input,
      initialText: 'Input',
      field: SuperTextFieldConfig(
        fillColor: primary,
        focusFillColor: onPrimary,
        borderColor: primary,
        focusBorderColor: onPrimary,
      ),
    );
    for (final scheme in [light, dark]) {
      await tester.pumpWidget(host(
        scheme,
        const SuperValue(id: 'semantic-input', config: config),
      ));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      final fill = field.decoration!.fillColor!;
      expect(WidgetStateProperty.resolveAs<Color>(fill, {}), scheme.primary);
      expect(WidgetStateProperty.resolveAs<Color>(fill, {WidgetState.focused}),
          scheme.onPrimary);
      expect(field.decoration!.enabledBorder!.borderSide.color, scheme.primary);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('runtime text and surface react to a changed ColorScheme', (
    tester,
  ) async {
    const surfaceKey = ValueKey('semantic-surface');
    const content = Column(
      children: [
        SuperValue(
          id: 'semantic-value',
          config: SuperValueConfig(initialText: 'Dynamic', color: primary),
        ),
        StyledSurface(
          key: surfaceKey,
          style: ContainerStyle(color: primary, borderColor: onPrimary),
          fallbackColor: Colors.white,
          borderColor: Colors.black,
          child: SizedBox(width: 100, height: 40),
        ),
      ],
    );
    for (final scheme in [light, dark]) {
      await tester.pumpWidget(host(scheme, content));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Dynamic')).style!.color,
        scheme.primary,
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(surfaceKey),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, scheme.primary);
      expect(tester.takeException(), isNull);
    }
  });
}
