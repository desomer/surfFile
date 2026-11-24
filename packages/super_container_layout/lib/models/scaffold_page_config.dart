/// Configuration structurelle ([ScaffoldPageConfig] / [SuperScaffoldConfig]) du `Scaffold` d'une page.
///
/// Gère l'activation des régions de niveau page (`appBar`, `body`,
/// `sidebarStart`, `sidebarEnd`, `drawer`, `endDrawer`, `bottomNavigationBar`,
/// `floatingActionButton`, `bottomSheet`), la portée de l'en-tête
/// ([ScaffoldHeaderSpan]), les dimensions des panneaux latéraux, le mode de
/// défilement ([ScaffoldBodyMode]) et les options de redimensionnement.
library;

import 'dart:ui' show Clip;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show Axis;

import 'component_config.dart';
import 'json_text_binding.dart';
import 'native_component_config.dart';
import 'native_property_descriptor.dart';

/// Régions structurelles natives détenues par un `Scaffold` / `SuperScaffold`.
enum ScaffoldPageRegion {
  /// Barre d'en-tête supérieure (`appBar`).
  appBar,

  /// Zone principale de contenu (`body`), toujours active.
  body,

  /// Panneau latéral fixe au début (gauche en LTR).
  sidebarStart,

  /// Panneau latéral fixe à la fin (droite en LTR).
  sidebarEnd,

  /// Tiroir latéral gauche (`drawer`).
  drawer,

  /// Tiroir latéral droit (`endDrawer`).
  endDrawer,

  /// Barre de navigation inférieure (`bottomNavigationBar`).
  bottomNavigationBar,

  /// Bouton d'action flottant (`floatingActionButton`).
  floatingActionButton,

  /// Feuille inférieure persistante (`bottomSheet`).
  bottomSheet,
}

/// Alias canonique de [ScaffoldPageRegion] pour l'API `SuperScaffold`.
typedef SuperScaffoldRegion = ScaffoldPageRegion;

/// Portée horizontale de la barre d'en-tête (`appBar`) vis-à-vis des panneaux
/// latéraux (`sidebarStart`, `sidebarEnd`).
enum ScaffoldHeaderSpan {
  /// L'en-tête occupe toute la largeur de la page, au-dessus des panneaux latéraux.
  fullWidth,

  /// L'en-tête est restreint à la zone centrale, entre les panneaux latéraux.
  contentOnly;

  /// Résout un [ScaffoldHeaderSpan] depuis son nom sérialisé.
  static ScaffoldHeaderSpan fromName(String? name) => name == 'contentOnly'
      ? ScaffoldHeaderSpan.contentOnly
      : ScaffoldHeaderSpan.fullWidth;
}

/// Mode d'affichage et de défilement de la zone `body` du `Scaffold`.
enum ScaffoldBodyMode {
  /// Zone `body` fixe occupant tout l'espace disponible (`SizedBox.expand`).
  standard,

  /// Zone `body` englobée dans un `SingleChildScrollView`.
  singleChildScrollView,

  /// Page en mode `CustomScrollView` (avec slivers pour `appBar` et `body`).
  customScrollView;

  /// Résout un [ScaffoldBodyMode] depuis son nom sérialisé.
  static ScaffoldBodyMode fromName(String? name) => switch (name) {
    'singleChildScrollView' => ScaffoldBodyMode.singleChildScrollView,
    'customScrollView' => ScaffoldBodyMode.customScrollView,
    _ => ScaffoldBodyMode.standard,
  };
}

/// API typée de configuration d'un `Scaffold` / `SuperScaffold` de page.
@immutable
class ScaffoldPageConfig extends ComponentConfig {
  /// Largeur minimale autorisée (en pixels) pour un panneau latéral.
  static const double minSidebarWidth = 48.0;

  /// Largeur maximale autorisée (en pixels) pour un panneau latéral.
  static const double maxSidebarWidth = 2000.0;

  /// Descripteurs déclaratifs des propriétés éditables d'un `Scaffold`.
  static const List<NativePropertyDescriptor> propertyDescriptors =
      scaffoldPagePropertyDescriptors;

  static double _validateSidebarWidth(String name, double width) {
    if (!width.isFinite || width < minSidebarWidth || width > maxSidebarWidth) {
      throw ArgumentError.value(
        width,
        name,
        'Sidebar width must be finite and between '
        '${minSidebarWidth.toInt()} and ${maxSidebarWidth.toInt()}.',
      );
    }
    return width;
  }

