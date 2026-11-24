/// Assemble l'historique et le prompt Vibe à partir de l'état courant.
library;

import 'dart:convert';

import '../../../ai/vibe_chat_attachment.dart';
import '../../../ai/vibe_plan.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/appearance_transfer.dart';
import '../../../services/inspection/vibe_page_audit.dart';
import '../../../theme/appearance.dart';
import '../slots/editor_context_menu.dart';
import 'vibe_chat_message.dart';
import 'vibe_scope_helpers.dart';

/// Construit les entrées de conversation et le contexte envoyé à Vibe.
abstract final class VibePromptBuilder {
  /// Directives strictes communes injectées lorsque le mode « Reproduire à l'identique » est actif.
  static const String reproduceExactCommonDirective = '''
MODE « REPRODUIRE À L’IDENTIQUE » ACTIF (CONSIGNE ESTHÉTIQUE EXPLICITE PRIORITAIRE) :
Reproduis le plus fidèlement possible (pixel-perfect) la page décrite dans la source fournie (fichier Blueprint GenUI .md, HTML/CSS ou capture), sans poser aucune question ("askUser": null obligatoire).

1. DÉROGATION EXPLICITE AU DESIGN SYSTEM GÉNÉRIQUE :
- N’utilise PAS les tokens "theme:*" ni les valeurs par défaut du Design System (rayons 12/16, espacements 4/8px génériques) : applique les valeurs EXACTES mesurées dans la source (.md) :
  - "mode", "accent" et "styles['background'].color" de la Section 1.
  - Toutes les couleurs #RRGGBB / #AARRGGBB exactes (fonds, textes, bordures, ombres, boutons et hover) issues des attributs data-surface, data-text, data-action et des règles CSS (Section 4).
  - Les rayons (radius / radii), bordures (borderWidth / borderWidths / borderColor / borderLine), ombres (shadow), paddingInsets, marginInsets, spacing, fontSize, fontWeight, lineHeight et textAlign exacts.

2. ARCHITECTURE & DÉFILEMENT DE LA PAGE :
- Conserve le slot hôte "scaffold:body" dans "root.placements.body" et configure "components['mainLayout']" (ou le conteneur du scope ciblé).
- Si la page de la source est plus haute que le viewport (ex: page web scrollable), configure le corps pour scroller verticalement sans compresser ni étirer les sections :
  - Utilise soit "root.bodyMode": "singleChildScrollView", soit "mainLayout.zoneFlows.center": { "expandSlots": false, "scrollable": true, "showScrollbar": true, "crossAxisAlignment": "stretch" } avec "autoSides": [] sur tout layout contenant une zone scrollable.
- Si la Section 1 détecte des barres fixes (appBar / north, west, east, south / bottomNavigationBar), place-les dans les zones correspondantes de "root" ou "mainLayout" avec les dimensions exactes (northSize, westSize, eastSize, southSize) et configure les coins (nw, ne, sw, se) en "row" ou "column" (jamais "none" à vide).
- Respecte les conteneurs centrés à largeur bornée du CSS (ex: max-width) via "slotSizeConstraints.<id>.maxWidth" (ex: "1232px") et "crossAxisAlignment": "center" sur leur zone parente.

3. MISE EN PAGE, FLEX & GRILLES (SANS PROPRIÉTÉS INVENTÉES) :
- Traduis chaque data-layout (axis:row / axis:column) via "zoneAxes" et "zoneFlows" ("mainAxisAlignment", "crossAxisAlignment", "spacing", "paddingInsets", "expandSlots": false quand fitContent:true).
- N’invente JAMAIS la propriété "colTracks" ni de CSS brut :
  - Pour des colonnes de largeurs inégales ou fixes (ex: 585px ou 45%/55%), utilise un "layout" en "zoneAxes": { "center": "row" } avec "slotSizeConstraints.<slotId>" ("preferredWidth" en "px" ou "%", "percentBasis": "zone", "fitContent": true/false).
  - Pour une grille multi-colonnes uniforme (ex: mosaïque de logos, cartes produits, footer 4 colonnes), utilise soit "positioning": "grid" avec "grid": { "columns": 12..48, "rowHeight": ..., "gap": ..., "items": { ... } }, soit des lignes "row" imbriquées.
- Lorsque data-ui vaut "iterableContent(card+layout)" ou qu’une surface stylisée contient plusieurs enfants, ou dès qu’un conteneur de zones (`type: "layout"`) doit recevoir une couleur de fond, une bordure, un arrondi ou un `paddingInsets` dans `styles[id]`, utilise `"registry:IterableContent"` dans les `placements` du parent (même ID dans `styles` et dans `components` avec `"type": "layout"`) — ou enveloppe dans `"registry:Card"`. Un `"registry:Layout"` pur est purement structurel et ignore `styles[id]`.

4. IMAGES, LOGOS & SVGs (SECTION 2) — STRICTEMENT FIDÈLES :
- Pour CHAQUE image (img, background-image) ou <svg> listé en Section 2 et visible dans la structure de la page :
  - Copie l’URL EXACTE au caractère près (avec tous ses paramètres ?width=...&format=...&fit=...) ou le code "<svg...>" inline dans "styles[<cardId>].fill.imageUrl". Ne remplace jamais une URL d’image de la Section 2 par une icône Material ou un texte placeholder.
  - Renseigne "fill.imageFit": "contain" pour les logos, icônes SVG et visuels détourés, ou "cover" pour les photos/bannières.
  - Fixe les dimensions exactes [w, h] de la Section 2 dans le "slotSizeConstraints[<cardId>]" de son conteneur parent ("preferredWidth": "<w>px", "preferredHeight": "<h>px", "fitContent": true).
  - Si la carte image n’a pas de composant enfant, laisse "color": "#00000000" (sauf fond explicite dans le .md) et déclare dans "components[<cardId>]" : { "type": "native", "regions": { "child": true }, "placements": {} } (ne mets JAMAIS "child": false).
  - Si des textes/boutons sont superposés sur une image de fond, utilise un "registry:IterableContent" avec "fill.imageUrl" dans "styles[<id>]" et les enfants dans "components[<id>].placements".

5. TEXTES, BOUTONS & RÈGLES GENUI STRICTES :
- Reproduis tous les textes exacts du DOM (Section 3) avec "type": "value" (mode "display" par défaut, "input" pour les champs de saisie), et "type": "action" pour les boutons/liens (variant, backgroundColor, color, radius, horizontalPadding, verticalPadding et states.hover d’après la Section 4 CSS).
- Respecte toutes les contraintes du moteur : JSON strict valide minifié (sans indentation superflue), ordre Top-Down ("styles" puis "components" parent -> enfants), "slotLabels" non vide sur le parent pour chaque nouveau composant, et "usages" uniquement pour les rôles non déductibles ("dynamicData", "staticData", "feedback" ou "translationKey" sur mesure — le moteur déduit automatiquement layout/action/userInput/decoration/explanation).''';

