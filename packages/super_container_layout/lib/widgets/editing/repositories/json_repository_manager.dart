import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../services/repositories/json_repository_store.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../dialogs/editor_dialog_header.dart';

class JsonRepositoryManager extends StatefulWidget {
  const JsonRepositoryManager({this.store, super.key});

  final JsonRepositoryStore? store;

  static Future<void> show(BuildContext context) {
    final store = JsonRepositoryScope.maybeOf(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => JsonRepositoryManager(store: store),
    );
  }

  @override
  State<JsonRepositoryManager> createState() => _JsonRepositoryManagerState();
}

class _JsonRepositoryManagerState extends State<JsonRepositoryManager> {
  final _folder = TextEditingController();
  final _text = TextEditingController();
  JsonRepositoryStore? _store;
  JsonRepositoryStore? _ownedStore;
  List<String> _names = [];
  String? _selected;
  String? _selectedId;
  String _savedText = '';
  String? _error;
  String? _notice;
  bool _busy = false;
  bool _confirming = false;
  bool get _dirty => _selected != null && _text.text != _savedText;

  @override
  void initState() {
    super.initState();
    _text.addListener(_edited);
    _run(() async {
      final store = widget.store ?? JsonRepositoryStore.defaultStore();
      if (widget.store == null) _ownedStore = store;
      _folder.text = store.directory.path;
      await _loadDirectory(store);
    });
  }

  void _edited() => setState(() => _notice = null);

  @override
  void dispose() {
    _store?.removeListener(_repositoryChanged);
    _ownedStore?.dispose();
    _folder.dispose();
    _text.removeListener(_edited);
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await operation();
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _error = 'Erreur de fichier : ${error.message}');
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _discard() async {
    if (!_dirty) return true;
    if (_confirming) return false;
    _confirming = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text('Abandonner les modifications du repository ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conserver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    _confirming = false;
    return result == true && mounted;
  }

  Future<void> _loadDirectory(JsonRepositoryStore store) async {
    final names = await store.list();
    if (!mounted) return;
    _store?.removeListener(_repositoryChanged);
    store.addListener(_repositoryChanged);
    setState(() {
      _store = store;
      _names = names;
      _selected = null;
      _selectedId = null;
      _savedText = '';
      _text.clear();
    });
  }

  void _repositoryChanged() {
    if (_busy || !mounted) return;
    if (_dirty) {
      setState(
        () => _error =
            'Le repository a changé. Enregistrez ou rechargez votre saisie.',
      );
      return;
    }
    _run(() async {
      final names = await _store!.list();
      final id = _selectedId;
      final catalog = id == null ? null : await _store!.catalog();
      final selected = catalog?.where((entry) => entry.id == id).firstOrNull;
      final text = selected == null ? null : await _store!.read(selected.name);
      if (!mounted) return;
      setState(() {
        _names = names;
        _selected = selected?.name;
        _selectedId = selected?.id;
        _savedText = text ?? '';
        _text.text = _savedText;
      });
    });
  }

  Future<void> _changeDirectory() async {
    if (!await _discard() || !mounted) return;
    await _run(() async {
      final path = _folder.text.trim();
      if (path.isEmpty) {
        throw const FormatException('Indiquez un dossier de repositories.');
      }
      final shared = widget.store;
      if (shared != null &&
          Directory(path).absolute.path == shared.directory.absolute.path) {
        await _loadDirectory(shared);
        _ownedStore?.dispose();
        _ownedStore = null;
      } else {
        final store = JsonRepositoryStore(Directory(path));
        try {
          await _loadDirectory(store);
          _ownedStore?.dispose();
          _ownedStore = store;
        } on FileSystemException {
          store.dispose();
          rethrow;
        }
      }
    });
  }

  Future<void> _select(String name) async {
    if (!await _discard() || !mounted) return;
    await _run(() async {
      final text = await _store!.read(name);
      final id = await _store!.idOf(name);
      if (!mounted) return;
      setState(() {
        _selected = name;
        _selectedId = id;
        _savedText = text;
        _text.text = text;
      });
    });
  }

  Future<String?> _askName({String? current}) => showDialog<String>(
    context: context,
    builder: (_) => _RepositoryNameDialog(current: current),
  );

  Future<void> _create() async {
    if (!await _discard() || !mounted) return;
    final name = await _askName();
    if (name == null || !mounted) return;
    await _run(() async {
      await _store!.create(name);
      final names = await _store!.list();
      final text = await _store!.read(name);
      final id = await _store!.idOf(name);
      if (!mounted) return;
      setState(() {
        _names = names;
        _selected = name;
        _selectedId = id;
        _savedText = text;
        _text.text = text;
        _notice = 'Repository créé.';
      });
    });
  }

  Future<void> _rename() async {
    final name = await _askName(current: _selected);
    if (name == null || !mounted) return;
    await _run(() async {
      await _store!.rename(_selected!, name);
      final names = await _store!.list();
      if (!mounted) return;
      setState(() {
        _selected = name;
        _names = names;
        _notice = 'Repository renommé.';
      });
    });
  }

  Future<void> _delete([String? target]) async {
    final name = target ?? _selected;
    if (name == null || _busy || _confirming) return;
    _confirming = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le repository ?'),
        content: Text('Supprimer définitivement « $name » ($name.json) ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('repository-confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _store!.delete(name);
      final names = await _store!.list();
      if (!mounted) return;
      final removedSelected =
          _selected != null && _selected!.toLowerCase() == name.toLowerCase();
      setState(() {
        _names = names;
        if (removedSelected) {
          _selected = null;
          _selectedId = null;
          _savedText = '';
          _text.clear();
        }
        _notice = 'Repository supprimé.';
      });
    });
  }

