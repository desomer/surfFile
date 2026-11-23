 /// Générateur du prompt d'agent TDD/ATDD ([QaTddPromptExporter]), exportateur de dossier QA ([QaDirectoryExporter]) et amorceurs déterministes en 1 clic ([QaAutoSeeder]).
library;

import 'dart:io';

import '../../models/business_object_model_preferences.dart';
import '../../models/business_object_spec.dart';
import '../../models/business_rule_spec.dart';
import '../../models/example_mapping_spec.dart';
import '../../models/json_schema_constraints.dart';
import '../../models/qa/gherkin_feature_spec.dart';
import '../../models/qa/qa_fixture_spec.dart';
import '../../models/qa/tdd_suite_spec.dart';
import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_vision.dart';
import '../../models/ux/ux_journey_spec.dart';
import '../../models/ux/ux_screen_spec.dart';
import '../spec_storage_slug.dart';
import 'gherkin_feature_exporter.dart';
import 'qa_markdown_exporter.dart';
import 'spec_super_designer_exporter.dart';

/// Assemble le prompt complet `prompt_tdd_agent.md` en français destiné à un agent de
/// codage IA (GitHub Copilot, Claude Code, Cursor, etc.) pour implémenter un
/// [SpecForgeProject] en suivant une discipline stricte **ATDD / BDD + Red → Green → Refactor TDD**.
abstract final class QaTddPromptExporter {
  /// Génère le prompt Markdown `prompt_tdd_agent.md` pour [project].
  static String export(SpecForgeProject project) {
    final buf = StringBuffer()
      ..writeln(
        '# Prompt Agent IA — Implémentation ATDD / BDD & TDD — ${project.name}',
      )
      ..writeln()
      ..writeln(
        'Tu es un ingénieur logiciel senior chargé d’implémenter **« ${project.name} »** en appliquant rigoureusement une approche **ATDD / BDD (Gherkin)** couplée à des cycles courts **TDD Red → Green → Refactor**.',
      )
      ..writeln();

    _writeMethodologySection(buf, project);
    _writeLexiconAndPreferencesSection(buf, project);
    _writeDomainAndRulesSection(buf, project);
    _writeFixturesCatalogSection(buf, project);
    _writeTddRoadmapSection(buf, project);
    _writeAcceptanceGateSection(buf, project);

    return SpecStorageIo.normalizeLf(buf.toString());
  }

  /// Délègue la construction de la carte `<slug>.json -> fixture.toJson()` à [QaDirectoryExporter].
  static Map<String, Map<String, Object?>> buildFixturesFilesMap(
    SpecForgeProject project,
  ) => QaDirectoryExporter.buildFixturesFilesMap(project);

  /// Délègue l'export complet du dossier QA sur disque à [QaDirectoryExporter].
  static Future<void> exportQaDirectory(
    SpecForgeProject project,
    Directory targetDirectory,
  ) => QaDirectoryExporter.exportQaDirectory(project, targetDirectory);

  static void _writeMethodologySection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf
      ..writeln(
        '## 1. Discipline d’Exécution ATDD / BDD & Red → Green → Refactor',
      )
      ..writeln(
        '1. **Un seul test échouant à la fois (`Red`)** : prends les cas unitaires `TC-001..N` dans l’ordre strict défini par chaque suite `TDD-xxx`. Écris d’abord le test automatisé, exécute-le et vérifie qu’il échoue pour la bonne raison métier.',
      )
      ..writeln(
        '2. **Implémentation minimale (`Green`)** : écris uniquement le code de production nécessaire pour faire passer le cas courant sans casser les tests précédents ni anticiper les cas suivants.',
      )
      ..writeln(
        '3. **Assainissement continu (`Refactor`)** : factorise les duplications, renforce l’immuabilité et vérifie les invariants du domaine en gardant 100 % des tests au vert.',
      )
      ..writeln(
        '4. **Validation d’acceptation BDD (`.feature`)** : une fois les suites unitaires `TDD-xxx` au vert, branche et exécute les scénarios d’acceptation `features/*.feature` (`FEAT-xxx` / `SCN-xxx`) en utilisant les jeux de données `fixtures/*.json` (`FIX-xxx`).',
      )
      ..writeln(
        '5. **Fidélité absolue au contrat** : respecte à la lettre le langage omniprésent (`SpecLexicon`), les préférences techniques (`BusinessObjectModelPreferences`), les contraintes JSON Schema et les messages d’erreur des règles `RG-xxx`.',
      )
      ..writeln();

