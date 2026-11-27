/// Moteur pur et déterministe de fusion 3-voies (`baseSpec` / `nextSpec` /
/// `currentDesign`) pour les objets métiers promus de la Spec vers l'espace
/// Design ([SpecDesignMergeEngine]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/business_object_spec.dart';
import '../models/json_schema_constraints.dart';
import '../models/value_object_spec.dart';

/// Nature de la décision appliquée à un attribut lors d'une fusion Spec → Design.
enum AttributeMergeKind {
  /// Nouvel attribut introduit par la spécification.
  addedFromSpec('Ajouté depuis la Spec'),

  /// Attribut existant mis à jour à partir des évolutions de la spécification.
  updatedFromSpec('Mis à jour depuis la Spec'),

  /// Attribut technique ou métier propre au Design conservé intact.
  preservedDesignOnly('Attribut Design conservé'),

  /// Typage Value Object choisi en Design préservé tout en fusionnant les métadonnées Spec.
  preservedDesignValueObject('Value Object Design conservé'),

  /// Attribut supprimé côté Spec et retiré car non spécialisé côté Design.
  removedFromSpec('Retiré (supprimé dans la Spec)'),

  /// Conflit entre une suppression/mutation incompatible Spec et une spécialisation Design, résolu en conservant le Design.
  conflictKeptDesign('Conflit — Design conservé');

  /// Construit un type de décision de fusion d'attribut.
  const AttributeMergeKind(this.label);

  /// Libellé court en français affiché dans les aperçus de fusion.
  final String label;
}

/// Trace structurée et immuable de la décision prise sur un attribut (direct ou imbriqué).
@immutable
class AttributeMergeDecision {
  /// Crée une trace immuable de décision de fusion d'attribut.
  const AttributeMergeDecision({
    required this.attributeId,
    required this.attributePath,
    required this.kind,
    required this.summary,
    this.beforeAttribute,
    this.afterAttribute,
    this.preservedValueObjectId,
  });

  /// Identifiant technique de l'attribut concerné.
  final String attributeId;

  /// Chemin pointé lisible de l'attribut (ex. `email` ou `entete.adresseLivraison`).
  final String attributePath;

  /// Catégorie de décision retenue par le moteur 3-voies.
  final AttributeMergeKind kind;

  /// Explication synthétique en français de la décision prise.
  final String summary;

  /// État de l'attribut dans `currentDesign` avant fusion (`null` si ajouté).
  final BusinessAttribute? beforeAttribute;

  /// État de l'attribut dans `mergedObject` après fusion (`null` si retiré).
  final BusinessAttribute? afterAttribute;

  /// Identifiant ou nom technique du Value Object conservé, le cas échéant.
  final String? preservedValueObjectId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttributeMergeDecision &&
          other.attributeId == attributeId &&
          other.attributePath == attributePath &&
          other.kind == kind &&
          other.summary == summary &&
          other.beforeAttribute == beforeAttribute &&
          other.afterAttribute == afterAttribute &&
          other.preservedValueObjectId == preservedValueObjectId;

  @override
  int get hashCode => Object.hash(
    attributeId,
    attributePath,
    kind,
    summary,
    beforeAttribute,
    afterAttribute,
    preservedValueObjectId,
  );
}

/// Résultat complet et immuable de la fusion 3-voies d'un [BusinessObjectSpec].
@immutable
class ObjectMergeResult {
  /// Crée un résultat immuable de fusion d'objet métier.
  ObjectMergeResult({
    required this.mergedObject,
    BusinessObjectSpec? currentDesign,
    List<AttributeMergeDecision> decisions = const <AttributeMergeDecision>[],
    List<String> preservedValueObjectIds = const <String>[],
    List<String> warnings = const <String>[],
  }) : currentDesign = currentDesign ?? mergedObject,
       decisions = List<AttributeMergeDecision>.unmodifiable(decisions),
       preservedValueObjectIds = List<String>.unmodifiable(
         preservedValueObjectIds,
       ),
       warnings = List<String>.unmodifiable(warnings);

  /// Objet métier fusionné prêt à être enregistré dans `DomainContracts`.
  final BusinessObjectSpec mergedObject;

  /// Photographie du modèle Design avant application de la fusion.
  final BusinessObjectSpec currentDesign;

  /// Décisions détaillées prises par attribut au cours de la fusion.
  final List<AttributeMergeDecision> decisions;

  /// Identifiants ou noms techniques uniques des Value Objects conservés depuis le Design.
  final List<String> preservedValueObjectIds;

  /// Avertissements lisibles en français signalant les conflits ou cas d'attention.
  final List<String> warnings;

  /// Nombre d'attributs ajoutés depuis la Spec.
  int get addedCount => decisions
      .where((d) => d.kind == AttributeMergeKind.addedFromSpec)
      .length;

  /// Nombre d'attributs mis à jour depuis la Spec.
  int get updatedCount => decisions
      .where((d) => d.kind == AttributeMergeKind.updatedFromSpec)
      .length;

  /// Nombre d'attributs supprimés suite à leur retrait dans la Spec.
  int get removedCount => decisions
      .where((d) => d.kind == AttributeMergeKind.removedFromSpec)
      .length;

  /// Nombre d'attributs Design préservés (attributs propres au Design + Value Objects préservés).
  int get preservedDesignCount => decisions
      .where(
        (d) =>
            d.kind == AttributeMergeKind.preservedDesignOnly ||
            d.kind == AttributeMergeKind.preservedDesignValueObject,
      )
      .length;

  /// Nombre d'attributs exclusivement propres au Design conservés.
  int get preservedDesignOnlyCount => decisions
      .where((d) => d.kind == AttributeMergeKind.preservedDesignOnly)
      .length;

  /// Nombre d'attributs dont le typage Value Object Design a été préservé sans conflit.
  int get preservedValueObjectCount => decisions
      .where((d) => d.kind == AttributeMergeKind.preservedDesignValueObject)
      .length;

