/// Façade historique des contrats, du rendu et des interactions de slots.
library;

export '../../editing/slots/editor_selection_region.dart'
    show BoxPointerRegion, SliverPointerRegion, SliverSlotScope;
export 'slot_core.dart'
    show
        SliverCapableWidget,
        isSliverWidget,
        SlotSizing,
        SlotContentFitScope,
        SlotImplementation,
        BuilderSlot,
        InstanceSlot;
export 'slot_drag.dart'
    show
        editorDragCursor,
        ComponentDragLabel,
        SlotDragData,
        SlotDropHint,
        LabelEmphasis,
        EmphasizedLabel,
        SlotMover,
        SlotDropTargetStack,
        SlotZoneTarget;
export 'slot_stack.dart' show SlotStack;
export 'zone_scrollable_viewport.dart'
    show ZoneScrollableViewport, ScrollViewportHost;
