/// Descripteurs déclaratifs de propriétés ([NativePropertyDescriptor]) des composants natifs.
///
/// Pilote la génération automatique des contrôles dans [NativeComponentEditor]
/// ainsi que la validation des valeurs stockées dans [NativeComponentConfig].
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart' show IconData, Icons;

import 'json_syntax.dart';
import 'native_shape_config.dart';

/// Type de contrôle générique utilisé pour éditer une propriété native.
enum NativePropertyEditorType {
  bool,
  color,
  number,
  select,
  shape;

  static NativePropertyEditorType fromJson(Object? value) => switch (value) {
    'bool' || 'boolean' || 'switch' => NativePropertyEditorType.bool,
    'color' => NativePropertyEditorType.color,
    'number' || 'slider' || 'double' => NativePropertyEditorType.number,
    'select' || 'enum' || 'dropdown' => NativePropertyEditorType.select,
    'shape' || 'shapeBorder' => NativePropertyEditorType.shape,
    _ => throw FormatException('Type d’éditeur de propriété invalide : $value'),
  };
}

/// Option d'une propriété de type [NativePropertyEditorType.select].
class NativePropertyOption {
  const NativePropertyOption({required this.value, required this.label});

  final String value;
  final String label;

  Map<String, Object> toJson() => {'value': value, 'label': label};

  factory NativePropertyOption.fromJson(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      final trimmed = raw.trim();
      return NativePropertyOption(value: trimmed, label: trimmed);
    }
    if (raw is! Map || raw['value'] is! String || raw['label'] is! String) {
      throw const FormatException('Option de propriété native invalide.');
    }
    final value = (raw['value'] as String).trim();
    final label = (raw['label'] as String).trim();
    if (value.isEmpty || label.isEmpty) {
      throw const FormatException('Option de propriété native vide.');
    }
    return NativePropertyOption(value: value, label: label);
  }

  @override
  bool operator ==(Object other) =>
      other is NativePropertyOption &&
      other.value == value &&
      other.label == label;

  @override
  int get hashCode => Object.hash(value, label);
}

/// Descripteur déclaratif d'une propriété de composant natif (`id`, `label`,
/// `editorType`, bornes et options), sérialisable en JSON.
class NativePropertyDescriptor {
  const NativePropertyDescriptor({
    required this.id,
    required this.label,
    required this.editorType,
    this.subtitle,
    this.defaultValue,
    this.min,
    this.max,
    this.divisions,
    this.options = const [],
    this.nullable = true,
  });

  /// Crée un descripteur de propriété de type couleur ([NativePropertyEditorType.color]).
  const NativePropertyDescriptor.color({
    required this.id,
    required this.label,
    this.subtitle,
    this.defaultValue,
    this.nullable = true,
  }) : editorType = NativePropertyEditorType.color,
       min = null,
       max = null,
       divisions = null,
       options = const [];

  /// Crée un descripteur de propriété booléenne ([NativePropertyEditorType.bool]).
  const NativePropertyDescriptor.flag({
    required this.id,
    required this.label,
    this.subtitle,
    bool? this.defaultValue,
    this.nullable = true,
  }) : editorType = NativePropertyEditorType.bool,
       min = null,
       max = null,
       divisions = null,
       options = const [];

  /// Crée un descripteur de propriété numérique ([NativePropertyEditorType.number]).
  const NativePropertyDescriptor.number({
    required this.id,
    required this.label,
    this.subtitle,
    double? this.defaultValue,
    this.min,
    this.max,
    this.divisions,
    this.nullable = true,
  }) : editorType = NativePropertyEditorType.number,
       options = const [];

  /// Crée un descripteur de propriété à choix multiple ([NativePropertyEditorType.select]).
  const NativePropertyDescriptor.select({
    required this.id,
    required this.label,
    required this.options,
    this.subtitle,
    String? this.defaultValue,
    this.nullable = true,
  }) : editorType = NativePropertyEditorType.select,
       min = null,
       max = null,
       divisions = null;

