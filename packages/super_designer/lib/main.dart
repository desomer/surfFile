/// Point d'entrée de l'application autonome `super_designer`.
///
/// Combine le moteur `super_container_layout` et le catalogue d'extensions
/// `super_container_extensions` (`SuperChart`, `SuperCode`, etc.) au sein d'un
/// même [Registry], avec gestion des applications sandboxées et persistance paginée.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, Brightness, PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_extensions/super_container_extensions.dart';
import 'package:super_container_layout/super_container_layout.dart';

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
  FlutterError.onError = (FlutterErrorDetails details) {
    saveError('[FLUTTER ERROR] ${details.exceptionAsString()}', details.stack);
    FlutterError.dumpErrorToConsole(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    saveError('[PLATFORM ERROR] $error\n$stack', stack);
    FlutterError.dumpErrorToConsole(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    return true;
  };

  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      if (!dotenv.isInitialized) {
        dotenv.loadFromString(envString: '', isOptional: true);
      }
      unawaited(_warmUpAiServices());
      runApp(const SuperDesignerApp(persistRepository: true));
    },
    (error, stack) {
      saveError('[DART ERROR] $error\n$stack', stack);
      FlutterError.dumpErrorToConsole(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
    zoneSpecification: createSuperDesignerLogZoneSpecification(),
  );
}

Future<void> _warmUpAiServices() async {
  try {
    final geminiKey = await resolveGeminiApiKey();
    if (geminiKey.isNotEmpty) {
      await VibeChatDialog.warmUp(rootBundle);
    }
  } catch (error, stack) {
    saveError('[AI WARMUP ERROR] $error', stack);
  }
}

/// Construit la [ZoneSpecification] de journalisation console horodatée pour `super_designer`.
///
/// Enregistre la ligne brute dans [debugEntries] via [saveLog] et préfixe
/// la sortie console avec l'heure locale `[HH:MM:SS.mmm]` via [formatTimestampedConsoleLog].
ZoneSpecification createSuperDesignerLogZoneSpecification({
  DateTime Function()? clock,
}) => ZoneSpecification(
  print: (self, parent, zone, line) {
    saveLog(line, null);
    parent.print(
      zone,
      formatTimestampedConsoleLog(line, timestamp: clock?.call()),
    );
  },
);

ContainerStyle _readBackgroundStyle(Appearance appearance) =>
    appearance.backgroundStyle;

Appearance _writeBackgroundStyle(Appearance appearance, ContainerStyle style) =>
    appearance.withStyle('background', style);

Appearance _resetBackgroundStyle(Appearance appearance) =>
    appearance.withStyle('background', null);

/// Widget racine de l'application d'édition visuelle et IA `super_designer`,
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

  /// Active la restauration et l'enregistrement automatique des données.
  final bool persistRepository;

  /// Dossier explicite du store de repositories ; `null` utilise le mode
  /// application sandboxée (si [persistRepository] est actif) ou le dossier par défaut.
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
  static const _backgroundSlot = AppearanceSlot(
    'Fond',
    name: 'demo-background',
    role: AppearanceSurfaceRole.applicationBackground,
    editShape: false,
    extendedLook: false,
    read: _readBackgroundStyle,
    write: _writeBackgroundStyle,
    reset: _resetBackgroundStyle,
  );

  Registry _registry = createSuperDesignerRegistry();
  final _eventBus = SuperEventBus();

  late final SandboxedApplicationStore _applicationStore =
      widget.applicationStore ?? SandboxedApplicationStore();
  late final CustomDesignSystemStore? _globalDesignSystemStore =
      CustomDesignSystemStore.tryDefaultStore();

  late EditorPageRouter _pageRouting;
  JsonRepositoryStore? _repositoryStore;
  PagedFileAppearanceStore? _appearanceStore;
  Directory? _currentAppDir;
  String? _currentAppName;
  int _appSessionGeneration = 0;

  Future<void>? _sessionInitialization;
  AppLifecycleListener? _lifecycle;

  GoRouter get _router => _pageRouting.router;

  bool get _usesSandboxedAppMode =>
      widget.repositoryDirectory == null &&
      (widget.persistRepository || widget.applicationDirectory != null);

  EditorPageRouter _createPageRouting() => EditorPageRouter(
    pageWrapper: (context, state, child) => wrapPageWithAppearanceShell(child),
    baseConfig: RoutingConfig(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => _buildRootPage(),
        ),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.persistRepository || widget.applicationDirectory != null) {
      // Annule la fermeture si des saisies ou leur sauvegarde échouent.
      _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    }
    _pageRouting = _createPageRouting();

    if (_usesSandboxedAppMode) {
      _sessionInitialization = _initializeSandboxedSession();
    } else {
      _repositoryStore = widget.repositoryDirectory == null
          ? JsonRepositoryStore.defaultStore()
          : JsonRepositoryStore(widget.repositoryDirectory!);
    }
  }

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
    _currentAppDir = targetDir;
    _currentAppName = manifest.name;
    _appearanceStore = SandboxedApplicationStore.appearanceStoreFor(
      targetDir,
      registry: _registry,
    );
    _repositoryStore = SandboxedApplicationStore.repositoryStoreFor(targetDir);
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
    _repositoryStore?.reportBindingError('Erreur du repository : $error');
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
    await _repositoryStore?.flushBindings();
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

    final nextRegistry = createSuperDesignerRegistry();
    final nextRepositoryStore = SandboxedApplicationStore.repositoryStoreFor(
      targetDir,
    );
    final nextAppearanceStore = SandboxedApplicationStore.appearanceStoreFor(
      targetDir,
      registry: nextRegistry,
    );
    final nextPageRouting = _createPageRouting();

    _registry = nextRegistry;
    _repositoryStore = nextRepositoryStore;
    _appearanceStore = nextAppearanceStore;
    _pageRouting = nextPageRouting;
    _currentAppDir = targetDir;
    _currentAppName = manifest.name;
    _sessionInitialization = null;
    _appSessionGeneration++;

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousPageRouting.dispose();
      previousRepositoryStore?.dispose();
      previousRegistry.dispose();
    });
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

  /// Attend l'initialisation et vide les saisies en cours avant de fermer.
  Future<AppExitResponse> _onExitRequested() async {
    final initialization = _sessionInitialization;
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
      await _flushActiveApplication(null);
      return AppExitResponse.exit;
    } catch (error, stack) {
      _reportRepositoryFailure(error, stack);
      return AppExitResponse.cancel;
    }
  }

  /// Libère les ressources asynchrones possédées par ce widget.
  @override
  void dispose() {
    _lifecycle?.dispose();
    unawaited(_eventBus.close());
    _pageRouting.dispose();
    _repositoryStore?.dispose();
    _registry.dispose();
    super.dispose();
  }

  /// Affiche l'application dès que la session initiale est prête.
  @override
  Widget build(BuildContext context) {
    final initialization = _sessionInitialization;
    if (initialization == null) return _buildApp();
    return FutureBuilder<void>(
      future: initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Impossible d’initialiser l’application : ${snapshot.error}',
                  ),
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          final isDark =
              PlatformDispatcher.instance.platformBrightness == Brightness.dark;
          return ColoredBox(
            color: isDark ? const Color(0xFF121212) : const Color(0xFFFAFAFA),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: Center(child: CircularProgressIndicator()),
            ),
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
          slot: _backgroundSlot,
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

  /// Construit la surface racine contenant la [SuperPage] et son layout principal.
  Widget _buildRootPage() {
    return Builder(
      builder: (context) {
        final superLayoutConfig = SuperApp.of(
          context,
        ).getLayoutConfigById('mainLayout');

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
