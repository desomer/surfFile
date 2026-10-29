/// Fenêtre de réglage d'un `SuperTreeView`.
///
/// Ouverte par clic droit sur le composant puis *TreeView* (en mode édition).
/// Permet de choisir :
///
/// * le repository (un repository existant, « Hérité de la liste englobante »
///   ou « Sans liaison ») ;
/// * le chemin de l'arbre JSON (par exemple `nodes`, `categories` ou
///   `clients[?].categories`) ;
/// * la clé des nœuds enfants (par défaut `children`) ;
/// * la largeur initiale de la zone `Header`, la hauteur de ligne et
///   l'indentation ;
/// * l'état déplié par défaut, l'affichage des connecteurs et des cases à cocher.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../dialogs/editor_dialog.dart';
import '../repositories/repository_binding_fields.dart'
    show inheritedRepositoryValue;

/// Ouvre la fenêtre de réglage pour [config].
Future<SuperTreeViewConfig?> showSuperTreeViewEditor({
  required BuildContext context,
  required SuperTreeViewConfig config,
}) {
  final repositories = JsonRepositoryScope.maybeOf(context);
  final scope = JsonListScope.maybeOf(context);
  return showEditorDialog<SuperTreeViewConfig>(
    context: context,
    target: context,
    builder: (_) => _SuperTreeViewEditor(
      config: config,
      repositories: repositories,
      scope: scope,
    ),
  );
}

String formatSuperTreeViewTooltip({
  required String title,
  required SuperTreeViewConfig config,
}) {
  final binding = config.binding == null
      ? 'Aucune'
      : '${config.binding!.repositoryId ?? 'Hérité'} · ${config.binding!.path}';
  return [
    title,
    'Liaison : $binding',
    'Clé enfants : ${config.childrenKey}',
    'Largeur Header : ${config.headerSize.toStringAsFixed(0)} px',
    'Hauteur ligne : ${config.rowHeight.toStringAsFixed(0)} px',
    'Indentation : ${config.indent.toStringAsFixed(0)} px',
  ].join('\n');
}

class _SuperTreeViewEditor extends StatefulWidget {
  const _SuperTreeViewEditor({
    required this.config,
    required this.repositories,
    required this.scope,
  });

  final SuperTreeViewConfig config;
  final JsonRepositoryStore? repositories;
  final JsonListScope? scope;

  @override
  State<_SuperTreeViewEditor> createState() => _SuperTreeViewEditorState();
}

class _SuperTreeViewEditorState extends State<_SuperTreeViewEditor> {
  final _form = GlobalKey<FormState>();
  late final _path = TextEditingController(
    text: widget.config.binding?.path ?? '',
  );
  late final _childrenKey = TextEditingController(
    text: widget.config.childrenKey,
  );
  late final _headerSize = TextEditingController(
    text: _number(widget.config.headerSize),
  );
  late final _rowHeight = TextEditingController(
    text: _number(widget.config.rowHeight),
  );
  late final _indent = TextEditingController(
    text: _number(widget.config.indent),
  );
  late final _empty = TextEditingController(text: widget.config.emptyText);

  late String _repository = widget.config.binding == null
      ? ''
      : widget.config.binding!.repositoryId ?? inheritedRepositoryValue;
  late bool _initiallyExpanded = widget.config.initiallyExpanded;
  late bool _showConnectors = widget.config.showConnectors;
  late bool _showCheckboxes = widget.config.showCheckboxes;
  late bool _animateSelectionAndHover = widget.config.animateSelectionAndHover;
  List<JsonRepositoryEntry> _repositories = [];
  String? _error;
  bool _busy = false;

