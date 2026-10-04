import 'dart:math' as math;
import 'dart:ui';

/// Dispose des surfaces proportionnelles à [weights] dans [bounds] (treemap
/// « squarified » : les rectangles restent proches du carré).
///
/// [weights] doit être trié par ordre décroissant et strictement positif ; le
/// rectangle `i` du résultat correspond à `weights[i]`.
List<Rect> squarifyTreemap(List<double> weights, Rect bounds) {
  if (weights.isEmpty) return const [];
  if (bounds.isEmpty) return List.filled(weights.length, Rect.zero);

  final total = weights.fold<double>(0, (sum, weight) => sum + weight);
  final scale = bounds.width * bounds.height / total;
  final areas = [for (final weight in weights) weight * scale];
  final result = List<Rect>.filled(weights.length, Rect.zero);

  var free = bounds;
  var start = 0;
  while (start < areas.length) {
    final side = math.min(free.width, free.height);
    var end = start + 1;
    var sum = areas[start];
    var worst = _worstRatio(areas[start], areas[start], sum, side);
    while (end < areas.length) {
      final candidate = sum + areas[end];
      final ratio = _worstRatio(areas[start], areas[end], candidate, side);
      if (ratio > worst) break;
      sum = candidate;
      worst = ratio;
      end++;
    }

    // La rangée occupe toute la petite dimension de l'espace libre.
    if (free.width >= free.height) {
      final width = sum / free.height;
      var top = free.top;
      for (var i = start; i < end; i++) {
        final height = areas[i] / width;
        result[i] = Rect.fromLTWH(free.left, top, width, height);
        top += height;
      }
      free = Rect.fromLTRB(
        free.left + width,
        free.top,
        free.right,
        free.bottom,
      );
    } else {
      final height = sum / free.width;
      var left = free.left;
      for (var i = start; i < end; i++) {
        final width = areas[i] / height;
        result[i] = Rect.fromLTWH(left, free.top, width, height);
        left += width;
      }
      free = Rect.fromLTRB(
        free.left,
        free.top + height,
        free.right,
        free.bottom,
      );
    }
    start = end;
  }
  return result;
}

/// Pire rapport d'aspect d'une rangée de surface totale [sum], dont la plus
/// grande surface est [largest] et la plus petite [smallest].
double _worstRatio(double largest, double smallest, double sum, double side) {
  final squared = side * side;
  return math.max(
    largest * squared / (sum * sum),
    sum * sum / (squared * smallest),
  );
}
