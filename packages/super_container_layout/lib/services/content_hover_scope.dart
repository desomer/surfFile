import 'package:material_ui/material_ui.dart';

/// The nearest IterableContent owns the hover of its whole row.
class ContentHoverScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ContentHoverScope({
    required ValueNotifier<bool> hovered,
    required super.child,
    super.key,
  }) : super(notifier: hovered);

  static ContentHoverScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentHoverScope>();

  bool get hovered => notifier!.value;
}
