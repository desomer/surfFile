/// Rendu et edition locale d'un export d'apparence, sans persistance implicite.
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/scaffold_page_config.dart';
import '../../models/super_renderer_config.dart';
import '../../services/appearance/appearance_codec.dart';
import '../../services/appearance/appearance_store.dart';
import '../../services/appearance/appearance_transfer.dart';
import '../../services/events/super_event_bus.dart';
import '../../services/pages/editor_page_graph.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../super_app.dart';
import '../../super_page.dart';
import '../../theme/appearance.dart';
import '../appearance/appearance_transfer_dialog.dart';
import '../editing/components/super_renderer_editor.dart';
import '../editing/dialogs/editor_dialog.dart';
import '../editing/history/editor_history.dart';
import '../editing/slots/editor_slot.dart';
import '../surfaces/styled_surface.dart';
import 'super_component.dart';

/// Importe une apparence et rend son contenu dans un contexte runtime isole.
///
/// Les editions sont locales et transmises par [onChanged], jamais sauvegardees
/// dans la source initiale ou l'apparence hote. Le registre fourni sert seulement
/// de catalogue ; ses controleurs ne sont pas reutilises.
class SuperRenderer extends SuperStatefulComponent<SuperRendererConfig> {
  const SuperRenderer({
    this.id = 'renderer',
    this.config = const SuperRendererConfig(),
    this.source,
    this.rootId,
    this.registry,
    this.codec,
    this.repositoryStore,
    this.eventBus,
    this.editMode,
    this.onChanged,
    super.behaviours,
    super.key,
  });

  @override
  final String id;
  @override
  final SuperRendererConfig config;

  /// Raccourci pour remplacer le JSON initial de [config].
  final String? source;

  /// Page ou composant initial ; null conserve la racine de [config].
  final String? rootId;

  /// Catalogue externe, jamais lie aux controleurs du document local.
  final Registry? registry;

  /// Codec du document importe ; herite du codec hote si absent.
  final AppearanceCodec? codec;

  /// Donnees externes possedees par l'hote, heritees si absentes.
  final JsonRepositoryStore? repositoryStore;

  /// Bus externe possede par l'hote, herite si absent.
  final SuperEventBus? eventBus;

  /// Force le mode edition ; null herite du contexte, sinon desactive.
  final bool? editMode;

  /// Document courant reimportable, emis apres import ou edition locale.
  final ValueChanged<String>? onChanged;

  @override
  State<SuperRenderer> createState() => _SuperRendererState();
}

class _SuperRendererState extends State<SuperRenderer> {
  late final _local = ValueNotifier(widget.config);

