import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/appearance.dart' as shell;
import 'package:super_container_layout/services/appearance_store.dart';
import '../services/appearance_store.dart' show SurfFileAppearanceCodec;
import 'surffile_appearance.dart' show SurfFileAppearance, requireSurfFileAppearance;

/// Typed view of the shell controller; updates preserve the application model.
class AppearanceScope extends StatefulWidget {
  const AppearanceScope({required this.controller, required this.child, super.key});
  final ValueNotifier<SurfFileAppearance> controller;
  final Widget child;
  @override
  State<AppearanceScope> createState() => _AppearanceScopeState();
  static ValueNotifier<SurfFileAppearance>? controllerOf(BuildContext context) =>
      switch (shell.AppearanceScope.controllerOf(context)) {
        null => null,
        _ShellController(:final delegate) => delegate,
        final controller => _SurfFileController(controller),
      };
  static SurfFileAppearance of(BuildContext context) => switch (shell.AppearanceScope.controllerOf(context)) {
    null => SurfFileAppearance(),
    final controller => requireSurfFileAppearance(controller.value),
  };
}

class _AppearanceScopeState extends State<AppearanceScope> {
  late _ShellController _controller;
  @override
  void initState() {
    super.initState();
    _controller = _ShellController(widget.controller);
  }
  @override
  void didUpdateWidget(AppearanceScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.dispose();
      _controller = _ShellController(widget.controller);
    }
  }
  @override
  Widget build(BuildContext context) => AppearanceServicesScope(
    codec: const SurfFileAppearanceCodec(),
    child: shell.AppearanceScope(controller: _controller, child: widget.child),
  );
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
}

class _SurfFileController extends ValueNotifier<SurfFileAppearance> {
  _SurfFileController(this.delegate) : super(requireSurfFileAppearance(delegate.value));
  final ValueNotifier<shell.Appearance> delegate;
  @override
  SurfFileAppearance get value => requireSurfFileAppearance(delegate.value);
  @override
  set value(SurfFileAppearance value) => delegate.value = value;
  @override
  bool get hasListeners => delegate.hasListeners;
  @override
  void addListener(VoidCallback listener) => delegate.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => delegate.removeListener(listener);
}
class _ShellController extends ValueNotifier<shell.Appearance> {
  _ShellController(this.delegate) : super(delegate.value);
  final ValueNotifier<SurfFileAppearance> delegate;
  @override
  shell.Appearance get value => delegate.value;
  @override
  set value(shell.Appearance value) => delegate.value = requireSurfFileAppearance(value);
  @override
  bool get hasListeners => delegate.hasListeners;
  @override
  void addListener(VoidCallback listener) => delegate.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => delegate.removeListener(listener);
}
