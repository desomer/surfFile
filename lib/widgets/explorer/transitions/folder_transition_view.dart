import 'package:material_ui/material_ui.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/theme/folder_transition.dart';

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
    _controller.duration = Duration(
      milliseconds: appearance.folderTransitionDuration.round(),
    );
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

  // Les *Transition écoutent directement le contrôleur : le contenu des
  // dossiers n'est ni reconstruit ni repeint à chaque image, seule la couche
  // de composition change.
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<double> _remaining = ReverseAnimation(_progress);

  Animation<Offset> _slide(double from, double to) => Tween<Offset>(
    begin: Offset(from, 0),
    end: Offset(to, 0),
  ).animate(_progress);

  Animation<double> _scale(double from, double to) =>
      Tween<double>(begin: from, end: to).animate(_progress);

  @override
  Widget build(BuildContext context) {
    final current = KeyedSubtree(
      key: ValueKey(widget.revision),
      child: RepaintBoundary(child: widget.child),
    );
    final direction = _reverse ? -1.0 : 1.0;
    final incoming = switch (_type) {
      FolderTransition.none => current,
      FolderTransition.fade ||
      FolderTransition.heroExpand ||
      FolderTransition.heroIcon => FadeTransition(
        key: const ValueKey('folder-fade'),
        opacity: _progress,
        child: current,
      ),
      FolderTransition.slide => SlideTransition(
        key: const ValueKey('folder-slide'),
        position: _slide(.08 * direction, 0),
        child: current,
      ),
      FolderTransition.fullSlide => SlideTransition(
        key: const ValueKey('folder-full-slide'),
        position: _slide(direction, 0),
        child: current,
      ),
      FolderTransition.zoom => ScaleTransition(
        key: const ValueKey('folder-zoom'),
        scale: _scale(1 - .03 * direction, 1),
        child: current,
      ),
    };
    final previous = _previous;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (previous != null)
            IgnorePointer(
              child: ExcludeSemantics(
                child: _outgoing(
                  KeyedSubtree(
                    key: ValueKey(_previousRevision),
                    child: RepaintBoundary(child: previous),
                  ),
                ),
              ),
            ),
          incoming,
        ],
      ),
    );
  }

  Widget _outgoing(Widget child) {
    final direction = _reverse ? 1.0 : -1.0;
    return switch (_type) {
      FolderTransition.none => child,
      FolderTransition.fade ||
      FolderTransition.heroExpand ||
      FolderTransition.heroIcon => FadeTransition(
        opacity: _remaining,
        child: child,
      ),
      FolderTransition.slide => SlideTransition(
        position: _slide(0, .08 * direction),
        child: FadeTransition(opacity: _remaining, child: child),
      ),
      FolderTransition.fullSlide => SlideTransition(
        position: _slide(0, direction),
        child: child,
      ),
      FolderTransition.zoom => FadeTransition(
        opacity: _remaining,
        child: ScaleTransition(
          scale: _scale(1, 1 - .03 * direction),
          child: child,
        ),
      ),
    };
  }
}
