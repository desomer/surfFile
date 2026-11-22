/// Action de comportement permettant de trier un [SuperListView] ou un [SuperTable]
/// ([SortCollectionAction]) selon un ou plusieurs critères ([CollectionSortCriterion]).
///
/// Fonctionne en deux modes :
/// - **Déclaratif (`BehaviorEvent.onBinding`)** : attaché directement au composant
///   collection (`SuperListView` / `SuperTable`) ; le `validator` du [ComponentBehavior]
///   sert de condition d'activation du tri.
/// - **Impératif (`onTap`, `onChanged`, `onSubmitted`, etc.)** : déclenché depuis
///   n'importe quel composant (en-tête de colonne, bouton, sélecteur) en ciblant la
///   collection via [targetComponentId], avec support de l'alternance `toggle`, de
///   l'ajout de critères secondaires (`add`) et de la réinitialisation (`clear`).
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../../services/behaviors/collection_view_state_registry.dart';
import '../component_behavior.dart';
import '../json_text_binding.dart';

/// Sens de tri appliqué à un critère [CollectionSortCriterion].
enum CollectionSortDirection {
  /// Tri croissant (A -> Z, 0 -> 9).
  asc('Croissant', Icons.arrow_upward_outlined),

  /// Tri décroissant (Z -> A, 9 -> 0).
  desc('Décroissant', Icons.arrow_downward_outlined),

  /// Alterne entre croissant et décroissant à chaque déclenchement impératif.
  toggle('Alterner (asc / desc)', Icons.swap_vert_outlined);

  const CollectionSortDirection(this.label, this.icon);

  /// Libellé français affiché dans l'éditeur.
  final String label;

  /// Icône représentative.
  final IconData icon;

  /// Résout un nom JSON en [CollectionSortDirection], ou `null` si inconnu.
  static CollectionSortDirection? tryParse(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    for (final value in values) {
      if (value.name == trimmed) return value;
    }
    return null;
  }
}

/// Mode d'application d'une [SortCollectionAction] sur la collection cible.
enum CollectionSortMode {
  /// Remplace les critères de tri actifs par ceux de l'action.
  set('Définir le tri'),

  /// Ajoute ou met à jour un critère de tri secondaire.
  add('Ajouter un critère'),

  /// Efface le tri impératif (revient au tri déclaratif ou à l'ordre source).
  clear('Réinitialiser le tri');

  const CollectionSortMode(this.label);

  /// Libellé français affiché dans l'éditeur.
  final String label;

  /// Résout un nom JSON en [CollectionSortMode], ou `null` si inconnu.
  static CollectionSortMode? tryParse(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    for (final value in values) {
      if (value.name == trimmed) return value;
    }
    return null;
  }
}

/// Critère unitaire de tri sur un attribut de ligne (ou `'.'` pour des valeurs primitives).
@immutable
class CollectionSortCriterion {
  /// Crée un critère de tri sur [path].
  const CollectionSortCriterion({
    required this.path,
    this.direction = CollectionSortDirection.asc,
    this.caseSensitive = false,
    this.nullsLast = true,
  });

  /// Chemin de l'attribut de ligne trié : relatif (`nom`, `client.nom`),
  /// modèle (`clients[?].nom`), attribut calculé (`@total`) ou `'.'` pour une
  /// collection de valeurs primitives.
  final String path;

  /// Sens du tri (`asc`, `desc`, ou `toggle` en mode impératif).
  final CollectionSortDirection direction;

  /// Indique si la comparaison textuelle distingue majuscules et minuscules.
  final bool caseSensitive;

  /// Indique si les valeurs nulles ou absentes sont placées en fin de liste.
  final bool nullsLast;

