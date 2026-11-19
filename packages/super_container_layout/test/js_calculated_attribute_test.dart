import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/components/super_list_view_editor.dart';

bool _tryLoadQuickJsDll() {
  if (!Platform.isWindows) return false;
  final candidates = [
    'quickjs_c_bridge.dll',
    '${Directory.current.path}\\build\\windows\\x64\\runner\\Debug\\quickjs_c_bridge.dll',
    '${Directory.current.path}\\build\\windows\\x64\\runner\\Release\\quickjs_c_bridge.dll',
  ];
  for (final path in candidates) {
    if (path != 'quickjs_c_bridge.dll' && !File(path).existsSync()) continue;
    try {
      ffi.DynamicLibrary.open(path);
      return true;
    } catch (_) {
      // Essayer le candidat suivant.
    }
  }
  return false;
}

class _FakeJsEvaluator implements JsCalculatedEvaluator {
  final List<String> evaluatedCodes = [];

  @override
  FutureOr<Object?> evaluate({
    required String code,
    required Object? scopeData,
    required Object? rootData,
    required CalculatedAttributeContext context,
  }) {
    evaluatedCodes.add(code);
    if (code.contains('SYNTAX_ERROR')) {
      throw const JsCalculationException('SyntaxError: unexpected token');
    }
    if (code == 'row.qte * row.pu') {
      final row = scopeData! as Map<String, Object?>;
      final qte = context.sync.getNum('qte', defaultValue: 0)!;
      final pu = context.sync.getNum('pu', defaultValue: 0)!;
      return (row['qte'] as num? ?? qte) * (row['pu'] as num? ?? pu);
    }
    if (code == 'ctx_total') {
      final items = context.sync.getList('articles', defaultValue: const [])!;
      var sum = 0.0;
      for (var i = 0; i < items.length; i++) {
        sum += context.sync.getDouble('articles[$i].@montant', defaultValue: 0)!;
      }
      final remise = context.sync.getDouble(
        'remise',
        repositoryId: 'cfg_repo',
        defaultValue: 0.0,
      )!;
      return sum * (1.0 - remise);
    }
    if (code == 'row.nom + "!"') {
      final row = scopeData! as Map<String, Object?>;
      return '${row['nom']}!';
    }
    return 99;
  }

  @override
  void invalidateDocument([String? repositoryId]) {}

  @override
  void dispose() {}
}

