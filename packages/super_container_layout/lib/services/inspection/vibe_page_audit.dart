/// Service de pré-audit déterministe d'une page ou d'un scope ([VibePageAuditService])
/// pour le bouton « Audit & correction » du chat Vibe IA.
///
/// Agrège en une passe structurée :
/// - la géométrie réelle et les coupures/débordements (`get_component_geometry`) ;
/// - la cohérence multi-pages (shells partagés, `scaffold:outlet` et navigation des pages) ;
/// - les erreurs runtime capturées dans `debugEntries` (`RenderFlex`, contraintes) ;
/// - les liaisons JSON, marges/tailles fixes et `@calculs` manquants (`inspect_bindings_and_diagnostics`) ;
/// - les défauts de contraste WCAG AA (`get_theme_and_contrast`).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:material_ui/material_ui.dart' show Axis, EdgeInsets, Size;

import '../../models/behaviours/go_back_action.dart';
import '../../models/behaviours/go_to_page_action.dart';
import '../../models/component_config.dart';
import '../../models/editor_page_config.dart';
import '../../models/native_component_config.dart';
import '../../models/scaffold_page_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_list_view_config.dart';
import '../../models/super_tab_config.dart';
import '../../models/super_table_config.dart';
import '../../models/super_tree_view_config.dart';
import '../../theme/appearance.dart';
import '../../widgets/editing/ai/vibe_scope_helpers.dart';
import '../diagnostics/debug_entry.dart';
import 'vibe_app_inspector.dart';
import 'vibe_debug_capture.dart';
import 'vibe_ghost_component_detector.dart';
import 'vibe_mounted_slot_index.dart';

/// Niveau de gravité d'une anomalie détectée lors du pré-audit.
enum VibeAuditSeverity {
  /// Anomalie critique (débordement, coupure, calcul cassé, erreur runtime).
  error('Critique'),

  /// Risque visuel ou fonctionnel (texte tronqué, calcul manquant suspecté, contraste).
  warning('Avertissement'),

  /// Point d'attention mineur.
  info('Info');

  const VibeAuditSeverity(this.label);

  /// Libellé lisible en français.
  final String label;
}

/// Catégorie fonctionnelle d'une anomalie d'audit de page.
enum VibeAuditCategory {
  /// Coupure de marge/padding, débordement parent/viewport, taille nulle ou texte tronqué.
  layoutAndClipping('Mise en page & marges'),

  /// Attribut calculé `@calculs` absent ou non déclaré pour un KPI / total.
  missingCalculation('Calculs & agrégats'),

  /// Liaison de données, schéma JSON, provider ou datasource en défaut.
  bindingAndSchema('Liaisons & données'),

  /// Erreur Flutter/runtime récente (`RenderFlex overflowed`, contrainte invalide, etc.).
  runtimeError('Erreurs runtime'),

  /// Contraste WCAG AA insuffisant.
  contrastAndStyle('Contraste & style');

  const VibeAuditCategory(this.label);

  /// Libellé lisible en français.
  final String label;
}

/// Anomalie unitaire structurée produite par [VibePageAuditService].
@immutable
class VibeAuditFinding {
  /// Construit une anomalie d'audit immuable.
  const VibeAuditFinding({
    required this.category,
    required this.severity,
    required this.kind,
    required this.message,
    this.componentId,
    this.zoneId,
    this.location,
    this.tabContext,
  });

  /// Catégorie de l'anomalie.
  final VibeAuditCategory category;

  /// Gravité de l'anomalie.
  final VibeAuditSeverity severity;

  /// Identifiant technique normalisé de l'anomalie.
  final String kind;

  /// Description actionnable en français destinée à l'IA et aux logs.
  final String message;

  /// Identifiant du composant concerné le cas échéant.
  final String? componentId;

  /// Identifiant de zone éventuel (ex. `center`, `north`).
  final String? zoneId;

  /// Chemin logique dans l'`Appearance` (ex. `components[kpi1].binding`).
  final String? location;

  /// Contexte d'onglet éventuel lorsque l'anomalie a été relevée lors du balayage d'un `SuperTab`.
  final String? tabContext;

  /// Sérialise cette anomalie en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'category': category.name,
    'severity': severity.name,
    'kind': kind,
    'message': message,
    if (componentId != null) 'componentId': componentId,
    if (zoneId != null) 'zoneId': zoneId,
    if (location != null) 'location': location,
    if (tabContext != null) 'tabContext': tabContext,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeAuditFinding &&
          other.category == category &&
          other.severity == severity &&
          other.kind == kind &&
          other.message == message &&
          other.componentId == componentId &&
          other.zoneId == zoneId &&
          other.location == location &&
          other.tabContext == tabContext;

  @override
  int get hashCode => Object.hash(
    category,
    severity,
    kind,
    message,
    componentId,
    zoneId,
    location,
    tabContext,
  );
}

/// Résumé immuable d'un onglet inspecté lors du balayage automatique hors scope.
@immutable
class VibeSweptTabSummary {
  /// Construit le résumé d'un onglet balayé pendant l'audit.
  const VibeSweptTabSummary({
    required this.tabComponentId,
    required this.tabIndex,
    required this.tabId,
    required this.label,
    required this.contentZone,
  });

  /// Identifiant du composant `SuperTab`.
  final String tabComponentId;

  /// Indice 0-based de l'onglet balayé.
  final int tabIndex;

  /// Identifiant technique du slot d'onglet.
  final String tabId;

  /// Libellé lisible de l'onglet.
  final String label;

  /// Zone de contenu inspectée (`content:<tabId>` ou `content`).
  final String contentZone;

  /// Sérialise ce résumé en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'tabComponentId': tabComponentId,
    'tabIndex': tabIndex,
    'tabId': tabId,
    'label': label,
    'contentZone': contentZone,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeSweptTabSummary &&
          other.tabComponentId == tabComponentId &&
          other.tabIndex == tabIndex &&
          other.tabId == tabId &&
          other.label == label &&
          other.contentZone == contentZone;

  @override
  int get hashCode =>
      Object.hash(tabComponentId, tabIndex, tabId, label, contentZone);
}

/// Rapport complet d'un pré-audit de page ou de scope.
@immutable
class VibePageAuditReport {
  /// Construit un rapport d'audit immuable.
  VibePageAuditReport({
    required this.targetLabel,
    this.pageId,
    this.pageName,
    this.pagePath,
    this.isScoped = false,
    this.visibleOnly = false,
    List<String> auditedComponentIds = const <String>[],
    List<VibeAuditFinding> findings = const <VibeAuditFinding>[],
    List<VibeSweptTabSummary> sweptTabs = const <VibeSweptTabSummary>[],
    List<String> measuredGeometrySummaries = const <String>[],
    this.viewportWidth,
    this.viewportHeight,
  }) : auditedComponentIds = List<String>.unmodifiable(auditedComponentIds),
       findings = List<VibeAuditFinding>.unmodifiable(findings),
       sweptTabs = List<VibeSweptTabSummary>.unmodifiable(sweptTabs),
       measuredGeometrySummaries = List<String>.unmodifiable(
         measuredGeometrySummaries,
       );

  /// Onglets inspectés séquentiellement lors du balayage automatique (hors scope).
  final List<VibeSweptTabSummary> sweptTabs;

  /// Résumés compacts des dimensions rendues (`id: W×H dp`) relevées durant le pré-audit.
  final List<String> measuredGeometrySummaries;

  /// Indique si l'audit était restreint à la zone visible (onglet actif et scroll courant).
  final bool visibleOnly;

  /// Libellé humain du périmètre audité (ex. `Page "Tableau de bord" (/dashboard)`).
  final String targetLabel;

  /// Identifiant de la page active si résolue.
  final String? pageId;

  /// Nom lisible de la page active si résolue.
  final String? pageName;

  /// Chemin de route de la page active si résolue.
  final String? pagePath;

  /// Indique si l'audit était restreint à un `VibeChatScope`.
  final bool isScoped;

