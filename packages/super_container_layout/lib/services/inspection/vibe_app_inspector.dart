/// Service d'introspection runtime en lecture seule ([VibeAppInspector]) pour Vibe IA.
///
/// Fournit l'implémentation concrète des outils exposés via [VibeAppToolRegistry] :
/// - `get_viewport_and_route` : dimensions fenêtre/viewport, route GoRouter, page active et scope ;
/// - `get_component_geometry` : taille réelle en dp, position, contraintes, scroll et diagnostics ;
/// - `get_runtime_tree` : arbre hiérarchique effectivement monté sur la page courante ;
/// - `query_repository_data` : catalogue, schémas, extraits paginés et sélections de [JsonRepositoryStore] ;
/// - `capture_screenshot` : capture PNG plafonnée en résolution depuis les [RenderRepaintBoundary].
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../ai/design_md_parser.dart';
import '../../ai/design_system_catalog.dart';
import '../../ai/vibe_app_tools.dart';
import '../../ai/vibe_chat_attachment.dart';
import '../appearance/custom_design_system_store.dart';
import '../../models/editor_page_config.dart';
import '../../models/json_text_binding.dart';
import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/repository_json_schema.dart';
import '../../models/responsive_layout_config.dart';
import '../../models/scaffold_page_config.dart';
import '../../models/super_conditional_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_list_view_config.dart';
import '../../models/super_tab_config.dart';
import '../../models/super_table_config.dart';
import '../../models/super_tree_view_config.dart';
import '../../theme/appearance.dart';
import '../../widgets/components/super_layout/layout_selection.dart';
import '../../widgets/editing/ai/vibe_repository_applier.dart';
import '../../widgets/editing/ai/vibe_scope_helpers.dart';
import '../../widgets/editing/overlay/editor_overlay.dart'
    show isRenderObjectOffstage;
import '../../widgets/editing/slots/editor_context_menu.dart'
    show VibeChatScope;
import '../../widgets/editing/slots/editor_slot.dart'
    show EditorSlotState, StyleEditScope;
import '../fonts/design_md_font_extractor.dart';
import '../fonts/dynamic_font_manager.dart';
import '../pages/editor_page_router.dart';
import '../repositories/json_repository_store.dart';
import '../repositories/json_schema_validator.dart';
import 'vibe_debug_capture.dart';
import 'vibe_diagnostics_inspector.dart';
import 'vibe_mounted_slot_index.dart';
import 'vibe_page_audit.dart';

/// État immuable d'un composant `SuperTab` visible en mode « Uniquement visible ».
@immutable
class VibeVisibleTabState {
  /// Construit le descripteur de l'onglet actif à conserver.
  VibeVisibleTabState({
    required this.tabComponentId,
    required this.activeIndex,
    required this.tabId,
    required this.label,
    required this.contentZone,
    List<String> inactiveZones = const <String>[],
  }) : inactiveZones = List<String>.unmodifiable(inactiveZones);

  /// Identifiant du composant `SuperTab`.
  final String tabComponentId;

  /// Indice 0-based de l'onglet actuellement affiché.
  final int activeIndex;

  /// Identifiant du slot d'onglet actif.
  final String tabId;

  /// Libellé lisible de l'onglet actif.
  final String label;

  /// Zone de contenu active (`content:<tabId>` ou `content`).
  final String contentZone;

  /// Zones de contenu des onglets inactifs (à préserver sans modification).
  final List<String> inactiveZones;
}

/// Instantané immuable de l'onglet actif, de la position de scroll et des composants
/// réellement visibles à l'écran pour le mode « Uniquement visible ».
@immutable
class VibeVisibleViewportSnapshot {
  /// Construit un instantané de visibilité viewport.
  VibeVisibleViewportSnapshot({
    required this.hasMeasuredViewport,
    Set<String> visibleComponentIds = const <String>{},
    Set<String> ancestorComponentIds = const <String>{},
    Set<String> protectedOffscreenComponentIds = const <String>{},
    List<String> orderedVisibleSlotSummaries = const <String>[],
    List<VibeVisibleTabState> activeTabs = const <VibeVisibleTabState>[],
    List<String> scrollPositionSummaries = const <String>[],
  }) : visibleComponentIds = Set<String>.unmodifiable(visibleComponentIds),
       ancestorComponentIds = Set<String>.unmodifiable(ancestorComponentIds),
       protectedOffscreenComponentIds = Set<String>.unmodifiable(
         protectedOffscreenComponentIds,
       ),
       orderedVisibleSlotSummaries = List<String>.unmodifiable(
         orderedVisibleSlotSummaries,
       ),
       activeTabs = List<VibeVisibleTabState>.unmodifiable(activeTabs),
       scrollPositionSummaries = List<String>.unmodifiable(
         scrollPositionSummaries,
       );

  /// Indique si au moins un `RenderBox` monté a pu être mesuré à l'écran.
  final bool hasMeasuredViewport;

  /// Identifiants des composants ayant une surface effectivement visible dans le viewport courant.
  final Set<String> visibleComponentIds;

  /// Conteneurs ancêtres menant aux composants visibles (ex. `root`, `mainLayout`, `SuperTab` actif).
  final Set<String> ancestorComponentIds;

  /// Composants existants de la page situés hors champ (onglet inactif ou hors scroll courant),
  /// à ne ni modifier ni supprimer.
  final Set<String> protectedOffscreenComponentIds;

  /// Résumés ordonnés (haut → bas, gauche → droite) des slots et zones visibles à l'écran.
  final List<String> orderedVisibleSlotSummaries;

  /// Onglets actuellement affichés dans les `SuperTab` visibles.
  final List<VibeVisibleTabState> activeTabs;

  /// Positions actuelles des zones défilables montées.
  final List<String> scrollPositionSummaries;

  /// Formate le contexte runtime injecté dans le prompt IA en mode « Uniquement visible ».
  String toPromptContext() {
    final buffer = StringBuffer()
      ..writeln(
        'CONTEXTE RUNTIME « UNIQUEMENT VISIBLE » (ONGLET & SCROLL COURANTS) :',
      );
    if (activeTabs.isNotEmpty) {
      buffer.writeln('• Onglet(s) actif(s) verrouillé(s) :');
      for (final tab in activeTabs) {
        final inactiveInfo = tab.inactiveZones.isEmpty
            ? ''
            : ' | zones inactives interdites : ${tab.inactiveZones.join(', ')}';
        buffer.writeln(
          '  - ${tab.tabComponentId} → onglet actif [${tab.activeIndex}] "${tab.label}" '
          '(zone active : "${tab.contentZone}"$inactiveInfo)',
        );
      }
    }
    if (scrollPositionSummaries.isNotEmpty) {
      buffer.writeln('• Position(s) de scroll courante(s) verrouillée(s) :');
      for (final s in scrollPositionSummaries) {
        buffer.writeln('  - $s');
      }
    }
    if (orderedVisibleSlotSummaries.isNotEmpty) {
      buffer.writeln(
        '• Éléments et zones actuellement visibles à l’écran (${orderedVisibleSlotSummaries.length}) : '
        '${orderedVisibleSlotSummaries.take(45).join(', ')}',
      );
    }
    if (protectedOffscreenComponentIds.isNotEmpty) {
      final sample = protectedOffscreenComponentIds.take(35).join(', ');
      final more = protectedOffscreenComponentIds.length > 35
          ? ' (+${protectedOffscreenComponentIds.length - 35} autres)'
          : '';
      buffer.writeln(
        '• Composants hors champ (onglets masqués ou hors scroll courant — NE PAS modifier ni retirer des placements) : '
        '$sample$more',
      );
    }
    return buffer.toString().trimRight();
  }
}

/// Service d'introspection runtime de l'application Flutter exposé à Vibe IA.
class VibeAppInspector {
  /// Crée un inspecteur connecté à l'état courant de l'application.
  VibeAppInspector({
    required this.readAppearance,
    VibeMountedSlotIndex? slotIndex,
    this.registry,
    this.repositoryStore,
    this.pageRouting,
    this.ensurePageLoaded,
    this.readScope,
    this.readVisibleOnly,
    this.onSelectScope,
    this.fallbackContext,
    this.turnStartMarker,
    this.previewTracker,
    this.repoTransaction,
    this.customDesignSystemStore,
    this.onRegisterDesignSystem,
    this.fontManager,
    this.waitForFrame,
    this.allowEndOfFrameInWidgetTests = false,
  }) : slotIndex = slotIndex ?? VibeMountedSlotIndex.instance;

  /// Fournisseur de l'[Appearance] active (incluant les éventuels défauts runtime).
  final Appearance Function() readAppearance;

  /// Index des slots et de la racine applicative montés.
  final VibeMountedSlotIndex slotIndex;

  /// Registre optionnel des composants pour compléter les métadonnées.
  final Registry? registry;

  /// Store optionnel de repositories JSON.
  final JsonRepositoryStore? repositoryStore;

  /// Transaction optionnelle du tour Vibe pour enregistrer les mutations de schémas.
  final VibeRepositoryTurnTransaction? repoTransaction;

  /// Routeur GoRouter dynamique optionnel.
  final EditorPageRouter? pageRouting;

  /// Callback optionnel chargeant à la demande une page avant navigation d'aperçu.
  final Future<void> Function(String pageId)? ensurePageLoaded;

  /// Fournisseur optionnel du périmètre restreint actif dans le chat Vibe.
  final VibeChatScope? Function()? readScope;

  /// Indique si le mode « Uniquement visible » restreint l'IA à l'onglet et au scroll courants.
  final bool Function()? readVisibleOnly;

  /// Callback optionnel permettant de mettre à jour le `VibeChatScope` du chat.
  final ValueChanged<VibeChatScope?>? onSelectScope;

  /// Contexte Flutter de repli (ex. celui de `VibeChatDialog`) si aucune racine `SuperApp` n'est enregistrée.
  final BuildContext? Function()? fallbackContext;

  /// Repère optionnel dans `debugEntries` capturé au début du tour courant.
  final VibeDebugMarker? turnStartMarker;

  /// Suivi optionnel des modifications d'aperçu réversibles.
  final VibePreviewStateTracker? previewTracker;

  /// Magasin disque optionnel utilisé en repli si [onRegisterDesignSystem] est absent.
  final CustomDesignSystemStore? customDesignSystemStore;

  /// Callback appelé par `register_design_system` pour enregistrer et éventuellement activer un `DESIGN.md`.
  final Future<({String? persistedPath, int totalCustomPresets})> Function(
    DesignSystemPreset preset, {
    required bool select,
  })?
  onRegisterDesignSystem;

  /// Gestionnaire optionnel de polices dynamiques utilisé pour le préchargement et les diagnostics.
  final DynamicFontManager? fontManager;

  /// Callback optionnel d'attente d'une frame de rendu (utile notamment en test).
  final Future<void> Function()? waitForFrame;

  /// Autorise l'attente de `SchedulerBinding.endOfFrame` sous `TestWidgetsFlutterBinding`
  /// lorsqu'une boucle `pumpUntil` / `pumpAndSettle` pompe activement les frames.
  final bool allowEndOfFrameInWidgetTests;

