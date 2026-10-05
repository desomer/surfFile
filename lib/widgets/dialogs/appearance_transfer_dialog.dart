import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/appearance_transfer_dialog.dart' as shell;
import '../../services/appearance_store.dart';
import '../../theme/surffile_appearance.dart';

class AppearanceTransferDialog extends shell.AppearanceTransferDialog {
  AppearanceTransferDialog({
    required ValueNotifier<Appearance> super.controller,
    SurfFileAppearanceCodec? codec,
    super.key,
  }) : super(codec: codec ?? SurfFileAppearanceCodec());

  static Future<void> show(BuildContext context, ValueNotifier<Appearance> controller) =>
      shell.AppearanceTransferDialog.show(
        context, controller,
        codec: SurfFileAppearanceCodec(preferences: SurfFilePreferencesScope.controllerOf(context)),
      );
}
