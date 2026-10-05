import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:surf_file/theme/surffile_appearance_slots.dart';

void main() {
  const style = ContainerStyle(color: Color(0xFF123456), radius: 27);

  test('SurfFile owns surface roles and extended editing capabilities', () {
    expect(
      SurfFileAppearanceSlots.background.role,
      AppearanceSurfaceRole.applicationBackground,
    );
    expect(SurfFileAppearanceSlots.background.editShape, isFalse);
    for (final slot in SurfFileAppearanceSlots.values) {
      final renderedElsewhere = {
        SurfFileAppearanceSlots.background,
        SurfFileAppearanceSlots.card,
        SurfFileAppearanceSlots.selectedCard,
      }.contains(slot);
      expect(slot.extendedLook, !renderedElsewhere, reason: slot.name);
      if (slot != SurfFileAppearanceSlots.background) {
        expect(slot.role, AppearanceSurfaceRole.standard, reason: slot.name);
      }
    }
  });

  test('predefined slots preserve their read, write and reset behavior', () {
    expect(SurfFileAppearanceSlots.values.length, 11);
    for (final slot in SurfFileAppearanceSlots.values) {
      final initial = defaultSurfFileAppearance();
      final changed = slot.write(initial, style);
      expect(slot.read(changed).color, style.color, reason: slot.name);
      expect(slot.read(changed).radius, style.radius, reason: slot.name);
      final reset = slot.read(slot.reset(changed));
      final expected = slot == SurfFileAppearanceSlots.pathBar
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
      read: (a) => a.style('custom-panel'),
      write: (a, value) => a.withStyle('custom-panel', value),
      reset: (a) => a.withStyle('custom-panel', null),
    );
    final updated = slot.write(Appearance(), style);
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
    expect(SurfFileAppearanceSlots.values, isNot(contains(slot)));
  });

  test('custom slots support standard and selected variant links', () {
    final standard = AppearanceSlot(
      'Custom standard',
      name: 'custom-standard',
      selectedVariant: SurfFileAppearanceSlots.selectedCard,
      read: (a) => a.style('custom-standard'),
      write: (a, value) => a.withStyle('custom-standard', value),
      reset: (a) => a.withStyle('custom-standard', null),
    );
    final selected = AppearanceSlot(
      'Custom selected',
      name: 'custom-selected',
      standard: standard,
      read: (a) => a.style('custom-selected'),
      write: (a, value) => a.withStyle('custom-selected', value),
      reset: (a) => a.withStyle('custom-selected', null),
    );
    expect(standard.selectedVariant, SurfFileAppearanceSlots.selectedCard);
    expect(selected.standard, same(standard));
    expect(selected.isSelectedVariant, isTrue);
    for (final slot in [
      SurfFileAppearanceSlots.card,
      SurfFileAppearanceSlots.diskTile,
      SurfFileAppearanceSlots.folder,
    ]) {
      expect(slot.selectedVariant!.standard, same(slot));
      expect(slot.selectedVariant!.isSelectedVariant, isTrue);
    }
  });
}
