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

import '../../../models/json_text_binding.dart';
import '../../../models/super_table_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../repositories/repository_binding_fields.dart'
    show inheritedRepositoryValue;

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

class _ColumnDraft {
  _ColumnDraft({
    required this.id,
    required String title,
    required double width,
    double fillPercent = SuperTableColumnConfig.defaultFillPercent,
  }) : title = TextEditingController(text: title),
       width = TextEditingController(
         text: width == width.roundToDouble() ? '${width.toInt()}' : '$width',
       ),
       fillPercent = TextEditingController(
         text: fillPercent == fillPercent.roundToDouble()
             ? '${fillPercent.toInt()}'
             : '$fillPercent',
       );

  final String id;
  final TextEditingController title;
  final TextEditingController width;
  final TextEditingController fillPercent;

  bool get hasFill {
    final val = double.tryParse(fillPercent.text.trim().replaceAll(',', '.'));
    return val != null && val > 0;
  }

  void dispose() {
    title.dispose();
    width.dispose();
    fillPercent.dispose();
  }
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
    text: _number(widget.config.headerRowHeight),
  );
  late final _rowHeight = TextEditingController(
    text: _number(widget.config.rowHeight),
  );
  late final _bottomHeight = TextEditingController(
    text: _number(widget.config.bottomRowHeight),
  );
  late final _empty = TextEditingController(text: widget.config.emptyText);
  late final List<_ColumnDraft> _columns = [
    for (final col in widget.config.columns)
      _ColumnDraft(
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

  void _addColumn() {
    final used = {for (final col in _columns) col.id};
    var index = _columns.length;
    while (used.contains('col_$index')) {
      index++;
    }
    setState(() {
      _columns.add(
        _ColumnDraft(
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

  JsonTextBinding? get _binding => _repository.isEmpty
      ? null
      : JsonTextBinding(
          repositoryId: _repository == inheritedRepositoryValue
              ? null
              : _repository,
          path: _path.text.trim(),
        );

  SuperTableConfig _config() {
    double number(TextEditingController field) {
      final value = double.tryParse(field.text.trim().replaceAll(',', '.'));
      if (value == null) {
        throw const FormatException('Valeur numérique invalide.');
      }
      return value;
    }

    final freeze = int.tryParse(_freezeCount.text.trim());
    if (freeze == null) {
      throw const FormatException(
        'Nombre de colonnes figées à gauche invalide.',
      );
    }

    final columns = [
      for (final col in _columns)
        SuperTableColumnConfig(
          id: col.id,
          title: col.title.text.trim(),
          width: number(col.width),
          fillPercent: col.fillPercent.text.trim().isEmpty
              ? 0.0
              : number(col.fillPercent),
        ),
    ];

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

    final binding = _binding;
    final result = widget.config.copyWith(
      binding: binding,
      clearBinding: binding == null,
      columns: columns,
      colFreezeLeftCount: freeze,
      showHeaderRow: _showHeaderRow,
      showBottomRow: _showBottomRow,
      headerRowHeight: number(_headerHeight),
      rowHeight: number(_rowHeight),
      bottomRowHeight: number(_bottomHeight),
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
                DropdownButtonFormField<String>(
                  key: const ValueKey('super-table-repository'),
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
                  key: const ValueKey('super-table-path'),
                  controller: _path,
                  enabled: _repository.isNotEmpty && !_busy,
                  decoration: InputDecoration(
                    labelText: 'Chemin du tableau JSON',
                    hintText: _depth == 0 ? 'clients' : 'clients[?].commandes',
                    helperText:
                        'Tableau JSON dont chaque élément devient une ligne.',
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Colonnes (${_columns.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('super-table-add-column'),
                      onPressed: _busy ? null : _addColumn,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Ajouter une colonne'),
                    ),
                  ],
                ),
                for (var i = 0; i < _columns.length; i++)
                  Row(
                    key: ValueKey('super-table-col-row-${_columns[i].id}'),
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          key: ValueKey(
                            'super-table-col-title-${_columns[i].id}',
                          ),
                          controller: _columns[i].title,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Titre (${_columns[i].id})',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _columns[i].fillPercent,
                          builder: (context, _, _) => TextFormField(
                            key: ValueKey(
                              'super-table-col-width-${_columns[i].id}',
                            ),
                            controller: _columns[i].width,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: _columns[i].hasFill
                                  ? 'Largeur min (px)'
                                  : 'Largeur (px)',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey(
                            'super-table-col-fill-${_columns[i].id}',
                          ),
                          controller: _columns[i].fillPercent,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Reste (%)',
                            suffixText: '%',
                          ),
                        ),
                      ),
                      IconButton(
                        key: ValueKey(
                          'super-table-col-delete-${_columns[i].id}',
                        ),
                        tooltip: 'Supprimer la colonne',
                        onPressed: _columns.length <= 1 || _busy
                            ? null
                            : () => _removeColumn(i),
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
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
                      child: SwitchListTile(
                        key: const ValueKey('super-table-show-header'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ligne d’en-tête'),
                        value: _showHeaderRow,
                        onChanged: (value) =>
                            setState(() => _showHeaderRow = value),
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
                      child: SwitchListTile(
                        key: const ValueKey('super-table-show-bottom'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ligne de pied figée'),
                        value: _showBottomRow,
                        onChanged: (value) =>
                            setState(() => _showBottomRow = value),
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
                SwitchListTile(
                  key: const ValueKey('super-table-allow-add'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoriser l’ajout d’éléments'),
                  value: _allowAdd,
                  onChanged: (value) => setState(() => _allowAdd = value),
                ),
                SwitchListTile(
                  key: const ValueKey('super-table-allow-remove'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoriser la suppression d’éléments'),
                  value: _allowRemove,
                  onChanged: (value) => setState(() => _allowRemove = value),
                ),
                SwitchListTile(
                  key: const ValueKey('super-table-animate-selection-hover'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Animer le déplacement de la sélection et du survol',
                  ),
                  value: _animateSelectionAndHover,
                  onChanged: (value) =>
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
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    _error!,
                    key: const ValueKey('super-table-editor-error'),
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
