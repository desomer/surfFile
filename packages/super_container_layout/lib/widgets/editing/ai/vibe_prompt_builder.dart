/// Assemble l'historique et le prompt Vibe à partir de l'état courant.
library;

import 'dart:convert';

import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/appearance_transfer.dart';
import '../../../theme/appearance.dart';
import '../slots/editor_context_menu.dart';
import 'vibe_chat_message.dart';
import 'vibe_scope_helpers.dart';

/// Construit les entrées de conversation et le contexte envoyé à Vibe.
abstract final class VibePromptBuilder {
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
  /// des repositories JSON ([repositoriesContext]) et de la portée choisie ([scope]).
  static String buildTurnPrompt({
    required String questioningDirective,
    required String conversation,
    required Appearance appearance,
    required AppearanceCodec codec,
    required VibeChatScope? scope,
    Iterable<String>? instantiatedComponentIds,
    String? repositoriesContext,
  }) {
    final trimmedRepositories = repositoriesContext?.trim() ?? '';
    final repositoriesSection = trimmedRepositories.isEmpty
        ? null
        : (trimmedRepositories.startsWith('REPOSITORIES DISPONIBLES')
              ? trimmedRepositories
              : 'REPOSITORIES DISPONIBLES (JSON) :\n$trimmedRepositories');

    if (scope != null) {
      final parentIds = VibeScopeHelpers.parentIdsOfScope(appearance, scope);
      final parentList = parentIds.map((id) => '"$id"').join(', ');
      final effectiveParent = parentIds.isNotEmpty
          ? parentList
          : '"${scope.canonicalComponentId}"';
      return [
        questioningDirective,
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
      if (instantiatedComponentIds != null)
        'Les composants instanciés sont : ${jsonEncode(instantiatedComponentIds.toList())}. '
            'Rattache les modifications à ces composants ou aux pages déclarées ; '
            'une configuration sauvegardée mais isolée ne suffit pas.',
      ?repositoriesSection,
      'ÉTAT ACTUEL (JSON) :\n$current',
      'CONVERSATION :\n$conversation',
    ].join('\n\n');
  }
}