  /// Crée un descripteur de propriété de forme géométrique ([NativePropertyEditorType.shape]).
  const NativePropertyDescriptor.shape({
    required this.id,
    required this.label,
    this.subtitle,
    this.nullable = true,
  }) : editorType = NativePropertyEditorType.shape,
       defaultValue = null,
       min = null,
       max = null,
       divisions = null,
       options = const [];

  final String id;
  final String label;
  final String? subtitle;
  final NativePropertyEditorType editorType;
  final Object? defaultValue;
  final double? min;
  final double? max;
  final int? divisions;
  final List<NativePropertyOption> options;
  final bool nullable;

  /// Normalise et valide une valeur brute JSON pour ce descripteur.
  Object? normalizeValue(Object? raw) {
    if (raw == null) return null;
    return switch (editorType) {
      NativePropertyEditorType.bool =>
        raw is bool
            ? raw
            : throw FormatException('Booléen attendu pour "$id".'),
      NativePropertyEditorType.color => JsonColor.toHex(
        JsonColor.parse(raw, id),
      ),
      NativePropertyEditorType.number => () {
        if (raw is! num || !raw.isFinite) {
          throw FormatException('Nombre fini attendu pour "$id".');
        }
        var value = raw.toDouble();
        if (min != null && value < min!) value = min!;
        if (max != null && value > max!) value = max!;
        return value;
      }(),
      NativePropertyEditorType.select => () {
        if (raw is! String || raw.trim().isEmpty) {
          throw FormatException('Chaîne attendue pour "$id".');
        }
        final trimmed = raw.trim();
        if (options.isNotEmpty &&
            !options.any((option) => option.value == trimmed)) {
          throw FormatException('Valeur "$trimmed" non autorisée pour "$id".');
        }
        return trimmed;
      }(),
      NativePropertyEditorType.shape =>
        NativeShapeConfig.fromJson(raw).toJson(),
    };
  }

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'subtitle': ?subtitle,
    'editorType': editorType.name,
    'defaultValue': ?defaultValue,
    'min': ?min,
    'max': ?max,
    'divisions': ?divisions,
    if (options.isNotEmpty)
      'options': [for (final option in options) option.toJson()],
    if (!nullable) 'nullable': false,
  };

  factory NativePropertyDescriptor.fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['label'] is! String) {
      throw const FormatException('Descripteur de propriété native invalide.');
    }
    final id = (raw['id'] as String).trim();
    final label = (raw['label'] as String).trim();
    if (id.isEmpty || label.isEmpty) {
      throw const FormatException(
        'Identifiant ou libellé de propriété native vide.',
      );
    }
    final editorType = NativePropertyEditorType.fromJson(
      raw['editorType'] ?? raw['type'],
    );
    final subtitle = raw['subtitle'];
    if (subtitle != null && subtitle is! String) {
      throw FormatException('Sous-titre invalide pour "$id".');
    }
    final min = raw['min'];
    if (min != null && (min is! num || !min.isFinite)) {
      throw FormatException('Borne min invalide pour "$id".');
    }
    final max = raw['max'];
    if (max != null && (max is! num || !max.isFinite)) {
      throw FormatException('Borne max invalide pour "$id".');
    }
    if (min is num && max is num && min > max) {
      throw FormatException('Bornes min/max incohérentes pour "$id".');
    }
    final divisions = raw['divisions'];
    if (divisions != null && (divisions is! int || divisions <= 0)) {
      throw FormatException('Divisions invalides pour "$id".');
    }
    final rawOptions = raw['options'];
    if (rawOptions != null && rawOptions is! List) {
      throw FormatException('Options invalides pour "$id".');
    }
    final options = rawOptions is List
        ? List<NativePropertyOption>.unmodifiable(
            rawOptions.map(NativePropertyOption.fromJson),
          )
        : const <NativePropertyOption>[];
    if (editorType == NativePropertyEditorType.select && options.isEmpty) {
      throw FormatException(
        'Une propriété "select" ("$id") doit déclarer au moins une option.',
      );
    }
    final nullable = raw['nullable'] ?? true;
    if (nullable is! bool) {
      throw FormatException('Indicateur nullable invalide pour "$id".');
    }
    final descriptor = NativePropertyDescriptor(
      id: id,
      label: label,
      subtitle: subtitle is String && subtitle.trim().isNotEmpty
          ? subtitle.trim()
          : null,
      editorType: editorType,
      defaultValue: raw['defaultValue'],
      min: (min as num?)?.toDouble(),
      max: (max as num?)?.toDouble(),
      divisions: divisions as int?,
      options: options,
      nullable: nullable,
    );
    if (descriptor.defaultValue != null) {
      descriptor.normalizeValue(descriptor.defaultValue);
    }
    return descriptor;
  }

  static List<NativePropertyDescriptor> listFromJson(Object? raw) {
    if (raw is! List) {
      throw const FormatException(
        'La liste des descripteurs de propriétés doit être un tableau JSON.',
      );
    }
    return List<NativePropertyDescriptor>.unmodifiable(
      raw.map(NativePropertyDescriptor.fromJson),
    );
  }

  static List<Map<String, Object>> listToJson(
    List<NativePropertyDescriptor> descriptors,
  ) => [for (final descriptor in descriptors) descriptor.toJson()];

  @override
  bool operator ==(Object other) =>
      other is NativePropertyDescriptor &&
      other.id == id &&
      other.label == label &&
      other.subtitle == subtitle &&
      other.editorType == editorType &&
      other.defaultValue == defaultValue &&
      other.min == min &&
      other.max == max &&
      other.divisions == divisions &&
      listEquals(other.options, options) &&
      other.nullable == nullable;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    subtitle,
    editorType,
    defaultValue,
    min,
    max,
    divisions,
    Object.hashAll(options),
    nullable,
  );
}

