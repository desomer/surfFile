/// Éditeur complet et aperçu des contraintes JSON Schema Draft 7 / 2020-12 pour un [BusinessAttribute]
/// ([showBusinessAttributeEditorDialog], [AttributeSchemaPreviewCard]).
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/business_object_spec.dart';
import '../../models/json_schema_constraints.dart';
import '../../models/spec_forge_project.dart';
import '../../services/exporters/spec_super_designer_exporter.dart';

/// Ouvre la boîte de dialogue multi-onglets d'édition d'un [BusinessAttribute]
/// incluant toutes les contraintes du standard JSON Schema.
Future<BusinessAttribute?> showBusinessAttributeEditorDialog(
  BuildContext context, {
  required SpecForgeProject project,
  BusinessAttribute? existing,
  bool isSubAttribute = false,
}) => showDialog<BusinessAttribute>(
  context: context,
  builder: (ctx) => _BusinessAttributeEditorDialog(
    project: project,
    existing: existing,
    isSubAttribute: isSubAttribute,
  ),
);

/// Carte affichant les contraintes JSON Schema actives et un aperçu Draft 2020-12 dépliable.
class AttributeSchemaPreviewCard extends StatefulWidget {
  /// Crée une carte de prévisualisation pour un [attribute] (ou un [schemaMap] libre).
  const AttributeSchemaPreviewCard({
    required this.schemaMap,
    this.badges = const <String>[],
    this.title = 'Contraintes & Aperçu JSON Schema',
    super.key,
  });

  /// Fragment JSON Schema à prévisualiser.
  final Map<String, Object?> schemaMap;

  /// Puces résumant les contraintes actives.
  final List<String> badges;

  /// Titre de la carte.
  final String title;

  @override
  State<AttributeSchemaPreviewCard> createState() =>
      _AttributeSchemaPreviewCardState();
}

