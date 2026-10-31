import 'package:material_ui/material_ui.dart';

import '../editing/slots/editor_slot.dart';
import 'appearance_settings.dart';

/// Compact 36x36 rounded icon button shared across application and editor toolbars.
class SuperToolbarIconButton extends StatelessWidget {
  const SuperToolbarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    isSelected: selected,
    icon: Icon(icon, size: 20),
    style: IconButton.styleFrom(
      minimumSize: const Size(36, 36),
      maximumSize: const Size(36, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      foregroundColor: selected
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : Theme.of(context).colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

/// Toggle button for [StyleEditScope] when present in [context].
class StyleEditModeButton extends StatelessWidget {
  const StyleEditModeButton({
    this.buttonKey = const ValueKey('style-edit-mode'),
    super.key,
  });

  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    if (StyleEditScope.controllerOf(context) case final editMode?) {
      return SuperToolbarIconButton(
        key: buttonKey,
        tooltip: editMode.value
            ? 'Quitter l’édition du style'
            : 'Éditer le style (clic droit sur une zone)',
        icon: Icons.brush_outlined,
        selected: editMode.value,
        onPressed: () => editMode.value = !editMode.value,
      );
    }
    return const SizedBox.shrink();
  }
}

/// Draggable floating toolbar exposing style-edit mode and appearance settings.
class FloatingAppearanceToolbar extends StatefulWidget {
  const FloatingAppearanceToolbar({
    this.initialPosition,
    this.onOpenSettings,
    super.key,
  });

  final Offset? initialPosition;
  final VoidCallback? onOpenSettings;

  @override
  State<FloatingAppearanceToolbar> createState() =>
      _FloatingAppearanceToolbarState();
}

class _FloatingAppearanceToolbarState extends State<FloatingAppearanceToolbar> {
  late _FloatingToolbarLayoutDelegate _layout =
      _FloatingToolbarLayoutDelegate(widget.initialPosition);

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: _layout,
      child: Material(
        key: const ValueKey('appearance-toolbar'),
        type: MaterialType.card,
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          child: Builder(
            builder: (context) {
              if (StyleEditScope.controllerOf(context) != null) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Déplacer la barre',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: GestureDetector(
                          key: const ValueKey('appearance-toolbar-drag'),
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) => setState(() {
                            _layout = _FloatingToolbarLayoutDelegate(
                              _layout.resolvedPosition + details.delta,
                            );
                          }),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(Icons.drag_indicator, size: 20),
                          ),
                        ),
                      ),
                    ),
                    const StyleEditModeButton(),
                    SuperToolbarIconButton(
                      key: const ValueKey('appearance-settings'),
                      tooltip: 'Paramètres d’apparence',
                      icon: Icons.settings_outlined,
                      onPressed:
                          widget.onOpenSettings ??
                          () => AppearanceSettings.show(context),
                    ),
                  ],
                );
              }
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }
}

class _FloatingToolbarLayoutDelegate extends SingleChildLayoutDelegate {
  _FloatingToolbarLayoutDelegate(this.position)
    : resolvedPosition = position ?? Offset.zero;

  final Offset? position;
  Offset resolvedPosition;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final desired = position ?? Offset(size.width - childSize.width - 16, 56);
    resolvedPosition = Offset(
      desired.dx.clamp(
        0.0,
        (size.width - childSize.width).clamp(0.0, double.infinity),
      ),
      desired.dy.clamp(
        0.0,
        (size.height - childSize.height).clamp(0.0, double.infinity),
      ),
    );
    return resolvedPosition;
  }

  @override
  bool shouldRelayout(_FloatingToolbarLayoutDelegate oldDelegate) =>
      position != oldDelegate.position;
}
