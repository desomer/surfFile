/// Action de comportement impérative copiant une valeur textuelle dans le
/// presse-papiers système ([CopyToClipboardAction]).
///
/// Accepte exactement une source mutuellement exclusive :
/// - texte statique ([text]) ;
/// - valeur runtime courante d'un composant ([targetComponentId]) via
///   [ComponentRuntimeValueRegistry] ou [Appearance] ;
/// - liaison réactive JSON ([binding]) via [JsonListScope.resolveSelected].
library;

import 'dart:io' show FileSystemException;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import '../../services/behaviors/component_runtime_value_registry.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../widgets/appearance/appearance_scope.dart';
import '../component_behavior.dart';
import '../json_text_binding.dart';
import '../super_value_config.dart';

/// Copie une chaîne statique, la valeur d'un composant ou d'une liaison dans le presse-papiers.
@immutable
class CopyToClipboardAction extends BehaviorAction {
  /// Crée une action de copie vers le presse-papiers.
  const CopyToClipboardAction({
    this.text,
    this.targetComponentId,
    this.binding,
    this.feedbackMessage,
  });

  /// Texte statique à copier dans le presse-papiers.
  final String? text;

  /// Identifiant d'un composant monté ou configuré dont la valeur est copiée.
  final String? targetComponentId;

  /// Liaison JSON dont la valeur résolue est copiée.
  final JsonTextBinding? binding;

  /// Message optionnel affiché dans une `SnackBar` après la copie.
  final String? feedbackMessage;

  /// Vérifie qu'une et une seule source valide est configurée.
  void validate() {
    final hasText = text != null;
    final hasTarget = targetComponentId != null;
    final hasBinding = binding != null;
    final sourceCount =
        (hasText ? 1 : 0) + (hasTarget ? 1 : 0) + (hasBinding ? 1 : 0);
    if (sourceCount != 1) {
      throw const FormatException(
        'copyToClipboard exige exactement une source parmi text, targetComponentId ou binding.',
      );
    }
    if (hasText && text!.isEmpty) {
      throw const FormatException(
        'Le champ "text" de copyToClipboard ne peut pas être vide.',
      );
    }
    if (hasTarget) {
      final trimmed = targetComponentId!.trim();
      if (trimmed.isEmpty || trimmed != targetComponentId) {
        throw const FormatException(
          'L’identifiant targetComponentId de copyToClipboard ne peut pas être vide ni contenir d’espaces superflus.',
        );
      }
    }
    binding?.validate();
  }

  @override
  String get type => 'copyToClipboard';

  @override
  String get label => 'Copier dans le presse-papiers';

  @override
  String get description {
    if (text != null) return 'Copier "$text"';
    if (targetComponentId != null) return 'Copier la valeur de $targetComponentId';
    if (binding != null) return 'Copier ${binding!.path}';
    return label;
  }

  @override
  IconData get icon => Icons.content_copy_outlined;

  @override
  Set<String> get referencedComponentIds =>
      targetComponentId == null ? const {} : {targetComponentId!};

  @override
  BehaviorAction remapComponentIds(Map<String, String> idMap) {
    final target = targetComponentId;
    if (target == null) return this;
    final remapped = idMap[target];
    if (remapped == null || remapped == target) return this;
    return copyWith(targetComponentId: remapped);
  }

  @override
  Future<void> execute(BuildContext context) => _executeCopy(context);

  @override
  Future<void> executeWithData(
    BuildContext context,
    BehaviorExecutionData data,
  ) => _executeCopy(context);

