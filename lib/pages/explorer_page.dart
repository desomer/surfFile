import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../models/explorer_entry.dart';
import '../models/explorer_location.dart';
import '../services/directory_scanner.dart';
import '../services/personal_folders.dart';
import '../services/windows_context_menu.dart';
import '../theme/explorer_colors.dart';
import '../widgets/explorer_breadcrumbs.dart';
import '../widgets/explorer_context_menu.dart';
import '../widgets/explorer_empty_state.dart';
import '../widgets/explorer_entries_view.dart';
import '../widgets/explorer_error_state.dart';
import '../widgets/explorer_sidebar.dart';
import '../widgets/explorer_skeleton.dart';
import '../widgets/explorer_sort_header.dart';
import '../widgets/explorer_toolbar.dart';
import '../widgets/explorer_view_toggle.dart';
import '../widgets/image_preview_panel.dart';
import '../widgets/text_preview_panel.dart';
import '../widgets/video_preview_panel.dart';
import '../widgets/mouse_back_navigation.dart';
import '../widgets/folder_transition_view.dart';
import '../widgets/folder_hero_flight.dart';
import '../theme/appearance.dart';
import '../theme/appearance_slot.dart';
import '../theme/folder_transition.dart';
import '../widgets/super_container.dart';
import '../widgets/file_action_bar.dart';
import '../widgets/transfer_panel.dart';
import '../actions/file_actions.dart';

enum _HistoryDirection { back, forward }

class ExplorerPage extends StatefulWidget {
  const ExplorerPage({super.key});

  @override
  State<ExplorerPage> createState() => _ExplorerPageState();
}

/// Héberge un ou deux [ExplorerPane] côte à côte (mode divisé).
class _ExplorerPageState extends State<ExplorerPage> {
  final _panes = [
    GlobalKey<_ExplorerPaneState>(),
    GlobalKey<_ExplorerPaneState>(),
  ];
  final _paths = <String?>[null, null];
  bool _split = false;
  int _active = 0;

  void _toggleSplit() => setState(() {
    _split = !_split;
    _active = _split ? 1 : 0;
    _paths[1] = null;
  });

  void _activate(int pane) {
    if (_active != pane) setState(() => _active = pane);
  }

  void _pathChanged(int pane, String path) {
    if (_paths[pane] != path) {
      setState(() => _paths[pane] = path);
    } else if (pane == 1) {
      _panes[0].currentState?._touch();
    }
  }

  /// Contexte des actions de la barre centrale ; `null` si un volet manque.
  FileActionContext? _actionContext() {
    final left = _panes[0].currentState;
    final right = _panes[1].currentState;
    if (left == null || right == null || !left._ready || !right._ready) {
      return null;
    }
    return FileActionContext(
      left: left._snapshot,
      right: right._snapshot,
      navigate: (leftPath, rightPath) => Future.wait([
        left._loadDirectory(leftPath),
        right._loadDirectory(rightPath),
      ]),
      refresh: () => Future.wait([left._refresh(), right._refresh()]),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SuperContainer(
      slot: AppearanceSlot.background,
      decorate: false,
      applyPadding: true,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: _panesView()),
            const Positioned(top: 56, right: 16, child: TransferPanel()),
          ],
        ),
      ),
    );
  }

  Widget _panesView() {
    return ExplorerPane(
      key: _panes[0],
      split: _split,
      active: _split && _active == 0,
      onActivate: () => _activate(0),
      onPathChanged: (path) => _pathChanged(0, path),
      onToggleSplit: _toggleSplit,
      sidebarPath: _split ? _paths[_active] : null,
      onSidebarLocation: _split
          ? (path) => _panes[_active].currentState?._loadDirectory(path)
          : null,
      splitBarBuilder: (_) => FileActionBar(
        actionContext: _actionContext(),
        onMessage: _showMessage,
      ),
      splitChild: _split
          ? ExplorerPane(
              key: _panes[1],
              initialPath: _paths[0],
              showSidebar: false,
              autofocus: false,
              split: true,
              active: _active == 1,
              onActivate: () => _activate(1),
              onPathChanged: (path) => _pathChanged(1, path),
              onSelectionChanged: () => _panes[0].currentState?._touch(),
              onToggleSplit: _toggleSplit,
            )
          : null,
    );
  }
}

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
  State<ExplorerPane> createState() => _ExplorerPaneState();
}

