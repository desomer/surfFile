import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../../models/editor_page_config.dart';
import '../../../models/registry.dart';
import '../../../services/pages/editor_page_graph.dart';
import '../../../services/pages/editor_page_router.dart';
import '../../../theme/appearance.dart';
import '../dialogs/editor_dialog_header.dart';
import '../history/editor_history.dart';

Future<void> showEditorPageManager({
  required BuildContext context,
  required ValueNotifier<Appearance> appearance,
  required EditorPageRouter routing,
  required Registry registry,
}) async {
  final location = await showDialog<String>(
    context: context,
    builder: (_) => _PageManager(
      appearance: appearance,
      routing: routing,
      registry: registry,
    ),
  );
  if (!context.mounted || location == null) return;
  routing.synchronize(appearance.value.pageCatalog);
  routing.router.go(location);
}

class _PageManager extends StatefulWidget {
  const _PageManager({
    required this.appearance,
    required this.routing,
    required this.registry,
  });
  final ValueNotifier<Appearance> appearance;
  final EditorPageRouter routing;
  final Registry registry;

  @override
  State<_PageManager> createState() => _PageManagerState();
}

class _PageManagerState extends State<_PageManager> {
  late Appearance _base = widget.appearance.value;
  late Appearance _draft = _base;
  String? _error;
  String? _notice;
  EditorPageCatalog get _catalog => _draft.pageCatalog;
  bool get _dirty => !identical(_draft, _base);

  void _catalogChanged(EditorPageCatalog value) {
    setState(() {
      _draft = _draft.copyWith(pageCatalog: value);
      _error = null;
    });
  }

  void _report(Object error) => setState(() {
    _error = error is FormatException ? error.message : error.toString();
  });

  Future<EditorPageConfig?> _details({
    EditorPageConfig? page,
    bool duplicate = false,
  }) async {
    final id = page == null || duplicate
        ? 'editor-page-${shortid.generate()}'
        : page.id;
    final edited = await showDialog<EditorPageConfig>(
      context: context,
      builder: (_) => _PageDetails(
        routing: widget.routing,
        catalog: _catalog,
        originalId: duplicate ? null : page?.id,
        page: EditorPageConfig(
          id: id,
          name: page == null
              ? 'Nouvelle page'
              : duplicate
              ? '${page.name} (copie)'
              : page.name,
          path: page == null
              ? '/nouvelle-page'
              : duplicate
              ? '/copie${page.path}'
              : page.path,
          defaultParameters: page?.defaultParameters ?? const {},
        ),
      ),
    );
    return edited;
  }

  Future<void> _add() async {
    final page = await _details();
    if (page == null || !mounted) return;
    _catalogChanged(_catalog.copyWith(pages: [..._catalog.pages, page]));
  }

  Future<void> _edit(EditorPageConfig page) async {
    final result = await _details(page: page);
    if (result == null || !mounted) return;
    _catalogChanged(
      _catalog.copyWith(
        pages: [
          for (final entry in _catalog.pages)
            entry.id == page.id ? result : entry,
        ],
      ),
    );
  }

  Future<void> _duplicate(EditorPageConfig page) async {
    final result = await _details(page: page, duplicate: true);
    if (result == null || !mounted) return;
    try {
      final copied = EditorPageGraph.duplicate(
        appearance: _draft,
        registry: widget.registry,
        sourcePageId: page.id,
        targetPageId: result.id,
      );
      setState(() => _draft = copied);
      _catalogChanged(_catalog.copyWith(pages: [..._catalog.pages, result]));
    } on FormatException catch (error) {
      _report(error);
    } on StateError catch (error) {
      _report(error);
    }
  }