const List<NativePropertyOption> _clipBehaviorOptions = [
  NativePropertyOption(value: 'none', label: 'Aucun (none)'),
  NativePropertyOption(value: 'hardEdge', label: 'Bord net (hardEdge)'),
  NativePropertyOption(value: 'antiAlias', label: 'Anticrénelage (antiAlias)'),
  NativePropertyOption(
    value: 'antiAliasWithSaveLayer',
    label: 'Anticrénelage avec calque (antiAliasWithSaveLayer)',
  ),
];

const NativePropertyDescriptor _surfaceTintColorDescriptor =
    NativePropertyDescriptor.color(
      id: 'surfaceTintColor',
      label: 'Teinte de surface',
      subtitle:
          'Teinte Material 3 appliquée avec l’élévation (surfaceTintColor)',
    );

const NativePropertyDescriptor _shadowColorDescriptor =
    NativePropertyDescriptor.color(
      id: 'shadowColor',
      label: 'Couleur de l’ombre',
      subtitle: 'Couleur de l’ombre portée sous la barre (shadowColor)',
    );

const NativePropertyDescriptor _shapeDescriptor =
    NativePropertyDescriptor.shape(
      id: 'shape',
      label: 'Forme et bordure (Shape)',
      subtitle: 'Découpe géométrique, coins arrondis et contour (shape)',
    );

const NativePropertyDescriptor _barClipBehaviorDescriptor =
    NativePropertyDescriptor.select(
      id: 'clipBehavior',
      label: 'Découpage (Clip)',
      subtitle: 'Mode de découpage du contenu dépassant de la barre',
      options: _clipBehaviorOptions,
    );

const NativePropertyDescriptor _initiallyExpandedDescriptor =
    NativePropertyDescriptor.flag(
      id: 'initiallyExpanded',
      label: 'Ouvert par défaut',
      subtitle: 'État initial hors liaison repository',
      defaultValue: false,
    );

const NativePropertyDescriptor _headerClickTogglesDescriptor =
    NativePropertyDescriptor.flag(
      id: 'headerClickToggles',
      label: 'Basculer au clic sur l’en-tête',
      defaultValue: true,
    );

