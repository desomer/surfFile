import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/appearance.dart';

import '../../../models/explorer_entry.dart';
import '../../../services/directory_scanner.dart';
import 'explorer_entries_view.dart';
import '../../file_operations/external_file_drop.dart';

/// Navigation en colonnes (comme le Finder) : un dossier par colonne, de la
/// racine jusqu'au dossier courant. Les colonnes parentes sont lues ici ;
/// la dernière, celle du dossier courant, est fournie par [current].
class ExplorerColumnsView extends StatefulWidget {
  const ExplorerColumnsView({
    required this.path,
    required this.current,
    required this.lastMinWidth,
    required this.sort,
    required this.ascending,
    required this.onNavigate,
    required this.onOpen,
    this.refreshToken,
    super.key,
  });

  static const columnWidth = 260.0;

  /// Dossier courant (dernière colonne).
  final String path;
  final Widget current;

  /// Largeur minimale de la dernière colonne (aperçu compris).
  final double lastMinWidth;
  final ExplorerSort sort;
  final bool ascending;

  /// Ouvre [path] ; [select] est alors l'élément à sélectionner.
  final void Function(String path, {String? select}) onNavigate;
  final ValueChanged<ExplorerEntry> onOpen;
  final Object? refreshToken;

  /// Dossiers parents de [path], de la racine au parent direct.
  static List<String> ancestors(String path) {
    final result = <String>[];
    var current = path;
    while (true) {
      final parent = Directory(current).parent.path;
      if (parent == current) break;
      result.insert(0, parent);
      current = parent;
    }
    return result;
  }

  @override
  State<ExplorerColumnsView> createState() => _ExplorerColumnsViewState();
}

class _ExplorerColumnsViewState extends State<ExplorerColumnsView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToEnd(animate: false);
  }

  @override
  void didUpdateWidget(ExplorerColumnsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _scrollToEnd();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (!animate || MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    final ancestors = ExplorerColumnsView.ancestors(widget.path);
    return LayoutBuilder(
      builder: (context, constraints) {
        final parentsWidth =
            ancestors.length * (ExplorerColumnsView.columnWidth + 1);
        final lastWidth = math.max(
          widget.lastMinWidth,
          constraints.maxWidth - parentsWidth,
        );
        return SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            height: constraints.maxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < ancestors.length; i++) ...[
                  SizedBox(
                    width: ExplorerColumnsView.columnWidth,
                    child: ExternalDropDestination(
                      path: ancestors[i],
                      child: _ParentColumn(
                        key: ValueKey(ancestors[i]),
                        path: ancestors[i],
                        selectedPath: i + 1 < ancestors.length
                            ? ancestors[i + 1]
                            : widget.path,
                        sort: widget.sort,
                        ascending: widget.ascending,
                        onNavigate: widget.onNavigate,
                        onOpen: widget.onOpen,
                        refreshToken: widget.refreshToken,
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: divider),
                ],
                SizedBox(width: lastWidth, child: widget.current),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Contenu d'un dossier parent ; son élément sélectionné est le dossier
/// suivant de la chaîne.
class _ParentColumn extends StatefulWidget {
  const _ParentColumn({
    required this.path,
    required this.selectedPath,
    required this.sort,
    required this.ascending,
    required this.onNavigate,
    required this.onOpen,
    this.refreshToken,
    super.key,
  });

  final String path;
  final String selectedPath;
  final ExplorerSort sort;
  final bool ascending;
  final void Function(String path, {String? select}) onNavigate;
  final ValueChanged<ExplorerEntry> onOpen;
  final Object? refreshToken;

  @override
  State<_ParentColumn> createState() => _ParentColumnState();
}

class _ParentColumnState extends State<_ParentColumn> {
  List<ExplorerEntry>? _entries;
  bool _failed = false;
  ScrollController? _scroll;
  List<ExplorerEntry> _sorted = const [];
  (ExplorerSort, bool)? _sortedBy;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ParentColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final entries = await DirectoryScanner.scan(widget.path);
      if (!mounted || request != _request) return;
      setState(() {
        _entries = entries;
        _failed = false;
        _sortedBy = null;
      });
    } on FileSystemException {
      if (mounted && request == _request) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  List<ExplorerEntry> _sortedEntries() {
    final by = (widget.sort, widget.ascending);
    if (_sortedBy != by) {
      _sorted = [..._entries!];
      sortExplorerEntries(_sorted, widget.sort, ascending: widget.ascending);
      _sortedBy = by;
    }
    return _sorted;
  }

  void _tapped(List<ExplorerEntry> entries, String path) {
    final entry = entries.where((e) => e.entity.path == path).firstOrNull;
    if (entry == null) return;
    if (entry.isDirectory) {
      widget.onNavigate(path);
    } else {
      widget.onNavigate(widget.path, select: path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Text(
          'Dossier inaccessible',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_entries == null) return const SizedBox.shrink();
    final entries = _sortedEntries();
    if (_scroll == null) {
      // Fait apparaître l'élément sélectionné au premier affichage.
      final appearance = AppearanceScope.of(context);
      final index = entries.indexWhere(
        (entry) => entry.entity.path == widget.selectedPath,
      );
      final stride = appearance.rowHeight + appearance.spacing / 6;
      _scroll = ScrollController(
        initialScrollOffset: math.max(0, (index - 2) * stride),
      );
    }
    return ExplorerEntriesView(
      key: ValueKey(widget.path),
      compact: true,
      entries: entries,
      gridView: false,
      selectedPath: widget.selectedPath,
      scrollController: _scroll,
      onSelected: (_) {},
      onTapped: (path) => _tapped(entries, path),
      onOpen: widget.onOpen,
    );
  }
}