    final summary = project.vision.ideaSummary.trim().isNotEmpty
        ? project.vision.ideaSummary.trim()
        : project.initialIdea.trim();
    buf.writeln('- **Périmètre fonctionnel** : $summary');
    if (project.vision.valueProposition.trim().isNotEmpty) {
      buf.writeln(
        '- **Proposition de valeur** : ${project.vision.valueProposition.trim()}',
      );
    }
    if (project.vision.personas.isNotEmpty) {
      final actors = project.vision.personas
          .map(
            (p) =>
                '`${p.id}` **${p.name}**${p.role.trim().isEmpty ? '' : ' (${p.role.trim()})'}',
          )
          .join(' · ');
      buf.writeln('- **Personas / Acteurs** : $actors');
    }
    buf.writeln();
  }

  static void _writeLexiconAndPreferencesSection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf.writeln(
      '## 2. Langage Omniprésent (`SpecLexicon`) & Conventions de Modélisation',
    );
    if (project.lexicon.terms.isNotEmpty) {
      buf.writeln('### 2.1 Terminologie métier canonique obligatoire');
      for (final term in project.lexicon.terms) {
        final syn = term.synonyms.isNotEmpty
            ? ' _(remplace : ${term.synonyms.join(', ')})_'
            : '';
        final def = term.definition.trim().isNotEmpty
            ? ' : ${term.definition.trim()}'
            : '';
        buf.writeln('- **${term.term}**$syn$def');
      }
      buf.writeln();
    }
    if (project.lexicon.conventions.isNotEmpty) {
      buf.writeln('### 2.2 Conventions terminologiques du projet');
      for (final conv in project.lexicon.conventions) {
        buf.writeln('- $conv');
      }
      buf.writeln();
    }

    final prefs = project.businessObjectModelPreferences;
    buf
      ..writeln(
        '### 2.3 Préférences de modélisation (`BusinessObjectModelPreferences`)',
      )
      ..writeln(prefs.toPromptDirective())
      ..writeln();
  }

  static void _writeDomainAndRulesSection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf.writeln(
      '## 3. Schéma du Domaine Métier & Règles de Gestion (`RG-xxx`)',
    );

    if (project.businessObjects.isEmpty) {
      buf
        ..writeln('_Aucun objet métier formalisé._')
        ..writeln();
    } else {
      buf.writeln(
        '### 3.1 Objets métiers, attributs, contraintes & cycles de vie',
      );
      for (final obj in project.businessObjects) {
        final alias = SpecSuperDesignerExporter.repoAliasFor(obj);
        final role = obj.aggregateRoot
            ? 'Agrégat racine'
            : 'Entité / Objet valeur';
        buf.writeln(
          '#### `${obj.technicalName}` — ${obj.name} ($role · alias `$alias`)',
        );
        if (obj.description.trim().isNotEmpty) {
          buf.writeln('- **Rôle métier** : ${obj.description.trim()}');
        }
        if (obj.lifecycleStates.isNotEmpty) {
          final states = obj.lifecycleStates
              .map(
                (s) =>
                    '`${s.name}` (${s.effectiveLabel}${s.isInitial ? ', initial' : ''}${s.isTerminal ? ', final' : ''})',
              )
              .join(', ');
          buf.writeln('- **États du cycle de vie** : $states');
        }
        if (obj.lifecycleTransitions.isNotEmpty) {
          final transitions = obj.lifecycleTransitions
              .map(
                (tr) =>
                    '`${tr.fromState}` → `${tr.toState}`${tr.trigger.trim().isEmpty ? '' : ' [quand: ${tr.trigger.trim()}]'}${tr.guardSummary.trim().isEmpty ? '' : ' (garde: ${tr.guardSummary.trim()})'}',
              )
              .join(' ; ');
          buf.writeln('- **Transitions autorisées** : $transitions');
        }
        if (obj.attributes.isNotEmpty) {
          buf.writeln('- **Attributs & contraintes** :');
          for (final attr in obj.attributes) {
            _writeAttributeLine(buf, project, attr, indent: '  ');
          }
        }
        if (obj.relations.isNotEmpty) {
          final rels = obj.relations
              .map((r) {
                final target = project.findBusinessObject(r.targetObjectId);
                final targetName = target?.technicalName ?? r.targetObjectId;
                return '`${r.name}` (${r.cardinality.symbol} → `$targetName`${r.required ? ', requis' : ''})';
              })
              .join(', ');
          buf.writeln('- **Relations** : $rels');
        }
        buf.writeln();
      }
    }

    final activeRules = project.businessRules.where((r) => r.active).toList();
    buf.writeln('### 3.2 Règles de gestion actives (`RG-xxx`)');
    if (activeRules.isEmpty) {
      buf
        ..writeln('_Aucune règle de gestion active._')
        ..writeln();
    } else {
      for (final r in activeRules) {
        final targets = r.targetObjectIds
            .map((oid) => project.findBusinessObject(oid)?.technicalName ?? oid)
            .toList();
        final targetInfo = targets.isEmpty
            ? ''
            : ' · cibles : ${targets.map((t) => '`$t`').join(', ')}';
        buf.writeln(
          '- **${r.code} — ${r.title}** _[${r.category.label}, priorité ${r.priority.label}]${targetInfo}_',
        );
        final details = <String>[
          if (r.trigger.trim().isNotEmpty) 'Quand : ${r.trigger.trim()}',
          if (r.condition.trim().isNotEmpty) 'Si : ${r.condition.trim()}',
          if (r.effect.trim().isNotEmpty) 'Alors : ${r.effect.trim()}',
          if (r.errorMessage.trim().isNotEmpty)
            'Erreur attendue : « ${r.errorMessage.trim()} »',
        ];
        if (details.isNotEmpty) {
          buf.writeln('  - ${details.join(' · ')}');
        } else if (r.description.trim().isNotEmpty) {
          buf.writeln('  - ${r.description.trim()}');
        }
      }
      buf.writeln();
    }
  }

  static void _writeAttributeLine(
    StringBuffer buf,
    SpecForgeProject project,
    BusinessAttribute attr, {
    required String indent,
  }) {
    final sc = attr.schemaConstraints;
    final meta = <String>[
      if (attr.isArray) '${attr.type.dslKeyword}[]' else attr.type.dslKeyword,
      if (attr.required) 'requis' else 'optionnel',
      if (attr.nullable) 'nullable',
      if (attr.unique) 'unique',
      if (attr.type == BusinessAttributeType.enumeration &&
          attr.enumValues.isNotEmpty)
        'enum: [${attr.enumValues.join(', ')}]',
      if (attr.type == BusinessAttributeType.reference &&
          attr.referenceObjectId.isNotEmpty)
        'réf → `${project.findBusinessObject(attr.referenceObjectId)?.technicalName ?? attr.referenceObjectId}`',
      if (sc.xMask != null) 'x-mask: `${sc.xMask}`',
      ...sc.describeBadges().where((b) => !b.startsWith('x-mask:')),
      if (attr.constraints.trim().isNotEmpty) attr.constraints.trim(),
    ];
    final desc = attr.description.trim().isNotEmpty
        ? ' — ${attr.description.trim()}'
        : '';
    buf.writeln('$indent- `${attr.name}` (${meta.join(', ')})$desc');
    for (final child in attr.children) {
      _writeAttributeLine(buf, project, child, indent: '$indent  ');
    }
  }

  static void _writeFixturesCatalogSection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf.writeln(
      '## 4. Référentiel des Jeux de Données Exportés (`fixtures/*.json`)',
    );
    final assigned = QaDirectoryExporter.assignFixtureFileNames(
      project.qaSpec.fixtures,
    );
    if (assigned.isEmpty) {
      buf
        ..writeln(
          '_Aucune fixture pré-exportée ; construis des fixtures déterministes conformes aux contraintes JSON Schema ci-dessus._',
        )
        ..writeln();
      return;
    }

    buf.writeln(
      'Charge ces fichiers JSON dans tes tests unitaires et tes définitions d’étapes BDD (ou depuis `fixtures_bundle.json`) :',
    );
    for (final entry in assigned.entries) {
      final f = entry.value;
      final code = f.code.trim().isNotEmpty ? f.code.trim() : f.id;
      final objName = f.businessObjectId.trim().isEmpty
          ? 'générique'
          : (project.findBusinessObject(f.businessObjectId)?.technicalName ??
                f.businessObjectId);
      final validity = f.expectedValid
          ? 'valide'
          : 'invalide${f.expectedErrorHint.trim().isEmpty ? '' : ' (erreur : « ${f.expectedErrorHint.trim()} »)'}';
      final rules = f.businessRuleIds.isEmpty
          ? ''
          : ' · règles : ${f.businessRuleIds.map((r) => '`$r`').join(', ')}';
      buf.writeln(
        '- **`fixtures/${entry.key}`** — **$code : ${f.name}** _[${f.kind.label}, objet `$objName`, $validity]${rules}_',
      );
    }
    buf.writeln();
  }

  static void _writeTddRoadmapSection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf.writeln(
      '## 5. Feuille de Route TDD Ordonnée (`TDD-xxx` / `TC-xxx` : Red → Green → Refactor)',
    );
    final suites = project.qaSpec.tddSuites;
    if (suites.isEmpty) {
      buf
        ..writeln(
          '_Aucune suite TDD pré-définie ; dérive des cas atomiques Arrange / Act / Assert pour chaque règle `RG-xxx` active._',
        )
        ..writeln();
      return;
    }

    final fixtureFilesById = <String, String>{};
    for (final entry in QaDirectoryExporter.assignFixtureFileNames(
      project.qaSpec.fixtures,
    ).entries) {
      fixtureFilesById[entry.value.id.toLowerCase()] = 'fixtures/${entry.key}';
      if (entry.value.code.trim().isNotEmpty) {
        fixtureFilesById[entry.value.code.trim().toLowerCase()] =
            'fixtures/${entry.key}';
      }
    }

    for (final suite in suites) {
      final suiteCode = suite.code.trim().isNotEmpty
          ? '${suite.code.trim()} — '
          : '';
      final targetObj = suite.targetObjectId.trim().isEmpty
          ? ''
          : ' · cible : `${project.findBusinessObject(suite.targetObjectId)?.technicalName ?? suite.targetObjectId}`';
      buf.writeln(
        '### $suiteCode${suite.name} (`${suite.id}` · ${suite.layer.label}$targetObj)',
      );
      if (suite.description.trim().isNotEmpty) {
        buf.writeln(suite.description.trim());
      }

      final orderedCases = List<TddTestCaseSpec>.from(suite.cases)
        ..sort((a, b) {
          final byOrder = a.order.compareTo(b.order);
          return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
        });

      for (final tc in orderedCases) {
        final tcCode = tc.code.trim().isNotEmpty ? tc.code.trim() : tc.id;
        final resolvedFixturePath = tc.fixtureId.trim().isEmpty
            ? null
            : fixtureFilesById[tc.fixtureId.trim().toLowerCase()];
        final fixtureSuffix = tc.fixtureId.trim().isEmpty
            ? ''
            : ' _(fixture `${tc.fixtureId}`${resolvedFixturePath != null ? ' → `$resolvedFixturePath`' : ''})_';
        final refs = <String>[
          ...tc.businessRuleIds.map((r) => '`$r`'),
          ...tc.requirementIds.map((r) => '`$r`'),
          ...tc.screenIds.map((s) => '`$s`'),
        ];
        final refsSuffix = refs.isEmpty ? '' : ' · couvre ${refs.join(', ')}';

        buf
          ..writeln(
            '${tc.order}. **$tcCode — ${tc.title}** [${tc.outcomeKind.label}]$refsSuffix',
          )
          ..writeln(
            '   - **Arrange** : ${tc.arrange.trim().isEmpty ? 'Initialiser le contexte de test' : tc.arrange.trim()}$fixtureSuffix',
          )
          ..writeln(
            '   - **Act** : ${tc.act.trim().isEmpty ? 'Exécuter l’opération ciblée' : tc.act.trim()}',
          );
        if (tc.assertExpected.trim().isNotEmpty) {
          buf.writeln('   - **Assert** : ${tc.assertExpected.trim()}');
        }
        if (tc.expectedErrorMessage.trim().isNotEmpty) {
          buf.writeln(
            '   - **Expected Error** : « ${tc.expectedErrorMessage.trim()} »',
          );
        }
      }
      buf.writeln();
    }
  }

  static void _writeAcceptanceGateSection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf.writeln(
      '## 6. Porte d’Acceptation Finale : Scénarios BDD (`features/*.feature`) & UX',
    );
    final featureFiles = GherkinFeatureExporter.assignFeatureFileNames(
      project.qaSpec.features,
    );
    if (featureFiles.isEmpty) {
      buf.writeln('_Aucun fichier `.feature` exporté._');
    } else {
      buf.writeln(
        'Tous les scénarios Gherkin suivants doivent passer de bout en bout avant clôture :',
      );
      for (final entry in featureFiles.entries) {
        final feat = entry.value;
        final featCode = feat.code.trim().isNotEmpty
            ? '${feat.code.trim()} — '
            : '';
        buf.writeln(
          '- **`features/${entry.key}`** — **$featCode${feat.title}** (${feat.scenarios.length} scénario(s)) :',
        );
        for (final sc in feat.scenarios) {
          final scCode = sc.code.trim().isNotEmpty ? sc.code.trim() : sc.id;
          final outlineNote = sc.isOutline
              ? ' [Plan du Scénario : ${sc.examples.rows.length} ligne(s) d’exemples]'
              : '';
          buf.writeln(
            '  - `$scCode` : ${sc.title} (${sc.steps.length} étape(s))$outlineNote',
          );
        }
      }
    }
    buf.writeln();

    final ux = project.uxSpec;
    if (ux.navigation.routes.isNotEmpty ||
        ux.screens.isNotEmpty ||
        ux.journeys.isNotEmpty) {
      buf.writeln(
        '### Alignement Routes, Écrans (`SCR-xxx`) & Parcours UX (`JRN-xxx`)',
      );
      if (ux.navigation.routes.isNotEmpty) {
        final routesSummary = ux.navigation.routes
            .map((r) => '`${r.path}` (${r.title}, `${r.pageType.name}`)')
            .join(', ');
        buf.writeln('- **Routes applicatives** : $routesSummary');
      }
      for (final screen in ux.screens) {
        final scrCode = screen.code.trim().isNotEmpty
            ? '${screen.code.trim()} — '
            : '';
        final route = screen.routeId.trim().isEmpty
            ? null
            : ux.navigation.findRoute(screen.routeId);
        final routeInfo = route != null
            ? '`${route.path}`'
            : (screen.routeId.trim().isEmpty ? '`/`' : '`${screen.routeId}`');
        final actionLabels = screen.actions
            .map((a) => '« ${a.label} »')
            .join(', ');
        buf.writeln(
          '- **$scrCode${screen.name}** (route $routeInfo, pattern `${screen.pattern.name}`)${actionLabels.isEmpty ? '' : ' · actions : $actionLabels'}',
        );
      }
      for (final journey in ux.journeys) {
        final jrnCode = journey.code.trim().isNotEmpty
            ? '${journey.code.trim()} — '
            : '';
        buf.writeln(
          '- **Parcours $jrnCode${journey.name}** (${journey.channel.label}, ${journey.steps.length} étape(s))',
        );
      }
      buf.writeln();
    }
  }
}

/// Exporte sur disque le dossier complet des livrables QA BDD/TDD (`.feature`,
/// `fixtures/*.json`, `fixtures_bundle.json`, `specification_bdd_tdd.md`,
/// `specification_qa.json` et `prompt_tdd_agent.md`, **sans aucun fichier `.html`**).
abstract final class QaDirectoryExporter {
  /// Assigne des noms de fichiers `<slug>.json` uniques et déterministes aux [fixtures].
  static Map<String, QaFixtureSpec> assignFixtureFileNames(
    Iterable<QaFixtureSpec> fixtures,
  ) => SpecStorageSlug.assignUniqueJsonFiles<QaFixtureSpec>(
    fixtures,
    labelFor: (fixture) {
      final rawCode = fixture.code.trim();
      return rawCode.isNotEmpty && rawCode.toUpperCase() != 'FIX'
          ? '$rawCode ${fixture.name.trim()}'
          : fixture.name.trim();
    },
    idFor: (fixture) => fixture.id,
    fallback: 'fixture',
  );

