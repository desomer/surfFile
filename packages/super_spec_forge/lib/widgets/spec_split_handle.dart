/// Poignée verticale de redimensionnement partagée entre panneaux (`SplitView`) ([SpecSplitHandle]).
library;

import 'package:material_ui/material_ui.dart';

/// Séparateur vertical interactif avec indicateur central et surbrillance au survol.
class SpecSplitHandle extends StatefulWidget {
  /// Largeur standard de la poignée en pixels logiques.
  static const double width = 8.0;

  /// Crée une poignée de redimensionnement horizontale.
  const SpecSplitHandle({
    required this.onHorizontalDragUpdate,
    this.onHorizontalDragDown,
    this.onDoubleTap,
    super.key,
  });

  /// Callback optionnel appelé dès l’appui initial avant déplacement.
  final GestureDragDownCallback? onHorizontalDragDown;

  /// Callback appelé lors du glisser horizontal de la poignée.
  final GestureDragUpdateCallback onHorizontalDragUpdate;

  /// Callback optionnel sur double-clic (ex. réinitialisation de la proportion).
  final VoidCallback? onDoubleTap;

  @override
  State<SpecSplitHandle> createState() => _SpecSplitHandleState();
}

class _SpecSplitHandleState extends State<SpecSplitHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTap,
        onHorizontalDragDown: widget.onHorizontalDragDown,
        onHorizontalDragUpdate: widget.onHorizontalDragUpdate,
        child: Container(
          width: SpecSplitHandle.width,
          decoration: BoxDecoration(
            color: _hovered
                ? colors.primary.withValues(alpha: 0.14)
                : colors.surfaceContainerLow,
            border: Border.symmetric(
              vertical: BorderSide(
                color: _hovered
                    ? colors.primary.withValues(alpha: 0.5)
                    : colors.outlineVariant,
              ),
            ),
          ),
          child: Center(
            child: Container(
              width: 2,
              height: 28,
              decoration: BoxDecoration(
                color: _hovered ? colors.primary : colors.outlineVariant,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
