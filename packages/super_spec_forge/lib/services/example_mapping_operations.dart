/// Opérations métier pures pour l'Example Mapping ([ExampleMappingOperations]) :
/// initialisation depuis les objets métiers & cas d'usage, promotion d'une carte
/// bleue en règle `RG-xxx` et enrichissement des exemples JSON Schema d'un objet métier.
library;

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/example_mapping_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_forge_project.dart';

/// Mode d'injection des valeurs d'exemples dans le JSON Schema d'un attribut.
enum ExampleInjectionMode {
  /// Ajoute les valeurs sélectionnées qui n'existent pas encore dans l'attribut.
  append(
    'Compléter',
    'Conserve les exemples actuels et ajoute les nouvelles valeurs cochées.',
  ),

  /// Remplace la liste des exemples actuels des attributs cochés par la sélection.
  replace(
    'Remplacer',
    'Remplace les exemples actuels de chaque attribut retenu par les valeurs cochées.',
  );

  const ExampleInjectionMode(this.label, this.description);

  /// Libellé court du mode.
  final String label;

  /// Explication affichée dans le dialogue de comparaison.
  final String description;
}

/// Valeur candidate extraite des cartes vertes d'une story avec ses sources.
@immutable
class ExampleCandidateValue {
  /// Construit une valeur candidate.
  ExampleCandidateValue({
    required this.value,
    required List<String> sources,
    this.alreadyPresent = false,
  }) : sources = List<String>.unmodifiable(sources);

  /// Valeur JSON brute issue d'`inputValues` ou `expectedOutcome`.
  final Object? value;

  /// Libellés des règles/exemples d'où provient cette valeur.
  final List<String> sources;

  /// Indique si la valeur figure déjà dans `schemaConstraints.examples`.
  final bool alreadyPresent;
}

/// Comparaison entre les exemples actuels d'un attribut et les candidats verts.
@immutable
class AttributeExampleComparison {
  /// Construit une comparaison pour un attribut donné.
  AttributeExampleComparison({
    required this.attributePath,
    required this.attributeName,
    required this.typeLabel,
    required List<Object?> existingExamples,
    required List<ExampleCandidateValue> candidates,
  }) : existingExamples = List<Object?>.unmodifiable(existingExamples),
       candidates = List<ExampleCandidateValue>.unmodifiable(candidates);

  /// Chemin complet de l'attribut dans l'objet (ex. `montantHt` ou `adresse.ville`).
  final String attributePath;

  /// Nom feuille de l'attribut.
  final String attributeName;

  /// Libellé du type de l'attribut (`number`, `enum`, etc.).
  final String typeLabel;

  /// Exemples actuellement enregistrés dans `schemaConstraints.examples`.
  final List<Object?> existingExamples;

  /// Valeurs candidates issues des cartes vertes.
  final List<ExampleCandidateValue> candidates;

  /// Vrai si au moins un candidat n'est pas encore présent dans l'objet.
  bool get hasNewCandidates => candidates.any((c) => !c.alreadyPresent);

  /// Vrai si des candidats ont été trouvés pour cet attribut.
  bool get hasCandidates => candidates.isNotEmpty;
}

/// Aperçu complet de comparaison avant injection d'exemples dans l'objet cible.
@immutable
class ExampleInjectionPreview {
  /// Construit l'aperçu de comparaison.
  ExampleInjectionPreview({
    required this.story,
    required this.targetObject,
    required List<AttributeExampleComparison> attributeComparisons,
    required Map<String, List<ExampleCandidateValue>> unmatchedCandidates,
  }) : attributeComparisons = List<AttributeExampleComparison>.unmodifiable(
         attributeComparisons,
       ),
       unmatchedCandidates = Map<String, List<ExampleCandidateValue>>.unmodifiable(
         {
           for (final entry in unmatchedCandidates.entries)
             entry.key: List<ExampleCandidateValue>.unmodifiable(entry.value),
         },
       );

  /// Story jaune source.
  final ExampleMapStory story;

  /// Objet métier cible s'il existe.
  final BusinessObjectSpec? targetObject;

  /// Attributs comparés (ceux ayant des candidats verts et/ou des exemples existants).
  final List<AttributeExampleComparison> attributeComparisons;

  /// Clés issues des cartes vertes ne correspondant à aucun attribut de l'objet.
  final Map<String, List<ExampleCandidateValue>> unmatchedCandidates;
}

