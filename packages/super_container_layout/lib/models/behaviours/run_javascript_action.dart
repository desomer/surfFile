/// Action JavaScript explicite d'un comportement, avec écritures validées par
/// le store de repositories et sans accès en écriture aux attributs calculés.
library;

import 'package:material_ui/material_ui.dart';

import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../component_behavior.dart';

/// Exécute un script JavaScript qui peut modifier des valeurs JSON via
/// `ctx.set(path, value)`.
@immutable
class RunJavaScriptAction extends BehaviorAction {
  /// Crée une action JavaScript, éventuellement liée à un repository explicite.
  const RunJavaScriptAction({required this.code, this.repositoryId});

  /// Code exécuté au déclenchement du comportement.
  final String code;

  /// Repository ciblé, ou `null` pour hériter de la liste englobante.
  final String? repositoryId;

  /// Vérifie le code et l'identifiant de repository facultatif.
  void validate() {
    if (code.trim().isEmpty) {
      throw const FormatException(
        'Le script JavaScript ne peut pas être vide.',
      );
    }
    final id = repositoryId?.trim();
    if (id != null && id.isNotEmpty) {
      if (id != repositoryId || !RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(id)) {
        throw const FormatException('ID de repository invalide.');
      }
    }
  }

  @override
  String get type => 'runJavaScript';

  @override
  String get label => 'Exécuter un script JavaScript';

  @override
  String get description {
    final id = repositoryId?.trim();
    return id == null || id.isEmpty
        ? 'Script JavaScript (repository de la liste)'
        : 'Script JavaScript ($id)';
  }

  @override
  IconData get icon => Icons.code;

  /// Exécute le script avec le repository hérité du contexte de liste.
  @override
  Future<void> execute(BuildContext context) => _execute(context, const {});

  /// Exécute le script avec les données de l'événement déclencheur.
  @override
  Future<void> executeWithData(
    BuildContext context,
    BehaviorExecutionData data,
  ) => _execute(context, {
    'componentId': data.componentId,
    'componentType': data.componentType,
    'event': data.event.name,
    'trigger': data.event.legacyTriggerName,
    'data': data.data,
  }, componentId: data.componentId);

  Future<void> _execute(
    BuildContext context,
    Map<String, Object?> eventData, {
    String? componentId,
  }) async {
    validate();
    final store = JsonRepositoryScope.maybeOf(context);
    if (store == null) {
      throw const FormatException(
        'Aucun store de repositories n’est disponible pour le script.',
      );
    }
    final scope = JsonListScope.maybeOf(context);
    final id = repositoryId?.trim().isNotEmpty == true
        ? repositoryId!.trim()
        : scope?.repositoryId;
    if (id == null || id.isEmpty) {
      store.reportBindingError(
        'Choisissez un repository pour le comportement JavaScript.',
      );
      return;
    }
    try {
      await store.runJavaScriptAction(
        repositoryId: id,
        code: code,
        scope: scope,
        eventData: eventData,
        componentId: componentId,
      );
    } on FormatException catch (error) {
      store.reportBindingError(error.message);
    }
  }

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'code': code,
      if (repositoryId?.trim().isNotEmpty == true)
        'repositoryId': repositoryId!.trim(),
    };
  }

  /// Décode une instance depuis une carte JSON.
  factory RunJavaScriptAction.fromJson(Map<String, dynamic> json) {
    final code = json['code'];
    final repositoryId = json['repositoryId'];
    if (code is! String || (repositoryId != null && repositoryId is! String)) {
      throw const FormatException(
        'code et repositoryId doivent être des chaînes pour runJavaScript.',
      );
    }
    return RunJavaScriptAction(
      code: code,
      repositoryId: repositoryId as String?,
    )..validate();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunJavaScriptAction &&
          other.code == code &&
          other.repositoryId == repositoryId;

  @override
  int get hashCode => Object.hash(code, repositoryId);
}
