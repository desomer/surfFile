/// Info-bulle générique par identifiant, partagée par les composants et slots.
/// Résout les textes liés sans écrire dans les repositories ni l'apparence.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/component_behavior.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/repositories/json_string_binding.dart';
import '../../theme/appearance.dart';
import '../editing/slots/editor_selection_region.dart';
import '../editing/slots/editor_slot.dart' show StyleEditScope;

/// Enveloppe publique pour tout composant identifié, y compris les extensions.
///
/// Les composants du moteur l'installent via leurs slots. Un widget personnalisé
/// peut aussi l'utiliser directement, avec le même ID que dans `behaviors`.
class ComponentTooltip extends StatefulWidget {
  const ComponentTooltip({
    required this.componentId,
    required this.child,
    this.behaviors,
    this.sliver,
    super.key,
  });

  final String componentId;
  final Widget child;

  /// Une liste explicite remplace les comportements de l'apparence.
  final List<ComponentBehavior>? behaviors;

  /// À défaut, utilise le contexte de rendu du slot.
  final bool? sliver;

  /// Premier tooltip activé, hors édition ; indépendant du type de composant.
  static TooltipAction? actionOf(
    BuildContext context,
    String componentId, {
    List<ComponentBehavior>? behaviors,
  }) {
    if (StyleEditScope.controllerOf(context)?.value ?? false) return null;
    final items =
        behaviors ?? AppearanceScope.of(context).behaviorsFor(componentId);
    for (final behavior in items) {
      if (behavior.enabled &&
          behavior.trigger == BehaviorTrigger.hover &&
          behavior.action is TooltipAction) {
        return behavior.action as TooltipAction;
      }
    }
    return null;
  }

  @override
  State<ComponentTooltip> createState() => _ComponentTooltipState();
}

class _TooltipScope extends InheritedWidget {
  const _TooltipScope({
    required this.owners,
    required this.suppressesNative,
    required super.child,
  });

  final Map<String, _ComponentTooltipState> owners;
  final bool suppressesNative;

  @override
  bool updateShouldNotify(_TooltipScope oldWidget) =>
      owners != oldWidget.owners ||
      suppressesNative != oldWidget.suppressesNative;
}

typedef _TooltipOverride = ({
  List<ComponentBehavior> behaviors,
  JsonRepositoryStore? store,
  JsonListScope? scope,
});

class _ComponentTooltipState extends State<ComponentTooltip> {
  final _childKey = GlobalKey();
  final _overrides = <Object, _TooltipOverride>{};
  _ComponentTooltipState? _overrideOwner;
  JsonStringBinding? _reader;
  JsonRepositoryStore? _store;
  String? _reportedError;
  bool _scheduled = false;

  void _detachOverride() {
    final owner = _overrideOwner;
    _overrideOwner = null;
    if (owner?._overrides.remove(this) != null) owner!._changed();
  }

  void _override(_ComponentTooltipState owner, _TooltipOverride value) {
    if (!identical(_overrideOwner, owner)) _detachOverride();
    _overrideOwner = owner;
    final previous = owner._overrides[this];
    if (previous != null &&
        listEquals(previous.behaviors, value.behaviors) &&
        identical(previous.store, value.store) &&
        identical(previous.scope, value.scope)) {
      return;
    }
    owner._overrides[this] = value;
    owner._changed();
  }

  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _clearReader() {
    _reader?.removeListener(_changed);
    _reader?.dispose();
    _reader = null;
    _store = null;
    _reportedError = null;
  }

