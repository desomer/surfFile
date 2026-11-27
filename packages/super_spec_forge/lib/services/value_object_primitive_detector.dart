/// Détection heuristique de *Primitive Obsession*, promotion d'attributs métier
/// en [ValueObjectSpec] et analyse d'impacts / usages dans [DomainCatalog]
/// ([ValueObjectPrimitiveDetector]).
library;

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';

import '../models/business_object_spec.dart';
import '../models/domain_catalog.dart';
import '../models/json_schema_constraints.dart';
import '../models/value_object_spec.dart';

/// Nature d'une suggestion de remplacement d'un attribut par un Value Object.
enum PrimitiveObsessionMatchKind {
  /// Un Value Object correspondant existe déjà dans le catalogue (domaine ou Shared Kernel).
  existingCatalogVo,

  /// Aucun Value Object existant ne correspond ; une création est proposée.
  newValueObjectCandidate,
}

/// Suggestion d'élimination de *Primitive Obsession* sur un attribut de modèle.
@immutable
class PrimitiveObsessionSuggestion {
  /// Crée une suggestion de Value Object.
  const PrimitiveObsessionSuggestion({
    required this.domainId,
    required this.entryId,
    required this.entryName,
    required this.attributePath,
    required this.attribute,
    required this.matchKind,
    required this.proposedSpec,
    required this.reason,
    this.matchedVo,
    this.suggestedScope = ValueObjectScope.domain,
  });

  /// Identifiant du domaine propriétaire du modèle.
  final String domainId;

  /// Identifiant de l'entrée DSL dans `DomainContracts`.
  final String entryId;

  /// Nom technique du modèle/contrat contenant l'attribut.
  final String entryName;

  /// Chemin d'IDs d'attributs dans le modèle.
  final List<String> attributePath;

  /// Attribut source actuellement primitif ou sous-objet.
  final BusinessAttribute attribute;

  /// Indique si la suggestion réutilise un VO existant ou en crée un nouveau.
  final PrimitiveObsessionMatchKind matchKind;

  /// Value Object existant correspondant si [matchKind] vaut [PrimitiveObsessionMatchKind.existingCatalogVo].
  final ResolvedValueObject? matchedVo;

  /// Spécification pré-remplie prête à être créée (ou celle de [matchedVo]).
  final ValueObjectSpec proposedSpec;

  /// Justification métier/architecturale affichée à l'utilisateur.
  final String reason;

  /// Portée conseillée si création.
  final ValueObjectScope suggestedScope;
}

/// Référence d'usage d'un Value Object par un attribut d'un modèle/contrat.
@immutable
class ValueObjectUsageRef {
  /// Crée une référence d'usage.
  const ValueObjectUsageRef({
    required this.domainId,
    required this.domainName,
    required this.entryId,
    required this.entryName,
    required this.attributePath,
    required this.attributeName,
  });

  /// Identifiant du domaine.
  final String domainId;

  /// Nom affiché du domaine.
  final String domainName;

  /// Identifiant de l'entrée dans `DomainContracts`.
  final String entryId;

  /// Nom de l'entrée dans `DomainContracts`.
  final String entryName;

  /// Chemin d'IDs d'attributs.
  final List<String> attributePath;

  /// Nom lisible du chemin d'attribut (ex. `facturation.montant`).
  final String attributeName;
}

