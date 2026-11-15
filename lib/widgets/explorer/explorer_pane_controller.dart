part of 'explorer_pane.dart';

/// Contrat de navigation exposé à la page d'explorateur.
abstract interface class ExplorerPaneHandle {
  /// Indique si le volet a terminé son chargement initial.
  bool get ready;

  /// Retourne le chemin et la sélection visibles du volet.
  PaneSnapshot get snapshot;

  /// Navigue vers [path].
  Future<void> navigate(String path);

  /// Recharge le dossier courant.
  Future<void> refresh();

  /// Reconstruit le volet après une mise à jour externe.
  void touch();
}

/// État et navigation propres à une instance de volet ; chaque State en possède un.
mixin ExplorerPaneController on State<ExplorerPane> {
  GlobalKey get _contentKey;
  GlobalKey get _titleIconKey;
  GlobalKey get _overlayKey;
  set _heroSource(Rect? value);
  set _heroDestination(Rect? value);
  bool get _heroExpand;
  set _heroExpand(bool value);
  int get _heroRevision;
  set _heroRevision(int value);
  set _heroDuration(Duration value);
  FocusNode get _explorerFocusNode;
  Size get _viewport;

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
  String _typed = '';
  DateTime _typedAt = DateTime(0);
  StreamSubscription<FileJob>? _jobsSubscription;
  final _ownJobs = <FileJob>{};

  /// Élément principal (clavier, aperçu, menu contextuel).
  String? get _selectedPath => _primary;
  set _selectedPath(String? path) {
    _primary = path;
    _anchor = path;
    _selection = path == null ? const {} : Set.unmodifiable({path});
  }

  void _setSelection(Set<String> paths) {
    final visible = _visibleEntries;
    _selection = paths.isEmpty ? const {} : Set.unmodifiable(paths);
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
      _selection = Set.unmodifiable(next);
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
    _selection = Set.unmodifiable(add ? {..._selection, ...range} : range);
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
    if (!keys.isShiftPressed &&
        !keys.isControlPressed &&
        _selection.length == 1 &&
        _selection.contains(path) &&
        _primary == path) {
      _anchor = path;
      _collapseTo = null;
      return;
    }
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
    if (_selection.length == 1 &&
        _selection.contains(path) &&
        _primary == path) {
      return;
    }
    _explorerFocusNode.requestFocus();
    _selectionChanged(() => _selectedPath = path);
  }

  String? _loadError;
  String? _failedPath;
  bool _initializationFailed = false;
  List<ExplorerLocation> _locations = const [];
  bool _isLoading = true;
  bool _gridView = false;
  bool _columnView = false;
  bool _heatmapView = false;
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

  bool get _ready => _hasLoadedDirectory && !_isLoading;

  PaneSnapshot get _snapshot => PaneSnapshot(
    path: _currentPath,
    selection: [
      for (final entry in _visibleEntries)
        if (_selection.contains(entry.entity.path)) entry.entity.path,
    ],
  );

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

  bool _samePath(String a, String b) =>
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
        _locations = List.unmodifiable([
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
        ]);
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
      widget.onPathChanged?.call(path);
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
    final preferences = SurfFilePreferencesScope.of(context);
    final type = preferences.folderTransition;
    final duration = Duration(
      milliseconds: preferences.folderTransitionDuration.round(),
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
}
