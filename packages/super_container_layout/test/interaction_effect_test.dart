import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/design_system.dart';
import 'package:super_container_layout/theme/interaction_effect.dart';
import 'package:super_container_layout/widgets/interaction_effect_box.dart';
import 'package:super_container_layout/widgets/styled_surface.dart';
import 'package:super_container_layout/widgets/super_container.dart';

void main() {
  test('interaction effect persists, defaults to ripple, rejects unknowns', () {
    const style = ContainerStyle(interactionEffect: InteractionEffect.pressed);
    expect(
      ContainerStyle.fromJson(style.toJson()).interactionEffect,
      InteractionEffect.pressed,
    );
    final old = style.toJson()..remove('interactionEffect');
    expect(
      ContainerStyle.fromJson(old).interactionEffect,
      InteractionEffect.ripple,
    );
    expect(
      () =>
          ContainerStyle.fromJson(style.toJson()..['interactionEffect'] = 'x'),
      throwsFormatException,
    );
    expect(
      DesignSystem.neumorphism.apply(style).interactionEffect,
      InteractionEffect.pressed,
    );
  });

  Future<TestGesture> pumpSurface(
    WidgetTester tester,
    InteractionEffect effect, {
    bool hover = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StyledSurface(
              style: ContainerStyle(
                radius: 8,
                elevation: 2,
                interactionEffect: effect,
                hoverEffect: hover,
              ),
              fallbackColor: Colors.white,
              borderColor: Colors.grey,
              child: const SizedBox(width: 120, height: 60),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    addTearDown(mouse.removePointer);
    return mouse;
  }

  double elevation(WidgetTester tester) => tester
      .widget<Material>(
        find
            .descendant(
              of: find.byType(StyledSurface),
              matching: find.byType(Material),
            )
            .first,
      )
      .elevation;

  double overlayAlpha(WidgetTester tester) {
    final boxes = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(StyledSurface),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>();
    return boxes.first.color!.a;
  }

  testWidgets('hover effect shows a veil only while hovered', (tester) async {
    final mouse = await pumpSurface(
      tester,
      InteractionEffect.ripple,
      hover: true,
    );
    expect(overlayAlpha(tester), 0);
    await mouse.moveTo(tester.getCenter(find.byType(StyledSurface)));
    await tester.pumpAndSettle();
    expect(overlayAlpha(tester), greaterThan(0));
    // Le survol s'efface pendant le clic et revient au relâchement.
    await mouse.down(tester.getCenter(find.byType(StyledSurface)));
    await tester.pumpAndSettle();
    expect(overlayAlpha(tester), 0);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(overlayAlpha(tester), greaterThan(0));
    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(overlayAlpha(tester), 0);
  });

  testWidgets('hover is independent: it combines with the pressed effect', (
    tester,
  ) async {
    final mouse = await pumpSurface(
      tester,
      InteractionEffect.pressed,
      hover: true,
    );
    expect(overlayAlpha(tester), 0);
    await mouse.moveTo(tester.getCenter(find.byType(StyledSurface)));
    await tester.pumpAndSettle();
    expect(overlayAlpha(tester), InteractionEffect.hoverOverlay);
    await mouse.down(tester.getCenter(find.byType(StyledSurface)));
    await tester.pumpAndSettle();
    expect(overlayAlpha(tester), InteractionEffect.pressedOverlay);
    await mouse.up();
  });

  test('legacy hover effect becomes the independent hover option', () {
    final style = ContainerStyle.fromJson(
      const ContainerStyle().toJson()..['interactionEffect'] = 'hover',
    );
    expect(style.hoverEffect, isTrue);
    expect(style.interactionEffect, InteractionEffect.ripple);
    expect(
      ContainerStyle.fromJson(const ContainerStyle(hoverEffect: true).toJson())
          .hoverEffect,
      isTrue,
    );
  });

  testWidgets('pressed effect veils and shrinks while the button is down', (
    tester,
  ) async {
    final mouse = await pumpSurface(tester, InteractionEffect.pressed);
    await mouse.moveTo(tester.getCenter(find.byType(StyledSurface)));
    await mouse.down(tester.getCenter(find.byType(StyledSurface)));
    await tester.pumpAndSettle();
    expect(overlayAlpha(tester), greaterThan(.1));
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      InteractionEffect.pressedScale,
    );
    await mouse.up();
    await tester.pumpAndSettle();
    expect(overlayAlpha(tester), 0);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('elevation effect lifts on hover and sinks on press', (
    tester,
  ) async {
    double inset() =>
        (tester
                    .widget<CustomPaint>(
                      find.byWidgetPredicate(
                        (w) =>
                            w is CustomPaint && w.painter is InsetShadowPainter,
                      ),
                    )
                    .painter!
                as InsetShadowPainter)
            .intensity;
    final mouse = await pumpSurface(tester, InteractionEffect.elevation);
    expect(elevation(tester), 2);
    expect(inset(), 0);
    await mouse.moveTo(tester.getCenter(find.byType(StyledSurface)));
    await tester.pumpAndSettle();
    expect(elevation(tester), 2 + InteractionEffect.hoverLift);
    await mouse.down(tester.getCenter(find.byType(StyledSurface)));
    await tester.pumpAndSettle();
    expect(elevation(tester), 0);
    expect(inset(), 1);
    expect(
      tester
          .widget<Transform>(
            find
                .ancestor(
                  of: find.byType(Stack),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .getTranslation()
          .x,
      InteractionEffect.sinkOffset.dx,
    );
    await mouse.up();
    await tester.pumpAndSettle();
    expect(elevation(tester), 2 + InteractionEffect.hoverLift);
    expect(inset(), 0);
  });

  testWidgets('ripple keeps the default ink; other effects turn it off', (
    tester,
  ) async {
    Future<InteractiveInkFeatureFactory> splash(InteractionEffect e) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StyledSurface(
              style: ContainerStyle(interactionEffect: e),
              fallbackColor: Colors.white,
              borderColor: Colors.grey,
              child: Builder(
                builder: (context) => SizedBox(
                  key: const ValueKey('probe'),
                  child: Text('${Theme.of(context).splashFactory.hashCode}'),
                ),
              ),
            ),
          ),
        ),
      );
      return Theme.of(tester.element(find.byKey(const ValueKey('probe'))))
          .splashFactory;
    }

    expect(
      await splash(InteractionEffect.ripple),
      isNot(NoSplash.splashFactory),
    );
    expect(await splash(InteractionEffect.elevation), NoSplash.splashFactory);
  });

  testWidgets('editor selector changes the interaction effect', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SuperContainer(
              child: SizedBox(width: 120, height: 60, child: Text('Box')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Box'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuItem<SuperContainerState>).first);
    await tester.pumpAndSettle();
    final selector = find.byType(DropdownButtonFormField<InteractionEffect>);
    expect(selector, findsOneWidget);
    final checkbox = find.byType(CheckboxListTile);
    expect(checkbox, findsOneWidget);
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(
      tester
          .state<SuperContainerState>(find.byType(SuperContainer))
          .style
          .hoverEffect,
      isTrue,
    );
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text(InteractionEffect.elevation.label).last);
    await tester.pumpAndSettle();
    expect(
      tester
          .state<SuperContainerState>(find.byType(SuperContainer))
          .style
          .interactionEffect,
      InteractionEffect.elevation,
    );
    // Le choix de l'effet au clic laisse l'effet au survol intact.
    expect(
      tester
          .state<SuperContainerState>(find.byType(SuperContainer))
          .style
          .hoverEffect,
      isTrue,
    );
  });

  test('hover tint persists and resolves the veil color', () {
    const accent = Color(0xFF123456);
    const style = ContainerStyle(
      hoverEffect: true,
      hoverTint: HoverTint.custom,
      hoverColor: Color(0xFFAA5500),
    );
    final saved = ContainerStyle.fromJson(style.toJson());
    expect(saved.hoverTint, HoverTint.custom);
    expect(saved.hoverBase(accent), const Color(0xFFAA5500));
    expect(const ContainerStyle().hoverBase(accent), isNull);
    expect(
      const ContainerStyle(hoverTint: HoverTint.accent).hoverBase(accent),
      accent,
    );
    expect(
      ContainerStyle.fromJson(
        const ContainerStyle().toJson()..remove('hoverTint'),
      ).hoverTint,
      HoverTint.material,
    );
    expect(
      () => ContainerStyle.fromJson(style.toJson()..['hoverTint'] = 'x'),
      throwsFormatException,
    );
  });

  testWidgets('hover veil takes the accent tint', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: StyledSurface(
              style: ContainerStyle(
                hoverEffect: true,
                hoverTint: HoverTint.custom,
                hoverColor: Color(0xFFFF0000),
              ),
              fallbackColor: Colors.white,
              borderColor: Colors.grey,
              child: SizedBox(width: 120, height: 60),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byType(StyledSurface)),
    );
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
    final veil = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(StyledSurface),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .first
        .color!;
    expect(veil.r, 1);
    expect(veil.g, 0);
    expect(veil.a, closeTo(InteractionEffect.hoverTintedOverlay, .005));
  });

  testWidgets('ownsHover removes the native hover when the option is off', (
    tester,
  ) async {
    Future<Color> hoverColorSeen({required bool owns}) async {
      late Color seen;
      await tester.pumpWidget(
        MaterialApp(
          home: InteractionEffectBox(
            effect: InteractionEffect.ripple,
            ownsHover: owns,
            radius: 0,
            builder: (context, _) => Builder(
              builder: (context) {
                seen = Theme.of(context).hoverColor;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return seen;
    }

    expect((await hoverColorSeen(owns: false)).a, greaterThan(0));
    expect((await hoverColorSeen(owns: true)).a, 0);
  });
}
