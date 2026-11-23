/// Atelier structuré de l'étape 4 : Frise chronologique d'Event Storming
/// (Événement orange, Commande bleue, Acteur jaune, Agrégat ambre, Politique lilas,
/// Read Model vert, Hotspot rouge) avec Bounded Contexts et passerelles Spec
/// ([EventStormingEditorView]).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/event_storming_spec.dart';
import '../../models/spec_forge_project.dart';
import '../../services/event_storming_operations.dart';
import '../../services/spec_forge_controller.dart';

/// Vue interactive en frise chronologique pour l'Event Storming d'un [SpecForgeProject].
class EventStormingEditorView extends StatefulWidget {
  /// Crée l'atelier connecté au [controller].
  const EventStormingEditorView({required this.controller, super.key});

  /// Contrôleur principal orchestrant l'état, Undo/Redo et les appels IA.
  final SpecForgeController controller;

  @override
  State<EventStormingEditorView> createState() =>
      _EventStormingEditorViewState();
}

class _EventStormingEditorViewState extends State<EventStormingEditorView> {
  String? _contextFilterId;
  final ScrollController _timelineScrollController = ScrollController();

  @override
  void dispose() {
    _timelineScrollController.dispose();
    super.dispose();
  }

  String _shortId(String prefix) {
    final token = shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return '${prefix}_${token.isEmpty ? DateTime.now().microsecondsSinceEpoch : token}';
  }

