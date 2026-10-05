import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/widgets/appearance_style_section.dart'
    as shell;
import '../../theme/surffile_appearance.dart';

/// Compatibility adapter for callers of the application style dialog.
class AppearanceStyleSection extends StatelessWidget {
  const AppearanceStyleSection(this.slot, {super.key});
  final AppearanceSlot slot;
  @override
  Widget build(BuildContext context) =>
      shell.AppearanceStyleSection(slot, defaults: defaultSurfFileAppearance);
}
