import 'dart:ui';

import 'package:flutter/painting.dart' show Axis;

/// Les neuf zones d'un [SuperLayoutConfig].
enum SuperLayoutZone {
  nw('Nord-Ouest'),
  north('Nord'),
  ne('Nord-Est'),
  west('Ouest'),
  center('Centre'),
  east('Est'),
  sw('Sud-Ouest'),
  south('Sud'),
  se('Sud-Est');

  const SuperLayoutZone(this.label);

  final String label;

  /// Zone symétrique par rapport au centre ; `null` pour le centre.
  SuperLayoutZone? get opposite => switch (this) {
    nw => se,
    north => south,
    ne => sw,
    west => east,
    center => null,
    east => west,
    sw => ne,
    south => north,
    se => nw,
  };

  bool get isCorner => switch (this) {
    nw || ne || sw || se => true,
    _ => false,
  };

  bool get isSide => switch (this) {
    north || south || west || east => true,
    _ => false,
  };

  /// Représentant de la paire (zone, opposée), qui identifie un échange.
  SuperLayoutZone get _pairKey => switch (this) {
    se => nw,
    south => north,
    sw => ne,
    east => west,
    _ => this,
  };
}

/// Où se range une zone de coin : sa propre case ou fusionnée avec un seul de
/// ses deux voisins (jamais les deux).
enum CornerMerge {
  /// Le coin garde sa propre case.
  none,

  /// Le coin est absorbé par la zone de sa ligne (Nord ou Sud).
  row,

  /// Le coin est absorbé par la zone de sa colonne (Ouest ou Est).
  column,
}

enum SlotSizeUnit { pixels, percent }

enum SlotPercentBasis { zone, layout }

class SlotDimension {
  const SlotDimension(this.value, this.unit);

  final double value;
  final SlotSizeUnit unit;

  double resolve(double available) =>
      unit == SlotSizeUnit.percent ? available * value / 100 : value;

  Map<String, Object> toJson() => {
    'value': value,
    'unit': unit == SlotSizeUnit.pixels ? 'px' : 'percent',
  };

  static SlotDimension fromJson(Object? value) {
    if (value is! Map ||
        value['value'] is! num ||
        !(value['value'] as num).isFinite ||
        (value['value'] as num) < 0 ||
        (value['unit'] != 'px' && value['unit'] != 'percent')) {
      throw const FormatException('Dimension de slot invalide.');
    }
    return SlotDimension(
      (value['value'] as num).toDouble(),
      value['unit'] == 'px' ? SlotSizeUnit.pixels : SlotSizeUnit.percent,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SlotDimension && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);
}

class SlotSizeConstraints {
  const SlotSizeConstraints({
    this.minWidth,
    this.minHeight,
    this.maxWidth,
    this.maxHeight,
    this.preferredWidth,
    this.preferredHeight,
    this.percentBasis = SlotPercentBasis.zone,
  });

  final SlotDimension? minWidth;
  final SlotDimension? minHeight;
  final SlotDimension? maxWidth;
  final SlotDimension? maxHeight;
  final SlotDimension? preferredWidth;
  final SlotDimension? preferredHeight;
  final SlotPercentBasis percentBasis;

  Map<String, Object?> toJson() => {
    'percentBasis': percentBasis.name,
    for (final (key, dimension) in [
      ('minWidth', minWidth),
      ('minHeight', minHeight),
      ('maxWidth', maxWidth),
      ('maxHeight', maxHeight),
      ('preferredWidth', preferredWidth),
      ('preferredHeight', preferredHeight),
    ])
      if (dimension != null) key: dimension.toJson(),
  };

  static SlotSizeConstraints fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Contraintes de taille invalides.');
    }
    SlotDimension? dimension(String key) =>
        value.containsKey(key) ? SlotDimension.fromJson(value[key]) : null;
    final basis = switch (value['percentBasis']) {
      null || 'zone' => SlotPercentBasis.zone,
      'layout' => SlotPercentBasis.layout,
      _ => throw const FormatException('Base de pourcentage invalide.'),
    };
    return SlotSizeConstraints(
      minWidth: dimension('minWidth'),
      minHeight: dimension('minHeight'),
      maxWidth: dimension('maxWidth'),
      maxHeight: dimension('maxHeight'),
      preferredWidth: dimension('preferredWidth'),
      preferredHeight: dimension('preferredHeight'),
      percentBasis: basis,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SlotSizeConstraints &&
      other.minWidth == minWidth &&
      other.minHeight == minHeight &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight &&
      other.preferredWidth == preferredWidth &&
      other.preferredHeight == preferredHeight &&
      other.percentBasis == percentBasis;

  @override
  int get hashCode => Object.hash(
    minWidth,
    minHeight,
    maxWidth,
    maxHeight,
    preferredWidth,
    preferredHeight,
    percentBasis,
  );
}

/// Disposition en grille 3×3 : les zones Nord, Sud, Est et Ouest sont
/// optionnelles et les coins peuvent fusionner avec l'un de leurs voisins.
///
/// Un coin n'existe que si ses deux voisins existent ; sinon sa fusion est
/// sans effet.
class SuperLayoutConfig {
  const SuperLayoutConfig({
    this.north = true,
    this.south = true,
    this.west = true,
    this.east = true,
    this.nw = CornerMerge.none,
    this.ne = CornerMerge.none,
    this.sw = CornerMerge.none,
    this.se = CornerMerge.none,
    this.northSize = 30,
    this.southSize = 30,
    this.westSize = 30,
    this.eastSize = 30,
    this.resizeSides = false,
    this.sideResizing = const {},
    this.collapsedSides = const {},
    this.swaps = const {},
    this.autoSides = const {},
    this.placements = const {},
    this.slotTypes = const {},
    this.slotPreferredSizes = const {},
    this.slotSizeConstraints = const {},
    this.zoneAxes = const {},
  });

