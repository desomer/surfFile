import 'package:flutter/painting.dart' show Axis;
import 'package:material_ui/material_ui.dart' show Color, Size, ThemeMode;
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;

import '../../models/component_config.dart';
import '../../models/editor_page_config.dart';
import '../../models/json_syntax.dart';
import '../../models/native_component_config.dart';
import '../../models/scaffold_page_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_list_view_config.dart';
import '../../models/super_value_config.dart';
import '../../models/super_action_config.dart';
import '../../theme/appearance.dart';
import '../../theme/container_style.dart';

/// Compilateur bidirectionnel et moteur incrémental ("Vibe") permettant à une IA
/// de décrire un écran en 1 phase (arbre hiérarchique imbriqué) ou étape par étape
/// (fusion partielle par ID et opérations atomiques `ops`).
abstract final class ScreenTreeCodec {
  static const Set<String> _scaffoldRegions = {
    'appBar',
    'body',
    'drawer',
    'endDrawer',
    'bottomNavigationBar',
    'floatingActionButton',
    'bottomSheet',
  };

  static const Set<String> _appBarRegions = {
    'leading',
    'title',
    'actions',
    'bottom',
    'flexibleSpace',
  };

  static const Set<String> _bottomBarRegions = {'left', 'center', 'right'};

  static const Set<String> _styleKeys = {
    'color',
    'fill',
    'radius',
    'borderWidth',
    'borderColor',
    'elevation',
    'shadowOpacity',
    'neon',
    'padding',
    'margin',
    'designSystem',
    'interactionEffect',
    'hoverEffect',
    'hoverTint',
    'hoverColor',
    'radii',
    'borderWidths',
    'borderLine',
    'shadow',
    'innerShadow',
    'opacity',
    'paddingInsets',
    'marginInsets',
    'backdropBlur',
    'pattern',
    'patternOpacity',
    'transform',
    'states',
  };

  static const Set<String> _valueKeys = {
    'mode',
    'kind',
    'initialText',
    'text',
    'initialBool',
    'value',
    'label',
    'placeholder',
    'enabled',
    'readOnly',
    'obscureText',
    'minLines',
    'maxLines',
    'fontFamily',
    'fontSize',
    'fontWeight',
    'italic',
    'color',
    'textAlign',
    'lineHeight',
    'letterSpacing',
    'binding',
    'propertyBindings',
    'field',
    'states',
  };

  static const Set<String> _actionKeys = {
    'kind',
    'variant',
    'label',
    'text',
    'tooltip',
    'icon',
    'iconPosition',
    'iconSize',
    'iconSpacing',
    'enabled',
    'fontFamily',
    'fontSize',
    'fontWeight',
    'italic',
    'color',
    'iconColor',
    'backgroundColor',
    'borderColor',
    'radius',
    'borderWidth',
    'elevation',
    'horizontalPadding',
    'verticalPadding',
    'textAlign',
    'letterSpacing',
    'style',
    'propertyBindings',
    'states',
  };

  static const Set<String> _listKeys = {
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

  static const Set<String> _layoutKeys = {
    'north',
    'south',
    'west',
    'east',
    'nw',
    'ne',
    'sw',
    'se',
    'northSize',
    'southSize',
    'westSize',
    'eastSize',
    'resizeSides',
    'sideResizing',
    'collapsedSides',
    'swaps',
    'autoSides',
    'zoneAxes',
    'slotPreferredSizes',
    'slotSizeConstraints',
    'label',
    'slotLabels',
    'positioning',
    'grid',
    'placements',
    'zones',
  };

  /// Indique si un document JSON utilise les extensions IA (arbre `screens`,
  /// opérations `ops`, mode `vibe`/`merge` ou nœuds inline).
  static bool isAiDocument(Map<String, dynamic> json) =>
      json.containsKey('screens') ||
      json.containsKey('ops') ||
      json['vibe'] == true ||
      json['merge'] == true ||
      json['mode'] == 'vibe' ||
      _hasInlineNodes(json);

  static bool _hasInlineNodes(Map<String, dynamic> json) {
    final layouts = json['layouts'];
    if (layouts is Map) {
      for (final layout in layouts.values) {
        if (layout is Map) {
          if (layout.containsKey('zones')) return true;
          final placements = layout['placements'];
          if (placements is Map) {
            for (final list in placements.values) {
              if (list is Map) return true;
              if (list is List) {
                for (final item in list) {
                  if (item is Map &&
                      item.keys.any((k) => k != 'id' && k != 'type')) {
                    return true;
                  }
                }
              }
            }
          }
        }
      }
    }
    final comps = json['components'];
    if (comps is Map) {
      for (final comp in comps.values) {
        if (comp is Map) {
          if (comp.keys.any(
            (k) =>
                _scaffoldRegions.contains(k) ||
                _appBarRegions.contains(k) ||
                _bottomBarRegions.contains(k) ||
                k == 'child',
          )) {
            return true;
          }
          final placements = comp['placements'];
          if (placements is Map) {
            for (final list in placements.values) {
              if (list is Map) return true;
              if (list is List) {
                for (final item in list) {
                  if (item is Map &&
                      item.keys.any((k) => k != 'id' && k != 'type')) {
                    return true;
                  }
                }
              }
            }
          }
        }
      }
    }
    return false;
  }

  /// Normalise et compile un document JSON complet ou partiel (incluant `screens`,
  /// nœuds inline dans `layouts`/`nativeComponents`, couleurs hexadécimales et `ops`)
  /// vers une map JSON canonique prête pour `AppearanceCodec.fromJson`, en partant
  /// optionnellement de l'état [base] lorsqu'on est en mode fusion / Vibe.
  static Map<String, dynamic> expandToCanonicalJson(
    Map<String, dynamic> input, {
    Appearance? base,
    bool forceMerge = false,
  }) {
    final isMerge =
        forceMerge ||
        input['vibe'] == true ||
        input['merge'] == true ||
        input['mode'] == 'vibe' ||
        input.containsKey('ops');

    var working = base ?? Appearance();
    final state = _CompilationState.fromAppearance(
      isMerge ? working : Appearance(),
    );

    // 1. Préférences de thème / fenêtre
    ThemeMode mode = isMerge ? working.mode : ThemeMode.light;
    if (input.containsKey('mode') && input['mode'] != 'vibe') {
      final rawMode = input['mode'];
      final parsedMode = ThemeMode.values
          .where((v) => v.name == rawMode)
          .firstOrNull;
      if (parsedMode == null) {
        throw const FormatException('Invalid theme or window preferences.');
      }
      mode = parsedMode;
    }

    Color accent = isMerge ? working.accent : const Color(0xFF5268D9);
    if (input.containsKey('accent') && input['accent'] != null) {
      try {
        accent = JsonColor.parse(input['accent'], 'accent');
      } on FormatException {
        throw const FormatException('Invalid theme or window preferences.');
      }
    }

    double numberPref(String key, double fallbackVal, double min, double max) {
      final v = input[key] ?? fallbackVal;
      if (v is! num || !v.isFinite || v < min || v > max) {
        throw FormatException('Invalid "$key".');
      }
      return v.toDouble();
    }

    final backgroundOpacity = numberPref(
      'backgroundOpacity',
      isMerge ? working.backgroundOpacity : 1.0,
      0.0,
      1.0,
    );
    final windowOpacity = numberPref(
      'windowOpacity',
      isMerge ? working.windowOpacity : 1.0,
      0.2,
      1.0,
    );

    WindowEffect windowEffect = isMerge
        ? working.windowEffect
        : WindowEffect.transparent;
    if (input.containsKey('windowEffect') && input['windowEffect'] != null) {
      final parsedEffect = WindowEffect.values
          .where((v) => v.name == input['windowEffect'])
          .firstOrNull;
      if (parsedEffect == null) {
        throw const FormatException('Invalid theme or window preferences.');
      }
      windowEffect = parsedEffect;
    }

    // 2. Dictionnaires plats explicites (styles, components, layouts, pageCatalog)
    if (input.containsKey('styles')) {
      final rawStyles = input['styles'];
      if (rawStyles is! Map) {
        throw const FormatException('Invalid "styles" map.');
      }
      for (final entry in rawStyles.entries) {
        final id = _requireId(entry.key, 'styles');
        if (entry.value is! Map) {
          throw const FormatException('Invalid "styles" map.');
        }
        final existing = state.styles[id];
        state.styles[id] = existing != null && isMerge
            ? existing.patchFromJson(entry.value as Map)
            : ContainerStyle.fromJson(entry.value);
      }
    }

    if (input.containsKey('components') && input['components'] != null) {
      final rawComponents = input['components'];
      if (rawComponents is! Map) {
        throw const FormatException('Invalid "components" map.');
      }
      for (final entry in rawComponents.entries) {
        final id = _requireId(entry.key, 'components');
        if (entry.value is! Map) {
          throw const FormatException('Invalid "components" map.');
        }
        final map = entry.value as Map;
        final rawType = map['type'] ?? map['componentType'];
        final payload = <String, Object?>{
          for (final e in map.entries)
            if (e.key is String &&
                e.key != 'type' &&
                e.key != 'componentType')
              e.key as String: e.value,
        };
        if (rawType == 'native' ||
            (rawType == null &&
                map.keys.any(
                  (k) =>
                      k == 'placements' ||
                      k == 'regions' ||
                      _scaffoldRegions.contains(k) ||
                      _appBarRegions.contains(k) ||
                      _bottomBarRegions.contains(k) ||
                      k == 'child',
                ))) {
          state.compileNativeMap(id, payload, isMerge: isMerge);
        } else {
          final existing = state.components[id];
          if (existing != null &&
              isMerge &&
              (rawType == null || existing.componentType == rawType)) {
            state.components[id] = existing.patchFromJson(payload);
          } else {
            state.components[id] = ComponentConfig.fromJson(map);
          }
        }
      }
    }

    if (input.containsKey('layouts')) {
      final rawLayouts = input['layouts'];
      if (rawLayouts is! Map) {
        throw const FormatException('Invalid "layouts" map.');
      }
      for (final entry in rawLayouts.entries) {
        final id = _requireId(entry.key, 'layouts');
        if (entry.value is! Map) {
          throw const FormatException('Invalid "layouts" map.');
        }
        state.compileLayoutMap(id, entry.value as Map, isMerge: isMerge);
      }
    }

    if (input.containsKey('pageCatalog')) {
      final catalog = EditorPageCatalog.fromJson(input['pageCatalog']);
      if (isMerge && state.pages.isNotEmpty) {
        for (final page in catalog.pages) {
          state.upsertPage(page);
        }
        if (catalog.homePageId != null) {
          state.homePageId = catalog.homePageId;
        }
      } else {
        state.pages
          ..clear()
          ..addAll(catalog.pages);
        state.homePageId = catalog.homePageId;
      }
    }

    // 3. Arbres d'écrans imbriqués (`screens`)
    if (input.containsKey('screens') && input['screens'] != null) {
      final rawScreens = input['screens'];
      if (rawScreens is! Map) {
        throw const FormatException('Invalid "screens" map.');
      }
      for (final entry in rawScreens.entries) {
        final screenId = _requireId(entry.key, 'screens');
        if (entry.value is! Map) {
          throw const FormatException('Invalid screen definition.');
        }
        state.compileScreen(screenId, entry.value as Map, isMerge: isMerge);
      }
    }

    // 4. Opérations étape par étape (`ops`) en mode Vibe
    if (input.containsKey('ops') && input['ops'] != null) {
      final rawOps = input['ops'];
      if (rawOps is! List) {
        throw const FormatException('Invalid "ops" list.');
      }
      for (final op in rawOps) {
        if (op is! Map) {
          throw const FormatException('Invalid operation in "ops".');
        }
        state.applyOperation(op);
      }
    }

    final compiledAppearance = Appearance(
      mode: mode,
      accent: accent,
      backgroundOpacity: backgroundOpacity,
      windowOpacity: windowOpacity,
      windowEffect: windowEffect,
      styles: state.styles,
      layouts: state.layouts,
      components: state.components,
      pageCatalog: EditorPageCatalog(
        pages: state.pages,
        homePageId: state.homePageId,
      ),
    );

    return {
      'version': input['version'] ?? 1,
      'mode': compiledAppearance.mode.name,
      'accent': compiledAppearance.accent.toARGB32(),
      'backgroundOpacity': compiledAppearance.backgroundOpacity,
      'windowOpacity': compiledAppearance.windowOpacity,
      'windowEffect': compiledAppearance.windowEffect.name,
      'styles': {
        for (final e in compiledAppearance.styles.entries)
          e.key: e.value.toJson(),
      },
      'layouts': {
        for (final e in compiledAppearance.layouts.entries)
          e.key: e.value.toJson(),
      },
      'components': {
        for (final e in compiledAppearance.components.entries)
          e.key: e.value.toTypedJson(),
      },
      'pageCatalog': compiledAppearance.pageCatalog.toJson(),
    };
  }

  static String _requireId(Object? key, String mapName) {
    if (key is! String || key.trim().isEmpty) {
      throw FormatException('Invalid "$mapName" map.');
    }
    return key;
  }

  /// Décompile une [Appearance] vers la syntaxe JSON IA hiérarchique et compacte
  /// (`screens` imbriqué, couleurs `#HEX`, dimensions `"64px"`/`"50%"`, valeurs par défaut omises).
  static Map<String, Object?> toAiJson(
    Appearance appearance, {
    bool includeInlineStyles = true,
  }) => _Decompiler(
    appearance,
    includeInlineStyles: includeInlineStyles,
  ).decompile();
}

class _Decompiler {
  _Decompiler(this.appearance, {this.includeInlineStyles = true}) {
    for (final layout in appearance.layouts.values) {
      for (final id in layout.placedSlotIds) {
        refCounts[id] = (refCounts[id] ?? 0) + 1;
      }
    }
    for (final comp in appearance.components.values) {
      if (comp case final NativeComponentConfig native) {
        for (final ids in native.placements.values) {
          for (final id in ids) {
            refCounts[id] = (refCounts[id] ?? 0) + 1;
          }
        }
      } else if (comp case final ScaffoldPageConfig scaffold) {
        for (final ids in scaffold.native.placements.values) {
          for (final id in ids) {
            refCounts[id] = (refCounts[id] ?? 0) + 1;
          }
        }
      }
    }
  }

