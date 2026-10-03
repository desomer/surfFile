import 'package:material_ui/material_ui.dart';

class FolderHeroFlight extends StatelessWidget {
  const FolderHeroFlight({
    required this.source,
    required this.destination,
    required this.duration,
    required this.expand,
    required this.color,
    required this.onComplete,
    super.key,
  });

  final Rect source;
  final Rect destination;
  final Duration duration;
  final bool expand;
  final Color color;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: duration,
            curve: Curves.easeInOutCubic,
            onEnd: onComplete,
            builder: (context, progress, _) {
              final rect = Rect.lerp(source, destination, progress)!;
              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: Opacity(
                      opacity: expand
                          ? (1 - ((progress - .5) * 2).clamp(0.0, 1.0))
                          : 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: expand ? color : null,
                          borderRadius:
                              BorderRadius.circular(13 * (1 - progress)),
                        ),
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Icon(Icons.folder_rounded,
                              color: expand
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : color,
                              size: 48),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
}
