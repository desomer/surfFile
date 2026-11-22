/// Action de comportement de retour arrière ou fermeture ([GoBackAction]).
///
/// Dépile la route ou le dialogue actif via [Navigator], [SuperApp] ou
/// [GoRouter], et navigue optionnellement vers [fallbackPagePath] lorsqu'aucune
/// pile de retour n'est disponible.
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../super_app.dart';
import '../component_behavior.dart';

/// Action de retour à l'écran précédent (ou de redirection vers [fallbackPagePath]).
@immutable
class GoBackAction extends BehaviorAction {
  /// Crée une action de retour arrière avec un chemin de repli optionnel.
  const GoBackAction({this.fallbackPagePath});

  /// Chemin de repli utilisé si aucun écran ou dialogue ne peut être dépilé.
  final String? fallbackPagePath;

  /// Vérifie que [fallbackPagePath], s'il est renseigné, est non vide et sans
  /// espaces superflus.
  void validate() {
    if (fallbackPagePath != null) {
      final trimmed = fallbackPagePath!.trim();
      if (trimmed.isEmpty || trimmed != fallbackPagePath) {
        throw const FormatException(
          'fallbackPagePath de goBack ne peut pas être vide ni contenir d’espaces superflus.',
        );
      }
    }
  }

  @override
  String get type => 'goBack';

  @override
  String get label => 'Revenir / Fermer';

  @override
  String get description {
    final fallback = fallbackPagePath?.trim();
    if (fallback != null && fallback.isNotEmpty) {
      return 'Revenir / Fermer (sinon $fallback)';
    }
    return 'Revenir à la page précédente ou fermer';
  }

  @override
  IconData get icon => Icons.arrow_back;

  @override
  Future<void> execute(BuildContext context) async {
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.pop();
      return;
    }

    final app = SuperApp.maybeOf(context);
    if (app?.pageRouting?.router.canPop() == true) {
      app!.pageRouting!.router.pop();
      return;
    }
    if (app != null && app.router.canPop()) {
      app.router.pop();
      return;
    }

    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
      return;
    }

    final fallback = fallbackPagePath?.trim();
    if (fallback == null || fallback.isEmpty) return;

    if (app?.pageRouting != null) {
      app!.pageRouting!.router.go(fallback);
      return;
    }
    if (app != null) {
      app.router.go(fallback);
      return;
    }
    router?.go(fallback);
  }

  /// Retourne une copie modifiée de cette action.
  GoBackAction copyWith({
    String? fallbackPagePath,
    bool clearFallbackPagePath = false,
  }) => GoBackAction(
    fallbackPagePath: clearFallbackPagePath
        ? null
        : (fallbackPagePath ?? this.fallbackPagePath),
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'type': type,
      if (fallbackPagePath != null) 'fallbackPagePath': fallbackPagePath,
    };
  }

  /// Sérialisation compacte pour le JSON GenUI.
  Map<String, Object?> toCompactJson() => toJson();

  /// Décode une instance depuis une carte JSON.
  factory GoBackAction.fromJson(Map<String, dynamic> json) {
    final rawFallback = json['fallbackPagePath'] ?? json['fallbackPath'];
    if (rawFallback != null && rawFallback is! String) {
      throw const FormatException(
        'Le champ "fallbackPagePath" de goBack doit être une chaîne.',
      );
    }
    return GoBackAction(fallbackPagePath: rawFallback as String?)..validate();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoBackAction && other.fallbackPagePath == fallbackPagePath;

  @override
  int get hashCode => fallbackPagePath.hashCode;
}
