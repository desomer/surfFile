import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Appelle [onReset] quand Win + Échap est pressé, quel que soit l'élément qui
/// a le focus. L'événement est consommé : Échap ne désélectionne pas.
class LayoutResetShortcut extends StatefulWidget {
  const LayoutResetShortcut({
    required this.onReset,
    required this.child,
    super.key,
  });

  final VoidCallback onReset;
  final Widget child;

  @override
  State<LayoutResetShortcut> createState() => _LayoutResetShortcutState();
}

class _LayoutResetShortcutState extends State<LayoutResetShortcut> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !HardwareKeyboard.instance.isMetaPressed) {
      return false;
    }
    widget.onReset();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
