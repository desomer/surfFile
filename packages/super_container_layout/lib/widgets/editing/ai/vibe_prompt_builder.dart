/// Assemble l'historique et le prompt Vibe à partir de l'état courant.
library;

import 'dart:convert';

import '../../../ai/vibe_chat_attachment.dart';
import '../../../ai/vibe_plan.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/appearance_transfer.dart';
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
- Respecte toutes les contraintes du moteur : JSON strict valide, ordre Top-Down ("styles" puis "components" parent -> enfants puis "usages"), "slotLabels" non vide sur le parent pour chaque nouveau composant, et "usages" renseigné pour chaque composant sans binding.''';

  /// Consigne de planification automatique en lots (Phase 1 du mode « Reproduire à l'identique »).
  static const String reproduceExactPlanningDirective = '''
PHASE 1 — PLANIFICATION EN LOTS OBLIGATOIRE :
- Avant de générer des composants "vibe", découpe la reproduction complète de la source en un plan ordonné de lots cohérents et autonomes afin de ne jamais dépasser la limite de sortie JSON ni dégrader la précision :
  - Lot 1 : Thème global ("mode", "accent", "styles['background']"), architecture de scroll/navigation, en-tête (header) et section Hero.
  - Lots intermédiaires : 1 à x sections visuelles, blocs fonctionnels par lot (avec toutes leurs URLs exactes).
  - Dernier lot : Pied de page (footer), bandeaux finaux et finitions.
  - (Si la page source est courte/simple, un plan à 1 seul lot suffit.)
- Renvoie UNIQUEMENT un objet JSON de la forme :
  {"message":"courte présentation du plan en français","plan":{"title":"...","lots":[{"id":"lot-1","title":"...","description":"détail précis des sections, textes, styles et images à inclure"}]},"vibe":null}
- Ne génère PAS encore de patch "vibe" sur ce tour.''';

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
  /// des repositories JSON ([repositoriesContext]), de la portée choisie ([scope])
  /// et du mode de reproduction exacte ([reproduceExactMode]).
  static String buildTurnPrompt({
    required String questioningDirective,
    required String conversation,
    required Appearance appearance,
    required AppearanceCodec codec,
    required VibeChatScope? scope,
    Iterable<String>? instantiatedComponentIds,
    List<String> mountedSlotSummaries = const <String>[],
    String? repositoriesContext,
    bool reproduceExactMode = false,
  }) {
    final trimmedRepositories = repositoriesContext?.trim() ?? '';
    final repositoriesSection = trimmedRepositories.isEmpty
        ? null
        : (trimmedRepositories.startsWith('REPOSITORIES DISPONIBLES')
              ? trimmedRepositories
              : 'REPOSITORIES DISPONIBLES (JSON) :\n$trimmedRepositories');
    final exactSection = reproduceExactMode
        ? '$reproduceExactCommonDirective\n\n$reproduceExactPlanningDirective'
        : null;
    final mountedHint = mountedSlotSummaries.isEmpty
        ? null
        : 'Slots montés actuellement à l’écran (utilisables avec get_component_geometry / capture_screenshot) : '
              '${jsonEncode(mountedSlotSummaries)}.';

    if (scope != null) {
      final parentIds = VibeScopeHelpers.parentIdsOfScope(appearance, scope);
      final parentList = parentIds.map((id) => '"$id"').join(', ');
      final effectiveParent = parentIds.isNotEmpty
          ? parentList
          : '"${scope.canonicalComponentId}"';
      return [
        questioningDirective,
        ?exactSection,
        '''RESTRICTION STRICTE DE SCOPE :
L'utilisateur a ouvert l'assistant IA sur un scope restreint : "${scope.displayLabel}" (composant id: "${scope.canonicalComponentId}"${scope.zoneId != null ? ', zone/région: "${scope.zoneId}"' : ''}${parentIds.isNotEmpty ? ', conteneur parent: $parentList' : ''}).
- Le périmètre modifiable autorisé couvre l'élément sélectionné ("${scope.canonicalComponentId}") ainsi que son conteneur parent ($effectiveParent) et tout le sous-arbre de ce parent.
- Ne modifie AUCUN composant situé au-dessus ou en dehors du conteneur parent ($effectiveParent).
- Ne modifie PAS les paramètres globaux de thème (mode, accent, background) ni pageCatalog.
- Tout nouveau composant créé doit être rattaché dans les placements de $effectiveParent ou de l’un de ses sous-composants.''',
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
    return [
      questioningDirective,
      ?exactSection,
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
    String? repositoriesContext,
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
    final lotDirective = '''
PHASE 2 — EXÉCUTION DU LOT ${lotIndex + 1}/${plan.lots.length} :
${plan.formatLotContextPrompt(lotIndex)}

RÈGLES D’EXÉCUTION DU LOT :
- Implémente UNIQUEMENT le lot cible (${lotIndex + 1}/${plan.lots.length}) et renvoie {"message":"résumé court du lot réalisé","vibe":{...}} (avec "plan": null et "askUser": null).
- PRÉSERVATION OBLIGATOIRE DES LOTS PRÉCÉDENTS : lorsque tu modifies "placements" ou "regions" d’un conteneur existant ("root", "mainLayout", etc.), réémets INTÉGRALEMENT tous les placements existants à conserver dans l’ordre (y compris ceux déjà construits par les lots précédents et "scaffold:body"), en ajoutant uniquement les nouvelles sections de ce lot.
- Renseigne systématiquement "slotLabels" sur le parent et "usages" pour chaque nouveau composant sans liaison.''';

    final attachmentsSummary = sourceAttachments.isEmpty
        ? ''
        : '\nPièces jointes de référence fournies : '
              '${sourceAttachments.map((a) => '"${a.name}"').join(', ')}.';
    final effectiveRequest = sourcePrompt.trim().isEmpty
        ? 'Reproduis à l’identique la source jointe.'
        : sourcePrompt.trim();
    final sourceSection =
        'DEMANDE INITIALE DE RÉFÉRENCE :\n$effectiveRequest$attachmentsSummary';

    if (scope != null) {
      final parentIds = VibeScopeHelpers.parentIdsOfScope(appearance, scope);
      final parentList = parentIds.map((id) => '"$id"').join(', ');
      final effectiveParent = parentIds.isNotEmpty
          ? parentList
          : '"${scope.canonicalComponentId}"';
      return [
        reproduceExactCommonDirective,
        lotDirective,
        '''RESTRICTION STRICTE DE SCOPE :
Périmètre modifiable autorisé : "${scope.canonicalComponentId}" et son parent ($effectiveParent).''',
        ?mountedHint,
        ?repositoriesSection,
        'ÉTAT ACTUEL DU SCOPE APRÈS LES LOTS PRÉCÉDENTS (JSON) :\n'
            '${VibeScopeHelpers.exportScopedAi(appearance, scope, codec: codec)}',
        sourceSection,
      ].join('\n\n');
    }

    final current = AppearanceTransfer.exportCompactAi(
      appearance,
      codec: codec,
    );
    return [
      reproduceExactCommonDirective,
      lotDirective,
      if (instantiatedComponentIds != null)
        'Les composants instanciés sont : ${jsonEncode(instantiatedComponentIds.toList())}. '
            'Rattache les nouvelles sections à ces conteneurs existants.',
      ?mountedHint,
      ?repositoriesSection,
      'ÉTAT ACTUEL DE L’ÉCRAN APRÈS LES LOTS PRÉCÉDENTS (JSON) :\n$current',
      sourceSection,
    ].join('\n\n');
  }
}
