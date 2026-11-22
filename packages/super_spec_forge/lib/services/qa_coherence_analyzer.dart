/// Analyseur déterministe de couverture 360° et cohérence Métier+UX↔QA ([QaCoherenceAnalyzer]).
library;

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/company_glossary.dart';
import '../models/qa/gherkin_feature_spec.dart';
import '../models/qa/qa_coherence_issue.dart';
import '../models/qa/qa_forge_stage.dart';
import '../models/qa/tdd_suite_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_vision.dart';
import '../models/ux/ux_journey_spec.dart';
import '../models/ux/ux_screen_spec.dart';

/// Vérifie de manière déterministe la cohérence référentielle, la validité structurelle
/// Gherkin/TDD, la conformité terminologique et la couverture 360° Métier+UX↔QA d'un [SpecForgeProject].
abstract final class QaCoherenceAnalyzer {
  /// Exécute tous les contrôles statiques QA 360° sur [project] (et optionnellement
  /// contre [companyGlossary]) et retourne la liste immuable des diagnostics triés.
  static List<QaCoherenceIssue> analyze(
    SpecForgeProject project, {
    CompanyGlossary? companyGlossary,
  }) {
    final issues = <QaCoherenceIssue>[];
    final usedIssueIds = <String>{};

    void addIssue({
      required String id,
      required CoherenceSeverity severity,
      required QaForgeStage stage,
      required String code,
      required String title,
      required String description,
      String targetRef = '',
      String suggestion = '',
    }) {
      var candidateId = _sanitizeId(id);
      if (!usedIssueIds.add(candidateId)) {
        var suffix = 2;
        while (!usedIssueIds.add('${candidateId}_$suffix')) {
          suffix++;
        }
        candidateId = '${candidateId}_$suffix';
      }
      issues.add(
        QaCoherenceIssue(
          id: candidateId,
          severity: severity,
          stage: stage,
          code: code,
          title: title,
          description: description,
          targetRef: targetRef,
          suggestion: suggestion,
        ),
      );
    }

    final qa = project.qaSpec;
    final ux = project.uxSpec;

    // 1. COH-QA-FIX-001 : Couverture des objets métiers par les fixtures & validité des fixtures
    for (final obj in project.businessObjects) {
      final hasFixture = qa.fixtures.any(
        (f) =>
            f.businessObjectId.trim().isNotEmpty &&
            _matchesBusinessObject(obj, f.businessObjectId),
      );
      if (!hasFixture) {
        addIssue(
          id: 'qa_fix_uncovered_obj_${obj.id}',
          severity: CoherenceSeverity.warning,
          stage: QaForgeStage.testFixtures,
          code: 'COH-QA-FIX-001',
          title: 'Objet métier sans jeu d’essai (fixture) : ${obj.name}',
          description:
              'L’objet métier « ${obj.name} » (${obj.technicalName}) n’est couvert par aucune fixture QA (QaFixtureSpec.businessObjectId).',
          targetRef: obj.id,
          suggestion:
              'Ajoutez au moins une fixture nominale et un cas aux bornes ou invalide pour « ${obj.technicalName} ».',
        );
      }
    }

    for (final fixture in qa.fixtures) {
      final fixtureRef = fixture.code.trim().isNotEmpty
          ? fixture.code.trim()
          : fixture.id;

      if (fixture.businessObjectId.trim().isNotEmpty &&
          project.findBusinessObject(fixture.businessObjectId) == null) {
        addIssue(
          id: 'qa_fix_unknown_obj_${fixture.id}_${fixture.businessObjectId}',
          severity: CoherenceSeverity.error,
          stage: QaForgeStage.testFixtures,
          code: 'COH-QA-FIX-001',
          title: 'Objet métier inconnu sur $fixtureRef',
          description:
              'La fixture « ${fixture.name} » référence l’objet métier introuvable « ${fixture.businessObjectId} ».',
          targetRef: fixtureRef,
          suggestion:
              'Associez un identifiant ou nom technique de BusinessObjectSpec existant.',
        );
      }

      if (fixture.personaId.trim().isNotEmpty &&
          _resolvePersona(project, fixture.personaId) == null) {
        addIssue(
          id: 'qa_fix_unknown_persona_${fixture.id}_${fixture.personaId}',
          severity: CoherenceSeverity.error,
          stage: QaForgeStage.testFixtures,
          code: 'COH-QA-FIX-001',
          title: 'Persona inconnu sur $fixtureRef',
          description:
              'La fixture « ${fixture.name} » référence le persona « ${fixture.personaId} » absent du cadrage.',
          targetRef: fixtureRef,
          suggestion:
              'Associez un identifiant de persona défini à l’étape Cadrage ou videz personaId.',
        );
      }

      for (final ruleId in fixture.businessRuleIds) {
        if (ruleId.trim().isNotEmpty && _resolveRule(project, ruleId) == null) {
          addIssue(
            id: 'qa_fix_unknown_rule_${fixture.id}_$ruleId',
            severity: CoherenceSeverity.error,
            stage: QaForgeStage.testFixtures,
            code: 'COH-QA-FIX-001',
            title: 'Règle de gestion inconnue sur $fixtureRef',
            description:
                'La fixture « ${fixture.name} » référence la règle introuvable « $ruleId ».',
            targetRef: fixtureRef,
            suggestion:
                'Rattachez un code ou identifiant RG-xxx existant ou retirez la référence obsolète.',
          );
        }
      }

      final hasNonEmptyRuleIds = fixture.businessRuleIds.any(
        (r) => r.trim().isNotEmpty,
      );
      if (!fixture.expectedValid &&
          fixture.expectedErrorHint.trim().isEmpty &&
          !hasNonEmptyRuleIds) {
        addIssue(
          id: 'qa_fix_missing_error_hint_${fixture.id}',
          severity: CoherenceSeverity.warning,
          stage: QaForgeStage.testFixtures,
          code: 'COH-QA-FIX-001',
          title: 'Motif de rejet manquant sur la fixture invalide $fixtureRef',
          description:
              'La fixture négative « ${fixture.name} » (expectedValid = false) ne précise ni expectedErrorHint ni businessRuleIds.',
          targetRef: fixtureRef,
          suggestion:
              'Renseignez le message/code d’erreur attendu dans expectedErrorHint et/ou la règle RG-xxx violée.',
        );
      }
    }

    // 2. COH-QA-GHK-001 & COH-QA-GHK-002 : Structure, syntaxe et références Gherkin
    for (final feature in qa.features) {
      final featureRef = feature.code.trim().isNotEmpty
          ? feature.code.trim()
          : feature.id;

      if (feature.scenarios.isEmpty) {
        addIssue(
          id: 'qa_ghk_empty_feature_${feature.id}',
          severity: CoherenceSeverity.warning,
          stage: QaForgeStage.gherkinFeatures,
          code: 'COH-QA-GHK-001',
          title: 'Feature Gherkin sans scénario : $featureRef',
          description:
              'La fonctionnalité « ${feature.title} » ($featureRef) ne contient aucun scénario exécutable.',
          targetRef: featureRef,
          suggestion:
              'Ajoutez au moins un Scénario nominal et des cas alternatifs ou d’erreur dans $featureRef.',
        );
      }

      if (feature.moduleId.trim().isNotEmpty &&
          _resolveModule(project, feature.moduleId) == null) {
        addIssue(
          id: 'qa_ghk_unknown_module_${feature.id}_${feature.moduleId}',
          severity: CoherenceSeverity.error,
          stage: QaForgeStage.gherkinFeatures,
          code: 'COH-QA-GHK-002',
          title: 'Module inconnu sur la feature $featureRef',
          description:
              'La feature « ${feature.title} » référence le module introuvable « ${feature.moduleId} ».',
          targetRef: featureRef,
          suggestion:
              'Rattachez un module existant du cahier des charges ou videz moduleId.',
        );
      }

      if (feature.personaId.trim().isNotEmpty &&
          _resolvePersona(project, feature.personaId) == null) {
        addIssue(
          id: 'qa_ghk_unknown_persona_${feature.id}_${feature.personaId}',
          severity: CoherenceSeverity.error,
          stage: QaForgeStage.gherkinFeatures,
          code: 'COH-QA-GHK-002',
          title: 'Persona inconnu sur la feature $featureRef',
          description:
              'La feature « ${feature.title} » référence le persona « ${feature.personaId} » absent du cadrage.',
          targetRef: featureRef,
          suggestion:
              'Associez un persona existant du cadrage ou laissez personaId vide.',
        );
      }

      for (final scenario in feature.scenarios) {
        final scenarioRef =
            scenario.code.trim().isNotEmpty &&
                scenario.code.trim().toUpperCase() != 'SCN'
            ? scenario.code.trim()
            : '${feature.id}.${scenario.id}';

        if (scenario.steps.isEmpty) {
          addIssue(
            id: 'qa_ghk_empty_steps_${feature.id}_${scenario.id}',
            severity: CoherenceSeverity.error,
            stage: QaForgeStage.gherkinFeatures,
            code: 'COH-QA-GHK-001',
            title: 'Scénario Gherkin sans étape : « ${scenario.title} »',
            description:
                'Le scénario « ${scenario.title} » ($scenarioRef) de la feature « ${feature.title} » ne comporte aucune étape Given / When / Then.',
            targetRef: scenarioRef,
            suggestion:
                'Rédigez au minimum une précondition (Given), une action (When) et une vérification (Then).',
          );
        } else {
          final hasThen = scenario.steps.any(
            (s) => s.keyword == GherkinStepKeyword.then,
          );
          if (!hasThen) {
            addIssue(
              id: 'qa_ghk_missing_then_${feature.id}_${scenario.id}',
              severity: CoherenceSeverity.warning,
              stage: QaForgeStage.gherkinFeatures,
              code: 'COH-QA-GHK-001',
              title:
                  'Assertion Alors/Then manquante dans « ${scenario.title} »',
              description:
                  'Le scénario « ${scenario.title} » ($scenarioRef) ne possède aucune étape de vérification (GherkinStepKeyword.then).',
              targetRef: scenarioRef,
              suggestion:
                  'Ajoutez au moins une étape Alors / Then décrivant le résultat observable attendu.',
            );
          }
        }

        if (scenario.isOutline) {
          if (scenario.examples.rows.isEmpty) {
            addIssue(
              id: 'qa_ghk_outline_empty_rows_${feature.id}_${scenario.id}',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.gherkinFeatures,
              code: 'COH-QA-GHK-001',
              title:
                  'Table d’exemples vide sur le Plan du Scénario « ${scenario.title} »',
              description:
                  'Le Plan du Scénario « ${scenario.title} » ($scenarioRef) a isOutline = true mais sa table Exemples ne contient aucune ligne.',
              targetRef: scenarioRef,
              suggestion:
                  'Ajoutez des colonnes et au moins une ligne de données dans examples, ou désactivez isOutline.',
            );
          }

          final referencedVars = scenario.referencedOutlineVariables;
          final headerList = [
            for (final h in scenario.examples.headers)
              if (h.trim().isNotEmpty) h.trim(),
          ];
          final headerSet = headerList.toSet();

          final unresolvedVars = [
            for (final v in referencedVars)
              if (!headerSet.contains(v)) v,
          ];
          if (unresolvedVars.isNotEmpty) {
            addIssue(
              id: 'qa_ghk_outline_unresolved_${feature.id}_${scenario.id}',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.gherkinFeatures,
              code: 'COH-QA-GHK-001',
              title:
                  'Variables <var> non résolues dans « ${scenario.title} »',
              description:
                  'Le Plan du Scénario « ${scenario.title} » ($scenarioRef) utilise ${unresolvedVars.map((v) => '<$v>').join(', ')} absent(s) des en-têtes Exemples (${headerList.isEmpty ? 'aucun' : headerList.join(', ')}).',
              targetRef: scenarioRef,
              suggestion:
                  'Ajoutez les colonnes manquantes dans examples.headers ou corrigez l’orthographe des paramètres <var>.',
            );
          }

          final unusedHeaders = [
            for (final h in headerList)
              if (!referencedVars.contains(h)) h,
          ];
          if (unusedHeaders.isNotEmpty) {
            addIssue(
              id: 'qa_ghk_outline_unused_col_${feature.id}_${scenario.id}',
              severity: CoherenceSeverity.warning,
              stage: QaForgeStage.gherkinFeatures,
              code: 'COH-QA-GHK-001',
              title:
                  'Colonnes Exemples non référencées dans « ${scenario.title} »',
              description:
                  'La table Exemples du scénario « ${scenario.title} » ($scenarioRef) déclare les colonnes non utilisées : ${unusedHeaders.join(', ')}.',
              targetRef: scenarioRef,
              suggestion:
                  'Référencez chaque colonne sous la forme <colonne> dans les étapes ou retirez les colonnes superflues.',
            );
          }
        }

        // Références croisées du scénario (COH-QA-GHK-002)
        for (final reqId in scenario.requirementIds) {
          if (reqId.trim().isNotEmpty &&
              !_projectHasRequirement(project, reqId)) {
            addIssue(
              id: 'qa_ghk_unknown_req_${feature.id}_${scenario.id}_$reqId',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.gherkinFeatures,
              code: 'COH-QA-GHK-002',
              title: 'Exigence inconnue sur « ${scenario.title} » ($reqId)',
              description:
                  'Le scénario « ${scenario.title} » ($scenarioRef) référence l’exigence introuvable « $reqId ».',
              targetRef: scenarioRef,
              suggestion:
                  'Associez un code ou identifiant EXF-xxx / ENF-xxx existant du cahier des charges.',
            );
          }
        }

        for (final ucId in scenario.useCaseIds) {
          if (ucId.trim().isNotEmpty &&
              _resolveUseCase(project, ucId) == null) {
            addIssue(
              id: 'qa_ghk_unknown_uc_${feature.id}_${scenario.id}_$ucId',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.gherkinFeatures,
              code: 'COH-QA-GHK-002',
              title: 'Cas d’usage inconnu sur « ${scenario.title} » ($ucId)',
              description:
                  'Le scénario « ${scenario.title} » ($scenarioRef) référence le cas d’usage introuvable « $ucId ».',
              targetRef: scenarioRef,
              suggestion:
                  'Reliez un cas d’usage existant du cahier des charges ou retirez cette référence.',
            );
          }
        }

        for (final ruleId in scenario.businessRuleIds) {
          if (ruleId.trim().isNotEmpty &&
              _resolveRule(project, ruleId) == null) {
            addIssue(
              id: 'qa_ghk_unknown_rule_${feature.id}_${scenario.id}_$ruleId',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.gherkinFeatures,
              code: 'COH-QA-GHK-002',
              title:
                  'Règle de gestion inconnue sur « ${scenario.title} » ($ruleId)',
              description:
                  'Le scénario « ${scenario.title} » ($scenarioRef) référence la règle introuvable « $ruleId ».',
              targetRef: scenarioRef,
              suggestion:
                  'Associez un code ou identifiant RG-xxx défini dans les règles de gestion.',
            );
          }
        }

        for (final journeyId in scenario.journeyIds) {
          if (journeyId.trim().isNotEmpty &&
              ux.findJourney(journeyId) == null) {
            addIssue(
              id: 'qa_ghk_unknown_jrn_${feature.id}_${scenario.id}_$journeyId',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.gherkinFeatures,
              code: 'COH-QA-GHK-002',
              title:
                  'Parcours UX inconnu sur « ${scenario.title} » ($journeyId)',
              description:
                  'Le scénario « ${scenario.title} » ($scenarioRef) référence le parcours UX introuvable « $journeyId ».',
              targetRef: scenarioRef,
              suggestion:
                  'Associez un identifiant ou code JRN-xxx existant dans le volet UX.',
            );
          }
        }

        for (final screenId in scenario.screenIds) {
          if (screenId.trim().isNotEmpty && ux.findScreen(screenId) == null) {
            addIssue(
              id: 'qa_ghk_unknown_scr_${feature.id}_${scenario.id}_$screenId',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.gherkinFeatures,
              code: 'COH-QA-GHK-002',
              title: 'Écran UX inconnu sur « ${scenario.title} » ($screenId)',
              description:
                  'Le scénario « ${scenario.title} » ($scenarioRef) référence l’écran UX introuvable « $screenId ».',
              targetRef: scenarioRef,
              suggestion:
                  'Associez un identifiant ou code SCR-xxx existant dans le volet UX.',
            );
          }
        }

        for (final fixtureId in scenario.fixtureIds) {
          if (fixtureId.trim().isNotEmpty &&
              qa.findFixture(fixtureId) == null) {
            addIssue(
              id: 'qa_ghk_unknown_fix_${feature.id}_${scenario.id}_$fixtureId',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.gherkinFeatures,
              code: 'COH-QA-GHK-002',
              title: 'Fixture QA inconnue sur « ${scenario.title} » ($fixtureId)',
              description:
                  'Le scénario « ${scenario.title} » ($scenarioRef) référence la fixture introuvable « $fixtureId ».',
              targetRef: scenarioRef,
              suggestion:
                  'Créez la fixture correspondante à l’étape Jeux d’essais ou corrigez fixtureIds.',
            );
          }
        }
      }
    }

    // 3. COH-QA-TDD-001 : Structure et références des suites et cas TDD
    for (final suite in qa.tddSuites) {
      final suiteRef = suite.code.trim().isNotEmpty
          ? suite.code.trim()
          : suite.id;

      if (suite.cases.isEmpty) {
        addIssue(
          id: 'qa_tdd_empty_suite_${suite.id}',
          severity: CoherenceSeverity.warning,
          stage: QaForgeStage.tddSuites,
          code: 'COH-QA-TDD-001',
          title: 'Suite TDD sans cas de test : $suiteRef',
          description:
              'La suite TDD « ${suite.name} » ($suiteRef) ne contient aucun cas unitaire Arrange / Act / Assert.',
          targetRef: suiteRef,
          suggestion:
              'Ajoutez des cas de tests atomiques ordonnés (Red → Green → Refactor) dans « ${suite.name} ».',
        );
      }

      if (suite.targetObjectId.trim().isNotEmpty &&
          project.findBusinessObject(suite.targetObjectId) == null) {
        addIssue(
          id: 'qa_tdd_unknown_obj_${suite.id}_${suite.targetObjectId}',
          severity: CoherenceSeverity.error,
          stage: QaForgeStage.tddSuites,
          code: 'COH-QA-TDD-001',
          title: 'Objet cible inconnu sur la suite $suiteRef',
          description:
              'La suite TDD « ${suite.name} » référence l’objet métier introuvable « ${suite.targetObjectId} ».',
          targetRef: suiteRef,
          suggestion:
              'Associez un BusinessObjectSpec existant ou laissez targetObjectId vide.',
        );
      }

      if (suite.moduleId.trim().isNotEmpty &&
          _resolveModule(project, suite.moduleId) == null) {
        addIssue(
          id: 'qa_tdd_unknown_mod_${suite.id}_${suite.moduleId}',
          severity: CoherenceSeverity.error,
          stage: QaForgeStage.tddSuites,
          code: 'COH-QA-TDD-001',
          title: 'Module inconnu sur la suite $suiteRef',
          description:
              'La suite TDD « ${suite.name} » référence le module introuvable « ${suite.moduleId} ».',
          targetRef: suiteRef,
          suggestion:
              'Rattachez un module existant du cahier des charges ou laissez moduleId vide.',
        );
      }

      for (final testCase in suite.cases) {
        final caseRef =
            testCase.code.trim().isNotEmpty &&
                testCase.code.trim().toUpperCase() != 'TC'
            ? '$suiteRef.${testCase.code.trim()}'
            : '${suite.id}.${testCase.id}';

        if (testCase.act.trim().isEmpty) {
          addIssue(
            id: 'qa_tdd_empty_act_${suite.id}_${testCase.id}',
            severity: CoherenceSeverity.error,
            stage: QaForgeStage.tddSuites,
            code: 'COH-QA-TDD-001',
            title: 'Action Act manquante sur « ${testCase.title} » ($suiteRef)',
            description:
                'Le cas TDD « ${testCase.title} » ($caseRef) ne définit aucune opération déclenchée dans le champ act.',
            targetRef: caseRef,
            suggestion:
                'Précisez l’appel de méthode, commande ou événement testé dans act.',
          );
        }

        final hasAssert = testCase.assertExpected.trim().isNotEmpty;
        final hasErrorMsg = testCase.expectedErrorMessage.trim().isNotEmpty;
        if (!hasAssert && !hasErrorMsg) {
          final isReject =
              testCase.outcomeKind == TddExpectedOutcomeKind.rejectsWithError;
          addIssue(
            id: 'qa_tdd_empty_assert_${suite.id}_${testCase.id}',
            severity: CoherenceSeverity.error,
            stage: QaForgeStage.tddSuites,
            code: 'COH-QA-TDD-001',
            title: isReject
                ? 'Erreur attendue manquante sur « ${testCase.title} » ($suiteRef)'
                : 'Assertion Assert manquante sur « ${testCase.title} » ($suiteRef)',
            description: isReject
                ? 'Le cas TDD de rejet « ${testCase.title} » ($caseRef) a outcomeKind = rejectsWithError mais ni expectedErrorMessage ni assertExpected n’est renseigné.'
                : 'Le cas TDD « ${testCase.title} » ($caseRef) ne définit ni assertExpected ni expectedErrorMessage.',
            targetRef: caseRef,
            suggestion: isReject
                ? 'Précisez le message ou type d’erreur attendu dans expectedErrorMessage (et/ou l’invariant vérifié dans assertExpected).'
                : 'Décrivez la valeur de retour, la mutation d’état ou l’erreur attendue dans assertExpected / expectedErrorMessage.',
          );
        }

        if (testCase.fixtureId.trim().isNotEmpty &&
            qa.findFixture(testCase.fixtureId) == null) {
          addIssue(
            id: 'qa_tdd_unknown_fix_${suite.id}_${testCase.id}_${testCase.fixtureId}',
            severity: CoherenceSeverity.error,
            stage: QaForgeStage.tddSuites,
            code: 'COH-QA-TDD-001',
            title:
                'Fixture QA inconnue sur « ${testCase.title} » (${testCase.fixtureId})',
            description:
                'Le cas TDD « ${testCase.title} » ($caseRef) référence la fixture introuvable « ${testCase.fixtureId} ».',
            targetRef: caseRef,
            suggestion:
                'Associez un identifiant ou code FIX-xxx existant ou videz fixtureId.',
          );
        }

        for (final ruleId in testCase.businessRuleIds) {
          if (ruleId.trim().isNotEmpty &&
              _resolveRule(project, ruleId) == null) {
            addIssue(
              id: 'qa_tdd_unknown_rule_${suite.id}_${testCase.id}_$ruleId',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.tddSuites,
              code: 'COH-QA-TDD-001',
              title:
                  'Règle de gestion inconnue sur « ${testCase.title} » ($ruleId)',
              description:
                  'Le cas TDD « ${testCase.title} » ($caseRef) référence la règle introuvable « $ruleId ».',
              targetRef: caseRef,
              suggestion:
                  'Associez un code ou identifiant RG-xxx existant dans les règles de gestion.',
            );
          }
        }

        for (final reqId in testCase.requirementIds) {
          if (reqId.trim().isNotEmpty &&
              !_projectHasRequirement(project, reqId)) {
            addIssue(
              id: 'qa_tdd_unknown_req_${suite.id}_${testCase.id}_$reqId',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.tddSuites,
              code: 'COH-QA-TDD-001',
              title: 'Exigence inconnue sur « ${testCase.title} » ($reqId)',
              description:
                  'Le cas TDD « ${testCase.title} » ($caseRef) référence l’exigence introuvable « $reqId ».',
              targetRef: caseRef,
              suggestion:
                  'Associez un code ou identifiant EXF-xxx / ENF-xxx valide.',
            );
          }
        }

        for (final screenId in testCase.screenIds) {
          if (screenId.trim().isNotEmpty && ux.findScreen(screenId) == null) {
            addIssue(
              id: 'qa_tdd_unknown_scr_${suite.id}_${testCase.id}_$screenId',
              severity: CoherenceSeverity.error,
              stage: QaForgeStage.tddSuites,
              code: 'COH-QA-TDD-001',
              title: 'Écran UX inconnu sur « ${testCase.title} » ($screenId)',
              description:
                  'Le cas TDD « ${testCase.title} » ($caseRef) référence l’écran UX introuvable « $screenId ».',
              targetRef: caseRef,
              suggestion:
                  'Associez un identifiant ou code SCR-xxx défini dans le volet UX.',
            );
          }
        }
      }
    }

    // 4. COH-QA-COV-001 : Couverture 360° Métier + UX par Gherkin et/ou TDD
    for (final req in project.cahierDesCharges.functionalRequirements) {
      if (req.priority != RequirementPriority.must &&
          req.priority != RequirementPriority.should) {
        continue;
      }
      final coveredByGherkin = qa.features.any(
        (f) => f.scenarios.any(
          (sc) => sc.requirementIds.any((ref) => _matchesRequirement(req, ref)),
        ),
      );
      final coveredByTdd = qa.tddSuites.any(
        (s) => s.cases.any(
          (c) => c.requirementIds.any((ref) => _matchesRequirement(req, ref)),
        ),
      );
      if (!coveredByGherkin && !coveredByTdd) {
        final reqRef = req.code.trim().isNotEmpty ? req.code.trim() : req.id;
        addIssue(
          id: 'qa_cov_req_${req.id}',
          severity: CoherenceSeverity.warning,
          stage: QaForgeStage.qaReviewExport,
          code: 'COH-QA-COV-001',
          title:
              'Exigence ${req.priority.code} non couverte par les tests : $reqRef',
          description:
              'L’exigence fonctionnelle « ${req.title} » ($reqRef, priorité ${req.priority.code}) n’est rattachée à aucun scénario Gherkin ni cas TDD.',
          targetRef: reqRef,
          suggestion:
              'Ajoutez au moins un scénario Gherkin ou un cas unitaire TDD référençant $reqRef.',
        );
      }
    }

    for (final uc in project.cahierDesCharges.useCases) {
      final coveredByGherkin = qa.features.any(
        (f) => f.scenarios.any(
          (sc) => sc.useCaseIds.any((ref) => _matchesUseCase(uc, ref)),
        ),
      );
      if (!coveredByGherkin) {
        addIssue(
          id: 'qa_cov_uc_${uc.id}',
          severity: CoherenceSeverity.warning,
          stage: QaForgeStage.qaReviewExport,
          code: 'COH-QA-COV-001',
          title: 'Cas d’usage sans scénario Gherkin : ${uc.title}',
          description:
              'Le cas d’usage « ${uc.title} » (${uc.id}) n’est couvert par aucun scénario Gherkin (GherkinScenarioSpec.useCaseIds).',
          targetRef: uc.id,
          suggestion:
              'Créez un scénario d’acceptation BDD vérifiant le flux nominal de « ${uc.title} ».',
        );
      }
    }

    for (final rule in project.businessRules) {
      if (!rule.active) continue;
      final coveredByGherkin = qa.features.any(
        (f) => f.scenarios.any(
          (sc) => sc.businessRuleIds.any((ref) => _matchesRule(rule, ref)),
        ),
      );
      final coveredByTdd = qa.tddSuites.any(
        (s) => s.cases.any(
          (c) => c.businessRuleIds.any((ref) => _matchesRule(rule, ref)),
        ),
      );
      if (!coveredByGherkin && !coveredByTdd) {
        final ruleRef = rule.code.trim().isNotEmpty
            ? rule.code.trim()
            : rule.id;
        addIssue(
          id: 'qa_cov_rule_${rule.id}',
          severity: CoherenceSeverity.warning,
          stage: QaForgeStage.qaReviewExport,
          code: 'COH-QA-COV-001',
          title: 'Règle de gestion active non testée : $ruleRef',
          description:
              'La règle active « ${rule.title} » ($ruleRef) n’est couverte par aucun scénario Gherkin ni cas de test TDD.',
          targetRef: ruleRef,
          suggestion:
              'Ajoutez des cas unitaires TDD (nominal + rejet) et/ou un scénario Gherkin référençant $ruleRef.',
        );
      }
    }

    if (ux.journeys.isNotEmpty) {
      for (final journey in ux.journeys) {
        final coveredByGherkin = qa.features.any(
          (f) => f.scenarios.any(
            (sc) => sc.journeyIds.any((ref) => _matchesJourney(journey, ref)),
          ),
        );
        if (!coveredByGherkin) {
          final journeyRef = journey.code.trim().isNotEmpty
              ? journey.code.trim()
              : journey.id;
          addIssue(
            id: 'qa_cov_jrn_${journey.id}',
            severity: CoherenceSeverity.warning,
            stage: QaForgeStage.qaReviewExport,
            code: 'COH-QA-COV-001',
            title: 'Parcours UX non couvert en Gherkin : $journeyRef',
            description:
                'Le parcours utilisateur « ${journey.name} » ($journeyRef) n’est référencé par aucun scénario d’acceptation Gherkin.',
            targetRef: journeyRef,
            suggestion:
                'Reliez $journeyRef à un scénario Gherkin bout-en-bout couvrant ses étapes clés.',
          );
        }
      }
    }

    if (ux.screens.isNotEmpty) {
      for (final screen in ux.screens) {
        final coveredByGherkin = qa.features.any(
          (f) => f.scenarios.any(
            (sc) => sc.screenIds.any((ref) => _matchesScreen(screen, ref)),
          ),
        );
        final coveredByTdd = qa.tddSuites.any(
          (s) => s.cases.any(
            (c) => c.screenIds.any((ref) => _matchesScreen(screen, ref)),
          ),
        );
        if (!coveredByGherkin && !coveredByTdd) {
          final screenRef = screen.code.trim().isNotEmpty
              ? screen.code.trim()
              : screen.id;
          addIssue(
            id: 'qa_cov_scr_${screen.id}',
            severity: CoherenceSeverity.warning,
            stage: QaForgeStage.qaReviewExport,
            code: 'COH-QA-COV-001',
            title: 'Écran UX non couvert par les tests : $screenRef',
            description:
                'L’écran « ${screen.name} » ($screenRef) n’est rattaché à aucun scénario Gherkin ni cas de test TDD.',
            targetRef: screenRef,
            suggestion:
                'Associez $screenRef aux scénarios BDD ou aux cas TDD de comportement IHM correspondants.',
          );
        }
      }
    }

    // 5. COH-QA-LEX-001 : Termes proscrits ou dépréciés du glossaire d'entreprise
    if (companyGlossary != null && companyGlossary.terms.isNotEmpty) {
      final rules = _buildGlossaryRules(companyGlossary);
      if (rules.isNotEmpty) {
        void checkText({
          required String idPrefix,
          required QaForgeStage stage,
          required String targetRef,
          required String contextLabel,
          required String text,
        }) {
          final trimmed = text.trim();
          if (trimmed.isEmpty) return;
          for (final rule in rules) {
            if (rule.pattern.hasMatch(trimmed)) {
              addIssue(
                id: '${idPrefix}_${rule.matchedTerm}',
                severity: CoherenceSeverity.warning,
                stage: stage,
                code: 'COH-QA-LEX-001',
                title: rule.isDeprecated
                    ? 'Terme déprécié « ${rule.matchedTerm} » dans $contextLabel'
                    : 'Terme proscrit « ${rule.matchedTerm} » dans $contextLabel',
                description: rule.isDeprecated
                    ? '$contextLabel (« $trimmed ») emploie le terme d’entreprise déprécié « ${rule.matchedTerm} ».'
                    : '$contextLabel (« $trimmed ») emploie le terme proscrit « ${rule.matchedTerm} » au lieu du terme officiel « ${rule.canonicalTerm.term} ».',
                targetRef: targetRef,
                suggestion: rule.isDeprecated
                    ? 'Remplacez « ${rule.matchedTerm} » par un terme validé du glossaire d’entreprise.'
                    : 'Utilisez le terme canonique « ${rule.canonicalTerm.term} » dans vos spécifications Gherkin et TDD.',
              );
            }
          }
        }

        for (final feature in qa.features) {
          final featureRef = feature.code.trim().isNotEmpty
              ? feature.code.trim()
              : feature.id;
          checkText(
            idPrefix: 'qa_lex_feat_${feature.id}',
            stage: QaForgeStage.gherkinFeatures,
            targetRef: featureRef,
            contextLabel: 'La feature $featureRef',
            text: feature.title,
          );
          for (final step in feature.backgroundSteps) {
            checkText(
              idPrefix: 'qa_lex_bg_${feature.id}_${step.id}',
              stage: QaForgeStage.gherkinFeatures,
              targetRef: '${feature.id}.${step.id}',
              contextLabel: 'Le contexte de $featureRef',
              text: step.text,
            );
          }
          for (final scenario in feature.scenarios) {
            final scenarioRef =
                scenario.code.trim().isNotEmpty &&
                    scenario.code.trim().toUpperCase() != 'SCN'
                ? scenario.code.trim()
                : '${feature.id}.${scenario.id}';
            checkText(
              idPrefix: 'qa_lex_scn_${feature.id}_${scenario.id}',
              stage: QaForgeStage.gherkinFeatures,
              targetRef: scenarioRef,
              contextLabel: 'Le scénario $scenarioRef',
              text: scenario.title,
            );
            for (final step in scenario.steps) {
              checkText(
                idPrefix:
                    'qa_lex_step_${feature.id}_${scenario.id}_${step.id}',
                stage: QaForgeStage.gherkinFeatures,
                targetRef: '${scenario.id}.${step.id}',
                contextLabel: 'L’étape Gherkin de $scenarioRef',
                text: step.text,
              );
            }
          }
        }

        for (final suite in qa.tddSuites) {
          final suiteRef = suite.code.trim().isNotEmpty
              ? suite.code.trim()
              : suite.id;
          checkText(
            idPrefix: 'qa_lex_tdd_${suite.id}',
            stage: QaForgeStage.tddSuites,
            targetRef: suiteRef,
            contextLabel: 'La suite TDD $suiteRef',
            text: suite.name,
          );
          for (final testCase in suite.cases) {
            final caseRef =
                testCase.code.trim().isNotEmpty &&
                    testCase.code.trim().toUpperCase() != 'TC'
                ? '$suiteRef.${testCase.code.trim()}'
                : '${suite.id}.${testCase.id}';
            checkText(
              idPrefix: 'qa_lex_tc_${suite.id}_${testCase.id}',
              stage: QaForgeStage.tddSuites,
              targetRef: caseRef,
              contextLabel: 'Le cas TDD $caseRef',
              text: testCase.title,
            );
          }
        }
      }
    }

    issues.sort((a, b) {
      final bySeverity = a.severity.index.compareTo(b.severity.index);
      if (bySeverity != 0) return bySeverity;
      final byStage = a.stage.index.compareTo(b.stage.index);
      if (byStage != 0) return byStage;
      final byCode = a.code.compareTo(b.code);
      if (byCode != 0) return byCode;
      return a.id.compareTo(b.id);
    });
    return List<QaCoherenceIssue>.unmodifiable(issues);
  }

