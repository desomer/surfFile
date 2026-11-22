/// Action de comportement supprimant un élément d'un tableau JSON
/// ([RemoveArrayItemAction]) avec confirmation optionnelle et mise à jour
/// de la sélection adjacente dans `JsonRepositoryBinding`.
library;

import 'package:material_ui/material_ui.dart';

import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../component_behavior.dart';
import '../json_text_binding.dart';

/// Supprime un élément d'un tableau JSON désigné par [binding] (chemin vers le
/// tableau tel que `clients` / `clients[?].commandes`, ou vers l'élément tel que
/// `clients[?]` / `clients[0]`).
@immutable
class RemoveArrayItemAction extends BehaviorAction {
  /// Crée une action de suppression d'élément dans le tableau [binding].
  const RemoveArrayItemAction({
    required this.binding,
    this.confirm = false,
    this.confirmTitle,
    this.confirmMessage,
    this.selectAdjacent = true,
  });

  /// Liaison vers le tableau ou l'élément cible (`clients`, `clients[?]`,
  /// `clients[?].commandes`, etc.).
  final JsonTextBinding binding;

  /// Demande une confirmation modale avant suppression (`false` par défaut).
  final bool confirm;

  /// Titre personnalisé du dialogue de confirmation (utilisé si [confirm] vaut `true`).
  final String? confirmTitle;

  /// Message personnalisé du dialogue de confirmation (utilisé si [confirm] vaut `true`).
  final String? confirmMessage;

  /// Sélectionne l'élément adjacent après suppression (`true` par défaut), ou
  /// efface la sélection lorsque le tableau devient vide.
  final bool selectAdjacent;

  /// Vérifie la syntaxe de la liaison cible.
  void validate() {
    binding.validate();
    final trimmed = binding.path.trim();
    if (trimmed.isEmpty) {
      throw const FormatException(
        'Le chemin du tableau cible est obligatoire.',
      );
    }
    if (JsonTextBinding.isCalculatedPath(trimmed)) {
      throw const FormatException(
        'Impossible de supprimer un élément sur un attribut calculé (@).',
      );
    }
  }

  @override
  String get type => 'removeArrayItem';

  @override
  String get label => 'Supprimer la ligne';

  @override
  String get description {
    final repo = binding.repositoryId?.trim();
    final target = repo != null && repo.isNotEmpty
        ? '$repo:${binding.path}'
        : binding.path;
    return 'Supprimer dans $target';
  }

  @override
  IconData get icon => Icons.delete_outline;

  @override
  Future<void> execute(BuildContext context) => _execute(context);

  @override
  Future<void> executeWithData(
    BuildContext context,
    BehaviorExecutionData data,
  ) => _execute(context, componentId: data.componentId);

  Future<void> _execute(BuildContext context, {String? componentId}) async {
    validate();
    final store = JsonRepositoryScope.maybeOf(context);
    if (store == null) return;
    final scope = JsonListScope.maybeOf(context);
    if (scope?.placeholder == true) return;

    try {
      final target = _resolveTarget(binding, scope, store);
      if (target == null) return;

      await store.flushBindings();
      final items = await store.readArray(
        target.repositoryId,
        target.concreteArrayPath,
      );
      if (target.index < 0 || target.index >= items.length) return;

      if (confirm) {
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              confirmTitle != null && confirmTitle!.trim().isNotEmpty
                  ? confirmTitle!.trim()
                  : 'Confirmer la suppression',
            ),
            content: Text(
              confirmMessage != null && confirmMessage!.trim().isNotEmpty
                  ? confirmMessage!.trim()
                  : 'Voulez-vous supprimer cet élément ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
      }

      final nextLength = await store.removeArrayItem(
        target.repositoryId,
        target.concreteArrayPath,
        target.index,
        expectedItem: items[target.index],
        componentId: componentId,
      );

      final repoBinding = store.bindingOf(target.repositoryId);
      repoBinding.removed(
        target.arrayTemplate,
        target.parentIndices,
        target.index,
      );

      if (selectAdjacent) {
        final arrayBinding = repoBinding.array(target.arrayTemplate);
        if (nextLength > 0) {
          final nextIndex = target.index < nextLength
              ? target.index
              : nextLength - 1;
          arrayBinding.select(target.parentIndices, nextIndex);
        } else {
          arrayBinding.clear();
        }
      }
    } on FormatException catch (error) {
      store.reportBindingError(error.message);
    }
  }

