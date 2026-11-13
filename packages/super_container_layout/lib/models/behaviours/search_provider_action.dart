/// Action de comportement qui lance la recherche d'un provider ([SearchProviderAction]).
///
/// Au déclenchement, appelle `JsonRepositoryStore.providers.search` : le
/// provider lit son repository de filtre, interroge sa source (API HTTP, code
/// hôte) puis alimente son repository cible.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../services/repositories/json_repository_scope.dart';
import '../component_behavior.dart';
import '../providers/data_provider.dart';

/// Lance la recherche du provider [providerId].
///
/// Seul l'identifiant est stocké dans l'apparence : le provider lui-même est
/// déclaré dans le code hôte ou créé dans l'éditeur de providers.
@immutable
class SearchProviderAction extends BehaviorAction {
  /// Crée une action de recherche pour le provider [providerId].
  const SearchProviderAction({required this.providerId});

  /// Identifiant du provider (`store.providers`).
  final String providerId;

  /// Vérifie l'identifiant du provider.
  void validate() {
    if (!isValidDataProviderId(providerId)) {
      throw const FormatException(
        'L’identifiant du provider doit utiliser a-z, 0-9 et _ '
        '(32 caractères au plus).',
      );
    }
  }

  @override
  String get type => 'searchProvider';

  @override
  String get label => 'Lancer la recherche';

  @override
  String get description => 'Provider $providerId';

  @override
  IconData get icon => Icons.manage_search_outlined;

  /// Lance la recherche sans l'attendre ; son échec est signalé par le store
  /// et les indicateurs du provider, jamais par une exception.
  @override
  Future<void> execute(BuildContext context) async {
    final store = JsonRepositoryScope.maybeOf(context);
    if (store == null) return;
    unawaited(store.providers.search(providerId));
  }

  /// Copie immuable de l'action.
  SearchProviderAction copyWith({String? providerId}) =>
      SearchProviderAction(providerId: providerId ?? this.providerId);

  @override
  Map<String, Object?> toJson() {
    validate();
    return {'type': type, 'providerId': providerId};
  }

  /// Forme compacte (identique : l'action ne contient aucune liaison).
  Map<String, Object?> toCompactJson() => toJson();

  /// Décode et valide une [SearchProviderAction] persistée.
  factory SearchProviderAction.fromJson(Map<String, dynamic> json) {
    for (final key in json.keys) {
      if (key != 'type' && key != 'providerId') {
        throw FormatException('Clé inconnue pour searchProvider : "$key".');
      }
    }
    final providerId = json['providerId'];
    if (providerId is! String) {
      throw const FormatException(
        'L’identifiant du provider de recherche est requis.',
      );
    }
    final result = SearchProviderAction(providerId: providerId);
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchProviderAction && other.providerId == providerId;

  @override
  int get hashCode => providerId.hashCode;
}
