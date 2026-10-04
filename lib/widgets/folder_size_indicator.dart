import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../services/folder_size_service.dart';
import '../theme/explorer_colors.dart';

/// Représentation visuelle de la taille d'un dossier, relative au plus gros
/// dossier calculé du même répertoire.
enum FolderSizeDisplay {
  none('Aucun indicateur', Icons.straighten_outlined),
  bar('Barre sous la taille', Icons.align_horizontal_left_rounded),
  dot('Pastille de couleur', Icons.circle),
  pie('Jauge circulaire', Icons.pie_chart_outline_rounded),
  background('Barre en fond de ligne', Icons.view_headline_rounded);

  const FolderSizeDisplay(this.label, this.icon);

  final String label;
  final IconData icon;
}

class FolderSizeIndicator {
  FolderSizeIndicator._();

  /// Indicateur choisi, commun à toutes les listes.
  static final mode = ValueNotifier(FolderSizeDisplay.bar);

  /// Part (0..1) de [path] par rapport au plus gros de [folders] ; `null`
  /// tant que sa taille n'est pas calculée.
  static double? ratio(String path, Iterable<String> folders) {
    final bytes = FolderSizeService.bytesOf(path);
    if (bytes == null) return null;
    var max = bytes;
    for (final folder in folders) {
      max = math.max(max, FolderSizeService.bytesOf(folder) ?? 0);
    }
    return max == 0 ? 0 : bytes / max;
  }

  static Color color(double ratio) => ratio < .5
      ? Color.lerp(const Color(0xFF43A047), const Color(0xFFFB8C00), ratio * 2)!
      : Color.lerp(
          const Color(0xFFFB8C00),
          const Color(0xFFE53935),
          (ratio - .5) * 2,
        )!;
}

/// Taille d'un dossier accompagnée de l'indicateur choisi (hors fond de
/// ligne, géré par [FolderSizeRowBackground]).
class FolderSizeGauge extends StatelessWidget {
  const FolderSizeGauge({
    required this.path,
    required this.siblings,
    required this.child,
    super.key,
  });

  final String path;
  final List<String> Function()? siblings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        FolderSizeIndicator.mode,
        FolderSizeService.revision,
      ]),
      builder: (context, _) {
        final display = FolderSizeIndicator.mode.value;
        final ratio = FolderSizeIndicator.ratio(
          path,
          siblings?.call() ?? const [],
        );
        if (ratio == null ||
            display == FolderSizeDisplay.none ||
            display == FolderSizeDisplay.background) {
          return child;
        }
        final color = FolderSizeIndicator.color(ratio);
        return switch (display) {
          FolderSizeDisplay.bar => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              child,
              const SizedBox(height: 2),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  key: const ValueKey('folder-size-bar'),
                  value: ratio,
                  minHeight: 4,
                  color: color,
                  backgroundColor: color.withValues(alpha: .2),
                ),
              ),
            ],
          ),
          FolderSizeDisplay.dot => Row(
            children: [
              Container(
                key: const ValueKey('folder-size-dot'),
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(child: child),
            ],
          ),
          _ => Row(
            children: [
              SizedBox.square(
                key: const ValueKey('folder-size-pie'),
                dimension: 14,
                child: CustomPaint(painter: _PiePainter(ratio, color)),
              ),
              const SizedBox(width: 6),
              Flexible(child: child),
            ],
          ),
        };
      },
    );
  }
}

class _PiePainter extends CustomPainter {
  const _PiePainter(this.ratio, this.color);

  final double ratio;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      true,
      Paint()..color = color.withValues(alpha: .2),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * ratio,
      true,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.ratio != ratio || old.color != color;
}

/// Barre de proportion derrière toute la ligne d'un dossier.
class FolderSizeRowBackground extends StatelessWidget {
  const FolderSizeRowBackground({
    required this.path,
    required this.siblings,
    super.key,
  });

  final String path;
  final List<String> Function()? siblings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        FolderSizeIndicator.mode,
        FolderSizeService.revision,
      ]),
      builder: (context, _) {
        if (FolderSizeIndicator.mode.value != FolderSizeDisplay.background) {
          return const SizedBox.shrink();
        }
        final ratio = FolderSizeIndicator.ratio(
          path,
          siblings?.call() ?? const [],
        );
        if (ratio == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              key: const ValueKey('folder-size-background'),
              widthFactor: ratio.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: FolderSizeIndicator.color(ratio)
                      .withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Menu de choix de l'indicateur de taille, à gauche de la barre d'affichage.
class FolderSizeDisplayButton extends StatelessWidget {
  const FolderSizeDisplayButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<FolderSizeDisplay>(
      valueListenable: FolderSizeIndicator.mode,
      builder: (context, mode, _) {
        final highlighted = mode != FolderSizeDisplay.none;
        return PopupMenuButton<FolderSizeDisplay>(
          key: const ValueKey('folder-size-display-toggle'),
          tooltip: 'Indicateur de taille : ${mode.label}',
          initialValue: mode,
          onSelected: (value) => FolderSizeIndicator.mode.value = value,
          position: PopupMenuPosition.under,
          borderRadius: BorderRadius.circular(8),
          itemBuilder: (context) => [
            for (final value in FolderSizeDisplay.values)
              CheckedPopupMenuItem<FolderSizeDisplay>(
                key: ValueKey('folder-size-display-${value.name}'),
                value: value,
                checked: value == mode,
                child: Row(
                  children: [
                    Icon(value.icon, size: 16),
                    const SizedBox(width: 8),
                    Flexible(child: Text(value.label)),
                  ],
                ),
              ),
          ],
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: highlighted
                  ? colors.primary.withValues(alpha: .12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              mode.icon,
              size: 17,
              color: highlighted
                  ? colors.primary
                  : explorerColor(
                      context,
                      const Color(0xFF9298A8),
                      colors.onSurfaceVariant,
                    ),
            ),
          ),
        );
      },
    );
  }
}