  static const minSize = 20.0;
  static const maxSize = 400.0;

  final bool north;
  final bool south;
  final bool west;
  final bool east;
  final CornerMerge nw;
  final CornerMerge ne;
  final CornerMerge sw;
  final CornerMerge se;

  /// Hauteur des zones Nord/Sud et largeur des zones Ouest/Est.
  final double northSize;
  final double southSize;
  final double westSize;
  final double eastSize;

  /// Autorise le redimensionnement des quatre cotes par leur bord interieur.
  final bool resizeSides;

  /// Reglages par cote ; sans entree, utilise [resizeSides].
  final Map<SuperLayoutZone, bool> sideResizing;
  /// Taille fixe a restaurer pour les cotes reduits a zero.
  final Map<SuperLayoutZone, double> collapsedSides;

  bool canResize(SuperLayoutZone side) =>
      side.isSide && (sideResizing[side] ?? resizeSides);

  SuperLayoutConfig withSideResizing(SuperLayoutZone side, bool enabled) {
    if (!side.isSide) throw ArgumentError.value(side, 'side', 'Pas un cote');
    return copyWith(sideResizing: {...sideResizing, side: enabled});
  }

  /// Bornes du glisser, en resolvant les % de zone sur la taille candidate.
  ({double min, double max}) resizeBounds(
    SuperLayoutZone side,
    Iterable<String> visibleSlotIds,
    double layoutExtent,
  ) {
    if (!side.isSide) throw ArgumentError.value(side, 'side', 'Pas un cote');
    final vertical =
        side == SuperLayoutZone.north || side == SuperLayoutZone.south;
    final stacked = axisOf(side) == (vertical ? Axis.vertical : Axis.horizontal);
    var lower = minSize;
    var upper = maxSize;
    void constrain(double coefficient, double constant) {
      if (coefficient > 0) {
        final bound = constant / coefficient;
        if (bound < upper) upper = bound;
      } else if (coefficient < 0) {
        final bound = constant / coefficient;
        if (bound > lower) lower = bound;
      } else if (constant < 0) {
        lower = double.infinity;
      }
    }

    (double, double) term(SlotDimension? dimension, SlotPercentBasis basis) {
      if (dimension == null) return (0, 0);
      if (dimension.unit == SlotSizeUnit.pixels) return (0, dimension.value);
      return basis == SlotPercentBasis.zone
          ? (dimension.value / 100, 0)
          : (0, dimension.resolve(layoutExtent));
    }

    var minCoefficient = 0.0;
    var minConstant = 0.0;
    var maxCoefficient = 0.0;
    var maxConstant = 0.0;
    var boundedMax = true;
    var count = 0;
    for (final id in visibleSlotIds) {
      count++;
      final constraints = slotSizeConstraints[id];
      final minimum = vertical ? constraints?.minHeight : constraints?.minWidth;
      final maximum = vertical ? constraints?.maxHeight : constraints?.maxWidth;
      final basis = constraints?.percentBasis ?? SlotPercentBasis.zone;
      final (minA, minB) = term(minimum, basis);
      final (maxA, maxB) = term(maximum, basis);
      if (stacked) {
        minCoefficient += minA;
        minConstant += minB;
        maxCoefficient += maxA;
        maxConstant += maxB;
        boundedMax &= maximum != null;
      } else {
        if (minimum != null) constrain(minA - 1, -minB);
        if (maximum != null) constrain(1 - maxA, maxB);
      }
    }
    if (stacked && count > 0) {
      constrain(minCoefficient - 1, -minConstant);
      if (boundedMax) constrain(1 - maxCoefficient, maxConstant);
    }
    return (min: lower, max: upper);
  }

