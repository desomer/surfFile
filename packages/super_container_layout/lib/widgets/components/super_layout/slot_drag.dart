/// Étiquettes, indications et cibles de glisser-déposer des slots.
library;

import 'package:flutter/foundation.dart'
    show
        ValueListenable,
        ValueNotifier,
        defaultTargetPlatform,
        TargetPlatform,
        kIsWeb;
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, RenderStack, StackParentData;
import 'package:material_ui/material_ui.dart';

import '../../editing/overlay/editor_overlay.dart';

/// Curseur utilisé sur les étiquettes déplaçables de l'éditeur.
MouseCursor editorDragCursor({required bool dragging}) {
  // Flutter's Windows cursor map does not implement grab or grabbing.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    return dragging ? SystemMouseCursors.move : SystemMouseCursors.click;
  }
  return dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab;
}

/// Étiquette partagée par les zones et la grille en mode édition.
class ComponentDragLabel extends StatelessWidget {
  /// Crée une étiquette pouvant refléter son état de survol ou de glissement.
  const ComponentDragLabel({
    required this.child,
    this.opacity = 0.5,
    this.highlighted = false,
    this.draggable = false,
    this.dragging = false,
    super.key,
  });

  /// Contenu textuel ou widget de l'étiquette.
  final Widget child;

  /// Opacité du fond non surligné.
  final double opacity;

  /// Indique si l'étiquette est mise en avant.
  final bool highlighted;

  /// Indique si elle peut être déplacée.
  final bool draggable;

  /// Indique si un glissement est en cours.
  final bool dragging;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: draggable
        ? editorDragCursor(dragging: dragging)
        : MouseCursor.defer,
    child: Material(
      color: highlighted
          ? Theme.of(context).colorScheme.tertiary
          : Theme.of(context).colorScheme.tertiaryContainer
                .withValues(alpha: opacity),
      textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 10,
        color: highlighted ? Theme.of(context).colorScheme.onTertiary : null,
      ),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (draggable && constraints.maxWidth >= 16) ...[
                Icon(
                  Icons.drag_indicator,
                  size: 12,
                  color: highlighted
                      ? Theme.of(context).colorScheme.onTertiary
                      : null,
                ),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: DefaultTextStyle.merge(
                  overflow: TextOverflow.ellipsis,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Données transportées lors du déplacement d'un slot.
class SlotDragData {
  /// Crée les données du slot [id] en cours de glissement.
  const SlotDragData({
    required this.id,
    required this.owner,
    required this.hint,
  });

  /// Identifiant du slot déplacé.
  final String id;

  /// Propriétaire qui accepte le dépôt.
  final Object owner;

  /// Indication de position actualisée par la cible survolée.
  final ValueNotifier<SlotDropHint?> hint;
}

/// Zone et rang qu'aurait un slot déposé sur la cible survolée.
class SlotDropHint {
  /// Crée une indication de destination.
  const SlotDropHint({
    required this.zoneLabel,
    required this.position,
    required this.total,
  });

  /// Nom de la zone de destination.
  final String zoneLabel;

  /// Position du slot après dépôt, indexée à partir de un.
  final int position;

  /// Nombre de slots dans la zone après dépôt.
  final int total;

  /// Texte décrivant la position envisagée.
  String get caption => '$zoneLabel $position/$total';

  /// Calcule la position d'un slot déposé avant ou après un autre slot.
  static SlotDropHint? at({
    required String? zoneLabel,
    required List<String> ids,
    required String movedId,
    String? beforeId,
    String? afterId,
  }) {
    if (zoneLabel == null) return null;
    final others = [
      for (final id in ids)
        if (id != movedId) id,
    ];
    var at = others.length;
    if (beforeId != null) {
      final index = others.indexOf(beforeId);
      if (index >= 0) at = index;
    } else if (afterId != null) {
      final index = others.indexOf(afterId);
      if (index >= 0) at = index + 1;
    }
    return SlotDropHint(
      zoneLabel: zoneLabel,
      position: at + 1,
      total: others.length + 1,
    );
  }
}

/// Mise en avant des étiquettes d'une disposition et des zones survolées.
class LabelEmphasis {
  /// Crée une mise en avant liée à [scope].
  const LabelEmphasis({
    required this.scopes,
    required this.scope,
    required this.onHover,
  });

  /// Zones dont une étiquette est survolée ou glissée.
  final ValueListenable<Set<Object>> scopes;

  /// Zone de l'étiquette qui utilise cette mise en avant.
  final Object scope;

  /// Signale le survol de l'étiquette [source] dans [scope].
  final void Function(Object scope, Object source, bool hovered) onHover;

  /// Signale le survol ou la fin du survol de l'étiquette [source].
  void report(Object source, bool hovered) => onHover(scope, source, hovered);
}

/// Agrandit son enfant au survol sans modifier sa géométrie.
class EmphasizedLabel extends StatelessWidget {
  /// Crée une étiquette réagissant à [emphasis].
  const EmphasizedLabel({
    required this.emphasis,
    required this.child,
    this.alignment = Alignment.center,
    this.allScopes = false,
    super.key,
  });

  /// Facteur d'agrandissement appliqué au survol.
  static const scale = 1.3;

  /// Source de l'état de mise en avant, absente si l'effet est désactivé.
  final LabelEmphasis? emphasis;

  /// Alignement de l'agrandissement.
  final Alignment alignment;

  /// Indique si tout survol d'une disposition active l'effet.
  final bool allScopes;

  /// Contenu affiché.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final emphasis = this.emphasis;
    if (emphasis == null) return child;
    return ValueListenableBuilder<Set<Object>>(
      valueListenable: emphasis.scopes,
      child: child,
      builder: (context, scopes, child) => AnimatedScale(
        scale: (allScopes ? scopes.isNotEmpty : scopes.contains(emphasis.scope))
            ? scale
            : 1,
        alignment: alignment,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}

/// Déplacement des slots d'une zone vers un autre rang.
class SlotMover {
  /// Crée un déplacement appartenant à [owner].
  const SlotMover({required this.owner, required this.onMove, this.canMove});

  /// Identité du propriétaire des slots déplaçables.
  final Object owner;

  /// Filtre optionnel des identifiants déplaçables.
  final bool Function(String id)? canMove;

  /// Range [id] juste avant [beforeId] ou juste après [afterId].
  final void Function(String id, {String? beforeId, String? afterId}) onMove;
}

/// `Stack` dont la cible de dépôt optionnelle (dernier enfant lorsque
/// [hasDropTarget] vaut `true`) est testée en collision **après** le contenu
/// et les superpositions afin de préserver la priorité aux cibles imbriquées
/// sans jamais reparenter l'enfant principal (indice `0`).
class SlotDropTargetStack extends Stack {
  /// Crée une pile de zone ou de slot à profondeur constante.
  const SlotDropTargetStack({
    super.key,
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
    this.hasDropTarget = false,
    super.children,
  });

  /// Indique si le dernier enfant de [children] est la cible de dépôt de fond.
  final bool hasDropTarget;

  @override
  RenderStack createRenderObject(BuildContext context) =>
      _RenderSlotDropTargetStack(
        alignment: alignment,
        textDirection: textDirection ?? Directionality.maybeOf(context),
        fit: fit,
        clipBehavior: clipBehavior,
        hasDropTarget: hasDropTarget,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderStack renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _RenderSlotDropTargetStack).hasDropTarget = hasDropTarget;
  }
}

class _RenderSlotDropTargetStack extends RenderStack {
  _RenderSlotDropTargetStack({
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
    required this.hasDropTarget,
  });

  bool hasDropTarget;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!hasDropTarget || lastChild == null) {
      return super.hitTestChildren(result, position: position);
    }
    final dropChild = lastChild!;
    var hit = false;
    RenderBox? child = childBefore(dropChild);
    while (child != null) {
      final childParentData = child.parentData! as StackParentData;
      final isHit = result.addWithPaintOffset(
        offset: childParentData.offset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) {
          assert(transformed == position - childParentData.offset);
          return child!.hitTest(result, position: transformed);
        },
      );
      if (isHit) {
        hit = true;
        break;
      }
      child = childParentData.previousSibling;
    }
    final dropParentData = dropChild.parentData! as StackParentData;
    result.addWithPaintOffset(
      offset: dropParentData.offset,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) {
        assert(transformed == position - dropParentData.offset);
        return dropChild.hitTest(result, position: transformed);
      },
    );
    return hit;
  }
}