  /// Valide le chemin du critère.
  void validate({bool allowToggle = true}) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Le chemin du champ à trier est requis.');
    }
    if (!allowToggle && direction == CollectionSortDirection.toggle) {
      throw const FormatException(
        'Le sens "toggle" est réservé aux tris impératifs (utilisez "asc" ou "desc" avec onBinding).',
      );
    }
    if (trimmed != '.' && !JsonTextBinding.isCalculatedPath(trimmed)) {
      JsonAttributePath(trimmed);
    }
  }

  /// Retourne une copie modifiée du critère.
  CollectionSortCriterion copyWith({
    String? path,
    CollectionSortDirection? direction,
    bool? caseSensitive,
    bool? nullsLast,
  }) => CollectionSortCriterion(
    path: path ?? this.path,
    direction: direction ?? this.direction,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    nullsLast: nullsLast ?? this.nullsLast,
  );

  /// Sérialisation JSON complète.
  Map<String, Object?> toJson() {
    validate();
    return {
      'path': path.trim(),
      'direction': direction.name,
      if (caseSensitive) 'caseSensitive': true,
      if (!nullsLast) 'nullsLast': false,
    };
  }

  /// Sérialisation JSON compacte.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'path': path.trim(),
      if (direction != CollectionSortDirection.asc) 'direction': direction.name,
      if (caseSensitive) 'caseSensitive': true,
      if (!nullsLast) 'nullsLast': false,
    };
  }

  /// Décode et valide un [CollectionSortCriterion] depuis JSON.
  factory CollectionSortCriterion.fromJson(Map<String, dynamic> json) {
    final rawPath = json['path'] ?? json['field'];
    if (rawPath is! String || rawPath.trim().isEmpty) {
      throw const FormatException(
        'Chaque critère de tri doit définir un champ ("path").',
      );
    }
    final rawDirection = json['direction'];
    final direction = rawDirection == null
        ? CollectionSortDirection.asc
        : CollectionSortDirection.tryParse(rawDirection);
    if (direction == null) {
      throw FormatException(
        'Sens de tri inconnu : "$rawDirection" (attendu : asc, desc ou toggle).',
      );
    }
    final rawCaseSensitive = json['caseSensitive'];
    if (rawCaseSensitive != null && rawCaseSensitive is! bool) {
      throw const FormatException('caseSensitive doit être un booléen.');
    }
    final rawNullsLast = json['nullsLast'];
    if (rawNullsLast != null && rawNullsLast is! bool) {
      throw const FormatException('nullsLast doit être un booléen.');
    }
    final result = CollectionSortCriterion(
      path: rawPath.trim(),
      direction: direction,
      caseSensitive: rawCaseSensitive as bool? ?? false,
      nullsLast: rawNullsLast as bool? ?? true,
    );
    result.validate();
    return result;
  }

  /// Description concise en français du critère.
  String get summary {
    final fieldLabel = path.trim() == '.' ? 'élément' : path.trim();
    final dirLabel = switch (direction) {
      CollectionSortDirection.asc => '↑',
      CollectionSortDirection.desc => '↓',
      CollectionSortDirection.toggle => '↕',
    };
    return '$fieldLabel $dirLabel';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectionSortCriterion &&
          other.path.trim() == path.trim() &&
          other.direction == direction &&
          other.caseSensitive == caseSensitive &&
          other.nullsLast == nullsLast;

  @override
  int get hashCode => Object.hash(path.trim(), direction, caseSensitive, nullsLast);
}

/// Action de comportement triant une collection (`SuperListView` ou `SuperTable`).
@immutable
class SortCollectionAction extends BehaviorAction {
  /// Crée une action de tri avec la liste ordonnée [criteria].
  SortCollectionAction({
    List<CollectionSortCriterion> criteria = const [],
    this.mode = CollectionSortMode.set,
    this.targetComponentId,
  }) : criteria = List<CollectionSortCriterion>.unmodifiable(criteria);

  /// Raccourci pour un tri sur un seul champ [path].
  SortCollectionAction.single({
    required String path,
    CollectionSortDirection direction = CollectionSortDirection.asc,
    bool caseSensitive = false,
    bool nullsLast = true,
    this.mode = CollectionSortMode.set,
    this.targetComponentId,
  }) : criteria = List<CollectionSortCriterion>.unmodifiable([
         CollectionSortCriterion(
           path: path,
           direction: direction,
           caseSensitive: caseSensitive,
           nullsLast: nullsLast,
         ),
       ]);

  /// Raccourci pour réinitialiser le tri impératif d'une collection.
  const SortCollectionAction.clear({this.targetComponentId})
    : criteria = const [],
      mode = CollectionSortMode.clear;

  /// Critères de tri ordonnés (du principal aux critères secondaires).
  final List<CollectionSortCriterion> criteria;

  /// Mode d'application (`set`, `add`, `clear`).
  final CollectionSortMode mode;

  /// Identifiant technique du `SuperListView` ou `SuperTable` cible (en mode impératif).
  ///
  /// Omis (`null`) en mode déclaratif (`onBinding`) ou lorsque l'action impérative
  /// est attachée directement à la collection elle-même.
  final String? targetComponentId;

  /// Vérifie la cohérence de l'action (en mode déclaratif ou impératif).
  void validate({bool declarative = false}) {
    if (targetComponentId != null && targetComponentId!.trim().isEmpty) {
      throw const FormatException(
        'targetComponentId ne peut pas être vide.',
      );
    }
    if (declarative) {
      if (targetComponentId != null) {
        throw const FormatException(
          'Un tri déclaratif (onBinding) s’applique directement au composant porteur et ne doit pas définir targetComponentId.',
        );
      }
      if (mode == CollectionSortMode.clear) {
        throw const FormatException(
          'Le mode "clear" est réservé aux tris impératifs.',
        );
      }
    }
    if (mode == CollectionSortMode.clear) {
      if (criteria.isNotEmpty) {
        throw const FormatException(
          'Aucun critère de tri n’est autorisé lorsque mode vaut "clear".',
        );
      }
      return;
    }
    if (criteria.isEmpty) {
      throw const FormatException(
        'Au moins un critère de tri ("path" ou "criteria") est requis.',
      );
    }
    for (final criterion in criteria) {
      criterion.validate(allowToggle: !declarative);
    }
  }