  /// Paires de zones opposées dont les contenus sont échangés, identifiées par
  /// leur représentant (Nord, Ouest, Nord-Ouest ou Nord-Est).
  final Set<SuperLayoutZone> swaps;

  /// Côtés (Nord, Sud, Est, Ouest) dont la taille suit celle de leur contenu au
  /// lieu de la valeur fixe correspondante.
  final Set<SuperLayoutZone> autoSides;

  /// Identifiants des slots rangés dans chaque zone, dans l'ordre d'empilement.
  /// Les clés sont celles de [contentZone] : un échange de zones déplace donc
  /// aussi les slots avec leur zone.
  final Map<SuperLayoutZone, List<String>> placements;

  /// Type de fabrique par ID d'instance ; sans entree, le type est l'ID.
  final Map<String, String> slotTypes;

  /// Tailles preferees par ID d'instance ; null force la taille automatique.
  final Map<String, Size?> slotPreferredSizes;

  /// Bornes min/max et tailles preferees par instance, en pixels ou en
  /// pourcentage de la zone qui contient le slot.
  final Map<String, SlotSizeConstraints> slotSizeConstraints;

  /// Axe des slots par zone de contenu ; une zone absente utilise Column.
  final Map<SuperLayoutZone, Axis> zoneAxes;

  Axis axisOf(SuperLayoutZone zone) =>
      zoneAxes[contentZone(zone)] ?? Axis.vertical;

  SuperLayoutConfig withAxis(SuperLayoutZone zone, Axis axis) =>
      copyWith(zoneAxes: {...zoneAxes, contentZone(zone): axis});

  SuperLayoutConfig withSlotPreferredSize(String id, Size? size) {
    if (size != null &&
        (!size.width.isFinite ||
            !size.height.isFinite ||
            size.width <= 0 ||
            size.height <= 0)) {
      throw ArgumentError.value(size, 'size', 'Dimensions positives requises.');
    }
    final sizes = {...slotPreferredSizes};
    sizes[id] = size;
    return copyWith(slotPreferredSizes: sizes);
  }

  String slotTypeOf(String id) => slotTypes[id] ?? id;

  bool isAuto(SuperLayoutZone side) => autoSides.contains(side);

  List<String> placementsOf(SuperLayoutZone zone) =>
      placements[zone] ?? const [];

  /// Zones qui existent, quelle que soit la taille disponible.
  Set<SuperLayoutZone> get visibleZones => resolve(Size.zero).keys.toSet();

  /// Zone dont le contenu est affiché à l'emplacement de [zone] ; la relation
  /// est symétrique, elle donne donc aussi l'emplacement du contenu de [zone].
  SuperLayoutZone contentZone(SuperLayoutZone zone) {
    final opposite = zone.opposite;
    return opposite != null && swaps.contains(zone._pairKey) ? opposite : zone;
  }

  /// Échange (ou rétablit) les contenus de [zone] et de sa zone opposée.
  ///
  /// Le contenu change de côté avec sa taille et les fusions de coins qui le
  /// concernent ; si la zone opposée n'existe pas, il s'agit d'un déplacement
  /// et l'existence des deux côtés est aussi échangée.
  SuperLayoutConfig withSwap(SuperLayoutZone zone) {
    final opposite = zone.opposite;
    if (opposite == null) {
      throw ArgumentError.value(zone, 'zone', 'Pas de zone opposée');
    }
    final key = zone._pairKey;
    var next = copyWith(
      swaps: swaps.contains(key) ? ({...swaps}..remove(key)) : {...swaps, key},
    );
    if (zone.isCorner) return next._reflectCorners(zone, opposite);
    final (first, second) = switch (zone) {
      SuperLayoutZone.north ||
      SuperLayoutZone.south => (SuperLayoutZone.north, SuperLayoutZone.south),
      _ => (SuperLayoutZone.west, SuperLayoutZone.east),
    };
    next = next
        .withSide(first, hasSide(second))
        .withSide(second, hasSide(first))
        ._withSize(first, sizeOf(second))
        ._withSize(second, sizeOf(first))
        ._withAuto(first, isAuto(second))
        ._withAuto(second, isAuto(first));
    // Les coins se reflètent d'un bord à l'autre de l'axe déplacé.
    return first == SuperLayoutZone.north
        ? next
              ._reflectCorners(SuperLayoutZone.nw, SuperLayoutZone.sw)
              ._reflectCorners(SuperLayoutZone.ne, SuperLayoutZone.se)
        : next
              ._reflectCorners(SuperLayoutZone.nw, SuperLayoutZone.ne)
              ._reflectCorners(SuperLayoutZone.sw, SuperLayoutZone.se);
  }

