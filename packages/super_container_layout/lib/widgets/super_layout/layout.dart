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
/// structure s'édite par clic droit, comme un [SuperContainer].
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
    this.slots = const [],
    this.config = const SuperLayoutConfig(),
    this.onChanged,
    this.onSlotAdded = defaultSlotAddition,
    this.label = 'Super layout',
    this.name,
    this.editable = true,
    this.showZoneNames = true,
    this.zoneLabels = const {},
    super.key,
  });

  final List<SlotImplementation> slots;
  final SuperLayoutConfig config;
  final ValueChanged<SuperLayoutConfig>? onChanged;

  /// Customizes an editor addition atomically with placement and persistence.
  /// Return [SlotAddition.config] to keep its sizes unchanged.
  final SlotAddedCallback onSlotAdded;

  /// Reuses the first sibling preference, or sets 20% of the whole layout.
  /// The other dimension and existing bounds are preserved.
  static SuperLayoutConfig defaultSlotAddition(SlotAddition addition) {
    final zone = addition.zone;
    if (!zone.isSide) return addition.config;
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
      if (constraints != null) {
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
          percentBasis: dimension.unit == SlotSizeUnit.percent
              ? basis
              : saved?.percentBasis ?? SlotPercentBasis.zone,
        ),
      },
    );
  }

  final String label;

  /// Nom court de la disposition, affiché dans le chemin de la bannière du mode
  /// édition ; [label] par défaut.
  final String? name;
  final bool editable;

  /// Affiche le nom des zones pendant le mode édition ; à désactiver pour une
  /// disposition imbriquée qui ne s'édite pas.
  final bool showZoneNames;
  final Map<SuperLayoutZone, String> zoneLabels;

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
  final _slotFocusKeys = <String, GlobalKey>{};
  SuperLayoutConfig? _reportedConfig;

  void _select(SuperLayoutZone zone) {
    _selectedSlot.value = null;
    _selected.value = _selected.value == zone ? null : zone;
  }

  void _selectSlot(SuperLayoutZone zone, SlotImplementation slot) {
    _selectedSlot.value =
        _selected.value == zone && _selectedSlot.value == slot.id
        ? null
        : slot.id;
    _selected.value = zone;
    _LayoutEditSelection.selected.value = this;
  }

  List<String> _reportedPath = const [];
  LayoutAxisAction? _reportedAxis;

  SuperLayoutZone get _actionZone =>
      _config.value.visibleZones.contains(_selected.value)
      ? _selected.value!
      : SuperLayoutZone.center;

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
  /// leurs étiquettes de slot et tous les noms de zone grossissent.
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

  void _update(SuperLayoutConfig value) {
    if (value == _config.value) return;
    _config.value = value;
    widget.onChanged?.call(value);
  }

  /// Resout uniquement le slot demande, y compris les slots masques.
  SlotImplementation? searchSlot(String id) => _searchSlot(id);

  @override
  Widget build(BuildContext context) => _buildLayout(context);
}