  /// Nombre de conflits résolus en conservant la spécialisation Design.
  int get conflictCount => decisions
      .where((d) => d.kind == AttributeMergeKind.conflictKeptDesign)
      .length;

  /// Vrai si le modèle fusionné diffère effectivement de [currentDesign].
  bool get hasChanges => mergedObject != currentDesign;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectMergeResult &&
          other.mergedObject == mergedObject &&
          other.currentDesign == currentDesign &&
          listEquals(other.decisions, decisions) &&
          listEquals(other.preservedValueObjectIds, preservedValueObjectIds) &&
          listEquals(other.warnings, warnings);

  @override
  int get hashCode => Object.hash(
    mergedObject,
    currentDesign,
    Object.hashAll(decisions),
    Object.hashAll(preservedValueObjectIds),
    Object.hashAll(warnings),
  );
}

/// Moteur statique de fusion intelligente 3-voies entre Spec et Design.
abstract final class SpecDesignMergeEngine {
  static const Set<BusinessAttributeType> _textualTypes =
      <BusinessAttributeType>{
        BusinessAttributeType.string,
        BusinessAttributeType.email,
        BusinessAttributeType.url,
        BusinessAttributeType.uuid,
        BusinessAttributeType.enumeration,
      };

  static const Set<BusinessAttributeType> _numericTypes =
      <BusinessAttributeType>{
        BusinessAttributeType.integer,
        BusinessAttributeType.number,
      };

  static const Set<BusinessAttributeType> _temporalTypes =
      <BusinessAttributeType>{
        BusinessAttributeType.date,
        BusinessAttributeType.datetime,
      };

  /// Fusionne de manière déterministe [nextSpecResolved] avec [currentDesign]
  /// en s'appuyant sur la baseline optionnelle [baseSpec] (et l'objet Spec brut
  /// optionnel [nextSpec]).
  ///
  /// Garanties principales :
  /// - Conservation des attributs techniques/métier ajoutés uniquement côté Design.
  /// - Conservation des affectations `ValueObject` compatibles côté Design tout en
  ///   appliquant les mises à jour Spec (`required`, `isArray`, `description`, etc.).
  /// - Conservation des enrichissements techniques (`x-database-index`,
  ///   `x-searchable`, `x-mask`, contraintes JSON Schema) non modifiés par la Spec.
  /// - Protection contre la perte silencieuse lorsqu'un attribut supprimé dans la
  ///   Spec avait été spécialisé côté Design (`conflictKeptDesign` + avertissement).
  static ObjectMergeResult merge({
    BusinessObjectSpec? baseSpec,
    required BusinessObjectSpec nextSpecResolved,
    BusinessObjectSpec? nextSpec,
    required BusinessObjectSpec currentDesign,
    List<ResolvedValueObject> availableValueObjects =
        const <ResolvedValueObject>[],
  }) {
    final decisions = <AttributeMergeDecision>[];
    final warnings = <String>[];
    final preservedVoIdsOrdered = <String>[];
    final preservedVoIdsSeen = <String>{};

    void recordPreservedVo(String rawVoId) {
      final clean = rawVoId.trim();
      if (clean.isEmpty) return;
      if (preservedVoIdsSeen.add(clean)) {
        preservedVoIdsOrdered.add(clean);
      }
    }

    final effectiveBaseAttrs = baseSpec == null
        ? null
        : _effectiveSpecAttributes(baseSpec);
    final effectiveRawNextAttrs = nextSpec == null
        ? null
        : _effectiveSpecAttributes(nextSpec);

    final mergedAttributes = _mergeAttributeLists(
      baseAttrs: effectiveBaseAttrs,
      rawNextAttrs: effectiveRawNextAttrs,
      nextAttrs: nextSpecResolved.attributes,
      designAttrs: currentDesign.attributes,
      availableValueObjects: availableValueObjects,
      parentPath: '',
      decisions: decisions,
      warnings: warnings,
      onPreservedVo: recordPreservedVo,
      maxTotalAttributes: BusinessObjectSpec.maxAttributesPerObject,
    );

    final effectiveSpecBaseDesc = baseSpec?.description.trim() ?? '';
    final effectiveSpecNextDesc =
        (nextSpec ?? nextSpecResolved).description.trim();
    final String mergedDescription;
    if (baseSpec != null) {
      mergedDescription = effectiveSpecNextDesc != effectiveSpecBaseDesc
          ? nextSpecResolved.description
          : currentDesign.description;
    } else {
      mergedDescription = nextSpecResolved.description.trim().isNotEmpty
          ? nextSpecResolved.description
          : currentDesign.description;
    }

    final mergedAggregateRoot =
        (baseSpec != null &&
            (nextSpec ?? nextSpecResolved).aggregateRoot ==
                baseSpec.aggregateRoot)
        ? currentDesign.aggregateRoot
        : nextSpecResolved.aggregateRoot;

    final mergedStates = _mergeLifecycleStates(
      baseStates: baseSpec?.lifecycleStates,
      nextStates: nextSpecResolved.lifecycleStates,
      designStates: currentDesign.lifecycleStates,
    );

    final mergedTransitions = _mergeLifecycleTransitions(
      baseTransitions: baseSpec?.lifecycleTransitions,
      nextTransitions: nextSpecResolved.lifecycleTransitions,
      designTransitions: currentDesign.lifecycleTransitions,
      validStates: mergedStates,
    );

    final mergedRelations = _mergeRelations(
      baseRelations: baseSpec?.relations,
      nextRelations: nextSpecResolved.relations,
      designRelations: currentDesign.relations,
    );

    final mergedObject = BusinessObjectSpec(
      id: currentDesign.id,
      name: nextSpecResolved.name,
      technicalName: currentDesign.technicalName,
      description: mergedDescription,
      aggregateRoot: mergedAggregateRoot,
      attributes: mergedAttributes,
      relations: mergedRelations,
      lifecycleStates: mergedStates,
      lifecycleTransitions: mergedTransitions,
    );
    mergedObject.validate();

    return ObjectMergeResult(
      mergedObject: mergedObject,
      currentDesign: currentDesign,
      decisions: decisions,
      preservedValueObjectIds: preservedVoIdsOrdered,
      warnings: warnings,
    );
  }