  /// Un échange est possible si la zone a une opposée et que celle-ci peut
  /// exister (un coin a besoin de ses deux côtés).
  bool canSwap(SuperLayoutZone zone) {
    final opposite = zone.opposite;
    if (opposite == null) return false;
    return !zone.isCorner || cornerExists(opposite);
  }

  double sizeOf(SuperLayoutZone side) => switch (side) {
    SuperLayoutZone.north => northSize,
    SuperLayoutZone.south => southSize,
    SuperLayoutZone.west => westSize,
    _ => eastSize,
  };

  SuperLayoutConfig withSize(SuperLayoutZone side, double value) {
    if (!side.isSide || !value.isFinite || value < minSize || value > maxSize) {
      throw ArgumentError('Cote et taille entre $minSize et $maxSize requis.');
    }
    return _withSize(side, value);
  }

  SuperLayoutConfig _withSize(SuperLayoutZone side, double value) =>
      switch (side) {
        SuperLayoutZone.north => copyWith(northSize: value),
        SuperLayoutZone.south => copyWith(southSize: value),
        SuperLayoutZone.west => copyWith(westSize: value),
        _ => copyWith(eastSize: value),
      };

  SuperLayoutConfig _withAuto(SuperLayoutZone side, bool auto) => copyWith(
    autoSides: auto ? {...autoSides, side} : ({...autoSides}..remove(side)),
  );

  SuperLayoutConfig withAuto(SuperLayoutZone side, bool auto) {
    if (!side.isSide) {
      throw ArgumentError.value(side, 'side', 'Pas un côté');
    }
    return _withAuto(side, auto);
  }

  SuperLayoutConfig withPlacement(SuperLayoutZone zone, List<String> ids) =>
      copyWith(
        placements: {
          for (final MapEntry(:key, :value) in placements.entries)
            if (key != zone) key: value,
          if (ids.isNotEmpty) zone: List.unmodifiable(ids),
        },
      );

  /// Range le slot [id] dans la zone de contenu [zone] (clé de [placements]),
  /// juste avant [beforeId] ou après [afterId], ou en dernier sans repère. Il
  /// quitte la zone où il se trouvait ; un repère inconnu place le slot en
  /// dernier.
  SuperLayoutConfig withSlotMoved(
    String id,
    SuperLayoutZone zone, {
    String? beforeId,
    String? afterId,
    String? type,
  }) {
    assert(beforeId == null || afterId == null);
    final next = {
      for (final MapEntry(:key, :value) in placements.entries)
        key: [
          for (final other in value)
            if (other != id) other,
        ],
    };
    final ids = next[zone] ?? <String>[];
    var at = ids.length;
    if (beforeId != null) {
      final index = ids.indexOf(beforeId);
      if (index >= 0) at = index;
    } else if (afterId != null) {
      final index = ids.indexOf(afterId);
      if (index >= 0) at = index + 1;
    }

    ids.insert(at, id);
    next[zone] = ids;
    return copyWith(
      slotTypes: type == null ? slotTypes : {...slotTypes, id: type},
      placements: {
        for (final MapEntry(:key, :value) in next.entries)
          if (value.isNotEmpty) key: List.unmodifiable(value),
      },
    );
  }

  SuperLayoutConfig _reflectCorners(SuperLayoutZone a, SuperLayoutZone b) =>
      withCorner(a, mergeOf(b)).withCorner(b, mergeOf(a));

  /// Retire une instance de slot et ses reglages sans supprimer son composant.
  SuperLayoutConfig withoutSlot(String id) => copyWith(
    placements: {
      for (final entry in placements.entries)
        if (entry.value.any((other) => other != id))
          entry.key: List.unmodifiable([
            for (final other in entry.value)
              if (other != id) other,
          ]),
    },
    slotTypes: {...slotTypes}..remove(id),
    slotPreferredSizes: {...slotPreferredSizes}..remove(id),
    slotSizeConstraints: {...slotSizeConstraints}..remove(id),
  );

  bool hasSide(SuperLayoutZone zone) => switch (zone) {
    SuperLayoutZone.north => north,
    SuperLayoutZone.south => south,
    SuperLayoutZone.west => west,
    SuperLayoutZone.east => east,
    _ => true,
  };

  CornerMerge mergeOf(SuperLayoutZone corner) => switch (corner) {
    SuperLayoutZone.nw => nw,
    SuperLayoutZone.ne => ne,
    SuperLayoutZone.sw => sw,
    SuperLayoutZone.se => se,
    _ => throw ArgumentError.value(corner, 'corner', 'Pas un coin'),
  };

  /// Un coin n'a de sens que si ses deux voisins existent.
  bool cornerExists(SuperLayoutZone corner) => switch (corner) {
    SuperLayoutZone.nw => north && west,
    SuperLayoutZone.ne => north && east,
    SuperLayoutZone.sw => south && west,
    SuperLayoutZone.se => south && east,
    _ => throw ArgumentError.value(corner, 'corner', 'Pas un coin'),
  };