  /// Consigne de planification automatique en lots (Phase 1 du mode « Plan »).
  static const String planModePlanningDirective = '''
PHASE 1 — PLANIFICATION EN LOTS OBLIGATOIRE (MODE « PLAN ») :
- Avant de générer des modifications "vibe" ou "repositories", découpe la demande complète en un plan ordonné de lots cohérents, calibrés et autonomes (exécutables en séquentiel par défaut ou via le bouton « Exécution en parallèle ») :
  - Lot 1 (`"id": "lot-1"`) : Thème global ("mode", "accent", styles principaux), repositories JSON éventuels **avec leur `"jsonSchema"` associé** (et `calculatedAttributes` si besoin) si le besoin manipule des données, architecture globale de navigation par **shell partagé** (dès ≥ 2 pages liées) : déclare le(s) shell(s) dans `"pageCatalog.shells"` (ex. `[{"id": "main-shell", "name": "Navigation principale"}]`), `"rootShellId": "main-shell"` (si la route hôte "/" utilise le même shell), `"components['main-shell']"` avec `"type": "scaffold"` (ou `"superScaffold"`), `appBar`, `sidebarStart` (ex. `NavigationRail` ou menu) et `"body": [{"id": "scaffold:outlet", "type": "scaffold:outlet"}]`, ET déclare dans `"pageCatalog.pages"` TOUTES les routes secondaires prévues avec `"shellId": "main-shell"` (sauf pages autonomes isolées comme `/login` qui conservent `shellId: null`, et rappel : la route "/" existe déjà côté hôte via "root" / "mainLayout" — ne prévois jamais une page "pageCatalog" avec "path": "/") afin que les lots suivants puissent construire chaque route indépendamment.
  - Lots d’écrans (`"lot-2"`, `"lot-3"`, ...) : calibre chaque lot à 1 écran riche ou 2 écrans simples maximum (≤ 45–50 composants par lot) pour éviter les flux JSON géants. Pour chaque page rattachée à un `"shellId"`, écris directement `components[pageId]` en `"type": "layout"` (sans répéter ni AppBar ni menu latéral déjà fournis par le shell) ; n’omets `shellId` que pour une page explicitement autonome (ex. `/login`) ou si l’utilisateur demande explicitement un `Scaffold` dupliqué par page. Pour chaque lot construisant une ou plusieurs routes dédiées déjà déclarées au Lot 1 (sans modifier le shell global), renseigne `"dependsOn": ["lot-1"]` afin de permettre son lancement via « Exécution en parallèle » ! Si un lot dépend d’un autre lot (ex. lot final de finitions/cohérence), renseigne `"dependsOn"` avec les identifiants exacts des lots prérequis.
  - (Si la demande est courte/simple, un plan à 1 seul lot sans `dependsOn` suffit.)
- Si le NIVEAU DE QUESTIONNEMENT autorise "askUser" sur ce tour et que des choix structurants restent ambigus, pose d’abord tes questions via {"message":"...","askUser":{...},"vibe":null} (sans "plan").
- Sinon (ou dès que les réponses sont fournies), renvoie UNIQUEMENT un objet JSON de la forme :
  {"message":"courte présentation du plan en français","plan":{"title":"...","lots":[{"id":"lot-1","title":"...","description":"détail précis des sections, données/repositories et leurs jsonSchema, textes, styles et actions à inclure"},{"id":"lot-2","title":"...","description":"...","dependsOn":["lot-1"]}]},"vibe":null}
- Ne génère PAS encore de patch "vibe" ni "repositories" sur ce tour.''';

  /// Alias historique conservé pour compatibilité ; préférer [planModePlanningDirective].
  static const String reproduceExactPlanningDirective =
      planModePlanningDirective;

  /// Directive stricte injectée lorsque le mode « Uniquement visible » est actif.
  static const String visibleOnlyDirective = '''
MODE « UNIQUEMENT VISIBLE » ACTIF (RESTRICTION STRICTE À L’ONGLET ET AU SCROLL COURANTS) :
L’utilisateur travaille exclusivement sur ce qui est actuellement affiché dans la fenêtre courante (onglet actif et position de défilement actuelle) :
1. VERROUILLAGE ONGLET & SCROLL :
   - Reste strictement sur l’onglet actif et la position de scroll courante : n’appelle JAMAIS `preview_navigation_or_selection` pour changer de route ou d’onglet, et ne fais jamais défiler la vue (`scrollIntoView: false`).
   - Ne crée ni ne modifie aucune autre page (`pageCatalog` inchangé) et ne modifie jamais `initialIndex` ni les zones `content:*` des onglets inactifs d’un `SuperTab`.
2. PÉRIMÈTRE DES AJOUTS, MODIFICATIONS, PLANS & AUDITS :
   - Pour un **ajout** : rattache les nouveaux composants directement dans le conteneur ou la zone d’onglet actuellement visible à la position de scroll courante (à l’endroit cohérent parmi les éléments visibles listés), tout en réémettant INTÉGRALEMENT dans `placements` tous les autres slots existants du conteneur parent (y compris ceux hors scroll) afin de ne rien supprimer hors champ.
   - Pour une **modification, un style, une valeur réactive, un plan ou un audit** : cible uniquement les composants et zones visibles à l’écran ; laisse strictement intacts tous les composants situés dans des onglets masqués ou hors de la fenêtre de scroll actuelle.''';

