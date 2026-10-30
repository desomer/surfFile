import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';

const inheritedRepositoryValue = '*';

class RepositoryBindingDialogResult {
  const RepositoryBindingDialogResult(this.binding);

  final JsonTextBinding? binding;
}

Future<RepositoryBindingDialogResult?> showRepositoryBindingDialog({
  required BuildContext context,
  required String title,
  required String keyPrefix,
  required String pathHint,
  required JsonTextBinding? binding,
  JsonRepositoryStore? store,
  JsonListScope? listScope,
  String? helper,
}) {
  final repositoryStore = store ?? JsonRepositoryScope.maybeOf(context);
  final repositoryListScope = listScope ?? JsonListScope.maybeOf(context);
  return showEditorDialog<RepositoryBindingDialogResult>(
    context: context,
    target: context,
    builder: (_) => _RepositoryBindingDialog(
      title: title,
      keyPrefix: keyPrefix,
      pathHint: pathHint,
      binding: binding,
      store: repositoryStore,
      listScope: repositoryListScope,
      helper: helper,
    ),
  );
}

class _RepositoryBindingDialog extends StatefulWidget {
  const _RepositoryBindingDialog({
    required this.title,
    required this.keyPrefix,
    required this.pathHint,
    required this.binding,
    required this.store,
    required this.listScope,
    required this.helper,
  });

  final String title;
  final String keyPrefix;
  final String pathHint;
  final JsonTextBinding? binding;
  final JsonRepositoryStore? store;
  final JsonListScope? listScope;
  final String? helper;

  @override
  State<_RepositoryBindingDialog> createState() =>
      _RepositoryBindingDialogState();
}

class _RepositoryBindingDialogState extends State<_RepositoryBindingDialog> {
  final _form = GlobalKey<FormState>();
  late JsonTextBinding? _selected = widget.binding;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: EditorDialogHeader(label: widget.title),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: RepositoryBindingFields(
          key: ValueKey('${widget.keyPrefix}-fields'),
          keyPrefix: widget.keyPrefix,
          binding: _selected,
          pathHint: widget.pathHint,
          helper: widget.helper,
          store: widget.store,
          listScope: widget.listScope,
          onChanged: (value) => setState(() => _selected = value),
        ),
      ),
    ),
    actions: [
      TextButton(
        key: ValueKey('${widget.keyPrefix}-remove'),
        onPressed: () =>
            Navigator.of(context)
                .pop(const RepositoryBindingDialogResult(null)),
        child: const Text('Supprimer la liaison'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: ValueKey('${widget.keyPrefix}-apply'),
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.of(context).pop(RepositoryBindingDialogResult(_selected));
        },
        child: const Text('Appliquer'),
      ),
    ],
  );
}

/// Repository binding fields shared by the add wizard and property editors.
class RepositoryBindingFields extends StatefulWidget {
  const RepositoryBindingFields({
    required this.keyPrefix,
    required this.binding,
    required this.onChanged,
    required this.pathHint,
    this.store,
    this.listScope,
    this.helper,
    super.key,
  });

  final String keyPrefix;
  final JsonTextBinding? binding;
  final ValueChanged<JsonTextBinding?> onChanged;
  final String pathHint;
  final JsonRepositoryStore? store;
  final JsonListScope? listScope;
  final String? helper;

  @override
  State<RepositoryBindingFields> createState() =>
      _RepositoryBindingFieldsState();
}

