/// Analyseur tolérant de fichiers `DESIGN.md` ([DesignMdParser]) pour le catalogue Vibe IA.
///
/// Convertit aussi bien un document `DESIGN.md` muni d'un frontmatter YAML structuré
/// qu'un fichier brut issu de Google Stitch ou de `getdesign.md` en un [DesignSystemPreset]
/// complet avec aperçu [DesignSystemPalettePreview] et système de surface [DesignSystem].
library;

import 'package:material_ui/material_ui.dart' show Color, HSLColor, ThemeMode;
import 'package:yaml/yaml.dart' show YamlList, YamlMap, loadYaml;

import '../theme/design_system.dart';
import 'design_system_catalog.dart';

/// Analyseur statique de chartes `DESIGN.md` (frontmatter YAML et heuristiques Markdown).
abstract final class DesignMdParser {
  static final RegExp _frontmatterPattern = RegExp(
    r'^---\s*\r?\n([\s\S]*?)\r?\n---\s*(?:\r?\n|$)',
  );

  static final RegExp _unquotedHexYamlLine = RegExp(
    r'^(\s*[A-Za-z0-9_-]+\s*:\s*)(#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3}))\s*$',
    multiLine: true,
  );

  static final RegExp _hexColorPattern = RegExp(
    r'#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b',
  );

  static final RegExp _h1Pattern = RegExp(
    r'^\s*#\s+(.+?)\s*$',
    multiLine: true,
  );

  static final RegExp _designAnalysisSuffix = RegExp(
    r'[-_\s]+design[-_\s]+analysis$',
    caseSensitive: false,
  );

  /// Retire l'éventuel bloc de frontmatter YAML (`--- ... ---`) en tête de [markdown].
  static String stripFrontmatter(String markdown) {
    final normalized = _stripBom(markdown);
    final match = _frontmatterPattern.firstMatch(normalized);
    if (match == null) return normalized.trim();
    return normalized.substring(match.end).trim();
  }

  /// Retourne le corps Markdown sans frontmatter s'il n'est pas vide, sinon [markdown] nettoyé.
  static String extractBodyOrFull(String markdown) {
    final normalized = _stripBom(markdown).trim();
    if (normalized.isEmpty) return '';
    final stripped = stripFrontmatter(normalized);
    return stripped.isNotEmpty ? stripped : normalized;
  }

