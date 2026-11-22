import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemoryModelDictionaryStore extends ModelDictionaryStore {
  _MemoryModelDictionaryStore() : super(Directory('memory_store'));

  BusinessObjectModelPreferences _prefs =
      BusinessObjectModelPreferences.defaults;

  @override
  Future<BusinessObjectModelPreferences> load() async => _prefs;

  @override
  Future<void> save(BusinessObjectModelPreferences preferences) async {
    preferences.validate();
    _prefs = preferences;
  }
}

class _MemoryCompanyGlossaryStore extends CompanyGlossaryStore {
  _MemoryCompanyGlossaryStore() : super(Directory('memory_store'));

  CompanyGlossary _glossary = CompanyGlossary.empty;
  List<SpecChatMessage> _chat = const <SpecChatMessage>[];

  @override
  Future<CompanyGlossary> loadGlossary() async => _glossary;

  @override
  Future<void> saveGlossary(CompanyGlossary glossary) async {
    glossary.validate();
    _glossary = glossary;
  }

  @override
  Future<List<SpecChatMessage>> loadChatMessages() async => _chat;

  @override
  Future<void> saveChatMessages(List<SpecChatMessage> messages) async {
    _chat = List<SpecChatMessage>.unmodifiable(messages);
  }
}

class _MemoryDomainCatalogStore extends DomainCatalogStore {
  _MemoryDomainCatalogStore() : super(Directory('memory_store'));

  DomainCatalog _catalog = DomainCatalog.empty;

  @override
  Future<DomainCatalog> load() async => _catalog;

  @override
  Future<void> save(DomainCatalog catalog) async {
    catalog.validate();
    _catalog = catalog;
  }
}

class _MemorySpecProjectStore extends SpecProjectStore {
  _MemorySpecProjectStore() : super(Directory('memory_store'));

  final Map<String, SpecForgeProject> _projects = {};
  String? _lastActiveId;

  @override
  Future<void> saveProject(SpecForgeProject project) async {
    project.validate();
    _projects[project.id] = project;
    _lastActiveId = project.id;
  }

  @override
  Future<SpecForgeProject?> loadProject(String projectId) async =>
      _projects[projectId];

  @override
  Future<void> deleteProject(String projectId) async {
    _projects.remove(projectId);
    if (_lastActiveId == projectId) _lastActiveId = null;
  }

  @override
  Future<List<SpecProjectSummary>> listProjects() async {
    final list = [
      for (final p in _projects.values)
        SpecProjectSummary(
          id: p.id,
          name: p.name,
          initialIdea: p.initialIdea,
          currentStage: p.currentStage,
          updatedAt: p.updatedAt,
          objectCount: p.businessObjects.length,
          ruleCount: p.businessRules.length,
          journeyCount: p.uxSpec.journeys.length,
          screenCount: p.uxSpec.screens.length,
          currentUxStage: p.uxSpec.currentStage,
        ),
    ];
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<String?> getLastActiveProjectId() async => _lastActiveId;

  @override
  Future<void> setLastActiveProjectId(String? projectId) async {
    _lastActiveId = projectId;
  }
}

/// Service IA factice émettant des fragments SSE multi-chunks pour simuler un tour UX.
class FakeSpecAiService implements SpecAiService {
  FakeSpecAiService(this._scriptedChunkBatches);

  final List<List<String>> _scriptedChunkBatches;
  final List<String> receivedPrompts = <String>[];
  final List<String?> receivedSystemInstructions = <String?>[];
  int _turnIndex = 0;

  @override
  Future<void> warmUp(
    SpecForgeStage stage, {
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
  }) async {}

