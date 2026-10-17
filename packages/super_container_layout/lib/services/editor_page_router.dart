import 'dart:async';
import 'dart:convert';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../models/editor_page_config.dart';
import '../models/scaffold_page_config.dart';
import '../super_page.dart';

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

/// Opt-in routing for editor-created pages. The application owns this object.
class EditorPageRouter {
  EditorPageRouter({
    required this.baseConfig,
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
      final route = GoRoute(
        path: page.path,
        name: _routeName(page.id),
        builder: (_, _) => SuperPage(
          key: ValueKey('editor-page-${page.id}'),
          id: page.id,
          label: page.name,
          pageConfig: ScaffoldPageConfig(),
        ),
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
