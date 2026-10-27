part of 'super_layout.dart';

typedef SlotAddedCallback = SuperLayoutConfig Function(SlotAddition addition);

/// An editor addition, before its configuration is committed.
class SlotAddition {
  const SlotAddition({
    required this.slotId,
    required this.component,
    required this.zone,
    required this.contentZone,
    required this.config,
    required this.existingSlots,
  });

  final String slotId;
  final SlotImplementation component;
  final SuperLayoutZone zone;
  final SuperLayoutZone contentZone;

  /// Configuration already containing the newly placed instance.
  final SuperLayoutConfig config;
  final List<SlotImplementation> existingSlots;
}

/// Disposition en neuf zones (Nord, Sud, Est, Ouest, coins et Centre) dont la
/// structure s'édite par clic droit via un [EditorSlot].
///
/// Les zones sont les récepteurs de [slots] : chaque [SlotImplementation] est
/// rangé dans une zone par [SuperLayoutConfig.placements] (ids ordonnés, empilés
/// de haut en bas). Une zone sans slot visible montre un repère portant son
/// nom. Le widget occupe tout l'espace disponible.
///
/// Un côté en taille automatique ([SuperLayoutConfig.autoSides]) prend la
/// taille de son contenu ; le centre reçoit le reste.
class SuperLayout extends StatefulWidget {
  const SuperLayout({
    this.id,
    this.slots = const [],
    this.config = const SuperLayoutConfig(),
    this.onChanged,
    this.onSlotAdded = defaultSlotAddition,
    this.label = 'Layout',
    this.name,
    this.editable = true,
    this.showZoneNames = true,
    this.shrinkWrap = false,
    this.menuIcon,
    this.zoneLabels = const {},
    this.zoneTagFilters = const {},
    super.key,
  });

  final List<SlotImplementation> slots;
  final SuperLayoutConfig config;

  /// Measures the layout from its contents instead of filling its parent.
  final bool shrinkWrap;
  final ValueChanged<SuperLayoutConfig>? onChanged;

  /// Customizes an editor addition atomically with placement and persistence.
  /// Return [SlotAddition.config] to keep its sizes unchanged.
  final SlotAddedCallback onSlotAdded;

  /// Reuses the first sibling preference, or sets 20% of the whole layout.
  /// The other dimension and existing bounds are preserved.
  static SuperLayoutConfig defaultSlotAddition(SlotAddition addition) {
    final zone = addition.zone;
    if (!zone.isSide) return addition.config;
    if (addition.component.tags
        .intersection(const {'action', 'button', 'text', 'input'})
        .isNotEmpty) {
      return addition.config;
    }
    final width = zone == SuperLayoutZone.west || zone == SuperLayoutZone.east;
    final config = addition.config;
    final saved = config.slotSizeConstraints[addition.slotId];
    final hasPercentBounds = [
      saved?.minWidth,
      saved?.minHeight,
      saved?.maxWidth,
      saved?.maxHeight,
      width ? saved?.preferredHeight : saved?.preferredWidth,
    ].any((dimension) => dimension?.unit == SlotSizeUnit.percent);
    SlotDimension? dimension;
    var basis = SlotPercentBasis.zone;
    for (final slot in addition.existingSlots) {
      final constraints = config.slotSizeConstraints[slot.id];
      if (constraints != null && constraints.hasSizeConstraints) {
        dimension = width
            ? constraints.preferredWidth
            : constraints.preferredHeight;
        // A slot has one percentage basis for all its dimensions.
        if (dimension?.unit == SlotSizeUnit.percent &&
            hasPercentBounds &&
            constraints.percentBasis != saved?.percentBasis) {
          dimension = null;
          continue;
        }
        basis = constraints.percentBasis;
      } else {
        final size = config.slotPreferredSizes.containsKey(slot.id)
            ? config.slotPreferredSizes[slot.id]
            : slot.preferredSize;
        if (size != null) {
          dimension = SlotDimension(
            width ? size.width : size.height,
            SlotSizeUnit.pixels,
          );
        }
      }
      if (dimension != null) break;
    }
    if (dimension == null) {
      dimension = const SlotDimension(20, SlotSizeUnit.percent);
      basis = SlotPercentBasis.layout;
    }
    final size = config.slotPreferredSizes.containsKey(addition.slotId)
        ? config.slotPreferredSizes[addition.slotId]
        : addition.component.preferredSize;
    final preferredWidth = saved != null
        ? saved.preferredWidth
        : size == null
        ? null
        : SlotDimension(size.width, SlotSizeUnit.pixels);
    final preferredHeight = saved != null
        ? saved.preferredHeight
        : size == null
        ? null
        : SlotDimension(size.height, SlotSizeUnit.pixels);
    return config.copyWith(
      slotSizeConstraints: {
        ...config.slotSizeConstraints,
        addition.slotId: SlotSizeConstraints(
          minWidth: saved?.minWidth,
          minHeight: saved?.minHeight,
          maxWidth: saved?.maxWidth,
          maxHeight: saved?.maxHeight,
          preferredWidth: width ? dimension : preferredWidth,
          preferredHeight: width ? preferredHeight : dimension,
          padding: saved?.padding ?? 0,
          paddingInsets: saved?.paddingInsets,
          percentBasis: dimension.unit == SlotSizeUnit.percent
              ? basis
              : saved?.percentBasis ?? SlotPercentBasis.zone,
          fitContent: saved?.fitContent,
        ),
      },
    );
  }