  /// Composants inclus dans le périmètre audité.
  final List<String> auditedComponentIds;

  /// Anomalies détectées par le pré-audit déterministe.
  final List<VibeAuditFinding> findings;

  /// Largeur logique du viewport en dp si disponible.
  final double? viewportWidth;

  /// Hauteur logique du viewport en dp si disponible.
  final double? viewportHeight;

  /// Indique si aucune anomalie n'a été détectée par le pré-audit déterministe.
  bool get isClean => findings.isEmpty;

  /// Nombre d'anomalies critiques.
  int get errorCount =>
      findings.where((f) => f.severity == VibeAuditSeverity.error).length;

  /// Nombre d'avertissements.
  int get warningCount =>
      findings.where((f) => f.severity == VibeAuditSeverity.warning).length;

  /// Sérialise ce rapport en JSON structuré (utilisable par l'outil IA).
  Map<String, Object?> toJson() => <String, Object?>{
    'targetLabel': targetLabel,
    if (pageId != null) 'pageId': pageId,
    if (pageName != null) 'pageName': pageName,
    if (pagePath != null) 'pagePath': pagePath,
    'isScoped': isScoped,
    if (visibleOnly) 'visibleOnly': true,
    if (viewportWidth != null && viewportHeight != null)
      'viewport': <String, Object?>{
        'width': viewportWidth,
        'height': viewportHeight,
      },
    'auditedComponentCount': auditedComponentIds.length,
    if (sweptTabs.isNotEmpty) ...<String, Object?>{
      'sweptTabCount': sweptTabs.length,
      'sweptTabs': [for (final t in sweptTabs) t.toJson()],
    },
    'findingCount': findings.length,
    'errorCount': errorCount,
    'warningCount': warningCount,
    'findings': [for (final f in findings) f.toJson()],
  };

  /// Formate un résumé textuel structuré et borné à injecter dans le prompt IA.
  String toPromptSummary({int maxFindings = 35}) {
    final buffer = StringBuffer()
      ..writeln('PÉRIMÈTRE AUDITÉ : $targetLabel')
      ..writeln(
        'COMPOSANTS DANS LE PÉRIMÈTRE : ${auditedComponentIds.length}'
        '${viewportWidth != null && viewportHeight != null ? ' | VIEWPORT : ${viewportWidth!.round()}×${viewportHeight!.round()} dp' : ''}',
      );
    if (sweptTabs.isNotEmpty) {
      final byTabComponent = <String, List<VibeSweptTabSummary>>{};
      for (final item in sweptTabs) {
        byTabComponent
            .putIfAbsent(item.tabComponentId, () => <VibeSweptTabSummary>[])
            .add(item);
      }
      final groups = byTabComponent.entries
          .map(
            (e) =>
                '${e.key} (${e.value.map((t) => '[${t.tabIndex}] "${t.label}"').join(', ')})',
          )
          .join(' ; ');
      buffer.writeln('ONGLETS BALAYÉS (${sweptTabs.length}) : $groups');
    }
    if (measuredGeometrySummaries.isNotEmpty) {
      buffer.writeln(
        'MESURES GÉOMÉTRIQUES DÉJÀ RELEVÉES (${measuredGeometrySummaries.length} composants montés — réutilise ces dimensions directement sans rappeler get_component_geometry ni get_viewport_and_route) : '
        '${measuredGeometrySummaries.take(45).join(', ')}',
      );
    }

    if (findings.isEmpty) {
      buffer.writeln(
        'PRÉ-AUDIT DÉTERMINISTE : 0 anomalie bloquante détectée automatiquement '
        '(vérifie toutefois l’équilibre visuel, les marges fines et les éventuels calculs métier attendus sur cette page).',
      );
      return buffer.toString().trimRight();
    }

    buffer.writeln(
      'ANOMALIES DÉTECTÉES (${findings.length} au total — '
      '$errorCount critique(s), $warningCount avertissement(s)) :',
    );
    for (final category in VibeAuditCategory.values) {
      final group = findings.where((f) => f.category == category).toList();
      if (group.isEmpty) continue;
      buffer.writeln('• ${category.label} (${group.length}) :');
      for (final item in group.take(maxFindings)) {
        final target = item.componentId == null
            ? ''
            : item.zoneId != null && item.zoneId!.isNotEmpty
            ? '[${item.componentId}::${item.zoneId}] '
            : '[${item.componentId}] ';
        final tabTag = item.tabContext != null && item.tabContext!.isNotEmpty
            ? '[Onglet ${item.tabContext}] '
            : '';
        final loc = item.location != null && item.location!.isNotEmpty
            ? ' (${item.location})'
            : '';
        buffer.writeln(
          '  - [${item.severity.label}] $tabTag$target${item.kind}$loc : ${item.message}',
        );
      }
    }
    return buffer.toString().trimRight();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibePageAuditReport &&
          other.targetLabel == targetLabel &&
          other.pageId == pageId &&
          other.pageName == pageName &&
          other.pagePath == pagePath &&
          other.isScoped == isScoped &&
          other.visibleOnly == visibleOnly &&
          other.viewportWidth == viewportWidth &&
          other.viewportHeight == viewportHeight &&
          listEquals(other.auditedComponentIds, auditedComponentIds) &&
          listEquals(other.findings, findings) &&
          listEquals(other.sweptTabs, sweptTabs) &&
          listEquals(
            other.measuredGeometrySummaries,
            measuredGeometrySummaries,
          );

  @override
  int get hashCode => Object.hash(
    targetLabel,
    pageId,
    pageName,
    pagePath,
    isScoped,
    visibleOnly,
    viewportWidth,
    viewportHeight,
    Object.hashAll(auditedComponentIds),
    Object.hashAll(findings),
    Object.hashAll(sweptTabs),
    Object.hashAll(measuredGeometrySummaries),
  );
}

/// Exécute un pré-audit déterministe complet sur la page active ou le scope actif.
abstract final class VibePageAuditService {
  static const int _maxGeometryIds = 60;
  static const int _maxTabSwitches = 24;
  static const int _maxNestedTabDepth = 3;

  static const Set<String> _navigationRegionNames = <String>{
    'appBar',
    'sidebarStart',
    'sidebarEnd',
    'bottomNavigationBar',
    'drawer',
    'endDrawer',
  };

