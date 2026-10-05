import 'package:material_ui/material_ui.dart';
import '../../models/explorer_entry.dart';
import '../../models/explorer_filter.dart';
import '../../models/explorer_location.dart';
import '../../models/selection_mode.dart';
import 'navigation/explorer_action_bar.dart';

/// Immutable presentation snapshots; state and commands remain owned by a pane.
typedef ExplorerPaneData = ({
  ExplorerSidebarData sidebar,
  String path,
  String title,
  bool split,
  bool active,
  bool editable,
  bool gridView,
  bool columnView,
  bool heatmapView,
  bool filterOpen,
  ExplorerFilter filter,
  ExplorerSort sort,
  bool ascending,
  SelectionMode selectionMode,
  List<ExplorerEntry> entries,
  int total,
  Set<String> selection,
  String? selectedPath,
  bool checkboxSelection,
  Object? revealToken,
  bool loading,
  bool pending,
  bool hasLoaded,
  String? error,
  bool hasQuery,
  bool dropEnabled,
  bool previewVisible,
  bool previewExpanded,
  int folderRevision,
  bool reverseTransition,
  Object refreshToken,
  GlobalKey contentKey,
  GlobalKey titleIconKey,
  GlobalKey imagePreviewKey,
  GlobalKey textPreviewKey,
  GlobalKey videoPreviewKey,
});

typedef ExplorerPaneActions = ({
  ValueChanged<String> onSidebarLocation,
  VoidCallback onActivate,
  List<ExplorerBarAction> Function({required bool canPaste}) barActions,
  ValueChanged<bool> onGridViewChanged,
  ValueChanged<bool> onColumnViewChanged,
  ValueChanged<bool> onHeatmapViewChanged,
  ValueChanged<SelectionMode> onSelectionModeChanged,
  VoidCallback onToggleFilter,
  ValueChanged<ExplorerFilter> onFilterChanged,
  VoidCallback onCloseFilter,
  ValueChanged<ExplorerSort> onSortChanged,
  VoidCallback onRetry,
  ValueChanged<String> onPointerSelect,
  ValueChanged<String> onTapped,
  ValueChanged<String> onColumnTapped,
  ValueChanged<Set<String>> onSelectionChanged,
  ValueChanged<String> onToggleSelection,
  ValueChanged<Size> onViewportChanged,
  ValueChanged<ExplorerEntry> onOpen,
  void Function(ExplorerEntry, Rect, Rect) onOpenWithBounds,
  void Function(ExplorerEntry, Offset)? onContextMenu,
  void Function(String, {String? select}) onNavigateColumn,
  void Function(List<String>, String) onDrop,
  VoidCallback onClosePreview,
  VoidCallback onTogglePreviewExpanded,
});

typedef ExplorerSidebarData = ({
  List<ExplorerLocation> locations,
  String currentPath,
});

typedef ExplorerSidebarActions = ({ValueChanged<String> onLocationSelected});

class ExplorerPaneScope extends InheritedWidget {
  const ExplorerPaneScope({
    required this.data,
    required this.actions,
    required super.child,
    super.key,
  });

  final ExplorerPaneData data;
  final ExplorerPaneActions actions;

  static ExplorerPaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ExplorerPaneScope>();

  static ExplorerPaneScope of(BuildContext context) =>
      maybeOf(context) ??
      (throw FlutterError('ExplorerPaneScope requires an ExplorerPane ancestor.'));

  @override
  bool updateShouldNotify(ExplorerPaneScope oldWidget) =>
      data != oldWidget.data || actions != oldWidget.actions;
}

class ExplorerSidebarScope extends InheritedWidget {
  const ExplorerSidebarScope({
    required this.data,
    required this.actions,
    required super.child,
    super.key,
  });

  final ExplorerSidebarData data;
  final ExplorerSidebarActions actions;

  static ExplorerSidebarScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ExplorerSidebarScope>();

  static ExplorerSidebarScope of(BuildContext context) =>
      maybeOf(context) ??
      (throw FlutterError('ExplorerSidebarScope requires a sidebar ancestor.'));

  @override
  bool updateShouldNotify(ExplorerSidebarScope oldWidget) =>
      data != oldWidget.data || actions != oldWidget.actions;
}

class ExplorerNavigation {
  const ExplorerNavigation({
    required this.path,
    required this.canGoBack,
    required this.canGoForward,
    required this.canGoUp,
    required this.split,
    required this.onBack,
    required this.onForward,
    required this.onUp,
    required this.onRefresh,
    required this.onSearchChanged,
    required this.onCreateFolder,
    required this.onNavigate,
    this.onToggleSplit,
  });

  final String path;
  final bool canGoBack;
  final bool canGoForward;
  final bool canGoUp;
  final bool split;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onUp;
  final VoidCallback onRefresh;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCreateFolder;
  final ValueChanged<String> onNavigate;
  final VoidCallback? onToggleSplit;
}

class ExplorerScope extends InheritedWidget {
  const ExplorerScope({
    required this.navigation,
    required super.child,
    super.key,
  });

  final ExplorerNavigation navigation;

  static ExplorerNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ExplorerScope>()?.navigation;

  static ExplorerNavigation of(BuildContext context) {
    final navigation = maybeOf(context);
    if (navigation == null) {
      throw FlutterError(
        'ExplorerScope.of() requires an ExplorerPane ancestor.',
      );
    }

    return navigation;
  }

  @override
  bool updateShouldNotify(ExplorerScope oldWidget) =>
      navigation != oldWidget.navigation;
}

/// Availability is local to a layout, not shared across split panes.
class ExplorerComponentScope extends InheritedWidget {
  const ExplorerComponentScope({
    required this.visible,
    required super.child,
    super.key,
  });

  final Set<String> visible;

  static ExplorerComponentScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ExplorerComponentScope>();

  @override
  bool updateShouldNotify(ExplorerComponentScope oldWidget) =>
      visible != oldWidget.visible;
}
