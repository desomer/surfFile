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

  void _select(SuperLayoutZone zone) =>
      _selected.value = _selected.value == zone ? null : zone;

  List<String> _reportedPath = const [];

  /// Déclare le chemin des zones sélectionnées à la bannière du mode édition.
  void _reportPath(List<String> path) {
    if (listEquals(_reportedPath, path)) return;
    _reportedPath = path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && listEquals(_reportedPath, path)) {
        LayoutSelection.report(this, path, clear: () => _selected.value = null);
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

  Future<void> _openEditor() async {
    final initial = _config.value;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (context) => AlertDialog(
        title: Text(widget.label),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: _config,
              builder: (context, _) =>
                  SuperLayoutEditor(config: _config.value, onChanged: _update),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
    if (confirmed != true && mounted) _update(initial);
  }

  Future<void> _addSlot(SuperLayoutZone zone) async {
    final id = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final slots = _availableSlots(context, includeRegistry: true);
        return SimpleDialog(
          title: Text('Ajouter un slot dans ${zone.label}'),
          children: [
            if (!slots.any((slot) => slot.visible))
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text('Aucun slot visible disponible.'),
              ),
            for (final slot in slots)
              if (slot.visible)
                SimpleDialogOption(
                  key: ValueKey('super-layout-add-slot-${slot.id}'),
                  onPressed: () => Navigator.of(dialogContext).pop(slot.id),
                  child: Text(slot.label),
                ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );
    if (id == null || !mounted) return;
    final config = _config.value;
    final supplied = widget.slots.any((slot) => slot.id == id);
    var instanceId = id;
    if (!supplied) {
      final used = {
        ...widget.slots.map((slot) => slot.id),
        ...config.placements.values.expand((ids) => ids),
      };
      do {
        instanceId = shortid.generate();
      } while (used.contains(instanceId));
    }

    _update(
      config.withSlotMoved(
        instanceId,
        config.contentZone(zone),
        type: supplied ? null : id,
      ),
    );
  }

  Future<void> _editSlotPreferredSize(SlotImplementation slot) async {
    final sizes = _config.value.slotPreferredSizes;
    final initial = sizes.containsKey(slot.id)
        ? sizes[slot.id]
        : slot.preferredSize;
    final width = TextEditingController(text: initial?.width.toString() ?? '');
    final height = TextEditingController(
      text: initial?.height.toString() ?? '',
    );
    final form = GlobalKey<FormState>();
    String? validate(String? text) {
      final value = double.tryParse((text ?? '').replaceAll(',', '.'));
      return value != null && value.isFinite && value > 0
          ? null
          : 'Saisissez une dimension positive en pixels.';
    }

    try {
      final result = await showDialog<({Size? size})>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Taille préférée : ${slot.label}'),
          content: SizedBox(
            width: 320,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in [
                    (controller: width, label: 'Largeur (px)', key: 'width'),
                    (controller: height, label: 'Hauteur (px)', key: 'height'),
                  ])
                    TextFormField(
                      key: ValueKey('slot-preferred-${field.key}'),
                      controller: field.controller,
                      decoration: InputDecoration(labelText: field.label),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: validate,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop((size: null)),
              child: const Text('Taille automatique'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.of(context).pop((
                  size: Size(
                    double.parse(width.text.replaceAll(',', '.')),
                    double.parse(height.text.replaceAll(',', '.')),
                  ),
                ));
              },
              child: const Text('Appliquer'),
            ),
          ],
        ),
      );
      if (result != null && mounted) {
        _update(_config.value.withSlotPreferredSize(slot.id, result.size));
      }
    } finally {
      // Le dialogue peut encore terminer son animation de fermeture.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        width.dispose();
        height.dispose();
      });
    }
  }

  List<SlotImplementation> _availableSlots(
    BuildContext context, {
    bool? includeRegistry,
  }) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final ids = {for (final slot in widget.slots) slot.id};
    return [
      ...widget.slots,
      if (registry != null)
        for (final entry in registry.components.entries)
          if (entry.value.isAvailable?.call(context) ?? true)
            if (!ids.contains(entry.value.slotId))
              entry.value.createSlot(
                entry.value.slotId ?? _registrySlotId(entry.key, ids),
              ),
      if (includeRegistry == true && registry != null)
        for (final entry in registry.registry.entries)
          _createRegistrySlot(
            entry.key,
            entry.value,
            _registrySlotId(entry.key, ids),
          ),
    ];
  }

  BuilderSlot _createRegistrySlot(
    String key,
    ComponentBuilder component,
    String id,
  ) => BuilderSlot(
    id: id,
    label: 'Registre : $key',
    builder: (_) => component.getWidget(XuiBuildCtx(id: id)),
  );

  String _registrySlotId(String key, Set<String> slotIds) {
    var id = 'registry:${Uri.encodeComponent(key)}';
    while (slotIds.contains(id)) {
      id = 'registry:$id';
    }
    return id;
  }

  /// Resout uniquement le slot demande, sans construire les autres slots.
  /// Retourne aussi les slots masques ; un identifiant inconnu renvoie null.
  SlotImplementation? searchSlot(String id) {
    final type = config.slotTypeOf(id);
    final registry = SuperApp.maybeOf(context)?.registry;
    final ids = <String>{};
    SlotImplementation? supplied;
    for (final slot in widget.slots) {
      ids.add(slot.id);
      if (slot.id == type) supplied = slot;
    }
    if (registry == null) return supplied;

    for (final entry in registry.registry.entries) {
      if (_registrySlotId(entry.key, ids) == type) {
        return _createRegistrySlot(entry.key, entry.value, id);
      }
    }
    if (supplied != null) return supplied;

    RegisteredComponent? component;
    for (final entry in registry.components.entries) {
      final candidate = entry.value;
      if (ids.contains(candidate.slotId)) continue;
      if ((candidate.slotId ?? _registrySlotId(entry.key, ids)) == type &&
          (candidate.isAvailable?.call(context) ?? true)) {
        component = candidate;
      }
    }
    return component?.createSlot(id);
  }

  /// Slots visibles rangés dans la zone de contenu [content], dans l'ordre de
  /// [SuperLayoutConfig.placements] ; un identifiant inconnu est ignoré.
  List<SlotImplementation> _slotsOf(
    SuperLayoutConfig config,
    SuperLayoutZone content,
  ) {
    final ids = config.placementsOf(content);
    if (ids.isEmpty) return const [];
    return [
      for (final id in ids)
        if (searchSlot(id) case final slot? when slot.visible) slot,
    ];
  }

  bool _hasContent(SuperLayoutConfig config, SuperLayoutZone content) =>
      _slotsOf(config, content).isNotEmpty;

  Widget _contentOf(
    SuperLayoutConfig config,
    SuperLayoutZone zone,
    Set<SuperLayoutZone> autoSides,
    bool editMode,
  ) {
    final content = config.contentZone(zone);
    final slots = _slotsOf(config, content);
    if (slots.isEmpty) {
      return _ZonePlaceholder(
        zone: zone,
        showLabel: !(editMode && widget.showZoneNames && widget.editable),
      );
    }
    final auto = autoSides.contains(zone);
    final axis = config.axisOf(zone);
    final autoHeight =
        auto &&
        (zone == SuperLayoutZone.north || zone == SuperLayoutZone.south);
    final autoWidth =
        auto && (zone == SuperLayoutZone.west || zone == SuperLayoutZone.east);
    return SlotStack(
      slots: slots,
      axis: axis,
      preferredSizes: config.slotPreferredSizes,
      onEditPreferredSize: editMode && widget.editable
          ? _editSlotPreferredSize
          : null,
      showLabels: editMode,
      emphasis: _emphasisFor(zone),
      zoneLabel: zone.label,
      mover: editMode && widget.editable
          ? SlotMover(
              owner: this,
              onMove: (id, {beforeId, afterId}) => _update(
                _config.value.withSlotMoved(
                  id,
                  content,
                  beforeId: beforeId,
                  afterId: afterId,
                ),
              ),
            )
          : null,
      expand: !(axis == Axis.vertical ? autoHeight : autoWidth),
      stretch: !(axis == Axis.vertical ? autoWidth : autoHeight),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if ((StyleEditScope.controllerOf(context)?.value ?? false) &&
          event.buttons == kPrimaryButton) {
        _LayoutEditSelection.select(this, event);
      }
    },
    child: SuperContainer(
      decorate: false,
      label: widget.label,
      editable: widget.editable,
      onEdit: _openEditor,
      onAdd: () => _addSlot(
        _config.value.visibleZones.contains(_selected.value)
            ? _selected.value!
            : SuperLayoutZone.center,
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _config,
          _selected,
          _LayoutEditSelection.selected,
        ]),
        builder: (context, _) {
          final config = _config.value;
          // Seule la disposition selectionnee affiche ses actions overlay.
          final editMode =
              (StyleEditScope.controllerOf(context)?.value ?? false) &&
              identical(_LayoutEditSelection.selected.value, this);
          final parentPath = _LabelScope.pathOf(context);
          final selected = _selected.value;
          final name = widget.name ?? widget.label;
          LayoutSelection.register(this, [...parentPath, name], (zoneLabel) {
            if (!mounted) return;
            _selected.value = zoneLabel == null
                ? null
                : SuperLayoutZone.values
                      .where((zone) => zone.label == zoneLabel)
                      .firstOrNull;
            _LayoutEditSelection.selected.value = this;
          }, parent: this.context.findAncestorStateOfType<SuperLayoutState>());
          _reportPath(
            editMode
                ? [...parentPath, name, if (selected != null) selected.label]
                : const [],
          );
          final editing = widget.showZoneNames && editMode;
          final zones = config.visibleZones;
          // Un côté automatique sans contenu garde sa taille fixe.
          final autoSides = {
            for (final side in config.autoSides)
              if (zones.contains(side) &&
                  _hasContent(config, config.contentZone(side)))
                side,
          };
          return _ZoneLayout(
            config: config,
            autoSides: autoSides,
            children: [
              for (final zone in zones)
                _ZoneEntry(
                  key: ValueKey('super-layout-${zone.name}'),
                  zone: zone,
                  child: _LabelScope(
                    path: [...parentPath, name, zone.label],
                    child: _contentOf(config, zone, autoSides, editMode),
                  ),
                ),
              // Une zone reçoit un slot glissé sur sa partie libre : il s'y range
              // en dernier.
              if (editMode && widget.editable)
                for (final zone in zones)
                  _ZoneEntry(
                    key: ValueKey('super-layout-slot-drop-${zone.name}'),
                    zone: zone,
                    overlay: true,
                    dropTarget: true,
                    child: _SlotZoneTarget(
                      owner: this,
                      zoneLabel: zone.label,
                      ids: [
                        for (final slot in _slotsOf(
                          config,
                          config.contentZone(zone),
                        ))
                          slot.id,
                      ],
                      onMove: (id) => _update(
                        config.withSlotMoved(id, config.contentZone(zone)),
                      ),
                    ),
                  ),
              // Noms des zones utilisées, au-dessus de leur centre.
              if (editing) ...[
                _ZoneEntry(
                  key: const ValueKey('super-layout-center-target'),
                  zone: SuperLayoutZone.center,
                  overlay: true,
                  dropTarget: true,
                  child: _CenterSwapTarget(
                    overCenter: _overCenter,
                    hint: _centerHint,
                    canSwap: (zone) =>
                        widget.editable &&
                        zones.contains(zone) &&
                        config.canSwap(zone),
                    onSwap: (zone) => _update(config.withSwap(zone)),
                  ),
                ),
                for (final zone in zones)
                  if (_hasContent(config, config.contentZone(zone)))
                    _ZoneEntry(
                      key: ValueKey('super-layout-name-${zone.name}'),
                      zone: zone,
                      overlay: true,
                      child: _ZoneNameBadge(
                        zone: zone,
                        overCenter: _overCenter,
                        onCenterHint: (active) => _hintCenter(zone, active),
                        emphasis: _emphasisFor(zone),
                        selected: selected == zone,
                        onSelect: () => _select(zone),
                        swapTarget: widget.editable && config.canSwap(zone)
                            ? zone.opposite
                            : null,
                        moves: !zones.contains(zone.opposite),
                        onSwap: () => _update(config.withSwap(zone)),
                      ),
                    )
                  else if (widget.editable)
                    _ZoneEntry(
                      key: ValueKey('super-layout-add-overlay-${zone.name}'),
                      zone: zone,
                      overlay: true,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: IconButton.filled(
                            key: ValueKey('super-layout-add-${zone.name}'),
                            tooltip: 'Ajouter un slot dans ${zone.label}',
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .35),
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .onSurface,
                            ),
                            icon: const Icon(Icons.add),
                            onPressed: () => _addSlot(zone),
                          ),
                        ),
                      ),
                    ),
              ],
            ],
          );
        },
      ),
    ),
  );
}