  /// Construit la carte déterministe `<slug>.json -> fixture.toJson()` pour [project].
  static Map<String, Map<String, Object?>> buildFixturesFilesMap(
    SpecForgeProject project,
  ) {
    final assigned = assignFixtureFileNames(project.qaSpec.fixtures);
    return Map<String, Map<String, Object?>>.unmodifiable(
      <String, Map<String, Object?>>{
        for (final entry in assigned.entries) entry.key: entry.value.toJson(),
      },
    );
  }

  /// Écrit l'arborescence complète des livrables QA BDD/TDD dans [targetDirectory]
  /// sans jamais générer de fichier `.html`.
  static Future<void> exportQaDirectory(
    SpecForgeProject project,
    Directory targetDirectory,
  ) async {
    await targetDirectory.create(recursive: true);
    final sep = Platform.pathSeparator;

    // Garantit l'absence de tout ancien fichier .html résiduel à la racine du dossier exporté.
    await for (final entity in targetDirectory.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.html')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }

    final featureFiles = GherkinFeatureExporter.exportAllFeatures(project);
    final featuresDir = Directory('${targetDirectory.path}${sep}features');
    await featuresDir.create(recursive: true);
    for (final entry in featureFiles.entries) {
      final fileName = entry.key.endsWith('.feature')
          ? entry.key
          : '${entry.key}.feature';
      await File('${featuresDir.path}$sep$fileName')
          .writeAsString(SpecStorageIo.normalizeLf(entry.value), flush: true);
    }
    await SpecStorageIo.pruneUnexpectedFiles(
      featuresDir,
      featureFiles.keys.toSet(),
      extension: '.feature',
    );

    final fixtureFiles = buildFixturesFilesMap(project);
    final fixturesDir = Directory('${targetDirectory.path}${sep}fixtures');
    await fixturesDir.create(recursive: true);
    for (final entry in fixtureFiles.entries) {
      final fileName = entry.key.endsWith('.json')
          ? entry.key
          : '${entry.key}.json';
      await File(
        '${fixturesDir.path}$sep$fileName',
      ).writeAsString(SpecStorageIo.encodePrettyJson(entry.value), flush: true);
    }
    await SpecStorageIo.pruneUnexpectedFiles(
      fixturesDir,
      fixtureFiles.keys.toSet(),
      extension: '.json',
    );

    final fixturesBundle = <String, Object?>{
      'fixtures': [for (final f in project.qaSpec.fixtures) f.toJson()],
    };
    await File('${targetDirectory.path}${sep}fixtures_bundle.json')
        .writeAsString(
          SpecStorageIo.encodePrettyJson(fixturesBundle),
          flush: true,
        );

    await File('${targetDirectory.path}${sep}specification_bdd_tdd.md')
        .writeAsString(
          SpecStorageIo.normalizeLf(QaMarkdownExporter.export(project)),
          flush: true,
        );

    await File('${targetDirectory.path}${sep}specification_qa.json')
        .writeAsString(
          SpecStorageIo.encodePrettyJson(project.qaSpec.toJson()),
          flush: true,
        );

    await File('${targetDirectory.path}${sep}prompt_tdd_agent.md')
        .writeAsString(
          SpecStorageIo.normalizeLf(QaTddPromptExporter.export(project)),
          flush: true,
        );
  }
}

/// Générateurs déterministes en 1 clic (« Auto-Seed ») amorçant les fixtures QA,
/// les fonctionnalités Gherkin BDD et les suites unitaires TDD à partir du modèle métier et UX.
abstract final class QaAutoSeeder {
  /// Génère 1 fixture `nominal` et 1 fixture `boundary` / `invalid` pour chaque
  /// [BusinessObjectSpec] de [project] ne disposant pas encore de fixture QA.
  static List<QaFixtureSpec> seedFixturesFromSchema(SpecForgeProject project) {
    final existing = project.qaSpec.fixtures;
    final usedIds = <String>{for (final f in existing) f.id.toLowerCase()};
    var nextCodeIndex = _nextSequentialNumber(
      existing.map((f) => f.code),
      prefix: 'FIX',
    );

    final locale = project.businessObjectModelPreferences.localeProfile;
    final defaultPersonaId = project.vision.personas.isNotEmpty
        ? project.vision.personas.first.id
        : '';

    final seeded = <QaFixtureSpec>[];

    for (final obj in project.businessObjects) {
      final alreadyHasFixture = existing.any(
        (f) =>
            f.businessObjectId.trim().isNotEmpty &&
            _matchesBusinessObject(obj, f.businessObjectId),
      );
      if (alreadyHasFixture) continue;

      final slug = SpecStorageSlug.slugify(
        obj.technicalName,
        fallback: 'objet',
        separator: '_',
      );
      final objRules = [
        for (final r in project.businessRules)
          if (r.active &&
              r.targetObjectIds.any((tid) => _matchesBusinessObject(obj, tid)))
            r,
      ];
      final nominalRuleRefs = <String>[
        for (final r in objRules.take(2))
          r.code.trim().isNotEmpty ? r.code.trim() : r.id,
      ];

      final nominalPayload = _buildNominalPayload(
        project,
        obj,
        visited: <String>{obj.id},
        locale: locale,
      );

      final nominalId = _allocateUniqueId('fix_${slug}_nominal', usedIds);
      final nominalCode = 'FIX-${(nextCodeIndex++).toString().padLeft(3, '0')}';
      seeded.add(
        QaFixtureSpec(
          id: nominalId,
          code: nominalCode,
          name: '${obj.name} — Cas nominal conforme',
          kind: QaFixtureKind.nominal,
          businessObjectId: obj.id,
          personaId: defaultPersonaId,
          businessRuleIds: nominalRuleRefs,
          description:
              'Enregistrement nominal valide de « ${obj.name} » (${obj.technicalName}) construit à partir des exemples et valeurs par défaut du schéma.',
          payload: nominalPayload,
          expectedValid: true,
        ),
      );

      final violation = _buildViolationMutation(
        obj,
        basePayload: nominalPayload,
        matchingRules: objRules,
      );
      final negativeId = _allocateUniqueId(
        'fix_${slug}_${violation.kind == QaFixtureKind.boundary ? 'borne' : 'invalide'}',
        usedIds,
      );
      final negativeCode =
          'FIX-${(nextCodeIndex++).toString().padLeft(3, '0')}';
      seeded.add(
        QaFixtureSpec(
          id: negativeId,
          code: negativeCode,
          name: '${obj.name} — ${violation.titleSuffix}',
          kind: violation.kind,
          businessObjectId: obj.id,
          personaId: defaultPersonaId,
          businessRuleIds: violation.ruleRefs,
          description: violation.description,
          payload: violation.payload,
          expectedValid: violation.expectedValid,
          expectedErrorHint: violation.expectedErrorHint,
        ),
      );
    }

    // Ajoute également des fixtures concrètes issues des cartes vertes d'Example Mapping
    for (final story in project.exampleMappings) {
      final obj = story.targetObjectId.trim().isEmpty
          ? null
          : project.findBusinessObject(story.targetObjectId);
      if (obj == null) continue;
      final basePayload = _buildNominalPayload(
        project,
        obj,
        visited: <String>{obj.id},
        locale: locale,
      );
      for (final emRule in story.rules) {
        for (final ex in emRule.examples) {
          if (ex.inputValues.isEmpty) continue;
          final slug = SpecStorageSlug.slugify(
            '${story.code}_${ex.title}',
            fallback: 'exemple',
            separator: '_',
          );
          final fixId = _allocateUniqueId('fix_em_$slug', usedIds);
          final alreadyExists = existing.any(
            (f) => f.id == fixId || f.id == ex.linkedFixtureId,
          );
          if (alreadyExists) continue;
          final fixKind = switch (ex.kind) {
            ExampleMapExampleKind.nominal ||
            ExampleMapExampleKind.stateTransition => QaFixtureKind.nominal,
            ExampleMapExampleKind.boundary => QaFixtureKind.boundary,
            ExampleMapExampleKind.error => QaFixtureKind.invalid,
            ExampleMapExampleKind.permission => QaFixtureKind.permission,
          };
          final mergedPayload = <String, Object?>{
            ...basePayload,
            ...ex.inputValues,
          };
          seeded.add(
            QaFixtureSpec(
              id: fixId,
              code: 'FIX-${(nextCodeIndex++).toString().padLeft(3, '0')}',
              name: '${obj.name} (${story.code}) — ${ex.title}',
              kind: fixKind,
              businessObjectId: obj.id,
              personaId: defaultPersonaId,
              businessRuleIds: <String>[
                if (emRule.linkedRuleId.isNotEmpty) emRule.linkedRuleId,
              ],
              description:
                  'Exemple concret issu de l’Example Mapping (${story.code} : ${emRule.title}).',
              payload: mergedPayload,
              expectedValid: ex.kind != ExampleMapExampleKind.error,
              expectedErrorHint: ex.kind == ExampleMapExampleKind.error
                  ? ex.then
                  : '',
            ),
          );
        }
      }
    }

    return List<QaFixtureSpec>.unmodifiable(seeded);
  }

