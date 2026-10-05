import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/theme/appearance.dart' as shell;
import 'package:super_container_layout/theme/container_fill.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/neon_style.dart';
import 'package:super_container_layout/theme/style_extras.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/services/appearance_transfer.dart';
import 'package:surf_file/theme/disk_gauge_style.dart';
import 'package:surf_file/theme/folder_transition.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/theme/surffile_appearance_slots.dart';

Map<String, Object?> legacyDocument() {
  const style = ContainerStyle(
    color: Color(0x80123456), radius: 21, borderWidth: 3,
    borderColor: Color(0xAA987654), elevation: 7, shadowOpacity: .6,
    padding: 13, margin: 3,
    fill: ContainerFill(type: FillType.linear, start: Color(0xAAFF0000), end: Color(0x880000FF)),
    neon: NeonStyle(enabled: true, intensity: .9, color: Colors.pink),
    radii: Quad(1, 2, 3, 4), opacity: .8, pattern: SurfacePattern.dots,
  );
  const layout = SuperLayoutConfig(
    north: false, east: false, westSize: 277, southSize: 109,
    swaps: {SuperLayoutZone.west}, autoSides: {SuperLayoutZone.south},
    placements: {
      SuperLayoutZone.west: ['sidebar', 'registry:custom'],
      SuperLayoutZone.center: ['main'],
    },
  );
  const gauge = DiskGaugeStyle(
    shape: DiskGaugeShape.meter, size: 77, thickness: 8,
    roundCaps: true, trackColor: Color(0x66123456), fillColor: Colors.cyan,
    gradient: [Colors.blue, Colors.purple], alertColor: Colors.red,
    alertThreshold: .7, start: DiskGaugeStart.left, clockwise: false,
    trackNeon: NeonStyle(enabled: true, intensity: 1.1),
    alertPulse: true, labelNeon: true, animate: false, animationMs: 900,
    percentSize: 15, percentWeight: 8, nameSize: 14, captionSize: 11, columns: 3,
  );
  return {
    'version': 2, 'mode': 'dark', 'accent': 0x8000796B,
    'backgroundOpacity': .45, 'windowOpacity': .8, 'windowEffect': 'mica',
    for (final key in SurfFileAppearanceCodec.styleIds.keys) key: style.toJson(),
    for (final key in SurfFileAppearanceCodec.layoutIds.keys) key: layout.toJson(),
    'diskGaugeStyle': gauge.toJson(),
    'cardHeight': 243.0, 'cardWidth': 287.0, 'rowHeight': 77.0,
    'spacing': 31.0, 'fontSize': 15.0, 'iconSize': 58.0,
    'folderTransition': 'fullSlide', 'folderTransitionDuration': 680.0,
    'scrollFadeEnabled': false, 'scrollFadeExtent': 57.0,
  };
}

