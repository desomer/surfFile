/// Sélection au lasso (`Ctrl` + clic gauche) en mode édition pour définir le scope Vibe IA.
///
/// Fournit la résolution géométrique ([EditorLassoResolver]) sur les slots montés
/// de [VibeMountedSlotIndex], le contrôleur d'état ([EditorLassoController]) et
/// le peintre visuel ([EditorLassoPainter]) affichant le tracé libre et les cibles détectées.
library;

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/rendering.dart' show RenderSliver;
import 'package:material_ui/material_ui.dart';

import '../../../services/inspection/vibe_mounted_slot_index.dart';
import '../../../theme/appearance_slot.dart';
import '../slots/editor_context_menu.dart'
    show VibeChatScope, VibeChatScopeTarget;
import '../slots/editor_slot.dart' show EditorSlotState;
import 'editor_overlay.dart' show isEditorOverlaySourceOffstage;

/// Élément candidat monté à l'écran avec ses coordonnées dans le viewport et sa hiérarchie.
@immutable
class EditorLassoCandidate {
  /// Crée un candidat pour la résolution géométrique du lasso.
  const EditorLassoCandidate({
    required this.target,
    required this.rect,
    required this.depth,
    this.parentIndex,
    this.isZone = false,
    this.isRoot = false,
  });

  /// Cible Vibe correspondante pour ce composant ou cette zone.
  final VibeChatScopeTarget target;

  /// Rectangle englobant exprimé dans les coordonnées locales du viewport de l'éditeur.
  final Rect rect;

  /// Profondeur hiérarchique parmi les candidats `EditorSlot` montés.
  final int depth;

  /// Indice du candidat parent direct dans la liste ordonnée, ou `null` pour la racine.
  final int? parentIndex;

  /// Indique si ce candidat représente une zone/région interne d'un conteneur.
  final bool isZone;

  /// Indique si ce candidat correspond à la racine `root` de la page.
  final bool isRoot;
}

/// Résultat résolu d'une sélection au lasso contenant les candidats retenus et le [VibeChatScope].
@immutable
class EditorLassoResolution {
  /// Crée un résultat de résolution de lasso.
  const EditorLassoResolution({
    required this.selectedCandidates,
    required this.scope,
  });

  /// Candidats retenus après filtrage hiérarchique, dans l'ordre visuel.
  final List<EditorLassoCandidate> selectedCandidates;

  /// Portée Vibe IA prête à être transmise à `VibeChatDialog.showScoped`.
  final VibeChatScope scope;
}

/// Utilitaires géométriques et de résolution hiérarchique pour la sélection au lasso.
abstract final class EditorLassoResolver {
  /// Longueur minimale (en px) d'un tracé pour être considéré comme intentionnel.
  static const double minStrokeLength = 14.0;

  /// Diagonale minimale (en px) de la boîte englobante d'un tracé valide.
  static const double minStrokeDiagonal = 10.0;

  /// Distance minimale (en px) entre deux points successifs enregistrés au pointeur.
  static const double minSampleDistance = 2.5;