  /// Directive d'édition des calculs JavaScript réactifs et de leurs champs IHM.
  static const String reactiveValuesDirective = '''
MODE « VALEURS RÉACTIVES » :
Configure les repositories et l’interface afin que les valeurs dérivées restent calculées à partir des données saisies.

1. CALCULS JAVASCRIPT RÉACTIFS (`calculatedAttributes`) :
- Déclare les attributs calculés JS dans le repository concerné, avec la syntaxe QuickJS `(row, ctx, doc)` et le format `calculatedAttributes` documenté dans le Guide IA.
- Par ligne de tableau : utilise `scope: "monTableau[?]"` pour les calculs unitaires (ex. `lignes[?].@totalHt = (row.quantite ?? 0) * (row.prixUnitaire ?? 0)`).
- Par entité parente : utilise le scope de l’entité pour les soldes ou taux dérivés (ex. `enveloppes[?].@disponible = (row.initial ?? 0) - (row.engage ?? 0)`).
- Globaux / racine : déclare sans scope les KPI agrégés du document racine (ex. `@kpisGlobal`, somme des montants du tableau).
- Respecte le format réel des définitions (`name`, `scope`, `code`, `description`) et n’enregistre jamais de clé `@...` ni dans les données `data` ni dans le `jsonSchema` du repository.

2. FRONTIÈRE IHM SAISIE VS CONSULTATION :
- Configure chaque champ de saisie en `mode: "input"` avec un `label` concis, un `placeholder` réaliste et les unités dans `suffix` (ex. `€ HT`, `j`).
- Configure tous les champs calculés en `mode: "display"` (strictement en lecture seule), liés directement à leur chemin calculé `@...`.

3. ERGONOMIE ET ATOMICITÉ :
- Respecte l’atomicité stricte : un attribut métier = un seul `SuperValue`, avec ses propriétés natives `label`, `binding` et `suffix`.
- Ne concatène jamais le libellé et la donnée dans `text`.
- Ne stocke aucun attribut préfixé par `@` dans les données du repository ; les `@calcul` restent en lecture seule.

4. GRAPHIQUES ET VISUALISATION DES VALEURS CALCULÉES :
- N’oublie pas les graphiques pertinents : lorsqu’une évolution, une comparaison ou une répartition aide à comprendre les données, ajoute un `registry:Chart` dans les `placements` et configure son entrée `components[chartId]` avec `"type": "chart"` (`SuperChart`).
- Lie `binding` au tableau JSON source, puis configure `labelPath` et `series[].valuePath` avec des chemins relatifs à chaque ligne. Les chemins calculés sont autorisés, par exemple `labelPath: "mois"` et `series: [{"label": "Total HT", "valuePath": "@totalHt"}]`.
- Garde le joker `[?]` uniquement dans `binding` (ex. `lignes[?].ventes`) ; `labelPath`, `valuePath` et `secondaryValuePath` sont relatifs à la ligne et ne doivent pas contenir `[?]`. Depuis une branche sœur de la liste, indique explicitement le repository dans `binding`.
- Le graphique doit lire les données et calculs réactifs du repository, jamais des valeurs recopiées ou simulées dans `data`. Un KPI calculé scalaire à la racine reste affiché dans un `SuperValue` ; ne le lie pas directement comme tableau au graphique.''';

  /// Conserve la fenêtre récente de conversation et l'erreur précédente utile.
  static String buildConversationHistory(
    List<VibeChatMessage> messages, {
    required String initialGreetingText,
    int maxEntries = 8,
  }) {
    final relevant = <VibeChatMessage>[];
    var seenUser = false;
    for (final message in messages) {
      if (message.isUser) {
        seenUser = true;
        relevant.add(message);
      } else if (seenUser || message.text != initialGreetingText) {
        relevant.add(message);
      }
    }
    if (relevant.length <= maxEntries) {
      return relevant.map((m) => m.toConversationEntry()).join('\n');
    }
    final windowed = relevant.sublist(relevant.length - maxEntries);
    if (relevant.length >= 2) {
      final preceding = relevant[relevant.length - 2];
      if (!preceding.isUser &&
          preceding.failedResponse != null &&
          !windowed.contains(preceding)) {
        windowed.insert(0, preceding);
      }
    }
    return windowed.map((m) => m.toConversationEntry()).join('\n');
  }

  /// Assemble le prompt à partir d'un instantané compact, du contexte optionnel
  /// des repositories JSON ([repositoriesContext]), de la portée choisie ([scope]),
  /// du mode de planification ([planMode]) et du mode de reproduction exacte
  /// ([reproduceExactMode]).
  static String buildTurnPrompt({
    required String questioningDirective,
    required String conversation,
    required Appearance appearance,
    required AppearanceCodec codec,
    required VibeChatScope? scope,
    Iterable<String>? instantiatedComponentIds,
    List<String> mountedSlotSummaries = const <String>[],
    List<String> codedRoutePaths = const <String>[],
    String? repositoriesContext,
    bool planMode = false,
    bool reproduceExactMode = false,
    bool visibleOnlyMode = false,
    String? visibleViewportContext,
  }) {
    final trimmedRepositories = repositoriesContext?.trim() ?? '';
    final repositoriesSection = trimmedRepositories.isEmpty
        ? null
        : (trimmedRepositories.startsWith('REPOSITORIES DISPONIBLES')
              ? trimmedRepositories
              : 'REPOSITORIES DISPONIBLES (JSON) :\n$trimmedRepositories');
    final exactSection = reproduceExactMode
        ? reproduceExactCommonDirective
        : null;
    final planSection = planMode ? planModePlanningDirective : null;
    final visibleOnlySection = visibleOnlyMode ? visibleOnlyDirective : null;
    final trimmedVisibleCtx = visibleViewportContext?.trim() ?? '';
    final visibleCtxSection = visibleOnlyMode && trimmedVisibleCtx.isNotEmpty
        ? trimmedVisibleCtx
        : null;
    final mountedHint = mountedSlotSummaries.isEmpty
        ? null
        : 'Slots montés actuellement à l’écran (utilisables avec get_component_geometry / capture_screenshot) : '
              '${jsonEncode(mountedSlotSummaries)}.';

    if (scope != null) {
      final parentIds = VibeScopeHelpers.parentIdsOfScope(appearance, scope);
      final parentList = parentIds.map((id) => '"$id"').join(', ');
      final targetIdsList = scope.canonicalComponentIds
          .map((id) => '"$id"')
          .join(', ');
      final effectiveParent = parentIds.isNotEmpty ? parentList : targetIdsList;
      final scopeDirective = scope.isMultiTarget
          ? '''RESTRICTION STRICTE DE SCOPE (SÉLECTION LASSO MULTI-CIBLES) :
L'utilisateur a entouré au lasso les éléments suivants :
${scope.allTargets.map((t) => '- "${t.displayLabel}" (id: "${t.canonicalComponentId}"${t.zoneId != null ? ', zone/région: "${t.zoneId}"' : ''})').join('\n')}
${parentIds.isNotEmpty ? '- Conteneur(s) parent(s) : $parentList\n' : ''}- Le périmètre modifiable autorisé couvre uniquement ces éléments sélectionnés ($targetIdsList), leurs sous-arbres et la réorganisation/ajout éventuel dans $effectiveParent.
- Ne modifie ni ne supprime AUCUN composant frère non sélectionné dans $effectiveParent, ni aucun composant au-dessus de $effectiveParent.
- Ne modifie PAS les paramètres globaux de thème (mode, accent, background) ni pageCatalog.
- Tout nouveau composant créé doit être rattaché dans les placements de $effectiveParent ou de l’un des éléments sélectionnés.'''
          : '''RESTRICTION STRICTE DE SCOPE :
L'utilisateur a ouvert l'assistant IA sur un scope restreint : "${scope.displayLabel}" (composant id: "${scope.canonicalComponentId}"${scope.zoneId != null ? ', zone/région: "${scope.zoneId}"' : ''}${parentIds.isNotEmpty ? ', conteneur parent: $parentList' : ''}).
- Le périmètre modifiable autorisé couvre l'élément sélectionné ("${scope.canonicalComponentId}") ainsi que son conteneur parent ($effectiveParent) et tout le sous-arbre de ce parent.
- Ne modifie AUCUN composant situé au-dessus ou en dehors du conteneur parent ($effectiveParent).
- Ne modifie PAS les paramètres globaux de thème (mode, accent, background) ni pageCatalog.
- Tout nouveau composant créé doit être rattaché dans les placements de $effectiveParent ou de l’un de ses sous-composants.''';
      return [
        questioningDirective,
        ?exactSection,
        ?planSection,
        ?visibleOnlySection,
        scopeDirective,
        ?visibleCtxSection,
        ?mountedHint,
        ?repositoriesSection,
        'ÉTAT DU SCOPE CIBLÉ (JSON) :\n${VibeScopeHelpers.exportScopedAi(appearance, scope, codec: codec)}',
        'CONVERSATION :\n$conversation',
      ].join('\n\n');
    }

    final current = AppearanceTransfer.exportCompactAi(
      appearance,
      codec: codec,
    );
    final codedRoutesHint = codedRoutePaths.isEmpty
        ? null
        : 'Routes codées existantes (réservées — ne jamais les réutiliser comme "path" dans "pageCatalog" ; "/" correspond déjà à "root"/"mainLayout") : '
              '${jsonEncode(codedRoutePaths)}.';
    return [
      questioningDirective,
      ?exactSection,
      ?planSection,
      ?visibleOnlySection,
      ?visibleCtxSection,
      ?codedRoutesHint,
      if (instantiatedComponentIds != null)
        'Les composants instanciés sont : ${jsonEncode(instantiatedComponentIds.toList())}. '
            'Rattache les modifications à ces composants ou aux pages déclarées ; '
            'une configuration sauvegardée mais isolée ne suffit pas.',
      ?mountedHint,
      ?repositoriesSection,
      'ÉTAT ACTUEL (JSON) :\n$current',
      'CONVERSATION :\n$conversation',
    ].join('\n\n');
  }

