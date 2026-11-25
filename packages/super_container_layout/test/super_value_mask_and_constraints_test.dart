import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/components/super_value_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PatternMask', () {
    test('strips and formats digits, letters, case transforms and escapes', () {
      final dateMask = PatternMask('##/##/####');
      expect(dateMask.slotCount, 8);
      expect(dateMask.strip('19/05/2026'), '19052026');
      expect(dateMask.strip('19052026'), '19052026');
      expect(dateMask.format('19052026'), '19/05/2026');
      expect(dateMask.format('1905'), '19/05');
      expect(dateMask.format('19'), '19');
      expect(dateMask.isComplete('19052026'), isTrue);
      expect(dateMask.isComplete('1905'), isFalse);

      final plateMask = PatternMask('UU-###-UU');
      expect(plateMask.format('ab123cd'), 'AB-123-CD');
      expect(plateMask.strip('ab-123-cd'), 'AB123CD');

      final phoneMask = PatternMask('+33 # ## ## ## ##');
      expect(phoneMask.format('612345678'), '+33 6 12 34 56 78');
      expect(phoneMask.strip('+33 6 12 34 56 78'), '612345678');
      expect(phoneMask.format(''), '');

      final escaped = PatternMask(r'\#UU-LL-**');
      expect(escaped.format('abCD1a'), '#AB-cd-1a');
    });

    test('handles backspace across literal separators cleanly', () {
      final mask = PatternMask('##/##/####');
      final outcome = mask.edit(
        oldText: '12/05',
        newText: '1205',
        oldCursor: 3,
        newCursor: 2,
        oldSelectionCollapsed: true,
        newSelectionCollapsed: true,
      );
      expect(outcome.text, '10/5');
      expect(outcome.cursorOffset, 1);
    });

    test('rejects masks without slots or dangling escape', () {
      expect(() => PatternMask.validatePattern('---'), throwsFormatException);
      expect(() => PatternMask.validatePattern(r'##\'), throwsFormatException);
    });
  });

  group('NumberFieldFormat & DateFieldFormat', () {
    test('formats and unformats decimal and thousands separators', () {
      expect(
        NumberFieldFormat.formatDisplay(
          '1234.5',
          decimalDigits: 2,
          decimalSeparator: ',',
          thousandsSeparator: ' ',
        ),
        '1 234,50',
      );
      expect(
        NumberFieldFormat.formatDisplay(
          '1234.5',
          decimalDigits: 2,
          decimalSeparator: ',',
          thousandsSeparator: ' ',
          focused: true,
        ),
        '1234,5',
      );
      expect(
        NumberFieldFormat.toStorage(
          '1 234,50',
          decimalSeparator: ',',
          thousandsSeparator: ' ',
        ),
        '1234.50',
      );
    });

    test('converts ISO dates to display pattern and back strictly', () {
      expect(
        DateFieldFormat.formatDisplay('2026-05-19', 'dd/MM/yyyy'),
        '19/05/2026',
      );
      expect(
        DateFieldFormat.tryToIso('19/05/2026', 'dd/MM/yyyy'),
        '2026-05-19',
      );
      expect(DateFieldFormat.tryToIso('31/02/2026', 'dd/MM/yyyy'), isNull);
    });
  });

  group('SuperTextFieldConfig masks & JSON Schema validation', () {
    test('round-trips toJson, toCompactJson and fromJson with aliases', () {
      const field = SuperTextFieldConfig(
        mask: '##/##/####',
        maskIncludeLiterals: true,
        decimalDigits: 2,
        decimalSeparator: ',',
        thousandsSeparator: ' ',
        dateFormat: 'dd/MM/yyyy',
        valueType: TextFieldValueType.number,
        required: true,
        minLength: 3,
        maxLength: 20,
        validationPattern: r'^\d+$',
        format: TextFieldFormat.dateTime,
        minimum: -10.5,
        maximum: 100.5,
        exclusiveMinimum: -11,
        exclusiveMaximum: 101,
        multipleOf: 0.5,
        enumValues: ['A', 'B'],
        constValue: 'A',
        validationMessage: 'Erreur personnalisée',
      );
      final json = jsonDecode(jsonEncode(field.toJson())) as Map<String, dynamic>;
      final restored = SuperTextFieldConfig.fromJson(json);
      expect(restored, field);
      expect(restored.hashCode, field.hashCode);

      final compact = field.toCompactJson();
      expect(compact['format'], 'date-time');
      expect(SuperTextFieldConfig.fromJson(compact), field);
      expect(
        SuperTextFieldConfig.fromJson({'format': 'url'}).format,
        TextFieldFormat.uri,
      );
    });

    test('rejects inconsistent bounds, separators and mask combinations', () {
      for (final invalid in [
        const SuperTextFieldConfig(minLength: -1),
        const SuperTextFieldConfig(minLength: 5, maxLength: 3),
        const SuperTextFieldConfig(validationPattern: '['),
        const SuperTextFieldConfig(mask: '---'),
        const SuperTextFieldConfig(decimalDigits: 11),
        const SuperTextFieldConfig(decimalSeparator: ';'),
        const SuperTextFieldConfig(
          decimalSeparator: ',',
          thousandsSeparator: ',',
        ),
        const SuperTextFieldConfig(multipleOf: 0),
        const SuperTextFieldConfig(minimum: 10, maximum: 5),
        const SuperTextFieldConfig(exclusiveMinimum: 5, exclusiveMaximum: 5),
        const SuperTextFieldConfig(minimum: 5, exclusiveMaximum: 5),
        const SuperTextFieldConfig(exclusiveMinimum: 5, maximum: 5),
      ]) {
        expect(() => invalid.validate(), throwsFormatException);
      }
      expect(
        () => const SuperValueConfig(
          obscureText: true,
          field: SuperTextFieldConfig(mask: '####'),
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => const SuperValueConfig(
          maxLines: 3,
          field: SuperTextFieldConfig(mask: '####'),
        ).validate(),
        throwsFormatException,
      );
    });

    test('validates all JSON Schema constraints', () {
      expect(
        const SuperTextFieldConfig(required: true).validateValue('   '),
        'Ce champ est obligatoire.',
      );
      expect(
        const SuperTextFieldConfig(
          minLength: 4,
          validationMessage: 'Trop court',
        ).validateValue('abc'),
        'Trop court',
      );
      expect(
        const SuperTextFieldConfig(
          valueType: TextFieldValueType.integer,
          minimum: 1,
          maximum: 10,
          multipleOf: 2,
        ).validateValue('4.5'),
        isNotNull,
      );
      expect(
        const SuperTextFieldConfig(
          valueType: TextFieldValueType.integer,
          minimum: 1,
          maximum: 10,
          multipleOf: 2,
        ).validateValue('4'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          valueType: TextFieldValueType.number,
          exclusiveMinimum: 0,
          exclusiveMaximum: 1,
          multipleOf: 0.1,
        ).validateValue('0.3'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          valueType: TextFieldValueType.number,
          exclusiveMinimum: 0,
        ).validateValue('0'),
        isNotNull,
      );
      expect(
        const SuperTextFieldConfig(
          validationPattern: r'^[A-Z]{2}\d{3}$',
        ).validateValue('AB123'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          validationPattern: r'^[A-Z]{2}\d{3}$',
        ).validateValue('AB12'),
        isNotNull,
      );
      expect(
        const SuperTextFieldConfig(
          enumValues: ['draft', 'published'],
        ).validateValue('archived'),
        isNotNull,
      );
      expect(
        const SuperTextFieldConfig(constValue: 'OK').validateValue('NO'),
        isNotNull,
      );

      // Formats
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.email,
        ).validateValue('a@b.fr'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.email,
        ).validateValue('invalid'),
        isNotNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.uri,
        ).validateValue('https://example.com/a'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.uuid,
        ).validateValue('123e4567-e89b-12d3-a456-426614174000'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.date,
        ).validateValue('2026-02-30'),
        isNotNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.dateTime,
        ).validateValue('2026-05-19T14:30:00Z'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.time,
        ).validateValue('23:59:59'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.ipv4,
        ).validateValue('192.168.1.1'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.ipv4,
        ).validateValue('256.1.1.1'),
        isNotNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.ipv6,
        ).validateValue('2001:db8::1'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.hostname,
        ).validateValue('api.example.com'),
        isNull,
      );
      expect(
        const SuperTextFieldConfig(
          format: TextFieldFormat.phone,
        ).validateValue('+33 6 12 34 56 78'),
        isNull,
      );
    });
  });

  group('SuperValue runtime masks, validation & AutomaticState.invalid', () {
    testWidgets('display mode formats pattern mask, date and numbers', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SuperValue(
                  id: 'phone',
                  config: SuperValueConfig(
                    initialText: '0612345678',
                    field: SuperTextFieldConfig(mask: '## ## ## ## ##'),
                  ),
                ),
                SuperValue(
                  id: 'date',
                  config: SuperValueConfig(
                    initialText: '2026-05-19',
                    field: SuperTextFieldConfig(dateFormat: 'dd/MM/yyyy'),
                  ),
                ),
                SuperValue(
                  id: 'amount',
                  config: SuperValueConfig(
                    initialText: '1234.5',
                    field: SuperTextFieldConfig(
                      decimalDigits: 2,
                      decimalSeparator: ',',
                      thousandsSeparator: ' ',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('06 12 34 56 78'), findsOneWidget);
      expect(find.text('19/05/2026'), findsOneWidget);
      expect(find.text('1 234,50'), findsOneWidget);
    });

    testWidgets(
      'input mask formats live and emits raw or masked values per config',
      (tester) async {
        final rawEvents = <String>[];
        final maskedEvents = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 240,
                    child: SuperValue(
                      id: 'raw',
                      onChanged: rawEvents.add,
                      config: const SuperValueConfig(
                        mode: SuperValueMode.input,
                        field: SuperTextFieldConfig(mask: 'UU-###-UU'),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: SuperValue(
                      id: 'masked',
                      onChanged: maskedEvents.add,
                      config: const SuperValueConfig(
                        mode: SuperValueMode.input,
                        field: SuperTextFieldConfig(
                          mask: 'UU-###-UU',
                          maskIncludeLiterals: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rawInput = find.byKey(const ValueKey('super-value-input-raw'));
        await tester.enterText(rawInput, 'ab123cd');
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(rawInput).controller!.text, 'AB-123-CD');
        expect(rawEvents.last, 'AB123CD');

        final maskedInput = find.byKey(
          const ValueKey('super-value-input-masked'),
        );
        await tester.enterText(maskedInput, 'ab123cd');
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(maskedInput).controller!.text,
          'AB-123-CD',
        );
        expect(maskedEvents.last, 'AB-123-CD');
      },
    );

    testWidgets(
      'validation shows after touch/blur and activates AutomaticState.invalid without clearing input',
      (tester) async {
        final config = SuperValueConfig(
          mode: SuperValueMode.input,
          field: const SuperTextFieldConfig(
            required: true,
            minLength: 3,
            validationPattern: r'^[a-z]+$',
          ),
          states: ValueConfigStates(
            automatic: {
              AutomaticState.invalid: ValueConfigOverride(
                config: const SuperValueConfig(color: Colors.red),
                properties: {ValueStateProperty.color},
              ),
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 260,
                    child: SuperValue(id: 'v', config: config),
                  ),
                  const TextField(key: ValueKey('other')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final inputFinder = find.byKey(const ValueKey('super-value-input-v'));
        final indicatorFinder = find.byKey(
          const ValueKey('super-value-error-indicator-v'),
        );
        String? tooltipMessage() {
          if (indicatorFinder.evaluate().isEmpty) return null;
          return tester
              .widget<Tooltip>(
                find.descendant(
                  of: indicatorFinder,
                  matching: find.byType(Tooltip),
                ),
              )
              .message;
        }

        // Silent before touch or blur
        final initialHeight = tester.getSize(inputFinder).height;
        expect(indicatorFinder, findsNothing);
        expect(
          tester.widget<TextField>(inputFinder).decoration!.errorText,
          isNull,
        );
        expect(tester.widget<TextField>(inputFinder).style!.color, isNot(Colors.red));

        // Focus then blur without typing -> shows red Excel triangle + Tooltip & invalid state
        await tester.tap(inputFinder);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('other')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(inputFinder).decoration!.errorText,
          isNull,
        );
        expect(tester.getSize(inputFinder).height, initialHeight);
        expect(indicatorFinder, findsOneWidget);
        expect(tooltipMessage(), 'Ce champ est obligatoire.');
        expect(
          tester.widget<TextField>(inputFinder).style!.color!.toARGB32(),
          Colors.red.toARGB32(),
        );

        // Hovering the red triangle opens the Tooltip with the error message
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(indicatorFinder));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
        await mouse.removePointer();

        // Typing invalid text preserves input, updates tooltip and keeps invalid state
        await tester.enterText(inputFinder, 'A1');
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(inputFinder).controller!.text, 'A1');
        expect(
          tooltipMessage(),
          'Longueur minimale : 3 caractère(s).',
        );

        // Typing valid text removes triangle indicator and invalid state
        await tester.enterText(inputFinder, 'abc');
        await tester.pumpAndSettle();
        expect(indicatorFinder, findsNothing);
        expect(
          tester.widget<TextField>(inputFinder).style!.color!.toARGB32(),
          isNot(Colors.red.toARGB32()),
        );
      },
    );

    testWidgets(
      'blocks repository save when invalid and stores raw/canonical value when valid',
      (tester) async {
        final dir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('sv-mask-repo-'),
        ))!;
        final store = JsonRepositoryStore(dir);
        addTearDown(() async {
          store.dispose();
          if (dir.existsSync()) await dir.delete(recursive: true);
        });
        store.registerRepository(
          RepositoryImpl(
            id: 'form_repo',
            json: {
              'phone': '0612345678',
              'price': 123.5,
              'birthDate': '2026-05-19',
            },
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: JsonRepositoryScope(
              store: store,
              child: const Scaffold(
                body: Column(
                  children: [
                    SizedBox(
                      width: 260,
                      child: SuperValue(
                        id: 'phone',
                        config: SuperValueConfig(
                          mode: SuperValueMode.input,
                          binding: JsonTextBinding(
                            repositoryId: 'form_repo',
                            path: 'phone',
                          ),
                          bindingDebounceMs: 100,
                          field: SuperTextFieldConfig(
                            mask: '## ## ## ## ##',
                            required: true,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: SuperValue(
                        id: 'price',
                        config: SuperValueConfig(
                          mode: SuperValueMode.input,
                          binding: JsonTextBinding(
                            repositoryId: 'form_repo',
                            path: 'price',
                          ),
                          bindingDebounceMs: 100,
                          field: SuperTextFieldConfig(
                            valueType: TextFieldValueType.number,
                            decimalDigits: 2,
                            decimalSeparator: ',',
                            thousandsSeparator: ' ',
                            minimum: 0,
                            maximum: 1000,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: SuperValue(
                        id: 'date',
                        config: SuperValueConfig(
                          mode: SuperValueMode.input,
                          binding: JsonTextBinding(
                            repositoryId: 'form_repo',
                            path: 'birthDate',
                          ),
                          bindingDebounceMs: 100,
                          field: SuperTextFieldConfig(
                            mask: '##/##/####',
                            dateFormat: 'dd/MM/yyyy',
                          ),
                        ),
                      ),
                    ),
                    TextField(key: ValueKey('blur-target')),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final phoneInput = find.byKey(const ValueKey('super-value-input-phone'));
        final priceInput = find.byKey(const ValueKey('super-value-input-price'));
        final dateInput = find.byKey(const ValueKey('super-value-input-date'));
        String? errorTooltipOf(String id) {
          final indicator = find.byKey(
            ValueKey('super-value-error-indicator-$id'),
          );
          if (indicator.evaluate().isEmpty) return null;
          return tester
              .widget<Tooltip>(
                find.descendant(
                  of: indicator,
                  matching: find.byType(Tooltip),
                ),
              )
              .message;
        }

        expect(
          tester.widget<TextField>(phoneInput).controller!.text,
          '06 12 34 56 78',
        );
        expect(tester.widget<TextField>(priceInput).controller!.text, '123,50');
        expect(
          tester.widget<TextField>(dateInput).controller!.text,
          '19/05/2026',
        );

        // Incomplete phone -> triangle tooltip shown, repository stays 0612345678
        await tester.enterText(phoneInput, '0612');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(errorTooltipOf('phone'), contains('Saisie incomplète'));
        expect(
          (await tester.runAsync(
            () => store.readAttribute(
              const JsonTextBinding(repositoryId: 'form_repo', path: 'phone'),
            ),
          ))!.value,
          '0612345678',
        );

        // Complete valid phone -> saved as raw digits without spaces
        await tester.enterText(phoneInput, '0698765432');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(errorTooltipOf('phone'), isNull);
        expect(
          (await tester.runAsync(
            () => store.readAttribute(
              const JsonTextBinding(repositoryId: 'form_repo', path: 'phone'),
            ),
          ))!.value,
          '0698765432',
        );

        // Price out of bounds -> blocked, valid price -> formatted & saved as JSON number
        await tester.enterText(priceInput, '1500');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(errorTooltipOf('price'), contains('1000'));
        expect(
          (await tester.runAsync(
            () => store.readAttribute(
              const JsonTextBinding(repositoryId: 'form_repo', path: 'price'),
            ),
          ))!.value,
          123.5,
        );

        await tester.tap(priceInput);
        await tester.pumpAndSettle();
        await tester.enterText(priceInput, '250,75');
        await tester.tap(find.byKey(const ValueKey('blur-target')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(priceInput).controller!.text,
          '250,75',
        );
        expect(
          (await tester.runAsync(
            () => store.readAttribute(
              const JsonTextBinding(repositoryId: 'form_repo', path: 'price'),
            ),
          ))!.value,
          250.75,
        );

        // Invalid calendar date -> blocked; valid date -> saved as ISO YYYY-MM-DD
        await tester.enterText(dateInput, '31022026');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(dateInput).controller!.text,
          '31/02/2026',
        );
        expect(errorTooltipOf('date'), contains('Date invalide'));
        expect(
          (await tester.runAsync(
            () => store.readAttribute(
              const JsonTextBinding(
                repositoryId: 'form_repo',
                path: 'birthDate',
              ),
            ),
          ))!.value,
          '2026-05-19',
        );

        await tester.enterText(dateInput, '20062026');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(
          (await tester.runAsync(
            () => store.readAttribute(
              const JsonTextBinding(
                repositoryId: 'form_repo',
                path: 'birthDate',
              ),
            ),
          ))!.value,
          '2026-06-20',
        );
      },
    );

    test('Dart codegen emits new mask and JSON Schema constraint properties', () {
      const config = SuperValueConfig(
        mode: SuperValueMode.input,
        field: SuperTextFieldConfig(
          mask: 'UU-###-UU',
          maskIncludeLiterals: true,
          decimalDigits: 2,
          decimalSeparator: ',',
          thousandsSeparator: ' ',
          dateFormat: 'dd/MM/yyyy',
          valueType: TextFieldValueType.number,
          required: true,
          minLength: 2,
          validationPattern: r'^[A-Z]+$',
          format: TextFieldFormat.email,
          minimum: 1,
          maximum: 10,
          exclusiveMinimum: 0,
          exclusiveMaximum: 11,
          multipleOf: 0.5,
          enumValues: ['A', 'B'],
          constValue: 'A',
          validationMessage: 'Invalide',
        ),
      );
      final registry = Registry()..bootstrap();
      final appearance = Appearance().withValueComponent('v', config);
      final context = DartCodegenContext(
        appearance: appearance,
        registry: registry,
      );
      final code = const SuperValueDartGenerator().generateWidget(
        context,
        id: 'v',
      );
      expect(code, contains("mask: 'UU-###-UU'"));
      expect(code, contains('maskIncludeLiterals: true'));
      expect(code, contains('decimalDigits: 2'));
      expect(code, contains('valueType: TextFieldValueType.number'));
      expect(code, contains('required: true'));
      expect(code, contains('minLength: 2'));
      expect(code, contains('format: TextFieldFormat.email'));
      expect(code, contains('minimum: 1'));
      expect(code, contains('maximum: 10'));
      expect(code, contains("enumValues: const ['A', 'B']"));
      expect(code, contains("constValue: 'A'"));
    });

    testWidgets('SuperValueEditor edits display and input masks/constraints', (
      tester,
    ) async {
      StyleEditorPanel.preferredDense = false;
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SuperValueConfig? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => saved = await showSuperValueEditor(
                  context: context,
                  config: const SuperValueConfig(initialText: '0612345678'),
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

      // Display mode mask section
      final displayMask = find.byKey(
        const ValueKey('super-value-display-mask'),
      );
      await tester.ensureVisible(displayMask);
      await tester.enterText(displayMask, '## ## ## ## ##');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('super-value-preview')),
          matching: find.text('06 12 34 56 78'),
        ),
        findsOneWidget,
      );

      // Switch to input mode: mask is preserved & JSON Schema controls appear
      final modeControl = find.byKey(
        const ValueKey('super-value-setting-mode'),
      );
      await tester.ensureVisible(modeControl);
      await tester.tap(
        find.descendant(of: modeControl, matching: find.text('Saisie')),
      );
      await tester.pumpAndSettle();

      final inputMask = find.byKey(const ValueKey('text-field-setting-mask'));
      expect(
        tester.widget<TextFormField>(inputMask).controller!.text,
        '## ## ## ## ##',
      );
      final reqSwitch = find.byKey(
        const ValueKey('text-field-setting-required'),
      );
      await tester.ensureVisible(reqSwitch);
      await tester.tap(reqSwitch);
      await tester.pumpAndSettle();

      final minLengthField = find.byKey(
        const ValueKey('text-field-setting-minLength'),
      );
      await tester.ensureVisible(minLengthField);
      await tester.enterText(minLengthField, '10');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(saved!.mode, SuperValueMode.input);
      expect(saved!.field.mask, '## ## ## ## ##');
      expect(saved!.field.required, isTrue);
      expect(saved!.field.minLength, 10);
    });

    testWidgets(
      'typing across validation error transitions and parent surface state saves preserves focus and EditableTextState',
      (tester) async {
        final tempDir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('sv_focus_validation_'),
        ))!;
        final store = JsonRepositoryStore(tempDir);
        addTearDown(() {
          store.dispose();
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final editMode = ValueNotifier<bool>(false);
        addTearDown(editMode.dispose);
        store.registerRepository(
          RepositoryImpl(
            id: 'focus_repo',
            json: <String, Object?>{'code': '', 'surfaceState': 'idle'},
          ),
        );
        await tester.runAsync(store.ensureSchemasLoaded);

        await tester.pumpWidget(
          MaterialApp(
            home: StyleEditScope(
              controller: editMode,
              child: JsonRepositoryScope(
                store: store,
                child: Scaffold(
                  body: EditableSurface(
                    id: 'card',
                    style: ContainerStyle(
                      states: SurfaceStyleStates(
                        binding: const JsonTextBinding(
                          repositoryId: 'focus_repo',
                          path: 'surfaceState',
                        ),
                        named: const {
                          'saved': ContainerStyle(
                            opacity: 0.92,
                            shadow: ShadowSpec(blur: 8),
                          ),
                        },
                        namedProperties: const {
                          'saved': {
                            SurfaceStyleProperty.opacity,
                            SurfaceStyleProperty.shadow,
                          },
                        },
                      ),
                    ),
                    child: const SizedBox(
                      width: 260,
                      child: SuperValue(
                        id: 'code',
                        config: SuperValueConfig(
                          mode: SuperValueMode.input,
                          binding: JsonTextBinding(
                            repositoryId: 'focus_repo',
                            path: 'code',
                          ),
                          bindingDebounceMs: 100,
                          field: SuperTextFieldConfig(
                            required: true,
                            minLength: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final inputFinder = find.byKey(const ValueKey('super-value-input-code'));
        await tester.tap(inputFinder);
        await tester.pump();

        final initialEditable = tester.state<EditableTextState>(
          find.descendant(of: inputFinder, matching: find.byType(EditableText)),
        );
        final focusNode = tester.widget<TextField>(inputFinder).focusNode!;
        expect(focusNode.hasFocus, isTrue);
        expect(
          find.byKey(const ValueKey('super-value-error-indicator-code')),
          findsNothing,
        );

        // 1st char: transitions from no indicator -> error triangle (minLength: 3).
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'A',
            selection: TextSelection.collapsed(offset: 1),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('super-value-error-indicator-code')),
          findsOneWidget,
        );
        expect(focusNode.hasFocus, isTrue);
        expect(
          tester.state<EditableTextState>(
            find.descendant(
              of: inputFinder,
              matching: find.byType(EditableText),
            ),
          ),
          same(initialEditable),
        );

        // 3rd char: transitions from error triangle -> valid, then saves and flips surface shadow/opacity.
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'ABC',
            selection: TextSelection.collapsed(offset: 3),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('super-value-error-indicator-code')),
          findsNothing,
        );
        expect(focusNode.hasFocus, isTrue);

        // Advance past the 100ms debounce so 'ABC' saves automatically, then flip surface state.
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(
          store
              .peekAttribute(
                const JsonTextBinding(repositoryId: 'focus_repo', path: 'code'),
              )!
              .value,
          'ABC',
        );
        expect(focusNode.hasFocus, isTrue);

        await store.writeAttribute(
          const JsonTextBinding(
            repositoryId: 'focus_repo',
            path: 'surfaceState',
          ),
          'saved',
          expectedValue: 'idle',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(focusNode.hasFocus, isTrue);
        expect(
          tester.state<EditableTextState>(
            find.descendant(
              of: inputFinder,
              matching: find.byType(EditableText),
            ),
          ),
          same(initialEditable),
        );
      },
    );
  });
}
