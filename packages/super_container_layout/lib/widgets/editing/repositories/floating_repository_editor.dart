/// Fenêtres flottantes d'édition JSON synchronisées avec les repositories.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';
import 'package:highlight/languages/json.dart' as highlight;
import 'package:material_ui/material_ui.dart';

import '../../../services/repositories/json_repository_store.dart';
import '../../components/internal_widget/code_editor.dart';

final _hosts = Expando<_FloatingRepositoryHost>();

/// Ouvre ou met au premier plan l'éditeur flottant du repository.
///
/// Retourne `true` si une fenêtre a été créée ; [onClosed] est alors appelé
/// après sa destruction et la fin de ses écritures en cours.
bool openFloatingRepositoryEditor(
  BuildContext context, {
  required JsonRepositoryStore store,
  required String repositoryId,
  required String name,
  required String text,
  VoidCallback? onClosed,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final host = _hosts[overlay] ??= _FloatingRepositoryHost(overlay);
  return host.open(store, repositoryId, name, text, onClosed);
}

class _FloatingWindow {
  _FloatingWindow(this.store, this.id, this.name, this.text, this.onClosed);

  final JsonRepositoryStore store;
  final String id;
  final String name;
  final String text;
  final VoidCallback? onClosed;
}

class _FloatingRepositoryHost {
  _FloatingRepositoryHost(this.overlay);

  final OverlayState overlay;
  final List<_FloatingWindow> windows = [];
  OverlayEntry? entry;

  bool open(
    JsonRepositoryStore store,
    String id,
    String name,
    String text,
    VoidCallback? onClosed,
  ) {
    final existing = windows
        .where((window) => identical(window.store, store) && window.id == id)
        .firstOrNull;
    if (existing != null) {
      _bringToFront(existing);
      return false;
    }
    final window = _FloatingWindow(store, id, name, text, onClosed);
    windows.add(window);
    if (entry == null) {
      entry = OverlayEntry(
        maintainState: true,
        builder: (_) => Stack(
          children: [
            for (final item in windows)
              _FloatingRepositoryEditor(
                key: ObjectKey(item),
                store: item.store,
                repositoryId: item.id,
                initialName: item.name,
                initialText: item.text,
                bringToFront: () => _bringToFront(item),
                close: () => _close(item),
                onDisposed: item.onClosed ?? () {},
              ),
          ],
        ),
      );
      overlay.insert(entry!);
    } else {
      entry!.markNeedsBuild();
    }
    return true;
  }

  void _bringToFront(_FloatingWindow window) {
    if (windows.isEmpty || identical(windows.last, window)) return;
    windows.remove(window);
    windows.add(window);
    entry?.markNeedsBuild();
  }

  void _close(_FloatingWindow window) {
    if (!windows.remove(window)) return;
    if (windows.isEmpty) {
      final oldEntry = entry;
      entry = null;
      oldEntry?.remove();
      oldEntry?.dispose();
    } else {
      entry?.markNeedsBuild();
    }
  }
}

class _FloatingRepositoryEditor extends StatefulWidget {
  const _FloatingRepositoryEditor({
    super.key,
    required this.store,
    required this.repositoryId,
    required this.initialName,
    required this.initialText,
    required this.bringToFront,
    required this.close,
    required this.onDisposed,
  });

  final JsonRepositoryStore store;
  final String repositoryId;
  final String initialName;
  final String initialText;
  final VoidCallback bringToFront;
  final VoidCallback close;
  final VoidCallback onDisposed;

  @override
  State<_FloatingRepositoryEditor> createState() =>
      _FloatingRepositoryEditorState();
}

class _FloatingRepositoryEditorState extends State<_FloatingRepositoryEditor> {
  late String _name = widget.initialName;
  late String _draft = widget.initialText;
  late String _appliedDraft = widget.initialText;
  late String _baseline = widget.initialText;
  final _editorError = ValueNotifier<String>('');
  late final _config = CodeEditorConfig(
    mode: highlight.json,
    getText: () => _draft,
    onChange: (String text, CodeEditorConfig _) => _edit(text),
    notifError: _editorError,
    useLargeTextViewer: false,
    type: 'json',
  );
  Offset _position = const Offset(36, 36);
  Size _size = const Size(680, 520);
  String? _error;
  String? _pending;
  Future<void>? _writing;
  bool _conflict = false;
  bool _refreshAfterWrite = false;
  bool _closing = false;
  bool _reloading = false;
  int _revision = 0;
  int _refreshVersion = 0;
  OverlayEntry? _confirmation;
  Completer<bool>? _confirmationResult;

  bool get _hasDraft => _draft != _appliedDraft;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_repositoryChanged);
    _error = _validationError(_draft);
  }

  @override
  void dispose() {
    _finishConfirmation(false);
    widget.store.removeListener(_repositoryChanged);
    _editorError.dispose();
    final writing = _writing;
    if (writing == null) {
      widget.onDisposed();
    } else {
      unawaited(writing.whenComplete(widget.onDisposed));
    }
    super.dispose();
  }

  String? _validationError(String text) {
    try {
      final decoded = jsonDecode(text);
      if (widget.store.isPersistentRepository(widget.repositoryId) &&
          decoded is! Map<String, dynamic>) {
        return 'Le repository applicatif doit être un objet JSON.';
      }
      return null;
    } on FormatException {
      return 'JSON invalide : corrigez votre saisie.';
    }
  }

  void _edit(String text) {
    if (text == _draft) return;
    _revision++;
    final error = _validationError(text);
    setState(() {
      _draft = text;
      if (!_conflict) {
        _error = error;
        _pending = error == null ? text : null;
      }
    });
    if (error == null && !_conflict) _startWriting();
  }

  void _startWriting() {
    if (_writing != null || _pending == null) return;
    final future = _writePending();
    _writing = future;
    unawaited(
      future.whenComplete(() {
        _writing = null;
        if (!mounted) return;
        if (_pending != null && !_conflict) _startWriting();
      }),
    );
  }

  Future<void> _writePending() async {
    while (mounted && !_conflict && _pending != null) {
      final text = _pending!;
      _pending = null;
      try {
        await widget.store.save(_name, text, expectedText: _baseline);
        final registered =
            widget.store.isMemoryOnlyRepository(widget.repositoryId) ||
            widget.store.isPersistentRepository(widget.repositoryId);
        _baseline = registered
            ? '${const JsonEncoder.withIndent('  ').convert(jsonDecode(text))}\n'
            : text;
        _appliedDraft = text;
        if (!mounted) return;
        setState(() {});
      } on FormatException catch (error) {
        if (!mounted) return;
        setState(() {
          _pending = null;
          _conflict = true;
          _error = error.message;
        });
      } on FileSystemException catch (error) {
        if (!mounted) return;
        setState(() {
          _pending = null;
          _conflict = true;
          _error = 'Erreur de fichier : ${error.message}';
        });
      }
    }
    if (mounted && _refreshAfterWrite) {
      _refreshAfterWrite = false;
      await _refresh(afterWrite: true);
    }
  }

  void _repositoryChanged() {
    if (_reloading) return;
    if (_writing != null) {
      _refreshAfterWrite = true;
    } else {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh({bool discard = false, bool afterWrite = false}) async {
    final revision = _revision;
    final refreshVersion = ++_refreshVersion;
    try {
      final catalog = await widget.store.catalog();
      final entry = catalog
          .where((entry) => entry.id == widget.repositoryId)
          .firstOrNull;
      if (entry == null) {
        throw const FormatException('Le repository a été supprimé.');
      }
      final text = await widget.store.read(entry.name);
      if (!mounted || refreshVersion != _refreshVersion) return;
      if (_writing != null && !afterWrite) {
        _refreshAfterWrite = true;
        return;
      }
      setState(() {
        _name = entry.name;
        if (discard ||
            (text != _baseline && !_hasDraft && revision == _revision)) {
          _draft = text;
          _appliedDraft = text;
          _baseline = text;
          _pending = null;
          _conflict = false;
          _error = _validationError(text);
          _config.repaintCode();
        } else if (text != _baseline) {
          _pending = null;
          _conflict = true;
          _error = 'Le repository a changé. Copiez le brouillon ou rechargez.';
        }
      });
    } on FormatException catch (error) {
      if (!mounted || refreshVersion != _refreshVersion) return;
      setState(() {
        _pending = null;
        _conflict = true;
        _error = error.message;
      });
    } on FileSystemException catch (error) {
      if (!mounted || refreshVersion != _refreshVersion) return;
      setState(() {
        _pending = null;
        _conflict = true;
        _error = 'Erreur de fichier : ${error.message}';
      });
    }
  }

  Future<void> _copy() => Clipboard.setData(ClipboardData(text: _draft));

  Future<bool> _confirmDiscard() async {
    if (!_hasDraft) return true;
    if (_confirmationResult != null) return false;
    final result = Completer<bool>();
    _confirmationResult = result;
    _confirmation = OverlayEntry(
      builder: (context) => Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Color(0x66000000)),
          Center(
            child: AlertDialog(
              title: const Text('Brouillon non appliqué'),
              content: const Text('Abandonner le texte non enregistré ?'),
              actions: [
                TextButton(
                  onPressed: () => _finishConfirmation(false),
                  child: const Text('Conserver'),
                ),
                TextButton(onPressed: _copy, child: const Text('Copier')),
                FilledButton(
                  onPressed: () => _finishConfirmation(true),
                  child: const Text('Abandonner'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_confirmation!);
    return result.future;
  }

  void _finishConfirmation(bool result) {
    final entry = _confirmation;
    final completer = _confirmationResult;
    _confirmation = null;
    _confirmationResult = null;
    if (entry == null || completer == null) return;
    entry.remove();
    entry.dispose();
    completer.complete(result);
  }

  Future<void> _reload() async {
    if (_reloading || !await _confirmDiscard() || !mounted) return;
    setState(() {
      _reloading = true;
      _config.readOnly = true;
    });
    try {
      while (_writing != null) {
        await _writing;
      }
      if (!mounted) return;
      if (widget.store.isPersistentRepository(widget.repositoryId)) {
        await widget.store.loadRepository(widget.repositoryId);
      }
      await _refresh(discard: true);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _error = 'Erreur de fichier : ${error.message}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _reloading = false;
          _config.readOnly = false;
        });
      }
    }
  }

  Future<void> _close() async {
    if (_closing || _reloading) return;
    _closing = true;
    while (_writing != null) {
      await _writing;
    }
    if (!mounted) return;
    if (!await _confirmDiscard() || !mounted) {
      _closing = false;
      return;
    }
    widget.close();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _size.width
            .clamp(math.min(320.0, constraints.maxWidth), constraints.maxWidth)
            .toDouble();
        final height = _size.height
            .clamp(
              math.min(240.0, constraints.maxHeight),
              constraints.maxHeight,
            )
            .toDouble();
        final left = _position.dx.clamp(0.0, constraints.maxWidth - width);
        final top = _position.dy.clamp(0.0, constraints.maxHeight - height);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: Listener(
                onPointerDown: (_) => widget.bringToFront(),
                child: Material(
                  key: ValueKey('floating-repository-${widget.repositoryId}'),
                  elevation: 12,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  color: Theme.of(context).colorScheme.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        key: const ValueKey('floating-repository-title'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onPanUpdate: (details) => setState(() {
                          _position = Offset(
                            (_position.dx.clamp(
                                      0.0,
                                      constraints.maxWidth - width,
                                    ) +
                                    details.delta.dx)
                                .clamp(0.0, constraints.maxWidth - width),
                            (_position.dy.clamp(
                                      0.0,
                                      constraints.maxHeight - height,
                                    ) +
                                    details.delta.dy)
                                .clamp(0.0, constraints.maxHeight - height),
                          );
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.drag_indicator),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Repository : $_name',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copier le JSON',
                                onPressed: _copy,
                                icon: const Icon(Icons.copy),
                              ),
                              IconButton(
                                key: const ValueKey(
                                  'floating-repository-close',
                                ),
                                tooltip: 'Fermer',
                                onPressed: _close,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.store.isMemoryOnlyRepository(
                        widget.repositoryId,
                      ))
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Repository en mémoire : aucune sauvegarde sur disque.',
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            _error!,
                            key: const ValueKey('floating-repository-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_conflict)
                        TextButton(
                          key: const ValueKey('floating-repository-reload'),
                          onPressed: _reload,
                          child: const Text('Recharger'),
                        ),
                      Expanded(
                        child: CodeEditor(
                          key: const ValueKey('floating-repository-code'),
                          config: _config,
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: GestureDetector(
                          key: const ValueKey('floating-repository-resize'),
                          behavior: HitTestBehavior.opaque,
                          dragStartBehavior: DragStartBehavior.down,
                          onPanUpdate: (details) => setState(() {
                            final maxWidth = constraints.maxWidth - left;
                            final maxHeight = constraints.maxHeight - top;
                            final minWidth = math.min(320.0, maxWidth);
                            final minHeight = math.min(240.0, maxHeight);
                            _size = Size(
                              (_size.width.clamp(minWidth, maxWidth) +
                                      details.delta.dx)
                                  .clamp(minWidth, maxWidth),
                              (_size.height.clamp(minHeight, maxHeight) +
                                      details.delta.dy)
                                  .clamp(minHeight, maxHeight),
                            );
                            _position = Offset(left, top);
                          }),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.drag_handle, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
