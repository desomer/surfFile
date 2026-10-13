import 'dart:math' as math;
import 'dart:ui';

enum SuperLayoutPositioning { zones, grid }

/// Integer cell coordinates, independent of the viewport's pixel size.
class GridSlotPosition {
  const GridSlotPosition({
    this.x = 0,
    this.y = 0,
    this.width = 4,
    this.height = 3,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  Rect get bounds => Rect.fromLTWH(
    x.toDouble(), y.toDouble(), width.toDouble(), height.toDouble(),
  );

  GridSlotPosition copyWith({int? x, int? y, int? width, int? height}) =>
      GridSlotPosition(
        x: x ?? this.x, y: y ?? this.y,
        width: width ?? this.width, height: height ?? this.height,
      );

  Map<String, Object> toJson() => {
    'x': x, 'y': y, 'width': width, 'height': height,
  };

  static GridSlotPosition fromJson(Object? value, int columns) {
    if (value is! Map) throw const FormatException('Position de grille invalide.');
    int integer(String key, int minimum) {
      final number = value[key];
      if (number is! int || number < minimum) {
        throw FormatException('Valeur de grille invalide : $key.');
      }
      return number;
    }
    final result = GridSlotPosition(
      x: integer('x', 0), y: integer('y', 0),
      width: integer('width', 1), height: integer('height', 1),
    );
    if (result.x + result.width > columns) {
      throw const FormatException('Slot hors des colonnes de la grille.');
    }
    return result;
  }

  @override
  bool operator ==(Object other) => other is GridSlotPosition &&
      x == other.x && y == other.y && width == other.width && height == other.height;
  @override
  int get hashCode => Object.hash(x, y, width, height);
}

class GridLayoutConfig {
  const GridLayoutConfig({
    this.columns = 12,
    this.rowHeight = 64,
    this.gap = 8,
    this.compact = true,
    this.items = const {},
  });

  final int columns;
  final double rowHeight;
  final double gap;
  final bool compact;
  final Map<String, GridSlotPosition> items;

  GridLayoutConfig copyWith({
    int? columns, double? rowHeight, double? gap, bool? compact,
    Map<String, GridSlotPosition>? items,
  }) => GridLayoutConfig(
    columns: columns ?? this.columns,
    rowHeight: rowHeight ?? this.rowHeight, gap: gap ?? this.gap,
    compact: compact ?? this.compact, items: items ?? this.items,
  );

  void validate() {
    if (columns < 1 || columns > 48 || !rowHeight.isFinite ||
        rowHeight < 16 || rowHeight > 400 || !gap.isFinite || gap < 0 || gap > 64) {
      throw ArgumentError('Parametres de grille invalides.');
    }
    for (final entry in items.entries) {
      final p = entry.value;
      if (entry.key.isEmpty || p.x < 0 || p.y < 0 || p.width < 1 ||
          p.height < 1 || p.x + p.width > columns) {
        throw ArgumentError('Position de grille invalide : ${entry.key}.');
      }
    }
  }

  /// The edited item wins collisions; other items are pushed down.
  GridLayoutConfig arrange({String? activeId, bool? compact}) {
    validate();
    final entries = items.entries.toList()
      ..sort((a, b) {
        if (a.key == activeId) return -1;
        if (b.key == activeId) return 1;
        final row = a.value.y.compareTo(b.value.y);
        return row != 0 ? row : a.value.x.compareTo(b.value.x);
      });
    final result = <String, GridSlotPosition>{};
    for (final entry in entries) {
      var p = entry.value;
      while (true) {
        final collisions = result.values.where((other) => other.bounds.overlaps(p.bounds));
        if (collisions.isEmpty) break;
        p = p.copyWith(y: collisions.map((other) => other.y + other.height)
            .reduce(math.max));
      }
      result[entry.key] = p;
    }
    if (compact ?? this.compact) {
      final ordered = result.keys.toList()
        ..sort((a, b) => result[a]!.y.compareTo(result[b]!.y));
      for (final id in ordered) {
        final p = result[id]!;
        final y = result.entries.where((entry) => entry.key != id &&
            entry.value.x < p.x + p.width &&
            p.x < entry.value.x + entry.value.width &&
            entry.value.y + entry.value.height <= p.y)
            .fold<int>(0, (bottom, entry) =>
              math.max(bottom, entry.value.y + entry.value.height));
        result[id] = p.copyWith(y: y);
      }
    }
    return copyWith(items: Map.unmodifiable(result));
  }

  GridLayoutConfig withItem(String id, GridSlotPosition position, {bool? compact}) =>
      copyWith(items: {...items, id: position}).arrange(activeId: id, compact: compact);

  GridLayoutConfig withColumns(int value) {
    if (value < 1 || value > 48) throw ArgumentError.value(value, 'columns');
    return copyWith(columns: value, items: {
      for (final entry in items.entries)
        entry.key: entry.value.copyWith(
          width: math.min(entry.value.width, value),
          x: math.min(entry.value.x, value - math.min(entry.value.width, value)),
        ),
    }).arrange();
  }

  GridLayoutConfig synchronize(Iterable<String> ids) {
    final ordered = ids.toSet();
    if (ordered.length == items.length && ordered.every(items.containsKey)) {
      return this;
    }
    final next = <String, GridSlotPosition>{
      for (final id in ordered) if (items.containsKey(id)) id: items[id]!,
    };
    for (final id in ordered) {
      if (next.containsKey(id)) continue;
      final width = math.min(4, columns);
      var p = GridSlotPosition(width: width);
      while (next.values.any((other) => other.bounds.overlaps(p.bounds))) {
        final x = p.x + width;
        p = p.copyWith(x: x + width <= columns ? x : 0,
            y: x + width <= columns ? p.y : p.y + 1);
      }
      next[id] = p;
    }
    return copyWith(items: Map.unmodifiable(next)).arrange();
  }

  Map<String, Object?> toJson() => {
    'columns': columns, 'rowHeight': rowHeight, 'gap': gap, 'compact': compact,
    'items': {for (final entry in items.entries) entry.key: entry.value.toJson()},
  };

  static GridLayoutConfig fromJson(Object? value) {
    if (value is! Map || value['columns'] is! int ||
        value['rowHeight'] is! num || value['gap'] is! num ||
        value['compact'] is! bool || value['items'] is! Map) {
      throw const FormatException('Grille invalide.');
    }
    final columns = value['columns'] as int;
    final raw = value['items'] as Map;
    final items = <String, GridSlotPosition>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) {
        throw const FormatException('Identifiant de grille invalide.');
      }
      items[entry.key as String] = GridSlotPosition.fromJson(entry.value, columns);
    }
    final result = GridLayoutConfig(
      columns: columns, rowHeight: (value['rowHeight'] as num).toDouble(),
      gap: (value['gap'] as num).toDouble(),
      compact: value['compact'] as bool, items: Map.unmodifiable(items),
    );
    try {
      result.validate();
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString());
    }
    if (items.entries.any((a) => items.entries.any((b) =>
        a.key != b.key && a.value.bounds.overlaps(b.value.bounds)))) {
      throw const FormatException('Chevauchement dans la grille.');
    }
    return result;
  }

  @override
  bool operator ==(Object other) => other is GridLayoutConfig &&
      columns == other.columns && rowHeight == other.rowHeight &&
      gap == other.gap && compact == other.compact &&
      items.length == other.items.length &&
      items.entries.every((entry) => other.items[entry.key] == entry.value);
  @override
  int get hashCode => Object.hash(columns, rowHeight, gap, compact,
      Object.hashAllUnordered(items.entries.map((e) => Object.hash(e.key, e.value))));
}
