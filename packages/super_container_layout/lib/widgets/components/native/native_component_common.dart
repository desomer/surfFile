/// Contrat et utilitaires partagés pour les composants Material natifs ([NativePreferredSizeWidget]).
///
/// Fournit la résolution des slots par région, l'adaptation des [SuperAction] en destinations
/// ainsi que la synchronisation réactive avec la route courante (`GoRouter` / [EditorPageRouter]).
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/component_behavior.dart';
import '../../../super_app.dart';
import '../../appearance/appearance_scope.dart';
import '../super_action.dart';
import '../super_layout/slot_implementation.dart';

Uri? _uriFromGoRouter(GoRouter router) {
  final config = router.routerDelegate.currentConfiguration;
  final providerUri = router.routeInformationProvider.value.uri;
  if (config.matches.isNotEmpty) {
    final last = config.matches.last;
    if (last is ImperativeRouteMatch && config.uri == providerUri) {
      return last.matches.uri;
    }
  }
  return providerUri;
}

String _normalizeRoutePath(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return '';
  var path = trimmed.contains('://')
      ? (Uri.tryParse(trimmed)?.path ?? trimmed)
      : trimmed.split(RegExp(r'[?#]')).first;
  if (path.isEmpty) return '/';
  path = path.replaceAll(RegExp(r'/+'), '/');
  if (!path.startsWith('/')) path = '/$path';
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

List<String> _routeSegments(String normalizedPath) {
  if (normalizedPath.isEmpty || normalizedPath == '/') return const [];
  return normalizedPath.substring(1).split('/');
}

bool _isParameterizedSegment(String segment) => segment.startsWith(':');

/// Résout de manière sûre l'URI de la route courante depuis [context].
///
/// Consulte successivement `SuperApp.pageRouting.currentUri`, `SuperApp.router`,
/// `GoRouter.maybeOf(context)` puis `GoRouterState.maybeOf(context)`.
Uri? currentRouteUri(BuildContext context) {
  final app = context.getInheritedWidgetOfExactType<SuperAppScope>()?.app;
  final pageRouting = app?.pageRouting;
  if (pageRouting != null) {
    return pageRouting.currentUri;
  }
  if (app != null) {
    return _uriFromGoRouter(app.router);
  }
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    return _uriFromGoRouter(router);
  }
  try {
    return GoRouterState.of(context).uri;
  } on Object {
    return null;
  }
}

/// Retourne le [Listenable] du routeur courant afin de reconstruire automatiquement
/// les composants de navigation lors d'un changement de route.
Listenable? currentRouteListenable(BuildContext context) {
  final app = context.getInheritedWidgetOfExactType<SuperAppScope>()?.app;
  final router =
      app?.pageRouting?.router ?? app?.router ?? GoRouter.maybeOf(context);
  return router?.routerDelegate;
}

/// Indique si [currentUri] correspond au chemin cible [targetPath].
///
/// La racine `'/'` requiert une correspondance exacte afin de ne pas masquer les
/// sous-routes ; les chemins statiques ou paramétrés (`'/clients'`, `'/clients/:id'`)
/// correspondent de manière exacte ou par préfixe de segments complets.
bool matchesRoutePath(Uri? currentUri, String targetPath) {
  if (currentUri == null) return false;
  final normalizedTarget = _normalizeRoutePath(targetPath);
  if (normalizedTarget.isEmpty) return false;
  final normalizedCurrent = _normalizeRoutePath(
    currentUri.path.isEmpty ? '/' : currentUri.path,
  );
  if (normalizedTarget == '/') {
    return normalizedCurrent == '/';
  }
  if (normalizedCurrent == normalizedTarget) return true;
  final targetSegments = _routeSegments(normalizedTarget);
  final currentSegments = _routeSegments(normalizedCurrent);
  if (currentSegments.length < targetSegments.length) return false;
  for (var i = 0; i < targetSegments.length; i++) {
    final targetSegment = targetSegments[i];
    if (_isParameterizedSegment(targetSegment)) {
      if (currentSegments[i].isEmpty) return false;
      continue;
    }
    if (currentSegments[i] != targetSegment) return false;
  }
  return true;
}

/// Retourne le chemin cible ([GoToPageAction.pagePath]) du premier comportement
/// de navigation actif associé à [componentId], ou `null` si aucun n'existe.
///
/// Lit les comportements dans `AppearanceScope` (avec repli sur [widgetBehaviors]).
String? goToPagePathForComponent(
  BuildContext context,
  String componentId, {
  List<ComponentBehavior>? widgetBehaviors,
  bool listen = true,
}) {
  final appearance = listen
      ? AppearanceScope.controllerOf(context)?.value
      : context
            .getInheritedWidgetOfExactType<AppearanceScope>()
            ?.notifier
            ?.value;
  final appearanceBehaviors = appearance?.behaviors[componentId];
  final behaviors =
      (appearanceBehaviors != null && appearanceBehaviors.isNotEmpty)
      ? appearanceBehaviors
      : (widgetBehaviors ?? const <ComponentBehavior>[]);
  for (final behavior in behaviors) {
    if (!behavior.enabled) continue;
    if (behavior.event != BehaviorEvent.onTap &&
        behavior.event != BehaviorEvent.onSelected) {
      continue;
    }
    final action = behavior.action;
    if (action is GoToPageAction) {
      final path = action.pagePath.trim();
      if (path.isNotEmpty) return path;
    }
  }
  return null;
}

