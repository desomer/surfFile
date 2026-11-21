/// Exportateur et importateur multi-formats (JSON, Markdown, CSV) du glossaire d'entreprise ([CompanyGlossaryCodec]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';

import '../../models/company_glossary.dart';
import '../company_glossary_store.dart';

/// Résumé d'aperçu calculé avant d'importer un glossaire dans le référentiel existant.
@immutable
class CompanyGlossaryImportPreview {
  /// Construit un aperçu de fusion.
  CompanyGlossaryImportPreview({
    required this.mergedGlossary,
    List<CompanyGlossaryTerm> addedTerms = const <CompanyGlossaryTerm>[],
    List<CompanyGlossaryTerm> updatedTerms = const <CompanyGlossaryTerm>[],
    this.unchangedCount = 0,
    this.addedConventionsCount = 0,
    this.addedAmbiguousCount = 0,
  }) : addedTerms = List<CompanyGlossaryTerm>.unmodifiable(addedTerms),
       updatedTerms = List<CompanyGlossaryTerm>.unmodifiable(updatedTerms);

  /// Glossaire résultant prêt à être appliqué.
  final CompanyGlossary mergedGlossary;

  /// Nouveaux termes qui seront ajoutés.
  final List<CompanyGlossaryTerm> addedTerms;

  /// Termes existants qui seront enrichis ou mis à jour.
  final List<CompanyGlossaryTerm> updatedTerms;

  /// Nombre de termes déjà identiques ignorés.
  final int unchangedCount;

  /// Nombre de conventions ajoutées.
  final int addedConventionsCount;

  /// Nombre de points d'ambiguïté ajoutés.
  final int addedAmbiguousCount;

  /// Nombre total de changements sur les termes.
  bool get hasChanges =>
      addedTerms.isNotEmpty ||
      updatedTerms.isNotEmpty ||
      addedConventionsCount > 0 ||
      addedAmbiguousCount > 0;
}

/// Sérialise et désérialise le [CompanyGlossary] aux formats JSON, Markdown et CSV.
abstract final class CompanyGlossaryCodec {
  static const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

  /// Exporte [glossary] en JSON formaté compatible ré-import.
  static String toJsonString(CompanyGlossary glossary) =>
      _prettyJson.convert(<String, Object?>{
        'format': CompanyGlossaryStore.glossaryFormat,
        'version': CompanyGlossaryStore.storageVersion,
        'data': glossary.toJson(),
      });

  /// Exporte [glossary] en document Markdown structuré.
  static String toMarkdown(CompanyGlossary glossary) {
    final buf = StringBuffer()
      ..writeln('# Glossaire d’entreprise')
      ..writeln()
      ..writeln('> Référentiel terminologique partagé — SuperSpecForge')
      ..writeln(
        '> ${glossary.terms.length} terme(s) '
        '(${glossary.countByStatus(CompanyGlossaryStatus.approved)} validé(s), '
        '${glossary.countByStatus(CompanyGlossaryStatus.draft)} brouillon(s), '
        '${glossary.countByStatus(CompanyGlossaryStatus.deprecated)} déprécié(s))'
        '${glossary.updatedAt != null ? ' · Dernière mise à jour : ${_formatDateTime(glossary.updatedAt!)}' : ''}',
      )
      ..writeln();

    if (!glossary.hasContent) {
      buf.writeln('_Aucun terme défini dans le glossaire d’entreprise._');
      return buf.toString();
    }

    if (glossary.terms.isNotEmpty) {
      buf
        ..writeln(
          '| Terme | Statut | Domaine | Définition | Synonymes | Termes à proscrire | Référent | Nom technique | Ajouté le | Modifié le |',
        )
        ..writeln('|---|---|---|---|---|---|---|---|---|---|');
      for (final t in glossary.terms) {
        buf.writeln(
          '| **${_escMd(t.term)}** '
          '| ${_escMd(t.status.label)} '
          '| ${_escMd(_dashIfEmpty(t.domain))} '
          '| ${_escMd(_dashIfEmpty(t.definition))} '
          '| ${_escMd(t.synonyms.isEmpty ? '—' : t.synonyms.join(', '))} '
          '| ${_escMd(t.forbiddenTerms.isEmpty ? '—' : t.forbiddenTerms.join(', '))} '
          '| ${_escMd(_dashIfEmpty(t.owner))} '
          '| ${_escMd(_dashIfEmpty(t.technicalNameHint))} '
          '| ${t.createdAt != null ? _formatDateTime(t.createdAt!) : '—'} '
          '| ${t.updatedAt != null ? _formatDateTime(t.updatedAt!) : '—'} |',
        );
      }
      buf.writeln();
    }

    if (glossary.conventions.isNotEmpty) {
      buf.writeln('## Conventions de nommage & unités');
      for (final c in glossary.conventions) {
        buf.writeln('- $c');
      }
      buf.writeln();
    }

    if (glossary.ambiguousTerms.isNotEmpty) {
      buf.writeln('## Termes ambigus & points d’attention');
      for (final a in glossary.ambiguousTerms) {
        buf.writeln('- $a');
      }
      buf.writeln();
    }

    return buf.toString();
  }