  final Appearance appearance;
  final bool includeInlineStyles;
  final consumedLayouts = <String>{};
  final consumedStyles = <String>{};
  final consumedComponents = <String>{};
  final refCounts = <String, int>{};
  final activeStack = <String>{};

  Map<String, Object?> decompileLayout(String id, SuperLayoutConfig config) {
    const d = SuperLayoutConfig();
    final zones = <String, Object?>{};
    for (final entry in config.placements.entries) {
      if (entry.value.isEmpty) continue;
      zones[entry.key.name] = [
        for (final slotId in entry.value)
          decompileSlot(
            id: slotId,
            type: config.slotTypeOf(slotId),
            constraints: config.slotSizeConstraints[slotId],
            preferredSize: config.slotPreferredSizes[slotId],
            hasPreferredSize: config.slotPreferredSizes.containsKey(slotId),
            slotLabel: config.slotLabels[slotId],
          ),
      ];
    }
    final placedSet = config.placedSlotIds.toSet();
    final unplacedPreferredSizes = {
      for (final e in config.slotPreferredSizes.entries)
        if (!placedSet.contains(e.key))
          e.key: e.value == null
              ? null
              : {'width': e.value!.width, 'height': e.value!.height},
    };
    final unplacedConstraints = {
      for (final e in config.slotSizeConstraints.entries)
        if (!placedSet.contains(e.key))
          e.key: JsonDimension.formatConstraintsCompact(e.value),
    };
    final unplacedLabels = {
      for (final e in config.slotLabels.entries)
        if (!placedSet.contains(e.key)) e.key: e.value,
    };
    return {
      if (config.label != null) 'label': config.label,
      if (config.positioning != d.positioning)
        'positioning': config.positioning.name,
      if (config.north)
        'north': true
      else if (zones.containsKey('north') ||
          zones.containsKey('nw') ||
          zones.containsKey('ne'))
        'north': false,
      if (config.south)
        'south': true
      else if (zones.containsKey('south') ||
          zones.containsKey('sw') ||
          zones.containsKey('se'))
        'south': false,
      if (config.west)
        'west': true
      else if (zones.containsKey('west') ||
          zones.containsKey('nw') ||
          zones.containsKey('sw'))
        'west': false,
      if (config.east)
        'east': true
      else if (zones.containsKey('east') ||
          zones.containsKey('ne') ||
          zones.containsKey('se'))
        'east': false,
      if (config.nw != d.nw) 'nw': config.nw.name,
      if (config.ne != d.ne) 'ne': config.ne.name,
      if (config.sw != d.sw) 'sw': config.sw.name,
      if (config.se != d.se) 'se': config.se.name,
      if (config.northSize != d.northSize) 'northSize': config.northSize,
      if (config.southSize != d.southSize) 'southSize': config.southSize,
      if (config.westSize != d.westSize) 'westSize': config.westSize,
      if (config.eastSize != d.eastSize) 'eastSize': config.eastSize,
      if (config.resizeSides) 'resizeSides': true,
      if (config.sideResizing.isNotEmpty)
        'sideResizing': {
          for (final e in config.sideResizing.entries) e.key.name: e.value,
        },
      if (config.collapsedSides.isNotEmpty)
        'collapsedSides': {
          for (final e in config.collapsedSides.entries) e.key.name: e.value,
        },
      if (config.swaps.isNotEmpty)
        'swaps': [for (final z in config.swaps) z.name],
      if (config.autoSides.isNotEmpty)
        'autoSides': [for (final z in config.autoSides) z.name],
      if (config.zoneAxes.isNotEmpty)
        'zoneAxes': {
          for (final e in config.zoneAxes.entries)
            e.key.name: e.value == Axis.horizontal ? 'row' : 'column',
        },
      if (unplacedPreferredSizes.isNotEmpty)
        'slotPreferredSizes': unplacedPreferredSizes,
      if (unplacedConstraints.isNotEmpty)
        'slotSizeConstraints': unplacedConstraints,
      if (unplacedLabels.isNotEmpty) 'slotLabels': unplacedLabels,
      if (config.grid != null) 'grid': config.grid!.toJson(),
      if (zones.isNotEmpty) 'zones': zones,
    };
  }

