/// Atelier structuré de l'étape 5 : Tableau d'Example Mapping à 4 couleurs
/// (Jaune : Story/Objet, Bleu : Règles, Vert : Exemples concrets, Rouge : Questions)
/// permettant d'affiner les objets métiers et de préparer les règles `RG-xxx`
/// ([ExampleMappingEditorView]).
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/business_rule_spec.dart';
import '../../models/example_mapping_spec.dart';
import '../../models/spec_forge_project.dart';
import '../../services/example_mapping_operations.dart';
import '../../services/spec_forge_controller.dart';

/// Vue interactive à 4 couleurs pour l'Example Mapping d'un [SpecForgeProject].
class ExampleMappingEditorView extends StatefulWidget {
  /// Crée l'atelier connecté au [controller].
  const ExampleMappingEditorView({required this.controller, super.key});

  /// Contrôleur principal orchestrant l'état, Undo/Redo et les appels IA.
  final SpecForgeController controller;

  @override
  State<ExampleMappingEditorView> createState() =>
      _ExampleMappingEditorViewState();
}

class _ExampleMappingEditorViewState extends State<ExampleMappingEditorView> {
  String? _objectFilterId;

  String _shortId(String prefix) {
    final token = shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return '${prefix}_${token.isEmpty ? DateTime.now().microsecondsSinceEpoch : token}';
  }