  static ({
    String repositoryId,
    String concreteArrayPath,
    String arrayTemplate,
    List<int> parentIndices,
    int index,
  })?
  _resolveTarget(
    JsonTextBinding binding,
    JsonListScope? scope,
    JsonRepositoryStore store,
  ) {
    final parsed = JsonAttributePath(binding.path.trim());
    final steps = parsed.steps;
    if (steps.isEmpty) return null;

    final last = steps.last;
    if (last.isWildcard) {
      if (steps.length < 2) {
        throw const FormatException(
          'Chemin de suppression invalide : tableau parent manquant.',
        );
      }
      final rawArrayPath = parsed.arrayTemplates.last;
      final arrayTemplate = JsonAttributePath(rawArrayPath).toString();
      final arrayResolved = JsonListScope.resolveSelected(
        JsonTextBinding(repositoryId: binding.repositoryId, path: rawArrayPath),
        scope,
        store,
      );
      final concreteArrayBinding = arrayResolved.binding;
      if (concreteArrayBinding == null) return null;

      final itemResolved = JsonListScope.resolveSelected(binding, scope, store);
      if (itemResolved.binding == null || itemResolved.indices.isEmpty) {
        return null;
      }
      final repoId = concreteArrayBinding.repositoryId?.trim();
      if (repoId == null || repoId.isEmpty) return null;

      return (
        repositoryId: repoId,
        concreteArrayPath: concreteArrayBinding.path,
        arrayTemplate: arrayTemplate,
        parentIndices: arrayResolved.indices,
        index: itemResolved.indices.last,
      );
    }

    if (last.index != null) {
      if (steps.length < 2) {
        throw const FormatException(
          'Chemin de suppression invalide : tableau parent manquant.',
        );
      }
      final rawArrayPath = _formatSteps(steps.sublist(0, steps.length - 1));
      final arrayTemplate = JsonAttributePath(rawArrayPath).toString();
      final arrayResolved = JsonListScope.resolveSelected(
        JsonTextBinding(repositoryId: binding.repositoryId, path: rawArrayPath),
        scope,
        store,
      );
      final concreteArrayBinding = arrayResolved.binding;
      if (concreteArrayBinding == null) return null;
      final repoId = concreteArrayBinding.repositoryId?.trim();
      if (repoId == null || repoId.isEmpty) return null;

      return (
        repositoryId: repoId,
        concreteArrayPath: concreteArrayBinding.path,
        arrayTemplate: arrayTemplate,
        parentIndices: arrayResolved.indices,
        index: last.index!,
      );
    }

    final arrayTemplate = parsed.toString();
    final arrayResolved = JsonListScope.resolveSelected(
      JsonTextBinding(repositoryId: binding.repositoryId, path: arrayTemplate),
      scope,
      store,
    );
    final concreteArrayBinding = arrayResolved.binding;
    if (concreteArrayBinding == null) return null;
    final repoId = concreteArrayBinding.repositoryId?.trim();
    if (repoId == null || repoId.isEmpty) return null;

    final parentIndices = arrayResolved.indices;
    final arrayWildcardCount = parsed.wildcardCount;
    final scopeRepo = scope?.repositoryId?.trim();
    final sameRepo =
        scopeRepo == null || scopeRepo.isEmpty || scopeRepo == repoId;
    final scopeTemplate = scope?.arrayTemplate;
    final matchesScopeTemplate =
        scopeTemplate == null ||
        scopeTemplate == arrayTemplate ||
        scopeTemplate.startsWith('$arrayTemplate[?].') ||
        scopeTemplate.startsWith('$arrayTemplate[?][');

    final int? index;
    if (scope != null &&
        !scope.placeholder &&
        sameRepo &&
        matchesScopeTemplate &&
        scope.indices.length > arrayWildcardCount) {
      index = scope.indices[arrayWildcardCount];
    } else {
      index = store
          .bindingOf(repoId)
          .array(arrayTemplate)
          .indexFor(parentIndices);
    }
    if (index == null) return null;

    return (
      repositoryId: repoId,
      concreteArrayPath: concreteArrayBinding.path,
      arrayTemplate: arrayTemplate,
      parentIndices: parentIndices,
      index: index,
    );
  }