  Map<String, Object?> decompileNative(
    String id,
    NativeComponentConfig config,
  ) {
    final placedSet = config.placements.values.expand((ids) => ids).toSet();
    final unplacedPreferredSizes = {
      for (final e in config.slotPreferredSizes.entries)
        if (!placedSet.contains(e.key))
          e.key: e.value == null
              ? null
              : [
                  e.value!.width.isFinite ? e.value!.width : null,
                  e.value!.height.isFinite ? e.value!.height : null,
                ],
    };
    final unplacedConstraints = {
      for (final e in config.slotSizeConstraints.entries)
        if (!placedSet.contains(e.key))
          e.key: JsonDimension.formatConstraintsCompact(e.value),
    };
    final unplacedLabels = {
      for (final e in config.slotLabels.entries)
        if (!placedSet.contains(e.key)) e.key: e.value,
    };
    final result = <String, Object?>{
      if (config.useDefaultNavigation != null)
        'useDefaultNavigation': config.useDefaultNavigation,
      if (config.regions.isNotEmpty) 'regions': config.regions,
      if (unplacedPreferredSizes.isNotEmpty)
        'slotPreferredSizes': unplacedPreferredSizes,
      if (unplacedConstraints.isNotEmpty)
        'slotSizeConstraints': unplacedConstraints,
      if (unplacedLabels.isNotEmpty) 'slotLabels': unplacedLabels,
    };
    for (final entry in config.placements.entries) {
      result[entry.key] = [
        for (final slotId in entry.value)
          decompileSlot(
            id: slotId,
            type: config.slotTypeOf(slotId),
            constraints: config.slotSizeConstraints[slotId],
            preferredSize: config.slotPreferredSizes[slotId],
            hasPreferredSize: config.slotPreferredSizes.containsKey(slotId),
            slotLabel: config.slotLabels[slotId],
            infiniteSides: true,
          ),
      ];
    }
    return result;
  }

  Map<String, Object?> decompileSlot({
    required String id,
    required String type,
    required SlotSizeConstraints? constraints,
    required Size? preferredSize,
    required bool hasPreferredSize,
    required String? slotLabel,
    bool infiniteSides = false,
  }) {
    final shortType = JsonComponentType.shortName(type);
    final canInline = (refCounts[id] ?? 0) <= 1 && !activeStack.contains(id);

    final node = <String, Object?>{
      'type': shortType,
      'id': id,
      'slotLabel': ?slotLabel,
      if (constraints != null)
        'size': JsonDimension.formatConstraintsCompact(constraints),
      if (hasPreferredSize)
        'preferredSize': preferredSize == null
            ? null
            : infiniteSides
            ? [
                preferredSize.width.isFinite ? preferredSize.width : null,
                preferredSize.height.isFinite ? preferredSize.height : null,
              ]
            : {'width': preferredSize.width, 'height': preferredSize.height},
    };

    if (!canInline) return node;

    activeStack.add(id);
    try {
      switch (shortType) {
        case 'Value':
          if (appearance.tryComponent<SuperValueConfig>(id) case final val?) {
            consumedComponents.add(id);
            node.addAll(val.toCompactJson());
          }
        case 'Action':
          if (appearance.tryComponent<SuperActionConfig>(id) case final act?) {
            consumedComponents.add(id);
            node.addAll(act.toCompactJson());
          }
        case 'Card':
          if (includeInlineStyles) {
            if (appearance.styles[id] case final style?) {
              consumedStyles.add(id);
              final compactStyle = style.toCompactJson();
              if (compactStyle.isNotEmpty) node['style'] = compactStyle;
            }
          }
          if (appearance.tryComponent<NativeComponentConfig>(id)
              case final native?) {
            consumedComponents.add(id);
            final childIds = native.slotsOf('child');
            if (childIds.length == 1 &&
                native.regions.keys.every((k) => k == 'child') &&
                native.regions['child'] != false) {
              final childId = childIds.single;
              node['child'] = decompileSlot(
                id: childId,
                type: native.slotTypeOf(childId),
                constraints: native.slotSizeConstraints[childId],
                preferredSize: native.slotPreferredSizes[childId],
                hasPreferredSize: native.slotPreferredSizes.containsKey(
                  childId,
                ),
                slotLabel: native.slotLabels[childId],
                infiniteSides: true,
              );
            } else {
              node.addAll(decompileNative(id, native));
            }
          }
        case 'Layout':
          if (appearance.layouts[id] case final layout?) {
            consumedLayouts.add(id);
            node.addAll(decompileLayout(id, layout));
          }
        case 'IterableContent':
          if (includeInlineStyles) {
            if (appearance.styles[id] case final style?) {
              consumedStyles.add(id);
              final compactStyle = style.toCompactJson();
              if (compactStyle.isNotEmpty) node['style'] = compactStyle;
            }
          }
          if (appearance.layouts[id] case final layout?) {
            consumedLayouts.add(id);
            node.addAll(decompileLayout(id, layout));
          }
        case 'ListView':
          if (appearance.tryComponent<SuperListViewConfig>(id)
              case final list?) {
            consumedComponents.add(id);
            node.addAll(list.toCompactJson());
          }
          if (includeInlineStyles) {
            if (appearance.styles[id] case final style?) {
              consumedStyles.add(id);
              final compactStyle = style.toCompactJson();
              if (compactStyle.isNotEmpty) node['style'] = compactStyle;
            }
          }
          if (appearance.layouts[id] case final template?) {
            consumedLayouts.add(id);
            node['template'] = decompileLayout(id, template);
          }
        case 'ApplicationBar' || 'BottomNavigationBar':
          if (appearance.tryComponent<NativeComponentConfig>(id)
              case final native?) {
            consumedComponents.add(id);
            node.addAll(decompileNative(id, native));
          }
      }
    } finally {
      activeStack.remove(id);
    }
    return node;
  }

  Map<String, Object?> decompile() {
    final screens = <String, Object?>{};
    // 1. Écran principal `root` / `contA`
    final rootNative = appearance.tryComponent<NativeComponentConfig>('root');
    if (rootNative != null || appearance.layouts.containsKey('contA')) {
      final rootScreen = <String, Object?>{};
      if (rootNative != null) {
        consumedComponents.add('root');
        rootScreen.addAll(decompileNative('root', rootNative));
      }
      final bodySlots = rootNative?.slotsOf('body') ?? const ['scaffold:body'];
      if (bodySlots.length == 1 &&
          bodySlots.single == 'scaffold:body' &&
          appearance.layouts.containsKey('contA') &&
          (refCounts['contA'] ?? 0) == 0) {
        consumedLayouts.add('contA');
        rootScreen['body'] = {
          'type': 'Layout',
          'id': 'contA',
          ...decompileLayout('contA', appearance.layouts['contA']!),
        };
      }
      if (rootScreen.isNotEmpty) {
        screens['root'] = rootScreen;
      }
    }

    // 2. Pages du `pageCatalog`
    for (final page in appearance.pageCatalog.pages) {
      final pageScreen = <String, Object?>{
        'name': page.name,
        'path': page.path,
        if (page.defaultParameters.isNotEmpty)
          'defaultParameters': page.defaultParameters,
        if (appearance.pageCatalog.homePageId == page.id) 'home': true,
      };
      if (appearance.tryComponent<NativeComponentConfig>(page.id)
          case final native?) {
        consumedComponents.add(page.id);
        pageScreen.addAll(decompileNative(page.id, native));
      }
      screens[page.id] = pageScreen;
    }

    final remainingStyles = {
      for (final e in appearance.styles.entries)
        if (!consumedStyles.contains(e.key)) e.key: e.value.toCompactJson(),
    };
    final remainingLayouts = {
      for (final e in appearance.layouts.entries)
        if (!consumedLayouts.contains(e.key))
          e.key: decompileLayout(e.key, e.value),
    };
    final remainingComponents = {
      for (final e in appearance.components.entries)
        if (!consumedComponents.contains(e.key))
          e.key: switch (e.value) {
            final NativeComponentConfig n => {
              'type': 'native',
              ...decompileNative(e.key, n),
            },
            final other => other.toTypedCompactJson(),
          },
    };

    return {
      'version': 1,
      'mode': appearance.mode.name,
      'accent': JsonColor.toHex(appearance.accent),
      if (appearance.backgroundOpacity != 1)
        'backgroundOpacity': appearance.backgroundOpacity,
      if (appearance.windowOpacity != 1)
        'windowOpacity': appearance.windowOpacity,
      if (appearance.windowEffect != WindowEffect.transparent)
        'windowEffect': appearance.windowEffect.name,
      'styles': remainingStyles,
      if (screens.isNotEmpty) 'screens': screens,
      if (remainingLayouts.isNotEmpty) 'layouts': remainingLayouts,
      'components': remainingComponents,
      'pageCatalog': appearance.pageCatalog.toJson(),
    };
  }
}

class _CompilationState {
  _CompilationState({
    required this.styles,
    required this.layouts,
    required this.components,
    required this.pages,
    required this.homePageId,
  });