  Future<void> _seedFromCahierDesCharges(BuildContext context) async {
    final res = await widget.controller.seedEventStormingFromSpecifications();
    if (!context.mounted) return;
    final msg = res.addedFlowsCount > 0 || res.addedContextsCount > 0
        ? '${res.addedFlowsCount} flux et ${res.addedContextsCount} contexte(s) borné(s) amorcé(s).'
        : 'Tous les cas d’usage et exigences sont déjà couverts par l’Event Storming.';
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _generateBusinessObjects(BuildContext context) async {
    final res = await widget.controller
        .generateBusinessObjectsFromEventStorming();
    if (!context.mounted) return;
    final msg = (res.createdObjectsCount > 0 || res.enrichedObjectsCount > 0)
        ? '${res.createdObjectsCount} objet(s) créé(s), ${res.enrichedObjectsCount} enrichi(s) dans Objets métiers.'
        : 'Aucun nouvel objet ou attribut à générer depuis les agrégats actuels.';
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _promotePolicy(
    BuildContext context, {
    required String flowId,
    required String nodeId,
  }) async {
    final res = await widget.controller.promoteEventStormPolicyToBusinessRule(
      flowId: flowId,
      nodeId: nodeId,
    );
    if (!context.mounted || res == null) return;
    final msg = res.createdNew
        ? 'Règle ${res.rule.code} créée dans les Règles de gestion.'
        : 'Politique synchronisée avec la règle ${res.rule.code}.';
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveEventStorming(
    SpecForgeProject project,
    EventStormingSpec nextEs, {
    String? focusFlowId,
    String? focusNodeId,
  }) async {
    await widget.controller.updateProject(
      project.copyWith(eventStorming: nextEs),
    );
    if (focusFlowId != null) {
      widget.controller.focusEventStormSelection(
        flowId: focusFlowId,
        nodeId: focusNodeId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final es = project.eventStorming;

    final flows = es.flows.where((f) {
      if (_contextFilterId == null || _contextFilterId!.isEmpty) return true;
      return f.boundedContextIds.contains(_contextFilterId) ||
          f.nodes.any((n) => n.boundedContextId == _contextFilterId);
    }).toList();

    final focusedFlowId = widget.controller.focusedEventStormFlowId;
    final selectedFlow =
        flows.where((f) => f.id == focusedFlowId).firstOrNull ??
        flows.firstOrNull;

    return Column(
      key: const ValueKey('event-storming-editor-view'),
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
                    'Event Storming (${es.flows.length} flux)',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${es.totalEventCount} événement(s) · ${es.totalCommandCount} commande(s) · '
                    '${es.totalPolicyCount} politique(s) · ${es.openHotspotCount} hotspot(s) ouvert(s)',
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
                  if (es.boundedContexts.isNotEmpty)
                    DropdownButton<String?>(
                      value:
                          es.boundedContexts.any(
                            (bc) => bc.id == _contextFilterId,
                          )
                          ? _contextFilterId
                          : null,
                      hint: const Text('Tous les contextes'),
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tous les contextes'),
                        ),
                        for (final bc in es.boundedContexts)
                          DropdownMenuItem<String?>(
                            value: bc.id,
                            child: Text('${bc.code} · ${bc.name}'),
                          ),
                      ],
                      onChanged: (val) => setState(() => _contextFilterId = val),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('spec-es-seed-btn'),
                    onPressed: !project.cahierDesCharges.hasContent
                        ? null
                        : () => _seedFromCahierDesCharges(context),
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                    label: const Text('Amorcer depuis Cahier des charges'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('spec-es-generate-objects-btn'),
                    onPressed: es.flows.isEmpty
                        ? null
                        : () => _generateBusinessObjects(context),
                    icon: const Icon(Icons.hub_outlined, size: 16),
                    label: const Text('Générer Objets métiers'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('spec-es-contexts-btn'),
                    onPressed: () => _manageContextsDialog(context, project),
                    icon: const Icon(Icons.workspaces_outlined, size: 16),
                    label: Text('Contextes (${es.boundedContexts.length})'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('spec-es-add-flow-btn'),
                    onPressed: () => _editFlowDialog(context, project),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Nouveau flux'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final masterPane = _buildFlowsMasterList(
                context,
                project,
                flows,
                selectedFlow,
                theme,
                colors,
              );
              final detailPane = selectedFlow == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 44,
                              color: colors.primary.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              es.flows.isEmpty
                                  ? 'Aucun flux Event Storming modélisé.\nAmorcez depuis le Cahier des charges, créez un flux ou discutez avec « Event Storming Facilitator » à gauche.'
                                  : 'Aucun flux ne correspond au contexte borné sélectionné.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildTimelineBoard(
                      context,
                      project,
                      selectedFlow,
                      theme,
                      colors,
                      isDark,
                    );

              if (constraints.maxWidth >= 560) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 248, child: masterPane),
                    const VerticalDivider(width: 1),
                    Expanded(child: detailPane),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: math.min(180, constraints.maxHeight * 0.30),
                    child: masterPane,
                  ),
                  const Divider(height: 1),
                  Expanded(child: detailPane),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFlowsMasterList(
    BuildContext context,
    SpecForgeProject project,
    List<EventStormBoard> flows,
    EventStormBoard? selectedFlow,
    ThemeData theme,
    ColorScheme colors,
  ) {
    if (flows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            project.eventStorming.flows.isEmpty
                ? 'Aucun flux défini.'
                : 'Aucun flux pour ce filtre.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: flows.length,
      itemBuilder: (context, index) {
        final flow = flows[index];
        final isSelected = selectedFlow?.id == flow.id;
        return Card(
          key: ValueKey('spec-es-flow-tile-${flow.id}'),
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          color: isSelected
              ? colors.primaryContainer.withValues(alpha: 0.55)
              : colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isSelected ? colors.primary : colors.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => widget.controller.focusEventStormFlow(flow.id),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          flow.code,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (flow.openHotspotCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${flow.openHotspotCount} hot',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.onErrorContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    flow.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${flow.domainEventCount} évts · ${flow.commandCount} cmds · ${flow.nodes.length} cartes',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimelineBoard(
    BuildContext context,
    SpecForgeProject project,
    EventStormBoard flow,
    ThemeData theme,
    ColorScheme colors,
    bool isDark,
  ) {
    final sortedNodes = flow.sortedNodes;
    final focusedNodeId = widget.controller.focusedEventStormNodeId;
    final es = project.eventStorming;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bandeau d'en-tête du flux sélectionné
        Container(
          color: colors.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${flow.code} — ${flow.title}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        for (final req in flow.requirementIds.take(3))
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(req),
                            labelStyle: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                    if (flow.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        flow.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Modifier ce flux',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _editFlowDialog(context, project, flow: flow),
              ),
              IconButton(
                tooltip: 'Supprimer ce flux',
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                onPressed: () {
                  final nextFlows = es.flows
                      .where((f) => f.id != flow.id)
                      .toList();
                  _saveEventStorming(
                    project,
                    es.copyWith(flows: nextFlows),
                    focusFlowId: nextFlows.firstOrNull?.id,
                  );
                },
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                key: const ValueKey('spec-es-add-node-btn'),
                onPressed: () => _editNodeDialog(context, project, flow),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Ajouter carte'),
              ),
            ],
          ),
        ),
        // Barre de légende / ajout rapide des 7 couleurs Event Storming
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.outlineVariant),
              bottom: BorderSide(color: colors.outlineVariant),
            ),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Ajout rapide :',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final kind in EventStormNodeKind.values)
                _QuickAddKindChip(
                  kind: kind,
                  palette: _EventStormPalette.forKind(kind, isDark),
                  onTap: () => _editNodeDialog(
                    context,
                    project,
                    flow,
                    initialKind: kind,
                  ),
                ),
              const SizedBox(width: 8),
              TextButton.icon(
                key: const ValueKey('spec-es-manage-links-btn'),
                onPressed: sortedNodes.length < 2
                    ? null
                    : () => _manageLinksDialog(context, project, flow),
                icon: const Icon(Icons.timeline_rounded, size: 16),
                label: Text('Liaisons (${flow.links.length})'),
              ),
            ],
          ),
        ),
        // Frise chronologique horizontale
        Expanded(
          child: sortedNodes.isEmpty
              ? Center(
                  child: Text(
                    'Aucune carte sur cette frise.\nUtilisez les pastilles ci-dessus pour poser un Événement, une Commande, un Agrégat…',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : Scrollbar(
                  controller: _timelineScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _timelineScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < sortedNodes.length; i++) ...[
                          if (i > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 76),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 20,
                                color: colors.outline,
                              ),
                            ),
                          _PostItCard(
                            key: ValueKey('spec-es-node-${sortedNodes[i].id}'),
                            node: sortedNodes[i],
                            index: i,
                            total: sortedNodes.length,
                            isFocused: focusedNodeId == sortedNodes[i].id,
                            palette: _EventStormPalette.forKind(
                              sortedNodes[i].kind,
                              isDark,
                            ),
                            boundedContext: sortedNodes[i]
                                    .boundedContextId
                                    .isEmpty
                                ? null
                                : es.findBoundedContext(
                                    sortedNodes[i].boundedContextId,
                                  ),
                            outgoingLinks: flow.links
                                .where((l) => l.fromNodeId == sortedNodes[i].id)
                                .toList(),
                            allNodes: flow.nodes,
                            onTap: () => widget.controller
                                .focusEventStormSelection(
                                  flowId: flow.id,
                                  nodeId: sortedNodes[i].id,
                                ),
                            onMoveLeft: i == 0
                                ? null
                                : () => _swapNodeOrder(
                                    project,
                                    flow,
                                    sortedNodes,
                                    i,
                                    i - 1,
                                  ),
                            onMoveRight: i == sortedNodes.length - 1
                                ? null
                                : () => _swapNodeOrder(
                                    project,
                                    flow,
                                    sortedNodes,
                                    i,
                                    i + 1,
                                  ),
                            onEdit: () => _editNodeDialog(
                              context,
                              project,
                              flow,
                              node: sortedNodes[i],
                            ),
                            onDelete: () => _deleteNode(
                              project,
                              flow,
                              sortedNodes[i].id,
                            ),
                            onToggleHotspotResolved:
                                sortedNodes[i].kind ==
                                    EventStormNodeKind.hotspot
                                ? () => _toggleHotspotResolved(
                                    project,
                                    flow,
                                    sortedNodes[i],
                                  )
                                : null,
                            onPromotePolicy:
                                sortedNodes[i].kind == EventStormNodeKind.policy
                                ? () => _promotePolicy(
                                    context,
                                    flowId: flow.id,
                                    nodeId: sortedNodes[i].id,
                                  )
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _swapNodeOrder(
    SpecForgeProject project,
    EventStormBoard flow,
    List<EventStormNode> sorted,
    int indexA,
    int indexB,
  ) async {
    final reordered = List<EventStormNode>.from(sorted);
    final moved = reordered.removeAt(indexA);
    reordered.insert(indexB, moved);
    final normalized = [
      for (var i = 0; i < reordered.length; i++)
        reordered[i].copyWith(sequenceOrder: i + 1),
    ];
    final nextFlow = flow.copyWith(nodes: normalized);
    final nextEs = project.eventStorming.copyWith(
      flows: [
        for (final f in project.eventStorming.flows)
          if (f.id == flow.id) nextFlow else f,
      ],
    );
    await _saveEventStorming(
      project,
      nextEs,
      focusFlowId: flow.id,
      focusNodeId: moved.id,
    );
  }

  Future<void> _deleteNode(
    SpecForgeProject project,
    EventStormBoard flow,
    String nodeId,
  ) async {
    final nextFlow = flow.copyWith(
      nodes: flow.nodes.where((n) => n.id != nodeId).toList(),
      links: flow.links
          .where((l) => l.fromNodeId != nodeId && l.toNodeId != nodeId)
          .toList(),
    );
    final nextEs = project.eventStorming.copyWith(
      flows: [
        for (final f in project.eventStorming.flows)
          if (f.id == flow.id) nextFlow else f,
      ],
    );
    await _saveEventStorming(project, nextEs, focusFlowId: flow.id);
  }

  Future<void> _toggleHotspotResolved(
    SpecForgeProject project,
    EventStormBoard flow,
    EventStormNode node,
  ) async {
    final updatedNode = node.copyWith(resolved: !node.resolved);
    final nextFlow = flow.copyWith(
      nodes: [
        for (final n in flow.nodes)
          if (n.id == node.id) updatedNode else n,
      ],
    );
    final nextEs = project.eventStorming.copyWith(
      flows: [
        for (final f in project.eventStorming.flows)
          if (f.id == flow.id) nextFlow else f,
      ],
    );
    await _saveEventStorming(
      project,
      nextEs,
      focusFlowId: flow.id,
      focusNodeId: node.id,
    );
  }

  Future<void> _editFlowDialog(
    BuildContext context,
    SpecForgeProject project, {
    EventStormBoard? flow,
  }) async {
    final codeCtrl = TextEditingController(
      text:
          flow?.code ??
          EventStormingOperations.nextFlowCode(project.eventStorming.flows),
    );
    final titleCtrl = TextEditingController(text: flow?.title ?? '');
    final descCtrl = TextEditingController(text: flow?.description ?? '');
    final reqsCtrl = TextEditingController(
      text: flow?.requirementIds.join(', ') ?? '',
    );
    final selectedBcs = Set<String>.from(
      flow?.boundedContextIds ?? const <String>[],
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            flow == null
                ? 'Nouveau flux Event Storming'
                : 'Modifier ${flow.code}',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('spec-es-flow-code-field'),
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      hintText: 'ES-001',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('spec-es-flow-title-field'),
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Titre du flux / processus *',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reqsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Exigences liées (séparées par des virgules)',
                      hintText: 'EXF-001, EXF-002',
                    ),
                  ),
                  if (project.eventStorming.boundedContexts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Bounded Contexts traversés :'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final bc in project.eventStorming.boundedContexts)
                          FilterChip(
                            label: Text('${bc.code} · ${bc.name}'),
                            selected: selectedBcs.contains(bc.id),
                            onSelected: (v) => setLocal(() {
                              if (v) {
                                selectedBcs.add(bc.id);
                              } else {
                                selectedBcs.remove(bc.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('spec-es-flow-save-btn'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;

    final reqIds = [
      for (final part in reqsCtrl.text.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    final nextFlow = (flow ??
            EventStormBoard(
              id: _shortId('es'),
              code: codeCtrl.text.trim().isEmpty
                  ? 'ES-001'
                  : codeCtrl.text.trim(),
              title: title,
            ))
        .copyWith(
          code: codeCtrl.text.trim().isEmpty ? 'ES-001' : codeCtrl.text.trim(),
          title: title,
          description: descCtrl.text.trim(),
          requirementIds: reqIds,
          boundedContextIds: selectedBcs.toList(),
        );
    final flows = List<EventStormBoard>.from(project.eventStorming.flows);
    if (flow == null) {
      flows.add(nextFlow);
    } else {
      final idx = flows.indexWhere((f) => f.id == flow.id);
      if (idx >= 0) flows[idx] = nextFlow;
    }
    await _saveEventStorming(
      project,
      project.eventStorming.copyWith(flows: flows),
      focusFlowId: nextFlow.id,
    );
  }

  Future<void> _editNodeDialog(
    BuildContext context,
    SpecForgeProject project,
    EventStormBoard flow, {
    EventStormNode? node,
    EventStormNodeKind? initialKind,
  }) async {
    var kind = node?.kind ?? initialKind ?? EventStormNodeKind.domainEvent;
    final titleCtrl = TextEditingController(text: node?.title ?? '');
    final descCtrl = TextEditingController(text: node?.description ?? '');
    final seqCtrl = TextEditingController(
      text: '${node?.sequenceOrder ?? (flow.nodes.length + 1)}',
    );
    final payloadCtrl = TextEditingController(
      text: node?.payloadFields.join(', ') ?? '',
    );
    final answerCtrl = TextEditingController(text: node?.answer ?? '');
    var isPivotal = node?.isPivotal ?? false;
    var resolved = node?.resolved ?? false;
    var bcId = node?.boundedContextId ??
        (flow.boundedContextIds.isNotEmpty ? flow.boundedContextIds.first : '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            node == null
                ? 'Nouvelle carte Event Storming'
                : 'Modifier [${kind.label}]',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<EventStormNodeKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Type de carte'),
                    items: [
                      for (final k in EventStormNodeKind.values)
                        DropdownMenuItem(
                          value: k,
                          child: Text('${k.shortCode} · ${k.label}'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => kind = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('spec-es-node-title-field'),
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Intitulé de la carte *',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Détail / précondition',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: seqCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Ordre chronologique',
                          ),
                        ),
                      ),
                      if (project.eventStorming.boundedContexts.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                project.eventStorming.boundedContexts.any(
                                  (b) => b.id == bcId,
                                )
                                ? bcId
                                : '',
                            decoration: const InputDecoration(
                              labelText: 'Bounded Context',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Aucun'),
                              ),
                              for (final bc
                                  in project.eventStorming.boundedContexts)
                                DropdownMenuItem(
                                  value: bc.id,
                                  child: Text('${bc.code} · ${bc.name}'),
                                ),
                            ],
                            onChanged: (v) => setLocal(() => bcId = v ?? ''),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: payloadCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Données / payload (séparées par virgules)',
                      hintText: 'commandeId, montantHt, valideeLe',
                    ),
                  ),
                  if (kind == EventStormNodeKind.domainEvent)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isPivotal,
                      title: const Text('Événement pivot (★)'),
                      onChanged: (v) => setLocal(() => isPivotal = v == true),
                    ),
                  if (kind == EventStormNodeKind.hotspot) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: resolved,
                      title: const Text('Zone d’ombre résolue'),
                      onChanged: (v) => setLocal(() => resolved = v == true),
                    ),
                    TextField(
                      controller: answerCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Décision / réponse retenue',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('spec-es-node-save-btn'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;

    final seq = int.tryParse(seqCtrl.text.trim()) ?? (flow.nodes.length + 1);
    final payloadFields = [
      for (final part in payloadCtrl.text.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    final nextNode = EventStormNode(
      id: node?.id ?? _shortId('esn'),
      code: node?.code ?? '${kind.shortCode}-${flow.nodes.length + 1}',
      kind: kind,
      title: title,
      description: descCtrl.text.trim(),
      sequenceOrder: seq < 0 ? 0 : seq,
      boundedContextId: bcId,
      isPivotal: kind == EventStormNodeKind.domainEvent && isPivotal,
      actorId: node?.actorId ?? '',
      targetObjectId: node?.targetObjectId ?? '',
      linkedRuleId: node?.linkedRuleId ?? '',
      payloadFields: payloadFields,
      resolved: kind == EventStormNodeKind.hotspot && resolved,
      answer: kind == EventStormNodeKind.hotspot ? answerCtrl.text.trim() : '',
      notes: node?.notes ?? '',
    );

    final nextNodes = List<EventStormNode>.from(flow.nodes);
    if (node == null) {
      nextNodes.add(nextNode);
    } else {
      final idx = nextNodes.indexWhere((n) => n.id == node.id);
      if (idx >= 0) nextNodes[idx] = nextNode;
    }
    final nextFlow = flow.copyWith(nodes: nextNodes);
    final nextEs = project.eventStorming.copyWith(
      flows: [
        for (final f in project.eventStorming.flows)
          if (f.id == flow.id) nextFlow else f,
      ],
    );
    await _saveEventStorming(
      project,
      nextEs,
      focusFlowId: flow.id,
      focusNodeId: nextNode.id,
    );
  }

  Future<void> _manageContextsDialog(
    BuildContext context,
    SpecForgeProject project,
  ) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var contexts = List<EventStormBoundedContext>.from(
      project.eventStorming.boundedContexts,
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Bounded Contexts (DDD)'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final bc in contexts)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${bc.code} · ${bc.name}'),
                      subtitle: bc.description.isEmpty
                          ? null
                          : Text(bc.description),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        onPressed: () {
                          setLocal(() {
                            contexts = contexts
                                .where((item) => item.id != bc.id)
                                .toList();
                          });
                        },
                      ),
                    ),
                  const Divider(),
                  TextField(
                    key: const ValueKey('spec-es-bc-name-field'),
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nouveau contexte borné',
                      hintText: 'Ex. Facturation',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Responsabilité',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      key: const ValueKey('spec-es-bc-add-btn'),
                      onPressed: () {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        setLocal(() {
                          contexts = [
                            ...contexts,
                            EventStormBoundedContext(
                              id: _shortId('bc'),
                              code: EventStormingOperations
                                  .nextBoundedContextCode(contexts),
                              name: name,
                              description: descCtrl.text.trim(),
                            ),
                          ];
                          nameCtrl.clear();
                          descCtrl.clear();
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Ajouter contexte'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Fermer'),
            ),
            FilledButton(
              key: const ValueKey('spec-es-bc-save-btn'),
              onPressed: () async {
                await _saveEventStorming(
                  project,
                  project.eventStorming.copyWith(boundedContexts: contexts),
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manageLinksDialog(
    BuildContext context,
    SpecForgeProject project,
    EventStormBoard flow,
  ) async {
    final sorted = flow.sortedNodes;
    if (sorted.length < 2) return;
    var fromId = sorted.first.id;
    var toId = sorted[1].id;
    var kind = EventStormLinkKind.triggers;
    var links = List<EventStormLink>.from(flow.links);

    String labelOf(String id) =>
        sorted.where((n) => n.id == id).firstOrNull?.title ?? id;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Liaisons · ${flow.code}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final link in links)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${labelOf(link.fromNodeId)} —[${link.kind.label}]→ ${labelOf(link.toNodeId)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        onPressed: () => setLocal(() {
                          links = links
                              .where((l) => l.id != link.id)
                              .toList();
                        }),
                      ),
                    ),
                  const Divider(),
                  DropdownButtonFormField<String>(
                    initialValue: fromId,
                    decoration: const InputDecoration(labelText: 'Source'),
                    items: [
                      for (final n in sorted)
                        DropdownMenuItem(
                          value: n.id,
                          child: Text('[${n.kind.shortCode}] ${n.title}'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => fromId = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<EventStormLinkKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Relation'),
                    items: [
                      for (final k in EventStormLinkKind.values)
                        DropdownMenuItem(value: k, child: Text(k.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => kind = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: toId,
                    decoration: const InputDecoration(labelText: 'Cible'),
                    items: [
                      for (final n in sorted)
                        DropdownMenuItem(
                          value: n.id,
                          child: Text('[${n.kind.shortCode}] ${n.title}'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => toId = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: fromId == toId
                          ? null
                          : () => setLocal(() {
                              links = [
                                ...links,
                                EventStormLink(
                                  id: _shortId('esl'),
                                  fromNodeId: fromId,
                                  toNodeId: toId,
                                  kind: kind,
                                ),
                              ];
                            }),
                      icon: const Icon(Icons.add_link_rounded, size: 16),
                      label: const Text('Ajouter liaison'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final nextFlow = flow.copyWith(links: links);
                final nextEs = project.eventStorming.copyWith(
                  flows: [
                    for (final f in project.eventStorming.flows)
                      if (f.id == flow.id) nextFlow else f,
                  ],
                );
                await _saveEventStorming(
                  project,
                  nextEs,
                  focusFlowId: flow.id,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddKindChip extends StatelessWidget {
  const _QuickAddKindChip({
    required this.kind,
    required this.palette,
    required this.onTap,
  });

  final EventStormNodeKind kind;
  final _EventStormPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      key: ValueKey('spec-es-quick-add-${kind.name}'),
      visualDensity: VisualDensity.compact,
      backgroundColor: palette.bg,
      side: BorderSide(color: palette.border),
      avatar: Icon(Icons.add_rounded, size: 14, color: palette.accent),
      label: Text(
        kind.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: palette.fg,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: onTap,
    );
  }
}

class _PostItCard extends StatelessWidget {
  const _PostItCard({
    required this.node,
    required this.index,
    required this.total,
    required this.isFocused,
    required this.palette,
    required this.boundedContext,
    required this.outgoingLinks,
    required this.allNodes,
    required this.onTap,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onEdit,
    required this.onDelete,
    this.onToggleHotspotResolved,
    this.onPromotePolicy,
    super.key,
  });

  final EventStormNode node;
  final int index;
  final int total;
  final bool isFocused;
  final _EventStormPalette palette;
  final EventStormBoundedContext? boundedContext;
  final List<EventStormLink> outgoingLinks;
  final List<EventStormNode> allNodes;
  final VoidCallback onTap;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onToggleHotspotResolved;
  final VoidCallback? onPromotePolicy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 232,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFocused ? palette.accent : palette.border,
          width: isFocused ? 2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${index + 1} · ${node.kind.label}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (node.isPivotal)
                    Tooltip(
                      message: 'Événement pivot',
                      child: Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: palette.accent,
                      ),
                    ),
                  if (node.kind == EventStormNodeKind.hotspot)
                    Icon(
                      node.resolved
                          ? Icons.check_circle_outline_rounded
                          : Icons.help_outline_rounded,
                      size: 16,
                      color: palette.accent,
                    ),
                ],
              ),
              if (boundedContext != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${boundedContext!.code} · ${boundedContext!.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.fg.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                node.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: palette.fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (node.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  node.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.fg.withValues(alpha: 0.85),
                  ),
                ),
              ],
              if (node.payloadFields.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final field in node.payloadFields.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.fg.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          field,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: palette.fg,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (node.kind == EventStormNodeKind.hotspot &&
                  node.answer.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '→ ${node.answer}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.fg,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (node.linkedRuleId.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'Liée : ${node.linkedRuleId}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (outgoingLinks.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final link in outgoingLinks.take(2))
                  Text(
                    '${link.kind.label} → ${allNodes.where((n) => n.id == link.toNodeId).firstOrNull?.title ?? link.toNodeId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.fg.withValues(alpha: 0.72),
                      fontSize: 10,
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: 'Déplacer à gauche',
                    onPressed: onMoveLeft,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: 'Déplacer à droite',
                    onPressed: onMoveRight,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  const Spacer(),
                  if (onToggleHotspotResolved != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      tooltip: node.resolved
                          ? 'Rouvrir le hotspot'
                          : 'Marquer résolu',
                      onPressed: onToggleHotspotResolved,
                      icon: Icon(
                        node.resolved
                            ? Icons.replay_rounded
                            : Icons.check_rounded,
                      ),
                    ),
                  if (onPromotePolicy != null)
                    IconButton(
                      key: ValueKey('spec-es-promote-policy-${node.id}'),
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      tooltip: node.linkedRuleId.isEmpty
                          ? 'Promouvoir en règle RG-xxx'
                          : 'Synchroniser avec ${node.linkedRuleId}',
                      onPressed: onPromotePolicy,
                      icon: const Icon(Icons.gavel_rounded),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: 'Modifier',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: 'Supprimer',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventStormPalette {
  const _EventStormPalette({
    required this.bg,
    required this.border,
    required this.fg,
    required this.accent,
  });

  final Color bg;
  final Color border;
  final Color fg;
  final Color accent;

  static _EventStormPalette forKind(EventStormNodeKind kind, bool isDark) {
    return switch (kind) {
      EventStormNodeKind.domainEvent => _EventStormPalette(
        bg: isDark ? const Color(0xFF42280B) : const Color(0xFFFFF3E0),
        border: isDark ? const Color(0xFFFB8C00) : const Color(0xFFFFB74D),
        fg: isDark ? const Color(0xFFFFE0B2) : const Color(0xFF4E2600),
        accent: isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
      ),
      EventStormNodeKind.command => _EventStormPalette(
        bg: isDark ? const Color(0xFF0D2B45) : const Color(0xFFE3F2FD),
        border: isDark ? const Color(0xFF42A5F5) : const Color(0xFF64B5F6),
        fg: isDark ? const Color(0xFFBBDEFB) : const Color(0xFF0D3C61),
        accent: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0),
      ),
      EventStormNodeKind.actor => _EventStormPalette(
        bg: isDark ? const Color(0xFF3E350B) : const Color(0xFFFFFDE7),
        border: isDark ? const Color(0xFFFDD835) : const Color(0xFFFBC02D),
        fg: isDark ? const Color(0xFFFFF9C4) : const Color(0xFF4A3C00),
        accent: isDark ? const Color(0xFFFDD835) : const Color(0xFFF57F17),
      ),
      EventStormNodeKind.aggregate => _EventStormPalette(
        bg: isDark ? const Color(0xFF402F07) : const Color(0xFFFFF8E1),
        border: isDark ? const Color(0xFFFFCA28) : const Color(0xFFFFB300),
        fg: isDark ? const Color(0xFFFFECB3) : const Color(0xFF4D3400),
        accent: isDark ? const Color(0xFFFFD54F) : const Color(0xFFFF8F00),
      ),
      EventStormNodeKind.policy => _EventStormPalette(
        bg: isDark ? const Color(0xFF321B47) : const Color(0xFFF3E5F5),
        border: isDark ? const Color(0xFFBA68C8) : const Color(0xFFCE93D8),
        fg: isDark ? const Color(0xFFE1BEE7) : const Color(0xFF38006B),
        accent: isDark ? const Color(0xFFCE93D8) : const Color(0xFF7B1FA2),
      ),
      EventStormNodeKind.readModel => _EventStormPalette(
        bg: isDark ? const Color(0xFF13361B) : const Color(0xFFE8F5E9),
        border: isDark ? const Color(0xFF66BB6A) : const Color(0xFF81C784),
        fg: isDark ? const Color(0xFFC8E6C9) : const Color(0xFF1B5E20),
        accent: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
      ),
      EventStormNodeKind.hotspot => _EventStormPalette(
        bg: isDark ? const Color(0xFF421418) : const Color(0xFFFFEBEE),
        border: isDark ? const Color(0xFFEF5350) : const Color(0xFFE57373),
        fg: isDark ? const Color(0xFFFFCDD2) : const Color(0xFF6A1014),
        accent: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828),
      ),
    };
  }
}
