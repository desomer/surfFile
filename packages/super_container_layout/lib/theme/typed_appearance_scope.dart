import 'package:material_ui/material_ui.dart';

import '../services/appearance_store.dart';
import 'appearance.dart';

/// Exposes an application-typed controller to the generic appearance widgets.
class TypedAppearanceScope<T extends Appearance> extends StatefulWidget {
  const TypedAppearanceScope({
    required this.controller,
    required this.codec,
    required this.child,
    super.key,
  });

  final ValueNotifier<T> controller;
  final AppearanceCodec codec;
  final Widget child;

  static ValueNotifier<T>? controllerOf<T extends Appearance>(
    BuildContext context,
  ) {
    final controller = AppearanceScope.controllerOf(context);
    if (controller == null) return null;
    if (controller is _ShellController<T> && controller.appearanceType == T) {
      return controller.delegate;
    }
    return _TypedController<T>(
      controller,
      AppearanceServicesScope.codecOf(context),
    );
  }

  static T? maybeOf<T extends Appearance>(BuildContext context) {
    final value = AppearanceScope.controllerOf(context)?.value;
    return value == null ? null : _requireType<T>(value);
  }

  static T of<T extends Appearance>(BuildContext context) =>
      maybeOf<T>(context) ??
      (throw StateError('TypedAppearanceScope<$T> is unavailable.'));

  @override
  State<TypedAppearanceScope<T>> createState() =>
      _TypedAppearanceScopeState<T>();
}

T _requireType<T extends Appearance>(Appearance value) {
  if (value is T) return value;
  throw StateError('Expected $T, received ${value.runtimeType}.');
}

class _TypedAppearanceScopeState<T extends Appearance>
    extends State<TypedAppearanceScope<T>> {
  late _ShellController<T> _controller;

  @override
  void initState() {
    super.initState();
    _controller = _ShellController(widget.controller, widget.codec);
  }

  @override
  void didUpdateWidget(TypedAppearanceScope<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.codec != widget.codec) {
      _controller.dispose();
      _controller = _ShellController(widget.controller, widget.codec);
    }
  }

  @override
  Widget build(BuildContext context) => AppearanceServicesScope(
    codec: widget.codec,
    child: AppearanceScope(controller: _controller, child: widget.child),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Each view owns its listener registrations, not the source notifier.
mixin _ForwardedListeners on ChangeNotifier {
  Listenable get source;
  final List<VoidCallback> _listeners = [];

  @override
  bool get hasListeners => _listeners.isNotEmpty;
  @override
  void addListener(VoidCallback listener) {
    assert(ChangeNotifier.debugAssertNotDisposed(this));
    source.addListener(listener);
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_listeners.remove(listener)) source.removeListener(listener);
  }

  @override
  void dispose() {
    for (final listener in _listeners) {
      source.removeListener(listener);
    }
    _listeners.clear();
    super.dispose();
  }
}

class _TypedController<T extends Appearance> extends ValueNotifier<T>
    with _ForwardedListeners {
  _TypedController(this.delegate, this.codec)
    : super(_requireType<T>(delegate.value));

  final ValueNotifier<Appearance> delegate;
  final AppearanceCodec codec;

  @override
  T get value => _requireType<T>(delegate.value);
  @override
  set value(T value) {
    final prepared = _requireType<T>(codec.prepare(value));
    final controller = delegate;
    if (controller is _ShellController<Appearance>) {
      controller.setPrepared(prepared);
    } else {
      controller.value = prepared;
    }
  }
  @override
  Listenable get source => delegate;
}

class _ShellController<T extends Appearance> extends ValueNotifier<Appearance>
    with _ForwardedListeners {
  _ShellController(this.delegate, this.codec) : super(delegate.value);

  final ValueNotifier<T> delegate;
  final AppearanceCodec codec;
  Type get appearanceType => T;

  void setPrepared(Appearance value) => delegate.value = _requireType<T>(value);

  @override
  Appearance get value => delegate.value;
  @override
  set value(Appearance value) => setPrepared(codec.prepare(value));
  @override
  Listenable get source => delegate;
}
