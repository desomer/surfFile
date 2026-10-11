import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/appearance.dart';

class EditorHistoryController extends ChangeNotifier {
  EditorHistoryController({
    required ValueNotifier<Appearance> appearance,
    required this._editMode,
    this.maxEntries = 100,
  }) : assert(maxEntries > 0),
       _appearance = appearance,
       _current = appearance.value {
    _appearance.addListener(_appearanceChanged);
    _editMode.addListener(_editModeChanged);
  }

  final ValueNotifier<Appearance> _appearance;
  final ValueListenable<bool> _editMode;
  final int maxEntries;
  final List<Appearance> _undo = [];
  final List<Appearance> _redo = [];
  Appearance _current;
  Appearance? _transactionStart;
  int _transactionDepth = 0;
  bool _applying = false;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void beginTransaction() {
    if (!_editMode.value) return;
    if (_transactionDepth++ == 0) _transactionStart = _current;
  }

  void commitTransaction() {
    if (_transactionDepth == 0) return;
    if (--_transactionDepth != 0) return;
    final before = _transactionStart;
    _transactionStart = null;
    if (before != null && !identical(before, _current)) {
      _pushUndo(before);
      _redo.clear();
      notifyListeners();
    }
  }

  /// Ends a transaction after its caller has restored the pre-edit value.
  void cancelTransaction() {
    _transactionDepth = 0;
    _transactionStart = null;
  }

  void undo() {
    if (!_editMode.value || !canUndo) return;
    while (_transactionDepth > 0) {
      commitTransaction();
    }
    if (!canUndo) return;
    _redo.add(_current);
    final target = _undo.removeLast();
    _apply(target);
  }

  void redo() {
    if (!_editMode.value || !canRedo) return;
    while (_transactionDepth > 0) {
      commitTransaction();
    }
    if (!canRedo) return;
    _pushUndo(_current);
    final target = _redo.removeLast();
    _apply(target);
  }

  void clear() {
    _undo.clear();
    _redo.clear();
    _transactionDepth = 0;
    _transactionStart = null;
    notifyListeners();
  }

  void _editModeChanged() {
    if (!_editMode.value) {
      while (_transactionDepth > 0) {
        commitTransaction();
      }
    }
  }

  void _appearanceChanged() {
    final next = _appearance.value;
    if (identical(next, _current)) return;
    final before = _current;
    _current = next;
    if (_applying) return;
    if (!_editMode.value) {
      _undo.clear();
      _redo.clear();
      _transactionDepth = 0;
      _transactionStart = null;
    } else if (_transactionDepth == 0) {
      _pushUndo(before);
      _redo.clear();
    }
    notifyListeners();
  }

  void _apply(Appearance value) {
    _applying = true;
    try {
      _appearance.value = value;
    } finally {
      _applying = false;
    }
    notifyListeners();
  }

  void _pushUndo(Appearance value) {
    _undo.add(value);
    if (_undo.length > maxEntries) _undo.removeAt(0);
  }

  @override
  void dispose() {
    _appearance.removeListener(_appearanceChanged);
    _editMode.removeListener(_editModeChanged);
    super.dispose();
  }
}

class EditorHistoryScope extends InheritedNotifier<EditorHistoryController> {
  const EditorHistoryScope({
    required EditorHistoryController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static EditorHistoryController? controllerOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EditorHistoryScope>()?.notifier;
}

class EditorHistoryShortcut extends StatefulWidget {
  const EditorHistoryShortcut({
    required this.editMode,
    required this.history,
    required this.child,
    super.key,
  });

  final ValueListenable<bool> editMode;
  final EditorHistoryController history;
  final Widget child;

  @override
  State<EditorHistoryShortcut> createState() => _EditorHistoryShortcutState();
}

class _EditorHistoryShortcutState extends State<EditorHistoryShortcut> {
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
        !widget.editMode.value ||
        !(HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.history.redo();
      } else {
        widget.history.undo();
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyY) {
      widget.history.redo();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class EditorHistorySlider extends StatelessWidget {
  const EditorHistorySlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.label,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final String? label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final history = EditorHistoryScope.controllerOf(context);
    return Slider(
      key: key,
      value: value,
      min: min,
      max: max,
      label: label,
      onChanged: onChanged,
      onChangeStart: (_) => history?.beginTransaction(),
      onChangeEnd: (_) => history?.commitTransaction(),
    );
  }
}
