/// Liste répétant une disposition pour chaque élément d'un tableau JSON.
///
/// ## Usage dans le designer
///
/// 1. Ajoutez le composant *SuperListView* (« Liste ») dans une disposition.
/// 2. Clic droit sur la liste, *Liste* : choisissez le repository et le
///    chemin du tableau, par exemple `clients`.
/// 3. Concevez la ligne : chaque ligne est un `SuperLayout` (« Ligne »)
///    partagé par tous les éléments. Placez-y des `SuperValue` liés à
///    `clients[?].nom` avec le repository « Hérité de la liste englobante ».
/// 4. Pour une sous-liste, placez une autre *SuperListView* dans la ligne,
///    liée à `clients[?].commandes` ; ses textes utilisent
///    `clients[?].commandes[?].ref`.
///
/// ## Sélection et maître / détail
///
/// Un clic sur une ligne la sélectionne (surlignage). La sélection est
/// mémorisée par chemin modèle de tableau dans le `JsonRepositoryBinding` du
/// repository, pas dans la liste : toutes les listes sur le même tableau
/// partagent la sélection. Un composant placé **hors** de la liste avec le
/// même chemin `clients[?].nom` affiche et modifie la ligne sélectionnée, et
/// une liste hors du maître sur `clients[?].commandes` affiche les commandes
/// du client sélectionné.
///
/// * aucune ligne n'est sélectionnée au départ ;
/// * *Ajouter* sélectionne l'élément ajouté ;
/// * *Supprimer* décale ou efface les sélections concernées ;
/// * une sélection hors du tableau après rechargement du fichier est effacée.
///
/// ## Usage en code
///
/// ```dart
/// SuperListView(
///   id: 'clients',
///   config: SuperListViewConfig(
///     binding: JsonTextBinding(repositoryId: id, path: 'clients'),
///     itemExtent: 80,
///   ),
///   template: SuperLayoutConfig(
///     placements: {SuperLayoutZone.center: ['nom']},
///   ),
///   slots: [
///     BuilderSlot(
///       id: 'nom',
///       label: 'Nom',
///       builder: (_) => const SuperValue(
///         id: 'nom',
///         config: SuperValueConfig(
///           binding: JsonTextBinding(path: 'clients[?].nom'),
///         ),
///       ),
///     ),
///   ],
/// )
/// ```
///
/// La liste a besoin d'un `JsonRepositoryScope` au-dessus d'elle. Avec un
/// `SuperApp`, ses réglages et sa disposition sont persistés dans
/// l'apparence sous [SuperListView.id].
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/json_text_binding.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_list_view_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../super_app.dart';
import '../../theme/appearance.dart';
import '../../theme/container_style.dart';
import '../editing/history/editor_history.dart';
import '../editing/components/super_list_view_editor.dart';
import '../super_layout/slot_implementation.dart';
import '../super_layout/super_layout.dart';
import '../super_layout/iterable_content.dart';
import '../editing/slots/editor_slot.dart';
import '../editing/slots/slot_size_editor.dart';

/// Répète une disposition [SuperLayout] pour chaque élément d'un tableau de
/// repository.
///
/// Chaque ligne expose son indice par un [JsonListScope] : une liaison
/// descendante `clients[?].nom` lit `clients[3].nom` dans la 4e ligne, et une
/// liste imbriquée sur `clients[?].commandes` répète sa propre ligne dans
/// chaque client.
///
/// Un clic sélectionne la ligne dans le [JsonArrayBinding] du chemin modèle :
/// une liaison placée hors de la liste, par exemple `clients[?].nom`, lit
/// alors la ligne sélectionnée.
class SuperListView extends StatefulWidget {
  const SuperListView({
    required this.id,
    this.itemId,
    this.config = const SuperListViewConfig(),
    this.template = const SuperLayoutConfig(),
    this.templateStyle = const ContainerStyle(),
    this.slots = const [],
    this.onConfigChanged,
    super.key,
  });

