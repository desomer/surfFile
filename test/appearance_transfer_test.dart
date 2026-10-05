import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:surf_file/services/appearance_store.dart';
import 'package:surf_file/services/appearance_transfer.dart';
import 'package:surf_file/theme/surffile_appearance.dart';

void main() {
  final custom = Appearance(
    accent: const Color(0xFF00796B),
    mode: ThemeMode.dark,
    fontSize: 15,
    layouts: {
      'explorer': SurfFileAppearanceDefaults.defaultExplorerLayout.withSwap(
        SuperLayoutZone.west,
      ),
      'explorerMain': SurfFileAppearanceDefaults.defaultExplorerMainLayout.withSwap(
        SuperLayoutZone.north,
      ),
    },
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
      expect(dataOf(text).keys, containsAll(['accent', 'layouts', 'application', 'styles']));
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
        Appearance(),
        text,
        both,
      );
      expect(AppearanceStore.encode(restored), AppearanceStore.encode(custom));
    });

    test('styles only keep the current layouts', () {
      final text = AppearanceTransfer.export(custom, both);
      final restored = AppearanceTransfer.import(Appearance(), text, {
        TransferGroup.styles,
      });
      expect(restored.accent, custom.accent);
      expect(restored.fontSize, 15);
      expect(restored.layout('explorer'), SurfFileAppearanceDefaults.defaultExplorerLayout);
      expect(restored.layout('explorerMain'), SurfFileAppearanceDefaults.defaultExplorerMainLayout);
    });

    test('layouts only keep the current styles', () {
      final text = AppearanceTransfer.export(custom, both);
      final restored = AppearanceTransfer.import(Appearance(), text, {
        TransferGroup.layouts,
      });
      expect(restored.layout('explorer'), custom.layout('explorer'));
      expect(restored.layout('explorerMain'), custom.layout('explorerMain'));
      expect(restored.accent, Appearance().accent);
      expect(restored.fontSize, Appearance().fontSize);
    });

    test('a separate export imports only what it holds', () {
      final text = AppearanceTransfer.export(custom, {TransferGroup.layouts});
      expect(AppearanceTransfer.groupsIn(text), {TransferGroup.layouts});
      // Les styles demandés mais absents n'ont rien à apporter.
      final restored = AppearanceTransfer.import(
        Appearance(),
        text,
        both,
      );
      expect(restored.layout('explorer'), custom.layout('explorer'));
      expect(restored.accent, Appearance().accent);
      expect(
        () => AppearanceTransfer.import(Appearance(), text, {
          TransferGroup.styles,
        }),
        throwsFormatException,
      );
    });

    test('a raw saved appearance is accepted', () {
      final raw = AppearanceStore.encode(custom);
      expect(AppearanceTransfer.groupsIn(raw), both);
      final restored = AppearanceTransfer.import(Appearance(), raw, both);
      expect(AppearanceStore.encode(restored), raw);
    });

    test('invalid texts are rejected and describe why', () {
      final valid = AppearanceTransfer.export(custom, both);
      final wrongVersion = jsonEncode({
        ...(jsonDecode(valid) as Map),
        'version': 99,
      });
      final badValue = jsonEncode({
        'format': AppearanceTransfer.format,
        'version': AppearanceStore.version,
        'groups': ['styles'],
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
        () => AppearanceTransfer.import(Appearance(), badValue, both),
        throwsFormatException,
      );
    });
  });
}
