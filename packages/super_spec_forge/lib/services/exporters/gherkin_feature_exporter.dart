/// Exportateur déterministe de spécifications exécutables Gherkin `.feature` ([GherkinFeatureExporter]).
library;

import '../../models/qa/gherkin_feature_spec.dart';
import '../../models/qa/qa_forge_stage.dart';
import '../../models/spec_forge_project.dart';
import '../spec_storage_slug.dart';

/// Formate les fonctionnalités [GherkinFeatureSpec] en fichiers `.feature` conformes
/// au standard Cucumber / Gherkin (français `# language: fr` ou anglais `# language: en`).
abstract final class GherkinFeatureExporter {
  /// Exporte une [feature] unique en syntaxe Gherkin officielle pour [language].
  static String exportFeature(
    GherkinFeatureSpec feature, {
    GherkinKeywordLanguage language = GherkinKeywordLanguage.fr,
  }) {
    final buf = StringBuffer()
      ..writeln(language.gherkinHeader)
      ..writeln();

    final featureTags = _collectFeatureTags(feature);
    if (featureTags.isNotEmpty) {
      buf.writeln(featureTags.join(' '));
    }

    buf.writeln('${language.featureKeyword}: ${_singleLine(feature.title)}');

    if (feature.narrative.trim().isNotEmpty) {
      final lines = feature.narrative
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n');
      for (final rawLine in lines) {
        final trimmed = rawLine.trim();
        if (trimmed.isEmpty) {
          buf.writeln();
        } else {
          buf.writeln('  $trimmed');
        }
      }
    }

    if (feature.backgroundSteps.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('  ${language.backgroundKeyword}:');
      for (final step in feature.backgroundSteps) {
        _writeStep(buf, step, language: language, indent: '    ');
      }
    }

    for (final scenario in feature.scenarios) {
      buf.writeln();
      final scenarioTags = _collectScenarioTags(scenario);
      if (scenarioTags.isNotEmpty) {
        buf.writeln('  ${scenarioTags.join(' ')}');
      }

      final scenarioKeyword = scenario.isOutline
          ? language.scenarioOutlineKeyword
          : language.scenarioKeyword;
      buf.writeln('  $scenarioKeyword: ${_singleLine(scenario.title)}');

      for (final step in scenario.steps) {
        _writeStep(buf, step, language: language, indent: '    ');
      }

      if (scenario.isOutline && scenario.examples.headers.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('    ${language.examplesKeyword}:');
        _writeAlignedPipeTable(
          buf,
          rows: <List<String>>[
            scenario.examples.headers,
            ...scenario.examples.rows,
          ],
          indent: '      ',
        );
      }
    }

    return SpecStorageIo.normalizeLf('${buf.toString().trimRight()}\n');
  }

  /// Assigne des noms de fichiers `<slug>.feature` uniques et déterministes à toutes
  /// les fonctionnalités Gherkin de [project] et retourne la carte ordonnée `fileName -> contenu`.
  static Map<String, String> exportAllFeatures(
    SpecForgeProject project, {
    GherkinKeywordLanguage? languageOverride,
  }) {
    final language = languageOverride ?? project.qaSpec.gherkinLanguage;
    final assigned = assignFeatureFileNames(project.qaSpec.features);
    final result = <String, String>{
      for (final entry in assigned.entries)
        entry.key: exportFeature(entry.value, language: language),
    };
    return Map<String, String>.unmodifiable(result);
  }

  /// Concatène l'ensemble des fichiers `.feature` de [project] avec des bannières
  /// `# ═══ features/<filename> ═══` pour la prévisualisation unifiée dans l'atelier.
  static String exportCombinedPreview(
    SpecForgeProject project, {
    GherkinKeywordLanguage? languageOverride,
  }) {
    final files = exportAllFeatures(
      project,
      languageOverride: languageOverride,
    );
    if (files.isEmpty) {
      final lang = languageOverride ?? project.qaSpec.gherkinLanguage;
      return '${lang.gherkinHeader}\n# Aucune fonctionnalité Gherkin (.feature) définie pour « ${project.name} ».\n';
    }

    final buf = StringBuffer();
    var first = true;
    for (final entry in files.entries) {
      if (!first) {
        buf.writeln();
      }
      first = false;
      buf
        ..writeln('# ═══ features/${entry.key} ═══')
        ..write(entry.value);
    }
    return SpecStorageIo.normalizeLf(buf.toString());
  }

