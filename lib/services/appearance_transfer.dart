import 'package:super_container_layout/services/appearance_transfer.dart' as shell;
import '../theme/surffile_appearance.dart';
import 'appearance_store.dart';
export 'package:super_container_layout/services/appearance_transfer.dart' show TransferGroup;

class AppearanceTransfer {
  const AppearanceTransfer._();
  static const format = 'surf_file.appearance';
  static const layoutKeys = {'layouts'};
  static String export(Appearance value, Set<shell.TransferGroup> groups) =>
      shell.AppearanceTransfer.export(value, groups, codec: const SurfFileAppearanceCodec());
  static Set<shell.TransferGroup> groupsIn(String text) =>
      shell.AppearanceTransfer.groupsIn(text, codec: const SurfFileAppearanceCodec());
  static Appearance import(Appearance current, String text, Set<shell.TransferGroup> groups) =>
      requireSurfFileAppearance(shell.AppearanceTransfer.import(current, text, groups, codec: const SurfFileAppearanceCodec()));
}
