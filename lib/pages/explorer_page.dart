import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../models/explorer_entry.dart';
import '../models/explorer_location.dart';
import '../services/personal_folders.dart';
import '../services/windows_context_menu.dart';
import '../theme/explorer_colors.dart';
import '../widgets/explorer_breadcrumbs.dart';
import '../widgets/explorer_context_menu.dart';
import '../widgets/explorer_empty_state.dart';
import '../widgets/explorer_entries_view.dart';
import '../widgets/explorer_error_state.dart';
import '../widgets/explorer_sidebar.dart';
import '../widgets/explorer_sort_header.dart';
import '../widgets/explorer_toolbar.dart';
import '../widgets/explorer_view_toggle.dart';
import '../widgets/mouse_back_navigation.dart';
import '../widgets/folder_transition_view.dart';
import '../widgets/folder_hero_flight.dart';
import '../theme/appearance.dart';
import '../theme/folder_transition.dart';

enum _HistoryDirection { back, forward }

class ExplorerPage extends StatefulWidget {
  const ExplorerPage({super.key});

  @override
  State<ExplorerPage> createState() => _ExplorerPageState();
}

class _ExplorerPageState extends State<ExplorerPage> {
  late String _currentPath;
  final List<String> _history = [];
  final List<String> _forwardHistory = [];
  _HistoryDirection? _failedDirection;
  List<ExplorerEntry> _entries = [];
  String _query = '';
  String? _selectedPath;
  String? _loadError;
  String? _failedPath;
  bool _initializationFailed = false;
  List<ExplorerLocation> _locations = [];
  bool _isLoading = true;
  bool _gridView = false;
  bool _ascending = true;
  bool _contextMenuOpen = false;
  ExplorerSort _sort = ExplorerSort.name;
  bool _hasLoadedDirectory = false;
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

  String get _homePath =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;

  @override
  void initState() {
    super.initState();
    _currentPath = _homePath;
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
              'Images', folders['Pictures']!, Icons.image_outlined),
          ExplorerLocation(
              'Musique', folders['Music']!, Icons.headphones_outlined),
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

