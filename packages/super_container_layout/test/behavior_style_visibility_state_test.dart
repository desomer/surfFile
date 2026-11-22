import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  group('BehaviorStylePatch & SetStyleAction / SetVisibilityAction / SetStateAction models', () {
    test('BehaviorStylePatch JSON & compact roundtrip with ThemeColor, aliases, merge & subtract', () {
      const patch = BehaviorStylePatch(
        backgroundColor: ThemeColor(ThemeColorRole.primaryContainer),
        foregroundColor: Color(0xFF112233),
        borderColor: ThemeColor(ThemeColorRole.primary),
        borderWidth: 2,
        radius: 12,
        opacity: 0.75,
        elevation: 4,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        namedState: 'active',
      );

      final decodedFull = BehaviorStylePatch.fromJson(patch.toJson());
      final decodedCompact = BehaviorStylePatch.fromJson(patch.toCompactJson());
      expect(decodedFull, patch);
      expect(decodedCompact, patch);

      // Aliases "color" and "textColor"
      final fromAliases = BehaviorStylePatch.fromJson({
        'color': '#FF00AA',
        'textColor': 'theme:onPrimary',
      });
      expect(fromAliases.backgroundColor, const Color(0xFFFF00AA));
      expect(
        fromAliases.foregroundColor,
        const ThemeColor(ThemeColorRole.onPrimary),
      );

      // Merge, isAppliedIn, subtract
      const other = BehaviorStylePatch(
        backgroundColor: Color(0xFF00FF00),
        opacity: 0.5,
      );
      final merged = patch.merge(other);
      expect(merged.backgroundColor, const Color(0xFF00FF00));
      expect(merged.foregroundColor, const Color(0xFF112233));
      expect(merged.opacity, 0.5);
      expect(other.isAppliedIn(merged), isTrue);

      final subtracted = merged.subtract(other);
      expect(subtracted.backgroundColor, isNull);
      expect(subtracted.opacity, isNull);
      expect(subtracted.foregroundColor, const Color(0xFF112233));
      expect(subtracted.namedState, 'active');

      // applyToContainerStyle
      final styled = patch.applyToContainerStyle(const ContainerStyle());
      expect(styled.color, const ThemeColor(ThemeColorRole.primaryContainer));
      expect(styled.borderColor, const ThemeColor(ThemeColorRole.primary));
      expect(styled.borderWidth, 2);
      expect(styled.radius, 12);
      expect(styled.opacity, 0.75);
      expect(styled.elevation, 4);
    });

    test('BehaviorStylePatch and actions validate bounds and invariants', () {
      expect(
        () => const BehaviorStylePatch(opacity: 1.5).validate(),
        throwsFormatException,
      );
      expect(
        () => const BehaviorStylePatch(borderWidth: -1).validate(),
        throwsFormatException,
      );
      expect(
        () => const BehaviorStylePatch(fontSize: 0).validate(),
        throwsFormatException,
      );
      expect(
        () => const BehaviorStylePatch(namedState: '  ').validate(),
        throwsFormatException,
      );
      expect(
        () => const SetStyleAction(operation: BehaviorStyleOperation.apply)
            .validate(),
        throwsFormatException,
      );
      expect(
        () => const SetStyleAction(operation: BehaviorStyleOperation.reset)
            .validate(),
        returnsNormally,
      );
      expect(
        () => const SetVisibilityAction(targetComponentId: ' ').validate(),
        throwsFormatException,
      );
      expect(
        () => const SetStateAction(targetComponentId: ' btn ').validate(),
        throwsFormatException,
      );
    });

    test('ComponentBehavior serialization, declarative event guard, and remapComponentIds', () {
      const styleBehavior = ComponentBehavior(
        id: 'b-style',
        event: BehaviorEvent.onTap,
        action: SetStyleAction(
          operation: BehaviorStyleOperation.toggle,
          targetComponentId: 'card-1',
          durationMs: 200,
          style: BehaviorStylePatch(
            backgroundColor: ThemeColor(ThemeColorRole.errorContainer),
            opacity: 0.8,
          ),
        ),
      );
      const visibilityBehavior = ComponentBehavior(
        id: 'b-vis',
        event: BehaviorEvent.onChanged,
        action: SetVisibilityAction(
          mode: BehaviorVisibilityMode.hide,
          targetComponentId: 'panel-1',
          maintainSize: true,
        ),
      );
      const stateBehavior = ComponentBehavior(
        id: 'b-state',
        event: BehaviorEvent.onTap,
        action: SetStateAction(
          state: BehaviorInteractiveState.disabled,
          operation: BehaviorStateOperation.set,
          value: false,
          targetComponentId: 'btn-1',
        ),
      );

      for (final b in [styleBehavior, visibilityBehavior, stateBehavior]) {
        expect(ComponentBehavior.fromJson(b.toJson()), b);
        expect(ComponentBehavior.fromJson(b.toCompactJson()), b);
      }

      // Declarative events must reject imperative actions
      expect(
        () => const ComponentBehavior(
          id: 'bad',
          event: BehaviorEvent.onBinding,
          action: SetVisibilityAction(mode: BehaviorVisibilityMode.hide),
        ).validate(),
        throwsFormatException,
      );

      // remapComponentIds remaps action targetComponentId
      final remappedStyle = styleBehavior.remapComponentIds({
        'card-1': 'card-2',
      });
      expect(
        (remappedStyle.action as SetStyleAction).targetComponentId,
        'card-2',
      );
      final remappedVis = visibilityBehavior.remapComponentIds({
        'panel-1': 'panel-2',
      });
      expect(
        (remappedVis.action as SetVisibilityAction).targetComponentId,
        'panel-2',
      );
      final remappedState = stateBehavior.remapComponentIds({'btn-1': 'btn-2'});
      expect(
        (remappedState.action as SetStateAction).targetComponentId,
        'btn-2',
      );
    });
  });

  group('BehaviorRuntimeStateController scoping & semantics', () {
    test('isolates row-scoped overrides and merges global + scoped cleanly', () {
      final controller = BehaviorRuntimeStateController();
      addTearDown(controller.dispose);

      final row0Token = Object();
      final row1Token = Object();
      controller.registerMountedInstance(
        token: row0Token,
        componentId: 'badge',
        scopeKey: 'tasks|0|',
      );
      controller.registerMountedInstance(
        token: row1Token,
        componentId: 'badge',
        scopeKey: 'tasks|1|',
      );

      expect(
        controller.resolveTargetScopeKey(
          'badge',
          isSelf: false,
          sourceScopeKey: 'tasks|0|',
        ),
        'tasks|0|',
      );
      expect(
        controller.resolveTargetScopeKey(
          'global-panel',
          isSelf: false,
          sourceScopeKey: 'tasks|0|',
        ),
        isNull,
      );

      // Apply global border, then row-0 background
      controller.applyStyle(
        'badge',
        patch: const BehaviorStylePatch(borderWidth: 2),
      );
      controller.applyStyle(
        'badge',
        scopeKey: 'tasks|0|',
        patch: const BehaviorStylePatch(backgroundColor: Color(0xFFFF0000)),
      );

      final row0 = controller.overrideFor('badge', scopeKey: 'tasks|0|');
      final row1 = controller.overrideFor('badge', scopeKey: 'tasks|1|');
      expect(row0?.style?.borderWidth, 2);
      expect(row0?.style?.backgroundColor, const Color(0xFFFF0000));
      expect(row1?.style?.borderWidth, 2);
      expect(row1?.style?.backgroundColor, isNull);

      // Toggle removes only its keys
      controller.toggleStyle(
        'badge',
        scopeKey: 'tasks|0|',
        patch: const BehaviorStylePatch(backgroundColor: Color(0xFFFF0000)),
      );
      expect(
        controller.overrideFor('badge', scopeKey: 'tasks|0|')?.style?.backgroundColor,
        isNull,
      );
      expect(
        controller.overrideFor('badge', scopeKey: 'tasks|0|')?.style?.borderWidth,
        2,
      );

      controller.unregisterMountedInstance(row0Token);
      controller.unregisterMountedInstance(row1Token);
    });
  });

  group('Runtime widget integration', () {
    testWidgets(
      'setVisibility hides/shows/toggles another component with maintainSize and suspends in edit mode',
      (tester) async {
        final editing = ValueNotifier<bool>(false);
        addTearDown(editing.dispose);
        final appearance = ValueNotifier<Appearance>(Appearance());
        addTearDown(appearance.dispose);
        final runtime = BehaviorRuntimeStateController();
        addTearDown(runtime.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: BehaviorRuntimeStateScope(
              controller: runtime,
              child: AppearanceScope(
                controller: appearance,
                child: StyleEditScope(
                  controller: editing,
                  child: Scaffold(
                    body: Column(
                      children: [
                        SuperAction(
                          id: 'btn-toggle-vis',
                          config: const SuperActionConfig(label: 'Basculer'),
                          behaviours: const [
                            ComponentBehavior(
                              id: 'b-toggle-vis',
                              event: BehaviorEvent.onTap,
                              action: SetVisibilityAction(
                                mode: BehaviorVisibilityMode.toggle,
                                targetComponentId: 'target-box',
                                maintainSize: true,
                              ),
                            ),
                          ],
                        ),
                        const ComponentStateBehavior(
                          componentId: 'target-box',
                          child: SizedBox(
                            key: ValueKey('target-inner'),
                            width: 120,
                            height: 40,
                            child: Text('Contenu secret'),
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

        expect(find.text('Contenu secret'), findsOneWidget);

        // First tap hides target-box with maintainSize: true
        await tester.tap(find.text('Basculer'));
        await tester.pumpAndSettle();

        final vis = tester.widget<Visibility>(find.byType(Visibility));
        expect(vis.visible, isFalse);
        expect(vis.maintainSize, isTrue);

        // Edit mode suspends runtime hide so designer can see/select it
        editing.value = true;
        await tester.pumpAndSettle();
        expect(find.byType(Visibility), findsNothing);
        expect(find.text('Contenu secret'), findsOneWidget);

        // Back to runtime mode: still hidden until toggled again
        editing.value = false;
        await tester.pumpAndSettle();
        expect(tester.widget<Visibility>(find.byType(Visibility)).visible, isFalse);

        // Second tap toggles back to visible
        await tester.tap(find.text('Basculer'));
        await tester.pumpAndSettle();
        expect(find.byType(Visibility), findsNothing);
        expect(find.text('Contenu secret'), findsOneWidget);
      },
    );

    testWidgets(
      'setState disables and re-enables SuperAction and SuperValue, blocking BehaviorDispatcher when disabled',
      (tester) async {
        final editing = ValueNotifier<bool>(false);
        addTearDown(editing.dispose);
        final appearance = ValueNotifier<Appearance>(Appearance());
        addTearDown(appearance.dispose);
        final runtime = BehaviorRuntimeStateController();
        addTearDown(runtime.dispose);
        final bus = SuperEventBus();
        addTearDown(bus.close);
        final received = <SuperComponentEvent>[];
        final sub = bus.on('submitted').listen(received.add);
        addTearDown(sub.cancel);

        await tester.pumpWidget(
          MaterialApp(
            home: SuperAppScope(
              app: SuperApp(router: _dummyRouter(), eventBus: bus),
              child: BehaviorRuntimeStateScope(
                controller: runtime,
                child: AppearanceScope(
                  controller: appearance,
                  child: StyleEditScope(
                    controller: editing,
                    child: Scaffold(
                      body: Column(
                        children: [
                          SuperAction(
                            id: 'btn-disable',
                            config: const SuperActionConfig(label: 'Verrouiller'),
                            behaviours: const [
                              ComponentBehavior(
                                id: 'b-disable-action',
                                event: BehaviorEvent.onTap,
                                action: SetStateAction(
                                  state: BehaviorInteractiveState.disabled,
                                  operation: BehaviorStateOperation.set,
                                  value: true,
                                  targetComponentId: 'btn-submit',
                                ),
                              ),
                              ComponentBehavior(
                                id: 'b-readonly-input',
                                event: BehaviorEvent.onTap,
                                action: SetStateAction(
                                  state: BehaviorInteractiveState.readOnly,
                                  operation: BehaviorStateOperation.set,
                                  value: true,
                                  targetComponentId: 'field-name',
                                ),
                              ),
                            ],
                          ),
                          SuperAction(
                            id: 'btn-enable',
                            config: const SuperActionConfig(label: 'Déverrouiller'),
                            behaviours: const [
                              ComponentBehavior(
                                id: 'b-enable-action',
                                event: BehaviorEvent.onTap,
                                action: SetStateAction(
                                  state: BehaviorInteractiveState.disabled,
                                  operation: BehaviorStateOperation.set,
                                  value: false,
                                  targetComponentId: 'btn-submit',
                                ),
                              ),
                            ],
                          ),
                          SuperAction(
                            id: 'btn-submit',
                            config: const SuperActionConfig(label: 'Envoyer'),
                            behaviours: [
                              ComponentBehavior(
                                id: 'b-submit',
                                event: BehaviorEvent.onTap,
                                action: EmitEventAction(eventId: 'submitted'),
                              ),
                            ],
                          ),
                          const SuperValue(
                            id: 'field-name',
                            config: SuperValueConfig(
                              mode: SuperValueMode.input,
                              initialText: 'Alice',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Initially enabled: clicking Envoyer emits event
        await tester.tap(find.text('Envoyer'));
        await tester.pumpAndSettle();
        expect(received.length, 1);

        // Lock btn-submit & set field-name readOnly
        await tester.tap(find.text('Verrouiller'));
        await tester.pumpAndSettle();

        // Clicking Envoyer is now blocked
        await tester.tap(find.text('Envoyer'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(received.length, 1);

        // TextField inside SuperValue is now readOnly
        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.readOnly, isTrue);

        // Unlock btn-submit
        await tester.tap(find.text('Déverrouiller'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Envoyer'));
        await tester.pumpAndSettle();
        expect(received.length, 2);
      },
    );

    testWidgets(
      'setStyle updates EditableSurface, SuperValue, SuperAction, namedState, never mutates Appearance, and does not leak to children',
      (tester) async {
        final editing = ValueNotifier<bool>(false);
        addTearDown(editing.dispose);
        final initialAppearance = Appearance(
          styles: {
            'card-main': ContainerStyle(
              color: const Color(0xFFFFFFFF),
              states: SurfaceStyleStates(
                named: const {
                  'danger': ContainerStyle(color: Color(0xFFCC0000)),
                },
                namedProperties: const {
                  'danger': {SurfaceStyleProperty.background},
                },
              ),
            ),
          },
        );
        final appearance = ValueNotifier<Appearance>(initialAppearance);
        addTearDown(appearance.dispose);
        final runtime = BehaviorRuntimeStateController();
        addTearDown(runtime.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: BehaviorRuntimeStateScope(
              controller: runtime,
              child: AppearanceScope(
                controller: appearance,
                child: StyleEditScope(
                  controller: editing,
                  child: Scaffold(
                    body: Column(
                      children: [
                        SuperAction(
                          id: 'btn-apply-style',
                          config: const SuperActionConfig(label: 'Styliser'),
                          behaviours: const [
                            ComponentBehavior(
                              id: 'b-style-card',
                              event: BehaviorEvent.onTap,
                              action: SetStyleAction(
                                targetComponentId: 'card-main',
                                style: BehaviorStylePatch(
                                  namedState: 'danger',
                                  borderColor: Color(0xFF0000FF),
                                  borderWidth: 3,
                                  radius: 16,
                                  opacity: 0.7,
                                ),
                              ),
                            ),
                            ComponentBehavior(
                              id: 'b-style-value',
                              event: BehaviorEvent.onTap,
                              action: SetStyleAction(
                                targetComponentId: 'val-title',
                                style: BehaviorStylePatch(
                                  foregroundColor: Color(0xFF008800),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SuperAction(
                          id: 'btn-reset-style',
                          config: const SuperActionConfig(label: 'Réinitialiser'),
                          behaviours: const [
                            ComponentBehavior(
                              id: 'b-reset-card',
                              event: BehaviorEvent.onTap,
                              action: SetStyleAction(
                                operation: BehaviorStyleOperation.reset,
                                targetComponentId: 'card-main',
                              ),
                            ),
                          ],
                        ),
                        EditableSurface(
                          id: 'card-main',
                          style: initialAppearance.styles['card-main']!,
                          child: const SuperValue(
                            id: 'val-child',
                            config: SuperValueConfig(initialText: 'Enfant'),
                          ),
                        ),
                        const SuperValue(
                          id: 'val-title',
                          config: SuperValueConfig(initialText: 'Titre'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Styliser'));
        await tester.pumpAndSettle();

        // EditableSurface applied namedState 'danger' + border + radius + opacity
        final superContainer = tester.widget<SuperContainer>(
          find.byType(SuperContainer),
        );
        expect(superContainer.style.color, const Color(0xFFCC0000));
        expect(superContainer.style.borderColor, const Color(0xFF0000FF));
        expect(superContainer.style.borderWidth, 3);
        expect(superContainer.style.radius, 16);
        expect(superContainer.style.opacity, 0.7);

        // Appearance was NEVER mutated
        expect(appearance.value, initialAppearance);

        // SuperValue applied foregroundColor + fontSize + fontWeight
        final titleText = tester.widget<Text>(find.text('Titre'));
        expect(titleText.style?.color, const Color(0xFF008800));
        expect(titleText.style?.fontSize, 22);
        expect(titleText.style?.fontWeight, FontWeight.w700);

        // Child inside card-main did NOT receive card-main's styleOverride via scope
        final childCtx = tester.element(find.text('Enfant'));
        expect(
          ComponentBehaviorStateScope.styleOverrideFor(childCtx, 'val-child'),
          isNull,
        );

        // Reset restores original card style
        await tester.tap(find.text('Réinitialiser'));
        await tester.pumpAndSettle();
        final resetContainer = tester.widget<SuperContainer>(
          find.byType(SuperContainer),
        );
        expect(resetContainer.style.color, const Color(0xFFFFFFFF));
        expect(resetContainer.style.borderWidth, 0);
        expect(resetContainer.style.opacity, 1);
      },
    );
  });

  group('Diagnostics, Dart codegen, and Editor UI', () {
    test('VibeDiagnosticsInspector reports unknown_action_target for missing targetComponentId', () async {
      final appearance = Appearance(
        components: const {
          'mainLayout': SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: ['btn-1'],
            },
          ),
          'btn-1': SuperActionConfig(label: 'Go'),
        },
        behaviors: const {
          'btn-1': [
            ComponentBehavior(
              id: 'b-bad-target',
              event: BehaviorEvent.onTap,
              action: SetVisibilityAction(
                mode: BehaviorVisibilityMode.hide,
                targetComponentId: 'missing-id',
              ),
            ),
          ],
        },
      );

      final inspector = VibeDiagnosticsInspector(
        readAppearance: () => appearance,
        slotIndex: VibeMountedSlotIndex.instance,
        resolvePrimaryContext: () => null,
      );
      final report = await inspector.inspectBindingsAndDiagnostics(const {});
      final issues = (report['issues'] as List).cast<Map<String, Object?>>();
      expect(
        issues.any(
          (i) =>
              i['kind'] == 'unknown_action_target' &&
              i['targetComponentId'] == 'missing-id',
        ),
        isTrue,
      );
    });

    test('DartCodegenContext formats SetStyleAction, SetVisibilityAction, and SetStateAction', () {
      final ctx = DartCodegenContext(
        appearance: Appearance(),
        registry: Registry(),
      );

      final styleCode = ctx.formatBehaviorAction(
        const SetStyleAction(
          operation: BehaviorStyleOperation.toggle,
          targetComponentId: 'card-1',
          durationMs: 150,
          style: BehaviorStylePatch(
            backgroundColor: ThemeColor(ThemeColorRole.primary),
            opacity: 0.5,
            namedState: 'selected',
          ),
        ),
      );
      expect(styleCode, contains('const SetStyleAction('));
      expect(styleCode, contains('BehaviorStyleOperation.toggle'));
      expect(styleCode, contains("targetComponentId: 'card-1'"));
      expect(styleCode, contains('BehaviorStylePatch('));
      expect(styleCode, contains('ThemeColor(ThemeColorRole.primary)'));
      expect(styleCode, contains("namedState: 'selected'"));
      expect(styleCode, contains('durationMs: 150'));

      final visCode = ctx.formatBehaviorAction(
        const SetVisibilityAction(
          mode: BehaviorVisibilityMode.hide,
          targetComponentId: 'panel-1',
          maintainSize: true,
        ),
      );
      expect(visCode, contains('const SetVisibilityAction('));
      expect(visCode, contains('BehaviorVisibilityMode.hide'));
      expect(visCode, contains('maintainSize: true'));

      final stateCode = ctx.formatBehaviorAction(
        const SetStateAction(
          state: BehaviorInteractiveState.disabled,
          operation: BehaviorStateOperation.set,
          value: false,
          targetComponentId: 'btn-1',
        ),
      );
      expect(stateCode, contains('const SetStateAction('));
      expect(stateCode, contains('BehaviorInteractiveState.disabled'));
      expect(stateCode, contains('value: false'));
      expect(stateCode, contains("targetComponentId: 'btn-1'"));
    });

    testWidgets('ComponentBehaviorWizard creates setVisibility, setState, and setStyle behaviors', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appearance = ValueNotifier<Appearance>(
        Appearance(
          components: const {
            'btn-1': SuperActionConfig(label: 'Action'),
            'card-2': SuperActionConfig(label: 'Cible'),
          },
        ),
      );
      addTearDown(appearance.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AppearanceScope(
            controller: appearance,
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showComponentBehaviorWizard(
                      context: context,
                      targets: const [
                        BehaviorTargetElement(id: 'btn-1', label: 'Bouton'),
                      ],
                    );
                  },
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );

      Future<void> tapKey(String key) async {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      // 1. Add SetVisibilityAction (toggle)
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-next');
      await tapKey('behavior-catalog-set_visibility');
      await tapKey('behavior-visibility-toggle');
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-submit');

      // 2. Add SetStateAction (disabled = true)
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-next');
      await tapKey('behavior-catalog-set_state');
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-submit');

      // 3. Add SetStyleAction (namedState: 'highlight')
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-next');
      await tapKey('behavior-catalog-set_style');
      final namedStateField = find.byKey(
        const ValueKey('behavior-style-named-state'),
      );
      await tester.ensureVisible(namedStateField);
      await tester.pumpAndSettle();
      await tester.enterText(namedStateField, 'highlight');
      await tester.pumpAndSettle();
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-next');
      await tapKey('behavior-add-submit');

      final saved = appearance.value.behaviorsFor('btn-1');
      expect(saved, hasLength(3));
      expect(
        saved[0].action,
        const SetVisibilityAction(mode: BehaviorVisibilityMode.toggle),
      );
      expect(
        saved[1].action,
        const SetStateAction(
          state: BehaviorInteractiveState.disabled,
          operation: BehaviorStateOperation.set,
          value: true,
        ),
      );
      expect(
        saved[2].action,
        const SetStyleAction(
          style: BehaviorStylePatch(namedState: 'highlight'),
        ),
      );
    });
  });
}

GoRouter _dummyRouter() => GoRouter(
  routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
);
