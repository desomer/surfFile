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
- DÉROGATION AU DESIGN SYSTEM GÉNÉRIQUE : n’utilise PAS les jetons "theme:*" ni les valeurs par défaut du Design System (rayons 12/16, espacements 4/8px génériques). Reproduis AU PIXEL ET À LA COULEUR #HEX PRÈS la source fournie (.md Blueprint, HTML/CSS ou capture) :
  - Applique les valeurs exactes "mode", "accent", "styles['background'].color", couleurs #RRGGBB / #AARRGGBB (fonds, textes, bordures, ombres, boutons et hover), rayons (radius / radii), bordures (borderWidth / borderWidths / borderColor / borderLine), ombres (shadow), paddingInsets, marginInsets, spacing, fontSize, fontWeight, lineHeight et textAlign.
- QUESTIONNEMENT DÉSACTIVÉ : ne pose aucune question ("askUser": null obligatoire).
- MISE EN PAGE & PROPORTIONS SANS PROPRIÉTÉS INVENTÉES :
  - N’invente JAMAIS "colTracks" ni de CSS brut : traduis les lignes et colonnes via "zoneAxes" ("row"/"column") + "slotSizeConstraints" ("preferredWidth", "preferredHeight", "maxWidth", "minHeight", "fitContent") ou via "positioning": "grid" ("columns", "rowHeight", "gap", "items").
  - Si la page source est plus haute que le viewport (page web scrollable), configure le défilement vertical sans compresser ni étirer les sections ("root.bodyMode": "singleChildScrollView", ou "mainLayout.zoneFlows.center" avec "expandSlots": false, "scrollable": true, "showScrollbar": true, "autoSides": []).
  - Conserve le slot hôte "scaffold:body" dans "root.placements.body" et rattache tes conteneurs dans "mainLayout" (ou dans le scope ciblé).
- IMAGES, LOGOS & SVGs FIDÈLES :
  - Copie les URLs EXACTES (avec tous leurs paramètres) ou le code "<svg...>" inline de la source dans "styles[<cardId>].fill.imageUrl". Ne remplace jamais une image/URL de la source par une icône Material ou un texte placeholder.
  - Utilise "fill.imageFit": "contain" pour les logos/SVGs/visuels détourés et "cover" pour les photos/bannières.
  - Pour une Card purement visuelle sans enfant, déclare "color": "#00000000" (sauf fond explicite), "components[<cardId>]": {"type": "native", "regions": {"child": true}, "placements": {}} (JAMAIS "child": false) et dimensionne-la dans le "slotSizeConstraints[<cardId>]" de son parent.
  - Lorsque des textes ou contrôles se superposent sur une image/surface stylisée, utilise "registry:IterableContent" (même ID dans "styles" et dans "components" avec "type": "layout").''';

  /// Consigne de planification automatique en lots (Phase 1 du mode « Reproduire à l'identique »).
  static const String reproduceExactPlanningDirective = '''
PHASE 1 — PLANIFICATION EN LOTS OBLIGATOIRE :
- Avant de générer des composants "vibe", découpe la reproduction complète de la source en un plan ordonné de lots cohérents et autonomes afin de ne jamais dépasser la limite de sortie JSON ni dégrader la précision :
  - Lot 1 : Thème global ("mode", "accent", "styles['background']"), architecture de scroll/navigation, en-tête (header) et section Hero.
  - Lots intermédiaires : 1 à 2 sections visuelles, grilles de logos/cartes ou blocs fonctionnels par lot (avec toutes leurs URLs exactes).
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
    String? repositoriesContext,
  }) {
    final trimmedRepositories = repositoriesContext?.trim() ?? '';
    final repositoriesSection = trimmedRepositories.isEmpty
        ? null
        : (trimmedRepositories.startsWith('REPOSITORIES DISPONIBLES')
              ? trimmedRepositories
              : 'REPOSITORIES DISPONIBLES (JSON) :\n$trimmedRepositories');
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
      ?repositoriesSection,
      'ÉTAT ACTUEL DE L’ÉCRAN APRÈS LES LOTS PRÉCÉDENTS (JSON) :\n$current',
      sourceSection,
    ].join('\n\n');
  }
}
