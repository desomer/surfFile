import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  Finder tabInkWell(String key) => find.descendant(
    of: find.byKey(const ValueKey('editor-wizard-tabs')),
    matching: find.byKey(ValueKey(key)),
  );

  bool isTabSelected(WidgetTester tester, String key) {
    final inkWell = tabInkWell(key);
    final container = tester.widget<Container>(
      find.descendant(of: inkWell, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    final border = decoration.border! as Border;
    return border.bottom.color != Colors.transparent;
  }

  bool isTabEnabled(WidgetTester tester, String key) {
    final widget = tester.widget<InkWell>(tabInkWell(key));
    return widget.onTap != null;
  }

  testWidgets(
    'context menu keeps both links for slot components and opens the wizard on the right tab',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mode = ValueNotifier(true);
      final valueConfig = ValueNotifier(
        const SuperValueConfig(initialText: 'Bonjour'),
      );
      final appearance = ValueNotifier(
        Appearance(
          layouts: {
            'root': const SuperLayoutConfig(
              north: false,
              south: false,
              east: false,
              west: false,
              placements: {
                SuperLayoutZone.center: ['val-slot'],
              },
            ),
          },
          components: {
            'val-slot': const SuperValueConfig(initialText: 'Bonjour'),
          },
        ),
      );
      final history = EditorHistoryController(
        appearance: appearance,
        editMode: mode,
      );
      addTearDown(() {
        history.dispose();
        valueConfig.dispose();
        appearance.dispose();
        mode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AppearanceScope(
            controller: appearance,
            child: EditorHistoryScope(
              controller: history,
              child: StyleEditScope(
                controller: mode,
                child: Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: ValueListenableBuilder<Appearance>(
                      valueListenable: appearance,
                      builder: (context, value, _) {
                        final currentValConfig =
                            value.components['val-slot'] as SuperValueConfig? ??
                            const SuperValueConfig(initialText: 'Bonjour');
                        return SuperLayout(
                          id: 'root',
                          config: value.layouts['root']!,
                          onChanged: (next) => appearance.value = appearance
                              .value
                              .withLayout('root', next),
                          slots: [
                            BuilderSlot(
                              id: 'val-slot',
                              label: 'Value',
                              builder: (_) => SuperValue(
                                id: 'val-slot',
                                config: currentValConfig,
                                onConfigChanged: (nextConfig) {
                                  appearance.value = appearance.value.copyWith(
                                    components: {
                                      ...appearance.value.components,
                                      'val-slot': nextConfig,
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Right-click on the SuperValue component and click the component row -> opens on Propriétés tab
      await tester.tapAt(
        tester.getTopLeft(find.byType(SuperValue)) + const Offset(100, 10),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('style-menu-Valeur')), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('style-menu-size-Taille et marge préférées : Value'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('style-menu-Valeur')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('editor-wizard-tabs')), findsOneWidget);
      expect(isTabSelected(tester, 'editor-wizard-tab-properties'), isTrue);
      expect(isTabSelected(tester, 'editor-wizard-tab-dimensions'), isFalse);
      expect(isTabEnabled(tester, 'editor-wizard-tab-properties'), isTrue);
      expect(isTabEnabled(tester, 'editor-wizard-tab-dimensions'), isTrue);
      expect(
        find.byKey(const ValueKey('super-value-setting-initialText')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('slot-preferred-width')),
        findsNothing,
      );

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      // 2. Right-click on the SuperValue component and click the ruler icon -> opens on Taille et marge tab
      await tester.tapAt(
        tester.getTopLeft(find.byType(SuperValue)) + const Offset(100, 10),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey('style-menu-size-Taille et marge préférées : Value'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('editor-wizard-tabs')), findsOneWidget);
      expect(isTabSelected(tester, 'editor-wizard-tab-properties'), isFalse);
      expect(isTabSelected(tester, 'editor-wizard-tab-dimensions'), isTrue);
      expect(isTabEnabled(tester, 'editor-wizard-tab-properties'), isTrue);
      expect(isTabEnabled(tester, 'editor-wizard-tab-dimensions'), isTrue);
      expect(
        find.byKey(const ValueKey('slot-preferred-width')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('super-value-setting-initialText')),
        findsNothing,
      );

      // 3. Edit both tabs in a single session and apply -> commits as one undoable transaction
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-width')),
        '220',
      );
      await tester.pumpAndSettle();

      await tester.tap(tabInkWell('editor-wizard-tab-properties'));
      await tester.pumpAndSettle();
      expect(isTabSelected(tester, 'editor-wizard-tab-properties'), isTrue);

      final initialTextField = find.byKey(
        const ValueKey('super-value-setting-initialText'),
      );
      await tester.ensureVisible(initialTextField);
      await tester.enterText(initialTextField, 'Modifié');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();

      expect(find.text('Modifié'), findsOneWidget);
      expect(
        appearance
            .value
            .layouts['root']!
            .slotPreferredSizes['val-slot']
            ?.width ??
            appearance
                .value
                .layouts['root']!
                .slotSizeConstraints['val-slot']
                ?.preferredWidth
                ?.value,
        220,
      );
      expect(history.canUndo, isTrue);

      // Single undo reverts both property and dimension changes
      history.undo();
      await tester.pumpAndSettle();
      expect(find.text('Bonjour'), findsOneWidget);
      expect(
        appearance.value.layouts['root']!.slotSizeConstraints['val-slot'],
        isNull,
      );

      // Single redo reapplies both
      history.redo();
      await tester.pumpAndSettle();
      expect(find.text('Modifié'), findsOneWidget);
      expect(
        appearance
            .value
            .layouts['root']!
            .slotSizeConstraints['val-slot']
            ?.preferredWidth
            ?.value,
        220,
      );
    },
  );

  testWidgets(
    'disables unavailable tab when component has no slot dimensions or slot has no properties',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mode = ValueNotifier(true);
      addTearDown(mode.dispose);

      // Standalone SuperValue outside any resizable slot -> Dimensions tab disabled
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: mode,
            child: const Scaffold(
              body: Center(
                child: SuperValue(
                  id: 'standalone-val',
                  config: SuperValueConfig(initialText: 'Standalone'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Standalone'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-menu-Valeur')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('editor-wizard-tabs')), findsOneWidget);
      expect(isTabSelected(tester, 'editor-wizard-tab-properties'), isTrue);
      expect(isTabEnabled(tester, 'editor-wizard-tab-properties'), isTrue);
      expect(isTabEnabled(tester, 'editor-wizard-tab-dimensions'), isFalse);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      // Raw BuilderSlot without properties editor -> Propriétés tab disabled
      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: mode,
            child: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: SuperLayout(
                  config: const SuperLayoutConfig(
                    north: false,
                    south: false,
                    east: false,
                    west: false,
                    placements: {
                      SuperLayoutZone.center: ['raw'],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'raw',
                      label: 'RawSlot',
                      builder: (_) =>
                          const SizedBox.expand(key: ValueKey('raw-box')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('raw-box'))) +
            const Offset(40, 40),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('style-menu-size-Taille et marge préférées : RawSlot'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('editor-wizard-tabs')), findsOneWidget);
      expect(isTabSelected(tester, 'editor-wizard-tab-dimensions'), isTrue);
      expect(isTabEnabled(tester, 'editor-wizard-tab-properties'), isFalse);
      expect(isTabEnabled(tester, 'editor-wizard-tab-dimensions'), isTrue);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'zone flow and native region context menu links position on the right tab and cancel restores both tabs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mode = ValueNotifier(true);
      final config = ValueNotifier(
        const SuperLayoutConfig(
          north: true,
          south: false,
          east: false,
          west: false,
          placements: {
            SuperLayoutZone.north: ['card-slot'],
          },
        ),
      );
      final cardStyle = ValueNotifier(const ContainerStyle(radius: 8));
      addTearDown(() {
        cardStyle.dispose();
        config.dispose();
        mode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StyleEditScope(
            controller: mode,
            child: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: ValueListenableBuilder<SuperLayoutConfig>(
                  valueListenable: config,
                  builder: (context, layoutValue, _) => SuperLayout(
                    config: layoutValue,
                    onChanged: (next) => config.value = next,
                    slots: [
                      BuilderSlot(
                        id: 'card-slot',
                        label: 'MaCarte',
                        builder: (_) => ValueListenableBuilder<ContainerStyle>(
                          valueListenable: cardStyle,
                          builder: (context, styleValue, _) => EditableSurface(
                            label: 'MaCarte',
                            style: styleValue,
                            onStyleChanged: (next) => cardStyle.value = next,
                            child: const SizedBox(
                              key: ValueKey('card-inner'),
                              width: 100,
                              height: 60,
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
        ),
      );
      await tester.pumpAndSettle();

      // Open via ruler icon on MaCarte -> opens on Taille et marge tab
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('card-inner'))) +
            const Offset(40, 20),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('style-menu-size-Taille et marge préférées : MaCarte'),
        ),
      );
      await tester.pumpAndSettle();

      expect(isTabSelected(tester, 'editor-wizard-tab-dimensions'), isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('slot-preferred-width')),
        '300',
      );
      await tester.pumpAndSettle();
      expect(
        config.value.slotPreferredSizes['card-slot']?.width ??
            config
                .value
                .slotSizeConstraints['card-slot']
                ?.preferredWidth
                ?.value,
        300,
      );

      // Switch to Propriétés tab, modify style radius, then Cancel -> restores both
      await tester.tap(tabInkWell('editor-wizard-tab-properties'));
      await tester.pumpAndSettle();
      expect(isTabSelected(tester, 'editor-wizard-tab-properties'), isTrue);

      final styleEditor = tester.widget<ContainerStyleEditor>(
        find.byType(ContainerStyleEditor),
      );
      styleEditor.onRadiusChanged!(24);
      await tester.pumpAndSettle();
      expect(cardStyle.value.radius, 24);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(cardStyle.value.radius, 8);
      expect(config.value.slotSizeConstraints['card-slot'], isNull);

      // Open zone Nord via zone row -> opens on Propriétés tab; via ruler icon -> opens on Taille et marge tab
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('card-inner'))) +
            const Offset(40, 20),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-menu-Nord')));
      await tester.pumpAndSettle();

      expect(isTabSelected(tester, 'editor-wizard-tab-properties'), isTrue);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('card-inner'))) +
            const Offset(40, 20),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-menu-zone-flow-Nord')));
      await tester.pumpAndSettle();

      expect(isTabSelected(tester, 'editor-wizard-tab-dimensions'), isTrue);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
    },
  );
}
