/// Boîte de dialogue de gestion du catalogue de pages ([EditorPageCatalog])
/// et des mises en page partagées ([EditorShellConfig]).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../../models/a4_page_config.dart';
import '../../../models/editor_page_config.dart';
import '../../../models/native_component_config.dart';
import '../../../models/registry.dart';
import '../../../models/responsive_layout_config.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../services/appearance/appearance_store.dart';
import '../../../services/pages/editor_page_graph.dart';
import '../../../services/pages/editor_page_router.dart';
import '../../../theme/appearance.dart';
import '../dialogs/editor_dialog_header.dart';
import '../history/editor_history.dart';

double _dialogContentWidth(BuildContext context, double preferred) =>
    math.min(preferred, math.max(0.0, MediaQuery.sizeOf(context).width - 80));

/// Ouvre la boîte de dialogue permettant de gérer les mises en page partagées
/// (Shells) et les pages routées du catalogue.
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
  routing.openLocation(location);
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

  Future<void> _ensurePageLoaded(String pageId) async {
    final notifier = widget.appearance;
    if (notifier is! PersistentAppearanceController) return;
    final before = notifier.value;
    await notifier.ensurePageLoaded(pageId);
    final after = notifier.value;
    if (identical(before, after) || !mounted) return;
    final slice = EditorPageAppearanceSlice(
      styles: {
        for (final entry in after.styles.entries)
          if (!before.styles.containsKey(entry.key)) entry.key: entry.value,
      },
      components: {
        for (final entry in after.components.entries)
          if (!before.components.containsKey(entry.key)) entry.key: entry.value,
      },
      behaviors: {
        for (final entry in after.behaviors.entries)
          if (!before.behaviors.containsKey(entry.key)) entry.key: entry.value,
      },
      usages: {
        for (final entry in after.usages.entries)
          if (!before.usages.containsKey(entry.key)) entry.key: entry.value,
      },
    );
    setState(() {
      final wasDirty = _dirty;
      _base = after;
      _draft = wasDirty ? slice.mergeInto(_draft) : after;
    });
  }

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
          pageType: page?.pageType ?? EditorPageType.standard,
          shellId: page?.shellId,
          modalWidth: page?.modalWidth,
          modalHeight: page?.modalHeight,
          showCloseButton: page?.showCloseButton ?? true,
          layoutOverride: page?.layoutOverride,
          defaultParameters: page?.defaultParameters ?? const {},
        ),
      ),
    );
    return edited;
  }

  Future<void> _addShell() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _ShellNameDialog(
        title: 'Nouvelle mise en page (Shell)',
        initialName: _catalog.shells.isEmpty
            ? 'Navigation principale'
            : 'Nouvelle mise en page',
      ),
    );
    if (name == null || !mounted) return;
    var id = 'shell-${shortid.generate()}';
    while (_catalog.shellById(id) != null ||
        _catalog.pages.any((page) => page.id == id) ||
        _draft.components.containsKey(id)) {
      id = 'shell-${shortid.generate()}';
    }
    final shell = EditorShellConfig(id: id, name: name);
    final scaffold = ScaffoldPageConfig.fromNative(
      NativeComponentConfig(
        regions: {
          ScaffoldPageRegion.appBar.name: true,
          ScaffoldPageRegion.sidebarStart.name: true,
          ScaffoldPageRegion.body.name: true,
        },
        placements: {
          ScaffoldPageRegion.body.name: const [EditorPageGraph.outletSlotId],
        },
        slotTypes: const {
          EditorPageGraph.outletSlotId: EditorPageGraph.outletSlotId,
        },
        slotLabels: const {EditorPageGraph.outletSlotId: 'Contenu de la page'},
      ),
    );
    setState(() {
      _draft = _draft
          .withComponent(shell.id, scaffold)
          .copyWith(
            pageCatalog: _catalog.copyWith(shells: [..._catalog.shells, shell]),
          );
      _error = null;
      _notice = null;
    });
  }

  Future<void> _renameShell(EditorShellConfig shell) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _ShellNameDialog(
        title: 'Renommer la mise en page',
        initialName: shell.name,
      ),
    );
    if (name == null || !mounted || name == shell.name) return;
    _catalogChanged(
      _catalog.copyWith(
        shells: [
          for (final entry in _catalog.shells)
            entry.id == shell.id ? entry.copyWith(name: name) : entry,
        ],
      ),
    );
  }

  void _toggleRootShell(EditorShellConfig shell) {
    if (_catalog.rootShellId == shell.id) {
      _catalogChanged(_catalog.copyWith(clearRootShellId: true));
    } else {
      _catalogChanged(_catalog.copyWith(rootShellId: shell.id));
    }
  }

  Future<void> _deleteShell(EditorShellConfig shell) async {
    final attachedCount = _catalog.pages
        .where((page) => page.shellId == shell.id)
        .length;
    final isRoot = _catalog.rootShellId == shell.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la mise en page ?'),
        content: Text(
          attachedCount > 0
              ? 'Supprimer la mise en page « ${shell.name} » ? '
                    'Les $attachedCount page${attachedCount > 1 ? 's' : ''} '
                    'rattachée${attachedCount > 1 ? 's' : ''} deviendr${attachedCount > 1 ? 'ont' : 'a'} '
                    'autonome${attachedCount > 1 ? 's' : ''} (sans Shell partagé).'
                    '${isRoot ? ' La route hôte « / » sera également détachée.' : ''} '
                    'Cette modification ne sera enregistrée qu’avec Appliquer.'
              : 'Supprimer la mise en page « ${shell.name} » ? '
                    'Les éventuelles pages rattachées deviendront autonomes.'
                    '${isRoot ? ' La route hôte « / » sera détachée.' : ''} '
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
      for (final page in _catalog.pages) {
        await _ensurePageLoaded(page.id);
        if (!mounted) return;
      }
      final removed = EditorPageGraph.removeShell(
        appearance: _draft,
        registry: widget.registry,
        shellId: shell.id,
      );
      setState(() {
        _draft = removed.appearance;
        _error = null;
        _notice = removed.limitations.isEmpty
            ? 'Mise en page « ${shell.name} » supprimée (enregistrée lors de Appliquer).'
            : 'Suppression préparée. Certaines données de composants personnalisés '
                  'ont été conservées car leur propriété n’est pas déclarée.';
      });
    } on FormatException catch (error) {
      _report(error);
    } on StateError catch (error) {
      _report(error);
    }
  }

  Future<void> _detachPageFromShell(EditorPageConfig page) async {
    if (page.shellId == null) return;
    try {
      await _ensurePageLoaded(page.id);
      if (!mounted) return;
      final detached = EditorPageGraph.detachPageFromShell(
        appearance: _draft,
        registry: widget.registry,
        pageId: page.id,
      );
      setState(() {
        _draft = detached;
        _error = null;
        _notice =
            'La page « ${page.name} » est désormais détachée du Shell et '
            'possède sa propre copie dédiée de l’AppBar et du menu.';
      });
    } on FormatException catch (error) {
      _report(error);
    } on StateError catch (error) {
      _report(error);
    }
  }

  Future<void> _add() async {
    final page = await _details();
    if (page == null || !mounted) return;
    if (page.pageType == EditorPageType.a4Document) {
      _draft = _draft.withA4Page(page.id, A4PageConfig.initialForPage(page.id));
    }
    _catalogChanged(_catalog.copyWith(pages: [..._catalog.pages, page]));
  }

  Future<void> _edit(EditorPageConfig page) async {
    final result = await _details(page: page);
    if (result == null || !mounted) return;
    if (result.pageType.usesScaffold != page.pageType.usesScaffold) {
      await _ensurePageLoaded(page.id);
      if (!mounted) return;
      final removed = EditorPageGraph.removal(
        appearance: _draft,
        registry: widget.registry,
        pageId: page.id,
      );
      _draft = removed.appearance;
      if (result.pageType == EditorPageType.a4Document) {
        _draft = _draft.withA4Page(
          result.id,
          A4PageConfig.initialForPage(result.id),
        );
      }
    }
    _catalogChanged(
      _catalog.copyWith(
        clearHomePage:
            result.pageType.isModal && _catalog.homePageId == page.id,
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
      await _ensurePageLoaded(page.id);
      if (!mounted) return;
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
      await _ensurePageLoaded(page.id);
      if (!mounted) return;
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
    if (page.pageType.isModal) return;
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

  Widget _buildShellRow(BuildContext context, EditorShellConfig shell) {
    final attachedCount = _catalog.pages
        .where((page) => page.shellId == shell.id)
        .length;
    final isRootShell = _catalog.rootShellId == shell.id;
    return Card(
      key: ValueKey('editor-shell-row-${shell.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  shell.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Chip(
                  label: Text(
                    attachedCount == 0
                        ? '0 page'
                        : '$attachedCount page${attachedCount > 1 ? 's' : ''}',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                if (isRootShell)
                  Chip(
                    key: ValueKey('editor-shell-root-badge-${shell.id}'),
                    avatar: const Icon(Icons.home, size: 16),
                    label: const Text('Accueil hôte /'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              shell.id,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  key: ValueKey('editor-shell-rename-${shell.id}'),
                  tooltip: 'Renommer',
                  onPressed: () => _renameShell(shell),
                  icon: const Icon(Icons.drive_file_rename_outline),
                ),
                FilterChip(
                  key: ValueKey('editor-shell-root-${shell.id}'),
                  selected: isRootShell,
                  label: const Text('Utiliser pour / (accueil hôte)'),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _toggleRootShell(shell),
                ),
                IconButton(
                  key: ValueKey('editor-shell-delete-${shell.id}'),
                  tooltip: 'Supprimer la mise en page',
                  onPressed: () => _deleteShell(shell),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageRow(BuildContext context, int pageIndex) {
    final page = _catalog.pages[pageIndex];
    final attachedShell = _catalog.shellById(page.shellId);
    final showAutonomeBadge = page.shellId == null && _catalog.hasShells;
    final hasExtraChips =
        attachedShell != null ||
        showAutonomeBadge ||
        (page.layoutOverride != null && !page.layoutOverride!.isEmpty);
    return Card(
      key: ValueKey('editor-page-row-${page.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    page.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(page.pageType.label),
                  avatar: Icon(page.pageType.icon, size: 16),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(page.path),
            if (hasExtraChips) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (attachedShell != null)
                    Chip(
                      key: ValueKey('editor-page-shell-badge-${page.id}'),
                      avatar: const Icon(Icons.dashboard_outlined, size: 16),
                      label: Text(attachedShell.name),
                      visualDensity: VisualDensity.compact,
                    )
                  else if (showAutonomeBadge)
                    Chip(
                      key: ValueKey('editor-page-shell-badge-${page.id}'),
                      label: const Text('Autonome'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (page.layoutOverride case final override?
                      when !override.isEmpty)
                    Chip(
                      label: Text(
                        override.containerMode == PageContainerMode.fullPage
                            ? 'Pleine page'
                            : 'Conteneur ${(override.maxWidth ?? ResponsiveLayoutConfig.defaultMaxWidth).round()}px',
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
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
                  tooltip: page.pageType.isModal
                      ? 'Une page modale ne peut pas être page d’accueil'
                      : 'Page d’accueil',
                  onPressed: page.pageType.isModal ? null : () => _home(page),
                  isSelected:
                      !page.pageType.isModal && _catalog.homePageId == page.id,
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                ),
                if (page.shellId != null)
                  IconButton(
                    key: ValueKey('page-detach-shell-${page.id}'),
                    tooltip:
                        'Détacher du Shell (copier dans un Scaffold dédié)',
                    onPressed: () => _detachPageFromShell(page),
                    icon: const Icon(Icons.link_off_outlined),
                  ),
                IconButton(
                  tooltip: 'Monter',
                  onPressed: pageIndex == 0 ? null : () => _move(pageIndex, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Descendre',
                  onPressed: pageIndex == _catalog.pages.length - 1
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
  }

  Widget _buildShellsHeader(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 4,
    children: [
      const Text(
        'Mises en page partagées (Shells)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      TextButton(
        key: const ValueKey('page-manager-add-shell'),
        onPressed: _addShell,
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        child: const Text('+ Nouvelle mise en page'),
      ),
    ],
  );

  List<Widget> _buildShellItems(BuildContext context) => [
    _buildShellsHeader(context),
    if (_catalog.shells.isEmpty)
      Text(
        'Aucune mise en page partagée.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      )
    else
      for (final shell in _catalog.shells) _buildShellRow(context, shell),
  ];

  List<Widget> _buildPageAndCodedItems(
    BuildContext context,
    List<EditorCodedRoute> codedRoutes,
  ) => [
    const Text('Pages configurables créées dans l’éditeur.'),
    const SizedBox(height: 8),
    if (_catalog.pages.isEmpty)
      const Text('Aucune page créée. Utilisez + pour ajouter une page.')
    else
      for (var i = 0; i < _catalog.pages.length; i++) _buildPageRow(context, i),
    if (codedRoutes.isNotEmpty) ...[
      const Padding(
        padding: EdgeInsets.fromLTRB(8, 16, 8, 4),
        child: Text(
          'Pages définies dans le code',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      for (final route in codedRoutes)
        Card(
          key: ValueKey('editor-coded-route-${route.path}'),
          child: ListTile(
            title: Text(route.label),
            subtitle: Text(route.path),
            trailing: IconButton(
              key: ValueKey('editor-coded-route-open-${route.path}'),
              tooltip: 'Ouvrir',
              onPressed: () => _openCoded(route),
              icon: const Icon(Icons.open_in_new),
            ),
          ),
        ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final codedRoutes = widget.routing.codedRoutes;
    return AlertDialog(
      key: const ValueKey('editor-pages-manager'),
      constraints: const BoxConstraints(maxWidth: 850),
      content: SizedBox(
        width: _dialogContentWidth(context, 760),
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
            if (_notice != null) ...[Text(_notice!), const SizedBox(height: 6)],
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _base = widget.appearance.value;
                    _draft = _base;
                    _error = null;
                    _notice = null;
                  }),
                  child: const Text('Recharger le brouillon'),
                ),
              ),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 600) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: ListView(
                            children: _buildPageAndCodedItems(
                              context,
                              codedRoutes,
                            ),
                          ),
                        ),
                        const VerticalDivider(width: 24),
                        Expanded(
                          flex: 2,
                          child: ListView(children: _buildShellItems(context)),
                        ),
                      ],
                    );
                  }
                  return ListView(
                    children: [
                      ..._buildShellItems(context),
                      const Divider(height: 16),
                      ..._buildPageAndCodedItems(context, codedRoutes),
                    ],
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
  late final _modalWidth = TextEditingController(
    text: widget.page.modalWidth?.round().toString() ?? '',
  );
  late final _modalHeight = TextEditingController(
    text: widget.page.modalHeight?.round().toString() ?? '',
  );
  late final _overrideMaxWidth = TextEditingController(
    text: widget.page.layoutOverride?.maxWidth?.round().toString() ?? '',
  );
  late final _overrideMobileGutter = TextEditingController(
    text: widget.page.layoutOverride?.mobileGutter?.round().toString() ?? '',
  );
  late final _overrideDesktopGutter = TextEditingController(
    text: widget.page.layoutOverride?.desktopGutter?.round().toString() ?? '',
  );
  late EditorPageType _pageType = widget.page.pageType;
  late String? _shellId = widget.page.pageType.isModal
      ? null
      : widget.catalog.shellById(widget.page.shellId)?.id;
  late bool _showCloseButton = widget.page.showCloseButton;
  late PageContainerMode? _overrideMode =
      widget.page.layoutOverride?.containerMode;
  final Map<String, TextEditingController> _parameters = {};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    _modalWidth.dispose();
    _modalHeight.dispose();
    _overrideMaxWidth.dispose();
    _overrideMobileGutter.dispose();
    _overrideDesktopGutter.dispose();
    for (final field in _parameters.values) {
      field.dispose();
    }
    super.dispose();
  }

  double? _parseOptionalDimension(
    TextEditingController controller, {
    String label = 'Dimension modale',
  }) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    if (parsed == null) {
      throw FormatException('$label invalide (nombre requis).');
    }
    return parsed;
  }

  ResponsiveLayoutOverride? _buildLayoutOverride() {
    if (_pageType != EditorPageType.standard) return null;
    final forceFull = _overrideMode == PageContainerMode.fullPage;
    final override = ResponsiveLayoutOverride(
      containerMode: _overrideMode,
      maxWidth: forceFull
          ? null
          : _parseOptionalDimension(
              _overrideMaxWidth,
              label: 'Largeur maximale',
            ),
      mobileGutter: forceFull
          ? null
          : _parseOptionalDimension(
              _overrideMobileGutter,
              label: 'Gutter mobile',
            ),
      desktopGutter: forceFull
          ? null
          : _parseOptionalDimension(
              _overrideDesktopGutter,
              label: 'Gutter desktop',
            ),
    );
    return override.isEmpty ? null : override;
  }

  EditorPageConfig _page() {
    final showWidth =
        _pageType == EditorPageType.dialog ||
        _pageType == EditorPageType.sideSheet;
    final showHeight =
        _pageType == EditorPageType.dialog ||
        _pageType == EditorPageType.bottomSheet;
    return EditorPageConfig(
      id: widget.page.id,
      name: _name.text.trim(),
      path: _path.text.trim(),
      pageType: _pageType,
      shellId: _pageType.isModal ? null : _shellId,
      modalWidth: showWidth ? _parseOptionalDimension(_modalWidth) : null,
      modalHeight: showHeight ? _parseOptionalDimension(_modalHeight) : null,
      showCloseButton: _pageType.isModal ? _showCloseButton : true,
      layoutOverride: _buildLayoutOverride(),
      defaultParameters: {
        for (final entry in _parameters.entries)
          if (entry.value.text.isNotEmpty) entry.key: entry.value.text,
      },
    );
  }

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
        width: _dialogContentWidth(context, 440),
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
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Type de page',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  key: const ValueKey('editor-page-type'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in EditorPageType.values)
                      ChoiceChip(
                        key: ValueKey('editor-page-type-${type.name}'),
                        avatar: Icon(type.icon, size: 18),
                        label: Text(type.label),
                        tooltip: type.description,
                        selected: _pageType == type,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _pageType = type;
                              if (type.isModal) {
                                _shellId = null;
                              }
                            });
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _pageType.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (!_pageType.isModal) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    key: const ValueKey('page-details-shell-dropdown'),
                    initialValue: _shellId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Mise en page (Shell)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'Aucune (page autonome avec son propre Scaffold)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final shell in widget.catalog.shells)
                        DropdownMenuItem<String?>(
                          value: shell.id,
                          child: Text(
                            shell.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _shellId = value;
                      _error = null;
                    }),
                  ),
                ],
                if (widget.originalId != null &&
                    widget.catalog.homePageId == widget.originalId &&
                    _pageType.isModal) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Une page modale ne peut pas être page d’accueil : '
                    'le statut de page d’accueil sera retiré.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (widget.originalId != null &&
                    _pageType.usesScaffold !=
                        widget.page.pageType.usesScaffold) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Attention : passer entre Document A4 et un type basé sur '
                    'Scaffold réinitialise la structure racine de la page.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_pageType.isModal) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_pageType == EditorPageType.dialog ||
                          _pageType == EditorPageType.sideSheet)
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('editor-page-modal-width'),
                            controller: _modalWidth,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Largeur (px)',
                              hintText: _pageType == EditorPageType.dialog
                                  ? '640'
                                  : '420',
                            ),
                          ),
                        ),
                      if (_pageType == EditorPageType.dialog)
                        const SizedBox(width: 12),
                      if (_pageType == EditorPageType.dialog ||
                          _pageType == EditorPageType.bottomSheet)
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('editor-page-modal-height'),
                            controller: _modalHeight,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Hauteur (px)',
                              hintText: _pageType == EditorPageType.dialog
                                  ? '520'
                                  : 'Auto',
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('editor-page-modal-close-button'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Bouton fermer par défaut'),
                    subtitle: const Text(
                      'Affiche un bouton × en haut à droite',
                    ),
                    value: _showCloseButton,
                    onChanged: (value) =>
                        setState(() => _showCloseButton = value),
                  ),
                ],
                if (_pageType == EditorPageType.standard) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Conteneur & Gutters (body)',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    key: const ValueKey('editor-page-container-mode'),
                    segments: const [
                      ButtonSegment(value: 'inherit', label: Text('Hériter')),
                      ButtonSegment(
                        value: 'fullPage',
                        label: Text('Pleine page'),
                      ),
                      ButtonSegment(
                        value: 'constrained',
                        label: Text('Centré'),
                      ),
                    ],
                    selected: {_overrideMode?.name ?? 'inherit'},
                    onSelectionChanged: (modes) => setState(() {
                      final selected = modes.single;
                      _overrideMode = selected == 'inherit'
                          ? null
                          : PageContainerMode.fromJson(selected);
                      _error = null;
                    }),
                  ),
                  if (_overrideMode != PageContainerMode.fullPage) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('editor-page-max-width'),
                            controller: _overrideMaxWidth,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max-width (px)',
                              hintText: '1440',
                            ),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('editor-page-gutter-mobile'),
                            controller: _overrideMobileGutter,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Gutter mobile',
                              hintText: '24',
                            ),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('editor-page-gutter-desktop'),
                            controller: _overrideDesktopGutter,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Gutter desktop',
                              hintText: '32',
                            ),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
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
                  clearHomePage:
                      page.pageType.isModal &&
                      widget.catalog.homePageId == widget.originalId,
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
      width: _dialogContentWidth(context, 400),
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

class _ShellNameDialog extends StatefulWidget {
  const _ShellNameDialog({required this.title, required this.initialName});

  final String title;
  final String initialName;

  @override
  State<_ShellNameDialog> createState() => _ShellNameDialogState();
}

class _ShellNameDialogState extends State<_ShellNameDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: _dialogContentWidth(context, 380),
      child: Form(
        key: _form,
        child: TextFormField(
          key: const ValueKey('page-manager-shell-name'),
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom de la mise en page',
            hintText: 'Ex. Navigation principale',
          ),
          onFieldSubmitted: (_) => _submit(),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Nom requis.' : null,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Valider')),
    ],
  );
}