/// Services déterministes manipulant les tableaux d'Example Mapping et leur
/// synchronisation avec [BusinessObjectSpec] et [BusinessRuleSpec].
abstract final class ExampleMappingOperations {
  /// Génère le prochain code séquentiel `EM-xxx` non utilisé dans [existing].
  static String nextStoryCode(List<ExampleMapStory> existing) {
    final pattern = RegExp(r'^EM-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final story in existing) {
      final match = pattern.firstMatch(story.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'EM-${(maxIndex + 1).toString().padLeft(3, '0')}';
  }

  /// Génère le prochain code séquentiel `RG-xxx` non utilisé dans [existing].
  static String nextRuleCode(List<BusinessRuleSpec> existing) {
    final pattern = RegExp(r'^RG-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final rule in existing) {
      final match = pattern.firstMatch(rule.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'RG-${(maxIndex + 1).toString().padLeft(3, '0')}';
  }

  /// Initialise des tableaux Jaunes d'Example Mapping pour les objets métiers (et
  /// cas d'usage associés) qui ne possèdent pas encore de tableau dans [project].
  static List<ExampleMapStory> seedStoriesFromObjectsAndUseCases(
    SpecForgeProject project,
  ) {
    final coveredObjectIds = <String>{
      for (final story in project.exampleMappings)
        if (story.targetObjectId.trim().isNotEmpty) story.targetObjectId,
    };
    final runningStories = List<ExampleMapStory>.of(project.exampleMappings);
    final created = <ExampleMapStory>[];

    for (final obj in project.businessObjects) {
      if (coveredObjectIds.contains(obj.id)) continue;
      final code = nextStoryCode(runningStories);
      final matchedUseCase = _findMatchingUseCase(
        project.cahierDesCharges.useCases,
        obj,
      );
      final matchedReqs = _findMatchingRequirements(
        project.cahierDesCharges.functionalRequirements,
        obj,
      );

      final rules = <ExampleMapRule>[];
      // 1. Règles issues du cycle de vie éventuel
      for (final tr in obj.lifecycleTransitions.take(3)) {
        final exId = _shortId('ex');
        rules.add(
          ExampleMapRule(
            id: _shortId('emr'),
            title:
                'Transition ${tr.fromState} → ${tr.toState} (${tr.trigger.isEmpty ? 'action métier' : tr.trigger})',
            description: tr.guardSummary,
            category: BusinessRuleCategory.stateTransition,
            targetObjectIds: [obj.id],
            targetAttributes: ['${obj.technicalName}.statut'],
            examples: [
              ExampleMapExample(
                id: exId,
                title: 'Passage valide de ${tr.fromState} à ${tr.toState}',
                kind: ExampleMapExampleKind.stateTransition,
                given:
                    'Un(e) ${obj.name} à l’état « ${tr.fromState} »${tr.guardSummary.isEmpty ? '' : ' (${tr.guardSummary})'}',
                when: tr.trigger.isEmpty ? 'L’utilisateur valide' : tr.trigger,
                then: 'L’état devient « ${tr.toState} »',
                inputValues: {'statut': tr.fromState},
                expectedOutcome: {'statut': tr.toState},
              ),
            ],
          ),
        );
      }

      // 2. Règle d'intégrité sur les attributs obligatoires ou contraints
      final keyAttrs = obj.attributes
          .where(
            (a) =>
                a.required ||
                a.schemaConstraints.isNotEmpty ||
                a.enumValues.isNotEmpty,
          )
          .take(4)
          .toList();
      if (keyAttrs.isNotEmpty) {
        final sampleInputs = <String, Object?>{
          for (final a in keyAttrs) a.name: _sampleValueForAttribute(a),
        };
        rules.add(
          ExampleMapRule(
            id: _shortId('emr'),
            title: 'Complétude et format des attributs clés de ${obj.name}',
            description:
                'Vérifie les champs obligatoires et bornes de ${obj.technicalName}',
            category: BusinessRuleCategory.validation,
            targetObjectIds: [obj.id],
            targetAttributes: [
              for (final a in keyAttrs) '${obj.technicalName}.${a.name}',
            ],
            examples: [
              ExampleMapExample(
                id: _shortId('ex'),
                title: 'Création nominale de ${obj.name}',
                kind: ExampleMapExampleKind.nominal,
                given: 'Tous les attributs requis sont renseignés',
                when: 'L’objet ${obj.technicalName} est enregistré',
                then: 'L’enregistrement réussit sans erreur de schéma',
                inputValues: sampleInputs,
              ),
            ],
          ),
        );
      }

      final questions = <ExampleMapQuestion>[
        ExampleMapQuestion(
          id: _shortId('emq'),
          question:
              'Quels cas aux limites ou exceptions métier peuvent bloquer ou modifier ${obj.name} ?',
          impact:
              'Permet de vérifier s’il manque des attributs, énumérations ou contraintes sur ${obj.technicalName}',
          linkedObjectId: obj.id,
        ),
      ];

      final story = ExampleMapStory(
        id: _shortId('em'),
        code: code,
        title: matchedUseCase != null
            ? '${obj.name} — ${matchedUseCase.title}'
            : 'Affinage de ${obj.name}',
        description: obj.description.isNotEmpty
            ? obj.description
            : 'Exploration par exemples de ${obj.name} (${obj.technicalName})',
        targetObjectId: obj.id,
        useCaseId: matchedUseCase?.id ?? '',
        requirementIds: [for (final r in matchedReqs) r.code],
        rules: rules,
        questions: questions,
      );
      runningStories.add(story);
      created.add(story);
    }

    return created;
  }

  /// Promeut une carte bleue [ruleId] de la story [storyId] en [BusinessRuleSpec]
  /// (`RG-xxx`) et associe son `linkedRuleId`. Si la règle est déjà liée à une
  /// règle existante, met à jour les exemples de cette règle.
  static ({
    SpecForgeProject project,
    BusinessRuleSpec rule,
    bool createdNew,
  })
  promoteRuleToBusinessRule(
    SpecForgeProject project, {
    required String storyId,
    required String ruleId,
  }) {
    final storyIndex = project.exampleMappings.indexWhere(
      (s) => s.id == storyId,
    );
    if (storyIndex < 0) {
      throw FormatException('Story Example Mapping introuvable : $storyId');
    }
    final story = project.exampleMappings[storyIndex];
    final emRuleIndex = story.rules.indexWhere((r) => r.id == ruleId);
    if (emRuleIndex < 0) {
      throw FormatException('Règle bleue introuvable : $ruleId');
    }
    final emRule = story.rules[emRuleIndex];

    final formattedExamples = <String>[
      for (final ex in emRule.examples) _formatExampleSummary(ex),
    ];

    final existingIdx = emRule.linkedRuleId.trim().isEmpty
        ? -1
        : project.businessRules.indexWhere(
            (r) =>
                r.id == emRule.linkedRuleId ||
                r.code.toLowerCase() == emRule.linkedRuleId.toLowerCase(),
          );

    final targetObjectIds = emRule.targetObjectIds.isNotEmpty
        ? emRule.targetObjectIds
        : (story.targetObjectId.trim().isNotEmpty
              ? <String>[story.targetObjectId]
              : const <String>[]);

    final BusinessRuleSpec resultRule;
    final List<BusinessRuleSpec> nextRules;
    final bool createdNew;

    if (existingIdx >= 0) {
      final existing = project.businessRules[existingIdx];
      final mergedExamples = <String>[
        ...existing.examples,
        for (final ex in formattedExamples)
          if (!existing.examples.contains(ex)) ex,
      ];
      resultRule = existing.copyWith(
        examples: mergedExamples,
        targetObjectIds: existing.targetObjectIds.isEmpty
            ? targetObjectIds
            : existing.targetObjectIds,
        targetAttributes: existing.targetAttributes.isEmpty
            ? emRule.targetAttributes
            : existing.targetAttributes,
      );
      nextRules = [
        for (var i = 0; i < project.businessRules.length; i++)
          if (i == existingIdx) resultRule else project.businessRules[i],
      ];
      createdNew = false;
    } else {
      final firstNominal = emRule.examples.firstOrNull;
      final firstError = emRule.examples
          .where((e) => e.kind == ExampleMapExampleKind.error)
          .firstOrNull;
      final code = nextRuleCode(project.businessRules);
      resultRule = BusinessRuleSpec(
        id: _shortId('rule'),
        code: code,
        title: emRule.title,
        category: emRule.category,
        priority: emRule.category == BusinessRuleCategory.validation
            ? BusinessRulePriority.high
            : BusinessRulePriority.medium,
        description: emRule.description.isNotEmpty
            ? emRule.description
            : '${emRule.title} (issue de ${story.code})',
        targetObjectIds: targetObjectIds,
        targetAttributes: emRule.targetAttributes,
        trigger: firstNominal?.when ?? '',
        condition: (firstError ?? firstNominal)?.given ?? '',
        effect: (firstError ?? firstNominal)?.then ?? '',
        errorMessage: firstError?.then ?? '',
        examples: formattedExamples,
      );
      nextRules = [...project.businessRules, resultRule];
      createdNew = true;
    }

    final updatedEmRule = emRule.copyWith(linkedRuleId: resultRule.id);
    final updatedStory = story.copyWith(
      rules: [
        for (var i = 0; i < story.rules.length; i++)
          if (i == emRuleIndex) updatedEmRule else story.rules[i],
      ],
    );
    final nextStories = [
      for (var i = 0; i < project.exampleMappings.length; i++)
        if (i == storyIndex) updatedStory else project.exampleMappings[i],
    ];

    final nextProject = project.copyWith(
      businessRules: nextRules,
      exampleMappings: nextStories,
    );
    nextProject.validate();
    return (project: nextProject, rule: resultRule, createdNew: createdNew);
  }

  /// Injecte les valeurs concrètes (`inputValues` & `expectedOutcome`) des cartes
  /// vertes de [storyId] (ou uniquement [exampleId]) dans les `examples` JSON Schema
  /// des attributs correspondants de l'objet métier cible.
  static ({SpecForgeProject project, int injectedValuesCount})
  enrichObjectExamplesFromStory(
    SpecForgeProject project, {
    required String storyId,
    String? exampleId,
  }) {
    final storyIndex = project.exampleMappings.indexWhere(
      (s) => s.id == storyId,
    );
    if (storyIndex < 0) {
      throw FormatException('Story Example Mapping introuvable : $storyId');
    }
    final story = project.exampleMappings[storyIndex];
    final targetObj = story.targetObjectId.trim().isEmpty
        ? null
        : project.findBusinessObject(story.targetObjectId);
    if (targetObj == null) {
      return (project: project, injectedValuesCount: 0);
    }

    final samplesByAttr = <String, List<Object?>>{};
    for (final rule in story.rules) {
      for (final ex in rule.examples) {
        if (exampleId != null && ex.id != exampleId) continue;
        void collect(Map<String, Object?> values) {
          for (final entry in values.entries) {
            final key = entry.key.trim().toLowerCase();
            if (key.isEmpty || entry.value == null) continue;
            final list = samplesByAttr.putIfAbsent(key, () => <Object?>[]);
            if (!list.any((v) => v == entry.value) && list.length < 5) {
              list.add(entry.value);
            }
          }
        }

        collect(ex.inputValues);
        collect(ex.expectedOutcome);
      }
    }

    if (samplesByAttr.isEmpty) {
      return (project: project, injectedValuesCount: 0);
    }

    var injectedCount = 0;
    List<BusinessAttribute> enrichAttrs(List<BusinessAttribute> attrs) {
      return [
        for (final attr in attrs)
          () {
            final candidates = samplesByAttr[attr.name.toLowerCase()];
            var nextAttr = attr;
            if (candidates != null && candidates.isNotEmpty) {
              final existing = List<Object?>.of(
                attr.schemaConstraints.examples,
              );
              var addedHere = 0;
              for (final val in candidates) {
                if (!existing.any((e) => e == val) && existing.length < 5) {
                  existing.add(val);
                  addedHere++;
                }
              }
              if (addedHere > 0) {
                injectedCount += addedHere;
                nextAttr = nextAttr.copyWith(
                  schemaConstraints: nextAttr.schemaConstraints.copyWith(
                    examples: existing,
                  ),
                );
              }
            }
            if (nextAttr.children.isNotEmpty) {
              nextAttr = nextAttr.copyWith(
                children: enrichAttrs(nextAttr.children),
              );
            }
            return nextAttr;
          }(),
      ];
    }

    final updatedObj = targetObj.copyWith(
      attributes: enrichAttrs(targetObj.attributes),
    );
    if (injectedCount == 0) {
      return (project: project, injectedValuesCount: 0);
    }

    final note =
        '$injectedCount exemple(s) injecté(s) dans ${updatedObj.technicalName} depuis ${story.code}';
    final updatedStory = story.copyWith(
      refinementNotes: story.refinementNotes.contains(note)
          ? story.refinementNotes
          : [...story.refinementNotes, note],
    );

    final nextProject = project.copyWith(
      businessObjects: [
        for (final obj in project.businessObjects)
          if (obj.id == updatedObj.id) updatedObj else obj,
      ],
      exampleMappings: [
        for (var i = 0; i < project.exampleMappings.length; i++)
          if (i == storyIndex) updatedStory else project.exampleMappings[i],
      ],
    );
    nextProject.validate();
    return (project: nextProject, injectedValuesCount: injectedCount);
  }

  /// Construit un aperçu de comparaison entre les exemples existants de l'objet
  /// cible et les valeurs candidates extraites des cartes vertes de [storyId].
  static ExampleInjectionPreview buildExampleInjectionPreview(
    SpecForgeProject project, {
    required String storyId,
    String? exampleId,
  }) {
    final story = project.exampleMappings
        .where((s) => s.id == storyId)
        .firstOrNull;
    if (story == null) {
      throw FormatException('Story Example Mapping introuvable : $storyId');
    }
    final targetObj = story.targetObjectId.trim().isEmpty
        ? null
        : project.findBusinessObject(story.targetObjectId);

    final rawCandidatesByKey = <String, _RawCandidateBucket>{};
    for (final rule in story.rules) {
      for (final ex in rule.examples) {
        if (exampleId != null && ex.id != exampleId) continue;
        void collect(Map<String, Object?> values, String originTag) {
          for (final entry in values.entries) {
            final rawKey = entry.key.trim();
            final normKey = rawKey.toLowerCase();
            if (normKey.isEmpty || entry.value == null) continue;
            final bucket = rawCandidatesByKey.putIfAbsent(
              normKey,
              () => _RawCandidateBucket(displayKey: rawKey),
            );
            bucket.add(
              entry.value,
              '${rule.title} · ${ex.title} ($originTag)',
            );
          }
        }

        collect(ex.inputValues, 'Entrée');
        collect(ex.expectedOutcome, 'Attendu');
      }
    }

    if (targetObj == null) {
      return ExampleInjectionPreview(
        story: story,
        targetObject: null,
        attributeComparisons: const <AttributeExampleComparison>[],
        unmatchedCandidates: {
          for (final bucket in rawCandidatesByKey.values)
            bucket.displayKey: [
              for (final item in bucket.items)
                ExampleCandidateValue(
                  value: item.value,
                  sources: item.sources,
                ),
            ],
        },
      );
    }

    final matchedNormKeys = <String>{};
    final comparisons = <AttributeExampleComparison>[];

    void walkAttributes(List<BusinessAttribute> attrs, String prefix) {
      for (final attr in attrs) {
        final path = prefix.isEmpty ? attr.name : '$prefix.${attr.name}';
        final pathKey = path.toLowerCase();
        final nameKey = attr.name.toLowerCase();

        final combined = _RawCandidateBucket(displayKey: path);
        final byPath = rawCandidatesByKey[pathKey];
        if (byPath != null) {
          matchedNormKeys.add(pathKey);
          for (final item in byPath.items) {
            for (final src in item.sources) {
              combined.add(item.value, src);
            }
          }
        }
        if (nameKey != pathKey) {
          final byName = rawCandidatesByKey[nameKey];
          if (byName != null) {
            matchedNormKeys.add(nameKey);
            for (final item in byName.items) {
              for (final src in item.sources) {
                combined.add(item.value, src);
              }
            }
          }
        }

        final existing = attr.schemaConstraints.examples;
        if (combined.items.isNotEmpty || existing.isNotEmpty) {
          comparisons.add(
            AttributeExampleComparison(
              attributePath: path,
              attributeName: attr.name,
              typeLabel: attr.type.dslKeyword,
              existingExamples: existing,
              candidates: [
                for (final item in combined.items)
                  ExampleCandidateValue(
                    value: item.value,
                    sources: item.sources,
                    alreadyPresent: existing.any(
                      (e) => _jsonValuesEqual(e, item.value),
                    ),
                  ),
              ],
            ),
          );
        }

        if (attr.children.isNotEmpty) {
          walkAttributes(attr.children, path);
        }
      }
    }

    walkAttributes(targetObj.attributes, '');

    // Mettre d'abord les attributs ayant des nouveautés, puis ceux avec candidats, puis existants seuls.
    comparisons.sort((a, b) {
      int rank(AttributeExampleComparison c) {
        if (c.hasNewCandidates) return 0;
        if (c.hasCandidates) return 1;
        return 2;
      }

      return rank(a).compareTo(rank(b));
    });

    final unmatched = <String, List<ExampleCandidateValue>>{};
    for (final entry in rawCandidatesByKey.entries) {
      if (matchedNormKeys.contains(entry.key)) continue;
      unmatched[entry.value.displayKey] = [
        for (final item in entry.value.items)
          ExampleCandidateValue(
            value: item.value,
            sources: item.sources,
          ),
      ];
    }

    return ExampleInjectionPreview(
      story: story,
      targetObject: targetObj,
      attributeComparisons: comparisons,
      unmatchedCandidates: unmatched,
    );
  }

  /// Applique une sélection utilisateur issue de la popup de comparaison/choix
  /// sur les attributs de l'objet métier cible de [storyId].
  static ({
    SpecForgeProject project,
    int injectedValuesCount,
    int updatedAttributesCount,
  })
  applyExampleInjectionSelection(
    SpecForgeProject project, {
    required String storyId,
    required Map<String, List<Object?>> selectedByAttributePath,
    ExampleInjectionMode mode = ExampleInjectionMode.append,
  }) {
    final storyIndex = project.exampleMappings.indexWhere(
      (s) => s.id == storyId,
    );
    if (storyIndex < 0) {
      throw FormatException('Story Example Mapping introuvable : $storyId');
    }
    final story = project.exampleMappings[storyIndex];
    final targetObj = story.targetObjectId.trim().isEmpty
        ? null
        : project.findBusinessObject(story.targetObjectId);
    if (targetObj == null || selectedByAttributePath.isEmpty) {
      return (
        project: project,
        injectedValuesCount: 0,
        updatedAttributesCount: 0,
      );
    }

    var injectedValuesCount = 0;
    var updatedAttributesCount = 0;

    List<BusinessAttribute> applyAttrs(
      List<BusinessAttribute> attrs,
      String prefix,
    ) {
      return [
        for (final attr in attrs)
          () {
            final path = prefix.isEmpty ? attr.name : '$prefix.${attr.name}';
            final selected = selectedByAttributePath[path];
            var nextAttr = attr;

            if (selected != null && selected.isNotEmpty) {
              final existing = attr.schemaConstraints.examples;
              final List<Object?> nextExamples;
              var addedOrChangedCount = 0;

              if (mode == ExampleInjectionMode.append) {
                final merged = List<Object?>.of(existing);
                for (final val in selected) {
                  if (!merged.any((e) => _jsonValuesEqual(e, val))) {
                    merged.add(val);
                    addedOrChangedCount++;
                  }
                }
                nextExamples = merged;
              } else {
                final replaced = <Object?>[];
                for (final val in selected) {
                  if (!replaced.any((e) => _jsonValuesEqual(e, val))) {
                    replaced.add(val);
                  }
                }
                nextExamples = replaced;
                if (!_jsonListsEqual(existing, replaced)) {
                  addedOrChangedCount = replaced.length;
                }
              }

              if (addedOrChangedCount > 0) {
                injectedValuesCount += addedOrChangedCount;
                updatedAttributesCount++;
                nextAttr = nextAttr.copyWith(
                  schemaConstraints: nextAttr.schemaConstraints.copyWith(
                    examples: nextExamples,
                  ),
                );
              }
            }

            if (nextAttr.children.isNotEmpty) {
              nextAttr = nextAttr.copyWith(
                children: applyAttrs(nextAttr.children, path),
              );
            }
            return nextAttr;
          }(),
      ];
    }

    final updatedObj = targetObj.copyWith(
      attributes: applyAttrs(targetObj.attributes, ''),
    );
    if (updatedAttributesCount == 0) {
      return (
        project: project,
        injectedValuesCount: 0,
        updatedAttributesCount: 0,
      );
    }

    final modeSuffix = mode == ExampleInjectionMode.replace
        ? ' (remplacement)'
        : '';
    final note =
        '$injectedValuesCount exemple(s) injecté(s)$modeSuffix sur $updatedAttributesCount attribut(s) de ${updatedObj.technicalName} depuis ${story.code}';
    final updatedStory = story.copyWith(
      refinementNotes: story.refinementNotes.contains(note)
          ? story.refinementNotes
          : [...story.refinementNotes, note],
    );

    final nextProject = project.copyWith(
      businessObjects: [
        for (final obj in project.businessObjects)
          if (obj.id == updatedObj.id) updatedObj else obj,
      ],
      exampleMappings: [
        for (var i = 0; i < project.exampleMappings.length; i++)
          if (i == storyIndex) updatedStory else project.exampleMappings[i],
      ],
    );
    nextProject.validate();
    return (
      project: nextProject,
      injectedValuesCount: injectedValuesCount,
      updatedAttributesCount: updatedAttributesCount,
    );
  }

  static UseCaseSpec? _findMatchingUseCase(
    List<UseCaseSpec> useCases,
    BusinessObjectSpec obj,
  ) {
    final nameNeedle = obj.name.trim().toLowerCase();
    final techNeedle = obj.technicalName.trim().toLowerCase();
    for (final uc in useCases) {
      final hay =
          '${uc.title} ${uc.mainFlow.join(' ')} ${uc.postconditions.join(' ')}'
              .toLowerCase();
      if ((nameNeedle.isNotEmpty && hay.contains(nameNeedle)) ||
          (techNeedle.isNotEmpty && hay.contains(techNeedle))) {
        return uc;
      }
    }
    return null;
  }

  static List<FunctionalRequirement> _findMatchingRequirements(
    List<FunctionalRequirement> reqs,
    BusinessObjectSpec obj,
  ) {
    final nameNeedle = obj.name.trim().toLowerCase();
    final techNeedle = obj.technicalName.trim().toLowerCase();
    return [
      for (final req in reqs)
        if ((nameNeedle.isNotEmpty &&
                ('${req.title} ${req.description}'.toLowerCase().contains(
                  nameNeedle,
                ))) ||
            (techNeedle.isNotEmpty &&
                ('${req.title} ${req.description}'.toLowerCase().contains(
                  techNeedle,
                ))))
          req,
    ].take(3).toList();
  }

  static Object? _sampleValueForAttribute(BusinessAttribute attr) {
    if (attr.schemaConstraints.examples.isNotEmpty) {
      return attr.schemaConstraints.examples.first;
    }
    if (attr.defaultValue != null && attr.defaultValue!.trim().isNotEmpty) {
      return attr.defaultValue;
    }
    if (attr.enumValues.isNotEmpty) {
      return attr.enumValues.first;
    }
    return switch (attr.type) {
      BusinessAttributeType.integer =>
        attr.schemaConstraints.minimum?.round() ?? 1,
      BusinessAttributeType.number =>
        attr.schemaConstraints.minimum?.toDouble() ?? 10.0,
      BusinessAttributeType.boolean => true,
      BusinessAttributeType.date => '2026-05-19',
      BusinessAttributeType.datetime => '2026-05-19T10:00:00Z',
      BusinessAttributeType.email => 'contact@exemple.fr',
      BusinessAttributeType.url => 'https://exemple.fr',
      BusinessAttributeType.uuid => '550e8400-e29b-41d4-a716-446655440000',
      _ => 'exemple_${attr.name}',
    };
  }

  static String _formatExampleSummary(ExampleMapExample ex) {
    final parts = <String>[
      ex.title,
      if (ex.given.isNotEmpty) 'Étant donné ${ex.given}',
      if (ex.when.isNotEmpty) 'Quand ${ex.when}',
      if (ex.then.isNotEmpty) 'Alors ${ex.then}',
    ];
    return parts.join(' — ');
  }

  static String _shortId(String prefix) {
    final token = shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return '${prefix}_${token.isEmpty ? DateTime.now().microsecondsSinceEpoch : token}';
  }

  static bool _jsonListsEqual(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonValuesEqual(a[i], b[i])) return false;
    }
    return true;
  }

  static bool _jsonValuesEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonValuesEqual(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) return false;
        if (!_jsonValuesEqual(entry.value, b[entry.key])) return false;
      }
      return true;
    }
    return a == b;
  }
}

class _RawCandidateBucket {
  _RawCandidateBucket({required this.displayKey});

  final String displayKey;
  final List<({Object? value, List<String> sources})> items = [];

  void add(Object? value, String source) {
    for (final existing in items) {
      if (ExampleMappingOperations._jsonValuesEqual(existing.value, value)) {
        if (!existing.sources.contains(source)) {
          existing.sources.add(source);
        }
        return;
      }
    }
    items.add((value: value, sources: <String>[source]));
  }
}