  static SpecPersona? _resolvePersona(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final persona in project.vision.personas) {
      if (persona.id.toLowerCase() == needle ||
          persona.name.toLowerCase() == needle) {
        return persona;
      }
    }
    return null;
  }

  static SpecModule? _resolveModule(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final module in project.cahierDesCharges.modules) {
      if (module.id.toLowerCase() == needle ||
          module.name.toLowerCase() == needle) {
        return module;
      }
    }
    return null;
  }

  static UseCaseSpec? _resolveUseCase(SpecForgeProject project, String ref) {
    for (final uc in project.cahierDesCharges.useCases) {
      if (_matchesUseCase(uc, ref)) return uc;
    }
    return null;
  }

  static bool _matchesUseCase(UseCaseSpec uc, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return uc.id.toLowerCase() == needle || uc.title.toLowerCase() == needle;
  }

  static bool _projectHasRequirement(SpecForgeProject project, String ref) {
    for (final req in project.cahierDesCharges.functionalRequirements) {
      if (_matchesRequirement(req, ref)) return true;
    }
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    for (final enf in project.cahierDesCharges.nonFunctionalRequirements) {
      if (enf.id.toLowerCase() == needle ||
          (enf.code.trim().isNotEmpty &&
              enf.code.trim().toLowerCase() == needle)) {
        return true;
      }
    }
    return false;
  }

  static bool _matchesRequirement(FunctionalRequirement req, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return req.id.toLowerCase() == needle ||
        (req.code.trim().isNotEmpty && req.code.trim().toLowerCase() == needle);
  }

  static BusinessRuleSpec? _resolveRule(SpecForgeProject project, String ref) {
    for (final rule in project.businessRules) {
      if (_matchesRule(rule, ref)) return rule;
    }
    return null;
  }

  static bool _matchesRule(BusinessRuleSpec rule, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return rule.id.toLowerCase() == needle ||
        (rule.code.trim().isNotEmpty &&
            rule.code.trim().toLowerCase() == needle);
  }

  static bool _matchesBusinessObject(BusinessObjectSpec obj, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return obj.id.toLowerCase() == needle ||
        obj.technicalName.toLowerCase() == needle ||
        obj.name.toLowerCase() == needle;
  }

  static bool _matchesJourney(UxJourneySpec journey, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return journey.id.toLowerCase() == needle ||
        (journey.code.trim().isNotEmpty &&
            journey.code.trim().toLowerCase() == needle) ||
        journey.name.toLowerCase() == needle;
  }

  static bool _matchesScreen(UxScreenSpec screen, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return screen.id.toLowerCase() == needle ||
        (screen.code.trim().isNotEmpty &&
            screen.code.trim().toLowerCase() == needle) ||
        (screen.routeId.trim().isNotEmpty &&
            screen.routeId.trim().toLowerCase() == needle) ||
        screen.name.toLowerCase() == needle;
  }

  static List<_GlossaryLexRule> _buildGlossaryRules(CompanyGlossary glossary) {
    final rules = <_GlossaryLexRule>[];
    final seenKeys = <String>{};

    void register({
      required String rawPhrase,
      required CompanyGlossaryTerm canonical,
      required bool isDeprecated,
    }) {
      final trimmed = rawPhrase.trim();
      if (trimmed.isEmpty) return;
      final normKey =
          '${isDeprecated ? 'dep' : 'forb'}:${trimmed.toLowerCase()}';
      if (!seenKeys.add(normKey)) return;
      final tokens = trimmed
          .split(RegExp(r'\s+'))
          .map(RegExp.escape)
          .join(r'\s+');
      final pattern = RegExp(
        '(?<![A-Za-zÀ-ÖØ-öø-ÿ0-9])$tokens(?:s|x)?(?![A-Za-zÀ-ÖØ-öø-ÿ0-9])',
        caseSensitive: false,
      );
      rules.add(
        _GlossaryLexRule(
          matchedTerm: trimmed,
          canonicalTerm: canonical,
          isDeprecated: isDeprecated,
          pattern: pattern,
        ),
      );
    }

    for (final term in glossary.terms) {
      if (term.status == CompanyGlossaryStatus.deprecated) {
        register(rawPhrase: term.term, canonical: term, isDeprecated: true);
      }
      for (final forbidden in term.forbiddenTerms) {
        register(rawPhrase: forbidden, canonical: term, isDeprecated: false);
      }
    }
    return rules;
  }

  static String _sanitizeId(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'qa_coh_issue' : cleaned;
  }
}

class _GlossaryLexRule {
  const _GlossaryLexRule({
    required this.matchedTerm,
    required this.canonicalTerm,
    required this.isDeprecated,
    required this.pattern,
  });

  final String matchedTerm;
  final CompanyGlossaryTerm canonicalTerm;
  final bool isDeprecated;
  final RegExp pattern;
}