  /// Indique si [points] forme un tracé de lasso suffisamment ample (anti-faux-clics).
  static bool isValidStroke(List<Offset> points) {
    if (points.length < 2) return false;
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      length += (curr - prev).distance;
      if (curr.dx < minX) minX = curr.dx;
      if (curr.dx > maxX) maxX = curr.dx;
      if (curr.dy < minY) minY = curr.dy;
      if (curr.dy > maxY) maxY = curr.dy;
      if (length >= minStrokeLength) return true;
    }
    final diagonal = Offset(maxX - minX, maxY - minY).distance;
    return diagonal >= minStrokeDiagonal;
  }

  /// Teste si [point] est situé à l'intérieur du polygone fermé défini par [polygon]
  /// (algorithme ray-casting pair/impair).
  static bool pointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    var j = polygon.length - 1;
    for (var i = 0; i < polygon.length; i++) {
      final pi = polygon[i];
      final pj = polygon[j];
      final intersects =
          ((pi.dy > point.dy) != (pj.dy > point.dy)) &&
          (point.dx <
              (pj.dx - pi.dx) * (point.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx);
      if (intersects) inside = !inside;
      j = i;
    }
    return inside;
  }

  /// Teste si le segment `[a, b]` coupe ou est contenu dans le rectangle [rect].
  static bool segmentIntersectsRect(Offset a, Offset b, Rect rect) {
    if (rect.isEmpty || !rect.isFinite) return false;
    if (rect.contains(a) || rect.contains(b)) return true;

    final minX = math.min(a.dx, b.dx);
    final maxX = math.max(a.dx, b.dx);
    final minY = math.min(a.dy, b.dy);
    final maxY = math.max(a.dy, b.dy);
    if (maxX < rect.left ||
        minX > rect.right ||
        maxY < rect.top ||
        minY > rect.bottom) {
      return false;
    }

    // Algorithme de Liang-Barsky sur [0, 1].
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    var t0 = 0.0;
    var t1 = 1.0;

    bool clip(double p, double q) {
      if (p == 0) {
        return q >= 0;
      }
      final r = q / p;
      if (p < 0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
      return true;
    }

    return clip(-dx, a.dx - rect.left) &&
        clip(dx, rect.right - a.dx) &&
        clip(-dy, a.dy - rect.top) &&
        clip(dy, rect.bottom - a.dy) &&
        t0 <= t1;
  }

  /// Teste si la polyligne [polyline] (segments tracés) intersecte [rect].
  static bool polylineIntersectsRect(List<Offset> polyline, Rect rect) {
    if (polyline.isEmpty || rect.isEmpty) return false;
    if (polyline.length == 1) return rect.contains(polyline.first);
    for (var i = 1; i < polyline.length; i++) {
      if (segmentIntersectsRect(polyline[i - 1], polyline[i], rect)) {
        return true;
      }
    }
    return false;
  }

  /// Indique si [rect] est entièrement englobé dans le polygone fermé [stroke]
  /// (ses 4 coins et son centre sont à l'intérieur).
  static bool isRectEnclosedByStroke(Rect rect, List<Offset> stroke) {
    if (rect.isEmpty || stroke.length < 3) return false;
    return pointInPolygon(rect.topLeft, stroke) &&
        pointInPolygon(rect.topRight, stroke) &&
        pointInPolygon(rect.bottomLeft, stroke) &&
        pointInPolygon(rect.bottomRight, stroke) &&
        pointInPolygon(rect.center, stroke);
  }

  /// Indique si [rect] correspond au tracé [stroke] selon la règle
  /// `intersects_or_center` (centre contenu dans le polygone ou intersection avec la polyligne).
  static bool rectMatchesStroke(Rect rect, List<Offset> stroke) {
    if (rect.isEmpty || !rect.isFinite || stroke.length < 2) return false;
    if (pointInPolygon(rect.center, stroke)) return true;
    return polylineIntersectsRect(stroke, rect);
  }

  /// Collecte les candidats montés, visibles et éditables à l'intérieur de [contentContext]
  /// en exprimant leurs rectangles dans le repère local de [viewportBox].
  static List<EditorLassoCandidate> collectMountedCandidates({
    required BuildContext contentContext,
    required RenderBox viewportBox,
    VibeMountedSlotIndex? slotIndex,
  }) {
    if (!contentContext.mounted ||
        !viewportBox.attached ||
        !viewportBox.hasSize) {
      return const [];
    }
    final index = slotIndex ?? VibeMountedSlotIndex.instance;
    final entries = index.allEntries;
    if (entries.isEmpty) return const [];

    final records =
        <
          ({
            EditorSlotState state,
            VibeChatScopeTarget target,
            Rect rect,
            bool isZone,
            bool isRoot,
          })
        >[];
    final stateToIndex = <EditorSlotState, int>{};

    for (final entry in entries) {
      final token = entry.token;
      if (token is! EditorSlotState) continue;
      final slotCtx = entry.slotContext();
      if (slotCtx == null || !slotCtx.mounted) continue;
      if (!token.canEdit || token.widget.identity is AppearanceSlot) continue;
      if (!_isDescendantOf(slotCtx, contentContext)) continue;
      if (isEditorOverlaySourceOffstage(slotCtx, stopAt: viewportBox)) {
        continue;
      }

      final rect = _resolveSlotRectInViewport(
        entry: entry,
        slotCtx: slotCtx,
        viewportBox: viewportBox,
      );
      if (rect == null || rect.isEmpty || !rect.isFinite) continue;

      final aiScope = token.aiScope;
      final target = aiScope.primaryTarget;
      final isZone = target.zoneId != null && target.zoneId!.isNotEmpty;
      final isRoot = !isZone && target.canonicalComponentId == 'root';
      stateToIndex[token] = records.length;
      records.add((
        state: token,
        target: target,
        rect: rect,
        isZone: isZone,
        isRoot: isRoot,
      ));
    }

    if (records.isEmpty) return const [];

    final candidates = <EditorLassoCandidate>[];
    for (var i = 0; i < records.length; i++) {
      final rec = records[i];
      int? parentIndex;
      var depth = 0;
      rec.state.context.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is EditorSlotState) {
          final ancestorIndex = stateToIndex[element.state as EditorSlotState];
          if (ancestorIndex != null && ancestorIndex != i) {
            parentIndex ??= ancestorIndex;
            depth++;
          }
        }
        return true;
      });
      candidates.add(
        EditorLassoCandidate(
          target: rec.target,
          rect: rec.rect,
          depth: depth,
          parentIndex: parentIndex,
          isZone: rec.isZone,
          isRoot: rec.isRoot,
        ),
      );
    }
    return candidates;
  }

  /// Résout la sélection de candidats et le [VibeChatScope] correspondant à [strokes].
  ///
  /// Retourne `null` si aucun tracé valide n'est présent ou si aucun candidat n'est touché.
  static EditorLassoResolution? resolveSelection({
    required List<EditorLassoCandidate> candidates,
    required List<List<Offset>> strokes,
  }) {
    if (candidates.isEmpty) return null;
    final validStrokes = <List<Offset>>[
      for (final stroke in strokes)
        if (isValidStroke(stroke)) stroke,
    ];
    if (validStrokes.isEmpty) return null;

    final matchedIndices = <int>{};
    final enclosedIndices = <int>{};

    for (var i = 0; i < candidates.length; i++) {
      final rect = candidates[i].rect;
      var matched = false;
      var enclosed = false;
      for (final stroke in validStrokes) {
        if (rectMatchesStroke(rect, stroke)) {
          matched = true;
        }
        if (isRectEnclosedByStroke(rect, stroke)) {
          enclosed = true;
        }
        if (matched && enclosed) break;
      }
      if (matched) {
        matchedIndices.add(i);
        if (enclosed) enclosedIndices.add(i);
      }
    }

    if (matchedIndices.isEmpty) return null;

    bool hasConsolidatingAncestor(int index) {
      var cursor = candidates[index].parentIndex;
      final visited = <int>{index};
      while (cursor != null && visited.add(cursor)) {
        final ancestor = candidates[cursor];
        if (matchedIndices.contains(cursor) &&
            enclosedIndices.contains(cursor) &&
            !ancestor.isZone &&
            !ancestor.isRoot) {
          return true;
        }
        cursor = ancestor.parentIndex;
      }
      return false;
    }

    // 1. Retient les candidats non absorbés par un conteneur parent entièrement entouré.
    final unabsorbedIndices = <int>{
      for (final index in matchedIndices)
        if (!hasConsolidatingAncestor(index)) index,
    };

    // 2. Retire les ancêtres dont au moins un descendant est déjà retenu.
    final ancestorsWithKeptChild = <int>{};
    for (final index in unabsorbedIndices) {
      var cursor = candidates[index].parentIndex;
      final visited = <int>{index};
      while (cursor != null && visited.add(cursor)) {
        ancestorsWithKeptChild.add(cursor);
        cursor = candidates[cursor].parentIndex;
      }
    }

    final keptIndices = <int>[
      for (final index in unabsorbedIndices)
        if (!ancestorsWithKeptChild.contains(index)) index,
    ];
    if (keptIndices.isEmpty) return null;

    keptIndices.sort((a, b) {
      final ra = candidates[a].rect;
      final rb = candidates[b].rect;
      final dy = ra.top.compareTo(rb.top);
      if (dy.abs() > 1e-3 && (ra.top - rb.top).abs() > 8.0) return dy;
      final dx = ra.left.compareTo(rb.left);
      if (dx != 0) return dx;
      return candidates[b].depth.compareTo(candidates[a].depth);
    });

    final selected = <EditorLassoCandidate>[
      for (final index in keptIndices) candidates[index],
    ];
    final targets = <VibeChatScopeTarget>[
      for (final candidate in selected) candidate.target,
    ];
    return EditorLassoResolution(
      selectedCandidates: List<EditorLassoCandidate>.unmodifiable(selected),
      scope: VibeChatScope.fromTargets(targets),
    );
  }

  static bool _isDescendantOf(BuildContext candidate, BuildContext ancestor) {
    if (identical(candidate, ancestor)) return true;
    var found = false;
    candidate.visitAncestorElements((element) {
      if (identical(element, ancestor)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  static Rect? _resolveSlotRectInViewport({
    required VibeMountedSlotEntry entry,
    required BuildContext slotCtx,
    required RenderBox viewportBox,
  }) {
    final contentObj = entry.contentKey.currentContext?.findRenderObject();
    final targetObj =
        (contentObj != null && contentObj.attached)
            ? contentObj
            : slotCtx.findRenderObject();
    if (targetObj == null || !targetObj.attached) return null;
    if (targetObj is RenderBox) {
      if (!targetObj.hasSize || !targetObj.size.isFinite) return null;
      final transform = targetObj.getTransformTo(viewportBox);
      if (transform.isZero()) return null;
      final rect = MatrixUtils.transformRect(
        transform,
        Offset.zero & targetObj.size,
      );
      return rect.isFinite ? rect : null;
    }
    if (targetObj is RenderSliver) {
      final geom = targetObj.geometry;
      if (geom == null || geom.paintExtent <= 0) return null;
      final size = targetObj.constraints.axis == Axis.vertical
          ? Size(targetObj.constraints.crossAxisExtent, geom.paintExtent)
          : Size(geom.paintExtent, targetObj.constraints.crossAxisExtent);
      if (size.isEmpty || !size.isFinite) return null;
      final transform = targetObj.getTransformTo(viewportBox);
      if (transform.isZero()) return null;
      final rect = MatrixUtils.transformRect(transform, Offset.zero & size);
      return rect.isFinite ? rect : null;
    }
    return null;
  }
}

/// Contrôleur d'état du mode lasso en mode édition.
class EditorLassoController extends ChangeNotifier {
  final List<List<Offset>> _completedStrokes = <List<Offset>>[];
  List<Offset>? _activeStroke;
  List<EditorLassoCandidate> _candidates = const [];
  EditorLassoResolution? _resolution;
  bool _ctrlArmed = false;

  /// Indique si la touche `Ctrl` arme actuellement l'interception du lasso.
  bool get isCtrlArmed => _ctrlArmed;

  /// Indique si un tracé est en cours de dessin au bouton gauche de la souris.
  bool get isDrawing => _activeStroke != null;

  /// Indique si au moins un tracé (actif ou validé) est présent à l'écran.
  bool get hasAnyStroke =>
      _completedStrokes.isNotEmpty || (_activeStroke?.isNotEmpty ?? false);

  /// Indique si au moins un tracé valide a été tracé durant cette session `Ctrl`.
  bool get hasValidStrokes {
    for (final stroke in _completedStrokes) {
      if (EditorLassoResolver.isValidStroke(stroke)) return true;
    }
    final active = _activeStroke;
    return active != null && EditorLassoResolver.isValidStroke(active);
  }

  /// Tracés déjà terminés pendant que `Ctrl` est maintenu.
  List<List<Offset>> get completedStrokes =>
      List<List<Offset>>.unmodifiable(_completedStrokes);

  /// Tracé actuellement en cours de dessin, ou `null`.
  List<Offset>? get activeStroke =>
      _activeStroke == null ? null : List<Offset>.unmodifiable(_activeStroke!);

  /// Résolution courante des composants ciblés en direct, ou `null`.
  EditorLassoResolution? get resolution => _resolution;

  /// Candidats actuellement surlignés par le lasso.
  List<EditorLassoCandidate> get highlightedCandidates =>
      _resolution?.selectedCandidates ?? const <EditorLassoCandidate>[];

  /// Met à jour l'état d'armement par `Ctrl`.
  void setCtrlArmed(bool armed) {
    if (_ctrlArmed == armed) return;
    _ctrlArmed = armed;
    notifyListeners();
  }

  /// Démarre un nouveau tracé à [position] avec le jeu courant de [candidates].
  void startStroke(
    Offset position, {
    required List<EditorLassoCandidate> candidates,
  }) {
    _candidates = candidates;
    _activeStroke = <Offset>[position];
    _recomputeResolution();
    notifyListeners();
  }

  /// Ajoute un point [position] au tracé actif s'il s'écarte suffisamment du précédent.
  void appendPoint(Offset position) {
    final active = _activeStroke;
    if (active == null) return;
    if (active.isNotEmpty &&
        (position - active.last).distance <
            EditorLassoResolver.minSampleDistance) {
      return;
    }
    active.add(position);
    _recomputeResolution();
    notifyListeners();
  }

  /// Termine le tracé actif et le conserve s'il est valide.
  void finishActiveStroke() {
    final active = _activeStroke;
    if (active == null) return;
    _activeStroke = null;
    if (EditorLassoResolver.isValidStroke(active)) {
      _completedStrokes.add(List<Offset>.unmodifiable(active));
    }
    _recomputeResolution();
    notifyListeners();
  }

  /// Termine la session `Ctrl`, résout le [VibeChatScope] éventuel et réinitialise le tracé.
  VibeChatScope? commitAndReset() {
    final active = _activeStroke;
    if (active != null) {
      _activeStroke = null;
      if (EditorLassoResolver.isValidStroke(active)) {
        _completedStrokes.add(List<Offset>.unmodifiable(active));
      }
    }
    _recomputeResolution();
    final scope = _resolution?.scope;
    _completedStrokes.clear();
    _candidates = const [];
    _resolution = null;
    _ctrlArmed = false;
    notifyListeners();
    return scope;
  }

  /// Annule immédiatement la session lasso en cours sans produire de scope.
  void cancel() {
    if (!hasAnyStroke && !_ctrlArmed && _resolution == null) return;
    _activeStroke = null;
    _completedStrokes.clear();
    _candidates = const [];
    _resolution = null;
    _ctrlArmed = false;
    notifyListeners();
  }

  void _recomputeResolution() {
    final allStrokes = <List<Offset>>[
      ..._completedStrokes,
      ?_activeStroke,
    ];
    _resolution = EditorLassoResolver.resolveSelection(
      candidates: _candidates,
      strokes: allStrokes,
    );
  }
}

/// Peintre rendant en surimpression les tracés du lasso et les cibles détectées en direct.
class EditorLassoPainter extends CustomPainter {
  /// Crée un peintre de lasso lié à [controller] et à la couleur d'[accent].
  EditorLassoPainter({
    required this.controller,
    required this.accent,
  }) : super(repaint: controller);

  /// Contrôleur fournissant les tracés et cibles surlignées.
  final EditorLassoController controller;

  /// Couleur d'accent utilisée pour le tracé et les contours détectés.
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.hasAnyStroke) return;

    final highlightFill = Paint()
      ..color = accent.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final highlightBorder = Paint()
      ..color = accent.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final candidate in controller.highlightedCandidates) {
      final rrect = RRect.fromRectAndRadius(
        candidate.rect,
        const Radius.circular(4),
      );
      canvas.drawRRect(rrect, highlightFill);
      canvas.drawRRect(rrect, highlightBorder);
    }

    final polygonFill = Paint()
      ..color = accent.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final glowPaint = Paint()
      ..color = accent.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final strokePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final closingDashPaint = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (final stroke in controller.completedStrokes) {
      _paintStroke(
        canvas,
        stroke,
        closed: true,
        polygonFill: polygonFill,
        glowPaint: glowPaint,
        strokePaint: strokePaint,
        closingDashPaint: closingDashPaint,
      );
    }

    if (controller.activeStroke case final active?) {
      _paintStroke(
        canvas,
        active,
        closed: false,
        polygonFill: polygonFill,
        glowPaint: glowPaint,
        strokePaint: strokePaint,
        closingDashPaint: closingDashPaint,
      );
    }
  }

  void _paintStroke(
    Canvas canvas,
    List<Offset> points, {
    required bool closed,
    required Paint polygonFill,
    required Paint glowPaint,
    required Paint strokePaint,
    required Paint closingDashPaint,
  }) {
    if (points.isEmpty) return;
    if (points.length >= 3) {
      final closedPath = Path()..addPolygon(points, true);
      canvas.drawPath(closedPath, polygonFill);
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    if (closed && points.length >= 3) {
      path.close();
    }
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, strokePaint);

    if (!closed && points.length >= 3) {
      final closingPath = Path()
        ..moveTo(points.last.dx, points.last.dy)
        ..lineTo(points.first.dx, points.first.dy);
      for (final PathMetric metric in closingPath.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 10.0) {
          final end = (d + 5.5).clamp(0.0, metric.length);
          canvas.drawPath(metric.extractPath(d, end), closingDashPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(EditorLassoPainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) ||
      accent != oldDelegate.accent;
}
