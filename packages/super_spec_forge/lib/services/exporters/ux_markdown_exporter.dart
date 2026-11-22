/// Exportateur de la spécification UX complète au format Markdown ([UxMarkdownExporter]).
library;

import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_coherence_issue.dart';
import '../../models/spec_forge_project.dart';
import '../../models/ux/ux_coherence_issue.dart';
import '../../models/ux/ux_journey_spec.dart';
import '../../models/ux/ux_screen_spec.dart';
import '../ux_coherence_analyzer.dart';

/// Génère un document Markdown structuré en français décrivant les parcours,
/// la navigation, les écrans et la matrice de traçabilité Métier↔UX d'un [SpecForgeProject].
abstract final class UxMarkdownExporter {
  /// Exporte le volet UX de [project] au format Markdown complet.
  static String export(SpecForgeProject project) {
    final buf = StringBuffer()
      ..writeln('# Spécification UX & Parcours — ${project.name}')
      ..writeln()
      ..writeln('> Généré par **SuperSpecForge**')
      ..writeln(
        '> Dernière mise à jour : `${project.updatedAt.toIso8601String()}`',
      )
      ..writeln();

    _writeSynthesisAndShell(buf, project);
    _writeJourneys(buf, project);
    _writeInformationArchitecture(buf, project);
    _writeScreenBlueprints(buf, project);
    _writeTraceabilityMatrix(buf, project);

    return buf.toString();
  }

  static void _writeSynthesisAndShell(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final ux = project.uxSpec;
    final nav = ux.navigation;
    final theme = nav.visualTheme;
    final homeRoute = nav.homeRouteId.trim().isNotEmpty
        ? nav.findRoute(nav.homeRouteId)
        : nav.findRoute('/');

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 1. Synthèse & Identité visuelle / Shell')
      ..writeln()
      ..writeln('### 1.1 Vue d’ensemble UX')
      ..writeln()
      ..writeln(
        '- **Étape UX courante** : ${ux.currentStage.title} (`${ux.currentStage.name}`)',
      )
      ..writeln('- **Parcours utilisateurs** : ${ux.journeys.length}')
      ..writeln('- **Routes applicatives** : ${nav.routes.length}')
      ..writeln('- **Schémas directeurs d’écrans** : ${ux.screens.length}')
      ..writeln()
      ..writeln('### 1.2 Coque applicative (Shell)')
      ..writeln()
      ..writeln(
        '- **Pattern de navigation** : ${nav.shellPattern.label} (`${nav.shellPattern.name}`)',
      )
      ..writeln(
        '- **Barre d’application (`ApplicationBar`)** : ${nav.hasAppBar ? 'Activée' : 'Désactivée'}',
      )
      ..writeln(
        '- **Fil d’Ariane contextuel** : ${nav.hasBreadcrumbs ? 'Activé' : 'Désactivé'}',
      )
      ..writeln(
        '- **Recherche globale transversale** : ${nav.hasGlobalSearch ? 'Activée' : 'Désactivée'}',
      )
      ..writeln(
        '- **Route d’accueil** : ${homeRoute != null ? '`${homeRoute.path}` — ${homeRoute.title} (`${homeRoute.id}`)' : (nav.homeRouteId.isEmpty ? '`Non définie`' : '`${nav.homeRouteId}`')}',
      )
      ..writeln()
      ..writeln('### 1.3 Identité visuelle Material 3 (`UxVisualThemeSeed`)')
      ..writeln()
      ..writeln('| Paramètre | Valeur |')
      ..writeln('|---|---|')
      ..writeln(
        '| **Couleur d’accentuation (`accentHex`)** | `${theme.accentHex}` |',
      )
      ..writeln('| **Mode de thème (`themeMode`)** | `${theme.themeMode}` |')
      ..writeln(
        '| **Système de surface (`surfaceSystem`)** | `${theme.surfaceSystem}` |',
      )
      ..writeln(
        '| **Police principale (`fontFamily`)** | `${_esc(theme.fontFamily)}` |',
      )
      ..writeln(
        '| **Profil de densité (`density`)** | ${_esc(theme.density.label)} (`${theme.density.name}`) |',
      )
      ..writeln(
        '| **Rayon des cartes (`cardRadius`)** | `${_formatNum(theme.cardRadius)} px` |',
      )
      ..writeln();

    if (theme.uxVoiceGuidelines.trim().isNotEmpty) {
      buf
        ..writeln('#### Ton éditorial & Accessibilité UX')
        ..writeln()
        ..writeln(theme.uxVoiceGuidelines.trim())
        ..writeln();
    }
  }

