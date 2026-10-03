import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surf_file/pages/explorer_page.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/services/personal_folders.dart';
import 'package:surf_file/theme/appearance.dart';
import 'package:surf_file/theme/folder_transition.dart';
import 'package:surf_file/widgets/appearance_settings.dart';
import 'package:surf_file/widgets/explorer_breadcrumbs.dart';
import 'package:surf_file/widgets/explorer_entries_view.dart';
import 'package:surf_file/widgets/explorer_sidebar.dart';
import 'package:surf_file/widgets/explorer_sort_header.dart';
import 'package:surf_file/widgets/explorer_view_toggle.dart';
import 'package:surf_file/widgets/folder_transition_view.dart';
import 'package:surf_file/widgets/folder_hero_flight.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('transition settings persist and invalid preferences are rejected',
      () async {
    SharedPreferences.setMockInitialValues({});
    for (final type in FolderTransition.values) {
      for (final duration in [100.0, 220.0, 1000.0]) {
        final appearance = const Appearance().copyWith(
            folderTransition: type, folderTransitionDuration: duration);
        await AppearanceStore().save(appearance);
        final restored = await AppearanceStore().load();
        expect(restored.folderTransition, type);
        expect(restored.folderTransitionDuration, duration);
      }
    }
    final legacy = AppearanceStore.decode('{"version":1,"mode":"light"}');
    expect(legacy.folderTransition, FolderTransition.none);
    expect(legacy.folderTransitionDuration, 220);
    for (final value in ['bad', 1]) {
      expect(
          () => AppearanceStore.decode(jsonEncode(
              {'version': 1, 'mode': 'light', 'folderTransition': value})),
          throwsFormatException);
    }
    for (final value in [99, 1001, 'slow']) {
      expect(
          () => AppearanceStore.decode(jsonEncode({
                'version': 1,
                'mode': 'light',
                'folderTransitionDuration': value,
              })),
          throwsFormatException);
    }
  });

  for (final type in FolderTransition.values) {
    testWidgets('transition $type respects duration and revision',
        (tester) async {
      final controller = ValueNotifier(
          Appearance(folderTransition: type, folderTransitionDuration: 400));
      addTearDown(controller.dispose);
      Future<void> show(int revision,
              {bool reverse = false,
              bool reduced = false,
              String text = 'content'}) =>
          tester.pumpWidget(AppearanceScope(
            controller: controller,
            child: MaterialApp(
                home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: SizedBox(
                  width: 400,
                  height: 300,
                  child: FolderTransitionView(
                      revision: revision, reverse: reverse, child: Text(text))),
            )),
          ));
      double remaining() => switch (type) {
            FolderTransition.none => 0,
            FolderTransition.fade ||
            FolderTransition.heroExpand ||
            FolderTransition.heroIcon =>
              1 -
                  tester
                      .widget<Opacity>(
                          find.byKey(const ValueKey('folder-fade')))
                      .opacity,
            FolderTransition.slide => tester
                    .widget<FractionalTranslation>(
                        find.byKey(const ValueKey('folder-slide')))
                    .translation
                    .dx
                    .abs() /
                .08,
            FolderTransition.fullSlide => tester
                .widget<FractionalTranslation>(
                    find.byKey(const ValueKey('folder-full-slide')))
                .translation
                .dx
                .abs(),
            FolderTransition.zoom => (tester
                            .widget<Transform>(
                                find.byKey(const ValueKey('folder-zoom')))
                            .transform
                            .storage[0] -
                        1)
                    .abs() /
                .03,
          };
      await show(0);
      expect(find.byKey(const ValueKey('folder-fade')), findsNothing);
      await show(1);
      if (type == FolderTransition.none) {
        expect(tester.binding.hasScheduledFrame, isFalse);
        return;
      }
      expect(remaining(), closeTo(1, .0001));
      if (type == FolderTransition.fullSlide) {
        final slide = find.byKey(const ValueKey('folder-full-slide'));
        final content = find.text('content').last;
        expect(tester.getTopLeft(content).dx - tester.getTopLeft(slide).dx,
            closeTo(tester.getSize(slide).width, .001));
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(remaining(), greaterThan(0));
      expect(remaining(), lessThan(1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(remaining(), closeTo(0, .0001));
      await show(1, text: 'filtered');
      expect(remaining(), closeTo(0, .0001));
      await show(2, reverse: true);
      if (type == FolderTransition.slide) {
        expect(
            tester
                .widget<FractionalTranslation>(
                    find.byKey(const ValueKey('folder-slide')))
                .translation
                .dx,
            -.08);
      }
      if (type == FolderTransition.fullSlide) {
        final slide = find.byKey(const ValueKey('folder-full-slide'));
        expect(tester.widget<FractionalTranslation>(slide).translation.dx, -1);
        expect(
            tester.getTopLeft(find.text('content').last).dx -
                tester.getTopLeft(slide).dx,
            closeTo(-tester.getSize(slide).width, .001));
      }
      if (type == FolderTransition.zoom) {
        expect(
            tester
                .widget<Transform>(find.byKey(const ValueKey('folder-zoom')))
                .transform
                .storage[0],
            1.03);
      }
      await show(2, reduced: true);
      expect(remaining(), closeTo(0, .0001));
      await show(3, reduced: true);
      expect(remaining(), closeTo(0, .0001));
      await show(4);
      controller.value =
          controller.value.copyWith(folderTransition: FolderTransition.none);
      await tester.pump();
      expect(remaining(), closeTo(0, .0001));
      expect(tester.takeException(), isNull);
    });
  }

  for (final type in FolderTransition.values) {
    testWidgets('old folder stays visible only during $type', (tester) async {
      final controller = ValueNotifier(
          Appearance(folderTransition: type, folderTransitionDuration: 400));
      addTearDown(controller.dispose);
      var oldTaps = 0;
      Future<void> show(int revision, String text) =>
          tester.pumpWidget(AppearanceScope(
            controller: controller,
            child: MaterialApp(
              home: FolderTransitionView(
                revision: revision,
                reverse: false,
                child: GestureDetector(
                  onTap: () => oldTaps++,
                  child: Text(text),
                ),
              ),
            ),
          ));
      await show(0, 'old folder');
      await show(1, 'new folder');
      expect(find.text('new folder'), findsOneWidget);
      if (type == FolderTransition.none) {
        expect(find.text('old folder'), findsNothing);
        return;
      }
      expect(find.text('old folder'), findsOneWidget);
      final blocked = find.ancestor(
          of: find.text('old folder'), matching: find.byType(IgnorePointer));
      expect(
          tester
              .widgetList<IgnorePointer>(blocked)
              .any((widget) => widget.ignoring),
          isTrue);
      expect(oldTaps, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('old folder'), findsOneWidget);
      if (type == FolderTransition.fullSlide) {
        final oldSlide = tester.widget<FractionalTranslation>(find
            .ancestor(
                of: find.text('old folder'),
                matching: find.byType(FractionalTranslation))
            .first);
        final newSlide = tester.widget<FractionalTranslation>(
            find.byKey(const ValueKey('folder-full-slide')));
        expect(oldSlide.translation.dx, lessThan(0));
        expect(newSlide.translation.dx - oldSlide.translation.dx, 1);
      }
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('old folder'), findsNothing);
      expect(find.text('new folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings expose all transition types and duration',
      (tester) async {
    final controller = ValueNotifier(const Appearance());
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1100, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppearanceScope(
      controller: controller,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => AppearanceSettings.show(context),
                        child: const Text('Réglages')),
                  ))),
    ));
    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Animation de navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Animation de navigation'));
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButtonFormField<FolderTransition>>(
        find.byKey(const ValueKey('folder-transition-type')));
    expect(dropdown.initialValue, FolderTransition.none);
    for (final type in FolderTransition.values) {
      await tester.tap(find.byKey(const ValueKey('folder-transition-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(type.label).last);
      await tester.pumpAndSettle();
      expect(controller.value.folderTransition, type);
    }
    final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('Durée de la transition (ms)')));
    expect(slider.min, 100);
    expect(slider.max, 1000);
    slider.onChanged!(750);
    await tester.pumpAndSettle();
    expect(controller.value.folderTransitionDuration, 750);
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    expect(controller.value.folderTransition, FolderTransition.none);
    expect(controller.value.folderTransitionDuration, 220);
    expect(tester.takeException(), isNull);
  });

  for (final navigationType in [
    FolderTransition.slide,
    FolderTransition.heroExpand,
    FolderTransition.heroIcon,
  ]) {
    testWidgets(
        'only successful folder changes trigger transitions: $navigationType',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('surf_file_transition_')))!;
      final first = Directory('${root.path}\\first');
      final second = Directory('${root.path}\\second');
      await tester.runAsync(() async {
        await first.create();
        await second.create();
        await File('${first.path}\\first.txt').writeAsString('first');
        await File('${second.path}\\second.txt').writeAsString('second');
        await Directory('${first.path}\\child').create();
      });
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          PersonalFolders.channel,
          (_) async => {
                for (final name in PersonalFolders.names) name: first.path,
                'Pictures': second.path,
                'Music': '${root.path}\\missing',
              });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(PersonalFolders.channel, null));
      final controller = ValueNotifier(Appearance(
          folderTransition: navigationType, folderTransitionDuration: 400));
      addTearDown(controller.dispose);
      await tester.pumpWidget(AppearanceScope(
          controller: controller,
          child: MaterialApp(
              theme: controller.value.theme(Brightness.light),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(.8)),
                  child: child!),
              home: const ExplorerPage())));
      Future<void> finishLoad() async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
        }
        fail('Directory loading did not finish.');
      }

      FolderTransitionView transition() => tester
          .widget<FolderTransitionView>(find.byType(FolderTransitionView));
      Future<void> navigate(String label) async {
        await tester.tap(find.descendant(
            of: find.byType(ExplorerSidebar), matching: find.text(label)));
      }

      String path() => tester
          .widget<ExplorerBreadcrumbs>(find.byType(ExplorerBreadcrumbs))
          .path;
      await finishLoad();
      expect(transition().revision, 0);
      await navigate('Documents');
      await finishLoad();
      await tester.pumpAndSettle();
      if (navigationType == FolderTransition.heroExpand ||
          navigationType == FolderTransition.heroIcon) {
        final entriesView = tester
            .widget<ExplorerEntriesView>(find.byType(ExplorerEntriesView));
        final child =
            entriesView.entries.firstWhere((entry) => entry.name == 'child');
        entriesView.onOpenWithBounds!(
            child,
            const Rect.fromLTWH(320, 250, 180, 80),
            const Rect.fromLTWH(330, 270, 24, 24));
        await tester.pump();
        await finishLoad();
        final flight =
            tester.widget<FolderHeroFlight>(find.byType(FolderHeroFlight));
        expect(flight.expand, navigationType == FolderTransition.heroExpand);
        expect(flight.duration.inMilliseconds, 400);
        await tester.pumpAndSettle();
        expect(find.byType(FolderHeroFlight), findsNothing);
        await tester.tap(find.byTooltip('Retour'));
        await finishLoad();
        await tester.pumpAndSettle();
      }
      final revision = transition().revision;
      await navigate('Images');
      expect(find.text('first.txt'), findsOneWidget);
      await finishLoad();
      expect(path(), second.path);
      expect(transition().revision, revision + 1);
      expect(transition().reverse, isFalse);
      expect(find.text('second.txt'), findsOneWidget);
      await tester.pumpAndSettle();
      final stableRevision = transition().revision;
      await tester.tap(find.byTooltip('Actualiser'));
      await finishLoad();
      expect(transition().revision, stableRevision);
      await tester.enterText(find.byType(TextField), 'second');
      await tester.pump();
      tester
          .widget<ExplorerSortHeader>(find.byType(ExplorerSortHeader))
          .onSortChanged(ExplorerSort.size);
      tester
          .widget<ExplorerViewToggle>(find.byType(ExplorerViewToggle))
          .onChanged(true);
      await tester.pump();
      expect(transition().revision, stableRevision);
      expect(
          tester
              .widget<ExplorerEntriesView>(find.byType(ExplorerEntriesView))
              .gridView,
          isTrue);
      await navigate('Musique');
      await finishLoad();
      expect(path(), second.path);
      expect(transition().revision, stableRevision);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byTooltip('Retour'));
      await finishLoad();
      expect(path(), first.path);
      expect(transition().reverse, isTrue);
      expect(transition().revision, stableRevision + 1);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Suivant'));
      await finishLoad();
      expect(path(), second.path);
      expect(transition().reverse, isFalse);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: !Platform.isWindows);
  }
}