  Future<void> _executeCopy(BuildContext context) async {
    validate();
    final resolved = await _resolveText(context);
    if (resolved == null) return;

    await Clipboard.setData(ClipboardData(text: resolved));
    final feedback = feedbackMessage?.trim();
    if (feedback != null && feedback.isNotEmpty && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2000),
          content: Text(feedback),
        ),
      );
    }
  }

  Future<String?> _resolveText(BuildContext context) async {
    if (text != null) return text!;

    if (binding != null) {
      return _readBindingText(context, binding!, allowStringList: true);
    }

    final targetId = targetComponentId;
    if (targetId == null) return null;

    final scope = context.getInheritedWidgetOfExactType<JsonListScope>();
    final scopeKey = ComponentRuntimeValueRegistry.scopeKeyOf(scope);
    final entry = ComponentRuntimeValueRegistry.instance.resolve(
      targetId,
      preferredScopeKey: scopeKey,
    );
    if (entry != null) {
      return _stringifyValue(entry.readValue()) ?? '';
    }

    final appearance = context
        .getInheritedWidgetOfExactType<AppearanceScope>()
        ?.notifier
        ?.value;
    final config = appearance?.components[targetId];
    if (config is SuperValueConfig) {
      if (config.binding != null) {
        return _readBindingText(
          context,
          config.binding!,
          allowStringList:
              config.kind.isChoice && config.choice.variant.isMultiple,
        );
      }
      return config.kind.isBoolean
          ? config.initialBool.toString()
          : config.initialText;
    }
    return null;
  }

  Future<String?> _readBindingText(
    BuildContext context,
    JsonTextBinding sourceBinding, {
    bool allowStringList = false,
  }) async {
    final store = context
        .getInheritedWidgetOfExactType<JsonRepositoryScope>()
        ?.store;
    if (store == null) return null;
    final scope = context.getInheritedWidgetOfExactType<JsonListScope>();
    try {
      final selected = JsonListScope.resolveSelected(
        sourceBinding,
        scope,
        store,
      );
      final concrete = selected.binding;
      if (concrete == null) return null;
      final cached = store.peekAttribute(
        concrete,
        allowStringList: allowStringList,
      );
      final attr =
          cached ??
          await store.readAttribute(
            concrete,
            allowStringList: allowStringList,
          );
      if (attr.text.isNotEmpty) return attr.text;
      return _stringifyValue(attr.value) ?? '';
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static String? _stringifyValue(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Iterable) {
      return value.map((item) => item?.toString() ?? '').join(', ');
    }
    return value.toString();
  }

  /// Retourne une copie modifiée de cette action.
  CopyToClipboardAction copyWith({
    String? text,
    bool clearText = false,
    String? targetComponentId,
    bool clearTargetComponentId = false,
    JsonTextBinding? binding,
    bool clearBinding = false,
    String? feedbackMessage,
    bool clearFeedbackMessage = false,
  }) => CopyToClipboardAction(
    text: clearText ? null : (text ?? this.text),
    targetComponentId: clearTargetComponentId
        ? null
        : (targetComponentId ?? this.targetComponentId),
    binding: clearBinding ? null : (binding ?? this.binding),
    feedbackMessage: clearFeedbackMessage
        ? null
        : (feedbackMessage ?? this.feedbackMessage),
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      if (text != null) 'text': text,
      if (targetComponentId != null) 'targetComponentId': targetComponentId,
      if (binding != null) 'binding': binding!.toJson(),
      if (feedbackMessage != null) 'feedbackMessage': feedbackMessage,
    };
  }

  /// Sérialisation JSON compacte pour GenUI.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'type': type,
      if (text != null) 'text': text,
      if (targetComponentId != null) 'targetComponentId': targetComponentId,
      if (binding != null) 'binding': binding!.toCompactJson(),
      if (feedbackMessage != null && feedbackMessage!.trim().isNotEmpty)
        'feedbackMessage': feedbackMessage,
    };
  }

  /// Décode et valide une [CopyToClipboardAction] depuis JSON.
  factory CopyToClipboardAction.fromJson(Map<String, dynamic> json) {
    final rawText = json['text'];
    if (rawText != null && rawText is! String) {
      throw const FormatException(
        'Le champ "text" de copyToClipboard doit être une chaîne.',
      );
    }
    final rawTarget = json['targetComponentId'];
    if (rawTarget != null && rawTarget is! String) {
      throw const FormatException(
        'Le champ "targetComponentId" de copyToClipboard doit être une chaîne.',
      );
    }
    final rawFeedback = json['feedbackMessage'];
    if (rawFeedback != null && rawFeedback is! String) {
      throw const FormatException(
        'Le champ "feedbackMessage" de copyToClipboard doit être une chaîne.',
      );
    }
    final action = CopyToClipboardAction(
      text: rawText as String?,
      targetComponentId: rawTarget as String?,
      binding: json['binding'] == null
          ? null
          : JsonTextBinding.fromJson(json['binding']),
      feedbackMessage: rawFeedback as String?,
    );
    action.validate();
    return action;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CopyToClipboardAction &&
          other.text == text &&
          other.targetComponentId == targetComponentId &&
          other.binding == binding &&
          other.feedbackMessage == feedbackMessage;

  @override
  int get hashCode =>
      Object.hash(text, targetComponentId, binding, feedbackMessage);
}