  /// Assemble le prompt d'exécution automatique d'un lot précis ([lotIndex]) d'un [plan].
  static String buildLotTurnPrompt({
    required VibeExecutionPlan plan,
    required int lotIndex,
    required String sourcePrompt,
    required Appearance appearance,
    required AppearanceCodec codec,
    required VibeChatScope? scope,
    List<VibeChatAttachment> sourceAttachments = const [],
    Iterable<String>? instantiatedComponentIds,
    List<String> mountedSlotSummaries = const <String>[],
    List<String> codedRoutePaths = const <String>[],
    String? repositoriesContext,
    bool visibleOnlyMode = false,
    String? visibleViewportContext,
  }) {
    final trimmedRepositories = repositoriesContext?.trim() ?? '';
    final repositoriesSection = trimmedRepositories.isEmpty
        ? null
        : (trimmedRepositories.startsWith('REPOSITORIES DISPONIBLES')
              ? trimmedRepositories
              : 'REPOSITORIES DISPONIBLES (JSON) :\n$trimmedRepositories');
    final mountedHint = mountedSlotSummaries.isEmpty
        ? null
        : 'Slots montés actuellement à l’écran : ${jsonEncode(mountedSlotSummaries)}.';
    final effectiveExact = plan.reproduceExact;
    final exactSection = effectiveExact ? reproduceExactCommonDirective : null;
    final visibleOnlySection = visibleOnlyMode ? visibleOnlyDirective : null;
    final trimmedVisibleCtx = visibleViewportContext?.trim() ?? '';
    final visibleCtxSection = visibleOnlyMode && trimmedVisibleCtx.isNotEmpty
        ? trimmedVisibleCtx
        : null;
    final isAuditPlan =
        sourcePrompt.trimLeft().startsWith('AUDIT & CORRECTION') ||
        plan.title.toLowerCase().contains('audit');
    final auditLotSection = isAuditPlan ? auditLotExecutionDirective : null;
    final lotDirective =
        '''
PHASE 2 — EXÉCUTION DU LOT ${lotIndex + 1}/${plan.lots.length} :
${plan.formatLotContextPrompt(lotIndex)}

RÈGLES D’EXÉCUTION DU LOT :
- Implémente UNIQUEMENT le lot cible (${lotIndex + 1}/${plan.lots.length}) et renvoie {"message":"résumé court du lot réalisé",${effectiveExact ? '' : '"repositories":{...} (si des repositories doivent être créés/peuplés dans ce lot et que REPOSITORIES DISPONIBLES est présent — inclus systématiquement "jsonSchema" pour chaque nouveau repository et mets à jour le "jsonSchema" existant si tu ajoutes de nouveaux champs), '}"vibe":{...}} (avec "plan": null et "askUser": null ; ajoute "verifyRender": true si le lot le demande, s’il s’agit d’un lot d’audit touchant un en-tête de carte maître, ou s’il crée/modifie une `SuperListView`, un `SuperTable`, une zone en ligne `zoneAxes: 'row'`, un volet étroit ≤ 480 dp, un en-tête ou une barre d’outils).
${effectiveExact ? '' : '- Respecte le Design System actif (tokens theme:* ou DESIGN.md sélectionné) et les règles d’atomicité GenUI.\n'}- PRÉSERVATION OBLIGATOIRE DES LOTS PRÉCÉDENTS : lorsque tu modifies "placements" ou "regions" d’un conteneur existant ("root", "mainLayout", etc.), réémets INTÉGRALEMENT tous les placements existants à conserver dans l’ordre (y compris ceux déjà construits par les lots précédents et "scaffold:body"), en ajoutant uniquement les nouvelles sections de ce lot.
- Renseigne systématiquement "slotLabels" sur le parent pour chaque nouveau composant ; le moteur déduit automatiquement "usages" pour les conteneurs (layout), boutons (action), saisies (userInput), indicateurs/séparateurs (decoration) et étiquettes simples (explanation) — n’émets dans "usages" que les rôles métier spécifiques ("dynamicData", "staticData", "feedback") afin d’accélérer la génération.
- Émets un JSON compact sur une seule ligne (sans indentation multi-espaces) et choisis directement tes icônes dans le catalogue `MaterialIconCatalog` du guide sans appeler `validate_or_list_icons`.''';

    final attachmentsSummary = sourceAttachments.isEmpty
        ? ''
        : '\nPièces jointes de référence fournies : '
              '${sourceAttachments.map((a) => '"${a.name}"').join(', ')}.';
    final effectiveRequest = sourcePrompt.trim().isEmpty
        ? (effectiveExact
              ? 'Reproduis à l’identique la source jointe.'
              : 'Réalise la demande décrite dans le plan.')
        : sourcePrompt.trim();
    final sourceSection =
        'DEMANDE INITIALE DE RÉFÉRENCE :\n$effectiveRequest$attachmentsSummary';

    if (scope != null) {
      final parentIds = VibeScopeHelpers.parentIdsOfScope(appearance, scope);
      final parentList = parentIds.map((id) => '"$id"').join(', ');
      final targetIdsList = scope.canonicalComponentIds
          .map((id) => '"$id"')
          .join(', ');
      final effectiveParent = parentIds.isNotEmpty ? parentList : targetIdsList;
      return [
        ?exactSection,
        lotDirective,
        ?auditLotSection,
        ?visibleOnlySection,
        '''RESTRICTION STRICTE DE SCOPE :
Périmètre modifiable autorisé : ${scope.isMultiTarget ? targetIdsList : '"${scope.canonicalComponentId}"'} et son/ses parent(s) ($effectiveParent).''',
        ?visibleCtxSection,
        ?mountedHint,
        ?repositoriesSection,
        'ÉTAT ACTUEL DU SCOPE APRÈS LES LOTS PRÉCÉDENTS (JSON) :\n'
            '${VibeScopeHelpers.exportScopedAi(appearance, scope, codec: codec)}',
        sourceSection,
      ].join('\n\n');
    }

    final current = exportLotStateAi(
      appearance,
      plan: plan,
      lotIndex: lotIndex,
      codec: codec,
      instantiatedComponentIds: instantiatedComponentIds,
    );
    final codedRoutesHint = codedRoutePaths.isEmpty
        ? null
        : 'Routes codées existantes (réservées — ne jamais les réutiliser comme "path" dans "pageCatalog" ; "/" correspond déjà à "root"/"mainLayout") : '
              '${jsonEncode(codedRoutePaths)}.';
    return [
      ?exactSection,
      lotDirective,
      ?auditLotSection,
      ?visibleOnlySection,
      ?visibleCtxSection,
      ?codedRoutesHint,
      if (instantiatedComponentIds != null)
        'Les composants instanciés sont : ${jsonEncode(instantiatedComponentIds.toList())}. '
            'Rattache les nouvelles sections à ces conteneurs existants.',
      ?mountedHint,
      ?repositoriesSection,
      'ÉTAT ACTUEL DE L’ÉCRAN APRÈS LES LOTS PRÉCÉDENTS (JSON) :\n$current',
      sourceSection,
    ].join('\n\n');
  }

