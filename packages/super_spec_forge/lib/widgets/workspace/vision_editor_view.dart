/// Atelier structuré de l'étape 1 : Cadrage, objectifs, personas et contraintes ([VisionEditorView]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/spec_forge_project.dart';
import '../../models/spec_vision.dart';
import '../../services/spec_forge_controller.dart';

/// Vue structurée et éditable du cadrage ([SpecVision]).
class VisionEditorView extends StatelessWidget {
  /// Crée la vue connectée au [controller].
  const VisionEditorView({required this.controller, super.key});

  /// Contrôleur principal.
  final SpecForgeController controller;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    if (project == null) return const SizedBox.shrink();
    final vision = project.vision;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Cadrage & Acteurs',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _editVisionSummaryDialog(context, project),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Éditer la synthèse'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Vision produit',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LabeledTextBlock(
                label: 'Résumé de l’idée',
                value: vision.ideaSummary,
                emptyText: 'Non renseigné.',
              ),
              const SizedBox(height: 10),
              _LabeledTextBlock(
                label: 'Problème adressé',
                value: vision.problemStatement,
                emptyText: 'À préciser avec le Product Strategist.',
              ),
              const SizedBox(height: 10),
              _LabeledTextBlock(
                label: 'Proposition de valeur',
                value: vision.valueProposition,
                emptyText: 'À préciser avec le Product Strategist.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Objectifs (${vision.objectives.length})',
          trailing: IconButton(
            tooltip: 'Ajouter un objectif',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => _addStringItem(
              context,
              title: 'Nouvel objectif',
              onSave: (val) => controller.updateProject(
                project.copyWith(
                  vision: vision.copyWith(
                    objectives: [...vision.objectives, val],
                  ),
                ),
              ),
            ),
          ),
          child: vision.objectives.isEmpty
              ? Text(
                  'Aucun objectif défini pour le moment.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < vision.objectives.length; i++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.flag_outlined, size: 18),
                        title: Text(vision.objectives[i]),
                        trailing: IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            final next = List<String>.from(vision.objectives)
                              ..removeAt(i);
                            controller.updateProject(
                              project.copyWith(
                                vision: vision.copyWith(objectives: next),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Acteurs & Personas (${vision.personas.length})',
          trailing: FilledButton.tonalIcon(
            onPressed: () => _editPersonaDialog(context, project),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
            label: const Text('Ajouter'),
          ),
          child: vision.personas.isEmpty
              ? Text(
                  'Aucun persona identifié pour le moment.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              : Column(
                  children: [
                    for (final persona in vision.personas)
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        color: colors.surfaceContainerLow,
                        child: ListTile(
                          title: Text(
                            persona.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (persona.role.isNotEmpty) Text(persona.role),
                              if (persona.goals.isNotEmpty)
                                Text(
                                  'Objectifs : ${persona.goals.join(' · ')}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              if (persona.painPoints.isNotEmpty)
                                Text(
                                  'Irritants : ${persona.painPoints.join(' · ')}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _editPersonaDialog(
                                  context,
                                  project,
                                  existing: persona,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                                onPressed: () {
                                  final next = vision.personas
                                      .where((p) => p.id != persona.id)
                                      .toList();
                                  controller.updateProject(
                                    project.copyWith(
                                      vision: vision.copyWith(personas: next),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SectionCard(
                title: 'Contraintes (${vision.constraints.length})',
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: () => _addStringItem(
                    context,
                    title: 'Nouvelle contrainte',
                    onSave: (val) => controller.updateProject(
                      project.copyWith(
                        vision: vision.copyWith(
                          constraints: [...vision.constraints, val],
                        ),
                      ),
                    ),
                  ),
                ),
                child: _StringBulletList(
                  items: vision.constraints,
                  emptyText: 'Aucune contrainte.',
                  onRemove: (idx) {
                    final next = List<String>.from(vision.constraints)
                      ..removeAt(idx);
                    controller.updateProject(
                      project.copyWith(
                        vision: vision.copyWith(constraints: next),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _SectionCard(
                title: 'Hors périmètre (${vision.outOfScope.length})',
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: () => _addStringItem(
                    context,
                    title: 'Élément hors périmètre',
                    onSave: (val) => controller.updateProject(
                      project.copyWith(
                        vision: vision.copyWith(
                          outOfScope: [...vision.outOfScope, val],
                        ),
                      ),
                    ),
                  ),
                ),
                child: _StringBulletList(
                  items: vision.outOfScope,
                  emptyText: 'Rien d’exclu explicitement.',
                  onRemove: (idx) {
                    final next = List<String>.from(vision.outOfScope)
                      ..removeAt(idx);
                    controller.updateProject(
                      project.copyWith(
                        vision: vision.copyWith(outOfScope: next),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editVisionSummaryDialog(
    BuildContext context,
    SpecForgeProject project,
  ) async {
    final summaryCtrl = TextEditingController(text: project.vision.ideaSummary);
    final problemCtrl = TextEditingController(
      text: project.vision.problemStatement,
    );
    final valueCtrl = TextEditingController(
      text: project.vision.valueProposition,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Éditer la synthèse de cadrage'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: summaryCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Résumé de l’idée',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: problemCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Problème adressé',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Proposition de valeur',
                  border: OutlineInputBorder(),
                ),
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
    );
    if (saved == true) {
      await controller.updateProject(
        project.copyWith(
          vision: project.vision.copyWith(
            ideaSummary: summaryCtrl.text.trim(),
            problemStatement: problemCtrl.text.trim(),
            valueProposition: valueCtrl.text.trim(),
          ),
        ),
      );
    }
    summaryCtrl.dispose();
    problemCtrl.dispose();
    valueCtrl.dispose();
  }

  Future<void> _addStringItem(
    BuildContext context, {
    required String title,
    required ValueChanged<String> onSave,
  }) async {
    final textCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (ok == true && textCtrl.text.trim().isNotEmpty) {
      onSave(textCtrl.text.trim());
    }
    textCtrl.dispose();
  }

  Future<void> _editPersonaDialog(
    BuildContext context,
    SpecForgeProject project, {
    SpecPersona? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final roleCtrl = TextEditingController(text: existing?.role ?? '');
    final goalsCtrl = TextEditingController(
      text: existing?.goals.join('\n') ?? '',
    );
    final painsCtrl = TextEditingController(
      text: existing?.painPoints.join('\n') ?? '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Nouvel acteur' : 'Modifier l’acteur'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom du rôle / persona *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: roleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Responsabilités',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: goalsCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Objectifs (un par ligne)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: painsCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Points de friction (un par ligne)',
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
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final persona = SpecPersona(
        id: existing?.id ?? 'persona_${shortid.generate()}',
        name: nameCtrl.text.trim(),
        role: roleCtrl.text.trim(),
        goals: _lines(goalsCtrl.text),
        painPoints: _lines(painsCtrl.text),
      );
      final currentList = List<SpecPersona>.from(project.vision.personas);
      final idx = currentList.indexWhere((p) => p.id == persona.id);
      if (idx >= 0) {
        currentList[idx] = persona;
      } else {
        currentList.add(persona);
      }
      await controller.updateProject(
        project.copyWith(vision: project.vision.copyWith(personas: currentList)),
      );
    }

    nameCtrl.dispose();
    roleCtrl.dispose();
    goalsCtrl.dispose();
    painsCtrl.dispose();
  }

  List<String> _lines(String text) => text
      .split(RegExp(r'[\r\n]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabeledTextBlock extends StatelessWidget {
  const _LabeledTextBlock({
    required this.label,
    required this.value,
    required this.emptyText,
  });

  final String label;
  final String value;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasValue = value.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hasValue ? value : emptyText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: hasValue ? colors.onSurface : colors.onSurfaceVariant,
            fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _StringBulletList extends StatelessWidget {
  const _StringBulletList({
    required this.items,
    required this.emptyText,
    required this.onRemove,
  });

  final List<String> items;
  final String emptyText;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (items.isEmpty) {
      return Text(
        emptyText,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Row(
            children: [
              const Text('• '),
              Expanded(child: Text(items[i])),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () => onRemove(i),
              ),
            ],
          ),
      ],
    );
  }
}
