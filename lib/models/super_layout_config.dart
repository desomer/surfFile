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
    );
  }

  /// Rectangles des zones affichées dans [size]. Une zone absente ou fusionnée
  /// n'apparaît pas dans le résultat ; la zone qui l'absorbe s'étend sur sa
  /// case.
  Map<SuperLayoutZone, Rect> resolve(Size size) {
    final (x1, x2) = _tracks(
      size.width,
      west ? westSize : 0,
      east ? eastSize : 0,
    );
    final (y1, y2) = _tracks(
      size.height,
      north ? northSize : 0,
      south ? southSize : 0,
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
      other.eastSize == eastSize;

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
  );
}