  factory _CompilationState.fromAppearance(Appearance a) => _CompilationState(
    styles: Map<String, ContainerStyle>.of(a.styles),
    layouts: Map<String, SuperLayoutConfig>.of(a.layouts),
    components: Map<String, ComponentConfig>.of(a.components),
    pages: List<EditorPageConfig>.of(a.pageCatalog.pages),
    homePageId: a.pageCatalog.homePageId,
  );

  final Map<String, ContainerStyle> styles;
  final Map<String, SuperLayoutConfig> layouts;
  final Map<String, ComponentConfig> components;
  final List<EditorPageConfig> pages;
  String? homePageId;
  int _counter = 1;

  T? tryComponent<T extends ComponentConfig>(String id) =>
      switch (components[id]) {
        final T v => v,
        _ => null,
      };

  NativeComponentConfig? tryNative(String id) => switch (components[id]) {
    final NativeComponentConfig n => n,
    final ScaffoldPageConfig s => s.native,
    _ => null,
  };

  Set<String> get _allUsedIds => {
    ...styles.keys,
    ...layouts.keys,
    ...components.keys,
    for (final p in pages) p.id,
    for (final l in layouts.values) ...l.placedSlotIds,
    for (final c in components.values)
      if (c case final NativeComponentConfig n)
        ...n.placements.values.expand((ids) => ids)
      else if (c case final ScaffoldPageConfig s)
        ...s.native.placements.values.expand((ids) => ids),
  };

  String _generateId(String parentId, String regionOrZone, String shortType) {
    final cleanType = shortType
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')
        .toLowerCase();
    final base = '${parentId}_${regionOrZone}_$cleanType';
    final used = _allUsedIds;
    if (!used.contains(base)) return base;
    while (true) {
      final candidate = '${base}_${_counter++}';
      if (!used.contains(candidate)) return candidate;
    }
  }

  void upsertPage(EditorPageConfig page) {
    final index = pages.indexWhere((p) => p.id == page.id);
    if (index >= 0) {
      pages[index] = page;
    } else {
      pages.add(page);
    }
  }

  /// Compile une définition d'écran sous `screens[screenId]`.
  void compileScreen(
    String screenId,
    Map<Object?, Object?> map, {
    required bool isMerge,
  }) {
    // Si la définition d'écran porte des métadonnées de route (path, name, home),
    // on met à jour le pageCatalog automatiquement (sauf pour 'root').
    if (screenId != 'root' &&
        (map.containsKey('path') || pages.any((p) => p.id == screenId))) {
      final existingPage = pages.where((p) => p.id == screenId).firstOrNull;
      final path = (map['path'] as String?) ?? existingPage?.path;
      final name =
          (map['name'] as String?) ??
          (map['title'] as String?) ??
          existingPage?.name ??
          screenId;
      if (path != null) {
        final rawParams = map['defaultParameters'];
        final params = rawParams is Map
            ? {
                for (final e in rawParams.entries)
                  if (e.key is String && e.value is String)
                    e.key as String: e.value as String,
              }
            : (existingPage?.defaultParameters ?? const <String, String>{});
        upsertPage(
          EditorPageConfig(
            id: screenId,
            name: name,
            path: path,
            defaultParameters: params,
          ),
        );
        if (map['home'] == true) {
          homePageId = screenId;
        }
      }
    }

    // Si l'écran est écrit directement comme un SuperLayout (contient `zones` ou `placements` de zones)
    if (map.containsKey('zones') ||
        (map['placements'] is Map &&
            (map['placements'] as Map).keys.any(
              (k) => SuperLayoutZone.values.any((z) => z.name == k),
            ))) {
      final targetLayoutId = screenId == 'root' ? 'contA' : '$screenId-body';
      compileLayoutMap(targetLayoutId, map, isMerge: isMerge);
      if (screenId != 'root') {
        final existingNative = tryNative(screenId);
        components[screenId] = NativeComponentConfig(
          useDefaultNavigation: existingNative?.useDefaultNavigation,
          regions: {...?existingNative?.regions, 'body': true},
          placements: {
            ...?existingNative?.placements,
            'body': [targetLayoutId],
          },
          slotTypes: {
            ...?existingNative?.slotTypes,
            targetLayoutId: 'registry:Layout',
          },
          slotPreferredSizes: existingNative?.slotPreferredSizes ?? const {},
          slotSizeConstraints: existingNative?.slotSizeConstraints ?? const {},
          slotLabels: existingNative?.slotLabels ?? const {},
        );
      }
      return;
    }

    // Sinon, c'est un écran structuré par régions de SuperPage (appBar, body, drawer, etc.)
    final nativeMap = <String, Object?>{};
    if (map.containsKey('regions') && map['regions'] is Map) {
      nativeMap['regions'] = map['regions'];
    }
    if (map.containsKey('slotPreferredSizes')) {
      nativeMap['slotPreferredSizes'] = map['slotPreferredSizes'];
    }
    if (map.containsKey('slotSizeConstraints')) {
      nativeMap['slotSizeConstraints'] = map['slotSizeConstraints'];
    }
    if (map.containsKey('slotLabels')) {
      nativeMap['slotLabels'] = map['slotLabels'];
    }

    final placements = <String, Object?>{};
    if (map['placements'] is Map) {
      for (final e in (map['placements'] as Map).entries) {
        if (e.key is String) placements[e.key as String] = e.value;
      }
    }
    for (final region in ScreenTreeCodec._scaffoldRegions) {
      if (map.containsKey(region)) {
        placements[region] = map[region];
      }
    }

    // Cas spécial ergonomique pour `root.body` : dans `main.dart`, la région `body`
    // de `SuperPage(id: 'root')` affiche `scaffold:body` qui monte `layouts['contA']`.
    // Si l'IA passe directement un Layout pour `root.body` (avec id 'contA' ou sans id),
    // on compile ce Layout dans `layouts['contA']` et on laisse `scaffold:body` dans `root.body`.
    if (screenId == 'root' && placements.containsKey('body')) {
      final bodyVal = placements['body'];
      final singleMap = bodyVal is Map
          ? bodyVal
          : (bodyVal is List && bodyVal.length == 1 && bodyVal.first is Map)
          ? bodyVal.first as Map
          : null;
      if (singleMap != null) {
        final rawType = singleMap['type'] as String?;
        final normalizedType = rawType == null
            ? 'registry:Layout'
            : JsonComponentType.normalize(rawType);
        final explicitId = singleMap['id'] as String?;
        if (normalizedType == 'registry:Layout' &&
            (explicitId == null || explicitId == 'contA')) {
          compileLayoutMap('contA', singleMap, isMerge: isMerge);
          placements['body'] = [
            {'id': 'scaffold:body', 'type': 'scaffold:body'},
          ];
        }
      }
    }

    if (screenId == 'root' && !placements.containsKey('body')) {
      final existingBody = tryNative('root')?.slotsOf('body');
      if (existingBody == null || existingBody.isEmpty) {
        placements['body'] = [
          {'id': 'scaffold:body', 'type': 'scaffold:body'},
        ];
      }
    }

    nativeMap['placements'] = placements;
    compileNativeMap(
      screenId,
      nativeMap,
      isMerge: isMerge,
      defaultRegions: ScreenTreeCodec._scaffoldRegions,
    );
  }