void main() {
  final hasQuickJs = _tryLoadQuickJsDll();

  group('CalculatedAttributeDefinition model & serialization', () {
    test('round-trips JSON and validates invariants', () {
      final rootDef = CalculatedAttributeDefinition(
        name: 'totalNet',
        code: 'row.brut * 0.8',
        description: 'Total après remise',
      );
      expect(rootDef.path, '@totalNet');
      expect(rootDef.toCompactJson(), {
        'name': 'totalNet',
        'code': 'row.brut * 0.8',
        'description': 'Total après remise',
      });
      expect(
        CalculatedAttributeDefinition.fromJson(rootDef.toJson()),
        rootDef,
      );

      final rowDef = CalculatedAttributeDefinition(
        name: 'montant',
        scope: 'articles[?]',
        code: 'row.qte * row.pu',
      );
      expect(rowDef.path, 'articles[?].@montant');
      expect(
        CalculatedAttributeDefinition.fromJson(rowDef.toCompactJson()),
        rowDef,
      );

      expect(
        () => CalculatedAttributeDefinition(name: 'bad-name', code: '1'),
        throwsFormatException,
      );
      expect(
        () => CalculatedAttributeDefinition(
          name: 'x',
          scope: 'articles',
          code: '1',
        ),
        throwsFormatException,
      );
      expect(
        () => CalculatedAttributeDefinition(name: 'x', code: '   '),
        throwsFormatException,
      );
    });
  });

  if (hasQuickJs) {
    group('QuickJsCalculatedEvaluator (real QuickJS on Windows)', () {
      late Directory dir;
      late JsonRepositoryStore store;

      setUp(() async {
        dir = await Directory.systemTemp.createTemp('qjs-calc-test-');
        store = JsonRepositoryStore(dir);
      });

      tearDown(() async {
        store.dispose();
        await dir.delete(recursive: true);
      });

      test(
        'evaluates expressions, function bodies, arrow fns, Proxy row tracking, and cross-repo ctx.get',
        () async {
          final cfg = RepositoryImpl(id: 'cfg_repo', json: {'tva': 0.2});
          final devis = RepositoryImpl(
            id: 'devis_repo',
            json: {
              'remise': 0.1,
              'articles': [
                {'label': 'Audit', 'qte': 2, 'pu': 100.0},
                {'label': 'Dev', 'qte': 3, 'pu': 200.0},
              ],
            },
          );
          devis.addJsCalculatedAttribute(
            'montantHt',
            scope: 'articles[?]',
            '(row.qte ?? 0) * (row.pu ?? 0)',
          );
          devis.addJsCalculatedAttribute(
            'montantTtc',
            scope: 'articles[?]',
            '''
const ht = row['@montantHt'];
const tva = ctx.getNum('tva', 'cfg_repo', 0);
return ht * (1 + tva);
''',
          );
          devis.addJsCalculatedAttribute(
            'totalNetTtc',
            '''
(row, ctx) => {
  let total = 0;
  for (let i = 0; i < row.articles.length; i++) {
    total += ctx.getDouble('articles[' + i + '].@montantTtc', null, 0);
  }
  return Math.round(total * (1 - (row.remise ?? 0)) * 100) / 100;
}
''',
          );

          store.registerRepository(cfg);
          store.registerRepository(devis);

          // Synchronous peekAttribute works immediately!
          expect(
            store
                .peekAttribute(
                  const JsonTextBinding(
                    repositoryId: 'devis_repo',
                    path: 'articles[0].@montantHt',
                  ),
                )
                ?.value,
            200.0,
          );
          expect(
            store
                .peekAttribute(
                  const JsonTextBinding(
                    repositoryId: 'devis_repo',
                    path: 'articles[1].@montantTtc',
                  ),
                )
                ?.value,
            720.0,
          );
          expect(
            (await store.readAttribute(
              const JsonTextBinding(
                repositoryId: 'devis_repo',
                path: '@totalNetTtc',
              ),
            )).value,
            864.0,
          );

          // Modifying cross-repo dependency invalidates @montantTtc and @totalNetTtc
          await store.writeAttribute(
            const JsonTextBinding(repositoryId: 'cfg_repo', path: 'tva'),
            '0.1',
            expectedValue: 0.2,
          );
          expect(
            (await store.readAttribute(
              const JsonTextBinding(
                repositoryId: 'devis_repo',
                path: '@totalNetTtc',
              ),
            )).value,
            792.0,
          );

          // Mutation inside JS throws read-only error
          await expectLater(
            store.testCalculatedAttribute(
              'devis_repo',
              CalculatedAttributeDefinition(
                name: 'badMut',
                code: 'row.remise = 0.5; return row.remise;',
              ),
            ),
            throwsFormatException,
          );

          // NaN / Infinity throws FormatException
          await expectLater(
            store.testCalculatedAttribute(
              'devis_repo',
              CalculatedAttributeDefinition(
                name: 'badNan',
                code: '0 / 0',
              ),
            ),
            throwsFormatException,
          );
        },
      );

      test(
        'uploads repository document once across many row evaluations and re-uploads after mutation',
        () async {
          final qjs = QuickJsCalculatedEvaluator();
          final localStore = JsonRepositoryStore(dir, jsEvaluator: qjs);
          addTearDown(localStore.dispose);

          final repo = RepositoryImpl(
            id: 'bulk_repo',
            json: {
              'tax': 0.2,
              'rows': [
                for (var i = 0; i < 20; i++) {'qty': i + 1, 'price': 10.0},
              ],
            },
          );
          repo.addJsCalculatedAttribute(
            'ttc',
            scope: 'rows[?]',
            'row.qty * row.price * (1 + doc.tax)',
          );
          localStore.registerRepository(repo);

          for (var i = 0; i < 20; i++) {
            final value = localStore
                .peekAttribute(
                  JsonTextBinding(
                    repositoryId: 'bulk_repo',
                    path: 'rows[$i].@ttc',
                  ),
                )
                ?.value;
            expect(value, closeTo((i + 1) * 12.0, 1e-9));
          }
          expect(qjs.debugDocumentUploadCount, 1);

          await localStore.writeAttribute(
            const JsonTextBinding(repositoryId: 'bulk_repo', path: 'tax'),
            '0.5',
            expectedValue: 0.2,
          );
          for (var i = 0; i < 20; i++) {
            final value = localStore
                .peekAttribute(
                  JsonTextBinding(
                    repositoryId: 'bulk_repo',
                    path: 'rows[$i].@ttc',
                  ),
                )
                ?.value;
            expect(value, closeTo((i + 1) * 15.0, 1e-9));
          }
          expect(qjs.debugDocumentUploadCount, 2);
        },
      );
    });
  }

  group('Persisted JS calculated attributes, UI & Vibe integration', () {
    late Directory dir;
    late _FakeJsEvaluator jsEvaluator;
    late JsonRepositoryStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('js-calc-store-');
      jsEvaluator = _FakeJsEvaluator();
      store = JsonRepositoryStore(dir, jsEvaluator: jsEvaluator);
    });

    tearDown(() async {
      store.dispose();
      await dir.delete(recursive: true);
    });

    test(
      'persists JS definitions per repositoryId, survives rename, preloads synchronously, and cleans up on delete',
      () async {
        await store.create('Facture');
        final id = await store.idOf('Facture');
        await store.replaceDocumentById(id, {
          'articles': [
            {'qte': 2, 'pu': 50},
            {'qte': 3, 'pu': 100},
          ],
        });
        await store.saveCalculatedAttributes(id, [
          CalculatedAttributeDefinition(
            name: 'montant',
            scope: 'articles[?]',
            code: 'row.qte * row.pu',
          ),
          CalculatedAttributeDefinition(
            name: 'total',
            code: 'ctx_total',
          ),
        ]);

        final cfgRepo = RepositoryImpl(id: 'cfg_repo', json: {'remise': 0.2});
        store.registerRepository(cfgRepo);

        // Rename file repository: calculated/<id>.json stays attached!
        await store.rename('Facture', 'Facture2026');
        expect(
          (await store.readAttribute(
            JsonTextBinding(repositoryId: id, path: '@total'),
          )).value,
          320.0,
        );

        // Reopen a fresh store and preload -> synchronous peekAttribute works!
        final store2 = JsonRepositoryStore(dir, jsEvaluator: _FakeJsEvaluator());
        addTearDown(store2.dispose);
        store2.registerRepository(
          RepositoryImpl(id: 'cfg_repo', json: {'remise': 0.2}),
        );
        await store2.preload();
        expect(
          store2
              .peekAttribute(
                JsonTextBinding(repositoryId: id, path: 'articles[1].@montant'),
              )
              ?.value,
          300,
        );
        expect(
          store2
              .peekAttribute(JsonTextBinding(repositoryId: id, path: '@total'))
              ?.value,
          320.0,
        );

        // Deleting repository cleans up calculated/<id>.json
        await store2.delete('Facture2026');
        final calcFile = File(
          '${dir.path}${Platform.pathSeparator}calculated'
          '${Platform.pathSeparator}$id.json',
        );
        expect(await calcFile.exists(), isFalse);
      },
    );

    test(
      'rejects collision between Dart and JS calculated attribute paths',
      () async {
        final repo = RepositoryImpl(
          id: 'app_repo',
          json: {'a': 1},
        )..addCalculatedAttribute('total', (ctx) => ctx.sync.getInt('a'));
        store.registerRepository(repo);

        await expectLater(
          store.saveCalculatedAttributes('app_repo', [
            CalculatedAttributeDefinition(name: 'total', code: '99'),
          ]),
          throwsFormatException,
        );
      },
    );

    testWidgets(
      'CalculatedAttributesDialog edits, tests live, saves and deletes JS formulas',
      (tester) async {
        final id = await tester.runAsync(() async {
          await store.create('Commandes');
          final repoId = await store.idOf('Commandes');
          await store.replaceDocumentById(repoId, {
            'articles': [
              {'qte': 4, 'pu': 25},
            ],
          });
          return repoId;
        }) as String;

        await tester.binding.setSurfaceSize(const Size(1100, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          JsonRepositoryScope(
            store: store,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    key: const ValueKey('open-calc-dialog'),
                    onPressed: () => CalculatedAttributesDialog.show(
                      context,
                      store: store,
                      repositoryId: id,
                      repositoryName: 'Commandes',
                    ),
                    child: const Text('Ouvrir'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('open-calc-dialog')));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('calculated-attr-name')),
          'montant',
        );
        await tester.enterText(
          find.byKey(const ValueKey('calculated-attr-scope')),
          'articles[?]',
        );
        await tester.pump();

        // Enter code into CodeEditor's inner EditableText
        final codeField = find.descendant(
          of: find.byKey(const ValueKey('calculated-attr-code')),
          matching: find.byType(EditableText),
        );
        await tester.runAsync(() async {
          await tester.showKeyboard(codeField);
          final controller = tester.widget<EditableText>(codeField).controller;
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
          await tester.enterText(codeField, 'row.qte * row.pu');
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.byKey(const ValueKey('calculated-attr-test')));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Résultat : 100'), findsOneWidget);

        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('calculated-attr-save')));
          await tester.pump();
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            await tester.pump();
            if (store.hasCalculatedAttribute(id, 'articles[0].@montant')) break;
          }
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byKey(const ValueKey('calculated-attr-error')),
          findsNothing,
        );
        expect(
          store.hasCalculatedAttribute(id, 'articles[0].@montant'),
          isTrue,
        );

        // Delete the JS formula
        await tester.runAsync(() async {
          await tester.tap(
            find.byKey(const ValueKey('calculated-attr-delete-0')),
          );
          await tester.pump();
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            await tester.pump();
            if (!store.hasCalculatedAttribute(id, 'articles[0].@montant')) {
              break;
            }
          }
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          store.hasCalculatedAttribute(id, 'articles[0].@montant'),
          isFalse,
        );

        await tester.tap(find.byKey(const ValueKey('calculated-attr-close')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'SuperListViewEditor disables add/remove and suggests calculated attributes',
      (tester) async {
        final repo = RepositoryImpl(
          id: 'list_repo',
          json: {
            'items': [
              {'nom': 'Alpha'},
            ],
          },
        )..addJsCalculatedAttribute('rows', '99');
        store.registerRepository(repo);

        await tester.binding.setSurfaceSize(const Size(900, 750));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          JsonRepositoryScope(
            store: store,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    key: const ValueKey('open-list-editor'),
                    onPressed: () => showSuperListViewEditor(
                      context: context,
                      config: const SuperListViewConfig(
                        binding: JsonTextBinding(
                          repositoryId: 'list_repo',
                          path: '@rows',
                        ),
                        allowAdd: true,
                        allowRemove: true,
                      ),
                    ),
                    child: const Text('Edit'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('open-list-editor')));
          await tester.pump();
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            await tester.pump();
            if (find
                .byKey(const ValueKey('super-list-calculated-suggestion-0'))
                .evaluate()
                .isNotEmpty) {
              break;
            }
          }
        });
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('super-list-calculated-status')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('super-list-calculated-status')),
              )
              .data,
          'Calculé — lecture seule',
        );
        expect(
          find.byKey(const ValueKey('super-list-calculated-suggestion-0')),
          findsOneWidget,
        );
        final allowAddSwitch = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('super-list-allow-add')),
        );
        expect(allowAddSwitch.onChanged, isNull);
        expect(allowAddSwitch.value, isFalse);
      },
    );

    test(
      'VibeRepositoryTurnTransaction creates, merges, rolls back, and undoes/redoes JS calculatedAttributes',
      () async {
        final tx = VibeRepositoryTurnTransaction(store);
        final aliasMap = await tx.applyRepositoriesPatch({
          'devis_calc': {
            'name': 'Devis',
            'mode': 'merge',
            'data': {
              'articles': [
                {'qte': 2, 'pu': 40},
              ],
            },
            'calculatedAttributes': [
              {
                'name': 'montant',
                'scope': 'articles[?]',
                'code': 'row.qte * row.pu',
              },
            ],
          },
        });
        final actualId = aliasMap['devis_calc']!;
        expect(
          (await store.readAttribute(
            JsonTextBinding(
              repositoryId: actualId,
              path: 'articles[0].@montant',
            ),
          )).value,
          80,
        );

        final callbacks = tx.buildHistoryCallbacks()!;
        await callbacks.undo();
        expect(await store.catalog(), isEmpty);

        await callbacks.redo();
        expect(
          (await store.readAttribute(
            JsonTextBinding(
              repositoryId: actualId,
              path: 'articles[0].@montant',
            ),
          )).value,
          80,
        );

        // Prompt formatter includes jsCalculatedAttributes
        final promptCtx = await VibeRepositoryPromptFormatter.formatStoreContext(
          store,
        );
        final jsonText = promptCtx.substring(promptCtx.indexOf('['));
        final parsed = jsonDecode(jsonText) as List;
        final desc = parsed.single as Map;
        expect(desc['calculatedAttributes'], ['articles[?].@montant']);
        expect(
          (desc['jsCalculatedAttributes'] as List).single['code'],
          'row.qte * row.pu',
        );

        // Rollback on a second transaction modifying calculatedAttributes
        final tx2 = VibeRepositoryTurnTransaction(store);
        await tx2.applyRepositoriesPatch({
          actualId: {
            'mode': 'merge',
            'calculatedAttributes': [
              {
                'name': 'montant',
                'scope': 'articles[?]',
                'code': '99',
              },
            ],
          },
        });
        expect(
          (await store.readAttribute(
            JsonTextBinding(
              repositoryId: actualId,
              path: 'articles[0].@montant',
            ),
          )).value,
          99,
        );
        await tx2.rollback();
        expect(
          (await store.readAttribute(
            JsonTextBinding(
              repositoryId: actualId,
              path: 'articles[0].@montant',
            ),
          )).value,
          80,
        );
      },
    );
  });
}