  /// Génère des fonctionnalités Gherkin initiales (`FEAT-...` avec étapes `Given / When / Then`)
  /// pour les parcours UX, cas d'usage et exigences fonctionnelles non encore couverts.
  static List<GherkinFeatureSpec> seedFeaturesFromSpecAndUx(
    SpecForgeProject project,
  ) {
    final qa = project.qaSpec;
    final ux = project.uxSpec;

    final usedFeatureIds = <String>{
      for (final f in qa.features) f.id.toLowerCase(),
    };
    var nextFeatNum = _nextSequentialNumber(
      qa.features.map((f) => f.code),
      prefix: 'FEAT',
    );
    var nextScnNum = _nextSequentialNumber([
      for (final f in qa.features)
        for (final sc in f.scenarios) sc.code,
    ], prefix: 'SCN');

    final coveredUcIds = <String>{};
    final coveredReqIds = <String>{};
    final coveredJrnIds = <String>{};
    final coveredScrIds = <String>{};

    for (final f in qa.features) {
      for (final sc in f.scenarios) {
        for (final uc in project.cahierDesCharges.useCases) {
          if (sc.useCaseIds.any((ref) => _matchesUseCase(uc, ref))) {
            coveredUcIds.add(uc.id);
          }
        }
        for (final req in project.cahierDesCharges.functionalRequirements) {
          if (sc.requirementIds.any((ref) => _matchesRequirement(req, ref))) {
            coveredReqIds.add(req.id);
          }
        }
        for (final jrn in ux.journeys) {
          if (sc.journeyIds.any((ref) => _matchesJourney(jrn, ref))) {
            coveredJrnIds.add(jrn.id);
          }
        }
        for (final scr in ux.screens) {
          if (sc.screenIds.any((ref) => _matchesScreen(scr, ref))) {
            coveredScrIds.add(scr.id);
          }
        }
      }
    }
    for (final s in qa.tddSuites) {
      for (final tc in s.cases) {
        for (final req in project.cahierDesCharges.functionalRequirements) {
          if (tc.requirementIds.any((ref) => _matchesRequirement(req, ref))) {
            coveredReqIds.add(req.id);
          }
        }
        for (final scr in ux.screens) {
          if (tc.screenIds.any((ref) => _matchesScreen(scr, ref))) {
            coveredScrIds.add(scr.id);
          }
        }
      }
    }

    final nominalFixtureRef = qa.fixtures.isNotEmpty
        ? (qa.fixtures.first.code.trim().isNotEmpty
              ? qa.fixtures.first.code.trim()
              : qa.fixtures.first.id)
        : '';

    final seeded = <GherkinFeatureSpec>[];

    // 1. Parcours UX non couverts -> 1 Feature par parcours
    for (final jrn in ux.journeys) {
      if (coveredJrnIds.contains(jrn.id)) continue;
      coveredJrnIds.add(jrn.id);

      final persona = _resolvePersona(project, jrn.personaId);
      final personaLabel = persona?.name ?? 'utilisateur autorisé';
      final jrnRef = jrn.code.trim().isNotEmpty ? jrn.code.trim() : jrn.id;

      final validUcs = <String>[];
      for (final rawUc in jrn.useCaseIds) {
        final uc = _resolveUseCase(project, rawUc);
        if (uc != null) {
          validUcs.add(uc.id);
          coveredUcIds.add(uc.id);
        }
      }

      final validReqs = <String>[];
      for (final rawReq in jrn.requirementIds) {
        final req = _resolveRequirement(project, rawReq);
        if (req != null) {
          validReqs.add(req.code.trim().isNotEmpty ? req.code.trim() : req.id);
          coveredReqIds.add(req.id);
        }
      }

      final linkedScreens = <String>[];
      for (final step in jrn.steps) {
        if (step.targetRouteId.trim().isEmpty) continue;
        for (final scr in ux.screens) {
          if (_screenMatchesRouteRef(project, scr, step.targetRouteId)) {
            final scrRef = scr.code.trim().isNotEmpty
                ? scr.code.trim()
                : scr.id;
            if (!linkedScreens.contains(scrRef)) {
              linkedScreens.add(scrRef);
            }
            coveredScrIds.add(scr.id);
          }
        }
      }

      final scnCode = 'SCN-${(nextScnNum++).toString().padLeft(3, '0')}';
      final slug = SpecStorageSlug.slugify(
        jrn.name,
        fallback: 'parcours',
        separator: '_',
      );
      final steps = _buildStepsFromJourney(jrn, personaLabel: personaLabel);

      final featCode = 'FEAT-${(nextFeatNum++).toString().padLeft(3, '0')}';
      final featId = _allocateUniqueId('feat_jrn_$slug', usedFeatureIds);
      seeded.add(
        GherkinFeatureSpec(
          id: featId,
          code: featCode,
          title: 'Parcours — ${jrn.name}',
          personaId: persona?.id ?? '',
          narrative:
              'En tant que $personaLabel\n'
              'Je veux ${jrn.goal.trim().isNotEmpty ? jrn.goal.trim() : 'compléter le parcours « ${jrn.name} »'}\n'
              'Afin de valider le flux utilisateur $jrnRef sur canal ${jrn.channel.label}',
          tags: <String>[
            '@parcours',
            '@${SpecStorageSlug.slugify(jrnRef, fallback: 'jrn')}',
          ],
          scenarios: <GherkinScenarioSpec>[
            GherkinScenarioSpec(
              id: 'scn_${slug}_nominal',
              code: scnCode,
              title: '${jrn.name} — Exécution nominale de bout en bout',
              tags: const <String>['@nominal'],
              steps: steps,
              journeyIds: <String>[jrnRef],
              useCaseIds: validUcs,
              requirementIds: validReqs,
              screenIds: linkedScreens,
              fixtureIds: <String>[
                if (nominalFixtureRef.isNotEmpty) nominalFixtureRef,
              ],
            ),
          ],
        ),
      );
    }

    // 2. Cas d'usage non encore couverts
    for (final uc in project.cahierDesCharges.useCases) {
      if (coveredUcIds.contains(uc.id)) continue;
      coveredUcIds.add(uc.id);

      final persona = _resolvePersona(project, uc.actorId);
      final actorName =
          persona?.name ??
          (uc.actorId.trim().isNotEmpty ? uc.actorId.trim() : 'utilisateur');
      final slug = SpecStorageSlug.slugify(
        uc.title,
        fallback: 'cas_usage',
        separator: '_',
      );

      final linkedScreens = <String>[];
      for (final scr in ux.screens) {
        if (scr.useCaseIds.any((ref) => _matchesUseCase(uc, ref))) {
          linkedScreens.add(
            scr.code.trim().isNotEmpty ? scr.code.trim() : scr.id,
          );
          coveredScrIds.add(scr.id);
        }
      }

      final scenarios = <GherkinScenarioSpec>[
        GherkinScenarioSpec(
          id: 'scn_uc_${slug}_nominal',
          code: 'SCN-${(nextScnNum++).toString().padLeft(3, '0')}',
          title: '${uc.title} — Flux nominal',
          tags: const <String>['@nominal'],
          steps: _buildNominalStepsFromUseCase(uc, actorName: actorName),
          useCaseIds: <String>[uc.id],
          screenIds: linkedScreens,
          fixtureIds: <String>[
            if (nominalFixtureRef.isNotEmpty) nominalFixtureRef,
          ],
        ),
        if (uc.alternativeFlows.isNotEmpty)
          GherkinScenarioSpec(
            id: 'scn_uc_${slug}_alternatif',
            code: 'SCN-${(nextScnNum++).toString().padLeft(3, '0')}',
            title: '${uc.title} — Cas alternatif ou d’exception',
            tags: const <String>['@alternatif'],
            steps: <GherkinStep>[
              GherkinStep(
                id: 'step_alt_given',
                keyword: GherkinStepKeyword.given,
                text: uc.preconditions.isNotEmpty
                    ? uc.preconditions.first
                    : 'que l’acteur « $actorName » accède au cas d’usage « ${uc.title} »',
              ),
              GherkinStep(
                id: 'step_alt_when',
                keyword: GherkinStepKeyword.when,
                text:
                    'une condition particulière survient lors de « ${uc.title} »',
              ),
              GherkinStep(
                id: 'step_alt_then',
                keyword: GherkinStepKeyword.then,
                text: uc.alternativeFlows.first,
              ),
            ],
            useCaseIds: <String>[uc.id],
            screenIds: linkedScreens,
          ),
      ];

      final featCode = 'FEAT-${(nextFeatNum++).toString().padLeft(3, '0')}';
      final featId = _allocateUniqueId('feat_uc_$slug', usedFeatureIds);
      seeded.add(
        GherkinFeatureSpec(
          id: featId,
          code: featCode,
          title: uc.title,
          personaId: persona?.id ?? '',
          narrative:
              'En tant que $actorName\n'
              'Je veux réaliser « ${uc.title} »\n'
              'Afin de satisfaire les postconditions métier attendues',
          tags: <String>[
            '@cas-usage',
            '@${SpecStorageSlug.slugify(uc.id, fallback: 'uc')}',
          ],
          scenarios: scenarios,
        ),
      );
    }

    // 3. Exigences fonctionnelles Must / Should non couvertes (regroupées par module)
    final uncoveredPriorityReqs = [
      for (final req in project.cahierDesCharges.functionalRequirements)
        if (!coveredReqIds.contains(req.id) &&
            (req.priority == RequirementPriority.must ||
                req.priority == RequirementPriority.should))
          req,
    ];
    final reqsToSeed =
        uncoveredPriorityReqs.isNotEmpty ||
            seeded.isNotEmpty ||
            qa.features.isNotEmpty
        ? uncoveredPriorityReqs
        : [
            for (final req in project.cahierDesCharges.functionalRequirements)
              if (!coveredReqIds.contains(req.id)) req,
          ];

    if (reqsToSeed.isNotEmpty) {
      final byModuleKey = <String, List<FunctionalRequirement>>{};
      for (final req in reqsToSeed) {
        final mod = _resolveModule(project, req.moduleId);
        final key = mod?.id ?? '';
        (byModuleKey[key] ??= <FunctionalRequirement>[]).add(req);
      }

      for (final entry in byModuleKey.entries) {
        final module = entry.key.isEmpty
            ? null
            : _resolveModule(project, entry.key);
        final groupReqs = entry.value;
        final groupTitle = module != null
            ? module.name
            : 'Exigences fonctionnelles — ${project.name}';
        final groupSlug = SpecStorageSlug.slugify(
          module?.id ?? 'exigences',
          fallback: 'exigences',
          separator: '_',
        );

        final scenarios = <GherkinScenarioSpec>[];
        for (var i = 0; i < groupReqs.length; i++) {
          final req = groupReqs[i];
          coveredReqIds.add(req.id);
          final reqRef = req.code.trim().isNotEmpty ? req.code.trim() : req.id;
          final actor = req.actorIds
              .map((aid) => _resolvePersona(project, aid))
              .whereType<SpecPersona>()
              .firstOrNull;
          final actorLabel = actor?.name ?? 'l’utilisateur habilité';

          final linkedScreens = <String>[];
          for (final scr in ux.screens) {
            if (scr.requirementIds.any(
              (ref) => _matchesRequirement(req, ref),
            )) {
              linkedScreens.add(
                scr.code.trim().isNotEmpty ? scr.code.trim() : scr.id,
              );
              coveredScrIds.add(scr.id);
            }
          }

          final criteria = req.acceptanceCriteria;
          final thenText = criteria.isNotEmpty
              ? criteria.first
              : (req.description.trim().isNotEmpty
                    ? req.description.trim()
                    : 'l’exigence $reqRef (« ${req.title} ») est vérifiée');

          scenarios.add(
            GherkinScenarioSpec(
              id: 'scn_req_${SpecStorageSlug.slugify(req.id, fallback: '${i + 1}', separator: '_')}',
              code: 'SCN-${(nextScnNum++).toString().padLeft(3, '0')}',
              title: '$reqRef — ${req.title}',
              tags: <String>[
                '@${SpecStorageSlug.slugify(reqRef, fallback: 'exf')}',
                '@${req.priority.name}',
              ],
              steps: <GherkinStep>[
                GherkinStep(
                  id: 'step_given',
                  keyword: GherkinStepKeyword.given,
                  text:
                      'que $actorLabel dispose d’un contexte valide dans l’application',
                ),
                GherkinStep(
                  id: 'step_when',
                  keyword: GherkinStepKeyword.when,
                  text:
                      'il sollicite la fonctionnalité relative à « ${req.title} »',
                ),
                GherkinStep(
                  id: 'step_then',
                  keyword: GherkinStepKeyword.then,
                  text: thenText,
                ),
                for (var c = 1; c < criteria.length && c < 3; c++)
                  GherkinStep(
                    id: 'step_and_$c',
                    keyword: GherkinStepKeyword.and,
                    text: criteria[c],
                  ),
              ],
              requirementIds: <String>[reqRef],
              screenIds: linkedScreens,
              fixtureIds: <String>[
                if (nominalFixtureRef.isNotEmpty) nominalFixtureRef,
              ],
            ),
          );
        }

        final featCode = 'FEAT-${(nextFeatNum++).toString().padLeft(3, '0')}';
        final featId = _allocateUniqueId('feat_mod_$groupSlug', usedFeatureIds);
        seeded.add(
          GherkinFeatureSpec(
            id: featId,
            code: featCode,
            title: groupTitle,
            moduleId: module?.id ?? '',
            narrative:
                'En tant qu’utilisateur métier\n'
                'Je veux disposer des capacités du périmètre « $groupTitle »\n'
                'Afin de satisfaire les critères d’acceptation du cahier des charges',
            tags: <String>['@exigences', '@$groupSlug'],
            scenarios: scenarios,
          ),
        );
      }
    }

    // 4. Écrans UX restants non encore rattachés à un scénario
    final remainingScreens = [
      for (final scr in ux.screens)
        if (!coveredScrIds.contains(scr.id)) scr,
    ];
    if (remainingScreens.isNotEmpty) {
      final scenarios = <GherkinScenarioSpec>[];
      for (var i = 0; i < remainingScreens.length; i++) {
        final scr = remainingScreens[i];
        final scrRef = scr.code.trim().isNotEmpty ? scr.code.trim() : scr.id;
        final route = scr.routeId.trim().isEmpty
            ? null
            : ux.navigation.findRoute(scr.routeId);
        final routeLabel =
            route?.path ??
            (scr.routeId.trim().isEmpty ? '/' : scr.routeId.trim());
        scenarios.add(
          GherkinScenarioSpec(
            id: 'scn_scr_${SpecStorageSlug.slugify(scr.id, fallback: '${i + 1}', separator: '_')}',
            code: 'SCN-${(nextScnNum++).toString().padLeft(3, '0')}',
            title: '$scrRef — Affichage et interactions de « ${scr.name} »',
            tags: const <String>['@ux', '@ecran'],
            steps: <GherkinStep>[
              GherkinStep(
                id: 'step_scr_given',
                keyword: GherkinStepKeyword.given,
                text:
                    'que les données initiales de l’écran « ${scr.name} » sont disponibles',
              ),
              GherkinStep(
                id: 'step_scr_when',
                keyword: GherkinStepKeyword.when,
                text:
                    'l’utilisateur ouvre la vue « ${scr.name} » sur la route "$routeLabel"',
              ),
              GherkinStep(
                id: 'step_scr_then',
                keyword: GherkinStepKeyword.then,
                text:
                    'l’écran affiche le pattern ${scr.pattern.label} avec ses zones actives et actions conformes',
              ),
            ],
            screenIds: <String>[scrRef],
            fixtureIds: <String>[
              if (nominalFixtureRef.isNotEmpty) nominalFixtureRef,
            ],
          ),
        );
      }
      final featCode = 'FEAT-${(nextFeatNum++).toString().padLeft(3, '0')}';
      final featId = _allocateUniqueId('feat_ux_screens', usedFeatureIds);
      seeded.add(
        GherkinFeatureSpec(
          id: featId,
          code: featCode,
          title: 'Écrans & Navigation UX — ${project.name}',
          narrative:
              'En tant qu’utilisateur de l’interface\n'
              'Je veux consulter et manipuler chaque écran applicatif\n'
              'Afin de vérifier le rendu et les comportements UX spécifiés',
          tags: const <String>['@ux'],
          scenarios: scenarios,
        ),
      );
    }

    // 5. Tableaux d'Example Mapping -> Features Gherkin avec Scénarios / Exemples
    for (final story in project.exampleMappings) {
      if (story.rules.every((r) => r.examples.isEmpty)) continue;
      final storySlug = SpecStorageSlug.slugify(
        story.code.trim().isNotEmpty ? story.code : story.id,
        fallback: 'em',
        separator: '_',
      );
      final featId = 'feat_em_$storySlug';
      if (usedFeatureIds.contains(featId.toLowerCase()) ||
          qa.features.any(
            (f) =>
                f.id == featId ||
                f.tags.any((t) => t.toLowerCase() == '@$storySlug'),
          )) {
        continue;
      }

      final scenarios = <GherkinScenarioSpec>[];
      for (final emRule in story.rules) {
        if (emRule.examples.isEmpty) continue;
        final ruleSlug = SpecStorageSlug.slugify(
          emRule.id,
          fallback: 'rule',
          separator: '_',
        );
        final sharedInputKeys = emRule.examples.length >= 2
            ? emRule.examples
                  .map((e) => e.inputValues.keys.toSet())
                  .reduce((a, b) => a.intersection(b))
                  .toList()
            : const <String>[];
        final sharedOutKeys = emRule.examples.length >= 2
            ? emRule.examples
                  .map((e) => e.expectedOutcome.keys.toSet())
                  .reduce((a, b) => a.intersection(b))
                  .toList()
            : const <String>[];

        if (sharedInputKeys.isNotEmpty || sharedOutKeys.isNotEmpty) {
          final columns = <String>[
            'cas',
            ...sharedInputKeys,
            ...sharedOutKeys.where((k) => !sharedInputKeys.contains(k)),
          ];
          final rows = <List<String>>[
            for (final ex in emRule.examples)
              <String>[
                ex.title,
                for (final k in sharedInputKeys) '${ex.inputValues[k] ?? ''}',
                for (final k in sharedOutKeys.where(
                  (k) => !sharedInputKeys.contains(k),
                ))
                  '${ex.expectedOutcome[k] ?? ''}',
              ],
          ];
          final inputPlaceholders = sharedInputKeys
              .map((k) => '$k vaut <$k>')
              .join(', ');
          final outPlaceholders = sharedOutKeys
              .map((k) => '$k vaut <$k>')
              .join(', ');
          scenarios.add(
            GherkinScenarioSpec(
              id: 'scn_em_${storySlug}_$ruleSlug',
              code: 'SCN-${(nextScnNum++).toString().padLeft(3, '0')}',
              title: '${emRule.title} (<cas>)',
              isOutline: true,
              tags: <String>[
                '@$storySlug',
                if (emRule.linkedRuleId.isNotEmpty)
                  '@${SpecStorageSlug.slugify(emRule.linkedRuleId, fallback: 'rg')}',
              ],
              steps: <GherkinStep>[
                GherkinStep(
                  id: 'step_em_given',
                  keyword: GherkinStepKeyword.given,
                  text: inputPlaceholders.isNotEmpty
                      ? 'que les données initiales vérifient $inputPlaceholders'
                      : (emRule.examples.first.given.isNotEmpty
                            ? emRule.examples.first.given
                            : 'que le contexte métier « ${story.title} » est initialisé'),
                ),
                GherkinStep(
                  id: 'step_em_when',
                  keyword: GherkinStepKeyword.when,
                  text: emRule.examples.first.when.isNotEmpty
                      ? emRule.examples.first.when
                      : 'la règle « ${emRule.title} » est évaluée',
                ),
                GherkinStep(
                  id: 'step_em_then',
                  keyword: GherkinStepKeyword.then,
                  text: outPlaceholders.isNotEmpty
                      ? 'le résultat attendu vérifie $outPlaceholders'
                      : (emRule.examples.first.then.isNotEmpty
                            ? emRule.examples.first.then
                            : 'le comportement est conforme à la règle'),
                ),
              ],
              examples: GherkinExamplesTable(headers: columns, rows: rows),
              businessRuleIds: <String>[
                if (emRule.linkedRuleId.isNotEmpty) emRule.linkedRuleId,
              ],
              requirementIds: story.requirementIds,
              useCaseIds: <String>[
                if (story.useCaseId.isNotEmpty) story.useCaseId,
              ],
            ),
          );
        } else {
          for (var i = 0; i < emRule.examples.length; i++) {
            final ex = emRule.examples[i];
            final exSlug = SpecStorageSlug.slugify(
              ex.id,
              fallback: '${i + 1}',
              separator: '_',
            );
            scenarios.add(
              GherkinScenarioSpec(
                id: 'scn_em_${storySlug}_$exSlug',
                code: 'SCN-${(nextScnNum++).toString().padLeft(3, '0')}',
                title: '${emRule.title} — ${ex.title}',
                tags: <String>[
                  '@$storySlug',
                  '@${ex.kind.name}',
                  if (emRule.linkedRuleId.isNotEmpty)
                    '@${SpecStorageSlug.slugify(emRule.linkedRuleId, fallback: 'rg')}',
                ],
                steps: <GherkinStep>[
                  GherkinStep(
                    id: 'step_em_given',
                    keyword: GherkinStepKeyword.given,
                    text: ex.given.isNotEmpty
                        ? ex.given
                        : 'que le contexte métier de « ${story.title} » est prêt',
                  ),
                  GherkinStep(
                    id: 'step_em_when',
                    keyword: GherkinStepKeyword.when,
                    text: ex.when.isNotEmpty
                        ? ex.when
                        : 'l’action associée à « ${emRule.title} » est exécutée',
                  ),
                  GherkinStep(
                    id: 'step_em_then',
                    keyword: GherkinStepKeyword.then,
                    text: ex.then.isNotEmpty
                        ? ex.then
                        : 'le résultat « ${ex.title} » est vérifié',
                  ),
                ],
                businessRuleIds: <String>[
                  if (emRule.linkedRuleId.isNotEmpty) emRule.linkedRuleId,
                ],
                requirementIds: story.requirementIds,
                useCaseIds: <String>[
                  if (story.useCaseId.isNotEmpty) story.useCaseId,
                ],
              ),
            );
          }
        }
      }

      if (scenarios.isNotEmpty) {
        usedFeatureIds.add(featId.toLowerCase());
        seeded.add(
          GherkinFeatureSpec(
            id: featId,
            code: 'FEAT-${(nextFeatNum++).toString().padLeft(3, '0')}',
            title: '${story.code} — ${story.title}',
            narrative:
                'En tant qu’utilisateur métier\n'
                'Je veux valider par des exemples concrets le périmètre « ${story.title} »\n'
                'Afin de garantir les règles métier découvertes en Example Mapping',
            tags: <String>['@example-mapping', '@$storySlug'],
            scenarios: scenarios,
          ),
        );
      }
    }

    return List<GherkinFeatureSpec>.unmodifiable(seeded);
  }

