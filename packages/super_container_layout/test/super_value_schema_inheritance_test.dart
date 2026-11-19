import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/components/super_value_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JsonSchemaFieldResolver', () {
    const schema = <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      r'$defs': {
        'PositiveAmount': {
          'type': 'number',
          'exclusiveMinimum': 0,
          'maximum': 9999.99,
          'multipleOf': 0.01,
          'x-decimalDigits': 2,
          'x-decimalSeparator': ',',
          'x-thousandsSeparator': ' ',
        },
      },
      'type': 'object',
      'required': ['client', 'clients'],
      'properties': {
        'client': {
          'type': 'object',
          'required': ['email', 'birthDate'],
          'properties': {
            'email': {
              'type': 'string',
              'format': 'email',
              'minLength': 5,
              'maxLength': 80,
              'pattern': r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
              'x-validationMessage': 'E-mail pro invalide',
            },
            'birthDate': {'type': 'string', 'format': 'date'},
            'phone': {
              'type': ['string', 'null'],
              'x-mask': '## ## ## ## ##',
              'x-maskIncludeLiterals': false,
            },
            'notes': {'type': 'string', 'maxLength': 200},
          },
        },
        'clients': {
          'type': 'array',
          'items': {
            'type': 'object',
            'required': ['age'],
            'properties': {
              'age': {
                'type': 'integer',
                'minimum': 18,
                'exclusiveMaximum': 120,
              },
              'tier': {
                'type': 'string',
                'enum': ['free', 'pro', 'enterprise'],
              },
              'country': {'type': 'string', 'const': 'FR'},
              'budget': {r'$ref': r'#/$defs/PositiveAmount'},
            },
          },
        },
      },
    };

    test('resolves nested object properties, required, extensions and format hints', () {
      final email = JsonSchemaFieldResolver.resolve(schema, 'client.email');
      expect(email, isNotNull);
      expect(email!.required, isTrue);
      expect(email.valueType, TextFieldValueType.string);
      expect(email.format, TextFieldFormat.email);
      expect(email.minLength, 5);
      expect(email.maxLength, 80);
      expect(email.validationPattern, r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
      expect(email.validationMessage, 'E-mail pro invalide');
      expect(email.lockedKeys, containsAll(['required', 'minLength', 'validationMessage']));
      expect(email.lockedKeys.contains('mask'), isFalse);

      final birthDate = JsonSchemaFieldResolver.resolve(schema, 'client.birthDate');
      expect(birthDate, isNotNull);
      expect(birthDate!.required, isTrue);
      expect(birthDate.format, TextFieldFormat.date);
      expect(birthDate.dateFormat, 'dd/MM/yyyy');
      expect(birthDate.mask, '##/##/####');
      expect(birthDate.maskIncludeLiterals, isFalse);
      expect(birthDate.lockedKeys, containsAll(['dateFormat', 'mask', 'maskIncludeLiterals']));

      final phone = JsonSchemaFieldResolver.resolve(schema, 'client.phone');
      expect(phone, isNotNull);
      expect(phone!.required, isFalse);
      expect(phone.valueType, TextFieldValueType.string);
      expect(phone.mask, '## ## ## ## ##');
      expect(phone.maskIncludeLiterals, isFalse);
      expect(phone.lockedKeys, containsAll(['mask', 'maskIncludeLiterals']));
      expect(phone.lockedKeys.contains('dateFormat'), isFalse);
    });

    test('resolves array wildcard [?], concrete index, refs and Draft-07 exclusive bounds', () {
      final age = JsonSchemaFieldResolver.resolve(schema, 'clients[?].age');
      expect(age, isNotNull);
      expect(age!.required, isTrue);
      expect(age.valueType, TextFieldValueType.integer);
      expect(age.minimum, 18);
      expect(age.exclusiveMaximum, 120);

      final tier = JsonSchemaFieldResolver.resolve(schema, 'clients[0].tier');
      expect(tier, isNotNull);
      expect(tier!.required, isFalse);
      expect(tier.enumValues, ['free', 'pro', 'enterprise']);

      final country = JsonSchemaFieldResolver.resolve(schema, 'clients[?].country');
      expect(country, isNotNull);
      expect(country!.constValue, 'FR');

      final budget = JsonSchemaFieldResolver.resolve(schema, 'clients[?].budget');
      expect(budget, isNotNull);
      expect(budget!.valueType, TextFieldValueType.number);
      expect(budget.exclusiveMinimum, 0);
      expect(budget.maximum, 9999.99);
      expect(budget.multipleOf, 0.01);
      expect(budget.decimalDigits, 2);
      expect(budget.decimalSeparator, ',');
      expect(budget.thousandsSeparator, ' ');
      expect(
        budget.lockedKeys,
        containsAll(['decimalDigits', 'decimalSeparator', 'thousandsSeparator']),
      );

      final draft07 = JsonSchemaFieldResolver.resolve({
        'type': 'object',
        'properties': {
          'qty': {
            'type': 'integer',
            'minimum': 0,
            'exclusiveMinimum': true,
            'maximum': 10,
            'exclusiveMaximum': true,
          },
        },
      }, 'qty');
      expect(draft07!.minimum, isNull);
      expect(draft07.exclusiveMinimum, 0);
      expect(draft07.maximum, isNull);
      expect(draft07.exclusiveMaximum, 10);

      expect(JsonSchemaFieldResolver.resolve(schema, '@calculated'), isNull);
      expect(JsonSchemaFieldResolver.resolve(schema, 'client.unknown'), isNull);
    });
  });

  group('SuperValue runtime inheritance from repository jsonSchema', () {
    late Directory dir;
    late JsonRepositoryStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sv-schema-inherit-');
      store = JsonRepositoryStore(dir);
    });

    tearDown(() async {
      store.dispose();
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    testWidgets(
      'inherits masks and constraints automatically (including JsonListScope) and respects opt-out',
      (tester) async {
        store.registerRepository(
          RepositoryImpl(
            id: 'crm_repo',
            json: const {
              'clients': [
                {
                  'phone': '0612345678',
                  'birthDate': '2026-05-19',
                  'age': 25,
                },
              ],
            },
            jsonSchema: const {
              'type': 'object',
              'properties': {
                'clients': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'required': ['phone', 'age'],
                    'properties': {
                      'phone': {
                        'type': 'string',
                        'minLength': 10,
                        'maxLength': 10,
                        'x-mask': '## ## ## ## ##',
                      },
                      'birthDate': {'type': 'string', 'format': 'date'},
                      'age': {
                        'type': 'integer',
                        'minimum': 18,
                        'maximum': 99,
                      },
                    },
                  },
                },
              },
            },
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: JsonRepositoryScope(
              store: store,
              child: const Scaffold(
                body: JsonListScope(
                  repositoryId: 'crm_repo',
                  indices: [0],
                  child: Column(
                    children: [
                      SuperValue(
                        id: 'display_phone',
                        config: SuperValueConfig(
                          mode: SuperValueMode.display,
                          binding: JsonTextBinding(path: 'clients[?].phone'),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: SuperValue(
                          id: 'input_date',
                          config: SuperValueConfig(
                            mode: SuperValueMode.input,
                            binding: JsonTextBinding(
                              path: 'clients[?].birthDate',
                            ),
                            bindingDebounceMs: 100,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: SuperValue(
                          id: 'input_age',
                          config: SuperValueConfig(
                            mode: SuperValueMode.input,
                            binding: JsonTextBinding(path: 'clients[?].age'),
                            bindingDebounceMs: 100,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: SuperValue(
                          id: 'optout_age',
                          config: SuperValueConfig(
                            mode: SuperValueMode.input,
                            binding: JsonTextBinding(path: 'clients[?].age'),
                            field: SuperTextFieldConfig(
                              useRepositorySchema: false,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Display mode inherited phone mask from schema
        expect(find.text('06 12 34 56 78'), findsOneWidget);

        // Input mode inherited date mask & dateFormat from schema format: "date"
        final dateInput = find.byKey(
          const ValueKey('super-value-input-input_date'),
        );
        expect(
          tester.widget<TextField>(dateInput).controller!.text,
          '19/05/2026',
        );

        // Invalid date -> Excel red triangle tooltip & blocks repository write
        await tester.enterText(dateInput, '31022026');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        final dateIndicator = find.byKey(
          const ValueKey('super-value-error-indicator-input_date'),
        );
        expect(dateIndicator, findsOneWidget);
        expect(
          (await tester.runAsync(
            () => store.readAttribute(
              const JsonTextBinding(
                repositoryId: 'crm_repo',
                path: 'clients[0].birthDate',
              ),
            ),
          ))!.value,
          '2026-05-19',
        );

        // Age < 18 -> blocked by inherited schema constraint
        final ageInput = find.byKey(
          const ValueKey('super-value-input-input_age'),
        );
        await tester.enterText(ageInput, '12');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('super-value-error-indicator-input_age')),
          findsOneWidget,
        );
        expect(
          (await tester.runAsync(
            () => store.readAttribute(
              const JsonTextBinding(
                repositoryId: 'crm_repo',
                path: 'clients[0].age',
              ),
            ),
          ))!.value,
          25,
        );

        // Opt-out field does not show schema error for 12
        final optOutInput = find.byKey(
          const ValueKey('super-value-input-optout_age'),
        );
        await tester.enterText(optOutInput, '12');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('super-value-error-indicator-optout_age')),
          findsNothing,
        );
      },
    );

    testWidgets('updates live when saveJsonSchema adds or modifies schema', (
      tester,
    ) async {
      final repoId = (await tester.runAsync(() async {
        await store.create('clients');
        final id = await store.idOf('clients');
        await store.save(
          'clients',
          '{"birthDate":"2026-05-19"}\n',
          expectedText: await store.read('clients'),
        );
        return id;
      }))!;

      await tester.pumpWidget(
        MaterialApp(
          home: JsonRepositoryScope(
            store: store,
            child: Scaffold(
              body: SizedBox(
                width: 260,
                child: SuperValue(
                  id: 'live_date',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    binding: JsonTextBinding(
                      repositoryId: repoId,
                      path: 'birthDate',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final input = find.byKey(const ValueKey('super-value-input-live_date'));
      expect(tester.widget<TextField>(input).controller!.text, '2026-05-19');

      // Attach schema dynamically -> SuperValue switches display to 19/05/2026
      await tester.runAsync(
        () => store.saveJsonSchema(repoId, const {
          'type': 'object',
          'properties': {
            'birthDate': {'type': 'string', 'format': 'date'},
          },
        }),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '19/05/2026');
    });
  });

  group('SuperValueEditor schema checkbox & selective greying out', () {
    late Directory dir;
    late JsonRepositoryStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sv-editor-schema-');
      store = JsonRepositoryStore(dir);
    });

    tearDown(() async {
      store.dispose();
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    Future<void> real(
      WidgetTester tester,
      Future<void> Function() action, {
      int delayMs = 150,
    }) async {
      await tester.runAsync(() async {
        await action();
        await tester.pump();
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      });
      await tester.pumpAndSettle();
    }

    testWidgets(
      'greys out schema constraints and schema-defined masks when checked, keeps custom masks editable, and restores manual values on uncheck',
      (tester) async {
        StyleEditorPanel.preferredDense = false;
        await tester.binding.setSurfaceSize(const Size(1280, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        store.registerRepository(
          RepositoryImpl(
            id: 'schema_repo',
            json: const {'code': 'AB123', 'birthDate': '2026-05-19'},
            jsonSchema: const {
              'type': 'object',
              'required': ['code'],
              'properties': {
                'code': {
                  'type': 'string',
                  'minLength': 5,
                  'maxLength': 10,
                  'pattern': r'^[A-Z]{2}\d+$',
                },
                'birthDate': {'type': 'string', 'format': 'date'},
              },
            },
          ),
        );

        SuperValueConfig? saved;
        await real(
          tester,
          () => tester.pumpWidget(
            JsonRepositoryScope(
              store: store,
              child: MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () async => saved = await showSuperValueEditor(
                        context: context,
                        config: const SuperValueConfig(
                          mode: SuperValueMode.input,
                          binding: JsonTextBinding(
                            repositoryId: 'schema_repo',
                            path: 'code',
                          ),
                          field: SuperTextFieldConfig(minLength: 2),
                        ),
                        availableFontFamilies: const [],
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await real(tester, () => tester.tap(find.text('Open')));

        final checkboxFinder = find.byKey(
          const ValueKey('super-value-setting-useRepositorySchema'),
        );
        await tester.ensureVisible(checkboxFinder);
        expect(
          tester.widget<CheckboxListTile>(checkboxFinder).value,
          isTrue,
        );

        // Schema constraint fields are greyed out (enabled == false) and show schema values
        final lockedMinLen = find.byKey(
          const ValueKey('text-field-setting-minLength-locked-5'),
        );
        expect(lockedMinLen, findsOneWidget);
        expect(tester.widget<TextFormField>(lockedMinLen).enabled, isFalse);

        final lockedPattern = find.byKey(
          const ValueKey(
            r'text-field-setting-validationPattern-locked-^[A-Z]{2}\d+$',
          ),
        );
        expect(lockedPattern, findsOneWidget);
        expect(tester.widget<TextFormField>(lockedPattern).enabled, isFalse);

        final requiredSwitch = find.byKey(
          const ValueKey('text-field-setting-required'),
        );
        expect(tester.widget<SwitchListTile>(requiredSwitch).value, isTrue);
        expect(tester.widget<SwitchListTile>(requiredSwitch).onChanged, isNull);

        // `code` has no mask in schema -> mask field stays editable
        final maskField = find.byKey(const ValueKey('text-field-setting-mask'));
        expect(maskField, findsOneWidget);
        expect(tester.widget<TextFormField>(maskField).enabled, isTrue);

        // Switch path to `birthDate` -> deduced mask & dateFormat become greyed out
        final pathField = find.byKey(
          const ValueKey('super-value-repository-path'),
        );
        await tester.ensureVisible(pathField);
        await tester.enterText(pathField, 'birthDate');
        await tester.pumpAndSettle();

        final lockedMask = find.byKey(
          const ValueKey('text-field-setting-mask-locked-##/##/####'),
        );
        await tester.ensureVisible(lockedMask);
        expect(lockedMask, findsOneWidget);
        expect(tester.widget<TextFormField>(lockedMask).enabled, isFalse);

        final lockedDateFmt = find.byKey(
          const ValueKey('text-field-setting-dateFormat-locked-dd/MM/yyyy'),
        );
        expect(lockedDateFmt, findsOneWidget);
        expect(tester.widget<TextFormField>(lockedDateFmt).enabled, isFalse);

        // Uncheck the checkbox -> manual minLength (2) returns and is editable!
        await tester.ensureVisible(checkboxFinder);
        await tester.tap(checkboxFinder);
        await tester.pumpAndSettle();

        final manualMinLen = find.byKey(
          const ValueKey('text-field-setting-minLength'),
        );
        expect(manualMinLen, findsOneWidget);
        expect(tester.widget<TextFormField>(manualMinLen).enabled, isTrue);
        expect(
          tester.widget<TextFormField>(manualMinLen).controller!.text,
          '2',
        );

        await real(tester, () => tester.tap(find.text('Appliquer')));
        expect(saved!.field.useRepositorySchema, isFalse);
        expect(saved!.field.minLength, 2);
      },
    );

    test('SuperTextFieldConfig.useRepositorySchema round-trips and generates Dart code', () {
      const config = SuperValueConfig(
        mode: SuperValueMode.input,
        field: SuperTextFieldConfig(useRepositorySchema: false),
      );
      final roundTripped = SuperValueConfig.fromJson(config.toJson());
      expect(roundTripped, config);
      expect(config.toCompactJson()['field'], {'useRepositorySchema': false});
      expect(const SuperTextFieldConfig().toCompactJson(), isEmpty);

      final registry = Registry()..bootstrap();
      final appearance = Appearance().withValueComponent('v', config);
      final code = const SuperValueDartGenerator().generateWidget(
        DartCodegenContext(appearance: appearance, registry: registry),
        id: 'v',
      );
      expect(code, contains('useRepositorySchema: false'));
    });
  });
}
