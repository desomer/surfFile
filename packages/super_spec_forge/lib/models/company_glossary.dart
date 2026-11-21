/// Modèles immuables du glossaire terminologique d'entreprise ([CompanyGlossary], [CompanyGlossaryTerm], [CompanyGlossaryStatus]).
library;

import 'package:flutter/foundation.dart';

import 'spec_lexicon.dart';

/// Statut de gouvernance d'un terme dans le glossaire d'entreprise.
enum CompanyGlossaryStatus {
  /// Terme en cours de rédaction ou de revue.
  draft('Brouillon'),

  /// Terme officiellement validé comme référence d'entreprise.
  approved('Validé'),

  /// Terme obsolète conservé pour traçabilité (à ne plus utiliser).
  deprecated('Déprécié');

  /// Construit un statut de gouvernance.
  const CompanyGlossaryStatus(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise un statut depuis JSON (avec repli sur [draft]).
  static CompanyGlossaryStatus fromJson(Object? raw) {
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      for (final status in CompanyGlossaryStatus.values) {
        if (status.name.toLowerCase() == normalized ||
            status.label.toLowerCase() == normalized) {
          return status;
        }
      }
      if (normalized == 'valide' || normalized == 'validated') {
        return CompanyGlossaryStatus.approved;
      }
      if (normalized == 'deprecie' || normalized == 'obsolete') {
        return CompanyGlossaryStatus.deprecated;
      }
    }
    return CompanyGlossaryStatus.draft;
  }
}

