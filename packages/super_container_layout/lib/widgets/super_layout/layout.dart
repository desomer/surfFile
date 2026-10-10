part of '../super_layout.dart';

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
    this.label = 'Super layout',
    this.name,
    this.editable = true,
    this.showZoneNames = true,
    super.key,
  });

  final List<SlotImplementation> slots;
  final SuperLayoutConfig config;
  final ValueChanged<SuperLayoutConfig>? onChanged;
  final String label;

  /// Nom court de la disposition, affiché dans le chemin de la bannière du mode
  /// édition ; [label] par défaut.
  final String? name;
  final bool editable;

  /// Affiche le nom des zones pendant le mode édition ; à désactiver pour une
  /// disposition imbriquée qui ne s'édite pas.
  final bool showZoneNames;

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

  void _select(SuperLayoutZone zone) {
    _selectedSlot.value = null;
    _selected.value = _selected.value == zone ? null : zone;
  }

  void _selectSlot(SuperLayoutZone zone, SlotImplementation slot) {
    _selectedSlot.value = _selected.value == zone && _selectedSlot.value == slot.id
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
    zoneLabel: zone.label,
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
    if (listEquals(_reportedPath, path) &&
        _reportedAxis?.axis == axis?.axis &&
        _reportedAxis?.zoneLabel == axis?.zoneLabel) {
      return;
    }
    _reportedPath = path;
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