class _ExplorerPaneState extends State<ExplorerPane> {
  late String _currentPath;
  final List<String> _history = [];
  final List<String> _forwardHistory = [];
  _HistoryDirection? _failedDirection;
  List<ExplorerEntry> _entries = [];
  ((List<ExplorerEntry>, String, ExplorerSort, bool), List<ExplorerEntry>)?
  _visibleCache;
  String _query = '';
  String? _selectedPath;
  String? _loadError;
  String? _failedPath;
  bool _initializationFailed = false;
  List<ExplorerLocation> _locations = [];
  bool _isLoading = true;
  bool _gridView = false;
  bool _previewVisible = false;
  bool _previewExpanded = false;
  bool _ascending = true;
  bool _contextMenuOpen = false;
  ExplorerSort _sort = ExplorerSort.name;
  bool _hasLoadedDirectory = false;
  bool _pendingEntries = false;
  int _folderRevision = 0;
  bool _reverseTransition = false;
  int _loadRequest = 0;
  final _contentKey = GlobalKey();
  final _titleIconKey = GlobalKey();
  final _overlayKey = GlobalKey();
  Rect? _heroSource;
  Rect? _heroDestination;
  bool _heroExpand = false;
  int _heroRevision = 0;
  Duration _heroDuration = Duration.zero;
  final _explorerFocusNode = FocusNode(debugLabel: 'File explorer');
  final _imagePreviewKey = GlobalKey();
  final _textPreviewKey = GlobalKey();
  final _videoPreviewKey = GlobalKey();

  bool get _ready => _hasLoadedDirectory && !_isLoading;

  PaneSnapshot get _snapshot =>
      PaneSnapshot(path: _currentPath, selection: [?_selectedPath]);

  Future<void> _refresh() => _loadDirectory(_currentPath, addToHistory: false);

  /// Reconstruit ce volet (et la barre d'actions) quand l'autre change.
  void _touch() {
    if (mounted) setState(() {});
  }

