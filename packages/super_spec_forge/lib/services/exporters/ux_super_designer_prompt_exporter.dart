/// Générateur de prompt structuré prêt à l'emploi pour le Vibe Chat de `SuperDesigner` ([UxSuperDesignerPromptExporter]).
library;

import '../../models/business_object_spec.dart';
import '../../models/business_rule_spec.dart';
import '../../models/spec_forge_project.dart';
import '../../models/ux/ux_navigation_spec.dart';
import '../../models/ux/ux_screen_spec.dart';
import 'spec_super_designer_exporter.dart';

/// Assemble un prompt complet en français destiné au Chat IA de `SuperDesigner`
/// (`super_container_layout`) afin de construire ou finaliser l'application
/// à partir des spécifications métier, des repositories JSON et du volet UX.
abstract final class UxSuperDesignerPromptExporter {
  /// Génère le texte Markdown du prompt pour [project].
  static String export(SpecForgeProject project) {
    final nav = project.uxSpec.navigation;
    final theme = nav.visualTheme;
    final buf = StringBuffer()
      ..writeln('# Prompt Vibe Chat SuperDesigner — ${project.name}')
      ..writeln()
      ..writeln(
        'Construis et finalise l’application complète **« ${project.name} »** dans `SuperDesigner` (`super_container_layout`) en respectant strictement l’architecture de navigation, les repositories JSON, les schémas, les fiches d’écrans UX et les règles de gestion détaillés ci-dessous.',
      )
      ..writeln()
      ..writeln('## Consignes d’exécution pour Vibe IA')
      ..writeln(
        '- Si le **Mode « Plan »** est actif, découpe la réalisation en lots calibrés et parallélisables (Lot 1 `"lot-1"` : Thème, Shell, Repositories initiaux & déclaration dans `"pageCatalog"` de toutes les routes secondaires ; Lots suivants : 1 à 2 écrans max par lot avec `"dependsOn": ["lot-1"]` pour exécution parallèle ; Dernier lot éventuel : valeurs réactives `@...` transverses et finitions).',
      )
      ..writeln(
        '- Sélectionne directement les icônes dans le catalogue `MaterialIconCatalog` fourni dans le guide sans appeler `validate_or_list_icons`, et émets un JSON compact sur une seule ligne.',
      )
      ..writeln(
        '- Réutilise **exactement** les identifiants de repositories (`<repoAlias>`), les clés de collections (`<collectionKey>`) et les noms d’attributs listés dans la section **Repositories & Liaisons** — n’invente aucun nom de champ absent du schéma.',
      )
      ..writeln(
        '- Respecte les règles géométriques Desktop de `super_container_layout` : couleurs sémantiques `"theme:*"` (graine `accent` = `${UxVisualThemeSeed.normalizeAccentHex(theme.accentHex)}`), aucun `padding` sur `styles["background"]`, jamais `"west"`/`"east"` dans `autoSides` lorsqu’ils contiennent une liste ou un arbre, `autoSides: []` sur tout layout ayant une zone `scrollable: true`, et atomicité `1 attribut métier = 1 SuperValue` (`label` + `binding`).',
      )
      ..writeln(
        '- Dans un pattern Maître / Détail, qualifie explicitement le repository dans la branche sœur de détail (`<repoAlias>.<collectionKey>[?].<attribut>`).',
      )
      ..writeln();

    _writeContextAndLexicon(buf, project);
    _writeVisualAndShellSection(buf, nav);
    _writeRepositoriesSection(buf, project);
    _writeRoutesSection(buf, project);
    _writeScreensSection(buf, project);
    _writeRulesSection(buf, project);
    _writeJourneysSection(buf, project);

    return '${buf.toString().trimRight()}\n';
  }

