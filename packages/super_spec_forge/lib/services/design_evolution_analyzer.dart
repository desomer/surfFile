/// Analyseur statique d'évolution des artefacts Design, conseiller SemVer et
/// moteur de propagation transitive d'impact entre Value Objects, Modèles &
/// Contrats, Use Cases et Sagas ([DesignEvolutionAnalyzer]).
library;

import 'package:flutter/foundation.dart';

import '../models/business_object_spec.dart';
import '../models/domain_catalog.dart';
import '../models/domain_contracts.dart';
import '../models/domain_iteration_snapshot.dart';
import '../models/domain_layer_spec.dart';
import '../models/json_schema_constraints.dart';
import '../models/usecase_orchestration_spec.dart';
import '../models/value_object_spec.dart';

final RegExp _semVerPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
);

({int major, int minor, int patch})? _tryParseSemVer(String raw) {
  final match = _semVerPattern.firstMatch(raw.trim());
  if (match == null) return null;
  return (
    major: int.parse(match.group(1)!),
    minor: int.parse(match.group(2)!),
    patch: int.parse(match.group(3)!),
  );
}

int _compareSemVer(String a, String b) {
  final parsedA = _tryParseSemVer(a);
  final parsedB = _tryParseSemVer(b);
  if (parsedA == null || parsedB == null) {
    return a.trim().compareTo(b.trim());
  }
  final majorCmp = parsedA.major.compareTo(parsedB.major);
  if (majorCmp != 0) return majorCmp;
  final minorCmp = parsedA.minor.compareTo(parsedB.minor);
  if (minorCmp != 0) return minorCmp;
  return parsedA.patch.compareTo(parsedB.patch);
}

/// Niveau d'incrément sémantique recommandé selon la nature des changements détectés.
enum SemVerBump implements Comparable<SemVerBump> {
  /// Aucun changement détecté.
  none('Aucun', 'Aucun'),

  /// Changement documentaire ou éditorial sans impact contractuel.
  patch('Patch', 'Patch'),

  /// Évolution rétrocompatible (ajout optionnel, assouplissement, extension).
  minor('Mineur', 'Mineur'),

  /// Rupture de compatibilité (suppression, renommage technique, durcissement).
  major('Majeur (Breaking)', 'Majeur');

  const SemVerBump(this.label, this.shortLabel);

  /// Libellé complet en français.
  final String label;

  /// Libellé court en français pour les badges et causes d'impact.
  final String shortLabel;

  /// Indique si un changement au moins documentaire a eu lieu.
  bool get hasChange => this != SemVerBump.none;

  /// Retourne le niveau d'impact maximal entre `this` et [other].
  SemVerBump max(SemVerBump other) => index >= other.index ? this : other;

  @override
  int compareTo(SemVerBump other) => index.compareTo(other.index);

  /// Indique si cet impact est strictement inférieur à [other].
  bool operator <(SemVerBump other) => index < other.index;

  /// Indique si cet impact est inférieur ou égal à [other].
  bool operator <=(SemVerBump other) => index <= other.index;

  /// Indique si cet impact est strictement supérieur à [other].
  bool operator >(SemVerBump other) => index > other.index;

  /// Indique si cet impact est supérieur ou égal à [other].
  bool operator >=(SemVerBump other) => index >= other.index;

  /// Applique cet incrément SemVer à la version `x.y.z` [currentSemVer].
  ///
  /// Suit la règle standard SemVer :
  /// - `major` incrémente `X` et remet `Y.Z` à `0.0` (`0.2.3` → `1.0.0`, `1.2.3` → `2.0.0`) ;
  /// - `minor` incrémente `Y` et remet `Z` à `0` (`0.0.1` → `0.1.0`) ;
  /// - `patch` incrémente `Z` (`0.0.1` → `0.0.2`) ;
  /// - `none` restitue la version normalisée inchangée.
  String applyTo(String currentSemVer) {
    final parsed = _tryParseSemVer(currentSemVer);
    if (parsed == null) {
      throw FormatException(
        'Version sémantique invalide (attendu x.y.z) : $currentSemVer',
      );
    }
    return switch (this) {
      SemVerBump.none => '${parsed.major}.${parsed.minor}.${parsed.patch}',
      SemVerBump.patch => '${parsed.major}.${parsed.minor}.${parsed.patch + 1}',
      SemVerBump.minor => '${parsed.major}.${parsed.minor + 1}.0',
      SemVerBump.major => '${parsed.major + 1}.0.0',
    };
  }
}

/// Catégorie d'artefact de conception analysée dans un domaine fonctionnel.
enum DesignArtifactKind {
  /// Value Object atomique ou composite (Shared Kernel ou Domaine).
  valueObject('Value Object', 'Value Object', 'Value Objects'),

  /// Modèle métier ou contrat d'échange issu de [DomainContracts].
  model('Modèle & Contrat', 'Modèle', 'Modèles & Contrats'),

  /// Cas d'usage applicatif CQRS ([ApplicationUseCaseSpec]).
  useCase('Use Case', 'Use Case', 'Cas d’usage'),

  /// Saga d'orchestration ou de chorégraphie ([OrchestrationSagaSpec]).
  saga('Saga', 'Saga', 'Sagas');

  const DesignArtifactKind(this.label, this.shortLabel, this.pluralLabel);

  /// Libellé complet en français.
  final String label;

  /// Libellé court utilisé dans les préfixes de causes d'impact.
  final String shortLabel;

  /// Libellé pluriel de regroupement.
  final String pluralLabel;
}

/// État d'évolution d'un artefact par rapport au jalon (baseline) actif.
enum ArtifactEvolutionState {
  /// Aucun jalon d'itération n'est actif sur le domaine.
  noBaseline('Sans jalon'),

  /// L'artefact est strictement conforme au jalon et à ses dépendances.
  unchanged('Conforme'),

  /// L'artefact a été créé depuis la capture du jalon.
  added('Nouveau'),

  /// L'artefact a subi des modifications directes depuis le jalon.
  modified('Δ Modifié'),

  /// L'artefact n'a pas changé directement mais dépend d'un artefact modifié ou supprimé.
  impacted('⇄ Impacté'),

  /// L'artefact existait dans le jalon mais a été supprimé du domaine.
  removed('Supprimé');

  const ArtifactEvolutionState(this.label);

  /// Libellé lisible en français affiché dans les badges d'évolution.
  final String label;

  /// Indique si l'artefact requiert une action de Build (`added`, `modified`, `impacted`).
  bool get isActionable =>
      this == ArtifactEvolutionState.added ||
      this == ArtifactEvolutionState.modified ||
      this == ArtifactEvolutionState.impacted;
}

/// Ligne unitaire de différence détectée sur un artefact de conception.
@immutable
class ArtifactChangeEntry {
  /// Crée une entrée immuable de différence structurelle ou documentaire.
  const ArtifactChangeEntry({
    required this.category,
    required this.summary,
    required this.impact,
  });

  /// Catégorie fonctionnelle du changement (ex. `Attribut`, `Contrainte`, `Couche Domain`).
  final String category;

  /// Résumé lisible en français de la modification.
  final String summary;

  /// Impact SemVer unitaire associé à cette modification.
  final SemVerBump impact;

  /// Retourne une copie modifiée de cette entrée.
  ArtifactChangeEntry copyWith({
    String? category,
    String? summary,
    SemVerBump? impact,
  }) => ArtifactChangeEntry(
    category: category ?? this.category,
    summary: summary ?? this.summary,
    impact: impact ?? this.impact,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactChangeEntry &&
          other.category == category &&
          other.summary == summary &&
          other.impact == impact;

  @override
  int get hashCode => Object.hash(category, summary, impact);

  @override
  String toString() => '[$category · ${impact.shortLabel}] $summary';
}

/// Rapport complet d'évolution et de recommandation SemVer d'un artefact Design.
@immutable
class ArtifactEvolutionReport {
  /// Crée un rapport immuable d'évolution d'artefact.
  ArtifactEvolutionReport({
    required this.kind,
    required this.id,
    required this.name,
    this.subtitle = '',
    this.valueObjectScope,
    required this.state,
    this.baselineVersion,
    required this.currentVersion,
    this.directBump = SemVerBump.none,
    SemVerBump? effectiveBump,
    String? recommendedVersion,
    List<ArtifactChangeEntry> directChanges = const <ArtifactChangeEntry>[],
    List<String> impactedBy = const <String>[],
  }) : effectiveBump = effectiveBump ?? directBump,
       recommendedVersion =
           recommendedVersion ??
           _computeRecommendedVersion(
             state: state,
             baselineVersion: baselineVersion,
             currentVersion: currentVersion,
             effectiveBump: effectiveBump ?? directBump,
           ),
       directChanges = List<ArtifactChangeEntry>.unmodifiable(directChanges),
       impactedBy = List<String>.unmodifiable(impactedBy);

  /// Catégorie de l'artefact.
  final DesignArtifactKind kind;

  /// Identifiant stable de l'artefact dans son référentiel.
  final String id;

  /// Nom technique principal de l'artefact.
  final String name;

  /// Sous-titre ou libellé métier complémentaire.
  final String subtitle;

  /// Portée du Value Object lorsque [kind] vaut [DesignArtifactKind.valueObject].
  final ValueObjectScope? valueObjectScope;

  /// État d'évolution vis-à-vis de la baseline.
  final ArtifactEvolutionState state;

  /// Version sémantique enregistrée dans la baseline (`null` si nouveau ou sans jalon).
  final String? baselineVersion;

  /// Version sémantique actuelle de l'artefact.
  final String currentVersion;

  /// Incrément SemVer induit par les seules modifications directes de l'artefact.
  final SemVerBump directBump;

  /// Incrément SemVer effectif (maximum entre [directBump] et les impacts amont).
  final SemVerBump effectiveBump;

  /// Version sémantique recommandée compte tenu de [baselineVersion] et [effectiveBump].
  final String recommendedVersion;

  /// Liste des différences directes détectées sur cet artefact.
  final List<ArtifactChangeEntry> directChanges;

  /// Causes amont lisibles expliquant un impact transitif.
  final List<String> impactedBy;

  /// Indique si la version courante n'a pas encore été incrémentée depuis la baseline
  /// alors qu'une évolution directe ou transitive a été détectée.
  bool get needsVersionBump =>
      state != ArtifactEvolutionState.removed &&
      baselineVersion != null &&
      effectiveBump.hasChange &&
      _compareSemVer(currentVersion, baselineVersion!) <= 0;

  static String _computeRecommendedVersion({
    required ArtifactEvolutionState state,
    required String? baselineVersion,
    required String currentVersion,
    required SemVerBump effectiveBump,
  }) {
    if (state == ArtifactEvolutionState.removed ||
        baselineVersion == null ||
        !effectiveBump.hasChange) {
      return currentVersion;
    }
    if (_compareSemVer(currentVersion, baselineVersion) <= 0) {
      return effectiveBump.applyTo(baselineVersion);
    }
    return currentVersion;
  }

