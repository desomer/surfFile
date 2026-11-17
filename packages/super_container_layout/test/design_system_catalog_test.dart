import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError, ValueNotifier;
import 'package:flutter/services.dart' show ByteData, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show
        Brightness,
        Color,
        Column,
        MaterialApp,
        RichText,
        Scaffold,
        Text,
        ThemeMode,
        ValueKey;
import 'package:super_container_layout/ai/design_md_parser.dart';
import 'package:super_container_layout/ai/design_system_catalog.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/design_system.dart';
import 'package:super_container_layout/widgets/appearance/appearance_scope.dart';
import 'package:super_container_layout/widgets/components/super_value.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';
import 'package:yaml/yaml.dart' show YamlList, YamlMap, loadYaml;

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._assets);

  final Map<String, String> _assets;
  final List<String> requestedKeys = <String>[];

  @override
  Future<ByteData> load(String key) async {
    throw FlutterError('Chargement binaire non supporté dans le test: $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    requestedKeys.add(key);
    final content = _assets[key];
    if (content == null) {
      throw FlutterError('Asset introuvable: $key');
    }
    return content;
  }
}

File _resolvePackageFile(String relativePath) {
  final fromRepoRoot = File('packages/super_container_layout/$relativePath');
  if (fromRepoRoot.existsSync()) return fromRepoRoot;
  return File(relativePath);
}

