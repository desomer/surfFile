import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surf_file/models/super_layout_config.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/theme/appearance.dart';
import 'package:surf_file/theme/container_style.dart';

class _DelayedStore extends AppearanceStore {
  final gate = Completer<void>();
  final writes = <Appearance>[];
  bool fail = false;

  @override
  Future<void> save(Appearance appearance) async {
    if (writes.isEmpty) await gate.future;
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

  const custom = Appearance(
    mode: ThemeMode.system,
    accent: Color(0xFF00796B),
    cardStyle: ContainerStyle(
      color: Color(0xFF102030),
      radius: 24,
      elevation: 5,
      shadowOpacity: .4,
      borderWidth: 2,
    ),
    backgroundStyle: ContainerStyle(color: Color(0xFFF0E0D0)),
    backgroundOpacity: .4,
    windowOpacity: .8,
    selectedCardStyle: ContainerStyle(elevation: 10),
    selectedFolderStyle: ContainerStyle(elevation: 8),
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
    second.value = const Appearance();
    await second.saved;
    final restored = await AppearanceStore().load();
    expect(
      AppearanceStore.encode(restored),
      AppearanceStore.encode(const Appearance()),
    );
    expect(restored.cardStyle.color, isNull);
    expect(restored.selectedCardStyle, isNull);
  });

  test('explorer main layout survives saving and has a default', () async {
    expect(
      (await AppearanceStore().load()).explorerMainLayout,
      Appearance.defaultExplorerMainLayout,
    );
    final moved = Appearance.defaultExplorerMainLayout.withSwap(
      SuperLayoutZone.north,
    );
    final errors = <Object>[];
    final first = PersistentAppearanceController(AppearanceStore(), errors.add);
    addTearDown(first.dispose);
    await first.restore();
    first.value = first.value.copyWith(explorerMainLayout: moved);
    await first.saved;
    final restored = await AppearanceStore().load();
    expect(restored.explorerMainLayout, moved);
    expect(restored.explorerMainLayout.south, isTrue);
    expect(restored.explorerMainLayout.isAuto(SuperLayoutZone.south), isTrue);
    expect(errors, isEmpty);
  });

  test('sidebar layout survives saving and has a default', () async {
    expect(
      (await AppearanceStore().load()).explorerSidebarLayout,
      Appearance.defaultExplorerSidebarLayout,
    );
    final moved = Appearance.defaultExplorerSidebarLayout.withSlotMoved(
      'sidebar-disks',
      SuperLayoutZone.center,
    );
    final controller = PersistentAppearanceController(
      AppearanceStore(),
      (_) {},
    );
    addTearDown(controller.dispose);
    await controller.restore();
    controller.value = controller.value.copyWith(explorerSidebarLayout: moved);
    await controller.saved;
    final restored = await AppearanceStore().load();
    expect(restored.explorerSidebarLayout, moved);
  });

  test('writes are ordered and save errors allow later writes', () async {
    final store = _DelayedStore()..fail = true;
    final errors = <Object>[];
    final controller = PersistentAppearanceController(store, errors.add);
    addTearDown(controller.dispose);
    controller.value = const Appearance(cardHeight: 200);
    controller.value = const Appearance(cardHeight: 250);
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
        expect(restored.cardStyle.color, custom.cardStyle.color);
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
        cardStyle: custom.cardStyle.copyWith(
          color: Color((alpha << 24) | 0x102030),
        ),
        backgroundStyle: custom.backgroundStyle.copyWith(
          color: Color((alpha << 24) | 0xE2E8F0),
        ),
      );
      await AppearanceStore().save(appearance);
      final restored = await AppearanceStore().load();
      expect(restored.accent.toARGB32(), appearance.accent.toARGB32());
      expect(
        restored.cardStyle.color?.toARGB32(),
        appearance.cardStyle.color?.toARGB32(),
      );
      expect(
        restored.backgroundStyle.color?.toARGB32(),
        appearance.backgroundStyle.color?.toARGB32(),
      );
      expect(
        restored.theme(Brightness.light).colorScheme.primary.a,
        closeTo(alpha / 255, .001),
      );
    }
  });

  test(
    'missing values default, v1 is discarded, and invalid data is rejected',
    () async {
      expect(
        AppearanceStore.decode('{"version":2,"mode":"dark"}').mode,
        ThemeMode.dark,
      );
      expect(
        AppearanceStore.decode('{"version":2,"mode":"dark"}').cardStyle,
        Appearance.defaultCardStyle,
      );
      final oldStored = jsonEncode({'version': 1, 'mode': 'dark'});
      expect(AppearanceStore.isOutdated(oldStored), isTrue);
      SharedPreferences.setMockInitialValues({AppearanceStore.key: oldStored});
      expect(await AppearanceStore().load(), isA<Appearance>());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(AppearanceStore.key), isFalse);
      for (final stored in [
        'not json',
        '{"version":1,"mode":"dark"}',
        '{"version":3,"mode":"dark"}',
        '{"version":2,"mode":"invalid"}',
        jsonEncode({'version': 2, 'mode': 'light', 'cardHeight': 1}),
        jsonEncode({
          'version': 2,
          'mode': 'light',
          'cardStyle': Appearance.defaultCardStyle.toJson()
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
      SharedPreferences.setMockInitialValues({AppearanceStore.key: 42});
      await expectLater(
        AppearanceStore().load(),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
