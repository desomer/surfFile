import 'package:material_ui/material_ui.dart';
import 'disk_gauge_style.dart';
import 'file_drag_mode.dart';
import 'folder_transition.dart';
import 'surffile_appearance.dart' show SurfFileAppearanceDefaults;

export 'file_drag_mode.dart';

@immutable
class SurfFilePreferences {
  const SurfFilePreferences({
    this.diskGaugeStyle = SurfFileAppearanceDefaults.diskGaugeStyle,
    this.folderTransition = SurfFileAppearanceDefaults.folderTransition,
    this.folderTransitionDuration = SurfFileAppearanceDefaults.folderTransitionDuration,
    this.fileDragMode = SurfFileAppearanceDefaults.fileDragMode,
  });

  final DiskGaugeStyle diskGaugeStyle;
  final FolderTransition folderTransition;
  final double folderTransitionDuration;
  final FileDragMode fileDragMode;

  SurfFilePreferences copyWith({
    DiskGaugeStyle? diskGaugeStyle,
    FolderTransition? folderTransition,
    double? folderTransitionDuration,
    FileDragMode? fileDragMode,
  }) => SurfFilePreferences(
    diskGaugeStyle: diskGaugeStyle ?? this.diskGaugeStyle,
    folderTransition: folderTransition ?? this.folderTransition,
    folderTransitionDuration: folderTransitionDuration ?? this.folderTransitionDuration,
    fileDragMode: fileDragMode ?? this.fileDragMode,
  );
}
