import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/theme/folder_transition.dart';
import 'package:surf_file/theme/disk_gauge_style.dart';
import 'package:super_container_layout/theme/container_style.dart';

class _DelayedStore extends AppearanceStore {
  final gate = Completer<void>();
  final writes = <Appearance>[];
  final documents = <Map<String, dynamic>>[];
  bool fail = false;

  @override
  Future<void> saveEncoded(String encoded) async {
    if (writes.isEmpty) await gate.future;
    final appearance = AppearanceStore.decode(encoded);
    documents.add(jsonDecode(encoded) as Map<String, dynamic>);
    writes.add(appearance);
    if (fail) {
      fail = false;
      throw StateError('Storage unavailable');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('independent preferences share immutable queued document snapshots', () async {
    final store = _DelayedStore();
    final errors = <Object>[];
    final controller = PersistentAppearanceController(store, errors.add);
    addTearDown(controller.dispose);
    controller.preferences.value = const SurfFilePreferences(
      folderTransition: FolderTransition.slide,
      folderTransitionDuration: 400,
    );
    controller.value = controller.value.copyWith(cardWidth: 240);
    controller.preferences.value = controller.preferences.value.copyWith(
      diskGaugeStyle: const DiskGaugeStyle(columns: 3),
      folderTransitionDuration: 700,
    );
    controller.value = controller.value.withLayout('dynamic', const SuperLayoutConfig(west: false));
    store.gate.complete();
    await controller.saved;
    expect(store.documents.length, 4);
    expect(store.documents.map((d) => (d['application'] as Map)['cardWidth']), [180, 240, 240, 240]);
    expect(store.documents.map((d) => (d['application'] as Map)['folderTransitionDuration']), [400, 400, 700, 700]);
    expect((store.documents[2]['application'] as Map)['diskGaugeStyle']['columns'], 3);
    expect((store.documents.last['layouts'] as Map).containsKey('dynamic'), isTrue);
    expect(errors, isEmpty);
  });

  test('business preference write errors surface and later writes recover', () async {
    final store = _DelayedStore()..fail = true;
    final errors = <Object>[];
    final controller = PersistentAppearanceController(store, errors.add);
    addTearDown(controller.dispose);
    controller.preferences.value = controller.preferences.value.copyWith(folderTransitionDuration: 400);
    controller.preferences.value = controller.preferences.value.copyWith(folderTransitionDuration: 600);
    store.gate.complete();
    await controller.saved;
    expect(errors.single, isA<StateError>());
    expect((store.documents.last['application'] as Map)['folderTransitionDuration'], 600);
  });

  final custom = Appearance(
    mode: ThemeMode.system,
    accent: Color(0xFF00796B),
    styles: {
      'card': ContainerStyle(
        color: Color(0xFF102030),
        radius: 24,
        elevation: 5,
        shadowOpacity: .4,
        borderWidth: 2,
      ),
      'background': ContainerStyle(color: Color(0xFFF0E0D0)),
      'selectedCard': ContainerStyle(elevation: 10),
      'selectedFolder': ContainerStyle(elevation: 8),
    },
    backgroundOpacity: .4,
    windowOpacity: .8,
    cardHeight: 230,
    cardWidth: 280,
    rowHeight: 70,
    spacing: 20,
    fontSize: 15,
    iconSize: 60,
  );

  test('all settings survive saving and a fresh controller', () async {
    final errors = <Object>[];
    final first = PersistentAppearanceController(AppearanceStore(), errors.add);
    await first.restore();
    first.value = custom;
    await first.saved;
    first.dispose();
    final second = PersistentAppearanceController(
      AppearanceStore(),
      errors.add,
    );
    addTearDown(second.dispose);
    await second.restore();
    expect(
      AppearanceStore.encode(second.value),
      AppearanceStore.encode(custom),
    );
    expect(errors, isEmpty);
    second.value = Appearance();
    await second.saved;
    final restored = await AppearanceStore().load();
    expect(
      AppearanceStore.encode(restored),
      AppearanceStore.encode(Appearance()),
    );
    expect(restored.style('card').color, isNull);
    expect(restored.styles['selectedCard'], isNull);
  });

  test('explorer main layout survives saving and has a default', () async {
    expect(
      (await AppearanceStore().load()).layout('explorerMain'),
      SurfFileAppearanceDefaults.defaultExplorerMainLayout,
    );
    final moved = SurfFileAppearanceDefaults.defaultExplorerMainLayout.withSwap(
      SuperLayoutZone.north,
    );
    final errors = <Object>[];
    final first = PersistentAppearanceController(AppearanceStore(), errors.add);
    addTearDown(first.dispose);
    await first.restore();
    first.value = first.value.withLayout('explorerMain', moved);
    await first.saved;
    final restored = await AppearanceStore().load();
    expect(restored.layout('explorerMain'), moved);
    expect(restored.layout('explorerMain').south, isTrue);
    expect(restored.layout('explorerMain').isAuto(SuperLayoutZone.south), isTrue);
    expect(errors, isEmpty);
  });

  test('sidebar layout survives saving and has a default', () async {
    expect(
      (await AppearanceStore().load()).layout('explorerSidebar'),
      SurfFileAppearanceDefaults.defaultExplorerSidebarLayout,
    );
    final moved = SurfFileAppearanceDefaults.defaultExplorerSidebarLayout.withSlotMoved(
      'sidebar-disks',
      SuperLayoutZone.center,
    );
    final controller = PersistentAppearanceController(
      AppearanceStore(),
      (_) {},
    );
    addTearDown(controller.dispose);
    await controller.restore();
    controller.value = controller.value.withLayout('explorerSidebar', moved);
    await controller.saved;
    final restored = await AppearanceStore().load();
    expect(restored.layout('explorerSidebar'), moved);
  });

  test('writes are ordered and save errors allow later writes', () async {
    final store = _DelayedStore()..fail = true;
    final errors = <Object>[];
    final controller = PersistentAppearanceController(store, errors.add);
    addTearDown(controller.dispose);
    controller.value = Appearance(cardHeight: 200);
    controller.value = Appearance(cardHeight: 250);
    store.gate.complete();
    await controller.saved;
    expect(store.writes.map((a) => a.cardHeight), [200, 250]);
    expect(errors.single, isA<StateError>());
  });

  test('expanded spacing and row height ranges survive persistence', () async {
    for (final spacing in [
      Appearance.minSpacing,
      48.0,
      Appearance.maxSpacing,
    ]) {
      for (final height in [Appearance.minRowHeight, Appearance.maxRowHeight]) {
        final appearance = custom.copyWith(spacing: spacing, rowHeight: height);
        await AppearanceStore().save(appearance);
        final restored = await AppearanceStore().load();
        expect(restored.spacing, spacing);
        expect(restored.rowHeight, height);
        expect(restored.style('card').color, custom.style('card').color);
      }
    }
    for (final spacing in [
      Appearance.minSpacing - 1,
      Appearance.maxSpacing + 1,
    ]) {
      expect(
        () => AppearanceStore.decode(
          AppearanceStore.encode(custom.copyWith(spacing: spacing)),
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('transparent and translucent colors survive persistence', () async {
    for (final alpha in [0, 64, 128, 255]) {
      final appearance = custom.copyWith(
        accent: Color((alpha << 24) | 0x00796B),
        styles: {
          ...custom.styles,
          'card': custom
              .style('card')
              .copyWith(color: Color((alpha << 24) | 0x102030)),
          'background': custom
              .style('background')
              .copyWith(color: Color((alpha << 24) | 0xE2E8F0)),
        },
      );
      await AppearanceStore().save(appearance);
      final restored = await AppearanceStore().load();
      expect(restored.accent.toARGB32(), appearance.accent.toARGB32());
      expect(
        restored.style('card').color?.toARGB32(),
        appearance.style('card').color?.toARGB32(),
      );
      expect(
        restored.style('background').color?.toARGB32(),
        appearance.style('background').color?.toARGB32(),
      );
      expect(
        restored.theme(Brightness.light).colorScheme.primary.a,
        closeTo(alpha / 255, .001),
      );
    }
  });

  test(
    'missing values default, legacy data migrates, invalid data is rejected',
    () async {
      expect(
        AppearanceStore.decode('{"version":2,"mode":"dark"}').mode,
        ThemeMode.dark,
      );
      expect(
        AppearanceStore.decode('{"version":2,"mode":"dark"}').style('card'),
        SurfFileAppearanceDefaults.defaultCardStyle,
      );
      final oldStored = jsonEncode({'version': 1, 'mode': 'dark'});
      SharedPreferences.setMockInitialValues({'appearance.v1': oldStored});
      expect(await AppearanceStore().load(), isA<Appearance>());
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('appearance.v1')!)['version'], 3);
      for (final stored in [
        'not json',
        '{"version":3,"mode":"dark"}',
        '{"version":2,"mode":"invalid"}',
        jsonEncode({'version': 2, 'mode': 'light', 'cardHeight': 1}),
        jsonEncode({
          'version': 2,
          'mode': 'light',
          'cardStyle': SurfFileAppearanceDefaults.defaultCardStyle.toJson()
            ..['shadowOpacity'] = 2,
        }),
        jsonEncode({'version': 2, 'mode': 'light', 'accent': 'red'}),
        jsonEncode({'version': 2, 'mode': 'light', 'windowOpacity': 0}),
        jsonEncode({'version': 2, 'mode': 'light', 'backgroundOpacity': 2}),
        jsonEncode({
          'version': 2,
          'mode': 'light',
          'cardStyle': {'color': -1},
        }),
        jsonEncode({
          'version': 2,
          'mode': 'light',
          'backgroundStyle': {'color': 0x100000000},
        }),
      ]) {
        expect(
          () => AppearanceStore.decode(stored),
          throwsA(isA<FormatException>()),
        );
      }
      SharedPreferences.setMockInitialValues({'appearance.v1': 42});
      await expectLater(
        AppearanceStore().load(),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
