/// Point d'entrée de l'application autonome `super_designer`.
///
/// Combine le moteur `super_container_layout` et le catalogue d'extensions
/// `super_container_extensions` (`SuperChart`, etc.) au sein d'un même [Registry].
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_extensions/super_container_extensions.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_designer/impl.dart';

import 'repository_schema_model.dart';
import 'yaml2jsonschemas_parser.dart';

export 'json_browser.dart';
export 'yaml2jsonschemas_parser.dart';

export 'package:super_container_extensions/super_container_extensions.dart';
export 'package:super_container_layout/super_container_layout.dart';

/// Crée et initialise un [Registry] contenant tous les composants du moteur
/// (`bootstrap`) ainsi que toutes les extensions (`registerAllExtensions`).
Registry createSuperDesignerRegistry({
  List<String> availableFontFamilies = Registry.defaultAvailableFontFamilies,
}) => Registry()
  ..bootstrap(availableFontFamilies: availableFontFamilies)
  ..registerAllExtensions(availableFontFamilies: availableFontFamilies);

/// Alias conservé pour la compatibilité avec le `main.dart` de `super_container_layout`.
typedef TestApp = SuperDesignerApp;

/// Lance l'application autonome `super_designer`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var envText = '';
  final sep = Platform.pathSeparator;
  final paths = [
    'env',
    '.env',
    ['packages', 'super_designer', 'env'].join(sep),
    ['packages', 'super_designer', '.env'].join(sep),
    ['packages', 'super_container_layout', 'env'].join(sep),
    ['packages', 'super_container_layout', '.env'].join(sep),
    ['..', 'super_container_layout', 'env'].join(sep),
    ['..', 'super_container_layout', '.env'].join(sep),
    ['..', 'super_designer', 'env'].join(sep),
    ['..', 'super_designer', '.env'].join(sep),
    ['..', 'env'].join(sep),
    ['..', '.env'].join(sep),
  ];
  for (final path in paths) {
    final file = File(path);
    if (await file.exists()) {
      envText = await file.readAsString();
      break;
    }
  }
  if (envText.isEmpty) {
    // Permet aussi de lancer l'application depuis un sous-dossier du monorepo.
    try {
      var dir = Directory.current;
      while (true) {
        for (final candidate in [
          'env',
          '.env',
          ['packages', 'super_designer', 'env'].join(sep),
          ['packages', 'super_container_layout', 'env'].join(sep),
        ]) {
          final file = File('${dir.path}$sep$candidate');
          if (await file.exists()) {
            envText = await file.readAsString();
            break;
          }
        }
        if (envText.isNotEmpty || dir.parent.path == dir.path) break;
        dir = dir.parent;
      }
    } catch (_) {}
  }
  final environmentKey = Platform.environment['GEMINI_API_KEY'];
  dotenv.loadFromString(
    envString: envText,
    isOptional: true,
    mergeWith: environmentKey == null
        ? const {}
        : {'GEMINI_API_KEY': environmentKey},
  );
  // Le point d'entrée de démonstration active la persistance par défaut.
  runApp(const SuperDesignerApp(persistRepository: true));
}

/// Widget racine de l'application de démonstration et d'édition `super_designer`,
/// donnant accès au moteur `super_container_layout` et à ses extensions.
class SuperDesignerApp extends StatefulWidget {
  const SuperDesignerApp({
    super.key,
    this.persistRepository = false,
    this.repositoryDirectory,
  });

  /// Active la restauration et l'enregistrement automatique du repository.
  final bool persistRepository;

  /// Dossier du store ; `null` utilise le dossier utilisateur par défaut.
  final Directory? repositoryDirectory;

  @override
  State<SuperDesignerApp> createState() => _SuperDesignerAppState();
}

class _SuperDesignerAppState extends State<SuperDesignerApp> {
  final _registry = createSuperDesignerRegistry();
  final _eventBus = SuperEventBus();
  late final StreamSubscription<SuperComponentEvent> _eventSubscription;

  static const _repositoryId = 'pan_model_repository';
  static const _eastSizeBinding = JsonTextBinding(
    repositoryId: _repositoryId,
    path: 'estSize',
  );
  static const _sourceBinding = JsonTextBinding(
    repositoryId: _repositoryId,
    path: 'source',
  );
  late final _repositoryStore = widget.repositoryDirectory == null
      ? JsonRepositoryStore.defaultStore()
      : JsonRepositoryStore(widget.repositoryDirectory!);

  late final _schemaModel = RepositorySchemaModel(Yaml2JsonSchemasParser());

  // L'initialisation est distincte de la validation, que des edits peuvent
  // ajouter à la file pendant une sauvegarde ou une fermeture.
  Future<void>? _repositoryInitialization;
  Future<void>? _validationQueue;
  AppLifecycleListener? _lifecycle;
  bool? _schemaModelReady;
  Object? _validationFailure;
  StackTrace? _validationFailureStack;

