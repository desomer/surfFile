/// Arbre `SuperTreeView` des champs Input / Output d'un Use Case aligné sur
/// le rendu de l'onglet « Objet » des objets métiers ([UseCaseFieldsObjectTree]).
library;

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/usecase_orchestration_spec.dart';
import '../workspace/business_objects/business_object_tree_models.dart';

/// Affiche une liste de [UseCaseFieldSpec] avec le même rendu arbre
/// (`SuperTreeView`, icônes typées `visualForBusinessObjectNode`, marqueur `*`
/// obligatoire, étiquette de type et barre de détail au clic) que l'onglet
/// « Objet » des objets métiers.
class UseCaseFieldsObjectTree extends StatefulWidget {
  /// Crée un arbre pour les champs [fields].
  const UseCaseFieldsObjectTree({
    required this.treeId,
    required this.fields,
    super.key,
  });

  /// Identifiant unique de l'instance `SuperTreeView`.
  final String treeId;

  /// Champs racines (Input ou Output) à afficher.
  final List<UseCaseFieldSpec> fields;

  @override
  State<UseCaseFieldsObjectTree> createState() =>
      _UseCaseFieldsObjectTreeState();
}

class _UseCaseFieldsObjectTreeState extends State<UseCaseFieldsObjectTree> {
  static const String _repo = 'usecase_fields';

  final JsonRepositoryStore _store = JsonRepositoryStore(Directory.systemTemp);
  final TextEditingController _filterCtrl = TextEditingController();
  final Map<String, BusinessObjectTreeSelectionTarget> _targets = {};
  final Map<String, UseCaseFieldSpec> _fieldsByNodePath = {};

  bool _registered = false;
  bool _showFilterBar = false;
  String _filter = '';
  String? _selectedNodePath;
  List<UseCaseFieldSpec>? _syncedFields;
  String? _syncedFilter;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(UseCaseFieldsObjectTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    _store.dispose();
    super.dispose();
  }

  void _sync() {
    if (identical(_syncedFields, widget.fields) && _syncedFilter == _filter) {
      return;
    }
    _syncedFields = widget.fields;
    _syncedFilter = _filter;

    _targets.clear();
    _fieldsByNodePath.clear();

    final nodes = _buildNodes(widget.fields, _filter.trim().toLowerCase());
    void index(Map<String, Object?> node, String nodePath) {
      final field = node['_field'] as UseCaseFieldSpec?;
      if (field != null) {
        _fieldsByNodePath[nodePath] = field;
      }
      _targets[nodePath] = BusinessObjectTreeSelectionTarget(
        nodePath: nodePath,
        objectId: widget.treeId,
        relationId: '',
        attributePath: const <String>[],
        isRootObject: false,
        isRelation: false,
        isArray: node['isArray'] == true,
        isRequired: node['isRequired'] == true,
        attrType: (node['attrType'] as String?) ?? '',
        totalAttributes: 0,
        estimatedMaxRows: null,
        typeIcon: (node['typeIcon'] as String?) ?? 'value',
        displayType: (node['displayType'] as String?) ?? '',
      );
      if (node['children'] case final List children) {
        for (var i = 0; i < children.length; i++) {
          final child = children[i];
          if (child is Map<String, Object?>) {
            index(child, '$nodePath.children[$i]');
          }
        }
      }
    }

    for (var i = 0; i < nodes.length; i++) {
      index(nodes[i], 'nodes[$i]');
    }

    if (_selectedNodePath != null &&
        !_fieldsByNodePath.containsKey(_selectedNodePath)) {
      _selectedNodePath = null;
    }

    final cleanNodes = [for (final n in nodes) _stripInternalField(n)];

    if (_registered) {
      unawaited(_store.replaceArray(_repo, 'nodes', cleanNodes));
    } else {
      _store.registerRepository(
        RepositoryImpl(id: _repo, json: {'nodes': cleanNodes}),
      );
      _registered = true;
    }
  }

  static Map<String, Object?> _stripInternalField(Map<String, Object?> node) {
    final copy = <String, Object?>{
      for (final entry in node.entries)
        if (entry.key != '_field') entry.key: entry.value,
    };
    if (copy['children'] case final List children) {
      copy['children'] = [
        for (final c in children)
          if (c is Map<String, Object?>) _stripInternalField(c),
      ];
    }
    return copy;
  }

  List<Map<String, Object?>> _buildNodes(
    List<UseCaseFieldSpec> fields,
    String query,
  ) {
    final out = <Map<String, Object?>>[];
    for (final field in fields) {
      final childNodes = _buildNodes(field.children, query);
      final info = _describeField(field);
      final selfMatch =
          query.isEmpty ||
          field.name.toLowerCase().contains(query) ||
          field.type.toLowerCase().contains(query) ||
          field.constraints.toLowerCase().contains(query) ||
          field.description.toLowerCase().contains(query) ||
          info.displayType.toLowerCase().contains(query);
      if (!selfMatch && childNodes.isEmpty) continue;

      final childrenToUse =
          query.isNotEmpty && selfMatch && childNodes.isEmpty
          ? _buildNodes(field.children, '')
          : childNodes;

      out.add({
        '_field': field,
        'displayName': field.name,
        'displayType': info.displayType,
        'attrType': info.attrType,
        'isArray': info.isArray,
        'isRequired': info.isRequired,
        'isNullable': field.nullable,
        'typeIcon': info.isContainer ? 'container' : 'value',
        if (childrenToUse.isNotEmpty) 'children': childrenToUse,
      });
    }
    return out;
  }