/// Service pur d'analyse *Primitive Obsession*, de promotion et de comptage d'usages.
abstract final class ValueObjectPrimitiveDetector {
  static final List<_HeuristicRule> _heuristics = <_HeuristicRule>[
    _HeuristicRule(
      presetTechnicalName: 'EmailAddress',
      suggestedScope: ValueObjectScope.shared,
      matches: (attr, lower) =>
          attr.type == BusinessAttributeType.email ||
          lower.contains('email') ||
          lower.contains('courriel') ||
          lower.endsWith('mail'),
      reason:
          'Adresse email représentée en primitif : un Value Object normalise (trim/lowercase) et garantit le format RFC.',
    ),
    _HeuristicRule(
      presetTechnicalName: 'Iban',
      suggestedScope: ValueObjectScope.shared,
      matches: (attr, lower) => lower.contains('iban'),
      reason:
          'IBAN manipulé en chaîne brute : un Value Object garantit la normalisation et le contrôle modulo 97.',
    ),
    _HeuristicRule(
      presetTechnicalName: 'PhoneNumber',
      suggestedScope: ValueObjectScope.shared,
      matches: (attr, lower) =>
          lower.contains('phone') ||
          lower.contains('telephone') ||
          lower.contains('tel_') ||
          lower == 'tel' ||
          lower.contains('mobile'),
      reason:
          'Numéro de téléphone en chaîne brute : un Value Object impose le format E.164.',
    ),
    _HeuristicRule(
      presetTechnicalName: 'CurrencyCode',
      suggestedScope: ValueObjectScope.shared,
      matches: (attr, lower) =>
          (attr.type == BusinessAttributeType.string) &&
          (lower.contains('currency') || lower.contains('devise')),
      reason:
          'Devise stockée en texte libre : un Value Object garantit un code ISO 4217 sur 3 majuscules.',
    ),
    _HeuristicRule(
      presetTechnicalName: 'Money',
      suggestedScope: ValueObjectScope.shared,
      matches: (attr, lower) =>
          (attr.type == BusinessAttributeType.number ||
              attr.type == BusinessAttributeType.integer ||
              attr.type == BusinessAttributeType.object) &&
          (lower.contains('amount') ||
              lower.contains('montant') ||
              lower.contains('price') ||
              lower.contains('prix') ||
              lower.contains('total') ||
              lower.contains('tarif') ||
              lower.contains('cout') ||
              lower.contains('cost')),
      reason:
          'Montant financier modélisé sans devise/encapsulation : un Value Object Money évite les erreurs d’arrondi et de mélange de devises.',
    ),
    _HeuristicRule(
      presetTechnicalName: 'Percentage',
      suggestedScope: ValueObjectScope.shared,
      matches: (attr, lower) =>
          (attr.type == BusinessAttributeType.number ||
              attr.type == BusinessAttributeType.integer) &&
          (lower.contains('percent') ||
              lower.contains('pourcent') ||
              lower.contains('taux') ||
              lower.contains('rate') ||
              lower.contains('ratio') ||
              lower.contains('discount') ||
              lower.contains('remise')),
      reason:
          'Taux/pourcentage numérique non encapsulé : un Value Object borne la valeur (0–100) de manière explicite.',
    ),
    _HeuristicRule(
      presetTechnicalName: 'PostalAddress',
      suggestedScope: ValueObjectScope.shared,
      matches: (attr, lower) =>
          attr.type == BusinessAttributeType.object &&
          (lower.contains('address') || lower.contains('adresse')),
      reason:
          'Sous-objet d’adresse dupliqué entre modèles : un Value Object composite PostalAddress centralise la structure et les règles.',
    ),
    _HeuristicRule(
      presetTechnicalName: 'DateRange',
      suggestedScope: ValueObjectScope.shared,
      matches: (attr, lower) =>
          attr.type == BusinessAttributeType.object &&
          (lower.contains('period') ||
              lower.contains('periode') ||
              lower.contains('daterange') ||
              lower.contains('plage')),
      reason:
          'Intervalle de dates modélisé en sous-objet libre : un Value Object DateRange garantit startDate <= endDate.',
    ),
    _HeuristicRule(
      presetTechnicalName: 'PositiveQuantity',
      suggestedScope: ValueObjectScope.shared,
      matches: (attr, lower) =>
          attr.type == BusinessAttributeType.integer &&
          (lower.contains('quantity') ||
              lower.contains('quantite') ||
              lower == 'qty' ||
              lower == 'qte'),
      reason:
          'Quantité entière brute : un Value Object empêche les valeurs nulles ou négatives incohérentes.',
    ),
    _HeuristicRule(
      presetTechnicalName: 'Slug',
      suggestedScope: ValueObjectScope.shared,
      matches: (attr, lower) =>
          attr.type == BusinessAttributeType.string && lower.contains('slug'),
      reason:
          'Slug URL en texte libre : un Value Object garantit le format kebab-case canonique.',
    ),
  ];

