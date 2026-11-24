/// Point d'entrée de l'application autonome `super_designer`.
///
/// Combine le moteur `super_container_layout` et le catalogue d'extensions
/// `super_container_extensions` (`SuperChart`, etc.) au sein d'un même [Registry].
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart' show rootBundle;
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

/// Lance l'application autonome `super_designer` en capturant les journaux et erreurs.
void main() {
  // Capture les erreurs Flutter (UI, widgets, rendering…)
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = '[FLUTTER ERROR] ${details.exceptionAsString()}';
    saveError(message, details.stack);
    //debugPrintSynchronously(message /*, stackTrace: details.stack*/);
    FlutterError.dumpErrorToConsole(details);
  };

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final geminiKey = await resolveGeminiApiKey();
      if (!dotenv.isInitialized) {
        dotenv.loadFromString(envString: '', isOptional: true);
      }
      if (geminiKey.isNotEmpty) {
        unawaited(VibeChatDialog.warmUp(rootBundle));
      }
      // Le point d'entrée de démonstration active la persistance par défaut.
      runApp(const SuperDesignerApp(persistRepository: true));
    },
    (error, stack) {
      final message = '[DART ERROR] $error\n$stack';
      saveError(message, stack);
      //debugPrintSynchronously(message);
      FlutterError.dumpErrorToConsole(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
    zoneSpecification: createSuperDesignerLogZoneSpecification(),
  );
}

/// Construit la [ZoneSpecification] de journalisation console horodatée pour `super_designer`.
///
/// Enregistre la ligne brute dans [debugEntries] via [saveLog] et préfixe
/// la sortie console avec l'heure locale `[HH:MM:SS.mmm]` via [formatTimestampedConsoleLog].
ZoneSpecification createSuperDesignerLogZoneSpecification({
  DateTime Function()? clock,
}) => ZoneSpecification(
  print: (self, parent, zone, line) {
    // Capture la stack ici, dans le contexte de l'appelant du print
    saveLog(line, null);

    // Et tu continues d'afficher normalement avec l'horodatage console
    parent.print(
      zone,
      formatTimestampedConsoleLog(line, timestamp: clock?.call()),
    );
  },
);

/// Widget racine de l'application de démonstration et d'édition `super_designer`,
/// donnant accès au moteur `super_container_layout` et à ses extensions.
class SuperDesignerApp extends StatefulWidget {
  const SuperDesignerApp({
    super.key,
    this.persistRepository = false,
    this.repositoryDirectory,
    this.applicationDirectory,
    this.applicationStore,
    this.pickDirectory,
  });

  /// Active la restauration et l'enregistrement automatique du repository.
  final bool persistRepository;

  /// Dossier du store ; `null` utilise le dossier utilisateur par défaut.
  final Directory? repositoryDirectory;

  /// Dossier initial de l'application sandboxée ; `null` ouvre la dernière
  /// application active (ou l'application par défaut) lorsque [persistRepository]
  /// est activé et que [repositoryDirectory] est absent.
  final Directory? applicationDirectory;

  /// Gestionnaire optionnel de dossiers d'applications sandboxées.
  final SandboxedApplicationStore? applicationStore;

  /// Sélecteur de dossier personnalisable (principalement utilisé pour les tests).
  final DirectoryPickerCallback? pickDirectory;

  @override
  State<SuperDesignerApp> createState() => _SuperDesignerAppState();
}

class _SuperDesignerAppState extends State<SuperDesignerApp> {
  Registry _registry = createSuperDesignerRegistry();
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

  late final SandboxedApplicationStore _applicationStore =
      widget.applicationStore ?? SandboxedApplicationStore();
  late final CustomDesignSystemStore? _globalDesignSystemStore =
      CustomDesignSystemStore.tryDefaultStore();