  @override
  void dispose() {
    _detachOverride();
    _clearReader();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parent = context.dependOnInheritedWidgetOfExactType<_TooltipScope>();
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    final owner = parent?.owners[widget.componentId];
    if (owner != null) {
      // The component's explicit code configuration wins over its outer slot.
      if (widget.behaviors case final behaviors?) {
        _override(owner, (
          behaviors: behaviors,
          store: JsonRepositoryScope.maybeOf(context),
          scope: JsonListScope.maybeOf(context),
        ));
      } else {
        _detachOverride();
      }
      _clearReader();
      return child;
    }
    _detachOverride();
    final override = _overrides.values.lastOrNull;
    final action = ComponentTooltip.actionOf(
      context,
      widget.componentId,
      behaviors: override?.behaviors ?? widget.behaviors,
    );
    final binding = action?.binding;
    String message = action?.message ?? '';
    if (binding == null) {
      _clearReader();
    } else {
      final store = override == null
          ? JsonRepositoryScope.maybeOf(context)
          : override.store;
      final scope = override == null
          ? JsonListScope.maybeOf(context)
          : override.scope;
      if (_reader == null) {
        _reader = JsonStringBinding(
          store: store,
          binding: binding,
          scope: scope,
        )..addListener(_changed);
      } else {
        _reader!.reconfigure(store: store, binding: binding, scope: scope);
      }
      _store = store;
      final error = _reader!.error;
      message = error == null ? (_reader!.value ?? '') : 'Info-bulle : $error';
      if (error != null && error != _reportedError) {
        _reportedError = error;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(store, _store) && _reader?.error == error) {
            store?.reportBindingError(
              'Info-bulle ${widget.componentId} : $error',
            );
          }
        });
      } else if (error == null) {
        _reportedError = null;
      }
    }

    final isSliver = widget.sliver ?? SliverSlotScope.isSliver(context);
    Widget content = action == null
        ? child
        : TooltipVisibility(visible: false, child: child);
    if (message.trim().isNotEmpty) {
      content = isSliver
          ? _SliverTooltip(message: message, child: content)
          : Tooltip(
              message: message,
              triggerMode: TooltipTriggerMode.manual,
              child: content,
            );
    }
    // A child's own identity restores its native tooltip, not its parent's.
    if (parent?.suppressesNative ?? false) {
      content = TooltipVisibility(visible: true, child: content);
    }
    return _TooltipScope(
      owners: {...?parent?.owners, widget.componentId: this},
      suppressesNative: action != null,
      child: content,
    );
  }
}

/// Ancre box dans l'overlay : le sliver conserve sa géométrie native.
class _SliverTooltip extends StatefulWidget {
  const _SliverTooltip({required this.message, required this.child});
  final String message;
  final Widget child;

  @override
  State<_SliverTooltip> createState() => _SliverTooltipState();
}

class _SliverTooltipState extends State<_SliverTooltip> {
  final _key = GlobalKey<TooltipState>();
  OverlayEntry? _entry;
  Timer? _timer;
  bool _hovered = false;
  Offset _position = Offset.zero;

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _show() {
    if (!mounted || !_hovered || _entry != null) return;
    final overlay = Overlay.of(context);
    final box = overlay.context.findRenderObject()! as RenderBox;
    final position = box.globalToLocal(_position);
    _entry = OverlayEntry(
      builder: (_) => InheritedTheme.captureAll(
        context,
        Positioned(
          left: position.dx,
          top: position.dy,
          child: IgnorePointer(
            child: TooltipVisibility(
              visible: true,
              child: Tooltip(
                key: _key,
                message: widget.message,
                triggerMode: TooltipTriggerMode.manual,
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hovered && _entry != null) {
        _key.currentState?.ensureTooltipVisible();
      }
    });
  }

  @override
  void didUpdateWidget(_SliverTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      _entry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SliverPointerRegion(
    onEnter: (event) {
      _hovered = true;
      _position = event.position;
      _timer?.cancel();
      _timer = Timer(
        TooltipTheme.of(context).waitDuration ?? Duration.zero,
        _show,
      );
    },
    onExit: (_) {
      _hovered = false;
      _hide();
    },
    onPointerDown: (_) => _hide(),
    child: widget.child,
  );
}