  /// Assigne des noms de fichiers `<slug>.feature` uniques et déterministes à [features].
  static Map<String, GherkinFeatureSpec> assignFeatureFileNames(
    Iterable<GherkinFeatureSpec> features,
  ) {
    final result = <String, GherkinFeatureSpec>{};
    final usedLower = <String>{};

    for (final feature in features) {
      final rawCode = feature.code.trim();
      final label =
          rawCode.isNotEmpty && rawCode.toUpperCase() != 'FEAT'
          ? '$rawCode ${feature.title.trim()}'
          : feature.title.trim();
      final base = SpecStorageSlug.slugify(label, fallback: 'feature');
      var candidate = '$base.feature';
      if (!usedLower.add(candidate.toLowerCase())) {
        final suffix = SpecStorageSlug.shortSuffixFromId(feature.id);
        candidate = '${base}__$suffix.feature';
        var index = 2;
        while (!usedLower.add(candidate.toLowerCase())) {
          candidate = '${base}__${suffix}_$index.feature';
          index++;
        }
      }
      result[candidate] = feature;
    }
    return Map<String, GherkinFeatureSpec>.unmodifiable(result);
  }

  static List<String> _collectFeatureTags(GherkinFeatureSpec feature) {
    final out = <String>[];
    final seenLower = <String>{};

    void pushTag(String raw) {
      final normalized = GherkinFeatureSpec.normalizeTag(raw);
      if (normalized.isEmpty) return;
      if (seenLower.add(normalized.toLowerCase())) {
        out.add(normalized);
      }
    }

    final trimmedCode = feature.code.trim();
    if (trimmedCode.isNotEmpty && trimmedCode.toUpperCase() != 'FEAT') {
      pushTag('@${SpecStorageSlug.slugify(trimmedCode, fallback: 'feat')}');
    }
    for (final tag in feature.tags) {
      pushTag(tag);
    }
    return out;
  }

  static List<String> _collectScenarioTags(GherkinScenarioSpec scenario) {
    final out = <String>[];
    final seenLower = <String>{};

    void pushTag(String raw) {
      final normalized = GherkinScenarioSpec.normalizeTag(raw);
      if (normalized.isEmpty) return;
      if (seenLower.add(normalized.toLowerCase())) {
        out.add(normalized);
      }
    }

    final trimmedCode = scenario.code.trim();
    if (trimmedCode.isNotEmpty && trimmedCode.toUpperCase() != 'SCN') {
      pushTag('@${SpecStorageSlug.slugify(trimmedCode, fallback: 'scn')}');
    }
    for (final tag in scenario.tags) {
      pushTag(tag);
    }
    return out;
  }

  static void _writeStep(
    StringBuffer buf,
    GherkinStep step, {
    required GherkinKeywordLanguage language,
    required String indent,
  }) {
    buf.writeln(
      '$indent${step.keyword.keywordFor(language)} ${_singleLine(step.text)}',
    );
    final childIndent = '$indent  ';

    if (step.docString.trim().isNotEmpty) {
      buf.writeln('$childIndent"""');
      final lines = step.docString
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n');
      for (final line in lines) {
        final escaped = line.replaceAll('"""', r'\"\"\"');
        if (escaped.isEmpty) {
          buf.writeln();
        } else {
          buf.writeln('$childIndent$escaped');
        }
      }
      buf.writeln('$childIndent"""');
    }

    if (step.dataTable.isNotEmpty) {
      _writeAlignedPipeTable(buf, rows: step.dataTable, indent: childIndent);
    }
  }

  static void _writeAlignedPipeTable(
    StringBuffer buf, {
    required List<List<String>> rows,
    required String indent,
  }) {
    if (rows.isEmpty) return;
    var colCount = 0;
    for (final row in rows) {
      if (row.length > colCount) {
        colCount = row.length;
      }
    }
    if (colCount == 0) return;

    final escapedMatrix = <List<String>>[
      for (final row in rows)
        <String>[
          for (var c = 0; c < colCount; c++)
            c < row.length ? _escapePipeCell(row[c]) : '',
        ],
    ];

    final widths = List<int>.filled(colCount, 0);
    for (final row in escapedMatrix) {
      for (var c = 0; c < colCount; c++) {
        final len = row[c].length;
        if (len > widths[c]) {
          widths[c] = len;
        }
      }
    }

    for (final row in escapedMatrix) {
      final paddedCells = <String>[
        for (var c = 0; c < colCount; c++) row[c].padRight(widths[c]),
      ];
      buf.writeln('$indent| ${paddedCells.join(' | ')} |');
    }
  }

  static String _escapePipeCell(String raw) => raw
      .replaceAll(r'\', r'\\')
      .replaceAll('|', r'\|')
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .trim();

  static String _singleLine(String raw) =>
      raw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
}
