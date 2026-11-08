/// Fenêtre de réglage d'une `SuperTable`.
///
/// Ouverte par clic droit sur le composant puis *Table* (en mode édition).
/// Permet de choisir :
///
/// * le repository (un repository existant, « Hérité de la liste englobante »
///   ou « Sans liaison ») ;
/// * le chemin du tableau JSON (par exemple `clients` ou
///   `clients[?].commandes`) ;
/// * les colonnes du tableau (ajout, suppression, titre et largeur) ;
/// * le nombre de colonnes figées à gauche ;
/// * l'affichage et la hauteur de l'en-tête, des lignes de données et du pied ;
/// * les boutons *Ajouter* / *Supprimer* et le message de tableau vide.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../models/super_table_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../repositories/repository_binding_fields.dart'
    show inheritedRepositoryValue;
import 'shared/collection_editor_controls.dart';
import 'shared/editor_segmented_field.dart';

/// Ouvre la fenêtre de réglage pour [config].
Future<SuperTableConfig?> showSuperTableEditor({
  required BuildContext context,
  required SuperTableConfig config,
}) {
  final repositories = JsonRepositoryScope.maybeOf(context);
  final scope = JsonListScope.maybeOf(context);
  return runWithDimensionDelegate<SuperTableConfig>(
    context: context,
    runner: (initialTab, dimensionDelegate) =>
        showEditorDialog<SuperTableConfig>(
          context: context,
          target: context,
          builder: (_) => _SuperTableEditor(
            initialTab: initialTab,
            dimensionDelegate: dimensionDelegate,
            config: config,
            repositories: repositories,
            scope: scope,
          ),
        ),
  );
}

String formatSuperTableTooltip({
  required String title,
  required SuperTableConfig config,
}) {
  final binding = config.binding == null
      ? 'Aucune'
      : '${config.binding!.repositoryId ?? 'Hérité'} · ${config.binding!.path}';
  return [
    title,
    'Liaison : $binding',
    'Colonnes : ${config.columns.length} (figées : ${config.colFreezeLeftCount})',
    'Hauteur ligne : ${config.rowHeight.toStringAsFixed(0)} px',
    if (config.showHeaderRow)
      'En-tête : ${config.headerRowHeight.toStringAsFixed(0)} px',
    if (config.showBottomRow)
      'Pied : ${config.bottomRowHeight.toStringAsFixed(0)} px',
  ].join('\n');
}

class _SuperTableEditor extends StatefulWidget {
  const _SuperTableEditor({
    required this.initialTab,
    required this.dimensionDelegate,
    required this.config,
    required this.repositories,
    required this.scope,
  });

  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;
  final SuperTableConfig config;
  final JsonRepositoryStore? repositories;
  final JsonListScope? scope;

  @override
  State<_SuperTableEditor> createState() => _SuperTableEditorState();
}

class _SuperTableEditorState extends State<_SuperTableEditor> {
  final _form = GlobalKey<FormState>();
  late final _path = TextEditingController(
    text: widget.config.binding?.path ?? '',
  );
  late final _freezeCount = TextEditingController(
    text: '${widget.config.colFreezeLeftCount}',
  );
  late final _headerHeight = TextEditingController(
    text: formatCollectionEditorNumber(widget.config.headerRowHeight),
  );
  late final _rowHeight = TextEditingController(
    text: formatCollectionEditorNumber(widget.config.rowHeight),
  );
  late final _bottomHeight = TextEditingController(
    text: formatCollectionEditorNumber(widget.config.bottomRowHeight),
  );
  late final _empty = TextEditingController(text: widget.config.emptyText);
  late final List<SuperTableColumnDraft> _columns = [
    for (final col in widget.config.columns)
      SuperTableColumnDraft(
        id: col.id,
        title: col.title,
        width: col.width,
        fillPercent: col.fillPercent,
      ),
  ];

