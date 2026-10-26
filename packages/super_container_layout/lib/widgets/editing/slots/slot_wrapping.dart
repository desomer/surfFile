import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../../models/native_component_config.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/registry.dart';
import '../../../models/super_layout_config.dart';
import '../../../theme/appearance.dart';
import '../history/editor_history.dart';
import 'editor_context_menu.dart';

enum EditorSlotWrapper {
  container('Card', 'Card', Icons.crop_square),
  layout('Layout', 'Layout', Icons.dashboard_outlined),
  iterableContent('IterableContent', 'IterableContent', Icons.article_outlined);

  const EditorSlotWrapper(this.label, this.factory, this.icon);

  final String label;
  final String factory;
  final IconData icon;
  String get type => 'registry:$factory';
}

List<EditorSlotWrapAction> slotWrapActions({
  required Registry? registry,
  required bool Function(Set<String>) acceptsTags,
  required Future<void> Function(EditorSlotWrapper) onWrap,
}) => [
  if (registry != null)
    for (final wrapper in EditorSlotWrapper.values)
      if (registry.registry[wrapper.factory] case final component?)
        if (acceptsTags(component.tags))
          EditorSlotWrapAction(
            label: wrapper.label,
            icon: wrapper.icon,
            onSelected: () => onWrap(wrapper),
          ),
];

List<EditorSlotWrapAction> zoneChildrenWrapActions({
  required Registry? registry,
  required bool hasChildren,
  required bool Function(Set<String>) acceptsTags,
  required Future<void> Function() onWrapInCard,
}) {
  if (!hasChildren || registry == null) return const [];
  final card = registry.registry[EditorSlotWrapper.container.factory];
  final layout = registry.registry[EditorSlotWrapper.layout.factory];
  if (card == null || layout == null || !acceptsTags(card.tags)) {
    return const [];
  }
  return [
    EditorSlotWrapAction(
      label: EditorSlotWrapper.container.label,
      icon: EditorSlotWrapper.container.icon,
      onSelected: onWrapInCard,
    ),
  ];
}

/// Wraps all children of a zone or native region into a `Card` containing a
/// `SuperLayout` whose center zone inherits the origin zone's axis and flow.
void wrapZoneChildrenInCard(
  BuildContext context, {
  required Registry registry,
  required List<String> childIds,
  required Map<String, String> slotTypes,
  required Map<String, String> slotLabels,
  required Map<String, Size?> slotPreferredSizes,
  required Map<String, SlotSizeConstraints> slotSizeConstraints,
  required Axis axis,
  ZoneFlowConfig flow = const ZoneFlowConfig(),
  required Set<String> occupiedIds,
  required void Function(String cardId, String cardType) replaceChildren,
}) {
  final cardId = uniqueInstanceId(
    context,
    registry: registry,
    occupiedIds: occupiedIds,
  );
  final layoutId = uniqueInstanceId(
    context,
    registry: registry,
    occupiedIds: {...occupiedIds, cardId},
  );
  final history = EditorHistoryScope.controllerOf(context);
  history?.beginTransaction();
  try {
    registry.nativeComponentController(cardId).value = NativeComponentConfig(
      placements: {
        'child': [layoutId],
      },
      slotTypes: {layoutId: EditorSlotWrapper.layout.type},
      slotLabels: {layoutId: EditorSlotWrapper.layout.label},
    );
    registry.layoutController(layoutId).value = SuperLayoutConfig(
      north: false,
      south: false,
      west: false,
      east: false,
      placements: {
        SuperLayoutZone.center: List.of(childIds),
      },
      slotTypes: {
        for (final id in childIds)
          if (slotTypes[id] case final type?) id: type,
      },
      slotLabels: {
        for (final id in childIds)
          if (slotLabels[id] case final label?) id: label,
      },
      slotPreferredSizes: {
        for (final id in childIds)
          if (slotPreferredSizes.containsKey(id)) id: slotPreferredSizes[id],
      },
      slotSizeConstraints: {
        for (final id in childIds)
          if (slotSizeConstraints[id] case final size?) id: size,
      },
      zoneAxes: {
        if (axis != Axis.vertical) SuperLayoutZone.center: axis,
      },
      zoneFlows: {
        if (!flow.isDefault) SuperLayoutZone.center: flow,
      },
    );
    replaceChildren(cardId, EditorSlotWrapper.container.type);
  } finally {
    history?.commitTransaction();
  }
}