  static void _writeJourneys(StringBuffer buf, SpecForgeProject project) {
    final journeys = project.uxSpec.journeys;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 2. Parcours utilisateurs & Flows')
      ..writeln();

    if (journeys.isEmpty) {
      buf
        ..writeln('_Aucun parcours utilisateur modélisé._')
        ..writeln();
      return;
    }

    for (final journey in journeys) {
      final persona = _findPersonaLabel(project, journey.personaId);
      final codePrefix = journey.code.trim().isNotEmpty
          ? '${journey.code} — '
          : '';
      buf.writeln('### $codePrefix${journey.name} (`${journey.id}`)');
      if (persona.isNotEmpty) {
        buf.writeln('- **Persona principal** : $persona');
      }
      buf.writeln(
        '- **Canal cible** : ${journey.channel.label} (`${journey.channel.name}`)',
      );
      if (journey.trigger.isNotEmpty) {
        buf.writeln('- **Déclencheur** : ${journey.trigger}');
      }
      if (journey.goal.isNotEmpty) {
        buf.writeln('- **Objectif visé** : ${journey.goal}');
      }
      if (journey.useCaseIds.isNotEmpty) {
        buf.writeln(
          '- **Cas d’usage couverts** : ${journey.useCaseIds.map((id) => '`$id`').join(', ')}',
        );
      }
      if (journey.requirementIds.isNotEmpty) {
        buf.writeln(
          '- **Exigences fonctionnelles liées** : ${journey.requirementIds.map((id) => '`$id`').join(', ')}',
        );
      }
      buf.writeln();

      if (journey.steps.isNotEmpty) {
        final orderedSteps = List<UxJourneyStep>.from(journey.steps)
          ..sort((a, b) => a.order.compareTo(b.order));
        buf
          ..writeln('#### Étapes du parcours')
          ..writeln()
          ..writeln(
            '| # | Étape | Action utilisateur | Réponse système | Route cible | Embranchement / Irritant résolu |',
          )
          ..writeln('|---|---|---|---|---|---|');
        for (final step in orderedSteps) {
          final routeNode = step.targetRouteId.isEmpty
              ? null
              : project.uxSpec.navigation.findRoute(step.targetRouteId);
          final routeCell = step.targetRouteId.isEmpty
              ? '—'
              : (routeNode != null
                    ? '`${routeNode.path}` (`${routeNode.id}`)'
                    : '`${step.targetRouteId}`');
          final notes = <String>[
            if (step.branchCondition.isNotEmpty)
              'Condition : ${step.branchCondition}',
            if (step.painPointResolved.isNotEmpty)
              'Irritant résolu : ${step.painPointResolved}',
          ].join('<br>');
          buf.writeln(
            '| ${step.order} | **${_esc(step.title)}** | ${_esc(step.actorAction.isEmpty ? '—' : step.actorAction)} | ${_esc(step.systemResponse.isEmpty ? '—' : step.systemResponse)} | ${_esc(routeCell)} | ${_esc(notes.isEmpty ? '—' : notes)} |',
          );
        }
        buf.writeln();
      }

      if (journey.successCriteria.isNotEmpty) {
        buf.writeln('#### Critères de succès UX');
        for (final criterion in journey.successCriteria) {
          buf.writeln('- $criterion');
        }
        buf.writeln();
      }
    }
  }