  static bool _hasNavigationRegion(ComponentConfig? config) {
    if (config is ScaffoldPageConfig) {
      for (final region in ScaffoldPageRegion.values) {
        if (_navigationRegionNames.contains(region.name) &&
            config.isEnabled(region) &&
            config.slotsOf(region).isNotEmpty) {
          return true;
        }
      }
      return false;
    }
    if (config is NativeComponentConfig) {
      for (final name in _navigationRegionNames) {
        if (config.isEnabled(name) && config.slotsOf(name).isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _hasShellOutletSlot(ComponentConfig? config) {
    if (config is ScaffoldPageConfig) {
      return config
          .slotsOf(ScaffoldPageRegion.body)
          .any(
            (slotId) =>
                slotId == 'scaffold:outlet' ||
                config.slotTypeOf(slotId) == 'scaffold:outlet',
          );
    }
    if (config is NativeComponentConfig) {
      return config
          .slotsOf('body')
          .any(
            (slotId) =>
                slotId == 'scaffold:outlet' ||
                config.slotTypeOf(slotId) == 'scaffold:outlet',
          );
    }
    return false;
  }

  static bool _isStandaloneAuthOrOnboardingPath(String path) {
    final normalized = path.trim().toLowerCase();
    for (final prefix in const <String>[
      '/login',
      '/signin',
      '/sign-in',
      '/register',
      '/signup',
      '/sign-up',
      '/auth',
      '/onboarding',
    ]) {
      if (normalized == prefix || normalized.startsWith('$prefix/')) {
        return true;
      }
    }
    return false;
  }

  static bool _subtreeHasNavigationAction(
    Appearance appearance,
    String rootId,
  ) {
    final subtreeIds = _collectSubtreeFromRoots(appearance, <String>[rootId]);
    for (final id in subtreeIds) {
      for (final key in <String>[id, '$id:item']) {
        final behaviors = appearance.behaviors[key];
        if (behaviors == null) continue;
        for (final behavior in behaviors) {
          if (behavior.action is GoToPageAction ||
              behavior.action is GoBackAction ||
              behavior.elseAction is GoToPageAction ||
              behavior.elseAction is GoBackAction) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static void _collectEmptyRootGhostComponentsFindings({
    required Appearance appearance,
    required Iterable<String> instantiatedIds,
    required Iterable<String> mountedComponentIds,
    required void Function(VibeAuditFinding finding) addFinding,
  }) {
    final emptyRootIds = VibeGhostComponentDetector.findEmptyRootLayoutIds(
      appearance,
      mountedComponentIds: mountedComponentIds,
    );
    if (emptyRootIds.isEmpty) return;

    final ghostIds = VibeGhostComponentDetector.findUnreachableComponentIds(
      appearance,
      extraRootIds: instantiatedIds,
      mountedRootIds: mountedComponentIds,
    );
    if (ghostIds.isEmpty) return;

    for (final rootId in emptyRootIds) {
      addFinding(
        VibeAuditFinding(
          category: VibeAuditCategory.layoutAndClipping,
          severity: VibeAuditSeverity.error,
          kind: 'ghost_components_empty_root',
          componentId: rootId,
          location: 'components[$rootId].placements',
          message: VibeGhostComponentDetector.formatEmptyRootWarning(
            rootLayoutId: rootId,
            ghostComponentIds: ghostIds,
          ),
        ),
      );
    }
  }

  static void _collectMultiPageNavigationFindings({
    required Appearance appearance,
    required void Function(VibeAuditFinding finding) addFinding,
  }) {
    final catalog = appearance.pageCatalog;

    // Vérifie que chaque shell partagé possède son composant Scaffold et son slot scaffold:outlet.
    for (final shell in catalog.shells) {
      final shellComp = appearance.components[shell.id];
      if (shellComp is! ScaffoldPageConfig &&
          shellComp is! NativeComponentConfig) {
        addFinding(
          VibeAuditFinding(
            category: VibeAuditCategory.layoutAndClipping,
            severity: VibeAuditSeverity.error,
            kind: 'missing_shell_outlet',
            componentId: shell.id,
            location: 'pageCatalog.shells[${shell.id}]',
            message:
                'Le shell "${shell.name}" (${shell.id}) déclaré dans pageCatalog.shells '
                'n’a pas de composant components["${shell.id}"] de type "scaffold" / "superScaffold" '
                'avec {"id": "scaffold:outlet", "type": "scaffold:outlet"} dans placements.body.',
          ),
        );
        continue;
      }
      if (!_hasShellOutletSlot(shellComp)) {
        addFinding(
          VibeAuditFinding(
            category: VibeAuditCategory.layoutAndClipping,
            severity: VibeAuditSeverity.error,
            kind: 'missing_shell_outlet',
            componentId: shell.id,
            location: 'components[${shell.id}].placements.body',
            message:
                'Le shell "${shell.name}" (${shell.id}) ne place pas '
                '{"id": "scaffold:outlet", "type": "scaffold:outlet"} dans placements.body : '
                'le contenu des pages rattachées ne pourra pas s’afficher dans le shell.',
          ),
        );
      }
    }

    if (catalog.pages.isEmpty) return;

    final hasAppChrome =
        catalog.shells.isNotEmpty ||
        _hasNavigationRegion(appearance.components['root']);
    final firstShellId = catalog.shells.isNotEmpty
        ? catalog.shells.first.id
        : null;

    for (final page in catalog.pages) {
      if (page.pageType.isModal || page.pageType == EditorPageType.a4Document) {
        continue;
      }
      if (page.shellId != null) continue;

      final pageConfig = appearance.components[page.id];
      if (_hasNavigationRegion(pageConfig)) continue;

      final hasNavAction = _subtreeHasNavigationAction(appearance, page.id);
      final isAuthOrOnboarding = _isStandaloneAuthOrOnboardingPath(page.path);

      if (hasNavAction && (isAuthOrOnboarding || !hasAppChrome)) {
        continue;
      }

      final severity = hasNavAction
          ? VibeAuditSeverity.warning
          : VibeAuditSeverity.error;
      final deadEndSuffix = hasNavAction
          ? ''
          : ' (impasse de navigation : aucune action goToPage/goBack détectée dans la page)';
      final recommendation = firstShellId != null
          ? 'Rattache cette page au shell existant via "shellId": "$firstShellId" '
                '(en passant components["${page.id}"] en "type": "layout"), '
                'ou ajoute une barre de navigation (appBar / sidebarStart / bottomNavigationBar) à son Scaffold.'
          : 'Déclare un shell partagé dans pageCatalog.shells et rattache cette page via "shellId", '
                'ou ajoute une barre de navigation (appBar / sidebarStart / bottomNavigationBar) à son Scaffold.';

      addFinding(
        VibeAuditFinding(
          category: VibeAuditCategory.layoutAndClipping,
          severity: severity,
          kind: 'missing_page_navigation',
          componentId: page.id,
          location: 'pageCatalog.pages[${page.id}]',
          message:
              'La page "${page.name}" (${page.path}) n’a ni shellId partagé ni région de navigation '
              'propre (appBar, sidebarStart, sidebarEnd, bottomNavigationBar ou drawer)$deadEndSuffix. '
              '$recommendation',
        ),
      );
    }
  }

  static Set<String> _collectSubtreeFromRoots(
    Appearance appearance,
    Iterable<String> roots,
  ) {
    final collected = <String>{};
    final queue = <String>[...roots];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      if (!collected.add(id)) continue;
      final cfg = appearance.components[id];
      if (cfg != null) {
        for (final childId in VibeScopeHelpers.childrenOfComponent(cfg)) {
          if (!collected.contains(childId)) {
            queue.add(childId);
          }
        }
      }
    }
    return collected;
  }

  static Set<String> _collectTabZoneSubtreeIds(
    Appearance appearance,
    String tabComponentId,
    String contentZone,
  ) {
    final cfg = appearance.components[tabComponentId];
    if (cfg is! SuperTabConfig) return const <String>{};
    return _collectSubtreeFromRoots(appearance, cfg.slotsOf(contentZone));
  }

  static Set<String> _collectAllTabContentSubtreeIds(
    Appearance appearance,
    String tabComponentId,
  ) {
    final cfg = appearance.components[tabComponentId];
    if (cfg is! SuperTabConfig) return const <String>{};
    final roots = <String>{
      for (final entry in cfg.placements.entries)
        if (entry.key == SuperTabConfig.dynamicContentZone ||
            entry.key.startsWith('content:'))
          ...entry.value,
    };
    return _collectSubtreeFromRoots(appearance, roots);
  }

  static void _recordDebugEntryFinding(
    DebugEntry entry, {
    required void Function(VibeAuditFinding finding) addFinding,
    String? tabContext,
  }) {
    if (entry.category == DebugErrorCategory.userInput) return;
    final msg = entry.message.trim();
    if (msg.isEmpty) return;
    final cid = entry.componentId;
    final firstLine = msg.split('\n').first.trim();
    final isLayoutOverflow =
        firstLine.contains('overflowed') ||
        firstLine.contains('RenderFlex') ||
        firstLine.contains('RenderBox');
    final VibeAuditCategory auditCategory = switch (entry.category) {
      DebugErrorCategory.binding => VibeAuditCategory.bindingAndSchema,
      DebugErrorCategory.font => VibeAuditCategory.contrastAndStyle,
      DebugErrorCategory.rendering when isLayoutOverflow =>
        VibeAuditCategory.layoutAndClipping,
      _ =>
        isLayoutOverflow
            ? VibeAuditCategory.layoutAndClipping
            : VibeAuditCategory.runtimeError,
    };
    final VibeAuditSeverity auditSeverity = switch (entry.severity) {
      DebugSeverity.warning => VibeAuditSeverity.warning,
      DebugSeverity.info => VibeAuditSeverity.info,
      _ => VibeAuditSeverity.error,
    };
    final String auditKind = switch (entry.category) {
      DebugErrorCategory.javascript => 'javascript_runtime_error',
      DebugErrorCategory.font => 'missing_or_invalid_font',
      DebugErrorCategory.binding => 'ui_binding_runtime_error',
      _ =>
        isLayoutOverflow
            ? 'render_overflow_debug_error'
            : 'runtime_debug_error',
    };
    addFinding(
      VibeAuditFinding(
        category: auditCategory,
        severity: auditSeverity,
        kind: auditKind,
        componentId: cid,
        location: cid != null ? 'components[$cid]' : null,
        tabContext: tabContext,
        message: firstLine.length > 180
            ? '${firstLine.substring(0, 177)}…'
            : firstLine,
      ),
    );
  }

  static Set<String> _collectFixedHeightSlotIds(Appearance appearance) {
    final fixedIds = <String>{};
    void inspectSlots(
      Map<String, Size?> preferredSizes,
      Map<String, SlotSizeConstraints> constraints,
    ) {
      for (final entry in preferredSizes.entries) {
        final sz = entry.value;
        if (sz != null && sz.height.isFinite && sz.height > 0) {
          fixedIds.add(entry.key);
        }
      }
      for (final entry in constraints.entries) {
        final c = entry.value;
        if (c.preferredHeight != null || c.maxHeight != null) {
          fixedIds.add(entry.key);
        }
      }
    }

    for (final cfg in appearance.components.values) {
      switch (cfg) {
        case final SuperLayoutConfig l:
          inspectSlots(l.slotPreferredSizes, l.slotSizeConstraints);
        case final SuperListViewConfig list:
          inspectSlots(
            list.template.slotPreferredSizes,
            list.template.slotSizeConstraints,
          );
        case final SuperTableConfig t:
          inspectSlots(t.slotPreferredSizes, t.slotSizeConstraints);
        case final SuperTreeViewConfig tree:
          inspectSlots(tree.slotPreferredSizes, tree.slotSizeConstraints);
        case final SuperTabConfig tab:
          inspectSlots(tab.slotPreferredSizes, tab.slotSizeConstraints);
        case final NativeComponentConfig n:
          inspectSlots(n.slotPreferredSizes, n.slotSizeConstraints);
        case final ScaffoldPageConfig s:
          inspectSlots(
            s.native.slotPreferredSizes,
            s.native.slotSizeConstraints,
          );
        default:
          break;
      }
    }
    return fixedIds;
  }

  static String _listTemplateMountedLayoutId(
    String listId,
    SuperListViewConfig cfg,
  ) {
    final itemId = cfg.itemId ?? '$listId:item';
    return itemId.endsWith(':item')
        ? '${itemId.substring(0, itemId.length - 5)}:layout'
        : '$itemId:layout';
  }

  static double? _boundedListRowHeight(SuperListViewConfig cfg) {
    final itemSize = cfg.itemSize;
    if (itemSize != null) {
      if (itemSize.preferredHeight?.unit == SlotSizeUnit.pixels) {
        return itemSize.preferredHeight!.value;
      }
      if (itemSize.maxHeight?.unit == SlotSizeUnit.pixels) {
        return itemSize.maxHeight!.value;
      }
      return null;
    }
    if (cfg.wrap) {
      return cfg.wrapSizing == ListWrapSizing.automatic ? null : cfg.itemExtent;
    }
    return cfg.axis == Axis.vertical ? cfg.itemExtent : null;
  }

  static Map<Object?, Object?>? _findVisibleZoneOccurrence(
    Object? compData, {
    required String? zoneId,
  }) {
    if (compData is! Map) return null;
    final occs = compData['occurrences'];
    if (occs is! List) return null;
    for (final occ in occs) {
      if (occ is! Map || occ['zoneId'] != zoneId) continue;
      final diag = occ['diagnostics'];
      if (diag is Map && diag['isOffscreen'] == true) continue;
      return occ;
    }
    return null;
  }

  static void _auditZoneSpatialBudget({
    required Map<Object?, Object?> comps,
    required Set<String> queriedSet,
    required String componentId,
    required String zoneName,
    required String location,
    required Axis axis,
    required ZoneFlowConfig flow,
    required List<String> childIds,
    required Map<Object?, Object?>? parentOcc,
    required bool hasExplicitBoundedHeight,
    required void Function(VibeAuditFinding finding) addFinding,
    EdgeInsets extraPadding = EdgeInsets.zero,
    String? tabContext,
  }) {
    if (flow.scrollable || childIds.isEmpty || parentOcc == null) return;
    if (!childIds.every(queriedSet.contains)) return;

    final sz = parentOcc['size'];
    if (sz is! Map) return;
    final parentWidth = sz['width'] is num
        ? (sz['width'] as num).toDouble()
        : null;
    final parentHeight = sz['height'] is num
        ? (sz['height'] as num).toDouble()
        : null;
    final constraints = parentOcc['constraints'];
    final hasBoundedHeight =
        hasExplicitBoundedHeight ||
        (constraints is Map && constraints['hasBoundedHeight'] == true) ||
        parentOcc['fixedHeight'] == true;

    final pad = flow.contentPadding + extraPadding;
    final availableWidth = parentWidth != null
        ? parentWidth - pad.left - pad.right
        : null;
    final availableHeight = parentHeight != null
        ? parentHeight - pad.top - pad.bottom
        : null;

    var measuredWidths = 0;
    var childrenWidthSum = 0.0;
    var measuredHeights = 0;
    var childrenHeightSum = 0.0;
    var maxChildHeight = 0.0;

    for (final childId in childIds) {
      final childOcc = _findVisibleZoneOccurrence(comps[childId], zoneId: null);
      if (childOcc == null) continue;
      final childSz = childOcc['size'];
      if (childSz is! Map) continue;
      if (childSz['width'] is num) {
        final w = (childSz['width'] as num).toDouble();
        if (w > 0) {
          childrenWidthSum += w;
          measuredWidths++;
        }
      }
      if (childSz['height'] is num) {
        final rawH = (childSz['height'] as num).toDouble();
        final unclippedH = childSz['unclippedHeight'] is num
            ? (childSz['unclippedHeight'] as num).toDouble()
            : rawH;
        final effectiveH = math.max(rawH, unclippedH);
        if (effectiveH > 0) {
          childrenHeightSum += effectiveH;
          if (effectiveH > maxChildHeight) maxChildHeight = effectiveH;
          measuredHeights++;
        }
      }
    }

    if (axis == Axis.horizontal) {
      if (availableWidth != null && availableWidth > 0 && measuredWidths >= 2) {
        final totalRequiredWidth =
            childrenWidthSum + flow.spacing * (measuredWidths - 1);
        if (totalRequiredWidth > availableWidth + 1.5) {
          addFinding(
            VibeAuditFinding(
              category: VibeAuditCategory.layoutAndClipping,
              severity: VibeAuditSeverity.error,
              kind: 'row_width_budget_exceeded',
              componentId: componentId,
              zoneId: zoneName,
              location: location,
              tabContext: tabContext,
              message:
                  'Budget de largeur en ligne dépassé (${totalRequiredWidth.round()} dp mesurés [enfants + espacements] pour ${availableWidth.round()} dp disponibles = ${parentWidth!.round()} dp - padding horizontal ${(pad.left + pad.right).round()} dp).',
            ),
          );
        }
      }

      if (hasExplicitBoundedHeight &&
          availableHeight != null &&
          availableHeight > 0 &&
          measuredHeights >= 1 &&
          maxChildHeight > availableHeight + 1.5) {
        addFinding(
          VibeAuditFinding(
            category: VibeAuditCategory.layoutAndClipping,
            severity: VibeAuditSeverity.error,
            kind: 'vertical_budget_overflow',
            componentId: componentId,
            zoneId: zoneName,
            location: location,
            tabContext: tabContext,
            message:
                'Budget de hauteur dépassé dans un conteneur borné (${maxChildHeight.round()} dp requis par un enfant pour ${availableHeight.round()} dp disponibles = ${parentHeight!.round()} dp - padding vertical ${(pad.top + pad.bottom).round()} dp) : appliquer un calibrage compact (preferredHeight: "32px", padding: 0) ou augmenter la hauteur du conteneur.',
          ),
        );
      }
      return;
    }

    if (hasBoundedHeight &&
        availableHeight != null &&
        availableHeight > 0 &&
        measuredHeights >= 1) {
      final totalRequiredHeight =
          childrenHeightSum +
          (measuredHeights > 1 ? flow.spacing * (measuredHeights - 1) : 0.0);
      if (totalRequiredHeight > availableHeight + 1.5) {
        final advice = measuredHeights >= 2 && parentHeight! < 68
            ? 'basculer zoneAxes en "row" avec crossAxisAlignment: "center", calibrer les contrôles en compact (preferredHeight: "32px") ou augmenter la hauteur utile.'
            : 'activer scrollable: true, basculer zoneAxes en "row", compacter les enfants ou augmenter la hauteur bornée du conteneur.';
        addFinding(
          VibeAuditFinding(
            category: VibeAuditCategory.layoutAndClipping,
            severity: VibeAuditSeverity.error,
            kind: 'vertical_budget_overflow',
            componentId: componentId,
            zoneId: zoneName,
            location: location,
            tabContext: tabContext,
            message:
                'Budget vertical dépassé (${totalRequiredHeight.round()} dp mesurés [enfants + espacements] pour ${availableHeight.round()} dp disponibles = ${parentHeight!.round()} dp - padding vertical ${(pad.top + pad.bottom).round()} dp) : $advice',
          ),
        );
      }
    }
  }

  static Future<void> _collectGeometryPass({
    required VibeAppInspector inspector,
    required Appearance appearance,
    required Iterable<String> candidateIds,
    required void Function(VibeAuditFinding finding) addFinding,
    Map<String, String>? recordedSizesById,
    Set<String> skipContentZonesForTabIds = const <String>{},
    String? onlyZoneFilter,
    String? tabContext,
    bool visibleOnly = false,
  }) async {
    final mountedSet = inspector.slotIndex.mountedComponentIds.toSet();
    final geometryIds = <String>[
      for (final id in candidateIds)
        if (mountedSet.contains(id)) id,
    ].take(_maxGeometryIds).toList(growable: false);
    if (geometryIds.isEmpty) return;

    final geometryIdSet = geometryIds.toSet();
    final companionMountIds = <String>[
      for (final id in geometryIds)
        if (appearance.components[id] case final SuperListViewConfig listCfg)
          if (_listTemplateMountedLayoutId(id, listCfg) case final mountId
              when mountedSet.contains(mountId) &&
                  !geometryIdSet.contains(mountId))
            mountId,
    ];

    final geo = await inspector.getComponentGeometry(<String, Object?>{
      'ids': <String>[...geometryIds, ...companionMountIds],
      'zoneId': ?onlyZoneFilter,
      'includeZones': true,
      'includeScroll': true,
    });
    final comps = geo['components'];
    if (comps is! Map) return;

    for (final entry in comps.entries) {
      final id = entry.key is String ? entry.key as String : '${entry.key}';
      if (!geometryIdSet.contains(id)) continue;
      final compData = entry.value;
      if (compData is! Map) continue;
      final occurrences = compData['occurrences'];
      if (occurrences is! List) continue;
      for (final occ in occurrences) {
        if (occ is! Map) continue;
        final zoneId = occ['zoneId'] as String?;
        if (recordedSizesById != null &&
            zoneId == null &&
            !recordedSizesById.containsKey(id)) {
          final sz = occ['size'];
          if (sz is Map && sz['width'] is num && sz['height'] is num) {
            final w = (sz['width'] as num).toDouble();
            final h = (sz['height'] as num).toDouble();
            if (w > 0 || h > 0) {
              recordedSizesById[id] = '${w.round()}×${h.round()} dp';
            }
          }
        }
        if (zoneId != null &&
            skipContentZonesForTabIds.contains(id) &&
            (zoneId == SuperTabConfig.dynamicContentZone ||
                zoneId.startsWith('content:'))) {
          continue;
        }
        final diag = occ['diagnostics'];
        if (diag is Map) {
          if (visibleOnly &&
              diag['isVisibleInViewport'] == false &&
              diag['isZeroSized'] != true) {
            continue;
          }
          if (diag['isZeroSized'] == true) {
            addFinding(
              VibeAuditFinding(
                category: VibeAuditCategory.layoutAndClipping,
                severity: VibeAuditSeverity.error,
                kind: 'zero_sized_component',
                componentId: id,
                zoneId: zoneId,
                tabContext: tabContext,
                message: 'Le composant ou sa zone a une taille rendue nulle (0 px), ce qui le rend invisible ou écrasé.',
              ),
            );
          }
          if (diag['exceedsParentWidth'] == true ||
              diag['exceedsParentHeight'] == true) {
            final axes = <String>[
              if (diag['exceedsParentWidth'] == true) 'largeur',
              if (diag['exceedsParentHeight'] == true) 'hauteur',
            ].join(' et ');
            addFinding(
              VibeAuditFinding(
                category: VibeAuditCategory.layoutAndClipping,
                severity: VibeAuditSeverity.error,
                kind: 'exceeds_parent_bounds',
                componentId: id,
                zoneId: zoneId,
                tabContext: tabContext,
                message:
                    'Déborde des bornes de son conteneur parent ($axes) : risque de coupure par les marges ou contraintes.',
              ),
            );
          }
          if (diag['isClippedByAncestor'] == true) {
            final edges = diag['clippedEdges'];
            final edgeLabel = edges is List && edges.isNotEmpty
                ? ' (bords : ${edges.join(', ')})'
                : '';
            addFinding(
              VibeAuditFinding(
                category: VibeAuditCategory.layoutAndClipping,
                severity: VibeAuditSeverity.error,
                kind: 'clipped_by_ancestor',
                componentId: id,
                zoneId: zoneId,
                tabContext: tabContext,
                message:
                    'Contenu rogné par un ancêtre clippé$edgeLabel : ajuster les marges, le padding ou `fitContent` / la taille du slot.',
              ),
            );
          }
          if (diag['clipsChildContent'] == true) {
            addFinding(
              VibeAuditFinding(
                category: VibeAuditCategory.layoutAndClipping,
                severity: VibeAuditSeverity.warning,
                kind: 'clips_child_content',
                componentId: id,
                zoneId: zoneId,
                tabContext: tabContext,
                message: 'Un ou plusieurs enfants dépassent la boîte rendue de ce conteneur (marge/padding ou contrainte fixe trop serrée).',
              ),
            );
          }
          if (diag['exceedsViewportWidth'] == true ||
              diag['exceedsViewportHeight'] == true) {
            addFinding(
              VibeAuditFinding(
                category: VibeAuditCategory.layoutAndClipping,
                severity: VibeAuditSeverity.error,
                kind: 'exceeds_viewport',
                componentId: id,
                zoneId: zoneId,
                tabContext: tabContext,
                message: 'Dépasse les limites visibles du viewport (horizontalement ou verticalement sans scroll adapté).',
              ),
            );
          }
          if (diag['hasTruncatedText'] == true) {
            final samples = diag['truncatedTextSamples'];
            final preview = samples is List && samples.isNotEmpty
                ? ' (« ${samples.first} »)'
                : '';
            addFinding(
              VibeAuditFinding(
                category: VibeAuditCategory.layoutAndClipping,
                severity: VibeAuditSeverity.warning,
                kind: 'truncated_text',
                componentId: id,
                zoneId: zoneId,
                tabContext: tabContext,
                message:
                    'Texte tronqué ou coupé par manque d’espace/hauteur$preview.',
              ),
            );
          }
        }
        final sliver = occ['sliver'];
        if (sliver is Map && sliver['hasVisualOverflow'] == true) {
          addFinding(
            VibeAuditFinding(
              category: VibeAuditCategory.layoutAndClipping,
              severity: VibeAuditSeverity.warning,
              kind: 'sliver_visual_overflow',
              componentId: id,
              zoneId: zoneId,
              tabContext: tabContext,
              message: 'Sliver présentant un débordement visuel dans sa zone de défilement.',
            ),
          );
        }
      }
    }

    // Contrôle budgétaire bidirectionnel (largeur en `row` et hauteur verticale bornée).
    if (onlyZoneFilter == null) {
      final queriedSet = geometryIdSet;
      final fixedHeightIds = _collectFixedHeightSlotIds(appearance);

      void auditSuperLayoutZones({
        required String ownerId,
        required String mountedLayoutId,
        required String locationPrefix,
        required SuperLayoutConfig layoutCfg,
        required bool hasExplicitContainerHeight,
        required bool inCompactRowTemplate,
      }) {
        final layoutData = comps[mountedLayoutId];
        if (layoutData is! Map) return;
        for (final placementEntry in layoutCfg.placements.entries) {
          final zone = placementEntry.key;
          final childIds = placementEntry.value;
          if (childIds.isEmpty) continue;
          final contentZone = layoutCfg.contentZone(zone);
          final axis = layoutCfg.effectiveAxisOf(
            contentZone,
            inCompactRowTemplate: inCompactRowTemplate,
            childCount: childIds.length,
          );
          final flow = layoutCfg.flowOf(contentZone);
          final fixedVerticalSide =
              (zone == SuperLayoutZone.north ||
                  zone == SuperLayoutZone.south) &&
              !layoutCfg.isAuto(zone);
          _auditZoneSpatialBudget(
            comps: comps,
            queriedSet: queriedSet,
            componentId: ownerId,
            zoneName: contentZone.name,
            location: '$locationPrefix.zoneFlows.${contentZone.name}',
            axis: axis,
            flow: flow,
            childIds: childIds,
            parentOcc: _findVisibleZoneOccurrence(
              layoutData,
              zoneId: contentZone.name,
            ),
            hasExplicitBoundedHeight:
                hasExplicitContainerHeight || fixedVerticalSide,
            addFinding: addFinding,
            tabContext: tabContext,
          );
        }
      }

      for (final ownerId in geometryIds) {
        final cfg = appearance.components[ownerId];
        switch (cfg) {
          case final SuperLayoutConfig layoutCfg:
            auditSuperLayoutZones(
              ownerId: ownerId,
              mountedLayoutId: ownerId,
              locationPrefix: 'components[$ownerId]',
              layoutCfg: layoutCfg,
              hasExplicitContainerHeight: fixedHeightIds.contains(ownerId),
              inCompactRowTemplate: false,
            );

          case final SuperListViewConfig listCfg:
            final boundedRowHeight = _boundedListRowHeight(listCfg);
            auditSuperLayoutZones(
              ownerId: ownerId,
              mountedLayoutId: _listTemplateMountedLayoutId(ownerId, listCfg),
              locationPrefix: 'components[$ownerId].template',
              layoutCfg: listCfg.template,
              hasExplicitContainerHeight: boundedRowHeight != null,
              inCompactRowTemplate:
                  boundedRowHeight != null &&
                  boundedRowHeight <=
                      SuperLayoutConfig.compactRowTemplateMaxHeight,
            );

          case final SuperTableConfig tableCfg:
            final tableData = comps[ownerId];
            final tableRootOcc = _findVisibleZoneOccurrence(
              tableData,
              zoneId: null,
            );
            final zoneSpecs =
                <
                  ({
                    String zoneId,
                    double rowHeight,
                    SuperTableColumnConfig col,
                  })
                >[
                  for (final col in tableCfg.columns) ...[
                    if (tableCfg.showHeaderRow)
                      (
                        zoneId: SuperTableConfig.headerZoneFor(col.id),
                        rowHeight: tableCfg.headerRowHeight,
                        col: col,
                      ),
                    (
                      zoneId: SuperTableConfig.cellZoneFor(col.id),
                      rowHeight: tableCfg.rowHeight,
                      col: col,
                    ),
                    if (tableCfg.showBottomRow)
                      (
                        zoneId: SuperTableConfig.bottomZoneFor(col.id),
                        rowHeight: tableCfg.bottomRowHeight,
                        col: col,
                      ),
                  ],
                ];
            for (final spec in zoneSpecs) {
              final zoneId = spec.zoneId;
              final childIds = tableCfg.slotsOf(zoneId);
              if (childIds.isEmpty) continue;
              final measuredZoneOcc = _findVisibleZoneOccurrence(
                tableData,
                zoneId: zoneId,
              );
              final fallbackZoneOcc =
                  measuredZoneOcc == null && tableRootOcc != null
                  ? <Object?, Object?>{
                      'size': <String, Object?>{
                        if (!spec.col.isFill) 'width': spec.col.width,
                        'height': spec.rowHeight,
                      },
                      'constraints': const <String, Object?>{
                        'hasBoundedHeight': true,
                      },
                    }
                  : null;
              final extraPad = fallbackZoneOcc != null
                  ? tableCfg.zoneStyleOf(zoneId).contentPadding
                  : EdgeInsets.zero;
              _auditZoneSpatialBudget(
                comps: comps,
                queriedSet: queriedSet,
                componentId: ownerId,
                zoneName: zoneId,
                location: 'components[$ownerId].zoneFlows.$zoneId',
                axis: tableCfg.zoneAxisOf(zoneId) ?? Axis.horizontal,
                flow: tableCfg.zoneFlowOf(zoneId),
                childIds: childIds,
                parentOcc: measuredZoneOcc ?? fallbackZoneOcc,
                hasExplicitBoundedHeight: true,
                extraPadding: extraPad,
                addFinding: addFinding,
                tabContext: tabContext,
              );
            }

          case final SuperTreeViewConfig treeCfg:
            final treeData = comps[ownerId];
            final treeRootOcc = _findVisibleZoneOccurrence(
              treeData,
              zoneId: null,
            );
            for (final zoneId in const <String>[
              SuperTreeViewConfig.headerZone,
              SuperTreeViewConfig.dataZone,
            ]) {
              final childIds = treeCfg.slotsOf(zoneId);
              if (childIds.isEmpty) continue;
              final measuredZoneOcc = _findVisibleZoneOccurrence(
                treeData,
                zoneId: zoneId,
              );
              final fallbackZoneOcc =
                  measuredZoneOcc == null && treeRootOcc != null
                  ? <Object?, Object?>{
                      'size': <String, Object?>{
                        if (zoneId == SuperTreeViewConfig.headerZone)
                          'width': treeCfg.headerSize,
                        'height': treeCfg.rowHeight,
                      },
                      'constraints': const <String, Object?>{
                        'hasBoundedHeight': true,
                      },
                    }
                  : null;
              _auditZoneSpatialBudget(
                comps: comps,
                queriedSet: queriedSet,
                componentId: ownerId,
                zoneName: zoneId,
                location: 'components[$ownerId].zoneFlows.$zoneId',
                axis: treeCfg.zoneAxisOf(zoneId) ?? Axis.horizontal,
                flow: treeCfg.zoneFlowOf(zoneId),
                childIds: childIds,
                parentOcc: measuredZoneOcc ?? fallbackZoneOcc,
                hasExplicitBoundedHeight: true,
                addFinding: addFinding,
                tabContext: tabContext,
              );
            }

          case final NativeComponentConfig nativeCfg:
            final nativeData = comps[ownerId];
            final ownerStyle = appearance.styles[ownerId];
            final hasFixedOwnerHeight =
                fixedHeightIds.contains(ownerId) ||
                nativeCfg.doubleProperty('toolbarHeight') != null;
            for (final entry in nativeCfg.placements.entries) {
              final regionId = entry.key;
              final childIds = entry.value;
              if (childIds.isEmpty || !nativeCfg.isEnabled(regionId)) continue;
              final regionOcc = _findVisibleZoneOccurrence(
                nativeData,
                zoneId: regionId,
              );
              final fallbackRootOcc = regionOcc == null && regionId == 'child'
                  ? _findVisibleZoneOccurrence(nativeData, zoneId: null)
                  : null;
              final extraPad = fallbackRootOcc != null && ownerStyle != null
                  ? ownerStyle.outerMargin + ownerStyle.contentPadding
                  : EdgeInsets.zero;
              final defaultHorizontalBar =
                  regionId == 'actions' ||
                  regionId == 'leading' ||
                  regionId == 'left' ||
                  regionId == 'right';
              final axis =
                  nativeCfg.regionAxisOf(regionId) ??
                  (defaultHorizontalBar ? Axis.horizontal : Axis.vertical);
              _auditZoneSpatialBudget(
                comps: comps,
                queriedSet: queriedSet,
                componentId: ownerId,
                zoneName: regionId,
                location: 'components[$ownerId].zoneFlows.$regionId',
                axis: axis,
                flow: nativeCfg.regionFlowOf(regionId),
                childIds: childIds,
                parentOcc: regionOcc ?? fallbackRootOcc,
                hasExplicitBoundedHeight: hasFixedOwnerHeight,
                extraPadding: extraPad,
                addFinding: addFinding,
                tabContext: tabContext,
              );
            }

          default:
            break;
        }
      }
    }
  }

  /// Collecte les anomalies géométriques, runtime, de calculs/bindings et de contraste.
  static Future<VibePageAuditReport> collect(VibeAppInspector inspector) async {
    final appearance = inspector.readAppearance();
    final scope = inspector.readScope?.call();
    final visibleOnly = inspector.readVisibleOnly?.call() == true;
    final activePage = inspector.resolveActivePage(appearance);
    final rawScopedIds = inspector
        .collectScopeOrActivePageComponentIds(appearance)
        .toList(growable: false);
    final visibleSnapshot = visibleOnly
        ? inspector.captureVisibleViewportSnapshot(appearance)
        : null;
    final scopedIds =
        visibleSnapshot != null && visibleSnapshot.hasMeasuredViewport
        ? <String>[
            for (final id in rawScopedIds)
              if (!visibleSnapshot.protectedOffscreenComponentIds.contains(id))
                id,
          ]
        : rawScopedIds;
    final scopedIdSet = scopedIds.toSet();

    final viewportRoute = await inspector.getViewportAndRoute();
    final vp = viewportRoute['viewport'];
    final viewportWidth = vp is Map && vp['width'] is num
        ? (vp['width'] as num).toDouble()
        : null;
    final viewportHeight = vp is Map && vp['height'] is num
        ? (vp['height'] as num).toDouble()
        : null;

    final String baseTargetLabel;
    if (scope != null) {
      baseTargetLabel = 'Scope "${scope.displayLabel}"';
    } else if (activePage != null) {
      baseTargetLabel = 'Page "${activePage.name}" (${activePage.path})';
    } else {
      baseTargetLabel = 'Écran actif';
    }
    final targetLabel = visibleOnly
        ? '$baseTargetLabel [Uniquement visible — onglet & scroll courants]'
        : baseTargetLabel;

    final findings = <VibeAuditFinding>[];
    final seenSignatures = <String>{};
    final sweptTabs = <VibeSweptTabSummary>[];
    final recordedSizesById = <String, String>{};

    void addFinding(VibeAuditFinding finding) {
      final sig =
          '${finding.kind}|${finding.componentId ?? ''}|${finding.zoneId ?? ''}|${finding.location ?? ''}|${finding.tabContext ?? ''}|${finding.message}';
      if (seenSignatures.add(sig)) {
        findings.add(finding);
      }
    }

    // 1. Géométrie, marges coupées, dépassements parent/viewport, budget de largeur `row`
    //    et balayage automatique des onglets `SuperTab` lorsqu'aucun scope ni mode « Uniquement visible » n'est actif.
    if (scope == null && !visibleOnly) {
      final rootTabs = inspector.collectActiveMountedTabEntries(
        allowedComponentIds: scopedIdSet,
      );
      final rootTabIds = <String>{for (final t in rootTabs) t.componentId};
      final allRootTabContentIds = <String>{
        for (final t in rootTabs)
          ..._collectAllTabContentSubtreeIds(appearance, t.componentId),
      };

      // 1a. Passe sur la coque de page (hors contenus internes des SuperTab).
      await _collectGeometryPass(
        inspector: inspector,
        appearance: appearance,
        candidateIds: scopedIds.where(
          (id) => !allRootTabContentIds.contains(id),
        ),
        skipContentZonesForTabIds: rootTabIds,
        recordedSizesById: recordedSizesById,
        addFinding: addFinding,
      );

      // 1b. Balayage séquentiel de tous les onglets montés (et sous-onglets éventuels).
      var tabSwitches = 0;
      final visitedTabIds = <String>{};

      Future<void> sweepTabEntries(
        List<VibeMountedTabEntry> entries, {
        required int depth,
      }) async {
        for (final tabEntry in entries) {
          if (!visitedTabIds.add(tabEntry.componentId)) continue;
          final snap = tabEntry.readSnapshot();
          if (snap == null || snap.tabCount == 0) continue;
          final initialIndex = snap.activeIndex;
          var didSwitch = false;
          try {
            for (final tabItem in snap.tabs) {
              sweptTabs.add(
                VibeSweptTabSummary(
                  tabComponentId: snap.componentId,
                  tabIndex: tabItem.index,
                  tabId: tabItem.tabId,
                  label: tabItem.label,
                  contentZone: tabItem.contentZone,
                ),
              );
              final tabLabelContext =
                  '${snap.componentId}[${tabItem.index}] "${tabItem.label}"';
              final currentActive = tabEntry.readSnapshot()?.activeIndex;
              VibeDebugMarker? beforeSwitch;
              if (currentActive != tabItem.index) {
                if (tabSwitches >= _maxTabSwitches) continue;
                beforeSwitch = VibeDebugCapture.markNow();
                if (tabEntry.selectTab(tabItem.index)) {
                  didSwitch = true;
                  tabSwitches++;
                  await inspector.waitForVisualFrame();
                }
              }

              final zoneSubtreeIds = _collectTabZoneSubtreeIds(
                appearance,
                snap.componentId,
                tabItem.contentZone,
              );
              final nestedTabs = depth + 1 < _maxNestedTabDepth
                  ? inspector
                        .collectActiveMountedTabEntries(
                          allowedComponentIds: zoneSubtreeIds,
                        )
                        .where((e) => !visitedTabIds.contains(e.componentId))
                        .toList(growable: false)
                  : const <VibeMountedTabEntry>[];
              final nestedTabIds = <String>{
                for (final n in nestedTabs) n.componentId,
              };
              final nestedContentIds = <String>{
                for (final n in nestedTabs)
                  ..._collectAllTabContentSubtreeIds(appearance, n.componentId),
              };

              await _collectGeometryPass(
                inspector: inspector,
                appearance: appearance,
                candidateIds: <String>[snap.componentId],
                onlyZoneFilter: tabItem.contentZone,
                tabContext: tabLabelContext,
                addFinding: addFinding,
              );
              await _collectGeometryPass(
                inspector: inspector,
                appearance: appearance,
                candidateIds: zoneSubtreeIds.where(
                  (id) => !nestedContentIds.contains(id),
                ),
                skipContentZonesForTabIds: nestedTabIds,
                tabContext: tabLabelContext,
                addFinding: addFinding,
              );

              if (beforeSwitch != null) {
                final switchErrors = VibeDebugCapture.entriesSince(
                  beforeSwitch,
                  type: DebugEntryType.error,
                );
                for (final err in switchErrors) {
                  _recordDebugEntryFinding(
                    err,
                    addFinding: addFinding,
                    tabContext: tabLabelContext,
                  );
                }
              }

              if (nestedTabs.isNotEmpty) {
                await sweepTabEntries(nestedTabs, depth: depth + 1);
              }
            }
          } finally {
            if (didSwitch) {
              tabEntry.restoreTab(initialIndex);
              await inspector.waitForVisualFrame();
            }
          }
        }
      }

      if (rootTabs.isNotEmpty) {
        await sweepTabEntries(rootTabs, depth: 0);
      }
    } else {
      // Scope actif : pas de balayage des autres onglets, et exclusion des zones d'onglets inactifs gardées en vie.
      final activeTabsInScope = inspector.collectActiveMountedTabEntries(
        allowedComponentIds: scopedIdSet,
      );
      final inactiveTabContentIds = <String>{};
      for (final tabEntry in activeTabsInScope) {
        final snap = tabEntry.readSnapshot();
        if (snap == null || snap.isDynamic) continue;
        for (final tabItem in snap.tabs) {
          if (tabItem.index == snap.activeIndex) continue;
          inactiveTabContentIds.addAll(
            _collectTabZoneSubtreeIds(
              appearance,
              snap.componentId,
              tabItem.contentZone,
            ),
          );
        }
      }
      await _collectGeometryPass(
        inspector: inspector,
        appearance: appearance,
        candidateIds: scopedIds.where(
          (id) => !inactiveTabContentIds.contains(id),
        ),
        visibleOnly: visibleOnly,
        recordedSizesById: recordedSizesById,
        addFinding: addFinding,
      );
    }

    // 2. Diagnostics de bindings, schémas, marges/tailles fixes et @calculs manquants.
    final bindingDiag = await inspector.inspectBindingsAndDiagnostics(
      <String, Object?>{if (scopedIds.isNotEmpty) 'componentIds': scopedIds},
    );
    final rawIssues = bindingDiag['issues'];
    if (rawIssues is List) {
      for (final raw in rawIssues) {
        if (raw is! Map) continue;
        final kind = raw['kind'] as String? ?? 'binding_issue';
        final componentId = raw['componentId'] as String?;
        final location = raw['location'] as String?;
        final message = raw['message'] as String? ?? kind;
        final category = switch (kind) {
          'undeclared_calculated_attribute' ||
          'suspected_missing_calculation' =>
            VibeAuditCategory.missingCalculation,
          'list_remove_button_overlap_risk' ||
          'excessive_margin_or_padding_for_fixed_size' =>
            VibeAuditCategory.layoutAndClipping,
          _ => VibeAuditCategory.bindingAndSchema,
        };
        final severity = switch (kind) {
          'suspected_missing_calculation' => VibeAuditSeverity.warning,
          _ => VibeAuditSeverity.error,
        };
        addFinding(
          VibeAuditFinding(
            category: category,
            severity: severity,
            kind: kind,
            componentId: componentId,
            location: location,
            message: message,
          ),
        );
      }
    }
    if (bindingDiag['activeRepositoryError'] case final String repoErr
        when repoErr.trim().isNotEmpty) {
      addFinding(
        VibeAuditFinding(
          category: VibeAuditCategory.bindingAndSchema,
          severity: VibeAuditSeverity.error,
          kind: 'active_repository_error',
          message: repoErr.trim(),
        ),
      );
    }

    // 3. Erreurs d'exécution typées récentes (RenderFlex, binding, JS, polices, erreurs rouges IHM).
    final debugDiag = await inspector.getDebugEntries(<String, Object?>{
      'type': 'error',
      'minSeverity': 'warning',
      'sinceTurnStart': false,
      'limit': 20,
    });
    final entries = debugDiag['entries'];
    if (entries is List) {
      for (final raw in entries) {
        if (raw is! Map) continue;
        final msg = raw['message'] as String? ?? '';
        if (msg.trim().isEmpty) continue;
        final rawCat = (raw['category'] as String? ?? '').trim();
        // Les erreurs de saisie utilisateur ne sont pas des défauts structurels de la page.
        if (rawCat == 'userInput') continue;
        final rawSev = (raw['severity'] as String? ?? 'error').trim();
        final cid = raw['componentId'] as String?;
        final firstLine = msg.trim().split('\n').first.trim();
        final isLayoutOverflow =
            firstLine.contains('overflowed') ||
            firstLine.contains('RenderFlex') ||
            firstLine.contains('RenderBox');
        final VibeAuditCategory auditCategory = switch (rawCat) {
          'binding' => VibeAuditCategory.bindingAndSchema,
          'font' => VibeAuditCategory.contrastAndStyle,
          'rendering' when isLayoutOverflow =>
            VibeAuditCategory.layoutAndClipping,
          _ =>
            isLayoutOverflow
                ? VibeAuditCategory.layoutAndClipping
                : VibeAuditCategory.runtimeError,
        };
        final VibeAuditSeverity auditSeverity = switch (rawSev) {
          'warning' => VibeAuditSeverity.warning,
          'info' => VibeAuditSeverity.info,
          _ => VibeAuditSeverity.error,
        };
        final String auditKind = switch (rawCat) {
          'javascript' => 'javascript_runtime_error',
          'font' => 'missing_or_invalid_font',
          'binding' => 'ui_binding_runtime_error',
          _ =>
            isLayoutOverflow
                ? 'render_overflow_debug_error'
                : 'runtime_debug_error',
        };
        addFinding(
          VibeAuditFinding(
            category: auditCategory,
            severity: auditSeverity,
            kind: auditKind,
            componentId: cid,
            location: cid != null ? 'components[$cid]' : null,
            message: firstLine.length > 180
                ? '${firstLine.substring(0, 177)}…'
                : firstLine,
          ),
        );
      }
    }

    // 4. Contraste WCAG AA sur les composants du périmètre.
    final contrastDiag = await inspector.getThemeAndContrast(<String, Object?>{
      if (scopedIds.isNotEmpty) 'componentIds': scopedIds,
      'onlyIssues': true,
    });
    final checks = contrastDiag['contrastChecks'];
    if (checks is List) {
      for (final raw in checks) {
        if (raw is! Map) continue;
        final cid = raw['componentId'] as String?;
        final ratio = raw['contrastRatio'];
        final fg = raw['foreground'];
        final bg = raw['background'];
        addFinding(
          VibeAuditFinding(
            category: VibeAuditCategory.contrastAndStyle,
            severity: VibeAuditSeverity.warning,
            kind: 'wcag_aa_contrast_failure',
            componentId: cid,
            location: cid != null ? 'components[$cid]' : null,
            message:
                'Contraste insuffisant (ratio $ratio, texte $fg sur fond $bg, minimum WCAG AA 4.5:1 ou 3:1 grand texte).',
          ),
        );
      }
    }

    // 5. Détection des composants fantômes lorsqu'un conteneur racine monté a 0 placement.
    if (scope == null) {
      _collectEmptyRootGhostComponentsFindings(
        appearance: appearance,
        instantiatedIds:
            inspector.registry?.instantiatedComponentIds ?? const <String>[],
        mountedComponentIds: inspector.slotIndex.mountedComponentIds,
        addFinding: addFinding,
      );
    }

    // 6. Cohérence de navigation multi-pages et intégrité des shells partagés (hors scope / visibleOnly).
    if (scope == null && !visibleOnly) {
      _collectMultiPageNavigationFindings(
        appearance: appearance,
        addFinding: addFinding,
      );
    }

    return VibePageAuditReport(
      targetLabel: targetLabel,
      pageId: activePage?.id,
      pageName: activePage?.name,
      pagePath: activePage?.path,
      isScoped: scope != null,
      visibleOnly: visibleOnly,
      auditedComponentIds: scopedIds,
      findings: findings,
      sweptTabs: sweptTabs,
      measuredGeometrySummaries: [
        for (final entry in recordedSizesById.entries)
          '${entry.key}: ${entry.value}',
      ],
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
  }
}