  @override
  void didUpdateWidget(SuperRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) _local.value = widget.config;
  }

  @override
  void dispose() {
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = SuperApp.maybeOf(context);
    final configuration =
        app?.registry?.componentController<SuperRendererConfig>(
          widget.id,
          fallback: widget.config,
        ) ??
        _local;
    return ValueListenableBuilder<SuperRendererConfig>(
      valueListenable: configuration,
      builder: (context, value, _) => EditorSlot(
        id: widget.id,
        label: 'SuperRenderer',
        menuType: 'SuperRenderer',
        eventComponentType: 'renderer',
        behaviors: widget.behaviours,
        onEdit: () async {
          final next = await showSuperRendererEditor(context, value);
          if (next != null && mounted) configuration.value = next;
        },
        child: _RendererDocument(
          config: value.copyWith(source: widget.source, rootId: widget.rootId),
          catalog: widget.registry ?? app?.registry,
          codec: widget.codec ?? AppearanceServicesScope.codecOf(context),
          repositoryStore:
              widget.repositoryStore ?? JsonRepositoryScope.maybeOf(context),
          eventBus: widget.eventBus ?? app?.eventBus,
          editMode:
              widget.editMode ??
              StyleEditScope.controllerOf(context)?.value ??
              false,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

class _RendererDocument extends StatefulWidget {
  const _RendererDocument({
    required this.config,
    required this.catalog,
    required this.codec,
    required this.repositoryStore,
    required this.eventBus,
    required this.editMode,
    required this.onChanged,
  });

  final SuperRendererConfig config;
  final Registry? catalog;
  final AppearanceCodec codec;
  final JsonRepositoryStore? repositoryStore;
  final SuperEventBus? eventBus;
  final bool editMode;
  final ValueChanged<String>? onChanged;

  @override
  State<_RendererDocument> createState() => _RendererDocumentState();
}

class _RendererDocumentState extends State<_RendererDocument> {
  late final _appearance = ValueNotifier<Appearance>(widget.codec.defaults);
  late final _editMode = ValueNotifier(widget.editMode);
  late final _history = EditorHistoryController(
    appearance: _appearance,
    editMode: _editMode,
  );
  late Registry _registry;
  late GoRouter _router;
  late _LocalCodec _codec;
  String? _error;
  bool _hasDocument = false;
  bool _notifyScheduled = false;
  bool _replacing = false;
  final _rootSelection = ValueNotifier<String?>(null);
  final _wrappers = <String, (String, ScaffoldPageConfig)>{};

  @override
  void initState() {
    super.initState();
    _createRuntime();
    _appearance.addListener(_changed);
    _loadSource();
  }

  void _createRuntime() {
    _codec = _LocalCodec(widget.codec);
    _registry = Registry()..bootstrap();
    if (widget.catalog case final catalog?) {
      _registry.registry.addAll(catalog.registry);
      _registry.components.addAll(catalog.components);
    }
    _registry.bindAppearance(_appearance);
    _router = _createRouter(_appearance.value);
  }

  GoRouter _createRouter(Appearance appearance) => GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => ValueListenableBuilder<String?>(
          valueListenable: _rootSelection,
          builder: (_, selected, _) => _root(selected ?? widget.config.rootId),
        ),
      ),
      for (final page in appearance.pageCatalog.pages)
        if (page.path != '/')
          GoRoute(path: page.path, builder: (_, _) => _root(page.id)),
    ],
    errorBuilder: (_, state) => Material(
      child: Center(child: Text('Navigation impossible : ${state.error}')),
    ),
  );

  void _loadSource() {
    if (widget.config.source.trim().isEmpty) {
      _replacing = true;
      _appearance.value = _codec.defaults;
      _replacing = false;
      _hasDocument = false;
      _error = null;
      _history.clear();
      _wrappers.clear();
      return;
    }
    try {
      widget.config.validate();
      final next = AppearanceTransfer.import(
        _codec.defaults,
        widget.config.source,
        {...TransferGroup.values},
        codec: _codec,
      );
      _validateRoot(next, widget.config.rootId);
      _replace(next);
    } on FormatException catch (error) {
      _error = error.message;
    }
  }

  String _rootId(Appearance appearance, String? requested) {
    if (requested != null) return requested;
    if (appearance.pageCatalog.homePageId case final home?) return home;
    if (appearance.components.containsKey('root')) return 'root';
    if (appearance.pageCatalog.pages.length == 1) {
      return appearance.pageCatalog.pages.single.id;
    }
    if (appearance.components.length == 1) {
      return appearance.components.keys.single;
    }
    throw const FormatException(
      'Selectionnez une page ou un composant racine.',
    );
  }

  void _validateRoot(Appearance appearance, String? requested) {
    final id = _rootId(appearance, requested);
    if (!appearance.components.containsKey(id)) {
      throw FormatException('Racine introuvable : $id.');
    }
  }

  Widget _root(String? requested) => ValueListenableBuilder<Appearance>(
    valueListenable: _appearance,
    builder: (context, appearance, _) {
      try {
        final id = _rootId(appearance, requested);
        final config = appearance.components[id];
        final isPage =
            config is ScaffoldPageConfig ||
            appearance.pageCatalog.pages.any((page) => page.id == id) ||
            id == 'root';
        if (isPage) {
          return SuperPage(
            key: ValueKey(id),
            id: id,
            pageConfig: switch (config) {
              ScaffoldPageConfig() => config,
              NativeComponentConfig() => ScaffoldPageConfig.fromNative(config),
              _ => throw FormatException('Page invalide : $id.'),
            },
          );
        }
        final (pageId, pageConfig) = _wrappers.putIfAbsent(id, () {
          final fragment = EditorPageGraph.fragment(
            appearance: appearance,
            registry: _registry,
            componentId: id,
          );
          final pageId = fragment.pageCatalog.homePageId!;
          return (pageId, fragment.components[pageId]! as ScaffoldPageConfig);
        });
        return SuperPage(
          key: ValueKey((id, pageId)),
          id: pageId,
          pageConfig: pageConfig,
        );
      } on FormatException catch (error) {
        return Material(child: Center(child: Text(error.message)));
      }
    },
  );

  void _replace(Appearance appearance) {
    final router = _createRouter(appearance);
    final previous = _router;
    _replacing = true;
    _appearance.value = appearance;
    _replacing = false;
    _history.clear();
    _wrappers.clear();
    _rootSelection.value = null;
    _router = router;
    _hasDocument = true;
    _error = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  void _changed() {
    if (_replacing || _notifyScheduled) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!mounted) return;
      widget.onChanged?.call(
        AppearanceTransfer.export(
          _registry.appearanceSnapshot(_appearance.value),
          {...TransferGroup.values},
          codec: _codec,
        ),
      );
    });
  }

  Future<void> _import() async {
    final draft = ValueNotifier<Appearance>(_codec.defaults);
    var applied = false;
    void changed() => applied = true;
    draft.addListener(changed);
    try {
      await showEditorDialog<void>(
        context: context,
        builder: (_) => AppearanceTransferDialog(
          controller: draft,
          codec: _codec,
          allowExport: false,
        ),
      );
      if (!mounted || !applied) return;
      try {
        _validateRoot(draft.value, widget.config.rootId);
        setState(() => _replace(draft.value));
        _changed();
      } on FormatException catch (error) {
        setState(() => _error = error.message);
      }
    } finally {
      draft.removeListener(changed);
      draft.dispose();
    }
  }

  @override
  void didUpdateWidget(_RendererDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    _editMode.value = widget.editMode;
    if (oldWidget.catalog != widget.catalog ||
        oldWidget.codec != widget.codec) {
      final previous = _router;
      final previousRegistry = _registry;
      previousRegistry.unbindAppearance();
      _createRuntime();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous.dispose();
        previousRegistry.dispose();
      });
    }
    if (oldWidget.config.source != widget.config.source) {
      _loadSource();
    } else if (oldWidget.config.rootId != widget.config.rootId) {
      final previous = _router;
      _router = _createRouter(_appearance.value);
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _appearance.removeListener(_changed);
    _registry.dispose();
    _router.dispose();
    _history.dispose();
    _editMode.dispose();
    _appearance.dispose();
    _rootSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = SuperAppScope(
      app: SuperApp(
        router: _router,
        registry: _registry,
        repositoryStore: widget.repositoryStore,
        eventBus: widget.eventBus,
      ),
      child: AppearanceServicesScope(
        codec: _codec,
        child: AppearanceScope(
          controller: _appearance,
          child: StyleEditScope(
            controller: _editMode,
            child: EditorHistoryScope(
              controller: _history,
              child: EditorHistoryShortcut(
                editMode: _editMode,
                history: _history,
                child: Column(
                  children: [
                    if (widget.config.showImport)
                      Wrap(
                        alignment: WrapAlignment.end,
                        children: [
                          if (_hasDocument)
                            PopupMenuButton<String>(
                              key: const ValueKey('renderer-select-root'),
                              tooltip: 'Choisir la page ou le composant racine',
                              icon: const Icon(Icons.account_tree_outlined),
                              itemBuilder: (_) => [
                                for (final id
                                    in _appearance.value.components.keys)
                                  PopupMenuItem(value: id, child: Text(id)),
                              ],
                              onSelected: (id) {
                                _rootSelection.value = id;
                                _router.go('/');
                              },
                            ),
                          TextButton.icon(
                            key: const ValueKey('renderer-import'),
                            onPressed: _import,
                            icon: const Icon(Icons.download),
                            label: const Text('Importer une apparence'),
                          ),
                        ],
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        key: const ValueKey('renderer-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    Expanded(
                      child: _hasDocument
                          ? ValueListenableBuilder<Appearance>(
                              valueListenable: _appearance,
                              builder: (context, appearance, _) => Theme(
                                data: appearance.theme(
                                  switch (appearance.mode) {
                                    ThemeMode.dark => Brightness.dark,
                                    ThemeMode.light => Brightness.light,
                                    ThemeMode.system =>
                                      MediaQuery.platformBrightnessOf(context),
                                  },
                                ),
                                child: StyledSurface(
                                  style: appearance.backgroundStyle,
                                  fallbackColor: Theme.of(context)
                                      .colorScheme
                                      .surface,
                                  borderColor: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                  child: Router.withConfig(
                                    key: ObjectKey(_router),
                                    config: _router,
                                  ),
                                ),
                              ),
                            )
                          : const Center(
                              child: Text('Importez un JSON d\'apparence.'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.repositoryStore case final store?) {
      content = JsonRepositoryScope(store: store, child: content);
    }
    return content;
  }
}

// Le codec de l'hote reste responsable du format, pas de ses effets globaux.
class _LocalCodec extends AppearanceCodec {
  const _LocalCodec(this.delegate);
  final AppearanceCodec delegate;

  @override
  String get format => delegate.format;
  @override
  int get schemaVersion => delegate.schemaVersion;
  @override
  Set<String> get additionalKeys => delegate.additionalKeys;
  @override
  Appearance get defaults => delegate.defaults;
  @override
  Map<String, Object?> toJson(Appearance a) => delegate.toJson(a);
  @override
  Appearance fromJson(Map<String, dynamic> json) => delegate.fromJson(json);
  @override
  Appearance decode(String text) => delegate.decode(text);
  @override
  Appearance patchFromJson(Appearance current, Map<String, dynamic> patch) =>
      delegate.patchFromJson(current, patch);
  @override
  Map<String, Object?> normalizeTransfer(
    Map<String, dynamic> data,
    int version,
  ) => delegate.normalizeTransfer(data, version);
  @override
  Object? mergeTransferValue(
    String key,
    Object? current,
    Object? incoming,
    int version,
  ) => delegate.mergeTransferValue(key, current, incoming, version);
}