  SuperLayoutConfig copyWith({
    bool? north,
    bool? south,
    bool? west,
    bool? east,
    CornerMerge? nw,
    CornerMerge? ne,
    CornerMerge? sw,
    CornerMerge? se,
    double? northSize,
    double? southSize,
    double? westSize,
    double? eastSize,
    bool? resizeSides,
    Map<SuperLayoutZone, bool>? sideResizing,
    Map<SuperLayoutZone, double>? collapsedSides,
    Set<SuperLayoutZone>? swaps,
    Set<SuperLayoutZone>? autoSides,
    Map<SuperLayoutZone, List<String>>? placements,
    Map<String, String>? slotTypes,
    Map<String, Size?>? slotPreferredSizes,
    Map<String, SlotSizeConstraints>? slotSizeConstraints,
    Map<SuperLayoutZone, Axis>? zoneAxes,
  }) => SuperLayoutConfig(
    north: north ?? this.north,
    south: south ?? this.south,
    west: west ?? this.west,
    east: east ?? this.east,
    nw: nw ?? this.nw,
    ne: ne ?? this.ne,
    sw: sw ?? this.sw,
    se: se ?? this.se,
    northSize: northSize ?? this.northSize,
    southSize: southSize ?? this.southSize,
    westSize: westSize ?? this.westSize,
    eastSize: eastSize ?? this.eastSize,
    resizeSides: resizeSides ?? this.resizeSides,
    sideResizing: sideResizing ?? this.sideResizing,
    collapsedSides: collapsedSides ?? this.collapsedSides,
    swaps: swaps ?? this.swaps,
    autoSides: autoSides ?? this.autoSides,
    placements: placements ?? this.placements,
    slotTypes: slotTypes ?? this.slotTypes,
    slotPreferredSizes: slotPreferredSizes ?? this.slotPreferredSizes,
    slotSizeConstraints: slotSizeConstraints ?? this.slotSizeConstraints,
    zoneAxes: zoneAxes ?? this.zoneAxes,
  );

  SuperLayoutConfig withCorner(SuperLayoutZone corner, CornerMerge merge) =>
      switch (corner) {
        SuperLayoutZone.nw => copyWith(nw: merge),
        SuperLayoutZone.ne => copyWith(ne: merge),
        SuperLayoutZone.sw => copyWith(sw: merge),
        SuperLayoutZone.se => copyWith(se: merge),
        _ => throw ArgumentError.value(corner, 'corner', 'Pas un coin'),
      };

  SuperLayoutConfig withSide(SuperLayoutZone side, bool exists) =>
      switch (side) {
        SuperLayoutZone.north => copyWith(north: exists),
        SuperLayoutZone.south => copyWith(south: exists),
        SuperLayoutZone.west => copyWith(west: exists),
        SuperLayoutZone.east => copyWith(east: exists),
        _ => throw ArgumentError.value(side, 'side', 'Pas un côté'),
      };

  Map<String, Object?> toJson() => {
    'north': north,
    'south': south,
    'west': west,
    'east': east,
    'nw': nw.name,
    'ne': ne.name,
    'sw': sw.name,
    'se': se.name,
    'northSize': northSize,
    'southSize': southSize,
    'westSize': westSize,
    'eastSize': eastSize,
    'resizeSides': resizeSides,
    'sideResizing': {
      for (final entry in sideResizing.entries) entry.key.name: entry.value,
    },
    'collapsedSides': {
      for (final entry in collapsedSides.entries) entry.key.name: entry.value,
    },
    'swaps': [for (final zone in swaps) zone.name],
    'autoSides': [for (final zone in autoSides) zone.name],
    'zoneAxes': {
      for (final entry in zoneAxes.entries)
        entry.key.name: entry.value == Axis.horizontal ? 'row' : 'column',
    },
    'slotPreferredSizes': {
      for (final entry in slotPreferredSizes.entries)
        entry.key: entry.value == null
            ? null
            : {'width': entry.value!.width, 'height': entry.value!.height},
    },
    'slotSizeConstraints': {
      for (final entry in slotSizeConstraints.entries)
        entry.key: entry.value.toJson(),
    },
    'placements': {
      for (final MapEntry(:key, :value) in placements.entries)
        key.name: [
          for (final id in value) {'type': slotTypeOf(id), 'id': id},
        ],
    },
  };

