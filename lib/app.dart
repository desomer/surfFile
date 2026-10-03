import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' show WindowEffect;

import 'pages/explorer_page.dart';
import 'services/appearance_store.dart';
import 'services/window_transparency.dart';
import 'theme/appearance.dart';
import 'theme/neon_style.dart';
import 'widgets/neon_surface.dart';
import 'widgets/super_container.dart';

class SurfFileApp extends StatefulWidget {
  const SurfFileApp({super.key});

  @override
  State<SurfFileApp> createState() => _SurfFileAppState();
}

class _SurfFileAppState extends State<SurfFileApp> {
  late final PersistentAppearanceController _appearance;
  final _styleEditMode = ValueNotifier(false);
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  bool _loading = true;
  String? _loadError;
  Future<void> _windowUpdates = Future.value();
  (double, WindowEffect, bool)? _appliedWindow;

  @override
  void initState() {
    super.initState();
    _appearance = PersistentAppearanceController(AppearanceStore(), (error) {
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
    });
    _appearance.addListener(_updateWindow);
    _restore();
  }

  void _updateWindow() {
    final appearance = _appearance.value;
    final dark = switch (appearance.mode) {
      ThemeMode.light => false,
      ThemeMode.dark => true,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
    final window = (appearance.windowOpacity, appearance.windowEffect, dark);
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
    _appearance.dispose();
    _styleEditMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppearanceScope(
      controller: _appearance,
      child: StyleEditScope(
        controller: _styleEditMode,
        child: ValueListenableBuilder<Appearance>(
          valueListenable: _appearance,
          builder: (context, appearance, child) => MaterialApp(
            title: 'SurfFile',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: _messenger,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            themeMode: appearance.mode,
            theme: appearance.theme(Brightness.light),
            darkTheme: appearance.theme(Brightness.dark),
            builder: (context, child) => Stack(
              children: [
                Positioned.fill(
                  child: NeonSurface(
                    key: const ValueKey('background-neon'),
                    style: appearance.backgroundStyle.neon ?? const NeonStyle(),
                    accent: appearance.accent,
                    radius: 0,
                    child: DecoratedBox(
                      key: const ValueKey('background-border'),
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color:
                              appearance.backgroundStyle.borderColor ??
                              Theme.of(context).colorScheme.outlineVariant,
                          width: appearance.backgroundStyle.borderWidth,
                          style: appearance.backgroundStyle.borderWidth == 0
                              ? BorderStyle.none
                              : BorderStyle.solid,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: appearance.backgroundStyle.fill.gradient(
                            opacity: appearance.backgroundOpacity,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(child: StyleEditBanner()),
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
                                _appearance.value = const Appearance();
                                setState(() => _loadError = null);
                              },
                              child: const Text('Réinitialiser les paramètres'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const ExplorerPage(),
          ),
        ),
      ),
    );
  }
}