  static String _formatSteps(
    List<({String? key, int? index, bool isWildcard})> steps,
  ) {
    final buffer = StringBuffer();
    for (final step in steps) {
      if (step.key != null) {
        if (buffer.isNotEmpty) buffer.write('.');
        buffer.write(step.key);
      } else if (step.isWildcard) {
        buffer.write('[?]');
      } else if (step.index != null) {
        buffer.write('[${step.index}]');
      }
    }
    return buffer.toString();
  }

  /// Retourne une copie modifiée de cette action.
  RemoveArrayItemAction copyWith({
    JsonTextBinding? binding,
    bool? confirm,
    String? confirmTitle,
    bool clearConfirmTitle = false,
    String? confirmMessage,
    bool clearConfirmMessage = false,
    bool? selectAdjacent,
  }) => RemoveArrayItemAction(
    binding: binding ?? this.binding,
    confirm: confirm ?? this.confirm,
    confirmTitle: clearConfirmTitle
        ? null
        : (confirmTitle ?? this.confirmTitle),
    confirmMessage: clearConfirmMessage
        ? null
        : (confirmMessage ?? this.confirmMessage),
    selectAdjacent: selectAdjacent ?? this.selectAdjacent,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'type': type,
      'binding': binding.toJson(),
      if (confirm) 'confirm': true,
      if (confirmTitle != null && confirmTitle!.trim().isNotEmpty)
        'confirmTitle': confirmTitle!.trim(),
      if (confirmMessage != null && confirmMessage!.trim().isNotEmpty)
        'confirmMessage': confirmMessage!.trim(),
      if (!selectAdjacent) 'selectAdjacent': false,
    };
  }

  /// Sérialisation compacte pour le JSON GenUI.
  Map<String, Object?> toCompactJson() {
    validate();
    return <String, Object?>{
      'type': type,
      'binding': binding.toCompactJson(),
      if (confirm) 'confirm': true,
      if (confirmTitle != null && confirmTitle!.trim().isNotEmpty)
        'confirmTitle': confirmTitle!.trim(),
      if (confirmMessage != null && confirmMessage!.trim().isNotEmpty)
        'confirmMessage': confirmMessage!.trim(),
      if (!selectAdjacent) 'selectAdjacent': false,
    };
  }

  /// Décode une instance depuis une carte JSON.
  factory RemoveArrayItemAction.fromJson(Map<String, dynamic> json) {
    final rawConfirm = json['confirm'];
    if (rawConfirm != null && rawConfirm is! bool) {
      throw const FormatException(
        'confirm doit être un booléen dans removeArrayItem.',
      );
    }
    final rawTitle = json['confirmTitle'];
    if (rawTitle != null && rawTitle is! String) {
      throw const FormatException(
        'confirmTitle doit être une chaîne dans removeArrayItem.',
      );
    }
    final rawMessage = json['confirmMessage'];
    if (rawMessage != null && rawMessage is! String) {
      throw const FormatException(
        'confirmMessage doit être une chaîne dans removeArrayItem.',
      );
    }
    final rawSelectAdjacent = json['selectAdjacent'];
    if (rawSelectAdjacent != null && rawSelectAdjacent is! bool) {
      throw const FormatException(
        'selectAdjacent doit être un booléen dans removeArrayItem.',
      );
    }
    return RemoveArrayItemAction(
      binding: JsonTextBinding.fromJson(json['binding']),
      confirm: (rawConfirm as bool?) ?? false,
      confirmTitle: rawTitle as String?,
      confirmMessage: rawMessage as String?,
      selectAdjacent: (rawSelectAdjacent as bool?) ?? true,
    )..validate();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoveArrayItemAction &&
          other.binding == binding &&
          other.confirm == confirm &&
          other.confirmTitle == confirmTitle &&
          other.confirmMessage == confirmMessage &&
          other.selectAdjacent == selectAdjacent;

  @override
  int get hashCode => Object.hash(
    binding,
    confirm,
    confirmTitle,
    confirmMessage,
    selectAdjacent,
  );
}
