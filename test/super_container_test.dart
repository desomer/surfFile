import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/theme/surffile_appearance_slots.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/container_style_editor.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_toolbar.dart';
import 'package:super_container_layout/widgets/styled_surface.dart';
import 'package:super_container_layout/widgets/super_container.dart';

import 'package:super_container_layout/widgets/style_edit_banner.dart';

void main() {
  Future<List<ContainerStyle>> pump(WidgetTester tester) async {
    final changes = <ContainerStyle>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SuperContainer(
              style: const ContainerStyle(radius: 4),
              onStyleChanged: changes.add,
              child: const SizedBox(width: 120, height: 60, child: Text('Box')),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  ContainerStyle current(WidgetTester tester) =>
      tester.state<SuperContainerState>(find.byType(SuperContainer)).style;

  Future<void> setRadius(WidgetTester tester, double value) async {
    final slider = tester.widget<Slider>(
      find
          .descendant(
            of: find.byType(ContainerStyleEditor),
            matching: find.byType(Slider),
          )
          .first,
    );
    slider.onChanged!(value);
    await tester.pump();
  }

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester, Finder finder) async {
    await rightClick(tester, finder);
    await tester.tap(find.byType(PopupMenuItem<SuperContainerState>).first);
    await tester.pumpAndSettle();
  }

  testWidgets('right click menu opens the editor and applies styles live', (
    tester,
  ) async {
    final changes = await pump(tester);
    expect(find.byType(ContainerStyleEditor), findsNothing);

    await edit(tester, find.text('Box'));
    expect(find.byType(ContainerStyleEditor), findsOneWidget);

    await setRadius(tester, 20);
    expect(current(tester).radius, 20);
    expect(changes.last.radius, 20);

    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(find.byType(ContainerStyleEditor), findsNothing);
    expect(current(tester).radius, 20);
  });

  testWidgets('disposing a hovered editable container is safe', (tester) async {
    final editMode = ValueNotifier(true);
    addTearDown(editMode.dispose);
    await tester.pumpWidget(
      StyleEditScope(
        controller: editMode,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SuperContainer(
                key: ValueKey('hovered-container'),
                child: SizedBox(width: 120, height: 60, child: Text('Box')),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey('hovered-container')),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel restores the previous style', (tester) async {
    final changes = await pump(tester);
    await edit(tester, find.text('Box'));
    await setRadius(tester, 30);
    expect(current(tester).radius, 30);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(current(tester).radius, 4);
    expect(changes.last.radius, 4);
  });

  group('slot mode', () {
    Future<(PersistentAppearanceController, ValueNotifier<bool>)> pumpSlot(
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final controller = PersistentAppearanceController(
        AppearanceStore(),
        (_) {},
      );
      final editMode = ValueNotifier(false);
      addTearDown(controller.dispose);
      addTearDown(editMode.dispose);
      await tester.pumpWidget(
        AppearanceScope(
          controller: controller,
          child: StyleEditScope(
            controller: editMode,
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    ExplorerToolbar(
                      canGoBack: false,
                      canGoUp: false,
                      onBack: () {},
                      onUp: () {},
                      onRefresh: () {},
                      onSearchChanged: (_) {},
                      onCreateFolder: () {},
                    ),
                    SuperContainer(
                      slot: SurfFileAppearanceSlots.sidebar,
                      child: const SizedBox(
                        width: 120,
                        height: 60,
                        child: Text('Box'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return (controller, editMode);
    }

    testWidgets('right click is ignored until edit mode is enabled', (
      tester,
    ) async {
      final (_, editMode) = await pumpSlot(tester);
      await rightClick(tester, find.text('Box'));
      expect(find.byType(PopupMenuItem<SuperContainerState>), findsNothing);
      expect(find.byType(ContainerStyleEditor), findsNothing);

      await tester.tap(find.byKey(const ValueKey('style-edit-mode')));
      await tester.pump();
      expect(editMode.value, isTrue);

      await edit(tester, find.text('Box'));
      expect(find.byType(ContainerStyleEditor), findsOneWidget);
      expect(find.text('Style du panneau de gauche'), findsWidgets);
    });

    testWidgets('edits are written to the appearance and persisted', (
      tester,
    ) async {
      final (controller, editMode) = await pumpSlot(tester);
      editMode.value = true;
      await tester.pump();
      await edit(tester, find.text('Box'));

      await setRadius(tester, 20);
      expect(controller.value.style('sidebar').radius, 20);
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(StyledSurface),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        (material.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(20),
      );

      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => controller.saved);
      final restored = await tester.runAsync(() => AppearanceStore().load());
      expect(restored!.style('sidebar').radius, 20);
    });

    testWidgets('cancel restores the stored appearance', (tester) async {
      final (controller, editMode) = await pumpSlot(tester);
      editMode.value = true;
      await tester.pump();
      await edit(tester, find.text('Box'));
      await setRadius(tester, 30);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(controller.value.style('sidebar').radius, 0);
      await tester.runAsync(() => controller.saved);
      final restored = await tester.runAsync(() => AppearanceStore().load());
      expect(restored!.style('sidebar').radius, 0);
    });
    testWidgets('menu lists the container and its parents', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ValueNotifier(Appearance());
      final editMode = ValueNotifier(true);
      addTearDown(controller.dispose);
      addTearDown(editMode.dispose);
      await tester.pumpWidget(
        AppearanceScope(
          controller: controller,
          child: StyleEditScope(
            controller: editMode,
            child: MaterialApp(
              home: SuperContainer(
                slot: SurfFileAppearanceSlots.background,
                decorate: false,
                child: Scaffold(
                  body: Center(
                    child: SuperContainer(
                      slot: SurfFileAppearanceSlots.card,
                      decorate: false,
                      child: const SizedBox(
                        width: 120,
                        height: 60,
                        child: Text('Box'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Iterable<bool> outlined() => tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(SuperContainer),
              matching: find.byType(CustomPaint),
            ),
          )
          .where(
            (p) =>
                p.foregroundPainter.runtimeType.toString().contains('Dashed'),
          )
          .map((_) => true);
      expect(outlined(), isEmpty);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(5, 5));
      await tester.pump();
      expect(outlined(), hasLength(1));
      await mouse.moveTo(tester.getCenter(find.text('Box')));
      await tester.pump();
      expect(outlined(), hasLength(1));
      final cardPaint = tester.widget<CustomPaint>(
        find
            .ancestor(of: find.text('Box'), matching: find.byType(CustomPaint))
            .first,
      );
      expect(cardPaint.foregroundPainter, isNotNull);
      await mouse.moveTo(const Offset(-10, -10));
      await tester.pump();
      expect(outlined(), isEmpty);

      await rightClick(tester, find.text('Box'));
      final items = find.byType(PopupMenuItem<SuperContainerState>);
      expect(items, findsNWidgets(2));
      expect(
        tester.getTopLeft(find.text('Style des cartes')).dy,
        lessThan(tester.getTopLeft(find.text('Fond de l’application')).dy),
      );

      await tester.tap(find.text('Fond de l’application'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(AlertDialog, 'Fond de l’application'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      await edit(tester, find.text('Box'));
      expect(
        find.widgetWithText(AlertDialog, 'Style des cartes'),
        findsOneWidget,
      );

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(items, findsOneWidget);
      expect(find.text('Style des cartes'), findsNothing);
    });
  });

  testWidgets('background editor selects a flutter_acrylic window effect', (
    tester,
  ) async {
    final controller = ValueNotifier(Appearance());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      AppearanceScope(
        controller: controller,
        child: MaterialApp(
          home: SuperContainer(
            slot: SurfFileAppearanceSlots.background,
            decorate: false,
            child: const Scaffold(body: SizedBox.expand(child: Text('Fond'))),
          ),
        ),
      ),
    );
    await edit(tester, find.text('Fond'));
    final dropdown = find.byKey(const ValueKey('window-effect'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    final items = tester
        .widget<DropdownButton<WindowEffect>>(
          find.byType(DropdownButton<WindowEffect>),
        )
        .items!;
    expect(items.map((i) => i.value), WindowEffect.values);
    expect(
      items.firstWhere((i) => i.value == WindowEffect.hudWindow).enabled,
      isFalse,
    );
    expect(
      items.firstWhere((i) => i.value == WindowEffect.mica).enabled,
      isTrue,
    );
    await tester.tap(find.text('Mica (Windows 11)').last);
    await tester.pumpAndSettle();
    expect(controller.value.windowEffect, WindowEffect.mica);

    final restored = AppearanceStore.decode(
      AppearanceStore.encode(controller.value),
    );
    expect(restored.windowEffect, WindowEffect.mica);
    expect(
      AppearanceStore.decode(AppearanceStore.encode(Appearance()))
          .windowEffect,
      WindowEffect.transparent,
    );
  }, skip: !Platform.isWindows);

  testWidgets('padding and margin are edited and applied', (tester) async {
    final changes = await pump(tester);
    final surface = find.byType(StyledSurface);
    final box = find.text('Box');
    final surfaceBefore = tester.getRect(surface);
    expect(tester.getRect(box).topLeft, surfaceBefore.topLeft);

    await edit(tester, box);
    final padding = tester.widget<Slider>(
      find.byKey(const ValueKey('padding-Super container')),
    );
    padding.onChanged!(10);
    await tester.pump();
    final margin = tester.widget<Slider>(
      find.byKey(const ValueKey('margin-Super container')),
    );
    margin.onChanged!(6);
    await tester.pump();
    expect(changes.last.padding, 10);
    expect(changes.last.margin, 6);

    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    final surfaceRect = tester.getRect(surface);
    final outer = tester.getRect(find.byType(SuperContainer));
    expect(surfaceRect.left - outer.left, 6);
    expect(tester.getRect(box).left - surfaceRect.left, 10);
  });

  test('padding and margin round-trip through JSON', () {
    const style = ContainerStyle(padding: 7, margin: 3);
    final restored = ContainerStyle.fromJson(style.toJson());
    expect(restored.padding, 7);
    expect(restored.margin, 3);
    expect(
      ContainerStyle.fromJson(
        {...style.toJson()}..remove('padding'),
        fallback: SurfFileAppearanceDefaults.defaultCardStyle,
      ).padding,
      12,
    );
    expect(
      () => ContainerStyle.fromJson({...style.toJson(), 'margin': 99}),
      throwsFormatException,
    );
  });

  testWidgets('edit mode banner shows and closes edit mode', (tester) async {
    final editMode = ValueNotifier(false);
    addTearDown(editMode.dispose);
    await tester.pumpWidget(
      StyleEditScope(
        controller: editMode,
        child: MaterialApp(
          builder: (context, child) => Stack(
            children: [
              child!,
              const Positioned.fill(child: StyleEditBanner()),
            ],
          ),
          home: const Scaffold(),
        ),
      ),
    );
    expect(find.text('Mode édition'), findsNothing);
    editMode.value = true;
    await tester.pump();
    expect(find.text('Mode édition'), findsOneWidget);
    final banner = tester.getRect(
      find.byKey(const ValueKey('style-edit-banner')),
    );
    expect(banner.center.dx, closeTo(400, 1));
    expect(banner.top, lessThan(20));

    final close = find.byKey(const ValueKey('style-edit-banner-close'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(close));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Quitter le mode édition'), findsOneWidget);
    await tester.tap(close);
    await tester.pump();
    expect(editMode.value, isFalse);
    expect(find.text('Mode édition'), findsNothing);
  });

  testWidgets('right click does nothing when not editable', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SuperContainer(
              editable: false,
              child: SizedBox(width: 120, height: 60, child: Text('Box')),
            ),
          ),
        ),
      ),
    );
    await rightClick(tester, find.text('Box'));
    expect(find.byType(ContainerStyleEditor), findsNothing);
  });
}