/// Catalogue déclaratif des propriétés de style Flutter disponibles sur [SuperAppBar].
const List<NativePropertyDescriptor> superAppBarPropertyDescriptors = [
  // Couleurs
  NativePropertyDescriptor.color(
    id: 'backgroundColor',
    label: 'Couleur de fond',
    subtitle: 'Arrière-plan de la barre (backgroundColor)',
  ),
  NativePropertyDescriptor.color(
    id: 'foregroundColor',
    label: 'Couleur du contenu',
    subtitle: 'Couleur par défaut du texte et des icônes (foregroundColor)',
  ),
  _surfaceTintColorDescriptor,
  _shadowColorDescriptor,
  // Élévation & transparence
  NativePropertyDescriptor.number(
    id: 'elevation',
    label: 'Élévation',
    subtitle: 'Hauteur de l’ombre portée au repos (elevation)',
    defaultValue: 0.0,
    min: 0,
    max: 24,
    divisions: 24,
  ),
  NativePropertyDescriptor.number(
    id: 'scrolledUnderElevation',
    label: 'Élévation au défilement',
    subtitle: 'Élévation lorsque le contenu défile dessous',
    defaultValue: 3.0,
    min: 0,
    max: 24,
    divisions: 24,
  ),
  NativePropertyDescriptor.flag(
    id: 'forceMaterialTransparency',
    label: 'Transparence Material forcée',
    subtitle: 'Rend le fond Material totalement transparent',
    defaultValue: false,
  ),
  _shapeDescriptor,
  // Dimensions & espacements
  NativePropertyDescriptor.number(
    id: 'leadingWidth',
    label: 'Largeur de Navigation',
    subtitle: 'Largeur réservée à la zone leading (leadingWidth)',
    defaultValue: 56.0,
    min: 24,
    max: 200,
    divisions: 88,
  ),
  NativePropertyDescriptor.number(
    id: 'titleSpacing',
    label: 'Espacement du titre',
    subtitle: 'Marge horizontale autour de la zone title (titleSpacing)',
    defaultValue: 0.0,
    min: 0,
    max: 64,
    divisions: 64,
  ),
  // Comportement & opacité
  NativePropertyDescriptor.flag(
    id: 'centerTitle',
    label: 'Centrer le titre',
    subtitle: 'Centre horizontalement la zone title dans la barre',
    defaultValue: false,
  ),
  NativePropertyDescriptor.number(
    id: 'toolbarOpacity',
    label: 'Opacité de la barre',
    subtitle: 'Opacité des éléments de la barre principale (0.0 à 1.0)',
    defaultValue: 1.0,
    min: 0,
    max: 1,
    divisions: 20,
  ),
  NativePropertyDescriptor.number(
    id: 'bottomOpacity',
    label: 'Opacité de la zone Bas',
    subtitle: 'Opacité de la région bottom de la barre (0.0 à 1.0)',
    defaultValue: 1.0,
    min: 0,
    max: 1,
    divisions: 20,
  ),
  NativePropertyDescriptor.flag(
    id: 'primary',
    label: 'Barre principale (SafeArea)',
    subtitle: 'Ajoute le retrait de la barre de statut système en haut',
    defaultValue: true,
  ),
  NativePropertyDescriptor.flag(
    id: 'excludeHeaderSemantics',
    label: 'Exclure la sémantique d’en-tête',
    subtitle: 'Ne marque pas le titre comme en-tête d’accessibilité',
    defaultValue: false,
  ),
  _barClipBehaviorDescriptor,
  NativePropertyDescriptor.select(
    id: 'systemOverlayStyle',
    label: 'Style de la barre système',
    subtitle: 'Luminosité des icônes système (statut / navigation)',
    options: [
      NativePropertyOption(value: 'light', label: 'Icônes claires (light)'),
      NativePropertyOption(value: 'dark', label: 'Icônes sombres (dark)'),
    ],
  ),
];

/// Descripteur de la propriété `useDefaultNavigation` de [SuperAppBar].
const NativePropertyDescriptor useDefaultNavigationPropertyDescriptor =
    NativePropertyDescriptor.flag(
      id: 'useDefaultNavigation',
      label: 'Bouton de navigation par défaut',
      subtitle:
          'Menu du drawer ou bouton Retour natif. Remplace la zone Navigation.',
      defaultValue: true,
    );

