/// Extracteur de familles de polices depuis une charte `DESIGN.md` ou un `fontHint`.
///
/// Analyse le frontmatter YAML, le champ `fontHint`, les extraits JSON (`"fontFamily"`),
/// les déclarations CSS (`font-family`), les URLs Google Fonts et les tableaux Markdown
/// de typographie tout en éliminant les descripteurs génériques non téléchargeables.
library;

import 'package:yaml/yaml.dart' show YamlList, YamlMap, loadYaml;

/// Utilitaire statique d'extraction des noms de polices d'un système de design `DESIGN.md`.
abstract final class DesignMdFontExtractor {
  static final RegExp _frontmatterPattern = RegExp(
    r'^---\s*\r?\n([\s\S]*?)\r?\n---\s*(?:\r?\n|$)',
  );

  static final RegExp _googleFontsUrlPattern = RegExp(
    r'fonts\.googleapis\.com/css2?\?[^\s"\x27`<>)\]]+',
    caseSensitive: false,
  );

  static final RegExp _jsonFontFamilyPattern = RegExp(
    r'"fontFamily"\s*:\s*"([^"\r\n]{1,64})"',
  );

  static final RegExp _cssFontFamilyPattern = RegExp(
    r'font-family\s*:\s*([^;\r\n}`]{1,160})',
    caseSensitive: false,
  );

  static final RegExp _markdownFontQuotePattern = RegExp(
    r'(?:\*\*`?"?|`?"?)([A-Z][A-Za-z0-9]+(?:\s+[A-Z0-9][A-Za-z0-9]*){0,3})(?:"?`?\*\*|"?`?)',
  );

  static final RegExp _parentheticalPattern = RegExp(r'\([^)]*\)');
  static final RegExp _validFamilyPattern = RegExp(
    r"^[A-Za-z][A-Za-z0-9\s\-']{1,48}$",
  );

  static const Set<String> _ignoredGenericNames = {
    'sans',
    'sans-serif',
    'sans serif',
    'serif',
    'monospace',
    'mono',
    'cursive',
    'fantasy',
    'system-ui',
    'ui-sans-serif',
    'ui-serif',
    'ui-monospace',
    'ui-rounded',
    '-apple-system',
    'blinkmacsystemfont',
    'inherit',
    'initial',
    'unset',
    'default',
    'auto',
    'none',
    'normal',
    'regular',
    'medium',
    'semibold',
    'semi-bold',
    'bold',
    'light',
    'thin',
    'italic',
    'oblique',
    'display',
    'display bold',
    'body',
    'heading',
    'headings',
    'caption',
    'label',
    'code',
    'text',
    'title',
    'subtitle',
    'material 3',
    'material',
    'sans franc',
    'sans doux',
    'sans neo-banque',
    'sans néo-banque',
    'serif editorial',
    'serif éditorial',
    'editorial serif',
    'geometric sans',
    'humanist sans',
    'neo-grotesque',
    'grotesque',
    'clean sans',
    'modern sans',
    'police du theme',
    'police du thème',
    'theme',
    'font',
    'fontfamily',
    'font family',
    'usage',
    'niveau',
    'color',
    'couleur',
    'size',
    'taille',
    'weight',
    'graisse',
  };

  /// Retourne `true` si [raw] correspond à un descripteur générique ou non téléchargeable.
  static bool isGenericOrIgnoredFontName(String raw) {
    final cleaned = cleanFontFamilyToken(raw);
    if (cleaned == null) return true;
    final lower = cleaned.toLowerCase();
    if (_ignoredGenericNames.contains(lower)) return true;
    if (lower.startsWith('theme:')) return true;
    if (lower.startsWith('var(')) return true;
    return false;
  }