/// A new component placed next to the wrapped child, inside a `Layout`
/// wrapper's center zone.
class WrapSibling {
  const WrapSibling({
    required this.type,
    required this.axis,
    required this.before,
    this.label,
    this.size,
    this.configure,
  });

  final String type;

  /// Axis of the wrapper's center zone.
  final Axis axis;

  /// Whether the sibling precedes the wrapped child.
  final bool before;
  final String? label;
  final SlotSizeConstraints? size;

  /// Writes the sibling settings under its new instance ID.
  final void Function(String instanceId)? configure;
}

/// Generates an instance ID unused by [occupiedIds] and every persisted
/// configuration.
String uniqueInstanceId(
  BuildContext context, {
  required Registry? registry,
  Set<String> occupiedIds = const {},
}) {
  final appearance = AppearanceScope.of(context);
  final used = <String>{
    ...occupiedIds,
    ...appearance.styles.keys,
    ...appearance.layouts.keys,
    ...appearance.components.keys,
    if (registry != null) ...[
      ...registry.superLayoutConfigById.keys,
      ...registry.containerStyleById.keys,
      ...registry.componentConfigById.keys,
      ...registry.nativeComponentConfigById.keys,
      ...registry.scaffoldPageConfigById.keys,
      ...registry.valueConfigById.keys,
      ...registry.actionConfigById.keys,
      ...registry.listConfigById.keys,
    ],
    for (final config in appearance.layouts.values) ...config.placedSlotIds,
    for (final config in appearance.components.values)
      if (config case final NativeComponentConfig native)
        for (final ids in native.placements.values) ...ids
      else if (config case final ScaffoldPageConfig scaffold)
        for (final ids in scaffold.native.placements.values) ...ids,
  };
  for (var attempt = 0; attempt < 1000; attempt++) {
    final candidate = shortid.generate();
    if (!used.contains(candidate)) return candidate;
  }
  throw StateError('Unable to generate a unique instance ID.');
}

/// Creates a real parent and reparents, rather than recreating, the child.
///
/// With [sibling], only allowed for [EditorSlotWrapper.layout], a new
/// component is placed next to the child in the wrapper's center zone.
void wrapSlotInstance(
  BuildContext context, {
  required Registry registry,
  required EditorSlotWrapper wrapper,
  required String id,
  required String type,
  required String label,
  required Set<String> occupiedIds,
  required void Function(String wrapperId, String wrapperType) replace,
  WrapSibling? sibling,
}) {
  assert(sibling == null || wrapper == EditorSlotWrapper.layout);
  final wrapperId = uniqueInstanceId(
    context,
    registry: registry,
    occupiedIds: occupiedIds,
  );
  final siblingId = sibling == null
      ? null
      : uniqueInstanceId(
          context,
          registry: registry,
          occupiedIds: {...occupiedIds, wrapperId},
        );
  final history = EditorHistoryScope.controllerOf(context);
  history?.beginTransaction();
  try {
    switch (wrapper) {
      case EditorSlotWrapper.container:
        registry
            .nativeComponentController(wrapperId)
            .value = NativeComponentConfig(
          placements: {
            'child': [id],
          },
          slotTypes: {id: type},
          slotLabels: {id: label},
        );
      case EditorSlotWrapper.layout:
      case EditorSlotWrapper.iterableContent:
        registry.layoutController(wrapperId).value = SuperLayoutConfig(
          north: false,
          south: false,
          west: false,
          east: false,
          placements: {
            SuperLayoutZone.center: [
              if (sibling != null && sibling.before) siblingId!,
              id,
              if (sibling != null && !sibling.before) siblingId!,
            ],
          },
          slotTypes: {id: type, if (sibling != null) siblingId!: sibling.type},
          slotLabels: {id: label, ?siblingId: ?sibling?.label},
          slotSizeConstraints: {?siblingId: ?sibling?.size},
          zoneAxes: {if (sibling != null) SuperLayoutZone.center: sibling.axis},
        );
        if (sibling != null) sibling.configure?.call(siblingId!);
    }
    replace(wrapperId, wrapper.type);
  } finally {
    history?.commitTransaction();
  }
}
