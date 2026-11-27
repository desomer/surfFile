/// Contrat IA, construction de prompts et application de patches pour le découpage
/// produit d'un projet en Initiatives et Features ([PortfolioSlicingAiAgent]).
library;

import 'dart:convert';

import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/spec_cahier_des_charges.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/spec_initiative.dart';
import '../models/spec_stage_chat.dart';

/// Orchestre les instructions système, prompts et application de patches IA
/// pour la page intermédiaire Initiatives & Features d'un projet.
abstract final class PortfolioSlicingAiAgent {
  /// Instruction système de l'agent IA « Product Portfolio & Feature Slicing Architect ».
  static const String systemInstruction = '''
Tu es le « Product Portfolio & Feature Slicing Architect » de SuperSpecForge.
Ta mission :
1. Aider l'utilisateur à structurer un projet en **Initiatives stratégiques** (`INIT-01`, `INIT-02`…) et en **Features fonctionnelles verticales** (`FEAT-01`, `FEAT-02`…).
2. Chaque **Feature** sera ensuite ouverte individuellement dans les 4 Wizards de SuperSpecForge (Spécification 8 étapes, UX & Parcours, BDD/Gherkin & TDD, Estimation de coût IT). Découpe donc des features cohérentes de bout en bout (« Vertical Slices » orientées valeur métier, ni trop monolithiques ni purement techniques).
3. Valorise des codes courts clairs (`INIT-01`, `FEAT-01`…), une description précise (problème, acteurs concernés, opérations clés et valeur attendue), un jalon cible (`targetRelease` : `MVP`, `Lot 1`, `Lot 2`…) et une priorité MoSCoW (`must`, `should`, `could`, `wont`).
4. Préserve les identifiants `id` des initiatives et features existantes lorsque tu les affines afin de conserver tous leurs livrables Wizards déjà produits.

Réponds EXCLUSIVEMENT en français et renvoie UNIQUEMENT un objet JSON valide (aucun Markdown, aucun texte hors JSON).
Place impérativement la clé "message" EN PREMIER pour permettre le streaming en direct :
{
  "message": "Synthèse claire de la proposition de découpage produit en français",
  "askUser": {
    "questions": [
      {
        "id": "identifiant_snake_case",
        "title": "Question de cadrage du portefeuille ou du MVP ?",
        "description": "Contexte court (optionnel)",
        "type": "single|multi|boolean|text",
        "options": ["Option A", "Option B"],
        "default": "Option A",
        "allowOther": true
      }
    ]
  },
  "specPatch": { ... }
}
Règles strictes :
- Si tu poses des questions via "askUser", mets "specPatch": null et fournis toujours des valeurs "default" pertinentes.
- Lorsque tu as les réponses ou que la demande est claire, mets "askUser": null et fournis un "specPatch" structuré.
''';

  /// Guide statique décrivant le schéma JSON attendu dans `"specPatch"`.
  static const String patchSchemaGuide = '''
SCHÉMA "specPatch" POUR INITIATIVES & FEATURES :
{
  "replaceDefaultPlaceholder": true,
  "activeFeatureId": "feat_reservations",
  "initiatives": [
    {
      "id": "init_parc_auto",
      "code": "INIT-01",
      "name": "Socle Parc & Réservations",
      "description": "Digitaliser le référentiel véhicules et le parcours de réservation collaborateur.",
      "owner": "Services Généraux",
      "targetTimeframe": "MVP - T1",
      "priority": "must",
      "status": "draft",
      "features": [
        {
          "id": "feat_referentiel_vehicules",
          "code": "FEAT-01",
          "name": "Référentiel véhicules & affectations",
          "description": "Gestion du parc immatriculé, contrats, affectations par site et alertes d'échéances.",
          "targetRelease": "MVP",
          "priority": "must",
          "status": "draft"
        },
        {
          "id": "feat_reservations",
          "code": "FEAT-02",
          "name": "Réservation & suivi kilométrique",
          "description": "Recherche de véhicule disponible, demande de prêt, check-in/check-out et relevé compteur.",
          "targetRelease": "MVP",
          "priority": "must",
          "status": "draft"
        }
      ]
    }
  ],
  "removeInitiativeIds": ["id_initiative_a_supprimer"],
  "removeFeatureIds": ["id_feature_a_supprimer"]
}
Règles de fusion :
- Les initiatives de "initiatives" fusionnent par "id" (ou par "code" / "name" insensible à la casse) et créent les nouvelles initiatives.
- Les features fusionnent par "id" (ou par "code" / "name") en conservant intégralement leurs livrables Wizards existants (vision, cahier des charges, objets métiers, règles, UX, QA, coûts).
- Si le projet ne contient encore que la « Feature initiale » vide par défaut, "replaceDefaultPlaceholder": true remplace proprement cette coquille vide par le découpage proposé.
- "removeInitiativeIds" et "removeFeatureIds" retirent les éléments explicitement supprimés (il restera toujours au moins 1 initiative et 1 feature dans le projet).
''';