  /// Analyse un modèle [object] et renvoie les suggestions *Primitive Obsession*.
  static List<PrimitiveObsessionSuggestion> detectForObject({
    required String domainId,
    required String entryId,
    required String entryName,
    required BusinessObjectSpec object,
    required List<ResolvedValueObject> catalogVos,
  }) {
    final suggestions = <PrimitiveObsessionSuggestion>[];
    final presetsByTech = <String, ValueObjectSpec>{
      for (final p in ValueObjectPresets.standardPresets)
        p.technicalName.toLowerCase(): p,
    };

    void visit(List<BusinessAttribute> attrs, List<String> prefix) {
      for (final attr in attrs) {
        final path = <String>[...prefix, attr.id];
        if (attr.type == BusinessAttributeType.valueObject ||
            attr.type == BusinessAttributeType.reference ||
            attr.type == BusinessAttributeType.uuid ||
            attr.type == BusinessAttributeType.boolean) {
          continue;
        }
        final lower = attr.name.toLowerCase();
        if (lower == 'id' || lower.endsWith('id') && attr.type == BusinessAttributeType.string) {
          continue;
        }

        // 1. Correspondance directe par nom avec un VO existant du catalogue.
        final directVo = _findMatchingCatalogVoByName(attr, catalogVos);
        if (directVo != null) {
          suggestions.add(
            PrimitiveObsessionSuggestion(
              domainId: domainId,
              entryId: entryId,
              entryName: entryName,
              attributePath: path,
              attribute: attr,
              matchKind: PrimitiveObsessionMatchKind.existingCatalogVo,
              matchedVo: directVo,
              proposedSpec: directVo.spec,
              reason:
                  'L’attribut « ${attr.name} » correspond au Value Object existant ${directVo.spec.technicalName} (${directVo.scope.label}).',
              suggestedScope: directVo.scope,
            ),
          );
          continue;
        }

        // 2. Heuristiques métier classiques (matching catalogue ou preset).
        _HeuristicRule? matchedRule;
        for (final rule in _heuristics) {
          if (rule.matches(attr, lower)) {
            matchedRule = rule;
            break;
          }
        }
        if (matchedRule != null) {
          final existing = catalogVos
              .where(
                (v) =>
                    v.spec.technicalName.toLowerCase() ==
                    matchedRule!.presetTechnicalName.toLowerCase(),
              )
              .firstOrNull;
          if (existing != null) {
            suggestions.add(
              PrimitiveObsessionSuggestion(
                domainId: domainId,
                entryId: entryId,
                entryName: entryName,
                attributePath: path,
                attribute: attr,
                matchKind: PrimitiveObsessionMatchKind.existingCatalogVo,
                matchedVo: existing,
                proposedSpec: existing.spec,
                reason:
                    'Réutiliser le Value Object ${existing.spec.technicalName} (${existing.scope.label}) plutôt que « ${attr.type.dslKeyword} ».',
                suggestedScope: existing.scope,
              ),
            );
          } else {
            final preset =
                presetsByTech[matchedRule.presetTechnicalName.toLowerCase()];
            final proposed = (preset ?? buildProposedValueObject(attr))
                .copyWith(id: 'vo_${shortid.generate()}');
            suggestions.add(
              PrimitiveObsessionSuggestion(
                domainId: domainId,
                entryId: entryId,
                entryName: entryName,
                attributePath: path,
                attribute: attr,
                matchKind: PrimitiveObsessionMatchKind.newValueObjectCandidate,
                proposedSpec: proposed,
                reason: matchedRule.reason,
                suggestedScope: matchedRule.suggestedScope,
              ),
            );
          }
          continue;
        }

        // 3. Primitif fortement contraint (regex, x-mask, bornes strictes).
        final sc = attr.schemaConstraints;
        final hasStrongConstraint =
            (sc.pattern != null && sc.pattern!.trim().isNotEmpty) ||
            (sc.xMask != null && sc.xMask!.trim().isNotEmpty);
        if (hasStrongConstraint &&
            ValueObjectSpec.allowedScalarTypes.contains(attr.type)) {
          suggestions.add(
            PrimitiveObsessionSuggestion(
              domainId: domainId,
              entryId: entryId,
              entryName: entryName,
              attributePath: path,
              attribute: attr,
              matchKind: PrimitiveObsessionMatchKind.newValueObjectCandidate,
              proposedSpec: buildProposedValueObject(attr),
              reason:
                  'Contraintes de format (${sc.pattern != null ? 'pattern' : 'x-mask'}) portées sur un primitif : encapsuler dans un Value Object pour garantir l’auto-validation.',
              suggestedScope: ValueObjectScope.domain,
            ),
          );
          continue;
        }

        if (attr.type == BusinessAttributeType.object && attr.children.isNotEmpty) {
          visit(attr.children, path);
        }
      }
    }

    visit(object.attributes, const <String>[]);
    return suggestions;
  }

