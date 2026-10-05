import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/theme/container_style.dart';

void main() {
  const style = ContainerStyle(color: Color(0xFF123456), radius: 27);

  test('predefined slots preserve their read, write and reset behavior', () {
    expect(AppearanceSlot.values.length, 11);
    for (final slot in AppearanceSlot.values) {
      const initial = Appearance();
      final changed = slot.write(initial, style);
      expect(slot.read(changed).color, style.color, reason: slot.name);
      expect(slot.read(changed).radius, style.radius, reason: slot.name);
      final reset = slot.read(slot.reset(changed));
      final expected = slot == AppearanceSlot.pathBar
          ? const ContainerStyle(borderWidth: 1)
          : slot.read(initial);
      expect(reset.toJson(), expected.toJson(), reason: slot.name);
    }
  });

  test('custom slots delegate style operations to the supplied functions', () {
    final slot = AppearanceSlot(
      'Custom panel',
      name: 'custom-panel',
      editShape: false,
      extendedLook: false,
      read: (a) => a.sidebarStyle,
      write: (a, value) => a.copyWith(sidebarStyle: value),
      reset: (a) => a.copyWith(sidebarStyle: const ContainerStyle()),
    );
    final updated = slot.write(const Appearance(), style);
    expect(slot.read(updated), same(style));
    expect(
      slot.read(slot.reset(updated)).toJson(),
      const ContainerStyle().toJson(),
    );
    expect(slot.name, 'custom-panel');
    expect(slot.editShape, isFalse);
    expect(slot.extendedLook, isFalse);
    expect(slot.standard, same(slot));
    expect(slot.selectedVariant, isNull);
    expect(slot.isSelectedVariant, isFalse);
    expect(AppearanceSlot.values, isNot(contains(slot)));
  });

  test('custom slots support standard and selected variant links', () {
    final standard = AppearanceSlot(
      'Custom standard',
      name: 'custom-standard',
      selectedVariant: AppearanceSlot.selectedCard,
      read: (a) => a.cardStyle,
      write: (a, value) => a.copyWith(cardStyle: value),
      reset: (a) => a.copyWith(cardStyle: Appearance.defaultCardStyle),
    );
    final selected = AppearanceSlot(
      'Custom selected',
      name: 'custom-selected',
      standard: standard,
      read: (a) => a.effectiveSelectedCardStyle,
      write: (a, value) => a.copyWith(selectedCardStyle: value),
      reset: (a) => a.copyWith(resetSelectedCardStyle: true),
    );
    expect(standard.selectedVariant, AppearanceSlot.selectedCard);
    expect(selected.standard, same(standard));
    expect(selected.isSelectedVariant, isTrue);
    for (final slot in [
      AppearanceSlot.card,
      AppearanceSlot.diskTile,
      AppearanceSlot.folder,
    ]) {
      expect(slot.selectedVariant!.standard, same(slot));
      expect(slot.selectedVariant!.isSelectedVariant, isTrue);
    }
  });
}
