/// Action de comportement de navigation vers une page ([GoToPageAction]).
///
/// Pilote le routeur de [SuperApp] ou le [GoRouter] ambiant lorsqu'un geste
/// utilisateur déclenche le comportement associé.
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../super_app.dart';
import '../component_behavior.dart';

/// Action de navigation vers une page.
@immutable
class GoToPageAction extends BehaviorAction {
  const GoToPageAction({required this.pagePath, this.pageId, this.pageName});

  final String pagePath;
  final String? pageId;
  final String? pageName;

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
    if (app?.pageRouting != null) {
      app!.pageRouting!.router.go(path);
      return;
    }
    if (app != null) {
      app.router.go(path);
      return;
    }
    GoRouter.maybeOf(context)?.go(path);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'pagePath': pagePath,
    if (pageId != null) 'pageId': pageId,
    if (pageName != null) 'pageName': pageName,
  };

  factory GoToPageAction.fromJson(Map<String, dynamic> json) {
    final path = (json['pagePath'] ?? json['path'] ?? '') as String;
    return GoToPageAction(
      pagePath: path,
      pageId: json['pageId'] as String?,
      pageName: json['pageName'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoToPageAction &&
          other.pagePath == pagePath &&
          other.pageId == pageId &&
          other.pageName == pageName;

  @override
  int get hashCode => Object.hash(pagePath, pageId, pageName);
}