  /// Construit le prompt utilisateur complet transmis à l'agent de découpage produit.
  static String buildTurnPrompt({
    required SpecForgeProject project,
    required List<SpecChatMessage> history,
    required String userInput,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    int maxHistoryEntries = 10,
  }) {
    final portfolioSnapshot = <String, Object?>{
      'projectId': project.id,
      'projectName': project.name,
      'initialIdea': project.initialIdea,
      'hasSingleDefaultPlaceholder':
          project.hasSingleDefaultFeature &&
          project.activeFeature.isUntouchedPlaceholder(project.initialIdea),
      'activeFeatureId': project.activeFeatureId,
      if (project.lexicon.terms.isNotEmpty)
        'sharedLexiconTerms': [
          for (final t in project.lexicon.terms.take(40))
            <String, Object?>{'term': t.term, 'definition': t.definition},
        ],
      'initiatives': [
        for (final init in project.initiatives)
          <String, Object?>{
            'id': init.id,
            'code': init.code,
            'name': init.name,
            'description': init.description,
            if (init.owner.isNotEmpty) 'owner': init.owner,
            if (init.targetTimeframe.isNotEmpty)
              'targetTimeframe': init.targetTimeframe,
            'priority': init.priority.name,
            'status': init.status.name,
            'features': [
              for (final feat in init.features)
                <String, Object?>{
                  'id': feat.id,
                  'code': feat.code,
                  'name': feat.name,
                  'description': feat.description,
                  if (feat.targetRelease.isNotEmpty)
                    'targetRelease': feat.targetRelease,
                  'priority': feat.priority.name,
                  'status': feat.status.name,
                  if (feat.disabledSpecStages.isNotEmpty)
                    'disabledSpecStages': [
                      for (final s in feat.disabledSpecStages) s.name,
                    ],
                  'hasWizardDeliverables': feat.hasDeliverableContent,
                  'objectCount': feat.businessObjects.length,
                  'ruleCount': feat.businessRules.length,
                  'uxScreenCount': feat.uxSpec.screens.length,
                  'qaFeatureCount': feat.qaSpec.features.length,
                  'costWbsCount': feat.costSpec.wbsItems.length,
                },
            ],
          },
      ],
    };

    final snapshotJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(portfolioSnapshot);
    final recent = history.length <= maxHistoryEntries
        ? history
        : history.sublist(history.length - maxHistoryEntries);
    final historyText = recent.map((m) => m.toConversationEntry()).join('\n');

    final String questioningRule;
    if (forceFollowUpQuestions) {
      questioningRule =
          'QUESTIONNEMENT DEMANDÉ (+ Questions) : Pose impérativement 2 à 4 questions ciblées via "askUser" (avec "default") sur le périmètre MVP, les lots ou la granularité des features, et laisse "specPatch": null.';
    } else if (afterAskUserReply) {
      questioningRule =
          'ARBITRAGE REÇU : "askUser": null obligatoire. Applique immédiatement les réponses dans "specPatch".';
    } else {
      questioningRule = switch (questioningLevel) {
        VibeQuestioningLevel.none =>
          'QUESTIONNEMENT 0/4 : "askUser": null obligatoire. Produis directement "specPatch" avec un découpage complet et pragmatique.',
        VibeQuestioningLevel.light =>
          'QUESTIONNEMENT 1/4 : Ne pose 1 à 2 questions via "askUser" que si une ambiguïté majeure bloque le découpage, sinon produis directement "specPatch".',
        VibeQuestioningLevel.balanced =>
          'QUESTIONNEMENT 2/4 : Pose 2 à 4 questions ciblées via "askUser" uniquement si le périmètre MVP ou les acteurs sont flous, sinon produis directement "specPatch".',
        VibeQuestioningLevel.thorough =>
          'QUESTIONNEMENT 3/4 : Pose 3 à 5 questions structurées via "askUser" (périmètre MVP, phasage, personas clés, exclusions) avant de finaliser "specPatch".',
        VibeQuestioningLevel.exhaustive =>
          'QUESTIONNEMENT 4/4 : Pose 5 à 8 questions approfondies via "askUser" couvrant stratégie produit, jalons, dépendances et priorités MoSCoW avant de produire "specPatch".',
      };
    }

    final buf = StringBuffer()
      ..writeln(
        'CONTEXTE : DÉCOUPAGE PRODUIT (INITIATIVES & FEATURES) DU PROJET « ${project.name} »',
      )
      ..writeln(questioningRule)
      ..writeln()
      ..writeln('ÉTAT ACTUEL DU PORTEFEUILLE PROJET (JSON) :')
      ..writeln(snapshotJson);

    if (historyText.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('HISTORIQUE RÉCENT :')
        ..writeln(historyText);
    }

    buf
      ..writeln()
      ..writeln('DEMANDE UTILISATEUR :')
      ..writeln(userInput.trim());

    return buf.toString();
  }