  /// Indique si le Value Object [valueObjectId] porté par un attribut Design est
  /// compatible avec le nouveau type [nextSpecType] issu de la Spec.
  static bool isValueObjectCompatibleWithSpecType({
    required String valueObjectId,
    required BusinessAttributeType nextSpecType,
    BusinessAttributeType? baseSpecType,
    List<ResolvedValueObject> availableValueObjects =
        const <ResolvedValueObject>[],
  }) {
    final cleanVoId = valueObjectId.trim();
    if (cleanVoId.isEmpty) return false;

    final resolvedVo = _findValueObject(cleanVoId, availableValueObjects);

    // Si la Spec n'a pas changé de type depuis la baseline et ne pointe pas vers
    // une référence d'entité incompatible, le choix explicite du Design reste valide.
    final specTypeUnchanged =
        baseSpecType != null && baseSpecType == nextSpecType;

    if (resolvedVo != null) {
      final vo = resolvedVo.spec;
      if (vo.isScalar) {
        if (_areSamePrimitiveFamily(vo.primitiveType, nextSpecType)) {
          return true;
        }
        // Tolère un scalaire texte/temporel lorsque la Spec n'a pas changé de type.
        if (specTypeUnchanged &&
            nextSpecType != BusinessAttributeType.reference &&
            nextSpecType != BusinessAttributeType.object) {
          return true;
        }
        return false;
      }

      // Value Object composite (ex. Money, PostalAddress, DateRange).
      if (specTypeUnchanged &&
          nextSpecType != BusinessAttributeType.reference &&
          nextSpecType != BusinessAttributeType.boolean) {
        return true;
      }
      if (baseSpecType != null && baseSpecType != nextSpecType) {
        if (nextSpecType == BusinessAttributeType.object) return true;
        if (_numericTypes.contains(baseSpecType) &&
            _numericTypes.contains(nextSpecType)) {
          return true;
        }
        if (_temporalTypes.contains(baseSpecType) &&
            _temporalTypes.contains(nextSpecType)) {
          return true;
        }
        return false;
      }
      return const <BusinessAttributeType>{
        BusinessAttributeType.object,
        BusinessAttributeType.string,
        BusinessAttributeType.number,
        BusinessAttributeType.integer,
        BusinessAttributeType.date,
        BusinessAttributeType.datetime,
      }.contains(nextSpecType);
    }

    // Value Object non résolu dans le catalogue fourni (ex. appel hors catalogue).
    if (nextSpecType == BusinessAttributeType.reference ||
        nextSpecType == BusinessAttributeType.boolean) {
      return specTypeUnchanged &&
          nextSpecType != BusinessAttributeType.reference;
    }
    if (baseSpecType == null || specTypeUnchanged) {
      return const <BusinessAttributeType>{
        BusinessAttributeType.object,
        BusinessAttributeType.string,
        BusinessAttributeType.number,
        BusinessAttributeType.integer,
        BusinessAttributeType.email,
        BusinessAttributeType.url,
        BusinessAttributeType.uuid,
        BusinessAttributeType.date,
        BusinessAttributeType.datetime,
        BusinessAttributeType.enumeration,
      }.contains(nextSpecType);
    }
    return _areSamePrimitiveFamily(baseSpecType, nextSpecType) ||
        nextSpecType == BusinessAttributeType.object;
  }

  static bool _areSamePrimitiveFamily(
    BusinessAttributeType a,
    BusinessAttributeType b,
  ) {
    if (a == b) return true;
    if (_textualTypes.contains(a) && _textualTypes.contains(b)) return true;
    if (_numericTypes.contains(a) && _numericTypes.contains(b)) return true;
    if (_temporalTypes.contains(a) && _temporalTypes.contains(b)) return true;
    return false;
  }

  static ResolvedValueObject? _findValueObject(
    String idOrTechName,
    List<ResolvedValueObject> available,
  ) {
    final needle = idOrTechName.trim();
    if (needle.isEmpty) return null;
    final lower = needle.toLowerCase();
    for (final item in available) {
      if (item.spec.id == needle) return item;
    }
    for (final item in available) {
      if (item.spec.technicalName.toLowerCase() == lower) return item;
    }
    return null;
  }

  /// Construit la liste effective des attributs d'un objet Spec brut en y
  /// intégrant les attributs synthétiques issus de `relations` (selon la même
  /// convention `attr_${rel.id}` que `SpecDesignPromoter`).
  static List<BusinessAttribute> _effectiveSpecAttributes(
    BusinessObjectSpec spec,
  ) {
    final out = <BusinessAttribute>[...spec.attributes];
    final usedNamesLower = <String>{
      for (final a in out) a.name.toLowerCase(),
    };
    for (final rel in spec.relations) {
      if (_hasEquivalentRefAttr(spec.attributes, rel)) continue;
      final name = _uniqueAttrName(rel.name, usedNamesLower);
      usedNamesLower.add(name.toLowerCase());
      final isArray =
          rel.cardinality == BusinessRelationCardinality.oneToMany ||
          rel.cardinality == BusinessRelationCardinality.manyToMany;
      out.add(
        BusinessAttribute(
          id: 'attr_${rel.id}',
          name: name,
          type: BusinessAttributeType.reference,
          referenceObjectId: rel.targetObjectId,
          isArray: isArray,
          required: rel.required,
          description: rel.description,
        ),
      );
    }
    return out;
  }