  /// [fallback] fournit les valeurs des clés absentes.
  static SuperLayoutConfig fromJson(
    Object? value, {
    SuperLayoutConfig fallback = const SuperLayoutConfig(),
  }) {
    if (value == null) return fallback;
    if (value is! Map) {
      throw const FormatException('Disposition invalide.');
    }
    bool flag(String key, bool fallback) {
      final v = value[key] ?? fallback;
      if (v is! bool) throw FormatException('Valeur invalide pour "$key".');
      return v;
    }

    Map<SuperLayoutZone, bool> resizing() {
      final raw = value['sideResizing'];
      if (raw == null) return fallback.sideResizing;
      if (raw is! Map) throw const FormatException('Redimensionnement invalide.');
      final result = <SuperLayoutZone, bool>{};
      for (final entry in raw.entries) {
        final side = SuperLayoutZone.values
            .where((side) => side.isSide && side.name == entry.key)
            .firstOrNull;
        if (side == null || entry.value is! bool) {
          throw const FormatException('Redimensionnement par cote invalide.');
        }
        result[side] = entry.value as bool;
      }
      return result;
    }

    Map<SuperLayoutZone, double> collapsed() {
      final raw = value['collapsedSides'];
      if (raw == null) return fallback.collapsedSides;
      if (raw is! Map) throw const FormatException('Cotes reduits invalides.');
      final result = <SuperLayoutZone, double>{};
      for (final entry in raw.entries) {
        final side = SuperLayoutZone.values
            .where((side) => side.isSide && side.name == entry.key)
            .firstOrNull;
        final extent = entry.value;
        if (side == null || extent is! num || !extent.isFinite ||
            extent < minSize || extent > maxSize) {
          throw const FormatException('Cote reduit invalide.');
        }
        result[side] = extent.toDouble();
      }
      return result;
    }

    CornerMerge merge(String key, CornerMerge fallback) {
      final name = value[key] ?? fallback.name;
      return CornerMerge.values.where((m) => m.name == name).firstOrNull ??
          (throw FormatException('Valeur invalide pour "$key".'));
    }

    double size(String key, double fallback) {
      final v = value[key] ?? fallback;
      if (v is! num || !v.isFinite || v < minSize || v > maxSize) {
        throw FormatException('Valeur invalide pour "$key".');
      }
      return v.toDouble();
    }

    Set<SuperLayoutZone> swapSet() {
      final v = value['swaps'];
      if (v == null) return fallback.swaps;
      if (v is! List) {
        throw const FormatException('Valeur invalide pour "swaps".');
      }
      return {
        for (final name in v)
          SuperLayoutZone.values
                  .where(
                    (z) =>
                        z.name == name && z.opposite != null && z._pairKey == z,
                  )
                  .firstOrNull ??
              (throw const FormatException('Valeur invalide pour "swaps".')),
      };
    }

    Set<SuperLayoutZone> autoSet() {
      final v = value['autoSides'];
      if (v == null) return fallback.autoSides;
      if (v is! List) {
        throw const FormatException('Valeur invalide pour "autoSides".');
      }
      return {
        for (final name in v)
          SuperLayoutZone.values
                  .where((z) => z.name == name && z.isSide)
                  .firstOrNull ??
              (throw const FormatException(
                'Valeur invalide pour "autoSides".',
              )),
      };
    }

    final slotTypes = <String, String>{};
    final seenTypes = <String, String>{};
    String placementId(Object? placement) {
      final String id;
      final String type;
      if (placement is String) {
        id = placement;
        type = placement;
      } else if (placement is Map &&
          placement['id'] is String &&
          placement['type'] is String &&
          (placement['id'] as String).isNotEmpty &&
          (placement['type'] as String).isNotEmpty) {
        id = placement['id'] as String;
        type = placement['type'] as String;
      } else {
        throw const FormatException('Placement invalide : type et id requis.');
      }
      if (seenTypes.containsKey(id) && seenTypes[id] != type) {
        throw FormatException('Types incompatibles pour le slot "$id".');
      }
      seenTypes[id] = type;
      if (type != id) slotTypes[id] = type;
      return id;
    }

    Map<SuperLayoutZone, List<String>> placementMap() {
      final v = value['placements'];
      if (v == null) return fallback.placements;
      if (v is! Map) {
        throw const FormatException('Valeur invalide pour "placements".');
      }
      return {
        for (final MapEntry(:key, :value) in v.entries)
          SuperLayoutZone.values.where((z) => z.name == key).firstOrNull ??
              (throw const FormatException(
                'Valeur invalide pour "placements".',
              )): switch (value) {
            List() => [for (final placement in value) placementId(placement)],
            _ => throw const FormatException(
              'Valeur invalide pour "placements".',
            ),
          },
      };
    }

    Map<String, Size?> preferredSizes() {
      final sizes = value['slotPreferredSizes'];
      if (sizes == null) return fallback.slotPreferredSizes;
      if (sizes is! Map) {
        throw const FormatException('Tailles preferees invalides.');
      }
      final result = <String, Size?>{};
      for (final entry in sizes.entries) {
        final dimensions = entry.value;
        if (entry.key is! String || (entry.key as String).isEmpty) {
          throw const FormatException('Taille preferee invalide.');
        }
        if (dimensions == null) {
          result[entry.key as String] = null;
          continue;
        }
        if (dimensions is! Map) {
          throw const FormatException('Taille preferee invalide.');
        }
        final width = dimensions['width'];
        final height = dimensions['height'];
        if (width is! num ||
            height is! num ||
            !width.isFinite ||
            !height.isFinite ||
            width <= 0 ||
            height <= 0) {
          throw const FormatException('Dimensions positives requises.');
        }
        result[entry.key as String] = Size(width.toDouble(), height.toDouble());
      }
      return result;
    }

    Map<String, SlotSizeConstraints> slotConstraints() {
      final raw = value['slotSizeConstraints'];
      if (raw == null) return fallback.slotSizeConstraints;
      if (raw is! Map) {
        throw const FormatException('Contraintes de taille invalides.');
      }
      final result = <String, SlotSizeConstraints>{};
      for (final entry in raw.entries) {
        if (entry.key is! String || (entry.key as String).isEmpty) {
          throw const FormatException('Identifiant de slot invalide.');
        }
        result[entry.key as String] = SlotSizeConstraints.fromJson(entry.value);
      }
      return result;
    }

    Map<SuperLayoutZone, Axis> axes() {
      final raw = value['zoneAxes'];
      if (raw == null) return fallback.zoneAxes;
      if (raw is! Map) {
        throw const FormatException('Axes des zones invalides.');
      }
      return {
        for (final entry in raw.entries)
          SuperLayoutZone.values
                  .where((zone) => zone.name == entry.key)
                  .firstOrNull ??
              (throw const FormatException(
                'Zone invalide pour "zoneAxes".',
              )): switch (entry.value) {
            'row' => Axis.horizontal,
            'column' => Axis.vertical,
            _ => throw const FormatException(
              'Axe invalide : row ou column requis.',
            ),
          },
      };
    }

    return SuperLayoutConfig(
      north: flag('north', fallback.north),
      south: flag('south', fallback.south),
      west: flag('west', fallback.west),
      east: flag('east', fallback.east),
      nw: merge('nw', fallback.nw),
      ne: merge('ne', fallback.ne),
      sw: merge('sw', fallback.sw),
      se: merge('se', fallback.se),
      northSize: size('northSize', fallback.northSize),
      southSize: size('southSize', fallback.southSize),
      westSize: size('westSize', fallback.westSize),
      eastSize: size('eastSize', fallback.eastSize),
      resizeSides: flag('resizeSides', fallback.resizeSides),
      sideResizing: resizing(),
      collapsedSides: collapsed(),
      swaps: swapSet(),
      autoSides: autoSet(),
      placements: placementMap(),
      slotTypes: value['placements'] == null ? fallback.slotTypes : slotTypes,
      slotPreferredSizes: preferredSizes(),
      slotSizeConstraints: slotConstraints(),
      zoneAxes: axes(),
    );
  }

