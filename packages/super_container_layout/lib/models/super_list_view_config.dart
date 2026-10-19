/// Réglages persistés d'une `SuperListView`.
///
/// Ils sont enregistrés dans l'apparence (`Appearance.listComponents`, clé
/// JSON `listComponents`) sous l'ID du composant, et modifiés par la fenêtre
/// « Liste JSON » (clic droit sur la liste, puis *Liste*). La disposition
/// des lignes est un `SuperLayoutConfig` séparé, enregistré sous le même ID.
///
/// ```dart
/// const config = SuperListViewConfig(
///   binding: JsonTextBinding(path: 'clients[?].commandes'), // repository hérité
///   axis: Axis.horizontal,
///   itemExtent: 120,
///   allowAdd: true,
/// );
/// ```
library;

import 'package:flutter/painting.dart' show Axis;
import 'package:flutter/foundation.dart';

import 'json_text_binding.dart';

/// Réglages d'une `SuperListView` : tableau lié, orientation, taille des
/// lignes et actions autorisées. Valeur immuable, comparable par valeur.
@immutable
class SuperListViewConfig {
  const SuperListViewConfig({
    this.binding,
    this.axis = Axis.vertical,
    this.itemExtent = 56,
    this.spacing = 0,
    this.allowAdd = false,
    this.allowRemove = false,
    this.emptyText = 'Aucun élément',
  });

  /// Tableau JSON affiché, ou `null` pour une liste non liée.
  ///
  /// Un repository `null` est hérité de la liste englobante. Les `[?]` sont
  /// remplis par les listes englobantes, puis par les lignes sélectionnées :
  /// hors de toute liste, `clients[?].commandes` affiche les commandes du
  /// client sélectionné.
  final JsonTextBinding? binding;

  /// Orientation et sens de défilement.
  final Axis axis;

  /// Hauteur d'une ligne, ou largeur pour une liste horizontale.
  final double itemExtent;

  /// Espace entre deux lignes.
  final double spacing;

  /// Affiche le bouton *Ajouter*, qui ajoute une copie vide du dernier
  /// élément et la sélectionne.
  final bool allowAdd;

  /// Affiche un bouton de suppression (avec confirmation) sur chaque ligne.
  final bool allowRemove;

  /// Message affiché quand le tableau est vide.
  final String emptyText;

  /// Bornes de [itemExtent].
  static const minItemExtent = 16.0;
  static const maxItemExtent = 2000.0;

  /// Borne supérieure de [spacing].
  static const maxSpacing = 200.0;

  /// Vérifie la liaison et les bornes numériques ; lève une
  /// [FormatException] avec un message affichable sinon.
  void validate() {
    binding?.validate();
    if (!itemExtent.isFinite ||
        itemExtent < minItemExtent ||
        itemExtent > maxItemExtent) {
      throw const FormatException('Taille d’élément de liste invalide.');
    }
    if (!spacing.isFinite || spacing < 0 || spacing > maxSpacing) {
      throw const FormatException('Espacement de liste invalide.');
    }
  }

  /// Copie modifiée ; [clearBinding] retire la liaison.
  SuperListViewConfig copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Axis? axis,
    double? itemExtent,
    double? spacing,
    bool? allowAdd,
    bool? allowRemove,
    String? emptyText,
  }) => SuperListViewConfig(
    binding: clearBinding ? null : binding ?? this.binding,
    axis: axis ?? this.axis,
    itemExtent: itemExtent ?? this.itemExtent,
    spacing: spacing ?? this.spacing,
    allowAdd: allowAdd ?? this.allowAdd,
    allowRemove: allowRemove ?? this.allowRemove,
    emptyText: emptyText ?? this.emptyText,
  );

  /// Forme JSON persistée dans l'apparence.
  Map<String, Object?> toJson() {
    validate();
    return {
      if (binding != null) 'binding': binding!.toJson(),
      'axis': axis.name,
      'itemExtent': itemExtent,
      'spacing': spacing,
      'allowAdd': allowAdd,
      'allowRemove': allowRemove,
      'emptyText': emptyText,
    };
  }

  static const _keys = {
    'binding',
    'axis',
    'itemExtent',
    'spacing',
    'allowAdd',
    'allowRemove',
    'emptyText',
  };

  /// Lecture stricte : les clés inconnues ou les types invalides lèvent une
  /// [FormatException] ; les clés absentes prennent leur valeur par défaut.
  factory SuperListViewConfig.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.any((key) => !_keys.contains(key))) {
      throw const FormatException('Configuration de liste invalide.');
    }
    const defaults = SuperListViewConfig();
    T read<T>(String key, T fallback) {
      final raw = value[key];
      if (raw == null) return fallback;
      if (raw is! T) {
        throw const FormatException('Configuration de liste invalide.');
      }
      return raw;
    }

    final axis = read<String>('axis', defaults.axis.name);
    final result = SuperListViewConfig(
      binding: value['binding'] == null
          ? null
          : JsonTextBinding.fromJson(value['binding']),
      axis: Axis.values.firstWhere(
        (candidate) => candidate.name == axis,
        orElse: () =>
            throw const FormatException('Orientation de liste invalide.'),
      ),
      itemExtent: read<num>('itemExtent', defaults.itemExtent).toDouble(),
      spacing: read<num>('spacing', defaults.spacing).toDouble(),
      allowAdd: read<bool>('allowAdd', defaults.allowAdd),
      allowRemove: read<bool>('allowRemove', defaults.allowRemove),
      emptyText: read<String>('emptyText', defaults.emptyText),
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperListViewConfig &&
      binding == other.binding &&
      axis == other.axis &&
      itemExtent == other.itemExtent &&
      spacing == other.spacing &&
      allowAdd == other.allowAdd &&
      allowRemove == other.allowRemove &&
      emptyText == other.emptyText;

  @override
  int get hashCode => Object.hash(
    binding,
    axis,
    itemExtent,
    spacing,
    allowAdd,
    allowRemove,
    emptyText,
  );
}
