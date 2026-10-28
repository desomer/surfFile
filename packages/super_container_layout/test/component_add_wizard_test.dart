import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

final _textConfigurator = ComponentAddConfigurator<String>(
  initial: (_) => 'Bonjour',
  builder: (context, draft, onChanged) => TextFormField(
    key: const ValueKey('test-config-text'),
    initialValue: draft,
    onChanged: onChanged,
  ),
  summary: (draft) => [('Texte', draft)],
  apply: (_, _, _) {},
  validate: (draft) => draft.trim().isEmpty ? 'Texte requis.' : null,
);

final _candidates = [
  ComponentAddCandidate(
    id: 'text',
    label: 'Texte',
    tags: const {'text'},
    configurator: _textConfigurator,
    previewBuilder: (_) => const Text('Aperçu du texte'),
  ),
  const ComponentAddCandidate(id: 'block', label: 'Bloc', tags: {'container'}),
];

const _targets = [
  ComponentAddTarget(id: 'a', label: 'Zone A', siblings: [('x', 'Existant')]),
  ComponentAddTarget(id: 'b', label: 'Zone B'),
];

void main() {
  Future<ValueNotifier<ComponentAddRequest?>> pumpLauncher(
    WidgetTester tester, {
    bool editableLabel = true,
  }) async {
    final result = ValueNotifier<ComponentAddRequest?>(null);
    addTearDown(result.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.value = await showComponentAddWizard(
                  context: context,
                  title: 'Ajouter dans Zone A',
                  keyPrefix: 'test',
                  candidates: _candidates,
                  targets: _targets,
                  initialTargetId: 'a',
                  editableLabel: editableLabel,
                );
              },
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    return result;
  }

  FilledButton nextButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const ValueKey('test-add-next')));

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('wizard separates settings, placement and editable summary', (
    tester,
  ) async {
    final result = await pumpLauncher(tester);
    expect(find.byKey(const ValueKey('test-add-stepper')), findsOneWidget);
    for (final stage in [
      'component',
      'settings',
      'placement',
      'binding',
      'summary',
    ]) {
      expect(find.byKey(ValueKey('test-add-step-$stage')), findsOneWidget);
    }
    expect(nextButton(tester).onPressed, isNull);
    expect(find.byKey(const ValueKey('test-add-back')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('test-add-search')),
      'contain',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-add-card-text')), findsNothing);
    expect(find.byKey(const ValueKey('test-add-card-block')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('test-add-search')), '');
    await tester.pumpAndSettle();

    await tapKey(tester, 'test-add-card-text');
    expect(nextButton(tester).onPressed, isNotNull);
    // Shown but skipped: this configurator has no repository binding.
    expect(
      tester
          .widget<Stepper>(find.byKey(const ValueKey('test-add-stepper')))
          .steps[3]
          .state,
      StepState.disabled,
    );
    await tapKey(tester, 'test-add-next');

    expect(find.byKey(const ValueKey('test-add-label')), findsNothing);
    expect(find.byKey(const ValueKey('test-add-target')), findsNothing);
    final config = find.byKey(const ValueKey('test-config-text'));
    await tester.enterText(config, ' ');
    await tester.pumpAndSettle();
    expect(find.text('Texte requis.'), findsOneWidget);
    expect(nextButton(tester).onPressed, isNull);
    await tester.enterText(config, 'Salut');
    await tester.pumpAndSettle();
    await tapKey(tester, 'test-add-next');

    expect(find.byKey(const ValueKey('test-add-placement')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-config-text')), findsNothing);
    await tapKey(tester, 'test-add-position-a');
    await tester.tap(find.text('Avant Existant').last);
    await tester.pumpAndSettle();

    await tapKey(tester, 'test-add-custom-size');
    final width = find.byKey(const ValueKey('test-add-size-preferredWidth'));
    await tester.ensureVisible(width);
    await tester.enterText(width, 'abc');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-add-error')), findsOneWidget);
    expect(nextButton(tester).onPressed, isNull);
    await tester.enterText(width, '120');
    await tester.pumpAndSettle();

    await tapKey(tester, 'test-add-next');

    final summary = find.byKey(const ValueKey('test-add-summary'));
    expect(summary, findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('test-add-label')),
      'Titre',
    );
    await tester.pumpAndSettle();
    for (final text in [
      'Zone A',
      'Avant Existant',
      'Largeur préférée 120 px',
      'Salut',
    ]) {
      expect(
        find.descendant(of: summary, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(find.text('Appliquer'), findsOneWidget);

    await tapKey(tester, 'test-add-back');
    expect(find.byKey(const ValueKey('test-add-placement')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-add-label')), findsNothing);
    await tapKey(tester, 'test-add-next');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('test-add-label')))
          .controller!
          .text,
      'Titre',
    );
    await tester.enterText(
      find.byKey(const ValueKey('test-add-label')),
      'Titre final',
    );
    await tapKey(tester, 'test-add-next');

    final request = result.value!;
    expect(find.byKey(const ValueKey('test-add-wizard')), findsNothing);
    expect(request.component.id, 'text');
    expect(request.targetId, 'a');
    expect(request.beforeId, 'x');
    expect(request.label, 'Titre final');
    expect(request.size!.preferredWidth!.value, 120);
    expect(request.size!.preferredWidth!.unit, SlotSizeUnit.pixels);
    expect(request.draft, 'Salut');
    expect(tester.takeException(), isNull);
  });

  testWidgets('wizard moves to another accepted zone', (tester) async {
    final result = await pumpLauncher(tester);
    await tapKey(tester, 'test-add-card-block');
    await tapKey(tester, 'test-add-next');
    expect(find.text('Aucun paramètre spécifique.'), findsOneWidget);
    await tapKey(tester, 'test-add-next');
    await tapKey(tester, 'test-add-target');
    await tester.tap(find.text('Zone B').last);
    await tester.pumpAndSettle();
    await tapKey(tester, 'test-add-next');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('test-add-summary')),
        matching: find.text('Par défaut'),
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'test-add-next');
    expect(result.value!.targetId, 'b');
    expect(result.value!.beforeId, isNull);
    expect(result.value!.label, isNull);
    expect(result.value!.size, isNull);
    expect(result.value!.draft, isNull);
  });

  testWidgets('cancel returns no request', (tester) async {
    final result = await pumpLauncher(tester);
    await tapKey(tester, 'test-add-card-text');
    await tapKey(tester, 'test-add-cancel');
    expect(find.byKey(const ValueKey('test-add-wizard')), findsNothing);
    expect(result.value, isNull);
  });

  testWidgets('summary respects disabled renaming', (tester) async {
    final result = await pumpLauncher(tester, editableLabel: false);
    await tapKey(tester, 'test-add-card-block');
    await tapKey(tester, 'test-add-next');
    await tapKey(tester, 'test-add-next');
    await tapKey(tester, 'test-add-next');
    expect(find.byKey(const ValueKey('test-add-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-add-label')), findsNothing);
    await tapKey(tester, 'test-add-next');
    expect(result.value!.label, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct add button skips settings and summary', (tester) async {
    final result = await pumpLauncher(tester);
    await tapKey(tester, 'test-add-slot-text');
    expect(find.byKey(const ValueKey('test-add-wizard')), findsNothing);
    expect(result.value!.component.id, 'text');
    expect(result.value!.targetId, 'a');
    expect(result.value!.draft, isNull);
  });

  testWidgets('double tap on a card adds directly', (tester) async {
    final result = await pumpLauncher(tester);
    final card = find.byKey(const ValueKey('test-add-card-block'));
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-add-wizard')), findsNothing);
    expect(result.value!.component.id, 'block');
  });

  testWidgets('Layout applies wizard label, position and size', (tester) async {
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    final changes = <SuperLayoutConfig>[];
    await tester.pumpWidget(
      StyleEditScope(
        controller: editMode,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: SuperLayout(
                config: const SuperLayoutConfig(
                  placements: {
                    SuperLayoutZone.center: ['placed'],
                  },
                ),
                onChanged: changes.add,
                slots: [
                  BuilderSlot(
                    id: 'placed',
                    label: 'Slot placé',
                    builder: (_) => const Text('Contenu placé'),
                  ),
                  BuilderSlot(
                    id: 'available',
                    label: 'Slot disponible',
                    builder: (_) => const Text('Nouveau contenu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-layout-add-center')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('super-layout-add-stepper')),
      findsOneWidget,
    );

    await tapKey(tester, 'super-layout-add-card-available');
    await tapKey(tester, 'super-layout-add-next');
    await tapKey(tester, 'super-layout-add-next');
    await tapKey(tester, 'super-layout-add-position-center');
    await tester.tap(find.text('Avant Slot placé').last);
    await tester.pumpAndSettle();
    await tapKey(tester, 'super-layout-add-custom-size');
    final width = find.byKey(
      const ValueKey('super-layout-add-size-preferredWidth'),
    );
    await tester.ensureVisible(width);
    await tester.enterText(width, '150');
    await tester.pumpAndSettle();
    await tapKey(tester, 'super-layout-add-next');
    await tester.enterText(
      find.byKey(const ValueKey('super-layout-add-label')),
      'Mon slot',
    );
    await tapKey(tester, 'super-layout-add-next');

    final config = changes.single;
    expect(config.placementsOf(SuperLayoutZone.center), [
      'available',
      'placed',
    ]);
    expect(config.slotLabels['available'], 'Mon slot');
    expect(config.slotSizeConstraints['available']!.preferredWidth!.value, 150);
    expect(find.text('Nouveau contenu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows preview widget when a candidate with previewBuilder is selected without shifting cards',
    (tester) async {
      await pumpLauncher(tester);
      expect(find.byKey(const ValueKey('test-add-preview')), findsNothing);
      final cardFinder = find.byKey(const ValueKey('test-add-card-text'));
      final initialTopLeft = tester.getTopLeft(cardFinder);

      await tester.tap(cardFinder);
      await tester.pump();
      expect(tester.getTopLeft(cardFinder), initialTopLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getTopLeft(cardFinder), initialTopLeft);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('test-add-preview')), findsOneWidget);
      expect(find.text('Aperçu : Texte'), findsOneWidget);
      expect(find.text('Aperçu du texte'), findsOneWidget);

      await tapKey(tester, 'test-add-card-block');
      expect(find.byKey(const ValueKey('test-add-preview')), findsNothing);
      expect(find.text('Aperçu du texte'), findsNothing);
      expect(tester.getTopLeft(cardFinder), initialTopLeft);
      await tapKey(tester, 'test-add-cancel');
    },
  );

  testWidgets(
    'ComponentBuilderDynamic custom label and previewBuilder apply in add popup while keeping registry key on slot',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      for (final channel in [
        const MethodChannel('com.alexmercerind/flutter_acrylic'),
        WindowTransparency.channel,
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
      }
      addTearDown(() {
        for (final channel in [
          const MethodChannel('com.alexmercerind/flutter_acrylic'),
          WindowTransparency.channel,
        ]) {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        }
      });

      final registry = Registry();
      registry.registry['CustomKey'] = ComponentBuilderDynamic(
        label: 'Mon Composant Perso',
        tags: const {'custom'},
        previewBuilder: (_) => const Text('Widget de previsualisation'),
        dynamicBuilder: (ctx) => BuilderSlot(
          id: ctx.id,
          label: 'CustomKey',
          builder: (_) => Text('Instance ${ctx.id}'),
        ),
      );

      final changes = <SuperLayoutConfig>[];
      final editMode = ValueNotifier(true);
      addTearDown(editMode.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: StyleEditScope(
                  controller: editMode,
                  child: SuperLayout(
                    config: const SuperLayoutConfig(
                      placements: {SuperLayoutZone.center: []},
                    ),
                    onChanged: changes.add,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(SuperApp(router: router, registry: registry));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('super-layout-center')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('super-layout-add-center')));
      await tester.pumpAndSettle();

      // Custom label is shown in the popup instead of the registry key.
      expect(find.text('Mon Composant Perso'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('super-layout-add-preview')),
        findsNothing,
      );

      // Selecting the card displays its preview widget.
      await tapKey(tester, 'super-layout-add-card-registry:CustomKey');
      expect(
        find.byKey(const ValueKey('super-layout-add-preview')),
        findsOneWidget,
      );
      expect(find.text('Aperçu : Mon Composant Perso'), findsOneWidget);
      expect(find.text('Widget de previsualisation'), findsOneWidget);

      // Adding without overriding the instance name keeps the registry key as slot label.
      await tapKey(tester, 'super-layout-add-slot-registry:CustomKey');
      final addedConfig = changes.single;
      final addedId = addedConfig.placementsOf(SuperLayoutZone.center).single;
      expect(addedConfig.slotLabels.containsKey(addedId), isFalse);
      expect(addedConfig.slotTypeOf(addedId), 'registry:CustomKey');
    },
  );

  testWidgets(
    'NativeComponentEditor and showContextualAddWizard use ComponentBuilderDynamic custom label and previewBuilder',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      for (final channel in [
        const MethodChannel('com.alexmercerind/flutter_acrylic'),
        WindowTransparency.channel,
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
      }
      addTearDown(() {
        for (final channel in [
          const MethodChannel('com.alexmercerind/flutter_acrylic'),
          WindowTransparency.channel,
        ]) {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        }
      });

      final registry = Registry();
      registry.registry['CustomNativeKey'] = ComponentBuilderDynamic(
        label: 'Label Popup Natif',
        tags: const {'custom'},
        previewBuilder: (_) => const Text('Aperçu Natif'),
        dynamicBuilder: (ctx) => Text('Contenu ${ctx.id}'),
      );

      final config = ValueNotifier(NativeComponentConfig());
      addTearDown(config.dispose);
      final editMode = ValueNotifier(true);
      addTearDown(editMode.dispose);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: StyleEditScope(
                  controller: editMode,
                  child: ValueListenableBuilder<NativeComponentConfig>(
                    valueListenable: config,
                    builder: (_, value, _) => NativeComponentEditor(
                      label: 'TestNative',
                      keyPrefix: 'test-native',
                      settingsTitle: 'Settings',
                      registry: registry,
                      config: value,
                      onChanged: (next) => config.value = next,
                      regions: const [
                        NativeRegion('body', 'Body', required: true),
                      ],
                      slots: const [],
                      builder: (_, editor) => editor.region('body'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(SuperApp(router: router, registry: registry));
      await tester.pumpAndSettle();

      final editorState = tester.state<NativeComponentEditorState>(
        find.byType(NativeComponentEditor),
      );
      unawaited(editorState.add('body'));
      await tester.pumpAndSettle();

      expect(find.text('Label Popup Natif'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('test-native-add-preview')),
        findsNothing,
      );

      await tapKey(tester, 'test-native-add-card-factory:CustomNativeKey');
      expect(
        find.byKey(const ValueKey('test-native-add-preview')),
        findsOneWidget,
      );
      expect(find.text('Aperçu : Label Popup Natif'), findsOneWidget);
      expect(find.text('Aperçu Natif'), findsOneWidget);

      await tapKey(tester, 'test-native-add-slot-factory:CustomNativeKey');
      final addedId = config.value.slotsOf('body').single;
      expect(config.value.slotLabels.containsKey(addedId), isFalse);
      expect(config.value.slotTypeOf(addedId), 'factory:CustomNativeKey');
      expect(editorState.slotsFor('body').single.label, 'CustomNativeKey');
    },
  );

  testWidgets(
    'every bootstrap registry component has a working previewBuilder',
    (tester) async {
      final registry = Registry()..bootstrap();
      expect(registry.registry, isNotEmpty);
      for (final entry in registry.registry.entries) {
        expect(
          entry.value.previewBuilder,
          isNotNull,
          reason: 'Missing previewBuilder for ${entry.key}',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Builder(builder: entry.value.previewBuilder!)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('wizard takes 90% of available height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpLauncher(tester);

    final dialogMaterial = find
        .descendant(
          of: find.byKey(const ValueKey('test-add-wizard')),
          matching: find.byType(Material),
        )
        .first;
    final size = tester.getSize(dialogMaterial);
    expect(size.height, closeTo(800 * 0.9, 0.5));
    await tapKey(tester, 'test-add-cancel');
  });
}
