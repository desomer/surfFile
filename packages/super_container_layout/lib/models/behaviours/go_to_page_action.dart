/// Action de comportement de navigation vers une page ([GoToPageAction]).
///
/// Pilote le routeur de [SuperApp] ou le [GoRouter] ambiant lorsqu'un geste
/// utilisateur déclenche le comportement associé, en sélectionnant le mode
/// `go` ou `push` selon [GoToPageNavigationMode] et le contexte de shell actif.
library;

import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../super_app.dart';
import '../../widgets/appearance/appearance_scope.dart';
import '../../widgets/appearance/super_shell_scope.dart';
import '../component_behavior.dart';
import '../editor_page_config.dart';

/// Stratégie de navigation appliquée par [GoToPageAction].
enum GoToPageNavigationMode {
  /// Choisit automatiquement : `push` pour les pages modales, `go` dès qu'un
  /// shell partagé est impliqué, sinon `push` entre pages autonomes.
  auto('Automatique'),

  /// Remplace la route courante (`router.go`) sans empiler d'entrée dans la pile.
  go('Remplacer (go)'),

  /// Empile la destination au-dessus de la route courante (`router.push`).
  push('Empiler (push)');

  const GoToPageNavigationMode(this.label);

  /// Libellé affiché dans l'éditeur de comportement.
  final String label;

  /// Décode un [GoToPageNavigationMode] depuis son nom JSON (`auto`, `go`, `push`).
  static GoToPageNavigationMode fromName(Object? value) => switch (value) {
    null || 'auto' => GoToPageNavigationMode.auto,
    'go' => GoToPageNavigationMode.go,
    'push' => GoToPageNavigationMode.push,
    _ => throw FormatException('Mode de navigation invalide : $value.'),
  };
}

/// Action de navigation vers une page.
@immutable
class GoToPageAction extends BehaviorAction {
  /// Crée une action de navigation vers [pagePath].
  const GoToPageAction({
    required this.pagePath,
    this.pageId,
    this.pageName,
    this.navigationMode = GoToPageNavigationMode.auto,
  });

  /// Chemin cible (absolu) vers lequel naviguer.
  final String pagePath;

  /// Identifiant optionnel de la page cible dans [EditorPageCatalog].
  final String? pageId;

  /// Libellé lisible optionnel de la page cible.
  final String? pageName;

  /// Mode de navigation (`auto`, `go` ou `push`).
  final GoToPageNavigationMode navigationMode;

  @override
  String get type => 'goToPage';

  @override
  String get label => 'Aller à la page';

  @override
  String get description => pageName != null && pageName!.trim().isNotEmpty
      ? '$pageName ($pagePath)'
      : pagePath;

  @override
  IconData get icon => Icons.alt_route;

  @override
  Future<void> execute(BuildContext context) async {
    final path = pagePath.trim();
    if (path.isEmpty) return;

    final app = SuperApp.maybeOf(context);
    final pageRouting = app?.pageRouting;
    final router = pageRouting?.router ?? app?.router ?? GoRouter.maybeOf(context);
    if (router == null) return;

    final catalog = AppearanceScope.controllerOf(context)?.value.pageCatalog;
    final targetUri = Uri.tryParse(path);
    EditorPageConfig? targetPage;
    if (pageRouting != null && targetUri != null) {
      targetPage = pageRouting.pageAt(targetUri, catalog: catalog);
    }
    if (targetPage == null && catalog != null) {
      if (pageId != null) {
        targetPage = catalog.pages.where((p) => p.id == pageId).firstOrNull;
      }
      targetPage ??= catalog.pages
          .where((p) => p.path == (targetUri?.path ?? path))
          .firstOrNull;
    }

    void goToTarget() {
      if (pageRouting != null && (targetPage == null || !targetPage.pageType.isModal)) {
        pageRouting.openLocation(path);
      } else {
        router.go(path);
      }
    }

    switch (navigationMode) {
      case GoToPageNavigationMode.go:
        goToTarget();
      case GoToPageNavigationMode.push:
        unawaited(router.push<Object?>(path));
      case GoToPageNavigationMode.auto:
        if (targetPage?.pageType.isModal == true) {
          if (pageRouting != null) {
            pageRouting.openLocation(path);
          } else {
            unawaited(router.push<Object?>(path));
          }
          return;
        }
        final isShellNavigation =
            SuperShellScope.isInsideShell(context) ||
            targetPage?.shellId != null ||
            ((targetUri?.path ?? path) == '/' && catalog?.rootShellId != null);
        if (isShellNavigation) {
          goToTarget();
        } else {
          unawaited(router.push<Object?>(path));
        }
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'pagePath': pagePath,
    if (pageId != null) 'pageId': pageId,
    if (pageName != null) 'pageName': pageName,
    if (navigationMode != GoToPageNavigationMode.auto)
      'navigationMode': navigationMode.name,
  };

  factory GoToPageAction.fromJson(Map<String, dynamic> json) {
    final path = (json['pagePath'] ?? json['path'] ?? '') as String;
    return GoToPageAction(
      pagePath: path,
      pageId: json['pageId'] as String?,
      pageName: json['pageName'] as String?,
      navigationMode: GoToPageNavigationMode.fromName(json['navigationMode']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoToPageAction &&
          other.pagePath == pagePath &&
          other.pageId == pageId &&
          other.pageName == pageName &&
          other.navigationMode == navigationMode;

  @override
  int get hashCode => Object.hash(pagePath, pageId, pageName, navigationMode);
}
