import 'package:material_ui/material_ui.dart';

/// Compact dialog title; renaming never changes a component's technical ID.
class EditorDialogHeader extends StatefulWidget {
  const EditorDialogHeader({
    required this.label,
    this.onLabelChanged,
    this.editableLabel,
    this.actions = const [],
    super.key,
  });

  final String label;
  final ValueChanged<String>? onLabelChanged;
  final String? editableLabel;
  final List<Widget> actions;

  @override
  State<EditorDialogHeader> createState() => _EditorDialogHeaderState();
}

class _EditorDialogHeaderState extends State<EditorDialogHeader> {
  bool _editing = false;
  late final _text = TextEditingController(text: widget.label);
  final _form = GlobalKey<FormState>();

  @override
  void didUpdateWidget(EditorDialogHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.label != widget.label) _text.text = widget.label;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    widget.onLabelChanged?.call(_text.text.trim());
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _editing
            ? Form(
                key: _form,
                child: TextFormField(
                  key: const ValueKey('editor-label-input'),
                  controller: _text,
                  autofocus: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Nom du composant',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Le nom ne peut pas être vide.'
                      : null,
                  onFieldSubmitted: (_) => _save(),
                ),
              )
            : Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
      ),
      if (widget.onLabelChanged != null)
        if (_editing) ...[
          IconButton(
            key: const ValueKey('editor-label-save'),
            tooltip: 'Valider le nom',
            onPressed: _save,
            icon: const Icon(Icons.check),
          ),
          IconButton(
            tooltip: 'Annuler le renommage',
            onPressed: () => setState(() => _editing = false),
            icon: const Icon(Icons.close),
          ),
        ] else
          IconButton(
            key: const ValueKey('editor-label-edit'),
            tooltip: 'Renommer le composant',
            onPressed: () => setState(() {
              _text.text = widget.editableLabel ?? widget.label;
              _editing = true;
            }),
            icon: const Icon(Icons.edit_outlined),
          ),
      ...widget.actions,
    ],
  );
}

/// Identity and rename callback of a slot instance, inherited by its content.
class EditorComponentLabel extends InheritedWidget {
  const EditorComponentLabel({
    this.id,
    required this.label,
    required this.onChanged,
    required this.onRestore,
    this.overridden = false,
    this.menuIcon,
    required super.child,
    super.key,
  });

  /// Stable technical identifier of the slot.
  final String? id;
  final String label;
  final ValueChanged<String> onChanged;
  final VoidCallback onRestore;
  final bool overridden;
  final IconData? menuIcon;

  static EditorComponentLabel? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EditorComponentLabel>();

  @override
  bool updateShouldNotify(EditorComponentLabel oldWidget) =>
      label != oldWidget.label ||
      overridden != oldWidget.overridden ||
      menuIcon != oldWidget.menuIcon ||
      onChanged != oldWidget.onChanged;
}
