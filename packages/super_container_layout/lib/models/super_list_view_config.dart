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

import 'component_config.dart';
import 'json_syntax.dart';
import 'json_text_binding.dart';
import 'super_layout_config.dart';

enum ListWrapSizing { fixed, automatic }

/// Réglages d'une `SuperListView` : tableau lié, orientation, taille des
/// lignes et actions autorisées. Valeur immuable, comparable par valeur.
@immutable
class SuperListViewConfig extends ComponentConfig {
  const SuperListViewConfig({
    this.binding,
    this.axis = Axis.vertical,
    this.wrap = false,
    this.wrapSizing = ListWrapSizing.fixed,
    this.itemWidth = 160,
    this.itemSize,
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

  /// Flow left to right into new runs, with vertical scrolling.
  final bool wrap;
  final ListWrapSizing wrapSizing;

  /// Width of a fixed-size Wrap item; [itemExtent] is its height.
  final double itemWidth;

  /// Shared preferred dimensions and outer spacing of the row template.
  /// Null retains the original fixed/automatic list sizing.
  final SlotSizeConstraints? itemSize;

  /// Hauteur d'une ligne ou d'un element Wrap fixe, ou largeur horizontale.
  final double itemExtent;

  /// Espace entre deux lignes ; en Wrap, entre elements et entre rangees.
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

  @override
  String get componentType => 'list';

  /// Vérifie la liaison et les bornes numériques ; lève une
  /// [FormatException] avec un message affichable sinon.
  @override
  void validate() {
    binding?.validate();
    if (itemSize case final dimensions?) {
      SlotSizeConstraints.fromJson(dimensions.toJson());
    }
    if (!itemWidth.isFinite ||
        itemWidth < minItemExtent ||
        itemWidth > maxItemExtent) {
      throw const FormatException('Largeur d’élément de liste invalide.');
    }
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
    bool? wrap,
    ListWrapSizing? wrapSizing,
    double? itemWidth,
    SlotSizeConstraints? itemSize,
    bool clearItemSize = false,
    double? itemExtent,
    double? spacing,
    bool? allowAdd,
    bool? allowRemove,
    String? emptyText,
  }) => SuperListViewConfig(
    binding: clearBinding ? null : binding ?? this.binding,
    axis: axis ?? this.axis,
    wrap: wrap ?? this.wrap,
    wrapSizing: wrapSizing ?? this.wrapSizing,
    itemWidth: itemWidth ?? this.itemWidth,
    itemSize: clearItemSize ? null : itemSize ?? this.itemSize,
    itemExtent: itemExtent ?? this.itemExtent,
    spacing: spacing ?? this.spacing,
    allowAdd: allowAdd ?? this.allowAdd,
    allowRemove: allowRemove ?? this.allowRemove,
    emptyText: emptyText ?? this.emptyText,
  );

  /// Forme JSON persistée dans l'apparence.
  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      if (binding != null) 'binding': binding!.toJson(),
      'axis': axis.name,
      'wrap': wrap,
      'wrapSizing': wrapSizing.name,
      'itemWidth': itemWidth,
      if (itemSize != null) 'itemSize': itemSize!.toJson(),
      'itemExtent': itemExtent,
      'spacing': spacing,
      'allowAdd': allowAdd,
      'allowRemove': allowRemove,
      'emptyText': emptyText,
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    const d = SuperListViewConfig();
    return {
      if (binding != null) 'binding': binding!.toCompactJson(),
      if (axis != d.axis) 'axis': axis.name,
      if (wrap != d.wrap) 'wrap': wrap,
      if (wrapSizing != d.wrapSizing) 'wrapSizing': wrapSizing.name,
      if (itemWidth != d.itemWidth) 'itemWidth': itemWidth,
      if (itemSize != null)
        'itemSize': JsonDimension.formatConstraintsCompact(itemSize!),
      if (itemExtent != d.itemExtent) 'itemExtent': itemExtent,
      if (spacing != d.spacing) 'spacing': spacing,
      if (allowAdd != d.allowAdd) 'allowAdd': allowAdd,
      if (allowRemove != d.allowRemove) 'allowRemove': allowRemove,
      if (emptyText != d.emptyText) 'emptyText': emptyText,
    };
  }

  @override
  SuperListViewConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperListViewConfig.fromJson(patch, fallback: this);

  static const _keys = {
    'binding',
    'axis',
    'wrap',
    'wrapSizing',
    'itemWidth',
    'itemSize',
    'itemExtent',
    'spacing',
    'allowAdd',
    'allowRemove',
    'emptyText',
  };

  /// Lecture stricte : les clés inconnues ou les types invalides lèvent une
  /// [FormatException] ; les clés absentes prennent leur valeur de [fallback].
  factory SuperListViewConfig.fromJson(
    Object? value, {
    SuperListViewConfig fallback = const SuperListViewConfig(),
  }) {
    if (value is! Map || value.keys.any((key) => !_keys.contains(key))) {
      throw const FormatException('Configuration de liste invalide.');
    }
    T read<T>(String key, T fallbackVal) {
      final raw = value[key];
      if (raw == null) return fallbackVal;
      if (raw is! T) {
        throw const FormatException('Configuration de liste invalide.');
      }
      return raw;
    }

    final axis = read<String>('axis', fallback.axis.name);
    final wrapSizing = read<String>('wrapSizing', fallback.wrapSizing.name);
    final result = SuperListViewConfig(
      binding: !value.containsKey('binding')
          ? fallback.binding
          : value['binding'] == null
          ? null
          : JsonTextBinding.fromJson(value['binding']),
      axis: Axis.values.firstWhere(
        (candidate) => candidate.name == axis,
        orElse: () =>
            throw const FormatException('Orientation de liste invalide.'),
      ),
      wrap: read<bool>('wrap', fallback.wrap),
      wrapSizing: ListWrapSizing.values.firstWhere(
        (candidate) => candidate.name == wrapSizing,
        orElse: () =>
            throw const FormatException('Taille Wrap de liste invalide.'),
      ),
      itemWidth: read<num>('itemWidth', fallback.itemWidth).toDouble(),
      itemSize: !value.containsKey('itemSize')
          ? fallback.itemSize
          : value['itemSize'] == null
          ? null
          : SlotSizeConstraints.fromJson(value['itemSize']),
      itemExtent: read<num>('itemExtent', fallback.itemExtent).toDouble(),
      spacing: read<num>('spacing', fallback.spacing).toDouble(),
      allowAdd: read<bool>('allowAdd', fallback.allowAdd),
      allowRemove: read<bool>('allowRemove', fallback.allowRemove),
      emptyText: read<String>('emptyText', fallback.emptyText),
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperListViewConfig &&
      binding == other.binding &&
      axis == other.axis &&
      wrap == other.wrap &&
      wrapSizing == other.wrapSizing &&
      itemWidth == other.itemWidth &&
      itemSize == other.itemSize &&
      itemExtent == other.itemExtent &&
      spacing == other.spacing &&
      allowAdd == other.allowAdd &&
      allowRemove == other.allowRemove &&
      emptyText == other.emptyText;

  @override
  int get hashCode => Object.hash(
    binding,
    axis,
    wrap,
    wrapSizing,
    itemWidth,
    itemSize,
    itemExtent,
    spacing,
    allowAdd,
    allowRemove,
    emptyText,
  );
}