  /// Génère des suites de tests unitaires TDD initiales (`TDD-...` avec cas `TC-...`
  /// nominaux et d'erreur en progression *Red → Green → Refactor*) pour les règles
  /// de gestion actives (`RG-xxx`) non encore couvertes par une suite TDD.
  static List<TddTestSuiteSpec> seedTddSuitesFromRules(
    SpecForgeProject project,
  ) {
    final qa = project.qaSpec;
    final usedSuiteIds = <String>{
      for (final s in qa.tddSuites) s.id.toLowerCase(),
    };
    var nextSuiteNum = _nextSequentialNumber(
      qa.tddSuites.map((s) => s.code),
      prefix: 'TDD',
    );
    var nextCaseNum = _nextSequentialNumber([
      for (final s in qa.tddSuites)
        for (final tc in s.cases) tc.code,
    ], prefix: 'TC');

    final uncoveredRules = [
      for (final rule in project.businessRules)
        if (rule.active &&
            !qa.tddSuites.any(
              (s) => s.cases.any(
                (tc) =>
                    tc.businessRuleIds.any((ref) => _matchesRule(rule, ref)),
              ),
            ))
          rule,
    ];
    if (uncoveredRules.isEmpty) {
      return const <TddTestSuiteSpec>[];
    }

    final grouped =
        <
          String,
          ({
            BusinessObjectSpec? targetObject,
            TddTargetLayer layer,
            List<BusinessRuleSpec> rules,
          })
        >{};

    for (final rule in uncoveredRules) {
      final targetObj = rule.targetObjectIds
          .map(project.findBusinessObject)
          .whereType<BusinessObjectSpec>()
          .firstOrNull;
      final layer = _mapCategoryToLayer(rule.category);
      final groupKey = '${targetObj?.id ?? '_global'}::${layer.name}';
      final bucket = grouped.putIfAbsent(
        groupKey,
        () => (
          targetObject: targetObj,
          layer: layer,
          rules: <BusinessRuleSpec>[],
        ),
      );
      bucket.rules.add(rule);
    }

    final seeded = <TddTestSuiteSpec>[];

    for (final bucket in grouped.values) {
      final obj = bucket.targetObject;
      final layer = bucket.layer;
      final suiteSlug = SpecStorageSlug.slugify(
        '${obj?.technicalName ?? 'domaine'}_${layer.name}',
        fallback: 'suite',
        separator: '_',
      );
      final suiteId = _allocateUniqueId('tdd_$suiteSlug', usedSuiteIds);
      final suiteCode = 'TDD-${(nextSuiteNum++).toString().padLeft(3, '0')}';
      final suiteName = obj != null
          ? '${obj.name} — ${layer.label}'
          : '${layer.label} — ${project.name}';

      final nominalFixture = obj == null
          ? null
          : qa.fixtures
                .where(
                  (f) =>
                      f.expectedValid &&
                      f.businessObjectId.trim().isNotEmpty &&
                      _matchesBusinessObject(obj, f.businessObjectId),
                )
                .firstOrNull;
      final invalidFixture = obj == null
          ? null
          : qa.fixtures
                .where(
                  (f) =>
                      !f.expectedValid &&
                      f.businessObjectId.trim().isNotEmpty &&
                      _matchesBusinessObject(obj, f.businessObjectId),
                )
                .firstOrNull;

      final cases = <TddTestCaseSpec>[];
      var order = 1;

      for (final rule in bucket.rules) {
        final ruleRef = rule.code.trim().isNotEmpty
            ? rule.code.trim()
            : rule.id;
        final ruleSlug = SpecStorageSlug.slugify(
          ruleRef,
          fallback: 'rg_$order',
          separator: '_',
        );

        final linkedScreens = <String>[];
        for (final scr in project.uxSpec.screens) {
          final scrHasRule =
              scr.actions.any(
                (a) => a.businessRuleIds.any((ref) => _matchesRule(rule, ref)),
              ) ||
              scr.states.readOnlyRuleIds.any((ref) => _matchesRule(rule, ref));
          if (scrHasRule) {
            linkedScreens.add(
              scr.code.trim().isNotEmpty ? scr.code.trim() : scr.id,
            );
          }
        }

        final nominalOutcome = switch (rule.category) {
          BusinessRuleCategory.calculation =>
            TddExpectedOutcomeKind.returnsValue,
          BusinessRuleCategory.stateTransition ||
          BusinessRuleCategory.trigger => TddExpectedOutcomeKind.mutatesState,
          BusinessRuleCategory.permission =>
            TddExpectedOutcomeKind.allowsAction,
          BusinessRuleCategory.validation =>
            TddExpectedOutcomeKind.returnsValue,
        };

        final actText = rule.trigger.trim().isNotEmpty
            ? rule.trigger.trim()
            : 'Exécuter l’opération soumise à la règle $ruleRef (« ${rule.title} »)';
        final nominalAssert = rule.effect.trim().isNotEmpty
            ? rule.effect.trim()
            : 'La règle $ruleRef est respectée et produit l’état conforme attendu.';

        // Cas 1 : Cas nominal (Green baseline)
        cases.add(
          TddTestCaseSpec(
            id: 'tc_${ruleSlug}_nominal_$order',
            code: 'TC-${(nextCaseNum++).toString().padLeft(3, '0')}',
            order: order++,
            title: '$ruleRef — Cas nominal conforme : ${rule.title}',
            fixtureId: nominalFixture != null
                ? (nominalFixture.code.trim().isNotEmpty
                      ? nominalFixture.code.trim()
                      : nominalFixture.id)
                : '',
            arrange: rule.condition.trim().isNotEmpty
                ? 'Préparer une instance conforme de ${obj?.technicalName ?? 'domaine'} respectant : ${rule.condition.trim()}'
                : 'Préparer une instance nominale valide de ${obj?.technicalName ?? 'domaine'}',
            act: actText,
            outcomeKind: nominalOutcome,
            assertExpected: nominalAssert,
            businessRuleIds: <String>[ruleRef],
            screenIds: linkedScreens,
          ),
        );

        // Cas 2 : Cas de rejet / violation ou garde-fou aux bornes
        final negativeOutcome = rule.category == BusinessRuleCategory.permission
            ? TddExpectedOutcomeKind.deniesAction
            : TddExpectedOutcomeKind.rejectsWithError;
        final errorMsg = rule.errorMessage.trim().isNotEmpty
            ? rule.errorMessage.trim()
            : 'Violation de la règle $ruleRef (${rule.title})';

        cases.add(
          TddTestCaseSpec(
            id: 'tc_${ruleSlug}_rejet_$order',
            code: 'TC-${(nextCaseNum++).toString().padLeft(3, '0')}',
            order: order++,
            title: '$ruleRef — Rejet sur non-respect : ${rule.title}',
            fixtureId: invalidFixture != null
                ? (invalidFixture.code.trim().isNotEmpty
                      ? invalidFixture.code.trim()
                      : invalidFixture.id)
                : '',
            arrange: rule.condition.trim().isNotEmpty
                ? 'Préparer un contexte enfreignant la condition de $ruleRef (${rule.condition.trim()})'
                : 'Préparer une entrée hors contrat ou non autorisée pour $ruleRef',
            act: actText,
            outcomeKind: negativeOutcome,
            assertExpected:
                'L’exécution est bloquée sans corruption d’état conformément à $ruleRef.',
            expectedErrorMessage: errorMsg,
            businessRuleIds: <String>[ruleRef],
            screenIds: linkedScreens,
          ),
        );
      }

      seeded.add(
        TddTestSuiteSpec(
          id: suiteId,
          code: suiteCode,
          name: suiteName,
          layer: layer,
          targetObjectId: obj?.id ?? '',
          description:
              'Suite TDD générée en progression Red → Green → Refactor couvrant ${bucket.rules.length} règle(s) de gestion.',
          cases: cases,
        ),
      );
    }

    return List<TddTestSuiteSpec>.unmodifiable(seeded);
  }