/// Catalogue déclaratif des propriétés de style Flutter disponibles sur [SuperBottomAppBar].
const List<NativePropertyDescriptor> superBottomAppBarPropertyDescriptors = [
  // Couleurs
  NativePropertyDescriptor.color(
    id: 'color',
    label: 'Couleur de fond',
    subtitle: 'Arrière-plan de la barre basse (color)',
  ),
  _surfaceTintColorDescriptor,
  _shadowColorDescriptor,
  // Élévation, forme & encoche
  NativePropertyDescriptor.number(
    id: 'elevation',
    label: 'Élévation',
    subtitle: 'Hauteur de l’ombre portée au repos (elevation)',
    defaultValue: 3.0,
    min: 0,
    max: 24,
    divisions: 24,
  ),
  _shapeDescriptor,
  NativePropertyDescriptor.number(
    id: 'notchMargin',
    label: 'Marge d’encoche (FAB)',
    subtitle: 'Espace entre le bouton flottant et l’encoche (notchMargin)',
    defaultValue: 4.0,
    min: 0,
    max: 24,
    divisions: 24,
  ),
  // Dimensions, marges & découpage
  NativePropertyDescriptor.number(
    id: 'padding',
    label: 'Marge intérieure (Padding)',
    subtitle: 'Espacement interne autour du contenu de la barre (padding)',
    defaultValue: 0.0,
    min: 0,
    max: 48,
    divisions: 48,
  ),
  _barClipBehaviorDescriptor,
];

/// Catalogue déclaratif des propriétés de style Flutter disponibles sur [SuperBottomNavigationBar].
const List<NativePropertyDescriptor>
superBottomNavigationBarPropertyDescriptors = [
  // Couleurs
  NativePropertyDescriptor.color(
    id: 'backgroundColor',
    label: 'Couleur de fond',
    subtitle: 'Arrière-plan de la barre de navigation (backgroundColor)',
  ),
  NativePropertyDescriptor.color(
    id: 'selectedItemColor',
    label: 'Couleur de l’élément sélectionné',
    subtitle: 'Couleur de l’icône et du libellé actifs (selectedItemColor)',
  ),
  NativePropertyDescriptor.color(
    id: 'unselectedItemColor',
    label: 'Couleur des éléments non sélectionnés',
    subtitle: 'Couleur des icônes et libellés inactifs (unselectedItemColor)',
  ),
  // Élévation & dimensions
  NativePropertyDescriptor.number(
    id: 'elevation',
    label: 'Élévation',
    subtitle: 'Hauteur de l’ombre portée de la barre (elevation)',
    defaultValue: 8.0,
    min: 0,
    max: 24,
    divisions: 24,
  ),
  NativePropertyDescriptor.number(
    id: 'iconSize',
    label: 'Taille des icônes',
    subtitle: 'Taille en pixels des icônes des destinations (iconSize)',
    defaultValue: 24.0,
    min: 12,
    max: 48,
    divisions: 36,
  ),
  NativePropertyDescriptor.number(
    id: 'selectedFontSize',
    label: 'Taille du texte sélectionné',
    subtitle: 'Taille de police du libellé actif (selectedFontSize)',
    defaultValue: 14.0,
    min: 8,
    max: 32,
    divisions: 24,
  ),
  NativePropertyDescriptor.number(
    id: 'unselectedFontSize',
    label: 'Taille du texte non sélectionné',
    subtitle: 'Taille de police des libellés inactifs (unselectedFontSize)',
    defaultValue: 12.0,
    min: 8,
    max: 32,
    divisions: 24,
  ),
  // Disposition, libellés & comportement
  NativePropertyDescriptor.select(
    id: 'navigationBarType',
    label: 'Type de barre',
    subtitle: 'Mode de disposition des destinations (type)',
    options: [
      NativePropertyOption(value: 'fixed', label: 'Fixe (fixed)'),
      NativePropertyOption(
        value: 'shifting',
        label: 'Animé / décalé (shifting)',
      ),
    ],
  ),
  NativePropertyDescriptor.select(
    id: 'landscapeLayout',
    label: 'Disposition en mode paysage',
    subtitle: 'Agencement des destinations à l’horizontale (landscapeLayout)',
    options: [
      NativePropertyOption(value: 'spread', label: 'Réparti (spread)'),
      NativePropertyOption(value: 'centered', label: 'Centré (centered)'),
      NativePropertyOption(
        value: 'linear',
        label: 'Linéaire côte à côte (linear)',
      ),
    ],
  ),
  NativePropertyDescriptor.flag(
    id: 'showSelectedLabels',
    label: 'Afficher le libellé sélectionné',
    subtitle:
        'Affiche le texte sous la destination active (showSelectedLabels)',
    defaultValue: true,
  ),
  NativePropertyDescriptor.flag(
    id: 'showUnselectedLabels',
    label: 'Afficher les libellés non sélectionnés',
    subtitle: 'Affiche le texte sous les destinations inactives (showUnselectedLabels)',
    defaultValue: true,
  ),
  NativePropertyDescriptor.flag(
    id: 'enableFeedback',
    label: 'Retour haptique et sonore',
    subtitle: 'Active les vibrations et sons système au clic (enableFeedback)',
    defaultValue: true,
  ),
  NativePropertyDescriptor.flag(
    id: 'useLegacyColorScheme',
    label: 'Schéma de couleurs hérité',
    subtitle: 'Applique la logique classique des couleurs d’icônes et libellés (useLegacyColorScheme)',
    defaultValue: true,
  ),
  NativePropertyDescriptor.select(
    id: 'mouseCursor',
    label: 'Curseur de la souris',
    subtitle: 'Apparence du pointeur au survol des destinations (mouseCursor)',
    options: [
      NativePropertyOption(value: 'click', label: 'Main cliquable (click)'),
      NativePropertyOption(value: 'basic', label: 'Flèche standard (basic)'),
      NativePropertyOption(value: 'defer', label: 'Hérité du parent (defer)'),
      NativePropertyOption(value: 'none', label: 'Masqué (none)'),
    ],
  ),
];

