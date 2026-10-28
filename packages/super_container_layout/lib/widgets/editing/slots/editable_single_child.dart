import 'package:material_ui/material_ui.dart';

import '../../../models/native_component_config.dart';
import '../../../models/registry.dart' show EditorConfigKind;
import '../../../super_app.dart';
import '../components/native_component_editor.dart';
import '../../components/super_layout/layout_selection.dart';
import '../../components/super_layout/slot_implementation.dart';
import 'editor_selection_region.dart';
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
  final _childKey = GlobalKey();
  late final _local = ValueNotifier(_initial);
  static const _providedId = '__provided-child';

  String? _childEditorLabel() {
    final root = _childKey.currentContext;
    if (root == null) return null;
    EditorSlotState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditorSlotState) {
        final state = element.state as EditorSlotState;
        if (state.canEdit) {
          found = state;
          return;
        }
      }
      element.visitChildren(visit);
    }

    root.visitChildElements(visit);
    return found?.label;
  }

  String _resolveSlotLabel(SlotImplementation slot) {
    if (slot.id == _providedId && !(slot is InstanceSlot && slot.overridden)) {
      return _childEditorLabel() ?? slot.label;
    }
    return slot.label;
  }

  bool _isSlotSelectable(SlotImplementation slot) {
    if (slot.id == _providedId && !(slot is InstanceSlot && slot.overridden)) {
      return _childEditorLabel() != null;
    }
    return true;
  }

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
      builder: (context, rawConfig, _) {
        final config = rawConfig.regions['child'] == false
            ? rawConfig.copyWith(
                regions: {
                  for (final entry in rawConfig.regions.entries)
                    if (entry.key != 'child') entry.key: entry.value,
                },
              )
            : rawConfig;
        return NativeComponentEditor(
          key: _editor,
          id: widget.id,
          label: widget.label,
          menuType: 'Card',
          keyPrefix: 'super-container-${widget.id}',
          settingsTitle: 'Configurer le contenu',
          showRegionInPath: false,
          resolveSlotLabel: _resolveSlotLabel,
          isSlotSelectable: _isSlotSelectable,
          slotContextFor: (_) => _childKey.currentContext,
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
            final fit = SlotContentFitScope.maybeOf(context);
            final slot = children.firstOrNull;
            final child = slot == null
                ? SizedBox(
                    width: (fit?.fitWidth ?? false) ? 48 : double.infinity,
                    height: (fit?.fitHeight ?? false) ? 48 : double.infinity,
                  )
                : KeyedSubtree(
                    key: _childKey,
                    child: EditorSelectionRegion(
                      enabled: editor.editing,
                      selected: editor.isSlotSelected('child', slot.id),
                      onSelect: () => editor.selectSlot('child', slot),
                      child: slot,
                    ),
                  );
            return widget.builder(
              context,
              LayoutSelectionScope(
                owner: editor,
                path: editor.componentPath,
                child: EditorSlotAction(
                  label: 'Composant enfant : ${widget.label}',
                  inline: true,
                  showEdit: false,
                  enabled: slot != null,
                  onSelect: slot == null
                      ? null
                      : () => editor.selectSlot('child', slot),
                  onEdit: () async {},
                  onRemove: slot == null ? null : () async => remove(),
                  wrapActions: slot == null
                      ? const []
                      : editor.wrapActionsForSlot('child', slot),
                  insertion: slot == null
                      ? null
                      : editor.insertionForSlot('child', slot),
                  child: child,
                ),
              ),
              slot != null,
              () async => remove(),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _local.dispose();
    super.dispose();
  }
}
