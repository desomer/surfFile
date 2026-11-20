/// Portée et cadre de simulation d'aperçu responsive ([EditorViewportPreviewScope], [EditorViewportPreviewFrame]).
///
/// Permet de prévisualiser l'application à la largeur exacte de chacun des
/// 4 breakpoints configurés (Mobile 375, Tablette 768, Desktop 1280, Large Desktop 1440)
/// depuis la bannière du mode édition ([StyleEditBanner]).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/responsive_layout_config.dart';

/// Portée descendante exposant le [ValueNotifier] du breakpoint simulé en édition.
class EditorViewportPreviewScope extends InheritedWidget {
  const EditorViewportPreviewScope({
    required this.controller,
    required super.child,
    super.key,
  });

  /// Contrôleur du breakpoint simulé (`null` = largeur réelle de la fenêtre).
  final ValueNotifier<ResponsiveBreakpoint?> controller;

  /// Retourne le contrôleur de prévisualisation responsive le plus proche, ou `null`.
  static ValueNotifier<ResponsiveBreakpoint?>? controllerOf(
    BuildContext context,
  ) => context
      .dependOnInheritedWidgetOfExactType<EditorViewportPreviewScope>()
      ?.controller;

  @override
  bool updateShouldNotify(EditorViewportPreviewScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Cadre de simulation appliquant une largeur fixe de breakpoint au contenu applicatif.
class EditorViewportPreviewFrame extends StatelessWidget {
  const EditorViewportPreviewFrame({
    required this.breakpoint,
    required this.breakpointsConfig,
    required this.child,
    this.onReset,
    super.key,
  });

  /// Breakpoint à simuler ; `null` rend [child] directement en pleine fenêtre.
  final ResponsiveBreakpoint? breakpoint;

  /// Seuils configurés permettant de résoudre la largeur exacte en pixels.
  final ResponsiveBreakpointsConfig breakpointsConfig;

  /// Callback optionnel pour revenir au mode fenêtre (`Auto`).
  final VoidCallback? onReset;

  /// Contenu applicatif simulé.
  final Widget child;

  static IconData iconFor(ResponsiveBreakpoint? bp) => switch (bp) {
    null => Icons.devices_outlined,
    ResponsiveBreakpoint.mobile => Icons.phone_android_outlined,
    ResponsiveBreakpoint.tablet => Icons.tablet_mac_outlined,
    ResponsiveBreakpoint.desktop => Icons.laptop_mac_outlined,
    ResponsiveBreakpoint.largeDesktop => Icons.desktop_windows_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final active = breakpoint;
    if (active == null) return child;

    final targetWidth = breakpointsConfig.previewWidthFor(active);
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);

    return ColoredBox(
      key: const ValueKey('editor-viewport-preview-backdrop'),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : media.size.width;
          final availableHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : media.size.height;
          final frameHeight = math.max(0.0, availableHeight);

          final frame = DecoratedBox(
            key: ValueKey('editor-viewport-preview-frame-${active.name}'),
            decoration: BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: scheme.outlineVariant),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                ),
              ],
            ),
            child: ClipRect(
              child: SizedBox(
                width: targetWidth,
                height: frameHeight,
                child: MediaQuery(
                  data: media.copyWith(size: Size(targetWidth, frameHeight)),
                  child: child,
                ),
              ),
            ),
          );

          if (availableWidth >= targetWidth) {
            return Center(child: frame);
          }

          return SingleChildScrollView(
            key: const ValueKey('editor-viewport-preview-scroll'),
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: availableWidth),
              child: Center(child: frame),
            ),
          );
        },
      ),
    );
  }
}
