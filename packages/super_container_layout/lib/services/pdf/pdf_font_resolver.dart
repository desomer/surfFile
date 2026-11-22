/// Résolution et mise en cache des polices PDF ([PdfFontResolver]).
///
/// Charge les polices TrueType libres embarquées dans `assets/fonts/` ainsi que
/// les variantes `.ttf`/`.otf` téléchargées dynamiquement dans [DynamicFontManager]
/// pour produire des documents vectoriels fidèles à l'interface Flutter, avec
/// repli automatique sur les polices standard PDF (`Helvetica`, `Courier`).
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:material_ui/material_ui.dart' show FontStyle, FontWeight;
import 'package:pdf/widgets.dart' as pw;

import '../fonts/dynamic_font_manager.dart';

import '../../models/registry.dart';
import '../diagnostics/debug_entry.dart';
import '../inspection/vibe_debug_capture.dart';

/// Paire de polices PDF (normale, gras, italique, gras-italique) pour un thème.
class PdfResolvedFontFamily {
  /// Crée une famille de polices PDF résolue.
  const PdfResolvedFontFamily({
    required this.base,
    required this.bold,
    required this.italic,
    required this.boldItalic,
    this.fallback = const [],
  });

  /// Police régulière.
  final pw.Font base;

  /// Police grasse.
  final pw.Font bold;

  /// Police italique.
  final pw.Font italic;

  /// Police grasse et italique.
  final pw.Font boldItalic;

  /// Polices de secours si un glyphe est absent.
  final List<pw.Font> fallback;

  /// Sélectionne la variante correspondant à [weight] et [style].
  pw.Font variant({FontWeight? weight, FontStyle? style}) {
    final isBold = (weight?.value ?? 400) >= 600;
    final isItalic = style == FontStyle.italic;
    if (isBold && isItalic) return boldItalic;
    if (isBold) return bold;
    if (isItalic) return italic;
    return base;
  }
}

/// Résout et met en cache les polices [pw.Font] depuis les assets du package
/// et le cache dynamique [DynamicFontManager].
class PdfFontResolver {
  /// Crée un résolveur de polices PDF utilisant [bundle] (par défaut [rootBundle])
  /// et [fontManager] (par défaut [DynamicFontManager.shared]).
  PdfFontResolver({AssetBundle? bundle, DynamicFontManager? fontManager})
    : _bundle = bundle ?? rootBundle,
      _fontManager = fontManager ?? DynamicFontManager.shared;

  final AssetBundle _bundle;
  final DynamicFontManager _fontManager;
  static final Map<String, pw.Font?> _sharedRootFonts = {};
  static final Map<String, PdfResolvedFontFamily> _sharedRootFamilies = {};
  final Map<String, pw.Font?> _loadedFonts = {};
  final Map<String, PdfResolvedFontFamily> _families = {};

  static const Map<String, ({String regular, String italic})> _bundledFiles = {
    'Inter': (
      regular: 'Inter-Variable.ttf',
      italic: 'Inter-Italic-Variable.ttf',
    ),
    'Plus Jakarta Sans': (
      regular: 'PlusJakartaSans-Variable.ttf',
      italic: 'PlusJakartaSans-Italic-Variable.ttf',
    ),
    'Geist': (
      regular: 'Geist-Variable.ttf',
      italic: 'Geist-Italic-Variable.ttf',
    ),
    'Geist Mono': (
      regular: 'GeistMono-Variable.ttf',
      italic: 'GeistMono-Italic-Variable.ttf',
    ),
    'JetBrains Mono': (
      regular: 'JetBrainsMono-Variable.ttf',
      italic: 'JetBrainsMono-Italic-Variable.ttf',
    ),
    'Rubik': (
      regular: 'Rubik-Variable.ttf',
      italic: 'Rubik-Italic-Variable.ttf',
    ),
    'Nunito': (
      regular: 'Nunito-Variable.ttf',
      italic: 'Nunito-Italic-Variable.ttf',
    ),
  };

  static const Set<String> _monoAliases = {
    'Geist Mono',
    'JetBrains Mono',
    'Cascadia Mono',
    'Consolas',
    'Courier New',
    'monospace',
  };

  /// Normalise un nom de famille Flutter (incluant le préfixe `packages/...`).
  static String normalizeFamilyName(String? raw) {
    if (raw == null) return 'Inter';
    var name = raw.trim();
    if (name.isEmpty) return 'Inter';
    const prefix = 'packages/super_container_layout/';
    if (name.startsWith(prefix)) {
      name = name.substring(prefix.length);
    }
    return name;
  }

