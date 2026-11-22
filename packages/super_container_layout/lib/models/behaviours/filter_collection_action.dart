/// Action de comportement permettant de filtrer un [SuperListView] ou un [SuperTable]
/// ([FilterCollectionAction]) à l'aide d'un [BehaviorValidator].
///
/// Fonctionne en deux modes :
/// - **Déclaratif (`BehaviorEvent.onBinding`)** : attaché directement au composant
///   collection (`SuperListView` / `SuperTable`). Si [predicate] est renseigné,
///   il est évalué **par ligne** dans son `JsonListScope` tandis que le `validator`
///   éventuel du [ComponentBehavior] sert de condition d'activation globale du filtre.
///   Si [predicate] est omis, le `validator` du [ComponentBehavior] est directement
///   évalué comme prédicat par ligne.
/// - **Impératif (`onTap`, `onChanged`, `onSubmitted`, etc.)** : déclenché depuis
///   n'importe quel composant en ciblant la collection via [targetComponentId], avec
///   support des modes `apply`, `toggle`, `clear` (par [filterKey]) et `clearAll`.
library;

import 'package:material_ui/material_ui.dart';

import '../../services/behaviors/collection_view_state_registry.dart';
import '../component_behavior.dart';

/// Mode d'application d'une [FilterCollectionAction] sur la collection cible.
enum CollectionFilterMode {
  /// Applique (ou remplace) le filtre identifié par [FilterCollectionAction.filterKey].
  apply('Appliquer le filtre'),

  /// Active le filtre s'il est absent, ou le retire s'il est déjà actif sur cette clé.
  toggle('Basculer le filtre'),

  /// Retire uniquement le filtre identifié par [FilterCollectionAction.filterKey].
  clear('Retirer ce filtre'),

  /// Retire tous les filtres impératifs actifs sur la collection cible.
  clearAll('Effacer tous les filtres');

  const CollectionFilterMode(this.label);

  /// Libellé français affiché dans l'éditeur.
  final String label;

  /// Résout un nom JSON en [CollectionFilterMode], ou `null` si inconnu.
  static CollectionFilterMode? tryParse(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    for (final value in values) {
      if (value.name == trimmed) return value;
    }
    return null;
  }
}

/// Action de comportement filtrant les lignes d'un `SuperListView` ou `SuperTable`.
@immutable
class FilterCollectionAction extends BehaviorAction {
  /// Crée une action de filtrage de collection.
  const FilterCollectionAction({
    this.mode = CollectionFilterMode.apply,
    this.predicate,
    this.targetComponentId,
    this.filterKey,
  });

  /// Raccourci pour retirer un filtre spécifique par [filterKey].
  const FilterCollectionAction.clear({
    this.targetComponentId,
    this.filterKey,
  }) : mode = CollectionFilterMode.clear,
       predicate = null;

  /// Raccourci pour effacer tous les filtres impératifs de la collection cible.
  const FilterCollectionAction.clearAll({this.targetComponentId})
    : mode = CollectionFilterMode.clearAll,
      predicate = null,
      filterKey = null;

  /// Mode d'application (`apply`, `toggle`, `clear`, `clearAll`).
  final CollectionFilterMode mode;

  /// Prédicat [BehaviorValidator] évalué pour chaque ligne (dans son `JsonListScope`).
  ///
  /// En mode déclaratif (`onBinding`), peut être omis si le [ComponentBehavior]
  /// porte déjà son prédicat dans `behavior.validator`.
  final BehaviorValidator? predicate;

  /// Identifiant technique du `SuperListView` ou `SuperTable` cible (en mode impératif).
  final String? targetComponentId;

  /// Clé logique permettant de gérer plusieurs filtres impératifs indépendants
  /// sur la même collection (ex. `'search'`, `'status'`).
  final String? filterKey;