  List<ExplorerEntry> get _visibleEntries {
    final query = _query.trim().toLowerCase();
    final entries = _entries
        .where((entry) =>
            query.isEmpty || entry.name.toLowerCase().contains(query))
        .toList();
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      final comparison = switch (_sort) {
        ExplorerSort.name =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        ExplorerSort.modified => a.modified.compareTo(b.modified),
        ExplorerSort.size => a.size.compareTo(b.size),
      };
      return _ascending ? comparison : -comparison;
    });
    return entries;
  }

  Future<void> _loadDirectory(
    String path, {
    bool addToHistory = true,
    _HistoryDirection? direction,
    Rect? heroCard,
    Rect? heroIcon,
  }) async {
    final request = ++_loadRequest;
    setState(() {
      _isLoading = true;
      _loadError = null;
      _failedPath = null;
      _failedDirection = null;
    });

    try {
      final directory = Directory(path);
      final entities = <FileSystemEntity>[];
      await for (final entity in directory.list(followLinks: false)) {
        entities.add(entity);
      }
      final entries = await Future.wait(
        entities.map((entity) async {
          final stat = await entity.stat();
          return ExplorerEntry(
            entity: entity,
            name: _fileName(entity.path),
            isDirectory: entity is Directory,
            modified: stat.modified,
            size: stat.size,
          );
        }),
      );
      if (!mounted || request != _loadRequest) return;

      setState(() {
        _heroSource = null;
        if (_hasLoadedDirectory && path != _currentPath) {
          _folderRevision++;
          _reverseTransition = direction == _HistoryDirection.back ||
              (direction == null &&
                  path == Directory(_currentPath).parent.path);
          final appearance = AppearanceScope.of(context);
          final type = appearance.folderTransition;
          if (heroCard != null &&
              heroIcon != null &&
              !MediaQuery.disableAnimationsOf(context) &&
              (type == FolderTransition.heroExpand ||
                  type == FolderTransition.heroIcon)) {
            _heroExpand = type == FolderTransition.heroExpand;
            final target = (_heroExpand ? _contentKey : _titleIconKey)
                .currentContext!
                .findRenderObject()! as RenderBox;
            final overlay =
                _overlayKey.currentContext!.findRenderObject()! as RenderBox;
            final origin = overlay.localToGlobal(Offset.zero);
            _heroSource = (_heroExpand ? heroCard : heroIcon).shift(-origin);
            _heroDestination = (target.localToGlobal(Offset.zero) & target.size)
                .shift(-origin);
            _heroDuration = Duration(
                milliseconds: appearance.folderTransitionDuration.round());
            _heroRevision++;
          }
        }
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
        _currentPath = path;
        _entries = entries;
        _selectedPath = null;
        _isLoading = false;
        _hasLoadedDirectory = true;
      });
    } on FileSystemException catch (error) {
      debugPrint('Error loading directory: $error');
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _isLoading = false;
        _failedPath = path;
        _failedDirection = direction;
        _loadError =
            'Impossible d’ouvrir le dossier "$path" : ${error.message}';
      });
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
    await _loadDirectory(_forwardHistory.last,
        direction: _HistoryDirection.forward);
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
        _showMessage('Impossible d’utiliser le menu Windows : '
            '${error.message ?? error.code}');
      }
    } on MissingPluginException catch (error) {
      debugPrint('Windows context menu unavailable: $error');
      if (mounted) {
        _showMessage('Le menu Windows est indisponible. '
            'Arrêtez puis relancez l’application.');
      }
    } finally {
      try {
        await menu?.close();
      } on PlatformException catch (error) {
        debugPrint('Error closing Windows context menu: $error');
        if (mounted) {
          _showMessage('Impossible de fermer le contexte du menu Windows : '
              '${error.message ?? error.code}');
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: MouseBackNavigation(
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
                  ExplorerSidebar(
                    locations: _locations,
                    currentPath: _currentPath,
                    onLocationSelected: _loadDirectory,
                  ),
                  //const VerticalDivider(width: 1, thickness: 1),
                  Expanded(child: _buildExplorer()),
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
    );
  }

  Widget _buildExplorer() {
    final entries = _visibleEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExplorerToolbar(
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
                Icon(Icons.folder_rounded,
                    key: _titleIconKey,
                    size: 28,
                    color: AppearanceScope.of(context).accent),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  _currentFolderName,
                  style: const TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${entries.length} élément${entries.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: explorerColor(context, const Color(0xFF82899A),
                      Theme.of(context).colorScheme.onSurfaceVariant),
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
                  child: _isLoading && !_hasLoadedDirectory
                      ? const Center(child: CircularProgressIndicator())
                      : _loadError != null
                          ? ExplorerErrorState(
                              message: _loadError!,
                              onRetry: () {
                                if (_initializationFailed) {
                                  _initialize();
                                } else {
                                  _loadDirectory(_failedPath ?? _currentPath,
                                      direction: _failedDirection);
                                }
                              },
                            )
                          : entries.isEmpty
                              ? ExplorerEmptyState(hasQuery: _query.isNotEmpty)
                              : ExplorerEntriesView(
                                  key: ValueKey(_currentPath),
                                  entries: entries,
                                  gridView: _gridView,
                                  selectedPath: _selectedPath,
                                  onSelected: (path) =>
                                      setState(() => _selectedPath = path),
                                  onOpen: _openEntry,
                                  onOpenWithBounds: (entry, card, icon) =>
                                      _loadDirectory(entry.entity.path,
                                          heroCard: card, heroIcon: icon),
                                  onContextMenu: Platform.isWindows
                                      ? _showContextMenu
                                      : null,
                                ),
                ),
              ),
              if (_isLoading && _hasLoadedDirectory)
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