  /// Analyse tous les modèles/contrats d'un domaine [domainId].
  static List<PrimitiveObsessionSuggestion> detectForDomain(
    DomainCatalog catalog,
    String domainId,
  ) {
    final domain = catalog.domains
        .where((d) => d.id == domainId)
        .firstOrNull;
    if (domain == null || domain.contracts == null) {
      return const <PrimitiveObsessionSuggestion>[];
    }
    final contracts = domain.contracts!;
    final catalogVos = catalog.resolvedValueObjectsForDomain(domainId);
    final out = <PrimitiveObsessionSuggestion>[];
    for (final group in contracts.groups) {
      for (final node in group.children) {
        final obj = contracts.objectFor(node);
        if (obj.attributes.isEmpty) continue;
        out.addAll(
          detectForObject(
            domainId: domainId,
            entryId: node.id,
            entryName: node.name,
            object: obj,
            catalogVos: catalogVos,
          ),
        );
      }
    }
    return out;
  }

  /// Construit un [ValueObjectSpec] pré-rempli à partir d'un attribut existant.
  static ValueObjectSpec buildProposedValueObject(
    BusinessAttribute attr, {
    String? id,
    String? technicalName,
  }) {
    final tech = (technicalName != null && technicalName.trim().isNotEmpty)
        ? BusinessAttribute.toPascalCaseDslIdentifier(technicalName)
        : BusinessAttribute.toPascalCaseDslIdentifier(attr.name);
    final effectiveTech = tech.isEmpty ? 'CustomValue' : tech;
    final voId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : 'vo_${shortid.generate()}';

    if (attr.type == BusinessAttributeType.object && attr.children.isNotEmpty) {
      return ValueObjectSpec(
        id: voId,
        technicalName: effectiveTech,
        name: attr.description.isNotEmpty ? attr.description : effectiveTech,
        description: attr.description.isNotEmpty
            ? attr.description
            : 'Value Object composite promu depuis l’attribut « ${attr.name} ».',
        kind: ValueObjectKind.composite,
        fields: attr.children,
        constraints: attr.constraints,
      );
    }

    final primitive = ValueObjectSpec.allowedScalarTypes.contains(attr.type)
        ? attr.type
        : BusinessAttributeType.string;
    final examples = <ValueObjectExample>[
      for (var i = 0; i < attr.schemaConstraints.examples.length; i++)
        ValueObjectExample(
          id: 'voex_ok_${i + 1}',
          value: '${attr.schemaConstraints.examples[i]}',
          isValid: true,
          reason: 'Exemple issu de l’attribut « ${attr.name} »',
        ),
    ];
    return ValueObjectSpec(
      id: voId,
      technicalName: effectiveTech,
      name: effectiveTech,
      description: attr.description.isNotEmpty
          ? attr.description
          : 'Value Object atomique promu depuis l’attribut « ${attr.name} ».',
      kind: ValueObjectKind.scalar,
      primitiveType: primitive,
      enumValues: primitive == BusinessAttributeType.enumeration
          ? attr.enumValues
          : const <String>[],
      schemaConstraints: attr.schemaConstraints,
      constraints: attr.constraints,
      examples: examples,
    );
  }

