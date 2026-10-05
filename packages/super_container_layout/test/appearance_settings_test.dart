import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

class _Codec extends AppearanceCodec {
  int resets = 0;
  @override
  Appearance get defaults => DefaultAppearance(accent: Colors.orange);
  @override
  void resetAdditional() => resets++;
}

class _ExtraScope extends InheritedWidget {
  const _ExtraScope({required this.token, required super.child});
  final Object token;
  static Object of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ExtraScope>()!.token;
  @override
  bool updateShouldNotify(_ExtraScope oldWidget) => token != oldWidget.token;
}

Future<void> _open(
  WidgetTester tester,
  ValueNotifier<Appearance> controller,
  _Codec codec, {
  List<AppearanceSlot> slots = const [],
  List<AppearanceSettingsSection> sections = const [],
  WidgetBuilder? additionalControls,
  WidgetBuilder? previewBuilder,
  VoidCallback? resetAdditional,
  Appearance Function()? defaults,
  Object? token,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: AppearanceServicesScope(
      codec: codec,
      child: AppearanceScope(
        controller: controller,
        child: _ExtraScope(
          token: token ?? Object(),
          child: Builder(builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                final captured = _ExtraScope.of(context);
                AppearanceSettings.show(
                  context,
                  slots: slots,
                  additionalSections: sections,
                  additionalControls: additionalControls,
                  previewBuilder: previewBuilder,
                  resetAdditional: resetAdditional,
                  defaults: defaults,
                  dialogWrapper: (child) =>
                      _ExtraScope(token: captured, child: child),
                );
              },
              child: const Text('Open'),
            ),
          )),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _section(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('base Appearance guards default-only sections and keeps controls',
      (tester) async {
    final controller = ValueNotifier<Appearance>(Appearance());
    addTearDown(controller.dispose);
    final codec = _Codec();
    await _open(tester, controller, codec,
      additionalControls: (_) => const Text('Extra controls'));
    expect(find.text('Extra controls'), findsOneWidget);
    expect(find.text('Dimensions et espacement'), findsNothing);
    expect(find.text('Texte et icônes'), findsNothing);
    expect(find.text('Fondu des fichiers'), findsNothing);
    await _section(tester, 'Transparence de la fenêtre');
    tester.widget<Slider>(find.byKey(
      const ValueKey('Opacité de la fenêtre'))).onChanged!(.6);
    await tester.pumpAndSettle();
    expect(controller.value.windowOpacity, .6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default sections edit geometry text fade and preserve subtype',
      (tester) async {
    final controller = ValueNotifier<Appearance>(DefaultAppearance());
    addTearDown(controller.dispose);
    await _open(tester, controller, _Codec());
    await _section(tester, 'Dimensions et espacement');
    tester.widget<Slider>(find.byKey(
      const ValueKey('Espacement'))).onChanged!(25);
    await tester.pumpAndSettle();
    expect((controller.value as DefaultAppearance).spacing, 25);
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    await _section(tester, 'Texte et icônes');
    tester.widget<Slider>(find.byKey(
      const ValueKey('Taille du texte'))).onChanged!(15);
    await tester.pumpAndSettle();
    expect((controller.value as DefaultAppearance).fontSize, 15);
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    await _section(tester, 'Fondu des fichiers');
    tester.widget<Slider>(find.byKey(
      const ValueKey('Hauteur du fondu (px)'))).onChanged!(60);
    await tester.pumpAndSettle();
    expect((controller.value as DefaultAppearance).scrollFadeExtent, 60);
    await tester.tap(find.text('Réinitialiser le fondu'));
    await tester.pumpAndSettle();
    expect((controller.value as DefaultAppearance).scrollFadeExtent, 28);
    expect(tester.takeException(), isNull);
  });

  testWidgets('routes capture controller codec extra scope and live theme',
      (tester) async {
    final controller = ValueNotifier<Appearance>(DefaultAppearance());
    addTearDown(controller.dispose);
    final codec = _Codec();
    final token = Object();
    await _open(tester, controller, codec,
      token: token,
      previewBuilder: (context) =>
          Text('Preview ${AppearanceScope.of(context).accent.toARGB32()}'),
      sections: [
        AppearanceSettingsSection(
          id: 'extra', label: 'Extra section', icon: Icons.animation,
          builder: (context) {
            expect(AppearanceScope.controllerOf(context), same(controller));
            expect(AppearanceServicesScope.codecOf(context), same(codec));
            expect(_ExtraScope.of(context), same(token));
            return const Text('Captured');
          },
        ),
      ],
    );
    await _section(tester, 'Extra section');
    controller.value = controller.value.copyWith(mode: ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Captured'))).brightness,
      Brightness.dark);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    controller.value = controller.value.copyWith(mode: ThemeMode.system);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Captured'))).brightness,
      Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Captured'))).brightness,
      Brightness.dark);
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    await _section(tester, 'Couleur d’accent');
    tester.widget<ColorPicker>(find.byType(ColorPicker))
        .onColorChanged(Colors.pink);
    await tester.pumpAndSettle();
    expect(tester.widget<ColorPicker>(find.byType(ColorPicker)).color,
      Colors.pink);
    expect(controller.value.accent, Colors.pink);
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Preview ${Colors.pink.toARGB32()}'), findsOneWidget);
    await tester.tap(find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    expect(codec.resets, 1);
    expect(controller.value.accent, Colors.orange);
    expect(tester.takeException(), isNull);
  });

  testWidgets('additional reset overrides codec reset exactly once',
      (tester) async {
    final controller = ValueNotifier<Appearance>(DefaultAppearance());
    addTearDown(controller.dispose);
    final codec = _Codec();
    var resets = 0;
    await _open(tester, controller, codec,
      resetAdditional: () => resets++,
      defaults: () => DefaultAppearance(accent: Colors.green));
    await tester.tap(find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(codec.resets, 0);
    expect(controller.value.accent, Colors.green);
  });

  testWidgets('injected slots use editor callbacks and selected variant reset',
      (tester) async {
    final controller = ValueNotifier<Appearance>(DefaultAppearance(styles: {
      'custom': const ContainerStyle(radius: 20),
    }));
    addTearDown(controller.dispose);
    final standard = AppearanceSlot(
      'Custom', name: 'custom',
      read: (a) => a.style('custom'),
      write: (a, s) => a.withStyle('custom', s),
      reset: (a) => a.withStyle('custom', null),
    );
    final selected = AppearanceSlot(
      'Custom selected', name: 'customSelected', standard: standard,
      read: (a) => a.variantStyle('customSelected', 'custom'),
      write: (a, s) => a.withStyle('customSelected', s),
      reset: (a) => a.withStyle('customSelected', null),
    );
    await _open(tester, controller, _Codec(), slots: [standard, selected]);
    await _section(tester, 'Custom selected');
    var editor = tester.widget<ContainerStyleEditor>(
      find.byType(ContainerStyleEditor));
    expect(editor.radius, 20);
    editor.onRadiusChanged!(32);
    editor = tester.widget<ContainerStyleEditor>(
      find.byType(ContainerStyleEditor));
    editor.onSolidColorChanged!(Colors.red);
    await tester.pumpAndSettle();
    expect(controller.value.style('customSelected').radius, 32);
    expect(controller.value.style('customSelected').color, Colors.red);
    tester.widget<ContainerStyleEditor>(
      find.byType(ContainerStyleEditor)).onReset!();
    await tester.pumpAndSettle();
    expect(controller.value.styles.containsKey('customSelected'), isFalse);
    expect(tester.widget<ContainerStyleEditor>(
      find.byType(ContainerStyleEditor)).radius, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background slot retains window controls and captured codec',
      (tester) async {
    final controller = ValueNotifier<Appearance>(DefaultAppearance());
    addTearDown(controller.dispose);
    final background = AppearanceSlot(
      'Background', name: 'background',
      role: AppearanceSurfaceRole.applicationBackground, editShape: false,
      read: (a) => a.backgroundStyle,
      write: (a, s) => a.withStyle('background', s),
      reset: (a) => a.withStyle('background', null),
    );
    await _open(tester, controller, _Codec(), slots: [background]);
    await _section(tester, 'Background');
    final editor = tester.widget<ContainerStyleEditor>(
      find.byType(ContainerStyleEditor));
    expect(editor.onRadiusChanged, isNull);
    expect(editor.extraSections.single.id, 'window');
    // Window content is a section of the shared editor, not app UI.
    final controls = editor.extraSections.single.child as Column;
    final slider = controls.children.whereType<Slider>().single;
    slider.onChanged!(.4);
    await tester.pumpAndSettle();
    expect(controller.value.backgroundOpacity, .4);
    expect(tester.takeException(), isNull);
  });
}
