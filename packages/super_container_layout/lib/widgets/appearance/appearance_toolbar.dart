/// Barre d'outils flottante et déplaçable de l'application ([AppearanceToolbar]).
///
/// Donne accès au basculement de thème, au mode édition, à l'historique Undo/Redo,
/// au gestionnaire de pages, aux repositories JSON, à l'import/export et au chat Vibe IA.
library;

import 'package:material_ui/material_ui.dart';

import '../../super_app.dart';
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

/// Portée `InheritedWidget` exposant une action d'ouverture du sélecteur
/// d'application sandboxée à [FloatingAppearanceToolbar].
class ApplicationSelectorScope extends InheritedWidget {
  const ApplicationSelectorScope({
    required this.onOpenApplications,
    this.tooltip = 'Applications',
    required super.child,
    super.key,
  });

  /// Action déclenchée lors du clic sur l'icône d'applications (`3×3` points).
  final VoidCallback? onOpenApplications;

  /// Info-bulle affichée sur le bouton d'applications.
  final String tooltip;

  /// Retourne la portée la plus proche si présente dans [context].
  static ApplicationSelectorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ApplicationSelectorScope>();

  @override
  bool updateShouldNotify(ApplicationSelectorScope oldWidget) =>
      onOpenApplications != oldWidget.onOpenApplications ||
      tooltip != oldWidget.tooltip;
}

/// Draggable floating toolbar exposing style-edit mode and appearance settings.
class FloatingAppearanceToolbar extends StatefulWidget {
  const FloatingAppearanceToolbar({
    this.initialPosition,
    this.onOpenSettings,
    this.onOpenApplications,
    this.applicationsTooltip,
    super.key,
  });

  final Offset? initialPosition;
  final VoidCallback? onOpenSettings;

  /// Action optionnelle ouvrant la sélection d'application sandboxée (`Icons.apps`).
  final VoidCallback? onOpenApplications;

  /// Info-bulle du bouton d'applications.
  final String? applicationsTooltip;

  @override
  State<FloatingAppearanceToolbar> createState() =>
      _FloatingAppearanceToolbarState();
}

class _FloatingAppearanceToolbarState extends State<FloatingAppearanceToolbar> {
  late _FloatingToolbarLayoutDelegate _layout =
      _FloatingToolbarLayoutDelegate(widget.initialPosition);
  bool _positionInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_positionInitialized) {
      _positionInitialized = true;
      final sharedPosition = SuperAppScope.toolbarPositionOf(context)?.value;
      if (widget.initialPosition == null && sharedPosition != null) {
        _layout = _FloatingToolbarLayoutDelegate(sharedPosition);
      }
    }
  }

  @override
  void didUpdateWidget(FloatingAppearanceToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPosition != widget.initialPosition &&
        widget.initialPosition != null) {
      _layout = _FloatingToolbarLayoutDelegate(widget.initialPosition);
    }
  }

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
                final appScope = ApplicationSelectorScope.maybeOf(context);
                final openApplications =
                    widget.onOpenApplications ?? appScope?.onOpenApplications;
                final appsTooltip =
                    widget.applicationsTooltip ??
                    appScope?.tooltip ??
                    'Applications';
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
                          onPanUpdate: (details) {
                            final nextPosition =
                                _layout.resolvedPosition + details.delta;
                            SuperAppScope.toolbarPositionOf(context)?.value =
                                nextPosition;
                            setState(() {
                              _layout = _FloatingToolbarLayoutDelegate(
                                nextPosition,
                              );
                            });
                          },
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
                    if (openApplications != null)
                      SuperToolbarIconButton(
                        key: const ValueKey('appearance-applications'),
                        tooltip: appsTooltip,
                        icon: Icons.apps,
                        onPressed: openApplications,
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
    final desired = position ?? Offset(size.width - childSize.width - 16,  size.height - childSize.height - 50);
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
