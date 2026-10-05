import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/services/appearance_store.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/design_system.dart';
import 'package:super_container_layout/widgets/super_container.dart';

void main() {
  test('design system persists, defaults to Material and rejects unknowns', () {
    const style = ContainerStyle(designSystem: DesignSystem.neumorphism);
    final saved = ContainerStyle.fromJson(style.toJson());
    expect(saved.designSystem, DesignSystem.neumorphism);
    final old = style.toJson()..remove('designSystem');
    expect(ContainerStyle.fromJson(old).designSystem, DesignSystem.material);
    expect(
      () => ContainerStyle.fromJson(style.toJson()..['designSystem'] = 'x'),
      throwsFormatException,
    );
    final appearance = AppearanceStore.decode(
      AppearanceStore.encode(
        Appearance(
          styles: {'custom': DesignSystem.liquidGlass.apply(const ContainerStyle())},
        ),
      ),
    );
    expect(appearance.style('custom').designSystem, DesignSystem.liquidGlass);
  });

  test('presets keep spacing and set the matching look', () {
    const base = ContainerStyle(padding: 7, margin: 3, radius: 1);
    final glass = DesignSystem.liquidGlass.apply(base);
    expect(glass.padding, 7);
    expect(glass.margin, 3);
    expect(glass.fill.gradient(), isNotNull);
    expect(glass.foreground, isNull);
    final neumorphic = DesignSystem.neumorphism.apply(base);
    expect(neumorphic.elevation, greaterThan(0));
    expect(neumorphic.borderWidth, 0);
    expect(
      DesignSystem.material.apply(neumorphic).designSystem,
      DesignSystem.material,
    );
  });

  testWidgets('editor selector applies the design system and renders it', (
    tester,
  ) async {
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

    SuperContainerState state() =>
        tester.state<SuperContainerState>(find.byType(SuperContainer));
    final selector = find.byType(DropdownButtonFormField<DesignSystem>);
    expect(selector, findsOneWidget);

    Future<void> choose(DesignSystem system) async {
      await tester.ensureVisible(selector);
      await tester.pumpAndSettle();
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text(system.label).last);
      await tester.pumpAndSettle();
    }

    await choose(DesignSystem.liquidGlass);
    expect(state().style.designSystem, DesignSystem.liquidGlass);
    // Le conteneur et l'aperçu de l'éditeur.
    expect(find.byType(BackdropFilter), findsNWidgets(2));

    await choose(DesignSystem.neumorphism);
    expect(state().style.designSystem, DesignSystem.neumorphism);
    expect(find.byType(BackdropFilter), findsNothing);
    final shadows = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => (decoration.boxShadow?.length ?? 0) == 2);
    expect(shadows, isNotEmpty);

    await choose(DesignSystem.material);
    expect(state().style.designSystem, DesignSystem.material);
  });
}
