/// Constructeur d'en-tête YAML normalisé et helpers de dates/slugs pour les
/// prompts IA générés par `BuildHexaPromptGenerator`.
library;

import '../../../models/build_design_item.dart';
import '../../../models/domain_catalog.dart';
import 'prompt_generator_models.dart';

/// Dates ISO (`YYYY-MM-DD`) de création et de mise à jour d'un prompt.
typedef PromptMetadataDates = ({String created, String updated});

/// Utilitaires de construction et d'extraction de l'en-tête ```` ```yaml ... ``` ````.
abstract final class PromptYamlHeaderBuilder {
  static final RegExp _yamlNumericPattern = RegExp(
    r'^[+-]?(\d+(\.\d*)?|\.\d+)$',
  );
  static const Set<String> _yamlReservedScalars = <String>{
    'true',
    'false',
    'null',
    'yes',
    'no',
    'on',
    'off',
    '~',
  };

  /// Segment de rôle en `kebab-case`.
  static String roleSlug(BuildHexaPromptRole role) => switch (role) {
    BuildHexaPromptRole.implementation => 'implementation',
    BuildHexaPromptRole.unitTest => 'unit-test',
    BuildHexaPromptRole.persistence => 'persistence',
  };

  /// Identifiant canonique `kind` en `kebab-case` (ex. `model-implementation`).
  static String kindFor(
    BuildDesignItemKind itemKind,
    BuildHexaPromptRole role,
  ) {
    final prefix = switch (itemKind) {
      BuildDesignItemKind.model => 'model',
      BuildDesignItemKind.useCase => 'usecase',
      BuildDesignItemKind.saga => 'saga',
    };
    return '$prefix-${roleSlug(role)}';
  }

  /// Construit le slug `name` d'un prompt à partir du nom technique et du rôle.
  static String buildPromptSlug(String rawName, BuildHexaPromptRole role) {
    final base = toKebabSlug(rawName);
    final slugRole = roleSlug(role);
    return base.isEmpty ? slugRole : '$base-$slugRole';
  }

  /// Convertit une chaîne libre ou PascalCase/camelCase en `kebab-case`.
  static String toKebabSlug(String raw) {
    final spaced = raw
        .trim()
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}-${m[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'),
          (m) => '${m[1]}-${m[2]}',
        );
    return spaced
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Extrait le contenu YAML brut du bloc ```` ```yaml ... ``` ```` en tête
  /// de [promptMarkdown], ou `null` s'il est absent.
  static String? extractYamlHeader(String promptMarkdown) {
    final normalized = promptMarkdown.replaceAll('\r\n', '\n').trimLeft();
    if (!normalized.startsWith('```yaml\n')) return null;
    final endIdx = normalized.indexOf('\n```', 8);
    if (endIdx < 0) return null;
    return normalized.substring(8, endIdx);
  }

  /// Résout les dates `created` et `updated` (`YYYY-MM-DD`) à partir du journal
  /// d'audit et de l'horodatage de mise à jour du [catalog].
  static PromptMetadataDates resolveMetadataDates({
    required FunctionalDomain domain,
    DomainCatalog? catalog,
    DateTime? referenceDate,
  }) {
    final fallback = (referenceDate ?? DateTime.now()).toUtc();
    final domainLogs =
        catalog?.auditLog
            .where((entry) => entry.domainId == domain.id)
            .toList(growable: false) ??
        const <AuditLogEntry>[];
    var createdDt = fallback;
    var updatedDt = catalog?.updatedAt ?? fallback;
    if (domainLogs.isNotEmpty) {
      createdDt = domainLogs
          .map((e) => e.recordedAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final latestLog = domainLogs
          .map((e) => e.recordedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (catalog?.updatedAt == null || latestLog.isAfter(updatedDt)) {
        updatedDt = latestLog;
      }
    }
    if (updatedDt.isBefore(createdDt)) {
      updatedDt = createdDt;
    }
    return (
      created: _formatIsoDate(createdDt),
      updated: _formatIsoDate(updatedDt),
    );
  }

  /// Construit le bloc Markdown ```` ```yaml ... ``` ```` placé en début de prompt.
  static String buildFencedYamlHeader({
    required String kind,
    required String name,
    required String title,
    required String version,
    required String domainCode,
    required String description,
    required List<String> tags,
    required Map<String, String> generation,
    required PromptMetadataDates dates,
  }) {
    final cleanTags = _dedupKebabTags(tags);
    final buf = StringBuffer()
      ..writeln('```yaml')
      ..writeln('kind: ${_yamlScalar(kind)}')
      ..writeln()
      ..writeln('name: ${_yamlScalar(name)}')
      ..writeln('title: ${_yamlScalar(title)}')
      ..writeln('version: ${_yamlScalar(version)}')
      ..writeln()
      ..writeln('domain: ${_yamlScalar(domainCode)}')
      ..writeln()
      ..writeln('description:')
      ..writeln('    ${_yamlScalar(_stripMarkdownFormatting(description))}')
      ..writeln()
      ..writeln('owner: ${_yamlScalar('$domainCode-team')}')
      ..writeln('status: approved')
      ..writeln()
      ..writeln('tags:');
    for (final tag in cleanTags) {
      buf.writeln('    - ${_yamlScalar(tag)}');
    }
    buf
      ..writeln()
      ..writeln('security:')
      ..writeln('    classification: internal')
      ..writeln()
      ..writeln('ai:')
      ..writeln('    searchable: true')
      ..writeln('    embeddable: true')
      ..writeln()
      ..writeln('generation:');
    for (final entry in generation.entries) {
      if (entry.value.trim().isNotEmpty) {
        buf.writeln('    ${entry.key}: ${_yamlScalar(entry.value)}');
      }
    }
    buf
      ..writeln()
      ..writeln('metadata:')
      ..writeln('    created: ${_yamlScalar(dates.created)}')
      ..writeln('    updated: ${_yamlScalar(dates.updated)}')
      ..write('```');
    return buf.toString();
  }

  static List<String> _dedupKebabTags(Iterable<String> rawTags) {
    final seen = <String>{};
    final out = <String>[];
    for (final tag in rawTags) {
      final clean = toKebabSlug(tag);
      if (clean.isNotEmpty && seen.add(clean)) {
        out.add(clean);
      }
    }
    return out;
  }

  static String _stripMarkdownFormatting(String raw) =>
      raw.replaceAll('`', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _yamlScalar(String raw) {
    final clean = raw.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (clean.isEmpty) return '""';
    final needsQuotes =
        _yamlReservedScalars.contains(clean.toLowerCase()) ||
        _yamlNumericPattern.hasMatch(clean) ||
        clean.startsWith('-') ||
        clean.startsWith('?') ||
        clean.contains(': ') ||
        clean.endsWith(':') ||
        clean.contains('#') ||
        clean.contains('"') ||
        clean.contains("'") ||
        clean.contains(r'\') ||
        clean.contains('[') ||
        clean.contains(']') ||
        clean.contains('{') ||
        clean.contains('}') ||
        clean.contains('&') ||
        clean.contains('*') ||
        clean.contains('!') ||
        clean.contains('|') ||
        clean.contains('>') ||
        clean.contains('%') ||
        clean.contains('@') ||
        clean.contains('`');
    if (!needsQuotes) return clean;
    final escaped = clean.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }

  static String _formatIsoDate(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