  /// Rectangles des zones affichées dans [size]. Une zone absente ou fusionnée
  /// n'apparaît pas dans le résultat ; la zone qui l'absorbe s'étend sur sa
  /// case. [measured] donne l'épaisseur mesurée des côtés en taille
  /// automatique ; sans mesure, la taille fixe du côté s'applique.
  Map<SuperLayoutZone, Rect> resolve(
    Size size, {
    Map<SuperLayoutZone, double> measured = const {},
  }) {
    double extent(SuperLayoutZone side) =>
        collapsedSides.containsKey(side)
        ? 0
        : isAuto(side) ? measured[side] ?? sizeOf(side) : sizeOf(side);
    final (x1, x2) = _tracks(
      size.width,
      west ? extent(SuperLayoutZone.west) : 0,
      east ? extent(SuperLayoutZone.east) : 0,
    );
    final (y1, y2) = _tracks(
      size.height,
      north ? extent(SuperLayoutZone.north) : 0,
      south ? extent(SuperLayoutZone.south) : 0,
    );
    final width = size.width;
    final height = size.height;
    return {
      SuperLayoutZone.center: Rect.fromLTRB(x1, y1, x2, y2),
      if (north)
        SuperLayoutZone.north: Rect.fromLTRB(
          nw == CornerMerge.row ? 0 : x1,
          0,
          ne == CornerMerge.row ? width : x2,
          y1,
        ),
      if (south)
        SuperLayoutZone.south: Rect.fromLTRB(
          sw == CornerMerge.row ? 0 : x1,
          y2,
          se == CornerMerge.row ? width : x2,
          height,
        ),
      if (west)
        SuperLayoutZone.west: Rect.fromLTRB(
          0,
          nw == CornerMerge.column ? 0 : y1,
          x1,
          sw == CornerMerge.column ? height : y2,
        ),
      if (east)
        SuperLayoutZone.east: Rect.fromLTRB(
          x2,
          ne == CornerMerge.column ? 0 : y1,
          width,
          se == CornerMerge.column ? height : y2,
        ),
      if (cornerExists(SuperLayoutZone.nw) && nw == CornerMerge.none)
        SuperLayoutZone.nw: Rect.fromLTRB(0, 0, x1, y1),
      if (cornerExists(SuperLayoutZone.ne) && ne == CornerMerge.none)
        SuperLayoutZone.ne: Rect.fromLTRB(x2, 0, width, y1),
      if (cornerExists(SuperLayoutZone.sw) && sw == CornerMerge.none)
        SuperLayoutZone.sw: Rect.fromLTRB(0, y2, x1, height),
      if (cornerExists(SuperLayoutZone.se) && se == CornerMerge.none)
        SuperLayoutZone.se: Rect.fromLTRB(x2, y2, width, height),
    };
  }

