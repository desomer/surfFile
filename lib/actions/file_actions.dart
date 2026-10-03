import 'package:material_ui/material_ui.dart';

import '../services/file_operations.dart';

/// État d'un volet de navigation exposé aux actions.
@immutable
class PaneSnapshot {
  const PaneSnapshot({required this.path, this.selection = const []});

  final String path;
  final List<String> selection;
}

/// Ce que voit une [FileAction] : les deux volets et de quoi les piloter.
class FileActionContext {
  const FileActionContext({
    required this.left,
    required this.right,
    required this.navigate,
    required this.refresh,
  });

  final PaneSnapshot left;
  final PaneSnapshot right;

  /// Ouvre [left] et [right] dans les volets correspondants.
  final Future<void> Function(String left, String right) navigate;

  /// Recharge le contenu des deux volets.
  final Future<void> Function() refresh;
}

/// Action déclenchable depuis la barre d'actions entre les deux volets.
///
/// Pour ajouter une action : sous-classer et l'ajouter à [FileAction.split].
abstract class FileAction {
  const FileAction();

  /// Actions affichées, dans l'ordre, dans la barre de la vue partagée.
  static const split = <FileAction>[
    SwapPanesAction(),
    CopyToRightAction(),
    MoveToRightAction(),
  ];

  String get id;
  String get label;
  IconData get icon;

  bool isEnabled(FileActionContext context) => true;

  /// Exécute l'action et renvoie un message éventuel pour l'utilisateur.
  Future<String?> run(FileActionContext context);
}

class SwapPanesAction extends FileAction {
  const SwapPanesAction();

  @override
  String get id => 'swap';
  @override
  String get label => 'Échanger les volets';
  @override
  IconData get icon => Icons.swap_horiz_rounded;

  @override
  bool isEnabled(FileActionContext context) =>
      context.left.path != context.right.path;

  @override
  Future<String?> run(FileActionContext context) async {
    await context.navigate(context.right.path, context.left.path);
    return null;
  }
}

/// Base des transferts de la sélection du volet gauche vers le droit.
abstract class TransferToRightAction extends FileAction {
  const TransferToRightAction();

  Future<String> transfer(String source, String destinationDir);
  String done(int count);

  @override
  bool isEnabled(FileActionContext context) =>
      context.left.selection.isNotEmpty &&
      context.left.path != context.right.path;

  @override
  Future<String?> run(FileActionContext context) async {
    final selection = context.left.selection;
    try {
      for (final path in selection) {
        await transfer(path, context.right.path);
      }
    } finally {
      await context.refresh();
    }
    return done(selection.length);
  }
}

class CopyToRightAction extends TransferToRightAction {
  const CopyToRightAction();

  @override
  String get id => 'copy-right';
  @override
  String get label => 'Copier vers la droite';
  @override
  IconData get icon => Icons.copy_all_rounded;

  @override
  Future<String> transfer(String source, String destinationDir) =>
      FileOperations.copy(source, destinationDir);

  @override
  String done(int count) =>
      '$count élément${count == 1 ? ' copié' : 's copiés'}';
}

class MoveToRightAction extends TransferToRightAction {
  const MoveToRightAction();

  @override
  String get id => 'move-right';
  @override
  String get label => 'Déplacer vers la droite';
  @override
  IconData get icon => Icons.drive_file_move_outline;

  @override
  Future<String> transfer(String source, String destinationDir) =>
      FileOperations.move(source, destinationDir);

  @override
  String done(int count) =>
      '$count élément${count == 1 ? ' déplacé' : 's déplacés'}';
}