  /// Exporte l'état `Appearance` pertinent pour le lot [lotIndex] d'un [plan].
  ///
  /// Pour les applications volumineuses (> 80 composants), conserve intégralement
  /// le shell racine (`root`, `mainLayout`), `pageCatalog`, les styles globaux et
  /// les sous-arbres des pages mentionnées dans le lot cible, tout en résumant
  /// les identifiants internes des autres pages secondaires déjà terminées afin
  /// d'éviter la croissance quadratique du prompt au fil des lots.
  static String exportLotStateAi(
    Appearance appearance, {
    required VibeExecutionPlan plan,
    required int lotIndex,
    AppearanceCodec codec = const AppearanceCodec(),
    Iterable<String>? instantiatedComponentIds,
  }) {
    if (appearance.components.length <= 80 ||
        appearance.pageCatalog.pages.isEmpty) {
      return AppearanceTransfer.exportCompactAi(appearance, codec: codec);
    }

    final targetLot = plan.lots[lotIndex];
    final lotTextLower =
        '${targetLot.id} ${targetLot.title} ${targetLot.description}'
            .toLowerCase();

    Set<String> collectSubtree(Iterable<String> roots) {
      final visited = <String>{};
      final stack = <String>[...roots];
      while (stack.isNotEmpty) {
        final id = stack.removeLast();
        if (!visited.add(id)) continue;
        final cfg = appearance.components[id];
        if (cfg != null) {
          stack.addAll(VibeScopeHelpers.childrenOfComponent(cfg));
        }
      }
      return visited;
    }

    final pageIds = <String>{for (final p in appearance.pageCatalog.pages) p.id};
    final shellRoots = <String>{
      'root',
      'mainLayout',
      for (final shell in appearance.pageCatalog.shells) shell.id,
      if (instantiatedComponentIds != null)
        ...instantiatedComponentIds.where((id) => !pageIds.contains(id)),
    };
    final keptComponentIds = <String>{...collectSubtree(shellRoots)};

    for (final page in appearance.pageCatalog.pages) {
      final pageIdLower = page.id.toLowerCase();
      final pagePathLower = page.path.toLowerCase();
      final pageNameLower = page.name.toLowerCase();
      final pathSegments = pagePathLower
          .split('/')
          .where((s) => s.length >= 4 && !s.startsWith(':'));
      final isRelevantToLot =
          lotTextLower.contains(pageIdLower) ||
          (pagePathLower.length > 1 && lotTextLower.contains(pagePathLower)) ||
          (pageNameLower.length >= 4 && lotTextLower.contains(pageNameLower)) ||
          pathSegments.any(lotTextLower.contains);
      if (isRelevantToLot) {
        keptComponentIds.addAll(collectSubtree(<String>[page.id]));
      } else {
        // Conserve la coque racine de la page afin que ses régions restent connues.
        keptComponentIds.add(page.id);
      }
    }

    final omittedComponentIds = <String>[
      for (final id in appearance.components.keys)
        if (!keptComponentIds.contains(id)) id,
    ];
    if (omittedComponentIds.length < 25) {
      return AppearanceTransfer.exportCompactAi(appearance, codec: codec);
    }

    final rawCompact = codec.toCompactJson(appearance)..remove('version');
    // Omet `usages` dans le contexte inter-lots des grandes apps pour économiser des dizaines de Ko.
    rawCompact.remove('usages');
    if (rawCompact['components'] case final Map<String, Object?> comps) {
      rawCompact['components'] = <String, Object?>{
        for (final entry in comps.entries)
          if (keptComponentIds.contains(entry.key)) entry.key: entry.value,
      };
    }
    if (rawCompact['styles'] case final Map<String, Object?> stylesMap) {
      rawCompact['styles'] = <String, Object?>{
        for (final entry in stylesMap.entries)
          if (entry.key == 'background' ||
              keptComponentIds.contains(entry.key) ||
              (entry.key.endsWith(':item') &&
                  keptComponentIds.contains(
                    entry.key.substring(0, entry.key.length - 5),
                  )))
            entry.key: entry.value,
      };
    }
    if (rawCompact['behaviors'] case final Map<String, Object?> behaviorsMap) {
      rawCompact['behaviors'] = <String, Object?>{
        for (final entry in behaviorsMap.entries)
          if (keptComponentIds.contains(entry.key)) entry.key: entry.value,
      };
    }
    final compactJson = jsonEncode(rawCompact);
    return '$compactJson\n'
        'Note : ${omittedComponentIds.length} composants internes d’autres routes secondaires déjà construites sont omis de cet aperçu mais intégralement préservés par fusion ("merge") ; ne réutilise pas leurs identifiants : ${jsonEncode(omittedComponentIds.take(120).toList())}.';
  }

