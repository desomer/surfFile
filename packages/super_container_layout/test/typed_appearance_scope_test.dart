import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

class _PreparingCodec extends DefaultAppearanceCodec {
  const _PreparingCodec();

  @override
  DefaultAppearance prepare(Appearance appearance) => DefaultAppearance(
    mode: appearance.mode,
    styles: appearance.styles,
    spacing: 32,
  );
}

class _ObservedController extends ValueNotifier<DefaultAppearance> {
  _ObservedController(super.value);
  bool get isObserved => hasListeners;
}

class _CountingCodec extends _PreparingCodec {
  int preparations = 0;

  @override
  DefaultAppearance prepare(Appearance appearance) {
    preparations++;
    return super.prepare(appearance);
  }
}

void main() {
  testWidgets(
    'wider typed views prepare once and codec replacement is applied',
    (tester) async {
      final controller = ValueNotifier(DefaultAppearance());
      addTearDown(controller.dispose);
      final codec = _CountingCodec();
      late BuildContext childContext;
      final child = Builder(
        builder: (context) {
          childContext = context;
          return const SizedBox();
        },
      );
      Widget scope(AppearanceCodec codec) =>
          TypedAppearanceScope<DefaultAppearance>(
            controller: controller,
            codec: codec,
            child: child,
          );
      await tester.pumpWidget(scope(codec));
      final view = TypedAppearanceScope.controllerOf<Appearance>(childContext)!;
      view.value = Appearance(mode: ThemeMode.dark);
      expect(controller.value.mode, ThemeMode.dark);
      expect(codec.preparations, 1);
      view.dispose();

      await tester.pumpWidget(scope(const AppearanceCodec()));
      final original = controller.value;
      expect(
        () => AppearanceScope.controllerOf(childContext)!.value = Appearance(),
        throwsStateError,
      );
      expect(controller.value, same(original));
      expect(codec.preparations, 1);
    },
  );

  testWidgets('typed and shell consumers share updates and captured codec', (
    tester,
  ) async {
    final controller = _ObservedController(DefaultAppearance());
    addTearDown(controller.dispose);
    const codec = _PreparingCodec();
    late BuildContext childContext;
    final seen = <ThemeMode>[];
    final child = Builder(
      builder: (context) {
        childContext = context;
        expect(
          TypedAppearanceScope.controllerOf<DefaultAppearance>(context),
          same(controller),
        );
        expect(AppearanceServicesScope.codecOf(context), same(codec));
        final value = TypedAppearanceScope.of<DefaultAppearance>(context);
        seen.add(value.mode);
        return const SizedBox();
      },
    );
    await tester.pumpWidget(
      TypedAppearanceScope<DefaultAppearance>(
        controller: controller,
        codec: codec,
        child: child,
      ),
    );
    controller.value = controller.value.copyWith(mode: ThemeMode.dark);
    await tester.pump();
    expect(seen, [ThemeMode.light, ThemeMode.dark]);
    AppearanceScope.controllerOf(childContext)!.value = Appearance(
      mode: ThemeMode.light,
    );
    await tester.pump();
    expect(controller.value.spacing, 32);
    expect(controller.value.mode, ThemeMode.light);
    await tester.pumpWidget(const SizedBox());
    expect(controller.isObserved, isFalse);
    controller.value = DefaultAppearance();
  });

  testWidgets('rebinding detaches the old controller without disposing it', (
    tester,
  ) async {
    final first = _ObservedController(DefaultAppearance());
    final second = ValueNotifier(DefaultAppearance(mode: ThemeMode.dark));
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final seen = <ThemeMode>[];
    final child = Builder(
      builder: (context) {
        seen.add(TypedAppearanceScope.of<DefaultAppearance>(context).mode);
        return const SizedBox();
      },
    );
    Widget scope(ValueNotifier<DefaultAppearance> controller) =>
        TypedAppearanceScope<DefaultAppearance>(
          controller: controller,
          codec: const DefaultAppearanceCodec(),
          child: child,
        );
    await tester.pumpWidget(scope(first));
    await tester.pumpWidget(scope(second));
    expect(first.isObserved, isFalse);
    expect(seen, [ThemeMode.light, ThemeMode.dark]);
    first.value = first.value.copyWith(mode: ThemeMode.system);
    second.value = second.value.copyWith(mode: ThemeMode.light);
    await tester.pump();
    expect(seen.last, ThemeMode.light);
  });

  testWidgets(
    'typed view of a shell controller forwards listeners and writes',
    (tester) async {
      final controller = ValueNotifier<Appearance>(DefaultAppearance());
      addTearDown(controller.dispose);
      late ValueNotifier<DefaultAppearance> typed;
      var calls = 0;
      void listener() => calls++;
      await tester.pumpWidget(
        AppearanceServicesScope(
          codec: const DefaultAppearanceCodec(),
          child: AppearanceScope(
            controller: controller,
            child: Builder(
              builder: (context) {
                typed = TypedAppearanceScope.controllerOf<DefaultAppearance>(
                  context,
                )!;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      typed.addListener(listener);
      typed.value = DefaultAppearance(spacing: 22);
      expect(calls, 1);
      expect(controller.value, same(typed.value));
      controller.value = Appearance();
      expect(calls, 2);
      expect(() => typed.value, throwsStateError);
      typed.removeListener(listener);
      typed.addListener(listener);
      typed.dispose();
      controller.value = DefaultAppearance();
      expect(calls, 2);
    },
  );

  testWidgets('missing scope and wrong model are explicit', (tester) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          expect(
            TypedAppearanceScope.maybeOf<DefaultAppearance>(context),
            isNull,
          );
          expect(
            TypedAppearanceScope.controllerOf<DefaultAppearance>(context),
            isNull,
          );
          expect(
            () => TypedAppearanceScope.of<DefaultAppearance>(context),
            throwsStateError,
          );
          return const SizedBox();
        },
      ),
    );
    final controller = ValueNotifier(Appearance());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      AppearanceScope(
        controller: controller,
        child: Builder(
          builder: (context) {
            expect(
              () => TypedAppearanceScope.maybeOf<DefaultAppearance>(context),
              throwsStateError,
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });
}
