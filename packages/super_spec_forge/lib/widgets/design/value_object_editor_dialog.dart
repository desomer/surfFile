/// Dialogues d'édition complète d'un [ValueObjectSpec] (scalaire ou composite,
/// exemples valides/invalides) et de promotion d'un attribut en Value Object
/// ([showValueObjectEditorDialog], [showPromoteToValueObjectDialog]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/business_object_spec.dart';
import '../../models/json_schema_constraints.dart';
import '../../models/spec_forge_project.dart';
import '../../models/value_object_spec.dart';
import '../../services/value_object_primitive_detector.dart';
import '../workspace/attribute_constraints_editor.dart';

/// Résultat validé du dialogue de promotion d'un attribut vers un Value Object.
class PromoteToValueObjectResult {
  /// Crée un résultat de promotion.
  const PromoteToValueObjectResult({
    required this.valueObject,
    required this.scope,
    required this.useExisting,
  });

  /// Value Object créé ou sélectionné.
  final ValueObjectSpec valueObject;

  /// Portée cible (`shared` ou `domain`).
  final ValueObjectScope scope;

  /// `true` si l'utilisateur a choisi de réutiliser un VO déjà dans le catalogue.
  final bool useExisting;
}

/// Ouvre l'éditeur modal complet d'un [ValueObjectSpec].
Future<ValueObjectSpec?> showValueObjectEditorDialog(
  BuildContext context, {
  ValueObjectSpec? existing,
  List<ResolvedValueObject> availableValueObjects = const <ResolvedValueObject>[],
  String? scopeLabel,
}) => showDialog<ValueObjectSpec>(
  context: context,
  builder: (_) => _ValueObjectEditorDialog(
    existing: existing,
    availableValueObjects: availableValueObjects,
    scopeLabel: scopeLabel,
  ),
);

/// Ouvre le dialogue de promotion / remplacement d'un attribut de modèle en Value Object.
Future<PromoteToValueObjectResult?> showPromoteToValueObjectDialog(
  BuildContext context, {
  required BusinessAttribute attribute,
  required List<ResolvedValueObject> availableValueObjects,
  ValueObjectSpec? suggestedSpec,
  ResolvedValueObject? suggestedExisting,
  ValueObjectScope initialScope = ValueObjectScope.domain,
}) => showDialog<PromoteToValueObjectResult>(
  context: context,
  builder: (_) => _PromoteToValueObjectDialog(
    attribute: attribute,
    availableValueObjects: availableValueObjects,
    suggestedSpec: suggestedSpec,
    suggestedExisting: suggestedExisting,
    initialScope: initialScope,
  ),
);

class _ValueObjectEditorDialog extends StatefulWidget {
  const _ValueObjectEditorDialog({
    required this.existing,
    required this.availableValueObjects,
    required this.scopeLabel,
  });

  final ValueObjectSpec? existing;
  final List<ResolvedValueObject> availableValueObjects;
  final String? scopeLabel;

  @override
  State<_ValueObjectEditorDialog> createState() =>
      _ValueObjectEditorDialogState();
}

class _ValueObjectEditorDialogState extends State<_ValueObjectEditorDialog> {
  late final TextEditingController _techNameCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _versionCtrl;
  late final TextEditingController _constraintsCtrl;
  late final TextEditingController _enumValuesCtrl;
  late final TextEditingController _normRulesCtrl;
  late final TextEditingController _crossRulesCtrl;

  // Contraintes JSON Schema scalaires courantes
  late final TextEditingController _minLenCtrl;
  late final TextEditingController _maxLenCtrl;
  late final TextEditingController _patternCtrl;
  late final TextEditingController _formatCtrl;
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late final TextEditingController _xMaskCtrl;