  ScaffoldPageConfig({
    Map<ScaffoldPageRegion, List<String>> placements = const {},
    Map<String, String> slotTypes = const {},
    Map<ScaffoldPageRegion, bool> regions = const {},
    Map<String, Object> properties = const {},
    ScaffoldBodyMode? bodyMode,
    ScaffoldHeaderSpan? headerSpan,
    double? sidebarStartWidth,
    double? sidebarEndWidth,
    bool? responsiveSidebarToDrawer,
    bool? extendBody,
    bool? extendBodyBehindAppBar,
    Axis? scrollDirection,
    bool? reverse,
    bool? primary,
    double? scrollPadding,
    Clip? clipBehavior,
  }) : this.fromNative(
         NativeComponentConfig(
           properties: {
             ...properties,
             if (bodyMode != null && bodyMode != ScaffoldBodyMode.standard)
               'bodyMode': bodyMode.name,
             if (headerSpan != null &&
                 headerSpan != ScaffoldHeaderSpan.fullWidth)
               'headerSpan': headerSpan.name,
             if (sidebarStartWidth != null)
               'sidebarStartWidth': _validateSidebarWidth(
                 'sidebarStartWidth',
                 sidebarStartWidth,
               ),
             if (sidebarEndWidth != null)
               'sidebarEndWidth': _validateSidebarWidth(
                 'sidebarEndWidth',
                 sidebarEndWidth,
               ),
             'responsiveSidebarToDrawer': ?responsiveSidebarToDrawer,
             'extendBody': ?extendBody,
             'extendBodyBehindAppBar': ?extendBodyBehindAppBar,
             if (scrollDirection != null)
               'scrollDirection': scrollDirection.name,
             'reverse': ?reverse,
             'primary': ?primary,
             'scrollPadding': ?scrollPadding,
             if (clipBehavior != null) 'clipBehavior': clipBehavior.name,
           },
           placements: {
             for (final entry in placements.entries)
               entry.key.name: entry.value,
           },
           slotTypes: slotTypes,
           regions: {
             for (final entry in regions.entries) entry.key.name: entry.value,
           },
         ),
       );

  /// Crée un [ScaffoldPageConfig] à partir de sa représentation [NativeComponentConfig].
  ScaffoldPageConfig.fromNative(this.native) {
    validate();
  }

  /// Configuration native sous-jacente portant les propriétés, régions et placements.
  final NativeComponentConfig native;

  Map<ScaffoldPageRegion, List<String>> get placements => Map.unmodifiable({
    for (final region in ScaffoldPageRegion.values)
      if (native.placements.containsKey(region.name))
        region: native.slotsOf(region.name),
  });
  Map<String, String> get slotTypes => native.slotTypes;
  Map<ScaffoldPageRegion, bool> get regions => Map.unmodifiable({
    for (final region in ScaffoldPageRegion.values)
      if (native.regions.containsKey(region.name))
        region: native.regions[region.name]!,
  });

  /// Mode d'affichage et de défilement de la zone `body`.
  ScaffoldBodyMode get bodyMode =>
      ScaffoldBodyMode.fromName(native.stringProperty('bodyMode'));

  /// Portée horizontale de la barre d'en-tête (`appBar`).
  ScaffoldHeaderSpan get headerSpan =>
      ScaffoldHeaderSpan.fromName(native.stringProperty('headerSpan'));

  /// Largeur fixe optionnelle du panneau latéral gauche (`sidebarStart`).
  double? get sidebarStartWidth => native.doubleProperty('sidebarStartWidth');

  /// Largeur fixe optionnelle du panneau latéral droit (`sidebarEnd`).
  double? get sidebarEndWidth => native.doubleProperty('sidebarEndWidth');

  /// Indique si `sidebarStart` se replie automatiquement dans le `drawer` sur écran étroit.
  bool get responsiveSidebarToDrawer =>
      native.boolProperty('responsiveSidebarToDrawer') ?? false;

  bool get extendBody => native.boolProperty('extendBody') ?? false;

  bool get extendBodyBehindAppBar =>
      native.boolProperty('extendBodyBehindAppBar') ?? false;

  Axis get scrollDirection => switch (native.stringProperty('scrollDirection')) {
    'horizontal' => Axis.horizontal,
    _ => Axis.vertical,
  };

  bool get reverse => native.boolProperty('reverse') ?? false;

  bool? get primary => native.boolProperty('primary');

  double? get scrollPadding => native.doubleProperty('scrollPadding');

  Clip? get clipBehavior => switch (native.stringProperty('clipBehavior')) {
    'none' => Clip.none,
    'hardEdge' => Clip.hardEdge,
    'antiAlias' => Clip.antiAlias,
    'antiAliasWithSaveLayer' => Clip.antiAliasWithSaveLayer,
    _ => null,
  };

  @override
  void validate() {
    native.validate();
    final names = ScaffoldPageRegion.values.map((region) => region.name).toSet();
    if (native.regions['body'] == false ||
        native.regions.keys.any((name) => !names.contains(name)) ||
        native.placements.keys.any((name) => !names.contains(name))) {
      throw ArgumentError('Invalid Scaffold regions; body must remain enabled.');
    }
    final startWidth = sidebarStartWidth;
    if (startWidth != null) {
      _validateSidebarWidth('sidebarStartWidth', startWidth);
    }
    final endWidth = sidebarEndWidth;
    if (endWidth != null) {
      _validateSidebarWidth('sidebarEndWidth', endWidth);
    }
  }

