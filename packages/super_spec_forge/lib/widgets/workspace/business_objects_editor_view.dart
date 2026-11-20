/// Atelier maître-détail de l'étape 3 : Objets métiers, attributs, relations et cycles de vie ([BusinessObjectsEditorView]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/business_object_spec.dart';
import '../../models/spec_forge_project.dart';
import '../../services/spec_forge_controller.dart';

/// Vue maître-détail pour explorer et éditer les [BusinessObjectSpec].
class BusinessObjectsEditorView extends StatefulWidget {
  /// Crée la vue connectée au [controller].
  const BusinessObjectsEditorView({required this.controller, super.key});

  /// Contrôleur principal.
  final SpecForgeController controller;

  @override
  State<BusinessObjectsEditorView> createState() =>
      _BusinessObjectsEditorViewState();
}

class _BusinessObjectsEditorViewState extends State<BusinessObjectsEditorView> {
  String? _selectedObjectId;

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();
    final objects = project.businessObjects;
    final selected = objects.isEmpty
        ? null
        : objects.firstWhere(
            (o) => o.id == _selectedObjectId,
            orElse: () => objects.first,
          );

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Objets métiers (${objects.length})',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _editObjectDialog(context, project),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Nouvel objet'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: objects.isEmpty
              ? const Center(
                  child: Text(
                    'Aucun objet métier pour l’instant.\nUtilisez le Domain Modeler à gauche ou cliquez sur « Nouvel objet ».',
                    textAlign: TextAlign.center,
                  ),
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 240,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: colors.outlineVariant),
                          ),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: objects.length,
                          itemBuilder: (context, index) {
                            final obj = objects[index];
                            final isSelected = selected?.id == obj.id;
                            return Card(
                              elevation: 0,
                              color: isSelected
                                  ? colors.primaryContainer
                                  : colors.surfaceContainerLow,
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                dense: true,
                                selected: isSelected,
                                title: Text(
                                  obj.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${obj.technicalName} · ${obj.attributes.length} attr.',
                                ),
                                onTap: () => setState(
                                  () => _selectedObjectId = obj.id,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: selected == null
                          ? const SizedBox.shrink()
                          : _BusinessObjectDetailPane(
                              project: project,
                              object: selected,
                              controller: widget.controller,
                              onEditMeta: () => _editObjectDialog(
                                context,
                                project,
                                existing: selected,
                              ),
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _editObjectDialog(
    BuildContext context,
    SpecForgeProject project, {
    BusinessObjectSpec? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final techCtrl = TextEditingController(text: existing?.technicalName ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    var aggregateRoot = existing?.aggregateRoot ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nouvel objet métier'
                : 'Modifier ${existing.name}',
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom métier *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: techCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom technique PascalCase (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Agrégat racine (entité principale)'),
                  value: aggregateRoot,
                  onChanged: (v) => setDialogState(() => aggregateRoot = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final obj = BusinessObjectSpec(
        id: existing?.id ?? 'obj_${shortid.generate()}',
        name: nameCtrl.text.trim(),
        technicalName: techCtrl.text.trim(),
        description: descCtrl.text.trim(),
        aggregateRoot: aggregateRoot,
        attributes: existing?.attributes ?? const [],
        relations: existing?.relations ?? const [],
        lifecycleStates: existing?.lifecycleStates ?? const [],
        lifecycleTransitions: existing?.lifecycleTransitions ?? const [],
      );
      final list = List<BusinessObjectSpec>.from(project.businessObjects);
      final idx = list.indexWhere((o) => o.id == obj.id);
      if (idx >= 0) {
        list[idx] = obj;
      } else {
        list.add(obj);
      }
      await widget.controller.updateProject(
        project.copyWith(businessObjects: list),
      );
      if (mounted) {
        setState(() => _selectedObjectId = obj.id);
      }
    }

    nameCtrl.dispose();
    techCtrl.dispose();
    descCtrl.dispose();
  }
}

class _BusinessObjectDetailPane extends StatelessWidget {
  const _BusinessObjectDetailPane({
    required this.project,
    required this.object,
    required this.controller,
    required this.onEditMeta,
  });

  final SpecForgeProject project;
  final BusinessObjectSpec object;
  final SpecForgeController controller;
  final VoidCallback onEditMeta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${object.name} (${object.technicalName})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (object.description.isNotEmpty)
                    Text(
                      object.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Modifier l’objet',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditMeta,
            ),
            IconButton(
              tooltip: 'Supprimer l’objet',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                final next = project.businessObjects
                    .where((o) => o.id != object.id)
                    .toList();
                controller.updateProject(
                  project.copyWith(businessObjects: next),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Attributs (${object.attributes.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _editAttributeDialog(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Ajouter attribut'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (object.attributes.isEmpty)
          Text(
            'Aucun attribut défini.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          )
        else
          for (final attr in object.attributes)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 6),
              color: colors.surfaceContainerLow,
              child: ListTile(
                dense: true,
                title: Row(
                  children: [
                    Text(
                      attr.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(
                        attr.isArray
                            ? '${attr.type.dslKeyword}[]'
                            : attr.type.dslKeyword,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (attr.required) ...[
                      const SizedBox(width: 6),
                      const Chip(
                        label: Text('requis'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  [
                    if (attr.enumValues.isNotEmpty)
                      'Valeurs : ${attr.enumValues.join(', ')}',
                    if (attr.constraints.isNotEmpty) attr.constraints,
                    if (attr.description.isNotEmpty) attr.description,
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      onPressed: () =>
                          _editAttributeDialog(context, existing: attr),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => _replaceObject(
                        object.copyWith(
                          attributes: object.attributes
                              .where((a) => a.id != attr.id)
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        if (object.relations.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Relations (${object.relations.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final rel in object.relations)
            ListTile(
              dense: true,
              leading: const Icon(Icons.link_rounded, size: 18),
              title: Text(
                '${rel.name} → ${project.findBusinessObject(rel.targetObjectId)?.name ?? rel.targetObjectId} (${rel.cardinality.symbol})',
              ),
              subtitle: rel.description.isEmpty ? null : Text(rel.description),
            ),
        ],
        if (object.lifecycleStates.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Cycle de vie (${object.lifecycleStates.length} états)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in object.lifecycleStates)
                Chip(
                  avatar: Icon(
                    s.isInitial
                        ? Icons.play_circle_outline_rounded
                        : (s.isTerminal
                              ? Icons.stop_circle_outlined
                              : Icons.circle_outlined),
                    size: 16,
                  ),
                  label: Text(s.effectiveLabel),
                ),
            ],
          ),
          if (object.lifecycleTransitions.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final tr in object.lifecycleTransitions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${tr.fromState} → ${tr.toState}'
                  '${tr.trigger.isEmpty ? '' : ' (${tr.trigger})'}'
                  '${tr.guardSummary.isEmpty ? '' : ' — Garde : ${tr.guardSummary}'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ],
    );
  }

  Future<void> _replaceObject(BusinessObjectSpec updated) async {
    final nextList = [
      for (final o in project.businessObjects)
        if (o.id == updated.id) updated else o,
    ];
    await controller.updateProject(project.copyWith(businessObjects: nextList));
  }

  Future<void> _editAttributeDialog(
    BuildContext context, {
    BusinessAttribute? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final enumCtrl = TextEditingController(
      text: existing?.enumValues.join(', ') ?? '',
    );
    final constraintsCtrl = TextEditingController(
      text: existing?.constraints ?? '',
    );
    var type = existing?.type ?? BusinessAttributeType.string;
    var requiredFlag = existing?.required ?? false;
    var isArray = existing?.isArray ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nouvel attribut'
                : 'Modifier ${existing.name}',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom technique (camelCase / snake_case) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<BusinessAttributeType>(
                    initialValue: type,
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
                      if (v != null) setDialogState(() => type = v);
                    },
                  ),
                  if (type == BusinessAttributeType.enumeration) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: enumCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Valeurs énumérées (séparées par virgule)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: constraintsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Contraintes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Obligatoire'),
                    value: requiredFlag,
                    onChanged: (v) =>
                        setDialogState(() => requiredFlag = v ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Liste / tableau'),
                    value: isArray,
                    onChanged: (v) =>
                        setDialogState(() => isArray = v ?? false),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final cleanedName = nameCtrl.text
          .trim()
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
          .replaceAll(RegExp(r'^@+'), '');
      final attr = BusinessAttribute(
        id: existing?.id ?? 'attr_${shortid.generate()}',
        name: cleanedName.isEmpty ? 'champ' : cleanedName,
        type: type,
        required: requiredFlag,
        isArray: isArray,
        enumValues: enumCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        description: descCtrl.text.trim(),
        constraints: constraintsCtrl.text.trim(),
      );
      final attrs = List<BusinessAttribute>.from(object.attributes);
      final idx = attrs.indexWhere((a) => a.id == attr.id);
      if (idx >= 0) {
        attrs[idx] = attr;
      } else {
        attrs.add(attr);
      }
      await _replaceObject(object.copyWith(attributes: attrs));
    }

    nameCtrl.dispose();
    descCtrl.dispose();
    enumCtrl.dispose();
    constraintsCtrl.dispose();
  }
}
