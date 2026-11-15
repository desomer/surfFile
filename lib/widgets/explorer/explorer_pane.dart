/// Volet de navigation autonome de l’explorateur, rendu par les scopes partagés.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/widgets/components/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';
import 'package:surf_file/theme/folder_transition.dart';
import 'package:surf_file/theme/surffile_appearance.dart';

import 'package:surf_file/actions/file_actions.dart';
import 'package:surf_file/models/explorer_entry.dart';
import 'package:surf_file/models/explorer_filter.dart';
import 'package:surf_file/models/explorer_location.dart';
import 'package:surf_file/models/selection_mode.dart';
import 'package:surf_file/services/directory_scanner.dart';
import 'package:surf_file/services/external_drop_transfer.dart';
import 'package:surf_file/services/favorites.dart';
import 'package:surf_file/services/file_operations.dart';
import 'package:surf_file/services/folder_size_service.dart';
import 'package:surf_file/services/personal_folders.dart';
import 'package:surf_file/services/windows_context_menu.dart';
import 'package:surf_file/widgets/dialogs/shortcuts_help_dialog.dart';
import 'package:surf_file/widgets/explorer/explorer_components.dart';
import 'package:surf_file/widgets/explorer/explorer_scope.dart';
import 'package:surf_file/widgets/explorer/menus/explorer_context_menu.dart';
import 'package:surf_file/widgets/explorer/navigation/explorer_action_bar.dart';
import 'package:surf_file/widgets/explorer/transitions/folder_hero_flight.dart';
import 'package:surf_file/widgets/explorer/views/entries_layout.dart';
import 'package:surf_file/widgets/file_operations/file_action_bar.dart';
import 'package:surf_file/widgets/interaction/mouse_back_navigation.dart';
import 'package:surf_file/widgets/preview/image_preview_panel.dart';
import 'package:surf_file/widgets/preview/text_preview_panel.dart';
import 'package:surf_file/widgets/preview/video_preview_panel.dart';

part 'explorer_pane_controller.dart';
part 'explorer_pane_commands.dart';

enum _HistoryDirection { back, forward }

/// Une navigation de dossiers complète (barre d'outils, chemin, fichiers).
typedef _LoadRollback = ({
  String path,
  List<ExplorerEntry> entries,
  List<String> history,
  List<String> forward,
  String? selected,
});

class ExplorerPane extends StatefulWidget {
  const ExplorerPane({
    this.initialPath,
    this.showSidebar = true,
    this.autofocus = true,
    this.split = false,
    this.active = false,
    this.onActivate,
    this.onPathChanged,
    this.onToggleSplit,
    this.sidebarPath,
    this.onSidebarLocation,
    this.splitChild,
    this.splitBarBuilder,
    this.onSelectionChanged,
    super.key,
  });

  final String? initialPath;
  final bool showSidebar;
  final bool autofocus;
  final bool split;

  /// Volet cible de la barre latérale en mode divisé (souligné).
  final bool active;
  final VoidCallback? onActivate;
  final ValueChanged<String>? onPathChanged;
  final VoidCallback? onToggleSplit;

  /// Dossier mis en évidence et cible de la barre latérale si elle pilote un
  /// autre volet que celui-ci.
  final String? sidebarPath;
  final ValueChanged<String>? onSidebarLocation;

  /// Second volet affiché à droite, hors de la navigation souris/clavier de
  /// celui-ci.
  final Widget? splitChild;

  /// Barre placée entre ce volet et [splitChild], reconstruite avec ce volet.
  final WidgetBuilder? splitBarBuilder;
  final VoidCallback? onSelectionChanged;

  @override
  State<ExplorerPane> createState() => ExplorerPaneState();
}

