/// Exportateur du cahier de recette BDD/Gherkin et de la stratégie TDD au format Markdown ([QaMarkdownExporter]).
library;

import 'dart:convert';

import '../../models/business_object_spec.dart';
import '../../models/business_rule_spec.dart';
import '../../models/qa/gherkin_feature_spec.dart';
import '../../models/qa/qa_coherence_issue.dart';
import '../../models/qa/qa_fixture_spec.dart';
import '../../models/qa/tdd_suite_spec.dart';
import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_coherence_issue.dart';
import '../../models/spec_forge_project.dart';
import '../../models/ux/ux_journey_spec.dart';
import '../../models/ux/ux_screen_spec.dart';
import '../qa_coherence_analyzer.dart';
import '../spec_storage_slug.dart';
import 'gherkin_feature_exporter.dart';

/// Génère un cahier de recette Markdown structuré en français réunissant
/// les métriques de couverture 360°, les fixtures JSON, les features Gherkin,
/// les suites TDD `Arrange / Act / Assert` et la matrice de traçabilité complète.
abstract final class QaMarkdownExporter {
  static const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

  /// Exporte l'ensemble du volet QA BDD/TDD de [project] au format Markdown complet.
  static String export(SpecForgeProject project) {
    final buf = StringBuffer()
      ..writeln('# Cahier de Recette BDD / Gherkin & Stratégie TDD — ${project.name}')
      ..writeln()
      ..writeln('> Généré par **SuperSpecForge**')
      ..writeln(
        '> Dernière mise à jour : `${project.updatedAt.toIso8601String()}`',
      )
      ..writeln();

    _writeSynthesisAndMetrics(buf, project);
    _writeFixturesSection(buf, project);
    _writeGherkinSection(buf, project);
    _writeTddSection(buf, project);
    _writeTraceabilityMatrix(buf, project);

    return SpecStorageIo.normalizeLf(buf.toString());
  }

