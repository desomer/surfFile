/// Atelier structuré de l'étape 3 : Cahier des charges fonctionnel et non fonctionnel ([SpecificationsEditorView]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_forge_project.dart';
import '../../services/spec_forge_controller.dart';

/// Vue structurée à onglets pour éditer modules, exigences MoSCoW, cas d'usage et ENF.
class SpecificationsEditorView extends StatelessWidget {
  /// Crée la vue connectée au [controller].
  const SpecificationsEditorView({required this.controller, super.key});

  /// Contrôleur principal.
  final SpecForgeController controller;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    if (project == null) return const SizedBox.shrink();
    final cdc = project.cahierDesCharges;

    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Cahier des charges',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _addRequirementDialog(context, project),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Ajouter EXF'),
                ),
              ],
            ),
          ),
          TabBar(
            tabs: [
              Tab(
                text: 'Exigences (${cdc.functionalRequirements.length})',
              ),
              Tab(text: 'Modules (${cdc.modules.length})'),
              Tab(text: 'Cas d’usage (${cdc.useCases.length})'),
              Tab(text: 'Non fonctionnel (${cdc.nonFunctionalRequirements.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _RequirementsTab(
                  project: project,
                  controller: controller,
                  onEdit: (req) =>
                      _addRequirementDialog(context, project, existing: req),
                ),
                _ModulesTab(project: project, controller: controller),
                _UseCasesTab(project: project, controller: controller),
                _NfrTab(project: project, controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addRequirementDialog(
    BuildContext context,
    SpecForgeProject project, {
    FunctionalRequirement? existing,
  }) async {
    final cdc = project.cahierDesCharges;
    final nextCode =
        'EXF-${(cdc.functionalRequirements.length + 1).toString().padLeft(3, '0')}';
    final codeCtrl = TextEditingController(text: existing?.code ?? nextCode);
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final criteriaCtrl = TextEditingController(
      text: existing?.acceptanceCriteria.join('\n') ?? '',
    );
    var priority = existing?.priority ?? RequirementPriority.must;
    var moduleId = existing?.moduleId ?? '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nouvelle exigence fonctionnelle'
                : 'Modifier ${existing.code}',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 130,
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
                        child: DropdownButtonFormField<RequirementPriority>(
                          initialValue: priority,
                          decoration: const InputDecoration(
                            labelText: 'Priorité MoSCoW',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final p in RequirementPriority.values)
                              DropdownMenuItem(
                                value: p,
                                child: Text('${p.code} — ${p.label}'),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => priority = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (cdc.modules.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: cdc.modules.any((m) => m.id == moduleId)
                          ? moduleId
                          : '',
                      decoration: const InputDecoration(
                        labelText: 'Module',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Aucun')),
                        for (final m in cdc.modules)
                          DropdownMenuItem(value: m.id, child: Text(m.name)),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => moduleId = val ?? ''),
                    ),
                    const SizedBox(height: 10),
                  ],
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
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: criteriaCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Critères d’acceptation (un par ligne)',
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
      final item = FunctionalRequirement(
        id: existing?.id ?? 'req_${shortid.generate()}',
        code: codeCtrl.text.trim().isEmpty ? nextCode : codeCtrl.text.trim(),
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim(),
        moduleId: moduleId,
        priority: priority,
        actorIds: existing?.actorIds ?? const [],
        acceptanceCriteria: criteriaCtrl.text
            .split(RegExp(r'[\r\n]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      );
      final list = List<FunctionalRequirement>.from(cdc.functionalRequirements);
      final idx = list.indexWhere((r) => r.id == item.id);
      if (idx >= 0) {
        list[idx] = item;
      } else {
        list.add(item);
      }
      await controller.updateProject(
        project.copyWith(
          cahierDesCharges: cdc.copyWith(functionalRequirements: list),
        ),
      );
    }

    codeCtrl.dispose();
    titleCtrl.dispose();
    descCtrl.dispose();
    criteriaCtrl.dispose();
  }
}

class _RequirementsTab extends StatelessWidget {
  const _RequirementsTab({
    required this.project,
    required this.controller,
    required this.onEdit,
  });

  final SpecForgeProject project;
  final SpecForgeController controller;
  final ValueChanged<FunctionalRequirement> onEdit;

  @override
  Widget build(BuildContext context) {
    final reqs = project.cahierDesCharges.functionalRequirements;
    if (reqs.isEmpty) {
      return const Center(
        child: Text(
          'Aucune exigence fonctionnelle pour le moment.\nDiscutez avec le Business Analyst ou cliquez sur « Ajouter EXF ».',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reqs.length,
      itemBuilder: (context, index) {
        final req = reqs[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: ListTile(
            title: Row(
              children: [
                Chip(
                  label: Text('${req.code} · ${req.priority.code}'),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    req.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (req.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(req.description),
                ],
                if (req.acceptanceCriteria.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final c in req.acceptanceCriteria) Text('✓ $c'),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => onEdit(req),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: () {
                    final next = reqs.where((r) => r.id != req.id).toList();
                    controller.updateProject(
                      project.copyWith(
                        cahierDesCharges: project.cahierDesCharges.copyWith(
                          functionalRequirements: next,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModulesTab extends StatelessWidget {
  const _ModulesTab({required this.project, required this.controller});

  final SpecForgeProject project;
  final SpecForgeController controller;

  @override
  Widget build(BuildContext context) {
    final modules = project.cahierDesCharges.modules;
    if (modules.isEmpty) {
      return const Center(child: Text('Aucun module défini pour le moment.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: modules.length,
      itemBuilder: (context, index) {
        final m = modules[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: Text(
              m.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: m.description.isEmpty ? null : Text(m.description),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              onPressed: () {
                final next = modules.where((x) => x.id != m.id).toList();
                controller.updateProject(
                  project.copyWith(
                    cahierDesCharges: project.cahierDesCharges.copyWith(
                      modules: next,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _UseCasesTab extends StatelessWidget {
  const _UseCasesTab({required this.project, required this.controller});

  final SpecForgeProject project;
  final SpecForgeController controller;

  @override
  Widget build(BuildContext context) {
    final cases = project.cahierDesCharges.useCases;
    if (cases.isEmpty) {
      return const Center(child: Text('Aucun cas d’usage formalisé.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: cases.length,
      itemBuilder: (context, index) {
        final uc = cases[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        uc.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () {
                        final next = cases.where((x) => x.id != uc.id).toList();
                        controller.updateProject(
                          project.copyWith(
                            cahierDesCharges: project.cahierDesCharges.copyWith(
                              useCases: next,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (uc.preconditions.isNotEmpty)
                  Text('Préconditions : ${uc.preconditions.join(' ; ')}'),
                if (uc.mainFlow.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final step in uc.mainFlow) Text('• $step'),
                ],
                if (uc.postconditions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Postconditions : ${uc.postconditions.join(' ; ')}'),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NfrTab extends StatelessWidget {
  const _NfrTab({required this.project, required this.controller});

  final SpecForgeProject project;
  final SpecForgeController controller;

  @override
  Widget build(BuildContext context) {
    final nfrs = project.cahierDesCharges.nonFunctionalRequirements;
    if (nfrs.isEmpty) {
      return const Center(
        child: Text('Aucune exigence non fonctionnelle définie.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: nfrs.length,
      itemBuilder: (context, index) {
        final enf = nfrs[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: ListTile(
            title: Text('${enf.code} · ${enf.title} (${enf.category.label})'),
            subtitle: Text(
              [
                if (enf.description.isNotEmpty) enf.description,
                if (enf.targetMetric.isNotEmpty) 'Cible : ${enf.targetMetric}',
              ].join('\n'),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              onPressed: () {
                final next = nfrs.where((x) => x.id != enf.id).toList();
                controller.updateProject(
                  project.copyWith(
                    cahierDesCharges: project.cahierDesCharges.copyWith(
                      nonFunctionalRequirements: next,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