  /// Identifiant technique optionnel du layout pour le stockage dans les JSON d'apparence.
  final String? id;

  final String label;

  /// Nom court de la disposition, affiché dans le chemin de la bannière du mode
  /// édition ; [label] par défaut.
  final String? name;
  final bool editable;

  /// Affiche le nom des zones pendant le mode édition ; à désactiver pour une
  /// disposition imbriquée qui ne s'édite pas.
  final bool showZoneNames;
  final IconData? menuIcon;
  final Map<SuperLayoutZone, String> zoneLabels;
  final Map<SuperLayoutZone, ComponentTagFilter> zoneTagFilters;

  String zoneLabel(SuperLayoutZone zone) => zoneLabels[zone] ?? zone.label;

  @override
  State<SuperLayout> createState() => SuperLayoutState();
}

class SuperLayoutState extends State<SuperLayout> {
  late final ValueNotifier<SuperLayoutConfig> _config = ValueNotifier(
    widget.config,
  );

  SuperLayoutConfig get config => _config.value;

  /// Vrai quand un nom de zone glissé survole le centre.
  final _overCenter = ValueNotifier(false);

  /// Vrai quand le nom d'une autre zone est survolé ou glissé : le centre, qui
  /// reçoit l'échange, est surligné.
  final _centerHint = ValueNotifier(false);
  final _hinting = <SuperLayoutZone>{};

  /// Zone selectionnee par un clic sur son nom, affichee dans la banniere.
  final _selected = ValueNotifier<SuperLayoutZone?>(null);
  final _selectedSlot = ValueNotifier<String?>(null);
  final _zoneFocusKeys = <SuperLayoutZone, GlobalKey>{};
  final _zoneSlotKeys = <SuperLayoutZone, GlobalKey<EditorSlotState>>{};
  final _slotFocusKeys = <String, GlobalKey>{};
  final _gridSlotSizeKeys = <String, GlobalKey>{};
  SuperLayoutConfig? _reportedConfig;

  void _select(SuperLayoutZone zone) {
    if (_selectedSlot.value != null) {
      _selectedSlot.value = null;
      _selected.value = zone;
    } else {
      _selected.value = _selected.value == zone ? null : zone;
    }
  }

  void _selectZone(SuperLayoutZone zone) {
    _selectedSlot.value = null;
    _selected.value = zone;
    _LayoutEditSelection.activate(this);
  }

  void _selectSlot(SuperLayoutZone zone, SlotImplementation slot) {
    _selectedSlot.value =
        _selected.value == zone && _selectedSlot.value == slot.id
        ? null
        : slot.id;
    _selected.value = zone;
    _LayoutEditSelection.activate(this);
  }