  Future<void> _save() => _run(() async {
    final text = _text.text;
    await _store!.save(_selected!, text, expectedText: _savedText);
    if (!mounted) return;
    setState(() {
      _savedText = text;
      _notice = 'Repository enregistré.';
    });
  });

  void _format() {
    try {
      final value = jsonDecode(_text.text);
      _text.text = '${const JsonEncoder.withIndent('  ').convert(value)}\n';
      setState(() => _error = null);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _close() async {
    if (_busy || !await _discard() || !mounted) return;
    setState(() {
      _selected = null;
    });
    // Let PopScope observe the clean state before popping.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Widget _repositories() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        key: const ValueKey('repository-create'),
        onPressed: _busy || _store == null ? null : _create,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau'),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _names.isEmpty
            ? const Text('Aucun repository dans ce dossier.')
            : ListView(
                children: [
                  for (final name in _names)
                    ListTile(
                      key: ValueKey('repository-entry-$name'),
                      title: Text(name),
                      subtitle: Text('$name.json'),
                      selected: name == _selected,
                      enabled: !_busy,
                      onTap: () => _select(name),
                      trailing: IconButton(
                        key: ValueKey('repository-delete-$name'),
                        tooltip: 'Supprimer',
                        onPressed: _busy ? null : () => _delete(name),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              ),
      ),
    ],
  );

  Widget _editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_selected != null)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text('$_selected${_dirty ? ' *' : ''}'),
            TextButton(
              onPressed: _busy ? null : _rename,
              child: const Text('Renommer'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _select(_selected!),
              child: const Text('Recharger'),
            ),
            TextButton(
              onPressed: _busy ? null : _format,
              child: const Text('Formater'),
            ),
            TextButton(
              key: const ValueKey('repository-delete'),
              onPressed: _busy ? null : () => _delete(_selected!),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      if (_selectedId != null) ...[
        SelectableText(
          'ID technique : $_selectedId',
          key: const ValueKey('repository-id'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
      ],
      Expanded(
        child: _selected == null
            ? const Center(child: Text('Sélectionnez ou créez un repository.'))
            : TextField(
                key: const ValueKey('repository-json'),
                controller: _text,
                readOnly: _busy,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'Contenu JSON',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy) _close();
    },
    child: AlertDialog(
      title: const EditorDialogHeader(label: 'Repository'),
      content: SizedBox(
        width: 900,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('repository-directory'),
              controller: _folder,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'Dossier des repositories',
                suffixIcon: IconButton(
                  tooltip: 'Charger le dossier',
                  onPressed: _busy ? null : _changeDirectory,
                  icon: const Icon(Icons.folder_open),
                ),
              ),
              onSubmitted: _busy ? null : (_) => _changeDirectory(),
            ),
            if (_store != null)
              Text('Dossier ouvert : ${_store!.directory.path}'),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                key: const ValueKey('repository-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_notice != null) Text(_notice!),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 600
                    ? Column(
                        children: [
                          SizedBox(height: 130, child: _repositories()),
                          const SizedBox(height: 8),
                          Expanded(child: _editor()),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 220, child: _repositories()),
                          const SizedBox(width: 16),
                          Expanded(child: _editor()),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _close,
          child: const Text('Fermer'),
        ),
        FilledButton(
          key: const ValueKey('repository-save'),
          onPressed: _busy || !_dirty ? null : _save,
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}

class _RepositoryNameDialog extends StatefulWidget {
  const _RepositoryNameDialog({this.current});
  final String? current;

  @override
  State<_RepositoryNameDialog> createState() => _RepositoryNameDialogState();
}

class _RepositoryNameDialogState extends State<_RepositoryNameDialog> {
  late final _name = TextEditingController(text: widget.current);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      Navigator.pop(context, JsonRepositoryStore.validateName(_name.text));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.current == null ? 'Nouveau repository' : 'Renommer'),
    content: TextField(
      key: const ValueKey('repository-name'),
      controller: _name,
      autofocus: true,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: 'Nom du repository',
        helperText: 'Le fichier portera ce nom, suivi de .json.',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Valider')),
    ],
  );
}
