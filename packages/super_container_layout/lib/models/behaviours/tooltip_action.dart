/// Action de comportement déclarative d'info-bulle au survol ([TooltipAction]).
///
/// Supporte un texte statique ou une liaison réactive ([JsonTextBinding]) résolue
/// par `ComponentTooltip` lors du survol du composant.
library;

import 'package:material_ui/material_ui.dart';

import '../component_behavior.dart';
import '../json_text_binding.dart';

/// Info-bulle déclarative, commune à tous les types de composants.
@immutable
class TooltipAction extends BehaviorAction {
  const TooltipAction({this.message = '', this.binding});

  /// Texte utilisé uniquement lorsqu'aucune liaison n'est configurée.
  final String message;

  /// Source réactive du texte, éventuellement héritée de la ligne.
  final JsonTextBinding? binding;

  /// Vérifie le texte fixe ou la syntaxe de la liaison.
  void validate() {
    binding?.validate();
    if (binding == null && message.trim().isEmpty) {
      throw const FormatException('Le texte de l’info-bulle est requis.');
    }
  }

  @override
  String get type => 'onTooltip';
  @override
  String get label => 'Afficher une info-bulle';
  @override
  String get description => binding?.path ?? message;
  @override
  IconData get icon => Icons.info_outline;

  @override
  Future<void> execute(BuildContext context) async {
    throw StateError('TooltipAction is rendered by ComponentTooltip.');
  }

  /// Copie immuable ; permet aussi de supprimer la liaison.
  TooltipAction copyWith({
    String? message,
    JsonTextBinding? binding,
    bool clearBinding = false,
  }) => TooltipAction(
    message: message ?? this.message,
    binding: clearBinding ? null : binding ?? this.binding,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'message': message,
      if (binding != null) 'binding': binding!.toJson(),
    };
  }

  /// Forme compacte compatible avec les liaisons courtes.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'type': type,
      if (message.isNotEmpty) 'message': message,
      if (binding != null) 'binding': binding!.toCompactJson(),
    };
  }

  /// Décode et valide une info-bulle persistée.
  factory TooltipAction.fromJson(Map<String, dynamic> json) {
    final message = json['message'];
    if (message != null && message is! String) {
      throw const FormatException(
        'Le texte de l’info-bulle doit être un texte.',
      );
    }
    final result = TooltipAction(
      message: message as String? ?? '',
      binding: json['binding'] == null
          ? null
          : JsonTextBinding.fromJson(json['binding']),
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TooltipAction &&
          other.message == message &&
          other.binding == binding;

  @override
  int get hashCode => Object.hash(message, binding);
}
