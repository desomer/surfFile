import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';

import 'models/registry.dart';

import 'services/appearance_store.dart';
import 'services/window_transparency.dart';
import 'theme/appearance.dart';
import 'theme/container_style.dart';
import 'theme/neon_style.dart';
import 'widgets/layout_reset_shortcut.dart';
import 'widgets/neon_surface.dart';
import 'widgets/style_edit_banner.dart';
import 'widgets/super_container.dart';

/// Application shell managing appearance persistence, layout reset and window
/// transparency.
class SuperApp extends StatefulWidget {
  const SuperApp({
    required this.home,
    this.appearanceStore,
    this.title = '',
    super.key,
    this.registry,
  });

  final Widget home;
  final AppearanceStore? appearanceStore;
  final String title;
  final Registry? registry;

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
  final _styleEditMode = ValueNotifier(false);
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  bool _loading = true;
  String? _loadError;
  Future<void> _windowUpdates = Future.value();
  (double, WindowEffect, bool)? _appliedWindow;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appearance = PersistentAppearanceController(
      widget.appearanceStore ?? AppearanceStore(),
      _saveFailed,
    )..addListener(_updateWindow);
    widget.registry?.bindAppearance(_appearance);
    _restore();
  }

  @override
  void didUpdateWidget(SuperApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearanceStore != widget.appearanceStore) {
      oldWidget.registry?.unbindAppearance();
      _appearance.removeListener(_updateWindow);
      _appearance.dispose();
      _appearance = PersistentAppearanceController(
        widget.appearanceStore ?? AppearanceStore(),
        _saveFailed,
      )..addListener(_updateWindow);
      widget.registry?.bindAppearance(_appearance);
      _restore();
    } else if (oldWidget.registry != widget.registry) {
      oldWidget.registry?.unbindAppearance();
      widget.registry?.bindAppearance(_appearance);
    }
  }

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
      await _appearance.restore();
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
    _appearance
      ..removeListener(_updateWindow)
      ..dispose();
    _styleEditMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SuperAppScope(
    app: widget,
    child: AppearanceServicesScope(
      codec: _appearance.store.codec,
      child: AppearanceScope(
        controller: _appearance,
        child: LayoutResetShortcut(
          onReset: _resetLayouts,
          child: StyleEditScope(
            controller: _styleEditMode,
            child: ValueListenableBuilder<Appearance>(
              valueListenable: _appearance,
              builder: (context, value, _) => MaterialApp(
                title: widget.title,
                debugShowCheckedModeBanner: false,
                scaffoldMessengerKey: _messenger,
                navigatorKey: _navigator,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                themeMode: value.mode,
                theme: value.theme(Brightness.light),
                darkTheme: value.theme(Brightness.dark),
                builder: (context, child) => Stack(
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
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: value.backgroundStyle.fill.gradient(
                                opacity: value.backgroundOpacity,
                              ),
                            ),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: StyleEditBanner(navigatorKey: _navigator),
                    ),
                  ],
                ),
                home: _loading
                    ? const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      )
                    : _loadError != null
                    ? Scaffold(
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
                                  child: const Text(
                                    'Réinitialiser les paramètres',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : widget.home,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SuperAppScope extends InheritedWidget {
  const _SuperAppScope({required this.app, required super.child});

  final SuperApp app;

  @override
  bool updateShouldNotify(_SuperAppScope oldWidget) => app != oldWidget.app;
}
