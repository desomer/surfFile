/// Génération et synchronisation dynamique du routeur `GoRouter` ([EditorPageRouter]) depuis [EditorPageCatalog].
///
/// Construit les routes correspondant aux pages configurées dans l'apparence
/// et maintient la navigation synchronisée lors de l'ajout ou du renommage de pages.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/editor_page_config.dart';
import '../../models/scaffold_page_config.dart';
import '../../super_page.dart';
import '../../widgets/appearance/appearance_scope.dart';
import '../../widgets/components/a4_document_page.dart';
import '../appearance/appearance_store.dart';

/// A route declared in the application's code, exposed for navigation only.
class EditorCodedRoute {
  const EditorCodedRoute._({
    required this.path,
    required this.parameters,
    this.name,
    required this.caseSensitive,
    required this._sourceRoute,
  });

  final String path;
  final String? name;
  final List<String> parameters;
  final bool caseSensitive;
  final GoRoute _sourceRoute;

  String get label => name ?? path;
}

/// Fonction enveloppant une page construite par [EditorPageRouter] (ex. surface de fond et barre d'outils flottante).
typedef EditorPageWrapper =
    Widget Function(BuildContext context, GoRouterState state, Widget child);

/// Opt-in routing for editor-created pages. The application owns this object.
class EditorPageRouter {
  EditorPageRouter({
    required this.baseConfig,
    this.pageWrapper,
    this.isPageLoaded,
    this.loadPage,
    String? initialLocation,
    GlobalKey<NavigatorState>? navigatorKey,
    List<NavigatorObserver>? observers,
    Listenable? refreshListenable,
    GoRouterWidgetBuilder? errorBuilder,
    GoRouterPageBuilder? errorPageBuilder,
    GoExceptionHandler? onException,
    Codec<Object?, Object?>? extraCodec,
    String? restorationScopeId,
    bool routerNeglect = false,
    bool requestFocus = true,
    bool overridePlatformDefaultLocation = false,
    bool debugLogDiagnostics = false,
  }) {
    _routing = ValueNotifier(baseConfig);
    router = GoRouter.routingConfig(
      routingConfig: _routing,
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      observers: observers,
      refreshListenable: refreshListenable,
      errorBuilder: errorBuilder,
      errorPageBuilder: errorPageBuilder,
      onException: onException,
      extraCodec: extraCodec,
      restorationScopeId: restorationScopeId,
      routerNeglect: routerNeglect,
      requestFocus: requestFocus,
      overridePlatformDefaultLocation: overridePlatformDefaultLocation,
      debugLogDiagnostics: debugLogDiagnostics,
    );
    _initialUri = router.routeInformationProvider.value.uri;
    // GoRouter cannot reparse its empty pre-mount location when pages restore.
    unawaited(
      router.routerDelegate.setInitialRoutePath(
        router.configuration.findMatch(_initialUri),
      ),
    );
  }

  final RoutingConfig baseConfig;

  /// Wrapper optionnel appliqué autour de chaque [SuperPage] générée hors code.
  final EditorPageWrapper? pageWrapper;

  /// Prédicat optionnel indiquant si la page [pageId] est déjà chargée en mémoire.
  final bool Function(String pageId)? isPageLoaded;

  /// Callback optionnel chargeant à la demande les données persistées de [pageId].
  final Future<void> Function(String pageId)? loadPage;

  late final ValueNotifier<RoutingConfig> _routing;
  late final GoRouter router;
  late final Uri _initialUri;
  EditorPageCatalog _catalog = EditorPageCatalog();
  EditorPageCatalog? _validatedCatalog;
  bool _initialized = false;

  String _routeName(String id) => '__editor_page_${Uri.encodeComponent(id)}';