/// Cible de dépôt dans l'espace libre d'une zone, après ses slots.
class SlotZoneTarget extends StatelessWidget {
  /// Crée une cible de dépôt pour une zone.
  const SlotZoneTarget({
    required this.owner,
    required this.zoneLabel,
    required this.ids,
    required this.onMove,
    required this.canMove,
    this.enabled = true,
    this.alignment = AlignmentDirectional.topStart,
    this.child,
    this.overlays = const [],
    super.key,
  });

  /// Identité du propriétaire qui accepte le dépôt.
  final Object owner;

  /// Filtre des identifiants que la cible peut déplacer.
  final bool Function(String id) canMove;

  /// Nom de la zone de destination.
  final String zoneLabel;

  /// Identifiants des slots déjà présents, dans l'ordre.
  final List<String> ids;

  /// Déplace le slot accepté dans la zone.
  final ValueChanged<String> onMove;

  /// Active ou désactive la cible de dépôt sans modifier la profondeur de [child].
  final bool enabled;

  /// Alignement du contenu et des superpositions.
  final AlignmentGeometry alignment;

  /// Contenu de la zone, s'il existe.
  final Widget? child;

  /// Widgets affichés au-dessus du contenu de la zone.
  final List<Widget> overlays;

  Widget _buildDropOverlay(ColorScheme colors) => DragTarget<SlotDragData>(
    onWillAcceptWithDetails: (details) {
      final accepts =
          identical(details.data.owner, owner) && canMove(details.data.id);
      if (accepts) {
        details.data.hint.value = SlotDropHint.at(
          zoneLabel: zoneLabel,
          ids: ids,
          movedId: details.data.id,
        );
      }
      return accepts;
    },
    onLeave: (data) => data?.hint.value = null,
    onAcceptWithDetails: (details) => onMove(details.data.id),
    builder: (context, candidates, _) {
      if (candidates.isEmpty) return const SizedBox.expand();
      return EditorOverlay(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.tertiary.withValues(alpha: .15),
              border: Border.all(color: colors.tertiary, width: 2),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (child == null && overlays.isEmpty) {
      return enabled ? _buildDropOverlay(colors) : const SizedBox.expand();
    }
    return SlotDropTargetStack(
      alignment: alignment,
      hasDropTarget: enabled,
      children: [
        ?child,
        if (enabled) ...overlays,
        if (enabled) Positioned.fill(child: _buildDropOverlay(colors)),
      ],
    );
  }
}