  static void _writeInformationArchitecture(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final nav = project.uxSpec.navigation;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln(
        '## 3. Architecture de l’information & Arborescence des routes',
      )
      ..writeln();

    if (nav.routes.isEmpty) {
      buf
        ..writeln('_Aucune route applicative définie._')
        ..writeln();
      return;
    }

    buf
      ..writeln(
        '| ID | Chemin | Titre | Type de page | Nav. primaire | Module | Parent | Personas & Habilitations |',
      )
      ..writeln('|---|---|---|---|---|---|---|---|');
    for (final route in nav.routes) {
      final accessParts = <String>[
        if (route.allowedPersonaIds.isNotEmpty)
          'Personas : ${route.allowedPersonaIds.map((p) => '`$p`').join(', ')}',
        if (route.permissionRuleIds.isNotEmpty)
          'RG : ${route.permissionRuleIds.map((r) => '`$r`').join(', ')}',
      ];
      final accessCell = accessParts.isEmpty
          ? 'Tous'
          : accessParts.join('<br>');
      buf.writeln(
        '| `${_esc(route.id)}` | `${_esc(route.path)}` | **${_esc(route.title)}** | `${route.pageType.name}` (${_esc(route.pageType.label)}) | ${route.showInPrimaryNav ? 'Oui' : 'Non'} | ${_esc(route.moduleId.isEmpty ? '—' : '`${route.moduleId}`')} | ${_esc(route.parentRouteId.isEmpty ? '—' : '`${route.parentRouteId}`')} | ${_esc(accessCell)} |',
      );
    }
    buf.writeln();

    if (nav.routes.length > 1) {
      buf
        ..writeln('```mermaid')
        ..writeln('flowchart LR');
      for (final route in nav.routes) {
        final safeId = _mermaidId(route.id);
        final label = '${route.title} (${route.path})'.replaceAll('"', "'");
        buf.writeln('  $safeId["$label"]');
      }
      for (final route in nav.routes) {
        if (route.parentRouteId.isEmpty) continue;
        final parent = nav.findRoute(route.parentRouteId);
        if (parent != null && parent.id != route.id) {
          buf.writeln('  ${_mermaidId(parent.id)} --> ${_mermaidId(route.id)}');
        }
      }
      buf
        ..writeln('```')
        ..writeln();
    }
  }