class ExplorerPaneState extends State<ExplorerPane>
    with ExplorerPaneController, ExplorerPaneCommands
    implements ExplorerPaneHandle {
  @override
  bool get ready => _ready;

  @override
  PaneSnapshot get snapshot => _snapshot;

  @override
  Future<void> navigate(String path) => _loadDirectory(path);

  @override
  Future<void> refresh() => _refresh();

  @override
  void touch() => _touch();

  late final Registry _standaloneRegistry = createExplorerRegistry();
  @override
  Size _viewport = Size.zero;
  @override
  final _contentKey = GlobalKey();
  @override
  final _titleIconKey = GlobalKey();
  @override
  final _overlayKey = GlobalKey();
  @override
  Rect? _heroSource;
  @override
  Rect? _heroDestination;
  @override
  bool _heroExpand = false;
  @override
  int _heroRevision = 0;
  @override
  Duration _heroDuration = Duration.zero;
  @override
  final _explorerFocusNode = FocusNode(debugLabel: 'File explorer');
  final _imagePreviewKey = GlobalKey();
  final _textPreviewKey = GlobalKey();
  final _videoPreviewKey = GlobalKey();

  @override
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Future<FileJob?> _confirmExternalDrop(
    List<String> sources,
    String destination,
  ) => ExternalDropTransfer.confirm(context, sources, destination);

  @override
  Future<bool> _confirmDelete(
    List<String> paths, {
    required bool permanent,
  }) async {
    final hard = permanent || !Platform.isWindows;
    final count = paths.length;
    final what = count == 1
        ? '« ${FileOperations.name(paths.first)} »'
        : '$count éléments';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('delete-confirm'),
        title: Text(
          hard ? 'Supprimer définitivement ?' : 'Mettre à la corbeille ?',
        ),
        content: Text(
          hard
              ? (count == 1
                    ? '$what sera supprimé sans passer par la corbeille.'
                    : '$what seront supprimés sans passer par la corbeille.')
              : (count == 1
                    ? '$what sera envoyé à la corbeille.'
                    : '$what seront envoyés à la corbeille.'),
        ),
        actions: [
          // Le focus initial évite qu'Entrée confirme une suppression.
          TextButton(
            key: const ValueKey('delete-cancel'),
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('delete-accept'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(hard ? 'Supprimer' : 'Mettre à la corbeille'),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _showContextMenu(ExplorerEntry entry, Offset position) async {
    if (_contextMenuOpen) return;
    _contextMenuOpen = true;
    _selectionChanged(() {
      if (_selection.contains(entry.entity.path)) {
        _primary = entry.entity.path;
      } else {
        _selectedPath = entry.entity.path;
      }
    });
    WindowsContextMenu? menu;
    try {
      menu = await WindowsContextMenu.open(entry.entity.path);
      if (!mounted) return;
      final command = await ExplorerContextMenu.show(
        context: context,
        position: position,
        menu: menu,
      );
      if (command == null || !mounted) return;
      if (command.verb.toLowerCase() == 'rename') {
        await _renameEntry(entry, menu, command.id);
      } else {
        if (command.verb.toLowerCase() == 'delete' &&
            !await _confirmDelete([entry.entity.path], permanent: false)) {
          return;
        }
        await menu.invoke(command.id);
      }
      if (mounted) {
        await _loadDirectory(_currentPath, addToHistory: false);
      }
    } on PlatformException catch (error) {
      debugPrint('Windows context menu error: $error');
      if (mounted) {
        _showMessage(
          'Impossible d’utiliser le menu Windows : '
          '${error.message ?? error.code}',
        );
      }
    } on MissingPluginException catch (error) {
      debugPrint('Windows context menu unavailable: $error');
      if (mounted) {
        _showMessage(
          'Le menu Windows est indisponible. '
          'Arrêtez puis relancez l’application.',
        );
      }
    } finally {
      try {
        await menu?.close();
      } on PlatformException catch (error) {
        debugPrint('Error closing Windows context menu: $error');
        if (mounted) {
          _showMessage(
            'Impossible de fermer le contexte du menu Windows : '
            '${error.message ?? error.code}',
          );
        }
      } finally {
        _contextMenuOpen = false;
      }
    }
  }

  @override
  Future<String?> _askNewName(ExplorerEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final dot = entry.name.lastIndexOf('.');
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: entry.isDirectory || dot <= 0 ? entry.name.length : dot,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nouveau nom'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return null;
    final newName = name.trim();
    if (newName.isEmpty ||
        newName == '.' ||
        newName == '..' ||
        RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(newName) ||
        newName.endsWith('.')) {
      _showMessage('Ce nom de fichier ou de dossier n’est pas valide.');
      return null;
    }
    return newName == entry.name ? null : newName;
  }

  @override
  Future<String?> _askFolderName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau dossier'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom du dossier',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    controller.dispose();
    return name;
  }

  @override
  void dispose() {
    _jobsSubscription?.cancel();
    FolderSizeService.revision.removeListener(_folderSizeChanged);
    _explorerFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) => setState(() => _query = value);

  void _onSidebarLocationSelected(String path) =>
      (widget.onSidebarLocation ?? _loadDirectory)(path);

  void _onPaneActivate() {
    widget.onActivate?.call();
    if (widget.split && !_explorerFocusNode.hasFocus) {
      _explorerFocusNode.requestFocus();
    }
  }

  void _onGridViewChanged(bool value) => setState(() => _gridView = value);
  void _onColumnViewChanged(bool value) => setState(() => _columnView = value);
  void _onHeatmapViewChanged(bool value) =>
      setState(() => _heatmapView = value);
  void _onSelectionModeChanged(SelectionMode value) =>
      setState(() => _selectionMode = value);
  void _onToggleFilter() => setState(() => _filterOpen = !_filterOpen);
  void _onFilterChanged(ExplorerFilter value) =>
      setState(() => _filter = value);
  void _onCloseFilter() => setState(() => _filterOpen = false);

  void _onSortChanged(ExplorerSort sort) => setState(() {
    if (_sort == sort) {
      _ascending = !_ascending;
    } else {
      _sort = sort;
      _ascending = true;
    }
  });

  void _onRetry() {
    if (_initializationFailed) {
      _initialize();
    } else {
      _loadDirectory(_failedPath ?? _currentPath, direction: _failedDirection);
    }
  }

  void _onMarqueeSelectionChanged(Set<String> paths) {
    _explorerFocusNode.requestFocus();
    _selectionChanged(() {
      _collapseTo = null;
      _setSelection(paths);
    });
  }

  void _onViewportChanged(Size size) => _viewport = size;

  void _onOpenWithBounds(ExplorerEntry entry, Rect card, Rect icon) =>
      _loadDirectory(entry.entity.path, heroCard: card, heroIcon: icon);

  void _onClosePreview() => setState(() {
    _previewVisible = false;
    _previewExpanded = false;
  });

  void _onTogglePreviewExpanded() =>
      setState(() => _previewExpanded = !_previewExpanded);

  late final ExplorerPaneActions _paneActions = (
    onSidebarLocation: _onSidebarLocationSelected,
    onActivate: _onPaneActivate,
    barActions: _barActions,
    onGridViewChanged: _onGridViewChanged,
    onColumnViewChanged: _onColumnViewChanged,
    onHeatmapViewChanged: _onHeatmapViewChanged,
    onSelectionModeChanged: _onSelectionModeChanged,
    onToggleFilter: _onToggleFilter,
    onFilterChanged: _onFilterChanged,
    onCloseFilter: _onCloseFilter,
    onSortChanged: _onSortChanged,
    onRetry: _onRetry,
    onPointerSelect: _pointerSelect,
    onTapped: _tapSelect,
    onColumnTapped: _columnTapped,
    onSelectionChanged: _onMarqueeSelectionChanged,
    onToggleSelection: _toggleSelection,
    onViewportChanged: _onViewportChanged,
    onOpen: _openEntry,
    onOpenWithBounds: _onOpenWithBounds,
    onContextMenu: Platform.isWindows ? _showContextMenu : null,
    onNavigateColumn: _openColumn,
    onDrop: _receiveExternalDrop,
    onClosePreview: _onClosePreview,
    onTogglePreviewExpanded: _onTogglePreviewExpanded,
  );

  @override
  Widget build(BuildContext context) {
    final splitChild = widget.splitChild;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppearanceScope.of(context).layout('explorer');
        final sidebar = _sidebarVisible && layout.west ? layout.westSize : 0.0;
        final bar = widget.splitBarBuilder;
        final pane =
            (constraints.maxWidth -
                sidebar -
                (bar == null ? 1 : FileActionBar.width)) /
            2;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ExplorerScope(
                navigation: ExplorerNavigation(
                  path: _currentPath,
                  canGoBack:
                      _history.isNotEmpty && !_isLoading && !_contextMenuOpen,
                  canGoForward:
                      _forwardHistory.isNotEmpty &&
                      !_isLoading &&
                      !_contextMenuOpen,
                  canGoUp: Directory(_currentPath).parent.path != _currentPath,
                  split: widget.split,
                  onToggleSplit: widget.onToggleSplit,
                  onBack: _goBack,
                  onForward: _goForward,
                  onUp: _goUp,
                  onRefresh: _refresh,
                  onSearchChanged: _onSearchChanged,
                  onCreateFolder: _createFolder,
                  onNavigate: _loadDirectory,
                ),
                child: ExplorerPaneScope(
                  data: (
                    sidebar: (
                      locations: _locations,
                      currentPath: widget.sidebarPath ?? _currentPath,
                    ),
                    path: _currentPath,
                    title: _currentFolderName,
                    split: widget.split,
                    active: widget.active,
                    editable: _sidebarVisible,
                    gridView: _gridView,
                    columnView: _columnView,
                    heatmapView: _heatmapView,
                    filterOpen: _filterOpen,
                    filter: _filter,
                    sort: _sort,
                    ascending: _ascending,
                    selectionMode: _selectionMode,
                    entries: _visibleEntries,
                    total: _entries.length,
                    selection: _selection,
                    selectedPath: _selectedPath,
                    checkboxSelection:
                        _effectiveSelectionMode == SelectionMode.checkbox,
                    revealToken: _revealToken,
                    loading: _isLoading,
                    pending: _pendingEntries,
                    hasLoaded: _hasLoadedDirectory,
                    error: _loadError,
                    hasQuery: _query.isNotEmpty || _filter.isActive,
                    dropEnabled:
                        Platform.isWindows && _ready && !_contextMenuOpen,
                    previewVisible: _previewVisible,
                    previewExpanded: _previewExpanded,
                    folderRevision: _folderRevision,
                    reverseTransition: _reverseTransition,
                    refreshToken: _loadRequest,
                    contentKey: _contentKey,
                    titleIconKey: _titleIconKey,
                    imagePreviewKey: _imagePreviewKey,
                    textPreviewKey: _textPreviewKey,
                    videoPreviewKey: _videoPreviewKey,
                  ),
                  actions: _paneActions,
                  child: Builder(builder: _buildPane),
                ),
              ),
            ),
            if (splitChild != null) ...[
              if (bar != null)
                bar(context)
              else
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              SizedBox(width: pane < 0 ? 0 : pane, child: splitChild),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPane(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        focusNode: _explorerFocusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _handleKeyEvent,
        child: MouseBackNavigation(
          enabled: _history.isNotEmpty && !_isLoading && !_contextMenuOpen,
          onBack: _goBack,
          forwardEnabled:
              _forwardHistory.isNotEmpty && !_isLoading && !_contextMenuOpen,
          onForward: _goForward,
          child: SafeArea(
            child: Stack(
              key: _overlayKey,
              fit: StackFit.expand,
              children: [
                _buildLayout(context),
                if (_heroSource != null &&
                    !MediaQuery.disableAnimationsOf(context))
                  FolderHeroFlight(
                    key: ValueKey(_heroRevision),
                    source: _heroSource!,
                    destination: _heroDestination!,
                    duration: _heroDuration,
                    expand: _heroExpand,
                    color: _heroExpand
                        ? Theme.of(context).colorScheme.primaryContainer
                        : AppearanceScope.of(context).accent,
                    onComplete: () {
                      if (mounted) setState(() => _heroSource = null);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _sidebarVisible => widget.showSidebar && !_previewExpanded;

  /// Disposition racine : panneau gauche à l'ouest, explorateur au centre.
  Widget _buildLayout(BuildContext context) {
    final appearance = AppearanceScope.controllerOf(context);
    final config = AppearanceScope.of(context).layout('explorer');
    final sidebarVisible = _sidebarVisible;
    final registry = SuperApp.maybeOf(context)?.registry ?? _standaloneRegistry;
    return registeredExplorerLayout(
      registry: registry,
      layout: SuperLayout(
        key: const ValueKey('explorer-layout'),
        label: 'Disposition de la page',
        name: 'Page',
        // Seul le volet qui affiche le panneau édite la disposition partagée.
        editable: sidebarVisible,
        config: sidebarVisible
            ? config
            : config.copyWith(
                // Masque l'emplacement où le panneau gauche est affiché.
                west:
                    config.contentZone(SuperLayoutZone.west) ==
                        SuperLayoutZone.west
                    ? false
                    : null,
                east:
                    config.contentZone(SuperLayoutZone.west) ==
                        SuperLayoutZone.east
                    ? false
                    : null,
              ),
        onChanged: appearance == null
            ? null
            : (value) => appearance.value = appearance.value.withLayout(
                'explorer',
                value,
              ),
        slots: [
          BuilderSlot(
            id: 'sidebar',
            label: 'Panneau gauche',
            builder: registry.component('explorer_sidebar').builder,
          ),
          BuilderSlot(
            id: 'main',
            label: 'Explorateur',
            // Les étiquettes de ses barres commencent au coin haut-gauche.
            labelAlignment: Alignment.topRight,
            builder: registry.component('explorer_main').builder,
          ),
        ],
      ),
    );
  }

  String get _currentFolderName {
    final name = _fileName(_currentPath);
    return name.isEmpty ? _currentPath : name;
  }
}