  late final VibeDiagnosticsInspector _diagnostics = VibeDiagnosticsInspector(
    readAppearance: readAppearance,
    slotIndex: slotIndex,
    resolvePrimaryContext: _resolvePrimaryContext,
    registry: registry,
    repositoryStore: repositoryStore,
    pageRouting: pageRouting,
    ensurePageLoaded: ensurePageLoaded,
    readScope: readScope,
    readVisibleOnly: readVisibleOnly,
    onSelectScope: onSelectScope,
    turnStartMarker: turnStartMarker,
    previewTracker: previewTracker,
    fontManager: fontManager,
    waitForVisualFrame: waitForVisualFrame,
  );

  /// Construit le [VibeAppToolRegistry] complet exposant l'ensemble des outils d'introspection.
  VibeAppToolRegistry buildToolRegistry() =>
      VibeAppToolRegistry.fromStandardHandlers(<String, VibeToolHandler>{
        'get_viewport_and_route': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await getViewportAndRoute(),
        ),
        'get_component_geometry': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await getComponentGeometry(call.arguments),
        ),
        'get_runtime_tree': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await getRuntimeTree(call.arguments),
        ),
        'query_repository_data': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await queryRepositoryData(call.arguments),
        ),
        'manage_repository_json_schema': (call) =>
            manageRepositoryJsonSchema(call.id, call.name, call.arguments),
        'capture_element_screenshot': (call) =>
            captureElementScreenshot(call.id, call.name, call.arguments),
        'capture_screenshot': (call) =>
            captureScreenshot(call.id, call.name, call.arguments),
        'get_debug_entries': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await getDebugEntries(call.arguments),
        ),
        'get_datasources_and_providers': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await getDatasourcesAndProviders(call.arguments),
        ),
        'inspect_bindings_and_diagnostics': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await inspectBindingsAndDiagnostics(call.arguments),
        ),
        'get_theme_and_contrast': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await getThemeAndContrast(call.arguments),
        ),
        'get_registry_and_selection': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await getRegistryAndSelection(call.arguments),
        ),
        'preview_navigation_or_selection': (call) =>
            previewNavigationOrSelection(call.id, call.name, call.arguments),
        'select_editor_element': (call) =>
            selectEditorElement(call.id, call.name, call.arguments),
        'register_design_system': (call) =>
            registerDesignSystem(call.id, call.name, call.arguments),
        'audit_active_page': (call) async {
          final report = await VibePageAuditService.collect(this);
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: report.toJson(),
          );
        },
        'validate_or_list_icons': (call) async =>
            validateOrListIcons(call.id, call.name, call.arguments),
      });

  /// Lit et filtre les journaux et erreurs d'exécution depuis `debugEntries`.
  Future<Map<String, Object?>> getDebugEntries(Map<String, Object?> args) =>
      _diagnostics.getDebugEntries(args);

  /// Inspecte le catalogue et l'état runtime de `DatasourceRegistry` et `DataProviderRegistry`.
  Future<Map<String, Object?>> getDatasourcesAndProviders(
    Map<String, Object?> args,
  ) => _diagnostics.getDatasourcesAndProviders(args);

  /// Audite la santé des liaisons JSON, les composants orphelins et les états forcés.
  Future<Map<String, Object?>> inspectBindingsAndDiagnostics(
    Map<String, Object?> args,
  ) => _diagnostics.inspectBindingsAndDiagnostics(args);

  /// Résout les rôles `theme:*` en `#RRGGBB` et vérifie les contrastes WCAG AA.
  Future<Map<String, Object?>> getThemeAndContrast(Map<String, Object?> args) =>
      _diagnostics.getThemeAndContrast(args);

  /// Expose les constructeurs/extensions de `Registry`, les polices et la sélection active.
  Future<Map<String, Object?>> getRegistryAndSelection(
    Map<String, Object?> args,
  ) => _diagnostics.getRegistryAndSelection(args);

  /// Valide un ou plusieurs identifiants d'icônes et/ou liste les icônes disponibles dans `MaterialIconCatalog`.
  VibeToolResult validateOrListIcons(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) => _diagnostics.validateOrListIcons(callId, toolName, args);

  /// Navigue temporairement vers une page ou sélectionne une ligne Maître/Détail en aperçu.
  Future<VibeToolResult> previewNavigationOrSelection(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) => _diagnostics.previewNavigationOrSelection(callId, toolName, args);

  /// Sélectionne (ou désélectionne) à distance un élément sur le canevas du mode édition.
  Future<VibeToolResult> selectEditorElement(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) => _diagnostics.selectEditorElement(callId, toolName, args);

  BuildContext? _resolvePrimaryContext() {
    final appRootCtx = slotIndex.activeAppRootKey?.currentContext;
    if (appRootCtx != null && appRootCtx.mounted) return appRootCtx;
    for (final entry in slotIndex.allEntries) {
      final ctx = entry.slotContext();
      if (ctx != null && ctx.mounted) return ctx;
    }
    final fallback = fallbackContext?.call();
    if (fallback != null && fallback.mounted) return fallback;
    return null;
  }

  Future<void> _settleFrameIfNeeded(RenderObject? target) async {
    final scheduler = SchedulerBinding.instance;
    final needsLayout = target != null && target.debugNeedsLayout;
    final missingSize = target is RenderBox && !target.hasSize;
    if ((needsLayout || missingSize) && scheduler.hasScheduledFrame) {
      try {
        await scheduler.endOfFrame.timeout(const Duration(milliseconds: 250));
      } on TimeoutException {
        // Ne bloque pas en environnement sans pompe de frames (ex. tests unitaires).
      }
    }
  }

  static double _round2(double value) => (value * 100).roundToDouble() / 100;

  static Object? _serializeBound(double value) =>
      value.isFinite ? _round2(value) : null;

  static Map<String, Object?> _rectToJson(Rect rect) => <String, Object?>{
    'left': _round2(rect.left),
    'top': _round2(rect.top),
    'width': _round2(rect.width),
    'height': _round2(rect.height),
    'right': _round2(rect.right),
    'bottom': _round2(rect.bottom),
  };

  RenderBox? _resolveRootBox(BuildContext? context) {
    final rootKeyCtx = slotIndex.activeAppRootKey?.currentContext;
    final rootObj = rootKeyCtx?.findRenderObject();
    if (rootObj is RenderBox && rootObj.attached && rootObj.hasSize) {
      return rootObj;
    }
    if (context == null || !context.mounted) return null;
    final mediaBox = context
        .findAncestorRenderObjectOfType<RenderRepaintBoundary>();
    if (mediaBox != null && mediaBox.attached && mediaBox.hasSize) {
      return mediaBox;
    }
    return null;
  }

  /// Résout la page active à partir de la route courante ou de `homePageId`.
  EditorPageConfig? resolveActivePage(Appearance appearance) {
    final uri = pageRouting?.currentUri;
    final pages = appearance.pageCatalog.pages;
    if (pages.isEmpty) return null;
    if (uri != null && uri.path.isNotEmpty) {
      final matched = pageRouting?.pageAt(uri, catalog: appearance.pageCatalog);
      if (matched != null) return matched;
      for (final page in pages) {
        if (page.path == uri.path) return page;
      }
    }
    final homeId = appearance.pageCatalog.homePageId;
    if (homeId != null) {
      for (final page in pages) {
        if (page.id == homeId) return page;
      }
    }
    return pages.first;
  }

  /// Collecte les identifiants de composants du [VibeChatScope] actif ou de la page active.
  Set<String> collectScopeOrActivePageComponentIds(Appearance appearance) {
    final scope = readScope?.call();
    if (scope != null) {
      return <String>{
        ...scope.canonicalComponentIds,
        ...VibeScopeHelpers.parentIdsOfScope(appearance, scope),
        ...VibeScopeHelpers.existingSubtreeIds(appearance, scope),
      };
    }

    final seeds = <String>{};
    final activePage = resolveActivePage(appearance);
    if (activePage != null) {
      seeds.add(activePage.id);
    } else if (appearance.components.containsKey('root')) {
      seeds.add('root');
    } else if (appearance.components.containsKey('mainLayout')) {
      seeds.add('mainLayout');
    }
    for (final mountedId in slotIndex.mountedComponentIds) {
      if (appearance.components.containsKey(mountedId)) {
        seeds.add(mountedId);
      }
    }
    if (seeds.isEmpty) {
      seeds.addAll(slotIndex.mountedComponentIds);
    }

    final collected = <String>{};
    final queue = <String>[...seeds];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      if (!collected.add(id)) continue;
      if (id == 'scaffold:body' &&
          appearance.components.containsKey('mainLayout') &&
          !collected.contains('mainLayout')) {
        queue.add('mainLayout');
      }
      final config = appearance.components[id];
      for (final childId in VibeScopeHelpers.childrenOfComponent(config)) {
        if (!collected.contains(childId)) {
          queue.add(childId);
        }
      }
    }
    return collected;
  }

  EditorPageConfig? _resolveActivePage(Appearance appearance) =>
      resolveActivePage(appearance);

  /// Retourne l'état du viewport, de la route active, du mode édition et du scope.
  Future<Map<String, Object?>> getViewportAndRoute() async {
    final appearance = readAppearance();
    final ctx = _resolvePrimaryContext();
    final media = ctx != null ? MediaQuery.maybeOf(ctx) : null;
    final editMode = ctx != null
        ? StyleEditScope.controllerOf(ctx)?.value
        : null;
    final scope = readScope?.call();
    final activePage = _resolveActivePage(appearance);
    final baseResponsive = activePage != null
        ? appearance.effectiveResponsiveLayoutForPage(activePage.id)
        : appearance.responsiveLayout;
    final effectiveResponsive = (activePage?.pageType.isModal ?? false)
        ? baseResponsive.copyWith(containerMode: PageContainerMode.fullPage)
        : baseResponsive;
    final resolvedResponsive = media != null
        ? effectiveResponsive.resolveForWidth(media.size.width)
        : null;

    String? currentLocation;
    try {
      currentLocation = pageRouting?.currentUri.toString();
    } catch (_) {
      currentLocation = null;
    }

    return <String, Object?>{
      if (media != null)
        'viewport': <String, Object?>{
          'width': _round2(media.size.width),
          'height': _round2(media.size.height),
          'devicePixelRatio': _round2(media.devicePixelRatio),
          'padding': <String, Object?>{
            'left': _round2(media.padding.left),
            'top': _round2(media.padding.top),
            'right': _round2(media.padding.right),
            'bottom': _round2(media.padding.bottom),
          },
          'viewInsetsBottom': _round2(media.viewInsets.bottom),
        },
      'route': <String, Object?>{
        'location': currentLocation,
        if (activePage != null)
          'activePage': <String, Object?>{
            'id': activePage.id,
            'name': activePage.name,
            'path': activePage.path,
            'pageType': activePage.pageType.name,
            if (activePage.pageType.isModal) 'isModal': true,
            if (activePage.modalWidth != null)
              'modalWidth': activePage.modalWidth,
            if (activePage.modalHeight != null)
              'modalHeight': activePage.modalHeight,
          },
        if (pageRouting != null)
          'codedRoutes': <String>[
            for (final route in pageRouting!.codedRoutes) route.path,
          ],
        'homePageId': appearance.pageCatalog.homePageId,
        'pageCount': appearance.pageCatalog.pages.length,
      },
      'responsive': <String, Object?>{
        'containerMode': effectiveResponsive.containerMode.name,
        if (resolvedResponsive != null) ...<String, Object?>{
          'breakpoint': resolvedResponsive.breakpoint.name,
          'gutter': _round2(resolvedResponsive.gutter),
          if (resolvedResponsive.maxWidth != null)
            'maxWidth': _round2(resolvedResponsive.maxWidth!),
        },
      },
      'editMode': ?editMode,
      if (scope != null)
        'scope': <String, Object?>{
          'componentId': scope.canonicalComponentId,
          'rawComponentId': scope.componentId,
          'zoneId': ?scope.zoneId,
          'displayLabel': scope.displayLabel,
          if (scope.isMultiTarget) 'multiTarget': true,
          if (scope.isMultiTarget)
            'targets': [
              for (final target in scope.allTargets)
                <String, Object?>{
                  'componentId': target.canonicalComponentId,
                  'rawComponentId': target.componentId,
                  'zoneId': ?target.zoneId,
                  'displayLabel': target.displayLabel,
                },
            ],
        },
      'mountedComponentCount': slotIndex.mountedComponentIds.length,
      if (collectActiveMountedTabEntries(
            allowedComponentIds: collectScopeOrActivePageComponentIds(
              appearance,
            ),
          )
          case final activeTabs when activeTabs.isNotEmpty)
        'mountedTabs': [
          for (final entry in activeTabs)
            if (entry.readSnapshot() case final snap? when snap.tabCount > 0)
              snap.toJson(),
        ],
    };
  }

  /// Attend la fin de la frame de rendu planifiée après une bascule d'aperçu ou d'onglet.
  Future<void> waitForVisualFrame() async {
    if (waitForFrame != null) {
      await waitForFrame!();
      return;
    }
    final scheduler = SchedulerBinding.instance;
    scheduler.ensureVisualUpdate();
    final isWidgetTest = WidgetsBinding.instance.runtimeType
        .toString()
        .contains('TestWidgetsFlutterBinding');
    if (isWidgetTest && !allowEndOfFrameInWidgetTests) {
      return;
    }
    if (scheduler.hasScheduledFrame) {
      try {
        await scheduler.endOfFrame.timeout(const Duration(milliseconds: 250));
      } on TimeoutException {
        return;
      }
    }
    if (scheduler.hasScheduledFrame) {
      try {
        await scheduler.endOfFrame.timeout(const Duration(milliseconds: 250));
      } on TimeoutException {
        // Poursuit sans blocage.
      }
    }
  }

  /// Retourne les entrées `SuperTab` montées et visibles (non offstage), filtrées le cas échéant sur [allowedComponentIds].
  List<VibeMountedTabEntry> collectActiveMountedTabEntries({
    Set<String>? allowedComponentIds,
  }) {
    final rootBox = _resolveRootBox(_resolvePrimaryContext());
    final active = <VibeMountedTabEntry>[];
    final seenIds = <String>{};
    for (final entry in slotIndex.allTabEntries.reversed) {
      if (allowedComponentIds != null &&
          !allowedComponentIds.contains(entry.componentId)) {
        continue;
      }
      final ctx = entry.tabContext();
      if (ctx == null || !ctx.mounted) continue;
      final ro = ctx.findRenderObject();
      if (ro != null &&
          (!ro.attached || isRenderObjectOffstage(ro, stopAt: rootBox))) {
        continue;
      }
      if (seenIds.add(entry.componentId)) {
        active.add(entry);
      }
    }
    return active.reversed.toList(growable: false);
  }

  /// Mesure la géométrie réelle des composants demandés ou du périmètre actif.
  Future<Map<String, Object?>> getComponentGeometry(
    Map<String, Object?> args,
  ) async {
    final appearance = readAppearance();
    final scope = readScope?.call();
    final zoneFilter =
        args['zoneId'] is String && (args['zoneId'] as String).trim().isNotEmpty
        ? (args['zoneId'] as String).trim()
        : null;
    final includeScroll = args['includeScroll'] is bool
        ? args['includeScroll'] as bool
        : true;
    final includeZones = args['includeZones'] is bool
        ? args['includeZones'] as bool
        : true;

    final requestedIds = <String>[];
    final rawIds = args['ids'];
    if (rawIds is List) {
      for (final item in rawIds) {
        if (item is String && item.trim().isNotEmpty) {
          requestedIds.add(item.trim());
        }
      }
    } else if (args['id'] is String &&
        (args['id'] as String).trim().isNotEmpty) {
      requestedIds.add((args['id'] as String).trim());
    }

    if (requestedIds.isEmpty) {
      if (scope != null) {
        requestedIds.addAll(scope.canonicalComponentIds);
        requestedIds.addAll(
          VibeScopeHelpers.parentIdsOfScope(appearance, scope),
        );
      } else {
        final activePage = _resolveActivePage(appearance);
        if (activePage != null &&
            slotIndex.entriesFor(activePage.id).isNotEmpty) {
          requestedIds.add(activePage.id);
        } else {
          requestedIds.addAll(slotIndex.mountedComponentIds.take(20));
        }
      }
    }

    final uniqueIds = requestedIds.toSet().toList();
    final primaryCtx = _resolvePrimaryContext();
    final viewportSize = primaryCtx != null
        ? MediaQuery.maybeSizeOf(primaryCtx)
        : null;
    final rootBox = _resolveRootBox(primaryCtx);

    final results = <String, Object?>{};
    for (final id in uniqueIds) {
      var entries = slotIndex.entriesFor(id, zoneId: zoneFilter);
      if (zoneFilter == null && !includeZones) {
        entries = entries
            .where((e) => e.zoneId == null || e.zoneId!.isEmpty)
            .toList();
      }
      if (entries.isEmpty) {
        results[id] = <String, Object?>{
          'mounted': false,
          'configured':
              appearance.components.containsKey(id) ||
              appearance.styles.containsKey(id),
          'occurrences': const <Object?>[],
        };
        continue;
      }

      final occurrences = <Map<String, Object?>>[];
      for (final entry in entries) {
        final slotCtx = entry.slotContext();
        final contentCtx = entry.contentKey.currentContext;
        final targetCtx = (contentCtx != null && contentCtx.mounted)
            ? contentCtx
            : slotCtx;
        if (targetCtx == null || !targetCtx.mounted) continue;

        final renderObj = targetCtx.findRenderObject();
        await _settleFrameIfNeeded(renderObj);

        if (renderObj == null || !renderObj.attached) continue;

        final item = <String, Object?>{
          'componentId': entry.componentId,
          if (entry.zoneId != null) 'zoneId': entry.zoneId,
          'label': entry.label,
          'componentType': entry.componentType,
          'fixedWidth': entry.fixedWidth,
          'fixedHeight': entry.fixedHeight,
          'scrollable': entry.scrollable,
        };

        if (renderObj is RenderBox && renderObj.hasSize) {
          final size = renderObj.size;
          item['size'] = <String, Object?>{
            'width': _round2(size.width),
            'height': _round2(size.height),
          };
          final constraints = renderObj.constraints;
          item['constraints'] = <String, Object?>{
            'minWidth': _round2(constraints.minWidth),
            'maxWidth': _serializeBound(constraints.maxWidth),
            'minHeight': _round2(constraints.minHeight),
            'maxHeight': _serializeBound(constraints.maxHeight),
            'hasBoundedWidth': constraints.hasBoundedWidth,
            'hasBoundedHeight': constraints.hasBoundedHeight,
          };

          final isOffstage = isRenderObjectOffstage(renderObj, stopAt: rootBox);
          final origin = rootBox != null
              ? renderObj.localToGlobal(Offset.zero, ancestor: rootBox)
              : renderObj.localToGlobal(Offset.zero);
          final globalRect = !isOffstage && origin.isFinite && size.isFinite
              ? (origin & size)
              : null;
          if (globalRect != null) {
            item['bounds'] = _rectToJson(globalRect);
          }

          final parentObj = renderObj.parent;
          var exceedsParentWidth = false;
          var exceedsParentHeight = false;
          if (parentObj is RenderBox &&
              parentObj.attached &&
              parentObj.hasSize) {
            final localOffset = renderObj.localToGlobal(
              Offset.zero,
              ancestor: parentObj,
            );
            if (localOffset.isFinite) {
              item['parentRelative'] = <String, Object?>{
                'left': _round2(localOffset.dx),
                'top': _round2(localOffset.dy),
                'parentWidth': _round2(parentObj.size.width),
                'parentHeight': _round2(parentObj.size.height),
              };
              const eps = 0.5;
              exceedsParentWidth =
                  localOffset.dx < -eps ||
                  localOffset.dx + size.width > parentObj.size.width + eps;
              exceedsParentHeight =
                  localOffset.dy < -eps ||
                  localOffset.dy + size.height > parentObj.size.height + eps;
            }
          }

          final ancestorClip = !isOffstage
              ? _inspectAncestorClipping(renderObj, size, rootBox)
              : (clipped: false, edges: const <String>[]);
          final clipsChildContent = !isOffstage
              ? _inspectChildOverflow(renderObj, size)
              : false;
          final truncatedTexts = !isOffstage
              ? _inspectTruncatedTexts(renderObj)
              : const <String>[];
          final visibleRectInViewport = !isOffstage
              ? _computeViewportVisibleRect(
                  renderObj,
                  size,
                  rootBox,
                  viewportSize,
                )
              : null;

          item['diagnostics'] = <String, Object?>{
            'isZeroSized': size.width <= 0.0 || size.height <= 0.0,
            'isVisibleInViewport': visibleRectInViewport != null,
            if (exceedsParentWidth) 'exceedsParentWidth': true,
            if (exceedsParentHeight) 'exceedsParentHeight': true,
            if (ancestorClip.clipped) ...<String, Object?>{
              'isClippedByAncestor': true,
              'clippedEdges': ancestorClip.edges,
            },
            if (clipsChildContent) 'clipsChildContent': true,
            if (truncatedTexts.isNotEmpty) ...<String, Object?>{
              'hasTruncatedText': true,
              'truncatedTextSamples': truncatedTexts,
            },
            if (globalRect == null || visibleRectInViewport == null)
              'isOffscreen': true
            else if (viewportSize != null) ...<String, Object?>{
              'exceedsViewportWidth':
                  globalRect.right > viewportSize.width + 0.5 ||
                  globalRect.left < -0.5,
              'exceedsViewportHeight':
                  globalRect.bottom > viewportSize.height + 0.5 ||
                  globalRect.top < -0.5,
              'isOffscreen': false,
            },
          };
        } else if (renderObj is RenderSliver) {
          final sliverGeo = renderObj.geometry;
          final sliverConstraints = renderObj.constraints;
          item['isSliver'] = true;
          item['sliver'] = <String, Object?>{
            'axis': sliverConstraints.axis.name,
            'crossAxisExtent': _round2(sliverConstraints.crossAxisExtent),
            'viewportMainAxisExtent': _round2(
              sliverConstraints.viewportMainAxisExtent,
            ),
            if (sliverGeo != null) ...<String, Object?>{
              'paintExtent': _round2(sliverGeo.paintExtent),
              'layoutExtent': _round2(sliverGeo.layoutExtent),
              'scrollExtent': _round2(sliverGeo.scrollExtent),
              'hasVisualOverflow': sliverGeo.hasVisualOverflow,
            },
          };
        }

        if (includeScroll && slotCtx != null && slotCtx.mounted) {
          final scrollable = Scrollable.maybeOf(slotCtx);
          if (scrollable != null && scrollable.position.hasPixels) {
            final pos = scrollable.position;
            item['scroll'] = <String, Object?>{
              'axis': axisDirectionToAxis(pos.axisDirection).name,
              'pixels': _round2(pos.pixels),
              'minScrollExtent': _round2(pos.minScrollExtent),
              'maxScrollExtent': _round2(pos.maxScrollExtent),
              'viewportDimension': _round2(pos.viewportDimension),
              'canScroll': pos.maxScrollExtent > pos.minScrollExtent,
            };
          }
        }

        occurrences.add(item);
      }

      results[id] = <String, Object?>{
        'mounted': occurrences.isNotEmpty,
        'occurrenceCount': occurrences.length,
        'occurrences': occurrences,
      };
    }

    return <String, Object?>{
      if (viewportSize != null)
        'viewport': <String, Object?>{
          'width': _round2(viewportSize.width),
          'height': _round2(viewportSize.height),
        },
      'components': results,
    };
  }

  /// Construit une vue arborescente légère des composants et zones effectivement montés.
  Future<Map<String, Object?>> getRuntimeTree(Map<String, Object?> args) async {
    final appearance = readAppearance();
    final scope = readScope?.call();
    final rawDepth = args['maxDepth'];
    final maxDepth = (rawDepth is num ? rawDepth.toInt() : 6).clamp(1, 12);

    String? rootId =
        args['rootId'] is String && (args['rootId'] as String).trim().isNotEmpty
        ? (args['rootId'] as String).trim()
        : null;
    rootId ??= scope?.canonicalComponentId;
    rootId ??= _resolveActivePage(appearance)?.id;
    if (rootId == null) {
      for (final entry in appearance.components.entries) {
        if (entry.value is ScaffoldPageConfig ||
            entry.value is SuperLayoutConfig) {
          rootId = entry.key;
          break;
        }
      }
    }
    rootId ??= slotIndex.mountedComponentIds.firstOrNull;

    if (rootId == null) {
      return <String, Object?>{
        'rootId': null,
        'tree': null,
        'mountedIds': slotIndex.mountedComponentIds.toList(),
      };
    }

    var visitedNodes = 0;
    const maxNodes = 120;
    var truncated = false;
    final seenInBranch = <String>{};

    Map<String, Object?> buildNode(String id, int depth) {
      visitedNodes++;
      final config = appearance.components[id];
      final entries = slotIndex.entriesFor(id);
      final primaryEntry =
          entries
              .where((e) => e.zoneId == null || e.zoneId!.isEmpty)
              .firstOrNull ??
          entries.firstOrNull;

      Map<String, Object?>? primarySize;
      final primaryCtx =
          primaryEntry?.contentKey.currentContext ??
          primaryEntry?.slotContext();
      if (primaryCtx != null && primaryCtx.mounted) {
        final ro = primaryCtx.findRenderObject();
        if (ro is RenderBox && ro.attached && ro.hasSize) {
          primarySize = <String, Object?>{
            'width': _round2(ro.size.width),
            'height': _round2(ro.size.height),
          };
        }
      }

      final node = <String, Object?>{
        'id': id,
        'type':
            config?.componentType ?? primaryEntry?.componentType ?? 'unknown',
        if (primaryEntry != null) 'label': primaryEntry.label,
        'mounted': entries.isNotEmpty,
        if (entries.length > 1) 'occurrenceCount': entries.length,
        'size': ?primarySize,
      };

      if (depth >= maxDepth || visitedNodes >= maxNodes) {
        if (VibeScopeHelpers.childrenOfComponent(config).isNotEmpty) {
          node['truncated'] = true;
          truncated = true;
        }
        return node;
      }

      if (!seenInBranch.add(id)) {
        node['cycle'] = true;
        return node;
      }

      try {
        if (config is SuperLayoutConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            final zoneName = entry.key.name;
            final zoneEntries = slotIndex.entriesFor(id, zoneId: zoneName);
            final childNodes = <Map<String, Object?>>[];
            for (final childId in entry.value) {
              if (visitedNodes >= maxNodes) {
                truncated = true;
                break;
              }
              childNodes.add(buildNode(childId, depth + 1));
            }
            zones[zoneName] = <String, Object?>{
              'mounted': zoneEntries.isNotEmpty,
              if (config.collapsedSides.containsKey(entry.key))
                'collapsed': true,
              'children': childNodes,
            };
          }
          if (zones.isNotEmpty) {
            node['zones'] = zones;
          }
        } else if (config is NativeComponentConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            final childNodes = <Map<String, Object?>>[];
            for (final childId in entry.value) {
              if (visitedNodes >= maxNodes) {
                truncated = true;
                break;
              }
              childNodes.add(buildNode(childId, depth + 1));
            }
            zones[entry.key] = childNodes;
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else if (config is ScaffoldPageConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.native.placements.entries) {
            final childNodes = <Map<String, Object?>>[];
            for (final childId in entry.value) {
              if (visitedNodes >= maxNodes) {
                truncated = true;
                break;
              }
              childNodes.add(buildNode(childId, depth + 1));
            }
            zones[entry.key] = childNodes;
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else if (config is SuperListViewConfig) {
          node['templateChildren'] = [
            for (final entry in config.template.placements.entries)
              for (final childId in entry.value)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
          ];
        } else if (config is SuperTabConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            zones[entry.key] = [
              for (final childId in entry.value)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
            ];
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else if (config is SuperConditionalConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            zones[entry.key] = [
              for (final childId in entry.value)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
            ];
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else if (config is SuperTableConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            zones[entry.key] = [
              for (final childId in entry.value)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
            ];
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else if (config is SuperTreeViewConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            zones[entry.key] = [
              for (final childId in entry.value)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
            ];
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else {
          final children = VibeScopeHelpers.childrenOfComponent(config);
          if (children.isNotEmpty) {
            node['children'] = [
              for (final childId in children)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
            ];
          }
        }
      } finally {
        seenInBranch.remove(id);
      }

      return node;
    }

    return <String, Object?>{
      'rootId': rootId,
      'truncated': truncated,
      'tree': buildNode(rootId, 0),
    };
  }

  /// Interroge les données, schémas et sélections actives du [JsonRepositoryStore].
  Future<Map<String, Object?>> queryRepositoryData(
    Map<String, Object?> args,
  ) async {
    final store = repositoryStore;
    if (store == null) {
      return const <String, Object?>{
        'available': false,
        'error': 'Aucun JsonRepositoryStore actif dans ce contexte.',
      };
    }

    final repoId = args['repositoryId'] is String
        ? (args['repositoryId'] as String).trim()
        : '';
    final path = args['path'] is String ? (args['path'] as String).trim() : '';
    final rawOffset = args['offset'];
    final offset = rawOffset is num ? math.max(0, rawOffset.toInt()) : 0;
    final rawLimit = args['limit'];
    final limit = (rawLimit is num ? rawLimit.toInt() : 10).clamp(1, 50);

    final catalog = await store.catalog();
    if (repoId.isEmpty) {
      final list = <Map<String, Object?>>[];
      for (final entry in catalog) {
        Object? doc;
        try {
          doc = await store.readDocument(entry.id);
        } on FormatException {
          doc = null;
        }
        final binding = store.bindingOf(entry.id);
        list.add(<String, Object?>{
          'id': entry.id,
          'name': entry.name,
          'kind': store.isPersistentRepository(entry.id)
              ? 'persistent'
              : (store.isMemoryOnlyRepository(entry.id) ? 'memory' : 'file'),
          if (doc is Map)
            'rootKeys': {
              for (final k in doc.keys) '$k': _describeJsonShape(doc[k]),
            },
          'calculatedAttributes': [
            for (final attr in store.calculatedAttributeCatalog(entry.id))
              attr.path,
          ],
          'hasJsonSchema': store.jsonSchemaOf(entry.id) != null,
          if (store.isCodeJsonSchema(entry.id)) 'isCodeJsonSchema': true,
          'selections': {
            for (final arr in binding.arrays)
              if (arr.selection != null) arr.template: arr.selection,
          },
        });
      }
      return <String, Object?>{
        'available': true,
        'repositoryCount': list.length,
        'repositories': list,
      };
    }

    final entry = catalog.where((e) => e.id == repoId).firstOrNull;
    if (entry == null) {
      return <String, Object?>{
        'available': true,
        'found': false,
        'error': 'Repository "$repoId" introuvable.',
      };
    }

    final binding = store.bindingOf(repoId);
    final selections = <String, Object?>{
      for (final arr in binding.arrays)
        if (arr.selection != null) arr.template: arr.selection,
    };

    if (path.isEmpty) {
      final doc = await store.readDocument(repoId);
      final schema = await store.readJsonSchema(repoId);
      return <String, Object?>{
        'available': true,
        'found': true,
        'id': entry.id,
        'name': entry.name,
        'hasJsonSchema': schema != null,
        if (store.isCodeJsonSchema(repoId)) 'isCodeJsonSchema': true,
        'jsonSchema': ?schema,
        if (selections.isNotEmpty) 'selections': selections,
        'data': _paginateJsonValue(doc, offset: offset, limit: limit),
      };
    }

    final parsedPath = JsonAttributePath(path);
    if (parsedPath.calculated != null) {
      final attr = await store.readAttribute(
        JsonTextBinding(repositoryId: repoId, path: path),
      );
      return <String, Object?>{
        'available': true,
        'found': true,
        'id': entry.id,
        'path': path,
        'text': attr.text,
        if (selections.isNotEmpty) 'selections': selections,
        'value': _paginateJsonValue(attr.value, offset: offset, limit: limit),
      };
    }

    parsedPath.requireResolved();
    final doc = await store.readDocument(repoId);
    final resolvedValue = _navigateJsonPath(doc, path);
    return <String, Object?>{
      'available': true,
      'found': true,
      'id': entry.id,
      'path': path,
      if (selections.isNotEmpty) 'selections': selections,
      'value': _paginateJsonValue(resolvedValue, offset: offset, limit: limit),
    };
  }

  /// Lit, infère, valide, crée, met à jour ou dissocie le JSON Schema d'un repository.
  Future<VibeToolResult> manageRepositoryJsonSchema(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) async {
    final store = repositoryStore;
    if (store == null) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Aucun JsonRepositoryStore actif dans ce contexte.',
      );
    }

    final rawAction = args['action'];
    if (rawAction is! String || rawAction.trim().isEmpty) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Paramètre "action" requis ("get", "create", "update", "delete", "validate" ou "infer").',
      );
    }
    final action = rawAction.trim();

    final rawRepo = args['repositoryId'];
    if (rawRepo is! String || rawRepo.trim().isEmpty) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Paramètre "repositoryId" requis.',
      );
    }
    final requestedRepo = rawRepo.trim();

    final catalog = await store.catalog();
    final entry =
        catalog.where((e) => e.id == requestedRepo).firstOrNull ??
        catalog
            .where((e) => e.name.toLowerCase() == requestedRepo.toLowerCase())
            .firstOrNull;
    if (entry == null) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Repository "$requestedRepo" introuvable dans le store.',
      );
    }

    final repoId = entry.id;
    final isCodeSchema = store.isCodeJsonSchema(repoId);

    try {
      switch (action) {
        case 'get':
          final schema = await store.readJsonSchema(repoId);
          return VibeToolResult(
            callId: callId,
            name: toolName,
            data: <String, Object?>{
              'ok': true,
              'action': action,
              'id': repoId,
              'name': entry.name,
              'hasJsonSchema': schema != null,
              'isCodeJsonSchema': isCodeSchema,
              'jsonSchema': ?schema,
            },
          );

        case 'infer':
          final doc = await store.readDocument(repoId);
          final markRequired = args['markPresentKeysRequired'] == true;
          final inferred = JsonSchemaValidator.inferSchema(
            doc,
            title: entry.name,
            markPresentKeysRequired: markRequired,
          );
          return VibeToolResult(
            callId: callId,
            name: toolName,
            data: <String, Object?>{
              'ok': true,
              'action': action,
              'id': repoId,
              'name': entry.name,
              'schema': inferred,
            },
          );

        case 'validate':
          final rawSchema = args['schema'];
          Map<String, Object?>? effectiveSchema;
          if (rawSchema != null) {
            effectiveSchema = JsonSchemaValidator.validateSchemaDefinition(
              rawSchema,
            );
          } else {
            effectiveSchema = await store.readJsonSchema(repoId);
          }
          if (effectiveSchema == null) {
            return VibeToolResult(
              callId: callId,
              name: toolName,
              data: <String, Object?>{
                'ok': true,
                'action': action,
                'id': repoId,
                'name': entry.name,
                'hasJsonSchema': false,
                'valid': true,
                'issueCount': 0,
                'issues': const <Object?>[],
              },
            );
          }
          final doc = await store.readDocument(repoId);
          final result = JsonSchemaValidator.validate(doc, effectiveSchema);
          return VibeToolResult(
            callId: callId,
            name: toolName,
            data: <String, Object?>{
              'ok': true,
              'action': action,
              'id': repoId,
              'name': entry.name,
              'hasJsonSchema': true,
              'valid': result.isValid,
              'issueCount': result.issues.length,
              'issues': [for (final issue in result.issues) issue.toJson()],
            },
          );

        case 'create':
        case 'update':
          if (isCodeSchema) {
            return VibeToolResult.error(
              callId: callId,
              name: toolName,
              message:
                  'Le JSON Schema de "${entry.name}" ($repoId) est figé dans le code via RepositoryImpl.jsonSchema.',
            );
          }
          final existing = await store.readJsonSchema(repoId);
          if (action == 'create' && existing != null) {
            return VibeToolResult.error(
              callId: callId,
              name: toolName,
              message:
                  'Un JSON Schema est déjà associé à "${entry.name}" ($repoId). Utilisez action="update" pour le remplacer.',
            );
          }
          final rawSchema = args['schema'];
          if (rawSchema is! Map) {
            return VibeToolResult.error(
              callId: callId,
              name: toolName,
              message:
                  'Le paramètre "schema" (objet JSON Schema) est requis pour action="$action".',
            );
          }
          final normalized = JsonSchemaValidator.validateSchemaDefinition(
            rawSchema,
          );
          final validateDoc = args['validateCurrentDocument'] is bool
              ? args['validateCurrentDocument'] as bool
              : true;

          final persisted = repoTransaction != null
              ? await repoTransaction!.applyJsonSchemaFromTool(
                  repoId,
                  normalized,
                  validateCurrentDocument: validateDoc,
                )
              : await (() async {
                  await store.saveJsonSchema(
                    repoId,
                    normalized,
                    validateCurrentDocument: validateDoc,
                  );
                  return store.readJsonSchema(repoId);
                })();
          return VibeToolResult(
            callId: callId,
            name: toolName,
            data: <String, Object?>{
              'ok': true,
              'action': action,
              'id': repoId,
              'name': entry.name,
              'hasJsonSchema': persisted != null,
              'validateCurrentDocument': validateDoc,
              'jsonSchema': ?persisted,
            },
          );

        case 'delete':
          if (isCodeSchema) {
            return VibeToolResult.error(
              callId: callId,
              name: toolName,
              message:
                  'Le JSON Schema de "${entry.name}" ($repoId) est figé dans le code via RepositoryImpl.jsonSchema.',
            );
          }
          final hadSchema = await store.readJsonSchema(repoId) != null;
          if (repoTransaction != null) {
            await repoTransaction!.applyJsonSchemaFromTool(repoId, null);
          } else {
            await store.saveJsonSchema(repoId, null);
          }
          return VibeToolResult(
            callId: callId,
            name: toolName,
            data: <String, Object?>{
              'ok': true,
              'action': action,
              'id': repoId,
              'name': entry.name,
              'hadJsonSchema': hadSchema,
              'hasJsonSchema': false,
            },
          );

        default:
          return VibeToolResult.error(
            callId: callId,
            name: toolName,
            message:
                'Action inconnue "$action" (attendu: "get", "create", "update", "delete", "validate" ou "infer").',
          );
      }
    } on JsonSchemaValidationException catch (error) {
      return VibeToolResult(
        callId: callId,
        name: toolName,
        isError: true,
        data: <String, Object?>{
          'ok': false,
          'action': action,
          'id': repoId,
          'name': entry.name,
          'error': error.message,
          'issues': [for (final issue in error.issues) issue.toJson()],
        },
      );
    } on FormatException catch (error) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: error.message,
      );
    }
  }

  static final RegExp _pathTokenPattern = RegExp(r'([^.\[\]]+)|\[(\d+)\]');

  static Object? _navigateJsonPath(Object? root, String path) {
    Object? current = root;
    for (final match in _pathTokenPattern.allMatches(path)) {
      final key = match.group(1);
      final indexRaw = match.group(2);
      if (key != null) {
        if (current is! Map) {
          throw const FormatException(
            'Structure JSON incompatible avec le chemin.',
          );
        }
        current = current[key];
      } else if (indexRaw != null) {
        final index = int.parse(indexRaw);
        if (current is! List || index < 0 || index >= current.length) {
          throw const FormatException('Indice de tableau JSON inexistant.');
        }
        current = current[index];
      }
    }
    return current;
  }

  static String _describeJsonShape(Object? value) => switch (value) {
    final List list => 'array(length=${list.length})',
    final Map map => 'object(keys=${map.length})',
    final String _ => 'string',
    final num _ => 'number',
    final bool _ => 'boolean',
    null => 'null',
    _ => value.runtimeType.toString(),
  };

  static Object? _paginateJsonValue(
    Object? value, {
    required int offset,
    required int limit,
    int depth = 0,
  }) {
    if (depth > 4) return _describeJsonShape(value);
    if (value is List) {
      final safeOffset = offset.clamp(0, value.length);
      final end = math.min(value.length, safeOffset + limit);
      return <String, Object?>{
        'totalCount': value.length,
        'offset': safeOffset,
        'limit': limit,
        'items': [
          for (var i = safeOffset; i < end; i++)
            _paginateJsonValue(value[i], offset: 0, limit: 5, depth: depth + 1),
        ],
      };
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _paginateJsonValue(
            entry.value,
            offset: offset,
            limit: limit,
            depth: depth + 1,
          ),
      };
    }
    if (value is String && value.length > 500) {
      return '${value.substring(0, 500)}…';
    }
    return value;
  }

  /// Capture une image PNG isolée d'un élément monté précis (sans capturer toute la page).
  ///
  /// Utilise directement le [RenderRepaintBoundary] interne propre à l'[EditorSlot]
  /// lorsque `contextPadding == 0`, garantissant un rendu net (HiDPI) sans contours
  /// d'édition ni rasterisation de la fenêtre complète.
  Future<VibeToolResult> captureElementScreenshot(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) async {
    var componentId =
        args['componentId'] is String &&
            (args['componentId'] as String).trim().isNotEmpty
        ? (args['componentId'] as String).trim()
        : (args['id'] is String && (args['id'] as String).trim().isNotEmpty
              ? (args['id'] as String).trim()
              : null);
    var zoneId =
        args['zoneId'] is String && (args['zoneId'] as String).trim().isNotEmpty
        ? (args['zoneId'] as String).trim()
        : null;

    if (componentId == null) {
      final scope = readScope?.call();
      if (scope != null) {
        componentId = scope.componentId;
        zoneId ??= scope.zoneId;
      } else {
        final focusCtx = LayoutSelection.focus.value?.context;
        final focusedSlot = (focusCtx != null && focusCtx.mounted)
            ? EditorSlotState.resolveFromContext(focusCtx)
            : null;
        if (focusedSlot != null && focusedSlot.mounted) {
          componentId = focusedSlot.effectiveComponentId;
          zoneId ??= focusedSlot.widget.zoneId;
        }
      }
    }

    if (componentId == null || componentId.isEmpty) {
      final available = slotIndex.mountedSlotSummaries(limit: 20);
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'Aucun élément ciblé : fournis "componentId" '
            '${available.isEmpty ? '' : '(ex: ${available.join(', ')}) '}'
            'ou utilise "capture_screenshot" pour la page entière.',
      );
    }

    var entries = slotIndex.entriesFor(componentId, zoneId: zoneId);
    if (entries.isEmpty) {
      final canonical = VibeChatScope.canonicalizeId(componentId);
      if (canonical != componentId) {
        entries = slotIndex.entriesFor(canonical, zoneId: zoneId);
        if (entries.isNotEmpty) {
          componentId = canonical;
        }
      }
    }
    if (entries.isEmpty) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'Élément "$componentId"${zoneId == null ? '' : ' (zone "$zoneId")'} non monté à l’écran.',
      );
    }

    final rawOcc = args['occurrenceIndex'];
    final occurrenceIndex = rawOcc is num ? rawOcc.toInt() : 0;
    if (occurrenceIndex < 0 || occurrenceIndex >= entries.length) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'occurrenceIndex $occurrenceIndex hors limites pour "$componentId" '
            '(${entries.length} occurrence(s) montée(s), indices 0..${entries.length - 1}).',
      );
    }

    final entry = entries[occurrenceIndex];
    final visibleOnly = readVisibleOnly?.call() == true;
    final scrollIntoView = visibleOnly
        ? false
        : (args['scrollIntoView'] is bool
              ? args['scrollIntoView'] as bool
              : true);
    final rawPadding = args['contextPadding'];
    final contextPadding = (rawPadding is num ? rawPadding.toDouble() : 0.0)
        .clamp(0.0, 200.0);
    final rawMaxDim = args['maxDimension'];
    final maxDimension = (rawMaxDim is num ? rawMaxDim.toInt() : 800).clamp(
      256,
      1600,
    );

    if (scrollIntoView) {
      final initialSlotCtx = entry.slotContext();
      if (initialSlotCtx != null &&
          initialSlotCtx.mounted &&
          Scrollable.maybeOf(initialSlotCtx) != null) {
        try {
          await Scrollable.ensureVisible(
            initialSlotCtx,
            alignment: 0.5,
            duration: Duration.zero,
          );
        } catch (_) {
          // Poursuit même si le Scrollable ne peut pas défiler jusqu'à la cible.
        }
      }
    }

    final ctx = entry.contentKey.currentContext ?? entry.slotContext();
    if (ctx == null || !ctx.mounted) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Contexte de l’élément "$componentId" indisponible.',
      );
    }

    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(ctx) ?? 1.0;
    final rootBoxForVisibility = visibleOnly ? _resolveRootBox(ctx) : null;
    final viewportSizeForVisibility = visibleOnly
        ? MediaQuery.maybeSizeOf(ctx)
        : null;
    final renderObj = ctx.findRenderObject();
    final directAncestorBoundary = ctx
        .findAncestorRenderObjectOfType<RenderRepaintBoundary>();
    await _settleFrameIfNeeded(renderObj);

    if (renderObj == null || !renderObj.attached) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Objet de rendu de "$componentId" détaché.',
      );
    }

    if (visibleOnly && renderObj is RenderBox && renderObj.hasSize) {
      if (isRenderObjectOffstage(renderObj, stopAt: rootBoxForVisibility) ||
          _computeViewportVisibleRect(
                renderObj,
                renderObj.size,
                rootBoxForVisibility,
                viewportSizeForVisibility,
              ) ==
              null) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'Mode « Uniquement visible » actif : "$componentId" est hors de la zone actuellement visible (onglet masqué ou hors du scroll courant).',
        );
      }
    }

    // Chemin rapide isolé : le contenu du slot possède son propre RenderRepaintBoundary
    // et aucune marge externe autour de l'élément n'est demandée.
    if (contextPadding <= 0.0 &&
        renderObj is RenderRepaintBoundary &&
        renderObj.hasSize) {
      final targetSize = renderObj.size;
      if (targetSize.width <= 0 || targetSize.height <= 0) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'L’élément "$componentId" a une taille nulle (${targetSize.width}x${targetSize.height}).',
        );
      }
      final paintError = await _ensureBoundaryPainted(renderObj);
      if (paintError != null) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message: paintError,
        );
      }
      final idealRatio = math.max(1.0, math.min(devicePixelRatio, 3.0));
      final longest = math.max(targetSize.width, targetSize.height);
      final ratio = longest * idealRatio > maxDimension
          ? maxDimension / longest
          : idealRatio;

      final ui.Image image = await renderObj.toImage(pixelRatio: ratio);
      final int pixelW = image.width;
      final int pixelH = image.height;
      Uint8List? pngBytes;
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        pngBytes = byteData?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
      if (pngBytes == null || pngBytes.isEmpty) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message: 'Échec de l’encodage PNG de "$componentId".',
        );
      }
      final fileLabel = _elementScreenshotFileName(
        componentId,
        zoneId: zoneId,
        occurrenceIndex: occurrenceIndex,
      );
      return VibeToolResult(
        callId: callId,
        name: toolName,
        data: <String, Object?>{
          'target': componentId,
          'componentId': componentId,
          'zoneId': ?zoneId,
          'occurrenceIndex': occurrenceIndex,
          'totalOccurrences': entries.length,
          'isolatedBoundary': true,
          'contextPadding': 0.0,
          'logicalWidth': _round2(targetSize.width),
          'logicalHeight': _round2(targetSize.height),
          'pixelWidth': pixelW,
          'pixelHeight': pixelH,
          'pixelRatio': _round2(ratio),
          'imageAttachment': fileLabel,
        },
        attachments: <VibeChatAttachment>[
          VibeChatAttachment.image(
            name: fileLabel,
            bytes: pngBytes,
            mimeType: 'image/png',
          ),
        ],
      );
    }

    // Chemin avec contexte parent (contextPadding > 0), RenderBox sans boundary propre, ou RenderSliver.
    RenderRepaintBoundary? boundary;
    if (renderObj is RenderRepaintBoundary && contextPadding <= 0.0) {
      boundary = renderObj;
    } else if (contextPadding > 0.0 &&
        renderObj is RenderBox &&
        renderObj.hasSize) {
      boundary =
          _findLargerAncestorBoundary(renderObj, renderObj.size) ??
          directAncestorBoundary;
    } else {
      boundary = directAncestorBoundary;
    }
    if (boundary == null || !boundary.attached || !boundary.hasSize) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'Aucun RenderRepaintBoundary parent trouvé pour capturer "$componentId".',
      );
    }

    Rect? logicalRectInBoundary;
    Size? logicalElementSize;

    if (isRenderObjectOffstage(renderObj, stopAt: boundary)) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'L’élément "$componentId" est masqué (offstage) et ne peut pas être capturé.',
      );
    }

    if (renderObj is RenderBox && renderObj.hasSize) {
      logicalElementSize = renderObj.size;
      if (logicalElementSize.width <= 0 || logicalElementSize.height <= 0) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'L’élément "$componentId" a une taille nulle (${logicalElementSize.width}x${logicalElementSize.height}).',
        );
      }
      final transform = renderObj.getTransformTo(boundary);
      if (transform.isZero()) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'L’élément "$componentId" est entièrement hors de la zone visible de son conteneur.',
        );
      }
      final baseRect = MatrixUtils.transformRect(
        transform,
        Offset.zero & logicalElementSize,
      );
      if (!baseRect.isFinite) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'L’élément "$componentId" est entièrement hors de la zone visible de son conteneur.',
        );
      }
      logicalRectInBoundary = baseRect
          .inflate(contextPadding)
          .intersect(Offset.zero & boundary.size);
    } else if (renderObj is RenderSliver) {
      final geo = renderObj.geometry;
      final paintExtent = geo?.paintExtent ?? 0.0;
      final crossExtent = renderObj.constraints.crossAxisExtent;
      if (paintExtent <= 0 || crossExtent <= 0) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'Le sliver "$componentId" n’a aucune surface visible peinte (paintExtent=$paintExtent).',
        );
      }
      final localSliverRect = renderObj.constraints.axis == Axis.vertical
          ? Rect.fromLTWH(0, 0, crossExtent, paintExtent)
          : Rect.fromLTWH(0, 0, paintExtent, crossExtent);
      logicalElementSize = localSliverRect.size;
      final viewportBox = _findNearestRenderBox(renderObj);
      final transform = viewportBox != null
          ? renderObj.getTransformTo(boundary)
          : null;
      if (transform != null && transform.isZero()) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'L’élément "$componentId" est entièrement hors de la zone visible de son conteneur.',
        );
      }
      final baseRect = transform != null
          ? MatrixUtils.transformRect(transform, localSliverRect)
          : localSliverRect;
      if (!baseRect.isFinite) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'L’élément "$componentId" est entièrement hors de la zone visible de son conteneur.',
        );
      }
      logicalRectInBoundary = baseRect
          .inflate(contextPadding)
          .intersect(Offset.zero & boundary.size);
    } else {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'L’élément "$componentId" ne dispose pas d’une géométrie mesurable.',
      );
    }

    if (!logicalRectInBoundary.isFinite ||
        logicalRectInBoundary.isEmpty ||
        logicalRectInBoundary.width <= 0 ||
        logicalRectInBoundary.height <= 0) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'L’élément "$componentId" est entièrement hors de la zone visible de son conteneur.',
      );
    }

    final paintError = await _ensureBoundaryPainted(boundary);
    if (paintError != null) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: paintError,
      );
    }

    final idealRatio = math.max(1.0, math.min(devicePixelRatio, 3.0));
    final boundaryLongest = math.max(boundary.size.width, boundary.size.height);
    final cropLongest = math.max(
      logicalRectInBoundary.width,
      logicalRectInBoundary.height,
    );
    var ratio = cropLongest * idealRatio > maxDimension
        ? maxDimension / cropLongest
        : idealRatio;
    if (boundaryLongest * ratio > 2400) {
      ratio = 2400 / boundaryLongest;
    }

    final ui.Image boundaryImage = await boundary.toImage(pixelRatio: ratio);
    Uint8List? pngBytes;
    int outPixelW = 0;
    int outPixelH = 0;
    try {
      final srcRect = Rect.fromLTWH(
        (logicalRectInBoundary.left * ratio).clamp(
          0.0,
          boundaryImage.width.toDouble(),
        ),
        (logicalRectInBoundary.top * ratio).clamp(
          0.0,
          boundaryImage.height.toDouble(),
        ),
        (logicalRectInBoundary.width * ratio).clamp(
          1.0,
          boundaryImage.width.toDouble(),
        ),
        (logicalRectInBoundary.height * ratio).clamp(
          1.0,
          boundaryImage.height.toDouble(),
        ),
      );
      final scaleDown = math.max(srcRect.width, srcRect.height) > maxDimension
          ? maxDimension / math.max(srcRect.width, srcRect.height)
          : 1.0;
      outPixelW = math.max(1, (srcRect.width * scaleDown).round());
      outPixelH = math.max(1, (srcRect.height * scaleDown).round());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        boundaryImage,
        srcRect,
        Rect.fromLTWH(0, 0, outPixelW.toDouble(), outPixelH.toDouble()),
        Paint(),
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(outPixelW, outPixelH);
      picture.dispose();
      try {
        final byteData = await cropped.toByteData(
          format: ui.ImageByteFormat.png,
        );
        pngBytes = byteData?.buffer.asUint8List();
      } finally {
        cropped.dispose();
      }
    } finally {
      boundaryImage.dispose();
    }

    if (pngBytes == null || pngBytes.isEmpty) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Échec de l’encodage PNG de "$componentId".',
      );
    }

    final fileLabel = _elementScreenshotFileName(
      componentId,
      zoneId: zoneId,
      occurrenceIndex: occurrenceIndex,
    );
    return VibeToolResult(
      callId: callId,
      name: toolName,
      data: <String, Object?>{
        'target': componentId,
        'componentId': componentId,
        'zoneId': ?zoneId,
        'occurrenceIndex': occurrenceIndex,
        'totalOccurrences': entries.length,
        'isolatedBoundary': false,
        'contextPadding': _round2(contextPadding),
        'logicalWidth': _round2(logicalElementSize.width),
        'logicalHeight': _round2(logicalElementSize.height),
        'pixelWidth': outPixelW,
        'pixelHeight': outPixelH,
        'pixelRatio': _round2(ratio),
        'imageAttachment': fileLabel,
      },
      attachments: <VibeChatAttachment>[
        VibeChatAttachment.image(
          name: fileLabel,
          bytes: pngBytes,
          mimeType: 'image/png',
        ),
      ],
    );
  }

  static RenderRepaintBoundary? _findLargerAncestorBoundary(
    RenderObject start,
    Size elementSize,
  ) {
    RenderRepaintBoundary? outermost;
    RenderObject? current = start.parent;
    while (current != null) {
      if (current is RenderRepaintBoundary &&
          current.attached &&
          current.hasSize) {
        outermost = current;
        if (current.size.width > elementSize.width + 0.5 ||
            current.size.height > elementSize.height + 0.5) {
          return current;
        }
      }
      current = current.parent;
    }
    return outermost;
  }

  static RenderBox? _findNearestRenderBox(RenderObject node) {
    RenderObject? current = node.parent;
    while (current != null) {
      if (current is RenderBox) return current;
      current = current.parent;
    }
    return null;
  }

  static String _elementScreenshotFileName(
    String componentId, {
    String? zoneId,
    int occurrenceIndex = 0,
  }) {
    final safeId = componentId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeZone = zoneId == null || zoneId.isEmpty
        ? ''
        : '_${zoneId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';
    final occ = occurrenceIndex > 0 ? '_$occurrenceIndex' : '';
    return 'element_$safeId$safeZone$occ.png';
  }

  Future<String?> _ensureBoundaryPainted(RenderRepaintBoundary boundary) async {
    if (!boundary.debugNeedsPaint) return null;
    SchedulerBinding.instance.ensureVisualUpdate();
    try {
      await SchedulerBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 250),
      );
    } on TimeoutException {
      // Poursuit et revérifie debugNeedsPaint ci-dessous.
    }
    if (boundary.debugNeedsPaint) {
      return 'La surface n’a pas encore été peinte : réessaye après le rendu.';
    }
    return null;
  }

  /// Capture une image PNG de la vue applicative complète (ou délègue à [captureElementScreenshot]
  /// lorsqu'un `componentId` est explicitement fourni).
  Future<VibeToolResult> captureScreenshot(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) async {
    final componentId =
        args['componentId'] is String &&
            (args['componentId'] as String).trim().isNotEmpty
        ? (args['componentId'] as String).trim()
        : null;
    if (componentId != null) {
      return captureElementScreenshot(callId, toolName, args);
    }

    final rawMaxDim = args['maxDimension'];
    final maxDimension = (rawMaxDim is num ? rawMaxDim.toInt() : 1024).clamp(
      256,
      1600,
    );

    final rootCtx = _resolvePrimaryContext();
    if (rootCtx == null || !rootCtx.mounted) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Aucune vue applicative montée à capturer.',
      );
    }
    final rootObj = rootCtx.findRenderObject();
    final ancestorBoundary = rootCtx
        .findAncestorRenderObjectOfType<RenderRepaintBoundary>();
    await _settleFrameIfNeeded(rootObj);

    RenderRepaintBoundary? boundary;
    RenderBox? targetBox;
    if (rootObj is RenderRepaintBoundary) {
      boundary = rootObj;
      targetBox = rootObj;
    } else {
      boundary = ancestorBoundary;
      if (rootObj is RenderBox && rootObj.attached && rootObj.hasSize) {
        targetBox = rootObj;
      } else {
        targetBox = boundary;
      }
    }

    if (boundary == null ||
        !boundary.attached ||
        !boundary.hasSize ||
        targetBox == null ||
        !targetBox.attached ||
        !targetBox.hasSize) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Aucun RenderRepaintBoundary actif trouvé pour la capture.',
      );
    }

    final paintError = await _ensureBoundaryPainted(boundary);
    if (paintError != null) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: paintError,
      );
    }

    final targetSize = targetBox.size;
    if (targetSize.width <= 0 || targetSize.height <= 0) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message:
            'La cible a une taille nulle (${targetSize.width}x${targetSize.height}).',
      );
    }

    final longest = math.max(targetSize.width, targetSize.height);
    final ratio = longest > maxDimension ? maxDimension / longest : 1.0;

    final ui.Image boundaryImage = await boundary.toImage(pixelRatio: ratio);
    Uint8List? pngBytes;
    try {
      final byteData = await boundaryImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      pngBytes = byteData?.buffer.asUint8List();
    } finally {
      boundaryImage.dispose();
    }

    if (pngBytes == null || pngBytes.isEmpty) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Échec de l’encodage PNG de la capture.',
      );
    }

    const fileLabel = 'screenshot_viewport.png';
    return VibeToolResult(
      callId: callId,
      name: toolName,
      data: <String, Object?>{
        'target': 'viewport',
        'logicalWidth': _round2(targetSize.width),
        'logicalHeight': _round2(targetSize.height),
        'pixelRatio': _round2(ratio),
        'imageAttachment': fileLabel,
      },
      attachments: <VibeChatAttachment>[
        VibeChatAttachment.image(
          name: fileLabel,
          bytes: pngBytes,
          mimeType: 'image/png',
        ),
      ],
    );
  }

  /// Génère, valide et enregistre un système de design `DESIGN.md` dans la liste des choix possibles.
  Future<VibeToolResult> registerDesignSystem(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) async {
    final registerCallback = onRegisterDesignSystem;
    final store = customDesignSystemStore;
    if (registerCallback == null && store == null) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Aucun gestionnaire de systèmes de design n’est disponible dans ce contexte.',
      );
    }

    String? optionalString(String key) {
      final raw = args[key];
      if (raw is! String) return null;
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final rawName = optionalString('name');
    final rawMarkdown = optionalString('markdown');
    if (rawName == null) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Le paramètre requis "name" est manquant ou vide.',
      );
    }
    if (rawMarkdown == null) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Le paramètre requis "markdown" est manquant ou vide.',
      );
    }

    final rawSlug = optionalString('slug');
    final slugBase =
        rawSlug != null && rawSlug.toLowerCase().startsWith('custom:')
        ? rawSlug.substring('custom:'.length)
        : (rawSlug ?? rawName);
    final normalizedSlug = DesignMdParser.slugify(slugBase);
    final resolvedId = 'custom:$normalizedSlug';

    final rawRadius = args['cardRadius'];
    final cardRadius = rawRadius is num && rawRadius.isFinite
        ? rawRadius.toDouble()
        : null;

    final rawTags = args['tags'];
    final tags = rawTags is List
        ? [
            for (final item in rawTags)
              if (item != null && item.toString().trim().isNotEmpty)
                item.toString().trim(),
          ]
        : null;

    final select = args['select'] is bool ? args['select'] as bool : true;

    try {
      final composedMarkdown = DesignMdParser.composeDesignMarkdown(
        markdown: rawMarkdown,
        id: resolvedId,
        name: rawName,
        slug: resolvedId,
        category: optionalString('category'),
        tagline: optionalString('tagline'),
        description: optionalString('description'),
        mode: optionalString('mode'),
        accent: optionalString('accent'),
        canvasColor: optionalString('canvasColor'),
        surfaceColor: optionalString('surfaceColor'),
        textColor: optionalString('textColor'),
        mutedTextColor: optionalString('mutedTextColor'),
        borderColor: optionalString('borderColor'),
        cardRadius: cardRadius,
        surfaceSystem: optionalString('surfaceSystem'),
        fontFamily: optionalString('fontFamily'),
        logo: optionalString('logo'),
        tags: tags,
      );

      final parsed = DesignMdParser.parseExternal(
        composedMarkdown,
        idOverride: resolvedId,
      );
      final normalizedPreset = parsed.copyWith(
        inlineMarkdown: DesignMdParser.toMarkdownWithFrontmatter(parsed),
      );

      String? persistedPath;
      int totalCustomPresets;
      if (registerCallback != null) {
        final outcome = await registerCallback(
          normalizedPreset,
          select: select,
        );
        persistedPath = outcome.persistedPath;
        totalCustomPresets = outcome.totalCustomPresets;
      } else {
        final file = await store!.save(normalizedPreset);
        persistedPath = file.path;
        totalCustomPresets = (await store.loadAll()).length;
      }

      final extractedFonts = DesignMdFontExtractor.extractFontFamilies(
        fontHint: normalizedPreset.palette.fontHint,
        markdown: normalizedPreset.inlineMarkdown,
      );
      Map<String, Object?>? fontsReport;
      final activeFontManager = fontManager;
      if (activeFontManager != null &&
          activeFontManager.autoDownloadEnabled &&
          extractedFonts.isNotEmpty) {
        final loadResults = await activeFontManager.ensureFontsLoaded(
          extractedFonts,
        );
        fontsReport = <String, Object?>{
          'extracted': extractedFonts,
          'available': [
            for (final entry in loadResults.entries)
              if (entry.value.isAvailable) entry.key,
          ],
          'missing': [
            for (final entry in loadResults.entries)
              if (!entry.value.isAvailable) entry.key,
          ],
        };
      }

      final palette = normalizedPreset.palette;
      return VibeToolResult(
        callId: callId,
        name: toolName,
        data: <String, Object?>{
          'ok': true,
          'id': normalizedPreset.id,
          'name': normalizedPreset.name,
          'category': normalizedPreset.category.id,
          'tagline': normalizedPreset.tagline,
          'selected': select,
          'hasLogo':
              normalizedPreset.logo != null &&
              normalizedPreset.logo!.trim().isNotEmpty,
          'logo': ?normalizedPreset.logo,
          'totalCustomPresets': totalCustomPresets,
          'persistedPath': ?persistedPath,
          if (extractedFonts.isNotEmpty)
            'extractedFontFamilies': extractedFonts,
          'fonts': ?fontsReport,
          'palette': <String, Object?>{
            'mode': palette.isDark ? 'dark' : 'light',
            'accent': DesignSystemPalettePreview.colorToHex(palette.accent),
            'canvas': DesignSystemPalettePreview.colorToHex(palette.canvas),
            'surface': DesignSystemPalettePreview.colorToHex(palette.surface),
            'textPrimary': DesignSystemPalettePreview.colorToHex(
              palette.textPrimary,
            ),
            'textMuted': DesignSystemPalettePreview.colorToHex(
              palette.textMuted,
            ),
            'border': DesignSystemPalettePreview.colorToHex(palette.border),
            'cardRadius': palette.cardRadius,
            'surfaceSystem': palette.surfaceSystem.name,
            'fontHint': palette.fontHint,
          },
        },
      );
    } on FormatException catch (error) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: error.message,
      );
    }
  }

  /// Capture l'instantané exact des onglets actifs, des positions de scroll et des
  /// composants effectivement visibles dans le viewport courant.
  VibeVisibleViewportSnapshot captureVisibleViewportSnapshot(
    Appearance appearance,
  ) {
    final primaryCtx = _resolvePrimaryContext();
    final viewportSize = primaryCtx != null
        ? MediaQuery.maybeSizeOf(primaryCtx)
        : null;
    final rootBox = _resolveRootBox(primaryCtx);
    final pageIds = collectScopeOrActivePageComponentIds(appearance);

    var measuredAny = false;
    final visibleIds = <String>{};
    final visibleEntriesWithBounds = <({Rect rect, String summary})>[];
    final seenCompositeSummaries = <String>{};
    final seenScrollPositions = <ScrollPosition>{};
    final scrollSummaries = <String>[];

    for (final entry in slotIndex.allEntries) {
      final slotCtx = entry.slotContext();
      final contentCtx = entry.contentKey.currentContext;
      final targetCtx = (contentCtx != null && contentCtx.mounted)
          ? contentCtx
          : slotCtx;
      if (targetCtx == null || !targetCtx.mounted) continue;

      if (slotCtx != null && slotCtx.mounted) {
        final scrollable = Scrollable.maybeOf(slotCtx);
        if (scrollable != null && scrollable.position.hasPixels) {
          final pos = scrollable.position;
          if (pos.hasContentDimensions &&
              pos.maxScrollExtent > 1.0 &&
              seenScrollPositions.add(pos)) {
            final axisLabel =
                axisDirectionToAxis(pos.axisDirection) == Axis.horizontal
                ? 'horizontal'
                : 'vertical';
            scrollSummaries.add(
              'scroll $axisLabel à ${pos.pixels.round()} dp / ${pos.maxScrollExtent.round()} dp '
              '(fenêtre ${pos.viewportDimension.round()} dp)',
            );
          }
        }
      }

      final ro = targetCtx.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      if (ro.size.width <= 0 || ro.size.height <= 0) continue;
      measuredAny = true;
      if (isRenderObjectOffstage(ro, stopAt: rootBox)) continue;

      final visibleRect = _computeViewportVisibleRect(
        ro,
        ro.size,
        rootBox,
        viewportSize,
      );
      if (visibleRect == null) continue;

      visibleIds.add(entry.componentId);
      final key = entry.compositeKey;
      if (seenCompositeSummaries.add(key)) {
        final label = entry.label.trim();
        final hasDistinctLabel =
            label.isNotEmpty &&
            label != entry.componentId &&
            label != 'Editable component';
        visibleEntriesWithBounds.add((
          rect: visibleRect,
          summary: hasDistinctLabel ? '$key ($label)' : key,
        ));
      }
    }

    visibleEntriesWithBounds.sort((a, b) {
      final dy = a.rect.top.compareTo(b.rect.top);
      return dy != 0 ? dy : a.rect.left.compareTo(b.rect.left);
    });

    final activeTabStates = <VibeVisibleTabState>[];
    final hiddenTabSubtreeIds = <String>{};
    for (final tabEntry in collectActiveMountedTabEntries(
      allowedComponentIds: pageIds,
    )) {
      final snap = tabEntry.readSnapshot();
      if (snap == null || snap.tabCount == 0) continue;
      final activeItem =
          snap.tabs[snap.activeIndex.clamp(0, snap.tabCount - 1)];
      final inactiveZones = <String>[];
      if (!snap.isDynamic) {
        for (final t in snap.tabs) {
          if (t.index == activeItem.index) continue;
          inactiveZones.add(t.contentZone);
          final cfg = appearance.components[snap.componentId];
          if (cfg is SuperTabConfig) {
            final queue = <String>[...cfg.slotsOf(t.contentZone)];
            while (queue.isNotEmpty) {
              final cid = queue.removeLast();
              if (!hiddenTabSubtreeIds.add(cid)) continue;
              for (final child in VibeScopeHelpers.childrenOfComponent(
                appearance.components[cid],
              )) {
                if (!hiddenTabSubtreeIds.contains(child)) {
                  queue.add(child);
                }
              }
            }
          }
        }
      }
      activeTabStates.add(
        VibeVisibleTabState(
          tabComponentId: snap.componentId,
          activeIndex: activeItem.index,
          tabId: activeItem.tabId,
          label: activeItem.label,
          contentZone: activeItem.contentZone,
          inactiveZones: inactiveZones,
        ),
      );
    }

    // Tout composant situé dans un onglet inactif est retiré de visibleIds par sécurité.
    visibleIds.removeAll(hiddenTabSubtreeIds);

    // Remonte la chaîne des conteneurs parents des composants visibles.
    final parentByChild = <String, Set<String>>{};
    for (final entry in appearance.components.entries) {
      for (final childId in VibeScopeHelpers.childrenOfComponent(entry.value)) {
        parentByChild.putIfAbsent(childId, () => <String>{}).add(entry.key);
      }
    }
    final ancestorIds = <String>{};
    final queue = <String>[...visibleIds];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      final parents = parentByChild[current];
      if (parents == null) continue;
      for (final p in parents) {
        if (ancestorIds.add(p)) {
          queue.add(p);
        }
      }
    }

    final protectedOffscreen = <String>{
      ...hiddenTabSubtreeIds,
      if (measuredAny)
        for (final id in pageIds)
          if (!visibleIds.contains(id) && !ancestorIds.contains(id)) id,
    };

    return VibeVisibleViewportSnapshot(
      hasMeasuredViewport: measuredAny,
      visibleComponentIds: visibleIds,
      ancestorComponentIds: ancestorIds,
      protectedOffscreenComponentIds: protectedOffscreen,
      orderedVisibleSlotSummaries: [
        for (final item in visibleEntriesWithBounds) item.summary,
      ],
      activeTabs: activeTabStates,
      scrollPositionSummaries: scrollSummaries,
    );
  }

  static Rect? _computeViewportVisibleRect(
    RenderBox target,
    Size targetSize,
    RenderBox? rootBox,
    Size? viewportSize,
  ) {
    if (targetSize.width <= 0 || targetSize.height <= 0) return null;
    var visibleLocal = Rect.fromLTWH(0, 0, targetSize.width, targetSize.height);
    RenderObject? current = target.parent;
    var hops = 0;
    while (current != null && current != rootBox && hops < 32) {
      hops++;
      final clipsViewport =
          current is RenderAbstractViewport ||
          (current is RenderClipRect && current.clipBehavior != Clip.none) ||
          (current is RenderClipRRect && current.clipBehavior != Clip.none) ||
          (current is RenderClipPath && current.clipBehavior != Clip.none) ||
          (current is RenderClipOval && current.clipBehavior != Clip.none);
      if (clipsViewport &&
          current is RenderBox &&
          current.attached &&
          current.hasSize) {
        final offset = target.localToGlobal(Offset.zero, ancestor: current);
        if (!offset.isFinite) return null;
        final clipLocal = Rect.fromLTWH(
          -offset.dx,
          -offset.dy,
          current.size.width,
          current.size.height,
        );
        visibleLocal = visibleLocal.intersect(clipLocal);
        if (visibleLocal.width <= 1.0 || visibleLocal.height <= 1.0) {
          return null;
        }
      }
      current = current.parent;
    }

    final origin = rootBox != null
        ? target.localToGlobal(Offset.zero, ancestor: rootBox)
        : target.localToGlobal(Offset.zero);
    if (!origin.isFinite) return null;
    var globalVisible = visibleLocal.shift(origin);
    final maxW = rootBox?.size.width ?? viewportSize?.width;
    final maxH = rootBox?.size.height ?? viewportSize?.height;
    if (maxW != null && maxH != null && maxW > 0 && maxH > 0) {
      globalVisible = globalVisible.intersect(Rect.fromLTWH(0, 0, maxW, maxH));
      if (globalVisible.width <= 1.0 || globalVisible.height <= 1.0) {
        return null;
      }
    }
    return globalVisible;
  }

  static ({bool clipped, List<String> edges}) _inspectAncestorClipping(
    RenderBox target,
    Size targetSize,
    RenderBox? rootBox,
  ) {
    if (targetSize.isEmpty) {
      return (clipped: false, edges: const <String>[]);
    }
    const eps = 1.0;
    final clippedEdges = <String>{};
    RenderObject? current = target.parent;
    var hops = 0;
    while (current != null && current != rootBox && hops < 14) {
      hops++;
      if (current is RenderAbstractViewport) {
        break;
      }
      final isClipNode =
          (current is RenderClipRect && current.clipBehavior != Clip.none) ||
          (current is RenderClipRRect && current.clipBehavior != Clip.none) ||
          (current is RenderClipPath && current.clipBehavior != Clip.none) ||
          (current is RenderClipOval && current.clipBehavior != Clip.none);
      if (isClipNode &&
          current is RenderBox &&
          current.attached &&
          current.hasSize) {
        final offset = target.localToGlobal(Offset.zero, ancestor: current);
        if (offset.isFinite) {
          if (offset.dx < -eps) clippedEdges.add('left');
          if (offset.dy < -eps) clippedEdges.add('top');
          if (offset.dx + targetSize.width > current.size.width + eps) {
            clippedEdges.add('right');
          }
          if (offset.dy + targetSize.height > current.size.height + eps) {
            clippedEdges.add('bottom');
          }
        }
      }
      current = current.parent;
    }
    return (
      clipped: clippedEdges.isNotEmpty,
      edges: clippedEdges.toList(growable: false),
    );
  }

  static bool _inspectChildOverflow(RenderBox container, Size containerSize) {
    if (containerSize.isEmpty) return false;
    const eps = 1.0;
    var overflowFound = false;
    var visited = 0;

    void walk(RenderObject node) {
      if (overflowFound || visited >= 80) return;
      node.visitChildren((child) {
        if (overflowFound || visited >= 80) return;
        visited++;
        if (child is RenderAbstractViewport) return;
        if (child is RenderBox && child.attached && child.hasSize) {
          final offset = child.localToGlobal(Offset.zero, ancestor: container);
          if (offset.isFinite) {
            if (offset.dx < -eps ||
                offset.dy < -eps ||
                offset.dx + child.size.width > containerSize.width + eps ||
                offset.dy + child.size.height > containerSize.height + eps) {
              overflowFound = true;
              return;
            }
          }
        }
        walk(child);
      });
    }

    walk(container);
    return overflowFound;
  }

  static List<String> _inspectTruncatedTexts(RenderBox container) {
    final samples = <String>[];
    var visited = 0;

    void walk(RenderObject node) {
      if (samples.length >= 3 || visited >= 80) return;
      node.visitChildren((child) {
        if (samples.length >= 3 || visited >= 80) return;
        visited++;
        if (child is RenderParagraph && child.attached && child.hasSize) {
          final text = child.text.toPlainText().trim();
          if (text.isNotEmpty) {
            final maxLines = child.maxLines;
            final clipsSingleLine =
                maxLines == 1 &&
                (child.overflow == TextOverflow.ellipsis ||
                    child.overflow == TextOverflow.clip ||
                    child.overflow == TextOverflow.fade) &&
                child.getMaxIntrinsicWidth(double.infinity) >
                    child.size.width + 1.5;
            if (child.didExceedMaxLines || clipsSingleLine) {
              final preview = text.length > 48
                  ? '${text.substring(0, 45)}…'
                  : text;
              if (!samples.contains(preview)) {
                samples.add(preview);
              }
            }
          }
        }
        walk(child);
      });
    }

    walk(container);
    return samples;
  }
}