  /// Compile un `SuperLayoutConfig` dont les entrées de `zones` / `placements`
  /// peuvent contenir des nœuds enfants complets imbriqués.
  void compileLayoutMap(
    String layoutId,
    Map<Object?, Object?> rawMap, {
    required bool isMerge,
  }) {
    final existing = isMerge
        ? (layouts[layoutId] ?? const SuperLayoutConfig(autoSides: {}))
        : const SuperLayoutConfig(autoSides: {});
    layouts[layoutId] = existing;

    final cleaned = <String, Object?>{};
    for (final entry in rawMap.entries) {
      if (entry.key is String &&
          ScreenTreeCodec._layoutKeys.contains(entry.key)) {
        cleaned[entry.key as String] = entry.value;
      }
    }

    final rawZones = rawMap.containsKey('zones')
        ? rawMap['zones']
        : rawMap['placements'];
    final slotConstraints = <String, Object?>{
      if (isMerge)
        for (final e in existing.slotSizeConstraints.entries)
          e.key: e.value.toJson(),
      if (rawMap['slotSizeConstraints'] is Map)
        for (final e in (rawMap['slotSizeConstraints'] as Map).entries)
          if (e.key is String) e.key as String: e.value,
    };
    final slotPreferredSizes = <String, Object?>{
      if (isMerge)
        for (final e in existing.slotPreferredSizes.entries)
          e.key: e.value == null
              ? null
              : {'width': e.value!.width, 'height': e.value!.height},
      if (rawMap['slotPreferredSizes'] is Map)
        for (final e in (rawMap['slotPreferredSizes'] as Map).entries)
          if (e.key is String) e.key as String: e.value,
    };
    final slotLabels = <String, Object?>{
      if (isMerge) ...existing.slotLabels,
      if (rawMap['slotLabels'] is Map)
        for (final e in (rawMap['slotLabels'] as Map).entries)
          if (e.key is String) e.key as String: e.value,
    };

    if (rawZones != null) {
      if (rawZones is! Map) {
        throw const FormatException('Valeur invalide pour "placements".');
      }
      final compiledPlacements = <String, List<Map<String, String>>>{
        if (isMerge)
          for (final e in existing.placements.entries)
            e.key.name: [
              for (final id in e.value)
                {'id': id, 'type': existing.slotTypeOf(id)},
            ],
      };

      for (final entry in rawZones.entries) {
        if (entry.key is! String) {
          throw const FormatException('Valeur invalide pour "placements".');
        }
        final zoneName = entry.key as String;
        final zoneItems = entry.value is Map
            ? [entry.value]
            : entry.value is List
            ? entry.value as List
            : (throw const FormatException(
                'Valeur invalide pour "placements".',
              ));
        final refs = <Map<String, String>>[];
        for (final item in zoneItems) {
          final compiled = _compileSlotNode(
            item,
            parentId: layoutId,
            zoneOrRegion: zoneName,
            isMerge: isMerge,
          );
          refs.add({'id': compiled.id, 'type': compiled.type});
          if (compiled.constraints != null) {
            slotConstraints[compiled.id] = compiled.constraints;
          }
          if (compiled.hasPreferredSize) {
            slotPreferredSizes[compiled.id] = compiled.preferredSize;
          }
          if (compiled.slotLabel != null) {
            slotLabels[compiled.id] = compiled.slotLabel;
          }
        }
        compiledPlacements[zoneName] = refs;
      }

      cleaned.remove('zones');
      cleaned['placements'] = compiledPlacements;
    }

    if (slotConstraints.isNotEmpty) {
      cleaned['slotSizeConstraints'] = slotConstraints;
    }
    if (slotPreferredSizes.isNotEmpty) {
      cleaned['slotPreferredSizes'] = slotPreferredSizes;
    }
    if (slotLabels.isNotEmpty) {
      cleaned['slotLabels'] = slotLabels;
    }

    // Si en création avec `zones` sans `north`/`south`/`west`/`east` explicite,
    // activer automatiquement les côtés qui contiennent des composants.
    if (rawMap.containsKey('zones')) {
      final placementsMap =
          cleaned['placements'] as Map<String, List<Map<String, String>>>?;
      if (placementsMap != null) {
        bool hasAny(List<String> keys) =>
            keys.any((k) => (placementsMap[k]?.isNotEmpty ?? false));
        if (!cleaned.containsKey('north') &&
            hasAny(const ['north', 'nw', 'ne'])) {
          cleaned['north'] = true;
        }
        if (!cleaned.containsKey('south') &&
            hasAny(const ['south', 'sw', 'se'])) {
          cleaned['south'] = true;
        }
        if (!cleaned.containsKey('west') &&
            hasAny(const ['west', 'nw', 'sw'])) {
          cleaned['west'] = true;
        }
        if (!cleaned.containsKey('east') &&
            hasAny(const ['east', 'ne', 'se'])) {
          cleaned['east'] = true;
        }
      }
    }

    layouts[layoutId] = SuperLayoutConfig.fromJson(cleaned, fallback: existing);
  }

  /// Compile un `NativeComponentConfig` (Page, Card, ApplicationBar, BottomNavigationBar)
  /// dont les régions peuvent être déclarées directement en clés ou dans `placements`.
  void compileNativeMap(
    String nativeId,
    Map<Object?, Object?> rawMap, {
    required bool isMerge,
    Set<String>? defaultRegions,
  }) {
    final existing = isMerge ? tryNative(nativeId) : null;
    final regions = <String, bool>{if (existing != null) ...existing.regions};
    if (rawMap.containsKey('regions')) {
      final rawRegions = rawMap['regions'];
      if (rawRegions is! Map) {
        throw const FormatException('Invalid native region activation.');
      }
      for (final e in rawRegions.entries) {
        if (e.key is! String || e.value is! bool) {
          throw const FormatException('Invalid native region activation.');
        }
        regions[e.key as String] = e.value as bool;
      }
    }

    final slotConstraints = <String, Object?>{
      if (existing != null)
        for (final e in existing.slotSizeConstraints.entries)
          e.key: e.value.toJson(),
      if (rawMap['slotSizeConstraints'] is Map)
        for (final e in (rawMap['slotSizeConstraints'] as Map).entries)
          if (e.key is String) e.key as String: e.value,
    };
    final slotPreferredSizes = <String, Object?>{
      if (existing != null)
        for (final e in existing.slotPreferredSizes.entries)
          e.key: e.value == null
              ? null
              : [
                  e.value!.width.isFinite ? e.value!.width : null,
                  e.value!.height.isFinite ? e.value!.height : null,
                ],
      if (rawMap['slotPreferredSizes'] is Map)
        for (final e in (rawMap['slotPreferredSizes'] as Map).entries)
          if (e.key is String) e.key as String: e.value,
    };
    final slotLabels = <String, Object?>{
      if (existing != null) ...existing.slotLabels,
      if (rawMap['slotLabels'] is Map)
        for (final e in (rawMap['slotLabels'] as Map).entries)
          if (e.key is String) e.key as String: e.value,
    };

    final rawPlacements = <String, Object?>{};
    if (rawMap.containsKey('placements')) {
      if (rawMap['placements'] is! Map) {
        throw const FormatException('Invalid native component configuration.');
      }
      for (final e in (rawMap['placements'] as Map).entries) {
        if (e.key is! String) {
          throw const FormatException('Invalid native region.');
        }
        rawPlacements[e.key as String] = e.value;
      }
    }

    final candidateRegionKeys =
        defaultRegions ??
        {
          ...ScreenTreeCodec._scaffoldRegions,
          ...ScreenTreeCodec._appBarRegions,
          ...ScreenTreeCodec._bottomBarRegions,
          'child',
        };
    for (final region in candidateRegionKeys) {
      if (rawMap.containsKey(region)) {
        rawPlacements[region] = rawMap[region];
      }
    }

    if (rawPlacements.isEmpty &&
        !rawMap.containsKey('placements') &&
        existing == null) {
      throw const FormatException('Invalid native component configuration.');
    }

    final compiledPlacements = <String, List<Map<String, String>>>{
      if (existing != null)
        for (final e in existing.placements.entries)
          e.key: [
            for (final id in e.value)
              {'id': id, 'type': existing.slotTypeOf(id)},
          ],
    };

    for (final entry in rawPlacements.entries) {
      final regionName = entry.key;
      final value = entry.value;
      final items = value == null
          ? const <Object?>[]
          : value is Map
          ? <Object?>[value]
          : value is List
          ? value
          : (throw const FormatException('Invalid native region.'));
      final refs = <Map<String, String>>[];
      for (final item in items) {
        final compiled = _compileSlotNode(
          item,
          parentId: nativeId,
          zoneOrRegion: regionName,
          isMerge: isMerge,
        );
        refs.add({'id': compiled.id, 'type': compiled.type});
        if (compiled.constraints != null) {
          slotConstraints[compiled.id] = compiled.constraints;
        }
        if (compiled.hasPreferredSize) {
          slotPreferredSizes[compiled.id] = compiled.preferredSize;
        }
        if (compiled.slotLabel != null) {
          slotLabels[compiled.id] = compiled.slotLabel;
        }
      }
      compiledPlacements[regionName] = refs;
      if (refs.isNotEmpty && !regions.containsKey(regionName)) {
        regions[regionName] = true;
      }
    }

    final canonical = <String, Object?>{
      if (rawMap.containsKey('useDefaultNavigation'))
        'useDefaultNavigation': rawMap['useDefaultNavigation']
      else if (existing?.useDefaultNavigation != null)
        'useDefaultNavigation': existing!.useDefaultNavigation,
      'regions': regions,
      'placements': compiledPlacements,
      if (slotPreferredSizes.isNotEmpty)
        'slotPreferredSizes': slotPreferredSizes,
      if (slotConstraints.isNotEmpty) 'slotSizeConstraints': slotConstraints,
      if (slotLabels.isNotEmpty) 'slotLabels': slotLabels,
    };

    components[nativeId] = NativeComponentConfig.fromJson(canonical);
  }