  /// Remplace l'attribut situé à [attributePath] dans [object] par un typage
  /// [BusinessAttributeType.valueObject] pointant vers [valueObjectId].
  static BusinessObjectSpec replaceAttributeAtPath(
    BusinessObjectSpec object,
    List<String> attributePath, {
    required String valueObjectId,
  }) {
    if (attributePath.isEmpty) return object;

    List<BusinessAttribute> rewrite(
      List<BusinessAttribute> list,
      int depth,
    ) {
      final targetId = attributePath[depth];
      return [
        for (final attr in list)
          if (attr.id != targetId)
            attr
          else if (depth == attributePath.length - 1)
            attr.copyWith(
              type: BusinessAttributeType.valueObject,
              valueObjectId: valueObjectId,
              referenceObjectId: '',
              enumValues: const <String>[],
              schemaConstraints: JsonSchemaConstraints.empty,
              children: const <BusinessAttribute>[],
            )
          else
            attr.copyWith(children: rewrite(attr.children, depth + 1)),
      ];
    }

    return object.copyWith(attributes: rewrite(object.attributes, 0));
  }

  /// Recense tous les usages d'un Value Object [vo] dans les modèles du catalogue.
  static List<ValueObjectUsageRef> findUsages(
    DomainCatalog catalog,
    ValueObjectSpec vo, {
    required ValueObjectScope scope,
    String? ownerDomainId,
  }) {
    final usages = <ValueObjectUsageRef>[];
    final targetId = vo.id;
    final targetTechLower = vo.technicalName.toLowerCase();

    for (final domain in catalog.domains) {
      if (scope == ValueObjectScope.domain && domain.id != ownerDomainId) {
        continue;
      }
      // Si le VO est dans le Shared Kernel mais masqué dans ce domaine par un homonyme
      // de domaine, seuls les attributs ciblant explicitement son ID comptent.
      final shadowedByDomain =
          scope == ValueObjectScope.shared &&
          domain.valueObjects.any(
            (dvo) => dvo.technicalName.toLowerCase() == targetTechLower,
          );
      final contracts = domain.contracts;
      if (contracts == null) continue;

      for (final group in contracts.groups) {
        for (final node in group.children) {
          final obj = contracts.objectFor(node);
          void scan(
            List<BusinessAttribute> attrs,
            List<String> pathIds,
            List<String> pathNames,
          ) {
            for (final attr in attrs) {
              final nextIds = <String>[...pathIds, attr.id];
              final nextNames = <String>[...pathNames, attr.name];
              if (attr.type == BusinessAttributeType.valueObject) {
                final ref = attr.valueObjectId.trim();
                final matchesId = ref == targetId;
                final matchesName =
                    !shadowedByDomain && ref.toLowerCase() == targetTechLower;
                if (matchesId || matchesName) {
                  usages.add(
                    ValueObjectUsageRef(
                      domainId: domain.id,
                      domainName: domain.name,
                      entryId: node.id,
                      entryName: node.name,
                      attributePath: nextIds,
                      attributeName: nextNames.join('.'),
                    ),
                  );
                }
              }
              if (attr.children.isNotEmpty) {
                scan(attr.children, nextIds, nextNames);
              }
            }
          }

          scan(obj.attributes, const <String>[], const <String>[]);
        }
      }
    }
    return usages;
  }

  static ResolvedValueObject? _findMatchingCatalogVoByName(
    BusinessAttribute attr,
    List<ResolvedValueObject> catalogVos,
  ) {
    final normAttr = BusinessAttribute.toPascalCaseDslIdentifier(
      attr.name,
    ).toLowerCase();
    for (final vo in catalogVos) {
      final voTech = vo.spec.technicalName.toLowerCase();
      if (voTech == normAttr) return vo;
    }
    return null;
  }
}

class _HeuristicRule {
  const _HeuristicRule({
    required this.presetTechnicalName,
    required this.suggestedScope,
    required this.matches,
    required this.reason,
  });

  final String presetTechnicalName;
  final ValueObjectScope suggestedScope;
  final bool Function(BusinessAttribute attr, String lowerName) matches;
  final String reason;
}