  /// Retourne une copie modifiée de ce rapport.
  ArtifactEvolutionReport copyWith({
    DesignArtifactKind? kind,
    String? id,
    String? name,
    String? subtitle,
    ValueObjectScope? valueObjectScope,
    bool clearValueObjectScope = false,
    ArtifactEvolutionState? state,
    String? baselineVersion,
    bool clearBaselineVersion = false,
    String? currentVersion,
    SemVerBump? directBump,
    SemVerBump? effectiveBump,
    String? recommendedVersion,
    List<ArtifactChangeEntry>? directChanges,
    List<String>? impactedBy,
  }) {
    final nextState = state ?? this.state;
    final nextBaselineVersion = clearBaselineVersion
        ? null
        : (baselineVersion ?? this.baselineVersion);
    final nextCurrentVersion = currentVersion ?? this.currentVersion;
    final nextDirectBump = directBump ?? this.directBump;
    final nextEffectiveBump = effectiveBump ?? this.effectiveBump;
    return ArtifactEvolutionReport(
      kind: kind ?? this.kind,
      id: id ?? this.id,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      valueObjectScope: clearValueObjectScope
          ? null
          : (valueObjectScope ?? this.valueObjectScope),
      state: nextState,
      baselineVersion: nextBaselineVersion,
      currentVersion: nextCurrentVersion,
      directBump: nextDirectBump,
      effectiveBump: nextEffectiveBump,
      recommendedVersion:
          recommendedVersion ??
          _computeRecommendedVersion(
            state: nextState,
            baselineVersion: nextBaselineVersion,
            currentVersion: nextCurrentVersion,
            effectiveBump: nextEffectiveBump,
          ),
      directChanges: directChanges ?? this.directChanges,
      impactedBy: impactedBy ?? this.impactedBy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactEvolutionReport &&
          other.kind == kind &&
          other.id == id &&
          other.name == name &&
          other.subtitle == subtitle &&
          other.valueObjectScope == valueObjectScope &&
          other.state == state &&
          other.baselineVersion == baselineVersion &&
          other.currentVersion == currentVersion &&
          other.directBump == directBump &&
          other.effectiveBump == effectiveBump &&
          other.recommendedVersion == recommendedVersion &&
          listEquals(other.directChanges, directChanges) &&
          listEquals(other.impactedBy, impactedBy);

  @override
  int get hashCode => Object.hash(
    kind,
    id,
    name,
    subtitle,
    valueObjectScope,
    state,
    baselineVersion,
    currentVersion,
    directBump,
    effectiveBump,
    recommendedVersion,
    Object.hashAll(directChanges),
    Object.hashAll(impactedBy),
  );
}

/// Rapport consolidé d'évolution et d'impact de tous les artefacts d'un domaine.
@immutable
class DomainEvolutionReport {
  /// Crée un rapport d'évolution de domaine immuable.
  DomainEvolutionReport({
    required this.domainId,
    this.baseline,
    Map<String, ArtifactEvolutionReport> valueObjects =
        const <String, ArtifactEvolutionReport>{},
    Map<String, ArtifactEvolutionReport> models =
        const <String, ArtifactEvolutionReport>{},
    Map<String, ArtifactEvolutionReport> useCases =
        const <String, ArtifactEvolutionReport>{},
    Map<String, ArtifactEvolutionReport> sagas =
        const <String, ArtifactEvolutionReport>{},
    List<ArtifactEvolutionReport> removedArtifacts =
        const <ArtifactEvolutionReport>[],
  }) : valueObjects = Map<String, ArtifactEvolutionReport>.unmodifiable(
         valueObjects,
       ),
       models = Map<String, ArtifactEvolutionReport>.unmodifiable(models),
       useCases = Map<String, ArtifactEvolutionReport>.unmodifiable(useCases),
       sagas = Map<String, ArtifactEvolutionReport>.unmodifiable(sagas),
       removedArtifacts = List<ArtifactEvolutionReport>.unmodifiable(
         removedArtifacts,
       );

  /// Identifiant du domaine fonctionnel analysé.
  final String domainId;

  /// Jalon d'itération ayant servi de baseline de comparaison (`null` si aucun).
  final DomainIterationSnapshot? baseline;

  /// Rapports des Value Objects visibles du domaine indexés par `vo.id`.
  final Map<String, ArtifactEvolutionReport> valueObjects;

  /// Rapports des modèles et contrats indexés par `entryId`.
  final Map<String, ArtifactEvolutionReport> models;

  /// Rapports des cas d'usage applicatifs indexés par `uc.id`.
  final Map<String, ArtifactEvolutionReport> useCases;

  /// Rapports des sagas indexés par `saga.id`.
  final Map<String, ArtifactEvolutionReport> sagas;

  /// Artefacts présents dans [baseline] et supprimés dans l'état courant du domaine.
  final List<ArtifactEvolutionReport> removedArtifacts;

  /// Indique si une baseline d'itération est active pour ce rapport.
  bool get hasBaseline => baseline != null;

  /// Itère sur tous les rapports d'artefacts actuellement présents dans le domaine.
  Iterable<ArtifactEvolutionReport> get allCurrentReports sync* {
    yield* valueObjects.values;
    yield* models.values;
    yield* useCases.values;
    yield* sagas.values;
  }

  /// Nombre d'artefacts ajoutés depuis la baseline (`added`).
  int get addedCount => allCurrentReports
      .where((r) => r.state == ArtifactEvolutionState.added)
      .length;

  /// Nombre d'artefacts directement modifiés depuis la baseline (`modified`).
  int get modifiedCount => allCurrentReports
      .where((r) => r.state == ArtifactEvolutionState.modified)
      .length;

  /// Nombre d'artefacts impactés par propagation transitive (`impacted`).
  int get impactedCount => allCurrentReports
      .where((r) => r.state == ArtifactEvolutionState.impacted)
      .length;

  /// Nombre d'artefacts supprimés depuis la baseline (`removed`).
  int get removedCount => removedArtifacts.length;

  /// Nombre total d'artefacts actuels nécessitant une attention Build (`added + modified + impacted`).
  int get totalActionableCount => addedCount + modifiedCount + impactedCount;

  /// Recherche le rapport associé au couple ([kind], [id]) parmi les artefacts actifs ou supprimés.
  ArtifactEvolutionReport? reportFor(DesignArtifactKind kind, String id) {
    final active = switch (kind) {
      DesignArtifactKind.valueObject => valueObjects[id],
      DesignArtifactKind.model => models[id],
      DesignArtifactKind.useCase => useCases[id],
      DesignArtifactKind.saga => sagas[id],
    };
    if (active != null) return active;
    return removedArtifacts
        .where((r) => r.kind == kind && r.id == id)
        .firstOrNull;
  }

  /// Retourne une copie modifiée de ce rapport de domaine.
  DomainEvolutionReport copyWith({
    String? domainId,
    DomainIterationSnapshot? baseline,
    bool clearBaseline = false,
    Map<String, ArtifactEvolutionReport>? valueObjects,
    Map<String, ArtifactEvolutionReport>? models,
    Map<String, ArtifactEvolutionReport>? useCases,
    Map<String, ArtifactEvolutionReport>? sagas,
    List<ArtifactEvolutionReport>? removedArtifacts,
  }) => DomainEvolutionReport(
    domainId: domainId ?? this.domainId,
    baseline: clearBaseline ? null : (baseline ?? this.baseline),
    valueObjects: valueObjects ?? this.valueObjects,
    models: models ?? this.models,
    useCases: useCases ?? this.useCases,
    sagas: sagas ?? this.sagas,
    removedArtifacts: removedArtifacts ?? this.removedArtifacts,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainEvolutionReport &&
          other.domainId == domainId &&
          other.baseline == baseline &&
          mapEquals(other.valueObjects, valueObjects) &&
          mapEquals(other.models, models) &&
          mapEquals(other.useCases, useCases) &&
          mapEquals(other.sagas, sagas) &&
          listEquals(other.removedArtifacts, removedArtifacts);

  @override
  int get hashCode => Object.hash(
    domainId,
    baseline,
    Object.hashAllUnordered([
      for (final e in valueObjects.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAllUnordered([
      for (final e in models.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAllUnordered([
      for (final e in useCases.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAllUnordered([
      for (final e in sagas.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAll(removedArtifacts),
  );
}

/// Moteur pur et sans état de calcul des différences typées, de conseil SemVer
/// et de propagation transitive des impacts sur le graphe d'un domaine fonctionnel.
abstract final class DesignEvolutionAnalyzer {
  static const Set<String> _primitiveFieldTypeTokens = <String>{
    'string',
    'text',
    'str',
    'int',
    'integer',
    'number',
    'float',
    'double',
    'decimal',
    'bool',
    'boolean',
    'date',
    'datetime',
    'timestamp',
    'uuid',
    'email',
    'url',
    'uri',
    'enum',
    'enumeration',
    'ref',
    'reference',
    'vo',
    'valueobject',
    'object',
    'json',
    'any',
    'list',
    'array',
    'set',
    'map',
    'void',
    'null',
    'optional',
    'optionnel',
    'required',
    'requis',
    'obligatoire',
  };

  /// Compare deux versions sémantiques `x.y.z` (`< 0`, `0`, `> 0`).
  static int compareSemVer(String a, String b) => _compareSemVer(a, b);

  /// Retourne l'impact SemVer maximal parmi une collection d'entrées de changements.
  static SemVerBump maxBumpOf(Iterable<ArtifactChangeEntry> changes) => changes
      .fold<SemVerBump>(SemVerBump.none, (acc, entry) => acc.max(entry.impact));

  /// Calcule les différences typées entre deux versions d'un [ValueObjectSpec].
  static List<ArtifactChangeEntry> diffValueObject(
    ValueObjectSpec previous,
    ValueObjectSpec current,
  ) {
    final changes = <ArtifactChangeEntry>[];

    if (previous.technicalName != current.technicalName) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Identité',
          summary:
              "~ Nom technique '${previous.technicalName}' → '${current.technicalName}'",
          impact: SemVerBump.major,
        ),
      );
    }

    if (previous.kind != current.kind) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Structure',
          summary: "~ Forme '${previous.kind.label}' → '${current.kind.label}'",
          impact: SemVerBump.major,
        ),
      );
    } else if (current.isScalar) {
      if (previous.primitiveType != current.primitiveType) {
        changes.add(
          ArtifactChangeEntry(
            category: 'Type',
            summary:
                "~ Type primitif '${previous.primitiveType.dslKeyword}' → '${current.primitiveType.dslKeyword}'",
            impact: SemVerBump.major,
          ),
        );
      }
      _diffEnumValues(
        changes,
        previous.enumValues,
        current.enumValues,
        targetLabel: "Value Object '${current.technicalName}'",
      );
      if (!listEquals(
        previous.normalizationRules,
        current.normalizationRules,
      )) {
        changes.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ Règles de normalisation : [${previous.normalizationRules.join(', ')}] → [${current.normalizationRules.join(', ')}]",
            impact: SemVerBump.major,
          ),
        );
      }
      _diffSchemaConstraints(
        changes,
        previous.schemaConstraints,
        current.schemaConstraints,
        targetLabel: "Value Object '${current.technicalName}'",
      );
    } else {
      _diffAttributes(
        changes,
        previous.fields,
        current.fields,
        nounSingular: 'Champ',
        pathPrefix: '',
      );
      _diffCrossFieldRules(
        changes,
        previous.crossFieldRules,
        current.crossFieldRules,
      );
    }

    if (previous.name.trim() != current.name.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: "~ Libellé '${previous.name}' → '${current.name}'",
          impact: SemVerBump.patch,
        ),
      );
    }
    if (previous.category.trim() != current.category.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: "~ Catégorie '${previous.category}' → '${current.category}'",
          impact: SemVerBump.patch,
        ),
      );
    }
    if (previous.description.trim() != current.description.trim()) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: '~ Description métier mise à jour',
          impact: SemVerBump.patch,
        ),
      );
    }
    if (previous.constraints.trim() != current.constraints.trim()) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: '~ Résumé libre des contraintes mis à jour',
          impact: SemVerBump.patch,
        ),
      );
    }
    if (!listEquals(previous.examples, current.examples)) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: '~ Exemples / contre-exemples mis à jour',
          impact: SemVerBump.patch,
        ),
      );
    }

    return List<ArtifactChangeEntry>.unmodifiable(changes);
  }

  /// Calcule les différences typées entre deux photographies de modèle/contrat
  /// ([SnapshotModelArtifact]).
  static List<ArtifactChangeEntry> diffModel({
    required SnapshotModelArtifact previous,
    required SnapshotModelArtifact current,
  }) {
    final changes = <ArtifactChangeEntry>[];

    if (previous.name != current.name) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Contrat DSL',
          summary: "~ Nom DSL '${previous.name}' → '${current.name}'",
          impact: SemVerBump.major,
        ),
      );
    }
    if (previous.dslType != current.dslType) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Contrat DSL',
          summary: "~ Type DSL '${previous.dslType}' → '${current.dslType}'",
          impact: SemVerBump.major,
        ),
      );
    }
    if (previous.groupName != current.groupName) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Métadonnée',
          summary:
              "~ Rubrique DSL '${previous.groupName}' → '${current.groupName}'",
          impact: SemVerBump.patch,
        ),
      );
    }
    if (previous.title.trim() != current.title.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: "~ Titre '${previous.title}' → '${current.title}'",
          impact: SemVerBump.patch,
        ),
      );
    }

    _diffObjectAndDomainLayer(
      changes,
      previousObject: previous.objectSpec,
      currentObject: current.objectSpec,
      previousDomainLayer: previous.domainLayerSpec,
      currentDomainLayer: current.domainLayerSpec,
      includeObjectIdentityDiff: false,
    );

    return List<ArtifactChangeEntry>.unmodifiable(changes);
  }

  /// Calcule directement les différences entre deux couples
  /// ([BusinessObjectSpec], [HexagonalDomainLayerSpec]).
  static List<ArtifactChangeEntry> diffModelSpecs({
    required BusinessObjectSpec previousObject,
    required BusinessObjectSpec currentObject,
    HexagonalDomainLayerSpec? previousDomainLayer,
    HexagonalDomainLayerSpec? currentDomainLayer,
  }) {
    final changes = <ArtifactChangeEntry>[];
    _diffObjectAndDomainLayer(
      changes,
      previousObject: previousObject,
      currentObject: currentObject,
      previousDomainLayer:
          previousDomainLayer ?? HexagonalDomainLayerSpec.empty,
      currentDomainLayer: currentDomainLayer ?? HexagonalDomainLayerSpec.empty,
      includeObjectIdentityDiff: true,
    );
    return List<ArtifactChangeEntry>.unmodifiable(changes);
  }

  /// Calcule les différences typées entre deux spécifications de Use Case
  /// applicatif ([ApplicationUseCaseSpec]).
  static List<ArtifactChangeEntry> diffUseCase(
    ApplicationUseCaseSpec previous,
    ApplicationUseCaseSpec current,
  ) {
    final changes = <ArtifactChangeEntry>[];

    if (previous.name.trim() != current.name.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Contrat Use Case',
          summary: "~ Nom du Use Case '${previous.name}' → '${current.name}'",
          impact: SemVerBump.major,
        ),
      );
    }
    if (previous.cqrsType != current.cqrsType) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Contrat Use Case',
          summary:
              "~ Qualification CQRS '${previous.cqrsType.label}' → '${current.cqrsType.label}'",
          impact: SemVerBump.major,
        ),
      );
    }
    if (previous.inboundPort.trim() != current.inboundPort.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Contrat Use Case',
          summary:
              "~ Port entrant '${previous.inboundPort}' → '${current.inboundPort}'",
          impact: SemVerBump.major,
        ),
      );
    }
    if (previous.targetAggregate.trim() != current.targetAggregate.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Contrat Use Case',
          summary:
              "~ Agrégat cible '${previous.targetAggregate}' → '${current.targetAggregate}'",
          impact: SemVerBump.major,
        ),
      );
    }

    _diffUseCaseFields(
      changes,
      previous.triggerInputs,
      current.triggerInputs,
      isInput: true,
      pathPrefix: '',
    );
    _diffUseCaseFields(
      changes,
      previous.outputs,
      current.outputs,
      isInput: false,
      pathPrefix: '',
    );

    final prevPorts = previous.outboundPorts.toSet();
    final currPorts = current.outboundPorts.toSet();
    final removedPorts = previous.outboundPorts
        .where((p) => !currPorts.contains(p))
        .toList();
    final addedPorts = current.outboundPorts
        .where((p) => !prevPorts.contains(p))
        .toList();
    for (final port in removedPorts) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Ports & Événements',
          summary: "- Port sortant '$port' supprimé",
          impact: SemVerBump.major,
        ),
      );
    }
    for (final port in addedPorts) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Ports & Événements',
          summary: "+ Port sortant '$port' ajouté",
          impact: SemVerBump.minor,
        ),
      );
    }

    if (!listEquals(previous.emittedEvents, current.emittedEvents)) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Ports & Événements',
          summary: '~ Événements publiés mis à jour',
          impact: SemVerBump.minor,
        ),
      );
    }
    if (!listEquals(previous.possibleErrors, current.possibleErrors)) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Règles & Scénarios',
          summary: '~ Erreurs métier possibles mises à jour',
          impact: SemVerBump.minor,
        ),
      );
    }
    if (!listEquals(previous.scenarios, current.scenarios)) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Règles & Scénarios',
          summary: '~ Scénarios Given/When/Then mis à jour',
          impact: SemVerBump.minor,
        ),
      );
    }
    if (!listEquals(previous.businessRules, current.businessRules)) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Règles & Scénarios',
          summary: '~ Règles métier du Use Case mises à jour',
          impact: SemVerBump.minor,
        ),
      );
    }
    if (!listEquals(previous.detailedProcess, current.detailedProcess)) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Règles & Scénarios',
          summary: '~ Processus détaillé mis à jour',
          impact: SemVerBump.minor,
        ),
      );
    }

    if (previous.code.trim() != current.code.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: "~ Code '${previous.code}' → '${current.code}'",
          impact: SemVerBump.patch,
        ),
      );
    }
    if (previous.boundedContext.trim() != current.boundedContext.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Métadonnée',
          summary:
              "~ Bounded Context '${previous.boundedContext}' → '${current.boundedContext}'",
          impact: SemVerBump.patch,
        ),
      );
    }
    if (previous.title.trim() != current.title.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: "~ Titre '${previous.title}' → '${current.title}'",
          impact: SemVerBump.patch,
        ),
      );
    }
    if (previous.businessGoal.trim() != current.businessGoal.trim()) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: '~ Objectif métier mis à jour',
          impact: SemVerBump.patch,
        ),
      );
    }
    if (!listEquals(previous.acceptanceCriteria, current.acceptanceCriteria)) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: '~ Critères d’acceptation mis à jour',
          impact: SemVerBump.patch,
        ),
      );
    }
    if (!listEquals(previous.nonGoals, current.nonGoals)) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: '~ Non-objectifs mis à jour',
          impact: SemVerBump.patch,
        ),
      );
    }
    if (previous.concurrencyAndIdempotency.trim() !=
        current.concurrencyAndIdempotency.trim()) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: '~ Notes de concurrence et d’idempotence mises à jour',
          impact: SemVerBump.patch,
        ),
      );
    }
    if (!listEquals(previous.linkedSpecRefs, current.linkedSpecRefs)) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: '~ Références de traçabilité Spec mises à jour',
          impact: SemVerBump.patch,
        ),
      );
    }

    return List<ArtifactChangeEntry>.unmodifiable(changes);
  }

  /// Calcule les différences typées entre deux spécifications de Saga
  /// ([OrchestrationSagaSpec]).
  static List<ArtifactChangeEntry> diffSaga(
    OrchestrationSagaSpec previous,
    OrchestrationSagaSpec current,
  ) {
    final changes = <ArtifactChangeEntry>[];

    if (previous.name.trim() != current.name.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Contrat Saga',
          summary: "~ Nom de la Saga '${previous.name}' → '${current.name}'",
          impact: SemVerBump.major,
        ),
      );
    }
    if (previous.coordinationMode != current.coordinationMode) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Contrat Saga',
          summary:
              "~ Mode de coordination '${previous.coordinationMode.label}' → '${current.coordinationMode.label}'",
          impact: SemVerBump.major,
        ),
      );
    }
    if (previous.triggerEventOrCommand.trim() !=
        current.triggerEventOrCommand.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Contrat Saga',
          summary:
              "~ Déclencheur '${previous.triggerEventOrCommand}' → '${current.triggerEventOrCommand}'",
          impact: SemVerBump.major,
        ),
      );
    }
    if (previous.correlationKey.trim() != current.correlationKey.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Contrat Saga',
          summary:
              "~ Clé de corrélation '${previous.correlationKey}' → '${current.correlationKey}'",
          impact: SemVerBump.major,
        ),
      );
    }

    _diffSagaCompensationMatrix(
      changes,
      previous.compensationMatrix,
      current.compensationMatrix,
    );

    final prevContexts = previous.boundedContexts.toSet();
    final currContexts = current.boundedContexts.toSet();
    final removedContexts = previous.boundedContexts
        .where((c) => !currContexts.contains(c))
        .toList();
    final addedContexts = current.boundedContexts
        .where((c) => !prevContexts.contains(c))
        .toList();
    for (final bc in removedContexts) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Participants Saga',
          summary: "- Participant Bounded Context '$bc' retiré",
          impact: SemVerBump.major,
        ),
      );
    }
    for (final bc in addedContexts) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Participants Saga',
          summary: "+ Participant Bounded Context '$bc' ajouté",
          impact: SemVerBump.minor,
        ),
      );
    }

    if (previous.failureRecoveryStrategy.trim() !=
        current.failureRecoveryStrategy.trim()) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Résilience Saga',
          summary: '~ Stratégie de reprise sur échec mise à jour',
          impact: SemVerBump.minor,
        ),
      );
    }

    if (previous.code.trim() != current.code.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: "~ Code '${previous.code}' → '${current.code}'",
          impact: SemVerBump.patch,
        ),
      );
    }
    if (previous.title.trim() != current.title.trim()) {
      changes.add(
        ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: "~ Titre '${previous.title}' → '${current.title}'",
          impact: SemVerBump.patch,
        ),
      );
    }
    if (previous.mermaidDiagram.trim() != current.mermaidDiagram.trim()) {
      changes.add(
        const ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: '~ Diagramme Mermaid mis à jour',
          impact: SemVerBump.patch,
        ),
      );
    }

    return List<ArtifactChangeEntry>.unmodifiable(changes);
  }

  /// Analyse l'évolution complète de [domain] par rapport à [baselineOverride]
  /// (ou [FunctionalDomain.activeBaselineSnapshot]) et propage transitivement
  /// les impacts sur le graphe `ValueObjects -> Modèles -> UseCases -> Sagas`.
  static DomainEvolutionReport analyzeDomain({
    required FunctionalDomain domain,
    DomainCatalog? catalog,
    DomainIterationSnapshot? baselineOverride,
  }) {
    final baseline = baselineOverride ?? domain.activeBaselineSnapshot;
    final resolvedVos = _resolveVisibleValueObjects(domain, catalog);
    final currentModels = _extractCurrentModels(domain);
    final currentUseCases =
        domain.useCaseOrchestration?.useCases ??
        const <ApplicationUseCaseSpec>[];
    final currentSagas =
        domain.useCaseOrchestration?.sagas ?? const <OrchestrationSagaSpec>[];

    if (baseline == null) {
      return DomainEvolutionReport(
        domainId: domain.id,
        valueObjects: <String, ArtifactEvolutionReport>{
          for (final item in resolvedVos)
            item.spec.id: ArtifactEvolutionReport(
              kind: DesignArtifactKind.valueObject,
              id: item.spec.id,
              name: item.spec.technicalName,
              subtitle: item.spec.name != item.spec.technicalName
                  ? item.spec.name
                  : '',
              valueObjectScope: item.scope,
              state: ArtifactEvolutionState.noBaseline,
              currentVersion: item.spec.version,
            ),
        },
        models: <String, ArtifactEvolutionReport>{
          for (final m in currentModels)
            m.entryId: ArtifactEvolutionReport(
              kind: DesignArtifactKind.model,
              id: m.entryId,
              name: m.name,
              subtitle: m.title.trim().isNotEmpty && m.title.trim() != m.name
                  ? m.title.trim()
                  : '',
              state: ArtifactEvolutionState.noBaseline,
              currentVersion: m.version,
            ),
        },
        useCases: <String, ArtifactEvolutionReport>{
          for (final uc in currentUseCases)
            uc.id: ArtifactEvolutionReport(
              kind: DesignArtifactKind.useCase,
              id: uc.id,
              name: _effectiveUseCaseName(uc),
              subtitle: _effectiveUseCaseSubtitle(uc),
              state: ArtifactEvolutionState.noBaseline,
              currentVersion: uc.version,
            ),
        },
        sagas: <String, ArtifactEvolutionReport>{
          for (final saga in currentSagas)
            saga.id: ArtifactEvolutionReport(
              kind: DesignArtifactKind.saga,
              id: saga.id,
              name: _effectiveSagaName(saga),
              subtitle: _effectiveSagaSubtitle(saga),
              state: ArtifactEvolutionState.noBaseline,
              currentVersion: saga.version,
            ),
        },
      );
    }

    final nodes = <String, _MutableArtifactNode>{};
    final removedArtifacts = <ArtifactEvolutionReport>[];

    // --- 1. Diff direct des Value Objects ---
    final matchedBaselineVoIds = <String>{};
    final voLookup = <String, _MutableArtifactNode>{};

    for (final resolved in resolvedVos) {
      final vo = resolved.spec;
      var baseVo = baseline.valueObjects[vo.id];
      if (baseVo != null) {
        matchedBaselineVoIds.add(baseVo.id);
      } else {
        final lowerTech = vo.technicalName.toLowerCase();
        for (final candidate in baseline.valueObjects.values) {
          if (!matchedBaselineVoIds.contains(candidate.id) &&
              candidate.spec.technicalName.toLowerCase() == lowerTech) {
            baseVo = candidate;
            matchedBaselineVoIds.add(candidate.id);
            break;
          }
        }
      }

      final key = _nodeKey(DesignArtifactKind.valueObject, vo.id);
      final changes = baseVo == null
          ? const <ArtifactChangeEntry>[]
          : diffValueObject(baseVo.spec, vo);
      final directBump = maxBumpOf(changes);
      final initialState = baseVo == null
          ? ArtifactEvolutionState.added
          : (changes.isEmpty
                ? ArtifactEvolutionState.unchanged
                : ArtifactEvolutionState.modified);
      final node = _MutableArtifactNode(
        key: key,
        kind: DesignArtifactKind.valueObject,
        id: vo.id,
        name: vo.technicalName,
        subtitle: vo.name != vo.technicalName ? vo.name : '',
        valueObjectScope: resolved.scope,
        state: initialState,
        baselineVersion: baseVo?.spec.version,
        currentVersion: vo.version,
        directBump: directBump,
        directChanges: changes,
        currentVo: vo,
        baselineVo: baseVo?.spec,
      );
      nodes[key] = node;
      voLookup[vo.id.toLowerCase()] = node;
      voLookup[vo.technicalName.toLowerCase()] = node;
      if (baseVo != null) {
        voLookup[baseVo.id.toLowerCase()] = node;
        voLookup[baseVo.spec.technicalName.toLowerCase()] = node;
      }
    }

    for (final baseVo in baseline.valueObjects.values) {
      if (matchedBaselineVoIds.contains(baseVo.id)) continue;
      final key = _nodeKey(DesignArtifactKind.valueObject, baseVo.id);
      final removedChanges = <ArtifactChangeEntry>[
        ArtifactChangeEntry(
          category: 'Suppression',
          summary: "- Value Object '${baseVo.spec.technicalName}' supprimé",
          impact: SemVerBump.major,
        ),
      ];
      final node = _MutableArtifactNode(
        key: key,
        kind: DesignArtifactKind.valueObject,
        id: baseVo.id,
        name: baseVo.spec.technicalName,
        subtitle: baseVo.spec.name != baseVo.spec.technicalName
            ? baseVo.spec.name
            : '',
        valueObjectScope: baseVo.scope,
        state: ArtifactEvolutionState.removed,
        baselineVersion: baseVo.spec.version,
        currentVersion: baseVo.spec.version,
        directBump: SemVerBump.major,
        directChanges: removedChanges,
        baselineVo: baseVo.spec,
      );
      nodes[key] = node;
      removedArtifacts.add(node.toReport(nodes));
      voLookup.putIfAbsent(baseVo.id.toLowerCase(), () => node);
      voLookup.putIfAbsent(baseVo.spec.technicalName.toLowerCase(), () => node);
    }

    // --- 2. Diff direct des Modèles & Contrats ---
    final matchedBaselineModelIds = <String>{};
    final modelLookup = <String, _MutableArtifactNode>{};
    final repoPortLookup = <String, _MutableArtifactNode>{};

    void registerModelAliases(
      _MutableArtifactNode node,
      SnapshotModelArtifact artifact, {
      required bool preferExisting,
    }) {
      void putAlias(Map<String, _MutableArtifactNode> map, String raw) {
        final trimmed = raw.trim().toLowerCase();
        if (trimmed.isEmpty) return;
        if (preferExisting) {
          map.putIfAbsent(trimmed, () => node);
        } else {
          map[trimmed] = node;
        }
      }

      putAlias(modelLookup, artifact.entryId);
      putAlias(modelLookup, artifact.name);
      putAlias(modelLookup, artifact.objectSpec.technicalName);
      final explicitRepo =
          artifact.domainLayerSpec.persistencePolicy.repositoryPortName;
      if (explicitRepo.trim().isNotEmpty) {
        putAlias(repoPortLookup, explicitRepo);
      }
      putAlias(
        repoPortLookup,
        '${artifact.objectSpec.technicalName}Repository',
      );
      putAlias(repoPortLookup, '${artifact.name}Repository');
    }

    for (final currModel in currentModels) {
      final baseModel = baseline.models[currModel.entryId];
      if (baseModel != null) {
        matchedBaselineModelIds.add(baseModel.entryId);
      }
      final key = _nodeKey(DesignArtifactKind.model, currModel.entryId);
      final changes = baseModel == null
          ? const <ArtifactChangeEntry>[]
          : diffModel(previous: baseModel, current: currModel);
      final directBump = maxBumpOf(changes);
      final initialState = baseModel == null
          ? ArtifactEvolutionState.added
          : (changes.isEmpty
                ? ArtifactEvolutionState.unchanged
                : ArtifactEvolutionState.modified);
      final node = _MutableArtifactNode(
        key: key,
        kind: DesignArtifactKind.model,
        id: currModel.entryId,
        name: currModel.name,
        subtitle:
            currModel.title.trim().isNotEmpty &&
                currModel.title.trim() != currModel.name
            ? currModel.title.trim()
            : '',
        state: initialState,
        baselineVersion: baseModel?.version,
        currentVersion: currModel.version,
        directBump: directBump,
        directChanges: changes,
        currentModel: currModel,
        baselineModel: baseModel,
      );
      nodes[key] = node;
      registerModelAliases(node, currModel, preferExisting: false);
      if (baseModel != null) {
        registerModelAliases(node, baseModel, preferExisting: true);
      }
    }

    for (final baseModel in baseline.models.values) {
      if (matchedBaselineModelIds.contains(baseModel.entryId)) continue;
      final key = _nodeKey(DesignArtifactKind.model, baseModel.entryId);
      final removedChanges = <ArtifactChangeEntry>[
        ArtifactChangeEntry(
          category: 'Suppression',
          summary: "- Modèle '${baseModel.name}' supprimé",
          impact: SemVerBump.major,
        ),
      ];
      final node = _MutableArtifactNode(
        key: key,
        kind: DesignArtifactKind.model,
        id: baseModel.entryId,
        name: baseModel.name,
        subtitle:
            baseModel.title.trim().isNotEmpty &&
                baseModel.title.trim() != baseModel.name
            ? baseModel.title.trim()
            : '',
        state: ArtifactEvolutionState.removed,
        baselineVersion: baseModel.version,
        currentVersion: baseModel.version,
        directBump: SemVerBump.major,
        directChanges: removedChanges,
        baselineModel: baseModel,
      );
      nodes[key] = node;
      removedArtifacts.add(node.toReport(nodes));
      registerModelAliases(node, baseModel, preferExisting: true);
    }

    // --- 3. Diff direct des Use Cases ---
    final matchedBaselineUcIds = <String>{};
    final ucNodes = <_MutableArtifactNode>[];

    for (final currUc in currentUseCases) {
      final baseUc = baseline.useCases[currUc.id];
      if (baseUc != null) {
        matchedBaselineUcIds.add(baseUc.id);
      }
      final key = _nodeKey(DesignArtifactKind.useCase, currUc.id);
      final changes = baseUc == null
          ? const <ArtifactChangeEntry>[]
          : diffUseCase(baseUc, currUc);
      final directBump = maxBumpOf(changes);
      final initialState = baseUc == null
          ? ArtifactEvolutionState.added
          : (changes.isEmpty
                ? ArtifactEvolutionState.unchanged
                : ArtifactEvolutionState.modified);
      final node = _MutableArtifactNode(
        key: key,
        kind: DesignArtifactKind.useCase,
        id: currUc.id,
        name: _effectiveUseCaseName(currUc),
        subtitle: _effectiveUseCaseSubtitle(currUc),
        state: initialState,
        baselineVersion: baseUc?.version,
        currentVersion: currUc.version,
        directBump: directBump,
        directChanges: changes,
        currentUseCase: currUc,
        baselineUseCase: baseUc,
      );
      nodes[key] = node;
      ucNodes.add(node);
    }

    for (final baseUc in baseline.useCases.values) {
      if (matchedBaselineUcIds.contains(baseUc.id)) continue;
      final key = _nodeKey(DesignArtifactKind.useCase, baseUc.id);
      final removedChanges = <ArtifactChangeEntry>[
        ArtifactChangeEntry(
          category: 'Suppression',
          summary: "- Use Case '${_effectiveUseCaseName(baseUc)}' supprimé",
          impact: SemVerBump.major,
        ),
      ];
      final node = _MutableArtifactNode(
        key: key,
        kind: DesignArtifactKind.useCase,
        id: baseUc.id,
        name: _effectiveUseCaseName(baseUc),
        subtitle: _effectiveUseCaseSubtitle(baseUc),
        state: ArtifactEvolutionState.removed,
        baselineVersion: baseUc.version,
        currentVersion: baseUc.version,
        directBump: SemVerBump.major,
        directChanges: removedChanges,
        baselineUseCase: baseUc,
      );
      nodes[key] = node;
      removedArtifacts.add(node.toReport(nodes));
      ucNodes.add(node);
    }

    // --- 4. Diff direct des Sagas ---
    final matchedBaselineSagaIds = <String>{};
    final activeSagaNodes = <_MutableArtifactNode>[];

    for (final currSaga in currentSagas) {
      final baseSaga = baseline.sagas[currSaga.id];
      if (baseSaga != null) {
        matchedBaselineSagaIds.add(baseSaga.id);
      }
      final key = _nodeKey(DesignArtifactKind.saga, currSaga.id);
      final changes = baseSaga == null
          ? const <ArtifactChangeEntry>[]
          : diffSaga(baseSaga, currSaga);
      final directBump = maxBumpOf(changes);
      final initialState = baseSaga == null
          ? ArtifactEvolutionState.added
          : (changes.isEmpty
                ? ArtifactEvolutionState.unchanged
                : ArtifactEvolutionState.modified);
      final node = _MutableArtifactNode(
        key: key,
        kind: DesignArtifactKind.saga,
        id: currSaga.id,
        name: _effectiveSagaName(currSaga),
        subtitle: _effectiveSagaSubtitle(currSaga),
        state: initialState,
        baselineVersion: baseSaga?.version,
        currentVersion: currSaga.version,
        directBump: directBump,
        directChanges: changes,
        currentSaga: currSaga,
        baselineSaga: baseSaga,
      );
      nodes[key] = node;
      activeSagaNodes.add(node);
    }

    for (final baseSaga in baseline.sagas.values) {
      if (matchedBaselineSagaIds.contains(baseSaga.id)) continue;
      final key = _nodeKey(DesignArtifactKind.saga, baseSaga.id);
      final removedChanges = <ArtifactChangeEntry>[
        ArtifactChangeEntry(
          category: 'Suppression',
          summary: "- Saga '${_effectiveSagaName(baseSaga)}' supprimée",
          impact: SemVerBump.major,
        ),
      ];
      final node = _MutableArtifactNode(
        key: key,
        kind: DesignArtifactKind.saga,
        id: baseSaga.id,
        name: _effectiveSagaName(baseSaga),
        subtitle: _effectiveSagaSubtitle(baseSaga),
        state: ArtifactEvolutionState.removed,
        baselineVersion: baseSaga.version,
        currentVersion: baseSaga.version,
        directBump: SemVerBump.major,
        directChanges: removedChanges,
        baselineSaga: baseSaga,
      );
      nodes[key] = node;
      removedArtifacts.add(node.toReport(nodes));
    }

    // --- 5. Propagation transitive des impacts ---
    // Étape 5a : ValueObject V1 -> ValueObject composite V2 (point fixe).
    final activeVoNodes = [
      for (final r in resolvedVos)
        nodes[_nodeKey(DesignArtifactKind.valueObject, r.spec.id)]!,
    ];
    var voChanged = true;
    while (voChanged) {
      voChanged = false;
      for (final voNode in activeVoNodes) {
        final vo = voNode.currentVo!;
        if (!vo.isComposite) continue;
        final refs = _collectVoRefsFromAttributes(vo.fields);
        for (final ref in refs) {
          final target = voLookup[ref.toLowerCase()];
          if (target != null && voNode.tryPropagateFrom(target)) {
            voChanged = true;
          }
        }
      }
    }

    // Étape 5b : ValueObject -> Modèle, puis Modèle M1 -> Modèle M2 (point fixe).
    final activeModelNodes = [
      for (final m in currentModels)
        nodes[_nodeKey(DesignArtifactKind.model, m.entryId)]!,
    ];
    for (final modelNode in activeModelNodes) {
      final model = modelNode.currentModel!;
      final voRefs = _collectVoRefsFromAttributes(model.objectSpec.attributes);
      for (final ref in voRefs) {
        final targetVo = voLookup[ref.toLowerCase()];
        if (targetVo != null) {
          modelNode.tryPropagateFrom(targetVo);
        }
      }
    }

    var modelChanged = true;
    while (modelChanged) {
      modelChanged = false;
      for (final modelNode in activeModelNodes) {
        final model = modelNode.currentModel!;
        final modelRefs = _collectModelRefs(model);
        for (final ref in modelRefs) {
          final targetModel = modelLookup[ref.toLowerCase()];
          if (targetModel != null && modelNode.tryPropagateFrom(targetModel)) {
            modelChanged = true;
          }
        }
      }
    }

    // Étape 5c : Modèle / ValueObject -> Use Case.
    final activeUcNodes = [
      for (final uc in currentUseCases)
        nodes[_nodeKey(DesignArtifactKind.useCase, uc.id)]!,
    ];
    for (final ucNode in activeUcNodes) {
      final uc = ucNode.currentUseCase!;
      final targetAgg = uc.targetAggregate.trim().toLowerCase();
      if (targetAgg.isNotEmpty) {
        final aggNode = modelLookup[targetAgg];
        if (aggNode != null) {
          ucNode.tryPropagateFrom(aggNode);
        }
      }
      for (final port in uc.outboundPorts) {
        final portKey = port.trim().toLowerCase();
        if (portKey.isEmpty) continue;
        final portOwner = repoPortLookup[portKey];
        if (portOwner != null) {
          ucNode.tryPropagateFrom(portOwner);
        }
      }
      final fieldTypeTokens = <String>{
        ..._collectUseCaseFieldTypeTokens(uc.triggerInputs),
        ..._collectUseCaseFieldTypeTokens(uc.outputs),
      };
      for (final token in fieldTypeTokens) {
        final lower = token.toLowerCase();
        final matchedVo = voLookup[lower];
        if (matchedVo != null) {
          ucNode.tryPropagateFrom(matchedVo);
        }
        final matchedModel = modelLookup[lower];
        if (matchedModel != null) {
          ucNode.tryPropagateFrom(matchedModel);
        }
      }
    }

    // Étape 5d : Use Case -> Saga.
    for (final sagaNode in activeSagaNodes) {
      final saga = sagaNode.currentSaga!;
      for (final ucNode in ucNodes) {
        if (!ucNode.isPropagatingSource) continue;
        if (_sagaReferencesUseCase(saga, ucNode)) {
          sagaNode.tryPropagateFrom(ucNode);
        }
      }
    }

    return DomainEvolutionReport(
      domainId: domain.id,
      baseline: baseline,
      valueObjects: <String, ArtifactEvolutionReport>{
        for (final node in activeVoNodes) node.id: node.toReport(nodes),
      },
      models: <String, ArtifactEvolutionReport>{
        for (final node in activeModelNodes) node.id: node.toReport(nodes),
      },
      useCases: <String, ArtifactEvolutionReport>{
        for (final node in activeUcNodes) node.id: node.toReport(nodes),
      },
      sagas: <String, ArtifactEvolutionReport>{
        for (final node in activeSagaNodes) node.id: node.toReport(nodes),
      },
      removedArtifacts: removedArtifacts,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers internes de diff
  // ---------------------------------------------------------------------------

  static void _diffEnumValues(
    List<ArtifactChangeEntry> out,
    List<String> prevValues,
    List<String> currValues, {
    required String targetLabel,
  }) {
    final prevSet = prevValues.toSet();
    final currSet = currValues.toSet();
    final removed = prevValues.where((v) => !currSet.contains(v)).toList();
    final added = currValues.where((v) => !prevSet.contains(v)).toList();
    for (final val in removed) {
      out.add(
        ArtifactChangeEntry(
          category: 'Énumération',
          summary: "- $targetLabel : valeur '$val' supprimée",
          impact: SemVerBump.major,
        ),
      );
    }
    for (final val in added) {
      out.add(
        ArtifactChangeEntry(
          category: 'Énumération',
          summary: "+ $targetLabel : valeur '$val' ajoutée",
          impact: SemVerBump.minor,
        ),
      );
    }
  }

  static void _diffCrossFieldRules(
    List<ArtifactChangeEntry> out,
    List<String> prevRules,
    List<String> currRules,
  ) {
    if (listEquals(prevRules, currRules)) return;
    final prevSet = prevRules.toSet();
    final currSet = currRules.toSet();
    final added = currRules.where((r) => !prevSet.contains(r)).toList();
    final removed = prevRules.where((r) => !currSet.contains(r)).toList();

    if (added.isNotEmpty &&
        removed.isNotEmpty &&
        added.length == removed.length) {
      for (var i = 0; i < added.length; i++) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ Règle inter-champs modifiée : '${removed[i]}' → '${added[i]}'",
            impact: SemVerBump.major,
          ),
        );
      }
      return;
    }
    for (final rule in added) {
      out.add(
        ArtifactChangeEntry(
          category: 'Contrainte',
          summary: "+ Règle inter-champs ajoutée : '$rule'",
          impact: SemVerBump.major,
        ),
      );
    }
    for (final rule in removed) {
      out.add(
        ArtifactChangeEntry(
          category: 'Contrainte',
          summary: "- Règle inter-champs retirée : '$rule'",
          impact: SemVerBump.minor,
        ),
      );
    }
  }

  static void _diffSchemaConstraints(
    List<ArtifactChangeEntry> out,
    JsonSchemaConstraints prev,
    JsonSchemaConstraints curr, {
    required String targetLabel,
  }) {
    if (prev == curr) return;

    void diffLowerBound(
      String keyword,
      num? p,
      num? c, {
      bool ignoreZeroAdd = false,
    }) {
      if (p == c) return;
      if (p == null && c != null) {
        if (ignoreZeroAdd && c <= 0) return;
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary: "~ $targetLabel : $keyword défini à $c (durcissement)",
            impact: SemVerBump.major,
          ),
        );
      } else if (p != null && c == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary: "~ $targetLabel : $keyword $p retiré (assouplissement)",
            impact: SemVerBump.minor,
          ),
        );
      } else if (p != null && c != null) {
        final tightened = c > p;
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ $targetLabel : $keyword $p → $c (${tightened ? 'durcissement' : 'assouplissement'})",
            impact: tightened ? SemVerBump.major : SemVerBump.minor,
          ),
        );
      }
    }

    void diffUpperBound(String keyword, num? p, num? c) {
      if (p == c) return;
      if (p == null && c != null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary: "~ $targetLabel : $keyword défini à $c (durcissement)",
            impact: SemVerBump.major,
          ),
        );
      } else if (p != null && c == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary: "~ $targetLabel : $keyword $p retiré (assouplissement)",
            impact: SemVerBump.minor,
          ),
        );
      } else if (p != null && c != null) {
        final tightened = c < p;
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ $targetLabel : $keyword $p → $c (${tightened ? 'durcissement' : 'assouplissement'})",
            impact: tightened ? SemVerBump.major : SemVerBump.minor,
          ),
        );
      }
    }

    diffLowerBound('minimum', prev.minimum, curr.minimum);
    diffUpperBound('maximum', prev.maximum, curr.maximum);
    diffLowerBound(
      'exclusiveMinimum',
      prev.exclusiveMinimum,
      curr.exclusiveMinimum,
    );
    diffUpperBound(
      'exclusiveMaximum',
      prev.exclusiveMaximum,
      curr.exclusiveMaximum,
    );
    diffLowerBound(
      'minLength',
      prev.minLength,
      curr.minLength,
      ignoreZeroAdd: true,
    );
    diffUpperBound('maxLength', prev.maxLength, curr.maxLength);
    diffLowerBound(
      'minItems',
      prev.minItems,
      curr.minItems,
      ignoreZeroAdd: true,
    );
    diffUpperBound('maxItems', prev.maxItems, curr.maxItems);
    diffLowerBound(
      'minProperties',
      prev.minProperties,
      curr.minProperties,
      ignoreZeroAdd: true,
    );
    diffUpperBound('maxProperties', prev.maxProperties, curr.maxProperties);
    diffLowerBound(
      'minContains',
      prev.minContains,
      curr.minContains,
      ignoreZeroAdd: true,
    );
    diffUpperBound('maxContains', prev.maxContains, curr.maxContains);

    if (prev.multipleOf != curr.multipleOf) {
      if (prev.multipleOf == null && curr.multipleOf != null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ $targetLabel : multipleOf défini à ${curr.multipleOf} (durcissement)",
            impact: SemVerBump.major,
          ),
        );
      } else if (prev.multipleOf != null && curr.multipleOf == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ $targetLabel : multipleOf ${prev.multipleOf} retiré (assouplissement)",
            impact: SemVerBump.minor,
          ),
        );
      } else {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ $targetLabel : multipleOf ${prev.multipleOf} → ${curr.multipleOf}",
            impact: SemVerBump.major,
          ),
        );
      }
    }

    String? cleanOpt(String? raw) =>
        (raw == null || raw.trim().isEmpty) ? null : raw.trim();

    final prevPattern = cleanOpt(prev.pattern);
    final currPattern = cleanOpt(curr.pattern);
    if (prevPattern != currPattern) {
      if (currPattern == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ $targetLabel : pattern '$prevPattern' retiré (assouplissement)",
            impact: SemVerBump.minor,
          ),
        );
      } else {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ $targetLabel : pattern '${prevPattern ?? 'aucun'}' → '$currPattern' (durcissement)",
            impact: SemVerBump.major,
          ),
        );
      }
    }

    final prevFormat = cleanOpt(prev.format);
    final currFormat = cleanOpt(curr.format);
    if (prevFormat != currFormat) {
      if (currFormat == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ $targetLabel : format '$prevFormat' retiré (assouplissement)",
            impact: SemVerBump.minor,
          ),
        );
      } else {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary:
                "~ $targetLabel : format '${prevFormat ?? 'aucun'}' → '$currFormat' (durcissement)",
            impact: SemVerBump.major,
          ),
        );
      }
    }

    final prevUniqueItems = prev.uniqueItems == true;
    final currUniqueItems = curr.uniqueItems == true;
    if (prevUniqueItems != currUniqueItems) {
      out.add(
        ArtifactChangeEntry(
          category: 'Contrainte',
          summary: currUniqueItems
              ? '~ $targetLabel : uniqueItems activé (durcissement)'
              : '~ $targetLabel : uniqueItems désactivé (assouplissement)',
          impact: currUniqueItems ? SemVerBump.major : SemVerBump.minor,
        ),
      );
    }

    if (prev.hasConst != curr.hasConst ||
        (curr.hasConst && prev.constValue != curr.constValue)) {
      out.add(
        ArtifactChangeEntry(
          category: 'Contrainte',
          summary: !curr.hasConst
              ? '~ $targetLabel : valeur constante retirée (assouplissement)'
              : '~ $targetLabel : valeur constante définie ou modifiée (durcissement)',
          impact: !curr.hasConst ? SemVerBump.minor : SemVerBump.major,
        ),
      );
    }

    final structuralChanged =
        cleanOpt(prev.contentMediaType) != cleanOpt(curr.contentMediaType) ||
        cleanOpt(prev.contentEncoding) != cleanOpt(curr.contentEncoding) ||
        !mapEquals(prev.contains, curr.contains) ||
        !listEquals(prev.prefixItems, curr.prefixItems) ||
        prev.additionalProperties != curr.additionalProperties ||
        !mapEquals(prev.patternProperties, curr.patternProperties) ||
        !mapEquals(prev.propertyNames, curr.propertyNames) ||
        !mapEquals(prev.dependentRequired, curr.dependentRequired) ||
        !mapEquals(prev.dependentSchemas, curr.dependentSchemas) ||
        !listEquals(prev.oneOf, curr.oneOf) ||
        !listEquals(prev.anyOf, curr.anyOf) ||
        !listEquals(prev.allOf, curr.allOf) ||
        !mapEquals(prev.not, curr.not) ||
        !mapEquals(prev.ifSchema, curr.ifSchema) ||
        !mapEquals(prev.thenSchema, curr.thenSchema) ||
        !mapEquals(prev.elseSchema, curr.elseSchema);
    if (structuralChanged) {
      out.add(
        ArtifactChangeEntry(
          category: 'Contrainte',
          summary:
              '~ $targetLabel : schémas conditionnels ou structurels modifiés',
          impact: SemVerBump.major,
        ),
      );
    }

    final metadataChanged =
        cleanOpt(prev.title) != cleanOpt(curr.title) ||
        cleanOpt(prev.comment) != cleanOpt(curr.comment) ||
        !listEquals(prev.examples, curr.examples) ||
        prev.readOnly != curr.readOnly ||
        prev.writeOnly != curr.writeOnly ||
        prev.deprecated != curr.deprecated ||
        !mapEquals(prev.extraKeywords, curr.extraKeywords);
    if (metadataChanged) {
      out.add(
        ArtifactChangeEntry(
          category: 'Métadonnée',
          summary:
              '~ $targetLabel : métadonnées ou exemples JSON Schema mis à jour',
          impact: SemVerBump.patch,
        ),
      );
    }
  }

  static String _formatAttrType(BusinessAttribute attr) {
    final base = switch (attr.type) {
      BusinessAttributeType.valueObject when attr.valueObjectId.isNotEmpty =>
        'VO:${attr.valueObjectId}',
      BusinessAttributeType.reference when attr.referenceObjectId.isNotEmpty =>
        'ref:${attr.referenceObjectId}',
      _ => attr.type.dslKeyword,
    };
    return attr.isArray ? '$base[]' : base;
  }

  static void _diffAttributes(
    List<ArtifactChangeEntry> out,
    List<BusinessAttribute> prevAttrs,
    List<BusinessAttribute> currAttrs, {
    required String nounSingular,
    required String pathPrefix,
  }) {
    final matchedPrevIds = <String>{};

    BusinessAttribute? findPrev(BusinessAttribute curr) {
      for (final p in prevAttrs) {
        if (p.id == curr.id && !matchedPrevIds.contains(p.id)) {
          matchedPrevIds.add(p.id);
          return p;
        }
      }
      final lowerName = curr.name.toLowerCase();
      for (final p in prevAttrs) {
        if (!matchedPrevIds.contains(p.id) &&
            p.name.toLowerCase() == lowerName) {
          matchedPrevIds.add(p.id);
          return p;
        }
      }
      return null;
    }

    final matchedPairs = <({BusinessAttribute prev, BusinessAttribute curr})>[];
    final addedAttrs = <BusinessAttribute>[];

    for (final curr in currAttrs) {
      final prev = findPrev(curr);
      if (prev == null) {
        addedAttrs.add(curr);
      } else {
        matchedPairs.add((prev: prev, curr: curr));
      }
    }

    for (final prev in prevAttrs) {
      if (matchedPrevIds.contains(prev.id)) continue;
      final fullName = '$pathPrefix${prev.name}';
      out.add(
        ArtifactChangeEntry(
          category: nounSingular,
          summary: "- $nounSingular '$fullName' supprimé",
          impact: SemVerBump.major,
        ),
      );
    }

    for (final added in addedAttrs) {
      final fullName = '$pathPrefix${added.name}';
      final reqLabel = added.required ? 'obligatoire' : 'optionnel';
      out.add(
        ArtifactChangeEntry(
          category: nounSingular,
          summary:
              "+ $nounSingular $reqLabel '$fullName' (${_formatAttrType(added)})",
          impact: added.required ? SemVerBump.major : SemVerBump.minor,
        ),
      );
    }

    for (final pair in matchedPairs) {
      final prev = pair.prev;
      final curr = pair.curr;
      final fullName = '$pathPrefix${curr.name}';

      if (prev.name != curr.name) {
        out.add(
          ArtifactChangeEntry(
            category: nounSingular,
            summary:
                "~ $nounSingular '$pathPrefix${prev.name}' renommé en '$fullName'",
            impact: SemVerBump.major,
          ),
        );
      }
      if (prev.type != curr.type ||
          prev.valueObjectId != curr.valueObjectId ||
          prev.referenceObjectId != curr.referenceObjectId ||
          prev.isArray != curr.isArray) {
        out.add(
          ArtifactChangeEntry(
            category: nounSingular,
            summary:
                "~ $nounSingular '$fullName' : type ${_formatAttrType(prev)} → ${_formatAttrType(curr)}",
            impact: SemVerBump.major,
          ),
        );
      }
      if (prev.required != curr.required) {
        out.add(
          ArtifactChangeEntry(
            category: nounSingular,
            summary: curr.required
                ? "~ $nounSingular '$fullName' devenu obligatoire (durcissement)"
                : "~ $nounSingular '$fullName' devenu optionnel (assouplissement)",
            impact: curr.required ? SemVerBump.major : SemVerBump.minor,
          ),
        );
      }
      if (prev.nullable != curr.nullable) {
        out.add(
          ArtifactChangeEntry(
            category: nounSingular,
            summary: curr.nullable
                ? "~ $nounSingular '$fullName' rendu nullable (assouplissement)"
                : "~ $nounSingular '$fullName' rendu non-nullable (durcissement)",
            impact: curr.nullable ? SemVerBump.minor : SemVerBump.major,
          ),
        );
      }
      if (prev.unique != curr.unique) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrainte',
            summary: curr.unique
                ? "~ $nounSingular '$fullName' : unicité activée (durcissement)"
                : "~ $nounSingular '$fullName' : unicité retirée (assouplissement)",
            impact: curr.unique ? SemVerBump.major : SemVerBump.minor,
          ),
        );
      }
      _diffEnumValues(
        out,
        prev.enumValues,
        curr.enumValues,
        targetLabel: "$nounSingular '$fullName'",
      );
      _diffSchemaConstraints(
        out,
        prev.schemaConstraints,
        curr.schemaConstraints,
        targetLabel: "$nounSingular '$fullName'",
      );
      if (prev.children.isNotEmpty || curr.children.isNotEmpty) {
        _diffAttributes(
          out,
          prev.children,
          curr.children,
          nounSingular: nounSingular,
          pathPrefix: '$fullName.',
        );
      }
      if (prev.description.trim() != curr.description.trim() ||
          prev.constraints.trim() != curr.constraints.trim() ||
          prev.defaultValue != curr.defaultValue ||
          prev.estimatedMaxRows != curr.estimatedMaxRows) {
        out.add(
          ArtifactChangeEntry(
            category: 'Métadonnée',
            summary:
                "~ $nounSingular '$fullName' : description ou métadonnées mises à jour",
            impact: SemVerBump.patch,
          ),
        );
      }
    }
  }

  static void _diffObjectAndDomainLayer(
    List<ArtifactChangeEntry> out, {
    required BusinessObjectSpec previousObject,
    required BusinessObjectSpec currentObject,
    required HexagonalDomainLayerSpec previousDomainLayer,
    required HexagonalDomainLayerSpec currentDomainLayer,
    required bool includeObjectIdentityDiff,
  }) {
    if (includeObjectIdentityDiff) {
      if (previousObject.technicalName != currentObject.technicalName) {
        out.add(
          ArtifactChangeEntry(
            category: 'Modèle',
            summary:
                "~ Nom technique '${previousObject.technicalName}' → '${currentObject.technicalName}'",
            impact: SemVerBump.major,
          ),
        );
      }
      if (previousObject.name.trim() != currentObject.name.trim()) {
        out.add(
          ArtifactChangeEntry(
            category: 'Métadonnée',
            summary:
                "~ Libellé métier '${previousObject.name}' → '${currentObject.name}'",
            impact: SemVerBump.patch,
          ),
        );
      }
    }

    if (previousObject.aggregateRoot != currentObject.aggregateRoot) {
      out.add(
        ArtifactChangeEntry(
          category: 'Modèle',
          summary:
              '~ Statut Aggregate Root : ${previousObject.aggregateRoot} → ${currentObject.aggregateRoot}',
          impact: SemVerBump.major,
        ),
      );
    }
    if (previousObject.description.trim() != currentObject.description.trim()) {
      out.add(
        const ArtifactChangeEntry(
          category: 'Métadonnée',
          summary: '~ Description du modèle mise à jour',
          impact: SemVerBump.patch,
        ),
      );
    }

    _diffAttributes(
      out,
      previousObject.attributes,
      currentObject.attributes,
      nounSingular: 'Attribut',
      pathPrefix: '',
    );
    _diffRelations(out, previousObject.relations, currentObject.relations);
    _diffLifecycle(
      out,
      previousStates: previousObject.lifecycleStates,
      currentStates: currentObject.lifecycleStates,
      previousTransitions: previousObject.lifecycleTransitions,
      currentTransitions: currentObject.lifecycleTransitions,
    );
    _diffDomainLayer(out, previousDomainLayer, currentDomainLayer);
  }

  static void _diffRelations(
    List<ArtifactChangeEntry> out,
    List<BusinessRelation> prevRels,
    List<BusinessRelation> currRels,
  ) {
    final matchedPrevIds = <String>{};
    for (final curr in currRels) {
      BusinessRelation? prev;
      for (final p in prevRels) {
        if (!matchedPrevIds.contains(p.id) &&
            (p.id == curr.id ||
                p.name.toLowerCase() == curr.name.toLowerCase())) {
          prev = p;
          matchedPrevIds.add(p.id);
          break;
        }
      }
      if (prev == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Relation',
            summary:
                "+ Relation '${curr.name}' (${curr.cardinality.symbol} → ${curr.targetObjectId})",
            impact: curr.required ? SemVerBump.major : SemVerBump.minor,
          ),
        );
        continue;
      }
      if (prev.name != curr.name ||
          prev.targetObjectId != curr.targetObjectId ||
          prev.cardinality != curr.cardinality ||
          (!prev.required && curr.required)) {
        out.add(
          ArtifactChangeEntry(
            category: 'Relation',
            summary: "~ Relation '${curr.name}' : contrat relationnel modifié",
            impact: SemVerBump.major,
          ),
        );
      } else if (prev.required && !curr.required) {
        out.add(
          ArtifactChangeEntry(
            category: 'Relation',
            summary: "~ Relation '${curr.name}' devenue optionnelle",
            impact: SemVerBump.minor,
          ),
        );
      } else if (prev.description != curr.description ||
          prev.inverseName != curr.inverseName) {
        out.add(
          ArtifactChangeEntry(
            category: 'Métadonnée',
            summary: "~ Relation '${curr.name}' : documentation mise à jour",
            impact: SemVerBump.patch,
          ),
        );
      }
    }

    for (final prev in prevRels) {
      if (matchedPrevIds.contains(prev.id)) continue;
      out.add(
        ArtifactChangeEntry(
          category: 'Relation',
          summary: "- Relation '${prev.name}' supprimée",
          impact: SemVerBump.major,
        ),
      );
    }
  }

  static void _diffLifecycle(
    List<ArtifactChangeEntry> out, {
    required List<LifecycleState> previousStates,
    required List<LifecycleState> currentStates,
    required List<LifecycleTransition> previousTransitions,
    required List<LifecycleTransition> currentTransitions,
  }) {
    final prevStateMap = <String, LifecycleState>{
      for (final s in previousStates) s.name.toLowerCase(): s,
    };
    final currStateMap = <String, LifecycleState>{
      for (final s in currentStates) s.name.toLowerCase(): s,
    };

    for (final entry in prevStateMap.entries) {
      if (!currStateMap.containsKey(entry.key)) {
        out.add(
          ArtifactChangeEntry(
            category: 'Cycle de vie',
            summary: "- État '${entry.value.name}' supprimé",
            impact: SemVerBump.major,
          ),
        );
      }
    }
    for (final entry in currStateMap.entries) {
      final prev = prevStateMap[entry.key];
      final curr = entry.value;
      if (prev == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Cycle de vie',
            summary: "+ État '${curr.name}' ajouté",
            impact: SemVerBump.minor,
          ),
        );
      } else if (prev.isInitial != curr.isInitial ||
          prev.isTerminal != curr.isTerminal) {
        out.add(
          ArtifactChangeEntry(
            category: 'Cycle de vie',
            summary: "~ État '${curr.name}' : rôle initial/terminal modifié",
            impact: SemVerBump.major,
          ),
        );
      } else if (prev.label != curr.label ||
          prev.description != curr.description) {
        out.add(
          ArtifactChangeEntry(
            category: 'Métadonnée',
            summary:
                "~ État '${curr.name}' : libellé ou description mis à jour",
            impact: SemVerBump.patch,
          ),
        );
      }
    }

    final matchedPrevTr = <String>{};
    for (final curr in currentTransitions) {
      LifecycleTransition? prev;
      for (final p in previousTransitions) {
        if (!matchedPrevTr.contains(p.id) &&
            (p.id == curr.id ||
                (p.fromState == curr.fromState && p.toState == curr.toState))) {
          prev = p;
          matchedPrevTr.add(p.id);
          break;
        }
      }
      if (prev == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Cycle de vie',
            summary:
                "+ Transition '${curr.fromState} → ${curr.toState}' ajoutée",
            impact: SemVerBump.minor,
          ),
        );
      } else if (prev.fromState != curr.fromState ||
          prev.toState != curr.toState ||
          prev.guardSummary != curr.guardSummary) {
        out.add(
          ArtifactChangeEntry(
            category: 'Cycle de vie',
            summary:
                "~ Transition '${curr.fromState} → ${curr.toState}' modifiée",
            impact: SemVerBump.major,
          ),
        );
      } else if (prev.trigger != curr.trigger) {
        out.add(
          ArtifactChangeEntry(
            category: 'Cycle de vie',
            summary:
                "~ Transition '${curr.fromState} → ${curr.toState}' : déclencheur mis à jour",
            impact: SemVerBump.minor,
          ),
        );
      }
    }
    for (final prev in previousTransitions) {
      if (matchedPrevTr.contains(prev.id)) continue;
      out.add(
        ArtifactChangeEntry(
          category: 'Cycle de vie',
          summary:
              "- Transition '${prev.fromState} → ${prev.toState}' supprimée",
          impact: SemVerBump.major,
        ),
      );
    }
  }

  static void _diffDomainLayer(
    List<ArtifactChangeEntry> out,
    HexagonalDomainLayerSpec prev,
    HexagonalDomainLayerSpec curr,
  ) {
    if (prev == curr) return;

    // 1. Invariants (ajout/modification = major, retrait = minor, doc = patch).
    final matchedInv = <String>{};
    for (final c in curr.invariants) {
      DomainInvariantSpec? p;
      for (final candidate in prev.invariants) {
        if (!matchedInv.contains(candidate.id) &&
            (candidate.id == c.id ||
                (c.code.isNotEmpty &&
                    candidate.code.toLowerCase() == c.code.toLowerCase()))) {
          p = candidate;
          matchedInv.add(candidate.id);
          break;
        }
      }
      if (p == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "+ Invariant '${c.title}' ajouté",
            impact: SemVerBump.major,
          ),
        );
      } else if (p != c) {
        final behaviorChanged =
            p.code != c.code ||
            p.methodSignature != c.methodSignature ||
            p.expression != c.expression ||
            !listEquals(p.rules, c.rules) ||
            !listEquals(p.associatedMethods, c.associatedMethods) ||
            !listEquals(p.relatedAttributes, c.relatedAttributes) ||
            p.violationError != c.violationError;
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: behaviorChanged
                ? "~ Invariant '${c.title}' modifié"
                : "~ Invariant '${c.title}' : documentation mise à jour",
            impact: behaviorChanged ? SemVerBump.major : SemVerBump.patch,
          ),
        );
      }
    }
    for (final p in prev.invariants) {
      if (!matchedInv.contains(p.id)) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "- Invariant '${p.title}' retiré",
            impact: SemVerBump.minor,
          ),
        );
      }
    }

    // 2. State changing methods.
    final matchedCmd = <String>{};
    for (final c in curr.stateChanges) {
      DomainStateChangeSpec? p;
      for (final candidate in prev.stateChanges) {
        if (!matchedCmd.contains(candidate.id) &&
            (candidate.id == c.id ||
                candidate.name.toLowerCase() == c.name.toLowerCase())) {
          p = candidate;
          matchedCmd.add(candidate.id);
          break;
        }
      }
      if (p == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "+ Méthode Domain '${c.name}' ajoutée",
            impact: SemVerBump.minor,
          ),
        );
      } else if (p != c) {
        final contractChanged =
            p.name != c.name ||
            p.methodSignature != c.methodSignature ||
            p.stateChangeRule != c.stateChangeRule ||
            !listEquals(p.rules, c.rules) ||
            !listEquals(p.associatedMethods, c.associatedMethods) ||
            !listEquals(p.parameters, c.parameters) ||
            !listEquals(p.preconditions, c.preconditions) ||
            !listEquals(p.mutations, c.mutations) ||
            !listEquals(p.fromStates, c.fromStates) ||
            p.toState != c.toState ||
            !listEquals(p.emittedEvents, c.emittedEvents) ||
            !listEquals(p.domainErrors, c.domainErrors) ||
            !listEquals(p.relatedAttributes, c.relatedAttributes);
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: contractChanged
                ? "~ Méthode Domain '${c.name}' : signature ou règles modifiées"
                : "~ Méthode Domain '${c.name}' : documentation mise à jour",
            impact: contractChanged ? SemVerBump.major : SemVerBump.patch,
          ),
        );
      }
    }
    for (final p in prev.stateChanges) {
      if (!matchedCmd.contains(p.id)) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "- Méthode Domain '${p.name}' supprimée",
            impact: SemVerBump.major,
          ),
        );
      }
    }

    // 3. Query methods.
    final matchedQry = <String>{};
    for (final c in curr.queries) {
      DomainQuerySpec? p;
      for (final candidate in prev.queries) {
        if (!matchedQry.contains(candidate.id) &&
            (candidate.id == c.id ||
                candidate.name.toLowerCase() == c.name.toLowerCase())) {
          p = candidate;
          matchedQry.add(candidate.id);
          break;
        }
      }
      if (p == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "+ Query Domain '${c.name}' ajoutée",
            impact: SemVerBump.minor,
          ),
        );
      } else if (p != c) {
        final contractChanged =
            p.name != c.name ||
            p.methodSignature != c.methodSignature ||
            !listEquals(p.rules, c.rules) ||
            !listEquals(p.associatedMethods, c.associatedMethods) ||
            !listEquals(p.parameters, c.parameters) ||
            p.returnType != c.returnType ||
            p.formula != c.formula ||
            !listEquals(p.relatedAttributes, c.relatedAttributes);
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: contractChanged
                ? "~ Query Domain '${c.name}' : signature ou formule modifiée"
                : "~ Query Domain '${c.name}' : documentation mise à jour",
            impact: contractChanged ? SemVerBump.major : SemVerBump.patch,
          ),
        );
      }
    }
    for (final p in prev.queries) {
      if (!matchedQry.contains(p.id)) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "- Query Domain '${p.name}' supprimée",
            impact: SemVerBump.major,
          ),
        );
      }
    }

    // 4. Policy Services.
    final matchedPol = <String>{};
    for (final c in curr.policyServices) {
      DomainPolicyServiceSpec? p;
      for (final candidate in prev.policyServices) {
        if (!matchedPol.contains(candidate.id) &&
            (candidate.id == c.id ||
                candidate.name.toLowerCase() == c.name.toLowerCase())) {
          p = candidate;
          matchedPol.add(candidate.id);
          break;
        }
      }
      if (p == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "+ Policy Service '${c.name}' ajouté",
            impact: SemVerBump.minor,
          ),
        );
      } else if (p != c) {
        final contractChanged =
            p.name != c.name ||
            p.methodSignature != c.methodSignature ||
            p.operation != c.operation ||
            !listEquals(p.collaborators, c.collaborators) ||
            !listEquals(p.rules, c.rules) ||
            !listEquals(p.associatedMethods, c.associatedMethods) ||
            !listEquals(p.relatedAttributes, c.relatedAttributes);
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: contractChanged
                ? "~ Policy Service '${c.name}' : contrat modifié"
                : "~ Policy Service '${c.name}' : documentation mise à jour",
            impact: contractChanged ? SemVerBump.major : SemVerBump.patch,
          ),
        );
      }
    }
    for (final p in prev.policyServices) {
      if (!matchedPol.contains(p.id)) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "- Policy Service '${p.name}' supprimé",
            impact: SemVerBump.major,
          ),
        );
      }
    }

    // 5. Factories.
    final matchedFac = <String>{};
    for (final c in curr.factories) {
      DomainFactorySpec? p;
      for (final candidate in prev.factories) {
        if (!matchedFac.contains(candidate.id) &&
            (candidate.id == c.id ||
                candidate.name.toLowerCase() == c.name.toLowerCase())) {
          p = candidate;
          matchedFac.add(candidate.id);
          break;
        }
      }
      if (p == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "+ Fabrique Domain '${c.name}' ajoutée",
            impact: SemVerBump.minor,
          ),
        );
      } else if (p != c) {
        final contractChanged =
            p.name != c.name ||
            p.methodSignature != c.methodSignature ||
            !listEquals(p.rules, c.rules) ||
            !listEquals(p.associatedMethods, c.associatedMethods) ||
            !listEquals(p.parameters, c.parameters) ||
            p.initialState != c.initialState ||
            !listEquals(p.enforcedInvariants, c.enforcedInvariants) ||
            !listEquals(p.emittedEvents, c.emittedEvents) ||
            !listEquals(p.relatedAttributes, c.relatedAttributes);
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: contractChanged
                ? "~ Fabrique Domain '${c.name}' : signature ou règles modifiées"
                : "~ Fabrique Domain '${c.name}' : documentation mise à jour",
            impact: contractChanged ? SemVerBump.major : SemVerBump.patch,
          ),
        );
      }
    }
    for (final p in prev.factories) {
      if (!matchedFac.contains(p.id)) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "- Fabrique Domain '${p.name}' supprimée",
            impact: SemVerBump.major,
          ),
        );
      }
    }

    // 6. Domain Events.
    final matchedEvt = <String>{};
    for (final c in curr.domainEvents) {
      DomainEventSpec? p;
      for (final candidate in prev.domainEvents) {
        if (!matchedEvt.contains(candidate.id) &&
            (candidate.id == c.id ||
                candidate.name.toLowerCase() == c.name.toLowerCase())) {
          p = candidate;
          matchedEvt.add(candidate.id);
          break;
        }
      }
      if (p == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "+ Événement Domain '${c.name}' ajouté",
            impact: SemVerBump.minor,
          ),
        );
      } else if (p != c) {
        final contractChanged =
            p.name != c.name ||
            p.methodSignature != c.methodSignature ||
            !listEquals(p.rules, c.rules) ||
            !listEquals(p.associatedMethods, c.associatedMethods) ||
            p.trigger != c.trigger ||
            !listEquals(p.payloadFields, c.payloadFields) ||
            p.contractEntryRef != c.contractEntryRef ||
            !listEquals(p.relatedAttributes, c.relatedAttributes);
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: contractChanged
                ? "~ Événement Domain '${c.name}' : payload ou contrat modifié"
                : "~ Événement Domain '${c.name}' : documentation mise à jour",
            impact: contractChanged ? SemVerBump.major : SemVerBump.patch,
          ),
        );
      }
    }
    for (final p in prev.domainEvents) {
      if (!matchedEvt.contains(p.id)) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: "- Événement Domain '${p.name}' supprimé",
            impact: SemVerBump.major,
          ),
        );
      }
    }

    // 7. Persistence Policy.
    final prevPol = prev.persistencePolicy;
    final currPol = curr.persistencePolicy;
    if (prevPol != currPol) {
      if (prevPol.repositoryPortName != currPol.repositoryPortName) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary:
                "~ Port Repository '${prevPol.repositoryPortName}' → '${currPol.repositoryPortName}'",
            impact: SemVerBump.major,
          ),
        );
      }
      if (prevPol.concurrencyStrategy != currPol.concurrencyStrategy) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary:
                "~ Stratégie de concurrence '${prevPol.concurrencyStrategy.label}' → '${currPol.concurrencyStrategy.label}'",
            impact: SemVerBump.major,
          ),
        );
      }
      if (prevPol.deletionStrategy != currPol.deletionStrategy) {
        out.add(
          ArtifactChangeEntry(
            category: 'Couche Domain',
            summary:
                "~ Stratégie de suppression '${prevPol.deletionStrategy.label}' → '${currPol.deletionStrategy.label}'",
            impact: SemVerBump.major,
          ),
        );
      }
      if (prevPol.aggregateBoundary != currPol.aggregateBoundary) {
        out.add(
          const ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: '~ Frontière transactionnelle d’agrégat modifiée',
            impact: SemVerBump.major,
          ),
        );
      }
      if (!listEquals(prevPol.rules, currPol.rules)) {
        out.add(
          const ArtifactChangeEntry(
            category: 'Couche Domain',
            summary: '~ Règles de persistance mises à jour',
            impact: SemVerBump.major,
          ),
        );
      }
      if (prevPol.consistencyNotes.trim() != currPol.consistencyNotes.trim()) {
        out.add(
          const ArtifactChangeEntry(
            category: 'Métadonnée',
            summary: '~ Notes de cohérence de persistance mises à jour',
            impact: SemVerBump.patch,
          ),
        );
      }

      final matchedRepoMethods = <String>{};
      for (final c in currPol.portMethods) {
        DomainRepositoryMethodSpec? p;
        for (final candidate in prevPol.portMethods) {
          if (!matchedRepoMethods.contains(candidate.id) &&
              (candidate.id == c.id ||
                  (c.name.isNotEmpty &&
                      candidate.name.toLowerCase() == c.name.toLowerCase()) ||
                  (c.effectiveMethodSignature.isNotEmpty &&
                      candidate.effectiveMethodSignature ==
                          c.effectiveMethodSignature))) {
            p = candidate;
            matchedRepoMethods.add(candidate.id);
            break;
          }
        }
        if (p == null) {
          out.add(
            ArtifactChangeEntry(
              category: 'Couche Domain',
              summary: "+ Méthode Repository '${c.effectiveTitle}' ajoutée",
              impact: SemVerBump.minor,
            ),
          );
        } else if (p != c) {
          final contractChanged =
              p.name != c.name ||
              p.methodSignature != c.methodSignature ||
              p.signature != c.signature ||
              p.category != c.category ||
              !listEquals(p.rules, c.rules) ||
              !listEquals(p.associatedMethods, c.associatedMethods) ||
              !listEquals(p.relatedAttributes, c.relatedAttributes);
          out.add(
            ArtifactChangeEntry(
              category: 'Couche Domain',
              summary: contractChanged
                  ? "~ Méthode Repository '${c.effectiveTitle}' modifiée"
                  : "~ Méthode Repository '${c.effectiveTitle}' : documentation mise à jour",
              impact: contractChanged ? SemVerBump.major : SemVerBump.patch,
            ),
          );
        }
      }
      for (final p in prevPol.portMethods) {
        if (!matchedRepoMethods.contains(p.id)) {
          out.add(
            ArtifactChangeEntry(
              category: 'Couche Domain',
              summary: "- Méthode Repository '${p.effectiveTitle}' supprimée",
              impact: SemVerBump.major,
            ),
          );
        }
      }
    }
  }

  static void _diffUseCaseFields(
    List<ArtifactChangeEntry> out,
    List<UseCaseFieldSpec> prevFields,
    List<UseCaseFieldSpec> currFields, {
    required bool isInput,
    required String pathPrefix,
  }) {
    final labelKind = isInput ? 'Entrée' : 'Sortie';
    final prevByName = <String, UseCaseFieldSpec>{
      for (final f in prevFields) f.name.toLowerCase(): f,
    };
    final currByName = <String, UseCaseFieldSpec>{
      for (final f in currFields) f.name.toLowerCase(): f,
    };

    for (final entry in prevByName.entries) {
      if (!currByName.containsKey(entry.key)) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrat Input/Output',
            summary: "- $labelKind '$pathPrefix${entry.value.name}' supprimée",
            impact: SemVerBump.major,
          ),
        );
      }
    }

    for (final curr in currFields) {
      final prev = prevByName[curr.name.toLowerCase()];
      final fullName = '$pathPrefix${curr.name}';
      if (prev == null) {
        if (isInput) {
          final req = curr.effectiveRequired;
          out.add(
            ArtifactChangeEntry(
              category: 'Contrat Input/Output',
              summary:
                  "+ Entrée ${req ? 'obligatoire' : 'optionnelle'} '$fullName' (${curr.type})",
              impact: req ? SemVerBump.major : SemVerBump.minor,
            ),
          );
        } else {
          out.add(
            ArtifactChangeEntry(
              category: 'Contrat Input/Output',
              summary: "+ Sortie '$fullName' (${curr.type})",
              impact: SemVerBump.minor,
            ),
          );
        }
        continue;
      }

      if (prev.type.trim() != curr.type.trim() ||
          prev.effectiveIsArray != curr.effectiveIsArray) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrat Input/Output',
            summary:
                "~ $labelKind '$fullName' : type '${prev.type}' → '${curr.type}'",
            impact: SemVerBump.major,
          ),
        );
      }
      if (prev.effectiveRequired != curr.effectiveRequired) {
        if (isInput) {
          out.add(
            ArtifactChangeEntry(
              category: 'Contrat Input/Output',
              summary: curr.effectiveRequired
                  ? "~ Entrée '$fullName' devenue obligatoire"
                  : "~ Entrée '$fullName' devenue optionnelle",
              impact: curr.effectiveRequired
                  ? SemVerBump.major
                  : SemVerBump.minor,
            ),
          );
        } else {
          out.add(
            ArtifactChangeEntry(
              category: 'Contrat Input/Output',
              summary: curr.effectiveRequired
                  ? "~ Sortie '$fullName' garantie non-optionnelle"
                  : "~ Sortie '$fullName' devenue optionnelle",
              impact: curr.effectiveRequired
                  ? SemVerBump.minor
                  : SemVerBump.major,
            ),
          );
        }
      }
      if (prev.nullable != curr.nullable) {
        final breaking = isInput ? !curr.nullable : curr.nullable;
        out.add(
          ArtifactChangeEntry(
            category: 'Contrat Input/Output',
            summary:
                "~ $labelKind '$fullName' : nullabilité ${prev.nullable} → ${curr.nullable}",
            impact: breaking ? SemVerBump.major : SemVerBump.minor,
          ),
        );
      }
      _diffEnumValues(
        out,
        prev.enumValues,
        curr.enumValues,
        targetLabel: "$labelKind '$fullName'",
      );
      if (prev.constraints.trim() != curr.constraints.trim()) {
        out.add(
          ArtifactChangeEntry(
            category: 'Contrat Input/Output',
            summary:
                "~ $labelKind '$fullName' : contraintes '${prev.constraints}' → '${curr.constraints}'",
            impact: curr.constraints.trim().isEmpty
                ? SemVerBump.minor
                : SemVerBump.major,
          ),
        );
      }
      if (prev.children.isNotEmpty || curr.children.isNotEmpty) {
        _diffUseCaseFields(
          out,
          prev.children,
          curr.children,
          isInput: isInput,
          pathPrefix: '$fullName.',
        );
      }
      if (prev.description.trim() != curr.description.trim()) {
        out.add(
          ArtifactChangeEntry(
            category: 'Métadonnée',
            summary: "~ $labelKind '$fullName' : description mise à jour",
            impact: SemVerBump.patch,
          ),
        );
      }
    }
  }

  static void _diffSagaCompensationMatrix(
    List<ArtifactChangeEntry> out,
    List<SagaCompensationRow> prevRows,
    List<SagaCompensationRow> currRows,
  ) {
    final matchedPrevIds = <String>{};
    for (final curr in currRows) {
      SagaCompensationRow? prev;
      for (final candidate in prevRows) {
        if (!matchedPrevIds.contains(candidate.id) &&
            (candidate.id == curr.id ||
                candidate.step.trim().toLowerCase() ==
                    curr.step.trim().toLowerCase())) {
          prev = candidate;
          matchedPrevIds.add(candidate.id);
          break;
        }
      }
      if (prev == null) {
        out.add(
          ArtifactChangeEntry(
            category: 'Compensation Saga',
            summary: "+ Étape de Saga '${curr.step}' ajoutée",
            impact: SemVerBump.minor,
          ),
        );
        continue;
      }
      if (prev.nominalAction != curr.nominalAction ||
          prev.compensationAction != curr.compensationAction ||
          prev.rollbackTrigger != curr.rollbackTrigger) {
        out.add(
          ArtifactChangeEntry(
            category: 'Compensation Saga',
            summary:
                "~ Étape '${curr.step}' : action nominale ou compensation modifiée",
            impact: SemVerBump.major,
          ),
        );
      } else if (prev.criticality != curr.criticality ||
          prev.idempotent != curr.idempotent ||
          prev.retryable != curr.retryable) {
        out.add(
          ArtifactChangeEntry(
            category: 'Compensation Saga',
            summary:
                "~ Étape '${curr.step}' : criticité ou paramètres de retry modifiés",
            impact: SemVerBump.minor,
          ),
        );
      } else if (prev.step != curr.step || prev.timeout != curr.timeout) {
        out.add(
          ArtifactChangeEntry(
            category: 'Compensation Saga',
            summary: "~ Étape '${curr.step}' : libellé ou timeout mis à jour",
            impact: SemVerBump.patch,
          ),
        );
      }
    }

    for (final prev in prevRows) {
      if (matchedPrevIds.contains(prev.id)) continue;
      out.add(
        ArtifactChangeEntry(
          category: 'Compensation Saga',
          summary: "- Étape de Saga '${prev.step}' supprimée",
          impact: SemVerBump.major,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers d'extraction et de résolution du graphe de dépendances
  // ---------------------------------------------------------------------------

  static List<ResolvedValueObject> _resolveVisibleValueObjects(
    FunctionalDomain domain,
    DomainCatalog? catalog,
  ) {
    if (catalog == null) {
      return <ResolvedValueObject>[
        for (final vo in domain.valueObjects)
          ResolvedValueObject(
            spec: vo,
            scope: ValueObjectScope.domain,
            domainId: domain.id,
          ),
      ];
    }
    if (catalog.domains.any((d) => d.id == domain.id && identical(d, domain))) {
      return catalog.resolvedValueObjectsForDomain(domain.id);
    }
    return catalog
        .copyWith(
          domains: <FunctionalDomain>[
            for (final d in catalog.domains)
              if (d.id != domain.id) d,
            domain,
          ],
        )
        .resolvedValueObjectsForDomain(domain.id);
  }

  static List<SnapshotModelArtifact> _extractCurrentModels(
    FunctionalDomain domain,
  ) {
    final contracts = domain.contracts;
    if (contracts == null) return const <SnapshotModelArtifact>[];
    final out = <SnapshotModelArtifact>[];
    for (final group in contracts.groups) {
      for (final node in group.children) {
        final detail = contracts.details[node.id] ?? ContractDetails.defaults;
        out.add(
          SnapshotModelArtifact(
            entryId: node.id,
            name: node.name,
            dslType: node.type,
            groupName: group.name,
            title: detail.title,
            version: detail.version,
            objectSpec: contracts.objectFor(node),
            domainLayerSpec: contracts.domainLayerFor(node),
          ),
        );
      }
    }
    return out;
  }

  static String _effectiveUseCaseName(ApplicationUseCaseSpec uc) =>
      uc.name.trim().isNotEmpty ? uc.name.trim() : uc.title.trim();

  static String _effectiveUseCaseSubtitle(ApplicationUseCaseSpec uc) {
    final t = uc.title.trim();
    final n = uc.name.trim();
    if (t.isNotEmpty && t != n) return t;
    return uc.code.trim();
  }

  static String _effectiveSagaName(OrchestrationSagaSpec saga) =>
      saga.name.trim().isNotEmpty ? saga.name.trim() : saga.title.trim();

  static String _effectiveSagaSubtitle(OrchestrationSagaSpec saga) {
    final t = saga.title.trim();
    final n = saga.name.trim();
    if (t.isNotEmpty && t != n) return t;
    return saga.code.trim();
  }

  static String _nodeKey(DesignArtifactKind kind, String id) =>
      '${kind.name}:$id';

  static Set<String> _collectVoRefsFromAttributes(
    List<BusinessAttribute> attributes,
  ) {
    final refs = <String>{};
    void walk(List<BusinessAttribute> attrs) {
      for (final attr in attrs) {
        if ((attr.type == BusinessAttributeType.valueObject ||
                attr.valueObjectId.trim().isNotEmpty) &&
            attr.valueObjectId.trim().isNotEmpty) {
          refs.add(attr.valueObjectId.trim());
        }
        if (attr.children.isNotEmpty) walk(attr.children);
      }
    }

    walk(attributes);
    return refs;
  }

  static Set<String> _collectModelRefs(SnapshotModelArtifact model) {
    final refs = <String>{};
    void walk(List<BusinessAttribute> attrs) {
      for (final attr in attrs) {
        if ((attr.type == BusinessAttributeType.reference ||
                attr.referenceObjectId.trim().isNotEmpty) &&
            attr.referenceObjectId.trim().isNotEmpty) {
          refs.add(attr.referenceObjectId.trim());
        }
        if (attr.children.isNotEmpty) walk(attr.children);
      }
    }

    walk(model.objectSpec.attributes);
    for (final rel in model.objectSpec.relations) {
      if (rel.targetObjectId.trim().isNotEmpty) {
        refs.add(rel.targetObjectId.trim());
      }
    }
    for (final evt in model.domainLayerSpec.domainEvents) {
      if (evt.contractEntryRef.trim().isNotEmpty) {
        refs.add(evt.contractEntryRef.trim());
      }
    }
    return refs;
  }

  static Set<String> _collectUseCaseFieldTypeTokens(
    List<UseCaseFieldSpec> fields,
  ) {
    final tokens = <String>{};
    final identPattern = RegExp(r'[A-Za-z_][A-Za-z0-9_-]*');
    void walk(List<UseCaseFieldSpec> list) {
      for (final f in list) {
        for (final match in identPattern.allMatches(f.type)) {
          final word = match.group(0)!;
          if (!_primitiveFieldTypeTokens.contains(word.toLowerCase())) {
            tokens.add(word);
          }
        }
        if (f.children.isNotEmpty) walk(f.children);
      }
    }

    walk(fields);
    return tokens;
  }

  static bool _sagaReferencesUseCase(
    OrchestrationSagaSpec saga,
    _MutableArtifactNode ucNode,
  ) {
    final haystacks = <String>[
      if (saga.triggerEventOrCommand.trim().isNotEmpty)
        saga.triggerEventOrCommand,
      for (final row in saga.compensationMatrix) ...<String>[
        row.step,
        row.nominalAction,
        row.compensationAction,
        row.rollbackTrigger,
      ],
      if (saga.mermaidDiagram.trim().isNotEmpty) saga.mermaidDiagram,
    ];
    if (haystacks.isEmpty) return false;

    final ucSpecs = <ApplicationUseCaseSpec>[
      if (ucNode.currentUseCase != null) ucNode.currentUseCase!,
      if (ucNode.baselineUseCase != null) ucNode.baselineUseCase!,
    ];

    for (final uc in ucSpecs) {
      final code = uc.code.trim();
      if (code.length >= 2) {
        final codePattern = RegExp(
          '(?<![A-Za-z0-9_-])${RegExp.escape(code)}(?![A-Za-z0-9_-])',
          caseSensitive: false,
        );
        if (haystacks.any(codePattern.hasMatch)) return true;
      }

      final name = uc.name.trim();
      if (name.length >= 3) {
        final namePattern = RegExp(
          '(?<![A-Za-z0-9_])${RegExp.escape(name)}(?:Command|Query|UseCase|Handler)?(?![A-Za-z0-9_])',
          caseSensitive: false,
        );
        if (haystacks.any(namePattern.hasMatch)) return true;
      }

      final inbound = uc.inboundPort.trim();
      if (inbound.length >= 3) {
        final inboundPattern = RegExp(
          '(?<![A-Za-z0-9_])${RegExp.escape(inbound)}(?![A-Za-z0-9_])',
          caseSensitive: false,
        );
        if (haystacks.any(inboundPattern.hasMatch)) return true;
      }

      for (final event in uc.emittedEvents) {
        final cleanEvt = event.trim();
        if (cleanEvt.length >= 3) {
          final evtPattern = RegExp(
            '(?<![A-Za-z0-9_])${RegExp.escape(cleanEvt)}(?![A-Za-z0-9_])',
            caseSensitive: false,
          );
          if (haystacks.any(evtPattern.hasMatch)) return true;
        }
      }
    }
    return false;
  }
}

class _MutableArtifactNode {
  _MutableArtifactNode({
    required this.key,
    required this.kind,
    required this.id,
    required this.name,
    required this.subtitle,
    this.valueObjectScope,
    required this.state,
    this.baselineVersion,
    required this.currentVersion,
    required this.directBump,
    required this.directChanges,
    this.currentVo,
    this.baselineVo,
    this.currentModel,
    this.baselineModel,
    this.currentUseCase,
    this.baselineUseCase,
    this.currentSaga,
    this.baselineSaga,
  }) : effectiveBump = directBump {
    if (state == ArtifactEvolutionState.modified ||
        state == ArtifactEvolutionState.removed) {
      reachedFromRoots[key] = <String>{key};
    }
  }

  final String key;
  final DesignArtifactKind kind;
  final String id;
  final String name;
  final String subtitle;
  final ValueObjectScope? valueObjectScope;
  ArtifactEvolutionState state;
  final String? baselineVersion;
  final String currentVersion;
  final SemVerBump directBump;
  SemVerBump effectiveBump;
  final List<ArtifactChangeEntry> directChanges;
  final Set<String> upstreamKeys = <String>{};
  final Map<String, Set<String>> reachedFromRoots = <String, Set<String>>{};

  final ValueObjectSpec? currentVo;
  final ValueObjectSpec? baselineVo;
  final SnapshotModelArtifact? currentModel;
  final SnapshotModelArtifact? baselineModel;
  final ApplicationUseCaseSpec? currentUseCase;
  final ApplicationUseCaseSpec? baselineUseCase;
  final OrchestrationSagaSpec? currentSaga;
  final OrchestrationSagaSpec? baselineSaga;

  bool get isPropagatingSource =>
      state == ArtifactEvolutionState.modified ||
      state == ArtifactEvolutionState.impacted ||
      state == ArtifactEvolutionState.removed;

  bool tryPropagateFrom(_MutableArtifactNode upstream) {
    if (upstream.key == key || !upstream.isPropagatingSource) return false;
    // Un artefact nouvellement créé dans l'itération reste `added`.
    if (state == ArtifactEvolutionState.added) return false;

    // Sélectionne uniquement les causes racines atteignant `upstream` par un
    // chemin simple ne passant pas déjà par `key` (évite tout écho circulaire).
    final validRootPaths = <String, Set<String>>{};
    for (final entry in upstream.reachedFromRoots.entries) {
      if (!entry.value.contains(key)) {
        validRootPaths[entry.key] = <String>{...entry.value, key};
      }
    }
    if (validRootPaths.isEmpty) return false;

    var changed = false;
    if (upstreamKeys.add(upstream.key)) {
      changed = true;
    }
    for (final entry in validRootPaths.entries) {
      if (!reachedFromRoots.containsKey(entry.key)) {
        reachedFromRoots[entry.key] = entry.value;
        changed = true;
      }
    }
    if (state == ArtifactEvolutionState.unchanged) {
      state = ArtifactEvolutionState.impacted;
      changed = true;
    }
    final nextBump = effectiveBump.max(upstream.effectiveBump);
    if (nextBump != effectiveBump) {
      effectiveBump = nextBump;
      changed = true;
    }
    return changed;
  }

  String formatAsUpstreamCause() {
    final prefix = kind.shortLabel;
    if (state == ArtifactEvolutionState.removed) {
      return '$prefix $name (Supprimé · ${SemVerBump.major.shortLabel})';
    }
    final bumpText = effectiveBump.shortLabel;
    if (baselineVersion != null && effectiveBump.hasChange) {
      final targetVer = _compareSemVer(currentVersion, baselineVersion!) <= 0
          ? effectiveBump.applyTo(baselineVersion!)
          : currentVersion;
      if (targetVer != baselineVersion) {
        return '$prefix $name (v$baselineVersion → v$targetVer · $bumpText)';
      }
    }
    return '$prefix $name (Δ $bumpText)';
  }

  ArtifactEvolutionReport toReport(Map<String, _MutableArtifactNode> allNodes) {
    final formattedCauses = <String>[
      for (final upKey in upstreamKeys)
        if (allNodes[upKey] != null) allNodes[upKey]!.formatAsUpstreamCause(),
    ];
    return ArtifactEvolutionReport(
      kind: kind,
      id: id,
      name: name,
      subtitle: subtitle,
      valueObjectScope: valueObjectScope,
      state: state,
      baselineVersion: baselineVersion,
      currentVersion: currentVersion,
      directBump: directBump,
      effectiveBump: effectiveBump,
      directChanges: directChanges,
      impactedBy: formattedCauses,
    );
  }
}