  /// Compile un élément de slot (chaîne simple, référence `{id, type}` ou nœud complet inline).
  _CompiledSlot _compileSlotNode(
    Object? item, {
    required String parentId,
    required String zoneOrRegion,
    required bool isMerge,
  }) {
    if (item is String) {
      if (item.trim().isEmpty) {
        throw const FormatException('Placement invalide : type et id requis.');
      }
      return _CompiledSlot(
        id: item,
        type: JsonComponentType.normalize(item, id: item),
      );
    }
    if (item is! Map) {
      throw const FormatException('Placement invalide : type et id requis.');
    }

    final inferredType = _inferType(item, zoneOrRegion: zoneOrRegion);
    if (inferredType == null || inferredType.trim().isEmpty) {
      throw const FormatException('Placement invalide : type et id requis.');
    }

    // Si aucun ID n'est fourni, ne l'auto-générer que s'il s'agit d'un nœud inline
    // (ou si le type est explicite et contient des données ou un composant du registre).
    final rawId = item['id'];
    if (rawId != null && (rawId is! String || rawId.trim().isEmpty)) {
      throw const FormatException('Placement invalide : type et id requis.');
    }

    final isPureReference =
        item.keys.every((k) => k == 'id' || k == 'type') && item.length <= 2;
    if (rawId == null && isPureReference) {
      throw const FormatException('Placement invalide : type et id requis.');
    }

    final shortType = JsonComponentType.shortName(inferredType);
    final id =
        (rawId as String?) ?? _generateId(parentId, zoneOrRegion, shortType);
    final normalizedType = JsonComponentType.normalize(inferredType, id: id);

    // Extraction des métadonnées de placement (size, preferredSize, slotLabel)
    Object? constraints = item['size'] ?? item['constraints'];
    if (constraints == null &&
        (item.containsKey('preferredWidth') ||
            item.containsKey('preferredHeight') ||
            item.containsKey('minWidth') ||
            item.containsKey('minHeight') ||
            item.containsKey('maxWidth') ||
            item.containsKey('maxHeight') ||
            item.containsKey('slotPadding'))) {
      constraints = <String, Object?>{
        if (item.containsKey('preferredWidth'))
          'preferredWidth': item['preferredWidth'],
        if (item.containsKey('preferredHeight'))
          'preferredHeight': item['preferredHeight'],
        if (item.containsKey('minWidth')) 'minWidth': item['minWidth'],
        if (item.containsKey('minHeight')) 'minHeight': item['minHeight'],
        if (item.containsKey('maxWidth')) 'maxWidth': item['maxWidth'],
        if (item.containsKey('maxHeight')) 'maxHeight': item['maxHeight'],
        if (item.containsKey('slotPadding')) 'padding': item['slotPadding'],
      };
    }

    final hasPreferredSize = item.containsKey('preferredSize');
    final preferredSize = item['preferredSize'];
    final String? slotLabel = item['slotLabel'] is String
        ? item['slotLabel'] as String
        : (shortType != 'Value' &&
              shortType != 'Action' &&
              item['label'] is String &&
              shortType != 'Layout')
        ? item['label'] as String
        : null;

    if (!isPureReference) {
      _compileComponentPayload(
        id: id,
        shortType: shortType,
        node: item,
        isMerge: isMerge,
      );
    }

    return _CompiledSlot(
      id: id,
      type: normalizedType,
      constraints: constraints,
      hasPreferredSize: hasPreferredSize,
      preferredSize: preferredSize,
      slotLabel: slotLabel,
    );
  }

  String? _inferType(
    Map<Object?, Object?> item, {
    required String zoneOrRegion,
  }) {
    if (item['type'] is String) return item['type'] as String;
    if (item.containsKey('zones') || item.containsKey('grid')) return 'Layout';
    if (item.containsKey('child')) return 'Card';
    if (item.containsKey('template') ||
        item.containsKey('itemExtent') ||
        item.containsKey('allowAdd')) {
      return 'ListView';
    }
    if (zoneOrRegion == 'appBar' &&
        (item.containsKey('title') ||
            item.containsKey('actions') ||
            item.containsKey('leading'))) {
      return 'ApplicationBar';
    }
    if (zoneOrRegion == 'bottomNavigationBar' &&
        (item.containsKey('left') ||
            item.containsKey('center') ||
            item.containsKey('right'))) {
      return 'BottomNavigationBar';
    }
    if (item.containsKey('variant') ||
        item.containsKey('icon') ||
        item.containsKey('iconPosition') ||
        item.containsKey('tooltip')) {
      return 'Action';
    }
    if (item.containsKey('initialText') ||
        item.containsKey('text') ||
        item.containsKey('placeholder') ||
        item.containsKey('field') ||
        item.containsKey('kind') ||
        item.containsKey('mode')) {
      return 'Value';
    }
    return null;
  }

  void _compileComponentPayload({
    required String id,
    required String shortType,
    required Map<Object?, Object?> node,
    required bool isMerge,
  }) {
    switch (shortType) {
      case 'Layout':
        final layoutSource = node['layout'] is Map
            ? node['layout'] as Map
            : node;
        if (layoutSource.keys.any(ScreenTreeCodec._layoutKeys.contains)) {
          compileLayoutMap(id, layoutSource, isMerge: isMerge);
        }
      case 'Card':
        _compileInlineStyle(id, node, isMerge: isMerge);
        if (node.containsKey('child') || node.containsKey('placements')) {
          compileNativeMap(
            id,
            {
              if (node.containsKey('regions')) 'regions': node['regions'],
              if (node.containsKey('placements'))
                'placements': node['placements'],
              if (node.containsKey('child')) 'child': node['child'],
            },
            isMerge: isMerge,
            defaultRegions: const {'child'},
          );
        }
      case 'IterableContent':
        _compileInlineStyle(id, node, isMerge: isMerge);
        final layoutSource = node['layout'] is Map
            ? node['layout'] as Map
            : node;
        if (layoutSource.keys.any(ScreenTreeCodec._layoutKeys.contains)) {
          compileLayoutMap(id, layoutSource, isMerge: isMerge);
        }
      case 'ListView':
        _compileInlineStyle(
          id,
          node,
          isMerge: isMerge,
          styleKey: node.containsKey('rowStyle')
              ? 'rowStyle'
              : node.containsKey('templateStyle')
              ? 'templateStyle'
              : 'style',
          allowRootStyleKeys: false,
        );
        final listSource = node['list'] is Map
            ? node['list'] as Map
            : node['config'] is Map
            ? node['config'] as Map
            : <String, Object?>{
                for (final e in node.entries)
                  if (e.key is String &&
                      ScreenTreeCodec._listKeys.contains(e.key))
                    e.key as String: e.value,
              };
        if (listSource.isNotEmpty) {
          final existing = tryComponent<SuperListViewConfig>(id);
          components[id] = existing != null && isMerge
              ? existing.patchFromJson(listSource)
              : SuperListViewConfig.fromJson(listSource);
        }
        final templateSource = node['template'] ?? node['row'];
        if (templateSource is Map) {
          compileLayoutMap(id, templateSource, isMerge: isMerge);
        } else if (node.containsKey('zones')) {
          compileLayoutMap(id, {'zones': node['zones']}, isMerge: isMerge);
        }
      case 'Value':
        final valueSource = node['config'] is Map
            ? node['config'] as Map
            : node['valueConfig'] is Map
            ? node['valueConfig'] as Map
            : <String, Object?>{
                for (final e in node.entries)
                  if (e.key is String &&
                      ScreenTreeCodec._valueKeys.contains(e.key))
                    e.key as String: e.value,
              };
        if (valueSource.isNotEmpty) {
          final existing = tryComponent<SuperValueConfig>(id);
          components[id] = existing != null && isMerge
              ? existing.patchFromJson(valueSource)
              : SuperValueConfig.fromJson(valueSource);
        }
      case 'Action':
        final actionSource = node['config'] is Map
            ? node['config'] as Map
            : node['actionConfig'] is Map
            ? node['actionConfig'] as Map
            : <String, Object?>{
                for (final e in node.entries)
                  if (e.key is String &&
                      ScreenTreeCodec._actionKeys.contains(e.key))
                    e.key as String: e.value,
              };
        if (actionSource.isNotEmpty) {
          final existing = tryComponent<SuperActionConfig>(id);
          components[id] = existing != null && isMerge
              ? existing.patchFromJson(actionSource)
              : SuperActionConfig.fromJson(actionSource);
        }
      case 'ApplicationBar':
        compileNativeMap(
          id,
          node,
          isMerge: isMerge,
          defaultRegions: ScreenTreeCodec._appBarRegions,
        );
      case 'BottomNavigationBar':
        compileNativeMap(
          id,
          node,
          isMerge: isMerge,
          defaultRegions: ScreenTreeCodec._bottomBarRegions,
        );
      default:
        if (node['style'] is Map) {
          _compileInlineStyle(id, node, isMerge: isMerge);
        }
        if (node['layout'] is Map || node.containsKey('zones')) {
          compileLayoutMap(
            id,
            node['layout'] is Map ? node['layout'] as Map : node,
            isMerge: isMerge,
          );
        }
    }
  }