  /// Directive de phase 1 pour l'audit complet et la planification de corrections.
  static const String auditPlanDirective = '''
MODE « AUDIT & CORRECTION » — PHASE 1 (ANALYSE + PLAN DE CORRECTION PAR LOTS) :
Tu dois auditer la page active (ou le scope ciblé) à partir du rapport de pré-audit déterministe ci-dessous, de l’instantané JSON et, uniquement si une information manque réellement, des outils d’inspection (`preview_navigation_or_selection`, `get_component_geometry`, `capture_element_screenshot`, `capture_screenshot`, `query_repository_data`, `inspect_bindings_and_diagnostics`).
EXPLOITATION DIRECTE DU PRÉ-AUDIT (ZÉRO TOUR D’OUTIL REDONDANT) :
- Le `RAPPORT DE PRÉ-AUDIT DÉTERMINISTE` ci-dessous a DÉJÀ exécuté localement `get_viewport_and_route`, `get_component_geometry` (avec les dimensions rendues en dp et le calcul budgétaire des lignes `row`), `inspect_bindings_and_diagnostics`, `get_debug_entries` et `get_theme_and_contrast` : réutilise directement ces mesures et constats sans rappeler ces outils un par un sur les composants déjà mesurés !
- Si un appel d’outil complémentaire est indispensable (ex. `capture_element_screenshot` ou `query_repository_data`), regroupe TOUS tes appels d’outils en UN SEUL tour parallèle.

RÈGLES OBLIGATOIRES :
1. NE génère PAS encore de patch `"vibe"` ni `"repositories"` sur ce tour (`"vibe": null`, `"askUser": null`).
2. Vérifie impérativement :
   - Les marges/paddings qui coupent le contenu, dépassements parent/viewport, contraintes `slotSizeConstraints` trop serrées (`fitContent: false`), textes tronqués et `RenderFlex` overflows ;
   - **Contrôle systématique du budget de largeur en ligne (`zoneAxes: 'row'`)** / **Contrôle budgétaire de largeur en ligne (`zoneAxes: 'row'`)** : Sur tout conteneur ou zone disposé en ligne (`zoneAxes: 'row'`), additionne systématiquement via `get_component_geometry` les largeurs mesurées des composants enfants et lève une alerte dès que `somme(width) > parentWidth - paddings` (et veille à ce que `[somme(width) + espacements]` reste strictement inférieur à `parentWidth - paddingLeft - paddingRight`) ;
   - **Maîtrise du budget de largeur & prévention de la troncature silencieuse (tout `SuperLayout` et `template` de liste)** :
     - Interdis `autoSides: ["east"]` ou `autoSides: ["west"]` sur tout layout ou gabarit de liste (`template`) dès que ce côté héberge des données textuelles dynamiques (email, téléphone, dates), des badges ou des groupes d'actions : impose une taille fixe explicite (`eastSize` ou `westSize` entre `180` et `320` dp) pour borner l'espace restant du `center` ;
     - Au-delà de `zoneAxes: 'row'`, vérifie pour tout `SuperLayout` que `[somme(tailles fixes des côtés actifs) + paddings + marges] < largeur totale disponible` et que `center` conserve une largeur minimale viable ;
     - Pour toute ligne riche combinant titre/désignation principale et métadonnées secondaires (statut, montant, actions), exige soit une zone droite dimensionnée en dur via `eastSize`, soit un layout en ligne avec `slotSizeConstraints` (`maxWidth` sur le texte long et `fitContent: true` sur les contrôles) ;
   - **Règle d'or sur les volets latéraux étroits (largeur ≤ 480 dp)** : Interdis strictement la cohabitation sur une même ligne d'un titre long (> 30 caractères) et d'un bouton d'action complet texte + icône ; exige soit un bouton d'action à icône seule (`kind: 'icon'`, avec `tooltip` explicite), soit un titre compacté (≤ 30 caractères) ;
   - **Audit visuel obligatoire par capture isolée (`capture_element_screenshot`)** & **Inspection visuelle par élément** : Ordonne et exécute une capture visuelle de contrôle avec `capture_element_screenshot` sur chaque en-tête de carte maître avant de clore un lot d'audit (ainsi qu'en cas de modification d'en-tête ou de barre d'outils), ainsi que sur la première occurrence (`occurrenceIndex: 0`) de toute `SuperListView` ou `SuperTable` créée ou auditée, pour valider l'alignement et l'absence de coupure, de texte tronqué ou de superposition en fin de ligne ;
   - Les calculs manquants (`@calculs` non déclarés sur les repositories, KPIs/totaux statiques ou placeholders sans binding calculé, bindings cassés) ;
   - La cohérence de navigation multi-pages (`missing_page_navigation` : pages standard sans `shellId` ni barre de navigation propre ; `missing_shell_outlet` : shell sans `scaffold:outlet` dans `body`) ;
   - Les erreurs runtime, problèmes de schémas/liaisons et défauts de contraste WCAG AA.
3. Si des anomalies sont confirmées, renvoie UNIQUEMENT un plan de correction structuré en lots cohérents :
   {"message":"Résumé clair des anomalies trouvées en français","plan":{"title":"Plan d’audit et correction","lots":[{"id":"lot-1","title":"...","description":"Liste précise des IDs de composants/styles/repositories et corrections exactes à appliquer"}]},"vibe":null}
   - Regroupe logiquement : par ex. Lot 1 = Mise en page, marges, paddings, volets latéraux étroits (≤ 480 dp), contraintes et coupures ; Lot 2 = Repositories, attributs `@calculs` et liaisons manquantes ; Lot 3 = Contrastes WCAG AA et finitions (ou 1 seul lot s’il y a peu de corrections).
   - Indique dans la description des lots corrigeant des marges/débordements, une zone en ligne (`zoneAxes: 'row'`), un volet latéral étroit (≤ 480 dp), un onglet, une barre d’outils ou un en-tête de carte maître de recontrôler le rendu après application (`"verifyRender": true`) avec une capture isolée `capture_element_screenshot` sur chaque en-tête de carte maître avant clôture du lot.
4. Si aucune anomalie réelle n’est détectée après vérification, renvoie :
   {"message":"Audit terminé : aucune anomalie détectée sur ce périmètre.","plan":null,"vibe":null}''';

