import 'package:material_ui/material_ui.dart';

import '../theme/appearance.dart';
import '../theme/folder_transition.dart';

class FolderTransitionView extends StatefulWidget {
  const FolderTransitionView({
    required this.revision,
    required this.reverse,
    required this.child,
    super.key,
  });

  final int revision;
  final bool reverse;
  final Widget child;

  @override
  State<FolderTransitionView> createState() => _FolderTransitionViewState();
}

class _FolderTransitionViewState extends State<FolderTransitionView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  FolderTransition _type = FolderTransition.none;
  bool _reverse = false;
  Widget? _previous;
  int? _previousRevision;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: 1);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _previous != null) {
        setState(() {
          _previous = null;
          _previousRevision = null;
        });
      }
    });
  }

  @override
  void didUpdateWidget(FolderTransitionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision == widget.revision) return;
    final appearance = AppearanceScope.of(context);
    _type = appearance.folderTransition;
    _reverse = widget.reverse;
    _controller.duration =
        Duration(milliseconds: appearance.folderTransitionDuration.round());
    if (_type == FolderTransition.none ||
        MediaQuery.disableAnimationsOf(context)) {
      _previous = null;
      _previousRevision = null;
      _controller.value = 1;
    } else {
      _previous = oldWidget.child;
      _previousRevision = oldWidget.revision;
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        AppearanceScope.of(context).folderTransition == FolderTransition.none) {
      _previous = null;
      _previousRevision = null;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = Curves.easeOutCubic.transform(_controller.value);
          final remaining = 1 - progress;
          final current = KeyedSubtree(
            key: ValueKey(widget.revision),
            child: widget.child,
          );
          final incoming = switch (_type) {
            FolderTransition.none => current,
            FolderTransition.fade ||
            FolderTransition.heroExpand ||
            FolderTransition.heroIcon =>
              Opacity(
                key: const ValueKey('folder-fade'),
                opacity: progress,
                child: current,
              ),
            FolderTransition.slide => FractionalTranslation(
                key: const ValueKey('folder-slide'),
                translation: Offset((_reverse ? -.08 : .08) * remaining, 0),
                child: current,
              ),
            FolderTransition.fullSlide => FractionalTranslation(
                key: const ValueKey('folder-full-slide'),
                translation: Offset((_reverse ? -1.0 : 1.0) * remaining, 0),
                child: current,
              ),
            FolderTransition.zoom => Transform.scale(
                key: const ValueKey('folder-zoom'),
                scale: 1 + (_reverse ? .03 : -.03) * remaining,
                child: current,
              ),
          };
          final previous = _previous;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (previous != null)
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: _outgoing(
                      progress,
                      remaining,
                      KeyedSubtree(
                        key: ValueKey(_previousRevision),
                        child: previous,
                      ),
                    ),
                  ),
                ),
              incoming,
            ],
          );
        },
      ),
    );
  }

  Widget _outgoing(double progress, double remaining, Widget child) {
    return switch (_type) {
      FolderTransition.none => child,
      FolderTransition.fade ||
      FolderTransition.heroExpand ||
      FolderTransition.heroIcon =>
        Opacity(
          opacity: remaining,
          child: child,
        ),
      FolderTransition.slide ||
      FolderTransition.fullSlide =>
        FractionalTranslation(
          translation: Offset(
              (_reverse ? 1.0 : -1.0) *
                  (_type == FolderTransition.fullSlide ? 1 : .08) *
                  progress,
              0),
          child: _type == FolderTransition.slide
              ? Opacity(opacity: remaining, child: child)
              : child,
        ),
      FolderTransition.zoom => Opacity(
          opacity: remaining,
          child: Transform.scale(
            scale: 1 + (_reverse ? -.03 : .03) * progress,
            child: child,
          ),
        ),
    };
  }
}