  late String _repository = widget.config.binding == null
      ? ''
      : widget.config.binding!.repositoryId ?? inheritedRepositoryValue;
  late bool _showHeaderRow = widget.config.showHeaderRow;
  late bool _showBottomRow = widget.config.showBottomRow;
  late bool _allowAdd = widget.config.allowAdd;
  late bool _allowRemove = widget.config.allowRemove;
  late bool _animateSelectionAndHover = widget.config.animateSelectionAndHover;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _path.dispose();
    _freezeCount.dispose();
    _headerHeight.dispose();
    _rowHeight.dispose();
    _bottomHeight.dispose();
    _empty.dispose();
    for (final col in _columns) {
      col.dispose();
    }
    super.dispose();
  }

  void _addColumn() {
    final used = {for (final col in _columns) col.id};
    var index = _columns.length;
    while (used.contains('col_$index')) {
      index++;
    }
    setState(() {
      _columns.add(
        SuperTableColumnDraft(
          id: 'col_$index',
          title: 'Colonne ${_columns.length + 1}',
          width: SuperTableColumnConfig.defaultWidth,
        ),
      );
    });
  }

  void _removeColumn(int index) {
    if (_columns.length <= 1) return;
    setState(() {
      final removed = _columns.removeAt(index);
      removed.dispose();
    });
  }

  SuperTableConfig _config() {
    final freeze = int.tryParse(_freezeCount.text.trim());
    if (freeze == null) {
      throw const FormatException(
        'Nombre de colonnes figées à gauche invalide.',
      );
    }

    final columns = [for (final col in _columns) col.toConfig()];
    final keptColumnIds = {for (final col in columns) col.id};
    final validZones = {
      for (final id in keptColumnIds) ...[
        SuperTableConfig.headerZoneFor(id),
        SuperTableConfig.cellZoneFor(id),
        SuperTableConfig.bottomZoneFor(id),
      ],
    };

    final nextPlacements = <String, List<String>>{
      for (final entry in widget.config.placements.entries)
        if (validZones.contains(entry.key)) entry.key: entry.value,
    };
    final keptSlots = nextPlacements.values.expand((ids) => ids).toSet();

    final binding = buildCollectionEditorBinding(_repository, _path.text);
    return widget.config.copyWith(
      binding: binding,
      clearBinding: binding == null,
      columns: columns,
      colFreezeLeftCount: freeze,
      showHeaderRow: _showHeaderRow,
      showBottomRow: _showBottomRow,
      headerRowHeight: parseCollectionEditorNumber(_headerHeight),
      rowHeight: parseCollectionEditorNumber(_rowHeight),
      bottomRowHeight: parseCollectionEditorNumber(_bottomHeight),
      allowAdd: _allowAdd,
      allowRemove: _allowRemove,
      animateSelectionAndHover: _animateSelectionAndHover,
      emptyText: _empty.text,
      placements: nextPlacements,
      slotTypes: {
        for (final entry in widget.config.slotTypes.entries)
          if (keptSlots.contains(entry.key)) entry.key: entry.value,
      },
      zoneAxes: {
        for (final entry in widget.config.zoneAxes.entries)
          if (validZones.contains(entry.key)) entry.key: entry.value,
      },
      zoneFlows: {
        for (final entry in widget.config.zoneFlows.entries)
          if (validZones.contains(entry.key)) entry.key: entry.value,
      },
      zoneStyles: {
        for (final entry in widget.config.zoneStyles.entries)
          if (validZones.contains(entry.key)) entry.key: entry.value,
      },
      slotPreferredSizes: {
        for (final entry in widget.config.slotPreferredSizes.entries)
          if (keptSlots.contains(entry.key)) entry.key: entry.value,
      },
      slotSizeConstraints: {
        for (final entry in widget.config.slotSizeConstraints.entries)
          if (keptSlots.contains(entry.key)) entry.key: entry.value,
      },
      slotLabels: {
        for (final entry in widget.config.slotLabels.entries)
          if (keptSlots.contains(entry.key)) entry.key: entry.value,
      },
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
    applyButtonKey: const ValueKey('super-table-apply'),
    initialTab: widget.initialTab,
    dimensionDelegate: widget.dimensionDelegate,
    propertiesTitle: const Text('Table JSON'),
    propertiesWidth: 520,
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
            keyPrefix: 'super-table',
            repositories: widget.repositories,
            scope: widget.scope,
            repository: _repository,
            pathController: _path,
            pathLabel: 'Chemin du tableau JSON',
            rootHint: 'clients',
            nestedHint: 'clients[?].commandes',
            helperText:
                'Tableau JSON dont chaque élément devient une ligne.',
            busy: _busy,
            onRepositoryChanged: (value) => setState(() => _repository = value),
            onLoadError: (msg) => setState(() => _error = msg),
          ),
          SuperTableColumnsEditor(
            columns: _columns,
            busy: _busy,
            onAddColumn: _addColumn,
            onRemoveColumn: _removeColumn,
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('super-table-freeze-left'),
                  controller: _freezeCount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Colonnes figées à gauche',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('super-table-row-height'),
                  controller: _rowHeight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Hauteur ligne (px)',
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: EditorSwitchTile(
                  tileKey: const ValueKey('super-table-show-header'),
                  title: 'Ligne d’en-tête',
                  value: _showHeaderRow,
                  onChanged: (value) => setState(() => _showHeaderRow = value),
                ),
              ),
              if (_showHeaderRow) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    key: const ValueKey('super-table-header-height'),
                    controller: _headerHeight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Hauteur en-tête (px)',
                    ),
                  ),
                ),
              ],
            ],
          ),
          Row(
            children: [
              Expanded(
                child: EditorSwitchTile(
                  tileKey: const ValueKey('super-table-show-bottom'),
                  title: 'Ligne de pied figée',
                  value: _showBottomRow,
                  onChanged: (value) => setState(() => _showBottomRow = value),
                ),
              ),
              if (_showBottomRow) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    key: const ValueKey('super-table-bottom-height'),
                    controller: _bottomHeight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Hauteur pied (px)',
                    ),
                  ),
                ),
              ],
            ],
          ),
          ...buildCollectionMutationSwitches(
            keyPrefix: 'super-table',
            allowAdd: _allowAdd,
            onAllowAddChanged: (value) => setState(() => _allowAdd = value),
            allowRemove: _allowRemove,
            onAllowRemoveChanged: (value) =>
                setState(() => _allowRemove = value),
            animateSelectionAndHover: _animateSelectionAndHover,
            onAnimateSelectionAndHoverChanged: (value) =>
                setState(() => _animateSelectionAndHover = value),
          ),
          TextFormField(
            key: const ValueKey('super-table-empty'),
            controller: _empty,
            decoration: const InputDecoration(
              labelText: 'Texte si le tableau est vide',
            ),
          ),
          const Text(
            'Chaque colonne expose une zone éditable de cellule (et '
            'optionnellement d’en-tête / de pied). Un SuperValue placé '
            'dans une colonne avec le repository hérité et un chemin '
            'comme nom ou clients[?].nom lit et modifie la ligne courante.',
          ),
          ...buildCollectionEditorStatusWidgets(
            context: context,
            keyPrefix: 'super-table',
            busy: _busy,
            error: _error,
          ),
        ],
      ),
    ),
  );
}
