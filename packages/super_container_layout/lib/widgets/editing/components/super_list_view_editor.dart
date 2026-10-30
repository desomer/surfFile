/// Fenêtre de réglage « Liste JSON » d'une `SuperListView`.
///
/// Ouverte par clic droit sur la liste puis *Liste* (en mode édition). Elle
/// permet de choisir :
///
/// * le repository : un repository existant, « Hérité de la liste
///   englobante » (uniquement dans une autre liste) ou « Sans liaison » ;
/// * le chemin du tableau, par exemple `clients`, `clients[0].commandes` ou
///   `clients[?].commandes` (`[?]` = ligne de la liste englobante, sinon
///   ligne sélectionnée) ;
/// * l'orientation, la taille des lignes, l'espacement, les boutons
///   *Ajouter* / *Supprimer* et le message de liste vide.
///
/// À l'application, le tableau est lu pour vérifier qu'il existe, sauf dans
/// une ligne de gabarit ou si aucune ligne parente n'est sélectionnée.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/super_list_view_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../repositories/repository_binding_fields.dart'
    show inheritedRepositoryValue;
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_tabbed_wizard.dart';

/// Valeur de la liste déroulante pour « Hérité de la liste englobante ».
/// Ouvre la fenêtre de réglage pour [config].
///
/// Le repository et la ligne englobante sont lus depuis [context]
/// (`JsonRepositoryScope`, `JsonListScope`). Retourne la nouvelle
/// configuration, ou `null` si l'utilisateur annule.
Future<SuperListViewConfig?> showSuperListViewEditor({
  required BuildContext context,
  required SuperListViewConfig config,
}) {
  final repositories = JsonRepositoryScope.maybeOf(context);
  final scope = JsonListScope.maybeOf(context);
  return runWithDimensionDelegate<SuperListViewConfig>(
    context: context,
    runner: (initialTab, dimensionDelegate) =>
        showEditorDialog<SuperListViewConfig>(
          context: context,
          target: context,
          builder: (_) => _SuperListViewEditor(
            initialTab: initialTab,
            dimensionDelegate: dimensionDelegate,
            config: config,
            repositories: repositories,
            scope: scope,
          ),
        ),
  );
}

class _SuperListViewEditor extends StatefulWidget {
  const _SuperListViewEditor({
    required this.initialTab,
    required this.dimensionDelegate,
    required this.config,
    required this.repositories,
    required this.scope,
  });

  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;
  final SuperListViewConfig config;
  final JsonRepositoryStore? repositories;
  final JsonListScope? scope;

  @override
  State<_SuperListViewEditor> createState() => _SuperListViewEditorState();
}

class _SuperListViewEditorState extends State<_SuperListViewEditor> {
  final _form = GlobalKey<FormState>();
  late final _path = TextEditingController(
    text: widget.config.binding?.path ?? '',
  );
  late final _spacing = TextEditingController(
    text: _number(widget.config.spacing),
  );
  late final _empty = TextEditingController(text: widget.config.emptyText);
  late String _repository = widget.config.binding == null
      ? ''
      : widget.config.binding!.repositoryId ?? inheritedRepositoryValue;
  late Axis _axis = widget.config.axis;
  late bool _wrap = widget.config.wrap;
  late bool _allowAdd = widget.config.allowAdd;
  late bool _allowRemove = widget.config.allowRemove;
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
    _spacing.dispose();
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

  SuperListViewConfig _config() {
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
      axis: _axis,
      wrap: _wrap,
      spacing: number(_spacing),
      allowAdd: _allowAdd,
      allowRemove: _allowRemove,
      emptyText: _empty.text,
    );
    result.validate();
    return result;
  }

  Future<bool> _apply() async {
    if (!(_form.currentState?.validate() ?? true)) return false;
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
        // Sans ligne parente sélectionnée, seul le chemin est vérifié.
        if (resolved != null) {
          await store.readArray(resolved.repositoryId!, resolved.path);
        }
      }
      if (mounted) Navigator.of(context).pop(config);
      return true;
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    } on FileSystemException {
      if (mounted) setState(() => _error = 'Impossible de lire le repository.');
      return false;
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
    return EditorTabbedAlertDialog(
      applyButtonKey: const ValueKey('super-list-apply'),
      initialTab: widget.initialTab,
      dimensionDelegate: widget.dimensionDelegate,
      propertiesTitle: const Text('Liste JSON'),
      propertiesWidth: 420,
      busy: _busy,
      onApply: _apply,
      onCancel: () => Navigator.of(context).pop(),
      propertiesContentBuilder: (context) => Form(
        key: _form,
        child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                DropdownButtonFormField<String>(
                  key: const ValueKey('super-list-repository'),
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
                  key: const ValueKey('super-list-path'),
                  controller: _path,
                  enabled: _repository.isNotEmpty && !_busy,
                  decoration: InputDecoration(
                    labelText: 'Chemin du tableau',
                    hintText: _depth == 0 ? 'clients' : 'clients[?].commandes',
                    helperText: _depth == 0
                        ? '[?] = ligne sélectionnée du tableau parent'
                        : 'Chaque [?] reçoit l’indice d’une liste englobante '
                              '($_depth disponible(s)), puis la ligne '
                              'sélectionnée.',
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
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'vertical',
                      tooltip: 'Verticale',
                      label: Text('Verticale'),
                      icon: Icon(Icons.view_agenda_outlined),
                    ),
                    ButtonSegment(
                      value: 'horizontal',
                      tooltip: 'Horizontale',
                      label: Text('Horizontale'),
                      icon: Icon(Icons.view_week_outlined),
                    ),
                    ButtonSegment(
                      value: 'wrap',
                      tooltip: 'Wrap',
                      label: Text('Wrap'),
                      icon: Icon(Icons.wrap_text),
                    ),
                  ],
                  selected: {_wrap ? 'wrap' : _axis.name},
                  onSelectionChanged: (value) => setState(() {
                    _wrap = value.single == 'wrap';
                    if (!_wrap) {
                      _axis = value.single == 'vertical'
                          ? Axis.vertical
                          : Axis.horizontal;
                    }
                  }),
                ),
                const Text(
                  'Les dimensions se règlent avec « Taille et marge » '
                  'sur l’entrée de style IterableContent du menu contextuel. '
                  'Laissez une dimension préférée vide pour une taille automatique.',
                ),
                TextFormField(
                  key: const ValueKey('super-list-spacing'),
                  controller: _spacing,
                  decoration: const InputDecoration(labelText: 'Espacement'),
                ),
                TextFormField(
                  key: const ValueKey('super-list-empty'),
                  controller: _empty,
                  decoration: const InputDecoration(
                    labelText: 'Texte si le tableau est vide',
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('super-list-allow-add'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoriser l’ajout d’éléments'),
                  value: _allowAdd,
                  onChanged: (value) => setState(() => _allowAdd = value),
                ),
                SwitchListTile(
                  key: const ValueKey('super-list-allow-remove'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoriser la suppression d’éléments'),
                  value: _allowRemove,
                  onChanged: (value) => setState(() => _allowRemove = value),
                ),
                const Text(
                  'Chaque ligne répète la disposition modèle de la liste. Dans '
                  'cette disposition, un texte lié à clients[?].nom affiche '
                  'le nom de l’élément de sa ligne.',
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    _error!,
                    key: const ValueKey('super-list-editor-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
      ),
    );
  }
}