  /// Nettoie un jeton de police brut (guillemets, backticks, parenthèses, préfixe package).
  ///
  /// Retourne `null` si le résultat est vide ou syntaxiquement invalide.
  static String? cleanFontFamilyToken(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;

    // Retire le préfixe interne Flutter `packages/<pkg>/`.
    if (value.startsWith('packages/')) {
      final parts = value.split('/');
      if (parts.length >= 3) {
        value = parts.sublist(2).join('/');
      }
    }

    // Retire les commentaires entre parenthèses (ex. "Inter (corps)").
    value = value.replaceAll(_parentheticalPattern, ' ');

    // Retire les décorations Markdown / guillemets en bordure.
    value = value
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll('`', '')
        .trim();
    while (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    }
    value = value
        .replaceAll(RegExp(r'^[\s"\x27•\-–—:;,.]+'), '')
        .replaceAll(RegExp(r'[\s"\x27:;,.]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (value.length < 2 || value.length > 50) return null;
    if (!_validFamilyPattern.hasMatch(value)) return null;
    return value;
  }

  /// Extrait toutes les familles de polices distinctes référencées par [fontHint] et/ou [markdown].
  ///
  /// L'ordre d'apparition est conservé (frontmatter / `fontHint` en priorité, puis URLs
  /// Google Fonts, extraits JSON, déclarations CSS et tableaux Markdown de typographie).
  static List<String> extractFontFamilies({
    String? fontHint,
    String? markdown,
  }) {
    final result = <String>[];
    final seenLower = <String>{};

    void addCandidate(String raw) {
      final cleaned = cleanFontFamilyToken(raw);
      if (cleaned == null) return;
      if (isGenericOrIgnoredFontName(cleaned)) return;
      final key = cleaned.toLowerCase();
      if (seenLower.add(key)) {
        result.add(cleaned);
      }
    }

    void addSplitCandidates(String raw) {
      for (final part in raw.split(RegExp(r'[/,+&|]'))) {
        addCandidate(part);
      }
    }

    if (fontHint != null && fontHint.trim().isNotEmpty) {
      addSplitCandidates(fontHint);
    }

    if (markdown != null && markdown.trim().isNotEmpty) {
      final normalized = markdown.startsWith('\uFEFF')
          ? markdown.substring(1)
          : markdown;

      // 1. Frontmatter YAML (`fontFamily`, `fontHint`, `headingFont`, `bodyFont`, `monoFont`, `fonts`).
      final fmMatch = _frontmatterPattern.firstMatch(normalized);
      if (fmMatch != null) {
        _extractFromFrontmatter(
          fmMatch.group(1) ?? '',
          addCandidate: addCandidate,
          addSplitCandidates: addSplitCandidates,
        );
      }

      // 2. URLs Google Fonts explicites (`fonts.googleapis.com/css2?family=...`).
      for (final match in _googleFontsUrlPattern.allMatches(normalized)) {
        final rawUrl = match.group(0)!;
        final uri = Uri.tryParse('https://$rawUrl');
        if (uri == null) continue;
        final families = uri.queryParametersAll['family'] ?? const <String>[];
        for (final entry in families) {
          // CSS2 : `Space Grotesk:wght@400;700`, CSS1 : `Open Sans|Roboto:400`
          for (final segment in entry.split('|')) {
            final familyName = segment.split(':').first.replaceAll('+', ' ');
            addCandidate(familyName);
          }
        }
      }

      // 3. Snippets JSON `"fontFamily": "..."`.
      for (final match in _jsonFontFamilyPattern.allMatches(normalized)) {
        addSplitCandidates(match.group(1)!);
      }

      // 4. Déclarations CSS `font-family: 'Space Grotesk', Inter, sans-serif;`.
      for (final match in _cssFontFamilyPattern.allMatches(normalized)) {
        final rawList = match.group(1)!;
        for (final part in rawList.split(',')) {
          addCandidate(part);
        }
      }

      // 5. Tableaux Markdown dans les sections Typographie ayant une colonne `fontFamily` / `Font` / `Police`.
      _extractFromTypographyTables(
        normalized,
        addSplitCandidates: addSplitCandidates,
      );
    }

    return List<String>.unmodifiable(result);
  }

  static void _extractFromFrontmatter(
    String rawYaml, {
    required void Function(String) addCandidate,
    required void Function(String) addSplitCandidates,
  }) {
    try {
      final sanitized = rawYaml.replaceAllMapped(
        RegExp(
          r'^(\s*[A-Za-z0-9_-]+\s*:\s*)(#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3}))\s*$',
          multiLine: true,
        ),
        (m) => '${m.group(1)}"${m.group(2)}"',
      );
      final parsed = loadYaml(sanitized);
      if (parsed is! YamlMap) return;
      const keys = <String>[
        'fontFamily',
        'fontHint',
        'font',
        'headingFont',
        'displayFont',
        'bodyFont',
        'monoFont',
        'codeFont',
        'fonts',
        'fontFamilies',
      ];
      for (final entry in parsed.entries) {
        final key = entry.key.toString().trim();
        final matchKey = keys.any(
          (candidate) => candidate.toLowerCase() == key.toLowerCase(),
        );
        if (!matchKey) continue;
        final value = entry.value;
        if (value is YamlList) {
          for (final item in value) {
            if (item != null) addSplitCandidates(item.toString());
          }
        } else if (value is String) {
          addSplitCandidates(value);
        } else if (value is YamlMap) {
          for (final nested in value.values) {
            if (nested is String) addSplitCandidates(nested);
          }
        }
      }
    } catch (_) {
      // Ignore les erreurs YAML pour rester tolérant sur un DESIGN.md libre.
    }
  }

  static void _extractFromTypographyTables(
    String markdown, {
    required void Function(String) addSplitCandidates,
  }) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    var inCodeFence = false;
    int? fontColIndex;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.startsWith('```')) {
        inCodeFence = !inCodeFence;
        fontColIndex = null;
        continue;
      }
      if (inCodeFence) continue;
      if (!line.startsWith('|')) {
        fontColIndex = null;
        continue;
      }

      final cells = line
          .split('|')
          .map((c) => c.trim())
          .toList(growable: false);
      if (cells.length < 3) continue;
      // Ignore les cellules vides de bord dues aux `|` initiaux/finaux.
      final inner = cells.sublist(
        cells.first.isEmpty ? 1 : 0,
        cells.last.isEmpty ? cells.length - 1 : cells.length,
      );
      if (inner.isEmpty) continue;

      // Ligne séparateur `| :--- | :--- |`
      if (inner.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) {
        continue;
      }

      if (fontColIndex == null) {
        for (var i = 0; i < inner.length; i++) {
          final header = inner[i]
              .replaceAll('`', '')
              .replaceAll('*', '')
              .trim()
              .toLowerCase();
          if (header == 'fontfamily' ||
              header == 'font' ||
              header == 'font family' ||
              header == 'police' ||
              header == 'typeface') {
            fontColIndex = i;
            break;
          }
        }
        continue;
      }

      if (fontColIndex < inner.length) {
        final cell = inner[fontColIndex];
        // Extrait les jetons cités ou séparés par `/`.
        final quoted = _markdownFontQuotePattern.allMatches(cell).toList();
        if (quoted.isNotEmpty) {
          for (final m in quoted) {
            addSplitCandidates(m.group(1)!);
          }
        } else {
          addSplitCandidates(cell);
        }
      }
    }
  }
}