/// Descripteur de la propriété `toggleIcon` partagée par [SuperExpansible] et [SuperMenuAnchor].
const NativePropertyDescriptor toggleIconPropertyDescriptor =
    NativePropertyDescriptor.select(
      id: 'toggleIcon',
      label: 'Icône ouvert / fermé',
      subtitle: 'Indicateur visuel de l’état déplié ou replié dans l’en-tête',
      defaultValue: 'none',
      nullable: false,
      options: [
        NativePropertyOption(value: 'none', label: 'Aucune (none)'),
        NativePropertyOption(
          value: 'chevron',
          label: 'Chevron (expand_more / expand_less)',
        ),
        NativePropertyOption(
          value: 'arrow',
          label: 'Flèche (arrow_downward / arrow_upward)',
        ),
        NativePropertyOption(
          value: 'plusMinus',
          label: 'Plus / Moins (add / remove)',
        ),
        NativePropertyOption(
          value: 'triangle',
          label: 'Triangle (arrow_drop_down / arrow_drop_up)',
        ),
      ],
    );

/// Descripteur de la propriété `toggleIconPosition` partagée par [SuperExpansible] et [SuperMenuAnchor].
const NativePropertyDescriptor
toggleIconPositionPropertyDescriptor = NativePropertyDescriptor.select(
  id: 'toggleIconPosition',
  label: 'Position de l’icône',
  subtitle: 'Emplacement de l’icône ouvert / fermé dans l’en-tête',
  defaultValue: 'trailing',
  nullable: false,
  options: [
    NativePropertyOption(value: 'trailing', label: 'Fin / Droite (trailing)'),
    NativePropertyOption(value: 'leading', label: 'Début / Gauche (leading)'),
  ],
);

/// Résout l’icône Material correspondant au style `toggleIcon` et à l’état [expanded].
///
/// Retourne `null` lorsque [style] est `null`, `'none'` ou inconnu.
IconData? resolveNativeToggleIcon(String? style, {required bool expanded}) =>
    switch (style?.trim()) {
      'chevron' => expanded ? Icons.expand_less : Icons.expand_more,
      'arrow' => expanded ? Icons.arrow_upward : Icons.arrow_downward,
      'plusMinus' => expanded ? Icons.remove : Icons.add,
      'triangle' => expanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
      _ => null,
    };