  static ({
    String attrType,
    bool isArray,
    bool isRequired,
    bool isContainer,
    String displayType,
  })
  _describeField(UseCaseFieldSpec field) {
    var baseType = field.type.trim();
    var isArray = field.effectiveIsArray;
    if (baseType.endsWith('[]')) {
      baseType = baseType.substring(0, baseType.length - 2).trim();
    } else {
      final listMatch = RegExp(
        r'^(?:list|array)<(.+)>$',
        caseSensitive: false,
      ).firstMatch(baseType);
      if (listMatch != null) {
        baseType = listMatch.group(1)!.trim();
      }
    }

    final lower = baseType.toLowerCase();
    final isContainer =
        field.children.isNotEmpty || lower == 'object' || lower == 'map';
    final String attrType;
    if (isContainer) {
      attrType = 'object';
    } else if (field.enumValues.isNotEmpty ||
        lower == 'enum' ||
        lower == 'enumeration') {
      attrType = 'enumeration';
    } else if (lower.contains('uuid')) {
      attrType = 'uuid';
    } else if (lower == 'int' || lower == 'integer') {
      attrType = 'integer';
    } else if (lower == 'number' ||
        lower == 'double' ||
        lower == 'float' ||
        lower == 'decimal') {
      attrType = 'number';
    } else if (lower == 'bool' || lower == 'boolean') {
      attrType = 'boolean';
    } else if (lower == 'datetime' || lower == 'timestamp') {
      attrType = 'datetime';
    } else if (lower == 'date') {
      attrType = 'date';
    } else if (lower == 'email') {
      attrType = 'email';
    } else if (lower == 'url' || lower == 'uri') {
      attrType = 'url';
    } else if (lower == 'reference' ||
        (baseType.isNotEmpty &&
            RegExp(r'^[A-Z][A-Za-z0-9_]*$').hasMatch(baseType))) {
      attrType = 'reference';
    } else {
      attrType = 'string';
    }

    final isRequired = field.effectiveRequired;
    final buf = StringBuffer()
      ..write(baseType.isEmpty ? 'string' : baseType);
    if (isArray) buf.write('[]');
    if (isRequired) buf.write('!');
    if (field.nullable) buf.write('?');
    if (field.enumValues.isNotEmpty) {
      buf.write(' (${field.enumValues.join(', ')})');
    }
    if (field.constraints.trim().isNotEmpty) {
      buf.write(' [${field.constraints.trim()}]');
    }

    return (
      attrType: attrType,
      isArray: isArray,
      isRequired: isRequired,
      isContainer: isContainer,
      displayType: buf.toString(),
    );
  }

  int get _totalFieldCount => widget.fields.fold<int>(
    0,
    (sum, field) => sum + field.totalFieldCount,
  );

