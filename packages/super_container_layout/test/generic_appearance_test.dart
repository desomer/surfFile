import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'arbitrary stable identifiers round trip through persistence and transfer',
    () async {
      final value = Appearance(
        styles: {'editor/preview': const ContainerStyle(radius: 23)},
        layouts: {'workspace': const SuperLayoutConfig(westSize: 203)},
      );
      final store = AppearanceStore();
      await store.save(value);
      final restored = await AppearanceStore().load();
      expect(AppearanceStore.encode(restored), AppearanceStore.encode(value));
      final export = AppearanceTransfer.export(value, {
        ...TransferGroup.values,
      });
      final imported = AppearanceTransfer.import(Appearance(), export, {
        ...TransferGroup.values,
      });
      expect(AppearanceStore.encode(imported), AppearanceStore.encode(value));
      expect(
        (await SharedPreferences.getInstance()).containsKey('appearance.v1'),
        isFalse,
      );
    },
  );
  test(
    'style and nested layout collections are immutable defensive snapshots',
    () {
      final ids = ['preview'];
      final placements = {SuperLayoutZone.center: ids};
      final styles = {'custom': const ContainerStyle(radius: 11)};
      final layouts = {'workspace': SuperLayoutConfig(placements: placements)};
      final a = Appearance(styles: styles, layouts: layouts);
      styles.clear();
      layouts.clear();
      ids.add('other');
      placements.clear();
      expect(a.style('custom').radius, 11);
      expect(a.layout('workspace').placementsOf(SuperLayoutZone.center), [
        'preview',
      ]);
      expect(() => a.styles.clear(), throwsUnsupportedError);
      expect(() => a.layouts.clear(), throwsUnsupportedError);
      expect(
        () => a
            .layout('workspace')
            .placementsOf(SuperLayoutZone.center)
            .add('other'),
        throwsUnsupportedError,
      );
      expect(
        () => a.layout('workspace').autoSides.add(SuperLayoutZone.north),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'generic registry controllers persist by ID and follow restore/reset',
    () async {
      final controller = PersistentAppearanceController(
        AppearanceStore(),
        (error) => fail('$error'),
      );
      final registry = Registry()..bindAppearance(controller);
      addTearDown(() {
        registry.unbindAppearance();
        controller.dispose();
      });
      final layout = registry.layoutController('workspace');
      final style = registry.styleController('preview');
      layout.value = const SuperLayoutConfig(westSize: 257);
      style.value = const ContainerStyle(radius: 27);
      await controller.saved;
      final restart = await AppearanceStore().load();
      expect(restart.layout('workspace').westSize, 257);
      expect(restart.style('preview').radius, 27);
      controller.value = controller.value.resetLayouts();
      expect(layout.value.westSize, 120);
      expect(style.value.radius, 27);
      controller.value = Appearance();
      expect(style.value.radius, 0);
      await controller.saved;
    },
  );
  test('invalid versions, keys, styles and layouts are rejected', () {
    final valid = jsonDecode(
      AppearanceStore.encode(Appearance()),
    ) as Map<String, dynamic>;
    for (final bad in [
      {...valid, 'version': 99},
      {...valid, 'unknown': true},
      {
        ...valid,
        'styles': {'bad': null},
      },
      {...valid, 'styles': []},
      {
        ...valid,
        'layouts': {'bad': false},
      },
      {...valid, 'windowOpacity': 0},
      {...valid, 'mode': 'invalid'},
    ]) {
      expect(
        () => AppearanceStore.decode(jsonEncode(bad)),
        throwsFormatException,
      );
    }
  });
  test('invalid stored data is retained rather than discarded', () async {
    const bad = '{"version":99}';
    SharedPreferences.setMockInitialValues({
      'super_container_layout.appearance': bad,
    });
    await expectLater(AppearanceStore().load(), throwsFormatException);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'super_container_layout.appearance',
      ),
      bad,
    );
  });
  test(
    'standalone package has no SurfFile imports or business model dependencies',
    () {
      final root = File('lib\\theme\\appearance.dart').existsSync()
          ? Directory('lib')
          : Directory('packages\\super_container_layout\\lib');
      for (final file
          in root
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        final text = file.readAsStringSync();
        expect(text, isNot(contains('package:surf_file/')), reason: file.path);
        for (final symbol in [
          'SurfFileAppearance',
          'DiskGaugeStyle',
          'FolderTransition',
          'defaultExplorerLayout',
        ]) {
          expect(text, isNot(contains(symbol)), reason: file.path);
        }
      }
    },
  );
}
