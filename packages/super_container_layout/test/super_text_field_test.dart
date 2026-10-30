import 'dart:convert';

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/components/super_text_field.dart';
import 'package:super_container_layout/widgets/editing/components/super_value_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native text context menu remains enabled outside editing', (
    tester,
  ) async {
    final mode = ValueNotifier(true);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: mode,
          child: const Scaffold(
            body: SizedBox(
              width: 300,
              height: 80,
              child: SuperValue(
                id: 'native-menu',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  initialText: 'Selectable text',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).contextMenuBuilder,
      isNull,
    );
    mode.value = false;
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).contextMenuBuilder,
      isNotNull,
    );
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.widget.focusNode.requestFocus();
    await tester.pumpAndSettle();
    editable.widget.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 10,
    );
    await tester.tap(find.byType(TextField), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('all input options round trip with defaults and strict validation', () {
    const field = SuperTextFieldConfig(
      variant: TextFieldVariant.outlined,
      fillColor: Colors.red,
      focusFillColor: Colors.blue,
      disabledFillColor: Colors.grey,
      errorFillColor: Colors.orange,
      borderColor: Colors.green,
      focusBorderColor: Colors.pink,
      disabledBorderColor: Colors.black,
      errorBorderColor: Colors.purple,
      radius: 15,
      borderWidth: 3,
      horizontalPadding: 20,
      verticalPadding: 16,
      dense: false,
      prefixText: '€',
      suffixText: 'kg',
      prefixIcon: TextFieldIcon.person,
      suffixIcon: TextFieldIcon.check,
      suffix: TextFieldSuffix.clear,
      helperText: 'Help',
      errorText: 'Error',
      showCounter: true,
      maxLength: 40,
      filter: TextFieldFilter.pattern,
      pattern: '[A-Z]',
      keyboard: TextFieldKeyboard.email,
      action: TextFieldAction.next,
      capitalization: TextCapitalization.words,
      verticalAlign: TextFieldVerticalAlign.center,
      floatingLabel: FloatingLabelBehavior.always,
      autocorrect: false,
      suggestions: false,
    );
    const config = SuperValueConfig(mode: SuperValueMode.input, field: field);
    final decoded = SuperValueConfig.fromJson(
      jsonDecode(jsonEncode(config.toJson())),
    );
    expect(decoded, config);
    expect(decoded.hashCode, config.hashCode);
    expect(
      SuperValueConfig.fromJson(<String, dynamic>{}).field,
      const SuperTextFieldConfig(),
    );
    expect(const SuperValueConfig().toJson().containsKey('field'), isFalse);
    expect(
      config.copyWith(field: const SuperTextFieldConfig()).field,
      const SuperTextFieldConfig(),
    );
    expect(
      field
          .copyWith(
            inheritFillColor: true,
            clearMaxLength: true,
            clearPrefixIcon: true,
            inheritRadius: true,
          )
          .fillColor,
      isNull,
    );
    expect(field.copyWith(clearMaxLength: true).maxLength, isNull);
    expect(field.copyWith(clearPrefixIcon: true).prefixIcon, isNull);
    expect(field.copyWith(inheritRadius: true).radius, isNull);
    expect(field.copyWith(inheritFloatingLabel: true).floatingLabel, isNull);
    for (final json in [
      {'radius': -1},
      {'borderWidth': double.nan},
      {'maxLength': 0},
      {'maxLength': 2.5},
      {'variant': 'unknown'},
      {'prefixIcon': 'bogus'},
      {'filter': 'pattern', 'pattern': '['},
      {'filter': 'pattern', 'pattern': 'a*'},
      {'filter': 'pattern', 'pattern': '(?=a)'},
      {'unknown': true},
      {'autocorrect': null},
    ]) {
      expect(() => SuperTextFieldConfig.fromJson(json), throwsFormatException);
    }
    expect(
      () => const SuperValueConfig(
        field: SuperTextFieldConfig(action: TextFieldAction.newline),
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const SuperValueConfig(
        obscureText: true,
        field: SuperTextFieldConfig(keyboard: TextFieldKeyboard.multiline),
      ).validate(),
      throwsFormatException,
    );
  });

  Future<void> mount(
    WidgetTester tester,
    SuperValueConfig config, {
    TextEditingController? controller,
    ValueChanged<String>? onChanged,
    InputDecorationThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(inputDecorationTheme: theme),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: SuperValue(
                id: 'field',
                config: config,
                controller: controller,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder getInput() => find.byKey(const ValueKey('super-value-input-field'));
  TextField input(WidgetTester tester) => tester.widget<TextField>(getInput());

  for (final variant in TextFieldVariant.values) {
    testWidgets('$variant renders without changing display mode', (
      tester,
    ) async {
      final config = SuperValueConfig(
        mode: SuperValueMode.input,
        label: 'Name',
        field: SuperTextFieldConfig(variant: variant),
      );

      await mount(tester, config);
      final decoration = input(tester).decoration!;
      switch (variant) {
        case TextFieldVariant.theme:
          expect(decoration.border, isNull);
        case TextFieldVariant.filled:
          expect(decoration.filled, isTrue);
          expect(decoration.border, isA<UnderlineInputBorder>());
        case TextFieldVariant.outlined:
          expect(decoration.border, isA<OutlineInputBorder>());
        case TextFieldVariant.underline:
          expect(decoration.border, isA<UnderlineInputBorder>());
        case TextFieldVariant.borderless:
          expect(decoration.border, InputBorder.none);
      }
      await mount(
        tester,
        config.copyWith(mode: SuperValueMode.display, initialText: 'Display'),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Display'), findsOneWidget);
      expect(
        tester
            .widget<InputDecorator>(find.byType(InputDecorator))
            .decoration
            .border,
        InputBorder.none,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('theme defaults and widths remain inherited', (tester) async {
    const theme = InputDecorationThemeData(
      filled: true,
      fillColor: Colors.amber,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.teal, width: 4),
      ),
    );
    await mount(
      tester,
      const SuperValueConfig(mode: SuperValueMode.input),
      theme: theme,
    );
    expect(input(tester).decoration!.filled, isNull);
    expect(input(tester).decoration!.border, isNull);
    expect(input(tester).decoration!.fillColor, isNull);
    expect(input(tester).decoration!.floatingLabelBehavior, isNull);
    expect(
      tester
          .widget<InputDecorator>(find.byType(InputDecorator))
          .decoration
          .floatingLabelBehavior,
      FloatingLabelBehavior.always,
    );
    await mount(
      tester,
      const SuperValueConfig(
        mode: SuperValueMode.input,
        field: SuperTextFieldConfig(radius: 24),
      ),
      theme: theme,
    );
    expect(
      input(tester).decoration!.focusedBorder!.borderSide,
      const BorderSide(color: Colors.teal, width: 4),
    );
    expect(input(tester).decoration!.focusedBorder, isA<OutlineInputBorder>());
  });

  testWidgets('colors, borders and padding are resolved for each field state', (
    tester,
  ) async {
    const field = SuperTextFieldConfig(
      variant: TextFieldVariant.outlined,
      radius: 20,
      borderWidth: 3,
      horizontalPadding: 10,
      verticalPadding: 8,
      fillColor: Colors.red,
      focusFillColor: Colors.green,
      disabledFillColor: Colors.blue,
      errorFillColor: Colors.orange,
      borderColor: Colors.black,
      focusBorderColor: Colors.pink,
      disabledBorderColor: Colors.grey,
      errorBorderColor: Colors.purple,
    );
    await mount(
      tester,
      const SuperValueConfig(mode: SuperValueMode.input, field: field),
    );
    final decoration = input(tester).decoration!;
    expect(decoration.enabledBorder!.borderSide.color, Colors.black);
    expect(decoration.focusedBorder!.borderSide.color, Colors.pink);
    expect(decoration.disabledBorder!.borderSide.color, Colors.grey);
    expect(decoration.errorBorder!.borderSide.color, Colors.purple);
    expect(decoration.focusedErrorBorder!.borderSide.color, Colors.purple);
    expect(
      decoration.contentPadding,
      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
    expect(
      (decoration.border as OutlineInputBorder).borderRadius,
      BorderRadius.circular(20),
    );
    expect(decoration.border!.borderSide.width, 3);
    for (final entry in <Set<WidgetState>, Color>{
      {}: Colors.red,
      {WidgetState.focused}: Colors.green,
      {WidgetState.disabled}: Colors.blue,
      {WidgetState.error}: Colors.orange,
      {WidgetState.focused, WidgetState.error}: Colors.orange,
    }.entries) {
      expect(
        WidgetStateProperty.resolveAs<Color>(decoration.fillColor!, entry.key),
        entry.value,
      );
    }
    await tester.tap(getInput());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clear action calls onChanged once and respects readOnly and disabled',
    (tester) async {
      var changes = 0;
      final controller = TextEditingController(text: 'Value');
      addTearDown(controller.dispose);
      const config = SuperValueConfig(
        mode: SuperValueMode.input,
        field: SuperTextFieldConfig(suffix: TextFieldSuffix.clear),
      );
      await mount(
        tester,
        config,
        controller: controller,
        onChanged: (_) => changes++,
      );
      await tester.tap(find.byTooltip('Effacer'));
      await tester.pumpAndSettle();
      expect(controller.text, '');
      expect(changes, 1);
      for (final restricted in [
        config.copyWith(readOnly: true),
        config.copyWith(enabled: false),
      ]) {
        controller.text = 'Keep';
        await mount(
          tester,
          restricted,
          controller: controller,
          onChanged: (_) => changes++,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton && widget.tooltip == 'Effacer',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(controller.text, 'Keep');
      }
      expect(changes, 1);
    },
  );

  testWidgets(
    'clear supports controlled value without changing its ownership',
    (tester) async {
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuperValue(
              id: 'controlled',
              value: 'Owned by parent',
              onChanged: (_) => changes++,
              config: const SuperValueConfig(
                mode: SuperValueMode.input,
                field: SuperTextFieldConfig(suffix: TextFieldSuffix.clear),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Effacer'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Owned by parent');
      expect(changes, 1);
    },
  );

  testWidgets('password visibility is local and never re-enables suggestions', (
    tester,
  ) async {
    const config = SuperValueConfig(
      mode: SuperValueMode.input,
      obscureText: true,
      field: SuperTextFieldConfig(suffix: TextFieldSuffix.visibility),
    );
    await mount(tester, config);
    await tester.enterText(getInput(), 'secret');
    await tester.tap(find.byTooltip('Afficher le mot de passe'));
    await tester.pumpAndSettle();
    expect(input(tester).obscureText, isFalse);
    expect(input(tester).enableSuggestions, isFalse);
    expect(input(tester).autocorrect, isFalse);
    expect(config.obscureText, isTrue);
    expect(jsonEncode(config.toJson()), isNot(contains('secret')));
    await tester.tap(find.byTooltip('Masquer le mot de passe'));
    await tester.pumpAndSettle();
    expect(input(tester).obscureText, isTrue);
    expect(input(tester).controller!.text, 'secret');
  });

  testWidgets(
    'filters and max length affect edits but never truncate injected values',
    (tester) async {
      final controller = TextEditingController(text: 'Programmatic content');
      addTearDown(controller.dispose);
      const config = SuperValueConfig(
        mode: SuperValueMode.input,
        field: SuperTextFieldConfig(
          filter: TextFieldFilter.digits,
          maxLength: 3,
          showCounter: true,
        ),
      );
      await mount(tester, config, controller: controller);
      expect(controller.text, 'Programmatic content');
      await tester.enterText(getInput(), 'a12345b');
      await tester.pumpAndSettle();
      expect(controller.text, '123');
      expect(find.text('3 / 3'), findsOneWidget);
      controller.text = 'Unfiltered longer';
      await tester.pumpAndSettle();
      expect(controller.text, 'Unfiltered longer');
      expect(find.text('17 / 3'), findsOneWidget);
    },
  );

  testWidgets(
    'maxLength counts graphemes and counter can be hidden or unlimited',
    (tester) async {
      const config = SuperValueConfig(
        mode: SuperValueMode.input,
        field: SuperTextFieldConfig(maxLength: 2, showCounter: true),
      );
      await mount(tester, config);
      await tester.enterText(getInput(), '👨‍👩‍👧‍👦e\u0301Z');
      await tester.pumpAndSettle();
      expect(input(tester).controller!.text, '👨‍👩‍👧‍👦e\u0301');
      expect(find.text('2 / 2'), findsOneWidget);
      await mount(
        tester,
        config.copyWith(field: const SuperTextFieldConfig(showCounter: true)),
      );
      expect(find.text('2'), findsOneWidget);
      await mount(
        tester,
        config.copyWith(field: const SuperTextFieldConfig(maxLength: 2)),
      );
      expect(find.text('2 / 2'), findsNothing);
    },
  );

  test(
    'filters handle Unicode, partial decimals, regex and IME composition',
    () {
      TextEditingValue filter(
        TextFieldFilter kind,
        String value, {
        String pattern = '',
      }) {
        return superTextInputFormatters(
          SuperTextFieldConfig(filter: kind, pattern: pattern),
        ).single.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: value),
        );
      }

      expect(
        filter(TextFieldFilter.letters, "Éléonore e\u0301 O’Neil-42_😊").text,
        "Éléonore e\u0301 O’Neil-",
      );
      expect(
        filter(TextFieldFilter.pattern, 'A1B2C3', pattern: '[A-Z]').text,
        'ABC',
      );
      for (final value in ['', '-', '+', '.', '-.', '-12.5']) {
        expect(filter(TextFieldFilter.decimal, value).text, value);
      }
      for (final value in ['1.2.3', '--1', '1-2', '1a']) {
        expect(filter(TextFieldFilter.decimal, value).text, '');
      }
      final formatter = superTextInputFormatters(
        const SuperTextFieldConfig(filter: TextFieldFilter.digits),
      ).single;
      const composing = TextEditingValue(
        text: 'a1',
        composing: TextRange(start: 0, end: 2),
      );
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, composing),
        composing,
      );
      expect(
        formatter
            .formatEditUpdate(
              composing,
              composing.copyWith(composing: TextRange.empty),
            )
            .text,
        '1',
      );
    },
  );

  testWidgets(
    'keyboard, action, ornaments, vertical align and label are wired',
    (tester) async {
      await mount(
        tester,
        const SuperValueConfig(
          mode: SuperValueMode.input,
          maxLines: 4,
          field: SuperTextFieldConfig(
            keyboard: TextFieldKeyboard.multiline,
            action: TextFieldAction.newline,
            capitalization: TextCapitalization.sentences,
            verticalAlign: TextFieldVerticalAlign.top,
            floatingLabel: FloatingLabelBehavior.always,
            prefixText: 'Before',
            suffixText: 'After',
            prefixIcon: TextFieldIcon.person,
            suffixIcon: TextFieldIcon.check,
            helperText: 'Help',
            errorText: 'Error',
            autocorrect: false,
            suggestions: false,
          ),
        ),
      );
      final field = input(tester);
      expect(field.keyboardType, TextInputType.multiline);
      expect(field.textInputAction, TextInputAction.newline);
      expect(field.textCapitalization, TextCapitalization.sentences);
      expect(field.textAlignVertical, TextAlignVertical.top);
      expect(field.decoration!.prefixText, 'Before');
      expect(field.decoration!.suffixText, 'After');
      expect(
        field.decoration!.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
      expect(field.decoration!.helperText, 'Help');
      expect(field.decoration!.errorText, 'Error');
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    },
  );

  testWidgets(
    'editor preview applies field options locally and cancel stays atomic',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SuperValueConfig? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showSuperValueEditor(
                  context: context,
                  config: const SuperValueConfig(
                    mode: SuperValueMode.input,
                    initialText: 'Draft',
                  ),
                  availableFontFamilies: const [],
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final panel = tester.widget<StyleEditorPanel>(
        find.byType(StyleEditorPanel),
      );
      expect(panel.sections.first.id, 'value-states');
      expect(panel.sections.map((section) => section.id), [
        'value-states',
        'value-repository',
        'value-content',
        'value-behavior',
        'value-typography',
        'value-color',
        'value-spacing',
        'text-field-style',
        'text-field-colors',
        'text-field-ornaments',
        'text-field-messages',
        'text-field-filters',
        'text-field-keyboard',
      ]);
      for (final section in panel.sections.where(
        (section) => section.id.startsWith('text-field-'),
      )) {
        final card = find.byKey(ValueKey('style-card-${section.id}'));
        expect(card, findsOneWidget);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final dropdown = find.byKey(
        const ValueKey('text-field-setting-variant-theme'),
      );
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: dropdown, matching: find.text('Outlined')),
      );
      await tester.pumpAndSettle();
      final preview = find.descendant(
        of: find.byKey(const ValueKey('super-value-preview')),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(preview).decoration!.border,
        isA<OutlineInputBorder>(),
      );
      expect(result, isNull);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );

  testWidgets('editor applies valid options and rejects invalid drafts', (
    tester,
  ) async {
    StyleEditorPanel.preferredDense = false;
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SuperValueConfig? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showSuperValueEditor(
                context: context,
                config: const SuperValueConfig(mode: SuperValueMode.input),
                availableFontFamilies: const [],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final radius = find.byKey(const ValueKey('text-field-setting-radius'));
    await tester.ensureVisible(radius);
    await tester.enterText(radius, '-1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(
      find.byKey(const ValueKey('text-field-settings-error')),
      findsOneWidget,
    );
    await tester.enterText(radius, '18');
    await tester.pumpAndSettle();
    final filter = find.byKey(const ValueKey('text-field-setting-filter-none'));
    await tester.ensureVisible(filter);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: filter,
        matching: find.text('Expression régulière'),
      ),
    );
    await tester.pumpAndSettle();
    final pattern = find.byKey(const ValueKey('text-field-setting-pattern'));
    await tester.ensureVisible(pattern);
    await tester.enterText(pattern, '[');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.enterText(pattern, '[a-z]');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(result!.field.radius, 18);
    expect(result!.field.filter, TextFieldFilter.pattern);
    expect(result!.field.pattern, '[a-z]');
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode filters cards and keeps field drafts across switches', (
    tester,
  ) async {
    StyleEditorPanel.preferredDense = false;
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SuperValueConfig? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showSuperValueEditor(
                context: context,
                config: const SuperValueConfig(),
                availableFontFamilies: const [],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    void checkMode(bool input) {
      final panel = tester.widget<StyleEditorPanel>(
        find.byType(StyleEditorPanel),
      );
      expect(panel.sections.first.id, 'value-states');
      expect(
        panel.sections.where((section) => section.id.startsWith('text-field-')),
        hasLength(input ? 6 : 0),
      );
      for (final key in ['readOnly', 'enabled', 'minLines', 'obscureText']) {
        expect(
          find.byKey(ValueKey('super-value-setting-$key')),
          input ? findsOneWidget : findsNothing,
        );
      }
      expect(
        find.byKey(const ValueKey('super-value-setting-maxLines')),
        findsOneWidget,
      );
    }

    Future<void> mode(String label) async {
      final field = find.byKey(const ValueKey('super-value-setting-mode'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: field, matching: find.text(label)),
      );
      await tester.pumpAndSettle();
    }

    checkMode(false);
    await mode('Saisie');
    checkMode(true);
    final radius = find.byKey(const ValueKey('text-field-setting-radius'));
    await tester.ensureVisible(radius);
    await tester.enterText(radius, '18');
    await tester.pumpAndSettle();
    await mode('Affichage');
    checkMode(false);
    await mode('Saisie');
    checkMode(true);
    expect(tester.widget<TextFormField>(radius).controller!.text, '18');
    await tester.ensureVisible(radius);
    await tester.enterText(radius, '-1');
    await tester.pumpAndSettle();
    await mode('Affichage');
    checkMode(false);
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(result!.mode, SuperValueMode.display);
    expect(result!.field.radius, 18);
    expect(tester.takeException(), isNull);
  });

  testWidgets('field settings fit a narrow editor', (tester) async {
    StyleEditorPanel.preferredDense = false;
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSuperValueEditor(
                context: context,
                config: const SuperValueConfig(),
                availableFontFamilies: const [],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final initial = find.byKey(
      const ValueKey('super-value-setting-initialText'),
    );
    await tester.ensureVisible(initial);
    await tester.enterText(initial, 'Preview draft');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-dense-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-dense-toggle')));
    await tester.pumpAndSettle();
    final panel = tester.widget<StyleEditorPanel>(
      find.byType(StyleEditorPanel),
    );
    expect(panel.sections.first.id, 'value-states');
    for (final section in panel.sections) {
      await tester.ensureVisible(
        find.byKey(ValueKey('style-card-${section.id}')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(
      tester.widget<TextFormField>(initial).controller!.text,
      'Preview draft',
    );
    expect(tester.takeException(), isNull);
  });
}
