import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../services/external_drop_transfer.dart';
import '../services/windows_file_drop.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(event.error!)),
        );
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
    if (event.kind == WindowsDropKind.drop) {
      _inside = false;
      _hovered.value = null;
      if (destination != null) widget.onDrop(event.paths, destination);
    } else {
      _hovered.value = destination;
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
        child: ExternalDropDestination(
          path: widget.path,
          child: widget.child,
        ),
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
              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
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
