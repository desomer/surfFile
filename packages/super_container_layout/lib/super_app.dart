import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';

import 'models/registry.dart';

import 'services/appearance/appearance_store.dart';
import 'services/pages/editor_page_router.dart';
import 'services/repositories/json_repository_store.dart';
import 'services/repositories/json_repository_scope.dart';
import 'services/window/window_transparency.dart';
import 'theme/appearance.dart';
import 'theme/container_style.dart';
import 'theme/neon_style.dart';
import 'widgets/editing/history/editor_history.dart';
import 'widgets/editing/pages/editor_page_manager.dart';
import 'widgets/components/super_layout/layout_reset_shortcut.dart';
import 'widgets/surfaces/neon_surface.dart';
import 'widgets/surfaces/styled_surface.dart';
import 'widgets/editing/overlay/style_edit_banner.dart';
import 'widgets/editing/slots/editor_slot.dart';

/// Application shell managing appearance persistence, layout reset, window
/// transparency and GoRouter navigation.
class SuperApp extends StatefulWidget {
  /// Uses an application-owned router, which is not disposed by this widget.
  const SuperApp({
    required this.router,
    this.appearanceStore,
    this.title = '',
    super.key,
    this.registry,
    this.pageRouting,
    this.repositoryStore,
  });

  final GoRouter router;
  final AppearanceStore? appearanceStore;
  final String title;
  final Registry? registry;
  final JsonRepositoryStore? repositoryStore;

  /// Optional editable routing. Its router must be [router]; owned by the caller.
  final EditorPageRouter? pageRouting;

  /// Returns the nearest application and subscribes to its configuration.
  static SuperApp? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SuperAppScope>()?.app;

  /// Returns the nearest application, or throws if none encloses [context].
  static SuperApp of(BuildContext context) {
    final app = maybeOf(context);
    if (app == null) {
      throw FlutterError(
        'SuperApp.of() called with a context that does not contain a SuperApp.',
      );
    }
    return app;
  }

  @override
  State<SuperApp> createState() => _SuperAppState();

  ValueNotifier<SuperLayoutConfig> getLayoutConfigById(String id) {
    final currentRegistry = registry;
    if (currentRegistry == null) {
      throw StateError(
        'SuperApp requires a registry for ID-based controllers.',
      );
    }
    return currentRegistry.layoutController(id);
  }

  ValueNotifier<ContainerStyle> getContainerStyleById(String id) {
    final currentRegistry = registry;
    if (currentRegistry == null) {
      throw StateError(
        'SuperApp requires a registry for ID-based controllers.',
      );
    }
    return currentRegistry.styleController(id);
  }
}