  /// ID sous lequel sont persistés les réglages et la disposition des lignes.
  final String id;

  /// ID technique distinct pour l'[IterableContent] des lignes.
  /// Si non spécifié, utilise [SuperListViewConfig.itemId] ou `'${id}-item'`.
  final String? itemId;

  /// Réglages initiaux, avant ceux enregistrés dans l'apparence.
  final SuperListViewConfig config;

  /// Disposition initiale des lignes, avant celle modifiée dans le designer.
  final SuperLayoutConfig template;

  /// Shared row surface style, before any persisted template override.
  final ContainerStyle templateStyle;

  /// Composants définis en code et disponibles dans la disposition des
  /// lignes.
  final List<SlotImplementation> slots;

  /// Appelé après une modification des réglages par la fenêtre d'édition.
  final ValueChanged<SuperListViewConfig>? onConfigChanged;

  @override
  State<SuperListView> createState() => _SuperListViewState();
}

/// Tableau résolu de la liste.
@immutable
class _Source {
  const _Source({
    this.binding,
    this.error,
    this.unselected = false,
    this.parents = const [],
    this.rowBase = const [],
    this.arrays = const [],
  });

  final JsonTextBinding? binding;
  final String? error;

  /// Un `[?]` du chemin n'a pas de ligne sélectionnée.
  final bool unselected;

  /// Valeurs des `[?]` du chemin du tableau.
  final List<int> parents;

  /// Indices transmis aux lignes, avant leur propre indice.
  final List<int> rowBase;

  /// Sélections dont dépend le chemin du tableau.
  final List<JsonArrayBinding> arrays;

  @override
  bool operator ==(Object other) =>
      other is _Source &&
      other.binding == binding &&
      other.error == error &&
      other.unselected == unselected &&
      listEquals(other.parents, parents) &&
      listEquals(other.rowBase, rowBase) &&
      listEquals(other.arrays, arrays);

  @override
  int get hashCode => Object.hash(
    binding,
    error,
    unselected,
    Object.hashAll(parents),
    Object.hashAll(rowBase),
    Object.hashAll(arrays),
  );
}

class _SuperListViewState extends State<SuperListView> {
  String get effectiveItemId =>
      widget.itemId ?? widget.config.itemId ?? '${widget.id}:item';

  late final ValueNotifier<SuperListViewConfig> _localConfig;
  late final ValueNotifier<SuperLayoutConfig> _localLayout;
  late final ValueNotifier<ContainerStyle> _localStyle;
  JsonRepositoryStore? _store;
  _Source? _source;

