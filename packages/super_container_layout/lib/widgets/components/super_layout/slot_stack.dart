/// Assemblage des slots visibles, de leurs actions et du flux de leur zone.
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/super_layout_config.dart';
import '../../editing/addition/insertion_plan.dart';
import '../../editing/dialogs/editor_tabbed_wizard.dart';
import '../../editing/slots/editor_slot.dart';
import 'labeled_slot.dart';
import 'slot_core.dart';
import 'slot_drag.dart';
import 'slot_render_layout.dart';
import 'zone_scrollable_viewport.dart';

/// Aligne les [slots] visibles d'une zone selon [axis].
class SlotStack extends StatelessWidget {
  /// Crée l'assemblage des slots et actions d'une zone.
  const SlotStack({
    required this.slots,
    this.axis = Axis.vertical,
    this.flow = const ZoneFlowConfig(),
    this.expand = true,
    this.stretch = true,
    this.showLabels = false,
    this.zoneLabel,
    this.mover,
    this.emphasis,
    this.preferredSizes = const {},
    this.sizeConstraints = const {},
    this.layoutSize = Size.zero,
    this.onEditPreferredSize,
    this.dimensionDelegateForSlot,
    this.onRemoveSlot,
    this.wrapActionsForSlot,
    this.insertionForSlot,
    this.onSelectSlot,
    this.onTapSlot,
    this.onSelectContent,
    this.canSelectSlot,
    this.selectedSlotId,
    this.onResizeSlot,
    this.focusKeys,
    this.regionSlotIds,
    super.key,
  });

  /// Slots de la zone, dans leur ordre d'affichage.
  final List<SlotImplementation> slots;

  /// Identifiants de slots de la région, si distincts de [slots].
  final List<String>? regionSlotIds;

  /// Clés de focus conservant les instances des slots.
  final Map<String, GlobalKey>? focusKeys;

  /// Axe principal du flux.
  final Axis axis;

  /// Paramètres de flux et de défilement de la zone.
  final ZoneFlowConfig flow;

  /// Indique si les slots flexibles se partagent l'espace principal.
  final bool expand;

  /// Indique si les slots s'étirent sur l'axe transversal.
  final bool stretch;

  /// Affiche le libellé de chaque slot en mode édition.
  final bool showLabels;

  /// Nom de la zone, ajouté aux étiquettes avec la position du slot.
  final String? zoneLabel;

  /// Permet de déplacer les slots dans leur zone.
  final SlotMover? mover;

  /// Mise en avant partagée des étiquettes de la disposition.
  final LabelEmphasis? emphasis;

  /// Tailles préférées historiques par identifiant de slot.
  final Map<String, Size?> preferredSizes;

  /// Contraintes de taille par identifiant de slot.
  final Map<String, SlotSizeConstraints> sizeConstraints;

  /// Taille du layout utilisée par les contraintes en pourcentage.
  final Size layoutSize;

  /// Ouvre l'éditeur de taille préférée d'un slot.
  final Future<void> Function(SlotImplementation)? onEditPreferredSize;

  /// Construit le délégué de dimensionnement d'un slot.
  final EditorDimensionDelegate Function(SlotImplementation)?
  dimensionDelegateForSlot;

  /// Retire un slot de la zone.
  final Future<void> Function(SlotImplementation)? onRemoveSlot;

  /// Actions d'enveloppement disponibles pour un slot.
  final List<EditorSlotWrapAction> Function(SlotImplementation)?
  wrapActionsForSlot;

  /// Plan d'insertion contextuelle autour d'un slot.
  final EditorSlotInsertion? Function(SlotImplementation)? insertionForSlot;

  /// Sélectionne un slot par son étiquette.
  final ValueChanged<SlotImplementation>? onSelectSlot;

  /// Signale le clic de pointeur sur le contenu d'un slot.
  final void Function(SlotImplementation, PointerDownEvent)? onTapSlot;

  /// Sélectionne le contenu d'un slot.
  final ValueChanged<SlotImplementation>? onSelectContent;

  /// Détermine si le contenu d'un slot peut être sélectionné.
  final bool Function(SlotImplementation)? canSelectSlot;

  /// Identifiant du slot sélectionné.
  final String? selectedSlotId;

