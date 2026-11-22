/// Service de pré-audit déterministe d'une page ou d'un scope ([VibePageAuditService])
/// pour le bouton « Audit & correction » du chat Vibe IA.
///
/// Agrège en une passe structurée :
/// - la géométrie réelle et les coupures/débordements (`get_component_geometry`) ;
/// - les erreurs runtime capturées dans `debugEntries` (`RenderFlex`, contraintes) ;
/// - les liaisons JSON, marges/tailles fixes et `@calculs` manquants (`inspect_bindings_and_diagnostics`) ;
/// - les défauts de contraste WCAG AA (`get_theme_and_contrast`).
library;

import 'package:flutter/foundation.dart' show immutable, listEquals;

import 'vibe_app_inspector.dart';

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

  /// Sérialise cette anomalie en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'category': category.name,
    'severity': severity.name,
    'kind': kind,
    'message': message,
    if (componentId != null) 'componentId': componentId,
    if (zoneId != null) 'zoneId': zoneId,
    if (location != null) 'location': location,
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
          other.location == location;

  @override
  int get hashCode => Object.hash(
    category,
    severity,
    kind,
    message,
    componentId,
    zoneId,
    location,
  );
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
    List<String> auditedComponentIds = const <String>[],
    List<VibeAuditFinding> findings = const <VibeAuditFinding>[],
    this.viewportWidth,
    this.viewportHeight,
  }) : auditedComponentIds = List<String>.unmodifiable(auditedComponentIds),
       findings = List<VibeAuditFinding>.unmodifiable(findings);

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
    if (viewportWidth != null && viewportHeight != null)
      'viewport': <String, Object?>{
        'width': viewportWidth,
        'height': viewportHeight,
      },
    'auditedComponentCount': auditedComponentIds.length,
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
        final loc = item.location != null && item.location!.isNotEmpty
            ? ' (${item.location})'
            : '';
        buffer.writeln(
          '  - [${item.severity.label}] $target${item.kind}$loc : ${item.message}',
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
          other.viewportWidth == viewportWidth &&
          other.viewportHeight == viewportHeight &&
          listEquals(other.auditedComponentIds, auditedComponentIds) &&
          listEquals(other.findings, findings);

  @override
  int get hashCode => Object.hash(
    targetLabel,
    pageId,
    pageName,
    pagePath,
    isScoped,
    viewportWidth,
    viewportHeight,
    Object.hashAll(auditedComponentIds),
    Object.hashAll(findings),
  );
}

/// Exécute un pré-audit déterministe complet sur la page active ou le scope actif.
abstract final class VibePageAuditService {
  static const int _maxGeometryIds = 60;

  /// Collecte les anomalies géométriques, runtime, de calculs/bindings et de contraste.
  static Future<VibePageAuditReport> collect(VibeAppInspector inspector) async {
    final appearance = inspector.readAppearance();
    final scope = inspector.readScope?.call();
    final activePage = inspector.resolveActivePage(appearance);
    final scopedIds = inspector
        .collectScopeOrActivePageComponentIds(appearance)
        .toList(growable: false);

    final viewportRoute = await inspector.getViewportAndRoute();
    final vp = viewportRoute['viewport'];
    final viewportWidth = vp is Map && vp['width'] is num
        ? (vp['width'] as num).toDouble()
        : null;
    final viewportHeight = vp is Map && vp['height'] is num
        ? (vp['height'] as num).toDouble()
        : null;

    final String targetLabel;
    if (scope != null) {
      targetLabel = 'Scope "${scope.displayLabel}"';
    } else if (activePage != null) {
      targetLabel = 'Page "${activePage.name}" (${activePage.path})';
    } else {
      targetLabel = 'Écran actif';
    }

    final findings = <VibeAuditFinding>[];
    final seenSignatures = <String>{};

    void addFinding(VibeAuditFinding finding) {
      final sig =
          '${finding.kind}|${finding.componentId ?? ''}|${finding.zoneId ?? ''}|${finding.location ?? ''}|${finding.message}';
      if (seenSignatures.add(sig)) {
        findings.add(finding);
      }
    }

    // 1. Géométrie, marges coupées, dépassements parent/viewport et troncatures.
    final mountedSet = inspector.slotIndex.mountedComponentIds.toSet();
    final geometryIds = <String>[
      for (final id in scopedIds)
        if (mountedSet.contains(id)) id,
    ].take(_maxGeometryIds).toList(growable: false);

    if (geometryIds.isNotEmpty) {
      final geo = await inspector.getComponentGeometry(<String, Object?>{
        'ids': geometryIds,
        'includeZones': true,
        'includeScroll': true,
      });
      final comps = geo['components'];
      if (comps is Map) {
        for (final entry in comps.entries) {
          final id = entry.key is String ? entry.key as String : '${entry.key}';
          final compData = entry.value;
          if (compData is! Map) continue;
          final occurrences = compData['occurrences'];
          if (occurrences is! List) continue;
          for (final occ in occurrences) {
            if (occ is! Map) continue;
            final zoneId = occ['zoneId'] as String?;
            final diag = occ['diagnostics'];
            if (diag is Map) {
              if (diag['isZeroSized'] == true) {
                addFinding(
                  VibeAuditFinding(
                    category: VibeAuditCategory.layoutAndClipping,
                    severity: VibeAuditSeverity.error,
                    kind: 'zero_sized_component',
                    componentId: id,
                    zoneId: zoneId,
                    message:
                        'Le composant ou sa zone a une taille rendue nulle (0 px), ce qui le rend invisible ou écrasé.',
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
                    message:
                        'Un ou plusieurs enfants dépassent la boîte rendue de ce conteneur (marge/padding ou contrainte fixe trop serrée).',
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
                    message:
                        'Dépasse les limites visibles du viewport (horizontalement ou verticalement sans scroll adapté).',
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
                  message:
                      'Sliver présentant un débordement visuel dans sa zone de défilement.',
                ),
              );
            }
          }
        }
      }
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
          'suspected_missing_calculation' => VibeAuditCategory.missingCalculation,
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

    // 3. Erreurs d'exécution Flutter récentes (RenderFlex overflowed, etc.).
    final debugDiag = await inspector.getDebugEntries(<String, Object?>{
      'onlyErrors': true,
      'sinceTurnStart': false,
      'limit': 15,
    });
    final entries = debugDiag['entries'];
    if (entries is List) {
      for (final raw in entries) {
        if (raw is! Map) continue;
        final msg = raw['message'] as String? ?? '';
        if (msg.trim().isEmpty) continue;
        final firstLine = msg.trim().split('\n').first.trim();
        final isLayoutOverflow =
            firstLine.contains('overflowed') ||
            firstLine.contains('RenderFlex') ||
            firstLine.contains('RenderBox');
        addFinding(
          VibeAuditFinding(
            category: isLayoutOverflow
                ? VibeAuditCategory.layoutAndClipping
                : VibeAuditCategory.runtimeError,
            severity: VibeAuditSeverity.error,
            kind: isLayoutOverflow
                ? 'render_overflow_debug_error'
                : 'runtime_debug_error',
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

    return VibePageAuditReport(
      targetLabel: targetLabel,
      pageId: activePage?.id,
      pageName: activePage?.name,
      pagePath: activePage?.path,
      isScoped: scope != null,
      auditedComponentIds: scopedIds,
      findings: findings,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
  }
}
