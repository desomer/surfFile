import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/pages/editor_page_manager.dart';

class _TestAppearanceCodec extends AppearanceCodec {
  const _TestAppearanceCodec(this._defaults);
  final Appearance _defaults;
  @override
  Appearance get defaults => _defaults;
}

final Uint8List _sample1x1Png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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

  group('EditorPageType & A4PageConfig models', () {
    test('EditorPageConfig preserves backward compatibility and a4Document type', () {
      final standard = EditorPageConfig(
        id: 'home',
        name: 'Accueil',
        path: '/home',
      );
      expect(standard.pageType, EditorPageType.standard);
      expect(standard.toJson().containsKey('pageType'), isFalse);

      final a4 = EditorPageConfig(
        id: 'invoice',
        name: 'Facture',
        path: '/facture',
        pageType: EditorPageType.a4Document,
      );
      final roundTrip = EditorPageConfig.fromJson(
        jsonDecode(jsonEncode(a4.toJson())),
      );
      expect(roundTrip.pageType, EditorPageType.a4Document);
      expect(roundTrip.toJson(), a4.toJson());
    });

    test('A4PageConfig JSON/compact round-trip, validation and slot remapping', () {
      final config = A4PageConfig(
        orientation: A4Orientation.landscape,
        marginTop: 24,
        marginRight: 28,
        marginBottom: 24,
        marginLeft: 28,
        headerSlotId: 'hdr',
        footerSlotId: 'ftr',
        showPageNumbers: true,
        showPageGuides: false,
        defaultFileName: 'facture.pdf',
        sheets: [
          A4SheetConfig(
            id: 's1',
            label: 'Feuille 1',
            rootSlotId: 'sheet-1-root',
          ),
          A4SheetConfig(
            id: 's2',
            label: 'Feuille 2',
            rootSlotId: 'sheet-2-root',
            backgroundColor: const Color(0xFFFDFDFD),
          ),
        ],
      );

      final decoded = ComponentConfig.fromJson({
        'type': 'a4Document',
        ...config.toJson(),
      });
      expect(decoded, isA<A4PageConfig>());
      expect(decoded, config);

      final compactDecoded = ComponentConfig.fromJson({
        'type': 'a4Document',
        ...config.toCompactJson(),
      });
      expect(compactDecoded, config);

      final remapped = config.copyWithRemappedSlots((id) => 'copy-$id');
      expect(remapped.headerSlotId, 'copy-hdr');
      expect(remapped.footerSlotId, 'copy-ftr');
      expect(remapped.sheets.first.rootSlotId, 'copy-sheet-1-root');
      expect(remapped.sheets.last.rootSlotId, 'copy-sheet-2-root');

      expect(
        () => A4PageConfig(sheets: const []),
        throwsArgumentError,
      );
      expect(
        () => A4PageConfig(marginLeft: 300, marginRight: 300),
        throwsArgumentError,
      );

      final minimal = ComponentConfig.fromJson({
        'type': 'a4Document',
        'defaultFileName': 'minimal.pdf',
      }) as A4PageConfig;
      expect(minimal.sheets.length, 1);
      expect(minimal.defaultFileName, 'minimal.pdf');

      expect(
        () => ComponentConfig.fromJson({
          'type': 'a4Document',
          'placements': {'body': []},
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('sheets'),
          ),
        ),
      );
    });

    test('GeneratePdfAction serializes and validates via BehaviorActionCatalog', () {
      const action = GeneratePdfAction(
        pageId: 'invoice-page',
        pageName: 'Facture A4',
        fileName: 'facture-2026.pdf',
        outputMode: PdfOutputMode.saveFile,
      );
      final behavior = ComponentBehavior(
        id: 'b-pdf',
        trigger: BehaviorTrigger.click,
        action: action,
      );
      final restored = ComponentBehavior.fromJson(
        jsonDecode(jsonEncode(behavior.toJson())) as Map<String, dynamic>,
      );
      expect(restored.action, action);

      expect(
        () => ComponentBehavior(
          id: 'bad',
          trigger: BehaviorTrigger.hover,
          action: action,
        ).validate(),
        throwsFormatException,
      );
    });
  });

  group('EditorPageGraph integration for A4 pages', () {
    test('duplicate and remove copy and clean up multi-sheet A4 graph', () {
      final registry = Registry()..bootstrap();
      final a4Config = A4PageConfig(
        sheets: [
          A4SheetConfig(
            id: 's1',
            label: 'Feuille 1',
            rootSlotId: 'p1-sheet-1',
          ),
        ],
      );
      final appearance = Appearance(
        pageCatalog: EditorPageCatalog(
          pages: [
            EditorPageConfig(
              id: 'p1',
              name: 'Facture',
              path: '/facture',
              pageType: EditorPageType.a4Document,
            ),
          ],
        ),
        components: {
          'p1': a4Config,
          'p1-sheet-1': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['title-1'],
            },
            slotTypes: {'title-1': 'registry:Value'},
          ),
          'title-1': const SuperValueConfig(initialText: 'FACTURE'),
        },
      );

      final duplicated = EditorPageGraph.duplicate(
        appearance: appearance,
        registry: registry,
        sourcePageId: 'p1',
        targetPageId: 'p2',
      );
      final copiedA4 = duplicated.tryComponent<A4PageConfig>('p2');
      expect(copiedA4, isNotNull);
      expect(copiedA4!.sheets.single.rootSlotId, isNot('p1-sheet-1'));
      final copiedSheetLayout = duplicated.tryComponent<SuperLayoutConfig>(
        copiedA4.sheets.single.rootSlotId,
      );
      expect(copiedSheetLayout, isNotNull);
      final copiedTitleId = copiedSheetLayout!
          .placementsOf(SuperLayoutZone.center)
          .single;
      expect(copiedTitleId, isNot('title-1'));
      expect(
        duplicated.tryComponent<SuperValueConfig>(copiedTitleId)?.initialText,
        'FACTURE',
      );

      final withCatalog = duplicated.copyWith(
        pageCatalog: EditorPageCatalog(
          pages: [
            ...duplicated.pageCatalog.pages,
            EditorPageConfig(
              id: 'p2',
              name: 'Facture 2',
              path: '/facture-2',
              pageType: EditorPageType.a4Document,
            ),
          ],
        ),
      );
      final removed = EditorPageGraph.removal(
        appearance: withCatalog,
        registry: registry,
        pageId: 'p2',
      );
      expect(removed.appearance.components.containsKey('p2'), isFalse);
      expect(
        removed.appearance.components.containsKey(
          copiedA4.sheets.single.rootSlotId,
        ),
        isFalse,
      );
      expect(removed.appearance.components.containsKey(copiedTitleId), isFalse);
      // Original page remains untouched.
      expect(removed.appearance.components.containsKey('p1'), isTrue);
      expect(removed.appearance.components.containsKey('title-1'), isTrue);
    });
  });

  group('A4PdfGenerator hybrid engine', () {
    test('generates valid multi-sheet PDF combining vector widgets and raster fallback', () async {
      final tempDir = Directory.systemTemp.createTempSync('a4_pdf_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final store = JsonRepositoryStore(tempDir);
      addTearDown(store.dispose);
      store.registerRepository(
        RepositoryImpl(
          id: 'facture_repo',
          json: {
            'numero': 'FAC-2026-001',
            'lignes': [
              {'libelle': 'Prestation Design', 'prix': '1200 EUR'},
              {'libelle': 'Audit PDF', 'prix': '600 EUR'},
            ],
          },
        ),
      );

      final appearance = Appearance(
        pageCatalog: EditorPageCatalog(
          pages: [
            EditorPageConfig(
              id: 'facture',
              name: 'Facture',
              path: '/facture',
              pageType: EditorPageType.a4Document,
            ),
          ],
        ),
        styles: {
          'card-header': const ContainerStyle(
            color: Color(0xFFF3F5FF),
            radius: 8,
            padding: 12,
            borderWidth: 1,
            borderColor: Color(0xFFD0D7FF),
          ),
        },
        components: {
          'facture': A4PageConfig(
            showPageNumbers: true,
            defaultFileName: 'facture_client',
            sheets: [
              A4SheetConfig(
                id: 's1',
                label: 'Page principale',
                rootSlotId: 's1-layout',
              ),
              A4SheetConfig(
                id: 's2',
                label: 'Annexe graphique',
                rootSlotId: 's2-layout',
              ),
            ],
          ),
          's1-layout': const SuperLayoutConfig(
            north: true,
            northSize: 80,
            placements: {
              SuperLayoutZone.north: ['card-header'],
              SuperLayoutZone.center: ['sep-1', 'table-lignes'],
            },
            slotTypes: {
              'card-header': 'registry:Card',
              'sep-1': 'registry:Separator',
              'table-lignes': 'registry:Table',
            },
          ),
          'card-header': NativeComponentConfig(
            placements: {
              'child': ['val-num'],
            },
            slotTypes: {'val-num': 'registry:Value'},
          ),
          'val-num': const SuperValueConfig(
            label: 'Facture N°',
            binding: JsonTextBinding(
              repositoryId: 'facture_repo',
              path: 'numero',
            ),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          'sep-1': const SuperSeparatorConfig(label: 'Détail'),
          'table-lignes': SuperTableConfig(
            binding: const JsonTextBinding(
              repositoryId: 'facture_repo',
              path: 'lignes',
            ),
            columns: const [
              SuperTableColumnConfig(id: 'col_lib', title: 'Désignation', width: 280),
              SuperTableColumnConfig(id: 'col_prix', title: 'Prix', width: 120),
            ],
            placements: const {
              'cell:col_lib': ['cell-lib'],
              'cell:col_prix': ['cell-prix'],
            },
            slotTypes: const {
              'cell-lib': 'registry:Value',
              'cell-prix': 'registry:Value',
            },
          ),
          'cell-lib': const SuperValueConfig(
            binding: JsonTextBinding(path: 'lignes[?].libelle'),
          ),
          'cell-prix': const SuperValueConfig(
            binding: JsonTextBinding(path: 'lignes[?].prix'),
          ),
          's2-layout': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['chart-1'],
            },
            slotTypes: {'chart-1': 'registry:Chart'},
          ),
        },
      );

      var rasterCalls = 0;
      final result = await A4PdfGenerator.generate(
        pageId: 'facture',
        appearance: appearance,
        repositoryStore: store,
        customRasterCapture: ({
          required String componentId,
          required String slotType,
          required Size logicalSize,
          required double pixelRatio,
        }) async {
          rasterCalls++;
          expect(componentId, 'chart-1');
          expect(slotType, 'registry:Chart');
          return _sample1x1Png;
        },
      );

      expect(result.fileName, 'facture_client.pdf');
      expect(result.pageCount, 2);
      expect(result.rasterFallbackCount, 1);
      expect(rasterCalls, 1);
      expect(result.bytes.length, greaterThan(200));
      expect(ascii.decode(result.bytes.take(5).toList()), '%PDF-');
    });

    test('renders 5-zone autoSides SuperLayout and nested Card without Flex infinity error', () async {
      final registry = Registry()..bootstrap();
      final a4 = A4PageConfig.initialForPage('p5');
      final s1 = a4.sheets.single.rootSlotId;
      final appearance = Appearance(
        components: {
          'p5': a4,
          s1: const SuperLayoutConfig(
            north: true,
            south: true,
            west: true,
            east: true,
            placements: {
              SuperLayoutZone.north: ['v-n'],
              SuperLayoutZone.west: ['v-w'],
              SuperLayoutZone.center: ['card-c'],
              SuperLayoutZone.east: ['v-e'],
              SuperLayoutZone.south: ['v-s'],
            },
            slotTypes: {
              'v-n': 'registry:Value',
              'v-w': 'registry:Value',
              'card-c': 'registry:Card',
              'v-e': 'registry:Value',
              'v-s': 'registry:Value',
            },
          ),
          'v-n': const SuperValueConfig(initialText: 'ENTETE'),
          'v-w': const SuperValueConfig(initialText: 'GAUCHE'),
          'card-c': NativeComponentConfig(
            placements: {'child': ['inner-l']},
            slotTypes: {'inner-l': 'registry:Layout'},
          ),
          'inner-l': const SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['v-c'],
            },
            slotTypes: {'v-c': 'registry:Value'},
          ),
          'v-c': const SuperValueConfig(initialText: 'CONTENU'),
          'v-e': const SuperValueConfig(initialText: 'DROITE'),
          'v-s': const SuperValueConfig(initialText: 'PIED'),
        },
      );
      final result = await A4PdfGenerator.generate(
        pageId: 'p5',
        appearance: appearance,
        registry: registry,
      );
      expect(result.bytes.length, greaterThan(500));
      expect(ascii.decode(result.bytes.take(5).toList()), '%PDF-');
    });
  });

  group('A4DocumentPage widget & EditorPageRouter', () {
    testWidgets('renders A4 page via EditorPageRouter and adds a sheet in edit mode', (
      tester,
    ) async {
      final registry = Registry()..bootstrap();
      final routing = EditorPageRouter(
        baseConfig: RoutingConfig(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
          ],
        ),
      );
      addTearDown(routing.dispose);

      routing.synchronize(
        EditorPageCatalog(
          homePageId: 'a4-1',
          pages: [
            EditorPageConfig(
              id: 'a4-1',
              name: 'Devis A4',
              path: '/devis',
              pageType: EditorPageType.a4Document,
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        SuperApp(
          router: routing.router,
          pageRouting: routing,
          registry: registry,
          appearanceStore: AppearanceStore(
            codec: _TestAppearanceCodec(
              Appearance(
                pageCatalog: EditorPageCatalog(
                  homePageId: 'a4-1',
                  pages: [
                    EditorPageConfig(
                      id: 'a4-1',
                      name: 'Devis A4',
                      path: '/devis',
                      pageType: EditorPageType.a4Document,
                    ),
                  ],
                ),
                components: {
                  'a4-1': A4PageConfig.initialForPage('a4-1'),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      routing.router.go('/devis');
      await tester.pumpAndSettle();

      expect(find.byType(A4DocumentPage), findsOneWidget);

      // Active le mode édition pour afficher la barre A4 et ajouter une feuille.
      final editController = StyleEditScope.controllerOf(
        tester.element(find.byType(A4DocumentPage)),
      );
      expect(editController, isNotNull);
      editController!.value = true;
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('a4-add-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('a4-page-settings')), findsOneWidget);
      expect(find.byKey(const ValueKey('a4-export-pdf')), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('a4-add-sheet')));
      await tester.pumpAndSettle();
      expect(
        registry.a4PageController('a4-1').value.sheets.length,
        2,
      );

      await tester.tap(find.byKey(const ValueKey('a4-toggle-orientation')));
      await tester.pumpAndSettle();
      expect(
        registry.a4PageController('a4-1').value.orientation,
        A4Orientation.landscape,
      );

      // Ajoute un SuperValue sur la première feuille avant d'exporter.
      registry.valueController('val-devis').value = const SuperValueConfig(
        initialText: 'DEVIS CLIENT',
      );
      registry.layoutController('a4-1-sheet-1').value = const SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: ['val-devis'],
        },
        slotTypes: {'val-devis': 'registry:Value'},
      );
      await tester.pumpAndSettle();

      // Clic sur Export PDF : ouvre la boîte d'export et enregistre un fichier .pdf.
      final exportDir = Directory.systemTemp.createTempSync('a4_export_ui_');
      addTearDown(() {
        if (exportDir.existsSync()) exportDir.deleteSync(recursive: true);
      });
      await tester.tap(find.byKey(const ValueKey('a4-export-pdf')));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (find.byKey(const ValueKey('pdf-export-dialog')).evaluate().isNotEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('pdf-export-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-export-filename')),
        'mon-devis.pdf',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pdf-export-directory')),
        exportDir.path,
      );
      await tester.tap(find.byKey(const ValueKey('pdf-export-save-only')));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (find.byKey(const ValueKey('pdf-export-dialog')).evaluate().isEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('pdf-export-dialog')), findsNothing);
      final exportedFile = File(
        '${exportDir.path}${Platform.pathSeparator}mon-devis.pdf',
      );
      expect(exportedFile.existsSync(), isTrue);
      final savedBytes = exportedFile.readAsBytesSync();
      expect(ascii.decode(savedBytes.take(5).toList()), '%PDF-');

      // Vérifie que le flux PDF contient bien des opérateurs de texte (non vide).
      final rawPdf = String.fromCharCodes(savedBytes);
      var hasTextOps = false;
      var searchIdx = 0;
      while (true) {
        final s = rawPdf.indexOf('stream\n', searchIdx);
        if (s == -1) break;
        final e = rawPdf.indexOf('\nendstream', s);
        if (e == -1) break;
        try {
          final decoded = String.fromCharCodes(
            zlib.decode(savedBytes.sublist(s + 7, e)),
          );
          if (decoded.contains('BT ') && decoded.contains('TJ ET')) {
            hasTextOps = true;
            break;
          }
        } catch (_) {}
        searchIdx = e + 10;
      }
      expect(hasTextOps, isTrue);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('EditorPageType modal routes & EditorPageManager selector', () {
    test('serializes modal page types and modal dimensions', () {
      for (final type in EditorPageType.values) {
        final page = EditorPageConfig(
          id: 'p-${type.name}',
          name: type.label,
          path: '/${type.name}',
          pageType: type,
          modalWidth: type == EditorPageType.dialog ? 700 : null,
          modalHeight: type == EditorPageType.bottomSheet ? 400 : null,
        );
        final roundTrip = EditorPageConfig.fromJson(
          jsonDecode(jsonEncode(page.toJson())),
        );
        expect(roundTrip.pageType, type);
        expect(roundTrip.modalWidth, page.modalWidth);
        expect(roundTrip.modalHeight, page.modalHeight);
      }
      expect(
        () => EditorPageConfig(
          id: 'bad',
          name: 'Bad',
          path: '/bad',
          pageType: EditorPageType.dialog,
          modalWidth: 50,
        ),
        throwsArgumentError,
      );
    });

    testWidgets('EditorPageRouter opens dialog, bottomSheet and sideSheet routes', (
      tester,
    ) async {
      final registry = Registry()..bootstrap();
      final routing = EditorPageRouter(
        baseConfig: RoutingConfig(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const SuperPage(child: Text('Home')),
            ),
          ],
        ),
      );
      addTearDown(routing.dispose);

      final catalog = EditorPageCatalog(
        pages: [
          EditorPageConfig(
            id: 'dlg',
            name: 'Mon Dialogue',
            path: '/dlg',
            pageType: EditorPageType.dialog,
            modalWidth: 500,
            modalHeight: 360,
          ),
          EditorPageConfig(
            id: 'bs',
            name: 'Mon Panneau Bas',
            path: '/bs',
            pageType: EditorPageType.bottomSheet,
            modalHeight: 320,
          ),
          EditorPageConfig(
            id: 'ss',
            name: 'Mon Panneau Latéral',
            path: '/ss',
            pageType: EditorPageType.sideSheet,
            modalWidth: 380,
          ),
        ],
      );
      routing.synchronize(catalog);

      await tester.pumpWidget(
        SuperApp(
          router: routing.router,
          pageRouting: routing,
          registry: registry,
          appearanceStore: AppearanceStore(
            codec: _TestAppearanceCodec(Appearance(pageCatalog: catalog)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      routing.router.push('/dlg');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-dialog-page-container')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('editor-modal-page-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-dialog-page-container')),
        findsNothing,
      );

      routing.router.push('/bs');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-bottom-sheet-page-container')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('editor-modal-page-close')));
      await tester.pumpAndSettle();

      routing.router.push('/ss');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-side-sheet-page-container')),
        findsOneWidget,
      );
    });

    testWidgets('EditorPageManager lets user choose and change page type on create and edit', (
      tester,
    ) async {
      final registry = Registry()..bootstrap();
      final routing = EditorPageRouter(
        baseConfig: RoutingConfig(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
          ],
        ),
      );
      addTearDown(routing.dispose);

      final appearance = ValueNotifier(Appearance());
      addTearDown(appearance.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showEditorPageManager(
                  context: context,
                  appearance: appearance,
                  routing: routing,
                  registry: registry,
                ),
                child: const Text('Open manager'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open manager'));
      await tester.pumpAndSettle();

      // Création d'une page Dialogue.
      await tester.tap(find.byKey(const ValueKey('editor-pages-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-page-type')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('editor-page-name')),
        'Aide',
      );
      await tester.enterText(
        find.byKey(const ValueKey('editor-page-path')),
        '/aide',
      );
      await tester.tap(find.byKey(const ValueKey('editor-page-type-dialog')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-page-modal-width')),
        findsOneWidget,
      );
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      // Édition de la page créée : bascule vers PDF A4.
      await tester.tap(find.byTooltip('Modifier'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-page-type')), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('editor-page-type-a4Document')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();

      expect(appearance.value.pageCatalog.pages.single.pageType, EditorPageType.a4Document);
      expect(
        appearance.value.components[appearance.value.pageCatalog.pages.single.id],
        isA<A4PageConfig>(),
      );
    });
  });
}
