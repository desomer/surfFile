import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  for (final (name, component, menuLabel) in <(String, Widget, String)>[
    ('Value', const SuperValue(id: 'text'), 'Valeur'),
    ('ListView', const SuperListView(id: 'list'), 'Liste'),
    ('Layout', const SuperLayout(), 'Layout'),
  ]) {
    testWidgets('$name advertises its configuration destination', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 500, height: 400, child: component),
          ),
        ),
      );
      final target = find
          .byWidgetPredicate(
            (widget) => widget is EditorSlot && widget.label == menuLabel,
          )
          .first;
      final state = tester.state<EditorSlotState>(target);
      final menu = state.openMenu(tester.getCenter(target));
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey('style-menu-$menuLabel'));
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(Icons.settings_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.palette_outlined)),
        findsNothing,
      );
      await tester.tapAt(const Offset(790, 590));
      await tester.pumpAndSettle();
      await menu;
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'style and configuration indicators precede titles without changing actions',
    (tester) async {
      var configured = 0;
      var added = 0;
      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: editing,
            child: Scaffold(
              body: Center(
                child: EditableSurface(
                  label: 'Style',
                  menuIcon: Icons.article_outlined,
                  child: EditorSlot(
                    label: 'Configuration',
                    menuTitle: 'Composant',
                    menuSubtitle: () => 'Zone',
                    onEdit: () async {
                      configured++;
                    },
                    onAdd: () async {
                      added++;
                    },
                    child: const SizedBox(
                      width: 160,
                      height: 80,
                      child: Text('Target'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('Target'), buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
      }

      await open();
      for (final (label, icon, title, tooltip) in [
        ('Style', Icons.palette_outlined, 'Style', 'Ouvre le style'),
        (
          'Configuration',
          Icons.settings_outlined,
          'Composant',
          'Ouvre les paramètres',
        ),
      ]) {
        final row = find.byKey(ValueKey('style-menu-$label'));
        final indicator = find.descendant(of: row, matching: find.byIcon(icon));
        expect(indicator, findsOneWidget);
        expect(tester.widget<Icon>(indicator).size, 12);
        expect(
          tester.getTopLeft(indicator).dx,
          lessThan(
            tester
                .getTopLeft(
                  find.descendant(of: row, matching: find.text(title)),
                )
                .dx,
          ),
        );
        expect(
          find.descendant(of: row, matching: find.byTooltip(tooltip)),
          findsOneWidget,
        );
        expect(
          find.ancestor(of: indicator, matching: find.byType(IconButton)),
          findsNothing,
        );
        expect(tester.getSize(row).height, lessThanOrEqualTo(48));
      }
      expect(find.byIcon(Icons.article_outlined), findsOneWidget);
      await tester.tap(find.text('Composant'));
      await tester.pumpAndSettle();
      expect(configured, 1);
      await open();
      await tester.tap(
        find.byKey(const ValueKey('style-menu-add-Configuration')),
      );
      await tester.pumpAndSettle();
      expect(added, 1);
      expect(configured, 1);
      await open();
      await tester.tap(find.byKey(const ValueKey('style-menu-Style')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('surface-state-selector')),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom surface editors and contributed entries declare destinations',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorContextMenuEntry(
              label: 'Contributed style',
              enabled: true,
              destination: EditorMenuDestination.style,
              onSelected: () async {
                calls++;
              },
              child: EditorSlotAction(
                label: 'Action',
                enabled: true,
                onEdit: () async {
                  calls++;
                },
                child: EditableSurface(
                  label: 'Custom',
                  onEdit: () async {
                    calls++;
                  },
                  child: const SizedBox(
                    width: 160,
                    height: 80,
                    child: Text('Target'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('Target'), buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
      }

      for (final (key, icon) in [
        ('style-menu-Custom', Icons.settings_outlined),
        ('style-menu-entry-Contributed style', Icons.palette_outlined),
      ]) {
        await open();
        final row = find.byKey(ValueKey(key));
        expect(
          find.descendant(of: row, matching: find.byIcon(icon)),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.settings_outlined), findsNWidgets(2));
        await tester.tap(row);
        await tester.pumpAndSettle();
      }
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled entry has no destination indicator', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EditorSlot(
            label: 'Disabled',
            child: SizedBox(width: 160, height: 80, child: Text('Target')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Target'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('style-menu-Disabled'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.settings_outlined)),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.palette_outlined)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a component type matching its menu title is not repeated', (
    tester,
  ) async {
    final editing = ValueNotifier(true);
    addTearDown(editing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: editing,
          child: Scaffold(
            body: EditorSlot(
              label: 'Configurer la carte',
              menuTitle: 'Card',
              menuType: 'Card',
              onEdit: () async {},
              child: const SizedBox(
                width: 160,
                height: 80,
                child: Text('Cible'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cible'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('style-menu-Configurer la carte'));
    expect(
      find.descendant(of: row, matching: find.text('Card')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Configurer la carte')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editor context menu prioritizes component title and compact actions',
    (tester) async {
      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: editing,
            child: Scaffold(
              body: Center(
                child: EditableSurface(
                  label: 'Parent',
                  child: EditableSurface(
                    label: 'Titre',
                    menuTitle: 'Composant',
                    menuType: 'Text',
                    menuSubtitle: () => 'Zone de titre',
                    onLabelChanged: (_) {},
                    onAdd: () async {},
                    child: const SizedBox(
                      width: 160,
                      height: 80,
                      child: Text('Cible'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Cible'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      final componentRow = find.byKey(const ValueKey('style-menu-Titre'));
      expect(tester.getSize(componentRow).height, lessThanOrEqualTo(48));
      expect(
        find.descendant(of: componentRow, matching: find.text('Composant')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: componentRow, matching: find.text('Zone de titre')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: componentRow, matching: find.text('Text')),
        findsNothing,
      );
      final componentTitle = tester.widget<Text>(
        find.descendant(of: componentRow, matching: find.text('Composant')),
      );
      final regionTitle = tester.widget<Text>(
        find.descendant(of: componentRow, matching: find.text('Zone de titre')),
      );
      expect(
        componentTitle.style!.fontSize,
        greaterThan(regionTitle.style!.fontSize!),
      );
      expect(
        find.descendant(
          of: componentRow,
          matching: find.byIcon(Icons.brush_outlined),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<PopupMenuDivider>(find.byType(PopupMenuDivider)).height,
        12,
      );

      for (final action in ['rename', 'add']) {
        final button = tester.widget<IconButton>(
          find.byKey(ValueKey('style-menu-$action-Titre')),
        );
        expect(button.style!.minimumSize!.resolve({}), const Size.square(36));
        expect(button.style!.visualDensity, VisualDensity.compact);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editor without a zone subtitle shows its component type', (
    tester,
  ) async {
    final editing = ValueNotifier(true);
    addTearDown(editing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleEditScope(
          controller: editing,
          child: Scaffold(
            body: Center(
              child: EditorSlot(
                label: 'Contenu',
                menuType: 'AppBar',
                onEdit: () async {},
                child: const SizedBox(
                  width: 160,
                  height: 80,
                  child: Text('Cible'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Cible'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('style-menu-Contenu'));
    expect(
      find.descendant(of: row, matching: find.text('Contenu')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('AppBar')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'overridden component instance shows label on line 1, type on line 2 only when distinct, and settingsTitle on line 3',
    (tester) async {
      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);
      for (final (instanceLabel, expectsTypeLine) in [
        ('NavigationRail', false),
        ('Mon rail', true),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: StyleEditScope(
              controller: editing,
              child: Scaffold(
                body: Center(
                  child: InstanceSlot(
                    BuilderSlot(
                      id: 'rail-1',
                      label: 'NavigationRail',
                      builder: (_) => EditorSlot(
                        label: 'Configurer le rail de navigation',
                        menuTitle: 'Rail de navigation',
                        menuType: 'NavigationRail',
                        onEdit: () async {},
                        child: const SizedBox(
                          width: 160,
                          height: 80,
                          child: Text('Cible'),
                        ),
                      ),
                    ),
                    label: instanceLabel,
                    overridden: true,
                    onRename: (_) {},
                    onRestore: () {},
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Cible'), buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        final row = find.byKey(ValueKey('style-menu-$instanceLabel'));
        expect(row, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.text('Rail de navigation')),
          findsNothing,
        );
        expect(
          find.descendant(of: row, matching: find.text(instanceLabel)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text('NavigationRail')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.byType(Text)),
          findsNWidgets(expectsTypeLine ? 3 : 2),
        );
        expect(
          find.descendant(
            of: row,
            matching: find.text('Configurer le rail de navigation'),
          ),
          findsOneWidget,
        );
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'context menu entry names expose property summary tooltips on hover',
    (tester) async {
      final editing = ValueNotifier(true);
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: editing,
            child: Scaffold(
              appBar: SuperAppBar(
                id: 'app-bar-tooltip',
                title: const Text('Barre Titre'),
                nativeConfig: NativeComponentConfig(
                  properties: const {'elevation': 4.0},
                  placements: const {
                    'title': ['title'],
                  },
                ),
              ),
              body: EditableSurface(
                label: 'Carte principale',
                style: const ContainerStyle(
                  radius: 12,
                  borderWidth: 2,
                  elevation: 3,
                  padding: 8,
                  margin: 4,
                ),
                child: SuperLayout(
                  label: 'Disposition',
                  config: const SuperLayoutConfig(
                    north: true,
                    south: false,
                    west: false,
                    east: false,
                    placements: {
                      SuperLayoutZone.center: ['val-slot', 'act-slot'],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'val-slot',
                      label: 'Champ texte',
                      builder: (_) => const SuperValue(
                        id: 'val-1',
                        config: SuperValueConfig(
                          mode: SuperValueMode.input,
                          initialText: 'Bonjour',
                          label: 'Nom',
                          fontSize: 16,
                        ),
                      ),
                    ),
                    BuilderSlot(
                      id: 'act-slot',
                      label: 'Bouton action',
                      builder: (_) => const SuperAction(
                        id: 'act-1',
                        config: SuperActionConfig(
                          kind: SuperActionKind.textAndIcon,
                          variant: SuperActionVariant.tonal,
                          label: 'Valider',
                          icon: 'check',
                          tooltip: 'Confirmer',
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

      // Right-click on SuperValue inside Centre zone -> Layout -> EditableSurface
      await tester.tap(
        find.byType(SuperValue),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      final valueTooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('style-menu-tooltip-Valeur')),
      );
      expect(
        valueTooltip.message,
        allOf(
          contains('Mode : Saisie · Type : Texte'),
          contains('Texte : Bonjour · Libellé : Nom'),
          contains('Taille : 16 px'),
        ),
      );

      final centerZoneTooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('style-menu-tooltip-Centre')),
      );
      expect(
        centerZoneTooltip.message,
        allOf(
          contains('Taille et flux de la zone Centre'),
          contains('Direction : Colonne (Column)'),
        ),
      );

      final layoutTooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('style-menu-tooltip-Disposition')),
      );
      expect(
        layoutTooltip.message,
        allOf(
          contains('Mode : Zones (Centre, Nord)'),
          contains('Nord : Auto'),
          contains('Éléments : 2'),
        ),
      );

      final surfaceTooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('style-menu-tooltip-Carte principale')),
      );
      expect(
        surfaceTooltip.message,
        allOf(
          contains('Carte principale'),
          contains('Rayon : 12 px · Bordure : 2 px · Élévation : 3'),
          contains('Padding : 8 px · Marge : 4 px'),
        ),
      );

      // Hover over the name 'Carte principale' to trigger its Tooltip overlay
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(
          find.descendant(
            of: find.byKey(const ValueKey('style-menu-Carte principale')),
            matching: find.text('Carte principale'),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.textContaining('Rayon : 12 px · Bordure : 2 px · Élévation : 3'),
        findsOneWidget,
      );

      // Close menu and right-click on SuperAction
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byType(SuperAction),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      final actionTooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('style-menu-tooltip-Action')),
      );
      expect(
        actionTooltip.message,
        allOf(
          contains('Type : Texte et icône · Variante : Tonal'),
          contains('Libellé : Valider · Icône : check · Infobulle : Confirmer'),
        ),
      );

      // Close menu and right-click on SuperAppBar
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Barre Titre'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      final appBarTooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('style-menu-tooltip-Configurer la barre')),
      );
      expect(
        appBarTooltip.message,
        allOf(
          contains('ApplicationBar'),
          contains('Zones actives : Titre (1)'),
        ),
      );

      await tester.tapAt(const Offset(10, 500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