  @override
  Stream<GeminiStreamEvent> streamTurn({
    required SpecForgeStage stage,
    required String prompt,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
    List<Map<String, Object?>>? conversationContents,
    bool enforceJsonResponse = true,
    String? systemInstructionOverride,
    String? staticGuideOverride,
  }) async* {
    receivedPrompts.add(prompt);
    receivedSystemInstructions.add(systemInstructionOverride);
    final chunks = _scriptedChunkBatches[
      _turnIndex < _scriptedChunkBatches.length
          ? _turnIndex
          : _scriptedChunkBatches.length - 1
    ];
    _turnIndex++;

    final accumulated = StringBuffer();
    for (var i = 0; i < chunks.length; i++) {
      final delta = chunks[i];
      accumulated.write(delta);
      yield GeminiStreamEvent(
        deltaText: delta,
        accumulatedText: accumulated.toString(),
        isDone: i == chunks.length - 1,
        usedContextCache: false,
      );
    }
  }
}

SpecForgeProject _buildRichBusinessProject() {
  final base = SpecForgeProject.fromIdea(
    idea: 'Plateforme B2B de gestion des commandes et expéditions',
    name: 'OrderFlow B2B',
    id: 'proj_orderflow',
  );
  return base.copyWith(
    lexicon: SpecLexicon(
      terms: [
        LexiconTerm(
          id: 'term_cmd',
          term: 'Commande client',
          definition: 'Engagement ferme de livraison de marchandises.',
          synonyms: const ['Ordre client'],
          domain: 'Ventes',
        ),
      ],
      conventions: const ['Montants HT en EUR'],
    ),
    vision: base.vision.copyWith(
      problemStatement: 'Saisie manuelle dispersée et retards de validation',
      objectives: const ['Diviser par 2 le temps de saisie'],
      personas: [
        SpecPersona(
          id: 'persona_adv',
          name: 'Gestionnaire ADV',
          role: 'Contrôle et valide les commandes B2B',
          goals: const ['Valider sans erreur de tarif'],
          painPoints: const ['Allers-retours e-mail'],
        ),
      ],
    ),
    cahierDesCharges: SpecCahierDesCharges(
      modules: const [
        SpecModule(
          id: 'mod_ventes',
          name: 'Administration des ventes',
          description: 'Cycle devis-commande-livraison',
        ),
      ],
      functionalRequirements: [
        FunctionalRequirement(
          id: 'req_exf_001',
          code: 'EXF-001',
          title: 'Valider une commande client',
          moduleId: 'mod_ventes',
          priority: RequirementPriority.must,
          actorIds: const ['persona_adv'],
          acceptanceCriteria: const ['Vérifie le plafond d’encours'],
        ),
      ],
      useCases: [
        UseCaseSpec(
          id: 'uc_valider_cmd',
          title: 'Validation commande B2B',
          actorId: 'persona_adv',
          mainFlow: const ['Ouvrir la commande', 'Contrôler et valider'],
        ),
      ],
      nonFunctionalRequirements: const [
        NonFunctionalRequirement(
          id: 'nfr_001',
          code: 'ENF-001',
          category: NonFunctionalCategory.performance,
          title: 'Affichage liste < 200 ms',
          targetMetric: 'p95 < 200 ms',
        ),
      ],
    ),
    businessObjects: [
      BusinessObjectSpec(
        id: 'obj_client',
        name: 'Client',
        technicalName: 'Client',
        description: 'Compte client B2B',
        attributes: [
          BusinessAttribute(
            id: 'attr_cli_raison',
            name: 'raisonSociale',
            type: BusinessAttributeType.string,
            required: true,
          ),
        ],
      ),
      BusinessObjectSpec(
        id: 'obj_commande',
        name: 'Commande',
        technicalName: 'Commande',
        description: 'Commande B2B soumise à validation ADV',
        attributes: [
          BusinessAttribute(
            id: 'attr_cmd_num',
            name: 'numero',
            type: BusinessAttributeType.string,
            required: true,
            unique: true,
            schemaConstraints: JsonSchemaConstraints(
              minLength: 5,
              examples: const ['CMD-2026-001'],
            ),
          ),
          BusinessAttribute(
            id: 'attr_cmd_statut',
            name: 'statut',
            type: BusinessAttributeType.enumeration,
            required: true,
            enumValues: const ['brouillon', 'validee'],
          ),
          BusinessAttribute(
            id: 'attr_cmd_lignes',
            name: 'lignes',
            type: BusinessAttributeType.object,
            isArray: true,
            estimatedMaxRows: 80,
            children: [
              BusinessAttribute(
                id: 'attr_lig_sku',
                name: 'codeArticle',
                type: BusinessAttributeType.string,
                required: true,
              ),
              BusinessAttribute(
                id: 'attr_lig_qte',
                name: 'quantite',
                type: BusinessAttributeType.integer,
                required: true,
              ),
            ],
          ),
        ],
        relations: const [
          BusinessRelation(
            id: 'rel_cmd_client',
            name: 'client',
            targetObjectId: 'obj_client',
            cardinality: BusinessRelationCardinality.oneToOne,
            description: 'Client donneur d’ordre',
            required: true,
          ),
        ],
        lifecycleStates: const [
          LifecycleState(
            name: 'brouillon',
            label: 'Brouillon',
            isInitial: true,
          ),
          LifecycleState(
            name: 'validee',
            label: 'Validée',
            isTerminal: true,
          ),
        ],
        lifecycleTransitions: const [
          LifecycleTransition(
            id: 'tr_cmd_valider',
            fromState: 'brouillon',
            toState: 'validee',
            trigger: 'Validation ADV',
            guardSummary: 'Encours autorisé',
          ),
        ],
      ),
    ],
    businessRules: [
      BusinessRuleSpec(
        id: 'rule_rg_001',
        code: 'RG-001',
        title: 'Plafond encours client',
        category: BusinessRuleCategory.validation,
        priority: BusinessRulePriority.critical,
        targetObjectIds: const ['obj_commande', 'obj_client'],
        targetAttributes: const ['Commande.numero'],
        condition: 'encoursClient <= plafondAutorise',
        effect: 'Autoriser la validation',
        examples: const ['Encours 8 000 € / plafond 10 000 € -> OK'],
      ),
      BusinessRuleSpec(
        id: 'rule_rg_002',
        code: 'RG-002',
        title: 'Quantité strictement positive',
        category: BusinessRuleCategory.validation,
        targetObjectIds: const ['obj_commande'],
        targetAttributes: const ['Commande.lignes.quantite'],
      ),
    ],
  );
}

void main() {
  group('Modèles UX, normalisation, validation et rétrocompatibilité', () {
    test('round-trip JSON complet de UxForgeSpec et de tous les sous-modèles UX', () {
      final journey = UxJourneySpec(
        id: 'jrn_validation_adv',
        code: 'JRN-001',
        name: 'Validation express d’une commande B2B',
        personaId: 'persona_adv',
        useCaseIds: const ['uc_valider_cmd'],
        requirementIds: const ['EXF-001'],
        channel: UxTargetChannel.desktop,
        trigger: 'Réception d’une nouvelle commande client EDI',
        goal: 'Valider et lancer la préparation en moins de 60 secondes',
        steps: const [
          UxJourneyStep(
            id: 'step_1',
            order: 1,
            title: 'Sélection dans la file d’attente',
            actorAction: 'Filtre les commandes à contrôler et clique une ligne',
            systemResponse: 'Affiche le détail client, lignes et encours',
            targetRouteId: 'route_commandes',
            painPointResolved: 'Plus besoin d’ouvrir un second outil CRM',
          ),
          UxJourneyStep(
            id: 'step_2',
            order: 2,
            title: 'Validation sous contrôle RG-001',
            actorAction: 'Clique sur « Valider la commande »',
            systemResponse: 'Vérifie RG-001 et passe le statut à Validée',
            targetRouteId: 'route_modal_confirmation',
            branchCondition: 'Si plafond dépassé : exige motif dérogation',
          ),
        ],
        successCriteria: const ['Validation en <= 3 clics'],
      );

      const theme = UxVisualThemeSeed(
        accentHex: '#1e88e5',
        themeMode: 'dark',
        surfaceSystem: 'liquidGlass',
        fontFamily: 'Plus Jakarta Sans',
        density: UxDensityProfile.compact,
        cardRadius: 12.0,
        uxVoiceGuidelines: 'Ton professionnel, concis et orienté action.',
      );

      final navigation = UxNavigationSpec(
        shellPattern: UxShellPattern.navigationRail,
        hasAppBar: true,
        hasBreadcrumbs: true,
        hasGlobalSearch: true,
        homeRouteId: 'route_commandes',
        visualTheme: theme,
        routes: [
          UxRouteNode(
            id: 'route_commandes',
            path: 'commandes/a-valider/',
            title: 'Commandes à valider',
            iconName: 'receipt_long_outlined',
            pageType: EditorPageType.standard,
            moduleId: 'mod_ventes',
            allowedPersonaIds: const ['persona_adv'],
            permissionRuleIds: const ['RG-001'],
            showInPrimaryNav: true,
          ),
          UxRouteNode(
            id: 'route_modal_confirmation',
            path: '/commandes/a-valider',
            title: 'Confirmation de validation',
            pageType: EditorPageType.dialog,
            parentRouteId: 'route_commandes',
            showInPrimaryNav: false,
          ),
          UxRouteNode(
            id: 'route_bon_pdf',
            path: '/commandes/bon-livraison',
            title: 'Aperçu Bon A4',
            pageType: EditorPageType.a4Document,
            parentRouteId: 'route_commandes',
            showInPrimaryNav: false,
          ),
        ],
      );

      final screen = UxScreenSpec(
        id: 'scr_commandes',
        code: 'SCR-001',
        name: 'Poste de validation commandes',
        routeId: 'route_commandes',
        pattern: UxScreenPattern.masterDetail,
        purpose: 'Permettre le contrôle rapide de la file ADV',
        personaIds: const ['persona_adv'],
        useCaseIds: const ['uc_valider_cmd'],
        requirementIds: const ['EXF-001'],
        primaryObjectId: 'obj_commande',
        zones: [
          UxScreenZoneSpec(
            zone: UxLayoutZoneName.west,
            sizePx: 340,
            slots: [
              UxZoneWidgetSlot(
                id: 'slot_search',
                title: 'Recherche rapide',
                kind: UxWidgetKind.searchFilterBar,
                businessObjectId: 'obj_commande',
                attributeNames: const ['numero', 'statut'],
              ),
              UxZoneWidgetSlot(
                id: 'slot_list',
                title: 'File des commandes',
                kind: UxWidgetKind.masterList,
                businessObjectId: 'obj_commande',
                attributeNames: const ['numero', 'statut'],
                summary: 'Triée par ancienneté',
              ),
            ],
          ),
          UxScreenZoneSpec(
            zone: UxLayoutZoneName.center,
            scrollable: true,
            slots: [
              UxZoneWidgetSlot(
                id: 'slot_detail',
                title: 'Détail commande & lignes',
                kind: UxWidgetKind.detailCard,
                businessObjectId: 'obj_commande',
                attributeNames: const ['numero', 'statut', 'lignes'],
              ),
            ],
          ),
        ],
        actions: [
          UxScreenAction(
            id: 'act_valider',
            label: 'Valider la commande',
            hierarchy: UxActionHierarchy.primary,
            businessRuleIds: const ['RG-001', 'RG-002'],
            targetRouteId: 'route_modal_confirmation',
          ),
          UxScreenAction(
            id: 'act_rejeter',
            label: 'Rejeter',
            hierarchy: UxActionHierarchy.destructive,
            confirmationMessage: 'Confirmer le rejet définitif de la commande ?',
          ),
        ],
        states: UxScreenStatesSpec(
          emptyStateTitle: 'Aucune commande en attente',
          emptyStateCta: 'Actualiser le flux EDI',
          loadingPattern: 'shimmer',
          errorHandling: 'Bandeau non bloquant avec bouton Réessayer',
          readOnlyRuleIds: const ['RG-001'],
        ),
      );

      const issue = UxCoherenceIssue(
        id: 'ux_coh_1',
        severity: CoherenceSeverity.warning,
        stage: UxForgeStage.screenBlueprints,
        code: 'UX-PDF-ACTION',
        title: 'Route PDF non déclenchée depuis SCR-001',
        description: 'La route route_bon_pdf n’a pas d’action dédiée.',
        targetRef: 'SCR-001',
        suggestion: 'Ajouter une action secondaire Aperçu PDF.',
        source: 'local',
      );

      final uxSpec = UxForgeSpec(
        currentStage: UxForgeStage.screenBlueprints,
        journeys: [journey],
        navigation: navigation,
        screens: [screen],
        stageStates: {
          UxForgeStage.userJourneys: UxStageState(
            stage: UxForgeStage.userJourneys,
            status: SpecStageStatus.validated,
            stageSummary: 'Parcours JRN-001 validé.',
            readyToAdvance: true,
            messages: [
              SpecChatMessage(
                id: 'ux_m1',
                isUser: true,
                text: 'Formalise le flux ADV.',
              ),
            ],
          ),
        },
        coherenceIssues: const [issue],
      );

      uxSpec.validate();
      expect(uxSpec.hasContent, isTrue);
      expect(navigation.routes.first.path, '/commandes/a-valider');
      expect(navigation.visualTheme.toJson()['accentHex'], '#1E88E5');

      final roundTripped = UxForgeSpec.fromJson(uxSpec.toJson());
      expect(roundTripped, equals(uxSpec));
      expect(roundTripped.findJourney('JRN-001'), equals(journey));
      expect(roundTripped.findScreen('SCR-001'), equals(screen));
      expect(roundTripped.findScreen('route_commandes'), equals(screen));
      expect(
        roundTripped.navigation.findRoute('commandes/a-valider'),
        equals(navigation.routes.first),
      );
      expect(roundTripped.screens.single.states.hasContent, isTrue);
    });

    test('UxScreenSpec.defaultZonesForPattern couvre tous les patterns et passe validate()', () {
      for (final pattern in UxScreenPattern.values) {
        final zones = UxScreenSpec.defaultZonesForPattern(pattern);
        expect(
          zones,
          isNotEmpty,
          reason: 'Le pattern ${pattern.name} doit fournir des zones initiales.',
        );
        final screen = UxScreenSpec(
          id: 'scr_${pattern.name}',
          code: 'SCR-${pattern.index + 1}',
          name: 'Écran ${pattern.label}',
          pattern: pattern,
          zones: zones,
        );
        expect(screen.validate, returnsNormally);
        expect(screen.zoneFor(UxLayoutZoneName.center), isNotNull);
      }

      final masterDetailZones = UxScreenSpec.defaultZonesForPattern(
        UxScreenPattern.masterDetail,
      );
      expect(masterDetailZones.map((z) => z.zone).toList(), [
        UxLayoutZoneName.west,
        UxLayoutZoneName.center,
      ]);
      expect(masterDetailZones.first.sizePx, 320);

      final wizardZones = UxScreenSpec.defaultZonesForPattern(
        UxScreenPattern.wizard,
      );
      expect(wizardZones.map((z) => z.zone).toList(), [
        UxLayoutZoneName.north,
        UxLayoutZoneName.center,
        UxLayoutZoneName.south,
      ]);
      expect(wizardZones[1].scrollable, isTrue);

      final a4Zones = UxScreenSpec.defaultZonesForPattern(
        UxScreenPattern.documentA4,
      );
      expect(a4Zones.map((z) => z.zone).toList(), [
        UxLayoutZoneName.north,
        UxLayoutZoneName.center,
        UxLayoutZoneName.south,
      ]);
    });

    test('normalisation (#RRGGBB, /path, enums) et cas limites de validation (IDs dupliqués)', () {
      // Normalisation couleur #RRGGBB (3, 6, 8 digits et fallback)
      expect(UxVisualThemeSeed.normalizeAccentHex('#0af'), '#00AAFF');
      expect(UxVisualThemeSeed.normalizeAccentHex('26a69a'), '#26A69A');
      expect(UxVisualThemeSeed.normalizeAccentHex('#FF8E24AA'), '#8E24AA');
      expect(
        UxVisualThemeSeed.normalizeAccentHex('invalide', fallback: '#112233'),
        '#112233',
      );
      expect(UxVisualThemeSeed.normalizeThemeMode('Clair'), 'light');
      expect(UxVisualThemeSeed.normalizeThemeMode('sombre'), 'dark');
      expect(
        UxVisualThemeSeed.normalizeSurfaceSystem('liquid-glass'),
        'liquidGlass',
      );
      expect(
        UxVisualThemeSeed.defaults.copyWith(cardRadius: 99).cardRadius,
        32.0,
      );

      // Normalisation des chemins de routes
      expect(UxRouteNode.normalizePath(''), '');
      expect(UxRouteNode.normalizePath('/'), '/');
      expect(UxRouteNode.normalizePath('clients///fiche/'), '/clients/fiche');
      expect(UxForgeStage.fromJson(2), UxForgeStage.iaNavigation);
      expect(UxForgeStage.fromJson('ux-review-export'), UxForgeStage.uxReviewExport);

      // Rejets de validate() sur invariants violés et identifiants dupliqués
      expect(
        const UxVisualThemeSeed(accentHex: '3F51B5').validate,
        throwsFormatException,
      );
      expect(
        const UxVisualThemeSeed(cardRadius: -1).validate,
        throwsFormatException,
      );
      expect(
        UxRouteNode(id: 'r1', path: '   ', title: 'Vide').validate,
        throwsFormatException,
      );
      expect(
        UxNavigationSpec(
          routes: [
            UxRouteNode(id: 'r1', path: '/ventes', title: 'Ventes 1'),
            UxRouteNode(id: 'r2', path: 'ventes/', title: 'Ventes 2'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        UxNavigationSpec(
          routes: [
            UxRouteNode(id: 'dup', path: '/a', title: 'A'),
            UxRouteNode(id: 'dup', path: '/b', title: 'B'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        UxJourneySpec(
          id: 'j1',
          name: 'Parcours',
          steps: const [
            UxJourneyStep(id: 's_dup', order: 1, title: 'Étape 1'),
            UxJourneyStep(id: 's_dup', order: 2, title: 'Étape 2'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        UxScreenSpec(
          id: 'scr_1',
          name: 'Écran',
          zones: [
            UxScreenZoneSpec(zone: UxLayoutZoneName.center),
            UxScreenZoneSpec(zone: UxLayoutZoneName.center),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        UxForgeSpec(
          journeys: [
            UxJourneySpec(id: 'j_dup', name: 'P1'),
            UxJourneySpec(id: 'j_dup', name: 'P2'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        UxForgeSpec(
          screens: [
            UxScreenSpec(id: 's_dup', name: 'E1'),
            UxScreenSpec(id: 's_dup', name: 'E2'),
          ],
        ).validate,
        throwsFormatException,
      );
      expect(
        UxForgeSpec(
          coherenceIssues: const [
            UxCoherenceIssue(
              id: 'c_dup',
              severity: CoherenceSeverity.error,
              stage: UxForgeStage.userJourneys,
              code: 'UX-1',
              title: 'Anomalie 1',
              description: 'D1',
            ),
            UxCoherenceIssue(
              id: 'c_dup',
              severity: CoherenceSeverity.warning,
              stage: UxForgeStage.iaNavigation,
              code: 'UX-2',
              title: 'Anomalie 2',
              description: 'D2',
            ),
          ],
        ).validate,
        throwsFormatException,
      );

      // Désérialisation tolérante : déduplique automatiquement les IDs et chemins non modaux
      final deduplicated = UxForgeSpec.fromJson({
        'journeys': [
          {'id': 'j1', 'name': 'A'},
          {'id': 'j1', 'name': 'B'},
        ],
        'navigation': {
          'routes': [
            {'id': 'r1', 'path': '/home', 'title': 'Accueil 1'},
            {'id': 'r1', 'path': '/home', 'title': 'Accueil 2'},
          ],
        },
        'screens': [
          {'id': 's1', 'name': 'Vue 1'},
          {'id': 's1', 'name': 'Vue 2'},
        ],
        'coherenceIssues': [
          {'id': 'i1', 'title': 'Issue 1'},
          {'id': 'i1', 'title': 'Issue 2'},
        ],
      });
      expect(deduplicated.journeys.map((j) => j.id).toList(), ['j1', 'j1_2']);
      expect(
        deduplicated.navigation.routes.map((r) => r.id).toList(),
        ['r1', 'r1_2'],
      );
      expect(
        deduplicated.navigation.routes.map((r) => r.path).toList(),
        ['/home', '/home-2'],
      );
      expect(deduplicated.screens.map((s) => s.id).toList(), ['s1', 's1_2']);
      expect(
        deduplicated.coherenceIssues.map((i) => i.id).toList(),
        ['i1', 'i1_2'],
      );
    });

    test('SpecForgeProject rétrocompatibilité quand uxSpec est omis vs renseigné et UxPromptBuilder', () {
      final withoutUx = SpecForgeProject.fromIdea(
        idea: 'Suivi SAV industriel',
        name: 'SavPro',
        id: 'proj_sav',
      );
      expect(withoutUx.uxSpec, equals(UxForgeSpec.empty));
      expect(withoutUx.uxSpec.hasContent, isFalse);

      final jsonWithoutUx = withoutUx.toJson();
      expect(jsonWithoutUx.containsKey('uxSpec'), isFalse);
      expect(
        withoutUx
            .toCompactContextJson(SpecForgeStage.reviewExport)
            .containsKey('uxSummary'),
        isFalse,
      );

      // Chargement d’un JSON historique dépourvu de la clé uxSpec
      final legacyLoaded = SpecForgeProject.fromJson(jsonWithoutUx);
      expect(legacyLoaded, equals(withoutUx));
      expect(legacyLoaded.uxSpec, equals(UxForgeSpec.empty));

      // Projet avec uxSpec renseigné
      final withUx = withoutUx.copyWith(
        uxSpec: UxForgeSpec(
          currentStage: UxForgeStage.iaNavigation,
          journeys: [
            UxJourneySpec(
              id: 'jrn_sav',
              code: 'JRN-001',
              name: 'Déclaration ticket SAV',
            ),
          ],
          navigation: UxNavigationSpec(
            routes: [
              UxRouteNode(
                id: 'route_tickets',
                path: '/tickets',
                title: 'Tickets SAV',
              ),
            ],
          ),
          screens: [
            UxScreenSpec(
              id: 'scr_tickets',
              code: 'SCR-001',
              name: 'Console Tickets',
              routeId: 'route_tickets',
              zones: UxScreenSpec.defaultZonesForPattern(
                UxScreenPattern.masterDetail,
              ),
            ),
          ],
        ),
      );
      final jsonWithUx = withUx.toJson();
      expect(jsonWithUx.containsKey('uxSpec'), isTrue);
      expect(
        withUx
            .toCompactContextJson(SpecForgeStage.reviewExport)
            .containsKey('uxSummary'),
        isTrue,
      );
      expect(SpecForgeProject.fromJson(jsonWithUx), equals(withUx));

      final focusBlock = UxPromptBuilder.buildUxFocusScopeBlock(
        project: withUx,
        focusedJourneyId: 'JRN-001',
        focusedRouteId: '/tickets',
        focusedScreenId: 'SCR-001',
        focusedZone: UxLayoutZoneName.west,
      );
      expect(focusBlock, contains('JRN-001'));
      expect(focusBlock, contains('/tickets'));
      expect(focusBlock, contains('SCR-001'));
      expect(focusBlock, contains('slot_master_list'));

      final turnPrompt = UxPromptBuilder.buildTurnPrompt(
        project: withUx,
        stage: UxForgeStage.screenBlueprints,
        userInput: 'Ajoute un filtre statut dans cette zone',
        questioningLevel: VibeQuestioningLevel.none,
        afterAskUserReply: false,
        focusedScreenId: 'scr_tickets',
        focusedZone: UxLayoutZoneName.west,
      );
      expect(turnPrompt, contains('CATALOGUE COMPACT DES SPÉCIFICATIONS MÉTIERS'));
      expect(turnPrompt, contains('FOCUS COURANT DANS L’ATELIER UX'));
    });
  });

  group('UxPatchApplier.apply, applyPartial & contrat additive_safe', () {
    test('ajoute, met à jour et supprime parcours, routes, thème visuel, écrans et diagnostics IA', () {
      final initial = _buildRichBusinessProject().copyWith(
        uxSpec: UxForgeSpec(
          coherenceIssues: const [
            UxCoherenceIssue(
              id: 'local_coh_1',
              severity: CoherenceSeverity.warning,
              stage: UxForgeStage.userJourneys,
              code: 'UX-LOCAL',
              title: 'Diagnostic local à préserver',
              description: 'Issu de l’analyseur local.',
              source: 'local',
            ),
          ],
        ),
      );

      // 1. Ajout initial de parcours, navigation/thème, écrans et diagnostics IA
      final step1 = UxPatchApplier.apply(
        initial,
        uxPatch: {
          'journeys': [
            {
              'id': 'jrn_1',
              'code': 'JRN-001',
              'name': 'Validation commande',
              'personaId': 'persona_adv',
              'steps': [
                {'id': 'st_1', 'order': 1, 'title': 'Ouvrir file ADV'},
              ],
            },
            {
              'id': 'jrn_2',
              'code': 'JRN-002',
              'name': 'Parcours temporaire',
            },
          ],
          'navigation': {
            'shellPattern': 'sidebar',
            'hasGlobalSearch': true,
            'homeRouteId': 'route_cmd',
            'visualTheme': {
              'accentHex': '#00897b',
              'themeMode': 'dark',
              'cardRadius': 10,
            },
            'routes': [
              {
                'id': 'route_cmd',
                'path': 'commandes',
                'title': 'Commandes',
              },
              {
                'id': 'route_old',
                'path': '/obsolete',
                'title': 'Obsolète',
              },
            ],
          },
          'screens': [
            {
              'id': 'scr_cmd',
              'code': 'SCR-001',
              'name': 'Poste Commandes',
              'routeId': 'route_cmd',
              'pattern': 'masterDetail',
              'primaryObjectId': 'obj_commande',
              'zones': [
                {
                  'zone': 'center',
                  'slots': [
                    {
                      'id': 'slot_1',
                      'title': 'Détail',
                      'kind': 'detailCard',
                    },
                  ],
                },
              ],
              'states': {
                'emptyStateTitle': 'Aucune commande',
                'loadingPattern': 'shimmer',
              },
            },
            {
              'id': 'scr_temp',
              'code': 'SCR-002',
              'name': 'Écran temporaire',
            },
          ],
          'coherenceIssues': [
            {
              'id': 'local_coh_1',
              'severity': 'info',
              'stage': 'iaNavigation',
              'code': 'UX-AI-1',
              'title': 'Recommandation IA dédupliquée',
              'description': 'Suggestion IA.',
            },
          ],
        },
      );

      final ux1 = step1.project.uxSpec;
      expect(ux1.journeys.length, 2);
      expect(ux1.navigation.shellPattern, UxShellPattern.sidebar);
      expect(ux1.navigation.hasGlobalSearch, isTrue);
      expect(ux1.navigation.visualTheme.accentHex, '#00897B');
      expect(ux1.navigation.visualTheme.themeMode, 'dark');
      expect(ux1.navigation.visualTheme.fontFamily, 'Inter');
      expect(ux1.navigation.routes.length, 2);
      expect(ux1.screens.length, 2);
      // Le diagnostic local est conservé et le diagnostic IA est suffixé et marqué 'ai'
      expect(ux1.coherenceIssues.length, 2);
      expect(ux1.coherenceIssues[0].source, 'local');
      expect(ux1.coherenceIssues[1].id, 'local_coh_1_2');
      expect(ux1.coherenceIssues[1].source, 'ai');

      // 2. Mise à jour incrémentale par code/path + suppressions ciblées
      final step2 = UxPatchApplier.apply(
        step1.project,
        uxPatch: {
          'removeJourneyIds': ['JRN-002'],
          'journeys': [
            {
              'code': 'JRN-001',
              'name': 'Validation commande consolidée',
              'personaId': 'persona_adv',
            },
          ],
          'removeRouteIds': ['/obsolete'],
          'visualTheme': {
            'uxVoiceGuidelines': 'Messages d’erreur orientés résolution.',
          },
          'navigation': {
            'routes': [
              {
                'path': '/commandes/',
                'title': 'Commandes B2B',
              },
            ],
          },
          'removeScreenIds': ['SCR-002'],
          'screens': [
            {
              'code': 'SCR-001',
              'purpose': 'Contrôler et valider les commandes en attente',
              'states': {
                'emptyStateCta': 'Importer un flux EDI',
              },
            },
          ],
        },
      );

      final ux2 = step2.project.uxSpec;
      expect(ux2.journeys.length, 1);
      expect(ux2.journeys.single.id, 'jrn_1');
      expect(ux2.journeys.single.name, 'Validation commande consolidée');

      expect(ux2.navigation.routes.length, 1);
      expect(ux2.navigation.routes.single.id, 'route_cmd');
      expect(ux2.navigation.routes.single.title, 'Commandes B2B');
      // Les champs visualTheme précédents (#00897B, dark, cardRadius 10) sont préservés
      expect(ux2.navigation.visualTheme.accentHex, '#00897B');
      expect(ux2.navigation.visualTheme.themeMode, 'dark');
      expect(ux2.navigation.visualTheme.cardRadius, 10.0);
      expect(
        ux2.navigation.visualTheme.uxVoiceGuidelines,
        'Messages d’erreur orientés résolution.',
      );

      expect(ux2.screens.length, 1);
      final updatedScr = ux2.screens.single;
      expect(updatedScr.id, 'scr_cmd');
      expect(updatedScr.name, 'Poste Commandes');
      expect(
        updatedScr.purpose,
        'Contrôler et valider les commandes en attente',
      );
      expect(updatedScr.zones.single.slots.single.id, 'slot_1');
      expect(updatedScr.states.emptyStateTitle, 'Aucune commande');
      expect(updatedScr.states.loadingPattern, 'shimmer');
      expect(updatedScr.states.emptyStateCta, 'Importer un flux EDI');
    });

    test('contrat additive_safe : enrichit objets/attributs/RG sans aucune suppression et ignore toutes les clés destructrices', () {
      final baseline = _buildRichBusinessProject();

      final destructiveAndAdditiveSpecPatch = <String, Object?>{
        // Clés destructrices interdites depuis un agent UX : doivent être 100 % ignorées
        'removeBusinessObjectIds': ['obj_client', 'obj_commande'],
        'removeBusinessRuleIds': ['rule_rg_001', 'rule_rg_002'],
        'removeLexiconTermIds': ['term_cmd'],
        'removePersonaIds': ['persona_adv'],
        'removeModuleIds': ['mod_ventes'],
        'removeRequirementIds': ['req_exf_001'],
        'removeUseCaseIds': ['uc_valider_cmd'],
        'removeNfrIds': ['nfr_001'],
        'removeAttributes': [
          {'objectId': 'obj_commande', 'attributeName': 'numero'},
        ],
        // Sections hors objets/règles ignorées en mode additif UX
        'lexicon': {'terms': <Object?>[]},
        'vision': {'personas': <Object?>[]},
        // Enrichissement additif : 1 attribut + 1 sous-attribut sur Commande existante + 1 nouvel objet
        'businessObjects': [
          {
            'id': 'obj_commande',
            'name': 'Commande',
            'technicalName': 'Commande',
            'attributes': [
              {
                'id': 'attr_cmd_motif_derogation',
                'name': 'motifDerogation',
                'type': 'string',
                'description': 'Saisi dans la modale UX en cas de dépassement encours',
              },
              {
                'name': 'statut',
                'type': 'enum',
                'enumValues': ['en_derogation'],
              },
              {
                'name': 'lignes',
                'type': 'object',
                'isArray': true,
                'children': [
                  {
                    'id': 'attr_lig_remise',
                    'name': 'remisePct',
                    'type': 'number',
                  },
                ],
              },
            ],
          },
          {
            'id': 'obj_bon_livraison',
            'name': 'Bon de livraison',
            'technicalName': 'BonLivraison',
            'attributes': [
              {
                'id': 'attr_bl_ref',
                'name': 'referenceBl',
                'type': 'string',
                'required': true,
              },
            ],
          },
        ],
        // Nouvelle règle RG-003
        'businessRules': [
          {
            'id': 'rule_rg_003',
            'code': 'RG-003',
            'title': 'Motif obligatoire si dérogation encours',
            'category': 'validation',
            'targetObjectIds': ['obj_commande'],
            'targetAttributes': ['Commande.motifDerogation'],
            'condition': 'statut == "en_derogation"',
            'effect': 'Exiger motifDerogation non vide',
          },
        ],
      };

      final res = UxPatchApplier.apply(
        baseline,
        uxPatch: {
          'journeys': [
            {
              'id': 'jrn_derogation',
              'code': 'JRN-001',
              'name': 'Validation avec dérogation',
            },
          ],
        },
        specPatch: destructiveAndAdditiveSpecPatch,
      );

      final updated = res.project;

      // Lexique, vision, personas, modules, exigences, cas d'usage et ENF intacts
      expect(updated.lexicon, equals(baseline.lexicon));
      expect(updated.vision, equals(baseline.vision));
      expect(updated.cahierDesCharges, equals(baseline.cahierDesCharges));

      // Objets métiers : Client conservé, Commande enrichie, BonLivraison ajouté
      expect(
        updated.businessObjects.map((o) => o.id).toList(),
        ['obj_client', 'obj_commande', 'obj_bon_livraison'],
      );

      final commande = updated.findBusinessObject('obj_commande')!;
      expect(
        commande.attributes.map((a) => a.name).toList(),
        ['numero', 'statut', 'lignes', 'motifDerogation'],
      );
      // Contraintes JSON Schema préexistantes préservées sur numero
      expect(commande.attributes[0].schemaConstraints.minLength, 5);
      expect(
        commande.attributes[0].schemaConstraints.examples,
        ['CMD-2026-001'],
      );
      // Valeurs d'énumération fusionnées sans perte
      expect(
        commande.attributes[1].enumValues,
        ['brouillon', 'validee', 'en_derogation'],
      );
      // Sous-attributs imbriqués de lignes préservés + remisePct ajouté
      final lignes = commande.attributes[2];
      expect(lignes.estimatedMaxRows, 80);
      expect(
        lignes.children.map((c) => c.name).toList(),
        ['codeArticle', 'quantite', 'remisePct'],
      );
      // Relations, états du cycle de vie et transitions intégralement préservés
      expect(commande.relations, equals(baseline.businessObjects[1].relations));
      expect(
        commande.lifecycleStates,
        equals(baseline.businessObjects[1].lifecycleStates),
      );
      expect(
        commande.lifecycleTransitions,
        equals(baseline.businessObjects[1].lifecycleTransitions),
      );

      // Règles de gestion : RG-001 et RG-002 préservées + RG-003 ajoutée
      expect(
        updated.businessRules.map((r) => r.code).toList(),
        ['RG-001', 'RG-002', 'RG-003'],
      );
      expect(updated.uxSpec.journeys.single.id, 'jrn_derogation');
    });

    test('UxPatchApplier.applyPartial et salvageFailedAttempt isolent les entrées invalides', () {
      final baseline = _buildRichBusinessProject();

      final partial = UxPatchApplier.applyPartial(
        baseline,
        uxPatch: {
          'journeys': [
            {'id': 'jrn_ok', 'code': 'JRN-001', 'name': 'Parcours valide'},
            'entrée_non_map_invalide',
          ],
          'navigation': {
            'routes': [
              {'id': 'route_ok', 'path': '/commandes', 'title': 'Commandes'},
              'route_invalide',
            ],
          },
          'screens': [
            {
              'id': 'scr_ok',
              'code': 'SCR-001',
              'name': 'Écran valide',
              'routeId': 'route_ok',
            },
            'ecran_invalide',
          ],
          'coherenceIssues': [
            {
              'id': 'coh_ok',
              'severity': 'warning',
              'stage': 'screenBlueprints',
              'code': 'UX-01',
              'title': 'Point d’attention valide',
              'description': 'Détail',
            },
            'issue_invalide',
          ],
        },
        specPatch: {
          'removeBusinessObjectIds': ['obj_client'],
          'businessObjects': [
            {
              'id': 'obj_transporteur',
              'name': 'Transporteur',
              'technicalName': 'Transporteur',
              'attributes': [
                {'id': 'a_nom', 'name': 'nom', 'type': 'string'},
              ],
            },
            {
              'id': 'obj_invalide',
              'name': 'Invalide',
              'attributes': [
                {'id': 'a_bad', 'name': '@nomInterdit', 'type': 'string'},
              ],
            },
          ],
        },
      );

      expect(partial.hasAppliedChanges, isTrue);
      expect(partial.project.uxSpec.journeys.single.id, 'jrn_ok');
      expect(partial.project.uxSpec.navigation.routes.single.id, 'route_ok');
      expect(partial.project.uxSpec.screens.single.id, 'scr_ok');
      expect(partial.project.uxSpec.coherenceIssues.single.id, 'coh_ok');
      expect(
        partial.project.findBusinessObject('obj_transporteur'),
        isNotNull,
      );
      expect(partial.project.findBusinessObject('obj_client'), isNotNull);
      expect(partial.rejectedEntries.length, 5);

      const truncatedUxJson =
          '{"message":"Génération en cours","uxPatch":{"journeys":[{"id":"jrn_salvaged","code":"JRN-009","name":"Parcours récupéré"},{"id":"jrn_tr';
      final salvage = UxPatchApplier.salvageFailedAttempt(
        workingProject: baseline,
        rawResponse: truncatedUxJson,
      );
      expect(salvage.hasCheckpoint, isTrue);
      expect(salvage.wasTruncated, isTrue);
      expect(
        salvage.checkpointProject.uxSpec.journeys.single.id,
        'jrn_salvaged',
      );
    });
  });

  group('SpecStreamParser & SpecAgentResponse pour uxPatch', () {
    test('détecte hasUxPatch en streaming puis décode uxPatch et specPatch', () {
      final parser = SpecStreamParser();

      var snap = parser.addChunk('{"message":"Structuration UX ');
      expect(snap.message, 'Structuration UX ');
      expect(snap.isMessageComplete, isFalse);
      expect(snap.hasUxPatch, isFalse);
      expect(snap.hasSpecPatch, isFalse);

      snap = parser.addChunk(
        'terminée.","askUser":null,"uxPatch":{"journeys":[{"id":"jrn_1","code":"JRN-001","name":"Flux A"}]}',
      );
      expect(snap.message, 'Structuration UX terminée.');
      expect(snap.isMessageComplete, isTrue);
      expect(snap.hasUxPatch, isTrue);
      expect(snap.hasSpecPatch, isFalse);

      snap = parser.addChunk(
        ',"specPatch":{"businessRules":[{"id":"r_ux","code":"RG-010","title":"Contrôle UX"}]},"stageSummary":"1 parcours créé","stageReadyToAdvance":true}',
      );
      expect(snap.hasUxPatch, isTrue);
      expect(snap.hasSpecPatch, isTrue);

      final parsed = SpecAgentResponse.parse('```json\n${parser.rawText}\n```');
      expect(parsed.message, 'Structuration UX terminée.');
      expect(parsed.askUser, isNull);
      expect(parsed.uxPatch, isNotNull);
      expect((parsed.uxPatch!['journeys'] as List).length, 1);
      expect(parsed.specPatch, isNotNull);
      expect((parsed.specPatch!['businessRules'] as List).length, 1);
      expect(parsed.stageSummary, '1 parcours créé');
      expect(parsed.stageReadyToAdvance, isTrue);
    });
  });

  group('SpecForgeController : mutations UX, Undo/Redo unifié et tour IA UX en streaming', () {
    test('updateUxSpec, goToUxStage, upserts métiers depuis UX et pile Undo/Redo unifiée', () async {
      final controller = SpecForgeController(
        store: _MemorySpecProjectStore(),
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        domainCatalogStore: _MemoryDomainCatalogStore(),
      );
      addTearDown(controller.dispose);

      await controller.initialize(restoreLastProject: false);
      await controller.createProjectFromIdea(
        idea: 'Portail logistique B2B',
        name: 'LogiFlow',
      );
      expect(controller.canUndo, isFalse);

      // 1. Mutation UX directe via updateUxSpec
      final uxWithJourney = controller.project!.uxSpec.copyWith(
        journeys: [
          UxJourneySpec(
            id: 'jrn_reception',
            code: 'JRN-001',
            name: 'Réception quai',
          ),
        ],
      );
      await controller.updateUxSpec(uxWithJourney);
      expect(controller.project!.uxSpec.journeys.length, 1);
      expect(controller.canUndo, isTrue);

      // 2. Navigation d'étape UX avec validation de l'étape précédente
      await controller.goToUxStage(
        UxForgeStage.screenBlueprints,
        validateCurrent: true,
      );
      expect(
        controller.project!.uxSpec.currentStage,
        UxForgeStage.screenBlueprints,
      );
      expect(
        controller.project!.uxSpec
            .stageStateFor(UxForgeStage.userJourneys)
            .status,
        SpecStageStatus.validated,
      );
      expect(
        controller.project!.uxSpec
            .stageStateFor(UxForgeStage.screenBlueprints)
            .status,
        SpecStageStatus.inProgress,
      );

      // 3. Création d'un objet métier depuis l'atelier UX
      final colisObj = BusinessObjectSpec(
        id: 'obj_colis',
        name: 'Colis',
        technicalName: 'Colis',
        attributes: [
          BusinessAttribute(
            id: 'attr_code_barre',
            name: 'codeBarre',
            type: BusinessAttributeType.string,
            required: true,
          ),
          BusinessAttribute(
            id: 'attr_dimensions',
            name: 'dimensions',
            type: BusinessAttributeType.object,
            children: [
              BusinessAttribute(
                id: 'attr_poids',
                name: 'poidsKg',
                type: BusinessAttributeType.number,
              ),
            ],
          ),
        ],
      );
      await controller.upsertBusinessObjectFromUx(colisObj);
      expect(controller.project!.businessObjects.single.id, 'obj_colis');

      // 4. Ajout d'un attribut racine puis d'un sous-attribut depuis l'atelier UX
      await controller.upsertBusinessAttributeFromUx(
        objectId: 'obj_colis',
        attribute: BusinessAttribute(
          id: 'attr_quai',
          name: 'numeroQuai',
          type: BusinessAttributeType.integer,
        ),
      );
      await controller.upsertBusinessAttributeFromUx(
        objectId: 'obj_colis',
        parentAttrPath: const ['attr_dimensions'],
        attribute: BusinessAttribute(
          id: 'attr_hauteur',
          name: 'hauteurCm',
          type: BusinessAttributeType.number,
        ),
      );
      expect(
        () => controller.upsertBusinessAttributeFromUx(
          objectId: 'obj_inexistant',
          attribute: BusinessAttribute(id: 'a_x', name: 'champX'),
        ),
        throwsStateError,
      );

      final enrichedColis = controller.project!.businessObjects.single;
      expect(
        enrichedColis.attributes.map((a) => a.name).toList(),
        ['codeBarre', 'dimensions', 'numeroQuai'],
      );
      expect(
        enrichedColis.attributes[1].children.map((c) => c.name).toList(),
        ['poidsKg', 'hauteurCm'],
      );

      // 5. Ajout puis mise à jour d'une règle de gestion depuis l'atelier UX
      await controller.upsertBusinessRuleFromUx(
        BusinessRuleSpec(
          id: 'r_colis_1',
          code: 'RG-001',
          title: 'Poids maximal 30 kg',
          targetObjectIds: const ['obj_colis'],
        ),
      );
      await controller.upsertBusinessRuleFromUx(
        BusinessRuleSpec(
          id: 'r_colis_1',
          code: 'RG-001',
          title: 'Poids maximal strict 25 kg',
          targetObjectIds: const ['obj_colis'],
        ),
      );
      expect(
        controller.project!.businessRules.single.title,
        'Poids maximal strict 25 kg',
      );

      // 6. Vérification de la pile Undo/Redo unifiée sur toutes les mutations
      await controller.undo();
      expect(
        controller.project!.businessRules.single.title,
        'Poids maximal 30 kg',
      );

      await controller.undo();
      expect(controller.project!.businessRules, isEmpty);

      await controller.undo();
      expect(
        controller.project!.businessObjects.single.attributes[1].children
            .map((c) => c.name)
            .toList(),
        ['poidsKg'],
      );

      await controller.undo();
      expect(
        controller.project!.businessObjects.single.attributes
            .map((a) => a.name)
            .toList(),
        ['codeBarre', 'dimensions'],
      );

      await controller.undo();
      expect(controller.project!.businessObjects, isEmpty);

      await controller.undo();
      expect(controller.project!.uxSpec.journeys, isEmpty);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);

      while (controller.canRedo) {
        await controller.redo();
      }
      expect(controller.project!.uxSpec.journeys.single.id, 'jrn_reception');
      expect(controller.project!.businessObjects.single.id, 'obj_colis');
      expect(
        controller.project!.businessRules.single.title,
        'Poids maximal strict 25 kg',
      );
    });

    test('simule un tour IA UX en streaming avec FakeSpecAiService, uxPatch + specPatch additif et Undo/Redo', () async {
      final responsePayload = <String, Object?>{
        'message': 'J’ai conçu l’écran SCR-001 et ajouté l’attribut prioritePreparation.',
        'askUser': null,
        'uxPatch': {
          'navigation': {
            'routes': [
              {
                'id': 'route_commandes',
                'path': '/commandes',
                'title': 'Commandes ADV',
              },
            ],
          },
          'screens': [
            {
              'id': 'scr_commandes',
              'code': 'SCR-001',
              'name': 'Poste ADV',
              'routeId': 'route_commandes',
              'pattern': 'masterDetail',
              'primaryObjectId': 'obj_commande',
              'zones': [
                {
                  'zone': 'center',
                  'slots': [
                    {
                      'id': 'slot_cmd_detail',
                      'title': 'Fiche commande',
                      'kind': 'detailCard',
                      'businessObjectId': 'obj_commande',
                      'attributeNames': ['numero', 'prioritePreparation'],
                    },
                  ],
                },
              ],
            },
          ],
        },
        'specPatch': {
          'removeBusinessObjectIds': ['obj_client'],
          'businessObjects': [
            {
              'id': 'obj_commande',
              'name': 'Commande',
              'technicalName': 'Commande',
              'attributes': [
                {
                  'id': 'attr_priorite_prep',
                  'name': 'prioritePreparation',
                  'type': 'enum',
                  'enumValues': ['normale', 'urgente'],
                },
              ],
            },
          ],
          'businessRules': [
            {
              'id': 'rule_rg_010',
              'code': 'RG-010',
              'title': 'Priorité urgente réservée aux comptes VIP',
              'category': 'permission',
              'targetObjectIds': ['obj_commande'],
            },
          ],
        },
        'stageSummary': 'Écran SCR-001 relié à Commande et RG-010.',
        'stageReadyToAdvance': true,
      };
      final fullJson = jsonEncode(responsePayload);
      final cut1 = fullJson.indexOf('SCR-001') + 7;
      final cut2 = fullJson.indexOf('"specPatch"');

      final fakeAi = FakeSpecAiService([
        [
          fullJson.substring(0, cut1),
          fullJson.substring(cut1, cut2),
          fullJson.substring(cut2),
        ],
      ]);

      final memoryStore = _MemorySpecProjectStore();
      final seeded = _buildRichBusinessProject();
      await memoryStore.saveProject(seeded);

      final controller = SpecForgeController(
        store: memoryStore,
        glossaryStore: _MemoryCompanyGlossaryStore(),
        modelDictionaryStore: _MemoryModelDictionaryStore(),
        domainCatalogStore: _MemoryDomainCatalogStore(),
        aiService: fakeAi,
        initialQuestioningLevel: VibeQuestioningLevel.none,
      );
      addTearDown(controller.dispose);

      await controller.initialize(restoreLastProject: true);
      await controller.goToUxStage(UxForgeStage.screenBlueprints);

      final observedStreamingMessages = <String>[];
      final observedStatuses = <String>[];
      var sawSendingUx = false;
      UxForgeStage? observedSendingUxStage;

      controller.addListener(() {
        if (controller.isSendingUx) {
          sawSendingUx = true;
          observedSendingUxStage = controller.sendingUxStage;
        }
        final msg = controller.streamingMessage;
        if (msg != null && msg.isNotEmpty) {
          observedStreamingMessages.add(msg);
        }
        if (controller.streamingStatus.isNotEmpty) {
          observedStatuses.add(controller.streamingStatus);
        }
      });

      await controller.sendUxUserMessage(
        'Conçois le poste ADV pour les commandes avec gestion de priorité.',
      );

      expect(sawSendingUx, isTrue);
      expect(observedSendingUxStage, UxForgeStage.screenBlueprints);
      expect(controller.isSendingUx, isFalse);
      expect(
        observedStreamingMessages.first,
        contains('J’ai conçu l’écran SCR-001'),
      );
      expect(
        observedStatuses,
        contains('Mise à jour de la spécification UX…'),
      );
      expect(fakeAi.receivedPrompts.length, 1);

      final updated = controller.project!;
      expect(updated.uxSpec.navigation.routes.single.id, 'route_commandes');
      expect(updated.uxSpec.screens.single.id, 'scr_commandes');

      // Vérifie que specPatch a enrichi Commande et ajouté RG-010 sans supprimer Client ni les attributs existants
      expect(updated.findBusinessObject('obj_client'), isNotNull);
      final commande = updated.findBusinessObject('obj_commande')!;
      expect(
        commande.attributes.map((a) => a.name).toList(),
        ['numero', 'statut', 'lignes', 'prioritePreparation'],
      );
      expect(
        updated.businessRules.map((r) => r.code).toList(),
        ['RG-001', 'RG-002', 'RG-010'],
      );

      final uxStageState = updated.uxSpec.stageStateFor(
        UxForgeStage.screenBlueprints,
      );
      expect(uxStageState.messages.length, 2);
      expect(uxStageState.messages.last.isUser, isFalse);
      expect(uxStageState.messages.last.appliedPatchSummary, isNotEmpty);
      expect(uxStageState.readyToAdvance, isTrue);
      expect(
        uxStageState.stageSummary,
        'Écran SCR-001 relié à Commande et RG-010.',
      );

      // Le tour IA UX complet s'annule et se rétablit en 1 clic via Undo / Redo
      expect(controller.canUndo, isTrue);
      await controller.undo();
      expect(controller.project!.uxSpec.screens, isEmpty);
      expect(
        controller.project!
            .findBusinessObject('obj_commande')!
            .attributes
            .any((a) => a.name == 'prioritePreparation'),
        isFalse,
      );
      expect(controller.project!.businessRules.length, 2);

      await controller.redo();
      expect(controller.project!.uxSpec.screens.single.id, 'scr_commandes');
      expect(controller.project!.businessRules.length, 3);
    });
  });
}