/// Retourne le libellé lisible d’un style `toggleIcon`.
String nativeToggleIconLabel(String? style) => switch (style?.trim()) {
  'chevron' => 'Chevron',
  'arrow' => 'Flèche',
  'plusMinus' => 'Plus / Moins',
  'triangle' => 'Triangle',
  _ => 'Aucune',
};

/// Retourne le libellé lisible d’une position `toggleIconPosition`.
String nativeToggleIconPositionLabel(String? position) =>
    switch (position?.trim()) {
      'leading' => 'Début / Gauche',
      _ => 'Fin / Droite',
    };

/// Catalogue déclaratif des propriétés de comportement de [SuperExpansible].
const List<NativePropertyDescriptor> superExpansiblePropertyDescriptors = [
  _initiallyExpandedDescriptor,
  _headerClickTogglesDescriptor,
  NativePropertyDescriptor.flag(
    id: 'maintainState',
    label: 'Maintenir l’état fermé',
    defaultValue: true,
  ),
  toggleIconPropertyDescriptor,
  toggleIconPositionPropertyDescriptor,
];

/// Catalogue déclaratif des propriétés de comportement de [SuperMenuAnchor].
const List<NativePropertyDescriptor> superMenuAnchorPropertyDescriptors = [
  _initiallyExpandedDescriptor,
  _headerClickTogglesDescriptor,
  NativePropertyDescriptor.flag(
    id: 'consumeOutsideTap',
    label: 'Consommer le clic extérieur',
    subtitle: 'Empêche le clic fermant le menu d’activer l’élément sous-jacent',
    defaultValue: false,
  ),
  toggleIconPropertyDescriptor,
  toggleIconPositionPropertyDescriptor,
  NativePropertyDescriptor.number(
    id: 'alignmentOffsetX',
    label: 'Décalage horizontal (X)',
    subtitle: 'Décalage en pixels sur l’axe horizontal (alignmentOffset.dx)',
    defaultValue: 0.0,
    min: -200,
    max: 200,
    divisions: 80,
  ),
  NativePropertyDescriptor.number(
    id: 'alignmentOffsetY',
    label: 'Décalage vertical (Y)',
    subtitle: 'Décalage en pixels sur l’axe vertical (alignmentOffset.dy)',
    defaultValue: 0.0,
    min: -200,
    max: 200,
    divisions: 80,
  ),
];

/// Catalogue déclaratif des propriétés supplémentaires de [SuperAppBar] en mode `SliverAppBar`.
const List<NativePropertyDescriptor> superSliverAppBarPropertyDescriptors = [
  NativePropertyDescriptor.flag(
    id: 'pinned',
    label: 'Épingler la barre (pinned)',
    subtitle: 'Garde la barre visible en haut lors du défilement',
    defaultValue: false,
  ),
  NativePropertyDescriptor.flag(
    id: 'floating',
    label: 'Barre flottante (floating)',
    subtitle: 'Réapparaît dès que l’utilisateur défile vers le haut',
    defaultValue: false,
  ),
  NativePropertyDescriptor.flag(
    id: 'snap',
    label: 'Magnétisme (snap)',
    subtitle: 'Anime complètement l’apparition/disparition (requiert floating)',
    defaultValue: false,
  ),
  NativePropertyDescriptor.flag(
    id: 'stretch',
    label: 'Étirement (stretch)',
    subtitle: 'Autorise l’étirement de la barre lors d’un sur-défilement',
    defaultValue: false,
  ),
  NativePropertyDescriptor.number(
    id: 'stretchTriggerOffset',
    label: 'Seuil d’étirement (stretchTriggerOffset)',
    subtitle: 'Distance de sur-défilement en pixels déclenchant l’étirement',
    defaultValue: 100.0,
    min: 10,
    max: 300,
    divisions: 58,
  ),
  NativePropertyDescriptor.number(
    id: 'expandedHeight',
    label: 'Hauteur étendue (expandedHeight)',
    subtitle: 'Hauteur maximale de la barre complètement déployée',
    defaultValue: 160.0,
    min: 56,
    max: 400,
    divisions: 172,
  ),
  NativePropertyDescriptor.number(
    id: 'collapsedHeight',
    label: 'Hauteur réduite (collapsedHeight)',
    subtitle: 'Hauteur minimale de la barre repliée',
    defaultValue: 56.0,
    min: 32,
    max: 200,
    divisions: 84,
  ),
  NativePropertyDescriptor.flag(
    id: 'forceElevated',
    label: 'Forcer l’élévation (forceElevated)',
    subtitle:
        'Affiche l’ombre même lorsque le contenu ne défile pas sous la barre',
    defaultValue: false,
  ),
  NativePropertyDescriptor.flag(
    id: 'useDefaultSemanticsOrder',
    label: 'Ordre sémantique par défaut (useDefaultSemanticsOrder)',
    subtitle: 'Utilise l’ordre standard d’accessibilité dans la barre sliver',
    defaultValue: true,
  ),
  NativePropertyDescriptor.number(
    id: 'actionsPadding',
    label: 'Marge des actions (actionsPadding)',
    subtitle: 'Marge horizontale intérieure autour de la zone Actions',
    defaultValue: 0.0,
    min: 0,
    max: 48,
    divisions: 48,
  ),
];