  bool isEnabled(ScaffoldPageRegion region) =>
      region == ScaffoldPageRegion.body || native.isEnabled(region.name);
  String slotTypeOf(String id) => native.slotTypeOf(id);
  List<String> slotsOf(ScaffoldPageRegion region) => native.slotsOf(region.name);
  ScaffoldPageConfig withRegionEnabled(ScaffoldPageRegion region, bool enabled) =>
      ScaffoldPageConfig.fromNative(native.withRegionEnabled(region.name, enabled));
  ScaffoldPageConfig withSlotAdded(String id, ScaffoldPageRegion region, {String? type}) =>
      ScaffoldPageConfig.fromNative(native.withSlotAdded(id, region.name, type: type));
  ScaffoldPageConfig withoutSlot(String id) =>
      ScaffoldPageConfig.fromNative(native.withoutSlot(id));
  ScaffoldPageConfig withProperty(String id, Object? value) =>
      ScaffoldPageConfig.fromNative(native.withProperty(id, value));
  ScaffoldPageConfig withBodyMode(ScaffoldBodyMode? mode) =>
      withProperty(
        'bodyMode',
        mode == null || mode == ScaffoldBodyMode.standard ? null : mode.name,
      );

  /// Retourne une copie avec la portée horizontale d'en-tête mise à jour.
  ScaffoldPageConfig withHeaderSpan(ScaffoldHeaderSpan? span) => withProperty(
    'headerSpan',
    span == null || span == ScaffoldHeaderSpan.fullWidth ? null : span.name,
  );

  /// Retourne une copie avec la largeur de `sidebarStart` mise à jour.
  ScaffoldPageConfig withSidebarStartWidth(double? width) => withProperty(
    'sidebarStartWidth',
    width == null ? null : _validateSidebarWidth('sidebarStartWidth', width),
  );

  /// Retourne une copie avec la largeur de `sidebarEnd` mise à jour.
  ScaffoldPageConfig withSidebarEndWidth(double? width) => withProperty(
    'sidebarEndWidth',
    width == null ? null : _validateSidebarWidth('sidebarEndWidth', width),
  );

  /// Retourne une copie avec l'option de repli responsive de `sidebarStart` mise à jour.
  ScaffoldPageConfig withResponsiveSidebarToDrawer(bool? responsive) =>
      withProperty('responsiveSidebarToDrawer', responsive);

  ScaffoldPageConfig withExtendBody(bool? extendBody) =>
      withProperty('extendBody', extendBody);
  ScaffoldPageConfig withExtendBodyBehindAppBar(bool? extendBodyBehindAppBar) =>
      withProperty('extendBodyBehindAppBar', extendBodyBehindAppBar);
  ScaffoldPageConfig withScrollDirection(Axis? direction) =>
      withProperty('scrollDirection', direction?.name);
  ScaffoldPageConfig withReverse(bool? reverse) =>
      withProperty('reverse', reverse);
  ScaffoldPageConfig withPrimary(bool? primary) =>
      withProperty('primary', primary);
  ScaffoldPageConfig withScrollPadding(double? padding) =>
      withProperty('scrollPadding', padding);
  ScaffoldPageConfig withClipBehavior(Clip? clip) =>
      withProperty('clipBehavior', clip?.name);

  @override
  String get componentType => 'scaffold';

  @override
  Iterable<JsonTextBinding> get referencedBindings => native.referencedBindings;

  @override
  ScaffoldPageConfig patchFromJson(Map<Object?, Object?> patch) =>
      ScaffoldPageConfig.fromJson({...toJson(), ...patch});

  @override
  Map<String, Object> toJson() => native.toJson();

  @override
  Map<String, Object?> toCompactJson() {
    final compact = Map<String, Object?>.of(native.toCompactJson());
    if (compact['bodyMode'] == ScaffoldBodyMode.standard.name) {
      compact.remove('bodyMode');
    }
    if (compact['headerSpan'] == ScaffoldHeaderSpan.fullWidth.name) {
      compact.remove('headerSpan');
    }
    if (compact['responsiveSidebarToDrawer'] == false) {
      compact.remove('responsiveSidebarToDrawer');
    }
    return compact;
  }

  /// Désérialise un [ScaffoldPageConfig] depuis sa représentation JSON.
  factory ScaffoldPageConfig.fromJson(Object? value) {
    try {
      return ScaffoldPageConfig.fromNative(
        NativeComponentConfig.fromJson(value),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid Scaffold configuration: ${error.message}');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScaffoldPageConfig && other.native == native);

  @override
  int get hashCode => native.hashCode;
}

/// Alias canonique de [ScaffoldPageConfig] pour l'API `SuperScaffold`.
typedef SuperScaffoldConfig = ScaffoldPageConfig;