class _FailingMigrationStore extends SurfFileAppearanceStore {
  @override
  Future<void> save(shell.Appearance appearance) async {
    throw StateError('Storage unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const both = {TransferGroup.styles, TransferGroup.layouts};

  test('complete legacy v2 values survive migration, restart, transfer and reset', () async {
    final legacy = legacyDocument();
    SharedPreferences.setMockInitialValues({'appearance.v1': jsonEncode(legacy)});
    final store = AppearanceStore();
    final migrated = await store.load();
    expect(jsonDecode(LegacyAppearanceCodec.encode(migrated, preferences: store.preferences.value)), legacy);
    final preferences = await SharedPreferences.getInstance();
    final persisted = preferences.getString('appearance.v1')!;
    expect(jsonDecode(persisted)['version'], 3);
    expect(jsonDecode(persisted)['styles']['selectedCard'], legacy['selectedCardStyle']);
    expect(jsonDecode(persisted)['application']['diskGaugeStyle'], legacy['diskGaugeStyle']);
    final errors = <Object>[];
    final restart = PersistentAppearanceController(AppearanceStore(), errors.add);
    addTearDown(restart.dispose);
    await restart.restore();
    final codec = SurfFileAppearanceCodec(preferences: restart.preferences);
    expect(codec.encode(restart.value), persisted);
    final exported = AppearanceTransfer.export(restart.value, both, codec: codec);
    final imported = AppearanceTransfer.import(Appearance(), exported, both, codec: codec);
    expect(codec.encode(imported), persisted);
    restart.value = imported;
    await restart.saved;
    final reloadedStore = AppearanceStore();
    expect(reloadedStore.codec.encode(await reloadedStore.load()), persisted);
    restart.reset();
    await restart.saved;
    expect(AppearanceStore.encode(await AppearanceStore().load()), AppearanceStore.encode(Appearance()));
    expect(errors, isEmpty);
  });

  test('legacy raw documents and envelopes import without resetting other groups', () {
    final legacy = legacyDocument();
    for (final text in [
      jsonEncode(legacy),
      jsonEncode({'format': AppearanceTransfer.format, 'version': 2, 'groups': ['styles', 'layouts'],
        'data': {...legacy}..remove('version')}),
    ]) {
      final codec = SurfFileAppearanceCodec();
      final restored = AppearanceTransfer.import(Appearance(), text, both, codec: codec);
      expect(jsonDecode(LegacyAppearanceCodec.encode(restored, preferences: codec.preferences.value)), legacy);
      final layoutCodec = SurfFileAppearanceCodec();
      final layouts = AppearanceTransfer.import(Appearance(), text, {TransferGroup.layouts}, codec: layoutCodec);
      expect(layouts.cardWidth, 180);
      expect(layoutCodec.preferences.value.folderTransition, FolderTransition.none);
      expect(layouts.layout('explorer').westSize, 277);
      final styles = AppearanceTransfer.import(Appearance(), text, {TransferGroup.styles});
      expect(styles.cardWidth, 287);
      expect(styles.layout('explorer'), SurfFileAppearanceDefaults.defaultExplorerLayout);
    }
  });

  test('partial legacy imports preserve unmentioned styles and clear nullable variants', () {
    final current = AppearanceStore.decode(jsonEncode(legacyDocument()));
    final text = jsonEncode({'format': AppearanceTransfer.format, 'version': 2, 'groups': ['styles'],
      'data': {'selectedCardStyle': null, 'fontSize': 13}});
    final imported = AppearanceTransfer.import(current, text, both);
    expect(imported.styles['selectedCard'], isNull);
    expect(imported.style('sidebar').toJson(), current.style('sidebar').toJson());
    expect(imported.styles['selectedDiskTile']?.toJson(), current.styles['selectedDiskTile']?.toJson());
    expect(imported.fontSize, 13);
    expect(imported.layout('explorer'), current.layout('explorer'));
  });

  test('generic shell updates keep typed business preferences and unknown IDs', () {
    final codec = SurfFileAppearanceCodec();
    final text = jsonEncode(legacyDocument());
    codec.restoreAdditional(text);
    shell.Appearance a = codec.decode(text);
    a = a.withStyle('third-party/surface', const ContainerStyle(radius: 31))
      .withLayout('third-party/layout', const SuperLayoutConfig(west: false))
      .copyWith(mode: ThemeMode.system);
    final restored = codec.decode(codec.encode(a));
    expect(restored.style('third-party/surface').radius, 31);
    expect(restored.layout('third-party/layout').west, isFalse);
    expect(restored.cardHeight, 243);
    expect(codec.preferences.value.folderTransitionDuration, 680);
    expect(restored.mode, ThemeMode.system);
    expect(a, isA<DefaultAppearance>());
  });

  testWidgets('typed scope preserves the controller and bridge across rebuilds', (tester) async {
    final controller = ValueNotifier(Appearance());
    addTearDown(controller.dispose);
    shell.Appearance? observed;
    ValueNotifier<shell.Appearance>? bridge;
    final home = Builder(builder: (context) {
      expect(AppearanceScope.controllerOf(context), same(controller));
      bridge = shell.AppearanceScope.controllerOf(context);
      observed = AppearanceScope.of(context);
      return Text(observed!.mode.name);
    });
    Future<void> pump() => tester.pumpWidget(AppearanceScope(
      controller: controller, child: MaterialApp(home: home),
    ));
    await pump();
    final initialBridge = bridge;
    await pump();
    expect(bridge, same(initialBridge));
    controller.value = controller.value.copyWith(mode: ThemeMode.dark, cardWidth: 241);
    await tester.pump();
    expect(find.text('dark'), findsOneWidget);
    expect((observed! as DefaultAppearance).cardWidth, 241);
    expect(tester.takeException(), isNull);
  });

  test('selection reset still follows standard style without deleting business values', () {
    final initial = AppearanceStore.decode(jsonEncode(legacyDocument()));
    final reset = SurfFileAppearanceSlots.selectedCard.reset(initial);
    expect(reset.styles['selectedCard'], isNull);
    expect(SurfFileAppearanceSlots.selectedCard.read(reset).radius, initial.style('card').radius);
    final configured = SurfFileAppearanceCodec().prepare(reset.resetLayouts());
    expect(configured.cardHeight, 243);
    expect(configured.layout('explorer'), SurfFileAppearanceDefaults.defaultExplorerLayout);
  });

  test('invalid legacy storage is reported and never overwritten', () async {
    final bad = jsonEncode({...legacyDocument(), 'cardWidth': -1});
    SharedPreferences.setMockInitialValues({'appearance.v1': bad});
    await expectLater(AppearanceStore().load(), throwsFormatException);
    expect((await SharedPreferences.getInstance()).getString('appearance.v1'), bad);
  });

  test('failed migration writes leave the original saved settings intact', () async {
    final stored = jsonEncode(legacyDocument());
    SharedPreferences.setMockInitialValues({'appearance.v1': stored});
    await expectLater(_FailingMigrationStore().load(), throwsStateError);
    expect((await SharedPreferences.getInstance()).getString('appearance.v1'), stored);
  });

  test('real version-one separate colors, geometry, fills and halos migrate', () async {
    final old = {
      'version': 1, 'mode': 'dark', 'accent': 0xFF123456,
      'cardColor': 0x88123456, 'backgroundColor': 0xAA654321,
      'cardFill': const ContainerFill(type: FillType.linear).toJson(),
      'backgroundFill': const ContainerFill(type: FillType.radial).toJson(),
      'cardNeon': const NeonStyle(enabled: true, color: Colors.cyan, intensity: 1.2).toJson(),
      'selectedFolderNeon': const NeonStyle(enabled: true, color: Colors.pink).toJson(),
      'backgroundNeon': const NeonStyle(enabled: true).toJson(),
      'radius': 27, 'elevation': 5, 'shadowOpacity': .4,
      'borderWidth': 3, 'cardBorderColor': 0xAAABCDEF,
      'backgroundBorderColor': 0x88112233, 'backgroundBorderWidth': 2,
      'selectedCardElevation': 11, 'selectedFolderElevation': 7,
      'selectedCardStyle': null, 'selectedFolderStyle': null,
      'cardWidth': 247, 'folderTransition': 'slide',
    };
    SharedPreferences.setMockInitialValues({'appearance.v1': jsonEncode(old)});
    final migrated = await AppearanceStore().load();
    expect(migrated.style('card').color, const Color(0x88123456));
    expect(migrated.style('card').radius, 27);
    expect(migrated.style('card').fill.type, FillType.linear);
    expect(migrated.style('card').neon?.color?.toARGB32(), Colors.cyan.toARGB32());
    expect(migrated.style('card').borderColor, const Color(0xAAABCDEF));
    expect(migrated.style('background').fill.type, FillType.radial);
    expect(migrated.style('background').neon?.enabled, isTrue);
    expect(migrated.style('background').borderWidth, 2);
    expect(SurfFileAppearanceSlots.selectedCard.read(migrated).elevation, 11);
    expect(SurfFileAppearanceSlots.selectedFolder.read(migrated).elevation, 7);
    expect(SurfFileAppearanceSlots.selectedFolder.read(migrated).neon?.color?.toARGB32(), Colors.pink.toARGB32());
    expect(migrated.cardWidth, 247);
    final imported = AppearanceTransfer.import(Appearance(), jsonEncode(old), both);
    expect(AppearanceStore.encode(imported), AppearanceStore.encode(migrated));
  });

  test('invalid new storage, future versions and malformed imports are rejected', () {
    final valid = jsonDecode(AppearanceStore.encode(Appearance())) as Map<String, dynamic>;
    for (final document in [
      {...valid, 'version': 99},
      {...valid, 'styles': {'broken': 'bad'}},
      {...valid, 'layouts': []},
      {...valid, 'application': {'cardWidth': -1}},
      {...valid, 'application': {'folderTransition': 'invalid'}},
      {...valid, 'application': {'unknown': 1}},
      {...valid, 'styles': {'': const ContainerStyle().toJson()}},
    ]) {
      expect(() => AppearanceStore.decode(jsonEncode(document)), throwsFormatException);
      expect(() => AppearanceTransfer.import(Appearance(), jsonEncode(document), both), throwsFormatException);
    }
    expect(() => AppearanceTransfer.groupsIn('not json'), throwsFormatException);
    expect(() => SurfFileAppearanceCodec().encode(shell.Appearance()), throwsStateError);
  });
}