  static bool _hasEquivalentRefAttr(
    List<BusinessAttribute> attrs,
    BusinessRelation rel,
  ) {
    final relIsArray =
        rel.cardinality == BusinessRelationCardinality.oneToMany ||
        rel.cardinality == BusinessRelationCardinality.manyToMany;
    for (final attr in attrs) {
      if (attr.name.toLowerCase() == rel.name.toLowerCase()) return true;
      if (attr.type == BusinessAttributeType.reference &&
          attr.isArray == relIsArray &&
          attr.referenceObjectId.trim().toLowerCase() ==
              rel.targetObjectId.trim().toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  static String _uniqueAttrName(String rawBase, Set<String> usedLower) {
    final base = BusinessAttribute.isValidDslIdentifier(rawBase)
        ? rawBase
        : BusinessAttribute.normalizeDslIdentifier(rawBase, fallback: 'ref');
    if (!usedLower.contains(base.toLowerCase())) return base;
    for (var i = 2; ; i++) {
      final candidate = '${base}_$i';
      if (!usedLower.contains(candidate.toLowerCase())) return candidate;
    }
  }

  static List<BusinessAttribute> _mergeAttributeLists({
    required List<BusinessAttribute>? baseAttrs,
    required List<BusinessAttribute>? rawNextAttrs,
    required List<BusinessAttribute> nextAttrs,
    required List<BusinessAttribute> designAttrs,
    required List<ResolvedValueObject> availableValueObjects,
    required String parentPath,
    required List<AttributeMergeDecision> decisions,
    required List<String> warnings,
    required void Function(String voId) onPreservedVo,
    required int maxTotalAttributes,
  }) {
    // Appariement nextAttrs <-> designAttrs (1. par ID exact, 2. par nom insensible à la casse).
    final nextToDesignIndex = <int, int>{};
    final matchedDesignIndices = <int>{};

    for (var ni = 0; ni < nextAttrs.length; ni++) {
      final nextAttr = nextAttrs[ni];
      for (var di = 0; di < designAttrs.length; di++) {
        if (matchedDesignIndices.contains(di)) continue;
        if (designAttrs[di].id == nextAttr.id) {
          nextToDesignIndex[ni] = di;
          matchedDesignIndices.add(di);
          break;
        }
      }
    }
    for (var ni = 0; ni < nextAttrs.length; ni++) {
      if (nextToDesignIndex.containsKey(ni)) continue;
      final nextLower = nextAttrs[ni].name.toLowerCase();
      for (var di = 0; di < designAttrs.length; di++) {
        if (matchedDesignIndices.contains(di)) continue;
        if (designAttrs[di].name.toLowerCase() == nextLower) {
          nextToDesignIndex[ni] = di;
          matchedDesignIndices.add(di);
          break;
        }
      }
    }

    BusinessAttribute? findMatchIn(
      List<BusinessAttribute>? pool,
      BusinessAttribute primary, [
      BusinessAttribute? secondary,
    ]) {
      if (pool == null || pool.isEmpty) return null;
      for (final candidate in pool) {
        if (candidate.id == primary.id ||
            (secondary != null && candidate.id == secondary.id)) {
          return candidate;
        }
      }
      final pLower = primary.name.toLowerCase();
      final sLower = secondary?.name.toLowerCase();
      for (final candidate in pool) {
        final cLower = candidate.name.toLowerCase();
        if (cLower == pLower || (sLower != null && cLower == sLower)) {
          return candidate;
        }
      }
      return null;
    }

    final result = <BusinessAttribute>[];
    final usedNamesLower = <String>{};

    String ensureUniqueSiblingName(String desiredName) {
      if (usedNamesLower.add(desiredName.toLowerCase())) return desiredName;
      for (var i = 2; ; i++) {
        final candidate = '${desiredName}_$i';
        if (usedNamesLower.add(candidate.toLowerCase())) return candidate;
      }
    }

    int currentTotalAttrs() =>
        result.fold<int>(0, (sum, a) => sum + a.totalAttributeCount);

    // 1. Parcours dans l'ordre canonique de la Spec entrante (ajouts + fusions).
    for (var ni = 0; ni < nextAttrs.length; ni++) {
      final nextAttr = nextAttrs[ni];
      final rawNextAttr = findMatchIn(rawNextAttrs, nextAttr);
      final di = nextToDesignIndex[ni];

      if (di == null) {
        if (currentTotalAttrs() + nextAttr.totalAttributeCount >
            maxTotalAttributes) {
          break;
        }
        final uniqueName = ensureUniqueSiblingName(nextAttr.name);
        final added = uniqueName == nextAttr.name
            ? nextAttr
            : nextAttr.copyWith(name: uniqueName);
        final path = _joinPath(parentPath, added.name);
        result.add(added);
        decisions.add(
          AttributeMergeDecision(
            attributeId: added.id,
            attributePath: path,
            kind: AttributeMergeKind.addedFromSpec,
            summary:
                'Attribut « $path » (${added.type.dslKeyword}) ajouté depuis la Spec.',
            afterAttribute: added,
          ),
        );
        continue;
      }

      final designAttr = designAttrs[di];
      final baseAttr = findMatchIn(baseAttrs, designAttr, nextAttr);
      final mergedAttr = _mergeMatchedAttribute(
        baseAttr: baseAttr,
        rawNextAttr: rawNextAttr,
        nextAttr: nextAttr,
        designAttr: designAttr,
        availableValueObjects: availableValueObjects,
        parentPath: parentPath,
        decisions: decisions,
        warnings: warnings,
        onPreservedVo: onPreservedVo,
        ensureUniqueName: ensureUniqueSiblingName,
        maxRemainingAttributes: maxTotalAttributes - currentTotalAttrs(),
      );
      result.add(mergedAttr);
    }

    // 2. Parcours des attributs présents uniquement dans currentDesign (absents de nextSpec).
    for (var di = 0; di < designAttrs.length; di++) {
      if (matchedDesignIndices.contains(di)) continue;
      final designAttr = designAttrs[di];
      final baseAttr = findMatchIn(baseAttrs, designAttr);
      final path = _joinPath(parentPath, designAttr.name);

      if (baseAttr == null) {
        // Attribut absent de baseSpec et de nextSpec (ou re-promotion legacy sans baseline) :
        // il s'agit d'un enrichissement Design à préserver intégralement.
        if (currentTotalAttrs() + designAttr.totalAttributeCount >
            maxTotalAttributes) {
          continue;
        }
        final uniqueName = ensureUniqueSiblingName(designAttr.name);
        final kept = uniqueName == designAttr.name
            ? designAttr
            : designAttr.copyWith(name: uniqueName);
        _collectNestedValueObjectIds(kept, onPreservedVo);
        result.add(kept);
        decisions.add(
          AttributeMergeDecision(
            attributeId: kept.id,
            attributePath: path,
            kind: AttributeMergeKind.preservedDesignOnly,
            summary:
                'Attribut propre au Design « $path » (${kept.type.dslKeyword}) conservé.',
            beforeAttribute: designAttr,
            afterAttribute: kept,
            preservedValueObjectId:
                kept.type == BusinessAttributeType.valueObject &&
                    kept.valueObjectId.trim().isNotEmpty
                ? kept.valueObjectId.trim()
                : null,
          ),
        );
        continue;
      }

      // L'attribut était présent dans baseSpec et a été supprimé dans nextSpec.
      if (_isSpecializedInDesign(designAttr, baseAttr)) {
        if (currentTotalAttrs() + designAttr.totalAttributeCount >
            maxTotalAttributes) {
          continue;
        }
        final uniqueName = ensureUniqueSiblingName(designAttr.name);
        final kept = uniqueName == designAttr.name
            ? designAttr
            : designAttr.copyWith(name: uniqueName);
        _collectNestedValueObjectIds(kept, onPreservedVo);
        result.add(kept);
        final voId =
            kept.type == BusinessAttributeType.valueObject &&
                kept.valueObjectId.trim().isNotEmpty
            ? kept.valueObjectId.trim()
            : null;
        final warnMsg = voId != null
            ? 'L’attribut « $path » a été supprimé dans la Spec mais utilise le Value Object « $voId » côté Design : il a été conservé pour éviter toute perte.'
            : 'L’attribut « $path » a été supprimé dans la Spec mais possède des enrichissements côté Design : il a été conservé pour revue manuelle.';
        warnings.add(warnMsg);
        decisions.add(
          AttributeMergeDecision(
            attributeId: kept.id,
            attributePath: path,
            kind: AttributeMergeKind.conflictKeptDesign,
            summary: warnMsg,
            beforeAttribute: designAttr,
            afterAttribute: kept,
            preservedValueObjectId: voId,
          ),
        );
      } else {
        decisions.add(
          AttributeMergeDecision(
            attributeId: designAttr.id,
            attributePath: path,
            kind: AttributeMergeKind.removedFromSpec,
            summary:
                'Attribut « $path » retiré (supprimé dans la Spec et non spécialisé en Design).',
            beforeAttribute: designAttr,
          ),
        );
      }
    }

    return result;
  }

  static BusinessAttribute _mergeMatchedAttribute({
    required BusinessAttribute? baseAttr,
    required BusinessAttribute? rawNextAttr,
    required BusinessAttribute nextAttr,
    required BusinessAttribute designAttr,
    required List<ResolvedValueObject> availableValueObjects,
    required String parentPath,
    required List<AttributeMergeDecision> decisions,
    required List<String> warnings,
    required void Function(String voId) onPreservedVo,
    required String Function(String desired) ensureUniqueName,
    required int maxRemainingAttributes,
  }) {
    final specNext = rawNextAttr ?? nextAttr;
    final hasBase = baseAttr != null;

    // 1. Nom d'attribut (préserve un renommage Design si la Spec n'a pas renommé).
    final desiredName = hasBase
        ? (specNext.name != baseAttr.name ? nextAttr.name : designAttr.name)
        : nextAttr.name;
    final mergedName = ensureUniqueName(desiredName);
    final path = _joinPath(parentPath, mergedName);

    // 2. Propriétés scalaires 3-voies.
    final mergedRequired = hasBase
        ? (specNext.required != baseAttr.required
              ? nextAttr.required
              : designAttr.required)
        : nextAttr.required;
    final mergedNullable = hasBase
        ? (specNext.nullable != baseAttr.nullable
              ? nextAttr.nullable
              : designAttr.nullable)
        : nextAttr.nullable;
    final mergedUnique = hasBase
        ? (specNext.unique != baseAttr.unique
              ? nextAttr.unique
              : designAttr.unique)
        : (nextAttr.unique || designAttr.unique);
    final mergedIsArray = hasBase
        ? (specNext.isArray != baseAttr.isArray
              ? nextAttr.isArray
              : designAttr.isArray)
        : nextAttr.isArray;
    final mergedMaxRows = hasBase
        ? (specNext.estimatedMaxRows != baseAttr.estimatedMaxRows
              ? nextAttr.estimatedMaxRows
              : designAttr.estimatedMaxRows)
        : (nextAttr.estimatedMaxRows ?? designAttr.estimatedMaxRows);
    final mergedDefaultValue = hasBase
        ? (specNext.defaultValue != baseAttr.defaultValue
              ? nextAttr.defaultValue
              : designAttr.defaultValue)
        : (nextAttr.defaultValue ?? designAttr.defaultValue);

    // Pour une référence convertie en scalaire, nextAttr.description contient la note
    // de domaine externe ; on ne l'écrase pas si la Spec brute a changé ou si base est absent.
    final String mergedDescription;
    if (hasBase) {
      final specDescChanged =
          specNext.description.trim() != baseAttr.description.trim();
      if (specDescChanged ||
          (baseAttr.type == BusinessAttributeType.reference &&
              designAttr.description.trim().isEmpty)) {
        mergedDescription = nextAttr.description;
      } else {
        mergedDescription = designAttr.description;
      }
    } else {
      mergedDescription = nextAttr.description.trim().isNotEmpty
          ? nextAttr.description
          : designAttr.description;
    }

    final mergedConstraintsText = hasBase
        ? (specNext.constraints.trim() != baseAttr.constraints.trim()
              ? nextAttr.constraints
              : designAttr.constraints)
        : (nextAttr.constraints.trim().isNotEmpty
              ? nextAttr.constraints
              : designAttr.constraints);

    final mergedSchemaConstraints = _mergeSchemaConstraints(
      base: baseAttr?.schemaConstraints,
      next: nextAttr.schemaConstraints,
      design: designAttr.schemaConstraints,
    );

    // 3. Cas où l'attribut Design est typé avec un Value Object.
    final isDesignVo =
        designAttr.type == BusinessAttributeType.valueObject &&
        designAttr.valueObjectId.trim().isNotEmpty;
    if (isDesignVo) {
      final voId = designAttr.valueObjectId.trim();
      // Si la Spec brute n'a pas changé le type (ex. référence externe convertie en uuid),
      // on considère le type de référence effectif stable.
      final effectiveBaseType =
          hasBase &&
              baseAttr.type == BusinessAttributeType.reference &&
              specNext.type == BusinessAttributeType.reference &&
              nextAttr.type != BusinessAttributeType.reference
          ? nextAttr.type
          : baseAttr?.type;

      final compatible = isValueObjectCompatibleWithSpecType(
        valueObjectId: voId,
        nextSpecType: nextAttr.type,
        baseSpecType: effectiveBaseType,
        availableValueObjects: availableValueObjects,
      );

      final mergedVoAttr = BusinessAttribute(
        id: designAttr.id,
        name: mergedName,
        type: BusinessAttributeType.valueObject,
        valueObjectId: voId,
        referenceObjectId: '',
        enumValues: const <String>[],
        required: mergedRequired,
        nullable: mergedNullable,
        unique: mergedUnique,
        isArray: mergedIsArray,
        estimatedMaxRows: mergedMaxRows,
        defaultValue: mergedDefaultValue,
        description: mergedDescription,
        constraints: mergedConstraintsText,
        schemaConstraints: mergedSchemaConstraints,
        children: const <BusinessAttribute>[],
      );
      onPreservedVo(voId);

      if (compatible) {
        final specMetaUpdated = mergedVoAttr != designAttr;
        decisions.add(
          AttributeMergeDecision(
            attributeId: mergedVoAttr.id,
            attributePath: path,
            kind: AttributeMergeKind.preservedDesignValueObject,
            summary: specMetaUpdated
                ? 'Value Object « $voId » conservé sur « $path » avec mise à jour des métadonnées Spec.'
                : 'Value Object « $voId » conservé intact sur « $path ».',
            beforeAttribute: designAttr,
            afterAttribute: mergedVoAttr,
            preservedValueObjectId: voId,
          ),
        );
      } else {
        final warnMsg =
            'Conflit de type sur « $path » : la Spec définit le type « ${nextAttr.type.dslKeyword} » incompatible avec le Value Object « $voId » ; le Value Object Design est conservé.';
        warnings.add(warnMsg);
        decisions.add(
          AttributeMergeDecision(
            attributeId: mergedVoAttr.id,
            attributePath: path,
            kind: AttributeMergeKind.conflictKeptDesign,
            summary: warnMsg,
            beforeAttribute: designAttr,
            afterAttribute: mergedVoAttr,
            preservedValueObjectId: voId,
          ),
        );
      }
      return mergedVoAttr;
    }

    // 4. Cas d'un attribut standard ou sous-objet.
    final bool takeNextType;
    if (!hasBase) {
      takeNextType = true;
    } else if (nextAttr.type == BusinessAttributeType.reference ||
        baseAttr.type == BusinessAttributeType.reference) {
      takeNextType = true;
    } else if (specNext.type != baseAttr.type) {
      takeNextType = true;
    } else {
      takeNextType = false;
    }

    final mergedType = takeNextType ? nextAttr.type : designAttr.type;
    final mergedRefId = mergedType == BusinessAttributeType.reference
        ? (nextAttr.type == BusinessAttributeType.reference
              ? nextAttr.referenceObjectId
              : designAttr.referenceObjectId)
        : '';

    final List<String> mergedEnumValues;
    if (mergedType != BusinessAttributeType.enumeration) {
      mergedEnumValues = const <String>[];
    } else if (!hasBase) {
      mergedEnumValues = nextAttr.enumValues.isNotEmpty
          ? nextAttr.enumValues
          : designAttr.enumValues;
    } else if (!listEquals(specNext.enumValues, baseAttr.enumValues)) {
      mergedEnumValues = nextAttr.enumValues;
    } else {
      mergedEnumValues = designAttr.enumValues.isNotEmpty
          ? designAttr.enumValues
          : nextAttr.enumValues;
    }

    List<BusinessAttribute> mergedChildren = const <BusinessAttribute>[];
    if (mergedType == BusinessAttributeType.object) {
      mergedChildren = _mergeAttributeLists(
        baseAttrs: baseAttr?.children,
        rawNextAttrs: rawNextAttr?.children,
        nextAttrs: nextAttr.children,
        designAttrs: designAttr.children,
        availableValueObjects: availableValueObjects,
        parentPath: path,
        decisions: decisions,
        warnings: warnings,
        onPreservedVo: onPreservedVo,
        maxTotalAttributes: (maxRemainingAttributes - 1).clamp(
          0,
          BusinessObjectSpec.maxAttributesPerObject,
        ),
      );
    }

    final mergedStandardAttr = BusinessAttribute(
      id: designAttr.id,
      name: mergedName,
      type: mergedType,
      required: mergedRequired,
      nullable: mergedNullable,
      unique: mergedUnique,
      isArray: mergedIsArray,
      estimatedMaxRows: mergedMaxRows,
      defaultValue: mergedDefaultValue,
      enumValues: mergedEnumValues,
      referenceObjectId: mergedRefId,
      valueObjectId: '',
      description: mergedDescription,
      constraints: mergedConstraintsText,
      schemaConstraints: mergedSchemaConstraints,
      children: mergedChildren,
    );

    final ownPropertiesChanged =
        mergedStandardAttr.copyWith(children: const <BusinessAttribute>[]) !=
        designAttr.copyWith(children: const <BusinessAttribute>[]);
    if (ownPropertiesChanged) {
      decisions.add(
        AttributeMergeDecision(
          attributeId: mergedStandardAttr.id,
          attributePath: path,
          kind: AttributeMergeKind.updatedFromSpec,
          summary:
              'Attribut « $path » mis à jour depuis la Spec (${mergedStandardAttr.type.dslKeyword}).',
          beforeAttribute: designAttr,
          afterAttribute: mergedStandardAttr,
        ),
      );
    }

    return mergedStandardAttr;
  }

  /// Détermine si [designAttr] a reçu des spécialisations explicites côté Design
  /// par rapport à [baseAttr] (Value Object, contraintes JSON Schema, index/masque,
  /// sous-attributs ajoutés ou spécialisés).
  static bool _isSpecializedInDesign(
    BusinessAttribute designAttr,
    BusinessAttribute baseAttr,
  ) {
    if (designAttr.type == BusinessAttributeType.valueObject &&
        designAttr.valueObjectId.trim().isNotEmpty) {
      return !(baseAttr.type == BusinessAttributeType.valueObject &&
          baseAttr.valueObjectId.trim() == designAttr.valueObjectId.trim());
    }
    if (designAttr.schemaConstraints != baseAttr.schemaConstraints) {
      return true;
    }
    if (designAttr.constraints.trim().isNotEmpty &&
        designAttr.constraints.trim() != baseAttr.constraints.trim()) {
      return true;
    }
    // Pour une référence Spec, la conversion en scalaire (uuid/int/string) est
    // automatique lors de la promotion hors domaine et ne constitue pas une
    // spécialisation manuelle.
    if (baseAttr.type != BusinessAttributeType.reference &&
        designAttr.type != baseAttr.type) {
      return true;
    }
    if (designAttr.enumValues.isNotEmpty &&
        !listEquals(designAttr.enumValues, baseAttr.enumValues)) {
      return true;
    }
    if (designAttr.children.length != baseAttr.children.length) {
      return true;
    }
    for (final dChild in designAttr.children) {
      final bChild =
          baseAttr.children.where((c) => c.id == dChild.id).firstOrNull ??
          baseAttr.children
              .where((c) => c.name.toLowerCase() == dChild.name.toLowerCase())
              .firstOrNull;
      if (bChild == null || _isSpecializedInDesign(dChild, bChild)) {
        return true;
      }
    }
    return false;
  }

  static void _collectNestedValueObjectIds(
    BusinessAttribute attr,
    void Function(String voId) onPreservedVo,
  ) {
    if (attr.type == BusinessAttributeType.valueObject &&
        attr.valueObjectId.trim().isNotEmpty) {
      onPreservedVo(attr.valueObjectId.trim());
    }
    for (final child in attr.children) {
      _collectNestedValueObjectIds(child, onPreservedVo);
    }
  }

  /// Fusionne en 3-voies les contraintes JSON Schema, y compris `x-database-index`,
  /// `x-searchable`, `x-mask` et les autres `extraKeywords`.
  static JsonSchemaConstraints _mergeSchemaConstraints({
    required JsonSchemaConstraints? base,
    required JsonSchemaConstraints next,
    required JsonSchemaConstraints design,
  }) {
    if (next.isEmpty && design.isEmpty) return JsonSchemaConstraints.empty;
    if (base == null && next.isEmpty) return design;
    if (design.isEmpty && (base == null || base.isEmpty)) return next;

    final baseMap = base?.toSchemaMap() ?? const <String, Object?>{};
    final nextMap = next.toSchemaMap();
    final designMap = design.toSchemaMap();

    final allKeys = <String>{
      ...baseMap.keys,
      ...nextMap.keys,
      ...designMap.keys,
    };

    final mergedMap = <String, Object?>{};
    final specUpdatedKeys = <String>{};

    for (final key in allKeys) {
      final baseHas = baseMap.containsKey(key);
      final nextHas = nextMap.containsKey(key);
      final designHas = designMap.containsKey(key);

      if (base != null) {
        final specChangedKey =
            baseHas != nextHas ||
            (baseHas &&
                nextHas &&
                !_jsonValueEquals(baseMap[key], nextMap[key]));
        if (specChangedKey) {
          specUpdatedKeys.add(key);
          if (nextHas) {
            mergedMap[key] = nextMap[key];
          }
        } else if (designHas) {
          mergedMap[key] = designMap[key];
        }
      } else {
        // Fusion 2-voies sans baseline : la Spec prime sur les clés qu'elle renseigne,
        // tandis que tous les enrichissements Design absents de la Spec (x-database-index,
        // x-searchable, x-mask, bornes techniques, etc.) sont conservés.
        if (nextHas) {
          specUpdatedKeys.add(key);
          mergedMap[key] = nextMap[key];
        } else if (designHas) {
          mergedMap[key] = designMap[key];
        }
      }
    }

    _reconcileNumericPair(
      mergedMap,
      minKey: 'minimum',
      maxKey: 'maximum',
      strict: false,
      specUpdatedKeys: specUpdatedKeys,
    );
    _reconcileNumericPair(
      mergedMap,
      minKey: 'exclusiveMinimum',
      maxKey: 'exclusiveMaximum',
      strict: true,
      specUpdatedKeys: specUpdatedKeys,
    );
    _reconcileNumericPair(
      mergedMap,
      minKey: 'minLength',
      maxKey: 'maxLength',
      strict: false,
      specUpdatedKeys: specUpdatedKeys,
    );
    _reconcileNumericPair(
      mergedMap,
      minKey: 'minItems',
      maxKey: 'maxItems',
      strict: false,
      specUpdatedKeys: specUpdatedKeys,
    );
    _reconcileNumericPair(
      mergedMap,
      minKey: 'minContains',
      maxKey: 'maxContains',
      strict: false,
      specUpdatedKeys: specUpdatedKeys,
    );
    _reconcileNumericPair(
      mergedMap,
      minKey: 'minProperties',
      maxKey: 'maxProperties',
      strict: false,
      specUpdatedKeys: specUpdatedKeys,
    );

    if (mergedMap.isEmpty) return JsonSchemaConstraints.empty;
    return JsonSchemaConstraints.fromJson(mergedMap);
  }

  static void _reconcileNumericPair(
    Map<String, Object?> map, {
    required String minKey,
    required String maxKey,
    required bool strict,
    required Set<String> specUpdatedKeys,
  }) {
    final minVal = map[minKey];
    final maxVal = map[maxKey];
    if (minVal is! num || maxVal is! num) return;
    final invalid = strict ? minVal >= maxVal : minVal > maxVal;
    if (!invalid) return;
    if (specUpdatedKeys.contains(maxKey) && !specUpdatedKeys.contains(minKey)) {
      map.remove(minKey);
    } else {
      map.remove(maxKey);
    }
  }

  static bool _jsonValueEquals(Object? a, Object? b) =>
      jsonEncode(a) == jsonEncode(b);

  static List<LifecycleState> _mergeLifecycleStates({
    required List<LifecycleState>? baseStates,
    required List<LifecycleState> nextStates,
    required List<LifecycleState> designStates,
  }) {
    if (nextStates.isEmpty && designStates.isEmpty) {
      return const <LifecycleState>[];
    }
    final out = <LifecycleState>[];
    final seenNamesLower = <String>{};

    LifecycleState? findState(List<LifecycleState>? list, String name) {
      if (list == null) return null;
      final lower = name.trim().toLowerCase();
      for (final s in list) {
        if (s.name.trim().toLowerCase() == lower) return s;
      }
      return null;
    }

    for (final nextState in nextStates) {
      seenNamesLower.add(nextState.name.trim().toLowerCase());
      final baseState = findState(baseStates, nextState.name);
      final designState = findState(designStates, nextState.name);
      if (baseState != null && designState != null && nextState == baseState) {
        out.add(designState);
      } else {
        out.add(nextState);
      }
    }

    for (final designState in designStates) {
      final key = designState.name.trim().toLowerCase();
      if (seenNamesLower.contains(key)) continue;
      final wasInBase = findState(baseStates, designState.name) != null;
      if (!wasInBase) {
        seenNamesLower.add(key);
        out.add(designState);
      }
    }
    return out;
  }

  static List<LifecycleTransition> _mergeLifecycleTransitions({
    required List<LifecycleTransition>? baseTransitions,
    required List<LifecycleTransition> nextTransitions,
    required List<LifecycleTransition> designTransitions,
    required List<LifecycleState> validStates,
  }) {
    if (nextTransitions.isEmpty && designTransitions.isEmpty) {
      return const <LifecycleTransition>[];
    }
    final out = <LifecycleTransition>[];
    final seenIds = <String>{};
    final seenSignatures = <String>{};
    final validStateNames = <String>{
      for (final s in validStates) s.name.trim().toLowerCase(),
    };

    String sigOf(LifecycleTransition t) =>
        '${t.fromState.trim().toLowerCase()}->${t.toState.trim().toLowerCase()}|${t.trigger.trim().toLowerCase()}';

    LifecycleTransition? findTransition(
      List<LifecycleTransition>? list,
      LifecycleTransition target,
    ) {
      if (list == null) return null;
      for (final t in list) {
        if (t.id == target.id) return t;
      }
      final targetSig = sigOf(target);
      for (final t in list) {
        if (sigOf(t) == targetSig) return t;
      }
      return null;
    }

    for (final nextTr in nextTransitions) {
      seenIds.add(nextTr.id);
      seenSignatures.add(sigOf(nextTr));
      final baseTr = findTransition(baseTransitions, nextTr);
      final designTr = findTransition(designTransitions, nextTr);
      if (baseTr != null && designTr != null && nextTr == baseTr) {
        out.add(designTr);
      } else {
        out.add(nextTr);
      }
    }

    for (final designTr in designTransitions) {
      if (seenIds.contains(designTr.id) ||
          seenSignatures.contains(sigOf(designTr))) {
        continue;
      }
      final wasInBase = findTransition(baseTransitions, designTr) != null;
      if (wasInBase) continue;
      final statesRemainValid =
          validStateNames.isEmpty ||
          (validStateNames.contains(designTr.fromState.trim().toLowerCase()) &&
              validStateNames.contains(designTr.toState.trim().toLowerCase()));
      if (statesRemainValid) {
        seenIds.add(designTr.id);
        seenSignatures.add(sigOf(designTr));
        out.add(designTr);
      }
    }
    return out;
  }

  static List<BusinessRelation> _mergeRelations({
    required List<BusinessRelation>? baseRelations,
    required List<BusinessRelation> nextRelations,
    required List<BusinessRelation> designRelations,
  }) {
    if (nextRelations.isEmpty && designRelations.isEmpty) {
      return const <BusinessRelation>[];
    }
    final out = <BusinessRelation>[...nextRelations];
    final seenIds = <String>{for (final r in out) r.id};
    final seenNames = <String>{for (final r in out) r.name.toLowerCase()};

    for (final dRel in designRelations) {
      if (seenIds.contains(dRel.id) ||
          seenNames.contains(dRel.name.toLowerCase())) {
        continue;
      }
      final wasInBase =
          baseRelations != null &&
          baseRelations.any(
            (b) =>
                b.id == dRel.id || b.name.toLowerCase() == dRel.name.toLowerCase(),
          );
      if (!wasInBase) {
        seenIds.add(dRel.id);
        seenNames.add(dRel.name.toLowerCase());
        out.add(dRel);
      }
    }
    return out;
  }

  static String _joinPath(String parent, String segment) =>
      parent.isEmpty ? segment : '$parent.$segment';
}