/// Catalogue déclaratif des propriétés de mise en page et défilement de [ScaffoldPageLayout].
const List<NativePropertyDescriptor> scaffoldPagePropertyDescriptors = [
  NativePropertyDescriptor.select(
    id: 'bodyMode',
    label: 'Mode du corps (Body)',
    subtitle: 'Conteneur principal de la zone Corps de la page',
    defaultValue: 'standard',
    nullable: false,
    options: [
      NativePropertyOption(
        value: 'standard',
        label: 'Standard (Fixe / plein écran)',
      ),
      NativePropertyOption(
        value: 'singleChildScrollView',
        label: 'Défilement simple (SingleChildScrollView)',
      ),
      NativePropertyOption(
        value: 'customScrollView',
        label: 'Défilement Slivers (CustomScrollView)',
      ),
    ],
  ),
  NativePropertyDescriptor.flag(
    id: 'extendBodyBehindAppBar',
    label: 'Étendre le corps derrière l’AppBar (extendBodyBehindAppBar)',
    subtitle: 'Fait passer la zone Corps sous l’AppBar en haut de la page',
    defaultValue: false,
  ),
  NativePropertyDescriptor.flag(
    id: 'extendBody',
    label: 'Étendre le corps sous la barre basse (extendBody)',
    subtitle: 'Fait passer la zone Corps derrière la barre de navigation basse',
    defaultValue: false,
  ),
  NativePropertyDescriptor.select(
    id: 'scrollDirection',
    label: 'Axe de défilement',
    subtitle:
        'Direction du défilement pour SingleChildScrollView / CustomScrollView',
    defaultValue: 'vertical',
    options: [
      NativePropertyOption(value: 'vertical', label: 'Vertical (vertical)'),
      NativePropertyOption(
        value: 'horizontal',
        label: 'Horizontal (horizontal)',
      ),
    ],
  ),
  NativePropertyDescriptor.flag(
    id: 'reverse',
    label: 'Inverser le sens de défilement',
    subtitle: 'Défile en sens inverse sur l’axe principal (reverse)',
    defaultValue: false,
  ),
  NativePropertyDescriptor.flag(
    id: 'primary',
    label: 'Défilement principal (primary)',
    subtitle: 'Utilise le PrimaryScrollController de la page',
    defaultValue: true,
  ),
  NativePropertyDescriptor.number(
    id: 'scrollPadding',
    label: 'Marge intérieure du défilement',
    subtitle: 'Espacement interne autour du contenu défilant (padding)',
    defaultValue: 0.0,
    min: 0,
    max: 64,
    divisions: 64,
  ),
  NativePropertyDescriptor.select(
    id: 'clipBehavior',
    label: 'Découpage (Clip)',
    subtitle: 'Mode de découpage de la zone de défilement',
    options: _clipBehaviorOptions,
  ),
];
