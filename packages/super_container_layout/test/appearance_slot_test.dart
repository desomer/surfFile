import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/theme/container_style.dart';

void main() {
  test('application callbacks define a slot without a predefined catalog', () {
    final slot = AppearanceSlot(
      'Custom surface',
      name: 'custom',
      read: (a) => a.backgroundStyle,
      write: (a, style) => a.copyWith(backgroundStyle: style),
      reset: (a) => a.copyWith(backgroundStyle: const ContainerStyle()),
    );
    const style = ContainerStyle(radius: 32);
    final changed = slot.write(Appearance(), style);
    expect(slot.read(changed), same(style));
    expect(slot.read(slot.reset(changed)).radius, const ContainerStyle().radius);
    expect(slot.role, AppearanceSurfaceRole.standard);
    expect(slot.standard, same(slot));
    expect(slot.selectedVariant, isNull);
  });

  test('application background role and variant links are explicit', () {
    late final AppearanceSlot selected;
    final standard = AppearanceSlot(
      'Surface',
      name: 'surface',
      role: AppearanceSurfaceRole.applicationBackground,
      editShape: false,
      extendedLook: false,
      selectedVariantResolver: () => selected,
      read: (a) => a.backgroundStyle,
      write: (a, style) => a.copyWith(backgroundStyle: style),
      reset: (a) => a.copyWith(backgroundStyle: const ContainerStyle()),
    );
    selected = AppearanceSlot(
      'Selected surface',
      name: 'selected-surface',
      standard: standard,
      read: (a) => a.backgroundStyle,
      write: (a, style) => a.copyWith(backgroundStyle: style),
      reset: (a) => a.copyWith(backgroundStyle: const ContainerStyle()),
    );
    expect(standard.role, AppearanceSurfaceRole.applicationBackground);
    expect(standard.editShape, isFalse);
    expect(standard.extendedLook, isFalse);
    expect(standard.selectedVariant, same(selected));
    expect(selected.standard, same(standard));
    expect(selected.isSelectedVariant, isTrue);
  });
}