  @override
  String get type => 'sortCollection';

  @override
  String get label => switch (mode) {
    CollectionSortMode.clear => 'Réinitialiser le tri',
    CollectionSortMode.add => 'Ajouter un critère de tri',
    CollectionSortMode.set => 'Trier la collection',
  };

  @override
  String get description {
    final targetPrefix =
        targetComponentId != null && targetComponentId!.trim().isNotEmpty
        ? '« ${targetComponentId!.trim()} » : '
        : '';
    if (mode == CollectionSortMode.clear) {
      return '${targetPrefix}Réinitialiser le tri';
    }
    final summary = criteria.map((c) => c.summary).join(', ');
    final modeLabel = mode == CollectionSortMode.add ? 'Ajouter tri' : 'Trier par';
    return '$targetPrefix$modeLabel $summary';
  }

  @override
  IconData get icon => Icons.sort;

  @override
  Set<String> get referencedComponentIds {
    final id = targetComponentId?.trim();
    return id == null || id.isEmpty ? const {} : {id};
  }

  @override
  SortCollectionAction remapComponentIds(Map<String, String> idMap) {
    final current = targetComponentId?.trim();
    if (current == null || !idMap.containsKey(current)) return this;
    return copyWith(targetComponentId: idMap[current]);
  }

  @override
  Future<void> execute(BuildContext context) async {
    final targetId = targetComponentId?.trim();
    if (targetId == null || targetId.isEmpty) return;
    CollectionViewStateRegistry.instance.applySort(targetId, this);
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
    CollectionViewStateRegistry.instance.applySort(targetId, this);
  }

  /// Retourne une copie modifiée de l'action.
  SortCollectionAction copyWith({
    List<CollectionSortCriterion>? criteria,
    CollectionSortMode? mode,
    String? targetComponentId,
    bool clearTargetComponentId = false,
  }) => SortCollectionAction(
    criteria: criteria ?? this.criteria,
    mode: mode ?? this.mode,
    targetComponentId: clearTargetComponentId
        ? null
        : (targetComponentId ?? this.targetComponentId),
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      if (mode != CollectionSortMode.set) 'mode': mode.name,
      if (targetComponentId != null)
        'targetComponentId': targetComponentId!.trim(),
      if (criteria.isNotEmpty)
        'criteria': [for (final c in criteria) c.toJson()],
    };
  }

  /// Forme compacte (raccourci `path`/`direction` lorsqu'un seul critère est présent).
  Map<String, Object?> toCompactJson() {
    validate();
    if (criteria.length == 1 && mode == CollectionSortMode.set) {
      final only = criteria.single;
      return {
        'type': type,
        if (targetComponentId != null)
          'targetComponentId': targetComponentId!.trim(),
        ...only.toCompactJson(),
      };
    }
    return {
      'type': type,
      if (mode != CollectionSortMode.set) 'mode': mode.name,
      if (targetComponentId != null)
        'targetComponentId': targetComponentId!.trim(),
      if (criteria.isNotEmpty)
        'criteria': [for (final c in criteria) c.toCompactJson()],
    };
  }

  /// Décode et valide une [SortCollectionAction] depuis JSON.
  factory SortCollectionAction.fromJson(Map<String, dynamic> json) {
    final rawMode = json['mode'];
    final mode = rawMode == null
        ? CollectionSortMode.set
        : CollectionSortMode.tryParse(rawMode);
    if (mode == null) {
      throw FormatException(
        'Mode de tri inconnu : "$rawMode" (attendu : set, add ou clear).',
      );
    }
    final rawTarget = json['targetComponentId'] ?? json['targetId'];
    if (rawTarget != null && rawTarget is! String) {
      throw const FormatException(
        'targetComponentId doit être une chaîne de caractères.',
      );
    }
    final criteria = <CollectionSortCriterion>[];
    if (json['criteria'] != null) {
      final rawCriteria = json['criteria'];
      if (rawCriteria is! List) {
        throw const FormatException('criteria doit être une liste JSON.');
      }
      for (final item in rawCriteria) {
        if (item is! Map) {
          throw const FormatException(
            'Chaque entrée de criteria doit être un objet JSON.',
          );
        }
        criteria.add(
          CollectionSortCriterion.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    } else if (json.containsKey('path') || json.containsKey('field')) {
      criteria.add(CollectionSortCriterion.fromJson(json));
    }

    final result = SortCollectionAction(
      criteria: criteria,
      mode: mode,
      targetComponentId: rawTarget as String?,
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SortCollectionAction &&
          other.mode == mode &&
          other.targetComponentId?.trim() == targetComponentId?.trim() &&
          listEquals(other.criteria, criteria);

  @override
  int get hashCode =>
      Object.hash(mode, targetComponentId?.trim(), Object.hashAll(criteria));
}