  void _compileInlineStyle(
    String id,
    Map<Object?, Object?> node, {
    required bool isMerge,
    String styleKey = 'style',
    bool allowRootStyleKeys = true,
  }) {
    Map<Object?, Object?>? styleMap;
    if (node[styleKey] is Map) {
      styleMap = node[styleKey] as Map;
    } else if (allowRootStyleKeys) {
      final extracted = <String, Object?>{
        for (final e in node.entries)
          if (e.key is String && ScreenTreeCodec._styleKeys.contains(e.key))
            e.key as String: e.value,
      };
      if (extracted.isNotEmpty) styleMap = extracted;
    }
    if (styleMap != null) {
      final existing = styles[id];
      styles[id] = existing != null && isMerge
          ? existing.patchFromJson(styleMap)
          : ContainerStyle.fromJson(styleMap);
    }
  }

  /// Exécute une opération atomique du mode Vibe (`add`, `patch`, `move`, `remove`,
  /// `upsertPage`, `removePage`).
  void applyOperation(Map<Object?, Object?> op) {
    final kind = (op['op'] ?? op['action']) as String?;
    switch (kind) {
      case 'add' || 'insert' || 'upsertSlot':
        _opAdd(op);
      case 'patch' || 'update' || 'set':
        _opPatch(op);
      case 'move':
        _opMove(op);
      case 'remove' || 'delete':
        _opRemove(op);
      case 'upsertPage' || 'addPage':
        _opUpsertPage(op);
      case 'removePage' || 'deletePage':
        _opRemovePage(op);
      default:
        throw FormatException('Opération Vibe inconnue : $kind.');
    }
  }

  void _opAdd(Map<Object?, Object?> op) {
    final target = (op['target'] ?? op['parent'] ?? 'contA') as String;
    final zoneOrRegion = (op['zone'] ?? op['region']) as String?;
    final rawNode = op['node'] ?? op['component'] ?? op['nodes'];
    if (rawNode == null) {
      throw const FormatException('Opération "add" : "node" requis.');
    }
    final items = rawNode is List ? rawNode : [rawNode];
    final beforeId = op['beforeId'] as String?;
    final afterId = op['afterId'] as String?;
    final replace = op['replace'] == true;

    // Est-ce une cible NativeComponent (ou page root / Card) ?
    final isNativeTarget =
        tryNative(target) != null ||
        target == 'root' ||
        pages.any((p) => p.id == target) ||
        (zoneOrRegion != null &&
            !SuperLayoutZone.values.any((z) => z.name == zoneOrRegion));

    if (isNativeTarget && !layouts.containsKey(target)) {
      final region =
          zoneOrRegion ??
          (target == 'root' || pages.any((p) => p.id == target)
              ? 'body'
              : 'child');
      var current =
          tryNative(target) ??
          (target == 'root'
              ? NativeComponentConfig(
                  regions: const {'body': true},
                  placements: const {
                    'body': ['scaffold:body'],
                  },
                  slotTypes: const {'scaffold:body': 'scaffold:body'},
                )
              : NativeComponentConfig());
      for (final item in items) {
        final compiled = _compileSlotNode(
          item,
          parentId: target,
          zoneOrRegion: region,
          isMerge: true,
        );
        current = current.withSlotAdded(
          compiled.id,
          region,
          type: compiled.type,
          replace: replace || region == 'child',
        );
        if (beforeId != null || afterId != null) {
          current = current.withSlotMoved(
            compiled.id,
            region,
            beforeId: beforeId,
            afterId: afterId,
          );
        }
        if (compiled.constraints != null) {
          current = current.withSlotSizeConstraints(
            compiled.id,
            SlotSizeConstraints.fromJson(compiled.constraints),
          );
        }
        if (compiled.hasPreferredSize) {
          current = current.withSlotSize(
            compiled.id,
            JsonDimension.parsePreferredSize(
              compiled.preferredSize,
              allowInfiniteSides: true,
            ),
          );
        }
        if (compiled.slotLabel != null) {
          current = current.withSlotLabel(compiled.id, compiled.slotLabel);
        }
      }
      components[target] = current;
      return;
    }

    // Sinon c'est un SuperLayout (ex: 'contA')
    final zoneName = zoneOrRegion ?? 'center';
    final zone = SuperLayoutZone.values
        .where((z) => z.name == zoneName)
        .firstOrNull;
    if (zone == null) {
      throw FormatException('Zone de layout invalide : $zoneName.');
    }
    var current = layouts[target] ?? const SuperLayoutConfig();
    if (replace) {
      current = current.withPlacement(zone, const []);
    }
    current = _enableZoneSides(current, zone);
    for (final item in items) {
      final compiled = _compileSlotNode(
        item,
        parentId: target,
        zoneOrRegion: zoneName,
        isMerge: true,
      );
      current = current.withSlotMoved(
        compiled.id,
        zone,
        beforeId: beforeId,
        afterId: afterId,
        type: compiled.type,
      );
      if (compiled.constraints != null) {
        current = current.copyWith(
          slotSizeConstraints: {
            ...current.slotSizeConstraints,
            compiled.id: SlotSizeConstraints.fromJson(compiled.constraints),
          },
        );
      }
      if (compiled.hasPreferredSize) {
        current = current.withSlotPreferredSize(
          compiled.id,
          JsonDimension.parsePreferredSize(
            compiled.preferredSize,
            allowInfiniteSides: false,
          ),
        );
      }
      if (compiled.slotLabel != null) {
        current = current.copyWith(
          slotLabels: {...current.slotLabels, compiled.id: compiled.slotLabel!},
        );
      }
    }
    layouts[target] = current;
  }

