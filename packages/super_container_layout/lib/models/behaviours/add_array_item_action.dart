/// Action de comportement ajoutant une nouvelle ligne dans un tableau JSON
/// ([AddArrayItemAction]) à partir du JSON Schema associé au repository et des
/// valeurs par défaut déclarées sur les `SuperValue`s via [CreationDefaultAction].
library;

import 'package:material_ui/material_ui.dart';

import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/repository_array_creation.dart';
import '../../widgets/appearance/appearance_scope.dart';
import '../component_behavior.dart';
import '../json_text_binding.dart';

/// Ajoute une nouvelle ligne dans le tableau JSON désigné par [binding] en
/// initialisant ses champs depuis le JSON Schema du repository puis les
/// éventuels comportements [CreationDefaultAction] des `SuperValue`s liées.
@immutable
class AddArrayItemAction extends BehaviorAction {
  /// Crée une action d'ajout de ligne dans le tableau [binding].
  const AddArrayItemAction({
    required this.binding,
    this.selectCreated = true,
  });

  /// Liaison vers le tableau cible (`repositoryId` + `path`, ex. `clients` ou
  /// `clients[?].commandes`).
  final JsonTextBinding binding;

  /// Sélectionne automatiquement la ligne créée dans le tableau (`true` par défaut).
  final bool selectCreated;

  /// Vérifie la syntaxe de la liaison cible.
  void validate() {
    binding.validate();
    if (binding.path.trim().isEmpty) {
      throw const FormatException(
        'Le chemin du tableau cible est obligatoire.',
      );
    }
    if (JsonTextBinding.isCalculatedPath(binding.path)) {
      throw const FormatException(
        'Impossible d’ajouter une ligne sur un attribut calculé (@).',
      );
    }
  }

  @override
  String get type => 'addArrayItem';

  @override
  String get label => 'Ajouter une ligne (JSON Schema)';

  @override
  String get description {
    final repo = binding.repositoryId?.trim();
    final target = repo != null && repo.isNotEmpty
        ? '$repo:${binding.path}'
        : binding.path;
    return 'Ajouter dans $target';
  }

  @override
  IconData get icon => Icons.playlist_add_outlined;

  @override
  Future<void> execute(BuildContext context) async {
    final store = JsonRepositoryScope.maybeOf(context);
    if (store == null) return;
    final scope = JsonListScope.maybeOf(context);
    final appearance = AppearanceScope.controllerOf(context)?.value;

    final resolved = JsonListScope.resolveSelected(binding, scope, store);
    final concreteBinding = resolved.binding;
    if (concreteBinding == null) return;
    final repoId = concreteBinding.repositoryId?.trim();
    if (repoId == null || repoId.isEmpty) return;

    try {
      await RepositoryArrayCreationService.appendSchemaRow(
        store: store,
        repositoryId: repoId,
        concreteArrayPath: concreteBinding.path,
        arrayTemplatePath: binding.path,
        appearance: appearance,
        parentIndices: resolved.indices,
        selectCreated: selectCreated,
      );
    } on FormatException catch (error) {
      store.reportBindingError(error.message);
    }
  }

  /// Retourne une copie modifiée de cette action.
  AddArrayItemAction copyWith({
    JsonTextBinding? binding,
    bool? selectCreated,
  }) => AddArrayItemAction(
    binding: binding ?? this.binding,
    selectCreated: selectCreated ?? this.selectCreated,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'type': type,
      'binding': binding.toJson(),
      if (!selectCreated) 'selectCreated': false,
    };
  }

  /// Sérialisation compacte pour le JSON GenUI.
  Map<String, Object?> toCompactJson() {
    validate();
    return <String, Object?>{
      'type': type,
      'binding': binding.toCompactJson(),
      if (!selectCreated) 'selectCreated': false,
    };
  }

  /// Décode une instance depuis une carte JSON.
  factory AddArrayItemAction.fromJson(Map<String, dynamic> json) {
    final rawSelect = json['selectCreated'];
    if (rawSelect != null && rawSelect is! bool) {
      throw const FormatException(
        'selectCreated doit être un booléen dans addArrayItem.',
      );
    }
    return AddArrayItemAction(
      binding: JsonTextBinding.fromJson(json['binding']),
      selectCreated: (rawSelect as bool?) ?? true,
    )..validate();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddArrayItemAction &&
          other.binding == binding &&
          other.selectCreated == selectCreated;

  @override
  int get hashCode => Object.hash(binding, selectCreated);
}
