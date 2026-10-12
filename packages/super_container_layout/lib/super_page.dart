import 'package:material_ui/material_ui.dart';

/// Common scaffold for GoRouter pages, including the default root page.
class SuperPage extends StatelessWidget {
  const SuperPage({
    this.child = const SizedBox.shrink(),
    this.appBar,
    super.key,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: appBar, body: child);
}