  /// Applique les contraintes modifiées par redimensionnement.
  final void Function(SlotImplementation, SlotSizeConstraints)? onResizeSlot;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final slot in slots)
        if (slot.visible) slot,
    ];
    final ids = regionSlotIds ?? [for (final slot in visible) slot.id];
    final padding = flow.contentPadding;
    Widget flex = SlotFlex(
      axis: axis,
      expand: expand,
      stretch: stretch,
      scrollable: flow.scrollable,
      expandSlots: flow.expandSlots,
      mainAxisAlignment: flow.mainAxisAlignment,
      crossAxisAlignment: flow.crossAxisAlignment,
      spacing: flow.spacing,
      preferredSizes: [
        for (final slot in visible)
          (sizeConstraints[slot.id]?.hasSizeConstraints ?? false)
              ? null
              : preferredSizes.containsKey(slot.id)
              ? preferredSizes[slot.id]
              : slot.preferredSize,
      ],
      sizeConstraints: [for (final slot in visible) sizeConstraints[slot.id]],
      layoutSize: layoutSize,
      sizing: [for (final slot in visible) slot.sizing],
      children: [
        for (final (index, slot) in visible.indexed)
          () {
            final idx = regionSlotIds != null ? ids.indexOf(slot.id) : index;
            return _labeled(
              context,
              slot,
              idx >= 0 ? idx : index,
              ids.length,
              ids,
            );
          }(),
      ],
    );
    if (flow.scrollable) {
      flex = ZoneScrollableViewport(
        axis: axis,
        showScrollbar: flow.showScrollbar,
        scrollbarStyle: flow.scrollbarStyle,
        padding: padding,
        child: flex,
      );
    } else if (padding != EdgeInsets.zero) {
      flex = Padding(padding: padding, child: flex);
    }
    return flex;
  }

  bool _slotFitsMain(SlotImplementation slot, {required bool parentFitMain}) {
    final constraints = sizeConstraints[slot.id];
    final hasExplicitMain = (constraints?.hasSizeConstraints ?? false)
        ? (axis == Axis.horizontal
              ? constraints!.preferredWidth != null
              : constraints!.preferredHeight != null)
        : (preferredSizes.containsKey(slot.id)
              ? preferredSizes[slot.id] != null
              : slot.preferredSize != null);
    if (hasExplicitMain) return false;
    if (parentFitMain || flow.scrollable) return true;
    final fitOverride = constraints?.fitContent;
    if (fitOverride != null) return fitOverride;
    return !flow.expandSlots ||
        flow.mainAxisAlignment != MainAxisAlignment.start;
  }

  bool _slotFitsCross(SlotImplementation slot, {required bool parentFitCross}) {
    final constraints = sizeConstraints[slot.id];
    final hasExplicitCross = (constraints?.hasSizeConstraints ?? false)
        ? (axis == Axis.horizontal
              ? constraints!.preferredHeight != null
              : constraints!.preferredWidth != null)
        : (preferredSizes.containsKey(slot.id)
              ? preferredSizes[slot.id] != null
              : slot.preferredSize != null);
    if (hasExplicitCross) return false;
    return parentFitCross ||
        flow.crossAxisAlignment != CrossAxisAlignment.stretch;
  }

  Widget _labeled(
    BuildContext context,
    SlotImplementation slot,
    int index,
    int count,
    List<String> ids,
  ) {
    final parentFit = SlotContentFitScope.maybeOf(context);
    final parentFitMain =
        !expand ||
        (axis == Axis.horizontal
            ? (parentFit?.fitWidth ?? false)
            : (parentFit?.fitHeight ?? false));
    final parentFitCross =
        !stretch ||
        (axis == Axis.horizontal
            ? (parentFit?.fitHeight ?? false)
            : (parentFit?.fitWidth ?? false));
    final fitMain = _slotFitsMain(slot, parentFitMain: parentFitMain);
    final fitCross = _slotFitsCross(slot, parentFitCross: parentFitCross);
    final fitWidth = axis == Axis.horizontal ? fitMain : fitCross;
    final fitHeight = axis == Axis.vertical ? fitMain : fitCross;
    final selectable =
        onSelectContent != null && (canSelectSlot?.call(slot) ?? true);
    final actionLabel = 'Taille et marge préférées : ${slot.label}';
    final constraints = sizeConstraints[slot.id];
    final preferredSize = preferredSizes.containsKey(slot.id)
        ? preferredSizes[slot.id]
        : slot.preferredSize;
    return EditorSlotAction(
      key: ValueKey('slot-item-${slot.id}'),
      label: actionLabel,
      tooltip: formatSlotSizeTooltip(
        title: actionLabel,
        constraints: constraints,
        preferredSize: preferredSize,
      ),
      inline: true,
      fixedWidth: hasFixedSlotWidth(
        constraints: constraints,
        preferredSize: preferredSize,
      ),
      fixedHeight: hasFixedSlotHeight(
        constraints: constraints,
        preferredSize: preferredSize,
      ),
      enabled:
          onEditPreferredSize != null ||
          onRemoveSlot != null ||
          wrapActionsForSlot != null ||
          insertionForSlot != null ||
          selectable,
      showEdit: onEditPreferredSize != null,
      onSelect: selectable ? () => onSelectContent!(slot) : null,
      onEdit: () async => onEditPreferredSize?.call(slot),
      onRemove: onRemoveSlot != null
          ? () async => onRemoveSlot?.call(slot)
          : null,
      wrapActions: wrapActionsForSlot?.call(slot) ?? const [],
      insertion: insertionForSlot?.call(slot),
      dimensionDelegateBuilder: dimensionDelegateForSlot == null
          ? null
          : () => dimensionDelegateForSlot!(slot),
      child: KeyedSubtree(
        key: focusKeys?.putIfAbsent(slot.id, GlobalKey.new),
        child: SlotContentFitScope(
          fitWidth: fitWidth,
          fitHeight: fitHeight,
          child: LabeledSlot(
            slot: slot,
            axis: axis,
            showLabel: showLabels,
            mover: mover,
            emphasis: emphasis,
            zoneLabel: zoneLabel,
            ids: ids,
            onSelect: onSelectSlot == null ? null : () => onSelectSlot!(slot),
            onTapContent: onTapSlot == null
                ? null
                : (event) => onTapSlot!(slot, event),
            onSelectContent: selectable ? () => onSelectContent!(slot) : null,
            selected: selectedSlotId == slot.id,
            onResize: onResizeSlot == null
                ? null
                : (dimensions) => onResizeSlot!(slot, dimensions),
            sizeConstraints: sizeConstraints[slot.id],
            padding:
                sizeConstraints[slot.id]?.contentPadding ?? EdgeInsets.zero,
            caption: zoneLabel == null
                ? slot.label
                : '${slot.label} · $zoneLabel ${index + 1}/$count',
          ),
        ),
      ),
    );
  }
}
