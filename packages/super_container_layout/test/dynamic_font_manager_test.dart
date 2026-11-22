import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show FontStyle, FontWeight;
import 'package:super_container_layout/super_container_layout.dart';

/// En-tête binaire TrueType minimal valide (signature 0x00010000 + padding).
Uint8List _fakeTtfBytes([int seed = 1]) => Uint8List.fromList(<int>[
  0x00, 0x01, 0x00, 0x00, // sfntVersion TrueType
  0x00, 0x04, 0x00, 0x40,
  0x00, 0x02, 0x00, 0x00,
  seed & 0xFF, 0x10, 0x20, 0x30,
]);

void main() {
  group('DesignMdFontExtractor', () {
    test(
      'extrait les polices du frontmatter, fontHint, Google Fonts URL, JSON, CSS et tableaux tout en filtrant les génériques',
      () {
        const md = '''
---
name: Editorial Lab
fontFamily: "Playfair Display"
monoFont: "Fira Code"
---

# Editorial Lab

Import Google Fonts : https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;700&family=Space+Grotesk&display=swap

| Niveau | `fontFamily` | `fontSize` |
| :--- | :--- | :--- |
| Titre | "Playfair Display" | 24 |
| Corps | `DM Sans` / Sans-serif | 14 |

```css
body { font-family: 'Outfit', sans-serif, system-ui; }
```

```json
{ "fontFamily": "Sora" }
```
''';

        final extracted = DesignMdFontExtractor.extractFontFamilies(
          fontHint: 'Playfair Display / Sans doux / Material 3',
          markdown: md,
        );

        expect(
          extracted,
          containsAllInOrder([
            'Playfair Display',
            'Fira Code',
            'DM Sans',
            'Space Grotesk',
            'Sora',
            'Outfit',
          ]),
        );
        expect(extracted, isNot(contains('Sans-serif')));
        expect(extracted, isNot(contains('Sans doux')));
        expect(extracted, isNot(contains('Material 3')));
        expect(extracted, isNot(contains('system-ui')));
      },
    );

    test('nettoie les préfixes packages/... et parenthèses', () {
      expect(
        DesignMdFontExtractor.cleanFontFamilyToken(
          'packages/super_container_layout/Plus Jakarta Sans',
        ),
        'Plus Jakarta Sans',
      );
      expect(
        DesignMdFontExtractor.cleanFontFamilyToken(' "Space Grotesk (titres)" '),
        'Space Grotesk',
      );
    });
  });

  group('GoogleFontsDownloader', () {
    test(
      'bascule sur les URLs CSS2 de repli en cas de 400 et parse les variantes TTF',
      () async {
        final requestedUrls = <String>[];
        final ttfRegular = _fakeTtfBytes(1);
        final ttfBold = _fakeTtfBytes(2);

        final downloader = GoogleFontsDownloader(
          httpGet: (uri, {headers}) async {
            requestedUrls.add(uri.toString());
            if (uri.host == 'fonts.googleapis.com') {
              // 1re requête (ital,wght) -> 400 ; 2e requête (wght) -> 200
              if (uri.toString().contains('ital,wght')) {
                return (statusCode: 400, bytes: Uint8List(0));
              }
              const css = '''
@font-face {
  font-family: 'Space Grotesk';
  font-style: normal;
  font-weight: 400;
  src: url(https://fonts.gstatic.com/s/spacegrotesk/v16/regular.ttf) format('truetype');
}
@font-face {
  font-family: 'Space Grotesk';
  font-style: normal;
  font-weight: 700;
  src: url(https://fonts.gstatic.com/s/spacegrotesk/v16/bold.ttf) format('truetype');
}
''';
              return (
                statusCode: 200,
                bytes: Uint8List.fromList(utf8.encode(css)),
              );
            }
            if (uri.path.endsWith('regular.ttf')) {
              return (statusCode: 200, bytes: ttfRegular);
            }
            if (uri.path.endsWith('bold.ttf')) {
              return (statusCode: 200, bytes: ttfBold);
            }
            return (statusCode: 404, bytes: Uint8List(0));
          },
        );

        final response = await downloader.download('Space Grotesk');
        expect(response.isSuccess, isTrue);
        expect(response.variants, hasLength(2));
        expect(response.variants[0].weight, 400);
        expect(response.variants[0].italic, isFalse);
        expect(response.variants[1].weight, 700);
        expect(requestedUrls.length, 4); // 2 CSS attempts + 2 TTF files
      },
    );

    test(
      'retourne notFound si toutes les requêtes CSS2 répondent 400/404',
      () async {
        final downloader = GoogleFontsDownloader(
          httpGet: (_, {headers}) async =>
              (statusCode: 400, bytes: Uint8List(0)),
        );
        final response = await downloader.download('ProprietaryBrandFont');
        expect(response.notFound, isTrue);
        expect(response.isSuccess, isFalse);
      },
    );

    test('rejette les fichiers ne possédant pas une signature TTF/OTF valide', () async {
      final downloader = GoogleFontsDownloader(
        httpGet: (uri, {headers}) async {
          if (uri.host == 'fonts.googleapis.com') {
            const css = '''
@font-face {
  font-family: 'BadFont';
  font-style: normal;
  font-weight: 400;
  src: url(https://fonts.gstatic.com/s/bad/regular.ttf) format('truetype');
}
''';
            return (
              statusCode: 200,
              bytes: Uint8List.fromList(utf8.encode(css)),
            );
          }
          return (
            statusCode: 200,
            bytes: Uint8List.fromList(utf8.encode('<html>not a font</html>')),
          );
        },
      );
      final response = await downloader.download('BadFont');
      expect(response.isSuccess, isFalse);
      expect(response.notFound, isFalse);
    });
  });

  group('DynamicFontManager', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('scl_dynamic_fonts_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'télécharge une police, déduplique les requêtes simultanées, persiste le cache disque et recharge hors-ligne',
      () async {
        var cssDownloads = 0;
        final registeredFamilies = <String>[];
        final completer = Completer<void>();

        final downloader = GoogleFontsDownloader(
          httpGet: (uri, {headers}) async {
            if (uri.host == 'fonts.googleapis.com') {
              cssDownloads++;
              await completer.future;
              const css = '''
@font-face {
  font-family: 'Space Grotesk';
  font-style: normal;
  font-weight: 400;
  src: url(https://fonts.gstatic.com/s/spacegrotesk/regular.ttf) format('truetype');
}
''';
              return (
                statusCode: 200,
                bytes: Uint8List.fromList(utf8.encode(css)),
              );
            }
            return (statusCode: 200, bytes: _fakeTtfBytes(7));
          },
        );

        final manager1 = DynamicFontManager(
          cacheDirectory: tempDir,
          downloader: downloader,
          registerFont: (family, fonts) async {
            registeredFamilies.add(family);
          },
        );

        // Deux appels simultanés doivent déclencher un seul téléchargement.
        final f1 = manager1.ensureFontLoaded('Space Grotesk');
        final f2 = manager1.ensureFontLoaded('Space Grotesk');
        await Future<void>.delayed(Duration.zero);
        expect(manager1.statusOf('Space Grotesk'), DynamicFontStatus.loading);
        completer.complete();

        final results = await Future.wait([f1, f2]);
        expect(cssDownloads, 1);
        expect(results[0].status, DynamicFontStatus.loaded);
        expect(results[1].status, DynamicFontStatus.loaded);
        expect(results[0].fromCache, isFalse);
        expect(registeredFamilies, ['Space Grotesk']);
        expect(manager1.loadedFontFamilies, ['Space Grotesk']);
        expect(
          manager1.effectiveAvailableFontFamilies(),
          contains('Space Grotesk'),
        );

        // Nouvelle instance hors-ligne : doit recharger depuis le cache disque sans HTTP.
        var offlineHttpCalls = 0;
        final offlineRegistered = <String>[];
        final manager2 = DynamicFontManager(
          cacheDirectory: tempDir,
          downloader: GoogleFontsDownloader(
            httpGet: (_, {headers}) async {
              offlineHttpCalls++;
              throw const SocketException('offline');
            },
          ),
          registerFont: (family, fonts) async {
            offlineRegistered.add(family);
          },
        );

        final count = await manager2.loadCachedFonts();
        expect(count, 1);
        expect(offlineHttpCalls, 0);
        expect(offlineRegistered, ['Space Grotesk']);
        expect(manager2.statusOf('Space Grotesk'), DynamicFontStatus.loaded);
        expect(manager2.entryOf('Space Grotesk')?.fromCache, isTrue);
      },
    );

    test(
      'mémorise les échecs et autorise un nouvel essai explicite avec forceRetry: true',
      () async {
        var attempts = 0;
        var shouldFail = true;

        final manager = DynamicFontManager(
          useDefaultCacheDirectory: false,
          downloader: GoogleFontsDownloader(
            httpGet: (uri, {headers}) async {
              if (uri.host == 'fonts.googleapis.com') {
                attempts++;
                if (shouldFail) {
                  return (statusCode: 503, bytes: Uint8List(0));
                }
                const css = '''
@font-face {
  font-family: 'DM Sans';
  font-style: normal;
  font-weight: 400;
  src: url(https://fonts.gstatic.com/s/dmsans/regular.ttf) format('truetype');
}
''';
                return (
                  statusCode: 200,
                  bytes: Uint8List.fromList(utf8.encode(css)),
                );
              }
              return (statusCode: 200, bytes: _fakeTtfBytes(9));
            },
          ),
          registerFont: (_, _) async {},
        );

        final first = await manager.ensureFontLoaded('DM Sans');
        expect(first.status, DynamicFontStatus.failed);
        expect(attempts, 1);

        // Sans forceRetry, le cache négatif évite une nouvelle requête.
        final second = await manager.ensureFontLoaded('DM Sans');
        expect(second.status, DynamicFontStatus.failed);
        expect(attempts, 1);

        // Avec forceRetry: true, le téléchargement reprend et réussit.
        shouldFail = false;
        final third = await manager.ensureFontLoaded(
          'DM Sans',
          forceRetry: true,
        );
        expect(third.status, DynamicFontStatus.loaded);
        expect(attempts, 2);
      },
    );

    test(
      'PdfFontResolver utilise les variantes .ttf dynamiques en cache',
      () async {
        final regularRealTtf = File(
          'assets/fonts/Inter-Variable.ttf',
        ).readAsBytesSync();
        final italicRealTtf = File(
          'assets/fonts/Inter-Italic-Variable.ttf',
        ).readAsBytesSync();

        final manager = DynamicFontManager(
          cacheDirectory: tempDir,
          downloader: GoogleFontsDownloader(
            httpGet: (uri, {headers}) async {
              if (uri.host == 'fonts.googleapis.com') {
                const css = '''
@font-face {
  font-family: 'CustomEditorial';
  font-style: normal;
  font-weight: 400;
  src: url(https://fonts.gstatic.com/s/customeditorial/regular.ttf) format('truetype');
}
@font-face {
  font-family: 'CustomEditorial';
  font-style: italic;
  font-weight: 400;
  src: url(https://fonts.gstatic.com/s/customeditorial/italic.ttf) format('truetype');
}
''';
                return (
                  statusCode: 200,
                  bytes: Uint8List.fromList(utf8.encode(css)),
                );
              }
              if (uri.path.endsWith('italic.ttf')) {
                return (statusCode: 200, bytes: italicRealTtf);
              }
              return (statusCode: 200, bytes: regularRealTtf);
            },
          ),
          registerFont: (_, _) async {},
        );

        final loaded = await manager.ensureFontLoaded('CustomEditorial');
        expect(loaded.status, DynamicFontStatus.loaded);

        final pdfResolver = PdfFontResolver(fontManager: manager);
        final resolved = await pdfResolver.resolveFamily('CustomEditorial');
        expect(resolved.base, isNotNull);
        expect(resolved.italic, isNot(same(resolved.base)));
        expect(
          resolved.variant(weight: FontWeight.w400, style: FontStyle.italic),
          same(resolved.italic),
        );
      },
    );
  });
}