  GoRoute routeFor(EditorPageConfig page) {
    try {
      if (!page.path.startsWith('/') ||
          page.path.startsWith('//') ||
          page.path == '/' ||
          page.path.endsWith('/') ||
          _hasInvalidLiteral(page.path)) {
        throw const FormatException(
          'Chemin absolu requis, différent de /, sans espace ni fragment.',
        );
      }
      _validatePathConstraints(page.path);
      final route = GoRoute(
        path: page.path,
        name: _routeName(page.id),
        pageBuilder: page.pageType.isModal
            ? (context, state) {
                final child = _OnDemandEditorPage(
                  pageId: page.id,
                  isPageLoaded: isPageLoaded,
                  loadPage: loadPage,
                  builder: (_) => SuperPage(
                    key: ValueKey('editor-page-${page.id}'),
                    id: page.id,
                    label: page.name,
                    pageConfig: ScaffoldPageConfig(),
                  ),
                );
                return switch (page.pageType) {
                  EditorPageType.dialog => _EditorDialogPage(
                    key: state.pageKey,
                    width: page.modalWidth,
                    height: page.modalHeight,
                    child: child,
                  ),
                  EditorPageType.bottomSheet => _EditorBottomSheetPage(
                    key: state.pageKey,
                    height: page.modalHeight,
                    child: child,
                  ),
                  EditorPageType.sideSheet => _EditorSideSheetPage(
                    key: state.pageKey,
                    width: page.modalWidth,
                    child: child,
                  ),
                  _ => MaterialPage<void>(key: state.pageKey, child: child),
                };
              }
            : null,
        builder: page.pageType.isModal
            ? null
            : (context, state) {
                final Widget child = _OnDemandEditorPage(
                  pageId: page.id,
                  isPageLoaded: isPageLoaded,
                  loadPage: loadPage,
                  builder: (_) => switch (page.pageType) {
                    EditorPageType.a4Document => A4DocumentPage(
                      key: ValueKey('editor-page-${page.id}'),
                      id: page.id,
                      label: page.name,
                    ),
                    _ => SuperPage(
                      key: ValueKey('editor-page-${page.id}'),
                      id: page.id,
                      label: page.name,
                      pageConfig: ScaffoldPageConfig(),
                    ),
                  },
                );
                return pageWrapper?.call(context, state, child) ?? child;
              },
      );
      final parameters = _parameters(route);
      if (parameters.toSet().length != parameters.length) {
        throw const FormatException(
          'Les paramètres du chemin doivent être uniques.',
        );
      }
      return route;
    } on FormatException {
      rethrow;
    } on ArgumentError {
      throw FormatException(
        'Chemin ou expression régulière invalide : ${page.path}',
      );
    } on AssertionError {
      throw FormatException('Chemin GoRouter invalide : ${page.path}');
    }
  }

  void _validatePathConstraints(String path) {
    var offset = 0;
    for (final parameter in RegExp(r':\w+').allMatches(path)) {
      if (parameter.start < offset) continue;
      final start = parameter.end;
      if (start >= path.length || path[start] != '(') continue;
      final end = _constraintEnd(path, start);
      if (end == null) {
        throw FormatException('Expression régulière invalide : $path');
      }
      final expression = path.substring(start + 1, end - 1);
      try {
        RegExp(expression);
      } on FormatException {
        throw FormatException('Expression régulière invalide : $path');
      }
      offset = end;
    }
  }

  List<String> _parameters(GoRoute route) {
    final names = <String>[];
    final tokens = RegExp(r':(\w+)');
    var offset = 0;
    for (final name in tokens.allMatches(route.path)) {
      if (name.start < offset) continue;
      names.add(name[1]!);
      offset = _constraintEnd(route.path, name.end) ?? name.end;
    }
    return names;
  }

  // GoRouter constraints allow escaped characters, but not nested groups.
  int? _constraintEnd(String path, int start) {
    if (start >= path.length || path[start] != '(') return null;
    for (var i = start + 1; i < path.length; i++) {
      if (path[i] == r'\') {
        i++;
      } else if (path[i] == '(') {
        return null;
      } else if (path[i] == ')') {
        return i == start + 1 ? null : i + 1;
      }
    }
    return null;
  }