  void _opPatch(Map<Object?, Object?> op) {
    final id = (op['id'] ?? op['target']) as String?;
    if (id == null || id.trim().isEmpty) {
      throw const FormatException('Opération "patch" : "id" requis.');
    }

    var matched = false;
    if (op['style'] is Map) {
      final existing = styles[id] ?? const ContainerStyle();
      styles[id] = existing.patchFromJson(op['style'] as Map);
      matched = true;
    }
    if (op['value'] is Map) {
      final existing =
          tryComponent<SuperValueConfig>(id) ?? const SuperValueConfig();
      components[id] = existing.patchFromJson(op['value'] as Map);
      matched = true;
    }
    if (op['action'] is Map) {
      final existing =
          tryComponent<SuperActionConfig>(id) ?? const SuperActionConfig();
      components[id] = existing.patchFromJson(op['action'] as Map);
      matched = true;
    }
    if (op['layout'] is Map) {
      compileLayoutMap(id, op['layout'] as Map, isMerge: true);
      matched = true;
    }
    if (op['list'] is Map) {
      final existing =
          tryComponent<SuperListViewConfig>(id) ?? const SuperListViewConfig();
      components[id] = existing.patchFromJson(op['list'] as Map);
      matched = true;
    }
    if (op.containsKey('template') || op.containsKey('row')) {
      final template = op['template'] ?? op['row'];
      if (template is! Map) {
        throw const FormatException(
          'Opération "patch" : "template" ou "row" doit être un objet.',
        );
      }
      compileLayoutMap(id, template, isMerge: true);
    }
    if (op['native'] is Map) {
      compileNativeMap(id, op['native'] as Map, isMerge: true);
      matched = true;
    }

    if (op.containsKey('size') || op.containsKey('slotLabel')) {
      final parentId = op['parent'] as String?;
      for (final entry in layouts.entries.toList()) {
        if (parentId != null && entry.key != parentId) continue;
        if (entry.value.placedSlotIds.contains(id)) {
          var l = entry.value;
          if (op['size'] != null) {
            l = l.copyWith(
              slotSizeConstraints: {
                ...l.slotSizeConstraints,
                id: SlotSizeConstraints.fromJson(op['size']),
              },
            );
          }
          if (op['slotLabel'] is String) {
            l = l.copyWith(
              slotLabels: {...l.slotLabels, id: op['slotLabel'] as String},
            );
          }
          layouts[entry.key] = l;
          matched = true;
        }
      }
    }

    if (!matched) {
      // Inférence directe selon les clés présentes sur `op` ou les maps existantes
      final directStyle = <String, Object?>{
        for (final e in op.entries)
          if (e.key is String && ScreenTreeCodec._styleKeys.contains(e.key))
            e.key as String: e.value,
      };
      final directValue = <String, Object?>{
        for (final e in op.entries)
          if (e.key is String && ScreenTreeCodec._valueKeys.contains(e.key))
            e.key as String: e.value,
      };
      final directAction = <String, Object?>{
        for (final e in op.entries)
          if (e.key is String && ScreenTreeCodec._actionKeys.contains(e.key))
            e.key as String: e.value,
      };
      final directLayout = <String, Object?>{
        for (final e in op.entries)
          if (e.key is String && ScreenTreeCodec._layoutKeys.contains(e.key))
            e.key as String: e.value,
      };
      final directList = <String, Object?>{
        for (final e in op.entries)
          if (e.key is String && ScreenTreeCodec._listKeys.contains(e.key))
            e.key as String: e.value,
      };

      final existingComp = components[id];
      if (existingComp is SuperActionConfig && directAction.isNotEmpty) {
        components[id] = existingComp.patchFromJson(directAction);
      } else if (existingComp is SuperValueConfig && directValue.isNotEmpty) {
        components[id] = existingComp.patchFromJson(directValue);
      } else if (styles.containsKey(id) && directStyle.isNotEmpty) {
        styles[id] = styles[id]!.patchFromJson(directStyle);
      } else if (layouts.containsKey(id) && directLayout.isNotEmpty) {
        compileLayoutMap(id, directLayout, isMerge: true);
      } else if (existingComp is SuperListViewConfig && directList.isNotEmpty) {
        components[id] = existingComp.patchFromJson(directList);
      } else if (directValue.isNotEmpty &&
          !directStyle.keys.any((k) => k != 'color' && k != 'states')) {
        components[id] =
            (tryComponent<SuperValueConfig>(id) ?? const SuperValueConfig())
                .patchFromJson(directValue);
      } else if (directStyle.isNotEmpty) {
        styles[id] = (styles[id] ?? const ContainerStyle()).patchFromJson(
          directStyle,
        );
      } else if (directLayout.isNotEmpty) {
        compileLayoutMap(id, directLayout, isMerge: true);
      } else if (directList.isNotEmpty) {
        components[id] =
            (tryComponent<SuperListViewConfig>(id) ??
                    const SuperListViewConfig())
                .patchFromJson(directList);
      }
    }
  }

  void _opMove(Map<Object?, Object?> op) {
    final target = (op['target'] ?? op['parent'] ?? 'contA') as String;
    final id = op['id'] as String?;
    final dest = (op['zone'] ?? op['region']) as String?;
    if (id == null || dest == null) {
      throw const FormatException('Opération "move" : "id" et "zone" requis.');
    }
    final beforeId = op['beforeId'] as String?;
    final afterId = op['afterId'] as String?;

    if (layouts.containsKey(target)) {
      final zone = SuperLayoutZone.values
          .where((z) => z.name == dest)
          .firstOrNull;
      if (zone == null) {
        throw FormatException('Zone de layout invalide : $dest.');
      }
      var current = layouts[target]!;
      current = _enableZoneSides(current, zone);
      layouts[target] = current.withSlotMoved(
        id,
        zone,
        beforeId: beforeId,
        afterId: afterId,
        type: current.slotTypeOf(id),
      );
      return;
    }
    if (tryNative(target) case final native?) {
      components[target] = native.withSlotMoved(
        id,
        dest,
        beforeId: beforeId,
        afterId: afterId,
      );
      return;
    }
    throw FormatException('Conteneur cible introuvable : $target.');
  }

  void _opRemove(Map<Object?, Object?> op) {
    final id = op['id'] as String?;
    if (id == null || id.trim().isEmpty) {
      throw const FormatException('Opération "remove" : "id" requis.');
    }
    final target = (op['target'] ?? op['parent']) as String?;
    for (final entry in layouts.entries.toList()) {
      if (target != null && entry.key != target) continue;
      if (entry.value.placedSlotIds.contains(id)) {
        layouts[entry.key] = entry.value.withoutSlot(id);
      }
    }
    for (final entry in components.entries.toList()) {
      if (target != null && entry.key != target) continue;
      final native = tryNative(entry.key);
      if (native != null &&
          native.placements.values.any((ids) => ids.contains(id))) {
        components[entry.key] = native.withoutSlot(id);
      }
    }
    // Si le slot n'est plus placé nulle part, nettoyer ses configurations propres
    final stillPlaced =
        layouts.values.any((l) => l.placedSlotIds.contains(id)) ||
        components.keys.any(
          (k) =>
              tryNative(k)?.placements.values.any((ids) => ids.contains(id)) ??
              false,
        );
    if (!stillPlaced && op['keepConfig'] != true) {
      styles.remove(id);
      layouts.remove(id);
      components.remove(id);
    }
  }

  void _opUpsertPage(Map<Object?, Object?> op) {
    final id = op['id'] as String?;
    final name = (op['name'] ?? op['title'] ?? id) as String?;
    final path = op['path'] as String?;
    if (id == null || name == null || path == null) {
      throw const FormatException(
        'Opération "upsertPage" : "id", "name" et "path" requis.',
      );
    }
    final rawParams = op['defaultParameters'];
    final params = rawParams is Map
        ? {
            for (final e in rawParams.entries)
              if (e.key is String && e.value is String)
                e.key as String: e.value as String,
          }
        : const <String, String>{};
    upsertPage(
      EditorPageConfig(
        id: id,
        name: name,
        path: path,
        defaultParameters: params,
      ),
    );
    if (op['home'] == true) {
      homePageId = id;
    }
    if (op['screen'] is Map) {
      compileScreen(id, op['screen'] as Map, isMerge: true);
    } else if (op.containsKey('body') || op.containsKey('appBar')) {
      compileScreen(id, op, isMerge: true);
    }
  }

  void _opRemovePage(Map<Object?, Object?> op) {
    final id = op['id'] as String?;
    if (id == null || id.trim().isEmpty) {
      throw const FormatException('Opération "removePage" : "id" requis.');
    }
    pages.removeWhere((p) => p.id == id);
    if (homePageId == id) homePageId = null;
    components.remove(id);
  }

  SuperLayoutConfig _enableZoneSides(
    SuperLayoutConfig config,
    SuperLayoutZone zone,
  ) => switch (zone) {
    SuperLayoutZone.north => config.withSide(SuperLayoutZone.north, true),
    SuperLayoutZone.south => config.withSide(SuperLayoutZone.south, true),
    SuperLayoutZone.west => config.withSide(SuperLayoutZone.west, true),
    SuperLayoutZone.east => config.withSide(SuperLayoutZone.east, true),
    SuperLayoutZone.nw =>
      config
          .withSide(SuperLayoutZone.north, true)
          .withSide(SuperLayoutZone.west, true),
    SuperLayoutZone.ne =>
      config
          .withSide(SuperLayoutZone.north, true)
          .withSide(SuperLayoutZone.east, true),
    SuperLayoutZone.sw =>
      config
          .withSide(SuperLayoutZone.south, true)
          .withSide(SuperLayoutZone.west, true),
    SuperLayoutZone.se =>
      config
          .withSide(SuperLayoutZone.south, true)
          .withSide(SuperLayoutZone.east, true),
    SuperLayoutZone.center => config,
  };
}

class _CompiledSlot {
  const _CompiledSlot({
    required this.id,
    required this.type,
    this.constraints,
    this.hasPreferredSize = false,
    this.preferredSize,
    this.slotLabel,
  });

  final String id;
  final String type;
  final Object? constraints;
  final bool hasPreferredSize;
  final Object? preferredSize;
  final String? slotLabel;
}