  /// Applique de manière immuable et non destructive un `"specPatch"` sur [current].
  static ({SpecForgeProject project, String summary}) applyPatch(
    SpecForgeProject current,
    Map<String, Object?> patch,
  ) {
    final removeInitIds = <String>{
      if (patch['removeInitiativeIds'] is List)
        for (final item in patch['removeInitiativeIds'] as List)
          if (item is String && item.trim().isNotEmpty) item.trim(),
    };
    final removeFeatIds = <String>{
      if (patch['removeFeatureIds'] is List)
        for (final item in patch['removeFeatureIds'] as List)
          if (item is String && item.trim().isNotEmpty) item.trim(),
    };

    final existingFeaturesById = <String, SpecFeatureSpec>{};
    final existingFeaturesByCode = <String, SpecFeatureSpec>{};
    final existingFeaturesByName = <String, SpecFeatureSpec>{};
    for (final feat in current.allFeatures) {
      existingFeaturesById[feat.id] = feat;
      if (feat.code.trim().isNotEmpty) {
        existingFeaturesByCode[feat.code.trim().toLowerCase()] = feat;
      }
      existingFeaturesByName[feat.name.trim().toLowerCase()] = feat;
    }

    final canDropDefaultPlaceholder =
        current.hasSingleDefaultFeature &&
        current.activeFeature.isUntouchedPlaceholder(current.initialIdea) &&
        patch['replaceDefaultPlaceholder'] != false &&
        patch['initiatives'] is List &&
        (patch['initiatives'] as List).isNotEmpty;

    final workingInitiatives = <SpecInitiative>[
      if (!canDropDefaultPlaceholder)
        for (final init in current.initiatives)
          if (!removeInitIds.contains(init.id))
            init.copyWith(
              features: <SpecFeatureSpec>[
                for (final f in init.features)
                  if (!removeFeatIds.contains(f.id)) f,
              ],
            ),
    ];

    var addedInitiatives = 0;
    var updatedInitiatives = 0;
    var addedFeatures = 0;
    var updatedFeatures = 0;
    final claimedFeatureIds = <String>{};

    final rawInitiatives = patch['initiatives'];
    if (rawInitiatives is List) {
      for (final rawInit in rawInitiatives) {
        if (rawInit is! Map) continue;
        final rawInitId = (rawInit['id'] as String?)?.trim() ?? '';
        final rawInitCode = (rawInit['code'] as String?)?.trim() ?? '';
        final rawInitName = (rawInit['name'] as String?)?.trim() ?? '';

        var matchIdx = -1;
        if (rawInitId.isNotEmpty) {
          matchIdx = workingInitiatives.indexWhere((i) => i.id == rawInitId);
        }
        if (matchIdx < 0 && rawInitCode.isNotEmpty) {
          matchIdx = workingInitiatives.indexWhere(
            (i) => i.code.trim().toLowerCase() == rawInitCode.toLowerCase(),
          );
        }
        if (matchIdx < 0 && rawInitName.isNotEmpty) {
          matchIdx = workingInitiatives.indexWhere(
            (i) => i.name.trim().toLowerCase() == rawInitName.toLowerCase(),
          );
        }

        final existingInit = matchIdx >= 0 ? workingInitiatives[matchIdx] : null;
        final initId = existingInit?.id ??
            (rawInitId.isNotEmpty
                ? _sanitizeId(rawInitId, prefix: 'init')
                : 'init_${shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}');
        final initName = rawInitName.isNotEmpty
            ? rawInitName
            : (existingInit?.name ?? 'Nouvelle initiative');
        final initCode = rawInitCode.isNotEmpty
            ? rawInitCode
            : (existingInit?.code ?? '');
        final initDesc = rawInit['description'] is String
            ? (rawInit['description'] as String).trim()
            : (existingInit?.description ?? '');
        final initOwner = rawInit['owner'] is String
            ? (rawInit['owner'] as String).trim()
            : (existingInit?.owner ?? '');
        final initTimeframe = rawInit['targetTimeframe'] is String
            ? (rawInit['targetTimeframe'] as String).trim()
            : (existingInit?.targetTimeframe ?? '');
        final initPriority = rawInit['priority'] != null
            ? RequirementPriority.fromJson(rawInit['priority'])
            : (existingInit?.priority ?? RequirementPriority.must);
        final initStatus = rawInit['status'] != null
            ? SpecPortfolioStatus.fromJson(rawInit['status'])
            : (existingInit?.status ?? SpecPortfolioStatus.draft);

        final mergedFeatures = <SpecFeatureSpec>[
          if (existingInit != null)
            for (final f in existingInit.features)
              if (!removeFeatIds.contains(f.id)) f,
        ];

        if (rawInit['features'] is List) {
          for (final rawFeat in rawInit['features'] as List) {
            if (rawFeat is! Map) continue;
            final rawFeatId = (rawFeat['id'] as String?)?.trim() ?? '';
            final rawFeatCode = (rawFeat['code'] as String?)?.trim() ?? '';
            final rawFeatName = (rawFeat['name'] as String?)?.trim() ?? '';

            SpecFeatureSpec? prevFeat;
            if (rawFeatId.isNotEmpty) {
              prevFeat = existingFeaturesById[rawFeatId];
            }
            prevFeat ??= rawFeatCode.isNotEmpty
                ? existingFeaturesByCode[rawFeatCode.toLowerCase()]
                : null;
            prevFeat ??= rawFeatName.isNotEmpty
                ? existingFeaturesByName[rawFeatName.toLowerCase()]
                : null;
            if (prevFeat != null &&
                canDropDefaultPlaceholder &&
                prevFeat.id == SpecFeatureSpec.defaultFeatureId &&
                rawFeatId != SpecFeatureSpec.defaultFeatureId) {
              prevFeat = null;
            }
            if (prevFeat != null && claimedFeatureIds.contains(prevFeat.id)) {
              prevFeat = null;
            }

            final featId = prevFeat?.id ??
                (rawFeatId.isNotEmpty
                    ? _sanitizeId(rawFeatId, prefix: 'feat')
                    : 'feat_${shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}');
            var uniqueFeatId = featId;
            var suffix = 2;
            while (!claimedFeatureIds.add(uniqueFeatId)) {
              uniqueFeatId = '${featId}_$suffix';
              suffix++;
            }

            final featName = rawFeatName.isNotEmpty
                ? rawFeatName
                : (prevFeat?.name ?? 'Nouvelle feature');
            final featCode = rawFeatCode.isNotEmpty
                ? rawFeatCode
                : (prevFeat?.code ?? '');
            final featDesc = rawFeat['description'] is String
                ? (rawFeat['description'] as String).trim()
                : (prevFeat?.description ?? '');
            final featRelease = rawFeat['targetRelease'] is String
                ? (rawFeat['targetRelease'] as String).trim()
                : (prevFeat?.targetRelease ?? '');
            final featPriority = rawFeat['priority'] != null
                ? RequirementPriority.fromJson(rawFeat['priority'])
                : (prevFeat?.priority ?? RequirementPriority.must);
            final featStatus = rawFeat['status'] != null
                ? SpecPortfolioStatus.fromJson(rawFeat['status'])
                : (prevFeat?.status ?? SpecPortfolioStatus.draft);
            final featDisabledStages = rawFeat.containsKey('disabledSpecStages')
                ? SpecFeatureSpec.parseDisabledSpecStages(
                    rawFeat['disabledSpecStages'],
                  )
                : (prevFeat?.disabledSpecStages ?? const <SpecForgeStage>{});

            final SpecFeatureSpec nextFeat;
            if (prevFeat != null) {
              final nextVision =
                  (prevFeat.vision.ideaSummary.trim().isEmpty &&
                      featDesc.isNotEmpty)
                  ? prevFeat.vision.copyWith(ideaSummary: featDesc)
                  : prevFeat.vision;
              nextFeat = prevFeat.copyWith(
                id: uniqueFeatId,
                code: featCode,
                name: featName,
                description: featDesc,
                targetRelease: featRelease,
                priority: featPriority,
                status: featStatus,
                disabledSpecStages: featDisabledStages,
                vision: nextVision,
              );
              updatedFeatures++;
            } else {
              nextFeat = SpecFeatureSpec.create(
                id: uniqueFeatId,
                code: featCode,
                name: featName,
                description: featDesc,
                targetRelease: featRelease,
                priority: featPriority,
                status: featStatus,
                disabledSpecStages: featDisabledStages,
              );
              addedFeatures++;
            }

            final localIdx = mergedFeatures.indexWhere(
              (f) => f.id == nextFeat.id,
            );
            if (localIdx >= 0) {
              mergedFeatures[localIdx] = nextFeat;
            } else {
              mergedFeatures.add(nextFeat);
            }

            // Si la feature a été déplacée depuis une autre initiative existante, la retirer de l'ancienne.
            for (var i = 0; i < workingInitiatives.length; i++) {
              if (i == matchIdx) continue;
              final other = workingInitiatives[i];
              if (other.featureById(nextFeat.id) != null) {
                workingInitiatives[i] = other.copyWith(
                  features: [
                    for (final f in other.features)
                      if (f.id != nextFeat.id) f,
                  ],
                );
              }
            }
          }
        }

        final nextInit = SpecInitiative(
          id: initId,
          code: initCode,
          name: initName,
          description: initDesc,
          owner: initOwner,
          targetTimeframe: initTimeframe,
          priority: initPriority,
          status: initStatus,
          features: mergedFeatures,
        );

        if (matchIdx >= 0) {
          workingInitiatives[matchIdx] = nextInit;
          updatedInitiatives++;
        } else {
          workingInitiatives.add(nextInit);
          addedInitiatives++;
        }
      }
    }

    // Assure des codes auto-numérotés propres lorsqu'ils sont vides.
    final normalizedInitiatives = <SpecInitiative>[];
    var autoFeatCounter = 1;
    for (var i = 0; i < workingInitiatives.length; i++) {
      final init = workingInitiatives[i];
      final initCode = init.code.trim().isNotEmpty
          ? init.code.trim()
          : 'INIT-${(i + 1).toString().padLeft(2, '0')}';
      final normFeatures = <SpecFeatureSpec>[];
      for (final feat in init.features) {
        final featCode = feat.code.trim().isNotEmpty
            ? feat.code.trim()
            : 'FEAT-${autoFeatCounter.toString().padLeft(2, '0')}';
        autoFeatCounter++;
        normFeatures.add(feat.copyWith(code: featCode));
      }
      normalizedInitiatives.add(
        init.copyWith(code: initCode, features: normFeatures),
      );
    }

    if (normalizedInitiatives.isEmpty) {
      return (project: current, summary: '');
    }

    // Garantit au moins 1 feature dans le projet.
    final hasAnyFeat = normalizedInitiatives.any((i) => i.features.isNotEmpty);
    if (!hasAnyFeat) {
      normalizedInitiatives[0] = normalizedInitiatives[0].copyWith(
        features: <SpecFeatureSpec>[
          SpecFeatureSpec.create(
            code: 'FEAT-01',
            name: normalizedInitiatives[0].name,
            description: normalizedInitiatives[0].description,
          ),
        ],
      );
    }

    final requestedActive = (patch['activeFeatureId'] as String?)?.trim();
    String? resolvedActive = requestedActive;
    final allFeats = [for (final i in normalizedInitiatives) ...i.features];
    if (resolvedActive == null ||
        !allFeats.any((f) => f.id == resolvedActive)) {
      resolvedActive = allFeats.any((f) => f.id == current.activeFeatureId)
          ? current.activeFeatureId
          : allFeats.first.id;
    }

    final nextProject = current.copyWith(
      initiatives: normalizedInitiatives,
      activeFeatureId: resolvedActive,
    );
    nextProject.validate();

    if (nextProject == current) {
      return (project: current, summary: '');
    }

    final summaryParts = <String>[];
    if (addedInitiatives > 0) {
      summaryParts.add('+$addedInitiatives initiative(s)');
    }
    if (updatedInitiatives > 0) {
      summaryParts.add('$updatedInitiatives initiative(s) mise(s) à jour');
    }
    if (addedFeatures > 0) {
      summaryParts.add('+$addedFeatures feature(s)');
    }
    if (updatedFeatures > 0) {
      summaryParts.add('$updatedFeatures feature(s) mise(s) à jour');
    }

    return (
      project: nextProject,
      summary: summaryParts.isEmpty
          ? 'portefeuille mis à jour'
          : summaryParts.join(', '),
    );
  }

  static String _sanitizeId(String raw, {required String prefix}) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (cleaned.isEmpty) {
      return '${prefix}_${shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}';
    }
    return cleaned;
  }
}
