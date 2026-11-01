import 'package:material_ui/material_ui.dart';
import 'package:super_container_extensions/widgets/components/internal_widget/widget_scroller.dart';

class WidgetErrorBanner extends StatefulWidget {
  const WidgetErrorBanner({super.key, required this.error});
  final ValueNotifier<String> error;

  @override
  State<WidgetErrorBanner> createState() => _WidgetErrorBannerState();
}

class _WidgetErrorBannerState extends State<WidgetErrorBanner> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.error,
      builder: (BuildContext context, String value, child) {
        bool isValid = widget.error.value == '_VALID_';
        bool isError = widget.error.value != '';
        if (isValid) {
          return SizedBox(
            height: 30,
            width: double.infinity,
            child: Card(
              color: Colors.green,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: const Text('COMPLIANT MODEL'),
              ),
            ),
          );
        }
        return isError
            ? SizedBox(
                width: double.infinity,
                child: Card(
                  color: Colors.red,
                  child: getDoubleScroll(
                    IntrinsicWidth(
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: SelectableText(value),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink();
      },
    );
  }

  Widget getDoubleScroll(Widget child) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200, minHeight: 100),
      child: WidgetScroller(child: child),
    );
  }
}