  List<String> _reportedPath = const [];
  LayoutAxisAction? _reportedAxis;

  SuperLayoutZone get _actionZone =>
      _config.value.visibleZones.contains(_selected.value)
      ? _selected.value!
      : SuperLayoutZone.center;

  void _selectContextZone(Offset position) {
    if (_config.value.positioning == SuperLayoutPositioning.grid) {
      _selected.value = null;
      _selectedSlot.value = null;
      for (final id in _config.value.placedSlotIds) {
        final box = _slotFocusKeys[id]?.currentContext?.findRenderObject();
        if (box is RenderBox &&
            box.attached &&
            box.hasSize &&
            (Offset.zero & box.size).contains(box.globalToLocal(position))) {
          _selectedSlot.value = id;
          break;
        }
      }
      _LayoutEditSelection.activate(this);
      return;
    }
    for (final zone in _config.value.visibleZones) {
      final box = _zoneFocusKeys[zone]?.currentContext?.findRenderObject();
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          box.size.isEmpty ||
          !(Offset.zero & box.size).contains(box.globalToLocal(position))) {
        continue;
      }
      _selectZone(zone);
      return;
    }
  }

  LayoutAxisAction _axisAction(SuperLayoutZone zone) => LayoutAxisAction(
    zoneLabel: widget.zoneLabel(zone),
    axis: _config.value.axisOf(zone),
    onToggle: () {
      if (!mounted || !widget.editable) return;
      final config = _config.value;
      _update(
        config.withAxis(
          zone,
          config.axisOf(zone) == Axis.horizontal
              ? Axis.vertical
              : Axis.horizontal,
        ),
      );
    },
    onEditFlow: widget.editable ? () => _openZoneFlowEditor(zone) : null,
  );

  /// Déclare le chemin des zones sélectionnées à la bannière du mode édition.
  void _reportPath(List<String> path, {LayoutAxisAction? axis}) {
    if (identical(_reportedConfig, _config.value) &&
        listEquals(_reportedPath, path) &&
        _reportedAxis?.axis == axis?.axis &&
        _reportedAxis?.zoneLabel == axis?.zoneLabel) {
      return;
    }
    _reportedPath = path;
    _reportedConfig = _config.value;
    _reportedAxis = axis;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && listEquals(_reportedPath, path)) {
        if (path.isEmpty && !LayoutSelection.isReported(this)) return;
        LayoutSelection.report(
          this,
          path,
          clear: () {
            _selectedSlot.value = null;
            _selected.value = null;
          },
          axis: _reportedAxis,
          focusContext:
              _slotFocusKeys[_selectedSlot.value]?.currentContext ??
              _zoneFocusKeys[_selected.value]?.currentContext ??
              context,
        );
      }
    });
  }

  /// Zones dont une étiquette (nom de zone ou slot) est survolée ou glissée :
  /// leurs étiquettes de slot changent de couleur, tous les noms de zone grossissent.
  final _emphasis = ValueNotifier<Set<Object>>(const {});
  final _emphasizing = <Object, Set<Object>>{};

  LabelEmphasis _emphasisFor(SuperLayoutZone zone) =>
      LabelEmphasis(scopes: _emphasis, scope: zone, onHover: _emphasize);

  void _emphasize(Object scope, Object source, bool hovered) {
    if (!mounted) return;
    final sources = _emphasizing[scope] ?? <Object>{};
    if (!(hovered ? sources.add(source) : sources.remove(source))) return;
    if (sources.isEmpty) {
      _emphasizing.remove(scope);
    } else {
      _emphasizing[scope] = sources;
    }
    _emphasis.value = {..._emphasizing.keys};
  }

  void _hintCenter(SuperLayoutZone zone, bool active) {
    if (!mounted) return;
    if (active ? _hinting.add(zone) : _hinting.remove(zone)) {
      _centerHint.value = _hinting.isNotEmpty;
    }
  }

  @override
  void didUpdateWidget(SuperLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) _config.value = widget.config;
  }

  @override
  void dispose() {
    LayoutSelection.unregister(this);
    _config.dispose();
    _overCenter.dispose();
    _centerHint.dispose();
    _emphasis.dispose();
    _selected.dispose();
    _selectedSlot.dispose();
    final owner = this;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LayoutSelection.report(owner, const []);
      if (identical(_LayoutEditSelection.selected.value, owner)) {
        _LayoutEditSelection.selected.value = null;
      }
    });
    super.dispose();
  }

  SuperLayoutZone? _displayZoneOf(SuperLayoutConfig value, String id) {
    for (final entry in value.placements.entries) {
      if (entry.value.contains(id)) {
        return value.positioning == SuperLayoutPositioning.grid
            ? SuperLayoutZone.center
            : value.contentZone(entry.key);
      }
    }
    return null;
  }

  String? _tagRejection(SuperLayoutConfig value) {
    for (final id in value.placedSlotIds) {
      final zone = _displayZoneOf(value, id)!;
      final unchanged =
          _displayZoneOf(_config.value, id) == zone &&
          _config.value.slotTypeOf(id) == value.slotTypeOf(id);
      if (!unchanged &&
          !(widget.zoneTagFilters[zone]?.accepts(
                _searchSlot(id, configuration: value)?.tags ?? const {},
              ) ??
              true)) {
        return 'Composant incompatible avec la zone ${widget.zoneLabel(zone)}.';
      }
    }
    return null;
  }

  bool _canMoveSlot(String id, SuperLayoutZone zone) =>
      _tagRejection(
        _config.value.withSlotMoved(id, _config.value.contentZone(zone)),
      ) ==
      null;

  bool _canSwapZone(SuperLayoutZone zone) =>
      _config.value.canSwap(zone) &&
      _tagRejection(_config.value.withSwap(zone)) == null;

  void _removeSlot(String id) {
    final type = _config.value.slotTypeOf(id);
    removeSlotInstance(
      context,
      id: id,
      type: type,
      containerKind: EditorConfigKind.layout,
      unplace: () => _update(_config.value.withoutSlot(id)),
    );
  }

  void _update(SuperLayoutConfig value, {bool validateTags = true}) {
    if (value == _config.value) return;
    final rejection = validateTags ? _tagRejection(value) : null;
    if (rejection != null) {
      debugPrint(rejection);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(rejection)));
      return;
    }
    if (value.label != _config.value.label ||
        value.positioning != _config.value.positioning) {
      setState(() => _config.value = value);
    } else {
      _config.value = value;
    }
    widget.onChanged?.call(value);
  }

  /// Resout uniquement le slot demande, y compris les slots masques.
  SlotImplementation? searchSlot(String id) {
    final slot = _searchSlot(id);
    if (slot == null) return null;
    final previousLabel = _config.value.slotLabels[id];
    return InstanceSlot(
      slot,
      label: _config.value.slotLabels[id] ?? slot.label,
      onRename: (label) => _update(
        label == slot.label
            ? _config.value.copyWith(
                slotLabels: {..._config.value.slotLabels}..remove(id),
              )
            : _config.value.withSlotLabel(id, label),
      ),
      overridden: previousLabel != null,
      onRestore: () => _update(
        _config.value.copyWith(
          slotLabels: {..._config.value.slotLabels}
            ..remove(id)
            ..addAll({id: ?previousLabel}),
        ),
      ),
    );
  }

  String get _displayLabel {
    final instance = editorComponentLabelOf(context);
    return (instance?.overridden ?? false)
        ? instance!.label
        : _config.value.label ?? widget.label;
  }

  void _rename(String label) {
    final instance = editorComponentLabelOf(context);
    if (instance != null) {
      instance.onChanged(label);
    } else {
      _update(_config.value.copyWith(label: label.trim()));
    }
  }

  @override
  Widget build(BuildContext context) => ProvidedSlotScope(
    slots: widget.slots,
    child: EditorAddZones(
      label: _displayLabel,
      enabled: widget.editable,
      zones: _addZones,
      child: _buildLayout(context),
    ),
  );
}
