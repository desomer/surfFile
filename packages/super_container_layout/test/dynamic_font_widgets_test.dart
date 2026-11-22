import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/components/super_value_editor.dart';

Uint8List _fakeTtfBytes() => Uint8List.fromList(<int>[
  0x00, 0x01, 0x00, 0x00,
  0x00, 0x04, 0x00, 0x40,
  0x00, 0x02, 0x00, 0x00,
  0x01, 0x02, 0x03, 0x04,
]);

DynamicFontManager _createMockFontManager({
  required Set<String> availableGoogleFonts,
  bool autoDownloadEnabled = true,
  Completer<void>? gate,
}) {
  return DynamicFontManager(
    useDefaultCacheDirectory: false,
    autoDownloadEnabled: autoDownloadEnabled,
    downloader: GoogleFontsDownloader(
      httpGet: (uri, {headers}) async {
        if (gate != null && !gate.isCompleted) {
          await gate.future;
        }
        if (uri.host == 'fonts.googleapis.com') {
          final rawFamily = (uri.queryParameters['family'] ?? '')
              .split(':')
              .first
              .replaceAll('+', ' ');
          if (availableGoogleFonts.contains(rawFamily)) {
            final css =
                '''
@font-face {
  font-family: '$rawFamily';
  font-style: normal;
  font-weight: 400;
  src: url(https://fonts.gstatic.com/s/${rawFamily.toLowerCase().replaceAll(' ', '')}/regular.ttf) format('truetype');
}
''';
            return (
              statusCode: 200,
              bytes: Uint8List.fromList(utf8.encode(css)),
            );
          }
          return (statusCode: 400, bytes: Uint8List(0));
        }
        return (statusCode: 200, bytes: _fakeTtfBytes());
      },
    ),
    registerFont: (_, _) async {},
  );
}

void main() {
  testWidgets(
    'SuperValue télécharge automatiquement une police Google Fonts manquante et se repeint',
    (tester) async {
      final gate = Completer<void>();
      final manager = _createMockFontManager(
        availableGoogleFonts: const {'Space Grotesk'},
        gate: gate,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DynamicFontScope(
            manager: manager,
            child: Scaffold(
              body: SuperValue(
                id: 'hero-title',
                availableFontFamilies: Registry.defaultAvailableFontFamilies,
                config: const SuperValueConfig(
                  initialText: 'Titre Dynamique',
                  fontFamily: 'Space Grotesk',
                ),
              ),
            ),
          ),
        ),
      );

      // Avant la fin du téléchargement, la police personnalisée n'est pas encore appliquée.
      final textBefore = tester.widget<Text>(find.text('Titre Dynamique'));
      expect(textBefore.style?.fontFamily, isNot('Space Grotesk'));

      gate.complete();
      await tester.pumpAndSettle();

      // Après chargement, SuperValue applique la police téléchargée.
      expect(manager.statusOf('Space Grotesk'), DynamicFontStatus.loaded);
      final textAfter = tester.widget<Text>(find.text('Titre Dynamique'));
      expect(textAfter.style?.fontFamily, 'Space Grotesk');
    },
  );

  testWidgets(
    'SuperValueEditor propose le bouton Télécharger pour une police manquante et valide après chargement',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final manager = _createMockFontManager(
        availableGoogleFonts: const {'Playfair Display'},
        autoDownloadEnabled: false,
      );
      SuperValueConfig? saved;

      await tester.pumpWidget(
        DynamicFontScope(
          manager: manager,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    saved = await showSuperValueEditor(
                      context: context,
                      config: const SuperValueConfig(
                        initialText: 'Éditorial',
                        fontFamily: 'Playfair Display',
                      ),
                      availableFontFamilies:
                          Registry.defaultAvailableFontFamilies,
                    );
                  },
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();

      // Ouvre la section Typographie si elle est repliée puis affiche le bouton Télécharger.
      final downloadBtn = find.byKey(
        const ValueKey('super-value-setting-download-font'),
      );
      if (downloadBtn.evaluate().isEmpty) {
        final typoHeader = find.text('Typographie');
        await tester.ensureVisible(typoHeader);
        await tester.tap(typoHeader);
        await tester.pumpAndSettle();
      }
      expect(downloadBtn, findsOneWidget);

      await tester.ensureVisible(downloadBtn);
      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();

      // La police est chargée, le bouton disparaît et la validation réussit.
      expect(manager.statusOf('Playfair Display'), DynamicFontStatus.loaded);
      expect(downloadBtn, findsNothing);

      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(saved?.fontFamily, 'Playfair Display');
    },
  );

  testWidgets(
    'DesignSystemCatalogDialog affiche le statut des polices et permet le téléchargement manuel dans l’inspecteur',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final manager = _createMockFontManager(
        availableGoogleFonts: const {'Outfit'},
        autoDownloadEnabled: false,
      );

      final customPreset = DesignMdParser.parseExternal('''
---
name: Outfit Studio
slug: outfit-studio
mode: light
accent: "#4F46E5"
fontFamily: "Outfit"
---

# Outfit Studio

## Typography
| Niveau | `fontFamily` |
| :--- | :--- |
| Titre | "Outfit" |
| Code | "JetBrains Mono" |
''');

      await tester.pumpWidget(
        MaterialApp(
          home: DynamicFontScope(
            manager: manager,
            child: Scaffold(
              body: DesignSystemCatalogDialog(
                customPresets: [customPreset],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ouvre l'inspecteur du DESIGN.md personnalisé.
      final inspectButton = find.byKey(
        ValueKey<String>('design-system-inspect-${customPreset.id}'),
      );
      expect(inspectButton, findsOneWidget);
      await tester.tap(inspectButton);
      await tester.pumpAndSettle();

      // Vérifie les puces de statut pour Outfit (manquante) et JetBrains Mono (embarquée).
      expect(
        find.byKey(const ValueKey('design-catalog-font-chip-Outfit')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('design-catalog-font-chip-JetBrains Mono')),
        findsOneWidget,
      );
      final downloadBtn = find.byKey(
        const ValueKey('design-catalog-download-fonts'),
      );
      expect(downloadBtn, findsOneWidget);

      // Télécharge manuellement Outfit.
      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();

      expect(manager.statusOf('Outfit'), DynamicFontStatus.loaded);
      expect(find.text('Outfit · téléchargée'), findsOneWidget);
      expect(downloadBtn, findsNothing);
    },
  );
}