  static void _writeContextAndLexicon(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf.writeln('## 1. Contexte Produit, Personas & Terminologie Métier');
    if (project.vision.ideaSummary.trim().isNotEmpty) {
      buf.writeln(
        '- **Idée / Périmètre** : ${project.vision.ideaSummary.trim()}',
      );
    } else {
      buf.writeln('- **Idée / Périmètre** : ${project.initialIdea.trim()}');
    }
    if (project.vision.valueProposition.trim().isNotEmpty) {
      buf.writeln(
        '- **Proposition de valeur** : ${project.vision.valueProposition.trim()}',
      );
    }
    if (project.vision.personas.isNotEmpty) {
      buf.writeln('- **Personas cibles** :');
      for (final p in project.vision.personas) {
        final roleSuffix = p.role.trim().isNotEmpty
            ? ' — ${p.role.trim()}'
            : '';
        buf.writeln('  - `${p.id}` **${p.name}**$roleSuffix');
      }
    }
    if (project.lexicon.terms.isNotEmpty) {
      buf.writeln(
        '- **Terminologie canonique obligatoire (à utiliser dans tous les titres, labels et boutons)** :',
      );
      for (final t in project.lexicon.terms) {
        final syn = t.synonyms.isNotEmpty
            ? ' *(remplace : ${t.synonyms.join(', ')})*'
            : '';
        final def = t.definition.trim().isNotEmpty
            ? ' : ${t.definition.trim()}'
            : '';
        buf.writeln('  - **${t.term}**$syn$def');
      }
    }
    buf.writeln();
  }

  static void _writeVisualAndShellSection(
    StringBuffer buf,
    UxNavigationSpec nav,
  ) {
    final theme = nav.visualTheme;
    buf
      ..writeln('## 2. Identité Visuelle & Shell Applicatif')
      ..writeln(
        '- **Système de surface** : `${theme.surfaceSystem}` · **Mode** : `${theme.themeMode}` · **Graine d’accent (`accent`)** : `${UxVisualThemeSeed.normalizeAccentHex(theme.accentHex)}`',
      )
      ..writeln(
        '- **Police principale (`fontFamily`)** : `${theme.fontFamily}` · **Densité** : ${theme.density.label} · **Rayon des cartes (`cardRadius`)** : `${theme.cardRadius.toStringAsFixed(0)}px`',
      )
      ..writeln(
        '- **Shell de navigation** : `${nav.shellPattern.name}` (${nav.shellPattern.label}) · AppBar : `${nav.hasAppBar}` · Fil d’Ariane : `${nav.hasBreadcrumbs}` · Recherche globale : `${nav.hasGlobalSearch}`',
      );
    if (theme.uxVoiceGuidelines.trim().isNotEmpty) {
      buf.writeln(
        '- **Ton & Microcopie UX** : ${theme.uxVoiceGuidelines.trim()}',
      );
    }
    buf.writeln();
  }