  static void _writeScreenBlueprints(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final screens = project.uxSpec.screens;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 4. Fiches d’écrans, Zones & Interactions')
      ..writeln();

    if (screens.isEmpty) {
      buf
        ..writeln('_Aucun schéma directeur d’écran formalisé._')
        ..writeln();
      return;
    }

    for (final screen in screens) {
      final codePrefix = screen.code.trim().isNotEmpty
          ? '${screen.code} — '
          : '';
      final route = screen.routeId.isEmpty
          ? null
          : project.uxSpec.navigation.findRoute(screen.routeId);
      final primaryObj = screen.primaryObjectId.isEmpty
          ? null
          : project.findBusinessObject(screen.primaryObjectId);

      buf.writeln('### $codePrefix${screen.name} (`${screen.id}`)');
      if (route != null) {
        buf.writeln(
          '- **Route associée** : `${route.path}` — ${route.title} (`${route.id}`)',
        );
      } else if (screen.routeId.isNotEmpty) {
        buf.writeln('- **Route associée** : `${screen.routeId}`');
      }
      buf.writeln(
        '- **Pattern spatial** : ${screen.pattern.label} (`${screen.pattern.name}`)',
      );
      if (primaryObj != null) {
        buf.writeln(
          '- **Objet métier primaire** : ${primaryObj.name} (`${primaryObj.technicalName}`)',
        );
      } else if (screen.primaryObjectId.isNotEmpty) {
        buf.writeln(
          '- **Objet métier primaire** : `${screen.primaryObjectId}`',
        );
      }
      if (screen.purpose.isNotEmpty) {
        buf.writeln('- **Intention UX** : ${screen.purpose}');
      }
      if (screen.personaIds.isNotEmpty) {
        buf.writeln(
          '- **Personas cibles** : ${screen.personaIds.map((p) => '`$p`').join(', ')}',
        );
      }
      if (screen.useCaseIds.isNotEmpty) {
        buf.writeln(
          '- **Cas d’usage liés** : ${screen.useCaseIds.map((u) => '`$u`').join(', ')}',
        );
      }
      if (screen.requirementIds.isNotEmpty) {
        buf.writeln(
          '- **Exigences fonctionnelles liées** : ${screen.requirementIds.map((r) => '`$r`').join(', ')}',
        );
      }
      buf.writeln();

      if (screen.zones.isNotEmpty) {
        buf
          ..writeln('#### Zones spatiales (`SuperLayout`)')
          ..writeln()
          ..writeln(
            '| Zone | État & Géométrie | Blocs fonctionnels & Liaisons métiers |',
          )
          ..writeln('|---|---|---|');
        for (final zone in _orderedZones(screen.zones)) {
          final geometry = <String>[
            zone.enabled ? 'Active' : 'Désactivée',
            'axe `${zone.axis}`',
            if (zone.sizePx != null) '${_formatNum(zone.sizePx!)} px',
            if (zone.scrollable) 'défilante',
          ].join(', ');
          final slotsSummary = zone.slots.isEmpty
              ? '_Aucun bloc_'
              : [
                  for (final slot in zone.slots) _formatSlotSummary(project, slot),
                ].join('<br>');
          buf.writeln(
            '| **${zone.zone.label}** (`${zone.zone.name}`) | ${_esc(geometry)} | ${_esc(slotsSummary)} |',
          );
        }
        buf.writeln();
      }

      if (screen.actions.isNotEmpty) {
        buf
          ..writeln('#### Actions & Règles de gestion (`RG-xxx`)')
          ..writeln()
          ..writeln(
            '| Action | Hiérarchie | Règles métier (`RG`) | Route cible | Confirmation |',
          )
          ..writeln('|---|---|---|---|---|');
        for (final action in screen.actions) {
          final rulesCell = action.businessRuleIds.isEmpty
              ? '—'
              : action.businessRuleIds.map((r) => '`$r`').join(', ');
          final targetRoute = action.targetRouteId.isEmpty
              ? null
              : project.uxSpec.navigation.findRoute(action.targetRouteId);
          final targetCell = action.targetRouteId.isEmpty
              ? '—'
              : (targetRoute != null
                    ? '`${targetRoute.path}` (`${targetRoute.id}`)'
                    : '`${action.targetRouteId}`');
          buf.writeln(
            '| **${_esc(action.label)}** (`${_esc(action.id)}`) | ${action.hierarchy.label} (`${action.hierarchy.name}`) | ${_esc(rulesCell)} | ${_esc(targetCell)} | ${_esc(action.confirmationMessage.isEmpty ? '—' : action.confirmationMessage)} |',
          );
        }
        buf.writeln();
      }

      final st = screen.states;
      buf
        ..writeln('#### États UX (Vide / Chargement / Erreur / Lecture seule)')
        ..writeln(
          '- **État vide** : ${st.emptyStateTitle.isEmpty ? '—' : st.emptyStateTitle}${st.emptyStateCta.isEmpty ? '' : ' _(CTA : « ${st.emptyStateCta} »)_'}',
        )
        ..writeln(
          '- **Chargement** : `${st.loadingPattern.isEmpty ? 'skeleton' : st.loadingPattern}`',
        )
        ..writeln(
          '- **Gestion des erreurs** : ${st.errorHandling.isEmpty ? '—' : st.errorHandling}',
        )
        ..writeln(
          '- **Règles de lecture seule** : ${st.readOnlyRuleIds.isEmpty ? '—' : st.readOnlyRuleIds.map((r) => '`$r`').join(', ')}',
        )
        ..writeln();
    }
  }

