import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/services/repositories/json_list_scope.dart';
import 'package:super_container_layout/services/repositories/json_repository_scope.dart';
import 'package:super_container_layout/services/repositories/json_repository_store.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/theme/container_fill.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/style_extras.dart';
import 'package:super_container_layout/widgets/surfaces/styled_surface.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';
import 'package:super_container_layout/widgets/surfaces/surface_painters.dart';

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

    test('a single-side border does not bleed onto zero-width sides', () async {
      const size = Size(300, 80);
      Future<ByteData> rasterize(StyleBorderPainter painter) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        addTearDown(image.dispose);
        addTearDown(picture.dispose);
        return (await image.toByteData())!;
      }

      int alphaAt(ByteData bytes, int x, int y) =>
          bytes.getUint8((y * size.width.toInt() + x) * 4 + 3);

      for (final line in BorderLine.values) {
        for (final radius in [0.0, 12.0]) {
          final leftOnly = await rasterize(
            StyleBorderPainter(
              widths: const Quad(0, 0, 0, 5),
              color: const Color(0xFFFF0000),
              radii: BorderRadius.circular(radius),
              line: line,
            ),
          );
          // Le côté gauche comporte bien des pixels peints (même en tireté/pointillé).
          final leftPainted = [
            for (var y = 12; y < 68; y++) alphaAt(leftOnly, 2, y),
          ].any((alpha) => alpha > 0);
          expect(
            leftPainted,
            isTrue,
            reason: 'left side should paint ($line, r=$radius)',
          );
          // Les côtés haut, bas (hors coin arrondi) et droit restent strictement à 0.
          final startX = radius == 0 ? 6 : 14;
          for (var x = startX; x < 290; x += 8) {
            expect(
              alphaAt(leftOnly, x, 1),
              0,
              reason: 'top side bled at x=$x ($line, r=$radius)',
            );
            expect(
              alphaAt(leftOnly, x, 78),
              0,
              reason: 'bottom side bled at x=$x ($line, r=$radius)',
            );
          }
          expect(
            alphaAt(leftOnly, 298, 40),
            0,
            reason: 'right side bled ($line, r=$radius)',
          );
        }
      }
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
              child: EditableSurface(
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
              child: EditableSurface(
                child: SizedBox(width: 120, height: 60, child: Text('Box')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Box'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuItem<EditorSlotState>).first);
      await tester.pumpAndSettle();
    }

    ContainerStyle current(WidgetTester tester) =>
        tester.state<EditableSurfaceState>(find.byType(EditableSurface)).style;

    Future<void> toggle(WidgetTester tester, String key) async {
      final finder = find.byKey(ValueKey('$key-Card'));
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
      final corner = find.byWidgetPredicate(
        (widget) =>
            widget is Slider && widget.key == const ValueKey('radii-1-Card'),
      );
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
      final topPadding = find.byWidgetPredicate(
        (widget) =>
            widget is Slider &&
            widget.key == const ValueKey('padding-side-0-Card'),
      );
      await tester.ensureVisible(topPadding);
      tester.widget<Slider>(topPadding).onChanged!(18);
      await tester.pump();
      expect(current(tester).paddingInsets!.top, 18);
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
      final blur = find.byKey(const ValueKey('shadow-blur-Card'));
      await tester.ensureVisible(blur);
      tester.widget<Slider>(blur).onChanged!(30);
      await tester.pump();
      expect(current(tester).shadow!.blur, 30);

      await toggle(tester, 'inner-shadow-switch');
      expect(current(tester).hasInnerShadow, isTrue);

      await toggle(tester, 'transform-switch');
      final rotation = find.byKey(const ValueKey('transform-rotation-Card'));
      await tester.ensureVisible(rotation);
      tester.widget<Slider>(rotation).onChanged!(45);
      await tester.pump();
      expect(current(tester).transform!.rotation, 45);

      final opacity = find.byKey(const ValueKey('opacity-Card'));
      await tester.ensureVisible(opacity);
      tester.widget<Slider>(opacity).onChanged!(40);
      await tester.pump();
      expect(current(tester).opacity, closeTo(.4, 1e-9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('border type and pattern selectors apply', (tester) async {
      await open(tester);
      Future<void> choose(Finder segmented, String text) async {
        await tester.ensureVisible(segmented);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: segmented, matching: find.text(text)),
        );
        await tester.pumpAndSettle();
      }

      await choose(
        find.byKey(const ValueKey('border-line-Card')),
        BorderLine.dotted.label,
      );
      expect(current(tester).borderLine, BorderLine.dotted);
      await choose(
        find.byKey(const ValueKey('pattern-Card')),
        SurfacePattern.lines.label,
      );
      expect(current(tester).pattern, SurfacePattern.lines);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'background image URL, fit and opacity edit the style and render in StyledSurface',
      (tester) async {
        await open(tester);
        final urlField = find.byKey(const ValueKey('image-url-field-Card'));
        expect(urlField, findsOneWidget);
        expect(find.byKey(const ValueKey('image-opacity-Card')), findsNothing);

        await tester.enterText(urlField, 'https://example.com/bg.png');
        await tester.pumpAndSettle();
        expect(current(tester).fill.imageUrl, 'https://example.com/bg.png');
        expect(current(tester).fill.hasImage, isTrue);

        final fitDropdown = find.byKey(const ValueKey('image-fit-Card-cover'));
        expect(fitDropdown, findsOneWidget);
        await tester.ensureVisible(fitDropdown);
        await tester.tap(fitDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Contenir (Contain)').last);
        await tester.pumpAndSettle();
        expect(current(tester).fill.imageFit, BoxFit.contain);

        final imageOpacity = find.byWidgetPredicate(
          (widget) =>
              widget is Slider &&
              widget.key == const ValueKey('image-opacity-Card'),
        );
        await tester.ensureVisible(imageOpacity);
        tester.widget<Slider>(imageOpacity).onChanged!(.65);
        await tester.pump();
        expect(current(tester).fill.imageOpacity, closeTo(.65, 1e-9));

        // Verify the preview StyledSurface has the DecorationImage configured.
        final previewInk = tester.widget<Ink>(
          find.descendant(
            of: find.byKey(const ValueKey('preview-Card')),
            matching: find.byType(Ink),
          ),
        );
        final decoration = previewInk.decoration! as BoxDecoration;
        expect(decoration.image, isNotNull);
        expect(
          (decoration.image!.image as NetworkImage).url,
          'https://example.com/bg.png',
        );
        expect(decoration.image!.fit, BoxFit.contain);
        expect(decoration.image!.opacity, closeTo(.65, 1e-9));

        // Clear button removes the image URL and hides image sub-controls.
        final clearBtn = find.byKey(const ValueKey('image-url-clear-Card'));
        await tester.ensureVisible(clearBtn);
        await tester.tap(clearBtn);
        await tester.pumpAndSettle();
        expect(current(tester).fill.imageUrl, isEmpty);
        expect(current(tester).fill.hasImage, isFalse);
        expect(find.byKey(const ValueKey('image-opacity-Card')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'surfaces resolve and render webp, svg and base64 via imageUrl',
      (tester) async {
        // Minimal 1x1 lossy WebP in base64 ("RIFF....WEBPVP8 ...")
        const webpBase64 =
            'UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA';
        final webpBytes = base64Decode(webpBase64);

        const svgMarkup =
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20">'
            '<rect width="40" height="20" fill="#5268D9"/>'
            '</svg>';
        final svgBase64 = base64Encode(utf8.encode(svgMarkup));

        // 1) WebP network URL
        const webpUrlFill = ContainerFill(
          imageUrl: 'https://example.com/banner.webp',
        );
        final webpUrlDecoration = webpUrlFill.decorationImage();
        expect(webpUrlDecoration, isNotNull);
        expect(webpUrlDecoration!.image, isA<NetworkImage>());
        expect(
          (webpUrlDecoration.image as NetworkImage).url,
          'https://example.com/banner.webp',
        );

        // 2) SVG network URL
        const svgUrlFill = ContainerFill(
          imageUrl: 'https://example.com/vector.svg',
        );
        final svgUrlDecoration = svgUrlFill.decorationImage();
        expect(svgUrlDecoration, isNotNull);
        expect(svgUrlDecoration!.image, isA<NetworkImage>());
        expect(
          (svgUrlDecoration.image as NetworkImage).url,
          'https://example.com/vector.svg',
        );

        // 3) WebP data URI and raw base64
        const webpDataUriFill = ContainerFill(
          imageUrl: 'data:image/webp;base64,$webpBase64',
        );
        final webpDataDecoration = webpDataUriFill.decorationImage();
        expect(webpDataDecoration, isNotNull);
        expect(webpDataDecoration!.image, isA<MemoryImage>());
        expect((webpDataDecoration.image as MemoryImage).bytes, webpBytes);

        const webpRawBase64Fill = ContainerFill(imageUrl: webpBase64);
        final webpRawDecoration = webpRawBase64Fill.decorationImage();
        expect(webpRawDecoration, isNotNull);
        expect(webpRawDecoration!.image, isA<MemoryImage>());
        expect((webpRawDecoration.image as MemoryImage).bytes, webpBytes);

        // 4) SVG data URI (base64 & utf8), raw base64 and inline SVG
        final svgDataBase64Fill = ContainerFill(
          imageUrl: 'data:image/svg+xml;base64,$svgBase64',
        );
        expect(
          svgDataBase64Fill.decorationImage()!.image,
          isA<SvgMemoryImage>(),
        );

        const svgDataUtf8Fill = ContainerFill(
          imageUrl: 'data:image/svg+xml;utf8,$svgMarkup',
        );
        expect(svgDataUtf8Fill.decorationImage()!.image, isA<SvgMemoryImage>());

        final svgRawBase64Fill = ContainerFill(imageUrl: svgBase64);
        expect(
          svgRawBase64Fill.decorationImage()!.image,
          isA<SvgMemoryImage>(),
        );

        const svgInlineFill = ContainerFill(imageUrl: svgMarkup);
        expect(svgInlineFill.decorationImage()!.image, isA<SvgMemoryImage>());

        // Verify SVG memory image decodes into a real ui.Image with 2:1 aspect ratio
        final svgCompleter = Completer<ImageInfo>();
        final stream = svgDataBase64Fill.decorationImage()!.image.resolve(
          ImageConfiguration.empty,
        );
        final listener = ImageStreamListener(
          (info, _) {
            if (!svgCompleter.isCompleted) svgCompleter.complete(info);
          },
          onError: (error, stackTrace) {
            if (!svgCompleter.isCompleted) {
              svgCompleter.completeError(error, stackTrace);
            }
          },
        );
        stream.addListener(listener);
        addTearDown(() => stream.removeListener(listener));
        final svgImageInfo = await svgCompleter.future;
        expect(svgImageInfo.image.width, greaterThan(0));
        expect(svgImageInfo.image.height, greaterThan(0));
        expect(
          svgImageInfo.image.width / svgImageInfo.image.height,
          closeTo(2.0, 0.05),
        );

        // Verify SVG network image decodes into a real ui.Image via mocked HttpClient
        debugNetworkImageHttpClientProvider = () =>
            _FakeSvgHttpClient(Uint8List.fromList(utf8.encode(svgMarkup)));
        try {
          final netSvgCompleter = Completer<ImageInfo>();
          final netStream = svgUrlFill.decorationImage()!.image.resolve(
            ImageConfiguration.empty,
          );
          final netListener = ImageStreamListener(
            (info, _) {
              if (!netSvgCompleter.isCompleted) netSvgCompleter.complete(info);
            },
            onError: (error, stackTrace) {
              if (!netSvgCompleter.isCompleted) {
                netSvgCompleter.completeError(error, stackTrace);
              }
            },
          );
          netStream.addListener(netListener);
          addTearDown(() => netStream.removeListener(netListener));
          final netSvgInfo = await netSvgCompleter.future;
          expect(
            netSvgInfo.image.width / netSvgInfo.image.height,
            closeTo(2.0, 0.05),
          );

          // Verify SVG with CSS Color 4 display-p3 style fallback preserves its fill color (#211B42)
          const p3Svg =
              '<svg width="93" height="44" viewBox="0 0 93 44" fill="none" xmlns="http://www.w3.org/2000/svg">'
              '<rect width="93" height="44" fill="#211B42" '
              'style="fill:#211B42;fill:color(display-p3 0.1294 0.1059 0.2588);fill-opacity:1;"/>'
              '</svg>';
          const p3Fill = ContainerFill(imageUrl: p3Svg);
          final p3Completer = Completer<ImageInfo>();
          final p3Stream = p3Fill.decorationImage()!.image.resolve(
            ImageConfiguration.empty,
          );
          final p3Listener = ImageStreamListener((info, _) {
            if (!p3Completer.isCompleted) p3Completer.complete(info);
          });
          p3Stream.addListener(p3Listener);
          addTearDown(() => p3Stream.removeListener(p3Listener));
          final p3Info = await p3Completer.future;
          final rgba = await tester.runAsync(
            () => p3Info.image.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          expect(rgba, isNotNull);
          // First pixel in RGBA should be #211B42 (R=0x21, G=0x1B, B=0x42, A=0xFF)
          expect(rgba!.getUint8(0), 0x21);
          expect(rgba.getUint8(1), 0x1B);
          expect(rgba.getUint8(2), 0x42);
          expect(rgba.getUint8(3), 0xFF);

          // Render StyledSurface with SVG data URI, WebP base64 and SVG network URL
          for (final fill in [
            svgDataBase64Fill,
            svgDataUtf8Fill,
            svgRawBase64Fill,
            webpDataUriFill,
            webpRawBase64Fill,
            svgUrlFill,
          ]) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: StyledSurface(
                    style: ContainerStyle(fill: fill),
                    fallbackColor: Colors.white,
                    borderColor: Colors.black12,
                    child: const SizedBox(width: 120, height: 60),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        } finally {
          debugNetworkImageHttpClientProvider = null;
        }
      },
    );

    testWidgets(
      'surface propertyBindings.imageUrl round-trips, resolves from repository and can be bound in editor',
      (tester) async {
        const repoId = '0123456789abcdef0123456789abcdef';
        const styleWithBinding = ContainerStyle(
          fill: ContainerFill(imageFit: BoxFit.contain, imageOpacity: .8),
          propertyBindings: {
            ContainerStyleProperty.imageUrl: JsonTextBinding(
              repositoryId: repoId,
              path: 'clients[?].avatar',
            ),
          },
        );
        expect(styleWithBinding.hasImage, isTrue);
        final json = styleWithBinding.toJson();
        expect(ContainerStyle.fromJson(json).toJson(), json);
        expect(
          ContainerStyle.fromJson(json).propertyBindings,
          styleWithBinding.propertyBindings,
        );
        final compact = styleWithBinding.toCompactJson();
        expect(ContainerStyle.fromJson(compact).toJson(), json);
        expect(
          ContainerStyle.fromJson(compact).propertyBindings,
          styleWithBinding.propertyBindings,
        );
        final cleared = styleWithBinding.patchFromJson({
          'propertyBindings': {'imageUrl': null},
        });
        expect(cleared.propertyBindings, isEmpty);
        expect(cleared.hasImage, isFalse);

        // State overrides track and apply propertyBindings.imageUrl under background
        final override = SelectedSurfaceStyle().edited(styleWithBinding);
        expect(override.properties, contains(SurfaceStyleProperty.background));
        final applied = override.apply(const ContainerStyle());
        expect(
          applied.propertyBindings[ContainerStyleProperty.imageUrl],
          const JsonTextBinding(
            repositoryId: repoId,
            path: 'clients[?].avatar',
          ),
        );

        final dir = await tester.runAsync(
          () => Directory.systemTemp.createTemp('surface-image-bind-'),
        );
        addTearDown(() => tester.runAsync(() => dir!.delete(recursive: true)));
        final store = JsonRepositoryStore(dir!);
        addTearDown(store.dispose);
        final actualRepoId = await tester.runAsync(() async {
          await store.create('Clients');
          final old = await store.read('Clients');
          await store.save(
            'Clients',
            '{"clients":[{"avatar":"https://example.com/a.png"},{"avatar":""}]}\n',
            expectedText: old,
          );
          return store.idOf('Clients');
        });

        Future<void> real(Future<void> Function() action) async {
          await tester.runAsync(() async {
            await action();
            for (var i = 0; i < 4; i++) {
              await tester.pump();
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          });
          await tester.pumpAndSettle();
        }

        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        // Runtime resolution inside a JsonListScope row with fallback imageUrl
        final rowIndex = ValueNotifier<int>(0);
        addTearDown(rowIndex.dispose);
        await real(
          () => tester.pumpWidget(
            MaterialApp(
              home: JsonRepositoryScope(
                store: store,
                child: Scaffold(
                  body: Center(
                    child: ValueListenableBuilder<int>(
                      valueListenable: rowIndex,
                      builder: (context, index, _) => JsonListScope(
                        repositoryId: actualRepoId!,
                        indices: [index],
                        child: const EditableSurface(
                          style: ContainerStyle(
                            fill: ContainerFill(
                              imageUrl: 'https://example.com/fallback.png',
                            ),
                            propertyBindings: {
                              ContainerStyleProperty.imageUrl: JsonTextBinding(
                                path: 'clients[?].avatar',
                              ),
                            },
                          ),
                          child: SizedBox(
                            width: 120,
                            height: 60,
                            child: Text('Row'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        Ink findSurfaceInk() => tester.widget<Ink>(
          find
              .descendant(
                of: find.byType(StyledSurface),
                matching: find.byType(Ink),
              )
              .first,
        );
        expect(
          ((findSurfaceInk().decoration! as BoxDecoration).image!.image
                  as NetworkImage)
              .url,
          'https://example.com/a.png',
        );

        // Switching to row 1 (empty avatar) falls back to imageUrl
        await real(() async => rowIndex.value = 1);
        expect(
          ((findSurfaceInk().decoration! as BoxDecoration).image!.image
                  as NetworkImage)
              .url,
          'https://example.com/fallback.png',
        );

        // Configure binding through the style editor dialog
        await tester.tap(find.text('Row'), buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PopupMenuItem<EditorSlotState>).first);
        await tester.pumpAndSettle();

        final bindBtn = find.byKey(const ValueKey('image-url-bind-Card'));
        await tester.ensureVisible(bindBtn);
        await tester.pumpAndSettle();
        await tester.tap(bindBtn);
        await real(() async {});

        final pathField = find.byKey(
          const ValueKey('image-url-binding-Card-repository-path'),
        );
        expect(pathField, findsOneWidget);
        await tester.enterText(pathField, 'clients[0].avatar');
        await tester.tap(
          find.byKey(const ValueKey('image-url-binding-Card-apply')),
        );
        await tester.pumpAndSettle();

        expect(
          current(tester).propertyBindings[ContainerStyleProperty.imageUrl],
          const JsonTextBinding(path: 'clients[0].avatar'),
        );
        expect(find.text('Lié à : clients[0].avatar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _FakeSvgHttpClient implements HttpClient {
  _FakeSvgHttpClient(this.bytes);

  final Uint8List bytes;

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeSvgHttpClientRequest(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSvgHttpClientRequest implements HttpClientRequest {
  _FakeSvgHttpClientRequest(this.bytes);

  final Uint8List bytes;

  @override
  final HttpHeaders headers = _FakeSvgHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeSvgHttpClientResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSvgHttpHeaders implements HttpHeaders {
  @override
  ContentType? get contentType => ContentType('image', 'svg+xml');

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSvgHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeSvgHttpClientResponse(this.bytes);

  final Uint8List bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _FakeSvgHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