  static void _writeSynthesisAndMetrics(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final qa = project.qaSpec;
    final ux = project.uxSpec;

    final nominalFixtures = qa.fixtures
        .where((f) => f.kind == QaFixtureKind.nominal)
        .length;
    final boundaryFixtures = qa.fixtures
        .where((f) => f.kind == QaFixtureKind.boundary)
        .length;
    final invalidFixtures = qa.fixtures
        .where((f) => f.kind == QaFixtureKind.invalid || !f.expectedValid)
        .length;
    final outlineCount = qa.features.fold<int>(
      0,
      (sum, f) => sum + f.scenarios.where((sc) => sc.isOutline).length,
    );

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 1. Synthèse & Métriques de couverture')
      ..writeln()
      ..writeln('### 1.1 Volumétrie QA')
      ..writeln()
      ..writeln(
        '- **Étape QA courante** : ${qa.currentStage.title} (`${qa.currentStage.name}`)',
      )
      ..writeln(
        '- **Langue Gherkin** : ${qa.gherkinLanguage.label} (`${qa.gherkinLanguage.gherkinHeader}`)',
      )
      ..writeln(
        '- **Jeux de données (`FIX-xxx`)** : ${qa.fixtures.length} _(nominaux : $nominalFixtures, bornes : $boundaryFixtures, cas d’erreur/invalides : $invalidFixtures)_',
      )
      ..writeln(
        '- **Spécifications Gherkin (`FEAT-xxx`)** : ${qa.features.length} fonctionnalité(s) · ${qa.totalScenarioCount} scénario(s) _(dont $outlineCount Plan(s) de Scénario)_',
      )
      ..writeln(
        '- **Suites unitaires TDD (`TDD-xxx`)** : ${qa.tddSuites.length} suite(s) · ${qa.totalTddCaseCount} cas de test `Arrange / Act / Assert`',
      )
      ..writeln();

    final objectsTotal = project.businessObjects.length;
    final objectsCovered = project.businessObjects
        .where(
          (obj) => qa.fixtures.any(
            (f) =>
                f.businessObjectId.trim().isNotEmpty &&
                _matchesBusinessObject(obj, f.businessObjectId),
          ),
        )
        .length;

    final mustReqs = project.cahierDesCharges.functionalRequirements
        .where((r) => r.priority == RequirementPriority.must)
        .toList();
    final mustCovered = mustReqs
        .where((req) => _isRequirementCovered(project, req))
        .length;

    final shouldReqs = project.cahierDesCharges.functionalRequirements
        .where((r) => r.priority == RequirementPriority.should)
        .toList();
    final shouldCovered = shouldReqs
        .where((req) => _isRequirementCovered(project, req))
        .length;

    final useCases = project.cahierDesCharges.useCases;
    final ucCovered = useCases
        .where(
          (uc) => qa.features.any(
            (f) => f.scenarios.any(
              (sc) => sc.useCaseIds.any((ref) => _matchesUseCase(uc, ref)),
            ),
          ),
        )
        .length;

    final activeRules = project.businessRules.where((r) => r.active).toList();
    final rulesCovered = activeRules
        .where((rule) => _isRuleCovered(project, rule))
        .length;

    buf
      ..writeln('### 1.2 Taux de couverture 360° (Métier & UX ↔ QA)')
      ..writeln()
      ..writeln('| Axe de couverture | Couverts / Total | Taux |')
      ..writeln('|---|---|---|')
      ..writeln(
        '| **Objets métiers dotés de fixtures** | $objectsCovered / $objectsTotal | ${_formatRate(objectsCovered, objectsTotal)} |',
      )
      ..writeln(
        '| **Exigences fonctionnelles `EXF` (Must)** | $mustCovered / ${mustReqs.length} | ${_formatRate(mustCovered, mustReqs.length)} |',
      );
    if (shouldReqs.isNotEmpty) {
      buf.writeln(
        '| **Exigences fonctionnelles `EXF` (Should)** | $shouldCovered / ${shouldReqs.length} | ${_formatRate(shouldCovered, shouldReqs.length)} |',
      );
    }
    buf
      ..writeln(
        '| **Cas d’usage (`UC`) en Gherkin** | $ucCovered / ${useCases.length} | ${_formatRate(ucCovered, useCases.length)} |',
      )
      ..writeln(
        '| **Règles de gestion actives (`RG-xxx`)** | $rulesCovered / ${activeRules.length} | ${_formatRate(rulesCovered, activeRules.length)} |',
      );

    if (ux.journeys.isNotEmpty) {
      final jrnCovered = ux.journeys
          .where(
            (j) => qa.features.any(
              (f) => f.scenarios.any(
                (sc) => sc.journeyIds.any((ref) => _matchesJourney(j, ref)),
              ),
            ),
          )
          .length;
      buf.writeln(
        '| **Parcours UX (`JRN-xxx`) en Gherkin** | $jrnCovered / ${ux.journeys.length} | ${_formatRate(jrnCovered, ux.journeys.length)} |',
      );
    }

    if (ux.screens.isNotEmpty) {
      final scrCovered = ux.screens
          .where((s) => _isScreenCovered(project, s))
          .length;
      buf.writeln(
        '| **Écrans UX (`SCR-xxx`) couverts (Gherkin / TDD)** | $scrCovered / ${ux.screens.length} | ${_formatRate(scrCovered, ux.screens.length)} |',
      );
    }
    buf.writeln();
  }

  static void _writeFixturesSection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final fixtures = project.qaSpec.fixtures;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 2. Jeux de Données & Cas aux Limites')
      ..writeln();

    if (fixtures.isEmpty) {
      buf
        ..writeln('_Aucun jeu d’essai (`FIX-xxx`) modélisé._')
        ..writeln();
      return;
    }