  /// Consignes impératives injectées en Phase 2 lors de l'exécution d'un lot issu de « Audit & correction ».
  static const String auditLotExecutionDirective = '''
RÈGLES IMPÉRATIVES D’AUDIT & CORRECTION SUR CE LOT :
- Exploitation directe des mesures : réutilise directement les dimensions, constats de liaisons et erreurs du `RAPPORT DE PRÉ-AUDIT DÉTERMINISTE` inclus dans la demande de référence sans refaire une série d’appels `get_viewport_and_route` / `get_component_geometry` / `get_debug_entries` avant de générer le patch ; regroupe tout éventuel appel d’outil restant en un seul tour parallèle.
1. **Contrôle systématique du budget de largeur en ligne (`zoneAxes: 'row'`) & budget horizontal universel (`SuperLayout`)** : Additionne les largeurs mesurées des composants enfants sur tout conteneur en ligne et corrige toute configuration où `somme(width) > parentWidth - paddings` (`[somme(width) + espacements] < parentWidth - paddingLeft - paddingRight`). Vérifie aussi sur tout `SuperLayout` que `[somme(tailles fixes des côtés actifs) + paddings + marges] < largeur totale disponible` avec un `center` viable, remplace tout `autoSides: ["east"]` / `["west"]` portant données dynamiques, badges ou actions (y compris dans un `template` de liste) par un `eastSize`/`westSize` fixe (`180`–`320` dp), et structure les lignes riches (titre + métadonnées) soit avec `eastSize` fixe soit avec `slotSizeConstraints` (`maxWidth` sur le texte long + `fitContent: true` sur les contrôles).
2. **Règle d'or sur les volets latéraux étroits (largeur ≤ 480 dp)** : Interdis sur une même ligne la cohabitation d'un titre long (> 30 caractères) et d'un bouton d'action complet texte + icône ; applique obligatoirement soit un bouton d'action à icône seule (`kind: 'icon'`, avec `tooltip`), soit un titre compacté.
3. **Audit visuel obligatoire par capture isolée (`capture_element_screenshot`)** : Active `"verifyRender": true` et effectue une capture visuelle de contrôle avec `capture_element_screenshot` sur chaque en-tête de carte maître ainsi que sur la première occurrence (`occurrenceIndex: 0`) de chaque `SuperListView` ou `SuperTable` concernée avant de clore ce lot d'audit.''';

  /// Consigne de balayage systématique des onglets (`SuperTab`) injectée uniquement hors scope.
  static const String auditTabSweepDirective = '''
BALAYAGE COMPLET DES ONGLETS DE LA PAGE (HORS SCOPE) :
- Aucun scope restreint n’est actif : l’audit couvre TOUS les onglets (`SuperTab` / `"type": "tab"`) de la page active en les balayant un par un, y compris les onglets initialement masqués.
- Le pré-audit déterministe ci-dessus a déjà balayé chaque onglet monté (voir `ONGLETS BALAYÉS`), mais dès qu’une mesure géométrique (`get_component_geometry` sur `zoneAxes: 'row'`, tailles, débordements) ou une capture isolée (`capture_element_screenshot`) est utile sur un onglet non affiché, bascule d’abord dessus via `preview_navigation_or_selection` (`{"tabComponentId": "<idDuSuperTab>", "tabIndex": <0..N-1>}` ou `"tabId": "<idOuLabel>"`) afin de monter réellement cet onglet à l’écran avant de l’inspecter.
- Mentionne explicitement l’onglet concerné dans la description des lots de correction.''';

  /// Consigne complémentaire injectée sur un audit lorsque le mode « Plan » est sélectionné,
  /// afin de déclarer `dependsOn` sur les lots indépendants pour l'option « Exécution en parallèle ».
  static const String auditParallelDependenciesDirective = '''
DÉPENDANCES ENTRE LOTS D’AUDIT (MODE « PLAN » ACTIF) :
- Le mode « Plan » est sélectionné : l’utilisateur pourra lancer ce plan soit en séquentiel par défaut, soit via le bouton « Exécution en parallèle ».
- Lorsque plusieurs lots d’audit corrigent des périmètres disjoints (ex. onglets/sections distincts ou styles vs repositories indépendants), renseigne explicitement `"dependsOn"` avec les identifiants exacts des lots prérequis (ou `"dependsOn": ["lot-1"]` pour les lots exécutables en parallèle après un lot socle).''';

