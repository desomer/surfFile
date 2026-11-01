import 'package:material_ui/material_ui.dart';

class WidgetScroller extends StatelessWidget {
  final Widget child;

  const WidgetScroller({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final horizontal = ScrollController();
    final vertical = ScrollController();

    return Scrollbar(
      controller: vertical,
      thumbVisibility: true,
      trackVisibility: true,
      child: Scrollbar(
        controller: horizontal,
        thumbVisibility: true,
        trackVisibility: true,
        notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            controller: vertical,
            scrollDirection: Axis.vertical,
            child: child,
          ),
        ),
      ),
    );
  }
}
