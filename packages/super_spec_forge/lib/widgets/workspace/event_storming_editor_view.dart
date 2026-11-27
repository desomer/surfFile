/// Atelier structuré de l'étape 4 : **Event Storming DSL v1.0**
/// (1 fichier `<slug>.es.yaml` par Bounded Context, 3 vues : Frise chronologique
/// par étapes, Catalogue `ACT/AGG/EXT`, YAML `.es.yaml` & schéma JSON)
/// ([EventStormingEditorView]).
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/event_storming_spec.dart';
import '../../models/spec_forge_project.dart';
import '../../services/exporters/event_storming_dsl_codec.dart';
import '../../services/spec_forge_controller.dart';
import 'event_storming/event_storming_dialogs.dart';
import 'event_storming/event_storming_step_column.dart';

/// Vue interactive de l'étape 4 Event Storming (DSL v1.0) pour un [SpecForgeProject].
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
  final ScrollController _timelineScrollController = ScrollController();

  @override
  void dispose() {
    _timelineScrollController.dispose();
    super.dispose();
  }

  Future<void> _seedFromCahierDesCharges(BuildContext context) async {
    final res = await widget.controller.seedEventStormingFromSpecifications();
    if (!context.mounted) return;
    final msg = res.addedDocumentsCount > 0 || res.addedStepsCount > 0
        ? '${res.addedDocumentsCount} Bounded Context(s) et ${res.addedStepsCount} étape(s) amorcé(s).'
        : 'Tous les modules et cas d’usage sont déjà couverts par l’Event Storming.';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _generateBusinessObjects(BuildContext context) async {
    final res = await widget.controller
        .generateBusinessObjectsFromEventStorming();
    if (!context.mounted) return;
    final msg = (res.createdObjectsCount > 0 || res.enrichedObjectsCount > 0)
        ? '${res.createdObjectsCount} objet(s) créé(s), ${res.enrichedObjectsCount} enrichi(s) dans Objets métiers.'
        : 'Aucun nouvel objet ou attribut à générer depuis les agrégats (AGG-*) actuels.';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _importYaml(BuildContext context) async {
    final yaml = await showEventStormYamlImportDialog(context);
    if (yaml == null || !context.mounted) return;
    try {
      final res = await widget.controller.importEventStormingYaml(yaml);
      if (!context.mounted || res == null) return;
      final msg = res.createdNew
          ? 'Bounded Context « ${res.boundedContext} » importé.'
          : 'Bounded Context « ${res.boundedContext} » mis à jour depuis YAML.';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } on FormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Erreur YAML : ${e.message}')),
      );
    }
  }

  Future<void> _promotePolicy(
    BuildContext context, {
    required String documentId,
    required int stepNumber,
  }) async {
    final res = await widget.controller.promoteEventStormPolicyToBusinessRule(
      documentId: documentId,
      stepNumber: stepNumber,
    );
    if (!context.mounted || res == null) return;
    final msg = res.createdNew
        ? 'Règle ${res.rule.code} créée dans les Règles de gestion.'
        : 'Politique synchronisée avec la règle ${res.rule.code}.';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _saveEventStorming(
    SpecForgeProject project,
    EventStormingSpec nextEs, {
    String? focusDocumentId,
    int? focusStepNumber,
  }) async {
    await widget.controller.updateProject(
      project.copyWith(eventStorming: nextEs),
    );
    if (focusDocumentId != null) {
      widget.controller.focusEventStormSelection(
        flowId: focusDocumentId,
        nodeId: focusStepNumber?.toString(),
      );
    }
  }

  Future<void> _updateDocument(
    SpecForgeProject project,
    EventStormDocument updated, {
    int? focusStepNumber,
  }) async {
    final docs = List<EventStormDocument>.from(project.eventStorming.documents);
    final idx = docs.indexWhere((d) => d.id == updated.id);
    if (idx >= 0) {
      docs[idx] = updated;
    } else {
      docs.add(updated);
    }
    await _saveEventStorming(
      project,
      project.eventStorming.copyWith(documents: docs),
      focusDocumentId: updated.id,
      focusStepNumber: focusStepNumber,
    );
  }

  Future<void> _createOrEditDocument(
    BuildContext context,
    SpecForgeProject project, {
    EventStormDocument? document,
  }) async {
    final saved = await showEventStormDocumentDialog(
      context,
      defaultDomain: project.name.isEmpty ? 'Domaine métier' : project.name,
      existingDocuments: project.eventStorming.documents,
      document: document,
    );
    if (saved == null) return;
    await _updateDocument(project, saved);
  }

  Future<void> _deleteDocument(
    SpecForgeProject project,
    EventStormDocument doc,
  ) async {
    final nextDocs = project.eventStorming.documents
        .where((d) => d.id != doc.id)
        .toList();
    await _saveEventStorming(
      project,
      project.eventStorming.copyWith(documents: nextDocs),
      focusDocumentId: nextDocs.firstOrNull?.id,
    );
  }

  Future<void> _addOrEditStep(
    BuildContext context,
    SpecForgeProject project,
    EventStormDocument doc, {
    EventStormStep? step,
  }) async {
    final saved = await showEventStormStepDialog(
      context,
      document: doc,
      step: step,
    );
    if (saved == null) return;
    final nextSteps = List<EventStormStep>.from(doc.flow);
    if (step != null) {
      nextSteps.removeWhere((s) => s.step == step.step);
    }
    // Évite collision si le numéro d'étape cible existe déjà
    nextSteps.removeWhere((s) => s.step == saved.step);
    nextSteps.add(saved);
    nextSteps.sort((a, b) => a.step.compareTo(b.step));
    await _updateDocument(
      project,
      doc.copyWith(flow: nextSteps),
      focusStepNumber: saved.step,
    );
  }

  Future<void> _deleteStep(
    SpecForgeProject project,
    EventStormDocument doc,
    int stepNumber,
  ) async {
    final nextSteps = doc.sortedSteps
        .where((s) => s.step != stepNumber)
        .toList();
    final renumbered = [
      for (var i = 0; i < nextSteps.length; i++)
        nextSteps[i].copyWith(step: i + 1),
    ];
    await _updateDocument(project, doc.copyWith(flow: renumbered));
  }

  Future<void> _swapSteps(
    SpecForgeProject project,
    EventStormDocument doc,
    int indexA,
    int indexB,
  ) async {
    final sorted = List<EventStormStep>.from(doc.sortedSteps);
    final moved = sorted.removeAt(indexA);
    sorted.insert(indexB, moved);
    final renumbered = [
      for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(step: i + 1),
    ];
    await _updateDocument(
      project,
      doc.copyWith(flow: renumbered),
      focusStepNumber: indexB + 1,
    );
  }

  Future<void> _toggleHotspotStatus(
    SpecForgeProject project,
    EventStormDocument doc,
    EventStormStep step,
    EventStormHotspot hotspot,
  ) async {
    final nextStatus = hotspot.isResolved
        ? EventStormHotspotStatus.open
        : EventStormHotspotStatus.resolved;
    final updatedStep = step.copyWith(
      hotspots: [
        for (final h in step.hotspots)
          if (h.id == hotspot.id) h.copyWith(status: nextStatus) else h,
      ],
    );
    final nextSteps = [
      for (final s in doc.flow)
        if (s.step == step.step) updatedStep else s,
    ];
    await _updateDocument(
      project,
      doc.copyWith(flow: nextSteps),
      focusStepNumber: step.step,
    );
  }

  Future<void> _addOrEditCatalogItem(
    BuildContext context,
    SpecForgeProject project,
    EventStormDocument doc, {
    required EventStormCatalogCategory category,
    EventStormCatalogItem? item,
  }) async {
    final existingIds = <String>{
      for (final a in doc.catalog.actors) a.id,
      for (final a in doc.catalog.aggregates) a.id,
      for (final e in doc.catalog.externalSystems) e.id,
    };
    if (item != null) existingIds.remove(item.id);

    final saved = await showEventStormCatalogItemDialog(
      context,
      category: category,
      existingIds: existingIds,
      item: item,
    );
    if (saved == null) return;

    List<EventStormCatalogItem> upsert(List<EventStormCatalogItem> list) {
      final copy = List<EventStormCatalogItem>.from(list);
      if (item != null) {
        final idx = copy.indexWhere((x) => x.id == item.id);
        if (idx >= 0) {
          copy[idx] = saved;
          return copy;
        }
      }
      final existingIdx = copy.indexWhere((x) => x.id == saved.id);
      if (existingIdx >= 0) {
        copy[existingIdx] = saved;
      } else {
        copy.add(saved);
      }
      return copy;
    }

    final nextCatalog = switch (category) {
      EventStormCatalogCategory.actor => doc.catalog.copyWith(
        actors: upsert(doc.catalog.actors),
      ),
      EventStormCatalogCategory.aggregate => doc.catalog.copyWith(
        aggregates: upsert(doc.catalog.aggregates),
      ),
      EventStormCatalogCategory.externalSystem => doc.catalog.copyWith(
        externalSystems: upsert(doc.catalog.externalSystems),
      ),
    };
    await _updateDocument(project, doc.copyWith(catalog: nextCatalog));
  }

  Future<void> _deleteCatalogItem(
    SpecForgeProject project,
    EventStormDocument doc, {
    required EventStormCatalogCategory category,
    required String id,
  }) async {
    final nextCatalog = switch (category) {
      EventStormCatalogCategory.actor => doc.catalog.copyWith(
        actors: doc.catalog.actors.where((a) => a.id != id).toList(),
      ),
      EventStormCatalogCategory.aggregate => doc.catalog.copyWith(
        aggregates: doc.catalog.aggregates.where((a) => a.id != id).toList(),
      ),
      EventStormCatalogCategory.externalSystem => doc.catalog.copyWith(
        externalSystems: doc.catalog.externalSystems
            .where((e) => e.id != id)
            .toList(),
      ),
    };
    await _updateDocument(project, doc.copyWith(catalog: nextCatalog));
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final es = project.eventStorming;

    final focusedDocId = widget.controller.focusedEventStormFlowId;
    final selectedDoc =
        (focusedDocId != null ? es.findDocument(focusedDocId) : null) ??
        es.documents.firstOrNull;

    return Column(
      key: const ValueKey('event-storming-editor-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bandeau principal
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
                    'Event Storming (${es.documents.length} contexte(s))',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${es.totalStepCount} étape(s) · ${es.totalEventCount} événement(s) · '
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
                  OutlinedButton.icon(
                    key: const ValueKey('spec-es-help-btn'),
                    onPressed: () => showEventStormCardsHelpDialog(context),
                    icon: const Icon(Icons.help_outline_rounded, size: 16),
                    label: const Text('Aide cartes'),
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
                    onPressed: es.documents.isEmpty
                        ? null
                        : () => _generateBusinessObjects(context),
                    icon: const Icon(Icons.hub_outlined, size: 16),
                    label: const Text('Générer Objets métiers'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('spec-es-import-yaml-btn'),
                    onPressed: () => _importYaml(context),
                    icon: const Icon(Icons.upload_file_outlined, size: 16),
                    label: const Text('Importer .es.yaml'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('spec-es-add-doc-btn'),
                    onPressed: () => _createOrEditDocument(context, project),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Nouveau contexte'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Corps Maître / Détail
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final masterPane = _buildDocumentsMasterList(
                context,
                es.documents,
                selectedDoc,
                theme,
                colors,
              );
              final detailPane = selectedDoc == null
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
                              'Aucun Bounded Context Event Storming (.es.yaml) modélisé.\n'
                              'Amorcez depuis le Cahier des charges, importez un `.es.yaml`, '
                              'créez un contexte ou discutez avec « Event Storming Facilitator » à gauche.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildDocumentDetail(
                      context,
                      project,
                      selectedDoc,
                      theme,
                      colors,
                      isDark,
                    );

              if (constraints.maxWidth >= 560) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 256, child: masterPane),
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

  Widget _buildDocumentsMasterList(
    BuildContext context,
    List<EventStormDocument> docs,
    EventStormDocument? selectedDoc,
    ThemeData theme,
    ColorScheme colors,
  ) {
    if (docs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Aucun Bounded Context.',
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
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final isSelected = selectedDoc?.id == doc.id;
        return Card(
          key: ValueKey('spec-es-doc-tile-${doc.id}'),
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
            onTap: () => widget.controller.focusEventStormFlow(doc.id),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          doc.fileName,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                      if (doc.openHotspotCount > 0)
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
                            '${doc.openHotspotCount} HS',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.onErrorContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    doc.meta.boundedContext,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${doc.meta.format.label} · ${doc.flow.length} étape(s) · ${doc.domainEventCount} évts',
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

  Widget _buildDocumentDetail(
    BuildContext context,
    SpecForgeProject project,
    EventStormDocument doc,
    ThemeData theme,
    ColorScheme colors,
    bool isDark,
  ) {
    final diagnostics = EventStormingDslCodec.validateDocument(
      doc,
      allDocuments: project.eventStorming.documents,
    );
    final errorCount = diagnostics
        .where((d) => d.severity == EventStormDslSeverity.error)
        .length;
    final warningCount = diagnostics
        .where((d) => d.severity == EventStormDslSeverity.warning)
        .length;

    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // En-tête du Bounded Context sélectionné
          Container(
            color: colors.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
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
                            doc.meta.boundedContext,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(doc.fileName),
                            labelStyle: theme.textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(doc.meta.format.yamlValue),
                            labelStyle: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Domaine : ${doc.meta.domain} · Date : ${doc.meta.date}'
                        '${doc.meta.facilitator.isEmpty ? '' : ' · Facilitateur : ${doc.meta.facilitator}'}'
                        ' · DSL v${doc.dslVersion}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Modifier les métadonnées (meta)',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () =>
                      _createOrEditDocument(context, project, document: doc),
                ),
                IconButton(
                  tooltip: 'Supprimer ce Bounded Context',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: () => _deleteDocument(project, doc),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  key: const ValueKey('spec-es-add-step-btn'),
                  onPressed: () => _addOrEditStep(context, project, doc),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Nouvelle étape'),
                ),
              ],
            ),
          ),

          // 3 sous-onglets : Frise & Étapes / Catalogue / YAML & Schéma
          TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Frise & Étapes (${doc.flow.length})'),
              Tab(
                text:
                    'Catalogue (${doc.catalog.actors.length + doc.catalog.aggregates.length + doc.catalog.externalSystems.length})',
              ),
              Tab(
                text: errorCount > 0
                    ? 'YAML (.es.yaml) · $errorCount err'
                    : (warningCount > 0
                          ? 'YAML (.es.yaml) · $warningCount warn'
                          : 'YAML (.es.yaml) ✓'),
              ),
            ],
          ),

          Expanded(
            child: TabBarView(
              children: [
                _buildFlowTimelineTab(
                  context,
                  project,
                  doc,
                  diagnostics,
                  theme,
                  colors,
                  isDark,
                ),
                _buildCatalogTab(context, project, doc, theme, colors, isDark),
                _buildYamlTab(context, project, doc, diagnostics, theme, colors),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowTimelineTab(
    BuildContext context,
    SpecForgeProject project,
    EventStormDocument doc,
    List<EventStormDslDiagnostic> diagnostics,
    ThemeData theme,
    ColorScheme colors,
    bool isDark,
  ) {
    final steps = doc.sortedSteps;
    final focusedStepNum = int.tryParse(
      widget.controller.focusedEventStormNodeId ?? '',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (diagnostics.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: colors.secondaryContainer.withValues(alpha: 0.4),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${diagnostics.length} remarque(s) DSL/grammaire — ${diagnostics.first.message}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: steps.isEmpty
              ? Center(
                  child: Text(
                    'Aucune étape dans `flow[]` pour « ${doc.meta.boundedContext} ».\n'
                    'Cliquez sur « Nouvelle étape » ou demandez à l’agent IA de modéliser le parcours.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Scrollbar(
                    controller: _timelineScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _timelineScrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < steps.length; i++) ...[
                            if (i > 0)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 96,
                                  left: 6,
                                  right: 6,
                                ),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                  color: colors.outline,
                                ),
                              ),
                            EventStormStepColumn(
                              key: ValueKey(
                                'spec-es-step-${doc.id}-${steps[i].step}',
                              ),
                              document: doc,
                              step: steps[i],
                              isFocused: focusedStepNum == steps[i].step,
                              isDark: isDark,
                              onTap: () => widget.controller
                                  .focusEventStormSelection(
                                    flowId: doc.id,
                                    nodeId: steps[i].step.toString(),
                                  ),
                              onMoveLeft: i == 0
                                  ? null
                                  : () => _swapSteps(project, doc, i, i - 1),
                              onMoveRight: i == steps.length - 1
                                  ? null
                                  : () => _swapSteps(project, doc, i, i + 1),
                              onEdit: () => _addOrEditStep(
                                context,
                                project,
                                doc,
                                step: steps[i],
                              ),
                              onDelete: () =>
                                  _deleteStep(project, doc, steps[i].step),
                              onPromotePolicy: steps[i].policy != null
                                  ? () => _promotePolicy(
                                      context,
                                      documentId: doc.id,
                                      stepNumber: steps[i].step,
                                    )
                                  : null,
                              onToggleHotspotStatus: (hs) =>
                                  _toggleHotspotStatus(
                                    project,
                                    doc,
                                    steps[i],
                                    hs,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCatalogTab(
    BuildContext context,
    SpecForgeProject project,
    EventStormDocument doc,
    ThemeData theme,
    ColorScheme colors,
    bool isDark,
  ) {
    Widget section({
      required String title,
      required EventStormCatalogCategory category,
      required List<EventStormCatalogItem> items,
      required EventStormPostItColors palette,
    }) {
      return Card(
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.border.withValues(alpha: 0.65)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: palette.border,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$title (${items.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: ValueKey('spec-es-cat-add-${category.name}'),
                    onPressed: () => _addOrEditCatalogItem(
                      context,
                      project,
                      doc,
                      category: category,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Aucune entrée dans cette catégorie.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final item in items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: palette.border),
                      ),
                      child: Text(
                        item.id,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: palette.foreground,
                        ),
                      ),
                    ),
                    title: Text(item.name),
                    subtitle: item.type != null
                        ? Text('Type : ${item.type!.label} (${item.type!.yamlValue})')
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Modifier',
                          iconSize: 16,
                          onPressed: () => _addOrEditCatalogItem(
                            context,
                            project,
                            doc,
                            category: category,
                            item: item,
                          ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          iconSize: 16,
                          onPressed: () => _deleteCatalogItem(
                            project,
                            doc,
                            category: category,
                            id: item.id,
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          section(
            title: 'Acteurs — Petit Jaune (`ACT-*`)',
            category: EventStormCatalogCategory.actor,
            items: doc.catalog.actors,
            palette: EventStormPostItColors.actor(isDark),
          ),
          section(
            title: 'Agrégats — Grand Jaune (`AGG-*`)',
            category: EventStormCatalogCategory.aggregate,
            items: doc.catalog.aggregates,
            palette: EventStormPostItColors.aggregate(isDark),
          ),
          section(
            title: 'Systèmes externes — Rose pâle (`EXT-*`)',
            category: EventStormCatalogCategory.externalSystem,
            items: doc.catalog.externalSystems,
            palette: EventStormPostItColors.externalSystem(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildYamlTab(
    BuildContext context,
    SpecForgeProject project,
    EventStormDocument doc,
    List<EventStormDslDiagnostic> diagnostics,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final yaml = EventStormingDslCodec.toYaml(doc);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    diagnostics.isEmpty
                        ? Icons.verified_outlined
                        : Icons.warning_amber_rounded,
                    size: 18,
                    color: diagnostics.isEmpty ? Colors.green : colors.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    diagnostics.isEmpty
                        ? '${doc.fileName} — Conforme au schéma DSL v1.0'
                        : '${doc.fileName} — ${diagnostics.length} diagnostic(s)',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: yaml));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(content: Text('${doc.fileName} copié.')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copier YAML'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('spec-es-edit-yaml-btn'),
                    onPressed: () async {
                      final edited = await showEventStormYamlImportDialog(
                        context,
                        initialYaml: yaml,
                        title: 'Éditer ${doc.fileName}',
                      );
                      if (edited == null || !context.mounted) return;
                      await widget.controller.importEventStormingYaml(
                        edited,
                        idHint: doc.id,
                      );
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    label: const Text('Éditer YAML'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('spec-es-view-schema-btn'),
                    onPressed: () => showEventStormSchemaDialog(context),
                    icon: const Icon(Icons.schema_outlined, size: 16),
                    label: const Text('es-dsl.schema.json'),
                  ),
                ],
              ),
            ],
          ),
          if (diagnostics.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 130),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: diagnostics.length,
                itemBuilder: (ctx, i) {
                  final d = diagnostics[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '[${d.severity.name.toUpperCase()} · ${d.code}] ${d.message}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: d.severity == EventStormDslSeverity.error
                            ? colors.error
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  key: const ValueKey('spec-es-yaml-preview'),
                  yaml,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
