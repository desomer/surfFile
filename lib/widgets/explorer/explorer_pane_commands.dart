part of 'explorer_pane.dart';

/// Raccordement des raccourcis et opérations de fichiers aux callbacks de l’UI.
mixin ExplorerPaneCommands on ExplorerPaneController {
  void _showMessage(String message);
  Future<bool> _confirmDelete(List<String> paths, {required bool permanent});
  Future<String?> _askNewName(ExplorerEntry entry);
  Future<String?> _askFolderName();
  Future<FileJob?> _confirmExternalDrop(
    List<String> sources,
    String destination,
  );

  /// Actions de la barre des modes d'affichage, activées selon la sélection.
  List<ExplorerBarAction> _barActions({required bool canPaste}) {
    final idle = _ready && !_contextMenuOpen;
    ExplorerEntry? entry;
    if (idle && _selection.isNotEmpty) {
      final preferred = _selectedPath;
      if (preferred != null) {
        for (final candidate in _visibleEntries) {
          if (candidate.entity.path == preferred) {
            entry = candidate;
            break;
          }
        }
      }
      if (entry == null) {
        for (final candidate in _visibleEntries) {
          if (_selection.contains(candidate.entity.path)) {
            entry = candidate;
            break;
          }
        }
      }
    }
    final targetEntry = entry;
    final hasSelection = targetEntry != null;
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
        onPressed: targetEntry != null
            ? () => _renameWithKeyboard(targetEntry)
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

  Future<void> _receiveExternalDrop(
    List<String> sources,
    String destination,
  ) async {
    try {
      final job = await _confirmExternalDrop(sources, destination);
      if (job == null) return;
      _ownJobs.add(job);
      Set<String>? created;
      try {
        created = (await job.result).toSet();
      } on FileOperationCancelled {
        // L'annulation est affichée dans le panneau de transferts.
      } finally {
        if (mounted) {
          await _reload(
            select: _samePath(_currentPath, destination) ? created : null,
          );
        }
      }
    } on FileSystemException catch (error) {
      if (mounted) _showMessage('Dépôt impossible : ${error.message}');
    } on Object catch (error) {
      debugPrint('Error receiving Windows file drop: $error');
      if (mounted) _showMessage('Dépôt impossible : $error');
    }
  }

  /// Demande confirmation avant de supprimer [paths] : à la corbeille, ou
  /// définitivement si [permanent] (ou si le système n'a pas de corbeille).
  Future<void> _deleteSelection({required bool permanent}) async {
    final paths = _snapshot.selection;
    if (paths.isEmpty || _contextMenuOpen) return;
    if (!await _confirmDelete(paths, permanent: permanent)) return;

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

  /// Crée un nouveau dossier dans le dossier courant.
  Future<void> _createFolder() async {
    final name = await _askFolderName();
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
}
