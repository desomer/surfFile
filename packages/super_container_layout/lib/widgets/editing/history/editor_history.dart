/// Contrôleur, portée et raccourcis clavier de l'historique Undo / Redo ([EditorHistoryController]).
library;

import 'dart:async' show FutureOr, unawaited;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../services/appearance/appearance_store.dart';
import '../../../services/pages/editor_page_graph.dart';
import '../../../theme/appearance.dart';
import '../../../models/json_numbers.dart';
import '../components/shared/editor_number_field.dart';

/// Couple d'actions d'annulation et de rétablissement associé à une entrée d'historique.
typedef EditorHistorySideEffect = ({
  FutureOr<void> Function() undo,
  FutureOr<void> Function() redo,
});

final class _HistoryEntry {
  _HistoryEntry({
    required this.appearance,
    List<EditorHistorySideEffect> sideEffects = const [],
  }) : sideEffects = sideEffects.isEmpty
           ? const <EditorHistorySideEffect>[]
           : List<EditorHistorySideEffect>.unmodifiable(sideEffects);

  final Appearance appearance;
  final List<EditorHistorySideEffect> sideEffects;
}

/// Contrôleur gérant la pile d'historique Undo/Redo des modifications d'[Appearance] et des repositories JSON.
class EditorHistoryController extends ChangeNotifier {
  /// Crée un contrôleur d'historique lié à [appearance] et actif lorsque [_editMode] vaut `true`.
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

  /// Nombre maximal d'entrées conservées dans la pile d'annulation.
  final int maxEntries;
  final List<_HistoryEntry> _undo = <_HistoryEntry>[];
  final List<_HistoryEntry> _redo = <_HistoryEntry>[];
  final List<EditorHistorySideEffect> _pendingSideEffects =
      <EditorHistorySideEffect>[];
  Appearance _current;
  Appearance? _transactionStart;
  int _transactionDepth = 0;
  bool _applying = false;
  bool _disposed = false;

  /// Indique si au moins une action peut être annulée.
  bool get canUndo => _undo.isNotEmpty;

  /// Indique si au moins une action annulée peut être rétablie.
  bool get canRedo => _redo.isNotEmpty;

  /// Ouvre une transaction regroupant les modifications suivantes en une seule entrée d'historique.
  void beginTransaction() {
    if (!_editMode.value) return;
    if (_transactionDepth++ == 0) {
      _transactionStart = _current;
      _pendingSideEffects.clear();
    }
  }

  /// Associe un effet compagnon ([undo] / [redo]) à la transaction en cours,
  /// ou empile directement une entrée dédiée si aucune transaction n'est ouverte.
  void addTransactionSideEffect({
    required FutureOr<void> Function() undo,
    required FutureOr<void> Function() redo,
  }) {
    if (!_editMode.value) return;
    final effect = (undo: undo, redo: redo);
    if (_transactionDepth > 0) {
      _pendingSideEffects.add(effect);
      return;
    }
    _pushUndo(
      _HistoryEntry(
        appearance: _current,
        sideEffects: <EditorHistorySideEffect>[effect],
      ),
    );
    _redo.clear();
    notifyListeners();
  }

  /// Valide la transaction en cours et empile une entrée si l'[Appearance] a changé
  /// ou si des effets compagnons ont été enregistrés.
  void commitTransaction() {
    if (_transactionDepth == 0) return;
    if (--_transactionDepth != 0) return;
    final before = _transactionStart;
    _transactionStart = null;
    final effects = _pendingSideEffects.isEmpty
        ? const <EditorHistorySideEffect>[]
        : List<EditorHistorySideEffect>.unmodifiable(_pendingSideEffects);
    _pendingSideEffects.clear();
    if (before != null && (!identical(before, _current) || effects.isNotEmpty)) {
      _pushUndo(_HistoryEntry(appearance: before, sideEffects: effects));
      _redo.clear();
      notifyListeners();
    }
  }

  /// Termine la transaction en cours après restauration par l'appelant de l'état initial.
  void cancelTransaction() {
    _transactionDepth = 0;
    _transactionStart = null;
    _pendingSideEffects.clear();
  }

