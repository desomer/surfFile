import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/models/super_layout_config.dart';
import 'package:surf_file/theme/appearance.dart';
import 'package:surf_file/widgets/explorer_breadcrumbs.dart';
import 'package:surf_file/widgets/super_container.dart';
import 'package:surf_file/widgets/super_layout.dart';

void main() {
  const size = Size(600, 400);
  const z = SuperLayoutZone.values;

  group('SuperLayoutConfig.resolve', () {
    test('full grid has nine distinct cells', () {
      final rects = const SuperLayoutConfig().resolve(size);
      expect(rects.keys.toSet(), z.toSet());
      expect(
        rects[SuperLayoutZone.center],
        const Rect.fromLTRB(120, 80, 480, 320),
      );
      expect(rects[SuperLayoutZone.nw], const Rect.fromLTRB(0, 0, 120, 80));
      expect(
        rects[SuperLayoutZone.se],
        const Rect.fromLTRB(480, 320, 600, 400),
      );
    });

    test('missing sides drop their cells and corners', () {
      final rects = const SuperLayoutConfig(
        north: false,
        west: false,
      ).resolve(size);
      expect(rects.keys.toSet(), {
        SuperLayoutZone.center,
        SuperLayoutZone.south,
        SuperLayoutZone.east,
        SuperLayoutZone.se,
      });
      expect(
        rects[SuperLayoutZone.center],
        const Rect.fromLTRB(0, 0, 480, 320),
      );
    });

    test('corner merges into the row side', () {
      final rects = const SuperLayoutConfig(sw: CornerMerge.row).resolve(size);
      expect(rects.containsKey(SuperLayoutZone.sw), isFalse);
      expect(
        rects[SuperLayoutZone.south],
        const Rect.fromLTRB(0, 320, 480, 400),
      );
      expect(rects[SuperLayoutZone.west], const Rect.fromLTRB(0, 80, 120, 320));
    });

    test('corner merges into the column side', () {
      final rects = const SuperLayoutConfig(sw: CornerMerge.column)
          .resolve(size);
      expect(rects.containsKey(SuperLayoutZone.sw), isFalse);
      expect(rects[SuperLayoutZone.west], const Rect.fromLTRB(0, 80, 120, 400));
      expect(
        rects[SuperLayoutZone.south],
        const Rect.fromLTRB(120, 320, 480, 400),
      );
    });

    test('all corners merged span full sides without overlap', () {
      final rects = const SuperLayoutConfig(
        nw: CornerMerge.row,
        ne: CornerMerge.row,
        sw: CornerMerge.column,
        se: CornerMerge.column,
      ).resolve(size);
      expect(rects[SuperLayoutZone.north], const Rect.fromLTRB(0, 0, 600, 80));
      expect(rects[SuperLayoutZone.west], const Rect.fromLTRB(0, 80, 120, 400));
      expect(
        rects[SuperLayoutZone.east],
        const Rect.fromLTRB(480, 80, 600, 400),
      );
      expect(
        rects[SuperLayoutZone.south],
        const Rect.fromLTRB(120, 320, 480, 400),
      );
      final list = rects.values.toList();
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          expect(list[i].intersect(list[j]).isEmpty, isTrue);
        }
      }
    });

    test('oversized sides shrink to fit', () {
      final rects = const SuperLayoutConfig(
        westSize: 600,
        eastSize: 600,
      ).resolve(size);
      expect(rects[SuperLayoutZone.west]!.width, 300);
      expect(rects[SuperLayoutZone.center]!.width, 0);
    });
  });

  Future<List<SuperLayoutConfig>> pump(
    WidgetTester tester, {
    SuperLayoutConfig config = const SuperLayoutConfig(),
  }) async {
    final changes = <SuperLayoutConfig>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: SuperLayout(
              config: config,
              onChanged: changes.add,
              zones: const {SuperLayoutZone.center: Text('Contenu')},
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  Future<void> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.tap(find.text('Contenu'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuItem<SuperContainerState>).first);
    await tester.pumpAndSettle();
  }

  testWidgets('renders zones with placeholders for the missing ones', (
    tester,
  ) async {
    await pump(tester, config: const SuperLayoutConfig(east: false));
    expect(find.text('Contenu'), findsOneWidget);
    expect(find.text('Nord'), findsOneWidget);
    expect(find.text('Est'), findsNothing);
    expect(find.text('Sud-Est'), findsNothing);
  });

  testWidgets('editor toggles sides and merges corners live', (tester) async {
    final changes = await pump(tester);
    await openEditor(tester);
    expect(find.byType(SuperLayoutEditor), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('super-layout-side-north')));
    await tester.pumpAndSettle();
    expect(changes.last.north, isFalse);
    expect(find.byKey(const ValueKey('super-layout-nw')), findsNothing);
    expect(
      find.byKey(const ValueKey('super-layout-preview-north')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('super-layout-side-north')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-layout-corner-sw')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fusionné avec Ouest').last);
    await tester.pumpAndSettle();
    expect(changes.last.sw, CornerMerge.column);
    expect(find.byKey(const ValueKey('super-layout-sw')), findsNothing);
  });

  testWidgets('cancel restores the previous layout', (tester) async {
    final changes = await pump(tester);
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('super-layout-side-east')));
    await tester.pumpAndSettle();
    expect(changes.last.east, isFalse);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(changes.last, const SuperLayoutConfig());
    expect(find.byKey(const ValueKey('super-layout-east')), findsOneWidget);
  });

  testWidgets('path bar layout is in the edit-mode menu and persists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final appearance = ValueNotifier(const Appearance());
    final editMode = ValueNotifier(true);
    addTearDown(appearance.dispose);
    addTearDown(editMode.dispose);
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ExplorerBreadcrumbs(
                    path: 'C:\\Users\\demo',
                    onNavigate: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Nord'), findsNothing);

    await tester.tap(find.text('Users'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final menu = find.byType(PopupMenuItem<SuperContainerState>);
    expect(menu, findsNWidgets(2));
    await tester.tap(
      find.byKey(
        const ValueKey('style-menu-Disposition de la barre de chemin'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-layout-side-north')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();

    expect(appearance.value.pathBarLayout.north, isTrue);
    expect(find.text('Nord'), findsOneWidget);
  });
}
