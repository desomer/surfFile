import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/services/appearance_store.dart';
import 'package:super_container_layout/services/appearance_transfer.dart';
import 'package:super_container_layout/theme/appearance.dart';

void main() {
  final custom = Appearance(
    accent: const Color(0xFF00796B),
    mode: ThemeMode.dark,
    fontSize: 15,
    explorerLayout: Appearance.defaultExplorerLayout.withSwap(
      SuperLayoutZone.west,
    ),
    explorerMainLayout: Appearance.defaultExplorerMainLayout.withSwap(
      SuperLayoutZone.north,
    ),
  );
  const both = {TransferGroup.styles, TransferGroup.layouts};

  Map<String, Object?> dataOf(String text) =>
      (jsonDecode(text) as Map)['data'] as Map<String, Object?>;

  group('export', () {
    test('both groups carry every setting', () {
      final text = AppearanceTransfer.export(custom, both);
      final json = jsonDecode(text) as Map;
      expect(json['format'], AppearanceTransfer.format);
      expect(json['version'], AppearanceStore.version);
      expect(json['groups'], ['styles', 'layouts']);
      expect(dataOf(text).keys, containsAll(['accent', 'explorerLayout']));
      expect(dataOf(text).containsKey('version'), isFalse);
    });

    test('styles alone leave the layouts out', () {
      final text = AppearanceTransfer.export(custom, {TransferGroup.styles});
      expect((jsonDecode(text) as Map)['groups'], ['styles']);
      expect(dataOf(text).keys, contains('accent'));
      expect(
        dataOf(text).keys.toSet().intersection(AppearanceTransfer.layoutKeys),
        isEmpty,
      );
    });

    test('layouts alone carry only the layouts', () {
      final text = AppearanceTransfer.export(custom, {TransferGroup.layouts});
      expect(dataOf(text).keys.toSet(), AppearanceTransfer.layoutKeys);
    });

    test('nothing to export is refused', () {
      expect(() => AppearanceTransfer.export(custom, {}), throwsArgumentError);
    });
  });

  group('import', () {
    test('a full export restores the whole appearance', () {
      final text = AppearanceTransfer.export(custom, both);
      final restored = AppearanceTransfer.import(
        const Appearance(),
        text,
        both,
      );
      expect(AppearanceStore.encode(restored), AppearanceStore.encode(custom));
    });

    test('styles only keep the current layouts', () {
      final text = AppearanceTransfer.export(custom, both);
      final restored = AppearanceTransfer.import(const Appearance(), text, {
        TransferGroup.styles,
      });
      expect(restored.accent, custom.accent);
      expect(restored.fontSize, 15);
      expect(restored.explorerLayout, Appearance.defaultExplorerLayout);
      expect(restored.explorerMainLayout, Appearance.defaultExplorerMainLayout);
    });

    test('layouts only keep the current styles', () {
      final text = AppearanceTransfer.export(custom, both);
      final restored = AppearanceTransfer.import(const Appearance(), text, {
        TransferGroup.layouts,
      });
      expect(restored.explorerLayout, custom.explorerLayout);
      expect(restored.explorerMainLayout, custom.explorerMainLayout);
      expect(restored.accent, const Appearance().accent);
      expect(restored.fontSize, const Appearance().fontSize);
    });

    test('a separate export imports only what it holds', () {
      final text = AppearanceTransfer.export(custom, {TransferGroup.layouts});
      expect(AppearanceTransfer.groupsIn(text), {TransferGroup.layouts});
      // Les styles demandés mais absents n'ont rien à apporter.
      final restored = AppearanceTransfer.import(
        const Appearance(),
        text,
        both,
      );
      expect(restored.explorerLayout, custom.explorerLayout);
      expect(restored.accent, const Appearance().accent);
      expect(
        () => AppearanceTransfer.import(const Appearance(), text, {
          TransferGroup.styles,
        }),
        throwsFormatException,
      );
    });

    test('a raw saved appearance is accepted', () {
      final raw = AppearanceStore.encode(custom);
      expect(AppearanceTransfer.groupsIn(raw), both);
      final restored = AppearanceTransfer.import(const Appearance(), raw, both);
      expect(AppearanceStore.encode(restored), raw);
    });

    test('invalid texts are rejected and describe why', () {
      final valid = AppearanceTransfer.export(custom, both);
      final wrongVersion = jsonEncode({
        ...(jsonDecode(valid) as Map),
        'version': 1,
      });
      final badValue = jsonEncode({
        'format': AppearanceTransfer.format,
        'version': AppearanceStore.version,
        'data': {'mode': 'sepia'},
      });
      for (final text in [
        '',
        'pas du json',
        '[]',
        '{"format": "autre"}',
        '{"version": 1}',
        wrongVersion,
        '{"format": "${AppearanceTransfer.format}", "version": '
            '${AppearanceStore.version}}',
        '{"format": "${AppearanceTransfer.format}", "version": '
            '${AppearanceStore.version}, "data": {"inconnu": 1}}',
      ]) {
        expect(
          () => AppearanceTransfer.groupsIn(text),
          throwsFormatException,
          reason: text,
        );
      }
      // Une valeur invalide n'est détectée qu'à l'application, sans rien changer.
      expect(AppearanceTransfer.groupsIn(badValue), {TransferGroup.styles});
      expect(
        () => AppearanceTransfer.import(const Appearance(), badValue, both),
        throwsFormatException,
      );
    });
  });
}