  /// Vérifie les invariants de l'action.
  void validate({
    bool declarative = false,
    bool hasBehaviorValidator = false,
  }) {
    predicate?.validate();
    if (targetComponentId != null && targetComponentId!.trim().isEmpty) {
      throw const FormatException('targetComponentId ne peut pas être vide.');
    }
    if (filterKey != null && filterKey!.trim().isEmpty) {
      throw const FormatException('filterKey ne peut pas être vide.');
    }
    if (mode == CollectionFilterMode.clear ||
        mode == CollectionFilterMode.clearAll) {
      if (predicate != null) {
        throw FormatException(
          'predicate n’est pas autorisé lorsque mode vaut "${mode.name}".',
        );
      }
    }
    if (mode == CollectionFilterMode.clearAll && filterKey != null) {
      throw const FormatException(
        'filterKey n’est pas autorisé lorsque mode vaut "clearAll".',
      );
    }
    if (declarative) {
      if (mode != CollectionFilterMode.apply) {
        throw FormatException(
          'Le mode "${mode.name}" est réservé aux filtres impératifs (utilisez "apply" avec onBinding).',
        );
      }
      if (targetComponentId != null) {
        throw const FormatException(
          'Un filtre déclaratif (onBinding) s’applique directement au composant porteur et ne doit pas définir targetComponentId.',
        );
      }
      if (predicate == null && !hasBehaviorValidator) {
        throw const FormatException(
          'Un filtre déclaratif exige un prédicat ("predicate") ou un validateur ("validator") sur le comportement.',
        );
      }
      return;
    }

    if ((mode == CollectionFilterMode.apply ||
            mode == CollectionFilterMode.toggle) &&
        predicate == null) {
      throw const FormatException(
        'Un prédicat ("predicate") est requis pour filtrer une collection en mode impératif.',
      );
    }
  }

  @override
  String get type => 'filterCollection';

  @override
  String get label => mode.label;

  @override
  String get description {
    final targetPrefix =
        targetComponentId != null && targetComponentId!.trim().isNotEmpty
        ? '« ${targetComponentId!.trim()} » : '
        : '';
    final keySuffix = filterKey != null && filterKey!.trim().isNotEmpty
        ? ' [${filterKey!.trim()}]'
        : '';
    return switch (mode) {
      CollectionFilterMode.clearAll =>
        '${targetPrefix}Effacer tous les filtres',
      CollectionFilterMode.clear =>
        '${targetPrefix}Retirer le filtre$keySuffix',
      CollectionFilterMode.toggle =>
        '${targetPrefix}Basculer filtre$keySuffix (${predicate?.description ?? 'validateur'})',
      CollectionFilterMode.apply =>
        predicate != null
            ? '${targetPrefix}Filtrer$keySuffix : ${predicate!.description}'
            : '${targetPrefix}Filtrer selon le validateur du comportement',
    };
  }

  @override
  IconData get icon => Icons.filter_list;

  @override
  Set<String> get referencedComponentIds {
    final ids = <String>{};
    final target = targetComponentId?.trim();
    if (target != null && target.isNotEmpty) ids.add(target);
    if (predicate != null) ids.addAll(predicate!.referencedComponentIds);
    return ids.isEmpty ? const {} : ids;
  }

  @override
  FilterCollectionAction remapComponentIds(Map<String, String> idMap) {
    if (idMap.isEmpty) return this;
    var changed = false;
    var nextTarget = targetComponentId;
    final currentTarget = targetComponentId?.trim();
    if (currentTarget != null && idMap.containsKey(currentTarget)) {
      nextTarget = idMap[currentTarget];
      changed = true;
    }
    var nextPredicate = predicate;
    if (predicate != null) {
      final remapped = predicate!.remapComponentIds(idMap);
      if (remapped != predicate) {
        nextPredicate = remapped;
        changed = true;
      }
    }
    if (!changed) return this;
    return copyWith(targetComponentId: nextTarget, predicate: nextPredicate);
  }

  @override
  Future<void> execute(BuildContext context) async {
    final targetId = targetComponentId?.trim();
    if (targetId == null || targetId.isEmpty) return;
    CollectionViewStateRegistry.instance.applyFilter(targetId, this);
  }

