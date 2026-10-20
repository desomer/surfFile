/// Liste répétant une disposition pour chaque élément d'un tableau JSON.
///
/// ## Usage dans le designer
///
/// 1. Ajoutez le composant *SuperListView* (« Liste ») dans une disposition.
/// 2. Clic droit sur la liste, *Liste* : choisissez le repository et le
///    chemin du tableau, par exemple `clients`.
/// 3. Concevez la ligne : chaque ligne est un `SuperLayout` (« Ligne »)
///    partagé par tous les éléments. Placez-y des `SuperText` liés à
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
///       builder: (_) => const SuperText(
///         id: 'nom',
///         config: SuperTextConfig(
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
import '../../services/json_list_scope.dart';
import '../../services/json_repository_binding.dart';
import '../../services/json_repository_scope.dart';
import '../../services/json_repository_store.dart';
import '../../super_app.dart';
import '../editing/history/editor_history.dart';
import '../editing/components/super_list_view_editor.dart';
import '../super_layout/slot_implementation.dart';
import '../super_layout/super_layout.dart';
import '../editing/slots/editor_slot.dart';

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
    this.config = const SuperListViewConfig(),
    this.template = const SuperLayoutConfig(),
    this.slots = const [],
    this.onConfigChanged,
    super.key,
  });

  /// ID sous lequel sont persistés les réglages et la disposition des lignes.
  final String id;

  /// Réglages initiaux, avant ceux enregistrés dans l'apparence.
  final SuperListViewConfig config;

  /// Disposition initiale des lignes, avant celle modifiée dans le designer.
  final SuperLayoutConfig template;

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
  late final ValueNotifier<SuperListViewConfig> _localConfig;
  late final ValueNotifier<SuperLayoutConfig> _localLayout;
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
  }

  @override
  void didUpdateWidget(SuperListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) _localConfig.value = widget.config;
  }

  @override
  void dispose() {
    _generation++;
    _store?.removeListener(_reload);
    _listen(const []);
    _localConfig.dispose();
    _localLayout.dispose();
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

  Widget _row(
    ValueNotifier<SuperLayoutConfig> layout,
    SuperListViewConfig config,
    JsonListScope? scope,
    int? index,
  ) {
    final row = ValueListenableBuilder<SuperLayoutConfig>(
      valueListenable: layout,
      builder: (context, value, _) => SuperLayout(
        label: 'Ligne',
        slots: widget.slots,
        config: value,
        onChanged: (next) => layout.value = next,
      ),
    );
    final vertical = config.axis == Axis.vertical;
    return Padding(
      key: ValueKey('super-list-row-${widget.id}-${index ?? 'template'}'),
      padding: vertical
          ? EdgeInsets.only(bottom: config.spacing)
          : EdgeInsets.only(right: config.spacing),
      child: JsonListScope(
        repositoryId: _source?.binding?.repositoryId ?? scope?.repositoryId,
        indices: [...?(_source?.rowBase ?? scope?.indices), index ?? 0],
        placeholder: index == null || (scope?.placeholder ?? false),
        child: Stack(
          children: [
            if (index != null && _isSelected(index))
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
            Positioned.fill(
              // Un Listener n'entre pas en concurrence avec le contenu : les
              // champs et boutons de la ligne restent utilisables.
              child: index == null || (scope?.placeholder ?? false)
                  ? row
                  : Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => _select(index),
                      child: row,
                    ),
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
    final configuration =
        registry?.listController(widget.id, fallback: widget.config) ??
        _localConfig;
    final layout =
        registry?.layoutController(widget.id, fallback: widget.template) ??
        _localLayout;
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
        final vertical = config.axis == Axis.vertical;

        return EditorSlot(
          label: 'Liste',
          onEdit: () => _edit(configuration),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fill = constraints.hasBoundedHeight;
              final list = ListView.builder(
                key: ValueKey('super-list-${widget.id}'),
                primary: false,
                shrinkWrap: vertical && !fill,
                scrollDirection: config.axis,
                itemExtent: config.itemExtent + config.spacing,
                itemCount: count + (add ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == count) {
                    return Align(
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
                  return _row(layout, config, scope, template ? null : index);
                },
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
