import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/neon_style.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/theme/surffile_appearance_slots.dart';

void main() {
  const custom = ContainerStyle(color: Color(0xFF123456), radius: 21);
  const dynamicLayout = SuperLayoutConfig(
    north: false,
    placements: {
      SuperLayoutZone.center: ['content'],
    },
  );

  test('partial maps keep every default style and layout', () {
    final appearance = Appearance(
      styles: const {'card': custom},
      layouts: const {'explorerMain': dynamicLayout},
    );
    expect(appearance.style('card'), same(custom));
    for (final id in Appearance.defaultStyles.keys.where((id) => id != 'card')) {
      expect(
        appearance.styles[id]!.toJson(),
        Appearance.defaultStyles[id]!.toJson(),
        reason: id,
      );
    }
    expect(appearance.layout('explorerMain'), same(dynamicLayout));
    expect(appearance.layout('explorer'), Appearance.defaultExplorerLayout);
    expect(
      appearance.layout('explorerSidebar'),
      Appearance.defaultExplorerSidebarLayout,
    );
    expect(appearance.styles['selectedCard'], isNull);
  });

  test('withStyle and withLayout keep the SurfFile type and scalars', () {
    final initial = Appearance(cardHeight: 210, spacing: 30);
    final SurfFileAppearance changed = initial
        .withStyle('custom-panel', custom)
        .withLayout('custom-layout', dynamicLayout)
        .withStyle('selectedCard', custom);
    expect(changed.cardHeight, 210);
    expect(changed.spacing, 30);
    expect(changed.style('custom-panel'), same(custom));
    expect(changed.layout('custom-layout'), same(dynamicLayout));
    final copied = changed.copyWith(rowHeight: 60);
    expect(copied.style('custom-panel'), same(custom));
    expect(copied.layout('custom-layout'), same(dynamicLayout));

    final removed = changed
        .withStyle('selectedCard', null)
        .withStyle('card', null);
    expect(removed.styles.containsKey('selectedCard'), isFalse);
    expect(
      removed.style('card').toJson(),
      Appearance.defaultCardStyle.toJson(),
    );
    expect(removed.style('custom-panel'), same(custom));
  });

  test('resetLayouts restores defaults and keeps styles and scalars', () {
    final appearance = Appearance(iconSize: 60)
        .withStyle('custom-panel', custom)
        .withLayout('explorer', dynamicLayout)
        .withLayout('custom-layout', dynamicLayout);
    final SurfFileAppearance reset = appearance.resetLayouts();
    expect(reset.iconSize, 60);
    expect(reset.style('custom-panel'), same(custom));
    expect(reset.layout('explorer'), Appearance.defaultExplorerLayout);
    expect(reset.layouts.containsKey('custom-layout'), isFalse);
  });

  test('dynamic style and layout IDs survive save and load', () {
    final appearance = Appearance()
        .withStyle('custom-panel', custom)
        .withStyle('selectedFolder', custom)
        .withLayout('custom-layout', dynamicLayout);
    final restored = AppearanceStore.decode(AppearanceStore.encode(appearance));
    expect(restored.style('custom-panel').toJson(), custom.toJson());
    expect(restored.styles['selectedFolder']!.toJson(), custom.toJson());
    expect(
      restored.layout('custom-layout').toJson(),
      dynamicLayout.toJson(),
    );
    expect(
      restored.style('card').toJson(),
      Appearance.defaultCardStyle.toJson(),
    );
  });

  test('selected variants derive from their standard style by ID', () {
    const glow = NeonStyle(enabled: true, color: Colors.pink);
    final appearance = Appearance(
      styles: const {
        'card': ContainerStyle(
          radius: 30,
          elevation: 4,
          color: Color(0xFF00FF00),
          neon: glow,
        ),
        'diskTile': ContainerStyle(radius: 7, color: Color(0xFF0000FF)),
      },
    );
    final selectedCard = SurfFileAppearanceSlots.selectedCard.read(appearance);
    expect(selectedCard.radius, 30);
    expect(selectedCard.elevation, 4);
    expect(selectedCard.color, isNull);
    expect(selectedCard.neon!.toJson(), glow.toJson());
    expect(
      appearance.variantStyle('selectedCard', 'card').toJson(),
      selectedCard.toJson(),
    );
    final selectedTile = SurfFileAppearanceSlots.selectedDiskTile.read(
      appearance,
    );
    expect(selectedTile.radius, 7);
    expect(selectedTile.color, const Color(0xFF0000FF));

    final overridden = appearance.withStyle(
      'selectedCard',
      const ContainerStyle(radius: 3),
    );
    final resolved = SurfFileAppearanceSlots.selectedCard.read(overridden);
    expect(resolved.radius, 3);
    expect(resolved.neon!.toJson(), glow.toJson());
  });
}