  /// Publie les mises à jour du schéma après un changement du repository.
  void _onRepositoryChanged(ChangeContext change) {
    final details = change.path.isEmpty
        ? '(document entier)'
        : '(${change.oldValue} -> ${change.newValue})';
    debugPrint(
      'Repository ${change.repositoryId}: ${change.path} changed by '
      '${change.componentId ?? 'unknown component'} '
      '$details',
    );
    if (change.path == 'source') {
      _queueValidation();
    } else if (change.path.isEmpty) {
      final previous = change.oldValue;
      final next = change.newValue;
      final sourceChanged =
          previous is Map &&
          next is Map &&
          previous['source'] != next['source'];
      _queueValidation(
        restoreModel: true,
        updateNodes: !change.isReload && sourceChanged,
      );
    }
  }

  /// Rend l'erreur visible à l'hôte et dans les liaisons de l'application.
  void _reportRepositoryFailure(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'super_designer',
      ),
    );
    _repositoryStore.reportBindingError('Erreur du repository : $error');
  }

  /// Sérialise la validation YAML pour éviter qu'un résultat ancien écrase le
  /// schéma correspondant à une source plus récente.
  void _queueValidation({bool restoreModel = false, bool updateNodes = true}) {
    _validationQueue = (_validationQueue ?? Future<void>.value())
        .then((_) async {
          if (!mounted) return;
          if (restoreModel || _schemaModelReady != true) {
            final nodes = await _repositoryStore.readArray(
              _repositoryId,
              'nodes',
            );
            if (!mounted) return;
            _schemaModel.restore(nodes);
            _schemaModelReady = true;
          }
          final source = await _repositoryStore.readAttribute(_sourceBinding);
          if (!mounted) return;
          await _validateYaml(source.value, updateNodes: updateNodes);
          _validationFailure = null;
          _validationFailureStack = null;
        })
        .catchError((Object error, StackTrace stack) {
          _validationFailure = error;
          _validationFailureStack = stack;
          _reportRepositoryFailure(error, stack);
        });
  }

  /// Charge d'abord le document sauvegardé, puis valide sa source YAML.
  Future<void> _initializePersistentRepository(
    RepositoryImpl repository,
  ) async {
    final restored = await _repositoryStore.registerPersistentRepository(
      repository,
    );
    if (!mounted) return;
    final nodes = await _repositoryStore.readArray(_repositoryId, 'nodes');
    if (!mounted) return;
    _schemaModel.restore(nodes);
    _schemaModelReady = true;
    final source = await _repositoryStore.readAttribute(_sourceBinding);
    if (!mounted) return;
    await _validateYaml(source.value, updateNodes: !restored);
  }

  /// Vérifie le YAML et patche les nœuds sans perdre leurs données éditées.
  Future<void> _validateYaml(Object? source, {bool updateNodes = true}) async {
    if (source is! String) {
      throw const FormatException('Le champ source doit être une chaîne.');
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      final previousNodes = await _repositoryStore.readArray(
        _repositoryId,
        'nodes',
      );
      if (!mounted) return;
      var message = '';
      List<Object?>? nodes;
      try {
        nodes = _schemaModel.patch(source, previousNodes);
      } on FormatException catch (error) {
        message = error.message;
      }
      final currentSource = await _repositoryStore.readAttribute(
        _sourceBinding,
      );
      if (!mounted || currentSource.value != source) return;
      const errorBinding = JsonTextBinding(
        repositoryId: _repositoryId,
        path: 'yamlError',
      );
      final current = await _repositoryStore.readAttribute(errorBinding);
      if (current.value != message) {
        await _repositoryStore.writeAttribute(
          errorBinding,
          message,
          expectedValue: current.value,
          componentId: 'yaml-validator',
        );
      }
      if (nodes == null || !updateNodes) return;
      try {
        await _repositoryStore.replaceArray(
          _repositoryId,
          'nodes',
          nodes,
          componentId: 'yaml-validator',
          expectedValues: {'source': source, 'nodes': previousNodes},
        );
        return;
      } on JsonRepositoryConflictException {
        if (attempt == 4) rethrow;
        final latestSource = await _repositoryStore.readAttribute(
          _sourceBinding,
        );
        if (!mounted || latestSource.value != source) return;
      }
    }
  }

  /// Déclare la page d'entrée de l'éditeur SuperDesigner.
  late final EditorPageRouter _pageRouting;
  GoRouter get _router => _pageRouting.router;

  @override
  void initState() {
    super.initState();
    if (widget.persistRepository) {
      // Annule la fermeture si des saisies ou leur sauvegarde échouent.
      _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    }
    _eventSubscription = _eventBus
        .on('node.click')
        .asyncMap((event) async {
          final current = await _repositoryStore.readAttribute(
            _eastSizeBinding,
          );
          final size = current.value;
          if (size is! num || !size.isFinite) {
            throw StateError('estSize doit etre une taille numerique finie.');
          }
          await _repositoryStore.writeAttribute(
            _eastSizeBinding,
            size == 0 ? '300' : '0',
            expectedValue: current.value,
            componentId: event.componentId,
          );
          return event;
        })
        .listen((event) {
          debugPrint(
            'Event ${event.eventId} from ${event.componentId} '
            '(${event.trigger}): ${event.data}',
          );
        });

    final repository = RepositoryImpl(
      id: _repositoryId,
      onChanged: _onRepositoryChanged,
      json: {
        'source': '',
        'estSize': 300,
        'yamlError': '',
        'nodes': <Object?>[],
      },
    );

    if (widget.persistRepository) {
      _repositoryInitialization = _initializePersistentRepository(repository);
    } else {
      _repositoryStore.registerRepository(repository);
      _repositoryInitialization = null;
      _queueValidation();
    }

    SuperDesignerRegistry(_registry).addRegistry();

    _pageRouting = EditorPageRouter(
      baseConfig: RoutingConfig(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => getRootWidget(_registry),
          ),
        ],
      ),
    );
  }

  /// Attend l'initialisation, les saisies et validations en attente avant
  /// d'enregistrer un dernier état cohérent sur disque.
  Future<AppExitResponse> _onExitRequested() async {
    final initialization = _repositoryInitialization;
    if (initialization == null) return AppExitResponse.exit;
    try {
      await initialization;
    } catch (error, stack) {
      _reportRepositoryFailure(error, stack);
      return AppExitResponse.exit;
    }
    if (!mounted) return AppExitResponse.exit;
    try {
      while (true) {
        await _repositoryStore.flushBindings();
        final pending = _validationQueue;
        if (pending != null) await pending;
        if (!identical(pending, _validationQueue)) continue;
        final error = _validationFailure;
        if (error != null) {
          Error.throwWithStackTrace(
            error,
            _validationFailureStack ?? StackTrace.current,
          );
        }
        await _repositoryStore.saveRepository(_repositoryId);
        if (identical(pending, _validationQueue)) {
          return AppExitResponse.exit;
        }
      }
    } catch (error, stack) {
      _reportRepositoryFailure(error, stack);
      return AppExitResponse.cancel;
    }
  }

  /// Libère les ressources asynchrones possédées par ce widget.
  @override
  void dispose() {
    _lifecycle?.dispose();
    unawaited(_eventSubscription.cancel());
    unawaited(_eventBus.close());
    _pageRouting.dispose();
    _repositoryStore.dispose();
    super.dispose();
  }

  /// Affiche l'application seulement après la restauration du repository.
  @override
  Widget build(BuildContext context) {
    final initialization = _repositoryInitialization;
    if (initialization == null) return _buildApp();
    return FutureBuilder<void>(
      future: initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text(
                  'Impossible de charger le repository : ${snapshot.error}',
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        return _buildApp();
      },
    );
  }

  /// Construit l'application hôte avec le routeur et le repository partagés.
  Widget _buildApp() => SuperApp(
    router: _router,
    pageRouting: _pageRouting,
    title: 'Card Layout demo 2',
    registry: _registry,
    repositoryStore: _repositoryStore,
    eventBus: _eventBus,
    editorBannerAlignment: Alignment.bottomCenter,
  );

  /// Construit la surface racine contenant la [SuperPage] et la barre d'outils flottante.
  Widget getRootWidget(Registry registry) {
    return Builder(
      builder: (context) {
        final superapp = SuperApp.of(context);
        final superLayoutConfig = superapp.getLayoutConfigById('mainLayout');

        return EditableSurface(
          slot: AppearanceSlot(
            'Fond',
            name: 'demo-background',
            role: AppearanceSurfaceRole.applicationBackground,
            editShape: false,
            extendedLook: false,
            read: (a) => a.backgroundStyle,
            write: (a, style) => a.withStyle('background', style),
            reset: (a) => a.withStyle('background', null),
          ),
          menuIcon: Icons.wallpaper_outlined,
          decorate: false,
          applyPadding: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: SuperPage(
                  menuIcon: Icons.article_outlined,
                  child: ValueListenableBuilder<SuperLayoutConfig>(
                    valueListenable: superLayoutConfig,
                    builder: (context, config, _) => SuperLayout(
                      label: 'Main Layout',
                      config: config,
                      onChanged: (value) => superLayoutConfig.value = value,
                      menuIcon: Icons.dashboard_outlined,
                      slots: const [],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(child: FloatingAppearanceToolbar()),
            ],
          ),
        );
      },
    );
  }
}