    buf
      ..writeln(
        '| Code | Intitulé | Catégorie | Objet métier | Validité attendue | Règles (`RG`) |',
      )
      ..writeln('|---|---|---|---|---|---|');
    for (final fixture in fixtures) {
      final code = fixture.code.trim().isNotEmpty ? fixture.code.trim() : fixture.id;
      final obj = fixture.businessObjectId.trim().isEmpty
          ? null
          : project.findBusinessObject(fixture.businessObjectId);
      final objLabel = obj != null
          ? '${obj.name} (`${obj.technicalName}`)'
          : (fixture.businessObjectId.isEmpty
                ? '—'
                : '`${fixture.businessObjectId}`');
      final validityLabel = fixture.expectedValid
          ? 'Valide (`true`)'
          : 'Rejeté (`false`)${fixture.expectedErrorHint.isEmpty ? '' : ' — ${fixture.expectedErrorHint}'}';
      final rulesCell = fixture.businessRuleIds.isEmpty
          ? '—'
          : fixture.businessRuleIds.map((r) => '`$r`').join(', ');
      buf.writeln(
        '| `${_esc(code)}` | **${_esc(fixture.name)}** | ${_esc(fixture.kind.label)} | ${_esc(objLabel)} | ${_esc(validityLabel)} | ${_esc(rulesCell)} |',
      );
    }
    buf.writeln();