  /// Exporte les termes de [glossary] en CSV RFC 4180 (séparateur `,`, listes jointes par `; `).
  static String toCsv(CompanyGlossary glossary) {
    final buf = StringBuffer()
      ..writeln(
        'term,status,domain,definition,synonyms,forbiddenTerms,owner,technicalNameHint,examples,createdAt,updatedAt',
      );
    for (final t in glossary.terms) {
      final cells = <String>[
        t.term,
        t.status.name,
        t.domain,
        t.definition,
        t.synonyms.join('; '),
        t.forbiddenTerms.join('; '),
        t.owner,
        t.technicalNameHint,
        t.examples.join(' | '),
        t.createdAt?.toUtc().toIso8601String() ?? '',
        t.updatedAt?.toUtc().toIso8601String() ?? '',
      ];
      buf.writeln(cells.map(_csvEscape).join(','));
    }
    return buf.toString();
  }

  /// Parse une chaîne JSON (format enveloppé, [CompanyGlossary] brut ou `SpecLexicon`).
  static CompanyGlossary parseJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Le contenu JSON est vide.');
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is List) {
      return CompanyGlossary(
        terms: [for (final item in decoded) CompanyGlossaryTerm.fromJson(item)],
      );
    }
    if (decoded is! Map) {
      throw const FormatException(
        'Le fichier JSON doit contenir un objet ou une liste de termes.',
      );
    }
    final payload = decoded['data'] is Map ? decoded['data'] : decoded;
    return CompanyGlossary.fromJson(payload);
  }

  /// Parse un CSV (séparateur `,` ou `;`, avec ligne d'en-têtes).
  static CompanyGlossary parseCsv(String raw) {
    var content = raw;
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }
    final rows = _parseCsvRows(content);
    if (rows.isEmpty) {
      throw const FormatException('Le fichier CSV est vide.');
    }

    final delimiterHeader = rows.first;
    final headers = <String>[
      for (final h in delimiterHeader) _normalizeHeader(h),
    ];

    final termIdx = _findHeaderIndex(headers, [
      'term',
      'terme',
      'name',
      'nom',
      'libelle',
    ]);
    if (termIdx < 0) {
      throw const FormatException(
        'Colonne « term » ou « terme » introuvable dans l’en-tête CSV.',
      );
    }
    final statusIdx = _findHeaderIndex(headers, ['status', 'statut']);
    final domainIdx = _findHeaderIndex(headers, ['domain', 'domaine']);
    final defIdx = _findHeaderIndex(headers, ['definition', 'description']);
    final synIdx = _findHeaderIndex(headers, ['synonyms', 'synonymes']);
    final forbIdx = _findHeaderIndex(headers, [
      'forbiddenterms',
      'forbidden',
      'termesaproscrire',
      'proscrits',
      'interdits',
    ]);
    final ownerIdx = _findHeaderIndex(headers, [
      'owner',
      'referent',
      'responsable',
    ]);
    final techIdx = _findHeaderIndex(headers, [
      'technicalnamehint',
      'technicalname',
      'nomtechnique',
    ]);
    final exIdx = _findHeaderIndex(headers, ['examples', 'exemples']);
    final createdIdx = _findHeaderIndex(headers, [
      'createdat',
      'dateajout',
      'datedajout',
      'datedecreation',
      'datecreation',
    ]);
    final updatedIdx = _findHeaderIndex(headers, [
      'updatedat',
      'datemodification',
      'datedemodification',
      'datemaj',
    ]);

    String cell(List<String> row, int idx) =>
        (idx >= 0 && idx < row.length) ? row[idx].trim() : '';

    final terms = <CompanyGlossaryTerm>[];
    final seenIds = <String>{};
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((c) => c.trim().isEmpty)) continue;
      final termText = cell(row, termIdx);
      if (termText.isEmpty) continue;
      var id = _slugId(termText);
      while (!seenIds.add(id)) {
        id = '${id}_${shortid.generate().substring(0, 4)}';
      }
      final rawCreated = cell(row, createdIdx);
      final rawUpdated = cell(row, updatedIdx);
      terms.add(
        CompanyGlossaryTerm(
          id: id,
          term: termText,
          status: statusIdx >= 0
              ? CompanyGlossaryStatus.fromJson(cell(row, statusIdx))
              : CompanyGlossaryStatus.draft,
          domain: cell(row, domainIdx),
          definition: cell(row, defIdx),
          synonyms: _splitList(cell(row, synIdx)),
          forbiddenTerms: _splitList(cell(row, forbIdx)),
          owner: cell(row, ownerIdx),
          technicalNameHint: cell(row, techIdx),
          examples: _splitList(cell(row, exIdx), splitPipe: true),
          createdAt: rawCreated.isEmpty
              ? null
              : DateTime.tryParse(rawCreated)?.toUtc(),
          updatedAt: rawUpdated.isEmpty
              ? null
              : DateTime.tryParse(rawUpdated)?.toUtc(),
        ),
      );
    }
    if (terms.isEmpty) {
      throw const FormatException('Aucun terme valide trouvé dans le CSV.');
    }
    return CompanyGlossary(terms: terms, updatedAt: DateTime.now().toUtc());
  }

  /// Calcule la prévisualisation de fusion entre [current] et [incoming].
  static CompanyGlossaryImportPreview previewMerge({
    required CompanyGlossary current,
    required CompanyGlossary incoming,
    bool replaceAll = false,
  }) {
    final now = DateTime.now().toUtc();
    if (replaceAll) {
      final normalizedTerms = [
        for (final t in incoming.terms)
          t.copyWith(createdAt: t.createdAt ?? now, updatedAt: now),
      ];
      return CompanyGlossaryImportPreview(
        mergedGlossary: CompanyGlossary(
          terms: normalizedTerms,
          conventions: incoming.conventions,
          ambiguousTerms: incoming.ambiguousTerms,
          updatedAt: now,
        ),
        addedTerms: normalizedTerms,
        addedConventionsCount: incoming.conventions.length,
        addedAmbiguousCount: incoming.ambiguousTerms.length,
      );
    }

    final merged = List<CompanyGlossaryTerm>.from(current.terms);
    final indexById = <String, int>{
      for (var i = 0; i < merged.length; i++) merged[i].id.toLowerCase(): i,
    };
    final indexByTerm = <String, int>{
      for (var i = 0; i < merged.length; i++) merged[i].term.toLowerCase(): i,
    };

    final added = <CompanyGlossaryTerm>[];
    final updated = <CompanyGlossaryTerm>[];
    var unchanged = 0;

    for (final inc in incoming.terms) {
      final existingIdx =
          indexById[inc.id.toLowerCase()] ??
          indexByTerm[inc.term.trim().toLowerCase()];
      if (existingIdx == null) {
        final uniqueId = indexById.containsKey(inc.id.toLowerCase())
            ? 'cg_${shortid.generate()}'
            : inc.id;
        final created = inc.copyWith(
          id: uniqueId,
          createdAt: inc.createdAt ?? now,
          updatedAt: now,
        );
        indexById[created.id.toLowerCase()] = merged.length;
        indexByTerm[created.term.toLowerCase()] = merged.length;
        merged.add(created);
        added.add(created);
      } else {
        final prev = merged[existingIdx];
        final next = prev.copyWith(
          term: inc.term.trim().isNotEmpty ? inc.term.trim() : prev.term,
          definition: inc.definition.trim().isNotEmpty
              ? inc.definition.trim()
              : prev.definition,
          synonyms: [...prev.synonyms, ...inc.synonyms],
          forbiddenTerms: [...prev.forbiddenTerms, ...inc.forbiddenTerms],
          domain: inc.domain.trim().isNotEmpty ? inc.domain.trim() : prev.domain,
          owner: inc.owner.trim().isNotEmpty ? inc.owner.trim() : prev.owner,
          technicalNameHint: inc.technicalNameHint.trim().isNotEmpty
              ? inc.technicalNameHint.trim()
              : prev.technicalNameHint,
          examples: [...prev.examples, ...inc.examples],
          status: inc.status,
          updatedAt: prev.updatedAt,
        );
        if (next == prev) {
          unchanged++;
        } else {
          final stamped = next.copyWith(
            createdAt: prev.createdAt ?? inc.createdAt ?? now,
            updatedAt: now,
          );
          merged[existingIdx] = stamped;
          updated.add(stamped);
        }
      }
    }

    final existingConventions = {
      for (final c in current.conventions) c.toLowerCase(),
    };
    final nextConventions = [...current.conventions];
    var addedConventions = 0;
    for (final c in incoming.conventions) {
      if (existingConventions.add(c.toLowerCase())) {
        nextConventions.add(c);
        addedConventions++;
      }
    }

    final existingAmbiguous = {
      for (final a in current.ambiguousTerms) a.toLowerCase(),
    };
    final nextAmbiguous = [...current.ambiguousTerms];
    var addedAmbiguous = 0;
    for (final a in incoming.ambiguousTerms) {
      if (existingAmbiguous.add(a.toLowerCase())) {
        nextAmbiguous.add(a);
        addedAmbiguous++;
      }
    }

    return CompanyGlossaryImportPreview(
      mergedGlossary: CompanyGlossary(
        terms: merged,
        conventions: nextConventions,
        ambiguousTerms: nextAmbiguous,
        updatedAt: (added.isNotEmpty ||
                updated.isNotEmpty ||
                addedConventions > 0 ||
                addedAmbiguous > 0)
            ? now
            : current.updatedAt,
      ),
      addedTerms: added,
      updatedTerms: updated,
      unchangedCount: unchanged,
      addedConventionsCount: addedConventions,
      addedAmbiguousCount: addedAmbiguous,
    );
  }

  static String _escMd(String text) =>
      text.replaceAll('|', r'\|').replaceAll('\n', ' ');

  static String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${pad2(local.day)}/${pad2(local.month)}/${local.year} '
        '${pad2(local.hour)}:${pad2(local.minute)}';
  }

  static String _dashIfEmpty(String text) =>
      text.trim().isEmpty ? '—' : text.trim();

  static String _csvEscape(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.contains(',') ||
        normalized.contains('"') ||
        normalized.contains('\n')) {
      return '"${normalized.replaceAll('"', '""')}"';
    }
    return normalized;
  }

  static String _normalizeHeader(String header) => header
      .trim()
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('à', 'a')
      .replaceAll(RegExp(r'[\s_-]+'), '');

  static int _findHeaderIndex(List<String> headers, List<String> candidates) {
    for (final candidate in candidates) {
      final idx = headers.indexOf(candidate);
      if (idx >= 0) return idx;
    }
    return -1;
  }

  static List<String> _splitList(String raw, {bool splitPipe = false}) {
    if (raw.trim().isEmpty) return const <String>[];
    final pattern = splitPipe ? RegExp(r'[;|]') : RegExp(r'[;,]');
    return [
      for (final part in raw.split(pattern))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static String _slugId(String term) {
    final slug = term
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll(RegExp(r'[ôö]'), 'o')
        .replaceAll(RegExp(r'[ùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isEmpty) return 'cg_${shortid.generate()}';
    return 'cg_$slug';
  }

  static List<List<String>> _parseCsvRows(String input) {
    final firstLineEnd = input.indexOf('\n');
    final firstLine =
        firstLineEnd >= 0 ? input.substring(0, firstLineEnd) : input;
    final delimiter = _detectCsvDelimiter(firstLine);

    final rows = <List<String>>[];
    var currentRow = <String>[];
    final currentCell = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            currentCell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          currentCell.write(ch);
        }
      } else {
        if (ch == '"' && currentCell.isEmpty) {
          inQuotes = true;
        } else if (ch == delimiter) {
          currentRow.add(currentCell.toString());
          currentCell.clear();
        } else if (ch == '\r') {
          if (i + 1 < input.length && input[i + 1] == '\n') {
            i++;
          }
          currentRow.add(currentCell.toString());
          currentCell.clear();
          rows.add(currentRow);
          currentRow = <String>[];
        } else if (ch == '\n') {
          currentRow.add(currentCell.toString());
          currentCell.clear();
          rows.add(currentRow);
          currentRow = <String>[];
        } else {
          currentCell.write(ch);
        }
      }
    }
    if (currentCell.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentCell.toString());
      rows.add(currentRow);
    }
    return rows;
  }

  static String _detectCsvDelimiter(String headerLine) {
    var commas = 0;
    var semicolons = 0;
    var inQuotes = false;
    for (var i = 0; i < headerLine.length; i++) {
      final ch = headerLine[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes) {
        if (ch == ',') commas++;
        if (ch == ';') semicolons++;
      }
    }
    return semicolons > commas ? ';' : ',';
  }
}