  static String _number(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  int get _depth => widget.scope?.indices.length ?? 0;

  @override
  void initState() {
    super.initState();
    _loadRepositories();
  }

  @override
  void dispose() {
    _path.dispose();
    _childrenKey.dispose();
    _headerSize.dispose();
    _rowHeight.dispose();
    _indent.dispose();
    _empty.dispose();
    super.dispose();
  }

  Future<void> _loadRepositories() async {
    final store = widget.repositories;
    if (store == null) return;
    try {
      final entries = await store.catalog();
      if (mounted) setState(() => _repositories = entries);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException {
      if (mounted) {
        setState(() => _error = 'Impossible de charger les repositories.');
      }
    }
  }

  JsonTextBinding? get _binding => _repository.isEmpty
      ? null
      : JsonTextBinding(
          repositoryId: _repository == inheritedRepositoryValue
              ? null
              : _repository,
          path: _path.text.trim(),
        );

  SuperTreeViewConfig _config() {
    double number(TextEditingController field) {
      final value = double.tryParse(field.text.trim().replaceAll(',', '.'));
      if (value == null) {
        throw const FormatException('Valeur numérique invalide.');
      }
      return value;
    }

    final binding = _binding;
    final result = widget.config.copyWith(
      binding: binding,
      clearBinding: binding == null,
      childrenKey: _childrenKey.text.trim(),
      headerSize: number(_headerSize),
      rowHeight: number(_rowHeight),
      indent: number(_indent),
      initiallyExpanded: _initiallyExpanded,
      showConnectors: _showConnectors,
      showCheckboxes: _showCheckboxes,
      animateSelectionAndHover: _animateSelectionAndHover,
      emptyText: _empty.text,
    );
    result.validate();
    return result;
  }

  Future<void> _apply() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = _config();
      final binding = config.binding;
      final scope = widget.scope;
      if (binding != null && !(scope?.placeholder ?? false)) {
        final store = widget.repositories;
        if (store == null) {
          throw const FormatException('Service de repositories indisponible.');
        }
        final resolved = JsonListScope.resolveSelected(
          binding,
          scope,
          store,
        ).binding;
        if (resolved != null) {
          await store.readTreeNodes(resolved.repositoryId!, resolved.path);
        }
      }
      if (mounted) Navigator.of(context).pop(config);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException {
      if (mounted) setState(() => _error = 'Impossible de lire le repository.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inheritable =
        widget.scope != null || _repository == inheritedRepositoryValue;
    final known =
        _repository.isEmpty ||
        _repository == inheritedRepositoryValue ||
        _repositories.any((entry) => entry.id == _repository);
    return AlertDialog(
      title: const Text('TreeView JSON'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                DropdownButtonFormField<String>(
                  key: const ValueKey('super-tree-repository'),
                  initialValue: _repository,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Repository'),
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
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _repository = value ?? ''),
                ),
                TextFormField(
                  key: const ValueKey('super-tree-path'),
                  controller: _path,
                  enabled: _repository.isNotEmpty && !_busy,
                  decoration: InputDecoration(
                    labelText: 'Chemin de l’arbre JSON',
                    hintText: _depth == 0 ? 'nodes' : 'clients[?].nodes',
                    helperText:
                        'Tableau ou objet JSON contenant les nœuds racines.',
                  ),
                  validator: (value) {
                    if (_repository.isEmpty) return null;
                    try {
                      JsonAttributePath(value?.trim() ?? '');
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                ),
                TextFormField(
                  key: const ValueKey('super-tree-children-key'),
                  controller: _childrenKey,
                  decoration: const InputDecoration(
                    labelText: 'Clé des nœuds enfants',
                    hintText: 'children',
                    helperText: 'Propriété JSON de chaque nœud contenant la liste de ses sous-nœuds.',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('super-tree-header-size'),
                        controller: _headerSize,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Largeur Header (px)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('super-tree-row-height'),
                        controller: _rowHeight,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Hauteur ligne (px)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('super-tree-indent'),
                        controller: _indent,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Indentation (px)',
                        ),
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  key: const ValueKey('super-tree-empty'),
                  controller: _empty,
                  decoration: const InputDecoration(
                    labelText: 'Texte si l’arbre est vide',
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('super-tree-initially-expanded'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Déplier les nœuds par défaut'),
                  value: _initiallyExpanded,
                  onChanged: (value) =>
                      setState(() => _initiallyExpanded = value),
                ),
                SwitchListTile(
                  key: const ValueKey('super-tree-show-connectors'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Afficher les traits de connexion'),
                  value: _showConnectors,
                  onChanged: (value) => setState(() => _showConnectors = value),
                ),
                SwitchListTile(
                  key: const ValueKey('super-tree-show-checkboxes'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Afficher les cases à cocher'),
                  value: _showCheckboxes,
                  onChanged: (value) => setState(() => _showCheckboxes = value),
                ),
                SwitchListTile(
                  key: const ValueKey('super-tree-animate-selection-hover'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Animer le déplacement de la sélection et du survol',
                  ),
                  value: _animateSelectionAndHover,
                  onChanged: (value) =>
                      setState(() => _animateSelectionAndHover = value),
                ),
                const Text(
                  'Chaque ligne expose 2 zones éditables : « Header » et '
                  '« Data ». Un SuperValue placé dans l’une de ces zones avec '
                  'le repository hérité et un chemin comme key, data ou '
                  'nodes[?].key lit et modifie la valeur du nœud courant.',
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    _error!,
                    key: const ValueKey('super-tree-editor-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('super-tree-apply'),
          onPressed: _busy ? null : _apply,
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}
