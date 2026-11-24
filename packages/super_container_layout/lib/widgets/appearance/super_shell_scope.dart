/// Portée héritée ([SuperShellScope]) indiquant qu'une sous-arborescence est montée
/// à l'intérieur d'un shell partagé ([SuperScaffold] via `ShellRoute`).
///
/// Permet aux routes enfants (notamment [SuperPage] racine `'/'`, [GoToPageAction]
/// et les enveloppes d'application hôte) d'éviter la duplication du `Scaffold`
/// externe ou de la barre d'outils flottante, et d'adapter le mode de navigation.
library;

import 'package:material_ui/material_ui.dart';

/// Portée `InheritedWidget` exposant l'identifiant du shell actif aux routes enfants.
@immutable
class SuperShellScope extends InheritedWidget {
  /// Crée une portée de shell partagé identifiée par [shellId].
  const SuperShellScope({
    required this.shellId,
    this.wrapsAppearanceShell = false,
    required super.child,
    super.key,
  });

  /// Identifiant du shell ([EditorShellConfig.id]) englobant la route active.
  final String shellId;

  /// Indique que la route de shell a déjà appliqué le wrapper d'apparence
  /// (`pageWrapper`) autour du [SuperScaffold].
  final bool wrapsAppearanceShell;

  /// Retourne la portée [SuperShellScope] englobante la plus proche, ou `null`.
  static SuperShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperShellScope>();

  /// Indique si [context] se trouve à l'intérieur d'un shell partagé.
  static bool isInsideShell(BuildContext context) => maybeOf(context) != null;

  @override
  bool updateShouldNotify(SuperShellScope oldWidget) =>
      shellId != oldWidget.shellId ||
      wrapsAppearanceShell != oldWidget.wrapsAppearanceShell;
}