/// Retourne l'indice de la destination dans [slots] dont le [GoToPageAction]
/// correspond le mieux à la route courante, ou `null` si aucune ne correspond.
///
/// Privilégie une correspondance exacte sur un préfixe, puis le préfixe le plus
/// spécifique (plus grand nombre de segments et segments statiques).
int? activeDestinationIndexForRoute(
  BuildContext context,
  List<SlotImplementation> slots,
  Map<String, SuperAction> supplied,
) {
  final uri = currentRouteUri(context);
  if (uri == null || slots.isEmpty) return null;
  final normalizedCurrent = _normalizeRoutePath(
    uri.path.isEmpty ? '/' : uri.path,
  );
  final currentSegments = _routeSegments(normalizedCurrent);

  int? bestIndex;
  var bestRank = -1;
  var bestSegmentCount = -1;
  var bestStaticCount = -1;
  var bestLength = -1;

  for (final (index, slot) in slots.indexed) {
    final targetPath = goToPagePathForComponent(
      context,
      slot.id,
      widgetBehaviors: supplied[slot.id]?.behaviours,
    );
    if (targetPath == null || !matchesRoutePath(uri, targetPath)) {
      continue;
    }
    final normalizedTarget = _normalizeRoutePath(targetPath);
    final targetSegments = _routeSegments(normalizedTarget);
    final staticCount = targetSegments
        .where((segment) => !_isParameterizedSegment(segment))
        .length;
    final rank = normalizedTarget == normalizedCurrent
        ? 3
        : targetSegments.length == currentSegments.length
        ? 2
        : 1;
    final isBetter =
        rank > bestRank ||
        (rank == bestRank && targetSegments.length > bestSegmentCount) ||
        (rank == bestRank &&
            targetSegments.length == bestSegmentCount &&
            staticCount > bestStaticCount) ||
        (rank == bestRank &&
            targetSegments.length == bestSegmentCount &&
            staticCount == bestStaticCount &&
            normalizedTarget.length > bestLength);
    if (isBetter) {
      bestIndex = index;
      bestRank = rank;
      bestSegmentCount = targetSegments.length;
      bestStaticCount = staticCount;
      bestLength = normalizedTarget.length;
    }
  }
  return bestIndex;
}

/// Builds an ID-keyed map of supplied [SuperAction] destinations.
Map<String, SuperAction> suppliedActionDestinationMap(
  Iterable<SuperAction> destinations, [
  List<SlotImplementation> extraSlots = const [],
  BuildContext? context,
]) {
  final actions = <String, SuperAction>{
    for (final action in destinations) action.id: action,
  };
  if (context != null) {
    for (final slot in extraSlots) {
      if (slot is BuilderSlot) {
        try {
          final built = slot.builder(context);
          if (built is SuperAction) {
            actions.putIfAbsent(slot.id, () => built);
            if (built.id.isNotEmpty) {
              actions.putIfAbsent(built.id, () => built);
            }
          }
        } on Object {
          // Ignore les builders dependant d'un InheritedWidget non monte.
        }
      }
    }
  }
  return actions;
}

/// Wraps supplied [SuperAction] destinations as [BuilderSlot]s followed by [extraSlots].
List<SlotImplementation> buildActionDestinationSlots(
  Iterable<SuperAction> destinations,
  List<SlotImplementation> extraSlots,
) => [
  for (final action in destinations)
    BuilderSlot(
      id: action.id,
      label: action.config.label,
      tags: const {'action', 'button', 'input'},
      sizing: SlotSizing.intrinsic,
      builder: (_) => action,
    ),
  ...extraSlots,
];

/// Computes target and effective heights for bottom bars accounting for system bottom inset.
({double targetHeight, double effectiveHeight}) resolveBottomBarHeights(
  BoxConstraints constraints,
  double baseHeight,
  double bottomPadding,
) {
  final targetHeight = constraints.hasTightHeight
      ? constraints.maxHeight
      : (baseHeight + bottomPadding).clamp(
          constraints.minHeight,
          constraints.maxHeight,
        );
  final resolvedHeight = targetHeight - bottomPadding;
  final effectiveHeight = resolvedHeight.isFinite && resolvedHeight > 0
      ? resolvedHeight
      : baseHeight;
  return (targetHeight: targetHeight, effectiveHeight: effectiveHeight);
}