class _SuperAppState extends State<SuperApp> with WidgetsBindingObserver {
  late PersistentAppearanceController _appearance;
  late EditorHistoryController _editorHistory;
  late JsonRepositoryStore _repositories;
  final _styleEditMode = ValueNotifier(false);
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  bool _loading = true;
  bool _pagesScheduled = false;
  String? _loadError;
  Future<void> _windowUpdates = Future.value();
  (double, WindowEffect, bool)? _appliedWindow;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPageRouting();
    _repositories =
        widget.repositoryStore ?? JsonRepositoryStore.defaultStore();
    _repositories.errors.addListener(_repositoryFailed);
    _appearance = _createAppearanceController();
    _editorHistory = _createEditorHistory();
    widget.registry?.bindAppearance(_appearance);
    _restore();
  }

  void _checkPageRouting() {
    if (widget.pageRouting != null &&
        !identical(widget.pageRouting!.router, widget.router)) {
      throw ArgumentError('SuperApp.router must be pageRouting.router.');
    }
  }

  void _repositoryFailed() {
    final error = _repositories.errors.value;
    if (error == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _messenger.currentState?.showSnackBar(SnackBar(content: Text(error)));
      }
    });
  }

  PersistentAppearanceController _createAppearanceController() =>
      PersistentAppearanceController(
          widget.appearanceStore ?? AppearanceStore(),
          _saveFailed,
          validateAppearance: (value) =>
              widget.pageRouting?.validate(value.pageCatalog),
        )
        ..addListener(_updateWindow)
        ..addListener(_pagesChanged);

  void _pagesChanged() {
    if (_pagesScheduled || widget.pageRouting == null || _loading) return;
    _pagesScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pagesScheduled = false;
      if (!mounted || _loading || widget.pageRouting == null) return;
      final notice = widget.pageRouting!.synchronize(
        _appearance.value.pageCatalog,
      );
      if (notice != null) {
        _messenger.currentState?.showSnackBar(SnackBar(content: Text(notice)));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(SuperApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkPageRouting();
    if (oldWidget.repositoryStore != widget.repositoryStore) {
      _repositories.errors.removeListener(_repositoryFailed);
      if (oldWidget.repositoryStore == null) _repositories.dispose();
      _repositories =
          widget.repositoryStore ?? JsonRepositoryStore.defaultStore();
      _repositories.errors.addListener(_repositoryFailed);
    }
    if (oldWidget.appearanceStore != widget.appearanceStore) {
      oldWidget.registry?.unbindAppearance();
      _editorHistory.dispose();
      _appearance.removeListener(_updateWindow);
      _appearance.removeListener(_pagesChanged);
      _appearance.dispose();
      _appearance = _createAppearanceController();
      _editorHistory = _createEditorHistory();
      widget.registry?.bindAppearance(_appearance);
      _restore();
    } else if (oldWidget.registry != widget.registry) {
      oldWidget.registry?.unbindAppearance();
      widget.registry?.bindAppearance(_appearance);
    }
    if (oldWidget.pageRouting != widget.pageRouting) _pagesChanged();
  }

  EditorHistoryController _createEditorHistory() => EditorHistoryController(
    appearance: _appearance,
    editMode: _styleEditMode,
  );

  @override
  void didChangePlatformBrightness() => _updateWindow();

  void _saveFailed(Object error) {
    debugPrint('Error saving appearance: $error');
    if (!mounted) return;
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text('Impossible d’enregistrer les paramètres : $error'),
        action: SnackBarAction(
          label: 'Réessayer',
          onPressed: () => _appearance.value = _appearance.value,
        ),
      ),
    );
  }

  void _resetLayouts() {
    _appearance.value = _appearance.value.resetLayouts();
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Zones et slots remis par défaut.')),
      );
  }

  void _updateWindow() {
    final value = _appearance.value;
    final dark = switch (value.mode) {
      ThemeMode.light => false,
      ThemeMode.dark => true,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
    final window = (value.windowOpacity, value.windowEffect, dark);
    if (_appliedWindow == window) return;
    _appliedWindow = window;
    _windowUpdates = _windowUpdates.then((_) async {
      try {
        await WindowTransparency.apply(
          window.$1,
          effect: window.$2,
          dark: window.$3,
        );
      } on PlatformException catch (error) {
        _windowUpdateFailed(error);
      } on MissingPluginException catch (error) {
        _windowUpdateFailed(error);
      }
    });
  }

  void _windowUpdateFailed(Object error) {
    _appliedWindow = null;
    debugPrint('Error applying window transparency: $error');
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messenger.currentState?.showSnackBar(
        SnackBar(
          content: const Text(
            'Impossible d’appliquer la transparence Windows. '
            'Arrêtez puis relancez l’application.',
          ),
          action: SnackBarAction(label: 'Réessayer', onPressed: _updateWindow),
        ),
      );
    });
  }

  Future<void> _restore() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await Future.wait([
        _appearance.restore(),
        _repositories.preload(),
      ]);
      if (!mounted) return;
      widget.pageRouting?.synchronize(_appearance.value.pageCatalog);
      _editorHistory.clear();
      _updateWindow();
      if (mounted) setState(() => _loading = false);
    } on FormatException catch (error) {
      _restoreFailed(error);
    } on PlatformException catch (error) {
      _restoreFailed(error);
    } on MissingPluginException catch (error) {
      _restoreFailed(error);
    } on StateError catch (error) {
      _restoreFailed(error);
    } on FileSystemException catch (error) {
      _restoreFailed(error);
    }
  }

  void _restoreFailed(Object error) {
    debugPrint('Error loading appearance: $error');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = 'Impossible de charger les paramètres : $error';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.registry?.unbindAppearance();
    _editorHistory.dispose();
    _appearance
      ..removeListener(_updateWindow)
      ..removeListener(_pagesChanged)
      ..dispose();
    _styleEditMode.dispose();
    _repositories.errors.removeListener(_repositoryFailed);
    if (widget.repositoryStore == null) _repositories.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SuperAppScope(
    app: widget,
    child: JsonRepositoryScope(
      store: _repositories,
      child: AppearanceServicesScope(
        codec: _appearance.store.codec,
        child: AppearanceScope(
          controller: _appearance,
          child: LayoutResetShortcut(
            onReset: _resetLayouts,
            child: EditorHistoryShortcut(
              editMode: _styleEditMode,
              history: _editorHistory,
              child: EditorHistoryScope(
                controller: _editorHistory,
                child: StyleEditScope(
                  controller: _styleEditMode,
                  child: ValueListenableBuilder<Appearance>(
                    valueListenable: _appearance,
                    builder: (context, value, _) => _buildApp(value),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildApp(Appearance value) {
    final router = widget.router;
    return MaterialApp.router(
      routerConfig: router,
      title: widget.title,
      debugShowCheckedModeBanner: false,
      showSemanticsDebugger: false,
      scaffoldMessengerKey: _messenger,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: value.mode,
      theme: _withHitTestablePages(value.theme(Brightness.light)),
      darkTheme: _withHitTestablePages(value.theme(Brightness.dark)),
      builder: (context, child) => _buildShell(
        context,
        _buildContent(child!),
        value,
        router.routerDelegate.navigatorKey,
      ),
    );
  }

  static ThemeData _withHitTestablePages(ThemeData theme) {
    final builders = theme.pageTransitionsTheme.builders;
    return theme.copyWith(
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: _HitTestablePageTransitionsBuilder(
              builders[platform] ?? const ZoomPageTransitionsBuilder(),
            ),
        },
      ),
    );
  }

  Widget _buildShell(
    BuildContext context,
    Widget child,
    Appearance value,
    GlobalKey<NavigatorState> navigatorKey,
  ) => Stack(
    children: [
      Positioned.fill(
        child: NeonSurface(
          key: const ValueKey('background-neon'),
          style: value.backgroundStyle.neon ?? const NeonStyle(),
          accent: value.accent,
          radius: 0,
          child: DecoratedBox(
            key: const ValueKey('background-border'),
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(
                color:
                    value.backgroundStyle.borderColor ??
                    Theme.of(context).colorScheme.outlineVariant,
                width: value.backgroundStyle.borderWidth,
                style: value.backgroundStyle.borderWidth == 0
                    ? BorderStyle.none
                    : BorderStyle.solid,
              ),
            ),
            child: BoundContainerFill(
              fill: value.backgroundStyle.fill,
              binding: value.backgroundStyle.imageBinding,
              builder: (context, fill) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: fill.gradient(
                    opacity: value.backgroundOpacity,
                  ),
                  image: fill.decorationImage(
                    opacity: value.backgroundOpacity,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
      if (!_loading && _loadError == null)
        Positioned.fill(
          child: StyleEditBanner(
            navigatorKey: navigatorKey,
            validateAppearance: (appearance) =>
                widget.pageRouting?.validate(appearance.pageCatalog),
            onManagePages: widget.pageRouting == null || widget.registry == null
                ? null
                : () async {
                    final target = navigatorKey.currentContext;
                    if (target == null) return;
                    await showEditorPageManager(
                      context: target,
                      appearance: _appearance,
                      routing: widget.pageRouting!,
                      registry: widget.registry!,
                    );
                  },
          ),
        ),
    ],
  );

  Widget _buildContent(Widget child) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _restore,
                  child: const Text('Réessayer'),
                ),
                TextButton(
                  onPressed: () {
                    _appearance.reset();
                    setState(() => _loadError = null);
                  },
                  child: const Text('Réinitialiser les paramètres'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return child;
  }
}

class _SuperAppScope extends InheritedWidget {
  const _SuperAppScope({required this.app, required super.child});

  final SuperApp app;

  @override
  bool updateShouldNotify(_SuperAppScope oldWidget) => app != oldWidget.app;
}

/// Makes every page opaque to hit testing. Otherwise a click on an empty area
/// reaches the route's non-dismissible ModalBarrier, which plays the system
/// alert sound (Windows beep).
class _HitTestablePageTransitionsBuilder extends PageTransitionsBuilder {
  const _HitTestablePageTransitionsBuilder(this.inner);

  final PageTransitionsBuilder inner;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      inner.delegatedTransition;

  @override
  Duration get transitionDuration => inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => inner.buildTransitions<T>(
    route,
    context,
    animation,
    secondaryAnimation,
    ColoredBox(color: const Color(0x00000000), child: child),
  );

  @override
  bool operator ==(Object other) =>
      other is _HitTestablePageTransitionsBuilder && other.inner == inner;

  @override
  int get hashCode => inner.hashCode;
}
