import 'dart:ui';

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
    this.northSize = 80,
    this.southSize = 80,
    this.westSize = 120,
    this.eastSize = 120,
    this.swaps = const {},
    this.autoSides = const {},
    this.placements = const {},
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
      placements: {
        for (final MapEntry(:key, :value) in next.entries)
          if (value.isNotEmpty) key: List.unmodifiable(value),
      },
    );
  }

  SuperLayoutConfig _reflectCorners(SuperLayoutZone a, SuperLayoutZone b) =>
      withCorner(a, mergeOf(b)).withCorner(b, mergeOf(a));

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
    Set<SuperLayoutZone>? swaps,
    Set<SuperLayoutZone>? autoSides,
    Map<SuperLayoutZone, List<String>>? placements,
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
    swaps: swaps ?? this.swaps,
    autoSides: autoSides ?? this.autoSides,
    placements: placements ?? this.placements,
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
    'swaps': [for (final zone in swaps) zone.name],
    'autoSides': [for (final zone in autoSides) zone.name],
    'placements': {
      for (final MapEntry(:key, :value) in placements.entries)
        key.name: [...value],
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
            List() when value.every((id) => id is String) => [
              ...value.cast<String>(),
            ],
            _ => throw const FormatException(
              'Valeur invalide pour "placements".',
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
      swaps: swapSet(),
      autoSides: autoSet(),
      placements: placementMap(),
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
        isAuto(side) ? measured[side] ?? sizeOf(side) : sizeOf(side);
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
      other.swaps.length == swaps.length &&
      other.swaps.containsAll(swaps) &&
      other.autoSides.length == autoSides.length &&
      other.autoSides.containsAll(autoSides) &&
      _samePlacements(other.placements);

  bool _samePlacements(Map<SuperLayoutZone, List<String>> other) {
    if (other.length != placements.length) return false;
    for (final MapEntry(:key, :value) in placements.entries) {
      final ids = other[key];
      if (ids == null || ids.length != value.length) return false;
      for (var i = 0; i < ids.length; i++) {
        if (ids[i] != value[i]) return false;
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
    Object.hashAllUnordered(swaps),
    Object.hashAllUnordered(autoSides),
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in placements.entries)
        Object.hash(key, Object.hashAll(value)),
    ]),
  );
}