  static Map<String, Object?> _buildNominalPayload(
    SpecForgeProject project,
    BusinessObjectSpec obj, {
    required Set<String> visited,
    required ModelLocaleProfile locale,
  }) {
    final map = <String, Object?>{};
    final initialState =
        obj.lifecycleStates.where((s) => s.isInitial).firstOrNull?.name ??
        (obj.lifecycleStates.isNotEmpty
            ? obj.lifecycleStates.first.name
            : null);

    for (final attr in obj.attributes) {
      if (attr.isArray) {
        final minItems = attr.schemaConstraints.minItems ?? 1;
        final count = minItems < 1 ? 1 : (minItems > 3 ? 3 : minItems);
        map[attr.name] = <Object?>[
          for (var i = 0; i < count; i++)
            _nominalValueForAttribute(
              attr,
              index: i,
              locale: locale,
              initialState: initialState,
            ),
        ];
      } else {
        map[attr.name] = _nominalValueForAttribute(
          attr,
          locale: locale,
          initialState: initialState,
        );
      }
    }

    for (final rel in obj.relations) {
      final target = project.findBusinessObject(rel.targetObjectId);
      final isList =
          rel.cardinality == BusinessRelationCardinality.oneToMany ||
          rel.cardinality == BusinessRelationCardinality.manyToMany;
      final Object itemValue = (target != null && !visited.contains(target.id))
          ? _buildNominalPayload(
              project,
              target,
              visited: <String>{...visited, target.id},
              locale: locale,
            )
          : 'ref_001';
      map[rel.name] = isList ? <Object?>[itemValue] : itemValue;
    }

    if (map.isEmpty) {
      map['id'] = '00000000-0000-4000-8000-000000000001';
    }
    return map;
  }