  /// Assemble le prompt spécialisé d'audit de la page active (ou du [scope] actif).
  static String buildAuditTurnPrompt({
    required VibePageAuditReport report,
    required String conversation,
    required Appearance appearance,
    required AppearanceCodec codec,
    required VibeChatScope? scope,
    Iterable<String>? instantiatedComponentIds,
    List<String> mountedSlotSummaries = const <String>[],
    String? repositoriesContext,
    bool planMode = false,
    bool visibleOnlyMode = false,
    String? visibleViewportContext,
  }) {
    final trimmedRepositories = repositoriesContext?.trim() ?? '';
    final repositoriesSection = trimmedRepositories.isEmpty
        ? null
        : (trimmedRepositories.startsWith('REPOSITORIES DISPONIBLES')
              ? trimmedRepositories
              : 'REPOSITORIES DISPONIBLES (JSON) :\n$trimmedRepositories');
    final mountedHint = mountedSlotSummaries.isEmpty
        ? null
        : 'Slots montés actuellement à l’écran : ${jsonEncode(mountedSlotSummaries)}.';
    final reportSection =
        'RAPPORT DE PRÉ-AUDIT DÉTERMINISTE :\n${report.toPromptSummary()}';
    final parallelAuditSection = planMode
        ? auditParallelDependenciesDirective
        : null;
    final visibleOnlySection = visibleOnlyMode ? visibleOnlyDirective : null;
    final trimmedVisibleCtx = visibleViewportContext?.trim() ?? '';
    final visibleCtxSection = visibleOnlyMode && trimmedVisibleCtx.isNotEmpty
        ? trimmedVisibleCtx
        : null;

    if (scope != null) {
      final parentIds = VibeScopeHelpers.parentIdsOfScope(appearance, scope);
      final parentList = parentIds.map((id) => '"$id"').join(', ');
      final targetIdsList = scope.canonicalComponentIds
          .map((id) => '"$id"')
          .join(', ');
      final effectiveParent = parentIds.isNotEmpty ? parentList : targetIdsList;
      final scopeDirective =
          '''RESTRICTION STRICTE DE SCOPE POUR L’AUDIT :
Le périmètre modifiable autorisé couvre uniquement ${scope.isMultiTarget ? targetIdsList : '"${scope.canonicalComponentId}"'} et son/ses parent(s) ($effectiveParent).
Ne propose aucune modification en dehors de ce scope ni sur les paramètres globaux de thème ou pageCatalog.''';
      return [
        auditPlanDirective,
        ?parallelAuditSection,
        ?visibleOnlySection,
        scopeDirective,
        ?visibleCtxSection,
        reportSection,
        ?mountedHint,
        ?repositoriesSection,
        'ÉTAT DU SCOPE CIBLÉ (JSON) :\n${VibeScopeHelpers.exportScopedAi(appearance, scope, codec: codec)}',
        if (conversation.trim().isNotEmpty) 'CONVERSATION :\n$conversation',
      ].join('\n\n');
    }

    final current = AppearanceTransfer.exportCompactAi(
      appearance,
      codec: codec,
    );
    return [
      auditPlanDirective,
      ?parallelAuditSection,
      if (visibleOnlyMode) visibleOnlyDirective else auditTabSweepDirective,
      ?visibleCtxSection,
      if (instantiatedComponentIds != null)
        'Les composants instanciés sont : ${jsonEncode(instantiatedComponentIds.toList())}.',
      reportSection,
      ?mountedHint,
      ?repositoriesSection,
      'ÉTAT ACTUEL (JSON) :\n$current',
      if (conversation.trim().isNotEmpty) 'CONVERSATION :\n$conversation',
    ].join('\n\n');
  }

  /// Assemble le prompt de la phase finale « Valeurs réactives » exécutée
  /// automatiquement après la génération (et avant la vérification post-rendu).
  static String buildPostReactiveValuesPrompt({
    required Appearance appearance,
    required AppearanceCodec codec,
    required VibeChatScope? scope,
    List<String> mountedSlotSummaries = const <String>[],
    String? repositoriesContext,
    bool visibleOnlyMode = false,
    String? visibleViewportContext,
  }) {
    final trimmedRepositories = repositoriesContext?.trim() ?? '';
    final repositoriesSection = trimmedRepositories.isEmpty
        ? null
        : (trimmedRepositories.startsWith('REPOSITORIES DISPONIBLES')
              ? trimmedRepositories
              : 'REPOSITORIES DISPONIBLES (JSON) :\n$trimmedRepositories');
    final mountedHint = mountedSlotSummaries.isEmpty
        ? null
        : 'Slots montés actuellement à l’écran : ${jsonEncode(mountedSlotSummaries)}.';
    final visibleOnlySection = visibleOnlyMode ? visibleOnlyDirective : null;
    final trimmedVisibleCtx = visibleViewportContext?.trim() ?? '';
    final visibleCtxSection = visibleOnlyMode && trimmedVisibleCtx.isNotEmpty
        ? trimmedVisibleCtx
        : null;

    String? scopeDirective;
    final String stateSection;
    if (scope != null) {
      final parentIds = VibeScopeHelpers.parentIdsOfScope(appearance, scope);
      final parentList = parentIds.map((id) => '"$id"').join(', ');
      final targetIdsList = scope.canonicalComponentIds
          .map((id) => '"$id"')
          .join(', ');
      final effectiveParent = parentIds.isNotEmpty ? parentList : targetIdsList;
      scopeDirective =
          '''RESTRICTION STRICTE DE SCOPE (PHASE VALEURS RÉACTIVES) :
Le périmètre modifiable autorisé dans "vibe" couvre uniquement ${scope.isMultiTarget ? targetIdsList : '"${scope.canonicalComponentId}"'} et son/ses parent(s) ($effectiveParent).
Ne modifie aucun composant hors de ce scope ni les paramètres globaux de thème ou pageCatalog.''';
      stateSection =
          'ÉTAT DU SCOPE CIBLÉ APRÈS GÉNÉRATION (JSON) :\n'
          '${VibeScopeHelpers.exportScopedAi(appearance, scope, codec: codec)}';
    } else {
      final current = AppearanceTransfer.exportCompactAi(
        appearance,
        codec: codec,
      );
      stateSection = 'ÉTAT ACTUEL APRÈS GÉNÉRATION (JSON) :\n$current';
    }

    const closingRules = '''SORTIE ATTENDUE (PHASE FINALE VALEURS RÉACTIVES) :
- Ne renvoie JAMAIS `"plan"` ni `"askUser"` durant cette phase finale.
- Si toutes les valeurs dérivées, liaisons `@...`, modes saisie/consultation et graphiques sont déjà corrects (ou qu’aucune valeur calculée réactive n’est pertinente sur cette génération), renvoie simplement {"message":"Valeurs réactives vérifiées.","vibe":null}.
- Sinon, renvoie uniquement un patch delta ciblé dans `"repositories"` (ex. `calculatedAttributes`) et/ou `"vibe"` (ex. `SuperValue` en `mode: "input"`/`"display"` lié à `@...`, ou `SuperChart`), avec `"verifyRender": false`.''';

    return [
      'PHASE FINALE — VALEURS RÉACTIVES (APERÇU APPLIQUÉ) :\n'
          'La génération principale vient d’être appliquée en aperçu. Vérifie et complète maintenant la réactivité des données calculées et de leur affichage.',
      reactiveValuesDirective,
      ?visibleOnlySection,
      ?scopeDirective,
      ?visibleCtxSection,
      ?mountedHint,
      ?repositoriesSection,
      stateSection,
      closingRules,
    ].join('\n\n');
  }
}
