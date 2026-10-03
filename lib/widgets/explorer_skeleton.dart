import 'package:material_ui/material_ui.dart';

import '../theme/appearance.dart';

/// Contenu provisoire affiché pendant le glissement vers un nouveau dossier.
///
/// Volontairement statique (pas de shimmer) et sans widgets de la liste
/// réelle : il ne coûte presque rien à construire et à peindre.
class ExplorerSkeleton extends StatelessWidget {
  const ExplorerSkeleton({required this.gridView, super.key});

  final bool gridView;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final block = colors.onSurface.withValues(alpha: .07);
    final appearance = AppearanceScope.of(context);
    return RepaintBoundary(
      child: ClipRect(
        child: LayoutBuilder(
          // Les lignes débordent volontairement en bas : pas d'avertissement.
          builder: (context, constraints) => OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: double.infinity,
            child: gridView
                ? _grid(constraints, appearance, block)
                : _list(constraints, block),
          ),
        ),
      ),
    );
  }

  Widget _list(BoxConstraints constraints, Color block) {
    const rowHeight = 46.0;
    final count = constraints.maxHeight.isFinite
        ? (constraints.maxHeight / rowHeight).ceil().clamp(1, 40)
        : 12;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 6, 30, 0),
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  _box(block, 24, 24, 6),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: .35 + (i * 37 % 40) / 100,
                        child: _box(block, null, 12, 6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  _box(block, 90, 10, 5),
                  const SizedBox(width: 20),
                  _box(block, 56, 10, 5),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(BoxConstraints constraints, Appearance appearance, Color block) {
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth - 60
        : 600.0;
    final spacing = appearance.spacing;
    final columns = ((width + spacing) / (appearance.cardWidth + spacing))
        .ceil()
        .clamp(1, 12);
    final rows = constraints.maxHeight.isFinite
        ? (constraints.maxHeight / (appearance.cardHeight + spacing))
              .ceil()
              .clamp(1, 10)
        : 3;
    final radius = appearance.cardStyle.radius;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 8, 30, 0),
      child: Column(
        children: [
          for (var r = 0; r < rows; r++)
            Padding(
              padding: EdgeInsets.only(bottom: spacing),
              child: Row(
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) SizedBox(width: spacing),
                    Expanded(
                      child: _box(block, null, appearance.cardHeight, radius),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Widget _box(
    Color color,
    double? width,
    double height,
    double radius,
  ) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