    for (final fixture in fixtures) {
      final codePrefix = fixture.code.trim().isNotEmpty
          ? '${fixture.code.trim()} — '
          : '';
      final obj = fixture.businessObjectId.trim().isEmpty
          ? null
          : project.findBusinessObject(fixture.businessObjectId);
      buf
        ..writeln('### $codePrefix${fixture.name} (`${fixture.id}`)')
        ..writeln(
          '- **Catégorie** : ${fixture.kind.label} (`${fixture.kind.name}`)',
        );
      if (obj != null) {
        buf.writeln(
          '- **Objet métier ciblé** : ${obj.name} (`${obj.technicalName}`)',
        );
      } else if (fixture.businessObjectId.trim().isNotEmpty) {
        buf.writeln('- **Objet métier ciblé** : `${fixture.businessObjectId}`');
      }
      if (fixture.personaId.trim().isNotEmpty) {
        buf.writeln(
          '- **Persona associé** : ${_findPersonaLabel(project, fixture.personaId)}',
        );
      }
      if (fixture.businessRuleIds.isNotEmpty) {
        buf.writeln(
          '- **Règles exercées** : ${fixture.businessRuleIds.map((r) => '`$r`').join(', ')}',
        );
      }
      buf.writeln(
        '- **Résultat attendu** : ${fixture.expectedValid ? 'Conforme au schéma et aux règles (`expectedValid: true`)' : 'Rejet attendu (`expectedValid: false`)'}',
      );
      if (!fixture.expectedValid && fixture.expectedErrorHint.trim().isNotEmpty) {
        buf.writeln('- **Erreur attendue** : « ${fixture.expectedErrorHint.trim()} »');
      }
      if (fixture.description.trim().isNotEmpty) {
        buf.writeln('- **Description** : ${fixture.description.trim()}');
      }
      buf
        ..writeln()
        ..writeln('```json')
        ..writeln(_prettyJson.convert(fixture.payload))
        ..writeln('```')
        ..writeln();
    }
  }

  static void _writeGherkinSection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final qa = project.qaSpec;
    final features = qa.features;
    final assignedFiles = GherkinFeatureExporter.assignFeatureFileNames(
      features,
    );
    final fileNameByFeatureId = <String, String>{
      for (final entry in assignedFiles.entries) entry.value.id: entry.key,
    };

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 3. Spécifications Exécutables Gherkin')
      ..writeln();

    if (features.isEmpty) {
      buf
        ..writeln('_Aucune fonctionnalité Gherkin (`FEAT-xxx`) formalisée._')
        ..writeln();
      return;
    }

    for (final feature in features) {
      final codePrefix = feature.code.trim().isNotEmpty
          ? '${feature.code.trim()} — '
          : '';
      final fileName = fileNameByFeatureId[feature.id] ?? '${feature.id}.feature';
      buf
        ..writeln('### $codePrefix${feature.title} (`${feature.id}`)')
        ..writeln('- **Fichier cible** : `features/$fileName`');
      if (feature.moduleId.trim().isNotEmpty) {
        buf.writeln('- **Module** : `${feature.moduleId}`');
      }
      if (feature.personaId.trim().isNotEmpty) {
        buf.writeln(
          '- **Persona principal** : ${_findPersonaLabel(project, feature.personaId)}',
        );
      }
      buf.writeln('- **Scénarios** : ${feature.scenarios.length}');

      final allReqs = <String>{
        for (final sc in feature.scenarios) ...sc.requirementIds,
      };
      final allUcs = <String>{
        for (final sc in feature.scenarios) ...sc.useCaseIds,
      };
      final allRules = <String>{
        for (final sc in feature.scenarios) ...sc.businessRuleIds,
      };
      final allJrns = <String>{
        for (final sc in feature.scenarios) ...sc.journeyIds,
      };
      final allScrs = <String>{
        for (final sc in feature.scenarios) ...sc.screenIds,
      };
      final allFixs = <String>{
        for (final sc in feature.scenarios) ...sc.fixtureIds,
      };

      final refsSummary = <String>[
        if (allReqs.isNotEmpty)
          'Exigences : ${allReqs.map((e) => '`$e`').join(', ')}',
        if (allUcs.isNotEmpty)
          'Cas d’usage : ${allUcs.map((e) => '`$e`').join(', ')}',
        if (allRules.isNotEmpty)
          'Règles : ${allRules.map((e) => '`$e`').join(', ')}',
        if (allJrns.isNotEmpty)
          'Parcours UX : ${allJrns.map((e) => '`$e`').join(', ')}',
        if (allScrs.isNotEmpty)
          'Écrans UX : ${allScrs.map((e) => '`$e`').join(', ')}',
        if (allFixs.isNotEmpty)
          'Fixtures : ${allFixs.map((e) => '`$e`').join(', ')}',
      ];
      if (refsSummary.isNotEmpty) {
        buf.writeln('- **Traçabilité** : ${refsSummary.join(' · ')}');
      }

      final gherkinContent = GherkinFeatureExporter.exportFeature(
        feature,
        language: qa.gherkinLanguage,
      ).trimRight();
      buf
        ..writeln()
        ..writeln('```gherkin')
        ..writeln(gherkinContent)
        ..writeln('```')
        ..writeln();
    }
  }

  static void _writeTddSection(StringBuffer buf, SpecForgeProject project) {
    final suites = project.qaSpec.tddSuites;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 4. Suites de Tests Unitaires & Contrats TDD')
      ..writeln();

    if (suites.isEmpty) {
      buf
        ..writeln('_Aucune suite de tests unitaires TDD (`TDD-xxx`) formalisée._')
        ..writeln();
      return;
    }

    for (final suite in suites) {
      final codePrefix = suite.code.trim().isNotEmpty
          ? '${suite.code.trim()} — '
          : '';
      final targetObj = suite.targetObjectId.trim().isEmpty
          ? null
          : project.findBusinessObject(suite.targetObjectId);

      buf
        ..writeln('### $codePrefix${suite.name} (`${suite.id}`)')
        ..writeln(
          '- **Couche cible** : ${suite.layer.label} (`${suite.layer.name}`)',
        );
      if (targetObj != null) {
        buf.writeln(
          '- **Objet métier ciblé** : ${targetObj.name} (`${targetObj.technicalName}`)',
        );
      } else if (suite.targetObjectId.trim().isNotEmpty) {
        buf.writeln('- **Objet métier ciblé** : `${suite.targetObjectId}`');
      }
      if (suite.moduleId.trim().isNotEmpty) {
        buf.writeln('- **Module** : `${suite.moduleId}`');
      }
      if (suite.description.trim().isNotEmpty) {
        buf.writeln('- **Stratégie** : ${suite.description.trim()}');
      }
      buf.writeln();

      if (suite.cases.isEmpty) {
        buf
          ..writeln('_Aucun cas de test défini dans cette suite._')
          ..writeln();
        continue;
      }

      final orderedCases = List<TddTestCaseSpec>.from(suite.cases)
        ..sort((a, b) {
          final byOrder = a.order.compareTo(b.order);
          return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
        });

      buf
        ..writeln(
          '#### Progression Red → Green → Refactor (${orderedCases.length} cas)',
        )
        ..writeln()
        ..writeln(
          '| # | Code | Intitulé | Fixture | Contrat attendu | Traçabilité (`RG` / `EXF` / `SCR`) |',
        )
        ..writeln('|---|---|---|---|---|---|');

      for (final tc in orderedCases) {
        final tcCode = tc.code.trim().isNotEmpty ? tc.code.trim() : tc.id;
        final fixCell = tc.fixtureId.trim().isEmpty ? '—' : '`${tc.fixtureId}`';
        final refs = <String>[
          ...tc.businessRuleIds.map((r) => '`$r`'),
          ...tc.requirementIds.map((r) => '`$r`'),
          ...tc.screenIds.map((s) => '`$s`'),
        ];
        buf.writeln(
          '| ${tc.order} | `${_esc(tcCode)}` | **${_esc(tc.title)}** | ${_esc(fixCell)} | ${_esc(tc.outcomeKind.label)} | ${refs.isEmpty ? '—' : _esc(refs.join(', '))} |',
        );
      }
      buf.writeln();

      for (final tc in orderedCases) {
        final tcCode = tc.code.trim().isNotEmpty ? tc.code.trim() : tc.id;
        buf
          ..writeln('##### [${tc.order}] $tcCode — ${tc.title}')
          ..writeln(
            '- **Arrange** : ${tc.arrange.trim().isEmpty ? '_(contexte standard)_' : tc.arrange.trim()}${tc.fixtureId.trim().isEmpty ? '' : ' _(fixture : `${tc.fixtureId}`)_'}',
          )
          ..writeln(
            '- **Act** : ${tc.act.trim().isEmpty ? '—' : tc.act.trim()}',
          )
          ..writeln(
            '- **Assert** _(${tc.outcomeKind.label})_ : ${tc.assertExpected.trim().isEmpty ? '—' : tc.assertExpected.trim()}',
          );
        if (tc.expectedErrorMessage.trim().isNotEmpty) {
          buf.writeln(
            '- **Erreur attendue** : « ${tc.expectedErrorMessage.trim()} »',
          );
        }
        buf.writeln();
      }
    }
  }

  static void _writeTraceabilityMatrix(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final qa = project.qaSpec;
    final ux = project.uxSpec;

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 5. Matrice de Traçabilité 360°')
      ..writeln();

    // 5.1 Exigences EXF & Cas d'usage UC
    buf.writeln('### 5.1 Exigences Fonctionnelles (`EXF`) & Cas d’Usage (`UC`)');
    final reqs = project.cahierDesCharges.functionalRequirements;
    final ucs = project.cahierDesCharges.useCases;
    if (reqs.isEmpty && ucs.isEmpty) {
      buf
        ..writeln('_Aucune exigence fonctionnelle ni cas d’usage défini._')
        ..writeln();
    } else {
      buf
        ..writeln(
          '| Élément métier | Type / Priorité | Scénarios Gherkin (`FEAT` / `SCN`) | Cas TDD (`TDD` / `TC`) |',
        )
        ..writeln('|---|---|---|---|');

      for (final req in reqs) {
        final gherkinHits = _gherkinRefsForRequirement(qa.features, req);
        final tddHits = _tddRefsForRequirement(qa.tddSuites, req);
        final code = req.code.trim().isNotEmpty ? req.code.trim() : req.id;
        buf.writeln(
          '| `${_esc(code)}` — ${_esc(req.title)} | ${req.priority.code} (${req.priority.label}) | ${gherkinHits.isEmpty ? '—' : gherkinHits.join(', ')} | ${tddHits.isEmpty ? '—' : tddHits.join(', ')} |',
        );
      }

      for (final uc in ucs) {
        final gherkinHits = _gherkinRefsForUseCase(qa.features, uc);
        buf.writeln(
          '| **${_esc(uc.title)}** (`${_esc(uc.id)}`) | Cas d’usage | ${gherkinHits.isEmpty ? '—' : gherkinHits.join(', ')} | — |',
        );
      }
      buf.writeln();
    }

    // 5.2 Règles de gestion RG-xxx
    buf.writeln('### 5.2 Règles de Gestion (`RG-xxx`) ↔ Fixtures, Gherkin & TDD');
    if (project.businessRules.isEmpty) {
      buf
        ..writeln('_Aucune règle de gestion formalisée._')
        ..writeln();
    } else {
      buf
        ..writeln(
          '| Règle | Catégorie & Statut | Fixtures (`FIX`) | Scénarios Gherkin (`FEAT` / `SCN`) | Cas TDD (`TDD` / `TC`) |',
        )
        ..writeln('|---|---|---|---|---|');
      for (final rule in project.businessRules) {
        final fixHits = <String>[
          for (final f in qa.fixtures)
            if (f.businessRuleIds.any((ref) => _matchesRule(rule, ref)))
              '`${f.code.trim().isNotEmpty ? f.code.trim() : f.id}`',
        ];
        final gherkinHits = _gherkinRefsForRule(qa.features, rule);
        final tddHits = _tddRefsForRule(qa.tddSuites, rule);
        final code = rule.code.trim().isNotEmpty ? rule.code.trim() : rule.id;
        final statusLabel = rule.active ? 'Active' : 'Inactive';
        buf.writeln(
          '| `${_esc(code)}` — ${_esc(rule.title)} | ${_esc(rule.category.label)} ($statusLabel) | ${fixHits.isEmpty ? '—' : fixHits.join(', ')} | ${gherkinHits.isEmpty ? '—' : gherkinHits.join(', ')} | ${tddHits.isEmpty ? '—' : tddHits.join(', ')} |',
        );
      }
      buf.writeln();
    }

    // 5.3 Parcours JRN-xxx & Écrans SCR-xxx
    buf.writeln(
      '### 5.3 Parcours (`JRN-xxx`) & Écrans UX (`SCR-xxx`) ↔ Gherkin & TDD',
    );
    if (ux.journeys.isEmpty && ux.screens.isEmpty) {
      buf
        ..writeln('_Aucun parcours ni écran UX formalisé._')
        ..writeln();
    } else {
      buf
        ..writeln(
          '| Élément UX | Type | Scénarios Gherkin (`FEAT` / `SCN`) | Cas TDD (`TDD` / `TC`) |',
        )
        ..writeln('|---|---|---|---|');

      for (final jrn in ux.journeys) {
        final jrnCode = jrn.code.trim().isNotEmpty ? jrn.code.trim() : jrn.id;
        final gherkinHits = _gherkinRefsForJourney(qa.features, jrn);
        buf.writeln(
          '| `${_esc(jrnCode)}` — ${_esc(jrn.name)} | Parcours (${_esc(jrn.channel.label)}) | ${gherkinHits.isEmpty ? '—' : gherkinHits.join(', ')} | — |',
        );
      }

      for (final scr in ux.screens) {
        final scrCode = scr.code.trim().isNotEmpty ? scr.code.trim() : scr.id;
        final gherkinHits = _gherkinRefsForScreen(qa.features, scr);
        final tddHits = _tddRefsForScreen(qa.tddSuites, scr);
        buf.writeln(
          '| `${_esc(scrCode)}` — ${_esc(scr.name)} | Écran (${_esc(scr.pattern.label)}) | ${gherkinHits.isEmpty ? '—' : gherkinHits.join(', ')} | ${tddHits.isEmpty ? '—' : tddHits.join(', ')} |',
        );
      }
      buf.writeln();
    }

    // 5.4 Diagnostic de cohérence QA 360°
    final localIssues = QaCoherenceAnalyzer.analyze(project);
    final aiIssues = qa.coherenceIssues.where((i) => i.source == 'ai');
    final allIssues = <QaCoherenceIssue>[...localIssues, ...aiIssues];
    if (allIssues.isNotEmpty) {
      buf
        ..writeln('### 5.4 Points de Vigilance & Cohérence QA 360°')
        ..writeln();
      for (final issue in allIssues) {
        final badge = switch (issue.severity) {
          CoherenceSeverity.error => '[ERREUR]',
          CoherenceSeverity.warning => '[ATTENTION]',
          CoherenceSeverity.info => '[INFO]',
        };
        buf.writeln(
          '- **$badge ${issue.code} — ${issue.title}** : ${issue.description}',
        );
      }
      buf.writeln();
    }
  }

  static List<String> _gherkinRefsForRequirement(
    List<GherkinFeatureSpec> features,
    FunctionalRequirement req,
  ) {
    final hits = <String>[];
    for (final f in features) {
      final fCode = f.code.trim().isNotEmpty ? f.code.trim() : f.id;
      for (final sc in f.scenarios) {
        if (sc.requirementIds.any((ref) => _matchesRequirement(req, ref))) {
          final scCode = sc.code.trim().isNotEmpty ? sc.code.trim() : sc.id;
          hits.add('`$fCode/$scCode`');
        }
      }
    }
    return hits;
  }

  static List<String> _tddRefsForRequirement(
    List<TddTestSuiteSpec> suites,
    FunctionalRequirement req,
  ) {
    final hits = <String>[];
    for (final s in suites) {
      final sCode = s.code.trim().isNotEmpty ? s.code.trim() : s.id;
      for (final tc in s.cases) {
        if (tc.requirementIds.any((ref) => _matchesRequirement(req, ref))) {
          final tcCode = tc.code.trim().isNotEmpty ? tc.code.trim() : tc.id;
          hits.add('`$sCode/$tcCode`');
        }
      }
    }
    return hits;
  }

  static List<String> _gherkinRefsForUseCase(
    List<GherkinFeatureSpec> features,
    UseCaseSpec uc,
  ) {
    final hits = <String>[];
    for (final f in features) {
      final fCode = f.code.trim().isNotEmpty ? f.code.trim() : f.id;
      for (final sc in f.scenarios) {
        if (sc.useCaseIds.any((ref) => _matchesUseCase(uc, ref))) {
          final scCode = sc.code.trim().isNotEmpty ? sc.code.trim() : sc.id;
          hits.add('`$fCode/$scCode`');
        }
      }
    }
    return hits;
  }

  static List<String> _gherkinRefsForRule(
    List<GherkinFeatureSpec> features,
    BusinessRuleSpec rule,
  ) {
    final hits = <String>[];
    for (final f in features) {
      final fCode = f.code.trim().isNotEmpty ? f.code.trim() : f.id;
      for (final sc in f.scenarios) {
        if (sc.businessRuleIds.any((ref) => _matchesRule(rule, ref))) {
          final scCode = sc.code.trim().isNotEmpty ? sc.code.trim() : sc.id;
          hits.add('`$fCode/$scCode`');
        }
      }
    }
    return hits;
  }

  static List<String> _tddRefsForRule(
    List<TddTestSuiteSpec> suites,
    BusinessRuleSpec rule,
  ) {
    final hits = <String>[];
    for (final s in suites) {
      final sCode = s.code.trim().isNotEmpty ? s.code.trim() : s.id;
      for (final tc in s.cases) {
        if (tc.businessRuleIds.any((ref) => _matchesRule(rule, ref))) {
          final tcCode = tc.code.trim().isNotEmpty ? tc.code.trim() : tc.id;
          hits.add('`$sCode/$tcCode`');
        }
      }
    }
    return hits;
  }

  static List<String> _gherkinRefsForJourney(
    List<GherkinFeatureSpec> features,
    UxJourneySpec journey,
  ) {
    final hits = <String>[];
    for (final f in features) {
      final fCode = f.code.trim().isNotEmpty ? f.code.trim() : f.id;
      for (final sc in f.scenarios) {
        if (sc.journeyIds.any((ref) => _matchesJourney(journey, ref))) {
          final scCode = sc.code.trim().isNotEmpty ? sc.code.trim() : sc.id;
          hits.add('`$fCode/$scCode`');
        }
      }
    }
    return hits;
  }

  static List<String> _gherkinRefsForScreen(
    List<GherkinFeatureSpec> features,
    UxScreenSpec screen,
  ) {
    final hits = <String>[];
    for (final f in features) {
      final fCode = f.code.trim().isNotEmpty ? f.code.trim() : f.id;
      for (final sc in f.scenarios) {
        if (sc.screenIds.any((ref) => _matchesScreen(screen, ref))) {
          final scCode = sc.code.trim().isNotEmpty ? sc.code.trim() : sc.id;
          hits.add('`$fCode/$scCode`');
        }
      }
    }
    return hits;
  }

  static List<String> _tddRefsForScreen(
    List<TddTestSuiteSpec> suites,
    UxScreenSpec screen,
  ) {
    final hits = <String>[];
    for (final s in suites) {
      final sCode = s.code.trim().isNotEmpty ? s.code.trim() : s.id;
      for (final tc in s.cases) {
        if (tc.screenIds.any((ref) => _matchesScreen(screen, ref))) {
          final tcCode = tc.code.trim().isNotEmpty ? tc.code.trim() : tc.id;
          hits.add('`$sCode/$tcCode`');
        }
      }
    }
    return hits;
  }

  static bool _isRequirementCovered(
    SpecForgeProject project,
    FunctionalRequirement req,
  ) {
    final qa = project.qaSpec;
    final inGherkin = qa.features.any(
      (f) => f.scenarios.any(
        (sc) => sc.requirementIds.any((ref) => _matchesRequirement(req, ref)),
      ),
    );
    if (inGherkin) return true;
    return qa.tddSuites.any(
      (s) => s.cases.any(
        (tc) => tc.requirementIds.any((ref) => _matchesRequirement(req, ref)),
      ),
    );
  }

  static bool _isRuleCovered(SpecForgeProject project, BusinessRuleSpec rule) {
    final qa = project.qaSpec;
    final inGherkin = qa.features.any(
      (f) => f.scenarios.any(
        (sc) => sc.businessRuleIds.any((ref) => _matchesRule(rule, ref)),
      ),
    );
    if (inGherkin) return true;
    return qa.tddSuites.any(
      (s) => s.cases.any(
        (tc) => tc.businessRuleIds.any((ref) => _matchesRule(rule, ref)),
      ),
    );
  }

  static bool _isScreenCovered(SpecForgeProject project, UxScreenSpec screen) {
    final qa = project.qaSpec;
    final inGherkin = qa.features.any(
      (f) => f.scenarios.any(
        (sc) => sc.screenIds.any((ref) => _matchesScreen(screen, ref)),
      ),
    );
    if (inGherkin) return true;
    return qa.tddSuites.any(
      (s) => s.cases.any(
        (tc) => tc.screenIds.any((ref) => _matchesScreen(screen, ref)),
      ),
    );
  }

  static bool _matchesBusinessObject(BusinessObjectSpec obj, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return obj.id.toLowerCase() == needle ||
        obj.technicalName.toLowerCase() == needle ||
        obj.name.toLowerCase() == needle;
  }

  static bool _matchesRequirement(FunctionalRequirement req, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return req.id.toLowerCase() == needle ||
        (req.code.trim().isNotEmpty && req.code.trim().toLowerCase() == needle);
  }

  static bool _matchesUseCase(UseCaseSpec uc, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return uc.id.toLowerCase() == needle || uc.title.toLowerCase() == needle;
  }

  static bool _matchesRule(BusinessRuleSpec rule, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return rule.id.toLowerCase() == needle ||
        (rule.code.trim().isNotEmpty &&
            rule.code.trim().toLowerCase() == needle);
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

  static String _findPersonaLabel(SpecForgeProject project, String personaId) {
    final trimmed = personaId.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    for (final p in project.vision.personas) {
      if (p.id.toLowerCase() == lower || p.name.toLowerCase() == lower) {
        return '${p.name} (`${p.id}`)';
      }
    }
    return '`$trimmed`';
  }

  static String _formatRate(int covered, int total) {
    if (total <= 0) return 'N/A';
    final pct = ((covered * 100.0) / total).round();
    return '$pct %';
  }

  static String _esc(String value) =>
      value.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}
