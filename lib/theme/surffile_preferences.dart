import 'package:material_ui/material_ui.dart';
import 'disk_gauge_style.dart';
import 'folder_transition.dart';
import 'surffile_appearance.dart' show SurfFileAppearanceDefaults;

@immutable
class SurfFilePreferences {
  const SurfFilePreferences({
    this.diskGaugeStyle = SurfFileAppearanceDefaults.diskGaugeStyle,
    this.folderTransition = SurfFileAppearanceDefaults.folderTransition,
    this.folderTransitionDuration = SurfFileAppearanceDefaults.folderTransitionDuration,
  });

  final DiskGaugeStyle diskGaugeStyle;
  final FolderTransition folderTransition;
  final double folderTransitionDuration;

  SurfFilePreferences copyWith({
    DiskGaugeStyle? diskGaugeStyle,
    FolderTransition? folderTransition,
    double? folderTransitionDuration,
  }) => SurfFilePreferences(
    diskGaugeStyle: diskGaugeStyle ?? this.diskGaugeStyle,
    folderTransition: folderTransition ?? this.folderTransition,
    folderTransitionDuration: folderTransitionDuration ?? this.folderTransitionDuration,
  );
}