  bool _hasInvalidLiteral(String path) {
    for (var i = 0; i < path.length; i++) {
      final char = path[i];
      if (char == ':') {
        final name = RegExp(r':\w+').matchAsPrefix(path, i);
        final end = name == null ? null : _constraintEnd(path, name.end);
        if (end != null) {
          i = end - 1;
          continue;
        }
      }
      if (char == '?' || char == '#' || RegExp(r'\s').hasMatch(char)) {
        return true;
      }
    }
    return false;
  }

  List<String> parametersOf(EditorPageConfig page) =>
      List.unmodifiable(_parameters(routeFor(page)));

  /// GoRouter itself constructs and matches concrete parameterized locations.
  String locationFor(EditorPageConfig page, Map<String, String> parameters) {
    final route = routeFor(page);
    final names = _parameters(route);
    if (parameters.length != names.length ||
        names.any((key) => parameters[key]?.isNotEmpty != true)) {
      throw const FormatException(
        'Renseignez tous les paramètres, sans paramètre supplémentaire.',
      );
    }
    final temporary = GoRouter(
      initialLocation: '/',
      overridePlatformDefaultLocation: true,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
        route,
      ],
    );
    try {
      final location = temporary.namedLocation(
        _routeName(page.id),
        pathParameters: parameters,
      );
      final match = temporary.configuration.findMatch(Uri.parse(location));
      if (match.isError ||
          match.last.route != route ||
          parameters.entries.any(
            (entry) => match.pathParameters[entry.key] != entry.value,
          )) {
        throw const FormatException(
          'Les valeurs ne respectent pas les contraintes du chemin.',
        );
      }
      return location;
    } finally {
      temporary.dispose();
    }
  }

  bool _matches(GoRoute route, String path) {
    final match = route.matchPatternAsPrefix(path);
    return match != null && match.group(0) == path;
  }

  String _joinRoutePath(String parent, String child) {
    final segment = child.startsWith('/') ? child.substring(1) : child;
    if (segment.isEmpty) return parent.isEmpty ? '/' : parent;
    if (parent.isEmpty || parent == '/') return '/$segment';
    return '$parent/$segment';
  }

  List<GoRoute> _codedRoutes() {
    final result = <GoRoute>[];
    void visit(List<RouteBase> routes, String parent, bool sensitive) {
      for (final route in routes) {
        if (route is GoRoute) {
          final path = _joinRoutePath(parent, route.path);
          result.add(
            GoRoute(
              path: path,
              caseSensitive: sensitive && route.caseSensitive,
              builder: (_, _) => const SizedBox.shrink(),
            ),
          );
          visit(route.routes, path, sensitive && route.caseSensitive);
        } else {
          visit(route.routes, parent, sensitive);
        }
      }
    }

    visit(baseConfig.routes, '', true);
    return result;
  }

  List<EditorCodedRoute> get codedRoutes {
    final result = <EditorCodedRoute>[];
    void visit(List<RouteBase> routes, String parent, bool sensitive) {
      for (final route in routes) {
        if (route is GoRoute) {
          final path = _joinRoutePath(parent, route.path);
          final caseSensitive = sensitive && route.caseSensitive;
          final pathRoute = GoRoute(
            path: path,
            builder: (_, _) => const SizedBox.shrink(),
          );
          result.add(
            EditorCodedRoute._(
              path: path,
              name: route.name,
              parameters: List.unmodifiable(_parameters(pathRoute)),
              caseSensitive: caseSensitive,
              sourceRoute: route,
            ),
          );
          visit(route.routes, path, caseSensitive);
        } else {
          visit(route.routes, parent, sensitive);
        }
      }
    }

    visit(baseConfig.routes, '', true);
    return List.unmodifiable(result);
  }

  /// Resolves a code-defined route with GoRouter's URL encoding and constraints.
  String locationForCodedRoute(
    EditorCodedRoute codedRoute,
    Map<String, String> parameters,
  ) {
    if (parameters.length != codedRoute.parameters.length ||
        codedRoute.parameters.any(
          (key) => parameters[key]?.isNotEmpty != true,
        )) {
      throw const FormatException(
        'Renseignez tous les paramètres, sans paramètre supplémentaire.',
      );
    }
    final route = GoRoute(
      path: codedRoute.path,
      name: '__coded_page_open',
      caseSensitive: codedRoute.caseSensitive,
      builder: (_, _) => const SizedBox.shrink(),
    );
    final temporary = GoRouter(
      initialLocation: '/',
      overridePlatformDefaultLocation: true,
      routes: codedRoute.path == '/'
          ? [route]
          : [
              GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
              route,
            ],
    );
    try {
      final location = temporary.namedLocation(
        '__coded_page_open',
        pathParameters: parameters,
      );
      final match = temporary.configuration.findMatch(Uri.parse(location));
      final actualMatch = router.configuration.findMatch(Uri.parse(location));
      if (match.isError ||
          match.last.route != route ||
          actualMatch.isError ||
          actualMatch.last.route != codedRoute._sourceRoute ||
          parameters.entries.any(
            (entry) => match.pathParameters[entry.key] != entry.value,
          )) {
        throw const FormatException(
          'Les valeurs ne respectent pas les contraintes du chemin.',
        );
      }
      return location;
    } finally {
      temporary.dispose();
    }
  }

  bool _mayOverlap(GoRoute a, GoRoute b) {
    if (!a.caseSensitive || !b.caseSensitive) {
      GoRoute insensitive(GoRoute route) => GoRoute(
        path: route.path,
        caseSensitive: false,
        builder: (_, _) => const SizedBox.shrink(),
      );
      a = insensitive(a);
      b = insensitive(b);
    }
    if (_parameters(a).isEmpty) return _matches(b, a.path);
    if (_parameters(b).isEmpty) return _matches(a, b.path);
    // Only a conflicting literal prefix proves arbitrary regexes disjoint.
    final left = a.path.substring(0, a.path.indexOf(':'));
    final right = b.path.substring(0, b.path.indexOf(':'));
    final length = left.length < right.length ? left.length : right.length;
    final sensitive = a.caseSensitive && b.caseSensitive;
    final l = left.substring(0, length);
    final r = right.substring(0, length);
    return sensitive ? l == r : l.toLowerCase() == r.toLowerCase();
  }

  void validate(EditorPageCatalog catalog) {
    if (identical(catalog, _validatedCatalog)) return;
    final coded = _codedRoutes();
    final accepted = <GoRoute>[];
    final reservedNames = <String>{};
    void names(List<RouteBase> routes) {
      for (final route in routes) {
        if (route is GoRoute && route.name != null) {
          reservedNames.add(route.name!);
        }
        names(route.routes);
      }
    }

    names(baseConfig.routes);
    for (final page in catalog.pages) {
      final route = routeFor(page);
      if (reservedNames.contains(route.name)) {
        throw FormatException(
          'Nom technique de route déjà utilisé : ${page.id}',
        );
      }
      for (final other in [...coded, ...accepted]) {
        if (_mayOverlap(route, other)) {
          throw FormatException(
            'Conflit possible entre ${page.path} et ${other.path}. '
            'L’absence de chevauchement doit être garantie, notamment pour les regex.',
          );
        }
      }
      accepted.add(route);
      if (page.defaultParameters.isNotEmpty || catalog.homePageId == page.id) {
        locationFor(page, page.defaultParameters);
      }
    }
    _validatedCatalog = catalog;
  }

  EditorPageConfig? pageAt(Uri uri, {EditorPageCatalog? catalog}) {
    for (final page in (catalog ?? _catalog).pages) {
      if (_matches(routeFor(page), uri.path)) return page;
    }
    return null;
  }

  String _home(EditorPageCatalog catalog) {
    for (final page in catalog.pages) {
      if (page.id == catalog.homePageId) {
        return locationFor(page, page.defaultParameters);
      }
    }
    return '/';
  }

  /// Returns a visible explanation when the current destination was removed.
  String? synchronize(EditorPageCatalog catalog) {
    validate(catalog);
    if (_initialized && identical(catalog, _catalog)) return null;
    final current = _initialized
        ? router.routeInformationProvider.value.uri
        : _initialUri;
    final oldPage = pageAt(current);
    String? destination;
    String? notice;
    if (!_initialized) {
      destination = current.path == '/' ? _home(catalog) : current.toString();
    } else if (oldPage != null) {
      final replacement = catalog.pages
          .where((page) => page.id == oldPage.id)
          .firstOrNull;
      if (replacement == null) {
        destination = _home(catalog);
        notice = 'La page courante a été supprimée. Retour à l’accueil.';
      } else if (replacement.path != oldPage.path) {
        final oldRoute = routeFor(oldPage);
        final match = oldRoute.matchPatternAsPrefix(current.path)!;
        final parameters = oldRoute
            .extractPathParams(match)
            .map((key, value) => MapEntry(key, Uri.decodeComponent(value)));
        try {
          destination = locationFor(replacement, parameters);
          final uri = Uri.parse(destination);
          destination = uri
              .replace(
                query: current.hasQuery ? current.query : null,
                fragment: current.hasFragment ? current.fragment : null,
              )
              .toString();
        } on FormatException {
          destination = _home(catalog);
          notice = 'Le chemin a changé et les paramètres ne sont plus valides. Retour à l’accueil.';
        }
      }
    }
    _catalog = catalog;
    _initialized = true;
    _routing.value = RoutingConfig(
      routes: [...baseConfig.routes, ...catalog.pages.map(routeFor)],
      redirect: baseConfig.redirect,
      redirectLimit: baseConfig.redirectLimit,
      onEnter: baseConfig.onEnter,
    );
    if (destination != null) router.go(destination);
    return notice;
  }

  void dispose() {
    router.dispose();
    _routing.dispose();
  }
}

