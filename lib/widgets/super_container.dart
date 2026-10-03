import 'package:material_ui/material_ui.dart';

import '../theme/appearance.dart';
import '../theme/container_style.dart';
import '../theme/neon_style.dart';
import 'container_style_editor.dart';
import 'styled_surface.dart';

/// Conteneur stylé par un [ContainerStyle] qui ouvre le
/// [ContainerStyleEditor] sur un appui long pour se styler lui-même.
class SuperContainer extends StatefulWidget {
  const SuperContainer({
    required this.child,
    this.style = const ContainerStyle(),
    this.onStyleChanged,
    this.label = 'Super container',
    this.fallbackColor,
    this.borderColor,
    this.padding,
    this.editable = true,
    super.key,
  });

  final Widget child;
  final ContainerStyle style;
  final ValueChanged<ContainerStyle>? onStyleChanged;
  final String label;
  final Color? fallbackColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final bool editable;

  @override
  State<SuperContainer> createState() => SuperContainerState();
}

class SuperContainerState extends State<SuperContainer> {
  late final ValueNotifier<ContainerStyle> _style =
      ValueNotifier(widget.style);

  ContainerStyle get style => _style.value;

  @override
  void didUpdateWidget(SuperContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) _style.value = widget.style;
  }

  @override
  void dispose() {
    _style.dispose();
    super.dispose();
  }

  void _update(ContainerStyle value) {
    _style.value = value;
    widget.onStyleChanged?.call(value);
  }

  Color _fallback(BuildContext context) =>
      widget.fallbackColor ?? Theme.of(context).colorScheme.surfaceContainerLow;

  Color _border(BuildContext context) =>
      widget.borderColor ?? Theme.of(context).colorScheme.outlineVariant;

  Future<void> openEditor() async {
    final initial = _style.value;
    final accent = AppearanceScope.of(context).accent;
    final fallback = _fallback(context);
    final border = _border(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => AlertDialog(
        title: Text(widget.label),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: ValueListenableBuilder<ContainerStyle>(
              valueListenable: _style,
              builder: (context, style, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ContainerStyleEditor(
                    label: widget.label,
                    collapsible: false,
                    value: style.fill,
                    solidColor: style.color ?? fallback,
                    radius: style.radius,
                    borderWidth: style.borderWidth,
                    borderColor: style.borderColor ?? border,
                    elevation: style.elevation,
                    shadowOpacity: style.shadowOpacity,
                    neon: style.neon ?? const NeonStyle(),
                    accent: accent,
                    onChanged: (v) => _update(style.copyWith(fill: v)),
                    onSolidColorChanged: (v) =>
                        _update(style.copyWith(color: v)),
                    onRadiusChanged: (v) => _update(style.copyWith(radius: v)),
                    onBorderWidthChanged: (v) =>
                        _update(style.copyWith(borderWidth: v)),
                    onBorderColorChanged: (v) =>
                        _update(style.copyWith(borderColor: v)),
                    onResetBorderColor: () =>
                        _update(style.copyWith(resetBorderColor: true)),
                    onElevationChanged: (v) =>
                        _update(style.copyWith(elevation: v)),
                    onShadowOpacityChanged: (v) =>
                        _update(style.copyWith(shadowOpacity: v)),
                    onNeonChanged: (v) => _update(style.copyWith(neon: v)),
                  ),
                  TextButton(
                    onPressed: () =>
                        _update(style.copyWith(resetColor: true)),
                    child: const Text('Couleur unie automatique'),
                  ),
                  TextButton(
                    onPressed: () => _update(const ContainerStyle()),
                    child: const Text('Réinitialiser ce style'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
    if (confirmed != true && mounted && _style.value != initial) {
      _update(initial);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onLongPress: widget.editable ? openEditor : null,
        child: ValueListenableBuilder<ContainerStyle>(
          valueListenable: _style,
          builder: (context, style, child) => StyledSurface(
            style: style,
            fallbackColor: _fallback(context),
            borderColor: _border(context),
            child: child!,
          ),
          child: widget.padding == null
              ? widget.child
              : Padding(padding: widget.padding!, child: widget.child),
        ),
      );
}