  @override
  Future<void> executeWithData(
    BuildContext context,
    BehaviorExecutionData data,
  ) async {
    final targetId =
        targetComponentId != null && targetComponentId!.trim().isNotEmpty
        ? targetComponentId!.trim()
        : data.componentId;
    final defaultKey = data.componentId.isEmpty ? 'default' : data.componentId;
    CollectionViewStateRegistry.instance.applyFilter(
      targetId,
      this,
      defaultKey: defaultKey,
    );
  }

  /// Retourne une copie modifiée de l'action.
  FilterCollectionAction copyWith({
    CollectionFilterMode? mode,
    BehaviorValidator? predicate,
    bool clearPredicate = false,
    String? targetComponentId,
    bool clearTargetComponentId = false,
    String? filterKey,
    bool clearFilterKey = false,
  }) => FilterCollectionAction(
    mode: mode ?? this.mode,
    predicate: clearPredicate ? null : (predicate ?? this.predicate),
    targetComponentId: clearTargetComponentId
        ? null
        : (targetComponentId ?? this.targetComponentId),
    filterKey: clearFilterKey ? null : (filterKey ?? this.filterKey),
  );

  @override
  Map<String, Object?> toJson() {
    validate(declarative: predicate == null && mode == CollectionFilterMode.apply, hasBehaviorValidator: true);
    return {
      'type': type,
      if (mode != CollectionFilterMode.apply) 'mode': mode.name,
      if (targetComponentId != null)
        'targetComponentId': targetComponentId!.trim(),
      if (filterKey != null) 'filterKey': filterKey!.trim(),
      if (predicate != null) 'predicate': predicate!.toJson(),
    };
  }

  /// Sérialisation compacte.
  Map<String, Object?> toCompactJson() {
    validate(declarative: predicate == null && mode == CollectionFilterMode.apply, hasBehaviorValidator: true);
    return {
      'type': type,
      if (mode != CollectionFilterMode.apply) 'mode': mode.name,
      if (targetComponentId != null)
        'targetComponentId': targetComponentId!.trim(),
      if (filterKey != null) 'filterKey': filterKey!.trim(),
      if (predicate != null) 'predicate': predicate!.toCompactJson(),
    };
  }

  /// Décode une [FilterCollectionAction] depuis JSON.
  ///
  /// La validation contextuelle (déclaratif vs impératif) est complétée par
  /// [ComponentBehavior.validate].
  factory FilterCollectionAction.fromJson(Map<String, dynamic> json) {
    final rawMode = json['mode'];
    final mode = rawMode == null
        ? CollectionFilterMode.apply
        : CollectionFilterMode.tryParse(rawMode);
    if (mode == null) {
      throw FormatException(
        'Mode de filtre inconnu : "$rawMode" (attendu : apply, toggle, clear ou clearAll).',
      );
    }
    final rawTarget = json['targetComponentId'] ?? json['targetId'];
    if (rawTarget != null && rawTarget is! String) {
      throw const FormatException(
        'targetComponentId doit être une chaîne de caractères.',
      );
    }
    final rawKey = json['filterKey'];
    if (rawKey != null && rawKey is! String) {
      throw const FormatException('filterKey doit être une chaîne de caractères.');
    }
    final rawPredicate = json['predicate'];
    BehaviorValidator? predicate;
    if (rawPredicate != null) {
      if (rawPredicate is! Map) {
        throw const FormatException('predicate doit être un objet JSON.');
      }
      predicate = BehaviorValidatorCatalog.decode(
        Map<String, dynamic>.from(rawPredicate),
      );
    }
    return FilterCollectionAction(
      mode: mode,
      predicate: predicate,
      targetComponentId: rawTarget as String?,
      filterKey: rawKey as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterCollectionAction &&
          other.mode == mode &&
          other.predicate == predicate &&
          other.targetComponentId?.trim() == targetComponentId?.trim() &&
          other.filterKey?.trim() == filterKey?.trim();

  @override
  int get hashCode => Object.hash(
    mode,
    predicate,
    targetComponentId?.trim(),
    filterKey?.trim(),
  );
}