  /// Analyse un contenu `DESIGN.md` externe et construit un [DesignSystemPreset] prêt à l'emploi.
  ///
  /// Lève une [FormatException] si [markdown] est vide ou ne contient que des espaces.
  static DesignSystemPreset parseExternal(
    String markdown, {
    String? fileName,
    String? idOverride,
  }) {
    final cleanedMarkdown = _stripBom(markdown).trim();
    if (cleanedMarkdown.isEmpty) {
      throw const FormatException(
        'Le contenu DESIGN.md ne peut pas être vide.',
      );
    }

    final (:frontmatter, :body) = _splitFrontmatter(cleanedMarkdown);
    final effectiveBody = body.isNotEmpty ? body : cleanedMarkdown;

    final rawName = _stringFromMap(frontmatter, const ['name', 'title']);
    final name = _resolveName(
      frontmatterName: rawName,
      body: effectiveBody,
      fileName: fileName,
    );

    final explicitSlug = _stringFromMap(frontmatter, const ['slug', 'id']);
    final resolvedId = _resolveId(
      idOverride: idOverride,
      explicitSlug: explicitSlug,
      name: name,
    );

    final rawCategory = _stringFromMap(frontmatter, const ['category']);
    final category = rawCategory == null
        ? DesignSystemCategory.custom
        : DesignSystemCategory.fromId(
            rawCategory,
            fallback: DesignSystemCategory.custom,
          );

    final overviewParagraph = _extractOverviewParagraph(effectiveBody);
    final description =
        _cleanInlineMarkdown(
          _stringFromMap(frontmatter, const ['description', 'summary']) ?? '',
        ).ifEmpty(
          overviewParagraph.ifEmpty(
            'Système de design importé depuis DESIGN.md pour guider la génération Vibe IA.',
          ),
        );

    final tagline = _cleanInlineMarkdown(
      _stringFromMap(frontmatter, const ['tagline', 'subtitle']) ?? '',
    ).ifEmpty(_summarizeTagline(description));

    final extractedColors = _extractBodyColorRoles(effectiveBody);

    final explicitAccent = _colorFromMap(frontmatter, const [
      'accent',
      'accentColor',
      'primary',
      'primaryColor',
      'brandColor',
    ]);
    final explicitCanvas = _colorFromMap(frontmatter, const [
      'canvasColor',
      'canvas',
      'backgroundColor',
      'background',
    ]);
    final explicitSurface = _colorFromMap(frontmatter, const [
      'surfaceColor',
      'surface',
      'cardColor',
    ]);
    final explicitText = _colorFromMap(frontmatter, const [
      'textColor',
      'textPrimary',
      'foreground',
      'foregroundColor',
    ]);
    final explicitMuted = _colorFromMap(frontmatter, const [
      'mutedTextColor',
      'textMuted',
      'secondaryTextColor',
    ]);
    final explicitBorder = _colorFromMap(frontmatter, const [
      'borderColor',
      'border',
      'dividerColor',
    ]);

    final candidateCanvas = explicitCanvas ?? extractedColors.canvas;
    final candidateSurface = explicitSurface ?? extractedColors.surface;

    final mode = _resolveThemeMode(
      explicitMode: _stringFromMap(frontmatter, const [
        'mode',
        'theme',
        'colorScheme',
      ]),
      canvas: candidateCanvas,
      surface: candidateSurface,
      body: effectiveBody,
    );

    final isDark = mode == ThemeMode.dark;
    final canvas = _ensureReadableCanvas(candidateCanvas, isDark: isDark);
    final surface = _ensureReadableSurface(
      candidateSurface,
      canvas: canvas,
      isDark: isDark,
    );
    final textPrimary = _ensureReadablePrimaryText(
      explicitText ?? extractedColors.textPrimary,
      canvas: canvas,
      isDark: isDark,
    );
    final textMuted = _ensureReadableMutedText(
      explicitMuted ?? extractedColors.textMuted,
      canvas: canvas,
      isDark: isDark,
    );
    final border =
        explicitBorder ??
        extractedColors.border ??
        (isDark ? const Color(0xFF252A36) : const Color(0xFFE2E8F0));
    final accent = _resolveAccentColor(
      explicitAccent: explicitAccent,
      heuristicAccent: extractedColors.accent,
      allBodyColors: extractedColors.allColors,
      canvas: canvas,
      isDark: isDark,
    );

    final cardRadius = _resolveCardRadius(
      frontmatterValue:
          frontmatter['cardRadius'] ??
          frontmatter['radius'] ??
          frontmatter['borderRadius'],
      body: effectiveBody,
    );

    final surfaceSystem = _resolveSurfaceSystem(
      explicitSystem: _stringFromMap(frontmatter, const [
        'surfaceSystem',
        'designSystem',
      ]),
      body: effectiveBody,
    );

    final fontHint = _resolveFontHint(
      explicitFont: _stringFromMap(frontmatter, const [
        'fontFamily',
        'fontHint',
        'font',
      ]),
      body: effectiveBody,
    );

    final tags = _resolveTags(
      rawTags: frontmatter['tags'] ?? frontmatter['keywords'],
      name: name,
      mode: mode,
      surfaceSystem: surfaceSystem,
    );

    return DesignSystemPreset(
      id: resolvedId,
      name: name,
      category: category,
      tagline: tagline,
      description: description,
      palette: DesignSystemPalettePreview(
        mode: mode,
        accent: accent,
        canvas: canvas,
        surface: surface,
        textPrimary: textPrimary,
        textMuted: textMuted,
        border: border,
        cardRadius: cardRadius,
        surfaceSystem: surfaceSystem,
        fontHint: fontHint,
      ),
      inlineMarkdown: cleanedMarkdown,
      tags: tags,
    );
  }

  static String _stripBom(String input) =>
      input.startsWith('\uFEFF') ? input.substring(1) : input;

  static ({Map<String, Object?> frontmatter, String body}) _splitFrontmatter(
    String markdown,
  ) {
    final match = _frontmatterPattern.firstMatch(markdown);
    if (match == null) {
      return (frontmatter: const <String, Object?>{}, body: markdown);
    }

    final rawYaml = match.group(1) ?? '';
    final body = markdown.substring(match.end).trim();
    final sanitizedYaml = rawYaml.replaceAllMapped(
      _unquotedHexYamlLine,
      (m) => '${m.group(1)}"${m.group(2)}"',
    );

    final map = <String, Object?>{};
    try {
      final parsed = loadYaml(sanitizedYaml);
      if (parsed is YamlMap) {
        for (final entry in parsed.entries) {
          final key = entry.key?.toString().trim();
          if (key != null && key.isNotEmpty) {
            map[key] = entry.value;
          }
        }
      }
    } catch (_) {
      for (final rawLine in sanitizedYaml.split(RegExp(r'\r?\n'))) {
        final colon = rawLine.indexOf(':');
        if (colon <= 0) continue;
        final key = rawLine.substring(0, colon).trim();
        var value = rawLine.substring(colon + 1).trim();
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        if (key.isNotEmpty && value.isNotEmpty) {
          map[key] = value;
        }
      }
    }
    return (frontmatter: map, body: body);
  }