  Future<void> _delete(EditorPageConfig page) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la page ?'),
        content: Text(
          'Supprimer « ${page.name} » et sa conception ? '
          'Cette modification ne sera enregistrée qu’avec Appliquer.',
        ),
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
    try {
      final removed = EditorPageGraph.removal(
        appearance: _draft,
        registry: widget.registry,
        pageId: page.id,
      );
      setState(() {
        _draft = removed.appearance;
        _notice = removed.limitations.isEmpty
            ? null
            : 'Suppression préparée. Certaines données de composants personnalisés '
                  'ont été conservées car leur propriété n’est pas déclarée.';
      });
      _catalogChanged(
        _catalog.copyWith(
          pages: _catalog.pages.where((entry) => entry.id != page.id).toList(),
          clearHomePage: _catalog.homePageId == page.id,
        ),
      );
    } on FormatException catch (error) {
      _report(error);
    } on StateError catch (error) {
      _report(error);
    }
  }

  void _move(int index, int delta) {
    final pages = [..._catalog.pages];
    final page = pages.removeAt(index);
    pages.insert(index + delta, page);
    _catalogChanged(_catalog.copyWith(pages: pages));
  }

  Future<Map<String, String>?> _parameters({
    required String path,
    required List<String> keys,
    Map<String, String> defaults = const {},
    required String Function(Map<String, String>) resolve,
  }) async {
    if (keys.isEmpty) return {};
    return showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _RouteParameters(
        path: path,
        keys: keys,
        defaults: defaults,
        resolve: resolve,
      ),
    );
  }

  Future<void> _home(EditorPageConfig page) async {
    if (_catalog.homePageId == page.id) {
      _catalogChanged(_catalog.copyWith(clearHomePage: true));
      return;
    }
    final parameters = await _parameters(
      path: page.path,
      keys: widget.routing.parametersOf(page),
      defaults: page.defaultParameters,
      resolve: (values) => widget.routing.locationFor(page, values),
    );
    if (parameters == null || !mounted) return;
    _catalogChanged(
      _catalog.copyWith(
        homePageId: page.id,
        pages: [
          for (final entry in _catalog.pages)
            entry.id == page.id
                ? page.copyWith(defaultParameters: parameters)
                : entry,
        ],
      ),
    );
  }

  bool _apply() {
    if (!identical(widget.appearance.value, _base)) {
      _report(
        const FormatException(
          'Les dispositions ont changé ailleurs. Rechargez le brouillon avant de continuer.',
        ),
      );
      return false;
    }
    try {
      widget.routing.validate(_catalog);
      if (_dirty) {
        final history = EditorHistoryScope.controllerOf(context);
        history?.beginTransaction();
        try {
          widget.appearance.value = _draft;
        } finally {
          history?.commitTransaction();
        }
      }
      return true;
    } on FormatException catch (error) {
      _report(error);
      return false;
    } on StateError catch (error) {
      _report(error);
      return false;
    }
  }

  Future<void> _open(EditorPageConfig page) async {
    try {
      final parameters = await _parameters(
        path: page.path,
        keys: widget.routing.parametersOf(page),
        defaults: page.defaultParameters,
        resolve: (values) => widget.routing.locationFor(page, values),
      );
      if (parameters == null || !mounted) return;
      await _openLocation(widget.routing.locationFor(page, parameters));
    } on FormatException catch (error) {
      _report(error);
    }
  }

  Future<void> _openCoded(EditorCodedRoute route) async {
    try {
      final parameters = await _parameters(
        path: route.path,
        keys: route.parameters,
        resolve: (values) =>
            widget.routing.locationForCodedRoute(route, values),
      );
      if (parameters == null || !mounted) return;
      await _openLocation(
        widget.routing.locationForCodedRoute(route, parameters),
      );
    } on FormatException catch (error) {
      _report(error);
    }
  }

  Future<void> _openLocation(String location) async {
    if (_dirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Appliquer avant d’ouvrir ?'),
          content: const Text(
            'Le brouillon doit être enregistré avant de naviguer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Appliquer et ouvrir'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      if (_apply() && mounted) Navigator.pop(context, location);
    } on FormatException catch (error) {
      _report(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final codedRoutes = widget.routing.codedRoutes;
    final editorPagesEnd = _catalog.pages.length + 1;
    final codedRoutesStart = editorPagesEnd + 1;
    return AlertDialog(
      key: const ValueKey('editor-pages-manager'),
      constraints: const BoxConstraints(maxWidth: 850),
      content: SizedBox(
        width: 760,
        height: math.min(
          560,
          math.max(160, MediaQuery.sizeOf(context).height - 220),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EditorDialogHeader(
              label: 'Gérer les pages',
              actions: [
                IconButton(
                  key: const ValueKey('editor-pages-add'),
                  tooltip: 'Ajouter une page',
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount:
                    editorPagesEnd +
                    (codedRoutes.isEmpty ? 0 : codedRoutes.length + 1),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Pages configurables créées dans l’éditeur.',
                        ),
                        const SizedBox(height: 8),
                        if (_notice != null) Text(_notice!),
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _base = widget.appearance.value;
                              _draft = _base;
                              _error = null;
                              _notice = null;
                            }),
                            child: const Text('Recharger le brouillon'),
                          ),
                        ],
                        if (_catalog.pages.isEmpty)
                          const Text(
                            'Aucune page créée. Utilisez + pour ajouter une page.',
                          ),
                      ],
                    );
                  }
                  if (index == editorPagesEnd) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(8, 16, 8, 4),
                      child: Text(
                        'Pages définies dans le code',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }
                  if (index >= codedRoutesStart) {
                    final route = codedRoutes[index - codedRoutesStart];
                    return Card(
                      key: ValueKey('editor-coded-route-${route.path}'),
                      child: ListTile(
                        title: Text(route.label),
                        subtitle: Text(route.path),
                        trailing: IconButton(
                          key: ValueKey(
                            'editor-coded-route-open-${route.path}',
                          ),
                          tooltip: 'Ouvrir',
                          onPressed: () => _openCoded(route),
                          icon: const Icon(Icons.open_in_new),
                        ),
                      ),
                    );
                  }
                  final pageIndex = index - 1;
                  final page = _catalog.pages[pageIndex];
                  return Card(
                    key: ValueKey('editor-page-row-${page.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            page.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(page.path),
                          Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Ouvrir',
                                onPressed: () => _open(page),
                                icon: const Icon(Icons.open_in_new),
                              ),
                              IconButton(
                                tooltip: 'Modifier',
                                onPressed: () => _edit(page),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Dupliquer',
                                onPressed: () => _duplicate(page),
                                icon: const Icon(Icons.copy_outlined),
                              ),
                              IconButton(
                                tooltip: 'Page d’accueil',
                                onPressed: () => _home(page),
                                isSelected: _catalog.homePageId == page.id,
                                icon: const Icon(Icons.home_outlined),
                                selectedIcon: const Icon(Icons.home),
                              ),
                              IconButton(
                                tooltip: 'Monter',
                                onPressed: pageIndex == 0
                                    ? null
                                    : () => _move(pageIndex, -1),
                                icon: const Icon(Icons.arrow_upward),
                              ),
                              IconButton(
                                tooltip: 'Descendre',
                                onPressed:
                                    pageIndex == _catalog.pages.length - 1
                                    ? null
                                    : () => _move(pageIndex, 1),
                                icon: const Icon(Icons.arrow_downward),
                              ),
                              IconButton(
                                tooltip: 'Supprimer',
                                onPressed: () => _delete(page),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (_apply()) Navigator.pop(context);
          },
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}

class _PageDetails extends StatefulWidget {
  const _PageDetails({
    required this.page,
    required this.routing,
    required this.catalog,
    this.originalId,
  });
  final EditorPageConfig page;
  final EditorPageRouter routing;
  final EditorPageCatalog catalog;
  final String? originalId;
  @override
  State<_PageDetails> createState() => _PageDetailsState();
}

class _PageDetailsState extends State<_PageDetails> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.page.name);
  late final _path = TextEditingController(text: widget.page.path);
  final Map<String, TextEditingController> _parameters = {};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    for (final field in _parameters.values) {
      field.dispose();
    }
    super.dispose();
  }

  EditorPageConfig _page() => EditorPageConfig(
    id: widget.page.id,
    name: _name.text.trim(),
    path: _path.text.trim(),
    defaultParameters: {
      for (final entry in _parameters.entries)
        if (entry.value.text.isNotEmpty) entry.key: entry.value.text,
    },
  );

  @override
  Widget build(BuildContext context) {
    List<String> keys = [];
    String? pathError;
    try {
      keys = widget.routing.parametersOf(
        EditorPageConfig(id: widget.page.id, name: 'Page', path: _path.text),
      );
    } on FormatException catch (error) {
      pathError = error.message;
    } on ArgumentError catch (error) {
      pathError = error.message?.toString() ?? 'Chemin invalide.';
    }
    for (final key in keys) {
      _parameters.putIfAbsent(
        key,
        () => TextEditingController(
          text: widget.page.defaultParameters[key] ?? '',
        ),
      );
    }
    return AlertDialog(
      title: Text(
        widget.originalId == null ? 'Nouvelle page' : 'Modifier la page',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('editor-page-name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Nom requis.' : null,
                ),
                TextFormField(
                  key: const ValueKey('editor-page-path'),
                  controller: _path,
                  decoration: const InputDecoration(
                    labelText: 'Chemin URL',
                    hintText: '/clients/:id',
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  validator: (value) =>
                      (value ?? '').isEmpty ? 'Chemin requis.' : null,
                ),
                for (final key in keys)
                  TextFormField(
                    controller: _parameters[key],
                    decoration: InputDecoration(
                      labelText: widget.catalog.homePageId == widget.page.id
                          ? '$key (valeur d’accueil requise)'
                          : '$key (valeur d’accueil optionnelle)',
                    ),
                  ),
                if (pathError != null)
                  Text(
                    pathError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_error != null && _error != pathError)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            try {
              final page = _page().copyWith(
                defaultParameters: {
                  for (final key in keys)
                    if (_parameters[key]!.text.isNotEmpty)
                      key: _parameters[key]!.text,
                },
              );
              widget.routing.validate(
                widget.catalog.copyWith(
                  pages: [
                    for (final entry in widget.catalog.pages)
                      if (entry.id != widget.originalId) entry,
                    page,
                  ],
                ),
              );
              Navigator.pop(context, page);
            } on FormatException catch (error) {
              setState(() => _error = error.message);
            } on ArgumentError catch (error) {
              setState(
                () => _error = error.message?.toString() ?? 'Page invalide.',
              );
            }
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}

class _RouteParameters extends StatefulWidget {
  const _RouteParameters({
    required this.path,
    required this.keys,
    required this.defaults,
    required this.resolve,
  });

  final String path;
  final List<String> keys;
  final Map<String, String> defaults;
  final String Function(Map<String, String>) resolve;

  @override
  State<_RouteParameters> createState() => _RouteParametersState();
}

class _RouteParametersState extends State<_RouteParameters> {
  late final _fields = {
    for (final key in widget.keys)
      key: TextEditingController(text: widget.defaults[key] ?? ''),
  };
  String? _error;
  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Paramètres de la page'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.path),
            for (final entry in _fields.entries)
              TextField(
                controller: entry.value,
                decoration: InputDecoration(labelText: entry.key),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          final values = {
            for (final entry in _fields.entries) entry.key: entry.value.text,
          };
          try {
            widget.resolve(values);
            Navigator.pop(context, values);
          } on FormatException catch (error) {
            setState(() => _error = error.message);
          }
        },
        child: const Text('Valider'),
      ),
    ],
  );
}
