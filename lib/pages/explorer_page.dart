import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../models/explorer_filter.dart';
import '../models/explorer_entry.dart';
import '../models/explorer_location.dart';
import '../models/selection_mode.dart';
import '../services/favorites.dart';
import '../services/folder_size_service.dart';
import '../services/directory_scanner.dart';
import '../services/file_operations.dart';
import '../services/personal_folders.dart';
import '../services/windows_context_menu.dart';
import '../widgets/explorer_breadcrumbs.dart';
import '../widgets/explorer_context_menu.dart';
import '../widgets/explorer_empty_state.dart';
import '../widgets/entries_layout.dart';
import '../widgets/explorer_entries_view.dart';
import '../widgets/explorer_columns_view.dart';
import '../widgets/explorer_error_state.dart';
import '../widgets/explorer_sidebar.dart';
import '../widgets/explorer_skeleton.dart';
import '../widgets/explorer_filter_bar.dart';
import '../widgets/explorer_sort_header.dart';
import '../widgets/explorer_toolbar.dart';
import '../widgets/explorer_action_bar.dart';
import '../widgets/explorer_view_mode_bar.dart';
import '../widgets/image_preview_panel.dart';
import '../widgets/text_preview_panel.dart';
import '../widgets/video_preview_panel.dart';
import '../widgets/mouse_back_navigation.dart';
import '../widgets/folder_transition_view.dart';
import '../widgets/folder_hero_flight.dart';
import '../theme/appearance.dart';
import '../theme/appearance_slot.dart';
import '../theme/folder_transition.dart';
import '../models/super_layout_config.dart';
import '../widgets/super_container.dart';
import '../widgets/super_layout.dart';
import '../widgets/file_action_bar.dart';
import '../widgets/shortcuts_help_dialog.dart';
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
  (
    (List<ExplorerEntry>, String, ExplorerSort, bool, ExplorerFilter),
    List<ExplorerEntry>,
  )?
  _visibleCache;
  String _query = '';
  ExplorerFilter _filter = const ExplorerFilter();
  bool _filterOpen = false;
  String? _primary;
  Set<String> _selection = const {};

  /// Point de départ des sélections de plage (Maj).
  String? _anchor;

  /// Élément cliqué dans une sélection multiple : la sélection s'y réduit au
  /// relâchement, sauf si un glisser a commencé entre-temps.
  String? _collapseTo;

  /// Incrémenté pour faire défiler jusqu'à l'élément principal.
  int _revealToken = 0;
  Size _viewport = Size.zero;
  String _typed = '';
  DateTime _typedAt = DateTime(0);
  StreamSubscription<FileJob>? _jobsSubscription;
  final _ownJobs = <FileJob>{};

  /// Élément principal (clavier, aperçu, menu contextuel).
  String? get _selectedPath => _primary;
  set _selectedPath(String? path) {
    _primary = path;
    _anchor = path;
    _selection = {?path};
  }

  void _setSelection(Set<String> paths) {
    final visible = _visibleEntries;
    _selection = paths;
    _anchor = null;
    if (!paths.contains(_primary)) {
      _primary = null;
      for (final entry in visible) {
        if (paths.contains(entry.entity.path)) {
          _primary = entry.entity.path;
          break;
        }
      }
    }
    _anchor = _primary;
  }

  void _toggle(String path) {
    final next = {..._selection};
    if (!next.remove(path)) next.add(path);
    if (next.contains(path)) {
      _selection = next;
      _primary = path;
    } else {
      _primary = null;
      _setSelection(next);
    }
    _anchor = path;
  }

  /// Sélectionne de [_anchor] à [path] ; [add] conserve la sélection actuelle.
  void _selectRange(String path, {required bool add}) {
    final visible = _visibleEntries;
    final to = visible.indexWhere((entry) => entry.entity.path == path);
    if (to < 0) return;
    final anchor = _anchor ?? _primary;
    var from = visible.indexWhere((entry) => entry.entity.path == anchor);
    if (from < 0) {
      from = to;
      _anchor = path;
    }
    final range = {
      for (var i = math.min(from, to); i <= math.max(from, to); i++)
        visible[i].entity.path,
    };
    _selection = add ? {..._selection, ...range} : range;
    _primary = path;
  }

  void _selectionChanged(VoidCallback change) {
    setState(change);
    widget.onSelectionChanged?.call();
  }

  /// Appui de la souris sur un élément (avant le relâchement).
  void _pointerSelect(String path) {
    _explorerFocusNode.requestFocus();
    if (_effectiveSelectionMode == SelectionMode.rowClick) return;
    final keys = HardwareKeyboard.instance;
    _selectionChanged(() {
      _collapseTo = null;
      if (keys.isShiftPressed) {
        _selectRange(path, add: keys.isControlPressed);
      } else if (keys.isControlPressed) {
        _toggle(path);
      } else if (_selection.contains(path)) {
        _primary = path;
        _anchor = path;
        _collapseTo = path;
      } else {
        _selectedPath = path;
      }
    });
  }

  /// Clic relâché sans glisser (ou toucher).
  void _tapSelect(String path) {
    final keys = HardwareKeyboard.instance;
    if (_effectiveSelectionMode == SelectionMode.rowClick) {
      _explorerFocusNode.requestFocus();
      _selectionChanged(() {
        _collapseTo = null;
        if (keys.isShiftPressed) {
          _selectRange(path, add: keys.isControlPressed);
        } else {
          _toggle(path);
        }
      });
      return;
    }
    final collapse = _collapseTo == path || !_selection.contains(path);
    _collapseTo = null;
    if (keys.isShiftPressed || keys.isControlPressed || !collapse) return;
    _explorerFocusNode.requestFocus();
    _selectionChanged(() => _selectedPath = path);
  }

  String? _loadError;
  String? _failedPath;
  bool _initializationFailed = false;
  List<ExplorerLocation> _locations = [];
  bool _isLoading = true;
  bool _gridView = false;
  bool _columnView = false;
  SelectionMode _selectionMode = SelectionMode.standard;

  /// Un clic de la vue en colonnes ouvre le dossier : pas de mode particulier.
  SelectionMode get _effectiveSelectionMode =>
      _columnView ? SelectionMode.standard : _selectionMode;

  /// Case à cocher : bascule l'élément sans toucher aux autres.
  void _toggleSelection(String path) {
    _explorerFocusNode.requestFocus();
    _selectionChanged(() {
      _collapseTo = null;
      _toggle(path);
    });
  }

  /// La vue en colonnes impose la liste réduite.
  bool get _showGrid => _gridView && !_columnView;
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

  PaneSnapshot get _snapshot => PaneSnapshot(
    path: _currentPath,
    selection: [
      for (final entry in _visibleEntries)
        if (_selection.contains(entry.entity.path)) entry.entity.path,
    ],
  );

  /// Actions de la barre des modes d'affichage, activées selon la sélection.
  List<ExplorerBarAction> _barActions({required bool canPaste}) {
    final idle = _ready && !_contextMenuOpen;
    final selected = _snapshot.selection;
    final hasSelection = idle && selected.isNotEmpty;
    final target = _selectedPath ?? selected.firstOrNull;
    final entry = target == null
        ? null
        : _visibleEntries.where((e) => e.entity.path == target).firstOrNull;
    return [
      ExplorerBarAction(
        id: 'new-folder',
        icon: Icons.create_new_folder_outlined,
        label: 'Nouveau dossier',
        shortcut: 'Ctrl+Maj+N',
        onPressed: idle ? _createFolder : null,
      ),
      ExplorerBarAction(
        id: 'cut',
        icon: Icons.content_cut_rounded,
        label: 'Couper',
        shortcut: 'Ctrl+X',
        separatorBefore: true,
        onPressed: hasSelection ? () => _toClipboard(FileTransfer.move) : null,
      ),
      ExplorerBarAction(
        id: 'copy',
        icon: Icons.content_copy_rounded,
        label: 'Copier',
        shortcut: 'Ctrl+C',
        onPressed: hasSelection ? () => _toClipboard(FileTransfer.copy) : null,
      ),
      ExplorerBarAction(
        id: 'paste',
        icon: Icons.content_paste_rounded,
        label: 'Coller',
        shortcut: 'Ctrl+V',
        onPressed: idle && canPaste ? _paste : null,
      ),
      ExplorerBarAction(
        id: 'rename',
        icon: Icons.drive_file_rename_outline_rounded,
        label: 'Renommer',
        shortcut: 'F2',
        separatorBefore: true,
        onPressed: hasSelection && entry != null
            ? () => _renameWithKeyboard(entry)
            : null,
      ),
      ExplorerBarAction(
        id: 'delete',
        icon: Icons.delete_outline_rounded,
        label: 'Supprimer',
        shortcut: 'Suppr',
        destructive: true,
        onPressed: hasSelection
            ? () => _deleteSelection(permanent: false)
            : null,
      ),
    ];
  }

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
    _jobsSubscription = FileJobs.ended.listen(_jobEnded);
    FolderSizeService.revision.addListener(_folderSizeChanged);
    _initialize();
  }

  static bool _samePath(String a, String b) =>
      Platform.isWindows ? a.toLowerCase() == b.toLowerCase() : a == b;

  /// Rafraîchit le volet quand un transfert touche le dossier affiché.
  void _jobEnded(FileJob job) {
    if (_ownJobs.remove(job) || !mounted || !_hasLoadedDirectory) return;
    final touched =
        _samePath(job.destination, _currentPath) ||
        job.sources.any(
          (source) => _samePath(FileOperations.parent(source), _currentPath),
        );
    if (touched) _reload();
  }

  /// Relit le dossier sans indicateur de chargement en gardant la sélection
  /// (ou en sélectionnant [select]).
  Future<void> _reload({Set<String>? select}) => _loadDirectory(
    _currentPath,
    addToHistory: false,
    keepSelection: true,
    select: select,
  );

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

  void _folderSizeChanged() {
    if (!mounted || _sort != ExplorerSort.size) return;
    setState(() => _visibleCache = null);
  }

  /// Filtré et trié une seule fois par combinaison liste/recherche/tri, au
  /// lieu de l'être à chaque reconstruction (survol, animation…).
  List<ExplorerEntry> get _visibleEntries {
    final key = (
      _entries,
      _query.trim().toLowerCase(),
      _sort,
      _ascending,
      _filter,
    );
    final cached = _visibleCache;
    if (cached != null &&
        identical(cached.$1.$1, key.$1) &&
        cached.$1.$2 == key.$2 &&
        cached.$1.$3 == key.$3 &&
        cached.$1.$4 == key.$4 &&
        cached.$1.$5 == key.$5) {
      return cached.$2;
    }
    final matches = _filter.matcher();
    final query = key.$2;
    final lower = {
      for (final entry in _entries) entry: entry.name.toLowerCase(),
    };
    final entries = _entries
        .where(
          (entry) =>
              (query.isEmpty || lower[entry]!.contains(query)) &&
              matches(entry),
        )
        .toList();
    sortExplorerEntries(entries, _sort, ascending: _ascending);
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
    bool keepSelection = false,
    Set<String>? select,
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

    if (!navigating && !keepSelection) {
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
          _selectedPath = select?.firstOrNull;
          if (select != null) _revealToken++;
          _pendingEntries = quick == null;
          _isLoading = quick == null;
        });
        widget.onPathChanged?.call(path);
        if (quick != null) return;
      }

      final entries = await scan;
      if (!mounted || request != _loadRequest) return;
      setState(() {
        if (!navigating) _commitHistory(path, direction, addToHistory);
        _currentPath = path;
        _entries = entries;
        if (!navigating) {
          if (keepSelection) {
            final existing = {for (final entry in entries) entry.entity.path};
            if (select != null) {
              _primary = null;
              _revealToken++;
            }
            _setSelection((select ?? _selection).intersection(existing));
          } else {
            _selectedPath = null;
          }
        }
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
        event is KeyUpEvent ||
        !_hasLoadedDirectory) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed;
    final shift = keys.isShiftPressed;
    final handled = keys.isAltPressed
        ? _handleAltKey(key)
        : _moveWithKey(key, shift: shift, add: ctrl) ||
              (event is KeyDownEvent &&
                  (ctrl
                      ? _handleCtrlKey(key, shift: shift)
                      : _handleKey(key, shift: shift))) ||
              (!ctrl && _typeAhead(event.character));
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  bool _handleAltKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft) {
      _goBack();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _goForward();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _goUp();
    } else {
      return false;
    }
    return true;
  }

  bool _handleCtrlKey(LogicalKeyboardKey key, {required bool shift}) {
    final visible = _visibleEntries;
    if (key == LogicalKeyboardKey.keyA) {
      _selectionChanged(
        () => shift
            ? _selectedPath = null
            : _setSelection({for (final entry in visible) entry.entity.path}),
      );
    } else if (key == LogicalKeyboardKey.keyI) {
      _selectionChanged(
        () => _setSelection({
          for (final entry in visible)
            if (!_selection.contains(entry.entity.path)) entry.entity.path,
        }),
      );
    } else if (key == LogicalKeyboardKey.keyC) {
      _toClipboard(FileTransfer.copy);
    } else if (key == LogicalKeyboardKey.keyX) {
      _toClipboard(FileTransfer.move);
    } else if (key == LogicalKeyboardKey.keyV) {
      _paste();
    } else if (key == LogicalKeyboardKey.keyN && shift) {
      _createFolder();
    } else if (key == LogicalKeyboardKey.keyR) {
      _reload();
    } else if (key == LogicalKeyboardKey.keyF && shift) {
      setState(() => _filterOpen = !_filterOpen);
    } else if (key == LogicalKeyboardKey.keyD) {
      Favorites.instance.toggle(_currentPath);
    } else {
      return false;
    }
    return true;
  }

  bool _handleKey(LogicalKeyboardKey key, {required bool shift}) {
    final primary = _visibleEntries
        .where((entry) => entry.entity.path == _selectedPath)
        .firstOrNull;
    if (key == LogicalKeyboardKey.space) return _togglePreview(primary);
    if (key == LogicalKeyboardKey.escape) {
      if (_selection.isEmpty) return false;
      _selectionChanged(() => _selectedPath = null);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (primary == null) return false;
      _openEntry(primary);
    } else if (key == LogicalKeyboardKey.backspace) {
      _goBack();
    } else if (key == LogicalKeyboardKey.f1) {
      ShortcutsHelpDialog.show(context);
    } else if (key == LogicalKeyboardKey.f2) {
      if (primary == null) return false;
      _renameWithKeyboard(primary);
    } else if (key == LogicalKeyboardKey.f5) {
      _reload();
    } else if (key == LogicalKeyboardKey.delete) {
      _deleteSelection(permanent: shift);
    } else {
      return false;
    }
    return true;
  }

  /// Flèches, Début/Fin et Page préc./suiv. ; Maj étend la sélection.
  bool _moveWithKey(
    LogicalKeyboardKey key, {
    required bool shift,
    required bool add,
  }) {
    if (_columnView && !shift && !add) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _columnLeft();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight) return _columnRight();
    }
    final visible = _visibleEntries;
    if (visible.isEmpty) return false;
    final layout = EntriesLayout(
      grid: _showGrid,
      compact: _columnView,
      appearance: AppearanceScope.of(context),
      viewport: _viewport,
      count: visible.length,
    );
    final columns = layout.columns;
    final page = layout.rowsPerPage * columns;
    final current = visible.indexWhere(
      (entry) => entry.entity.path == _selectedPath,
    );
    final int target;
    if (key == LogicalKeyboardKey.arrowDown) {
      target = current < 0 ? 0 : current + columns;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      target = current < 0 ? 0 : current - columns;
    } else if (_showGrid && key == LogicalKeyboardKey.arrowRight) {
      target = current + 1;
    } else if (_showGrid && key == LogicalKeyboardKey.arrowLeft) {
      target = current < 0 ? 0 : current - 1;
    } else if (key == LogicalKeyboardKey.home) {
      target = 0;
    } else if (key == LogicalKeyboardKey.end) {
      target = visible.length - 1;
    } else if (key == LogicalKeyboardKey.pageDown) {
      target = math.max(current, 0) + page;
    } else if (key == LogicalKeyboardKey.pageUp) {
      target = current - page;
    } else {
      return false;
    }
    // Comme l'Explorateur : une ligne incomplète de la grille ne bloque pas.
    final index = target.clamp(0, visible.length - 1);
    _moveTo(visible[index].entity.path, extend: shift, add: add);
    return true;
  }

  /// Vue en colonnes : revient au dossier parent en gardant le dossier quitté
  /// sélectionné.
  void _columnLeft() {
    final parent = Directory(_currentPath).parent.path;
    if (parent != _currentPath) _loadDirectory(parent, select: {_currentPath});
  }

  /// Vue en colonnes : entre dans le dossier sélectionné.
  bool _columnRight() {
    final primary = _visibleEntries
        .where((entry) => entry.entity.path == _selectedPath)
        .firstOrNull;
    if (primary == null || !primary.isDirectory) return false;
    _loadDirectory(primary.entity.path);
    return true;
  }

  /// Vue en colonnes : un clic sur un dossier l'ouvre dans la colonne suivante.
  void _columnTapped(String path) {
    _tapSelect(path);
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed || keys.isControlPressed) return;
    final entry = _entries.where((e) => e.entity.path == path).firstOrNull;
    if (entry != null && entry.isDirectory) _loadDirectory(path);
  }

  void _openColumn(String path, {String? select}) {
    _explorerFocusNode.requestFocus();
    _loadDirectory(path, select: select == null ? null : {select});
  }

  void _moveTo(String path, {bool extend = false, bool add = false}) {
    _selectionChanged(() {
      _collapseTo = null;
      if (extend) {
        _selectRange(path, add: add);
      } else {
        _selectedPath = path;
      }
      _revealToken++;
    });
  }

  /// Saisie rapide : va au prochain élément commençant par les lettres tapées.
  bool _typeAhead(String? character) {
    if (character == null ||
        character.length != 1 ||
        character.codeUnitAt(0) < 0x21 ||
        character.codeUnitAt(0) == 0x7F) {
      return false;
    }
    final visible = _visibleEntries;
    if (visible.isEmpty) return false;
    final now = DateTime.now();
    if (now.difference(_typedAt) > const Duration(seconds: 1)) _typed = '';
    _typedAt = now;
    _typed += character.toLowerCase();
    final repeated = _typed.split('').every((c) => c == _typed[0]);
    final current = visible.indexWhere(
      (entry) => entry.entity.path == _selectedPath,
    );
    ExplorerEntry? find(String prefix, int from) {
      for (var i = 0; i < visible.length; i++) {
        final entry = visible[(from + i) % visible.length];
        if (entry.name.toLowerCase().startsWith(prefix)) return entry;
      }
      return null;
    }

    final start = math.max(current, 0);
    final match =
        (_typed.length > 1 ? find(_typed, start) : null) ??
        (repeated ? find(_typed[0], current + 1) : null);
    if (match != null) _moveTo(match.entity.path);
    return true;
  }

  bool _togglePreview(ExplorerEntry? selected) {
    if (selected == null ||
        (!VideoPreviewPanel.supports(selected.name) &&
            !ImagePreviewPanel.supports(selected.name) &&
            !TextPreviewPanel.supports(selected.name))) {
      return false;
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
    return true;
  }

  void _toClipboard(FileTransfer kind) {
    final paths = _snapshot.selection;
    if (paths.isEmpty) return;
    FileClipboard.set(kind, paths);
    final count = paths.length;
    final plural = count == 1 ? '' : 's';
    _showMessage(
      kind == FileTransfer.copy
          ? '$count élément$plural copié$plural'
          : '$count élément$plural coupé$plural',
    );
  }

  Future<void> _paste() async {
    final content = FileClipboard.content.value;
    if (content == null) return;
    final destination = _currentPath;
    final move = content.kind == FileTransfer.move;
    final sources = [
      for (final path in content.paths)
        if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound &&
            !(move && _samePath(FileOperations.parent(path), destination)))
          path,
    ];
    if (sources.isEmpty) {
      if (content.paths.every(
        (path) =>
            FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound,
      )) {
        FileClipboard.clear();
        _showMessage('Les éléments du presse-papiers n’existent plus.');
      }
      return;
    }
    final separator = Platform.pathSeparator;
    if (sources.any(
      (source) =>
          _samePath(source, destination) ||
          (Platform.isWindows ? destination.toLowerCase() : destination)
              .startsWith(
                '${Platform.isWindows ? source.toLowerCase() : source}'
                '$separator',
              ),
    )) {
      _showMessage('Impossible de coller un dossier dans lui-même.');
      return;
    }
    if (move) FileClipboard.clear();
    final job = FileOperations.start(content.kind, sources, destination);
    _ownJobs.add(job);
    Set<String>? created;
    try {
      created = (await job.result).toSet();
    } on FileOperationCancelled {
      // Le panneau de transferts affiche déjà l'annulation.
    } on Object catch (error) {
      if (mounted) _showMessage('Collage impossible : $error');
    }
    if (mounted && _samePath(_currentPath, destination)) {
      await _reload(select: created);
    }
  }

  Future<void> _deleteSelection({required bool permanent}) async {
    final paths = _snapshot.selection;
    if (paths.isEmpty || _contextMenuOpen) return;
    if (permanent || !Platform.isWindows) {
      final count = paths.length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Supprimer définitivement ?'),
          content: Text(
            count == 1
                ? '« ${FileOperations.name(paths.first)} » sera supprimé '
                      'sans passer par la corbeille.'
                : '$count éléments seront supprimés sans passer par la '
                      'corbeille.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    // Après suppression, l'élément suivant devient la sélection.
    final visible = _visibleEntries;
    final last = visible.lastIndexWhere(
      (entry) => _selection.contains(entry.entity.path),
    );
    final next = visible
        .skip(last + 1)
        .followedBy(visible.take(last).toList().reversed)
        .where((entry) => !_selection.contains(entry.entity.path))
        .firstOrNull;

    _contextMenuOpen = true;
    try {
      for (final path in paths) {
        if (permanent || !Platform.isWindows) {
          await FileSystemEntity.isDirectory(path)
              ? await Directory(path).delete(recursive: true)
              : await File(path).delete();
        } else {
          await _recycle(path);
        }
      }
    } on FileSystemException catch (error) {
      if (mounted) _showMessage('Suppression impossible : ${error.message}');
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage('Suppression impossible : ${error.message ?? error.code}');
      }
    } finally {
      _contextMenuOpen = false;
    }
    if (mounted) await _reload(select: {?next?.entity.path});
  }

  /// Envoie [path] à la corbeille via la commande « Supprimer » du Shell.
  Future<void> _recycle(String path) async {
    final menu = await WindowsContextMenu.open(path);
    try {
      final delete = menu.items
          .where((item) => item.verb.toLowerCase() == 'delete')
          .firstOrNull;
      if (delete == null) {
        throw PlatformException(
          code: 'no_delete',
          message: 'Windows ne propose pas la suppression de cet élément.',
        );
      }
      await menu.invoke(delete.id);
    } finally {
      await menu.close();
    }
  }

  Future<void> _renameWithKeyboard(ExplorerEntry entry) async {
    final newName = await _askNewName(entry);
    if (newName == null || !mounted) return;
    final target = FileOperations.join(
      FileOperations.parent(entry.entity.path),
      newName,
    );
    if (!_samePath(target, entry.entity.path) &&
        FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
      _showMessage('Un élément nommé « $newName » existe déjà.');
      return;
    }
    try {
      await entry.entity.rename(target);
    } on FileSystemException catch (error) {
      if (mounted) _showMessage('Impossible de renommer : ${error.message}');
      return;
    }
    if (mounted) await _reload(select: {target});
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
    final newName = await _askNewName(entry);
    if (newName == null || !mounted) return;
    await menu.rename(commandId, newName);
  }

  /// Demande un nouveau nom valide ; `null` si annulé ou inchangé.
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
    _jobsSubscription?.cancel();
    FolderSizeService.revision.removeListener(_folderSizeChanged);
    _explorerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final splitChild = widget.splitChild;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppearanceScope.of(context).explorerLayout;
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
    final config =
        appearance?.value.explorerLayout ?? Appearance.defaultExplorerLayout;
    final sidebarVisible = _sidebarVisible;
    return SuperLayout(
      key: const ValueKey('explorer-layout'),
      label: 'Disposition de la page',
      // Seul le volet qui affiche le panneau édite la disposition partagée.
      editable: sidebarVisible,
      config: sidebarVisible ? config : config.copyWith(west: false),
      onChanged: appearance == null
          ? null
          : (value) => appearance.value = appearance.value.copyWith(
              explorerLayout: value,
            ),
      zones: {
        SuperLayoutZone.west: ExplorerSidebar(
          locations: _locations,
          currentPath: widget.sidebarPath ?? _currentPath,
          onLocationSelected: widget.onSidebarLocation ?? _loadDirectory,
        ),
        SuperLayoutZone.center: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            widget.onActivate?.call();
            if (widget.split && !_explorerFocusNode.hasFocus) {
              _explorerFocusNode.requestFocus();
            }
          },
          child: _buildExplorer(),
        ),
      },
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
          ValueListenableBuilder(
            valueListenable: FileClipboard.content,
            builder: (context, clipboard, _) => ExplorerViewModeBar(
              actions: _barActions(canPaste: clipboard != null),
              title: _currentFolderName,
              itemCount: entries.length,
              pending: _pendingEntries,
              gridView: _gridView,
              onGridViewChanged: (gridView) =>
                  setState(() => _gridView = gridView),
              columnView: _columnView,
              onColumnViewChanged: (columnView) =>
                  setState(() => _columnView = columnView),
              titleIconKey: _titleIconKey,
              filterCount: _filter.activeCount,
              filterOpen: _filterOpen,
              onToggleFilter: () => setState(() => _filterOpen = !_filterOpen),
              selectionMode: _selectionMode,
              onSelectionModeChanged: (mode) =>
                  setState(() => _selectionMode = mode),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _filterOpen
                ? ExplorerFilterBar(
                    filter: _filter,
                    shown: entries.length,
                    total: _entries.length,
                    onChanged: (filter) => setState(() => _filter = filter),
                    onClose: () => setState(() => _filterOpen = false),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (!_columnView)
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
              _wrapContent(
                IgnorePointer(
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
                            gridView: _showGrid,
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
                                    hasQuery:
                                        _query.isNotEmpty || _filter.isActive,
                                  )
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      final fileList = ExplorerEntriesView(
                                        key: ValueKey(_currentPath),
                                        entries: entries,
                                        gridView: _showGrid,
                                        compact: _columnView,
                                        selectedPath: _selectedPath,
                                        selectedPaths: _selection,
                                        onSelected: _pointerSelect,
                                        onTapped: _columnView
                                            ? _columnTapped
                                            : _tapSelect,
                                        onSelectionChanged: (paths) {
                                          _explorerFocusNode.requestFocus();
                                          _selectionChanged(() {
                                            _collapseTo = null;
                                            _setSelection(paths);
                                          });
                                        },
                                        onToggle:
                                            _effectiveSelectionMode ==
                                                SelectionMode.checkbox
                                            ? _toggleSelection
                                            : null,
                                        revealToken: _revealToken,
                                        onViewportChanged: (size) =>
                                            _viewport = size,
                                        onOpen: _openEntry,
                                        onOpenWithBounds: _columnView
                                            ? null
                                            : (entry, card, icon) =>
                                                  _loadDirectory(
                                                    entry.entity.path,
                                                    heroCard: card,
                                                    heroIcon: icon,
                                                  ),
                                        onContextMenu: Platform.isWindows
                                            ? _showContextMenu
                                            : null,
                                      );
                                      if (!_previewVisible) {
                                        return _columnView
                                            ? Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  SizedBox(
                                                    width: ExplorerColumnsView
                                                        .columnWidth,
                                                    child: fileList,
                                                  ),
                                                ],
                                              )
                                            : fileList;
                                      }

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
                                      if (_columnView) {
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            SizedBox(
                                              width: ExplorerColumnsView
                                                  .columnWidth,
                                              child: fileList,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(child: preview),
                                          ],
                                        );
                                      }
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

  /// Enveloppe le contenu du dossier : colonnes parentes (vue en colonnes) ou
  /// transition de dossier.
  Widget _wrapContent(Widget child) {
    if (_columnView && !_previewExpanded) {
      return ExplorerColumnsView(
        path: _currentPath,
        current: child,
        lastMinWidth:
            ExplorerColumnsView.columnWidth + (_previewVisible ? 352 : 0),
        sort: _sort,
        ascending: _ascending,
        onNavigate: _openColumn,
        onOpen: _openEntry,
      );
    }
    return FolderTransitionView(
      revision: _folderRevision,
      reverse: _reverseTransition,
      child: child,
    );
  }

  String get _currentFolderName {
    final name = _fileName(_currentPath);
    return name.isEmpty ? _currentPath : name;
  }
}