  /// Charge la famille de polices [familyName] ou fournit un repli propre.
  Future<PdfResolvedFontFamily> resolveFamily(String? familyName) async {
    final normalized = normalizeFamilyName(familyName);
    final useShared =
        identical(_bundle, rootBundle) &&
        identical(_fontManager, DynamicFontManager.shared);
    final familyCache = useShared ? _sharedRootFamilies : _families;

    final isBundled = _bundledFiles.containsKey(normalized);
    if (isBundled) {
      final cached = familyCache[normalized];
      if (cached != null) return cached;
    }

    if (!isBundled) {
      final dynamicVariants = _fontManager.cachedVariantsFor(normalized);
      if (dynamicVariants != null && dynamicVariants.isNotEmpty) {
        final dynamicResolved = _resolveDynamicVariants(
          normalized,
          dynamicVariants,
        );
        if (dynamicResolved != null) {
          familyCache[normalized] = dynamicResolved;
          return dynamicResolved;
        }
      }
    }

    final isMono = _monoAliases.contains(normalized);
    final isKnownFamily =
        isBundled ||
        isMono ||
        Registry.defaultAvailableFontFamilies.contains(normalized);
    final bundledKey = isBundled
        ? normalized
        : (isMono ? 'JetBrains Mono' : 'Inter');
    if (familyName != null && familyName.trim().isNotEmpty && !isKnownFamily) {
      VibeDebugCapture.recordTypedError(
        message:
            '[FONT ERROR] Police PDF indisponible « $normalized » : repli sur « $bundledKey ».',
        category: DebugErrorCategory.font,
        severity: DebugSeverity.warning,
        source: 'PdfFontResolver',
      );
    }
    final files = _bundledFiles[bundledKey];

    pw.Font? regular;
    pw.Font? italic;
    if (files != null) {
      regular = await _loadAssetFont(files.regular);
      italic = await _loadAssetFont(files.italic);
      if (regular == null) {
        VibeDebugCapture.recordTypedError(
          message:
              '[FONT ERROR] Impossible de charger la police TrueType PDF « $bundledKey » (${files.regular}) : repli sur police standard.',
          category: DebugErrorCategory.font,
          severity: DebugSeverity.warning,
          source: 'PdfFontResolver',
        );
      }
    }

    final standardBase = isMono ? pw.Font.courier() : pw.Font.helvetica();
    final standardBold = isMono
        ? pw.Font.courierBold()
        : pw.Font.helveticaBold();
    final standardItalic = isMono
        ? pw.Font.courierOblique()
        : pw.Font.helveticaOblique();
    final standardBoldItalic = isMono
        ? pw.Font.courierBoldOblique()
        : pw.Font.helveticaBoldOblique();

    final resolved = PdfResolvedFontFamily(
      base: regular ?? standardBase,
      bold: regular ?? standardBold,
      italic: italic ?? regular ?? standardItalic,
      boldItalic: italic ?? regular ?? standardBoldItalic,
      fallback: [
        if (regular != null) standardBase,
        pw.Font.helvetica(),
        pw.Font.courier(),
      ],
    );
    if (isBundled) {
      familyCache[normalized] = resolved;
    }
    return resolved;
  }

  PdfResolvedFontFamily? _resolveDynamicVariants(
    String normalized,
    List<CachedFontVariantBytes> variants,
  ) {
    pw.Font? tryBuild(CachedFontVariantBytes? candidate) {
      if (candidate == null) return null;
      try {
        return pw.Font.ttf(ByteData.sublistView(candidate.bytes));
      } catch (_) {
        return null;
      }
    }

    CachedFontVariantBytes? pickBest({
      required bool italic,
      required int targetWeight,
      required bool requireBold,
    }) {
      CachedFontVariantBytes? best;
      var bestDistance = 1 << 30;
      for (final variant in variants) {
        if (variant.meta.italic != italic) continue;
        if (requireBold && variant.meta.weight < 600) continue;
        final distance = (variant.meta.weight - targetWeight).abs();
        if (distance < bestDistance) {
          best = variant;
          bestDistance = distance;
        }
      }
      return best;
    }

    final regularFont =
        tryBuild(
          pickBest(italic: false, targetWeight: 400, requireBold: false),
        ) ??
        tryBuild(variants.first);
    if (regularFont == null) return null;

    final boldFont =
        tryBuild(
          pickBest(italic: false, targetWeight: 700, requireBold: true),
        ) ??
        regularFont;
    final italicFont =
        tryBuild(
          pickBest(italic: true, targetWeight: 400, requireBold: false),
        ) ??
        regularFont;
    final boldItalicFont =
        tryBuild(
          pickBest(italic: true, targetWeight: 700, requireBold: true),
        ) ??
        italicFont;

    final isMono =
        _monoAliases.contains(normalized) ||
        normalized.toLowerCase().contains('mono') ||
        normalized.toLowerCase().contains('code');
    final standardBase = isMono ? pw.Font.courier() : pw.Font.helvetica();

    return PdfResolvedFontFamily(
      base: regularFont,
      bold: boldFont,
      italic: italicFont,
      boldItalic: boldItalicFont,
      fallback: [standardBase, pw.Font.helvetica(), pw.Font.courier()],
    );
  }

  /// Construit un [pw.ThemeData] PDF par défaut pour le document.
  Future<pw.ThemeData> buildDefaultTheme({String? defaultFamily}) async {
    final family = await resolveFamily(defaultFamily);
    return pw.ThemeData.withFont(
      base: family.base,
      bold: family.bold,
      italic: family.italic,
      boldItalic: family.boldItalic,
      fontFallback: family.fallback,
    );
  }

  Future<pw.Font?> _loadAssetFont(String fileName) async {
    final useShared = identical(_bundle, rootBundle);
    final cache = useShared ? _sharedRootFonts : _loadedFonts;
    if (cache.containsKey(fileName)) return cache[fileName];
    for (final path in [
      'packages/super_container_layout/assets/fonts/$fileName',
      'assets/fonts/$fileName',
    ]) {
      try {
        final data = await _bundle.load(path);
        final font = pw.Font.ttf(data);
        cache[fileName] = font;
        return font;
      } catch (_) {
        // Essaie le chemin candidat suivant.
      }
    }
    cache[fileName] = null;
    return null;
  }
}
