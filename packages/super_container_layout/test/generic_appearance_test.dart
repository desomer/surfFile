import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart' show Axis;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('numeric normalization preserves integers, text and input collections', () {
    final input = <String, Object?>{
      'nested': [1.23456, -4.56789, .0001, -0.0, 1e100],
      'color': 0xFF5268D9,
      'text': '1.23456',
    };
    final normalized = JsonNumbers.normalizeMap(input);
    expect(normalized['nested'], [1.23, -4.57, 0, 0, 1e100]);
    expect(normalized['color'], isA<int>());
    expect(normalized['text'], '1.23456');
    expect((input['nested'] as List).first, 1.23456);
    expect(JsonNumbers.normalizeMap(normalized), normalized);
    for (final value in [double.nan, double.infinity, double.negativeInfinity]) {
      expect(() => JsonNumbers.normalizeMap({'value': value}),
          throwsFormatException);
    }
  });

  test('persistence, export and Vibe round nested UI numbers consistently', () async {
    const codec = DefaultAppearanceCodec();
    final appearance = DefaultAppearance(
      fontSize: 14.12345,
      styles: {
        'card': const ContainerStyle(
          radius: 12.34567, opacity: .45678,
          transform: TransformSpec(scale: 1.12345),
        ),
      },
      components: {
        'layout': const SuperLayoutConfig(
          westSize: 123.45678,
          slotSizeConstraints: {
            'text': SlotSizeConstraints(
              preferredWidth: SlotDimension(32.12345, SlotSizeUnit.percent),
            ),
          },
        ),
        'text': const SuperValueConfig(
          fontSize: 16.78912, initialText: '1.23456',
        ),
      },
    );
    void verify(Object? value) {
      if (value is double) {
        expect(value, double.parse(value.toStringAsFixed(2)));
      } else if (value is Map) {
        value.values.forEach(verify);
      } else if (value is List) {
        value.forEach(verify);
      }
    }
    final store = AppearanceStore(codec: codec);
    // Exercise the public raw-document entry point as well as codec.encode.
    await store.saveEncoded(jsonEncode(codec.toJson(appearance)));
    final saved = (await SharedPreferences.getInstance()).getString(store.key)!;
    verify(jsonDecode(saved));
    expect(((await store.load()) as DefaultAppearance).fontSize, 14.12);
    expect(codec.encode(codec.decode(saved)), saved);
    final export = AppearanceTransfer.export(
      appearance, {...TransferGroup.values}, codec: codec,
    );
    verify(jsonDecode(export));
    final restored = AppearanceTransfer.import(
      DefaultAppearance(), export, {...TransferGroup.values}, codec: codec,
    );
    expect(restored.valueComponent('text').initialText, '1.23456');
    final patched = AppearanceTransfer.applyVibe(
      restored,
      '{"styles":{"card":{"radius":23.45678}}}',
      codec: codec,
    );
    expect(patched.style('card').radius, 23.46);
    verify(jsonDecode(codec.encode(patched)));
    expect(JsonDimension.format(
      const SlotDimension(32.12345, SlotSizeUnit.percent),
    ), '32.12%');
  });

  test('large extensible settings round trip without raising slider limits', () {
    final style = ContainerStyle(
      radius: 4000.12, borderWidth: 1000.12, elevation: 1000.12,
      padding: 4000.12, margin: 4000.12, backdropBlur: 4000.12,
      radii: const Quad.all(4000.12),
      borderWidths: const Quad.all(1000.12),
      paddingInsets: const Quad.all(4000.12),
      marginInsets: const Quad.all(4000.12),
      shadow: const ShadowSpec(blur: 4000.12, dx: -4000.12, spread: 4000.12),
      transform: const TransformSpec(dx: 4000.12, scale: 40.12),
    );
    final layout = const SuperLayoutConfig().withSize(
      SuperLayoutZone.west, 5000.12,
    ).copyWith(zoneFlows: {
      SuperLayoutZone.center: const ZoneFlowConfig(
        spacing: 2000.12, padding: 3000.12,
        scrollbarStyle: ScrollbarStyleConfig(thickness: 1000.12, radius: 1000.12),
      ),
    }, slotSizeConstraints: {
      'text': const SlotSizeConstraints(padding: 3000.12),
    });
    final appearance = Appearance(styles: {'card': style}, layouts: {'main': layout});
    final restored = AppearanceStore.decode(AppearanceStore.encode(appearance));
    expect(restored.style('card'), style);
    expect(restored.layout('main'), layout);
    final shape = const NativeShapeConfig().copyWith(
      radius: 1000.12, borderWidth: 1000.12,
    );
    expect(NativeShapeConfig.fromJson(shape.toJson()), shape);
    final elevation = superAppBarPropertyDescriptors.firstWhere(
      (descriptor) => descriptor.id == 'elevation',
    );
    expect(elevation.normalizeValue(1000.12), 1000.12);
    final opacity = superAppBarPropertyDescriptors.firstWhere(
      (descriptor) => descriptor.id == 'toolbarOpacity',
    );
    expect(opacity.normalizeValue(10), 1);
    expect(() => ContainerStyle.fromJson({'opacity': 10}), throwsFormatException);
  });
  test(
    'arbitrary stable identifiers round trip through persistence and transfer',
    () async {
      final value = Appearance(
        styles: {'editor/preview': const ContainerStyle(radius: 23)},
        layouts: {
          'workspace': const SuperLayoutConfig(westSize: 203)
              .withSlotMoved(
                'nested-instance',
                SuperLayoutZone.center,
                type: 'registry:Layout',
              )
              .withSlotPreferredSize('nested-instance', const Size(250, 150))
              .withAxis(SuperLayoutZone.center, Axis.horizontal),
          'nested-instance': const SuperLayoutConfig(
            swaps: {SuperLayoutZone.west},
          ),
        },
        components: {
          'workspace-page': ScaffoldPageConfig(
            placements: {
              ScaffoldPageRegion.drawer: ['navigation'],
            },
            slotTypes: {'navigation': 'component:navigation'},
          ).withRegionEnabled(ScaffoldPageRegion.drawer, false),
        },
      );
      final store = AppearanceStore();
      await store.save(value);
      final restored = await AppearanceStore().load();
      expect(AppearanceStore.encode(restored), AppearanceStore.encode(value));
      expect(
        restored.layout('workspace').slotTypeOf('nested-instance'),
        'registry:Layout',
      );
      expect(restored.layout('nested-instance').swaps, {SuperLayoutZone.west});
      expect(
        restored.layout('workspace').axisOf(SuperLayoutZone.center),
        Axis.horizontal,
      );
      expect(
        restored.layout('workspace').slotPreferredSizes['nested-instance'],
        const Size(250, 150),
      );
      expect(
        restored.scaffoldPage('workspace-page').slotTypeOf('navigation'),
        'component:navigation',
      );
      expect(
        restored
            .scaffoldPage('workspace-page')
            .isEnabled(ScaffoldPageRegion.drawer),
        isFalse,
      );
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
      final slotTypes = {'preview': 'registry:preview'};
      final axes = {SuperLayoutZone.center: Axis.horizontal};
      final styles = {'custom': const ContainerStyle(radius: 11)};
      final layouts = {
        'workspace': SuperLayoutConfig(
          placements: placements,
          slotTypes: slotTypes,
          zoneAxes: axes,
        ),
      };
      final a = Appearance(styles: styles, layouts: layouts);
      styles.clear();
      layouts.clear();
      ids.add('other');
      placements.clear();
      slotTypes.clear();
      axes.clear();
      expect(
        a.layout('workspace').axisOf(SuperLayoutZone.center),
        Axis.horizontal,
      );
      expect(
        () => a.layout('workspace').zoneAxes.clear(),
        throwsUnsupportedError,
      );
      expect(a.layout('workspace').slotTypeOf('preview'), 'registry:preview');
      expect(
        () => a.layout('workspace').slotTypes.clear(),
        throwsUnsupportedError,
      );
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
      expect(layout.value.westSize, 100);
      expect(style.value.radius, 27);
      controller.value = Appearance();
      expect(style.value.radius, 0);
      await controller.saved;
    },
  );
  test('invalid versions, keys, styles and components are rejected', () {
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
        'components': {'bad': false},
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