  late String _category;
  late ValueObjectKind _kind;
  late BusinessAttributeType _primitiveType;
  late List<BusinessAttribute> _fields;
  late List<ValueObjectExample> _examples;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    final sc = ex?.schemaConstraints ?? JsonSchemaConstraints.empty;
    _techNameCtrl = TextEditingController(text: ex?.technicalName ?? '');
    _nameCtrl = TextEditingController(text: ex?.name ?? '');
    _descCtrl = TextEditingController(text: ex?.description ?? '');
    _versionCtrl = TextEditingController(text: ex?.version ?? '1.0.0');
    _constraintsCtrl = TextEditingController(text: ex?.constraints ?? '');
    _enumValuesCtrl = TextEditingController(
      text: (ex?.enumValues ?? const <String>[]).join(', '),
    );
    _normRulesCtrl = TextEditingController(
      text: (ex?.normalizationRules ?? const <String>[]).join(', '),
    );
    _crossRulesCtrl = TextEditingController(
      text: (ex?.crossFieldRules ?? const <String>[]).join('\n'),
    );

    _minLenCtrl = TextEditingController(text: sc.minLength?.toString() ?? '');
    _maxLenCtrl = TextEditingController(text: sc.maxLength?.toString() ?? '');
    _patternCtrl = TextEditingController(text: sc.pattern ?? '');
    _formatCtrl = TextEditingController(text: sc.format ?? '');
    _minCtrl = TextEditingController(text: sc.minimum?.toString() ?? '');
    _maxCtrl = TextEditingController(text: sc.maximum?.toString() ?? '');
    _xMaskCtrl = TextEditingController(text: sc.xMask ?? '');