  void _setFilter(String next) {
    setState(() {
      _filter = next;
      _sync();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final filtering = _showFilterBar || _filter.trim().isNotEmpty;
    final totalCount = _totalFieldCount;
    final selectedField = _selectedNodePath == null
        ? null
        : _fieldsByNodePath[_selectedNodePath!];
    final selectedMeta = _selectedNodePath == null
        ? null
        : _targets[_selectedNodePath!];

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: colors.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 16,
                  color: colors.primary,
                ),
                Expanded(
                  child: Text(
                    'Attributs ($totalCount)',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.fields.isNotEmpty)
                  IconButton(
                    tooltip: 'Filtrer les attributs',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    color: filtering ? colors.primary : colors.onSurfaceVariant,
                    onPressed: () {
                      setState(() {
                        if (_showFilterBar && _filter.trim().isNotEmpty) {
                          _filterCtrl.clear();
                          _filter = '';
                          _showFilterBar = false;
                          _sync();
                        } else {
                          _showFilterBar = !_showFilterBar;
                        }
                      });
                    },
                    icon: Icon(
                      filtering ? Icons.filter_alt_rounded : Icons.search_rounded,
                    ),
                  ),
              ],
            ),
          ),
          if (filtering)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: TextField(
                controller: _filterCtrl,
                onChanged: _setFilter,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 15),
                  suffixIcon: _filter.isNotEmpty
                      ? IconButton(
                          tooltip: 'Effacer le filtre',
                          iconSize: 15,
                          onPressed: () {
                            _filterCtrl.clear();
                            _setFilter('');
                          },
                          icon: const Icon(Icons.close_rounded),
                        )
                      : null,
                  hintText: 'Filtrer nom, type ou contrainte…',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          const Divider(height: 1, thickness: 1),
          if (widget.fields.isNotEmpty && _targets.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Text(
                    'Aucun attribut ne correspond à « ${_filter.trim()} ».',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _filterCtrl.clear();
                      _setFilter('');
                    },
                    icon: const Icon(Icons.clear_rounded, size: 15),
                    label: const Text('Effacer le filtre'),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, bounds) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: JsonRepositoryScope(
                  store: _store,
                  child: SuperTreeView(
                    id: widget.treeId,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    showScrollbar: false,
                    config: SuperTreeViewConfig(
                      binding: const JsonTextBinding(
                        repositoryId: _repo,
                        path: 'nodes',
                      ),
                      rowHeight: 34,
                      headerSize: ((bounds.maxWidth - 44) * 0.50).clamp(
                        120.0,
                        260.0,
                      ),
                      indent: 18,
                      initiallyExpanded: true,
                      showConnectors: true,
                      emptyText: 'Aucun attribut défini',
                      placements: const {
                        SuperTreeViewConfig.headerZone: ['header'],
                        SuperTreeViewConfig.dataZone: ['data'],
                      },
                    ),
                    onNodeSelected: (nodePath) {
                      setState(() {
                        _selectedNodePath = _selectedNodePath == nodePath
                            ? null
                            : nodePath;
                      });
                    },
                    header: Builder(
                      builder: (cell) {
                        final nodePath = JsonListScope.maybeOf(cell)?.nodePath;
                        final meta = nodePath == null
                            ? null
                            : _targets[nodePath];
                        final field = nodePath == null
                            ? null
                            : _fieldsByNodePath[nodePath];
                        final visual = visualForBusinessObjectNode(
                          meta,
                          colors,
                          theme.brightness,
                        );
                        final strong =
                            meta?.isRelation == true ||
                            meta?.attrType == 'object' ||
                            meta?.isArray == true;
                        final row = Row(
                          children: [
                            Icon(visual.icon, size: 15, color: visual.fgColor),
                            const SizedBox(width: 7),
                            Expanded(
                              child: SuperValue(
                                id: '${widget.treeId}-name',
                                config: SuperValueConfig(
                                  mode: SuperValueMode.display,
                                  color: colors.onSurface,
                                  fontWeight: strong
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  binding: const JsonTextBinding(
                                    repositoryId: _repo,
                                    path: 'nodes[?].displayName',
                                  ),
                                ),
                              ),
                            ),
                            if (meta?.isRequired == true)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  '*',
                                  style: TextStyle(
                                    color: colors.error,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        );
                        final tooltip = field == null
                            ? ''
                            : [
                                field.formatLine(),
                                if (field.effectiveRequired) 'Obligatoire',
                                if (field.nullable) 'Nullable',
                              ].join(' · ');
                        return tooltip.isEmpty
                            ? row
                            : Tooltip(message: tooltip, child: row);
                      },
                    ),
                    data: Builder(
                      builder: (cell) {
                        final nodePath = JsonListScope.maybeOf(cell)?.nodePath;
                        final meta = nodePath == null
                            ? null
                            : _targets[nodePath];
                        final visual = visualForBusinessObjectNode(
                          meta,
                          colors,
                          theme.brightness,
                        );
                        return SuperValue(
                          id: '${widget.treeId}-type',
                          config: SuperValueConfig(
                            mode: SuperValueMode.display,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: visual.fgColor,
                            binding: const JsonTextBinding(
                              repositoryId: _repo,
                              path: 'nodes[?].displayType',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          if (selectedField != null)
            _SelectedFieldInspectorStrip(
              field: selectedField,
              meta: selectedMeta,
              onClose: () => setState(() => _selectedNodePath = null),
            ),
        ],
      ),
    );
  }
}

class _SelectedFieldInspectorStrip extends StatelessWidget {
  const _SelectedFieldInspectorStrip({
    required this.field,
    required this.meta,
    required this.onClose,
  });

  final UseCaseFieldSpec field;
  final BusinessObjectTreeSelectionTarget? meta;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visual = visualForBusinessObjectNode(
      meta,
      colors,
      theme.brightness,
    );
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: visual.bgColor,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: visual.borderColor),
            ),
            child: Icon(visual.icon, size: 15, color: visual.fgColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      field.name,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _InspectorPill(
                      label: meta?.displayType ?? field.type,
                      bg: visual.bgColor,
                      fg: visual.fgColor,
                      border: visual.borderColor,
                    ),
                    _InspectorPill(
                      label: field.effectiveRequired
                          ? 'Obligatoire (!)'
                          : 'Optionnel',
                      bg: field.effectiveRequired
                          ? colors.errorContainer.withValues(alpha: 0.7)
                          : colors.surfaceContainerHighest,
                      fg: field.effectiveRequired
                          ? colors.onErrorContainer
                          : colors.onSurfaceVariant,
                    ),
                    if (field.nullable)
                      _InspectorPill(
                        label: 'Nullable (?)',
                        bg: colors.surfaceContainerHighest,
                        fg: colors.onSurfaceVariant,
                      ),
                  ],
                ),
                if (field.description.isNotEmpty)
                  Text(
                    field.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fermer l’aperçu',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _InspectorPill extends StatelessWidget {
  const _InspectorPill({
    required this.label,
    required this.bg,
    required this.fg,
    this.border,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