class _AttributeSchemaPreviewCardState
    extends State<AttributeSchemaPreviewCard> {
  bool _showJson = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final pretty = const JsonEncoder.withIndent('  ').convert(widget.schemaMap);

    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schema_outlined, size: 16, color: colors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  key: const ValueKey('spec-attr-toggle-json-schema'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => setState(() => _showJson = !_showJson),
                  child: Text(_showJson ? 'Masquer JSON' : 'Voir JSON Schema'),
                ),
              ],
            ),
            if (widget.badges.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final b in widget.badges)
                    Chip(
                      label: Text(b),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Aucune contrainte JSON Schema additionnelle.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            if (_showJson) ...[
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('spec-attr-json-schema-preview'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: SelectableText(
                  pretty,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BusinessAttributeEditorDialog extends StatefulWidget {
  const _BusinessAttributeEditorDialog({
    required this.project,
    required this.existing,
    required this.isSubAttribute,
  });

  final SpecForgeProject project;
  final BusinessAttribute? existing;
  final bool isSubAttribute;

  @override
  State<_BusinessAttributeEditorDialog> createState() =>
      _BusinessAttributeEditorDialogState();
}

class _BusinessAttributeEditorDialogState
    extends State<_BusinessAttributeEditorDialog> {
  // Onglet 1 : Général
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  final List<_EnumChoiceRow> _enumRows = <_EnumChoiceRow>[];
  late final TextEditingController _defaultCtrl;
  late final TextEditingController _maxRowsCtrl;
  late final TextEditingController _freeConstraintsCtrl;

  // Onglet 2 : Contraintes typées JSON Schema
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late final TextEditingController _exclMinCtrl;
  late final TextEditingController _exclMaxCtrl;
  late final TextEditingController _multipleOfCtrl;

  late final TextEditingController _minLenCtrl;
  late final TextEditingController _maxLenCtrl;
  late final TextEditingController _patternCtrl;
  late final TextEditingController _formatCtrl;
  late final TextEditingController _contentMediaCtrl;
  late final TextEditingController _contentEncCtrl;
  late final TextEditingController _xMaskCtrl;

  late final TextEditingController _minItemsCtrl;
  late final TextEditingController _maxItemsCtrl;
  late final TextEditingController _minContainsCtrl;
  late final TextEditingController _maxContainsCtrl;

  late final TextEditingController _minPropsCtrl;
  late final TextEditingController _maxPropsCtrl;

  late final TextEditingController _constCtrl;
  late final TextEditingController _examplesCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _commentCtrl;

  // Onglet 3 : Avancé JSON (composition, conditionnels, dependentRequired, x-*)
  late final TextEditingController _advancedJsonCtrl;

  late BusinessAttributeType _type;
  late bool _requiredFlag;
  late bool _nullableFlag;
  late bool _uniqueFlag;
  late bool _isArray;
  late String _refObjectId;

  late bool _uniqueItems;
  late bool _readOnly;
  late bool _writeOnly;
  late bool _deprecated;
  late bool _hasConst;
  bool? _additionalPropertiesBool; // null = non spécifié, true, false
  bool? _xSearchable; // null = non spécifié, true, false
  bool? _xDatabaseIndex; // null = non spécifié, true, false

  String? _validationError;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    final sc = ex?.schemaConstraints ?? JsonSchemaConstraints.empty;

    _nameCtrl = TextEditingController(text: ex?.name ?? '');
    _descCtrl = TextEditingController(text: ex?.description ?? '');
    final exValues = ex?.enumValues ?? const <String>[];
    final exNames = sc.enumNames;
    final exDescs = sc.enumDescriptions;
    for (var i = 0; i < exValues.length; i++) {
      _enumRows.add(
        _EnumChoiceRow(
          value: exValues[i],
          name: i < exNames.length ? exNames[i] : '',
          description: i < exDescs.length ? exDescs[i] : '',
        ),
      );
    }
    if ((ex?.type == BusinessAttributeType.enumeration) && _enumRows.isEmpty) {
      _enumRows.add(_EnumChoiceRow());
    }
    _defaultCtrl = TextEditingController(text: ex?.defaultValue ?? '');
    _maxRowsCtrl = TextEditingController(
      text: ex?.estimatedMaxRows?.toString() ?? '',
    );
    _freeConstraintsCtrl = TextEditingController(text: ex?.constraints ?? '');

    _minCtrl = TextEditingController(text: sc.minimum?.toString() ?? '');
    _maxCtrl = TextEditingController(text: sc.maximum?.toString() ?? '');
    _exclMinCtrl = TextEditingController(
      text: sc.exclusiveMinimum?.toString() ?? '',
    );
    _exclMaxCtrl = TextEditingController(
      text: sc.exclusiveMaximum?.toString() ?? '',
    );
    _multipleOfCtrl = TextEditingController(
      text: sc.multipleOf?.toString() ?? '',
    );

    _minLenCtrl = TextEditingController(text: sc.minLength?.toString() ?? '');
    _maxLenCtrl = TextEditingController(text: sc.maxLength?.toString() ?? '');
    _patternCtrl = TextEditingController(text: sc.pattern ?? '');
    _formatCtrl = TextEditingController(text: sc.format ?? '');
    _contentMediaCtrl = TextEditingController(text: sc.contentMediaType ?? '');
    _contentEncCtrl = TextEditingController(text: sc.contentEncoding ?? '');
    _xMaskCtrl = TextEditingController(text: sc.xMask ?? '');

    _minItemsCtrl = TextEditingController(text: sc.minItems?.toString() ?? '');
    _maxItemsCtrl = TextEditingController(text: sc.maxItems?.toString() ?? '');
    _minContainsCtrl = TextEditingController(
      text: sc.minContains?.toString() ?? '',
    );
    _maxContainsCtrl = TextEditingController(
      text: sc.maxContains?.toString() ?? '',
    );

    _minPropsCtrl = TextEditingController(
      text: sc.minProperties?.toString() ?? '',
    );
    _maxPropsCtrl = TextEditingController(
      text: sc.maxProperties?.toString() ?? '',
    );

    _hasConst = sc.hasConst;
    _constCtrl = TextEditingController(
      text: sc.hasConst ? _encodeScalarOrJson(sc.constValue) : '',
    );
    _examplesCtrl = TextEditingController(
      text: [for (final item in sc.examples) _encodeScalarOrJson(item)].join('\n'),
    );
    _titleCtrl = TextEditingController(text: sc.title ?? '');
    _commentCtrl = TextEditingController(text: sc.comment ?? '');

    _type = ex?.type ?? BusinessAttributeType.string;
    _requiredFlag = ex?.required ?? false;
    _nullableFlag = ex?.nullable ?? false;
    _uniqueFlag = ex?.unique ?? false;
    _isArray = ex?.isArray ?? false;
    _refObjectId = ex?.referenceObjectId ?? '';

    _uniqueItems = sc.uniqueItems ?? false;
    _readOnly = sc.readOnly ?? false;
    _writeOnly = sc.writeOnly ?? false;
    _deprecated = sc.deprecated ?? false;
    _additionalPropertiesBool = sc.additionalProperties is bool
        ? sc.additionalProperties as bool
        : null;
    _xSearchable = sc.xSearchable;
    _xDatabaseIndex = sc.xDatabaseIndex;

    final advMap = <String, Object?>{
      if (sc.oneOf.isNotEmpty) 'oneOf': sc.oneOf,
      if (sc.anyOf.isNotEmpty) 'anyOf': sc.anyOf,
      if (sc.allOf.isNotEmpty) 'allOf': sc.allOf,
      if (sc.not != null) 'not': sc.not,
      if (sc.ifSchema != null) 'if': sc.ifSchema,
      if (sc.thenSchema != null) 'then': sc.thenSchema,
      if (sc.elseSchema != null) 'else': sc.elseSchema,
      if (sc.contains != null) 'contains': sc.contains,
      if (sc.prefixItems.isNotEmpty) 'prefixItems': sc.prefixItems,
      if (sc.additionalProperties is Map)
        'additionalProperties': sc.additionalProperties,
      if (sc.patternProperties != null && sc.patternProperties!.isNotEmpty)
        'patternProperties': sc.patternProperties,
      if (sc.propertyNames != null) 'propertyNames': sc.propertyNames,
      if (sc.dependentRequired != null && sc.dependentRequired!.isNotEmpty)
        'dependentRequired': sc.dependentRequired,
      if (sc.dependentSchemas != null && sc.dependentSchemas!.isNotEmpty)
        'dependentSchemas': sc.dependentSchemas,
      ...sc.extraKeywords,
    };
    advMap.remove('x-mask');
    advMap.remove('x-searchable');
    advMap.remove('x-database-index');
    if (ex?.type == BusinessAttributeType.enumeration) {
      advMap.remove('x-enumNames');
      advMap.remove('x-enumDescriptions');
    }
    _advancedJsonCtrl = TextEditingController(
      text: advMap.isEmpty
          ? ''
          : const JsonEncoder.withIndent('  ').convert(advMap),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    for (final row in _enumRows) {
      row.dispose();
    }
    _defaultCtrl.dispose();
    _maxRowsCtrl.dispose();
    _freeConstraintsCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _exclMinCtrl.dispose();
    _exclMaxCtrl.dispose();
    _multipleOfCtrl.dispose();
    _minLenCtrl.dispose();
    _maxLenCtrl.dispose();
    _patternCtrl.dispose();
    _formatCtrl.dispose();
    _contentMediaCtrl.dispose();
    _contentEncCtrl.dispose();
    _xMaskCtrl.dispose();
    _minItemsCtrl.dispose();
    _maxItemsCtrl.dispose();
    _minContainsCtrl.dispose();
    _maxContainsCtrl.dispose();
    _minPropsCtrl.dispose();
    _maxPropsCtrl.dispose();
    _constCtrl.dispose();
    _examplesCtrl.dispose();
    _titleCtrl.dispose();
    _commentCtrl.dispose();
    _advancedJsonCtrl.dispose();
    super.dispose();
  }

  BusinessAttribute _buildAndValidateAttribute() {
    final rawName = _nameCtrl.text.trim();
    if (rawName.isEmpty) {
      throw const FormatException('Le nom de l’attribut est obligatoire.');
    }
    final cleanedName = rawName
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .replaceAll(RegExp(r'^@+'), '');

    final advRawText = _advancedJsonCtrl.text.trim();
    var advMap = <String, Object?>{};
    if (advRawText.isNotEmpty) {
      final decoded = jsonDecode(advRawText);
      if (decoded is! Map) {
        throw const FormatException(
          'L’éditeur avancé doit contenir un objet JSON {...}.',
        );
      }
      advMap = <String, Object?>{
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }

    final examplesList = _examplesCtrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(_decodeScalarOrJson)
        .toList();

    final maxRows = _isArray ? int.tryParse(_maxRowsCtrl.text.trim()) : null;
    final maxItems = _isArray
        ? (_parseIntOrNull(_maxItemsCtrl.text) ?? maxRows)
        : null;
    if (_isArray &&
        maxItems != null &&
        maxItems > BusinessObjectSpec.maxEmbeddedArrayRows) {
      throw const FormatException(
        'Un tableau imbriqué ne peut pas dépasser 200 lignes (maxItems / estimatedMaxRows). Extrayez-le en objet métier séparé.',
      );
    }

    final enumValues = <String>[];
    final enumNames = <String>[];
    final enumDescriptions = <String>[];
    if (_type == BusinessAttributeType.enumeration) {
      advMap.remove('x-enumNames');
      advMap.remove('x-enumDescriptions');
      for (final row in _enumRows) {
        final v = row.valueCtrl.text.trim();
        final n = row.nameCtrl.text.trim();
        final d = row.descCtrl.text.trim();
        if (v.isEmpty && n.isEmpty && d.isEmpty) continue;
        if (v.isEmpty) {
          throw const FormatException(
            'Chaque choix d’énumération renseigné doit avoir une valeur (enum).',
          );
        }
        enumValues.add(v);
        enumNames.add(n);
        enumDescriptions.add(d);
      }
    }

    final mergedSchemaMap = <String, Object?>{
      ...advMap,
      if (_type == BusinessAttributeType.enumeration &&
          enumNames.any((n) => n.isNotEmpty))
        'x-enumNames': enumNames,
      if (_type == BusinessAttributeType.enumeration &&
          enumDescriptions.any((d) => d.isNotEmpty))
        'x-enumDescriptions': enumDescriptions,
      'minimum': ?_parseNumOrNull(_minCtrl.text),
      'maximum': ?_parseNumOrNull(_maxCtrl.text),
      'exclusiveMinimum': ?_parseNumOrNull(_exclMinCtrl.text),
      'exclusiveMaximum': ?_parseNumOrNull(_exclMaxCtrl.text),
      'multipleOf': ?_parseNumOrNull(_multipleOfCtrl.text),
      'minLength': ?_parseIntOrNull(_minLenCtrl.text),
      'maxLength': ?_parseIntOrNull(_maxLenCtrl.text),
      if (_patternCtrl.text.trim().isNotEmpty)
        'pattern': _patternCtrl.text.trim(),
      if (_formatCtrl.text.trim().isNotEmpty) 'format': _formatCtrl.text.trim(),
      if (_contentMediaCtrl.text.trim().isNotEmpty)
        'contentMediaType': _contentMediaCtrl.text.trim(),
      if (_contentEncCtrl.text.trim().isNotEmpty)
        'contentEncoding': _contentEncCtrl.text.trim(),
      if (_xMaskCtrl.text.trim().isNotEmpty) 'x-mask': _xMaskCtrl.text.trim(),
      if (_xSearchable != null) 'x-searchable': _xSearchable,
      if (_xDatabaseIndex != null) 'x-database-index': _xDatabaseIndex,
      if (_isArray) 'minItems': ?_parseIntOrNull(_minItemsCtrl.text),
      if (_isArray) 'maxItems': ?maxItems,
      if (_isArray && _uniqueItems) 'uniqueItems': true,
      if (_isArray) 'minContains': ?_parseIntOrNull(_minContainsCtrl.text),
      if (_isArray) 'maxContains': ?_parseIntOrNull(_maxContainsCtrl.text),
      if (_type == BusinessAttributeType.object)
        'minProperties': ?_parseIntOrNull(_minPropsCtrl.text),
      if (_type == BusinessAttributeType.object)
        'maxProperties': ?_parseIntOrNull(_maxPropsCtrl.text),
      if (_type == BusinessAttributeType.object)
        'additionalProperties': ?_additionalPropertiesBool,
      if (_hasConst) 'const': _decodeScalarOrJson(_constCtrl.text),
      if (examplesList.isNotEmpty) 'examples': examplesList,
      if (_readOnly) 'readOnly': true,
      if (_writeOnly) 'writeOnly': true,
      if (_deprecated) 'deprecated': true,
      if (_titleCtrl.text.trim().isNotEmpty) 'title': _titleCtrl.text.trim(),
      if (_commentCtrl.text.trim().isNotEmpty)
        r'$comment': _commentCtrl.text.trim(),
    };

    final schemaConstraints = JsonSchemaConstraints.fromJson(mergedSchemaMap);
    final attr = BusinessAttribute(
      id: widget.existing?.id ?? 'attr_${shortid.generate()}',
      name: cleanedName.isEmpty ? 'champ' : cleanedName,
      type: _type,
      required: _requiredFlag,
      nullable: _nullableFlag,
      unique: _uniqueFlag,
      isArray: _isArray,
      estimatedMaxRows: _isArray ? (maxRows ?? maxItems) : null,
      defaultValue: _defaultCtrl.text.trim().isEmpty
          ? null
          : _defaultCtrl.text.trim(),
      enumValues: _type == BusinessAttributeType.enumeration
          ? enumValues
          : const <String>[],
      referenceObjectId: _refObjectId,
      description: _descCtrl.text.trim(),
      constraints: _freeConstraintsCtrl.text.trim(),
      schemaConstraints: schemaConstraints,
      children: widget.existing?.children ?? const [],
    );
    attr.validate();
    // Vérifie le JSON Schema complet produit pour cet attribut.
    JsonSchemaValidator.validateSchemaDefinition(
      SpecSuperDesignerExporter.attributeToJsonSchema(attr),
    );
    return attr;
  }

  void _save() {
    try {
      final attr = _buildAndValidateAttribute();
      Navigator.pop(context, attr);
    } on FormatException catch (e) {
      setState(() => _validationError = e.message);
    } catch (e) {
      setState(() => _validationError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final title = widget.existing == null
        ? (widget.isSubAttribute
              ? 'Nouveau sous-attribut'
              : 'Nouvel attribut / sous-objet')
        : 'Modifier ${widget.existing!.name}';

    return AlertDialog(
      insetPadding: const EdgeInsets.all(20),
      title: Text(title),
      content: SizedBox(
        width: (screen.width * 0.72).clamp(620.0, 940.0),
        height: (screen.height * 0.76).clamp(460.0, 720.0),
        child: DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Général'),
                  Tab(text: 'Contraintes JSON Schema'),
                  Tab(text: 'Avancé (Composition / JSON)'),
                ],
              ),
              if (_validationError != null)
                Container(
                  key: const ValueKey('spec-attr-validation-error'),
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _validationError!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onErrorContainer,
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildGeneralTab(),
                    _buildTypedConstraintsTab(),
                    _buildAdvancedJsonTab(colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('spec-attr-save-btn'),
          onPressed: _save,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _buildGeneralTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('spec-attr-name-field'),
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nom technique (camelCase / snake_case) *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<BusinessAttributeType>(
            key: const ValueKey('spec-attr-type-dropdown'),
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final t in BusinessAttributeType.values)
                DropdownMenuItem(
                  value: t,
                  child: Text('${t.label} (${t.dslKeyword})'),
                ),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _type = v;
                  if (_type == BusinessAttributeType.enumeration &&
                      _enumRows.isEmpty) {
                    _enumRows.add(_EnumChoiceRow());
                  }
                });
              }
            },
          ),
          if (_type == BusinessAttributeType.enumeration) ...[
            const SizedBox(height: 12),
            _buildEnumTableSection(),
          ],
          if (_type == BusinessAttributeType.reference &&
              widget.project.businessObjects.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: widget.project.businessObjects.any(
                (o) => o.id == _refObjectId,
              )
                  ? _refObjectId
                  : '',
              decoration: const InputDecoration(
                labelText: 'Objet métier référencé',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Sélectionner…')),
                for (final o in widget.project.businessObjects)
                  DropdownMenuItem(value: o.id, child: Text(o.name)),
              ],
              onChanged: (v) => setState(() => _refObjectId = v ?? ''),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _defaultCtrl,
            decoration: const InputDecoration(
              labelText: 'Valeur par défaut (optionnel)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _freeConstraintsCtrl,
            decoration: const InputDecoration(
              labelText: 'Note libre de contraintes (optionnel)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('spec-attr-examples-field'),
            controller: _examplesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Exemples JSON Schema (un exemple par ligne)',
              hintText: 'Ex.\nCMD-2026-0001\nCMD-2026-0042',
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Obligatoire (!)'),
            value: _requiredFlag,
            onChanged: (v) => setState(() => _requiredFlag = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Nullable (?)'),
            value: _nullableFlag,
            onChanged: (v) => setState(() => _nullableFlag = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Unique'),
            value: _uniqueFlag,
            onChanged: (v) => setState(() => _uniqueFlag = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tableau imbriqué ([], max 200 lignes)'),
            value: _isArray,
            onChanged: (v) => setState(() => _isArray = v ?? false),
          ),
          if (_isArray) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _maxRowsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Lignes max estimées (<= 200)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnumTableSection() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      key: const ValueKey('spec-attr-enum-table'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            color: colors.surfaceContainerLow,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choix de l’énumération (${_enumRows.length})',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('spec-attr-enum-add-row'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    setState(() => _enumRows.add(_EnumChoiceRow()));
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Ajouter un choix'),
                ),
              ],
            ),
          ),
          if (_enumRows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Aucun choix défini. Cliquez sur « Ajouter un choix ».',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.1),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1.8),
                3: FixedColumnWidth(40),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder(
                top: BorderSide(color: colors.outlineVariant),
                horizontalInside: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow.withValues(alpha: 0.55),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        'Valeur (enum) *',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        'Nom (x-enumNames)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        'Descriptif (x-enumDescriptions)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
                for (var i = 0; i < _enumRows.length; i++)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: TextField(
                          key: ValueKey('spec-attr-enum-value-$i'),
                          controller: _enumRows[i].valueCtrl,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'ex. pending',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: TextField(
                          key: ValueKey('spec-attr-enum-name-$i'),
                          controller: _enumRows[i].nameCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'ex. En attente',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: TextField(
                          key: ValueKey('spec-attr-enum-desc-$i'),
                          controller: _enumRows[i].descCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Description du choix…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        key: ValueKey('spec-attr-enum-remove-$i'),
                        tooltip: 'Supprimer ce choix',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: () {
                          setState(() {
                            final removed = _enumRows.removeAt(i);
                            removed.dispose();
                          });
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTypedConstraintsTab() {
    final isNumeric =
        _type == BusinessAttributeType.integer ||
        _type == BusinessAttributeType.number;
    final isStringLike =
        _type == BusinessAttributeType.string ||
        _type == BusinessAttributeType.email ||
        _type == BusinessAttributeType.url ||
        _type == BusinessAttributeType.uuid ||
        _type == BusinessAttributeType.date ||
        _type == BusinessAttributeType.datetime;
    final isObject = _type == BusinessAttributeType.object;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isNumeric) ...[
            const Text(
              'Contraintes numériques',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('spec-attr-minimum-field'),
                    controller: _minCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'minimum (>=)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('spec-attr-maximum-field'),
                    controller: _maxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'maximum (<=)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _exclMinCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'exclusiveMinimum (>)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _exclMaxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'exclusiveMaximum (<)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('spec-attr-multiple-of-field'),
              controller: _multipleOfCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'multipleOf (> 0, ex. 0.01 ou 5)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (isStringLike) ...[
            const Text(
              'Contraintes de chaîne & format',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('spec-attr-min-length-field'),
                    controller: _minLenCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'minLength (>= 0)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('spec-attr-max-length-field'),
                    controller: _maxLenCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'maxLength (>= 0)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('spec-attr-pattern-field'),
              controller: _patternCtrl,
              decoration: const InputDecoration(
                labelText: 'pattern (Expression régulière)',
                hintText: r'Ex. ^[A-Z]{2}-\d{4}$',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _formatCtrl,
                    decoration: const InputDecoration(
                      labelText: 'format (JSON Schema)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  hint: const Text('Presets'),
                  items: [
                    for (final f in JsonSchemaConstraints.standardFormats)
                      DropdownMenuItem(value: f, child: Text(f)),
                  ],
                  onChanged: (v) {
                    if (v != null) _formatCtrl.text = v;
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _contentMediaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'contentMediaType (ex. application/json)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _contentEncCtrl,
                    decoration: const InputDecoration(
                      labelText: 'contentEncoding (ex. base64)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('spec-attr-x-mask-field'),
              controller: _xMaskCtrl,
              decoration: const InputDecoration(
                labelText: 'x-mask (masque PatternMask : #, A, U, L, *)',
                hintText: 'Ex. UU-###-UU ou ## ## ## ## ##',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (_isArray) ...[
            const Text(
              'Contraintes de tableau',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minItemsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'minItems (>= 0)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _maxItemsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'maxItems (<= 200)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minContainsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'minContains (>= 0)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _maxContainsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'maxContains (>= 0)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Éléments uniques (uniqueItems)'),
              value: _uniqueItems,
              onChanged: (v) => setState(() => _uniqueItems = v ?? false),
            ),
            const SizedBox(height: 10),
          ],
          if (isObject) ...[
            const Text(
              'Contraintes de sous-objet',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minPropsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'minProperties (>= 0)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _maxPropsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'maxProperties (>= 0)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<bool?>(
              initialValue: _additionalPropertiesBool,
              decoration: const InputDecoration(
                labelText: 'additionalProperties',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Non spécifié')),
                DropdownMenuItem(value: true, child: Text('Autorisé (true)')),
                DropdownMenuItem(value: false, child: Text('Interdit (false)')),
              ],
              onChanged: (v) => setState(() => _additionalPropertiesBool = v),
            ),
            const SizedBox(height: 14),
          ],
          const Text(
            'Valeur constante & métadonnées JSON Schema',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Imposer une valeur constante (const)'),
            value: _hasConst,
            onChanged: (v) => setState(() => _hasConst = v ?? false),
          ),
          if (_hasConst) ...[
            TextField(
              controller: _constCtrl,
              decoration: const InputDecoration(
                labelText: 'Valeur const (JSON ou texte)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'title (libellé JSON Schema)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentCtrl,
            decoration: const InputDecoration(
              labelText: r'$comment (commentaire développeur)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<bool?>(
            key: const ValueKey('spec-attr-x-searchable-dropdown'),
            initialValue: _xSearchable,
            decoration: const InputDecoration(
              labelText: 'Indexation / recherche (x-searchable)',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Non spécifié')),
              DropdownMenuItem(value: true, child: Text('Recherchable (true)')),
              DropdownMenuItem(
                value: false,
                child: Text('Non recherchable (false)'),
              ),
            ],
            onChanged: (v) => setState(() => _xSearchable = v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<bool?>(
            key: const ValueKey('spec-attr-x-database-index-dropdown'),
            initialValue: _xDatabaseIndex,
            decoration: const InputDecoration(
              labelText: 'Index base de données (x-database-index)',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Non spécifié')),
              DropdownMenuItem(value: true, child: Text('Indexé en base (true)')),
              DropdownMenuItem(
                value: false,
                child: Text('Non indexé (false)'),
              ),
            ],
            onChanged: (v) => setState(() => _xDatabaseIndex = v),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lecture seule (readOnly)'),
            value: _readOnly,
            onChanged: (v) => setState(() => _readOnly = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Écriture seule (writeOnly)'),
            value: _writeOnly,
            onChanged: (v) => setState(() => _writeOnly = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Obsolète (deprecated)'),
            value: _deprecated,
            onChanged: (v) => setState(() => _deprecated = v ?? false),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedJsonTab(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Mots-clés JSON Schema avancés : oneOf, anyOf, allOf, not, if/then/else, '
            'contains, prefixItems, patternProperties, propertyNames, dependentRequired, '
            'dependentSchemas et extensions x-* (x-mask, x-dateFormat…).',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('spec-attr-advanced-json-field'),
              controller: _advancedJsonCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText:
                    '{\n  "x-mask": "AA-###-AA",\n  "oneOf": [{"minLength": 5}, {"maxLength": 2}]\n}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  static num? _parseNumOrNull(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final parsed = num.tryParse(trimmed);
    if (parsed == null) {
      throw FormatException('Valeur numérique invalide : « $trimmed ».');
    }
    return parsed;
  }

  static int? _parseIntOrNull(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null) {
      throw FormatException('Entier attendu : « $trimmed ».');
    }
    return parsed;
  }

  static String _encodeScalarOrJson(Object? value) {
    if (value is String) return value;
    return jsonEncode(value);
  }

  static Object? _decodeScalarOrJson(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return trimmed;
    }
  }
}

class _EnumChoiceRow {
  _EnumChoiceRow({
    String value = '',
    String name = '',
    String description = '',
  }) : valueCtrl = TextEditingController(text: value),
       nameCtrl = TextEditingController(text: name),
       descCtrl = TextEditingController(text: description);

  final TextEditingController valueCtrl;
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;

  void dispose() {
    valueCtrl.dispose();
    nameCtrl.dispose();
    descCtrl.dispose();
  }
}