/// Terme canonique du glossaire d'entreprise, gouverné transversalement aux projets.
@immutable
class CompanyGlossaryTerm {
  /// Construit un terme de glossaire d'entreprise immuable.
  CompanyGlossaryTerm({
    required this.id,
    required this.term,
    this.definition = '',
    List<String> synonyms = const <String>[],
    List<String> forbiddenTerms = const <String>[],
    this.domain = '',
    this.owner = '',
    this.technicalNameHint = '',
    List<String> examples = const <String>[],
    this.status = CompanyGlossaryStatus.draft,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : synonyms = List<String>.unmodifiable(_dedupeStrings(synonyms)),
       forbiddenTerms = List<String>.unmodifiable(
         _dedupeStrings(forbiddenTerms),
       ),
       examples = List<String>.unmodifiable(_dedupeStrings(examples)),
       createdAt = createdAt?.toUtc(),
       updatedAt = updatedAt?.toUtc();

  /// Crée un [CompanyGlossaryTerm] à partir d'un [LexiconTerm] de projet.
  factory CompanyGlossaryTerm.fromLexiconTerm(
    LexiconTerm lexiconTerm, {
    String? idOverride,
    CompanyGlossaryStatus status = CompanyGlossaryStatus.approved,
    String owner = '',
    String technicalNameHint = '',
    List<String> forbiddenTerms = const <String>[],
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return CompanyGlossaryTerm(
      id: (idOverride != null && idOverride.trim().isNotEmpty)
          ? idOverride.trim()
          : lexiconTerm.id,
      term: lexiconTerm.term.trim(),
      definition: lexiconTerm.definition.trim(),
      synonyms: lexiconTerm.synonyms,
      forbiddenTerms: forbiddenTerms,
      domain: lexiconTerm.domain.trim(),
      owner: owner.trim(),
      technicalNameHint: technicalNameHint.trim(),
      examples: lexiconTerm.examples,
      status: status,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// Identifiant technique stable du terme.
  final String id;

  /// Terme canonique officiel retenu à l'échelle de l'entreprise.
  final String term;

  /// Définition métier claire et univoque.
  final String definition;

  /// Synonymes tolérés ou alias historiques rattachés à [term].
  final List<String> synonyms;

  /// Termes, faux-amis ou variantes de jargon à proscrire au profit de [term].
  final List<String> forbiddenTerms;

  /// Domaine métier ou pôle d'entreprise associé.
  final String domain;

  /// Référent métier, équipe ou direction propriétaire du concept.
  final String owner;

  /// Indice de nommage technique recommandé (ex. `DeliveryNote` ou `delivery_note`).
  final String technicalNameHint;

  /// Exemples concrets d'usage.
  final List<String> examples;

  /// Statut de gouvernance ([CompanyGlossaryStatus]).
  final CompanyGlossaryStatus status;

  /// Horodatage UTC optionnel de création.
  final DateTime? createdAt;

  /// Horodatage UTC optionnel de dernière mise à jour.
  final DateTime? updatedAt;

  /// Vérifie les invariants du terme.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'CompanyGlossaryTerm.id ne peut pas être vide.',
      );
    }
    if (term.trim().isEmpty) {
      throw const FormatException(
        'CompanyGlossaryTerm.term ne peut pas être vide.',
      );
    }
  }

  /// Convertit ce terme d'entreprise en [LexiconTerm] exploitable dans un projet.
  LexiconTerm toLexiconTerm({
    String? idOverride,
    bool includeForbiddenAsSynonyms = true,
  }) {
    final mergedSynonyms = <String>[
      ...synonyms,
      if (includeForbiddenAsSynonyms) ...forbiddenTerms,
    ];
    return LexiconTerm(
      id: (idOverride != null && idOverride.trim().isNotEmpty)
          ? idOverride.trim()
          : id,
      term: term,
      definition: definition,
      synonyms: _dedupeStrings(mergedSynonyms),
      domain: domain,
      examples: examples,
    );
  }

  /// Indique si [query] correspond au terme, sa définition, son domaine, ses
  /// synonymes, ses termes proscrits, son référent ou son nom technique.
  bool matchesQuery(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return term.toLowerCase().contains(needle) ||
        definition.toLowerCase().contains(needle) ||
        domain.toLowerCase().contains(needle) ||
        owner.toLowerCase().contains(needle) ||
        technicalNameHint.toLowerCase().contains(needle) ||
        synonyms.any((s) => s.toLowerCase().contains(needle)) ||
        forbiddenTerms.any((f) => f.toLowerCase().contains(needle)) ||
        examples.any((e) => e.toLowerCase().contains(needle));
  }

  /// Copie modifiée.
  CompanyGlossaryTerm copyWith({
    String? id,
    String? term,
    String? definition,
    List<String>? synonyms,
    List<String>? forbiddenTerms,
    String? domain,
    String? owner,
    String? technicalNameHint,
    List<String>? examples,
    CompanyGlossaryStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CompanyGlossaryTerm(
    id: id ?? this.id,
    term: term ?? this.term,
    definition: definition ?? this.definition,
    synonyms: synonyms ?? this.synonyms,
    forbiddenTerms: forbiddenTerms ?? this.forbiddenTerms,
    domain: domain ?? this.domain,
    owner: owner ?? this.owner,
    technicalNameHint: technicalNameHint ?? this.technicalNameHint,
    examples: examples ?? this.examples,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'term': term,
    'definition': definition,
    'synonyms': synonyms,
    'forbiddenTerms': forbiddenTerms,
    'domain': domain,
    'owner': owner,
    'technicalNameHint': technicalNameHint,
    'examples': examples,
    'status': status.name,
    if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };

  /// Désérialise depuis JSON (accepte aussi des entrées issues de `LexiconTerm`).
  factory CompanyGlossaryTerm.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'CompanyGlossaryTerm doit être un objet JSON.',
      );
    }
    final term = (raw['term'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final item = CompanyGlossaryTerm(
      id: id.isEmpty ? 'cg_${term.hashCode.abs()}' : id,
      term: term.isEmpty ? 'Terme sans nom' : term,
      definition: (raw['definition'] as String?)?.trim() ?? '',
      synonyms: _stringList(raw['synonyms']),
      forbiddenTerms: _stringList(raw['forbiddenTerms']),
      domain: (raw['domain'] as String?)?.trim() ?? '',
      owner: (raw['owner'] as String?)?.trim() ?? '',
      technicalNameHint: (raw['technicalNameHint'] as String?)?.trim() ?? '',
      examples: _stringList(raw['examples']),
      status: CompanyGlossaryStatus.fromJson(raw['status']),
      createdAt: _parseDateTime(raw['createdAt'] ?? raw['created_at']),
      updatedAt: _parseDateTime(raw['updatedAt'] ?? raw['updated_at']),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanyGlossaryTerm &&
          other.id == id &&
          other.term == term &&
          other.definition == definition &&
          listEquals(other.synonyms, synonyms) &&
          listEquals(other.forbiddenTerms, forbiddenTerms) &&
          other.domain == domain &&
          other.owner == owner &&
          other.technicalNameHint == technicalNameHint &&
          listEquals(other.examples, examples) &&
          other.status == status &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    term,
    definition,
    Object.hashAll(synonyms),
    Object.hashAll(forbiddenTerms),
    domain,
    owner,
    technicalNameHint,
    Object.hashAll(examples),
    status,
    createdAt,
    updatedAt,
  );
}

/// Glossaire terminologique complet d'entreprise partagé entre tous les projets.
@immutable
class CompanyGlossary {
  /// Construit un glossaire d'entreprise immuable.
  CompanyGlossary({
    List<CompanyGlossaryTerm> terms = const <CompanyGlossaryTerm>[],
    List<String> ambiguousTerms = const <String>[],
    List<String> conventions = const <String>[],
    DateTime? updatedAt,
  }) : terms = List<CompanyGlossaryTerm>.unmodifiable(terms),
       ambiguousTerms = List<String>.unmodifiable(
         _dedupeStrings(ambiguousTerms),
       ),
       conventions = List<String>.unmodifiable(_dedupeStrings(conventions)),
       updatedAt = updatedAt?.toUtc();

  /// Glossaire vide initial.
  static final CompanyGlossary empty = CompanyGlossary();

  /// Termes gouvernés du glossaire d'entreprise.
  final List<CompanyGlossaryTerm> terms;

  /// Termes polysémiques ou points d'attention transverses à surveiller.
  final List<String> ambiguousTerms;

  /// Conventions de nommage, unités, formats et sigles d'entreprise.
  final List<String> conventions;

  /// Horodatage UTC de dernière modification.
  final DateTime? updatedAt;

  /// Vrai si au moins un terme, une convention ou une ambiguïté est défini.
  bool get hasContent =>
      terms.isNotEmpty || ambiguousTerms.isNotEmpty || conventions.isNotEmpty;

  /// Liste triée des domaines métier distincts utilisés dans [terms].
  List<String> get domains {
    final set = <String>{
      for (final t in terms)
        if (t.domain.trim().isNotEmpty) t.domain.trim(),
    };
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return List<String>.unmodifiable(list);
  }

  /// Nombre de termes ayant le [status] demandé.
  int countByStatus(CompanyGlossaryStatus status) =>
      terms.where((t) => t.status == status).length;

  /// Recherche un terme par identifiant, libellé canonique, synonyme ou terme proscrit.
  CompanyGlossaryTerm? findMatchingTerm(String needle) {
    final normalized = needle.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final term in terms) {
      if (term.id.toLowerCase() == normalized ||
          term.term.toLowerCase() == normalized) {
        return term;
      }
    }
    for (final term in terms) {
      if (term.synonyms.any((s) => s.toLowerCase() == normalized) ||
          term.forbiddenTerms.any((f) => f.toLowerCase() == normalized)) {
        return term;
      }
    }
    return null;
  }

  /// Retourne une copie contenant [term] inséré ou mis à jour par `id`.
  ///
  /// Renseigne automatiquement `createdAt` à l'ajout et `updatedAt` à chaque
  /// modification tout en préservant le `createdAt` initial lors des mises à jour.
  CompanyGlossary upsertTerm(CompanyGlossaryTerm term, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final list = List<CompanyGlossaryTerm>.from(terms);
    final idx = list.indexWhere((t) => t.id == term.id);
    if (idx >= 0) {
      final prev = list[idx];
      list[idx] = term.copyWith(
        createdAt: term.createdAt ?? prev.createdAt ?? timestamp,
        updatedAt: term.updatedAt ?? timestamp,
      );
    } else {
      list.add(
        term.copyWith(
          createdAt: term.createdAt ?? timestamp,
          updatedAt: term.updatedAt ?? timestamp,
        ),
      );
    }
    return copyWith(terms: list, updatedAt: timestamp);
  }

  /// Retourne une copie sans le terme identifié par [termId].
  CompanyGlossary removeTerm(String termId, {DateTime? now}) {
    final next = terms.where((t) => t.id != termId).toList();
    if (next.length == terms.length) return this;
    return copyWith(terms: next, updatedAt: (now ?? DateTime.now()).toUtc());
  }

  /// Valide l'unicité des identifiants de termes.
  void validate() {
    final ids = <String>{};
    for (final term in terms) {
      term.validate();
      if (!ids.add(term.id)) {
        throw FormatException(
          'Identifiant de terme d’entreprise dupliqué : ${term.id}',
        );
      }
    }
  }

  /// Produit un instantané JSON compact destiné aux prompts IA de projets.
  Map<String, Object?> toPromptContextJson({int maxTerms = 80}) {
    final prioritized = [
      ...terms.where((t) => t.status == CompanyGlossaryStatus.approved),
      ...terms.where((t) => t.status == CompanyGlossaryStatus.draft),
      ...terms.where((t) => t.status == CompanyGlossaryStatus.deprecated),
    ];
    final slice = prioritized.length <= maxTerms
        ? prioritized
        : prioritized.sublist(0, maxTerms);
    return <String, Object?>{
      'terms': [
        for (final t in slice)
          <String, Object?>{
            'id': t.id,
            'term': t.term,
            'status': t.status.name,
            if (t.definition.isNotEmpty) 'definition': t.definition,
            if (t.domain.isNotEmpty) 'domain': t.domain,
            if (t.technicalNameHint.isNotEmpty)
              'technicalNameHint': t.technicalNameHint,
            if (t.synonyms.isNotEmpty) 'synonyms': t.synonyms,
            if (t.forbiddenTerms.isNotEmpty) 'forbiddenTerms': t.forbiddenTerms,
          },
      ],
      if (conventions.isNotEmpty) 'conventions': conventions,
      if (ambiguousTerms.isNotEmpty) 'ambiguousTerms': ambiguousTerms,
    };
  }

  /// Copie modifiée.
  CompanyGlossary copyWith({
    List<CompanyGlossaryTerm>? terms,
    List<String>? ambiguousTerms,
    List<String>? conventions,
    DateTime? updatedAt,
  }) => CompanyGlossary(
    terms: terms ?? this.terms,
    ambiguousTerms: ambiguousTerms ?? this.ambiguousTerms,
    conventions: conventions ?? this.conventions,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'terms': [for (final t in terms) t.toJson()],
    'ambiguousTerms': ambiguousTerms,
    'conventions': conventions,
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };

  /// Désérialise depuis JSON (tolère `null`).
  factory CompanyGlossary.fromJson(Object? raw) {
    if (raw == null) return CompanyGlossary.empty;
    if (raw is! Map) {
      throw const FormatException('CompanyGlossary doit être un objet JSON.');
    }
    final glossary = CompanyGlossary(
      terms: [
        if (raw['terms'] is List)
          for (final item in raw['terms'] as List)
            CompanyGlossaryTerm.fromJson(item),
      ],
      ambiguousTerms: _stringList(raw['ambiguousTerms']),
      conventions: _stringList(raw['conventions']),
      updatedAt: _parseDateTime(raw['updatedAt'] ?? raw['updated_at']),
    );
    glossary.validate();
    return glossary;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanyGlossary &&
          listEquals(other.terms, terms) &&
          listEquals(other.ambiguousTerms, ambiguousTerms) &&
          listEquals(other.conventions, conventions) &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(terms),
    Object.hashAll(ambiguousTerms),
    Object.hashAll(conventions),
    updatedAt,
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return _dedupeStrings([
    for (final item in raw)
      if (item is String) item,
  ]);
}

List<String> _dedupeStrings(Iterable<String> source) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in source) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final key = trimmed.toLowerCase();
    if (seen.add(key)) {
      result.add(trimmed);
    }
  }
  return result;
}

DateTime? _parseDateTime(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