  /// Fin de la première piste et début de la dernière ; les pistes fixes sont
  /// réduites proportionnellement si elles dépassent [total].
  static (double, double) _tracks(double total, double start, double end) {
    final fixed = start + end;
    final scale = fixed > total && fixed > 0 ? total / fixed : 1.0;
    return (start * scale, total - end * scale);
  }

  @override
  bool operator ==(Object other) =>
      other is SuperLayoutConfig &&
      other.north == north &&
      other.south == south &&
      other.west == west &&
      other.east == east &&
      other.nw == nw &&
      other.ne == ne &&
      other.sw == sw &&
      other.se == se &&
      other.northSize == northSize &&
      other.southSize == southSize &&
      other.westSize == westSize &&
      other.eastSize == eastSize &&
      other.resizeSides == resizeSides &&
      other.collapsedSides.length == collapsedSides.length &&
      collapsedSides.entries.every(
        (entry) => other.collapsedSides[entry.key] == entry.value,
      ) &&
      other.sideResizing.length == sideResizing.length &&
      sideResizing.entries.every(
        (entry) => other.sideResizing[entry.key] == entry.value,
      ) &&
      other.swaps.length == swaps.length &&
      other.swaps.containsAll(swaps) &&
      other.autoSides.length == autoSides.length &&
      other.autoSides.containsAll(autoSides) &&
      other.zoneAxes.length == zoneAxes.length &&
      zoneAxes.entries.every(
        (entry) => other.zoneAxes[entry.key] == entry.value,
      ) &&
      other.slotPreferredSizes.length == slotPreferredSizes.length &&
      slotPreferredSizes.entries.every(
        (entry) =>
            other.slotPreferredSizes.containsKey(entry.key) &&
            other.slotPreferredSizes[entry.key] == entry.value,
      ) &&
      other.slotSizeConstraints.length == slotSizeConstraints.length &&
      slotSizeConstraints.entries.every(
        (entry) =>
            other.slotSizeConstraints.containsKey(entry.key) &&
            other.slotSizeConstraints[entry.key] == entry.value,
      ) &&
      _samePlacements(other);

  bool _samePlacements(SuperLayoutConfig other) {
    if (other.placements.length != placements.length) return false;
    for (final MapEntry(:key, :value) in placements.entries) {
      final ids = other.placements[key];
      if (ids == null || ids.length != value.length) return false;
      for (var i = 0; i < ids.length; i++) {
        if (ids[i] != value[i] ||
            other.slotTypeOf(ids[i]) != slotTypeOf(value[i])) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    north,
    south,
    west,
    east,
    nw,
    ne,
    sw,
    se,
    northSize,
    southSize,
    westSize,
    eastSize,
    Object.hash(
      resizeSides,
      Object.hashAllUnordered([
        for (final entry in sideResizing.entries)
          Object.hash(entry.key, entry.value),
      ]),
      Object.hashAllUnordered([
        for (final entry in collapsedSides.entries)
          Object.hash(entry.key, entry.value),
      ]),
    ),
    Object.hashAllUnordered(swaps),
    Object.hashAllUnordered(autoSides),
    Object.hashAllUnordered([
      for (final entry in zoneAxes.entries) Object.hash(entry.key, entry.value),
    ]),
    Object.hashAllUnordered([
      for (final entry in slotPreferredSizes.entries)
        Object.hash(entry.key, entry.value),
    ]),
    Object.hashAllUnordered([
      for (final entry in slotSizeConstraints.entries)
        Object.hash(entry.key, entry.value),
    ]),
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in placements.entries)
        Object.hash(
          key,
          Object.hashAll([
            for (final id in value) Object.hash(id, slotTypeOf(id)),
          ]),
        ),
    ]),
  );
}