  static Object? _nominalValueForAttribute(
    BusinessAttribute attr, {
    int index = 0,
    required ModelLocaleProfile locale,
    String? initialState,
  }) {
    final sc = attr.schemaConstraints;
    if (sc.hasConst) return sc.constValue;
    if (sc.examples.isNotEmpty && index < sc.examples.length) {
      return sc.examples[index];
    }
    if (attr.type == BusinessAttributeType.object && attr.children.isNotEmpty) {
      return <String, Object?>{
        for (final child in attr.children)
          child.name: child.isArray
              ? <Object?>[
                  _nominalValueForAttribute(
                    child,
                    index: index,
                    locale: locale,
                  ),
                ]
              : _nominalValueForAttribute(child, index: index, locale: locale),
      };
    }
    if (index == 0 &&
        attr.defaultValue != null &&
        attr.defaultValue!.trim().isNotEmpty) {
      return _coerceDefaultValue(attr, attr.defaultValue!.trim());
    }

    final lowerName = attr.name.toLowerCase();
    if (initialState != null &&
        (lowerName == 'status' ||
            lowerName == 'statut' ||
            lowerName == 'state' ||
            lowerName == 'etat') &&
        (attr.type == BusinessAttributeType.string ||
            (attr.type == BusinessAttributeType.enumeration &&
                (attr.enumValues.isEmpty ||
                    attr.enumValues.contains(initialState))))) {
      return initialState;
    }

    return switch (attr.type) {
      BusinessAttributeType.string => _nominalString(attr, index: index),
      BusinessAttributeType.integer => _nominalInt(sc, index: index),
      BusinessAttributeType.number => _nominalDouble(sc, index: index),
      BusinessAttributeType.boolean => index.isEven,
      BusinessAttributeType.date =>
        '2026-03-${(10 + (index % 18)).toString().padLeft(2, '0')}',
      BusinessAttributeType.datetime =>
        '2026-03-${(10 + (index % 18)).toString().padLeft(2, '0')}T09:30:00Z',
      BusinessAttributeType.uuid =>
        '00000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
      BusinessAttributeType.email => locale.sampleEmail,
      BusinessAttributeType.url => locale.sampleUrl,
      BusinessAttributeType.enumeration =>
        attr.enumValues.isNotEmpty
            ? attr.enumValues[index % attr.enumValues.length]
            : 'val_${index + 1}',
      BusinessAttributeType.reference =>
        'ref_${(index + 1).toString().padLeft(3, '0')}',
      BusinessAttributeType.object ||
      BusinessAttributeType.json => const <String, Object?>{},
    };
  }

  static Object _coerceDefaultValue(BusinessAttribute attr, String raw) =>
      switch (attr.type) {
        BusinessAttributeType.integer => int.tryParse(raw) ?? 1,
        BusinessAttributeType.number => double.tryParse(raw) ?? 1.0,
        BusinessAttributeType.boolean =>
          raw.toLowerCase() == 'true' || raw == '1',
        _ => raw,
      };

  static String _nominalString(BusinessAttribute attr, {int index = 0}) {
    final minLen = attr.schemaConstraints.minLength ?? 0;
    final maxLen = attr.schemaConstraints.maxLength;
    var value = index == 0
        ? 'Exemple ${attr.name}'
        : 'Exemple ${attr.name} ${index + 1}';
    if (minLen > value.length) {
      value = value.padRight(minLen, 'x');
    }
    if (maxLen != null && value.length > maxLen) {
      value = value.substring(0, maxLen);
    }
    return value;
  }

  static int _nominalInt(JsonSchemaConstraints sc, {int index = 0}) {
    final low =
        sc.minimum?.ceil() ??
        (sc.exclusiveMinimum != null ? sc.exclusiveMinimum!.floor() + 1 : 1);
    final step = sc.multipleOf?.round();
    if (step != null && step > 0) {
      final rem = low % step;
      final aligned = rem == 0 ? low : low + (step - rem);
      final candidate = aligned + (index * step);
      return (sc.maximum != null && candidate > sc.maximum!)
          ? aligned
          : candidate;
    }
    final candidate = low + index;
    return (sc.maximum != null && candidate > sc.maximum!) ? low : candidate;
  }

  static double _nominalDouble(JsonSchemaConstraints sc, {int index = 0}) {
    final low =
        sc.minimum?.toDouble() ??
        (sc.exclusiveMinimum != null
            ? sc.exclusiveMinimum!.toDouble() + 1.0
            : 10.0);
    final step = sc.multipleOf?.toDouble() ?? 1.0;
    final candidate = low + (index * step);
    return (sc.maximum != null && candidate > sc.maximum!) ? low : candidate;
  }

  static _FixtureViolationMutation _buildViolationMutation(
    BusinessObjectSpec obj, {
    required Map<String, Object?> basePayload,
    required List<BusinessRuleSpec> matchingRules,
  }) {
    final validationRules = matchingRules
        .where((r) => r.category == BusinessRuleCategory.validation)
        .toList();
    final chosenRule = validationRules.isNotEmpty
        ? validationRules.first
        : (matchingRules.isNotEmpty ? matchingRules.first : null);
    final ruleRefs = <String>[
      if (chosenRule != null)
        chosenRule.code.trim().isNotEmpty
            ? chosenRule.code.trim()
            : chosenRule.id,
    ];

    final mutated = Map<String, Object?>.from(basePayload);

    // 1. Violation de borne numérique (minimum / exclusiveMinimum / maximum / exclusiveMaximum)
    for (final attr in obj.attributes) {
      if (attr.isArray) continue;
      final sc = attr.schemaConstraints;
      if (sc.minimum != null) {
        final invalidNum = attr.type == BusinessAttributeType.integer
            ? sc.minimum!.floor() - 1
            : sc.minimum!.toDouble() - 1.0;
        mutated[attr.name] = invalidNum;
        return _FixtureViolationMutation(
          kind: QaFixtureKind.invalid,
          titleSuffix: 'Hors borne minimale sur ${attr.name}',
          description:
              'Vérifie le rejet lorsque « ${attr.name} » ($invalidNum) est inférieur à minimum (${sc.minimum}).',
          payload: mutated,
          expectedValid: false,
          expectedErrorHint:
              'La valeur de « ${attr.name} » doit être supérieure ou égale à ${sc.minimum}.',
          ruleRefs: ruleRefs,
        );
      }
      if (sc.exclusiveMinimum != null) {
        mutated[attr.name] = sc.exclusiveMinimum;
        return _FixtureViolationMutation(
          kind: QaFixtureKind.boundary,
          titleSuffix: 'Borne exclusive atteinte sur ${attr.name}',
          description:
              'Vérifie le rejet à la borne exclusive « ${attr.name} » = ${sc.exclusiveMinimum}.',
          payload: mutated,
          expectedValid: false,
          expectedErrorHint:
              'La valeur de « ${attr.name} » doit être strictement supérieure à ${sc.exclusiveMinimum}.',
          ruleRefs: ruleRefs,
        );
      }
      if (sc.maximum != null) {
        final invalidNum = attr.type == BusinessAttributeType.integer
            ? sc.maximum!.ceil() + 1
            : sc.maximum!.toDouble() + 1.0;
        mutated[attr.name] = invalidNum;
        return _FixtureViolationMutation(
          kind: QaFixtureKind.invalid,
          titleSuffix: 'Dépassement du maximum sur ${attr.name}',
          description:
              'Vérifie le rejet lorsque « ${attr.name} » ($invalidNum) dépasse maximum (${sc.maximum}).',
          payload: mutated,
          expectedValid: false,
          expectedErrorHint:
              'La valeur de « ${attr.name} » ne peut pas dépasser ${sc.maximum}.',
          ruleRefs: ruleRefs,
        );
      }
      if (sc.exclusiveMaximum != null) {
        mutated[attr.name] = sc.exclusiveMaximum;
        return _FixtureViolationMutation(
          kind: QaFixtureKind.boundary,
          titleSuffix: 'Borne maximale exclusive atteinte sur ${attr.name}',
          description:
              'Vérifie le rejet à la borne exclusive « ${attr.name} » = ${sc.exclusiveMaximum}.',
          payload: mutated,
          expectedValid: false,
          expectedErrorHint:
              'La valeur de « ${attr.name} » doit être strictement inférieure à ${sc.exclusiveMaximum}.',
          ruleRefs: ruleRefs,
        );
      }
    }

    // 2. Violation de minLength, pattern ou enumValues
    for (final attr in obj.attributes) {
      if (attr.isArray) continue;
      final sc = attr.schemaConstraints;
      if (sc.minLength != null && sc.minLength! > 0) {
        mutated[attr.name] = '';
        return _FixtureViolationMutation(
          kind: QaFixtureKind.invalid,
          titleSuffix: 'Chaîne trop courte sur ${attr.name}',
          description:
              'Vérifie le rejet lorsque « ${attr.name} » est vide alors que minLength = ${sc.minLength}.',
          payload: mutated,
          expectedValid: false,
          expectedErrorHint:
              'Le champ « ${attr.name} » doit contenir au moins ${sc.minLength} caractère(s).',
          ruleRefs: ruleRefs,
        );
      }
      if (sc.pattern != null && sc.pattern!.isNotEmpty) {
        mutated[attr.name] = '@@@FORMAT_INVALIDE@@@';
        return _FixtureViolationMutation(
          kind: QaFixtureKind.invalid,
          titleSuffix: 'Format non conforme sur ${attr.name}',
          description:
              'Vérifie le rejet lorsque « ${attr.name} » ne respecte pas l’expression régulière `${sc.pattern}`.',
          payload: mutated,
          expectedValid: false,
          expectedErrorHint:
              'Le format du champ « ${attr.name} » est invalide (motif attendu : ${sc.pattern}).',
          ruleRefs: ruleRefs,
        );
      }
      if (attr.type == BusinessAttributeType.enumeration &&
          attr.enumValues.isNotEmpty) {
        mutated[attr.name] = '__VALEUR_HORS_NOMENCLATURE__';
        return _FixtureViolationMutation(
          kind: QaFixtureKind.invalid,
          titleSuffix: 'Valeur hors énumération sur ${attr.name}',
          description:
              'Vérifie le rejet d’une valeur absente de [${attr.enumValues.join(', ')}] sur « ${attr.name} ».',
          payload: mutated,
          expectedValid: false,
          expectedErrorHint:
              'Valeur non autorisée pour « ${attr.name} » (attendu : ${attr.enumValues.join(', ')}).',
          ruleRefs: ruleRefs,
        );
      }
    }

    // 3. Omission d'un champ obligatoire (required)
    for (final attr in obj.attributes) {
      if (attr.required) {
        mutated.remove(attr.name);
        return _FixtureViolationMutation(
          kind: QaFixtureKind.invalid,
          titleSuffix: 'Champ obligatoire manquant (${attr.name})',
          description:
              'Vérifie le rejet lorsque l’attribut obligatoire « ${attr.name} » est absent de la charge JSON.',
          payload: mutated,
          expectedValid: false,
          expectedErrorHint:
              'Le champ obligatoire « ${attr.name} » est requis.',
          ruleRefs: ruleRefs,
        );
      }
    }

    // 4. Repli générique invalide
    final fallbackHint =
        chosenRule != null && chosenRule.errorMessage.trim().isNotEmpty
        ? chosenRule.errorMessage.trim()
        : 'Données invalides ou incomplètes pour ${obj.technicalName}.';
    return _FixtureViolationMutation(
      kind: QaFixtureKind.invalid,
      titleSuffix: 'Cas d’erreur / contrat invalide',
      description:
          'Jeu de données négatif destiné à vérifier le rejet des entrées non conformes sur « ${obj.name} ».',
      payload: const <String, Object?>{},
      expectedValid: false,
      expectedErrorHint: fallbackHint,
      ruleRefs: ruleRefs,
    );
  }