    _category = (ex?.category.isNotEmpty ?? false) ? ex!.category : 'Métier';
    _kind = ex?.kind ?? ValueObjectKind.scalar;
    _primitiveType = ex?.primitiveType ?? BusinessAttributeType.string;
    _fields = List<BusinessAttribute>.from(ex?.fields ?? const []);
    _examples = List<ValueObjectExample>.from(ex?.examples ?? const []);
  }

  @override
  void dispose() {
    _techNameCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _versionCtrl.dispose();
    _constraintsCtrl.dispose();
    _enumValuesCtrl.dispose();
    _normRulesCtrl.dispose();
    _crossRulesCtrl.dispose();
    _minLenCtrl.dispose();
    _maxLenCtrl.dispose();
    _patternCtrl.dispose();
    _formatCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _xMaskCtrl.dispose();
    super.dispose();
  }

  SpecForgeProject _dummyProjectForFields() {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return SpecForgeProject(
      id: 'vo_editor_ctx',
      name: 'VO',
      initialIdea: '',
      createdAt: epoch,
      updatedAt: epoch,
    );
  }

  Future<void> _addOrEditField({BusinessAttribute? existing, int? index}) async {
    final otherVos = [
      for (final item in widget.availableValueObjects)
        if (item.spec.id != widget.existing?.id) item,
    ];
    final edited = await showBusinessAttributeEditorDialog(
      context,
      project: _dummyProjectForFields(),
      existing: existing,
      isSubAttribute: true,
      availableValueObjects: otherVos,
    );
    if (edited == null || !mounted) return;
    setState(() {
      if (index != null) {
        _fields[index] = edited;
      } else {
        _fields.add(edited);
      }
    });
  }

  Future<void> _addOrEditExample({
    ValueObjectExample? existing,
    int? index,
    required bool defaultValid,
  }) async {
    final valueCtrl = TextEditingController(text: existing?.value ?? '');
    final reasonCtrl = TextEditingController(text: existing?.reason ?? '');
    var isValid = existing?.isValid ?? defaultValid;

    final result = await showDialog<ValueObjectExample>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AlertDialog(
          title: Text(
            existing == null
                ? (isValid
                      ? 'Nouvel exemple valide'
                      : 'Nouveau contre-exemple invalide')
                : 'Modifier l’exemple',
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Valide'),
                      icon: Icon(Icons.check_circle_outline_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Invalide (TDD)'),
                      icon: Icon(Icons.cancel_outlined, size: 16),
                    ),
                  ],
                  selected: {isValid},
                  onSelectionChanged: (sel) =>
                      setLocal(() => isValid = sel.first),
                ),
                TextField(
                  key: const ValueKey('vo-example-value-field'),
                  controller: valueCtrl,
                  autofocus: true,
                  maxLines: _kind == ValueObjectKind.composite ? 3 : 1,
                  decoration: InputDecoration(
                    labelText: _kind == ValueObjectKind.composite
                        ? 'Valeur JSON *'
                        : 'Valeur *',
                    hintText: _kind == ValueObjectKind.composite
                        ? '{"amountMinorUnits": 1500, "currency": "EUR"}'
                        : 'Ex. alice@exemple.fr',
                    border: const OutlineInputBorder(),
                  ),
                ),
                TextField(
                  key: const ValueKey('vo-example-reason-field'),
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: isValid
                        ? 'Commentaire métier (optionnel)'
                        : 'Raison du rejet / erreur attendue',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('vo-example-save-btn'),
              onPressed: () {
                final val = valueCtrl.text.trim();
                if (val.isEmpty && isValid) return;
                Navigator.pop(
                  dialogCtx,
                  ValueObjectExample(
                    id: existing?.id ?? 'voex_${shortid.generate()}',
                    value: val,
                    isValid: isValid,
                    reason: reasonCtrl.text.trim(),
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    valueCtrl.dispose();
    reasonCtrl.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (index != null) {
        _examples[index] = result;
      } else {
        _examples.add(result);
      }
    });
  }

  void _save() {
    try {
      final tech = _techNameCtrl.text.trim();
      final name = _nameCtrl.text.trim();
      final existingSc =
          widget.existing?.schemaConstraints ?? JsonSchemaConstraints.empty;
      final extra = <String, Object?>{...existingSc.extraKeywords};
      if (_xMaskCtrl.text.trim().isNotEmpty) {
        extra['x-mask'] = _xMaskCtrl.text.trim();
      } else {
        extra.remove('x-mask');
      }
      final sc = JsonSchemaConstraints(
        minimum: num.tryParse(_minCtrl.text.trim()),
        maximum: num.tryParse(_maxCtrl.text.trim()),
        exclusiveMinimum: existingSc.exclusiveMinimum,
        exclusiveMaximum: existingSc.exclusiveMaximum,
        multipleOf: existingSc.multipleOf,
        minLength: int.tryParse(_minLenCtrl.text.trim()),
        maxLength: int.tryParse(_maxLenCtrl.text.trim()),
        pattern: _patternCtrl.text.trim().isEmpty
            ? null
            : _patternCtrl.text.trim(),
        format: _formatCtrl.text.trim().isEmpty
            ? null
            : _formatCtrl.text.trim(),
        extraKeywords: extra,
      );
      final enumValues = [
        for (final part in _enumValuesCtrl.text.split(RegExp(r'[\r\n,]+')))
          if (part.trim().isNotEmpty) part.trim(),
      ];
      final normRules = [
        for (final part in _normRulesCtrl.text.split(RegExp(r'[\r\n,]+')))
          if (part.trim().isNotEmpty) part.trim(),
      ];
      final crossRules = [
        for (final line in _crossRulesCtrl.text.split(RegExp(r'\r?\n')))
          if (line.trim().isNotEmpty) line.trim(),
      ];

      final spec = ValueObjectSpec(
        id: widget.existing?.id ?? 'vo_${shortid.generate()}',
        technicalName: tech,
        name: name.isEmpty ? tech : name,
        description: _descCtrl.text.trim(),
        category: _category,
        version: _versionCtrl.text.trim().isEmpty
            ? '1.0.0'
            : _versionCtrl.text.trim(),
        kind: _kind,
        primitiveType: _primitiveType,
        enumValues: _primitiveType == BusinessAttributeType.enumeration
            ? enumValues
            : const <String>[],
        schemaConstraints: _kind == ValueObjectKind.scalar
            ? sc
            : JsonSchemaConstraints.empty,
        normalizationRules: _kind == ValueObjectKind.scalar
            ? normRules
            : const <String>[],
        constraints: _constraintsCtrl.text.trim(),
        fields: _kind == ValueObjectKind.composite
            ? _fields
            : const <BusinessAttribute>[],
        crossFieldRules: _kind == ValueObjectKind.composite
            ? crossRules
            : const <String>[],
        examples: _examples,
      );
      spec.validate();
      Navigator.pop(context, spec);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final colors = Theme.of(context).colorScheme;
    final title = widget.existing == null
        ? 'Nouveau Value Object${widget.scopeLabel != null ? ' (${widget.scopeLabel})' : ''}'
        : 'Modifier ${widget.existing!.technicalName}';

    return AlertDialog(
      insetPadding: const EdgeInsets.all(20),
      title: Text(title),
      content: SizedBox(
        width: (screen.width * 0.72).clamp(640.0, 920.0),
        height: (screen.height * 0.78).clamp(480.0, 740.0),
        child: DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TabBar(
                tabs: [
                  Tab(key: ValueKey('vo-editor-tab-general'), text: 'Identité'),
                  Tab(
                    key: ValueKey('vo-editor-tab-structure'),
                    text: 'Structure & Contraintes',
                  ),
                  Tab(
                    key: ValueKey('vo-editor-tab-examples'),
                    text: 'Exemples TDD',
                  ),
                ],
              ),
              if (_error != null)
                Container(
                  key: const ValueKey('vo-editor-error'),
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildIdentityTab(),
                    _buildStructureTab(colors),
                    _buildExamplesTab(colors),
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
          key: const ValueKey('vo-editor-save-btn'),
          onPressed: _save,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _buildIdentityTab() {
    final categories = <String>{
      ...ValueObjectSpec.standardCategories,
      _category,
    }.toList(growable: false);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 10,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  key: const ValueKey('vo-editor-tech-name'),
                  controller: _techNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom technique (PascalCase ASCII) *',
                    hintText: 'Ex. EmailAddress, Money, InvoiceNumber',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  key: const ValueKey('vo-editor-version'),
                  controller: _versionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Version (x.y.z)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  key: const ValueKey('vo-editor-name'),
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Libellé métier *',
                    hintText: 'Ex. Adresse email',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('vo-editor-category'),
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Catégorie',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                ),
              ),
            ],
          ),
          SegmentedButton<ValueObjectKind>(
            key: const ValueKey('vo-editor-kind-segment'),
            segments: const [
              ButtonSegment(
                value: ValueObjectKind.scalar,
                label: Text('Scalaire (atomique)'),
                icon: Icon(Icons.tag_rounded, size: 16),
              ),
              ButtonSegment(
                value: ValueObjectKind.composite,
                label: Text('Composite (multi-champs)'),
                icon: Icon(Icons.view_module_outlined, size: 16),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (sel) => setState(() => _kind = sel.first),
          ),
          TextField(
            key: const ValueKey('vo-editor-description'),
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description métier & sémantique d’immuabilité',
              border: OutlineInputBorder(),
            ),
          ),
          TextField(
            key: const ValueKey('vo-editor-constraints'),
            controller: _constraintsCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes / invariants complémentaires (optionnel)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStructureTab(ColorScheme colors) {
    if (_kind == ValueObjectKind.scalar) {
      final isStringLike =
          _primitiveType == BusinessAttributeType.string ||
          _primitiveType == BusinessAttributeType.email ||
          _primitiveType == BusinessAttributeType.url ||
          _primitiveType == BusinessAttributeType.uuid;
      final isNumeric =
          _primitiveType == BusinessAttributeType.integer ||
          _primitiveType == BusinessAttributeType.number;

      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            DropdownButtonFormField<BusinessAttributeType>(
              key: const ValueKey('vo-editor-primitive-type'),
              initialValue: _primitiveType,
              decoration: const InputDecoration(
                labelText: 'Type primitif encapsulé',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in ValueObjectSpec.allowedScalarTypes)
                  DropdownMenuItem(
                    value: t,
                    child: Text('${t.label} (${t.dslKeyword})'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _primitiveType = v);
              },
            ),
            if (_primitiveType == BusinessAttributeType.enumeration)
              TextField(
                controller: _enumValuesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valeurs d’énumération (séparées par virgule)',
                  border: OutlineInputBorder(),
                ),
              ),
            if (isStringLike) ...[
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minLenCtrl,
                      decoration: const InputDecoration(
                        labelText: 'minLength',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _maxLenCtrl,
                      decoration: const InputDecoration(
                        labelText: 'maxLength',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _formatCtrl,
                      decoration: const InputDecoration(
                        labelText: 'format (email, uri…)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const ValueKey('vo-editor-pattern'),
                      controller: _patternCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Expression régulière (pattern)',
                        hintText: r'^[A-Z]{3}$',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _xMaskCtrl,
                      decoration: const InputDecoration(
                        labelText: 'x-mask (optionnel)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (isNumeric)
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('vo-editor-min'),
                      controller: _minCtrl,
                      decoration: const InputDecoration(
                        labelText: 'minimum',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('vo-editor-max'),
                      controller: _maxCtrl,
                      decoration: const InputDecoration(
                        labelText: 'maximum',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            TextField(
              key: const ValueKey('vo-editor-norm-rules'),
              controller: _normRulesCtrl,
              decoration: const InputDecoration(
                labelText: 'Règles de normalisation avant validation',
                hintText: 'trim, lowercase, uppercase, removeSpaces…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Champs immuables du composite (${_fields.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('vo-editor-add-field'),
              onPressed: () => _addOrEditField(),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Ajouter un champ'),
            ),
          ],
        ),
        Expanded(
          child: _fields.isEmpty
              ? Center(
                  child: Text(
                    'Ajoutez au moins un champ immuable (ex. amountMinorUnits, currency).',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: _fields.length,
                  itemBuilder: (_, index) {
                    final f = _fields[index];
                    return Card(
                      elevation: 0,
                      color: colors.surfaceContainerLow,
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          '${f.name} : ${f.type == BusinessAttributeType.valueObject ? 'VO(${f.valueObjectId})' : f.type.dslKeyword}${f.required ? '!' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: f.description.isEmpty
                            ? null
                            : Text(f.description),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              onPressed: () =>
                                  _addOrEditField(existing: f, index: index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () =>
                                  setState(() => _fields.removeAt(index)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        TextField(
          key: const ValueKey('vo-editor-cross-rules'),
          controller: _crossRulesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Règles inter-champs (une par ligne)',
            hintText: 'Ex.\nstartDate <= endDate\namountMinorUnits >= 0',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildExamplesTab(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('vo-editor-add-valid-example'),
              onPressed: () => _addOrEditExample(defaultValid: true),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
              label: const Text('+ Exemple valide'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('vo-editor-add-invalid-example'),
              onPressed: () => _addOrEditExample(defaultValid: false),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('+ Contre-exemple invalide'),
            ),
          ],
        ),
        Expanded(
          child: _examples.isEmpty
              ? Center(
                  child: Text(
                    'Aucun exemple saisi. Ajoutez des cas valides et invalides pour documenter et piloter les tests TDD.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: _examples.length,
                  itemBuilder: (_, index) {
                    final ex = _examples[index];
                    return Card(
                      elevation: 0,
                      color: ex.isValid
                          ? colors.surfaceContainerLow
                          : colors.errorContainer.withValues(alpha: 0.35),
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          ex.isValid
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 18,
                          color: ex.isValid ? Colors.green : colors.error,
                        ),
                        title: Text(
                          ex.value.isEmpty ? '(chaîne vide)' : ex.value,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        subtitle: ex.reason.isEmpty ? null : Text(ex.reason),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              onPressed: () => _addOrEditExample(
                                existing: ex,
                                index: index,
                                defaultValid: ex.isValid,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () =>
                                  setState(() => _examples.removeAt(index)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PromoteToValueObjectDialog extends StatefulWidget {
  const _PromoteToValueObjectDialog({
    required this.attribute,
    required this.availableValueObjects,
    required this.suggestedSpec,
    required this.suggestedExisting,
    required this.initialScope,
  });

  final BusinessAttribute attribute;
  final List<ResolvedValueObject> availableValueObjects;
  final ValueObjectSpec? suggestedSpec;
  final ResolvedValueObject? suggestedExisting;
  final ValueObjectScope initialScope;

  @override
  State<_PromoteToValueObjectDialog> createState() =>
      _PromoteToValueObjectDialogState();
}

class _PromoteToValueObjectDialogState
    extends State<_PromoteToValueObjectDialog> {
  late bool _useExisting;
  late String _selectedExistingId;
  late ValueObjectScope _scope;
  late final TextEditingController _techNameCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late ValueObjectSpec _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft =
        widget.suggestedSpec ??
        ValueObjectPrimitiveDetector.buildProposedValueObject(widget.attribute);
    _useExisting =
        widget.suggestedExisting != null &&
        widget.availableValueObjects.isNotEmpty;
    _selectedExistingId =
        widget.suggestedExisting?.spec.id ??
        (widget.availableValueObjects.firstOrNull?.spec.id ?? '');
    _scope = widget.initialScope;
    _techNameCtrl = TextEditingController(text: _draft.technicalName);
    _nameCtrl = TextEditingController(text: _draft.name);
    _descCtrl = TextEditingController(text: _draft.description);
  }

  @override
  void dispose() {
    _techNameCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_useExisting) {
      final chosen = widget.availableValueObjects
          .where((v) => v.spec.id == _selectedExistingId)
          .firstOrNull;
      if (chosen == null) {
        setState(() => _error = 'Sélectionnez un Value Object existant.');
        return;
      }
      Navigator.pop(
        context,
        PromoteToValueObjectResult(
          valueObject: chosen.spec,
          scope: chosen.scope,
          useExisting: true,
        ),
      );
      return;
    }
    try {
      final tech = _techNameCtrl.text.trim();
      final name = _nameCtrl.text.trim();
      final spec = _draft.copyWith(
        technicalName: tech,
        name: name.isEmpty ? tech : name,
        description: _descCtrl.text.trim(),
      );
      spec.validate();
      Navigator.pop(
        context,
        PromoteToValueObjectResult(
          valueObject: spec,
          scope: _scope,
          useExisting: false,
        ),
      );
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasExisting = widget.availableValueObjects.isNotEmpty;

    return AlertDialog(
      title: Text('Promouvoir « ${widget.attribute.name} » en Value Object'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              if (hasExisting)
                SegmentedButton<bool>(
                  key: const ValueKey('vo-promote-mode-segment'),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Créer un nouveau VO'),
                      icon: Icon(Icons.add_circle_outline_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Réutiliser du catalogue'),
                      icon: Icon(Icons.diamond_outlined, size: 16),
                    ),
                  ],
                  selected: {_useExisting},
                  onSelectionChanged: (sel) =>
                      setState(() => _useExisting = sel.first),
                ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: colors.error)),
              if (_useExisting && hasExisting)
                DropdownButtonFormField<String>(
                  key: const ValueKey('vo-promote-existing-dropdown'),
                  initialValue: widget.availableValueObjects.any(
                    (v) => v.spec.id == _selectedExistingId,
                  )
                      ? _selectedExistingId
                      : widget.availableValueObjects.first.spec.id,
                  decoration: const InputDecoration(
                    labelText: 'Value Object du catalogue',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final item in widget.availableValueObjects)
                      DropdownMenuItem(
                        value: item.spec.id,
                        child: Text(
                          '${item.spec.technicalName} — ${item.spec.name} (${item.scope.label})',
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedExistingId = v);
                  },
                )
              else ...[
                SegmentedButton<ValueObjectScope>(
                  key: const ValueKey('vo-promote-scope-segment'),
                  segments: const [
                    ButtonSegment(
                      value: ValueObjectScope.domain,
                      label: Text('Domaine actif'),
                      icon: Icon(Icons.domain_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: ValueObjectScope.shared,
                      label: Text('Shared Kernel'),
                      icon: Icon(Icons.hub_outlined, size: 16),
                    ),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (sel) =>
                      setState(() => _scope = sel.first),
                ),
                TextField(
                  key: const ValueKey('vo-promote-tech-name'),
                  controller: _techNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom technique (PascalCase ASCII) *',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  key: const ValueKey('vo-promote-name'),
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Libellé métier',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                Text(
                  'Structure héritée : ${_draft.kind.label} · ${_draft.formatStructureSummary()}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
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
          key: const ValueKey('vo-promote-confirm-btn'),
          onPressed: _confirm,
          child: Text(_useExisting ? 'Remplacer par ce VO' : 'Créer & remplacer'),
        ),
      ],
    );
  }
}
