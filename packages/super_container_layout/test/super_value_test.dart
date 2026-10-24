import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/components/super_value_editor.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    StyleEditorPanel.preferredDense = false;
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });
  tearDown(() {
    for (final channel in [
      const MethodChannel('com.alexmercerind/flutter_acrylic'),
      WindowTransparency.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  const initial = SuperValueConfig(initialText: 'Initial');
  const input = SuperValueConfig(
    mode: SuperValueMode.input,
    initialText: 'Initial',
  );

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  );

  Future<void> mount(
    WidgetTester tester,
    Registry registry,
    Widget page,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => page)],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(SuperApp(router: router, registry: registry));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'SuperApp edits persist atomically and undo resets without saving runtime input',
    (tester) async {
      final registry = Registry()..bootstrap(availableFontFamilies: ['Roboto']);
      await mount(
        tester,
        registry,
        const SuperPage(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 80),
              child: SizedBox(
                width: 320,
                child: SuperValue(id: 'persisted', config: input),
              ),
            ),
          ),
        ),
      );
      StyleEditScope.controllerOf(tester.element(find.byType(SuperValue)))!
              .value =
          true;
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SuperValue));
      final history = EditorHistoryScope.controllerOf(context)!;
      final appearance = AppearanceScope.controllerOf(context)!;
      final design = registry.valueController('persisted');
      final before = const AppearanceCodec().encode(appearance.value);
      await tester.enterText(find.byType(TextField), 'Never persisted');
      await tester.pumpAndSettle();
      expect(const AppearanceCodec().encode(appearance.value), before);
      expect(history.canUndo, isFalse);
      await tester.tap(find.byType(TextField), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valeur'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('super-value-settings')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('super-value-setting-initialText')),
        'Saved design',
      );
      final radius = find.byKey(const ValueKey('text-field-setting-radius'));
      await tester.ensureVisible(radius);
      await tester.enterText(radius, '17');
      await tester.pumpAndSettle();
      expect(history.canUndo, isFalse);
      expect(design.value, input);
      final live = tester.widget<TextField>(
        find.byKey(const ValueKey('super-value-input-persisted')),
      );
      expect(live.controller!.text, 'Saved design');
      expect(
        (live.decoration!.border as UnderlineInputBorder).borderRadius,
        BorderRadius.circular(17),
      );
      expect(const AppearanceCodec().encode(appearance.value), before);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(design.value.initialText, 'Saved design');
      expect(design.value.field.radius, 17);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Saved design',
      );
      expect(history.canUndo, isTrue);
      final store = AppearanceStore();
      await store.save(appearance.value);
      expect((await store.load()).valueComponents['persisted'], design.value);
      history.undo();
      await tester.pumpAndSettle();
      expect(design.value, input);
      expect(history.canUndo, isFalse);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Initial',
      );
      history.redo();
      await tester.pumpAndSettle();
      expect(design.value.initialText, 'Saved design');
      expect(design.value.field.radius, 17);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog instances compose inside native bars and grid without sharing state',
    (tester) async {
      final registry = Registry()..bootstrap(availableFontFamilies: ['Roboto']);
      registry.valueController('bar-text', fallback: input);
      registry.valueController('bottom-text', fallback: initial);
      registry.valueController(
        'grid-text',
        fallback: initial.copyWith(initialText: 'Grid'),
      );
      final layout = const SuperLayoutConfig(
        north: false,
        south: false,
        east: false,
        west: false,
        placements: {
          SuperLayoutZone.center: ['grid-text'],
        },
        slotTypes: {'grid-text': 'registry:Value'},
      ).withPositioning(SuperLayoutPositioning.grid);
      await mount(
        tester,
        registry,
        SuperPage(
          appBar: SuperAppBar(
            id: 'bar',
            nativeConfig: NativeComponentConfig(
              placements: {
                'title': ['bar-text'],
              },
              slotTypes: {'bar-text': 'factory:Value'},
            ),
          ),
          bottomNavigationBar: SuperBottomNavigationBar(
            id: 'bottom',
            nativeConfig: NativeComponentConfig(
              placements: {
                'left': ['bottom-text'],
              },
              slotTypes: {'bottom-text': 'factory:Value'},
            ),
          ),
          child: SuperLayout(config: layout),
        ),
      );
      expect(find.byType(SuperValue), findsNWidgets(3));
      expect(find.text('Grid'), findsOneWidget);
      expect(
        tester
            .widget<SuperValue>(find.byType(SuperValue).first)
            .availableFontFamilies,
        ['Roboto'],
      );
      await tester.enterText(find.byType(TextField), 'Only bar');
      await tester.pumpAndSettle();
      expect(find.text('Only bar'), findsOneWidget);
      expect(find.text('Initial'), findsOneWidget);
      expect(find.text('Grid'), findsOneWidget);
      expect(registry.valueController('bar-text').value, input);
      expect(tester.takeException(), isNull);
    },
  );

  test('config round trips all fields and restores inherited typography', () {
    const config = SuperValueConfig(
      mode: SuperValueMode.input,
      initialText: 'Bonjour',
      label: 'Nom',
      placeholder: 'Votre nom',
      enabled: false,
      readOnly: true,
      minLines: 2,
      maxLines: 4,
      fontFamily: 'Roboto',
      fontSize: 18,
      fontWeight: FontWeight.w600,
      italic: true,
      color: Color(0xFF123456),
      textAlign: TextAlign.center,
      lineHeight: 1.4,
      letterSpacing: -.5,
      propertyBindings: {
        SuperValueProperty.label: JsonTextBinding(
          repositoryId: '0123456789abcdef0123456789abcdef',
          path: 'client.name',
        ),
        SuperValueProperty.color: JsonTextBinding(path: 'client.color'),
      },
    );
    final decoded = SuperValueConfig.fromJson(
      jsonDecode(jsonEncode(config.toJson())),
    );
    expect(decoded, config);
    expect(decoded.hashCode, config.hashCode);
    expect(
      SuperValueConfig.fromJson(<String, dynamic>{}).propertyBindings,
      isEmpty,
    );
    final inherited = decoded.copyWith(
      inheritFontFamily: true,
      inheritFontSize: true,
      inheritFontWeight: true,
      inheritItalic: true,
      inheritColor: true,
      inheritLineHeight: true,
      inheritLetterSpacing: true,
    );
    expect(inherited.fontFamily, isNull);
    expect(inherited.fontSize, isNull);
    expect(inherited.fontWeight, isNull);
    expect(inherited.italic, isNull);
    expect(inherited.color, isNull);
    expect(inherited.lineHeight, isNull);
    expect(inherited.letterSpacing, isNull);
    expect(SuperValueConfig.fromJson(<String, dynamic>{}).italic, isNull);
    expect(SuperValueConfig.fromJson({'italic': null}).italic, isNull);
    for (final italic in [false, true]) {
      final explicit = inherited.copyWith(italic: italic);
      expect(SuperValueConfig.fromJson(explicit.toJson()).italic, italic);
    }
  });

  test(
    'strict config rejects malformed fields and unsafe password defaults',
    () {
      for (final json in <Object?>[
        null,
        [],
        {'unknown': true},
        {'mode': 'other'},
        {'enabled': 'yes'},
        {'italic': 'yes'},
        {'minLines': 1.5},
        {'minLines': 0},
        {'minLines': 3, 'maxLines': 2},
        {'fontSize': 0},
        {'lineHeight': -1},
        {'letterSpacing': double.infinity},
        {'fontWeight': 450},
        {'fontFamily': ''},
        {'color': -1},
        {'obscureText': true, 'initialText': 'secret'},
        {'obscureText': true, 'maxLines': 2},
        {
          'propertyBindings': {
            'unknown': {'path': 'client.name'},
          },
        },
        {
          'propertyBindings': {
            'label': {'path': ''},
          },
        },
      ]) {
        expect(() => SuperValueConfig.fromJson(json), throwsFormatException);
      }
      const password = SuperValueConfig(obscureText: true);
      expect(password.toJson().containsKey('initialText'), isFalse);
      expect(SuperValueConfig.fromJson(password.toJson()), password);
      expect(
        () => const SuperValueConfig(
          obscureText: true,
          initialText: 'secret',
        ).toJson(),
        throwsArgumentError,
      );
    },
  );

  for (final mode in SuperValueMode.values) {
    testWidgets('$mode inherits the native AppBar title style', (
      tester,
    ) async {
      const titleStyle = TextStyle(
        fontSize: 27,
        fontWeight: FontWeight.w800,
        fontStyle: FontStyle.italic,
        color: Colors.purple,
        height: 1.2,
        letterSpacing: 1.7,
      );
      final registry = Registry()..bootstrap();
      await mount(
        tester,
        registry,
        Theme(
          data: ThemeData(
            appBarTheme: const AppBarTheme(titleTextStyle: titleStyle),
          ),
          child: SuperPage(
            appBar: SuperAppBar(
              id: 'styled-bar',
              title: SuperValue(
                id: 'title-style',
                config: SuperValueConfig(mode: mode, initialText: 'Title'),
              ),
            ),
          ),
        ),
      );
      final style = mode == SuperValueMode.display
          ? tester
                .widget<Text>(
                  find.byKey(const ValueKey('super-value-display-title-style')),
                )
                .style!
          : tester.widget<TextField>(find.byType(TextField)).style!;
      expect(style.fontSize, titleStyle.fontSize);
      expect(style.fontWeight, titleStyle.fontWeight);
      expect(style.fontStyle, titleStyle.fontStyle);
      expect(style.color, titleStyle.color);
      expect(style.height, titleStyle.height);
      expect(style.letterSpacing, titleStyle.letterSpacing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$mode inherits parent typography but respects explicit overrides',
      (tester) async {
        const parentStyle = TextStyle(
          fontFamily: 'ParentFont',
          fontSize: 26,
          fontWeight: FontWeight.w800,
          fontStyle: FontStyle.italic,
          color: Colors.purple,
          height: 1.2,
          letterSpacing: 1.7,
        );
        Widget text(SuperValueConfig config) => host(
          DefaultTextStyle(
            style: parentStyle,
            child: SuperValue(id: 'inherit', config: config),
          ),
        );
        TextStyle style() => mode == SuperValueMode.display
            ? tester
                  .widget<Text>(
                    find.byKey(const ValueKey('super-value-display-inherit')),
                  )
                  .style!
            : tester.widget<TextField>(find.byType(TextField)).style!;
        final config = SuperValueConfig(mode: mode, initialText: 'Parent');
        await tester.pumpWidget(text(config));
        expect(style(), parentStyle);
        await tester.pumpWidget(
          text(
            config.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w400,
              italic: false,
              color: Colors.red,
            ),
          ),
        );
        expect(style().fontSize, 18);
        expect(style().fontWeight, FontWeight.w400);
        expect(style().fontStyle, FontStyle.normal);
        expect(style().color, Colors.red);
        expect(style().fontFamily, 'ParentFont');
        expect(style().height, 1.2);
        expect(style().letterSpacing, 1.7);
      },
    );
  }

  for (final catalog in [false, true]) {
    testWidgets(
      'display title is vertically centered (${catalog ? 'catalog' : 'direct'})',
      (tester) async {
        final registry = Registry()..bootstrap();
        registry.valueController('centered-title', fallback: initial);
        await mount(
          tester,
          registry,
          SuperPage(
            appBar: SuperAppBar(
              id: 'centered-bar',
              toolbarHeight: 80,
              title: catalog
                  ? null
                  : const SuperValue(id: 'centered-title', config: initial),
              nativeConfig: catalog
                  ? NativeComponentConfig(
                      placements: {
                        'title': ['centered-title'],
                      },
                      slotTypes: {'centered-title': 'factory:Value'},
                    )
                  : null,
            ),
          ),
        );
        final title = find.byKey(
          const ValueKey('super-value-display-centered-title'),
        );
        final toolbar = find.byType(NavigationToolbar);
        expect(
          tester.getCenter(title).dy,
          closeTo(tester.getCenter(toolbar).dy, .5),
        );
        expect(
          find.descendant(
            of: find.byType(SuperValue),
            matching: find.byType(InputDecorator),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'display centers within tight slots and retains labels and multiline',
    (tester) async {
      for (final config in [
        initial,
        initial.copyWith(initialText: '', placeholder: 'Placeholder'),
        initial.copyWith(
          initialText: 'First\nSecond',
          minLines: 2,
          maxLines: 2,
        ),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              key: const ValueKey('tight-text-slot'),
              height: 120,
              child: SuperValue(id: 'tight', config: config),
            ),
          ),
        );
        final text = find.byKey(const ValueKey('super-value-display-tight'));
        expect(
          tester.getCenter(text).dy,
          closeTo(
            tester.getCenter(find.byKey(const ValueKey('tight-text-slot'))).dy,
            .5,
          ),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(
        host(
          SizedBox(
            height: 120,
            child: SuperValue(
              id: 'tight',
              config: initial.copyWith(label: 'Label'),
            ),
          ),
        ),
      );
      expect(find.byType(InputDecorator), findsOneWidget);
      expect(find.text('Label'), findsOneWidget);
      expect(find.text('Initial'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('font style editor selects inherited normal and italic', (
    tester,
  ) async {
    for (final choice in ['Normal', 'Italique', 'Style du parent']) {
      SuperValueConfig? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showSuperValueEditor(
                context: context,
                config: initial.copyWith(italic: true),
                availableFontFamilies: [],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final dropdown = find.byKey(const ValueKey('super-value-setting-italic'));
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(
        result!.italic,
        choice == 'Style du parent' ? null : choice == 'Italique',
      );
    }
  });

  for (final screen in [const Size(1440, 900), const Size(400, 700)]) {
    testWidgets(
      'text panel adapts to $screen with local preview and dense mode',
      (tester) async {
        await tester.binding.setSurfaceSize(screen);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SuperValueConfig? result;
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showSuperValueEditor(
                  context: context,
                  config: initial,
                  availableFontFamilies: ['Roboto'],
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(StyleEditorPanel), findsOneWidget);
        expect(
          find.byKey(const ValueKey('super-value-preview')),
          findsOneWidget,
        );
        for (final id in [
          'value-content',
          'value-behavior',
          'value-typography',
          'value-color',
          'value-spacing',
        ]) {
          expect(find.byKey(ValueKey('style-card-$id')), findsOneWidget);
        }
        final field = find.byKey(
          const ValueKey('super-value-setting-initialText'),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, 'Preview draft');
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('super-value-preview')),
            matching: find.text('Preview draft'),
          ),
          findsOneWidget,
        );
        expect(result, isNull);
        await tester.tap(find.byKey(const ValueKey('style-dense-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('super-value-preview')), findsNothing);
        expect(
          tester.widget<TextFormField>(field).controller!.text,
          'Preview draft',
        );
        await tester.tap(find.byKey(const ValueKey('style-dense-toggle')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('super-value-preview')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(result, isNull);
      },
    );
  }

  testWidgets(
    'text palette and inherited color update only the draft preview',
    (tester) async {
      SuperValueConfig? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showSuperValueEditor(
                context: context,
                config: initial.copyWith(color: Colors.red),
                availableFontFamilies: [],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final color = find.byKey(const ValueKey('super-value-setting-color'));
      await tester.ensureVisible(color);
      await tester.enterText(color, 'ff0000ff');
      await tester.pumpAndSettle();
      final preview = find.descendant(
        of: find.byKey(const ValueKey('super-value-preview')),
        matching: find.text('Initial'),
      );
      expect(
        tester.widget<Text>(preview).style!.color,
        const Color(0xFF0000FF),
      );
      final reset = find.byKey(const ValueKey('super-value-inherit-color'));
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(color).controller!.text, '');
      expect(result, isNull);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(result!.color, isNull);
    },
  );

  test('appearance codecs transfer reset and subtype preserve text design', () {
    const codec = DefaultAppearanceCodec();
    const styled = SuperValueConfig(
      initialText: 'Initial',
      field: SuperTextFieldConfig(
        variant: TextFieldVariant.filled,
        radius: 12,
        maxLength: 40,
        suffix: TextFieldSuffix.clear,
      ),
    );
    final appearance = DefaultAppearance(cardWidth: 222)
        .withValueComponent('title', styled);
    expect(appearance.cardWidth, 222);
    final decoded = codec.decode(codec.encode(appearance)) as DefaultAppearance;
    expect(decoded.valueComponents, {'title': styled});
    expect(decoded.cardWidth, 222);
    expect(decoded.copyWith(spacing: 20).valueComponents, {'title': styled});
    expect(decoded.resetLayouts().valueComponents, isEmpty);
    final legacy = codec.toJson(appearance)..remove('valueComponents');
    expect(codec.fromJson(legacy).valueComponents, isEmpty);
    final exported = AppearanceTransfer.export(appearance, {
      TransferGroup.layouts,
    }, codec: codec);
    final imported = AppearanceTransfer.import(
      DefaultAppearance(cardWidth: 240),
      exported,
      {TransferGroup.layouts},
      codec: codec,
    ) as DefaultAppearance;
    expect(imported.valueComponents, {'title': styled});
    expect(imported.cardWidth, 240);
    final styles = AppearanceTransfer.export(appearance, {
      TransferGroup.styles,
    }, codec: codec);
    expect(jsonDecode(styles)['data'].containsKey('valueComponents'), isFalse);
    final invalid = codec.toJson(appearance)..['valueComponents'] = {'a': 'bad'};
    expect(() => codec.fromJson(invalid), throwsFormatException);
  });

  test(
    'registry synchronizes history defaults rebinds and independent instances',
    () {
      final registry = Registry()..bootstrap();
      final appearance = ValueNotifier<Appearance>(Appearance());
      final edit = ValueNotifier(true);
      final history = EditorHistoryController(
        appearance: appearance,
        editMode: edit,
      );
      registry.bindAppearance(appearance);
      final a = registry.valueController('a', fallback: initial);
      final b = registry.valueController('b');
      a.value = input;
      expect(appearance.value.valueComponents['a'], input);
      expect(b.value, const SuperValueConfig());
      history.undo();
      expect(a.value, initial);
      history.redo();
      expect(a.value, input);
      appearance.value = appearance.value.resetLayouts();
      expect(a.value, initial);
      registry.unbindAppearance();
      a.value = input;
      expect(appearance.value.valueComponents, isEmpty);
      final second = ValueNotifier<Appearance>(
        Appearance(valueComponents: {'a': initial}),
      );
      registry.bindAppearance(second);
      expect(a.value, initial);
      expect(registry.registry['Value']!.tags, {'text', 'input'});
      final firstWidget = registry.registry['Value']!.getWidget(
        XuiBuildCtx(id: 'x'),
      );
      final secondWidget = registry.registry['Value']!.getWidget(
        XuiBuildCtx(id: 'y'),
      );
      expect((firstWidget as SuperValue).id, 'x');
      expect((secondWidget as SuperValue).id, 'y');
      registry.unbindAppearance();
      history.dispose();
      appearance.dispose();
      second.dispose();
      edit.dispose();
    },
  );

  testWidgets(
    'local input initializes once resets on mode and initial changes only',
    (tester) async {
      final events = <String>[];
      Widget text(SuperValueConfig config) =>
          host(SuperValue(id: 'local', config: config, onChanged: events.add));
      await tester.pumpWidget(text(input));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Initial',
      );
      expect(events, isEmpty);
      await tester.enterText(find.byType(TextField), 'Saisi');
      expect(events, ['Saisi']);
      await tester.pumpWidget(text(input.copyWith(fontSize: 20)));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Saisi',
      );
      await tester.pumpWidget(text(initial));
      await tester.pump();
      expect(find.text('Initial'), findsOneWidget);
      expect(events, ['Saisi', 'Initial']);
      await tester.pumpWidget(text(initial.copyWith(initialText: 'Nouveau')));
      await tester.pump();
      expect(find.text('Nouveau'), findsOneWidget);
      expect(events, ['Saisi', 'Initial', 'Nouveau']);
      await tester.pumpWidget(text(initial.copyWith(initialText: 'Nouveau')));
      await tester.pump();
      expect(events.length, 3);
    },
  );

  testWidgets(
    'external controllers keep ownership and receive reset exactly once',
    (tester) async {
      final first = TextEditingController(text: 'Application');
      final second = TextEditingController(text: 'Autre');
      final events = <String>[];
      Widget text(TextEditingController controller, SuperValueConfig config) =>
          host(
            SuperValue(
              id: 'bound',
              controller: controller,
              config: config,
              onChanged: events.add,
            ),
          );
      await tester.pumpWidget(text(first, initial));
      expect(find.text('Application'), findsOneWidget);
      expect(events, isEmpty);
      first.text = 'Mise à jour';
      await tester.pump();
      expect(find.text('Mise à jour'), findsOneWidget);
      await tester.pumpWidget(text(second, initial));
      expect(find.text('Autre'), findsOneWidget);
      await tester.pumpWidget(text(second, input));
      await tester.pump();
      expect(second.text, 'Initial');
      expect(second.selection, const TextSelection.collapsed(offset: 7));
      expect(second.value.composing, TextRange.empty);
      expect(events, ['Initial']);
      expect(first.text, 'Mise à jour');
      await tester.pumpWidget(const SizedBox());
      first.text = 'Still owned';
      second.text = 'Still owned';
      first.dispose();
      second.dispose();
    },
  );

  testWidgets(
    'value binding is controlled and resets notify parent without overriding value',
    (tester) async {
      final events = <String>[];
      var config = input;
      var value = 'Parent';
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return SuperValue(
                id: 'controlled',
                config: config,
                value: value,
                onChanged: (next) {
                  events.add(next);
                  update(() => value = next);
                },
              );
            },
          ),
        ),
      );
      expect(events, isEmpty);
      await tester.enterText(find.byType(TextField), 'Nouveau');
      await tester.pump();
      expect(value, 'Nouveau');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Nouveau',
      );
      update(() => config = initial);
      await tester.pumpAndSettle();
      expect(value, 'Initial');
      expect(events, ['Nouveau', 'Initial']);
    },
  );

  testWidgets(
    'password masks display and semantics and clears text when enabled',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController(text: 'Secret');
      final events = <String>[];
      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'password',
            config: const SuperValueConfig(obscureText: true),
            controller: controller,
            onChanged: events.add,
          ),
        ),
      );
      expect(find.text('Secret'), findsNothing);
      expect(find.text('\u2022' * 6), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('super-value-display-password')),
            )
            .getSemanticsData()
            .label,
        isNot(contains('Secret')),
      );
      expect(events, isEmpty);
      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'password',
            config: const SuperValueConfig(
              mode: SuperValueMode.input,
              obscureText: true,
            ),
            controller: controller,
            onChanged: events.add,
          ),
        ),
      );
      await tester.pump();
      expect(controller.text, '');
      expect(events, ['']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'password',
            config: const SuperValueConfig(mode: SuperValueMode.input),
            controller: controller,
          ),
        ),
      );
      controller.text = 'New secret';
      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'password',
            config: const SuperValueConfig(
              mode: SuperValueMode.input,
              obscureText: true,
            ),
            controller: controller,
            onChanged: events.add,
          ),
        ),
      );
      await tester.pump();
      expect(controller.text, '');
      expect(events, ['', '']);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      semantics.dispose();
    },
  );

  testWidgets('controlled parent may reject edits and reset notifications', (
    tester,
  ) async {
    final events = <String>[];
    Widget text(SuperValueConfig config) => host(
      SuperValue(
        id: 'fixed',
        config: config,
        value: 'Fixed',
        onChanged: events.add,
      ),
    );
    await tester.pumpWidget(text(input));
    await tester.enterText(find.byType(TextField), 'Rejected');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Fixed',
    );
    await tester.pumpWidget(text(initial));
    await tester.pump();
    expect(find.text('Fixed'), findsOneWidget);
    expect(events, ['Rejected', 'Initial']);
  });

  testWidgets(
    'input gives only the editor menu while editing and restores the native menu',
    (tester) async {
      final edit = ValueNotifier(true);
      addTearDown(edit.dispose);
      await tester.pumpWidget(
        host(
          StyleEditScope(
            controller: edit,
            child: const SuperValue(id: 'menu-mode', config: input),
          ),
        ),
      );
      await tester.tap(find.byType(TextField), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-menu-Valeur')), findsOneWidget);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.contextMenuBuilder, isNull);
      expect(field.enableInteractiveSelection, isTrue);
      expect(field.readOnly, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      edit.value = false;
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-menu-Valeur')), findsNothing);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).contextMenuBuilder,
        isNotNull,
      );
      edit.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      await tester.tap(find.byType(TextField), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-menu-Valeur')), findsOneWidget);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('input keeps native text menu when visual editing is disabled', (
    tester,
  ) async {
    final edit = ValueNotifier(false);
    await tester.pumpWidget(
      host(
        StyleEditScope(
          controller: edit,
          child: const SuperValue(id: 'runtime', config: input),
        ),
      ),
    );
    await tester.tap(find.byType(TextField), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('style-menu-Valeur')), findsNothing);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    edit.dispose();
  });

  testWidgets('display and input compose in unbounded-width bar actions', (
    tester,
  ) async {
    for (final config in [initial, input]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [SuperValue(id: 'action', config: config)],
            ),
            bottomNavigationBar: SizedBox(
              height: 56,
              child: Row(
                children: [SuperValue(id: 'bottom', config: config)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'typography multiline readOnly disabled and missing fonts render',
    (tester) async {
      final edit = ValueNotifier(true);
      await tester.pumpWidget(
        host(
          StyleEditScope(
            controller: edit,
            child: SuperValue(
              id: 'style',
              config: input.copyWith(
                label: 'Nom',
                placeholder: 'Votre nom',
                minLines: 2,
                maxLines: 4,
                enabled: false,
                readOnly: true,
                fontFamily: 'Unavailable',
                fontSize: 21,
                fontWeight: FontWeight.w700,
                italic: true,
                color: Colors.red,
                textAlign: TextAlign.end,
                lineHeight: 1.5,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
      expect(field.readOnly, isTrue);
      expect(field.minLines, 2);
      expect(field.maxLines, 4);
      expect(field.style!.fontSize, 21);
      expect(field.style!.fontWeight, FontWeight.w700);
      expect(field.style!.fontStyle, FontStyle.italic);
      expect(field.style!.color, Colors.red);
      expect(field.style!.height, 1.5);
      expect(field.style!.letterSpacing, 2);
      expect(field.textAlign, TextAlign.end);
      expect(
        find.byKey(const ValueKey('super-value-font-warning-style')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      edit.dispose();
    },
  );

  testWidgets(
    'dialog cancel never resets text and apply publishes one config',
    (tester) async {
      final controller = TextEditingController(text: 'Runtime');
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      final configs = <SuperValueConfig>[];
      final events = <String>[];
      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'editor',
            config: initial,
            controller: controller,
            onConfigChanged: configs.add,
            onChanged: events.add,
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(
          find.byKey(const ValueKey('super-value-display-editor')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('style-menu-Valeur')),
            matching: find.text('Value'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('style-menu-Valeur')));
        await tester.pumpAndSettle();
      }

      await open();
      await tester.enterText(
        find.byKey(const ValueKey('super-value-setting-initialText')),
        'Draft',
      );
      await tester.pumpAndSettle();
      expect(find.text('Draft'), findsWidgets);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('super-value-display-editor')),
            )
            .data,
        'Draft',
      );
      expect(controller.text, 'Runtime');
      expect(events, isEmpty);
      expect(
        tester.getCenter(find.text('Annuler')).dx,
        lessThan(tester.getCenter(find.text('Appliquer')).dx),
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Runtime');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('super-value-display-editor')),
            )
            .data,
        'Runtime',
      );
      expect(configs, isEmpty);
      expect(events, isEmpty);
      await open();
      await tester.enterText(
        find.byKey(const ValueKey('super-value-setting-label')),
        'Temporary label',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InputDecorator>(
              find
                  .descendant(
                    of: find.byType(SuperValue),
                    matching: find.byType(InputDecorator),
                  )
                  .first,
            )
            .decoration
            .labelText,
        'Temporary label',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('super-value-settings')), findsNothing);
      expect(controller.text, 'Runtime');
      expect(configs, isEmpty);
      await open();
      await tester.enterText(
        find.byKey(const ValueKey('super-value-setting-initialText')),
        'Applied',
      );
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(configs.single.initialText, 'Applied');
      expect(controller.text, 'Applied');
      expect(events, ['Applied']);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'live password styling keeps runtime content and cancels safely',
    (tester) async {
      final controller = TextEditingController(text: 'secret');
      final events = <String>[];
      await tester.pumpWidget(
        host(
          SuperValue(
            id: 'live-password',
            controller: controller,
            onChanged: events.add,
            config: const SuperValueConfig(
              mode: SuperValueMode.input,
              obscureText: true,
            ),
          ),
        ),
      );
      final live = find.byKey(const ValueKey('super-value-input-live-password'));
      await tester.tap(live, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-menu-Valeur')));
      await tester.pumpAndSettle();
      final radius = find.byKey(const ValueKey('text-field-setting-radius'));
      await tester.ensureVisible(radius);
      await tester.enterText(radius, '19');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(live).obscureText, isTrue);
      expect(tester.widget<TextField>(live).controller!.text, 'secret');
      expect(controller.text, 'secret');
      expect(events, isEmpty);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(live).controller, same(controller));
      expect(controller.text, 'secret');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'dialog password clears defaults and validates numeric typography',
    (tester) async {
      SuperValueConfig? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showSuperValueEditor(
                context: context,
                config: initial.copyWith(minLines: 2, maxLines: 3),
                availableFontFamilies: ['Roboto'],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('super-value-setting-obscureText')),
      );
      await tester.tap(
        find.byKey(const ValueKey('super-value-setting-obscureText')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('super-value-setting-initialText')),
        findsNothing,
      );
      final size = find.byKey(const ValueKey('super-value-setting-fontSize'));
      await tester.ensureVisible(size);
      await tester.enterText(size, '-4');
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Valeur numérique valide requise.'), findsOneWidget);
      await tester.enterText(size, '18');
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(result!.obscureText, isTrue);
      expect(result!.initialText, '');
      expect(result!.minLines, 1);
      expect(result!.maxLines, 1);
      expect(result!.fontSize, 18);
      expect(result!.toJson().containsKey('initialText'), isFalse);
    },
  );

  test('boolean kinds round trip and reject obscureText', () {
    for (final kind in [
      SuperValueKind.checkbox,
      SuperValueKind.switchControl,
    ]) {
      final config = SuperValueConfig(
        mode: SuperValueMode.input,
        kind: kind,
        initialBool: true,
        label: 'Actif',
      );
      final decoded = SuperValueConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())),
      );
      expect(decoded, config);
      expect(decoded.hashCode, config.hashCode);
      expect(
        () => SuperValueConfig(kind: kind, obscureText: true).validate(),
        throwsArgumentError,
      );
    }
    expect(
      SuperValueConfig.fromJson({'kind': 'switch'}).kind,
      SuperValueKind.switchControl,
    );
    expect(
      () => SuperValueConfig.fromJson({'kind': 'invalid'}),
      throwsFormatException,
    );
  });

  testWidgets('checkbox and switch render and toggle in input mode only', (
    tester,
  ) async {
    final boolEvents = <bool>[];
    final textEvents = <String>[];
    await tester.pumpWidget(
      host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SuperValue(
              id: 'cb',
              config: const SuperValueConfig(
                mode: SuperValueMode.input,
                kind: SuperValueKind.checkbox,
                initialBool: false,
                label: 'Case',
              ),
              onBoolChanged: boolEvents.add,
              onChanged: textEvents.add,
            ),
            const SuperValue(
              id: 'sw-display',
              config: SuperValueConfig(
                mode: SuperValueMode.display,
                kind: SuperValueKind.switchControl,
                initialBool: true,
                label: 'Interrupteur',
              ),
            ),
          ],
        ),
      ),
    );
    final cbFinder = find.byKey(const ValueKey('super-value-checkbox-cb'));
    final swFinder = find.byKey(
      const ValueKey('super-value-switch-sw-display'),
    );
    expect(tester.widget<Checkbox>(cbFinder).value, isFalse);
    expect(tester.widget<Switch>(swFinder).value, isTrue);
    expect(tester.widget<Switch>(swFinder).onChanged, isNull);

    await tester.tap(cbFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(cbFinder).value, isTrue);
    expect(boolEvents, [true]);
    expect(textEvents, ['true']);

    await tester.tap(find.byKey(const ValueKey('super-value-label-cb')));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(cbFinder).value, isFalse);
    expect(boolEvents, [true, false]);
    expect(textEvents, ['true', 'false']);
  });

  testWidgets('editor configures checkbox and switch with initialBool', (
    tester,
  ) async {
    SuperValueConfig? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showSuperValueEditor(
              context: context,
              config: initial,
              availableFontFamilies: const [],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final kindDropdown = find.byKey(const ValueKey('super-value-setting-kind'));
    await tester.ensureVisible(kindDropdown);
    await tester.tap(kindDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Case à cocher (Checkbox)').last);
    await tester.pumpAndSettle();
    final initBool = find.byKey(
      const ValueKey('super-value-setting-initialBool'),
    );
    await tester.ensureVisible(initBool);
    await tester.tap(initBool);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(result!.kind, SuperValueKind.checkbox);
    expect(result!.initialBool, isTrue);
  });
}