  String get _homePath =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath ?? _homePath;
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _initializationFailed = false;
    });
    try {
      final folders = await PersonalFolders.resolve(_homePath);
      if (!mounted) return;
      setState(() {
        _locations = [
          ExplorerLocation('Accueil', _homePath, Icons.home_outlined),
          ExplorerLocation(
            'Bureau',
            folders['Desktop']!,
            Icons.desktop_windows_outlined,
          ),
          ExplorerLocation(
            'Documents',
            folders['Documents']!,
            Icons.description_outlined,
          ),
          ExplorerLocation(
            'Téléchargements',
            folders['Downloads']!,
            Icons.download_outlined,
          ),
          ExplorerLocation(
            'Images',
            folders['Pictures']!,
            Icons.image_outlined,
          ),
          ExplorerLocation(
            'Musique',
            folders['Music']!,
            Icons.headphones_outlined,
          ),
          ExplorerLocation('Vidéos', folders['Videos']!, Icons.movie_outlined),
        ];
      });
      await _loadDirectory(_currentPath, addToHistory: false);
    } on PlatformException catch (error) {
      _handleInitializationError(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      _handleInitializationError(error.message ?? error.toString());
    }
  }

  void _handleInitializationError(String message) {
    debugPrint('Error resolving personal folders: $message');
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _initializationFailed = true;
      _loadError = 'Impossible de trouver les dossiers personnels : $message';
    });
  }

  /// Filtré et trié une seule fois par combinaison liste/recherche/tri, au
  /// lieu de l'être à chaque reconstruction (survol, animation…).
  List<ExplorerEntry> get _visibleEntries {
    final key = (_entries, _query.trim().toLowerCase(), _sort, _ascending);
    final cached = _visibleCache;
    if (cached != null &&
        identical(cached.$1.$1, key.$1) &&
        cached.$1.$2 == key.$2 &&
        cached.$1.$3 == key.$3 &&
        cached.$1.$4 == key.$4) {
      return cached.$2;
    }
    final query = key.$2;
    final lower = {
      for (final entry in _entries) entry: entry.name.toLowerCase(),
    };
    final entries = _entries
        .where((entry) => query.isEmpty || lower[entry]!.contains(query))
        .toList();
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      final comparison = switch (_sort) {
        ExplorerSort.name => lower[a]!.compareTo(lower[b]!),
        ExplorerSort.modified => a.modified.compareTo(b.modified),
        ExplorerSort.size => a.size.compareTo(b.size),
      };
      return _ascending ? comparison : -comparison;
    });
    final visible = List<ExplorerEntry>.unmodifiable(entries);
    _visibleCache = (key, visible);
    return visible;
  }

  Future<void> _loadDirectory(
    String path, {
    bool addToHistory = true,
    _HistoryDirection? direction,
    Rect? heroCard,
    Rect? heroIcon,
  }) async {
    final request = ++_loadRequest;
    final navigating = _hasLoadedDirectory && path != _currentPath;
    final scan = DirectoryScanner.scan(path);
    void reset() {
      _previewVisible = false;
      _previewExpanded = false;
      _loadError = null;
      _failedPath = null;
      _failedDirection = null;
    }

    if (!navigating) {
      setState(() {
        reset();
        _isLoading = true;
      });
    }

    _LoadRollback? rollback;
    try {
      if (navigating) {
        // Un petit dossier est lu en quelques millisecondes : il glisse
        // directement avec son contenu. Sinon le glissement part sur un
        // squelette, remplacé dès que la liste est prête.
        final quick = await Future.any<List<ExplorerEntry>?>([
          scan,
          Future<List<ExplorerEntry>?>.delayed(_quickScan),
        ]);
        if (!mounted || request != _loadRequest) return;
        rollback = (
          path: _currentPath,
          entries: _entries,
          history: List.of(_history),
          forward: List.of(_forwardHistory),
          selected: _selectedPath,
        );
        setState(() {
          reset();
          _startTransition(path, direction, heroCard, heroIcon);
          _commitHistory(path, direction, addToHistory);
          _currentPath = path;
          _entries = quick ?? const [];
          _selectedPath = null;
          _pendingEntries = quick == null;
          _isLoading = quick == null;
        });
        widget.onPathChanged?.call(path);
        if (quick != null) return;
      }

      final entries = await scan;
      if (!mounted || request != _loadRequest) return;
      setState(() {
        if (!navigating) {
          _commitHistory(path, direction, addToHistory);
          _selectedPath = null;
        }
        _currentPath = path;
        _entries = entries;
        _pendingEntries = false;
        _isLoading = false;
        _hasLoadedDirectory = true;
      });
      if (!navigating) widget.onPathChanged?.call(path);
    } on FileSystemException catch (error) {
      _loadFailed(request, path, direction, error, rollback);
    }
  }

  /// Délai de lecture sous lequel un dossier s'affiche sans squelette.
  static const _quickScan = Duration(milliseconds: 60);

  void _loadFailed(
    int request,
    String path,
    _HistoryDirection? direction,
    FileSystemException error,
    _LoadRollback? rollback,
  ) {
    debugPrint('Error loading directory: $error');
    if (!mounted || request != _loadRequest) return;
    setState(() {
      if (rollback != null) {
        _currentPath = rollback.path;
        _entries = rollback.entries;
        _history
          ..clear()
          ..addAll(rollback.history);
        _forwardHistory
          ..clear()
          ..addAll(rollback.forward);
        _selectedPath = rollback.selected;
      }
      _pendingEntries = false;
      _isLoading = false;
      _failedPath = path;
      _failedDirection = direction;
      _loadError = 'Impossible d’ouvrir le dossier "$path" : ${error.message}';
    });
    if (rollback != null) widget.onPathChanged?.call(rollback.path);
  }

  /// Lance la transition vers [path].
  void _startTransition(
    String path,
    _HistoryDirection? direction,
    Rect? heroCard,
    Rect? heroIcon,
  ) {
    _heroSource = null;
    _folderRevision++;
    _reverseTransition =
        direction == _HistoryDirection.back ||
        (direction == null && path == Directory(_currentPath).parent.path);
    final appearance = AppearanceScope.of(context);
    final type = appearance.folderTransition;
    final duration = Duration(
      milliseconds: appearance.folderTransitionDuration.round(),
    );
    if (heroCard != null &&
        heroIcon != null &&
        !MediaQuery.disableAnimationsOf(context) &&
        (type == FolderTransition.heroExpand ||
            type == FolderTransition.heroIcon)) {
      _heroExpand = type == FolderTransition.heroExpand;
      final target =
          (_heroExpand ? _contentKey : _titleIconKey).currentContext!
                  .findRenderObject()!
              as RenderBox;
      final overlay =
          _overlayKey.currentContext!.findRenderObject()! as RenderBox;
      final origin = overlay.localToGlobal(Offset.zero);
      _heroSource = (_heroExpand ? heroCard : heroIcon).shift(-origin);
      _heroDestination = (target.localToGlobal(Offset.zero) & target.size)
          .shift(-origin);
      _heroDuration = duration;
      _heroRevision++;
    }
  }

  void _commitHistory(
    String path,
    _HistoryDirection? direction,
    bool addToHistory,
  ) {
    if (direction == _HistoryDirection.back) {
      _history.removeLast();
      _forwardHistory.add(_currentPath);
    } else if (direction == _HistoryDirection.forward) {
      _forwardHistory.removeLast();
      _history.add(_currentPath);
    } else if (addToHistory && path != _currentPath) {
      _history.add(_currentPath);
      _forwardHistory.clear();
    }
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _joinPath(String parent, String child) =>
      '$parent${parent.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$child';

  Future<void> _goUp() async {
    final parent = Directory(_currentPath).parent.path;
    if (parent != _currentPath) await _loadDirectory(parent);
  }

  Future<void> _goBack() async {
    if (_history.isEmpty || _isLoading || _contextMenuOpen) return;
    await _loadDirectory(_history.last, direction: _HistoryDirection.back);
  }

  Future<void> _goForward() async {
    if (_forwardHistory.isEmpty || _isLoading || _contextMenuOpen) return;
    await _loadDirectory(
      _forwardHistory.last,
      direction: _HistoryDirection.forward,
    );
  }

  Future<void> _openEntry(ExplorerEntry entry) async {
    if (entry.isDirectory) {
      await _loadDirectory(entry.entity.path);
      return;
    }
    try {
      final path = entry.entity.path;
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
      } else {
        throw UnsupportedError('Cette plateforme n’est pas prise en charge.');
      }
    } on ProcessException catch (error) {
      _showMessage('Impossible d’ouvrir le fichier : ${error.message}');
    } on UnsupportedError catch (error) {
      _showMessage('Impossible d’ouvrir le fichier : $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (!_explorerFocusNode.hasPrimaryFocus ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    final selected = _visibleEntries.where(
      (entry) => entry.entity.path == _selectedPath,
    );
    if (selected.isEmpty ||
        (!VideoPreviewPanel.supports(selected.first.name) &&
            !ImagePreviewPanel.supports(selected.first.name) &&
            !TextPreviewPanel.supports(selected.first.name))) {
      return KeyEventResult.ignored;
    }
    setState(() {
      if (_previewExpanded) {
        _previewVisible = false;
        _previewExpanded = false;
      } else if (_previewVisible) {
        _previewExpanded = true;
      } else {
        _previewVisible = true;
        _previewExpanded = false;
      }
    });
    return KeyEventResult.handled;
  }

  Future<void> _showContextMenu(ExplorerEntry entry, Offset position) async {
    if (_contextMenuOpen) return;
    _contextMenuOpen = true;
    setState(() => _selectedPath = entry.entity.path);
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

  Future<void> _renameEntry(
    ExplorerEntry entry,
    WindowsContextMenu menu,
    int commandId,
  ) async {
    // The Shell rename verb requires an Explorer view; SurfFile owns the dialog.
    final controller = TextEditingController(text: entry.name);
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
    if (name == null || !mounted) return;
    final newName = name.trim();
    if (newName.isEmpty ||
        newName == '.' ||
        newName == '..' ||
        RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(newName) ||
        newName.endsWith('.')) {
      _showMessage('Ce nom de fichier ou de dossier n’est pas valide.');
      return;
    }
    if (newName == entry.name) return;
    await menu.rename(commandId, newName);
  }

  Future<void> _createFolder() async {
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
    if (name == null || name.trim().isEmpty) return;
    final folderName = name.trim();
    if (folderName == '.' ||
        folderName == '..' ||
        folderName.contains('/') ||
        folderName.contains('\\')) {
      _showMessage('Le nom du dossier ne peut pas contenir de chemin.');
      return;
    }

    try {
      await Directory(_joinPath(_currentPath, folderName)).create();
      await _loadDirectory(_currentPath, addToHistory: false);
      _showMessage('Dossier créé.');
    } on FileSystemException catch (error) {
      _showMessage('Impossible de créer le dossier : ${error.message}');
    }
  }

  @override
  void dispose() {
    _explorerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final splitChild = widget.splitChild;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sidebar = widget.showSidebar && !_previewExpanded
            ? ExplorerSidebar.width
            : 0.0;
        final bar = widget.splitBarBuilder;
        final pane =
            (constraints.maxWidth -
                sidebar -
                (bar == null ? 1 : FileActionBar.width)) /
            2;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildPane(context)),
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
                Row(
                  children: [
                    if (widget.showSidebar && !_previewExpanded)
                      ExplorerSidebar(
                        locations: _locations,
                        currentPath: widget.sidebarPath ?? _currentPath,
                        onLocationSelected:
                            widget.onSidebarLocation ?? _loadDirectory,
                      ),
                    Expanded(
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (_) {
                          widget.onActivate?.call();
                          if (widget.split && !_explorerFocusNode.hasFocus) {
                            _explorerFocusNode.requestFocus();
                          }
                        },
                        child: _buildExplorer(),
                      ),
                    ),
                  ],
                ),
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

  Widget _buildExplorer() {
    final entries = _visibleEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_previewExpanded) ...[
          if (widget.split)
            AnimatedContainer(
              key: ValueKey('split-active-${widget.active}'),
              duration: const Duration(milliseconds: 150),
              height: 3,
              color: widget.active
                  ? AppearanceScope.of(context).accent
                  : Colors.transparent,
            ),
          ExplorerToolbar(
            split: widget.split,
            onToggleSplit: widget.onToggleSplit,
            canGoBack: _history.isNotEmpty && !_isLoading && !_contextMenuOpen,
            canGoUp: Directory(_currentPath).parent.path != _currentPath,
            onBack: _goBack,
            canGoForward:
                _forwardHistory.isNotEmpty && !_isLoading && !_contextMenuOpen,
            onForward: _goForward,
            onUp: _goUp,
            onRefresh: () => _loadDirectory(_currentPath, addToHistory: false),
            onSearchChanged: (value) => setState(() => _query = value),
            onCreateFolder: _createFolder,
          ),
          ExplorerBreadcrumbs(path: _currentPath, onNavigate: _loadDirectory),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 23, 30, 14),
            child: Row(
              children: [
                if (AppearanceScope.of(context).folderTransition ==
                    FolderTransition.heroIcon) ...[
                  Icon(
                    Icons.folder_rounded,
                    key: _titleIconKey,
                    size: 28,
                    color: AppearanceScope.of(context).accent,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    _currentFolderName,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  _pendingEntries
                      ? '…'
                      : '${entries.length} élément${entries.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: explorerColor(
                      context,
                      const Color(0xFF82899A),
                      Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 14),
                ExplorerViewToggle(
                  gridView: _gridView,
                  onChanged: (gridView) => setState(() => _gridView = gridView),
                ),
              ],
            ),
          ),
          ExplorerSortHeader(
            sort: _sort,
            ascending: _ascending,
            onSortChanged: (sort) => setState(() {
              if (_sort == sort) {
                _ascending = !_ascending;
              } else {
                _sort = sort;
                _ascending = true;
              }
            }),
          ),
        ],
        Expanded(
          key: _contentKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FolderTransitionView(
                revision: _folderRevision,
                reverse: _reverseTransition,
                child: IgnorePointer(
                  ignoring: _isLoading,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, if (current != null) current],
                    ),
                    child: _pendingEntries && _loadError == null
                        ? ExplorerSkeleton(
                            key: const ValueKey('explorer-skeleton'),
                            gridView: _gridView,
                          )
                        : KeyedSubtree(
                            key: const ValueKey('explorer-content'),
                            child: _isLoading && !_hasLoadedDirectory
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _loadError != null
                                ? ExplorerErrorState(
                                    message: _loadError!,
                                    onRetry: () {
                                      if (_initializationFailed) {
                                        _initialize();
                                      } else {
                                        _loadDirectory(
                                          _failedPath ?? _currentPath,
                                          direction: _failedDirection,
                                        );
                                      }
                                    },
                                  )
                                : entries.isEmpty
                                ? ExplorerEmptyState(
                                    hasQuery: _query.isNotEmpty,
                                  )
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      final fileList = ExplorerEntriesView(
                                        key: ValueKey(_currentPath),
                                        entries: entries,
                                        gridView: _gridView,
                                        selectedPath: _selectedPath,
                                        onSelected: (path) {
                                          _explorerFocusNode.requestFocus();
                                          setState(() => _selectedPath = path);
                                          widget.onSelectionChanged?.call();
                                        },
                                        onOpen: _openEntry,
                                        onOpenWithBounds: (entry, card, icon) =>
                                            _loadDirectory(
                                              entry.entity.path,
                                              heroCard: card,
                                              heroIcon: icon,
                                            ),
                                        onContextMenu: Platform.isWindows
                                            ? _showContextMenu
                                            : null,
                                      );
                                      if (!_previewVisible) return fileList;

                                      final matching = entries.where(
                                        (entry) =>
                                            entry.entity.path == _selectedPath,
                                      );
                                      final selected = matching.isEmpty
                                          ? null
                                          : matching.first;
                                      void closePreview() => setState(() {
                                        _previewVisible = false;
                                        _previewExpanded = false;
                                      });
                                      void toggleExpanded() => setState(
                                        () => _previewExpanded =
                                            !_previewExpanded,
                                      );
                                      final preview =
                                          selected != null &&
                                              VideoPreviewPanel.supports(
                                                selected.name,
                                              )
                                          ? VideoPreviewPanel(
                                              key: _videoPreviewKey,
                                              path: selected.entity.path,
                                              onClose: closePreview,
                                              isExpanded: _previewExpanded,
                                              onToggleExpanded: toggleExpanded,
                                            )
                                          : selected != null &&
                                                ImagePreviewPanel.supports(
                                                  selected.name,
                                                )
                                          ? ImagePreviewPanel(
                                              key: _imagePreviewKey,
                                              path: selected.entity.path,
                                              onClose: closePreview,
                                              isExpanded: _previewExpanded,
                                              onToggleExpanded: toggleExpanded,
                                            )
                                          : TextPreviewPanel(
                                              key: _textPreviewKey,
                                              path:
                                                  selected != null &&
                                                      TextPreviewPanel.supports(
                                                        selected.name,
                                                      )
                                                  ? selected.entity.path
                                                  : null,
                                              onClose: closePreview,
                                              isExpanded: _previewExpanded,
                                              onToggleExpanded: toggleExpanded,
                                            );
                                      if (_previewExpanded) return preview;
                                      if (constraints.maxWidth >= 760) {
                                        return Row(
                                          children: [
                                            Expanded(child: fileList),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 340,
                                              child: preview,
                                            ),
                                          ],
                                        );
                                      }
                                      return Column(
                                        children: [
                                          Expanded(flex: 3, child: fileList),
                                          const SizedBox(height: 12),
                                          SizedBox(height: 240, child: preview),
                                        ],
                                      );
                                    },
                                  ),
                          ),
                  ),
                ),
              ),
              if (_isLoading && _hasLoadedDirectory && !_pendingEntries)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ],
    );
  }

  String get _currentFolderName {
    final name = _fileName(_currentPath);
    return name.isEmpty ? _currentPath : name;
  }
}