  Future<void> _seedStories(BuildContext context) async {
    final count = await widget.controller.seedExampleMappingStories();
    if (!context.mounted) return;
    final msg = count > 0
        ? '$count tableau${count > 1 ? 'x' : ''} d’Example Mapping initialisé${count > 1 ? 's' : ''}.'
        : 'Tous les objets métiers ont déjà un tableau d’Example Mapping.';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _enrichObject(
    BuildContext context,
    ExampleMapStory story, {
    String? exampleId,
  }) async {
    final injected = await widget.controller
        .enrichBusinessObjectFromExampleMapping(
          storyId: story.id,
          exampleId: exampleId,
        );
    if (!context.mounted) return;
    final msg = injected > 0
        ? '$injected valeur${injected > 1 ? 's' : ''} d’exemple injectée${injected > 1 ? 's' : ''} dans le schéma de l’objet métier.'
        : 'Aucune nouvelle valeur d’attribut à injecter (ajoutez des inputValues correspondant aux attributs de l’objet).';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _promoteRule(
    BuildContext context, {
    required String storyId,
    required String ruleId,
  }) async {
    final res = await widget.controller.promoteExampleRuleToBusinessRule(
      storyId: storyId,
      ruleId: ruleId,
    );
    if (!context.mounted || res == null) return;
    final msg = res.createdNew
        ? 'Règle ${res.rule.code} créée dans les Règles de gestion.'
        : 'Exemples synchronisés avec la règle ${res.rule.code}.';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _saveStories(
    SpecForgeProject project,
    List<ExampleMapStory> nextStories, {
    String? focusStoryId,
  }) async {
    await widget.controller.updateProject(
      project.copyWith(exampleMappings: nextStories),
    );
    if (focusStoryId != null) {
      widget.controller.focusExampleStory(focusStoryId);
    }
  }

  BusinessRuleSpec? _resolveLinkedRule(
    SpecForgeProject project,
    String linkedRuleId,
  ) {
    final needle = linkedRuleId.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final rule in project.businessRules) {
      if (rule.id.toLowerCase() == needle ||
          rule.code.toLowerCase() == needle) {
        return rule;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final stories = project.exampleMappings.where((s) {
      if (_objectFilterId == null || _objectFilterId!.isEmpty) return true;
      return s.targetObjectId == _objectFilterId ||
          s.rules.any((r) => r.targetObjectIds.contains(_objectFilterId));
    }).toList();

    final focusedId = widget.controller.focusedExampleStoryId;
    final selectedStory =
        stories.where((s) => s.id == focusedId).firstOrNull ??
        stories.firstOrNull;

    final totalExamples = project.exampleMappings.fold<int>(
      0,
      (sum, s) => sum + s.totalExampleCount,
    );
    final openQuestions = project.exampleMappings.fold<int>(
      0,
      (sum, s) => sum + s.openQuestionCount,
    );

    return Column(
      key: const ValueKey('example-mapping-editor-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Example Mapping (${project.exampleMappings.length} story${project.exampleMappings.length > 1 ? 's' : ''})',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$totalExamples exemple(s) vert(s) · $openQuestions question(s) rouge(s) ouverte(s)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (project.businessObjects.isNotEmpty)
                    DropdownButton<String?>(
                      value: project.businessObjects.any(
                            (o) => o.id == _objectFilterId,
                          )
                          ? _objectFilterId
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
                      onChanged: (val) => setState(() => _objectFilterId = val),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('spec-em-seed-btn'),
                    onPressed: project.businessObjects.isEmpty
                        ? null
                        : () => _seedStories(context),
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                    label: const Text('Initialiser depuis Objets & UC'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('spec-em-add-story-btn'),
                    onPressed: () => _editStoryDialog(context, project),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Nouvelle Story (Jaune)'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (stories.isNotEmpty) ...[
          SizedBox(
            height: 46,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: stories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final story = stories[index];
                final isSelected = selectedStory?.id == story.id;
                final obj = story.targetObjectId.isEmpty
                    ? null
                    : project.findBusinessObject(story.targetObjectId);
                return ChoiceChip(
                  key: ValueKey('spec-em-story-chip-${story.id}'),
                  selected: isSelected,
                  onSelected: (_) =>
                      widget.controller.focusExampleStory(story.id),
                  avatar: story.openQuestionCount > 0
                      ? Icon(
                          Icons.help_outline_rounded,
                          size: 16,
                          color: isDark
                              ? Colors.red.shade300
                              : Colors.red.shade700,
                        )
                      : Icon(
                          Icons.view_kanban_outlined,
                          size: 16,
                          color: isDark
                              ? Colors.amber.shade300
                              : Colors.amber.shade900,
                        ),
                  label: Text(
                    '${story.code} · ${obj?.technicalName ?? story.title}',
                  ),
                );
              },
            ),
          ),
        ],
        const Divider(height: 1),
        Expanded(
          child: selectedStory == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.view_kanban_outlined,
                          size: 44,
                          color: colors.primary.withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          project.businessObjects.isEmpty
                              ? 'Modélisez d’abord au moins un objet métier ou créez une Story manuellement.'
                              : 'Aucun tableau d’Example Mapping pour ce filtre.\nInitialisez depuis vos Objets métiers & Cas d’usage ou lancez « Example Mapper » à gauche.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildStoryBoard(context, project, selectedStory, isDark),
        ),
      ],
    );
  }

  Widget _buildStoryBoard(
    BuildContext context,
    SpecForgeProject project,
    ExampleMapStory story,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = _ExampleMapPalette.resolve(isDark, colors);

    final targetObj = story.targetObjectId.isEmpty
        ? null
        : project.findBusinessObject(story.targetObjectId);
    final targetUseCase = story.useCaseId.isEmpty
        ? null
        : project.cahierDesCharges.useCases
              .where((u) => u.id == story.useCaseId)
              .firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Carte JAUNE : Story / Objet métier cible
          Container(
            key: ValueKey('spec-em-yellow-card-${story.id}'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.yellowBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.yellowBorder, width: 1.4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.yellowBadgeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        story.code,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: palette.yellowBadgeFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            story.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (story.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              story.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Modifier cette story jaune',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () =>
                          _editStoryDialog(context, project, existing: story),
                    ),
                    IconButton(
                      tooltip: 'Supprimer cette story jaune',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () async {
                        final next = project.exampleMappings
                            .where((s) => s.id != story.id)
                            .toList();
                        await _saveStories(
                          project,
                          next,
                          focusStoryId: next.firstOrNull?.id,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (targetObj != null)
                      Chip(
                        avatar: const Icon(Icons.hub_outlined, size: 15),
                        label: Text(
                          'Objet : ${targetObj.name} (${targetObj.technicalName})',
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (targetUseCase != null)
                      Chip(
                        avatar: const Icon(Icons.route_outlined, size: 15),
                        label: Text('UC : ${targetUseCase.title}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    for (final req in story.requirementIds)
                      Chip(
                        label: Text(req),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (targetObj != null)
                      FilledButton.tonalIcon(
                        key: const ValueKey('spec-em-enrich-object-btn'),
                        onPressed: () => _enrichObject(context, story),
                        icon: const Icon(
                          Icons.playlist_add_check_rounded,
                          size: 16,
                        ),
                        label: Text(
                          'Injecter exemples → ${targetObj.technicalName}',
                        ),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('spec-em-ask-ai-refine-btn'),
                      onPressed: widget.controller.isSending
                          ? null
                          : () => widget.controller.sendUserMessage(
                              'En te basant sur le tableau ${story.code} (« ${story.title} »), '
                              'analyse les exemples verts et questions rouges pour affiner l’objet métier cible '
                              '(attributs manquants, bornes, énumérations, cycle de vie) et complète les cas limites manquants.',
                            ),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                      label: const Text('Affiner l’objet avec l’IA'),
                    ),
                  ],
                ),
                if (story.refinementNotes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final note in story.refinementNotes)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              note,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Section BLEUE + VERTE : Règles & Exemples concrets
          Row(
            children: [
              Expanded(
                child: Text(
                  'Règles (Bleu) & Exemples concrets (Vert) — ${story.rules.length} règle(s), ${story.totalExampleCount} exemple(s)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('spec-em-add-rule-btn'),
                onPressed: () => _editRuleDialog(context, project, story),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Ajouter règle (Bleue)'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (story.rules.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: const Text(
                'Aucune carte bleue pour l’instant. Ajoutez une règle métier puis illustrez-la avec des exemples verts.',
              ),
            )
          else
            for (final emRule in story.rules) ...[
              _buildBlueRuleSection(
                context,
                project,
                story,
                emRule,
                palette,
              ),
              const SizedBox(height: 12),
            ],

          const SizedBox(height: 10),

          // Section ROUGE : Questions / Zones d'ombre
          Row(
            children: [
              Expanded(
                child: Text(
                  'Questions & Zones d’ombre (Rouge) — ${story.openQuestionCount} ouverte(s)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('spec-em-add-question-btn'),
                onPressed: () => _editQuestionDialog(context, project, story),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Ajouter question (Rouge)'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (story.questions.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: const Text(
                'Aucune zone d’ombre recensée sur ce périmètre.',
              ),
            )
          else
            for (final q in story.questions) ...[
              _buildRedQuestionCard(context, project, story, q, palette),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _buildBlueRuleSection(
    BuildContext context,
    SpecForgeProject project,
    ExampleMapStory story,
    ExampleMapRule emRule,
    _ExampleMapPalette palette,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final linkedRule = _resolveLinkedRule(project, emRule.linkedRuleId);

    return Container(
      key: ValueKey('spec-em-blue-card-${emRule.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.blueBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.blueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Chip(
                label: Text(emRule.category.label),
                visualDensity: VisualDensity.compact,
                backgroundColor: palette.blueBadgeBg,
                labelStyle: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: palette.blueBadgeFg,
                ),
              ),
              if (linkedRule != null) ...[
                const SizedBox(width: 6),
                Chip(
                  avatar: const Icon(Icons.gavel_rounded, size: 14),
                  label: Text(linkedRule.code),
                  visualDensity: VisualDensity.compact,
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emRule.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (emRule.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        emRule.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Modifier cette règle bleue',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _editRuleDialog(
                  context,
                  project,
                  story,
                  existing: emRule,
                ),
              ),
              IconButton(
                tooltip: 'Supprimer cette règle bleue',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  final updatedStory = story.copyWith(
                    rules: story.rules
                        .where((r) => r.id != emRule.id)
                        .toList(),
                  );
                  await _saveStories(project, [
                    for (final s in project.exampleMappings)
                      if (s.id == story.id) updatedStory else s,
                  ]);
                },
              ),
            ],
          ),
          if (emRule.targetAttributes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final attr in emRule.targetAttributes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      attr,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                key: ValueKey('spec-em-add-example-${emRule.id}'),
                onPressed: () =>
                    _editExampleDialog(context, project, story, emRule),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Ajouter exemple (Vert)'),
              ),
              FilledButton.tonalIcon(
                key: ValueKey('spec-em-promote-rule-${emRule.id}'),
                onPressed: () => _promoteRule(
                  context,
                  storyId: story.id,
                  ruleId: emRule.id,
                ),
                icon: const Icon(Icons.gavel_rounded, size: 16),
                label: Text(
                  linkedRule != null
                      ? 'Synchroniser → ${linkedRule.code}'
                      : 'Promouvoir → RG',
                ),
              ),
            ],
          ),
          if (emRule.examples.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final ex in emRule.examples)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 260,
                      maxWidth: 420,
                    ),
                    child: _buildGreenExampleCard(
                      context,
                      project,
                      story,
                      emRule,
                      ex,
                      palette,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGreenExampleCard(
    BuildContext context,
    SpecForgeProject project,
    ExampleMapStory story,
    ExampleMapRule emRule,
    ExampleMapExample ex,
    _ExampleMapPalette palette,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      key: ValueKey('spec-em-green-card-${ex.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.greenBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.greenBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.greenBadgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ex.kind.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.greenBadgeFg,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ex.title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Modifier cet exemple',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: () => _editExampleDialog(
                  context,
                  project,
                  story,
                  emRule,
                  existing: ex,
                ),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Supprimer cet exemple',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: () async {
                  final updatedRule = emRule.copyWith(
                    examples: emRule.examples
                        .where((item) => item.id != ex.id)
                        .toList(),
                  );
                  final updatedStory = story.copyWith(
                    rules: [
                      for (final r in story.rules)
                        if (r.id == emRule.id) updatedRule else r,
                    ],
                  );
                  await _saveStories(project, [
                    for (final s in project.exampleMappings)
                      if (s.id == story.id) updatedStory else s,
                  ]);
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (ex.given.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Étant donné : ${ex.given}', style: theme.textTheme.bodySmall),
          ],
          if (ex.when.isNotEmpty)
            Text('Quand : ${ex.when}', style: theme.textTheme.bodySmall),
          if (ex.then.isNotEmpty)
            Text('Alors : ${ex.then}', style: theme.textTheme.bodySmall),
          if (ex.inputValues.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final entry in ex.inputValues.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${entry.key}=${jsonEncode(entry.value)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (ex.expectedOutcome.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final entry in ex.expectedOutcome.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '→ ${entry.key}=${jsonEncode(entry.value)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (ex.discoveredAttributes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Attributs découverts : ${ex.discoveredAttributes.join(', ')}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRedQuestionCard(
    BuildContext context,
    SpecForgeProject project,
    ExampleMapStory story,
    ExampleMapQuestion q,
    _ExampleMapPalette palette,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bg = q.resolved ? colors.surfaceContainerLow : palette.redBg;
    final border = q.resolved ? colors.outlineVariant : palette.redBorder;

    return Container(
      key: ValueKey('spec-em-red-card-${q.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            q.resolved
                ? Icons.check_circle_rounded
                : Icons.help_outline_rounded,
            size: 20,
            color: q.resolved ? colors.primary : palette.redBadgeFg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.question,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: q.resolved ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (q.impact.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Impact : ${q.impact}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (q.answer.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Réponse : ${q.answer}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    TextButton.icon(
                      key: ValueKey('spec-em-toggle-question-${q.id}'),
                      onPressed: () => _resolveQuestionDialog(
                        context,
                        project,
                        story,
                        q,
                      ),
                      icon: Icon(
                        q.resolved ? Icons.replay_rounded : Icons.done_rounded,
                        size: 15,
                      ),
                      label: Text(
                        q.resolved ? 'Rouvrir' : 'Répondre & résoudre',
                      ),
                    ),
                    if (!q.resolved)
                      TextButton.icon(
                        onPressed: widget.controller.isSending
                            ? null
                            : () => widget.controller.sendUserMessage(
                                'Arbitrons cette question rouge de ${story.code} : « ${q.question} »'
                                '${q.impact.isEmpty ? '' : ' (impact : ${q.impact})'}. '
                                'Pose-moi tes choix via askUser ou applique la décision sur l’objet métier et résous la question.',
                              ),
                        icon: const Icon(Icons.auto_awesome_outlined, size: 15),
                        label: const Text('Arbitrer avec l’IA'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Modifier la question',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () =>
                _editQuestionDialog(context, project, story, existing: q),
          ),
          IconButton(
            tooltip: 'Supprimer la question',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () async {
              final updatedStory = story.copyWith(
                questions: story.questions
                    .where((item) => item.id != q.id)
                    .toList(),
              );
              await _saveStories(project, [
                for (final s in project.exampleMappings)
                  if (s.id == story.id) updatedStory else s,
              ]);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editStoryDialog(
    BuildContext context,
    SpecForgeProject project, {
    ExampleMapStory? existing,
  }) async {
    final codeCtrl = TextEditingController(
      text:
          existing?.code ??
          ExampleMappingOperations.nextStoryCode(project.exampleMappings),
    );
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    var selectedObjectId =
        existing?.targetObjectId ??
        project.businessObjects.firstOrNull?.id ??
        '';
    var selectedUseCaseId = existing?.useCaseId ?? '';
    final reqsCtrl = TextEditingController(
      text: (existing?.requirementIds ?? const <String>[]).join(', '),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nouvelle Story (Jaune)'
                : 'Modifier ${existing.code}',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Code (EM-xxx)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Titre de la story / périmètre',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (project.businessObjects.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: project.businessObjects.any(
                            (o) => o.id == selectedObjectId,
                          )
                          ? selectedObjectId
                          : '',
                      decoration: const InputDecoration(
                        labelText: 'Objet métier cible',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('— Aucun —'),
                        ),
                        for (final obj in project.businessObjects)
                          DropdownMenuItem(
                            value: obj.id,
                            child: Text('${obj.name} (${obj.technicalName})'),
                          ),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedObjectId = val ?? ''),
                    ),
                  const SizedBox(height: 8),
                  if (project.cahierDesCharges.useCases.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: project.cahierDesCharges.useCases.any(
                            (u) => u.id == selectedUseCaseId,
                          )
                          ? selectedUseCaseId
                          : '',
                      decoration: const InputDecoration(
                        labelText: 'Cas d’usage lié (optionnel)',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('— Aucun —'),
                        ),
                        for (final uc in project.cahierDesCharges.useCases)
                          DropdownMenuItem(
                            value: uc.id,
                            child: Text(uc.title),
                          ),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedUseCaseId = val ?? ''),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reqsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Exigences EXF liées (séparées par virgules)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || titleCtrl.text.trim().isEmpty) return;

    final reqIds = reqsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final story = (existing ??
            ExampleMapStory(
              id: _shortId('em'),
              code: codeCtrl.text.trim(),
              title: titleCtrl.text.trim(),
            ))
        .copyWith(
          code: codeCtrl.text.trim().isEmpty
              ? ExampleMappingOperations.nextStoryCode(project.exampleMappings)
              : codeCtrl.text.trim(),
          title: titleCtrl.text.trim(),
          description: descCtrl.text.trim(),
          targetObjectId: selectedObjectId,
          useCaseId: selectedUseCaseId,
          requirementIds: reqIds,
        );

    final nextStories = existing == null
        ? [...project.exampleMappings, story]
        : [
            for (final s in project.exampleMappings)
              if (s.id == story.id) story else s,
          ];
    await _saveStories(project, nextStories, focusStoryId: story.id);
  }

  Future<void> _editRuleDialog(
    BuildContext context,
    SpecForgeProject project,
    ExampleMapStory story, {
    ExampleMapRule? existing,
  }) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final attrsCtrl = TextEditingController(
      text: (existing?.targetAttributes ?? const <String>[]).join(', '),
    );
    var category = existing?.category ?? BusinessRuleCategory.validation;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nouvelle règle (Bleue)'
                : 'Modifier la règle bleue',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Énoncé de la règle',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<BusinessRuleCategory>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Catégorie'),
                    items: [
                      for (final cat in BusinessRuleCategory.values)
                        DropdownMenuItem(value: cat, child: Text(cat.label)),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => category = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Précision métier (optionnel)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: attrsCtrl,
                    decoration: const InputDecoration(
                      labelText:
                          'Attributs cibles (ex. Commande.montantHt, Commande.statut)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || titleCtrl.text.trim().isEmpty) return;

    final targetAttrs = attrsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final rule = (existing ??
            ExampleMapRule(
              id: _shortId('emr'),
              title: titleCtrl.text.trim(),
              targetObjectIds: story.targetObjectId.isNotEmpty
                  ? [story.targetObjectId]
                  : const <String>[],
            ))
        .copyWith(
          title: titleCtrl.text.trim(),
          description: descCtrl.text.trim(),
          category: category,
          targetAttributes: targetAttrs,
        );

    final nextRules = existing == null
        ? [...story.rules, rule]
        : [
            for (final r in story.rules)
              if (r.id == rule.id) rule else r,
          ];
    final updatedStory = story.copyWith(rules: nextRules);
    await _saveStories(project, [
      for (final s in project.exampleMappings)
        if (s.id == story.id) updatedStory else s,
    ]);
  }

  Future<void> _editExampleDialog(
    BuildContext context,
    SpecForgeProject project,
    ExampleMapStory story,
    ExampleMapRule emRule, {
    ExampleMapExample? existing,
  }) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    var kind = existing?.kind ?? ExampleMapExampleKind.nominal;
    final givenCtrl = TextEditingController(text: existing?.given ?? '');
    final whenCtrl = TextEditingController(text: existing?.when ?? '');
    final thenCtrl = TextEditingController(text: existing?.then ?? '');
    final inputsCtrl = TextEditingController(
      text: (existing == null || existing.inputValues.isEmpty)
          ? ''
          : jsonEncode(existing.inputValues),
    );
    final outcomeCtrl = TextEditingController(
      text: (existing == null || existing.expectedOutcome.isEmpty)
          ? ''
          : jsonEncode(existing.expectedOutcome),
    );
    final discoveredCtrl = TextEditingController(
      text: (existing?.discoveredAttributes ?? const <String>[]).join(', '),
    );
    String? jsonError;

    Map<String, Object?> parseMapOrEmpty(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return const <String, Object?>{};
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        throw const FormatException('Doit être un objet JSON {"cle": valeur}.');
      }
      return {
        for (final entry in decoded.entries) '${entry.key}': entry.value,
      };
    }

    Map<String, Object?>? parsedInputs;
    Map<String, Object?>? parsedOutcomes;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nouvel exemple (Vert)'
                : 'Modifier l’exemple vert',
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Titre du scénario concret',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ExampleMapExampleKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Nature'),
                    items: [
                      for (final k in ExampleMapExampleKind.values)
                        DropdownMenuItem(value: k, child: Text(k.label)),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => kind = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: givenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Étant donné (contexte initial)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: whenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Quand (action / événement)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: thenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Alors (résultat attendu)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: inputsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Valeurs d’entrée JSON (optionnel)',
                      hintText: '{"montantHt": 500, "statut": "brouillon"}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: outcomeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Sorties attendues JSON (optionnel)',
                      hintText: '{"tauxRemise": 10, "statut": "validee"}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: discoveredCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Attributs / états découverts (virgules)',
                    ),
                  ),
                  if (jsonError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      jsonError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  parsedInputs = parseMapOrEmpty(inputsCtrl.text);
                  parsedOutcomes = parseMapOrEmpty(outcomeCtrl.text);
                  Navigator.pop(context, true);
                } on FormatException catch (e) {
                  setDialogState(() => jsonError = e.message);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || titleCtrl.text.trim().isEmpty) return;

    final discovered = discoveredCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final example = (existing ??
            ExampleMapExample(
              id: _shortId('ex'),
              title: titleCtrl.text.trim(),
            ))
        .copyWith(
          title: titleCtrl.text.trim(),
          kind: kind,
          given: givenCtrl.text.trim(),
          when: whenCtrl.text.trim(),
          then: thenCtrl.text.trim(),
          inputValues: parsedInputs ?? const <String, Object?>{},
          expectedOutcome: parsedOutcomes ?? const <String, Object?>{},
          discoveredAttributes: discovered,
        );

    final nextExamples = existing == null
        ? [...emRule.examples, example]
        : [
            for (final item in emRule.examples)
              if (item.id == example.id) example else item,
          ];
    final updatedRule = emRule.copyWith(examples: nextExamples);
    final updatedStory = story.copyWith(
      rules: [
        for (final r in story.rules)
          if (r.id == emRule.id) updatedRule else r,
      ],
    );
    await _saveStories(project, [
      for (final s in project.exampleMappings)
        if (s.id == story.id) updatedStory else s,
    ]);
  }

  Future<void> _editQuestionDialog(
    BuildContext context,
    SpecForgeProject project,
    ExampleMapStory story, {
    ExampleMapQuestion? existing,
  }) async {
    final questionCtrl = TextEditingController(text: existing?.question ?? '');
    final impactCtrl = TextEditingController(text: existing?.impact ?? '');
    final attrCtrl = TextEditingController(
      text: existing?.linkedAttributePath ?? '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existing == null
              ? 'Nouvelle question (Rouge)'
              : 'Modifier la question rouge',
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: questionCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Question / Zone d’ombre',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: impactCtrl,
                decoration: const InputDecoration(
                  labelText: 'Impact sur l’objet ou les règles (optionnel)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: attrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Attribut concerné (optionnel)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (ok != true || questionCtrl.text.trim().isEmpty) return;

    final q = (existing ??
            ExampleMapQuestion(
              id: _shortId('emq'),
              question: questionCtrl.text.trim(),
              linkedObjectId: story.targetObjectId,
            ))
        .copyWith(
          question: questionCtrl.text.trim(),
          impact: impactCtrl.text.trim(),
          linkedAttributePath: attrCtrl.text.trim(),
        );

    final nextQuestions = existing == null
        ? [...story.questions, q]
        : [
            for (final item in story.questions)
              if (item.id == q.id) q else item,
          ];
    final updatedStory = story.copyWith(questions: nextQuestions);
    await _saveStories(project, [
      for (final s in project.exampleMappings)
        if (s.id == story.id) updatedStory else s,
    ]);
  }

  Future<void> _resolveQuestionDialog(
    BuildContext context,
    SpecForgeProject project,
    ExampleMapStory story,
    ExampleMapQuestion q,
  ) async {
    if (q.resolved) {
      final updatedQ = q.copyWith(resolved: false);
      final updatedStory = story.copyWith(
        questions: [
          for (final item in story.questions)
            if (item.id == q.id) updatedQ else item,
        ],
      );
      await _saveStories(project, [
        for (final s in project.exampleMappings)
          if (s.id == story.id) updatedStory else s,
      ]);
      return;
    }

    final answerCtrl = TextEditingController(text: q.answer);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Résoudre la question rouge'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                q.question,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: answerCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Décision / Réponse retenue',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Valider la résolution'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final updatedQ = q.copyWith(
      resolved: true,
      answer: answerCtrl.text.trim(),
    );
    final updatedStory = story.copyWith(
      questions: [
        for (final item in story.questions)
          if (item.id == q.id) updatedQ else item,
      ],
    );
    await _saveStories(project, [
      for (final s in project.exampleMappings)
        if (s.id == story.id) updatedStory else s,
    ]);
  }
}

class _ExampleMapPalette {
  const _ExampleMapPalette({
    required this.yellowBg,
    required this.yellowBorder,
    required this.yellowBadgeBg,
    required this.yellowBadgeFg,
    required this.blueBg,
    required this.blueBorder,
    required this.blueBadgeBg,
    required this.blueBadgeFg,
    required this.greenBg,
    required this.greenBorder,
    required this.greenBadgeBg,
    required this.greenBadgeFg,
    required this.redBg,
    required this.redBorder,
    required this.redBadgeFg,
  });

  final Color yellowBg;
  final Color yellowBorder;
  final Color yellowBadgeBg;
  final Color yellowBadgeFg;
  final Color blueBg;
  final Color blueBorder;
  final Color blueBadgeBg;
  final Color blueBadgeFg;
  final Color greenBg;
  final Color greenBorder;
  final Color greenBadgeBg;
  final Color greenBadgeFg;
  final Color redBg;
  final Color redBorder;
  final Color redBadgeFg;

  static _ExampleMapPalette resolve(bool isDark, ColorScheme colors) {
    if (isDark) {
      return _ExampleMapPalette(
        yellowBg: Colors.amber.shade900.withValues(alpha: 0.20),
        yellowBorder: Colors.amber.shade600.withValues(alpha: 0.55),
        yellowBadgeBg: Colors.amber.shade700,
        yellowBadgeFg: Colors.black,
        blueBg: Colors.blue.shade900.withValues(alpha: 0.22),
        blueBorder: Colors.blue.shade500.withValues(alpha: 0.45),
        blueBadgeBg: Colors.blue.shade800,
        blueBadgeFg: Colors.white,
        greenBg: Colors.green.shade900.withValues(alpha: 0.24),
        greenBorder: Colors.green.shade500.withValues(alpha: 0.45),
        greenBadgeBg: Colors.green.shade700,
        greenBadgeFg: Colors.white,
        redBg: Colors.red.shade900.withValues(alpha: 0.20),
        redBorder: Colors.red.shade400.withValues(alpha: 0.55),
        redBadgeFg: Colors.red.shade300,
      );
    }
    return _ExampleMapPalette(
      yellowBg: Colors.amber.shade50,
      yellowBorder: Colors.amber.shade400,
      yellowBadgeBg: Colors.amber.shade700,
      yellowBadgeFg: Colors.white,
      blueBg: Colors.blue.shade50,
      blueBorder: Colors.blue.shade300,
      blueBadgeBg: Colors.blue.shade700,
      blueBadgeFg: Colors.white,
      greenBg: Colors.green.shade50,
      greenBorder: Colors.green.shade300,
      greenBadgeBg: Colors.green.shade700,
      greenBadgeFg: Colors.white,
      redBg: Colors.red.shade50,
      redBorder: Colors.red.shade300,
      redBadgeFg: Colors.red.shade700,
    );
  }
}
