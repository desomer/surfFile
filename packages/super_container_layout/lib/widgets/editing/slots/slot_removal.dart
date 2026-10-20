import 'package:material_ui/material_ui.dart';

import '../../../models/registry.dart';
import '../../../super_app.dart';
import '../history/editor_history.dart';

/// Unplaces the slot instance [id] with [unplace], then recursively deletes
/// the persisted configurations of its now orphaned subtree, as a single
/// undoable edit.
void removeSlotInstance(
  BuildContext context, {
  required String id,
  required String type,
  required EditorConfigKind containerKind,
  required VoidCallback unplace,
}) {
  final registry = SuperApp.maybeOf(context)?.registry;
  final history = EditorHistoryScope.controllerOf(context);
  history?.beginTransaction();
  try {
    unplace();
    registry?.purgeInstance(id, type, containerKind);
  } finally {
    history?.commitTransaction();
  }
}