  static String? _stringFromMap(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final direct = map[key];
      if (direct != null) {
        final text = direct.toString().trim();
        if (text.isNotEmpty) return text;
      }
      final lowerKey = key.toLowerCase();
      for (final entry in map.entries) {
        if (entry.key.toLowerCase() == lowerKey && entry.value != null) {
          final text = entry.value.toString().trim();
          if (text.isNotEmpty) return text;
        }
      }
    }
    return null;
  }

  static Color? _colorFromMap(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      Object? rawValue = map[key];
      if (rawValue == null) {
        final lowerKey = key.toLowerCase();
        for (final entry in map.entries) {
          if (entry.key.toLowerCase() == lowerKey && entry.value != null) {
            rawValue = entry.value;
            break;
          }
        }
      }
      if (rawValue == null) continue;
      if (rawValue is int && rawValue >= 0 && rawValue <= 0xFFFFFFFF) {
        return Color(0xFF000000 | (rawValue & 0xFFFFFF));
      }
      final parsed = _tryParseFlexibleColor(rawValue.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  static String _resolveName({
    required String? frontmatterName,
    required String body,
    required String? fileName,
  }) {
    if (frontmatterName != null && frontmatterName.trim().isNotEmpty) {
      final cleaned = _cleanPresetName(frontmatterName);
      if (cleaned.isNotEmpty) return cleaned;
    }

    final h1Match = _h1Pattern.firstMatch(body);
    if (h1Match != null) {
      final rawHeading = _cleanInlineMarkdown(h1Match.group(1) ?? '');
      final cleanedHeading = _cleanHeadingTitle(rawHeading);
      if (cleanedHeading.isNotEmpty) return cleanedHeading;
    }

    if (fileName != null && fileName.trim().isNotEmpty) {
      final stem = _extractFileStem(fileName);
      if (stem.isNotEmpty) return stem;
    }

    return 'Design personnalisé';
  }

  static String _cleanPresetName(String raw) {
    var cleaned = _cleanInlineMarkdown(raw)
        .replaceAll(_designAnalysisSuffix, '')
        .trim();
    if (cleaned.isEmpty) return '';

    final looksLikeLowerSlug =
        cleaned == cleaned.toLowerCase() &&
        RegExp(r'^[a-z0-9._-]+$').hasMatch(cleaned) &&
        !cleaned.contains('.');
    if (looksLikeLowerSlug) {
      return _humanizeSlug(cleaned);
    }
    return cleaned;
  }

  static String _cleanHeadingTitle(String heading) {
    var text = heading.replaceAll(_designAnalysisSuffix, '').trim();
    final prefixPatterns = <RegExp>[
      RegExp(
        r'^(?:design\s+system|système\s+de\s+design)\s*[:—–-]\s*',
        caseSensitive: false,
      ),
      RegExp(r'^design\s+analysis\s*[:—–-]\s*', caseSensitive: false),
    ];
    for (final pattern in prefixPatterns) {
      text = text.replaceFirst(pattern, '').trim();
    }
    text = text
        .replaceFirst(
          RegExp(r'\s*[:—–-]\s*design\.md$', caseSensitive: false),
          '',
        )
        .trim();
    final strippedSuffix = text
        .replaceFirst(RegExp(r'\s+design\s+system$', caseSensitive: false), '')
        .trim();
    if (strippedSuffix.isNotEmpty &&
        strippedSuffix.toLowerCase() != 'design' &&
        strippedSuffix.toLowerCase() != 'system') {
      text = strippedSuffix;
    }
    if (text.toLowerCase() == 'design.md' ||
        text.toLowerCase() == 'design system' ||
        text.toLowerCase() == 'design') {
      return '';
    }
    return text;
  }

  static String _extractFileStem(String fileName) {
    final normalized = fileName.replaceAll('\\', '/');
    var base = normalized.split('/').last.trim();
    base = base.replaceFirst(
      RegExp(r'\.(?:markdown|md|txt)$', caseSensitive: false),
      '',
    );
    base = base.replaceAll(_designAnalysisSuffix, '');
    base = base.replaceFirst(
      RegExp(r'^(?:design[-_\s]*system[-_\s]*)', caseSensitive: false),
      '',
    );
    base = base.replaceFirst(
      RegExp(r'(?:[-_\s]*design)$', caseSensitive: false),
      '',
    );
    final lower = base.trim().toLowerCase();
    if (lower.isEmpty ||
        const <String>{
          'design',
          'design_system',
          'design-system',
          'readme',
          'presse-papiers',
          'clipboard',
        }.contains(lower)) {
      return '';
    }
    return _humanizeSlug(base.trim());
  }

  static String _humanizeSlug(String slug) {
    final parts = slug
        .split(RegExp(r'[-_\s]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .toList(growable: false);
    return parts.join(' ');
  }

  static String _slugify(String input) {
    final normalized = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâäãå]'), 'a')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[òóôöõ]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'design-personnalise' : normalized;
  }

  static String _resolveId({
    required String? idOverride,
    required String? explicitSlug,
    required String name,
  }) {
    if (idOverride != null && idOverride.trim().isNotEmpty) {
      return idOverride.trim();
    }
    if (explicitSlug != null && explicitSlug.trim().isNotEmpty) {
      final cleanSlug = _slugify(
        explicitSlug.replaceAll(_designAnalysisSuffix, ''),
      );
      return cleanSlug;
    }
    return 'custom:${_slugify(name)}';
  }

  static String _extractOverviewParagraph(String body) {
    final lines = body.split(RegExp(r'\r?\n'));
    var inPreferredSection = false;
    var sawAnyH2 = false;
    final preferredBuffer = <String>[];
    final fallbackBuffer = <String>[];

    var inCodeFence = false;
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.startsWith('```')) {
        inCodeFence = !inCodeFence;
        continue;
      }
      if (inCodeFence) continue;

      if (line.startsWith('## ')) {
        if (preferredBuffer.isNotEmpty) break;
        sawAnyH2 = true;
        final heading = line.substring(3).toLowerCase();
        inPreferredSection =
            heading.contains('overview') ||
            heading.contains('visual theme') ||
            heading.contains('atmosphere') ||
            heading.contains('philosophy') ||
            heading.contains('aperçu') ||
            heading.contains('atmosphère') ||
            heading.startsWith('1.');
        continue;
      }

      if (line.isEmpty) {
        if (inPreferredSection && preferredBuffer.isNotEmpty) break;
        if (!sawAnyH2 && fallbackBuffer.isNotEmpty) continue;
        continue;
      }

      if (line.startsWith('#') ||
          line.startsWith('|') ||
          line.startsWith('---') ||
          line.startsWith('- ') ||
          line.startsWith('* ')) {
        continue;
      }

      final cleaned = _cleanInlineMarkdown(
        line.replaceFirst(RegExp(r'^>\s*'), ''),
      );
      if (cleaned.length < 16) continue;

      if (inPreferredSection) {
        preferredBuffer.add(cleaned);
        if (preferredBuffer.join(' ').length >= 160) break;
      } else if (fallbackBuffer.isEmpty) {
        fallbackBuffer.add(cleaned);
      }
    }

    if (preferredBuffer.isNotEmpty) {
      return preferredBuffer.join(' ');
    }
    return fallbackBuffer.isEmpty ? '' : fallbackBuffer.first;
  }

  static String _summarizeTagline(String description) {
    final cleaned = description.trim();
    if (cleaned.isEmpty) return 'Charte visuelle personnalisée';
    final sentenceEnd = RegExp(r'[.!;](\s|$)').firstMatch(cleaned);
    final firstSentence = sentenceEnd == null
        ? cleaned
        : cleaned.substring(0, sentenceEnd.start).trim();
    final candidate = firstSentence.isNotEmpty ? firstSentence : cleaned;
    if (candidate.length <= 92) return candidate;
    final cut = candidate.substring(0, 89).trimRight();
    final lastSpace = cut.lastIndexOf(' ');
    final safeCut = lastSpace > 45 ? cut.substring(0, lastSpace) : cut;
    return '$safeCut…';
  }

  static String _cleanInlineMarkdown(String text) => text
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAll('`', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static _ExtractedBodyColors _extractBodyColorRoles(String body) {
    Color? accent;
    Color? canvas;
    Color? surface;
    Color? textPrimary;
    Color? textMuted;
    Color? border;
    final allColors = <Color>[];

    var currentH2 = '';
    var currentH3 = '';
    var inCodeFence = false;

    for (final rawLine in body.split(RegExp(r'\r?\n'))) {
      final trimmed = rawLine.trim();
      if (trimmed.startsWith('```')) {
        inCodeFence = !inCodeFence;
        continue;
      }
      if (trimmed.startsWith('## ')) {
        currentH2 = trimmed.substring(3).toLowerCase();
        currentH3 = '';
        continue;
      }
      if (trimmed.startsWith('### ')) {
        currentH3 = trimmed.substring(4).toLowerCase();
        continue;
      }
      if (inCodeFence) continue;

      final matches = _hexColorPattern.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      final colorsOnLine = <Color>[];
      for (final match in matches) {
        final parsed = _tryParseHexColor(match.group(0)!);
        if (parsed != null) {
          colorsOnLine.add(parsed);
          if (!allColors.contains(parsed)) {
            allColors.add(parsed);
          }
        }
      }
      if (colorsOnLine.isEmpty) continue;

      final firstMatch = matches.first;
      final firstColor = colorsOnLine.first;
      final prefixLabel = trimmed.substring(0, firstMatch.start).toLowerCase();
      final suffixLabel = trimmed.substring(firstMatch.end).toLowerCase();
      final primaryLabel = _hasAnyRoleHint(prefixLabel)
          ? prefixLabel
          : suffixLabel;
      final context = '$currentH2 $currentH3 $primaryLabel';

      final isAccentLine =
          _hasAnyKeyword(primaryLabel, const [
            'accent',
            'brand',
            'cta',
            'interactive',
            'primary action',
            'highlight',
            'primary color',
            'couleur principale',
          ]) ||
          (context.contains('brand') && primaryLabel.contains('primary'));
      final isBorderLine =
          !isAccentLine &&
          _hasAnyKeyword(primaryLabel, const [
            'border',
            'divider',
            'hairline',
            'stroke',
            'outline',
            'separator',
            'bordure',
            'séparateur',
          ]);
      final isMutedTextLine =
          !isAccentLine &&
          !isBorderLine &&
          _hasAnyKeyword(primaryLabel, const [
            'muted',
            'secondary text',
            'subtle text',
            'tertiary text',
            'caption',
            'placeholder',
            'subtext',
            'helper text',
            'texte secondaire',
            'texte atténué',
            'encre secondaire',
          ]);
      final isPrimaryTextLine =
          !isAccentLine &&
          !isBorderLine &&
          !isMutedTextLine &&
          (_hasAnyKeyword(primaryLabel, const [
                'primary text',
                'main text',
                'body text',
                'heading',
                'foreground',
                'ink',
                'texte principal',
                'encre principale',
                'encre primaire',
              ]) ||
              (currentH3.contains('text') &&
                  _hasAnyKeyword(primaryLabel, const ['primary', 'default'])));
      final isSurfaceLine =
          !isAccentLine &&
          !isBorderLine &&
          !isPrimaryTextLine &&
          !isMutedTextLine &&
          _hasAnyKeyword(primaryLabel, const [
            'surface',
            'card',
            'panel',
            'elevated',
            'container',
            'sidebar',
            'modal',
            'secondary background',
            'subtle background',
            'carte',
            'panneau',
          ]);
      final isCanvasLine =
          !isAccentLine &&
          !isBorderLine &&
          !isSurfaceLine &&
          !isPrimaryTextLine &&
          !isMutedTextLine &&
          _hasAnyKeyword(primaryLabel, const [
            'canvas',
            'page background',
            'app background',
            'primary background',
            'main background',
            'body background',
            'backdrop',
            'fond principal',
            'arrière-plan',
            'background',
          ]);

      if (isAccentLine && accent == null) {
        accent = firstColor;
      } else if (isCanvasLine && canvas == null) {
        canvas = firstColor;
      } else if (isSurfaceLine && surface == null) {
        surface = firstColor;
      } else if (isPrimaryTextLine && textPrimary == null) {
        textPrimary = firstColor;
      } else if (isMutedTextLine && textMuted == null) {
        textMuted = firstColor;
      } else if (isBorderLine && border == null) {
        border = firstColor;
      }
    }

    return _ExtractedBodyColors(
      accent: accent,
      canvas: canvas,
      surface: surface,
      textPrimary: textPrimary,
      textMuted: textMuted,
      border: border,
      allColors: allColors,
    );
  }

  static ThemeMode _resolveThemeMode({
    required String? explicitMode,
    required Color? canvas,
    required Color? surface,
    required String body,
  }) {
    if (explicitMode != null) {
      final lower = explicitMode.trim().toLowerCase();
      if (lower.contains('dark') ||
          lower.contains('sombre') ||
          lower.contains('night')) {
        return ThemeMode.dark;
      }
      if (lower.contains('light') ||
          lower.contains('clair') ||
          lower.contains('day')) {
        return ThemeMode.light;
      }
    }

    if (canvas != null) {
      return canvas.computeLuminance() < 0.25
          ? ThemeMode.dark
          : ThemeMode.light;
    }

    final lowerBody = body.toLowerCase();
    final overviewSlice = lowerBody.length > 2400
        ? lowerBody.substring(0, 2400)
        : lowerBody;

    final darkSignals = const <String>[
      'dark mode',
      'dark-mode',
      'dark theme',
      'dark-first',
      'dark ui',
      'near-black',
      'pure black',
      'pitch black',
      'obsidian',
      'deep charcoal',
      'midnight',
      'mode sombre',
      'thème sombre',
      'fond noir',
      'fond sombre',
    ];
    final lightSignals = const <String>[
      'light mode',
      'light-mode',
      'light theme',
      'light-first',
      'warm paper',
      'pure white',
      'crisp white',
      'airy white',
      'porcelain',
      'daylight',
      'mode clair',
      'thème clair',
      'fond blanc',
      'fond clair',
    ];

    var darkScore = 0;
    for (final signal in darkSignals) {
      if (overviewSlice.contains(signal)) darkScore += 2;
    }
    var lightScore = 0;
    for (final signal in lightSignals) {
      if (overviewSlice.contains(signal)) lightScore += 2;
    }

    if (darkScore != lightScore) {
      return darkScore > lightScore ? ThemeMode.dark : ThemeMode.light;
    }

    if (surface != null) {
      return surface.computeLuminance() < 0.25
          ? ThemeMode.dark
          : ThemeMode.light;
    }

    return ThemeMode.light;
  }

  static Color _ensureReadableCanvas(Color? candidate, {required bool isDark}) {
    if (candidate == null) {
      return isDark ? const Color(0xFF0B0D12) : const Color(0xFFF8FAFC);
    }
    final lum = candidate.computeLuminance();
    if (isDark && lum > 0.45) return const Color(0xFF0B0D12);
    if (!isDark && lum < 0.35) return const Color(0xFFF8FAFC);
    return candidate;
  }

  static Color _ensureReadableSurface(
    Color? candidate, {
    required Color canvas,
    required bool isDark,
  }) {
    if (candidate != null) {
      final lum = candidate.computeLuminance();
      if (isDark && lum <= 0.5) return candidate;
      if (!isDark && lum >= 0.35) return candidate;
    }
    if (isDark) {
      return Color.lerp(canvas, const Color(0xFFFFFFFF), 0.05) ??
          const Color(0xFF151821);
    }
    return canvas.computeLuminance() > 0.96
        ? const Color(0xFFF3F4F6)
        : const Color(0xFFFFFFFF);
  }

  static Color _ensureReadablePrimaryText(
    Color? candidate, {
    required Color canvas,
    required bool isDark,
  }) {
    if (candidate != null) {
      final diff = (candidate.computeLuminance() - canvas.computeLuminance())
          .abs();
      if (diff >= 0.32) return candidate;
    }
    return isDark ? const Color(0xFFF5F7FA) : const Color(0xFF111827);
  }

  static Color _ensureReadableMutedText(
    Color? candidate, {
    required Color canvas,
    required bool isDark,
  }) {
    if (candidate != null) {
      final diff = (candidate.computeLuminance() - canvas.computeLuminance())
          .abs();
      if (diff >= 0.12) return candidate;
    }
    return isDark ? const Color(0xFF8B93A7) : const Color(0xFF64748B);
  }

  static Color _resolveAccentColor({
    required Color? explicitAccent,
    required Color? heuristicAccent,
    required List<Color> allBodyColors,
    required Color canvas,
    required bool isDark,
  }) {
    if (explicitAccent != null &&
        _hasEnoughAccentVisibility(explicitAccent, canvas)) {
      return explicitAccent;
    }
    if (heuristicAccent != null &&
        _hasEnoughAccentVisibility(heuristicAccent, canvas)) {
      return heuristicAccent;
    }

    for (final candidate in allBodyColors) {
      final hsl = HSLColor.fromColor(candidate);
      if (hsl.saturation >= 0.25 &&
          hsl.lightness >= 0.15 &&
          hsl.lightness <= 0.85 &&
          _hasEnoughAccentVisibility(candidate, canvas)) {
        return candidate;
      }
    }

    for (final candidate in allBodyColors) {
      if (_hasEnoughAccentVisibility(candidate, canvas)) {
        final lumDiff =
            (candidate.computeLuminance() - canvas.computeLuminance()).abs();
        if (lumDiff >= 0.35) return candidate;
      }
    }

    return isDark ? const Color(0xFF5E6AD2) : const Color(0xFF2563EB);
  }

  static bool _hasEnoughAccentVisibility(Color accent, Color canvas) {
    final lumDiff = (accent.computeLuminance() - canvas.computeLuminance())
        .abs();
    final saturation = HSLColor.fromColor(accent).saturation;
    if (lumDiff >= 0.14) return true;
    return saturation >= 0.35 && lumDiff >= 0.06;
  }

  static double _resolveCardRadius({
    required Object? frontmatterValue,
    required String body,
  }) {
    if (frontmatterValue is num) {
      return frontmatterValue.toDouble().clamp(0.0, 36.0);
    }
    if (frontmatterValue is String) {
      final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(frontmatterValue);
      if (match != null) {
        final parsed = double.tryParse(match.group(1)!);
        if (parsed != null) return parsed.clamp(0.0, 36.0);
      }
    }

    final lower = body.toLowerCase();
    if (_hasAnyKeyword(lower, const [
      '0px border-radius',
      'border-radius: 0',
      'radius: 0px',
      'zero radius',
      'sharp corners',
      'square corners',
      'pixel-sharp',
      'angles droits',
      'angles vifs',
      'sans arrondi',
    ])) {
      return 0.0;
    }
    if (RegExp(r'\b0px\b').hasMatch(lower) &&
        _hasAnyKeyword(lower, const ['sharp', 'square', 'brutal'])) {
      return 0.0;
    }
    if (_hasAnyKeyword(lower, const ['sharp', 'square']) &&
        !_hasAnyKeyword(lower, const ['rounded', 'pill'])) {
      return 2.0;
    }

    final cardRadiusMatch = RegExp(
      r'(?:card|surface|container|panel|carte)[^\n]{0,48}?(\d{1,2})\s*px',
      caseSensitive: false,
    ).firstMatch(body);
    if (cardRadiusMatch != null) {
      final value = double.tryParse(cardRadiusMatch.group(1)!);
      if (value != null && value <= 28) {
        return value;
      }
    }

    if (_hasAnyKeyword(lower, const [
      'generously rounded',
      'pill',
      'rounded corners',
      'soft rounded',
      'coins arrondis',
    ])) {
      return 16.0;
    }

    return 12.0;
  }

  static DesignSystem _resolveSurfaceSystem({
    required String? explicitSystem,
    required String body,
  }) {
    if (explicitSystem != null) {
      final lower = explicitSystem.trim().toLowerCase();
      if (lower.contains('neumorph')) return DesignSystem.neumorphism;
      if (lower.contains('liquid') || lower.contains('glass')) {
        return DesignSystem.liquidGlass;
      }
      if (lower.contains('material')) return DesignSystem.material;
    }

    final lowerBody = body.toLowerCase();
    if (lowerBody.contains('neumorph')) {
      return DesignSystem.neumorphism;
    }
    if (lowerBody.contains('glassmorphism') ||
        lowerBody.contains('backdrop-filter') ||
        lowerBody.contains('liquidglass') ||
        lowerBody.contains('liquid glass')) {
      return DesignSystem.liquidGlass;
    }
    return DesignSystem.material;
  }

  static String _resolveFontHint({
    required String? explicitFont,
    required String body,
  }) {
    if (explicitFont != null && explicitFont.trim().isNotEmpty) {
      return _cleanInlineMarkdown(explicitFont);
    }

    const knownFonts = <String>[
      'Geist Mono',
      'Geist',
      'JetBrains Mono',
      'SF Pro',
      'SF Mono',
      'Source Code Pro',
      'Fira Code',
      'IBM Plex Mono',
      'IBM Plex Sans',
      'Plus Jakarta Sans',
      'Space Grotesk',
      'Cal Sans',
      'DM Sans',
      'Manrope',
      'Inter',
      'Nunito',
      'Rubik',
      'Poppins',
      'Circular',
      'Segoe UI',
      'Playfair Display',
      'Merriweather',
      'Georgia',
      'Tahoma',
      'Roboto',
    ];

    final detected = <String>[];
    final lower = body.toLowerCase();
    for (final font in knownFonts) {
      if (lower.contains(font.toLowerCase())) {
        detected.add(font);
        if (detected.length == 2) break;
      }
    }
    if (detected.isNotEmpty) {
      return detected.join(' / ');
    }
    if (lower.contains('monospace')) return 'Monospace / Sans';
    if (lower.contains('serif') && !lower.contains('sans-serif')) {
      return 'Serif éditorial';
    }
    return 'Sans-serif';
  }

  static List<String> _resolveTags({
    required Object? rawTags,
    required String name,
    required ThemeMode mode,
    required DesignSystem surfaceSystem,
  }) {
    final result = <String>[];
    void addTag(String raw) {
      final tag = raw.trim().toLowerCase();
      if (tag.isNotEmpty && !result.contains(tag)) {
        result.add(tag);
      }
    }

    if (rawTags is YamlList) {
      for (final item in rawTags) {
        if (item != null) addTag(item.toString());
      }
    } else if (rawTags is Iterable) {
      for (final item in rawTags) {
        if (item != null) addTag(item.toString());
      }
    } else if (rawTags is String) {
      for (final part in rawTags.split(RegExp(r'[,;]'))) {
        addTag(part);
      }
    }

    addTag('custom');
    addTag('design.md');
    addTag(mode == ThemeMode.dark ? 'dark' : 'light');
    if (surfaceSystem != DesignSystem.material) {
      addTag(surfaceSystem.name.toLowerCase());
    }
    addTag(name);
    return List<String>.unmodifiable(result);
  }

  static Color? _tryParseFlexibleColor(String raw) {
    final trimmed = raw.trim();
    final directHex = _tryParseHexColor(trimmed);
    if (directHex != null) return directHex;

    if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
      final hex = trimmed.substring(2);
      if (RegExp(r'^[0-9a-fA-F]{6,8}$').hasMatch(hex)) {
        final value = int.parse(hex, radix: 16);
        return Color(0xFF000000 | (value & 0xFFFFFF));
      }
    }
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(trimmed)) {
      return Color(0xFF000000 | int.parse(trimmed, radix: 16));
    }
    return null;
  }

  static Color? _tryParseHexColor(String raw) {
    final match = _hexColorPattern.firstMatch(raw.trim());
    if (match == null) return null;
    final hex = match.group(1)!;
    if (hex.length == 3) {
      final r = int.parse(hex[0], radix: 16) * 17;
      final g = int.parse(hex[1], radix: 16) * 17;
      final b = int.parse(hex[2], radix: 16) * 17;
      return Color(0xFF000000 | (r << 16) | (g << 8) | b);
    }
    if (hex.length == 6) {
      return Color(0xFF000000 | int.parse(hex, radix: 16));
    }
    if (hex.length == 8) {
      final value = int.parse(hex, radix: 16);
      final rgb = (value >>> 8) & 0xFFFFFF;
      return Color(0xFF000000 | rgb);
    }
    return null;
  }

  static bool _hasAnyRoleHint(String text) => _hasAnyKeyword(text, const [
    'accent',
    'brand',
    'cta',
    'interactive',
    'highlight',
    'canvas',
    'background',
    'backdrop',
    'fond',
    'arrière-plan',
    'surface',
    'card',
    'panel',
    'elevated',
    'container',
    'sidebar',
    'modal',
    'carte',
    'panneau',
    'text',
    'heading',
    'foreground',
    'ink',
    'muted',
    'caption',
    'placeholder',
    'subtext',
    'texte',
    'encre',
    'border',
    'divider',
    'hairline',
    'stroke',
    'outline',
    'separator',
    'bordure',
    'séparateur',
  ]);

  static bool _hasAnyKeyword(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }
}

class _ExtractedBodyColors {
  const _ExtractedBodyColors({
    required this.accent,
    required this.canvas,
    required this.surface,
    required this.textPrimary,
    required this.textMuted,
    required this.border,
    required this.allColors,
  });

  final Color? accent;
  final Color? canvas;
  final Color? surface;
  final Color? textPrimary;
  final Color? textMuted;
  final Color? border;
  final List<Color> allColors;
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
