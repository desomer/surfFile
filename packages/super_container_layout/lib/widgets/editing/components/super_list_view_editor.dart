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

import '../../../models/scrollbar_style_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../repositories/repository_binding_fields.dart'
    show inheritedRepositoryValue;
import '../styles/scrollbar_style_editor.dart';
import 'shared/collection_editor_controls.dart';

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
    text: formatCollectionEditorNumber(widget.config.spacing),
  );
  late final _empty = TextEditingController(text: widget.config.emptyText);
  late String _repository = widget.config.binding == null
      ? ''
      : widget.config.binding!.repositoryId ?? inheritedRepositoryValue;
  late Axis _axis = widget.config.axis;
  late bool _wrap = widget.config.wrap;
  late bool _allowAdd = widget.config.allowAdd;
  late bool _allowRemove = widget.config.allowRemove;
  late bool _showScrollbar = widget.config.showScrollbar;
  late ScrollbarStyleConfig _scrollbarStyle = widget.config.scrollbarStyle;
  late bool _animateSelectionAndHover = widget.config.animateSelectionAndHover;
  String? _error;
  bool _busy = false;

  int get _depth => widget.scope?.indices.length ?? 0;

  @override
  void dispose() {
    _path.dispose();
    _spacing.dispose();
    _empty.dispose();
    super.dispose();
  }

  SuperListViewConfig _config() {
    final binding = buildCollectionEditorBinding(_repository, _path.text);
    return widget.config.copyWith(
      binding: binding,
      clearBinding: binding == null,
      axis: _axis,
      wrap: _wrap,
      spacing: parseCollectionEditorNumber(_spacing),
      allowAdd: _allowAdd,
      allowRemove: _allowRemove,
      showScrollbar: _showScrollbar,
      scrollbarStyle: _scrollbarStyle,
      animateSelectionAndHover: _animateSelectionAndHover,
      emptyText: _empty.text,
    )..validate();
  }

  Future<bool> _apply() async {
    if (!(_form.currentState?.validate() ?? true)) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = _config();
      await verifyCollectionBindingTarget(
        binding: config.binding,
        scope: widget.scope,
        store: widget.repositories,
        readTarget: (store, repoId, path) => store.readArray(repoId, path),
      );
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
  Widget build(BuildContext context) => EditorTabbedAlertDialog(
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
          CollectionRepositorySourceFields(
            keyPrefix: 'super-list',
            repositories: widget.repositories,
            scope: widget.scope,
            repository: _repository,
            pathController: _path,
            pathLabel: 'Chemin du tableau',
            rootHint: 'clients',
            nestedHint: 'clients[?].commandes',
            helperText: _depth == 0
                ? '[?] = ligne sélectionnée du tableau parent'
                : 'Chaque [?] reçoit l’indice d’une liste englobante '
                      '($_depth disponible(s)), puis la ligne '
                      'sélectionnée.',
            busy: _busy,
            onRepositoryChanged: (value) => setState(() => _repository = value),
            onLoadError: (msg) => setState(() => _error = msg),
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
          SwitchListTile(
            key: const ValueKey('super-list-animate-selection-hover'),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Animer le déplacement de la sélection et du survol',
            ),
            value: _animateSelectionAndHover,
            onChanged: (value) =>
                setState(() => _animateSelectionAndHover = value),
          ),
          SwitchListTile(
            key: const ValueKey('super-list-show-scrollbar'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Afficher la barre de défilement (ScrollBar)'),
            value: _showScrollbar,
            onChanged: (value) => setState(() => _showScrollbar = value),
          ),
          if (_showScrollbar)
            ListTile(
              key: const ValueKey('super-list-scrollbar-style'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.palette_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Style de la barre de défilement'),
              subtitle: Text(
                _scrollbarStyle.summary,
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_scrollbarStyle.isDefault)
                    IconButton(
                      key: const ValueKey('super-list-scrollbar-style-reset'),
                      tooltip: 'Style par défaut',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      onPressed: () => setState(
                        () => _scrollbarStyle = const ScrollbarStyleConfig(),
                      ),
                    ),
                  const Icon(Icons.tune, size: 18),
                ],
              ),
              onTap: () => showScrollbarStyleEditor(
                context: context,
                axis: _wrap ? Axis.vertical : _axis,
                keyPrefix: 'super-list-scrollbar-editor',
                initialValue: _scrollbarStyle,
                onChanged: (nextStyle) =>
                    setState(() => _scrollbarStyle = nextStyle),
              ),
            ),
          const Text(
            'Chaque ligne répète la disposition modèle de la liste. Dans '
            'cette disposition, un texte lié à clients[?].nom affiche '
            'le nom de l’élément de sa ligne.',
          ),
          ...buildCollectionEditorStatusWidgets(
            context: context,
            keyPrefix: 'super-list',
            busy: _busy,
            error: _error,
          ),
        ],
      ),
    ),
  );
}
