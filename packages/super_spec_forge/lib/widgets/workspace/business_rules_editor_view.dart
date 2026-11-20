/// Atelier structuré de l'étape 4 : Règles de gestion filtrables et éditables ([BusinessRulesEditorView]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/business_rule_spec.dart';
import '../../models/spec_forge_project.dart';
import '../../services/spec_forge_controller.dart';

/// Vue structurée pour consulter, filtrer et éditer les règles de gestion (`RG-xxx`).
class BusinessRulesEditorView extends StatefulWidget {
  /// Crée la vue connectée au [controller].
  const BusinessRulesEditorView({required this.controller, super.key});

  /// Contrôleur principal.
  final SpecForgeController controller;

  @override
  State<BusinessRulesEditorView> createState() =>
      _BusinessRulesEditorViewState();
}

class _BusinessRulesEditorViewState extends State<BusinessRulesEditorView> {
  BusinessRuleCategory? _categoryFilter;
  String? _objectFilter;

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();

    final filtered = project.businessRules.where((rule) {
      if (_categoryFilter != null && rule.category != _categoryFilter) {
        return false;
      }
      if (_objectFilter != null &&
          !rule.targetObjectIds.contains(_objectFilter)) {
        return false;
      }
      return true;
    }).toList();

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
                  'Règles de gestion (${filtered.length}/${project.businessRules.length})',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _editRuleDialog(context, project),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Nouvelle règle'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Toutes'),
                selected: _categoryFilter == null,
                onSelected: (_) => setState(() => _categoryFilter = null),
              ),
              for (final cat in BusinessRuleCategory.values)
                FilterChip(
                  label: Text(cat.label),
                  selected: _categoryFilter == cat,
                  onSelected: (_) => setState(
                    () => _categoryFilter = _categoryFilter == cat ? null : cat,
                  ),
                ),
              if (project.businessObjects.isNotEmpty)
                DropdownButton<String?>(
                  value: project.businessObjects
                          .any((o) => o.id == _objectFilter)
                      ? _objectFilter
                      : null,
                  hint: const Text('Tous les objets'),
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tous les objets'),
                    ),
                    for (final obj in project.businessObjects)
                      DropdownMenuItem<String?>(
                        value: obj.id,
                        child: Text(obj.name),
                      ),
                  ],
                  onChanged: (val) => setState(() => _objectFilter = val),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'Aucune règle de gestion correspondante.\nUtilisez le Rule Architect à gauche ou créez une règle manuellement.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final rule = filtered[index];
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: colors.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Chip(
                                  label: Text(rule.code),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 6),
                                Chip(
                                  label: Text(rule.category.label),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 6),
                                Chip(
                                  label: Text(rule.priority.label),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    rule.title,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () => _editRuleDialog(
                                    context,
                                    project,
                                    existing: rule,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    final next = project.businessRules
                                        .where((r) => r.id != rule.id)
                                        .toList();
                                    widget.controller.updateProject(
                                      project.copyWith(businessRules: next),
                                    );
                                  },
                                ),
                              ],
                            ),
                            if (rule.description.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(rule.description),
                            ],
                            if (rule.targetObjectIds.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final oid in rule.targetObjectIds)
                                    Chip(
                                      avatar: const Icon(
                                        Icons.hub_outlined,
                                        size: 14,
                                      ),
                                      label: Text(
                                        project
                                                .findBusinessObject(oid)
                                                ?.name ??
                                            oid,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 6),
                            if (rule.trigger.isNotEmpty)
                              _RuleClause(label: 'Quand', value: rule.trigger),
                            if (rule.condition.isNotEmpty)
                              _RuleClause(label: 'Si', value: rule.condition),
                            if (rule.effect.isNotEmpty)
                              _RuleClause(label: 'Alors', value: rule.effect),
                            if (rule.errorMessage.isNotEmpty)
                              _RuleClause(
                                label: 'Message',
                                value: rule.errorMessage,
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

  Future<void> _editRuleDialog(
    BuildContext context,
    SpecForgeProject project, {
    BusinessRuleSpec? existing,
  }) async {
    final nextCode =
        'RG-${(project.businessRules.length + 1).toString().padLeft(3, '0')}';
    final codeCtrl = TextEditingController(text: existing?.code ?? nextCode);
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final triggerCtrl = TextEditingController(text: existing?.trigger ?? '');
    final condCtrl = TextEditingController(text: existing?.condition ?? '');
    final effectCtrl = TextEditingController(text: existing?.effect ?? '');
    final errCtrl = TextEditingController(text: existing?.errorMessage ?? '');

    var category = existing?.category ?? BusinessRuleCategory.validation;
    var priority = existing?.priority ?? BusinessRulePriority.high;
    final selectedObjectIds = Set<String>.from(
      existing?.targetObjectIds ?? const <String>[],
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nouvelle règle de gestion'
                : 'Modifier ${existing.code}',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: codeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Code',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<BusinessRuleCategory>(
                          initialValue: category,
                          decoration: const InputDecoration(
                            labelText: 'Catégorie',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final c in BusinessRuleCategory.values)
                              DropdownMenuItem(
                                value: c,
                                child: Text(c.label),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) setDialogState(() => category = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<BusinessRulePriority>(
                          initialValue: priority,
                          decoration: const InputDecoration(
                            labelText: 'Criticité',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final p in BusinessRulePriority.values)
                              DropdownMenuItem(
                                value: p,
                                child: Text(p.label),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) setDialogState(() => priority = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Intitulé *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (project.businessObjects.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Objets métiers concernés :'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final obj in project.businessObjects)
                          FilterChip(
                            label: Text(obj.name),
                            selected: selectedObjectIds.contains(obj.id),
                            onSelected: (sel) => setDialogState(() {
                              if (sel) {
                                selectedObjectIds.add(obj.id);
                              } else {
                                selectedObjectIds.remove(obj.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: triggerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Quand (déclencheur)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: condCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Si (condition)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: effectCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Alors (effet / action)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: errCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Message d’erreur utilisateur',
                      border: OutlineInputBorder(),
                    ),
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

    if (saved == true && titleCtrl.text.trim().isNotEmpty) {
      final rule = BusinessRuleSpec(
        id: existing?.id ?? 'rule_${shortid.generate()}',
        code: codeCtrl.text.trim().isEmpty ? nextCode : codeCtrl.text.trim(),
        title: titleCtrl.text.trim(),
        category: category,
        priority: priority,
        description: descCtrl.text.trim(),
        targetObjectIds: selectedObjectIds.toList(),
        targetAttributes: existing?.targetAttributes ?? const [],
        trigger: triggerCtrl.text.trim(),
        condition: condCtrl.text.trim(),
        effect: effectCtrl.text.trim(),
        errorMessage: errCtrl.text.trim(),
        examples: existing?.examples ?? const [],
      );
      final list = List<BusinessRuleSpec>.from(project.businessRules);
      final idx = list.indexWhere((r) => r.id == rule.id);
      if (idx >= 0) {
        list[idx] = rule;
      } else {
        list.add(rule);
      }
      await widget.controller.updateProject(
        project.copyWith(businessRules: list),
      );
    }

    codeCtrl.dispose();
    titleCtrl.dispose();
    descCtrl.dispose();
    triggerCtrl.dispose();
    condCtrl.dispose();
    effectCtrl.dispose();
    errCtrl.dispose();
  }
}

class _RuleClause extends StatelessWidget {
  const _RuleClause({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$label : ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