File _resolveDesignSystemAssetFile(String slug) =>
    _resolvePackageFile('assets/design_systems/$slug.md');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(DesignSystemCatalog.clearCache);

  group('DesignSystemCatalog — intégrité et 24 assets DESIGN.md embarqués', () {
    test('expose 24 préréglages intégrés uniques couvrant les 7 catégories non-custom', () {
      const presets = DesignSystemCatalog.builtInPresets;
      expect(presets, hasLength(24));

      final ids = presets.map((preset) => preset.id).toSet();
      expect(ids, hasLength(24));

      final slugs = presets
          .map((preset) => preset.assetSlug)
          .whereType<String>()
          .toSet();
      expect(slugs, hasLength(24));

      for (final preset in presets) {
        expect(preset.isCustom, isFalse, reason: 'preset ${preset.id}');
        expect(preset.inlineMarkdown, isNull, reason: 'preset ${preset.id}');
        expect(preset.name.trim(), isNotEmpty, reason: 'preset ${preset.id}');
        expect(
          preset.tagline.trim(),
          isNotEmpty,
          reason: 'preset ${preset.id}',
        );
        expect(
          preset.description.trim(),
          isNotEmpty,
          reason: 'preset ${preset.id}',
        );
        expect(preset.tags, isNotEmpty, reason: 'preset ${preset.id}');
        expect(
          () => preset.tags.add('mutation'),
          throwsUnsupportedError,
          reason: 'tags doit être non modifiable pour ${preset.id}',
        );
        expect(preset.candidateAssetPaths, <String>[
          'assets/design_systems/${preset.assetSlug}.md',
          'packages/super_container_layout/assets/design_systems/${preset.assetSlug}.md',
        ]);
      }

      final categories = presets.map((preset) => preset.category).toSet();
      expect(categories, <DesignSystemCategory>{
        DesignSystemCategory.productivitySaas,
        DesignSystemCategory.developerTools,
        DesignSystemCategory.aiPlatforms,
        DesignSystemCategory.fintech,
        DesignSystemCategory.designCreative,
        DesignSystemCategory.mediaRetail,
        DesignSystemCategory.specialRetro,
      });
      expect(categories.contains(DesignSystemCategory.custom), isFalse);
    });

    test('charge les 24 fichiers via rootBundle et valide chaque DESIGN.md sur disque avec DesignMdParser', () async {
      const requiredSections = <String>[
        'Visual Theme',
        'Color Palette',
        'Typography',
        'Component',
        'Layout',
        'Depth',
        "Do's and Don'ts",
        'Agent Prompt Guide',
      ];

      for (final preset in DesignSystemCatalog.builtInPresets) {
        final slug = preset.assetSlug!;
        final file = _resolveDesignSystemAssetFile(slug);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Fichier manquant sur disque pour $slug (${file.path})',
        );

        final rawDiskContent = await file.readAsString();
        expect(
          rawDiskContent.length,
          greaterThan(1500),
          reason: 'Contenu trop court sur disque pour ${preset.id}',
        );

        final loadedFromBundle = await DesignSystemCatalog.loadMarkdown(preset);
        expect(
          loadedFromBundle.length,
          greaterThan(1500),
          reason: 'Contenu chargé trop court pour ${preset.id}',
        );
        expect(
          loadedFromBundle.startsWith('---'),
          isFalse,
          reason: 'Le frontmatter YAML doit être retiré pour ${preset.id}',
        );
        expect(
          loadedFromBundle,
          DesignMdParser.extractBodyOrFull(rawDiskContent),
          reason:
              'Cohérence rootBundle vs fichier disque attendue pour ${preset.id}',
        );

        for (final section in requiredSections) {
          expect(
            loadedFromBundle,
            contains(section),
            reason: 'Section "$section" absente dans ${preset.id} ($slug.md)',
          );
        }

        final parsed = DesignMdParser.parseExternal(
          rawDiskContent,
          fileName: '$slug.md',
        );
        expect(parsed.id, preset.id, reason: 'ID parsé pour ${preset.id}');
        expect(parsed.name, preset.name, reason: 'Nom parsé pour ${preset.id}');
        expect(
          parsed.category,
          preset.category,
          reason: 'Catégorie parsée pour ${preset.id}',
        );
        expect(
          parsed.palette.mode,
          preset.palette.mode,
          reason: 'Mode clair/sombre discordant pour ${preset.id}',
        );
        expect(
          parsed.palette.surfaceSystem,
          preset.palette.surfaceSystem,
          reason: 'surfaceSystem discordant pour ${preset.id}',
        );
        expect(
          parsed.palette.cardRadius,
          preset.palette.cardRadius,
          reason: 'cardRadius discordant pour ${preset.id}',
        );
        expect(
          parsed.palette.accent,
          preset.palette.accent,
          reason: 'Couleur accent discordante pour ${preset.id}',
        );
      }
    });

    test('gère le cache rootBundle, le fallback AssetBundle package et les presets inlineMarkdown', () async {
      DesignSystemCatalog.clearCache();
      final linear = DesignSystemCatalog.byId('linear')!;

      // Déduplication des appels concurrents et mise en cache rootBundle.
      final concurrentResults = await Future.wait<String>(<Future<String>>[
        DesignSystemCatalog.loadMarkdown(linear),
        DesignSystemCatalog.loadMarkdown(linear),
      ]);
      expect(identical(concurrentResults[0], concurrentResults[1]), isTrue);

      final cachedResult = await DesignSystemCatalog.loadMarkdown(linear);
      expect(identical(cachedResult, concurrentResults[0]), isTrue);

      // Fallback sur packages/super_container_layout/assets/design_systems/<slug>.md.
      final fallbackBundle = _FakeAssetBundle(<String, String>{
        'packages/super_container_layout/assets/design_systems/linear.md': '---\nname: Linear\n---\n# Linear Guide\n\nContenu via fallback package.',
      });
      final fromPackagePath = await DesignSystemCatalog.loadMarkdown(
        linear,
        bundle: fallbackBundle,
      );
      expect(
        fromPackagePath,
        '# Linear Guide\n\nContenu via fallback package.',
      );
      expect(fallbackBundle.requestedKeys, <String>[
        'assets/design_systems/linear.md',
        'packages/super_container_layout/assets/design_systems/linear.md',
      ]);

      // Preset personnalisé avec inlineMarkdown (frontmatter retiré automatiquement).
      final inlinePreset = DesignSystemPreset(
        id: 'custom:inline',
        name: 'Inline Studio',
        category: DesignSystemCategory.custom,
        tagline: 'Guide embarqué en mémoire',
        description: 'Description test',
        palette: linear.palette,
        inlineMarkdown: '---\nname: Inline Studio\nmode: dark\n---\n# Inline Studio\n\n## Overview\nCorps Markdown.',
      );
      expect(inlinePreset.isCustom, isTrue);
      final inlineLoaded = await DesignSystemCatalog.loadMarkdown(
        inlinePreset,
        bundle: _FakeAssetBundle(const <String, String>{}),
      );
      expect(inlineLoaded, '# Inline Studio\n\n## Overview\nCorps Markdown.');

      // Erreurs explicites si aucun chemin valide ou asset absent.
      final orphanPreset = DesignSystemPreset(
        id: 'custom:orphan',
        name: 'Orphan',
        category: DesignSystemCategory.custom,
        tagline: 'Sans source',
        description: 'Aucune source',
        palette: linear.palette,
      );
      await expectLater(
        DesignSystemCatalog.loadMarkdown(orphanPreset),
        throwsFlutterError,
      );
      await expectLater(
        DesignSystemCatalog.loadMarkdown(
          linear,
          bundle: _FakeAssetBundle(const <String, String>{}),
        ),
        throwsFlutterError,
      );
    });
  });

  group(
    'DesignMdParser.parseExternal — formats getdesign.md et Google Stitch',
    () {
      test('analyse un fichier style getdesign.md avec frontmatter et retire le suffixe -design-analysis', () {
        const getDesignMd = '''
---
version: alpha
name: Linear-design-analysis
description: "A near-black product-focused canvas built around #010102, light gray text (#f7f8f8), and lavender-blue (#5e6ad2) accents for high-velocity product teams."
---

# Linear-design-analysis

## Overview
A near-black product-focused workspace crafted for keyboard-first engineering workflows and crisp 1px hairlines.

## Colors

### Brand & Accent
- **Brand Primary**: `#5e6ad2` — Signature lavender-blue interactive accent

### Surface
- **Page Background**: `#010102` — Near-black primary canvas
- **Elevated Surface**: `#111215` — Graphite card container

### Text
- **Primary Text**: `#f7f8f8` — High-contrast light gray ink
- **Muted Text**: `#8a8f98` — Secondary metadata label ink

### Borders
- **Hairline Border**: `#23252a` — Subtle 1px structural divider

## Layout & Geometry
Card panels use 8px radius (`card: 8px`) with Inter and JetBrains Mono typography.
''';

        final preset = DesignMdParser.parseExternal(getDesignMd);

        expect(preset.name, 'Linear');
        expect(preset.id, 'custom:linear');
        expect(preset.isCustom, isTrue);
        expect(preset.category, DesignSystemCategory.custom);
        expect(
          preset.description,
          contains('near-black product-focused canvas'),
        );
        expect(preset.palette.mode, ThemeMode.dark);
        expect(preset.palette.isDark, isTrue);
        expect(preset.palette.brightness, Brightness.dark);
        expect(preset.palette.accent, const Color(0xFF5E6AD2));
        expect(preset.palette.canvas, const Color(0xFF010102));
        expect(preset.palette.surface, const Color(0xFF111215));
        expect(preset.palette.textPrimary, const Color(0xFFF7F8F8));
        expect(preset.palette.textMuted, const Color(0xFF8A8F98));
        expect(preset.palette.border, const Color(0xFF23252A));
        expect(preset.palette.cardRadius, 8.0);
        expect(preset.palette.surfaceSystem, DesignSystem.material);
        expect(preset.palette.fontHint, 'JetBrains Mono / Inter');
      });

      test('analyse un DESIGN.md brut sans frontmatter (mode clair, accent CTA, glassmorphism et 0px sharp corners)', () {
        const rawStitchGlassSharp = '''
# Acme Studio

## Overview
Light-first editorial creative studio built on an airy daylight canvas with translucent glassmorphism panels (`backdrop-filter: blur(20px)`) and brutalist 0px sharp corners.

## Color Palette
- **Page Background**: #FAFAFA
- **Card Surface**: #FFFFFF
- **Primary CTA**: #E11D48
- **Primary Text**: #18181B
- **Secondary Text**: #71717A
- **Divider Border**: #E4E4E7

## Component Stylings
Cards combine frosted `backdrop-filter` translucency with 0px sharp corners and Space Grotesk headings.
''';

        final glassPreset = DesignMdParser.parseExternal(rawStitchGlassSharp);
        expect(glassPreset.name, 'Acme Studio');
        expect(glassPreset.id, 'custom:acme-studio');
        expect(glassPreset.isCustom, isTrue);
        expect(glassPreset.palette.mode, ThemeMode.light);
        expect(glassPreset.palette.brightness, Brightness.light);
        expect(glassPreset.palette.canvas, const Color(0xFFFAFAFA));
        expect(glassPreset.palette.surface, const Color(0xFFFFFFFF));
        expect(glassPreset.palette.accent, const Color(0xFFE11D48));
        expect(glassPreset.palette.textPrimary, const Color(0xFF18181B));
        expect(glassPreset.palette.textMuted, const Color(0xFF71717A));
        expect(glassPreset.palette.border, const Color(0xFFE4E4E7));
        expect(glassPreset.palette.cardRadius, 0.0);
        expect(glassPreset.palette.surfaceSystem, DesignSystem.liquidGlass);
        expect(glassPreset.palette.fontHint, 'Space Grotesk');
        expect(glassPreset.tags, contains('liquidglass'));

        const rawNeumorphic = '''
# Tactile Desk — DESIGN.md

## 1. Visual Theme & Atmosphere
Soft neumorphism console sculpted from warm light porcelain with generously rounded surfaces.

## 2. Color Palette & Roles
- **Canvas Background**: #E6E9EF
- **Card Surface**: #E6E9EF
- **Brand Accent**: #4F46E5
- **Primary Text**: #1E293B
''';
        final neumorphicPreset = DesignMdParser.parseExternal(rawNeumorphic);
        expect(neumorphicPreset.name, 'Tactile Desk');
        expect(neumorphicPreset.palette.mode, ThemeMode.light);
        expect(neumorphicPreset.palette.accent, const Color(0xFF4F46E5));
        expect(
          neumorphicPreset.palette.surfaceSystem,
          DesignSystem.neumorphism,
        );
        expect(neumorphicPreset.palette.cardRadius, 16.0);
      });

      test('accepte les couleurs #HEX non quotées et quotées dans le frontmatter YAML sans les tronquer en commentaires', () {
        const unquotedAndQuotedYaml = '''
---
name: Hex Frontmatter Check
slug: hex-check
category: fintech
mode: dark
accent: #10B981
canvasColor: "#090D16"
surfaceColor: #111827
textColor: '#F9FAFB'
mutedTextColor: #9CA3AF
borderColor: #1F2937
cardRadius: 14px
surfaceSystem: liquidGlass
tags: [fintech, emerald, trading]
---

# Hex Frontmatter Check

## Overview
High-contrast dark trading terminal.
''';

        final preset = DesignMdParser.parseExternal(unquotedAndQuotedYaml);

        expect(preset.id, 'hex-check');
        expect(preset.name, 'Hex Frontmatter Check');
        expect(preset.category, DesignSystemCategory.fintech);
        expect(preset.palette.mode, ThemeMode.dark);
        expect(preset.palette.accent, const Color(0xFF10B981));
        expect(preset.palette.canvas, const Color(0xFF090D16));
        expect(preset.palette.surface, const Color(0xFF111827));
        expect(preset.palette.textPrimary, const Color(0xFFF9FAFB));
        expect(preset.palette.textMuted, const Color(0xFF9CA3AF));
        expect(preset.palette.border, const Color(0xFF1F2937));
        expect(preset.palette.cardRadius, 14.0);
        expect(preset.palette.surfaceSystem, DesignSystem.liquidGlass);
        expect(
          preset.tags,
          containsAll(<String>['fintech', 'emerald', 'trading', 'liquidglass']),
        );
        expect(
          DesignSystemPalettePreview.colorToHex(preset.palette.accent),
          '#10B981',
        );
      });

      test('lève une FormatException sur une entrée vide ou composée uniquement d’espaces', () {
        expect(() => DesignMdParser.parseExternal(''), throwsFormatException);
        expect(
          () => DesignMdParser.parseExternal('   \n\t\r\n  '),
          throwsFormatException,
        );
        expect(
          () => DesignMdParser.parseExternal('\uFEFF   \n  '),
          throwsFormatException,
        );
      });
    },
  );

  group('Recherche plein texte, catégories et résolution par identifiant', () {
    List<String> searchIds(String query) => DesignSystemCatalog.builtInPresets
        .where((preset) => preset.matchesQuery(query))
        .map((preset) => preset.id)
        .toList();

    test('matchesQuery supporte les requêtes multi-mots bilingues avec ou sans accents', () {
      expect(searchIds(''), hasLength(24));
      expect(searchIds('   '), hasLength(24));

      final sombreIde = searchIds('sombre ide');
      expect(sombreIde, contains('cursor'));
      for (final id in sombreIde) {
        final preset = DesignSystemCatalog.byId(id)!;
        expect(preset.palette.isDark, isTrue);
      }

      final fintechPaiement = searchIds('fintech paiement');
      expect(fintechPaiement, contains('stripe'));

      // Insensibilité aux accents ('editeur developpeur' vs 'éditeur développeur').
      expect(
        searchIds('editeur developpeur'),
        equals(searchIds('éditeur développeur')),
      );
      expect(searchIds('editeur developpeur'), contains('cursor'));

      final neumorphism = searchIds('neumorphism');
      expect(neumorphism, contains('neumorphic-soft'));

      final brutaliste = searchIds('brutaliste');
      expect(brutaliste, contains('wired'));

      final glass = searchIds('glass');
      expect(glass, contains('raycast'));

      expect(searchIds('introuvable-xyz-999'), isEmpty);
    });

    test('DesignSystemCategory.fromId résout identifiants, libellés FR/EN, mots-clés et fallback', () {
      for (final category in DesignSystemCategory.values) {
        expect(DesignSystemCategory.fromId(category.id), category);
        expect(DesignSystemCategory.fromId(category.name), category);
        expect(DesignSystemCategory.fromId(category.label), category);
        expect(DesignSystemCategory.fromId(category.englishLabel), category);
      }

      expect(
        DesignSystemCategory.fromId('Outils developpeur & CLI'),
        DesignSystemCategory.developerTools,
      );
      expect(
        DesignSystemCategory.fromId('Plateforme Agent LLM'),
        DesignSystemCategory.aiPlatforms,
      );
      expect(
        DesignSystemCategory.fromId('plateforme ia'),
        DesignSystemCategory.aiPlatforms,
      );
      expect(
        DesignSystemCategory.fromId('paiement'),
        DesignSystemCategory.fintech,
      );
      expect(
        DesignSystemCategory.fromId('Banque & Finance'),
        DesignSystemCategory.fintech,
      );
      expect(
        DesignSystemCategory.fromId('Treasury & Wallet'),
        DesignSystemCategory.fintech,
      );
      expect(
        DesignSystemCategory.fromId('Creative Prototyping Studio'),
        DesignSystemCategory.designCreative,
      );
      expect(
        DesignSystemCategory.fromId('E-commerce & Audio'),
        DesignSystemCategory.mediaRetail,
      );
      expect(
        DesignSystemCategory.fromId('Vintage Win98 Brutal'),
        DesignSystemCategory.specialRetro,
      );
      expect(
        DesignSystemCategory.fromId('Enterprise B2B CRM'),
        DesignSystemCategory.productivitySaas,
      );
      expect(
        DesignSystemCategory.fromId('Import externe'),
        DesignSystemCategory.custom,
      );

      expect(DesignSystemCategory.fromId(null), DesignSystemCategory.custom);
      expect(DesignSystemCategory.fromId('   '), DesignSystemCategory.custom);
      expect(
        DesignSystemCategory.fromId(
          'secteur-inconnu',
          fallback: DesignSystemCategory.productivitySaas,
        ),
        DesignSystemCategory.productivitySaas,
      );
    });

    test('DesignSystemCatalog.byId gère la casse, les espaces et donne priorité à customPresets', () {
      expect(DesignSystemCatalog.byId(''), isNull);
      expect(DesignSystemCatalog.byId('   '), isNull);
      expect(DesignSystemCatalog.byId('unknown-preset'), isNull);

      final stripe = DesignSystemCatalog.byId('stripe');
      expect(stripe, isNotNull);
      expect(stripe!.name, 'Stripe');
      expect(DesignSystemCatalog.byId('  STRIPE  '), same(stripe));

      final customOverride = stripe.copyWith(
        name: 'Stripe Custom Fork',
        category: DesignSystemCategory.custom,
        inlineMarkdown: '# Stripe Custom Fork',
      );
      final customExtra = DesignSystemPreset(
        id: 'custom:acme',
        name: 'Acme',
        category: DesignSystemCategory.custom,
        tagline: 'Tagline',
        description: 'Description',
        palette: stripe.palette,
        inlineMarkdown: '# Acme',
      );

      final resolvedOverride = DesignSystemCatalog.byId(
        'stripe',
        customPresets: <DesignSystemPreset>[customOverride, customExtra],
      );
      expect(resolvedOverride, same(customOverride));
      expect(resolvedOverride!.name, 'Stripe Custom Fork');

      final resolvedCustomCaseInsensitive = DesignSystemCatalog.byId(
        'CUSTOM:ACME',
        customPresets: <DesignSystemPreset>[customOverride, customExtra],
      );
      expect(resolvedCustomCaseInsensitive, same(customExtra));
    });
  });

  group('Polices embarquées, intégrité typographique des 24 DESIGN.md et rendu SuperValue', () {
    test('Registry déclare Cascadia Mono et les 7 familles embarquées avec leurs fichiers .ttf valides dans pubspec.yaml', () async {
      const expectedBundled = <String>{
        'Inter',
        'Plus Jakarta Sans',
        'Geist',
        'Geist Mono',
        'JetBrains Mono',
        'Rubik',
        'Nunito',
      };
      expect(Registry.bundledPackageFontFamilies, expectedBundled);
      expect(Registry.defaultAvailableFontFamilies, contains('Cascadia Mono'));
      expect(
        Registry.defaultAvailableFontFamilies,
        containsAll(Registry.bundledPackageFontFamilies),
      );

      final pubspecFile = _resolvePackageFile('pubspec.yaml');
      expect(
        pubspecFile.existsSync(),
        isTrue,
        reason: 'pubspec.yaml introuvable (${pubspecFile.path})',
      );

      final pubspecYaml = loadYaml(await pubspecFile.readAsString()) as YamlMap;
      final flutterSection = pubspecYaml['flutter'] as YamlMap;
      final fontsList = flutterSection['fonts'] as YamlList;

      final declaredFamilies = <String>{};
      for (final rawEntry in fontsList) {
        final entry = rawEntry as YamlMap;
        final family = (entry['family'] as String).trim();
        declaredFamilies.add(family);

        final assets = entry['fonts'] as YamlList;
        expect(
          assets,
          isNotEmpty,
          reason: 'Aucun fichier .ttf déclaré pour la famille "$family"',
        );

        for (final rawAsset in assets) {
          final assetMap = rawAsset as YamlMap;
          final assetPath = (assetMap['asset'] as String).trim();
          expect(
            assetPath.toLowerCase(),
            endsWith('.ttf'),
            reason: 'Extension .ttf attendue pour $assetPath ($family)',
          );
          final ttfFile = _resolvePackageFile(assetPath);
          expect(
            ttfFile.existsSync(),
            isTrue,
            reason: 'Fichier police introuvable sur disque : ${ttfFile.path}',
          );
          expect(
            ttfFile.lengthSync(),
            greaterThan(40 * 1024),
            reason:
                'Fichier police trop petit (<= 40 Ko) pour $assetPath (${ttfFile.lengthSync()} octets)',
          );
        }
      }

      expect(
        declaredFamilies,
        containsAll(Registry.bundledPackageFontFamilies),
      );
      expect(declaredFamilies, Registry.bundledPackageFontFamilies);
    });

    test('aucune police absente ou propriétaire dans les 24 fichiers DESIGN.md ni dans DesignSystemCatalog.builtInPresets', () async {
      const forbiddenFonts = <String>[
        'SF Pro',
        'SF Mono',
        'Circular',
        'Source Code Pro',
        'Cal Sans',
        'Fira Code',
        'IBM Plex',
      ];
      final frontmatterBlockPattern = RegExp(r'^---\s*\r?\n([\s\S]*?)\r?\n---');
      final frontmatterFontPattern = RegExp(
        r'''^\s*fontFamily\s*:\s*['"]?([^'"\r\n]+?)['"]?\s*$''',
        multiLine: true,
      );
      final jsonFontPattern = RegExp(r'"fontFamily"\s*:\s*"([^"]*)"');
      final inlineFontPattern = RegExp(r'\bfontFamily\s*:\s*"([^"]*)"');

      final assetsDir = Directory(
        _resolvePackageFile('assets/design_systems').path,
      );
      final mdFilesOnDisk = assetsDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.md'))
          .toList();
      expect(mdFilesOnDisk, hasLength(24));

      for (final preset in DesignSystemCatalog.builtInPresets) {
        final slug = preset.assetSlug!;
        final mdFile = _resolveDesignSystemAssetFile(slug);
        final rawMarkdown = await mdFile.readAsString();
        final lowerMarkdown = rawMarkdown.toLowerCase();
        final lowerFontHint = preset.palette.fontHint.toLowerCase();

        for (final forbidden in forbiddenFonts) {
          final needle = forbidden.toLowerCase();
          expect(
            lowerFontHint.contains(needle),
            isFalse,
            reason:
                'Police indisponible/propriétaire "$forbidden" trouvée dans preset.palette.fontHint de ${preset.id} ("${preset.palette.fontHint}")',
          );
          expect(
            lowerMarkdown.contains(needle),
            isFalse,
            reason:
                'Police indisponible/propriétaire "$forbidden" trouvée dans $slug.md',
          );
        }

        final frontmatterMatch = frontmatterBlockPattern.firstMatch(
          rawMarkdown,
        );
        expect(
          frontmatterMatch,
          isNotNull,
          reason: 'Frontmatter YAML attendu dans $slug.md',
        );
        final frontmatterText = frontmatterMatch!.group(1)!;
        final fmFontMatches = frontmatterFontPattern
            .allMatches(frontmatterText)
            .toList();
        expect(
          fmFontMatches,
          isNotEmpty,
          reason: 'Clé fontFamily attendue dans le frontmatter de $slug.md',
        );
        for (final match in fmFontMatches) {
          final fmFont = match.group(1)!.trim();
          if (fmFont.isEmpty) continue;
          expect(
            Registry.defaultAvailableFontFamilies,
            contains(fmFont),
            reason:
                'Frontmatter fontFamily "$fmFont" dans $slug.md absente de Registry.defaultAvailableFontFamilies',
          );
        }

        final bodyText = DesignMdParser.extractBodyOrFull(rawMarkdown);
        final jsonFontMatches = jsonFontPattern.allMatches(bodyText).toList();
        expect(
          jsonFontMatches,
          isNotEmpty,
          reason: 'Au moins un exemple JSON "fontFamily" attendu dans $slug.md',
        );
        for (final match in jsonFontMatches) {
          final fontName = match.group(1)!.trim();
          if (fontName.isEmpty) continue;
          expect(
            Registry.defaultAvailableFontFamilies,
            contains(fontName),
            reason:
                'JSON "fontFamily": "$fontName" dans $slug.md absente de Registry.defaultAvailableFontFamilies',
          );
        }

        for (final match in inlineFontPattern.allMatches(bodyText)) {
          final fontName = match.group(1)!.trim();
          if (fontName.isEmpty) continue;
          expect(
            Registry.defaultAvailableFontFamilies,
            contains(fontName),
            reason:
                'Occurrence fontFamily: "$fontName" dans $slug.md absente de Registry.defaultAvailableFontFamilies',
          );
        }
      }
    });

    test('Registry.resolveEffectiveFontFamily préfixe les polices du package et préserve les polices système', () {
      for (final family in const <String>[
        'Inter',
        'Plus Jakarta Sans',
        'Geist',
        'Geist Mono',
        'JetBrains Mono',
        'Rubik',
        'Nunito',
      ]) {
        expect(
          Registry.resolveEffectiveFontFamily(family),
          'packages/super_container_layout/$family',
          reason: 'Préfixe package attendu pour "$family"',
        );
      }

      expect(Registry.resolveEffectiveFontFamily('Segoe UI'), 'Segoe UI');
      expect(
        Registry.resolveEffectiveFontFamily('Cascadia Mono'),
        'Cascadia Mono',
      );
      expect(Registry.resolveEffectiveFontFamily(null), isNull);
      expect(Registry.resolveEffectiveFontFamily(''), '');
    });

    testWidgets(
      'SuperValue résout le fontFamily effectif du package pour Inter et direct pour Cascadia Mono sans altérer SuperValueConfig',
      (tester) async {
        final appearanceController = ValueNotifier<Appearance>(Appearance());
        final editController = ValueNotifier<bool>(true);
        addTearDown(appearanceController.dispose);
        addTearDown(editController.dispose);

        const interConfig = SuperValueConfig(
          initialText: 'Titre Inter',
          fontFamily: 'Inter',
        );
        const cascadiaConfig = SuperValueConfig(
          initialText: 'Code Cascadia',
          fontFamily: 'Cascadia Mono',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AppearanceScope(
              controller: appearanceController,
              child: StyleEditScope(
                controller: editController,
                child: const Scaffold(
                  body: Column(
                    children: [
                      SuperValue(
                        id: 'val-inter',
                        config: interConfig,
                        availableFontFamilies:
                            Registry.defaultAvailableFontFamilies,
                      ),
                      SuperValue(
                        id: 'val-cascadia',
                        config: cascadiaConfig,
                        availableFontFamilies:
                            Registry.defaultAvailableFontFamilies,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(interConfig.fontFamily, 'Inter');
        expect(cascadiaConfig.fontFamily, 'Cascadia Mono');
        expect(find.textContaining('Police indisponible'), findsNothing);

        final interDisplayFinder = find.byKey(
          const ValueKey<String>('super-value-display-val-inter'),
        );
        final interText = tester.widget<Text>(interDisplayFinder);
        expect(
          interText.style?.fontFamily,
          'packages/super_container_layout/Inter',
        );
        final interRichText = tester.widget<RichText>(
          find.descendant(
            of: interDisplayFinder,
            matching: find.byType(RichText),
          ),
        );
        expect(
          interRichText.text.style?.fontFamily,
          'packages/super_container_layout/Inter',
        );

        final cascadiaDisplayFinder = find.byKey(
          const ValueKey<String>('super-value-display-val-cascadia'),
        );
        final cascadiaText = tester.widget<Text>(cascadiaDisplayFinder);
        expect(cascadiaText.style?.fontFamily, 'Cascadia Mono');
        final cascadiaRichText = tester.widget<RichText>(
          find.descendant(
            of: cascadiaDisplayFinder,
            matching: find.byType(RichText),
          ),
        );
        expect(cascadiaRichText.text.style?.fontFamily, 'Cascadia Mono');
      },
    );
  });
}