class _OnDemandEditorPage extends StatefulWidget {
  const _OnDemandEditorPage({
    required this.pageId,
    required this.builder,
    this.isPageLoaded,
    this.loadPage,
  });

  final String pageId;
  final WidgetBuilder builder;
  final bool Function(String pageId)? isPageLoaded;
  final Future<void> Function(String pageId)? loadPage;

  @override
  State<_OnDemandEditorPage> createState() => _OnDemandEditorPageState();
}

class _OnDemandEditorPageState extends State<_OnDemandEditorPage> {
  bool _loading = false;
  Object? _error;
  int _requestToken = 0;

  PersistentAppearanceController? _controller() {
    final notifier = context
        .getInheritedWidgetOfExactType<AppearanceScope>()
        ?.notifier;
    return notifier is PersistentAppearanceController ? notifier : null;
  }

  bool _isLoaded() {
    if (widget.loadPage != null) {
      return widget.isPageLoaded?.call(widget.pageId) ?? false;
    }
    final controller = _controller();
    if (controller == null) return true;
    return controller.isPageLoaded(widget.pageId);
  }

  Future<void> Function()? _resolveLoader() {
    if (widget.loadPage != null) {
      return () => widget.loadPage!(widget.pageId);
    }
    final controller = _controller();
    if (controller == null) return null;
    return () => controller.ensurePageLoaded(widget.pageId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(_OnDemandEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageId != widget.pageId ||
        oldWidget.loadPage != widget.loadPage ||
        oldWidget.isPageLoaded != widget.isPageLoaded) {
      _requestToken++;
      _loading = false;
      _error = null;
      _ensureLoaded();
    }
  }

  void _ensureLoaded() {
    if (_loading || _error != null || _isLoaded()) return;
    final loader = _resolveLoader();
    if (loader == null) return;
    final token = ++_requestToken;
    _loading = true;
    _error = null;
    unawaited(
      loader()
          .then((_) {
            if (!mounted || token != _requestToken) return;
            setState(() => _loading = false);
          })
          .catchError((Object error, StackTrace _) {
            if (!mounted || token != _requestToken) return;
            setState(() {
              _loading = false;
              _error = error;
            });
          }),
    );
  }

  void _retry() {
    setState(() {
      _error = null;
      _ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Material(
        type: MaterialType.transparency,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Impossible de charger la page : $_error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _retry,
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_loading || !_isLoaded()) {
      return const Material(
        type: MaterialType.transparency,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.builder(context);
  }
}

Widget _wrapWithModalClose(BuildContext context, Widget child) => Stack(
  children: [
    Positioned.fill(child: child),
    Positioned(
      top: 8,
      right: 8,
      child: Material(
        type: MaterialType.transparency,
        child: IconButton(
          key: const ValueKey('editor-modal-page-close'),
          tooltip: 'Fermer',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              GoRouter.maybeOf(context)?.go('/');
            }
          },
          icon: const Icon(Icons.close, size: 20),
        ),
      ),
    ),
  ],
);

class _EditorDialogPage extends Page<void> {
  const _EditorDialogPage({
    required this.child,
    this.width,
    this.height,
    super.key,
  });

  final Widget child;
  final double? width;
  final double? height;

  @override
  Route<void> createRoute(BuildContext context) => DialogRoute<void>(
    context: context,
    settings: this,
    barrierDismissible: true,
    builder: (dialogContext) {
      final viewport = MediaQuery.sizeOf(dialogContext);
      final targetWidth = math.min(width ?? 640.0, math.max(240.0, viewport.width - 48));
      final targetHeight = math.min(height ?? 520.0, math.max(220.0, viewport.height - 48));
      return Dialog(
        key: const ValueKey('editor-dialog-page-container'),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: targetWidth,
          height: targetHeight,
          child: _wrapWithModalClose(dialogContext, child),
        ),
      );
    },
  );
}

class _EditorBottomSheetPage extends Page<void> {
  const _EditorBottomSheetPage({
    required this.child,
    this.height,
    super.key,
  });

  final Widget child;
  final double? height;

  @override
  Route<void> createRoute(BuildContext context) => ModalBottomSheetRoute<void>(
    settings: this,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    clipBehavior: Clip.antiAlias,
    builder: (sheetContext) {
      final viewportHeight = MediaQuery.sizeOf(sheetContext).height;
      final targetHeight = math.min(
        height ?? viewportHeight * 0.72,
        math.max(220.0, viewportHeight - 48),
      );
      return SizedBox(
        key: const ValueKey('editor-bottom-sheet-page-container'),
        height: targetHeight,
        child: _wrapWithModalClose(sheetContext, child),
      );
    },
  );
}

class _EditorSideSheetPage extends Page<void> {
  const _EditorSideSheetPage({
    required this.child,
    this.width,
    super.key,
  });

  final Widget child;
  final double? width;

  @override
  Route<void> createRoute(BuildContext context) => RawDialogRoute<void>(
    settings: this,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (sheetContext, _, _) {
      final viewportWidth = MediaQuery.sizeOf(sheetContext).width;
      final targetWidth = math.min(
        width ?? 420.0,
        math.max(240.0, viewportWidth - 32),
      );
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          key: const ValueKey('editor-side-sheet-page-container'),
          elevation: 16,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
          child: SizedBox(
            width: targetWidth,
            height: double.infinity,
            child: _wrapWithModalClose(sheetContext, child),
          ),
        ),
      );
    },
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      ),
      child: child,
    ),
  );
}
