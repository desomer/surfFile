/// Modèles immuables du lexique métier / Ubiquitous Language ([SpecLexicon], [LexiconTerm]).
library;

import 'package:flutter/foundation.dart';

/// Terme métier défini de manière univoque dans le lexique du projet.
@immutable
class LexiconTerm {
  /// Construit un terme de lexique immuable.
  LexiconTerm({
    required this.id,
    required this.term,
    this.definition = '',
    List<String> synonyms = const <String>[],
    this.domain = '',
    List<String> examples = const <String>[],
  }) : synonyms = List<String>.unmodifiable(synonyms),
       examples = List<String>.unmodifiable(examples);

  /// Identifiant technique stable du terme.
  final String id;

  /// Terme canonique retenu dans le langage omniprésent (ex. `Bon de livraison`).
  final String term;

  /// Définition métier claire et sans ambiguïté.
  final String definition;

  /// Synonymes ou variantes de vocabulaire à unifier vers [term].
  final List<String> synonyms;

  /// Domaine ou sous-domaine métier associé (optionnel).
  final String domain;

  /// Exemples concrets d'utilisation.
  final List<String> examples;

  /// Vérifie les invariants du terme.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('LexiconTerm.id ne peut pas être vide.');
    }
    if (term.trim().isEmpty) {
      throw const FormatException('LexiconTerm.term ne peut pas être vide.');
    }
  }

  /// Copie modifiée.
  LexiconTerm copyWith({
    String? id,
    String? term,
    String? definition,
    List<String>? synonyms,
    String? domain,
    List<String>? examples,
  }) => LexiconTerm(
    id: id ?? this.id,
    term: term ?? this.term,
    definition: definition ?? this.definition,
    synonyms: synonyms ?? this.synonyms,
    domain: domain ?? this.domain,
    examples: examples ?? this.examples,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'term': term,
    'definition': definition,
    'synonyms': synonyms,
    'domain': domain,
    'examples': examples,
  };

  /// Désérialise depuis JSON.
  factory LexiconTerm.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('LexiconTerm doit être un objet JSON.');
    }
    final term = (raw['term'] as String?)?.trim() ?? '';
    final id = (raw['id'] as String?)?.trim() ?? '';
    final item = LexiconTerm(
      id: id.isEmpty ? 'term_${term.hashCode.abs()}' : id,
      term: term.isEmpty ? 'Terme sans nom' : term,
      definition: (raw['definition'] as String?)?.trim() ?? '',
      synonyms: _stringList(raw['synonyms']),
      domain: (raw['domain'] as String?)?.trim() ?? '',
      examples: _stringList(raw['examples']),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LexiconTerm &&
          other.id == id &&
          other.term == term &&
          other.definition == definition &&
          listEquals(other.synonyms, synonyms) &&
          other.domain == domain &&
          listEquals(other.examples, examples);

  @override
  int get hashCode => Object.hash(
    id,
    term,
    definition,
    Object.hashAll(synonyms),
    domain,
    Object.hashAll(examples),
  );
}

/// Lexique métier complet de l'étape 1.
@immutable
class SpecLexicon {
  /// Construit un lexique métier immuable.
  SpecLexicon({
    List<LexiconTerm> terms = const <LexiconTerm>[],
    List<String> ambiguousTerms = const <String>[],
    List<String> conventions = const <String>[],
  }) : terms = List<LexiconTerm>.unmodifiable(terms),
       ambiguousTerms = List<String>.unmodifiable(ambiguousTerms),
       conventions = List<String>.unmodifiable(conventions);

  /// Lexique vide initial.
  static final SpecLexicon empty = SpecLexicon();

  /// Termes canoniques définis avec l'utilisateur.
  final List<LexiconTerm> terms;

  /// Termes ambigus ou polysémiques identifiés et à surveiller.
  final List<String> ambiguousTerms;

  /// Conventions de vocabulaire, unités ou sigles du projet.
  final List<String> conventions;

  /// Vrai si au moins un élément est renseigné.
  bool get hasContent =>
      terms.isNotEmpty || ambiguousTerms.isNotEmpty || conventions.isNotEmpty;

  /// Valide l'unicité des identifiants de termes.
  void validate() {
    final ids = <String>{};
    for (final term in terms) {
      term.validate();
      if (!ids.add(term.id)) {
        throw FormatException('Identifiant de terme dupliqué : ${term.id}');
      }
    }
  }

  /// Copie modifiée.
  SpecLexicon copyWith({
    List<LexiconTerm>? terms,
    List<String>? ambiguousTerms,
    List<String>? conventions,
  }) => SpecLexicon(
    terms: terms ?? this.terms,
    ambiguousTerms: ambiguousTerms ?? this.ambiguousTerms,
    conventions: conventions ?? this.conventions,
  );

  /// Sérialise en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'terms': [for (final t in terms) t.toJson()],
    'ambiguousTerms': ambiguousTerms,
    'conventions': conventions,
  };

  /// Désérialise depuis JSON.
  factory SpecLexicon.fromJson(Object? raw) {
    if (raw == null) return SpecLexicon.empty;
    if (raw is! Map) {
      throw const FormatException('SpecLexicon doit être un objet JSON.');
    }
    final lexicon = SpecLexicon(
      terms: [
        if (raw['terms'] is List)
          for (final item in raw['terms'] as List) LexiconTerm.fromJson(item),
      ],
      ambiguousTerms: _stringList(raw['ambiguousTerms']),
      conventions: _stringList(raw['conventions']),
    );
    lexicon.validate();
    return lexicon;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecLexicon &&
          listEquals(other.terms, terms) &&
          listEquals(other.ambiguousTerms, ambiguousTerms) &&
          listEquals(other.conventions, conventions);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(terms),
    Object.hashAll(ambiguousTerms),
    Object.hashAll(conventions),
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