  static List<GherkinStep> _buildStepsFromJourney(
    UxJourneySpec journey, {
    required String personaLabel,
  }) {
    final steps = <GherkinStep>[
      GherkinStep(
        id: 'step_jrn_given',
        keyword: GherkinStepKeyword.given,
        text: journey.trigger.trim().isNotEmpty
            ? 'que $personaLabel démarre dans le contexte : ${journey.trigger.trim()}'
            : 'que $personaLabel est authentifié et prêt à démarrer « ${journey.name} »',
      ),
    ];

    final ordered = List<UxJourneyStep>.from(journey.steps)
      ..sort((a, b) => a.order.compareTo(b.order));

    if (ordered.isEmpty) {
      steps
        ..add(
          GherkinStep(
            id: 'step_jrn_when',
            keyword: GherkinStepKeyword.when,
            text: 'il exécute le parcours « ${journey.name} »',
          ),
        )
        ..add(
          GherkinStep(
            id: 'step_jrn_then',
            keyword: GherkinStepKeyword.then,
            text: journey.goal.trim().isNotEmpty
                ? journey.goal.trim()
                : (journey.successCriteria.isNotEmpty
                      ? journey.successCriteria.first
                      : 'le parcours « ${journey.name} » aboutit avec succès'),
          ),
        );
      return steps;
    }

    var emittedWhen = false;
    var emittedThen = false;
    for (var i = 0; i < ordered.length; i++) {
      final js = ordered[i];
      final actionText = js.actorAction.trim().isNotEmpty
          ? js.actorAction.trim()
          : js.title.trim();
      steps.add(
        GherkinStep(
          id: 'step_jrn_act_${i + 1}',
          keyword: emittedWhen
              ? GherkinStepKeyword.and
              : GherkinStepKeyword.when,
          text: actionText,
        ),
      );
      emittedWhen = true;

      if (js.systemResponse.trim().isNotEmpty) {
        steps.add(
          GherkinStep(
            id: 'step_jrn_resp_${i + 1}',
            keyword: emittedThen
                ? GherkinStepKeyword.and
                : GherkinStepKeyword.then,
            text: js.systemResponse.trim(),
          ),
        );
        emittedThen = true;
      }
    }

    if (!emittedThen) {
      final finalOutcome = journey.successCriteria.isNotEmpty
          ? journey.successCriteria.first
          : (journey.goal.trim().isNotEmpty
                ? journey.goal.trim()
                : 'le parcours « ${journey.name} » est complété sans erreur');
      steps.add(
        GherkinStep(
          id: 'step_jrn_then_final',
          keyword: GherkinStepKeyword.then,
          text: finalOutcome,
        ),
      );
    }
    return steps;
  }

  static List<GherkinStep> _buildNominalStepsFromUseCase(
    UseCaseSpec uc, {
    required String actorName,
  }) {
    final steps = <GherkinStep>[
      GherkinStep(
        id: 'step_uc_given',
        keyword: GherkinStepKeyword.given,
        text: uc.preconditions.isNotEmpty
            ? uc.preconditions.first
            : 'que l’acteur « $actorName » dispose des droits requis',
      ),
    ];
    for (var i = 1; i < uc.preconditions.length && i < 2; i++) {
      steps.add(
        GherkinStep(
          id: 'step_uc_given_and_$i',
          keyword: GherkinStepKeyword.and,
          text: uc.preconditions[i],
        ),
      );
    }

    if (uc.mainFlow.isEmpty) {
      steps.add(
        GherkinStep(
          id: 'step_uc_when',
          keyword: GherkinStepKeyword.when,
          text: 'il exécute le cas d’usage « ${uc.title} »',
        ),
      );
    } else {
      steps.add(
        GherkinStep(
          id: 'step_uc_when_1',
          keyword: GherkinStepKeyword.when,
          text: uc.mainFlow.first,
        ),
      );
      for (var i = 1; i < uc.mainFlow.length && i < 3; i++) {
        steps.add(
          GherkinStep(
            id: 'step_uc_when_${i + 1}',
            keyword: GherkinStepKeyword.and,
            text: uc.mainFlow[i],
          ),
        );
      }
    }

    if (uc.postconditions.isEmpty) {
      steps.add(
        GherkinStep(
          id: 'step_uc_then',
          keyword: GherkinStepKeyword.then,
          text: 'le cas d’usage « ${uc.title} » est validé et persisté',
        ),
      );
    } else {
      steps.add(
        GherkinStep(
          id: 'step_uc_then_1',
          keyword: GherkinStepKeyword.then,
          text: uc.postconditions.first,
        ),
      );
      for (var i = 1; i < uc.postconditions.length && i < 3; i++) {
        steps.add(
          GherkinStep(
            id: 'step_uc_then_${i + 1}',
            keyword: GherkinStepKeyword.and,
            text: uc.postconditions[i],
          ),
        );
      }
    }

    return steps;
  }

  static TddTargetLayer _mapCategoryToLayer(BusinessRuleCategory category) =>
      switch (category) {
        BusinessRuleCategory.calculation => TddTargetLayer.calculationFormula,
        BusinessRuleCategory.validation => TddTargetLayer.domainValidation,
        BusinessRuleCategory.stateTransition => TddTargetLayer.stateMachine,
        BusinessRuleCategory.permission => TddTargetLayer.permissionPolicy,
        BusinessRuleCategory.trigger => TddTargetLayer.domainValidation,
      };

  static int _nextSequentialNumber(
    Iterable<String> existingCodes, {
    required String prefix,
  }) {
    final regex = RegExp(
      '^${RegExp.escape(prefix)}[-_]?([0-9]+)\$',
      caseSensitive: false,
    );
    var maxFound = 0;
    for (final raw in existingCodes) {
      final match = regex.firstMatch(raw.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1) ?? '');
        if (parsed != null && parsed > maxFound) {
          maxFound = parsed;
        }
      }
    }
    return maxFound + 1;
  }

  static String _allocateUniqueId(String base, Set<String> usedLower) {
    final sanitized = base
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final effective = sanitized.isEmpty ? 'qa_item' : sanitized;
    if (usedLower.add(effective.toLowerCase())) {
      return effective;
    }
    var suffix = 2;
    while (!usedLower.add('${effective}_$suffix'.toLowerCase())) {
      suffix++;
    }
    return '${effective}_$suffix';
  }

  static SpecPersona? _resolvePersona(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final p in project.vision.personas) {
      if (p.id.toLowerCase() == needle || p.name.toLowerCase() == needle) {
        return p;
      }
    }
    return null;
  }

  static SpecModule? _resolveModule(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final m in project.cahierDesCharges.modules) {
      if (m.id.toLowerCase() == needle || m.name.toLowerCase() == needle) {
        return m;
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

  static FunctionalRequirement? _resolveRequirement(
    SpecForgeProject project,
    String ref,
  ) {
    for (final req in project.cahierDesCharges.functionalRequirements) {
      if (_matchesRequirement(req, ref)) return req;
    }
    return null;
  }

  static bool _screenMatchesRouteRef(
    SpecForgeProject project,
    UxScreenSpec screen,
    String routeRef,
  ) {
    final needle = routeRef.trim().toLowerCase();
    if (needle.isEmpty) return false;
    if (screen.routeId.trim().toLowerCase() == needle) return true;
    final route = project.uxSpec.navigation.findRoute(routeRef);
    if (route == null) return false;
    final scrRoute = screen.routeId.trim().toLowerCase();
    return scrRoute == route.id.toLowerCase() ||
        scrRoute == route.path.toLowerCase();
  }

  static bool _matchesBusinessObject(BusinessObjectSpec obj, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return obj.id.toLowerCase() == needle ||
        obj.technicalName.toLowerCase() == needle ||
        obj.name.toLowerCase() == needle;
  }

  static bool _matchesUseCase(UseCaseSpec uc, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return uc.id.toLowerCase() == needle || uc.title.toLowerCase() == needle;
  }

  static bool _matchesRequirement(FunctionalRequirement req, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return req.id.toLowerCase() == needle ||
        (req.code.trim().isNotEmpty && req.code.trim().toLowerCase() == needle);
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
}

class _FixtureViolationMutation {
  const _FixtureViolationMutation({
    required this.kind,
    required this.titleSuffix,
    required this.description,
    required this.payload,
    required this.expectedValid,
    required this.expectedErrorHint,
    required this.ruleRefs,
  });

  final QaFixtureKind kind;
  final String titleSuffix;
  final String description;
  final Map<String, Object?> payload;
  final bool expectedValid;
  final String expectedErrorHint;
  final List<String> ruleRefs;
}
