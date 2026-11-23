/// Opérations métier pures pour l'Example Mapping ([ExampleMappingOperations]) :
/// initialisation depuis les objets métiers & cas d'usage, promotion d'une carte
/// bleue en règle `RG-xxx` et enrichissement des exemples JSON Schema d'un objet métier.
library;

import 'package:shortid/shortid.dart';

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/example_mapping_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_forge_project.dart';

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
}