  late JsonRepositoryStore _repositoryStore;
  FileAppearanceStore? _appearanceStore;
  Directory? _currentAppDir;
  String? _currentAppName;
  int _appSessionGeneration = 0;

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
          if (!mounted ||
              !_repositoryStore.isRegisteredRepository(_repositoryId)) {
            return;
          }
          if (restoreModel || _schemaModelReady != true) {
            final nodes = await _repositoryStore.readArray(
              _repositoryId,
              'nodes',
            );
            if (!mounted ||
                !_repositoryStore.isRegisteredRepository(_repositoryId)) {
              return;
            }
            _schemaModel.restore(nodes);
            _schemaModelReady = true;
          }
          final source = await _repositoryStore.readAttribute(_sourceBinding);
          if (!mounted ||
              !_repositoryStore.isRegisteredRepository(_repositoryId)) {
            return;
          }
          await _validateYaml(source.value, updateNodes: updateNodes);
          _validationFailure = null;
          _validationFailureStack = null;
        })
        .catchError((Object error, StackTrace stack) {
          if (!mounted ||
              !_repositoryStore.isRegisteredRepository(_repositoryId)) {
            return;
          }
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
        nodes = await _schemaModel.patchAsync(source, previousNodes);
      } on FormatException catch (error) {
        message = error.message;
      }
      if (!mounted) return;
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
  late EditorPageRouter _pageRouting;
  GoRouter get _router => _pageRouting.router;

  bool get _usesSandboxedAppMode =>
      widget.repositoryDirectory == null &&
      (widget.persistRepository || widget.applicationDirectory != null);

  EditorPageRouter _createPageRouting(Registry registry) => EditorPageRouter(
    pageWrapper: (context, state, child) => wrapPageWithAppearanceShell(child),
    baseConfig: RoutingConfig(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => getRootWidget(registry),
        ),
      ],
    ),
  );

  // RepositoryImpl _createPanModelRepository() {
  //   final repository = RepositoryImpl(
  //     id: _repositoryId,
  //     onChanged: _onRepositoryChanged,
  //     json: {
  //       'source': '',
  //       'estSize': 300,
  //       'yamlError': '',
  //       'nodes': <Object?>[],
  //     },
  //   );

  //   repository.addCalculatedAttribute('total', (ctx) {
  //     final articles = ctx.sync.getValue('articles')! as List;
  //     return articles.fold<num>(
  //       0,
  //       (sum, article) => sum + ((article as Map)['prix'] as num),
  //     );
  //   });
  //   return repository;
  // }

  Future<void> _initializeSandboxedSession() async {
    final requestedDir = widget.applicationDirectory;
    final Directory targetDir;
    final SandboxedApplicationManifest manifest;
    if (requestedDir != null) {
      final inspection = await _applicationStore.inspectDirectory(requestedDir);
      if (!inspection.exists) {
        manifest = await _applicationStore.createApplication(
          requestedDir,
          name: SandboxedApplicationStore.fallbackNameForDirectory(
            requestedDir,
          ),
        );
      } else {
        manifest = await _applicationStore.openApplication(
          requestedDir,
          initializeNonEmpty: true,
        );
      }
      targetDir = Directory(
        SandboxedApplicationStore.normalizePath(requestedDir.path),
      );
    } else {
      targetDir = await _applicationStore.ensureDefaultApplication();
      final inspection = await _applicationStore.inspectDirectory(targetDir);
      manifest =
          inspection.manifest ??
          SandboxedApplicationManifest(
            name: SandboxedApplicationStore.fallbackNameForDirectory(targetDir),
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
    }
    if (!mounted) return;
    _repositoryStore.dispose();
    _currentAppDir = targetDir;
    _currentAppName = manifest.name;
    _appearanceStore = SandboxedApplicationStore.appearanceStoreFor(
      targetDir,
      registry: _registry,
    );
    _repositoryStore = SandboxedApplicationStore.repositoryStoreFor(targetDir);
    //await _initializePersistentRepository(_createPanModelRepository());
  }

  @override
  void initState() {
    super.initState();
    if (widget.persistRepository || widget.applicationDirectory != null) {
      // Annule la fermeture si des saisies ou leur sauvegarde échouent.
      _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    }
    _eventSubscription = _eventBus
        .on('node.click')
        .asyncMap((event) async {
          if (!_repositoryStore.isRegisteredRepository(_repositoryId)) {
            return event;
          }
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

    //SuperDesignerRegistry(_registry).addRegistry();
    _pageRouting = _createPageRouting(_registry);
    _repositoryStore = widget.repositoryDirectory == null
        ? JsonRepositoryStore.defaultStore()
        : JsonRepositoryStore(widget.repositoryDirectory!);

    if (_usesSandboxedAppMode) {
      _repositoryInitialization = _initializeSandboxedSession();
    } else if (widget.persistRepository) {
      // _repositoryInitialization = _initializePersistentRepository(
      //   _createPanModelRepository(),
      // );
    } else {
      //_repositoryStore.registerRepository(_createPanModelRepository());
      _repositoryInitialization = null;
      _queueValidation();
    }
  }

  /// Enregistre les modifications d'apparence et de repositories en attente.
  Future<void> _flushActiveApplication(BuildContext? appContext) async {
    final navContext =
        appContext ??
        _pageRouting.router.routerDelegate.navigatorKey.currentContext;
    if (navContext != null && navContext.mounted) {
      final controller = AppearanceScope.controllerOf(navContext);
      if (controller is PersistentAppearanceController) {
        await controller.flush();
      }
      if (_currentAppDir != null &&
          controller != null &&
          !SandboxedApplicationStore.appearanceFileFor(_currentAppDir!)
              .existsSync()) {
        await _appearanceStore?.save(controller.value);
      }
    }
    if (_repositoryStore.isRegisteredRepository(_repositoryId)) {
      await _repositoryStore.flushBindings();
      final pending = _validationQueue;
      if (pending != null) await pending;
      if (_repositoryStore.isPersistentRepository(_repositoryId)) {
        await _repositoryStore.saveRepository(_repositoryId);
      }
    }
  }

  /// Bascule à chaud toute l'application vers le dossier [targetDir].
  Future<void> _activateApplicationDirectory(
    Directory targetDir,
    SandboxedApplicationManifest manifest,
  ) async {
    if (!mounted) return;
    _lifecycle ??= AppLifecycleListener(onExitRequested: _onExitRequested);

    final previousRegistry = _registry;
    final previousPageRouting = _pageRouting;
    final previousRepositoryStore = _repositoryStore;

    LayoutSelection.clearAll();
    _validationQueue = null;
    _validationFailure = null;
    _validationFailureStack = null;
    _schemaModelReady = false;

    final nextRegistry = createSuperDesignerRegistry();
    //SuperDesignerRegistry(nextRegistry).addRegistry();
    final nextRepositoryStore = SandboxedApplicationStore.repositoryStoreFor(
      targetDir,
    );
    final nextAppearanceStore = SandboxedApplicationStore.appearanceStoreFor(
      targetDir,
      registry: nextRegistry,
    );
    final nextPageRouting = _createPageRouting(nextRegistry);

    _registry = nextRegistry;
    _repositoryStore = nextRepositoryStore;
    _appearanceStore = nextAppearanceStore;
    _pageRouting = nextPageRouting;
    _currentAppDir = targetDir;
    _currentAppName = manifest.name;
    _appSessionGeneration++;

    // _repositoryInitialization = _initializePersistentRepository(
    //   _createPanModelRepository(),
    // );
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousPageRouting.dispose();
      previousRepositoryStore.dispose();
      previousRegistry.dispose();
    });

    await _repositoryInitialization;
  }

  Future<void> _switchToApplication(
    BuildContext appContext,
    Directory targetDir, {
    required bool initializeNonEmpty,
  }) async {
    final normalized = Directory(
      SandboxedApplicationStore.normalizePath(targetDir.path),
    );
    await _flushActiveApplication(appContext);
    final manifest = await _applicationStore.openApplication(
      normalized,
      initializeNonEmpty: initializeNonEmpty,
    );
    await _activateApplicationDirectory(normalized, manifest);
  }

  Future<void> _createAndSwitchApplication(
    BuildContext appContext,
    Directory targetDir, {
    required String name,
    required bool cloneCurrent,
  }) async {
    final normalized = Directory(
      SandboxedApplicationStore.normalizePath(targetDir.path),
    );
    await _flushActiveApplication(appContext);
    final manifest = await _applicationStore.createApplication(
      normalized,
      name: name,
      cloneFromDirectory: cloneCurrent ? _currentAppDir : null,
    );
    await _activateApplicationDirectory(normalized, manifest);
  }

  Future<void> _openApplicationSelector(BuildContext appContext) =>
      ApplicationSelectorDialog.show(
        appContext,
        store: _applicationStore,
        currentDirectory: _currentAppDir,
        currentName: _currentAppName,
        canCloneCurrent: _currentAppDir != null,
        pickDirectory: widget.pickDirectory,
        onSelectDirectory: (directory, {required initializeNonEmpty}) =>
            _switchToApplication(
              appContext,
              directory,
              initializeNonEmpty: initializeNonEmpty,
            ),
        onCreateApplication:
            (directory, {required name, required cloneCurrent}) =>
                _createAndSwitchApplication(
                  appContext,
                  directory,
                  name: name,
                  cloneCurrent: cloneCurrent,
                ),
      );

  /// Attend l'initialisation, les saisies et validations en attente avant
  /// d'enregistrer un dernier état cohérent sur disque.
  Future<AppExitResponse> _onExitRequested() async {
    final initialization = _repositoryInitialization;
    if (initialization != null) {
      try {
        await initialization;
      } catch (error, stack) {
        _reportRepositoryFailure(error, stack);
        return AppExitResponse.exit;
      }
    }
    if (!mounted) return AppExitResponse.exit;
    try {
      final navContext =
          _pageRouting.router.routerDelegate.navigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        final controller = AppearanceScope.controllerOf(navContext);
        if (controller is PersistentAppearanceController) {
          await controller.flush();
        }
      }
      while (true) {
        await _repositoryStore.flushBindings();
        if (!_repositoryStore.isPersistentRepository(_repositoryId)) {
          return AppExitResponse.exit;
        }
        final pending = _validationQueue;
        if (pending != null) await pending;
        if (!identical(pending, _validationQueue)) continue;
        if (!_repositoryStore.isPersistentRepository(_repositoryId)) {
          return AppExitResponse.exit;
        }
        final error = _validationFailure;
        if (error != null) {
          Error.throwWithStackTrace(
            error,
            _validationFailureStack ?? StackTrace.current,
          );
        }
        if (_repositoryStore.isPersistentRepository(_repositoryId)) {
          try {
            await _repositoryStore.saveRepository(_repositoryId);
          } catch (_) {
            if (!_repositoryStore.isPersistentRepository(_repositoryId)) {
              return AppExitResponse.exit;
            }
            rethrow;
          }
        }
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
    key: ValueKey('super-app-$_appSessionGeneration'),
    router: _router,
    pageRouting: _pageRouting,
    title: 'SURF UI by Desomer Gauthier',
    registry: _registry,
    appearanceStore: _appearanceStore,
    repositoryStore: _repositoryStore,
    customDesignSystemStore: _globalDesignSystemStore,
    eventBus: _eventBus,
    editorBannerAlignment: Alignment.bottomCenter,
  );

  /// Enveloppe une page dans la surface de fond éditable et la barre d'outils flottante.
  Widget wrapPageWithAppearanceShell(Widget page) {
    return Builder(
      builder: (context) {
        if (SuperShellScope.maybeOf(context)?.wrapsAppearanceShell == true) {
          return page;
        }
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
              Positioned.fill(child: page),
              Positioned.fill(
                child: RepaintBoundary(
                  child: Builder(
                    builder: (toolbarContext) => FloatingAppearanceToolbar(
                      onOpenApplications: () =>
                          _openApplicationSelector(toolbarContext),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Construit la surface racine contenant la [SuperPage] et la barre d'outils flottante.
  Widget getRootWidget(Registry registry) {
    return Builder(
      builder: (context) {
        final superapp = SuperApp.of(context);
        final superLayoutConfig = superapp.getLayoutConfigById('mainLayout');

        return wrapPageWithAppearanceShell(
          SuperPage(
            menuIcon: Icons.article_outlined,
            child: ValueListenableBuilder<SuperLayoutConfig>(
              valueListenable: superLayoutConfig,
              builder: (context, config, _) => SuperLayout(
                id: 'mainLayout',
                label: 'Main Layout',
                config: config,
                onChanged: (value) => superLayoutConfig.value = value,
                menuIcon: Icons.dashboard_outlined,
                slots: const [],
              ),
            ),
          ),
        );
      },
    );
  }
}