  /// Sélection du tableau de la liste, puis celles utilisées par son chemin.
  JsonArrayBinding? _selection;
  List<JsonArrayBinding> _listened = const [];
  List<Object?>? _items;
  String? _error;
  bool _loading = false;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.config.validate();
    _localConfig = ValueNotifier(widget.config);
    _localLayout = ValueNotifier(widget.template);
    _localStyle = ValueNotifier(widget.templateStyle);
  }

  @override
  void didUpdateWidget(SuperListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.config != widget.config) {
      _localConfig.value = widget.config;
    }
    if (oldWidget.id != widget.id || oldWidget.template != widget.template) {
      _localLayout.value = widget.template;
    }
    if (oldWidget.id != widget.id ||
        oldWidget.templateStyle != widget.templateStyle) {
      _localStyle.value = widget.templateStyle;
    }
  }

  @override
  void dispose() {
    _generation++;
    _store?.removeListener(_reload);
    _listen(const []);
    _localConfig.dispose();
    _localLayout.dispose();
    _localStyle.dispose();
    super.dispose();
  }

  _Source _resolve(
    SuperListViewConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final binding = config.binding;
    if (binding == null) return const _Source();
    try {
      final resolved = JsonListScope.resolveSelected(binding, scope, store);
      final scoped = scope?.indices ?? const <int>[];
      return _Source(
        binding: resolved.binding,
        unselected: resolved.binding == null,
        parents: resolved.indices,
        rowBase: resolved.indices.length > scoped.length
            ? resolved.indices
            : scoped,
        arrays: resolved.arrays,
      );
    } on FormatException catch (error) {
      return _Source(error: error.message);
    }
  }

  /// Chemin modèle du tableau, qui identifie sa sélection.
  String? get _template {
    final path = _configPath;
    return path == null ? null : JsonAttributePath(path).toString();
  }

  String? _configPath;

  void _listen(List<JsonArrayBinding> arrays) {
    for (final array in _listened) {
      array.removeListener(_selectionChanged);
    }
    _listened = arrays;
    for (final array in arrays) {
      array.addListener(_selectionChanged);
    }
  }

  void _observe(_Source source, JsonRepositoryStore? store) {
    if (_source == source && identical(_store, store)) return;
    if (_source != source) {
      // Les lignes d'un autre tableau (indices parents décalés…) ne doivent
      // pas être affichées avec les nouveaux indices avant le rechargement.
      _items = null;
      _error = null;
    }
    _source = source;
    if (!identical(_store, store)) {
      _store?.removeListener(_reload);
      _store = store?..addListener(_reload);
    }
    final binding = source.binding;
    _selection = binding == null || store == null
        ? null
        : store.bindingOf(binding.repositoryId!).array(_template!);
    _listen([?_selection, ...source.arrays]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  bool _isSelected(int index) {
    final source = _source;
    return source != null && _selection?.indexFor(source.parents) == index;
  }

  void _select(int index) {
    final source = _source;
    if (source == null) return;
    _selection?.select(source.parents, index);
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final binding = _source?.binding;
    final store = _store;
    if (binding == null || store == null) {
      setState(() {
        _items = null;
        _loading = false;
        _error =
            _source?.error ??
            (store == null && _source?.unselected == true
                ? 'Service de repositories indisponible.'
                : null);
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await store.readArray(binding.repositoryId!, binding.path);
      if (!mounted || generation != _generation) return;
      final selected = _selection?.indexFor(_source!.parents);
      // Le fichier a changé hors de la liste : oublie une ligne disparue.
      if (selected != null && selected >= items.length) _selection!.clear();
      setState(() {
        _items = items;
        _error = null;
      });
    } on FormatException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.message);
      }
    } on FileSystemException {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Impossible de lire le repository lié.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _change(
    Future<int> Function(JsonRepositoryStore, JsonTextBinding) action,
  ) async {
    final binding = _source?.binding;
    final store = _store;
    if (binding == null || store == null || _busy) return;
    setState(() => _busy = true);
    try {
      // Les saisies en attente visent les indices actuels : les enregistrer
      // d'abord.
      await store.flushBindings();
      await action(store, binding);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException {
      if (mounted) {
        setState(() => _error = 'Impossible d’enregistrer le repository lié.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() {
    final length = _items?.length ?? 0;
    return _change((store, binding) async {
      final count = await store.appendArrayItem(
        binding.repositoryId!,
        binding.path,
        expectedLength: length,
      );
      if (mounted && _source?.binding == binding) _select(count - 1);
      return count;
    });
  }

  Future<void> _remove(int index) async {
    final items = _items;
    if (items == null || index >= items.length) return;
    final expected = items[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l’élément ?'),
        content: Text('L’élément ${index + 1} sera retiré du repository.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _change((store, binding) async {
      final count = await store.removeArrayItem(
        binding.repositoryId!,
        binding.path,
        index,
        expectedItem: expected,
      );
      final template = _template;
      if (template != null) {
        store
            .bindingOf(binding.repositoryId!)
            .removed(template, _source!.parents, index);
      }
      return count;
    });
  }

  Future<void> _edit(ValueNotifier<SuperListViewConfig> configuration) async {
    final result = await showSuperListViewEditor(
      context: context,
      config: configuration.value,
    );
    if (result == null || !mounted || result == configuration.value) return;
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    try {
      configuration.value = result;
    } finally {
      history?.commitTransaction();
    }
    widget.onConfigChanged?.call(result);
  }

  SlotSizeConstraints _initialItemSize(SuperListViewConfig config) {
    if (config.itemSize case final dimensions?) return dimensions;
    final automatic =
        config.wrap && config.wrapSizing == ListWrapSizing.automatic;
    return SlotSizeConstraints(
      preferredWidth:
          automatic || (!config.wrap && config.axis == Axis.vertical)
          ? null
          : SlotDimension(
              config.wrap ? config.itemWidth : config.itemExtent,
              SlotSizeUnit.pixels,
            ),
      preferredHeight:
          automatic || (!config.wrap && config.axis == Axis.horizontal)
          ? null
          : SlotDimension(config.itemExtent, SlotSizeUnit.pixels),
    );
  }

  Size _parentLayoutSize(Size fallback) {
    final parent = context
        .findAncestorStateOfType<SuperLayoutState>()
        ?.context
        .findRenderObject();
    if (parent is! RenderBox) return fallback;
    final bounds = parent.constraints.biggest;
    return Size(
      bounds.width.isFinite ? bounds.width : fallback.width,
      bounds.height.isFinite ? bounds.height : fallback.height,
    );
  }

  Future<void> _editItemSize(
    BuildContext target,
    ValueNotifier<SuperListViewConfig> configuration,
    Size viewport,
  ) async {
    final initial = configuration.value.itemSize;
    await showSlotSizeEditor(
      context: context,
      target: target,
      slot: BuilderSlot(
        id: widget.id,
        label: 'Iterable Content',
        builder: (_) => const SizedBox(),
      ),
      saved: _initialItemSize(configuration.value),
      legacy: null,
      changes: configuration,
      measure: () {
        if (!target.mounted) return null;
        final box = target.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return null;
        return (
          layout: _parentLayoutSize(viewport),
          zone: Offset.zero & viewport,
          slot: Offset.zero & box.size,
        );
      },
      onApply: (dimensions, _) {
        configuration.value = configuration.value.copyWith(
          itemSize: dimensions,
        );
        widget.onConfigChanged?.call(configuration.value);
      },
      onRestore: () {
        configuration.value = configuration.value.copyWith(
          itemSize: initial,
          clearItemSize: initial == null,
        );
        widget.onConfigChanged?.call(configuration.value);
      },
    );
  }

  Widget _row(
    ValueNotifier<SuperLayoutConfig> layout,
    ValueNotifier<ContainerStyle> style,
    ValueNotifier<SuperListViewConfig> configuration,
    SuperListViewConfig config,
    JsonListScope? scope,
    int? index,
    Size viewport,
  ) {
    final natural =
        config.itemSize != null ||
        (config.wrap && config.wrapSizing == ListWrapSizing.automatic);
    final content = ValueListenableBuilder<SuperLayoutConfig>(
      valueListenable: layout,
      builder: (context, value, _) => ValueListenableBuilder<ContainerStyle>(
        valueListenable: style,
        builder: (context, rowStyle, _) => IterableContent(
          id: effectiveItemId,
          label: 'Iterable Content',
          slots: widget.slots,
          config: value,
          style: rowStyle,
          shrinkWrap: natural,
          onEditSize: () => _editItemSize(context, configuration, viewport),
          onChanged: (next) => layout.value = next,
          onStyleChanged: (next) => style.value = next,
        ),
      ),
    );
    final row = natural && config.allowRemove
        ? ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: kMinInteractiveDimension,
              minHeight: kMinInteractiveDimension,
            ),
            child: content,
          )
        : content;
    final vertical = config.axis == Axis.vertical;
    final dimensions = _initialItemSize(config);
    final basis = dimensions.percentBasis == SlotPercentBasis.layout
        ? _parentLayoutSize(viewport)
        : viewport;
    double? resolve(SlotDimension? value, double extent) =>
        value?.resolve(extent);
    (double, double, double?) bounds(
      SlotDimension? minimum,
      SlotDimension? maximum,
      SlotDimension? preferred,
      double available,
      double limit,
    ) {
      final min = (resolve(minimum, available) ?? 0).clamp(0.0, limit);
      final max = (resolve(maximum, available) ?? limit).clamp(min, limit);
      final size = resolve(preferred, available)?.clamp(min, max);
      return (min, max, size);
    }

    final (minWidth, maxWidth, width) = bounds(
      dimensions.minWidth,
      dimensions.maxWidth,
      dimensions.preferredWidth,
      basis.width,
      !config.wrap && config.axis == Axis.horizontal
          ? double.infinity
          : viewport.width,
    );
    final (minHeight, maxHeight, height) = bounds(
      dimensions.minHeight,
      dimensions.maxHeight,
      dimensions.preferredHeight,
      basis.height,
      !config.wrap && config.axis == Axis.horizontal
          ? viewport.height
          : double.infinity,
    );
    final item = Padding(
      key: ValueKey('super-list-row-${widget.id}-${index ?? 'template'}'),
      padding: config.wrap || config.itemSize != null
          ? EdgeInsets.zero
          : vertical
          ? EdgeInsets.only(bottom: config.spacing)
          : EdgeInsets.only(right: config.spacing),
      child: JsonListScope(
        selected: index != null && _isSelected(index),
        repositoryId: _source?.binding?.repositoryId ?? scope?.repositoryId,
        indices: [...?(_source?.rowBase ?? scope?.indices), index ?? 0],
        placeholder: index == null || (scope?.placeholder ?? false),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (index != null &&
                _isSelected(index) &&
                style.value.states?.hasSelected != true)
              Positioned.fill(
                key: ValueKey('super-list-selected-${widget.id}-$index'),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: .6),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            // A Listener leaves the row's fields and buttons interactive.
            if (index == null || (scope?.placeholder ?? false))
              row
            else
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _select(index),
                child: row,
              ),
            if (index != null && config.allowRemove)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  key: ValueKey('super-list-remove-${widget.id}-$index'),
                  tooltip: 'Supprimer l’élément',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: _busy ? null : () => _remove(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          ],
        ),
      ),
    );
    final rowHeight =
        height ??
        (!config.wrap && config.axis == Axis.horizontal ? maxHeight : null);
    final sized = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth,
        maxWidth: maxWidth.isFinite
            ? maxWidth
            : (width ?? viewport.width).clamp(minWidth, double.infinity),
        minHeight: minHeight,
        maxHeight: maxHeight,
      ),
      child: SizedBox(
        width:
            width ??
            (!config.wrap && config.axis == Axis.vertical ? maxWidth : null),
        height: rowHeight,
        child: Padding(
          padding: dimensions.contentPadding,
          child: Column(
            mainAxisSize: rowHeight == null
                ? MainAxisSize.min
                : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                fit: natural && rowHeight == null
                    ? FlexFit.loose
                    : FlexFit.tight,
                child: item,
              ),
            ],
          ),
        ),
      ),
    );
    return config.itemSize == null || config.wrap
        ? sized
        : Align(
            alignment: Alignment.topLeft,
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
              padding: vertical
                  ? EdgeInsets.only(bottom: config.spacing)
                  : EdgeInsets.only(right: config.spacing),
              child: sized,
            ),
          );
  }

  Widget _message(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(
      text,
      key: ValueKey('super-list-message-${widget.id}'),
      style: error
          ? TextStyle(color: Theme.of(context).colorScheme.error)
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final app = SuperApp.maybeOf(context);
    final registry = app?.registry;
    final rowId = effectiveItemId;
    final rowStyleFallback = app == null
        ? widget.templateStyle
        : (app.registry?.containerStyleById[rowId]?.value ??
              app.registry?.containerStyleById[widget.id]?.value ??
              AppearanceScope.controllerOf(context)?.value.styles[rowId] ??
              AppearanceScope.controllerOf(context)?.value.styles[widget.id] ??
              widget.templateStyle);
    final configuration =
        registry?.listController(widget.id, fallback: widget.config) ??
        _localConfig;
    final layout =
        registry?.layoutController(widget.id, fallback: widget.template) ??
        _localLayout;
    final style =
        registry?.styleController(rowId, fallback: rowStyleFallback) ??
        _localStyle;
    final scope = JsonListScope.maybeOf(context);
    final store = JsonRepositoryScope.maybeOf(context);
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;

    return ValueListenableBuilder<SuperListViewConfig>(
      valueListenable: configuration,
      builder: (context, config, _) {
        final placeholder = scope?.placeholder ?? false;
        _configPath = config.binding?.path;
        if (!placeholder) _observe(_resolve(config, scope, store), store);
        final items = placeholder ? null : _items;
        final message = placeholder
            ? null
            : config.binding == null
            ? 'Liste non liée : choisissez un tableau dans les réglages.'
            : _error ??
                  (_source?.unselected == true
                      ? 'Aucune ligne sélectionnée.'
                      : items != null && items.isEmpty && !_loading
                      ? config.emptyText
                      : null);
        // Sans donnée, la ligne de gabarit reste modifiable dans le designer.
        final template =
            (items == null || items.isEmpty) && (editing || placeholder);
        final count = template ? 1 : items?.length ?? 0;
        final add =
            !placeholder &&
            config.allowAdd &&
            _source?.binding != null &&
            _error == null;
        final vertical = config.wrap || config.axis == Axis.vertical;

        return EditorSlot(
          id: widget.id,
          label: 'Liste',
          menuType: 'ListView',
          onEdit: () => _edit(configuration),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fill = constraints.hasBoundedHeight;
              final viewport = Size(
                constraints.maxWidth,
                fill
                    ? constraints.maxHeight
                    : MediaQuery.sizeOf(context).height,
              );
              Widget item(BuildContext context, int index) {
                if (index == count) {
                  return Align(
                    widthFactor: config.wrap ? 1 : null,
                    heightFactor: config.wrap ? 1 : null,
                    alignment: vertical
                        ? Alignment.centerLeft
                        : Alignment.center,
                    child: TextButton.icon(
                      key: ValueKey('super-list-add-${widget.id}'),
                      onPressed: _busy ? null : _add,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter'),
                    ),
                  );
                }
                return _row(
                  layout,
                  style,
                  configuration,
                  config,
                  scope,
                  template ? null : index,
                  viewport,
                );
              }

              final Widget list = config.wrap
                  ? SingleChildScrollView(
                      key: ValueKey('super-list-${widget.id}'),
                      primary: false,
                      child: Wrap(
                        spacing: config.spacing,
                        runSpacing: config.spacing,
                        children: [
                          for (
                            var index = 0;
                            index < count + (add ? 1 : 0);
                            index++
                          )
                            if (index == count &&
                                config.wrapSizing == ListWrapSizing.fixed &&
                                config.itemSize == null)
                              SizedBox(
                                width: config.itemWidth,
                                height: config.itemExtent,
                                child: item(context, index),
                              )
                            else
                              item(context, index),
                        ],
                      ),
                    )
                  : ListView.builder(
                      key: ValueKey('super-list-${widget.id}'),
                      primary: false,
                      shrinkWrap: vertical && !fill,
                      scrollDirection: config.axis,
                      itemExtent: config.itemSize == null
                          ? config.itemExtent + config.spacing
                          : null,
                      itemCount: count + (add ? 1 : 0),
                      itemBuilder: item,
                    );
              final error = _error != null || config.binding == null;
              return Column(
                mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (message != null) _message(message, error: error),
                  if (_error != null && config.binding != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Recharger la liste'),
                      ),
                    ),
                  if (count > 0 || add)
                    if (fill)
                      Expanded(child: list)
                    else if (vertical)
                      list
                    else
                      // Une liste horizontale a besoin d'une hauteur bornée.
                      SizedBox(height: config.itemExtent, child: list),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
