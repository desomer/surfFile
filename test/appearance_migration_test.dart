import 'dart:convert';
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
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

String v3Document() {
  const style = ContainerStyle(
    color: Color(0x80123456),
    radius: 21,
    borderWidth: 3,
    borderColor: Color(0xAA987654),
    elevation: 7,
    shadowOpacity: .6,
    padding: 13,
    margin: 3,
    fill: ContainerFill(
      type: FillType.linear,
      start: Color(0xAAFF0000),
      end: Color(0x880000FF),
    ),
    neon: NeonStyle(enabled: true, intensity: .9, color: Colors.pink),
    radii: Quad(1, 2, 3, 4),
    opacity: .8,
    pattern: SurfacePattern.dots,
  );
  const layout = SuperLayoutConfig(
    north: false,
    east: false,
    westSize: 277,
    southSize: 109,
    swaps: {SuperLayoutZone.west},
    autoSides: {SuperLayoutZone.south},
    placements: {
      SuperLayoutZone.west: ['sidebar', 'registry:custom'],
      SuperLayoutZone.center: ['main'],
    },
  );
  const gauge = DiskGaugeStyle(
    shape: DiskGaugeShape.meter,
    size: 77,
    thickness: 8,
    roundCaps: true,
    trackColor: Color(0x66123456),
    fillColor: Colors.cyan,
    gradient: [Colors.blue, Colors.purple],
    alertColor: Colors.red,
    alertThreshold: .7,
    start: DiskGaugeStart.left,
    clockwise: false,
    trackNeon: NeonStyle(enabled: true, intensity: 1.1),
    alertPulse: true,
    labelNeon: true,
    animate: false,
    animationMs: 900,
    percentSize: 15,
    percentWeight: 8,
    nameSize: 14,
    captionSize: 11,
    columns: 3,
  );
  final appearance = DefaultAppearance(
    mode: ThemeMode.dark,
    accent: const Color(0x8000796B),
    backgroundOpacity: .45,
    windowOpacity: .8,
    windowEffect: WindowEffect.mica,
    styles: {
      for (final id in SurfFileAppearanceDefaults.defaultStyles.keys) id: style,
      'selectedCard': style,
    },
    layouts: {
      for (final id in SurfFileAppearanceDefaults.defaultLayouts.keys)
        id: layout,
    },
    cardHeight: 243.0,
    cardWidth: 287.0,
    rowHeight: 77.0,
    spacing: 31.0,
    fontSize: 15.0,
    iconSize: 58.0,
    scrollFadeEnabled: false,
    scrollFadeExtent: 57.0,
  );
  const prefs = SurfFilePreferences(
    diskGaugeStyle: gauge,
    folderTransition: FolderTransition.fullSlide,
    folderTransitionDuration: 680.0,
  );
  return AppearanceStore.encode(appearance, preferences: prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const both = {TransferGroup.styles, TransferGroup.layouts};

  test('v3 values survive restart, transfer and reset', () async {
    final doc = v3Document();
    SharedPreferences.setMockInitialValues({'appearance.v1': doc});
    final store = AppearanceStore();
    final loaded = await store.load();
    expect(
      AppearanceStore.encode(loaded, preferences: store.preferences.value),
      doc,
    );
    final errors = <Object>[];
    final restart = PersistentAppearanceController(
      AppearanceStore(),
      errors.add,
    );
    addTearDown(restart.dispose);
    await restart.restore();
    final codec = SurfFileAppearanceCodec(preferences: restart.preferences);
    expect(codec.encode(restart.value), doc);
    final exported = AppearanceTransfer.export(
      restart.value,
      both,
      codec: codec,
    );
    final imported = AppearanceTransfer.import(
      Appearance(),
      exported,
      both,
      codec: codec,
    );
    expect(codec.encode(imported), doc);
    restart.reset();
    await restart.saved;
    expect(
      AppearanceStore.encode(await AppearanceStore().load()),
      AppearanceStore.encode(Appearance()),
    );
    expect(errors, isEmpty);
  });

  test('generic shell updates keep typed business preferences and unknown IDs', () {
    final codec = SurfFileAppearanceCodec();
    final text = v3Document();
    codec.restoreAdditional(text);
    shell.Appearance a = codec.decode(text);
    a = a
        .withStyle('third-party/surface', const ContainerStyle(radius: 31))
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

  testWidgets('typed scope preserves the controller and bridge across rebuilds', (
    tester,
  ) async {
    final controller = ValueNotifier(Appearance());
    addTearDown(controller.dispose);
    shell.Appearance? observed;
    ValueNotifier<shell.Appearance>? bridge;
    final home = Builder(
      builder: (context) {
        expect(AppearanceScope.controllerOf(context), same(controller));
        bridge = shell.AppearanceScope.controllerOf(context);
        observed = AppearanceScope.of(context);
        return Text(observed!.mode.name);
      },
    );
    Future<void> pump() => tester.pumpWidget(
      AppearanceScope(
        controller: controller,
        child: MaterialApp(home: home),
      ),
    );
    await pump();
    final initialBridge = bridge;
    await pump();
    expect(bridge, same(initialBridge));
    controller.value = controller.value.copyWith(
      mode: ThemeMode.dark,
      cardWidth: 241,
    );
    await tester.pump();
    expect(find.text('dark'), findsOneWidget);
    expect((observed! as DefaultAppearance).cardWidth, 241);
    expect(tester.takeException(), isNull);
  });

  test('selection reset still follows standard style without deleting business values', () {
    final initial = AppearanceStore.decode(v3Document());
    final reset = SurfFileAppearanceSlots.selectedCard.reset(initial);
    expect(reset.styles['selectedCard'], isNull);
    expect(
      SurfFileAppearanceSlots.selectedCard.read(reset).radius,
      initial.style('card').radius,
    );
    final configured = SurfFileAppearanceCodec().prepare(reset.resetLayouts());
    expect(configured.cardHeight, 243);
    expect(
      configured.layout('explorer'),
      SurfFileAppearanceDefaults.defaultExplorerLayout,
    );
  });

  test('invalid new storage, future versions and malformed imports are rejected', () {
    final valid =
        jsonDecode(AppearanceStore.encode(Appearance())) as Map<String, dynamic>;
    for (final document in [
      {...valid, 'version': 1},
      {...valid, 'version': 2},
      {...valid, 'version': 99},
      {...valid, 'styles': {'broken': 'bad'}},
      {...valid, 'layouts': []},
      {...valid, 'application': {'cardWidth': -1}},
      {...valid, 'application': {'folderTransition': 'invalid'}},
      {...valid, 'application': {'unknown': 1}},
      {...valid, 'styles': {'': const ContainerStyle().toJson()}},
    ]) {
      expect(
        () => AppearanceStore.decode(jsonEncode(document)),
        throwsFormatException,
      );
      expect(
        () => AppearanceTransfer.import(Appearance(), jsonEncode(document), both),
        throwsFormatException,
      );
    }
    expect(
      () => AppearanceTransfer.groupsIn('not json'),
      throwsFormatException,
    );
    expect(
      () => SurfFileAppearanceCodec().encode(shell.Appearance()),
      throwsStateError,
    );
  });
}