  static void _writeTraceabilityMatrix(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final ux = project.uxSpec;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 5. Matrice de traçabilité Métier ↔ UX')
      ..writeln();

    // 5.1 Personas
    buf.writeln('### 5.1 Personas ↔ Parcours & Écrans');
    if (project.vision.personas.isEmpty) {
      buf
        ..writeln('_Aucun persona métier défini._')
        ..writeln();
    } else {
      buf
        ..writeln('| Persona | Parcours (`JRN`) | Routes autorisées | Écrans (`SCR`) |')
        ..writeln('|---|---|---|---|');
      for (final p in project.vision.personas) {
        final pKey = p.id.toLowerCase();
        final pName = p.name.toLowerCase();
        final jrns = [
          for (final j in ux.journeys)
            if (j.personaId.toLowerCase() == pKey ||
                j.personaId.toLowerCase() == pName)
              '`${j.code.isEmpty ? j.id : j.code}`',
        ];
        final routes = [
          for (final r in ux.navigation.routes)
            if (r.allowedPersonaIds.isEmpty ||
                r.allowedPersonaIds.any(
                  (id) => id.toLowerCase() == pKey || id.toLowerCase() == pName,
                ))
              '`${r.path}`',
        ];
        final scrs = [
          for (final s in ux.screens)
            if (s.personaIds.any(
              (id) => id.toLowerCase() == pKey || id.toLowerCase() == pName,
            ))
              '`${s.code.isEmpty ? s.id : s.code}`',
        ];
        buf.writeln(
          '| **${_esc(p.name)}** (`${_esc(p.id)}`) | ${jrns.isEmpty ? '—' : jrns.join(', ')} | ${routes.isEmpty ? '—' : routes.join(', ')} | ${scrs.isEmpty ? '—' : scrs.join(', ')} |',
        );
      }
      buf.writeln();
    }

    // 5.2 Cas d'usage & Exigences fonctionnelles
    buf.writeln(
      '### 5.2 Cas d’usage & Exigences fonctionnelles ↔ Parcours & Écrans',
    );
    final reqs = project.cahierDesCharges.functionalRequirements;
    final ucs = project.cahierDesCharges.useCases;
    if (reqs.isEmpty && ucs.isEmpty) {
      buf
        ..writeln('_Aucun cas d’usage ni exigence fonctionnelle défini._')
        ..writeln();
    } else {
      buf
        ..writeln('| Élément métier | Priorité / Type | Parcours (`JRN`) | Écrans (`SCR`) |')
        ..writeln('|---|---|---|---|');
      for (final uc in ucs) {
        final ucKey = uc.id.toLowerCase();
        final jrns = [
          for (final j in ux.journeys)
            if (j.useCaseIds.any((id) => id.toLowerCase() == ucKey))
              '`${j.code.isEmpty ? j.id : j.code}`',
        ];
        final scrs = [
          for (final s in ux.screens)
            if (s.useCaseIds.any((id) => id.toLowerCase() == ucKey))
              '`${s.code.isEmpty ? s.id : s.code}`',
        ];
        buf.writeln(
          '| **${_esc(uc.title)}** (`${_esc(uc.id)}`) | Cas d’usage | ${jrns.isEmpty ? '—' : jrns.join(', ')} | ${scrs.isEmpty ? '—' : scrs.join(', ')} |',
        );
      }
      for (final req in reqs) {
        final reqKeys = <String>{
          req.id.toLowerCase(),
          if (req.code.isNotEmpty) req.code.toLowerCase(),
        };
        final jrns = [
          for (final j in ux.journeys)
            if (j.requirementIds.any((id) => reqKeys.contains(id.toLowerCase())))
              '`${j.code.isEmpty ? j.id : j.code}`',
        ];
        final scrs = [
          for (final s in ux.screens)
            if (s.requirementIds.any((id) => reqKeys.contains(id.toLowerCase())))
              '`${s.code.isEmpty ? s.id : s.code}`',
        ];
        buf.writeln(
          '| `${_esc(req.code)}` — ${_esc(req.title)} | ${_formatPriority(req.priority)} | ${jrns.isEmpty ? '—' : jrns.join(', ')} | ${scrs.isEmpty ? '—' : scrs.join(', ')} |',
        );
      }
      buf.writeln();
    }

    // 5.3 Objets métiers
    buf.writeln('### 5.3 Objets métiers ↔ Écrans & Blocs UX');
    if (project.businessObjects.isEmpty) {
      buf
        ..writeln('_Aucun objet métier modélisé._')
        ..writeln();
    } else {
      buf
        ..writeln('| Objet métier | Rôle | Écrans primaires (`SCR`) | Blocs de zones liés |')
        ..writeln('|---|---|---|---|');
      for (final obj in project.businessObjects) {
        final keys = <String>{
          obj.id.toLowerCase(),
          obj.technicalName.toLowerCase(),
          obj.name.toLowerCase(),
        };
        final primaryScrs = <String>[];
        final slotRefs = <String>[];
        for (final s in ux.screens) {
          final scrCode = s.code.isEmpty ? s.id : s.code;
          if (s.primaryObjectId.isNotEmpty &&
              keys.contains(s.primaryObjectId.toLowerCase())) {
            primaryScrs.add('`$scrCode`');
          }
          for (final z in s.zones) {
            for (final slot in z.slots) {
              if (slot.businessObjectId.isNotEmpty &&
                  keys.contains(slot.businessObjectId.toLowerCase())) {
                slotRefs.add('`$scrCode.${z.zone.name}:${slot.title}`');
              }
            }
          }
        }
        buf.writeln(
          '| **${_esc(obj.name)}** (`${_esc(obj.technicalName)}`) | ${obj.aggregateRoot ? 'Agrégat racine' : 'Entité / Sous-objet'} | ${primaryScrs.isEmpty ? '—' : primaryScrs.join(', ')} | ${_esc(slotRefs.isEmpty ? '—' : slotRefs.join(', '))} |',
        );
      }
      buf.writeln();
    }

    // 5.4 Règles de gestion
    buf.writeln('### 5.4 Règles de gestion (`RG-xxx`) ↔ Routes, Actions & États');
    if (project.businessRules.isEmpty) {
      buf
        ..writeln('_Aucune règle de gestion formalisée._')
        ..writeln();
    } else {
      buf
        ..writeln('| Règle | Catégorie | Routes (Habilitations) | Actions & États d’écrans |')
        ..writeln('|---|---|---|---|');
      for (final rule in project.businessRules) {
        final keys = <String>{
          rule.id.toLowerCase(),
          if (rule.code.isNotEmpty) rule.code.toLowerCase(),
        };
        final routeHits = [
          for (final r in ux.navigation.routes)
            if (r.permissionRuleIds.any((id) => keys.contains(id.toLowerCase())))
              '`${r.path}`',
        ];
        final screenHits = <String>[];
        for (final s in ux.screens) {
          final scrCode = s.code.isEmpty ? s.id : s.code;
          for (final a in s.actions) {
            if (a.businessRuleIds.any((id) => keys.contains(id.toLowerCase()))) {
              screenHits.add('`$scrCode` (${a.label})');
            }
          }
          if (s.states.readOnlyRuleIds.any(
            (id) => keys.contains(id.toLowerCase()),
          )) {
            screenHits.add('`$scrCode` (lecture seule)');
          }
        }
        buf.writeln(
          '| `${_esc(rule.code)}` — ${_esc(rule.title)} | ${rule.category.label} | ${routeHits.isEmpty ? '—' : routeHits.join(', ')} | ${_esc(screenHits.isEmpty ? '—' : screenHits.join(', '))} |',
        );
      }
      buf.writeln();
    }

    // 5.5 Rapport de cohérence UX
    final localIssues = UxCoherenceAnalyzer.analyze(project);
    final aiIssues = ux.coherenceIssues.where((i) => i.source == 'ai');
    final allIssues = <UxCoherenceIssue>[...localIssues, ...aiIssues];
    if (allIssues.isNotEmpty) {
      buf
        ..writeln('### 5.5 Points de vigilance & Cohérence Métier ↔ UX')
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

  static List<UxScreenZoneSpec> _orderedZones(List<UxScreenZoneSpec> source) {
    const order = <UxLayoutZoneName>[
      UxLayoutZoneName.north,
      UxLayoutZoneName.west,
      UxLayoutZoneName.center,
      UxLayoutZoneName.east,
      UxLayoutZoneName.south,
    ];
    final sorted = List<UxScreenZoneSpec>.from(source)
      ..sort(
        (a, b) => order.indexOf(a.zone).compareTo(order.indexOf(b.zone)),
      );
    return sorted;
  }

  static String _formatSlotSummary(
    SpecForgeProject project,
    UxZoneWidgetSlot slot,
  ) {
    final obj = slot.businessObjectId.isEmpty
        ? null
        : project.findBusinessObject(slot.businessObjectId);
    final objLabel = obj != null
        ? ' → `${obj.technicalName}`'
        : (slot.businessObjectId.isNotEmpty
              ? ' → `${slot.businessObjectId}`'
              : '');
    final attrsLabel = slot.attributeNames.isEmpty
        ? ''
        : ' (${slot.attributeNames.map((a) => '`$a`').join(', ')})';
    final summaryLabel = slot.summary.isEmpty ? '' : ' — ${slot.summary}';
    return '**${slot.title}** _[${slot.kind.label}]_$objLabel$attrsLabel$summaryLabel';
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

  static String _formatPriority(RequirementPriority priority) =>
      '${priority.code} (${priority.label})';

  static String _formatNum(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  static String _mermaidId(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    if (cleaned.isEmpty) return 'node';
    return RegExp(r'^[0-9]').hasMatch(cleaned) ? 'r_$cleaned' : cleaned;
  }

  static String _esc(String value) =>
      value.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}