  /// Annule la dernière entrée d'historique de façon synchrone (et lance en tâche de fond
  /// les éventuels effets compagnons asynchrones).
  void undo() {
    if (!_editMode.value || !canUndo) return;
    while (_transactionDepth > 0) {
      commitTransaction();
    }
    if (!canUndo) return;
    final target = _undo.removeLast();
    _redo.add(
      _HistoryEntry(
        appearance: _current,
        sideEffects: target.sideEffects,
      ),
    );
    _applyAppearance(target.appearance);
    if (target.sideEffects.isNotEmpty) {
      _runSideEffectsSyncOrUnawaited(
        <FutureOr<void> Function()>[
          for (final effect in target.sideEffects.reversed) effect.undo,
        ],
      );
    }
    notifyListeners();
  }

  /// Annule la dernière entrée d'historique et attend séquentiellement tous ses effets compagnons.
  Future<void> undoAsync() async {
    if (!_editMode.value || !canUndo) return;
    while (_transactionDepth > 0) {
      commitTransaction();
    }
    if (!canUndo) return;
    final target = _undo.removeLast();
    _redo.add(
      _HistoryEntry(
        appearance: _current,
        sideEffects: target.sideEffects,
      ),
    );
    _applyAppearance(target.appearance);
    for (final effect in target.sideEffects.reversed) {
      final res = effect.undo();
      if (res is Future<void>) {
        await res;
      }
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Rétablit la dernière entrée annulée de façon synchrone (et lance en tâche de fond
  /// les éventuels effets compagnons asynchrones).
  void redo() {
    if (!_editMode.value || !canRedo) return;
    while (_transactionDepth > 0) {
      commitTransaction();
    }
    if (!canRedo) return;
    final target = _redo.removeLast();
    _pushUndo(
      _HistoryEntry(
        appearance: _current,
        sideEffects: target.sideEffects,
      ),
    );
    _applyAppearance(target.appearance);
    if (target.sideEffects.isNotEmpty) {
      _runSideEffectsSyncOrUnawaited(
        <FutureOr<void> Function()>[
          for (final effect in target.sideEffects) effect.redo,
        ],
      );
    }
    notifyListeners();
  }

  /// Rétablit la dernière entrée annulée et attend séquentiellement tous ses effets compagnons.
  Future<void> redoAsync() async {
    if (!_editMode.value || !canRedo) return;
    while (_transactionDepth > 0) {
      commitTransaction();
    }
    if (!canRedo) return;
    final target = _redo.removeLast();
    _pushUndo(
      _HistoryEntry(
        appearance: _current,
        sideEffects: target.sideEffects,
      ),
    );
    _applyAppearance(target.appearance);
    for (final effect in target.sideEffects) {
      final res = effect.redo();
      if (res is Future<void>) {
        await res;
      }
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Vide intégralement les piles Undo / Redo et réinitialise toute transaction ouverte.
  void clear() {
    _undo.clear();
    _redo.clear();
    _pendingSideEffects.clear();
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
    if (_appearance case final PersistentAppearanceController persistent
        when persistent.isHydrating) {
      _current = next;
      final slice = persistent.activeHydrationSlice;
      if (slice != null && !slice.isEmpty) {
        _injectHydratedSliceIntoSnapshots(slice);
      }
      return;
    }
    final before = _current;
    _current = next;
    if (_applying) return;
    if (!_editMode.value) {
      _undo.clear();
      _redo.clear();
      _pendingSideEffects.clear();
      _transactionDepth = 0;
      _transactionStart = null;
    } else if (_transactionDepth == 0) {
      _pushUndo(_HistoryEntry(appearance: before));
      _redo.clear();
    }
    notifyListeners();
  }

  void _injectHydratedSliceIntoSnapshots(EditorPageAppearanceSlice slice) {
    for (var i = 0; i < _undo.length; i++) {
      final entry = _undo[i];
      _undo[i] = _HistoryEntry(
        appearance: slice.mergeInto(entry.appearance),
        sideEffects: entry.sideEffects,
      );
    }
    for (var i = 0; i < _redo.length; i++) {
      final entry = _redo[i];
      _redo[i] = _HistoryEntry(
        appearance: slice.mergeInto(entry.appearance),
        sideEffects: entry.sideEffects,
      );
    }
    if (_transactionStart != null) {
      _transactionStart = slice.mergeInto(_transactionStart!);
    }
  }

  void _applyAppearance(Appearance value) {
    if (identical(_appearance.value, value)) {
      _current = value;
      return;
    }
    _applying = true;
    try {
      _appearance.value = value;
    } finally {
      _applying = false;
    }
  }

  void _runSideEffectsSyncOrUnawaited(
    List<FutureOr<void> Function()> callbacks,
  ) {
    for (var i = 0; i < callbacks.length; i++) {
      final res = callbacks[i]();
      if (res is Future<void>) {
        unawaited(_continueAsyncSideEffects(res, callbacks, i + 1));
        return;
      }
    }
  }

  Future<void> _continueAsyncSideEffects(
    Future<void> pending,
    List<FutureOr<void> Function()> callbacks,
    int nextIndex,
  ) async {
    await pending;
    for (var i = nextIndex; i < callbacks.length; i++) {
      final res = callbacks[i]();
      if (res is Future<void>) {
        await res;
      }
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _pushUndo(_HistoryEntry entry) {
    _undo.add(entry);
    if (_undo.length > maxEntries) _undo.removeAt(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _appearance.removeListener(_appearanceChanged);
    _editMode.removeListener(_editModeChanged);
    super.dispose();
  }
}

/// Portée `InheritedNotifier` exposant l'[EditorHistoryController] à l'arbre de widgets.
class EditorHistoryScope extends InheritedNotifier<EditorHistoryController> {
  const EditorHistoryScope({
    required EditorHistoryController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static EditorHistoryController? controllerOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EditorHistoryScope>()?.notifier;
}

/// Widget interceptant les raccourcis clavier standards (`Ctrl+Z` / `Ctrl+Y`) pour déclencher Undo/Redo.
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
    final focus = FocusManager.instance.primaryFocus?.context;
    final focusedHistory = focus == null
        ? null
        : EditorHistoryScope.controllerOf(focus);
    if (focusedHistory != null && focusedHistory != widget.history) {
      return false;
    }
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

/// Curseur numerique editable regroupant le glisser en une transaction Undo/Redo.
class EditorHistorySlider extends StatelessWidget {
  /// Cree un curseur avec saisie numerique et historique partage.
  const EditorHistorySlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.label,
    this.sliderKey,
    this.divisions,
    this.integer = false,
    this.valueScale = 1,
    this.unit = '',
    this.showValue = true,
    this.allowAboveMax = false,
    this.allowBelowMin = false,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final String? label;
  final ValueChanged<double>? onChanged;
  final Key? sliderKey;
  final int? divisions;
  final bool integer;
  final double valueScale;
  final String unit;
  final bool showValue;
  final bool allowAboveMax;
  final bool allowBelowMin;

  @override
  Widget build(BuildContext context) {
    final history = EditorHistoryScope.controllerOf(context);
    void change(double value) {
      final next = JsonNumbers.round(
        integer ? (value * valueScale).roundToDouble() / valueScale : value,
      );
      onChanged?.call(next);
    }

    final slider = Slider(
      key: sliderKey ?? key,
      value: value.clamp(min, max),
      min: min,
      max: max,
      label: label,
      divisions: divisions,
      onChanged: onChanged == null ? null : change,
      onChangeStart: (_) => history?.beginTransaction(),
      onChangeEnd: (_) => history?.commitTransaction(),
    );
    if (!showValue) return slider;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: EditorNumberField(
            value: value,
            min: min,
            max: max,
            integer: integer,
            scale: valueScale,
            unit: unit,
            label: label,
            allowAboveMax: allowAboveMax,
            allowBelowMin: allowBelowMin,
            onChanged: onChanged == null ? null : change,
          ),
        ),
        slider,
      ],
    );
  }
}
