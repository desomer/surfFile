import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/external_drop_transfer.dart';
import '../../services/windows_file_drop.dart';
import '../../theme/file_drag_mode.dart';
import '../interaction/drag_select_region.dart';

/// Source de glisser-déposer natif d'un élément de la vue.
///
/// Selon [mode], le glisser part de tout l'élément quand il est sélectionné
/// ([FileDragMode.selected]), seulement de ses [ExternalFileDragHandle]
/// ([FileDragMode.nameAndIcon]), ou jamais. Ailleurs, le glisser reste
/// disponible pour la sélection par cadre de [DragSelectRegion]. La structure
/// des widgets ne dépend pas du mode ni de la sélection.
class ExternalFileDragSource extends StatefulWidget {
  const ExternalFileDragSource({
    required this.paths,
    required this.label,
    required this.child,
    this.mode = FileDragMode.selected,
    this.selected = true,
    super.key,
  });

  final List<String> paths;
  final String label;
  final Widget child;
  final FileDragMode mode;
  final bool selected;

  @override
  State<ExternalFileDragSource> createState() => _ExternalFileDragSourceState();
}

class _ExternalFileDragSourceState extends State<ExternalFileDragSource> {
  Offset? _origin;

  bool get _active => Platform.isWindows && widget.paths.isNotEmpty;
  bool get _wholeItem =>
      _active && widget.mode == FileDragMode.selected && widget.selected;
  bool get _handles => _active && widget.mode == FileDragMode.nameAndIcon;

  @override
  Widget build(BuildContext context) {
    if (!_active) return widget.child;
    return _DragSourceScope(
      state: this,
      handles: _handles,
      paths: widget.paths,
      child: _draggable(enabled: _wholeItem, child: widget.child),
    );
  }

  Widget _draggable({required bool enabled, required Widget child}) {
    final paths = widget.paths;
    return Listener(
      onPointerDown: (event) {
        _origin = event.position;
        if (enabled &&
            event.kind == PointerDeviceKind.mouse &&
            event.buttons == kPrimaryButton) {
          DragSelectRegion.excludePointer(event.pointer);
        }
      },
      child: _ThresholdDraggable<String>(
        data: paths.first,
        maxSimultaneousDrags: enabled ? null : 0,
        feedback: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              paths.length == 1 ? widget.label : '${paths.length} éléments',
            ),
          ),
        ),
        onDragStarted: _startDrag,
        child: child,
      ),
    );
  }

  Future<void> _startDrag() async {
    try {
      await WindowsFileDrop.startDrag(widget.paths, origin: _origin);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de glisser les éléments : $error')),
      );
    }
  }
}

/// Distance (px logiques) à parcourir avant de lancer le glisser natif.
///
/// Pour la souris, [Draggable] démarre dès 1 px : un léger tremblement pendant
/// un double-clic lançait alors `DoDragDrop`, qui capture la souris et avale le
/// second clic. Ce seuil reste inférieur à la tolérance d'un tap.
const double fileDragStartDistance = 8;

class _ThresholdDraggable<T extends Object> extends Draggable<T> {
  const _ThresholdDraggable({
    required super.child,
    required super.feedback,
    super.data,
    super.maxSimultaneousDrags,
    super.onDragStarted,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _ThresholdMultiDragGestureRecognizer()..onStart = onStart;
}

class _ThresholdMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  _ThresholdMultiDragGestureRecognizer() : super(debugOwner: null);

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _ThresholdPointerState(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'threshold multidrag';
}

class _ThresholdPointerState extends MultiDragPointerState {
  _ThresholdPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > fileDragStartDistance) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) =>
      starter(initialPosition);
}

class _DragSourceScope extends InheritedWidget {
  const _DragSourceScope({
    required this.state,
    required this.handles,
    required this.paths,
    required super.child,
  });

  final _ExternalFileDragSourceState state;
  final bool handles;
  final List<String> paths;

  @override
  bool updateShouldNotify(_DragSourceScope old) =>
      handles != old.handles || state != old.state || paths != old.paths;
}

/// Zone (icône, nom) d'où part le glisser en mode [FileDragMode.nameAndIcon].
class ExternalFileDragHandle extends StatelessWidget {
  const ExternalFileDragHandle({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DragSourceScope>();
    if (scope == null) return child;
    return scope.state._draggable(enabled: scope.handles, child: child);
  }
}

class ExternalFileDrop extends StatefulWidget {
  const ExternalFileDrop({
    required this.path,
    required this.enabled,
    required this.onDrop,
    required this.child,
    super.key,
  });

  final String path;
  final bool enabled;
  final void Function(List<String> sources, String destination) onDrop;
  final Widget child;

  @override
  State<ExternalFileDrop> createState() => _ExternalFileDropState();
}

class _ExternalFileDropState extends State<ExternalFileDrop> {
  final _hovered = ValueNotifier<String?>(null);
  bool _inside = false;

  @override
  void initState() {
    super.initState();
    WindowsFileDrop.initialize();
    WindowsFileDrop.events.addListener(_handleEvent);
  }

  void _handleEvent() {
    final event = WindowsFileDrop.events.value;
    if (event == null) return;
    if (event.kind == WindowsDropKind.error) {
      if (_inside) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(event.error!)));
      }
      _inside = false;
      _hovered.value = null;
      return;
    }
    if (event.kind == WindowsDropKind.exited) {
      _hovered.value = null;
      return;
    }
    if (!widget.enabled ||
        ExternalDropTransfer.prompting.value ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      _inside = false;
      _hovered.value = null;
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final position = event.position / MediaQuery.devicePixelRatioOf(context);
    _inside = (Offset.zero & box.size).contains(box.globalToLocal(position));
    if (!_inside) {
      _hovered.value = null;
      return;
    }
    final destination = _destination(position);
    final ignored = WindowsFileDrop.ignoresInternalDrop(position, destination);
    if (event.kind == WindowsDropKind.drop) {
      _inside = false;
      _hovered.value = null;
      if (destination != null && !ignored) {
        widget.onDrop(event.paths, destination);
      }
    } else {
      _hovered.value = ignored ? null : destination;
    }
  }

  String? _destination(Offset position) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      position,
      View.of(context).viewId,
    );
    for (final hit in result.path) {
      if (hit.target case RenderMetaData(
        metaData: _DropDestination destination,
      )) {
        return destination.path;
      }
    }
    return null;
  }

  @override
  void dispose() {
    WindowsFileDrop.events.removeListener(_handleEvent);
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DropScope(
    notifier: _hovered,
    child: ExternalDropDestination(path: widget.path, child: widget.child),
  );
}

class _DropScope extends InheritedNotifier<ValueNotifier<String?>> {
  const _DropScope({required super.notifier, required super.child});
}

class _DropDestination {
  const _DropDestination(this.path);

  final String path;
}

/// Marque un dossier sans installer une cible native supplémentaire.
class ExternalDropDestination extends StatelessWidget {
  const ExternalDropDestination({
    required this.path,
    required this.child,
    super.key,
  });

  final String? path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DropScope>();
    if (path == null || scope == null) return child;
    final hovered = scope.notifier?.value == path;
    return MetaData(
      metaData: _DropDestination(path!),
      behavior: HitTestBehavior.translucent,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: hovered
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
          color: hovered
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      ),
    );
  }
}
