import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/style_extras.dart';
import 'package:super_container_layout/widgets/styled_surface.dart';
import 'package:super_container_layout/widgets/super_container.dart';
import 'package:super_container_layout/widgets/surface_painters.dart';

void main() {
  group('model', () {
    test('default style serializes without the extended keys', () {
      final json = const ContainerStyle().toJson();
      for (final key in [
        'radii',
        'borderWidths',
        'borderLine',
        'shadow',
        'innerShadow',
        'opacity',
        'paddingInsets',
        'marginInsets',
        'backdropBlur',
        'pattern',
        'patternOpacity',
        'transform',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect(ContainerStyle.fromJson(json).toJson(), json);
    });

    test('every extended setting round-trips through JSON', () {
      const style = ContainerStyle(
        radius: 8,
        radii: Quad(4, 8, 12, 16),
        borderWidth: 1,
        borderWidths: Quad(1, 2, 3, 4),
        borderLine: BorderLine.dashed,
        shadow: ShadowSpec(
          color: Color(0xFF112233),
          opacity: .4,
          blur: 20,
          spread: -4,
          dx: 3,
          dy: -5,
        ),
        innerShadow: ShadowSpec(enabled: false, blur: 6),
        opacity: .7,
        paddingInsets: Quad(1, 2, 3, 4),
        marginInsets: Quad(5, 6, 7, 8),
        backdropBlur: 12,
        pattern: SurfacePattern.dots,
        patternOpacity: .3,
        transform: TransformSpec(dx: 4, dy: -6, rotation: 15, scale: 1.2),
      );
      final copy = ContainerStyle.fromJson(style.toJson());
      expect(copy.toJson(), style.toJson());
      expect(copy.radii, style.radii);
      expect(copy.shadow, style.shadow);
      expect(copy.innerShadow, style.innerShadow);
      expect(copy.transform, style.transform);
      expect(copy.borderLine, BorderLine.dashed);
      expect(copy.pattern, SurfacePattern.dots);
      expect(copy.backdropBlur, 12);
    });

    test('invalid extended values are rejected', () {
      final base = const ContainerStyle().toJson();
      for (final bad in <Map<String, Object?>>[
        {
          'radii': [1, 2, 3],
        },
        {
          'radii': [1, 2, 3, 99],
        },
        {
          'borderWidths': [1, 2, 3, -1],
        },
        {'borderLine': 'wavy'},
        {'pattern': 'stripes'},
        {'opacity': 2},
        {'backdropBlur': 400},
        {
          'shadow': {'blur': -1},
        },
        {
          'transform': {'scale': 9},
        },
        {
          'paddingInsets': [1, 2, 3, 400],
        },
      ]) {
        expect(
          () => ContainerStyle.fromJson({...base, ...bad}),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('copyWith can clear the optional settings', () {
      final style = const ContainerStyle().copyWith(
        radii: const Quad.all(4),
        shadow: const ShadowSpec(),
        transform: const TransformSpec(dx: 1),
        backdropBlur: 5,
      );
      expect(style.radii, isNotNull);
      final cleared = style.copyWith(
        radii: null,
        shadow: null,
        transform: null,
        backdropBlur: null,
      );
      expect(cleared.radii, isNull);
      expect(cleared.shadow, isNull);
      expect(cleared.transform, isNull);
      expect(cleared.backdropBlur, isNull);
      expect(style.copyWith(radius: 3).radii, style.radii);
    });

    test('derived geometry follows the independent values', () {
      const style = ContainerStyle(
        radius: 6,
        radii: Quad(1, 2, 3, 4),
        paddingInsets: Quad(1, 2, 3, 4),
        borderWidths: Quad(1, 1, 1, 2),
      );
      expect(style.borderRadius.topRight, const Radius.circular(2));
      expect(style.borderRadius.bottomLeft, const Radius.circular(4));
      expect(style.maxRadius, 4);
      expect(style.contentPadding, const EdgeInsets.fromLTRB(4, 1, 2, 3));
      expect(style.outerMargin, EdgeInsets.zero);
      expect(style.plainBorder, isFalse);
      expect(const ContainerStyle(borderWidth: 2).plainBorder, isTrue);
    });
  });

  group('rendering', () {
    Future<void> pump(WidgetTester tester, ContainerStyle style) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 100,
                  child: StyledSurface(
                    style: style,
                    fallbackColor: Colors.white,
                    borderColor: Colors.black,
                    child: const Text('x'),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('a plain style keeps the simple structure', (tester) async {
      await pump(tester, const ContainerStyle(borderWidth: 2, radius: 8));
      expect(find.byType(StyleBorderPainter), findsNothing);
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('independent corners shape the surface', (tester) async {
      await pump(
        tester,
        const ContainerStyle(radii: Quad(0, 10, 20, 30), borderWidth: 1),
      );
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
        const BorderRadius.only(
          topLeft: Radius.zero,
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(20),
          bottomLeft: Radius.circular(30),
        ),
      );
    });

    testWidgets('per-side and dashed borders use the border painter', (
      tester,
    ) async {
      await pump(
        tester,
        const ContainerStyle(
          radius: 12,
          borderWidths: Quad(1, 2, 3, 4),
          borderLine: BorderLine.dashed,
        ),
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.foregroundPainter)
          .whereType<StyleBorderPainter>()
          .single;
      expect(painter.widths, const Quad(1, 2, 3, 4));
      expect(painter.line, BorderLine.dashed);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a detailed shadow replaces the elevation', (tester) async {
      await pump(
        tester,
        const ContainerStyle(
          elevation: 8,
          shadow: ShadowSpec(blur: 10, spread: 2, dx: 1, dy: 6),
        ),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(StyledSurface),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0);
      final shadows = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .expand((decoration) => decoration.boxShadow ?? <BoxShadow>[])
          .toList();
      expect(shadows, hasLength(1));
      expect(shadows.single.blurRadius, 10);
      expect(shadows.single.spreadRadius, 2);
      expect(shadows.single.offset, const Offset(1, 6));
    });

    testWidgets('a disabled detailed shadow draws nothing', (tester) async {
      await pump(
        tester,
        const ContainerStyle(elevation: 8, shadow: ShadowSpec(enabled: false)),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(StyledSurface),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0);
      expect(
        tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .expand((decoration) => decoration.boxShadow ?? <BoxShadow>[]),
        isEmpty,
      );
    });

    testWidgets('opacity, blur, transform, pattern and inner shadow apply', (
      tester,
    ) async {
      await pump(
        tester,
        const ContainerStyle(
          opacity: .5,
          backdropBlur: 8,
          transform: TransformSpec(rotation: 10, scale: 1.1),
          pattern: SurfacePattern.grain,
          innerShadow: ShadowSpec(blur: 6, dx: 2, dy: 2),
        ),
      );
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, .5);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(
        tester
            .widgetList<Transform>(find.byType(Transform))
            .any((t) => !t.transform.isIdentity()),
        isTrue,
      );
      final overlay = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<SurfaceOverlayPainter>()
          .single;
      expect(overlay.pattern, SurfacePattern.grain);
      expect(overlay.innerShadow, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every pattern and line type paints without errors', (
      tester,
    ) async {
      for (final line in BorderLine.values) {
        for (final pattern in SurfacePattern.values) {
          await pump(
            tester,
            ContainerStyle(
              radii: const Quad(0, 8, 0, 8),
              borderWidths: const Quad(1, 0, 3, 2),
              borderLine: line,
              pattern: pattern,
              innerShadow: const ShadowSpec(),
            ),
          );
          await tester.pump();
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the container applies per-side padding and margin', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SuperContainer(
                style: ContainerStyle(
                  paddingInsets: Quad(4, 8, 12, 16),
                  marginInsets: Quad(1, 2, 3, 4),
                ),
                child: SizedBox(width: 50, height: 20, key: ValueKey('c')),
              ),
            ),
          ),
        ),
      );
      final surface = tester.getRect(find.byType(StyledSurface));
      final child = tester.getRect(find.byKey(const ValueKey('c')));
      expect(surface.topLeft, const Offset(4, 1));
      expect(child.topLeft - surface.topLeft, const Offset(16, 4));
      expect(surface.width, 16 + 50 + 8);
      expect(surface.height, 4 + 20 + 12);
    });
  });

  test('application defines whether a slot offers the extended look', () {
    final slot = AppearanceSlot(
      'Simple surface',
      name: 'simple',
      extendedLook: false,
      read: (a) => a.backgroundStyle,
      write: (a, style) => a.copyWith(backgroundStyle: style),
      reset: (a) => a.copyWith(backgroundStyle: const ContainerStyle()),
    );
    expect(slot.extendedLook, isFalse);
  });

  group('editor', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
    }

    ContainerStyle current(WidgetTester tester) =>
        tester.state<SuperContainerState>(find.byType(SuperContainer)).style;

    Future<void> toggle(WidgetTester tester, String key) async {
      final finder = find.byKey(ValueKey('$key-Super container'));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('lists the new groups', (tester) async {
      await open(tester);
      for (final id in [
        'inner',
        'opacity',
        'pattern',
        'transform',
        'shadow',
        'border',
        'radius',
      ]) {
        expect(
          find.byKey(ValueKey('style-card-$id')),
          findsOneWidget,
          reason: id,
        );
      }
    });

    testWidgets('independent corners and sides can be switched on and off', (
      tester,
    ) async {
      await open(tester);
      await toggle(tester, 'radii-switch');
      expect(current(tester).radii, isNotNull);
      final corner = find.byKey(const ValueKey('radii-1-Super container'));
      await tester.ensureVisible(corner);
      tester.widget<Slider>(corner).onChanged!(20);
      await tester.pump();
      expect(current(tester).radii!.right, 20);
      expect(current(tester).borderRadius.topRight, const Radius.circular(20));
      await toggle(tester, 'radii-switch');
      expect(current(tester).radii, isNull);

      await toggle(tester, 'border-sides-switch');
      expect(current(tester).borderWidths, isNotNull);
      await toggle(tester, 'padding-sides-switch');
      expect(current(tester).paddingInsets, isNotNull);
      await toggle(tester, 'margin-sides-switch');
      expect(current(tester).marginInsets, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detailed, inner shadow and transform edit the style', (
      tester,
    ) async {
      await open(tester);
      await toggle(tester, 'shadow-detail-switch');
      expect(current(tester).shadow, isNotNull);
      final blur = find.byKey(const ValueKey('shadow-blur-Super container'));
      await tester.ensureVisible(blur);
      tester.widget<Slider>(blur).onChanged!(30);
      await tester.pump();
      expect(current(tester).shadow!.blur, 30);

      await toggle(tester, 'inner-shadow-switch');
      expect(current(tester).hasInnerShadow, isTrue);

      await toggle(tester, 'transform-switch');
      final rotation = find.byKey(
        const ValueKey('transform-rotation-Super container'),
      );
      await tester.ensureVisible(rotation);
      tester.widget<Slider>(rotation).onChanged!(45);
      await tester.pump();
      expect(current(tester).transform!.rotation, 45);

      final opacity = find.byKey(const ValueKey('opacity-Super container'));
      await tester.ensureVisible(opacity);
      tester.widget<Slider>(opacity).onChanged!(40);
      await tester.pump();
      expect(current(tester).opacity, closeTo(.4, 1e-9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('border type and pattern selectors apply', (tester) async {
      await open(tester);
      Future<void> choose(Finder dropdown, String text) async {
        await tester.ensureVisible(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(text).last);
        await tester.pumpAndSettle();
      }

      await choose(
        find.byKey(const ValueKey('border-line-Super container')),
        BorderLine.dotted.label,
      );
      expect(current(tester).borderLine, BorderLine.dotted);
      await choose(
        find.byKey(const ValueKey('pattern-Super container')),
        SurfacePattern.lines.label,
      );
      expect(current(tester).pattern, SurfacePattern.lines);
      expect(tester.takeException(), isNull);
    });
  });
}
