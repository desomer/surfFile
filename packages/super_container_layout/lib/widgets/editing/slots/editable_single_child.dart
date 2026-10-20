import 'package:material_ui/material_ui.dart';

import '../../../models/native_component_config.dart';
import '../../../models/registry.dart' show EditorConfigKind;
import '../../../super_app.dart';
import '../../native/native_component_editor.dart';
import '../../super_layout/slot_implementation.dart';
import 'editor_slot.dart';
import '../dialogs/editor_dialog.dart';
import 'slot_removal.dart';

/// Manages an optional registry-backed component in a single child region.
class EditableSingleChild extends StatefulWidget {
  const EditableSingleChild({
    required this.id,
    required this.label,
    required this.child,
    required this.builder,
    super.key,
  });

  final String id;
  final String label;
  final Widget? child;

  /// Receives the resolved child, whether it exists, and the recursive-safe
  /// removal callback. The editor checks child menu ownership at menu time.
  final Widget Function(
    BuildContext context,
    Widget child,
    bool hasChild,
    Future<void> Function() removeChild,
  )
  builder;

  @override
  State<EditableSingleChild> createState() => EditableSingleChildState();
}

class EditableSingleChildState extends State<EditableSingleChild> {
  final _editor = GlobalKey<NativeComponentEditorState>();
  late final _local = ValueNotifier(_initial);
  static const _providedId = '__provided-child';

  NativeComponentConfig get _initial => NativeComponentConfig(
    placements: {
      if (widget.child != null) 'child': [_providedId],
    },
  );

  ValueNotifier<NativeComponentConfig> get _config =>
      SuperApp.maybeOf(context)?.registry
          ?.nativeComponentController(widget.id, fallback: _initial) ??
      _local;

  bool get hasChild => _config.value.slotsOf('child').isNotEmpty;

  void remove() {
    final current = _config.value;
    if (hasChild) {
      final id = current.slotsOf('child').single;
      removeSlotInstance(
        context,
        id: id,
        type: current.slotTypeOf(id),
        containerKind: EditorConfigKind.nativeComponent,
        unplace: () => _config.value = current.withoutSlot(id),
      );
    }
  }

  @override
  void didUpdateWidget(EditableSingleChild oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _local.value = _initial;
  }

  Future<void> add() async {
    if (hasChild) {
      final confirmed = await showEditorDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remplacer le composant enfant ?'),
          content: const Text(
            'Le conteneur ne peut contenir qu’un seul composant. '
            'Le nouveau composant remplacera le contenu actuel.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remplacer'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _editor.currentState?.add('child');
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final controller = _config;
    return ValueListenableBuilder<NativeComponentConfig>(
      valueListenable: controller,
      builder: (context, config, _) => NativeComponentEditor(
        key: _editor,
        label: widget.label,
        keyPrefix: 'super-container-${widget.id}',
        settingsTitle: 'Configurer le contenu',
        config: config,
        onChanged: (value) => controller.value = value,
        registry: registry,
        regions: const [
          NativeRegion('child', 'Enfant', required: true, single: true),
        ],
        slots: [
          if (widget.child case final child?)
            BuilderSlot(
              id: _providedId,
              label: 'Contenu initial',
              builder: (_) => child,
            ),
        ],
        builder: (context, editor) {
          final children = editor.slotsFor('child');
          final child = children.isEmpty
              ? const SizedBox.expand()
              : children.single;
          return widget.builder(
            context,
            EditorSlotAction(
              label: 'Composant enfant : ${widget.label}',
              inline: true,
              showEdit: false,
              enabled: children.isNotEmpty,
              onEdit: () async {},
              onRemove: children.isEmpty ? null : () async => remove(),
              child: child,
            ),
            children.isNotEmpty,
            () async => remove(),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _local.dispose();
    super.dispose();
  }
}