  static void _writeRepositoriesSection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf.writeln('## 3. Repositories JSON, Schémas & Chemins de Liaison');
    if (project.businessObjects.isEmpty) {
      buf
        ..writeln(
          '_Aucun objet métier défini ; crée les repositories JSON nécessaires selon les écrans._',
        )
        ..writeln();
      return;
    }
    buf.writeln(
      'Les repositories suivants sont pré-enregistrés avec leur JSON Schema Draft 2020-12 et leurs données de démarrage :',
    );
    buf.writeln();
    for (final obj in project.businessObjects) {
      final alias = SpecSuperDesignerExporter.repoAliasFor(obj);
      final collection = SpecSuperDesignerExporter.collectionKeyFor(alias);
      buf.writeln(
        '### Repository `$alias` — ${obj.name} (`${obj.technicalName}`)',
      );
      if (obj.description.trim().isNotEmpty) {
        buf.writeln('- **Description** : ${obj.description.trim()}');
      }
      buf
        ..writeln(
          '- **Liaison de collection (ListView / Table / Chart)** : `$alias.$collection`',
        )
        ..writeln(
          '- **Liaison Maître / Détail (hors liste)** : `$alias.$collection[?].<attribut>`',
        );
      if (obj.lifecycleStates.isNotEmpty) {
        final states = obj.lifecycleStates
            .map(
              (s) =>
                  '`${s.name}` (${s.effectiveLabel}${s.isInitial ? ', initial' : ''}${s.isTerminal ? ', final' : ''})',
            )
            .join(', ');
        buf.writeln('- **Cycle de vie** : $states');
      }
      if (obj.attributes.isNotEmpty) {
        buf.writeln('- **Attributs disponibles** :');
        for (final attr in obj.attributes) {
          _writeAttributeBullet(buf, project, attr, indent: '  ');
        }
      }
      if (obj.relations.isNotEmpty) {
        final rels = obj.relations
            .map((r) {
              final target = project.findBusinessObject(r.targetObjectId);
              final targetAlias = target != null
                  ? SpecSuperDesignerExporter.repoAliasFor(target)
                  : r.targetObjectId;
              return '`${r.name}` (${r.cardinality.symbol} → `$targetAlias`)';
            })
            .join(', ');
        buf.writeln('- **Relations** : $rels');
      }
      buf.writeln();
    }
  }

  static void _writeAttributeBullet(
    StringBuffer buf,
    SpecForgeProject project,
    BusinessAttribute attr, {
    required String indent,
  }) {
    final extras = <String>[
      if (attr.isArray) 'tableau[]' else attr.type.dslKeyword,
      if (attr.required) 'requis' else 'optionnel',
      if (attr.type == BusinessAttributeType.enumeration &&
          attr.enumValues.isNotEmpty)
        'valeurs: [${attr.enumValues.join(', ')}]',
      if (attr.type == BusinessAttributeType.reference &&
          attr.referenceObjectId.isNotEmpty)
        'réf → `${_resolveRepoAliasOrId(project, attr.referenceObjectId)}`',
      if (attr.schemaConstraints.xMask != null &&
          attr.schemaConstraints.xMask!.trim().isNotEmpty)
        'masque: `${attr.schemaConstraints.xMask}`',
      if (attr.schemaConstraints.xSearchable == true) 'filtrable/searchable',
      if (attr.schemaConstraints.readOnly == true) 'lecture seule',
    ];
    final desc = attr.description.trim().isNotEmpty
        ? ' — ${attr.description.trim()}'
        : '';
    buf.writeln('$indent- `${attr.name}` (${extras.join(', ')})$desc');
    for (final child in attr.children) {
      _writeAttributeBullet(buf, project, child, indent: '$indent  ');
    }
  }

  static void _writeRoutesSection(StringBuffer buf, SpecForgeProject project) {
    final nav = project.uxSpec.navigation;
    buf.writeln('## 4. Catalogue des Pages & Routes (`pageCatalog`)');
    if (nav.routes.isEmpty) {
      buf
        ..writeln(
          '_Aucune route explicite définie ; utilise `/` comme accueil._',
        )
        ..writeln();
      return;
    }
    for (final route in nav.routes) {
      final isHome =
          route.id == nav.homeRouteId ||
          (nav.homeRouteId.isEmpty && route.path == '/');
      final navFlag = route.showInPrimaryNav ? 'menu principal' : 'hors menu';
      final personas = route.allowedPersonaIds.isNotEmpty
          ? ' · personas: ${route.allowedPersonaIds.join(', ')}'
          : '';
      buf.writeln(
        '- **`${route.path}`** — **${route.title}** (`id`: `${route.id}`, type: `${route.pageType.name}`, $navFlag${isHome ? ', **ACCUEIL**' : ''}$personas)',
      );
    }
    buf.writeln();
  }

  static void _writeScreensSection(StringBuffer buf, SpecForgeProject project) {
    buf.writeln('## 5. Spécification Détaillée des Écrans (`SCR-xxx`)');
    if (project.uxSpec.screens.isEmpty) {
      buf
        ..writeln('_Aucune fiche d’écran détaillée._')
        ..writeln();
      return;
    }

    for (final screen in project.uxSpec.screens) {
      final route = project.uxSpec.navigation.findRoute(screen.routeId);
      final routeLabel = route != null
          ? '`${route.path}` (`${route.id}` — ${route.pageType.label})'
          : (screen.routeId.isNotEmpty ? '`${screen.routeId}`' : '`/`');
      final primaryObj = screen.primaryObjectId.isNotEmpty
          ? project.findBusinessObject(screen.primaryObjectId)
          : null;
      final primaryRepoInfo = primaryObj != null
          ? () {
              final alias = SpecSuperDesignerExporter.repoAliasFor(primaryObj);
              final col = SpecSuperDesignerExporter.collectionKeyFor(alias);
              return '`$alias.$col` (${primaryObj.name})';
            }()
          : (screen.primaryObjectId.isNotEmpty
                ? '`${screen.primaryObjectId}`'
                : 'aucun');

      buf
        ..writeln(
          '### ${screen.code.isNotEmpty ? '${screen.code} — ' : ''}${screen.name}',
        )
        ..writeln(
          '- **Route** : $routeLabel · **Pattern spatial** : `${screen.pattern.name}` (${screen.pattern.label}) · **Repository principal** : $primaryRepoInfo',
        );
      if (screen.purpose.trim().isNotEmpty) {
        buf.writeln('- **Objectif UX** : ${screen.purpose.trim()}');
      }

      final enabledZones = screen.zones.where((z) => z.enabled).toList();
      if (enabledZones.isNotEmpty) {
        buf.writeln('- **Découpage par zones (`SuperLayout`)** :');
        for (final z in enabledZones) {
          final sizeInfo = z.sizePx != null
              ? ', taille: `${z.sizePx!.toStringAsFixed(0)}px`'
              : '';
          final scrollInfo = z.scrollable ? ', `scrollable: true`' : '';
          buf.writeln(
            '  - **Zone `${z.zone.name}`** (`axis: "${z.axis}"`$sizeInfo$scrollInfo) :',
          );
          if (z.slots.isEmpty) {
            buf.writeln(
              '    - Conteneur adapté au pattern `${screen.pattern.name}`.',
            );
          } else {
            for (final slot in z.slots) {
              _writeSlotBullet(buf, project, screen, slot);
            }
          }
        }
      }

      if (screen.actions.isNotEmpty) {
        buf.writeln('- **Actions & Boutons (`SuperAction`)** :');
        for (final action in screen.actions) {
          final targetRoute = action.targetRouteId.isNotEmpty
              ? project.uxSpec.navigation.findRoute(action.targetRouteId)
              : null;
          final navSuffix = targetRoute != null
              ? ' → navigue vers `${targetRoute.path}` (`${targetRoute.id}`)'
              : (action.targetRouteId.isNotEmpty
                    ? ' → cible `${action.targetRouteId}`'
                    : '');
          final rgSuffix = action.businessRuleIds.isNotEmpty
              ? ' · règles: ${action.businessRuleIds.join(', ')}'
              : '';
          final confirmSuffix = action.confirmationMessage.trim().isNotEmpty
              ? ' · confirmation: « ${action.confirmationMessage.trim()} »'
              : '';
          buf.writeln(
            '  - **[${action.hierarchy.label}] « ${action.label} »** (`${action.id}`)$navSuffix$rgSuffix$confirmSuffix',
          );
        }
      }

      if (screen.states.hasContent) {
        final s = screen.states;
        final parts = <String>[
          if (s.emptyStateTitle.trim().isNotEmpty)
            'état vide: « ${s.emptyStateTitle.trim()} »${s.emptyStateCta.trim().isNotEmpty ? ' (CTA: « ${s.emptyStateCta.trim()} »)' : ''}',
          if (s.loadingPattern.trim().isNotEmpty)
            'chargement: `${s.loadingPattern.trim()}`',
          if (s.errorHandling.trim().isNotEmpty)
            'erreurs: ${s.errorHandling.trim()}',
          if (s.readOnlyRuleIds.isNotEmpty)
            'lecture seule selon: ${s.readOnlyRuleIds.join(', ')}',
        ];
        if (parts.isNotEmpty) {
          buf.writeln('- **États UX** : ${parts.join(' · ')}');
        }
      }
      buf.writeln();
    }
  }

  static void _writeSlotBullet(
    StringBuffer buf,
    SpecForgeProject project,
    UxScreenSpec screen,
    UxZoneWidgetSlot slot,
  ) {
    final rawObjId = slot.businessObjectId.isNotEmpty
        ? slot.businessObjectId
        : screen.primaryObjectId;
    final obj = rawObjId.isNotEmpty
        ? project.findBusinessObject(rawObjId)
        : null;
    final bindingInfo = obj != null
        ? () {
            final alias = SpecSuperDesignerExporter.repoAliasFor(obj);
            final col = SpecSuperDesignerExporter.collectionKeyFor(alias);
            return 'repo `$alias.$col`';
          }()
        : (rawObjId.isNotEmpty ? 'objet `$rawObjId`' : '');
    final attrsInfo = slot.attributeNames.isNotEmpty
        ? ' · champs: ${slot.attributeNames.map((a) => '`$a`').join(', ')}'
        : '';
    final summaryInfo = slot.summary.trim().isNotEmpty
        ? ' — ${slot.summary.trim()}'
        : '';
    final meta = [
      slot.kind.label,
      if (bindingInfo.isNotEmpty) bindingInfo,
    ].join(', ');
    buf.writeln('    - **${slot.title}** ($meta)$attrsInfo$summaryInfo');
  }

  static void _writeRulesSection(StringBuffer buf, SpecForgeProject project) {
    final activeRules = project.businessRules.where((r) => r.active).toList();
    if (activeRules.isEmpty) return;

    buf
      ..writeln(
        '## 6. Règles de Gestion (`RG-xxx`) → Calculs Réactifs `@...`, Validateurs & Droits',
      )
      ..writeln(
        'Traduis les règles métier suivantes en `calculatedAttributes` QuickJS (`@...` en `mode: "display"`), validateurs de champs (`mode: "input"`) et comportements d’actions :',
      );
    for (final r in activeRules) {
      final targets = [
        for (final oid in r.targetObjectIds)
          _resolveRepoAliasOrId(project, oid),
      ];
      final targetInfo = targets.isNotEmpty
          ? ' (cible: ${targets.map((t) => '`$t`').join(', ')})'
          : '';
      buf.writeln(
        '- **${r.code} — ${r.title}** [${r.category.label}, priorité ${r.priority.label}]$targetInfo',
      );
      final clauses = <String>[
        if (r.trigger.trim().isNotEmpty) 'Quand: ${r.trigger.trim()}',
        if (r.condition.trim().isNotEmpty) 'Si: ${r.condition.trim()}',
        if (r.effect.trim().isNotEmpty) 'Alors: ${r.effect.trim()}',
        if (r.errorMessage.trim().isNotEmpty)
          'Message d’erreur: « ${r.errorMessage.trim()} »',
      ];
      if (clauses.isNotEmpty) {
        buf.writeln('  - ${clauses.join(' · ')}');
      }
      if (r.category == BusinessRuleCategory.calculation) {
        buf.writeln(
          '  - _Implémentation SuperDesigner_ : déclarer un attribut calculé réactif `@...` dans le repository concerné et l’afficher en lecture seule (`mode: "display"`).',
        );
      }
    }
    buf.writeln();
  }

  static void _writeJourneysSection(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    if (project.uxSpec.journeys.isEmpty) return;
    buf
      ..writeln(
        '## 7. Parcours Utilisateurs (`JRN-xxx`) à Vérifier de Bout en Bout',
      )
      ..writeln(
        'Assure-toi que les enchaînements de navigation (`GoToPageAction` / ouverture de modale ou tiroir / retour) couvrent sans impasse ces parcours :',
      );
    for (final j in project.uxSpec.journeys) {
      final routeFlow = j.steps
          .where((s) => s.targetRouteId.trim().isNotEmpty)
          .map((s) {
            final route = project.uxSpec.navigation.findRoute(s.targetRouteId);
            return route != null ? '`${route.path}`' : '`${s.targetRouteId}`';
          })
          .toList();
      final flowSuffix = routeFlow.isNotEmpty
          ? ' → flux: ${routeFlow.join(' → ')}'
          : '';
      buf.writeln(
        '- **${j.code.isNotEmpty ? '${j.code} — ' : ''}${j.name}** (${j.channel.label})$flowSuffix : ${j.steps.length} étape(s).',
      );
    }
    buf.writeln();
  }

  static String _resolveRepoAliasOrId(SpecForgeProject project, String rawId) {
    final obj = project.findBusinessObject(rawId);
    if (obj == null) return rawId;
    return SpecSuperDesignerExporter.repoAliasFor(obj);
  }
}
