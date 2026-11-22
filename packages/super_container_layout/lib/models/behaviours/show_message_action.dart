/// Action de comportement impérative affichant un retour utilisateur (toast /
/// SnackBar Material 3) via [ShowMessageAction].
///
/// Prend en charge un message statique ou une liaison réactive
/// ([JsonTextBinding]) résolue avec [JsonListScope.resolveSelected], un niveau
/// de sévérité ([BehaviorMessageSeverity]) et une durée d'affichage configurable.
library;

import 'dart:io' show FileSystemException;

import 'package:material_ui/material_ui.dart';

import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../component_behavior.dart';
import '../json_text_binding.dart';

/// Niveau de sévérité visuelle du message affiché par [ShowMessageAction].
enum BehaviorMessageSeverity {
  /// Message d'information standard.
  info('Information', Icons.info_outline),

  /// Confirmation de succès d'une opération.
  success('Succès', Icons.check_circle_outline),

  /// Message d'avertissement non bloquant.
  warning('Avertissement', Icons.warning_amber_outlined),

  /// Signalement d'une erreur.
  error('Erreur', Icons.error_outline);

  const BehaviorMessageSeverity(this.label, this.icon);

  /// Libellé français affiché dans l'éditeur.
  final String label;

  /// Icône Material associée à la sévérité.
  final IconData icon;

  /// Résout un nom JSON en [BehaviorMessageSeverity], ou `null` si inconnu.
  static BehaviorMessageSeverity? tryParse(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    for (final value in values) {
      if (value.name == trimmed) return value;
    }
    return null;
  }
}

/// Affiche un message utilisateur temporaire (`SnackBar`) lors d'un événement impératif.
@immutable
class ShowMessageAction extends BehaviorAction {
  /// Crée une action d'affichage de message utilisateur.
  const ShowMessageAction({
    this.message = '',
    this.binding,
    this.severity = BehaviorMessageSeverity.info,
    this.durationMs = 3000,
  });

  /// Texte statique affiché (ou repli si [binding] produit une valeur vide).
  final String message;

  /// Source réactive optionnelle du message dans un repository JSON.
  final JsonTextBinding? binding;

  /// Niveau visuel du message (`info`, `success`, `warning`, `error`).
  final BehaviorMessageSeverity severity;

  /// Durée d'affichage en millisecondes (strictement positive).
  final int durationMs;

  /// Valide la présence d'un message ou d'une liaison et la durée positive.
  void validate() {
    binding?.validate();
    if (binding == null && message.trim().isEmpty) {
      throw const FormatException(
        'Le message ou une liaison de message est requis pour showMessage.',
      );
    }
    if (durationMs <= 0) {
      throw const FormatException(
        'La durée (durationMs) de showMessage doit être strictement positive.',
      );
    }
  }

  @override
  String get type => 'showMessage';

  @override
  String get label => 'Afficher un message';

  @override
  String get description {
    final text = binding?.path ?? message.trim();
    return text.isEmpty ? severity.label : '${severity.label} : $text';
  }

  @override
  IconData get icon => severity.icon;

  @override
  Future<void> execute(BuildContext context) async {
    validate();
    final resolvedMessage = await _resolveMessage(context);
    if (resolvedMessage.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final colorScheme = Theme.of(context).colorScheme;
    final (backgroundColor, foregroundColor) = switch (severity) {
      BehaviorMessageSeverity.info => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      BehaviorMessageSeverity.success => (
        Colors.green.shade700,
        Colors.white,
      ),
      BehaviorMessageSeverity.warning => (
        Colors.amber.shade800,
        Colors.white,
      ),
      BehaviorMessageSeverity.error => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
    };

    messenger.showSnackBar(
      SnackBar(
        duration: Duration(milliseconds: durationMs),
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            Icon(severity.icon, color: foregroundColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                resolvedMessage,
                style: TextStyle(color: foregroundColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _resolveMessage(BuildContext context) async {
    final currentBinding = binding;
    if (currentBinding != null) {
      final store = context
          .getInheritedWidgetOfExactType<JsonRepositoryScope>()
          ?.store;
      final scope = context.getInheritedWidgetOfExactType<JsonListScope>();
      if (store != null) {
        try {
          final selected = JsonListScope.resolveSelected(
            currentBinding,
            scope,
            store,
          );
          final concrete = selected.binding;
          if (concrete != null) {
            final cached = store.peekAttribute(
              concrete,
              allowStringList: true,
            );
            final attr =
                cached ??
                await store.readAttribute(concrete, allowStringList: true);
            final resolved = attr.text.trim().isNotEmpty
                ? attr.text.trim()
                : (attr.value?.toString().trim() ?? '');
            if (resolved.isNotEmpty) return resolved;
          }
        } on FormatException {
          // Repli sur le message statique éventuel.
        } on FileSystemException {
          // Repli sur le message statique éventuel.
        }
      }
    }
    return message.trim();
  }

  /// Retourne une copie modifiée de cette action.
  ShowMessageAction copyWith({
    String? message,
    JsonTextBinding? binding,
    bool clearBinding = false,
    BehaviorMessageSeverity? severity,
    int? durationMs,
  }) => ShowMessageAction(
    message: message ?? this.message,
    binding: clearBinding ? null : (binding ?? this.binding),
    severity: severity ?? this.severity,
    durationMs: durationMs ?? this.durationMs,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'message': message,
      if (binding != null) 'binding': binding!.toJson(),
      'severity': severity.name,
      'durationMs': durationMs,
    };
  }

  /// Sérialisation JSON compacte pour GenUI.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'type': type,
      if (message.isNotEmpty) 'message': message,
      if (binding != null) 'binding': binding!.toCompactJson(),
      if (severity != BehaviorMessageSeverity.info) 'severity': severity.name,
      if (durationMs != 3000) 'durationMs': durationMs,
    };
  }

  /// Décode et valide une [ShowMessageAction] depuis JSON.
  factory ShowMessageAction.fromJson(Map<String, dynamic> json) {
    final rawMessage = json['message'];
    if (rawMessage != null && rawMessage is! String) {
      throw const FormatException(
        'Le champ "message" de showMessage doit être une chaîne.',
      );
    }
    final rawSeverity = json['severity'];
    BehaviorMessageSeverity severity;
    if (rawSeverity == null) {
      severity = BehaviorMessageSeverity.info;
    } else {
      severity =
          BehaviorMessageSeverity.tryParse(rawSeverity) ??
          (throw FormatException(
            'Sévérité inconnue dans showMessage : "$rawSeverity".',
          ));
    }
    final rawDuration = json['durationMs'];
    if (rawDuration != null && rawDuration is! int) {
      throw const FormatException(
        'Le champ "durationMs" de showMessage doit être un entier.',
      );
    }
    final action = ShowMessageAction(
      message: rawMessage as String? ?? '',
      binding: json['binding'] == null
          ? null
          : JsonTextBinding.fromJson(json['binding']),
      severity: severity,
      durationMs: rawDuration as int? ?? 3000,
    );
    action.validate();
    return action;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShowMessageAction &&
          other.message == message &&
          other.binding == binding &&
          other.severity == severity &&
          other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(message, binding, severity, durationMs);
}