class _RepositoryBindingFieldsState extends State<RepositoryBindingFields> {
  late final _path = TextEditingController(text: widget.binding?.path ?? '');
  late String _repository = widget.binding == null
      ? ''
      : widget.binding!.repositoryId ?? inheritedRepositoryValue;
  List<JsonRepositoryEntry> _repositories = const [];
  JsonRepositoryStore? _store;
  bool _loading = false;
  String? _loadError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateStore();
  }

  @override
  void didUpdateWidget(covariant RepositoryBindingFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) _updateStore();
    if (oldWidget.binding != widget.binding) {
      _repository = widget.binding == null
          ? ''
          : widget.binding!.repositoryId ?? inheritedRepositoryValue;
      final path = widget.binding?.path ?? '';
      if (_path.text != path) _path.text = path;
    }
  }

  void _updateStore() {
    final store = widget.store ?? JsonRepositoryScope.maybeOf(context);
    if (!identical(store, _store)) {
      _store = store;
      if (store != null) _load();
    }
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = _store;
    if (store == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final entries = await store.catalog();
      if (mounted && identical(store, _store)) {
        setState(() => _repositories = entries);
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } on FileSystemException {
      if (mounted) {
        setState(() => _loadError = 'Impossible de charger les repositories.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _emit() => widget.onChanged(
    _repository.isEmpty
        ? null
        : JsonTextBinding(
            repositoryId: _repository == inheritedRepositoryValue
                ? null
                : _repository,
            path: _path.text.trim(),
          ),
  );

  String? get _pathError {
    if (_repository.isEmpty) return null;
    if (_path.text.trim().isEmpty) return 'Chemin requis.';
    try {
      JsonAttributePath(_path.text.trim());
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _store != null;
    final listScope = widget.listScope ?? JsonListScope.maybeOf(context);
    final depth = listScope?.indices.length ?? 0;
    final inheritable =
        listScope != null || _repository == inheritedRepositoryValue;
    final known =
        _repository.isEmpty ||
        _repository == inheritedRepositoryValue ||
        _repositories.any((entry) => entry.id == _repository);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                key: ValueKey('${widget.keyPrefix}-repository'),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Repository',
                  prefixIcon: Icon(Icons.link),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _repository,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Sans liaison'),
                      ),
                      if (inheritable)
                        const DropdownMenuItem(
                          value: inheritedRepositoryValue,
                          child: Text('Hérité de la liste englobante'),
                        ),
                      for (final entry in _repositories)
                        DropdownMenuItem(
                          value: entry.id,
                          child: Text(
                            entry.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (!known)
                        DropdownMenuItem(
                          value: _repository,
                          child: const Text('Repository indisponible'),
                        ),
                    ],
                    onChanged: !available && !inheritable
                        ? null
                        : (value) {
                            setState(() => _repository = value ?? '');
                            _emit();
                          },
                  ),
                ),
              ),
            ),
            IconButton(
              key: ValueKey('${widget.keyPrefix}-repository-reload'),
              tooltip: 'Recharger les repositories',
              onPressed: available && !_loading ? _load : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_repository.isNotEmpty)
          TextFormField(
            key: ValueKey('${widget.keyPrefix}-repository-path'),
            controller: _path,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Chemin',
              hintText: widget.pathHint,
              errorText: _pathError,
              helperText:
                  widget.helper ??
                  (depth == 0
                      ? '[?] = ligne sélectionnée du tableau'
                      : 'Chaque [?] reçoit l’indice d’une liste englobante '
                            '($depth disponible(s)).'),
            ),
            validator: (_) => _pathError,
            onChanged: (_) {
              setState(() {});
              _emit();
            },
          ),
        if (!available)
          Text(
            'Service de repositories indisponible.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (_loading)
          Text(
            'Chargement des repositories…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (_loadError != null)
          Text(
            _loadError!,
            key: ValueKey('${widget.keyPrefix}-repository-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

/// Bouton d'icône permettant de créer ou modifier une liaison repository.
///
/// Lorsqu'une [binding] est active, le bouton est mis en évidence par un fond
/// coloré (`primaryContainer`), une bordure `primary`, l'icône `Icons.link`
/// ainsi qu'une pastille ([Badge]).
class RepositoryBindingIconButton extends StatelessWidget {
  const RepositoryBindingIconButton({
    required this.binding,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
    this.iconSize = 18,
    super.key,
  });

  final Key? buttonKey;
  final JsonTextBinding? binding;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBound = binding != null;
    final keyVal = buttonKey is ValueKey<String>
        ? (buttonKey! as ValueKey<String>).value
        : null;
    final effectiveTooltip = isBound
        ? '$tooltip (${binding!.path})'
        : tooltip;
    return IconButton(
      key: buttonKey,
      tooltip: effectiveTooltip,
      visualDensity: VisualDensity.compact,
      style: isBound
          ? IconButton.styleFrom(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.primary,
              side: BorderSide(color: scheme.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            )
          : null,
      onPressed: onPressed,
      icon: isBound
          ? Badge(
              key: keyVal != null ? ValueKey('$keyVal-badge') : null,
              backgroundColor: scheme.primary,
              smallSize: 7,
              child: Icon(
                Icons.link,
                size: iconSize,
                color: scheme.primary,
              ),
            )
          : Icon(Icons.add_link, size: iconSize),
    );
  }
}

/// Bandeau compact affichant le chemin de liaison actif (`Lié à : ...`)
/// avec possibilité de modifier ou supprimer rapidement la liaison.
class RepositoryBindingBanner extends StatelessWidget {
  const RepositoryBindingBanner({
    required this.binding,
    this.keyPrefix,
    this.onTap,
    this.onClear,
    super.key,
  });

  final JsonTextBinding binding;
  final String? keyPrefix;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: keyPrefix != null ? ValueKey('$keyPrefix-binding-banner') : null,
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.link, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Lié à : ${binding.path}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Supprimer la liaison',
                  child: InkWell(
                    key: keyPrefix != null
                        ? ValueKey('$keyPrefix-binding-clear')
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.link_off,
                        size: 14,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Enveloppe un champ de propriété avec son bouton de liaison et, lorsqu'une
/// liaison est active, un encadrement visuel coloré ainsi qu'un bandeau
/// affichant la cible de la liaison.
class RepositoryBoundPropertyTile extends StatelessWidget {
  const RepositoryBoundPropertyTile({
    required this.binding,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.buttonKey,
    this.keyPrefix,
    this.onClear,
    super.key,
  });

  final Key? buttonKey;
  final String? keyPrefix;
  final JsonTextBinding? binding;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onClear;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isBound = binding != null;
    final effectivePrefix =
        keyPrefix ??
        (buttonKey is ValueKey<String>
            ? (buttonKey! as ValueKey<String>).value
            : null);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: child),
        const SizedBox(width: 4),
        RepositoryBindingIconButton(
          buttonKey: buttonKey,
          binding: binding,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ],
    );
    if (!isBound) return row;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: effectivePrefix != null
          ? ValueKey('$effectivePrefix-bound-tile')
          : null,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            row,
            const SizedBox(height: 6),
            RepositoryBindingBanner(
              binding: binding!,
              keyPrefix: effectivePrefix,
              onTap: onPressed,
              onClear: onClear,
            ),
          ],
        ),
      ),
    );
  }
}

