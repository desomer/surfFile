/// Dialogues d'édition et d'import/export pour l'atelier Event Storming DSL v1.0
/// ([showEventStormDocumentDialog], [showEventStormCatalogItemDialog],
/// [showEventStormStepDialog], [showEventStormYamlImportDialog],
/// [showEventStormSchemaDialog], [showEventStormCardsHelpDialog]).
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/event_storming_spec.dart';
import '../../../services/event_storming_operations.dart';
import '../../../services/exporters/event_storming_dsl_codec.dart';
import 'event_storming_step_column.dart';

/// Catégorie d'entrée dans le bloc `catalog`.
enum EventStormCatalogCategory {
  /// Acteurs (`ACT-*`, Petit Jaune).
  actor('Acteur', 'ACT'),

  /// Agrégats (`AGG-*`, Grand Jaune).
  aggregate('Agrégat', 'AGG'),

  /// Systèmes externes (`EXT-*`, Rose pâle).
  externalSystem('Système externe', 'EXT');

  /// Construit une catégorie de catalogue.
  const EventStormCatalogCategory(this.label, this.prefix);

  /// Libellé français.
  final String label;

  /// Préfixe d'identifiant (`ACT`, `AGG`, `EXT`).
  final String prefix;
}

/// Ouvre le dialogue de création ou d'édition des métadonnées `meta` d'un
/// [EventStormDocument] (1 fichier `<slug>.es.yaml` par Bounded Context).
Future<EventStormDocument?> showEventStormDocumentDialog(
  BuildContext context, {
  required String defaultDomain,
  required List<EventStormDocument> existingDocuments,
  EventStormDocument? document,
}) async {
  final today = DateTime.now();
  final todayIso =
      '${today.year.toString().padLeft(4, '0')}-'
      '${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';

  final domainCtrl = TextEditingController(
    text: document?.meta.domain ?? defaultDomain,
  );
  final bcCtrl = TextEditingController(
    text: document?.meta.boundedContext ?? '',
  );
  final dateCtrl = TextEditingController(text: document?.meta.date ?? todayIso);
  final facilitatorCtrl = TextEditingController(
    text: document?.meta.facilitator ?? 'Product Owner',
  );
  var format = document?.meta.format ?? EventStormFormat.processModeling;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(
          document == null
              ? 'Nouveau Bounded Context (.es.yaml)'
              : 'Métadonnées — ${document.fileName}',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                TextField(
                  key: const ValueKey('spec-es-doc-domain-field'),
                  controller: domainCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Domaine métier (`meta.domain`) *',
                    hintText: 'E-Commerce',
                  ),
                ),
                TextField(
                  key: const ValueKey('spec-es-doc-bc-field'),
                  controller: bcCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bounded Context (`meta.bounded_context`) *',
                    hintText: 'Gestion des commandes',
                  ),
                ),
                DropdownButtonFormField<EventStormFormat>(
                  initialValue: format,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Format d’atelier (`meta.format`)',
                  ),
                  items: [
                    for (final f in EventStormFormat.values)
                      DropdownMenuItem(
                        value: f,
                        child: Text(
                          '${f.label} (${f.yamlValue})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => format = v);
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Date ISO (`YYYY-MM-DD`) *',
                          hintText: '2026-11-24',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: facilitatorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Facilitateur',
                          hintText: 'Product Owner',
                        ),
                      ),
                    ),
                  ],
                ),
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
            key: const ValueKey('spec-es-doc-save-btn'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true) return null;
  final bcName = bcCtrl.text.trim();
  if (bcName.isEmpty) return null;
  final domain = domainCtrl.text.trim().isEmpty
      ? defaultDomain
      : domainCtrl.text.trim();
  final date = dateCtrl.text.trim().isEmpty ? todayIso : dateCtrl.text.trim();
  final meta = EventStormMeta(
    domain: domain,
    boundedContext: bcName,
    format: format,
    date: date,
    facilitator: facilitatorCtrl.text.trim(),
  );

  if (document != null) {
    return document.copyWith(meta: meta);
  }
  final id = EventStormingOperations.nextDocumentId(bcName, existingDocuments);
  return EventStormDocument(id: id, meta: meta);
}

/// Ouvre le dialogue de création/édition d'une entrée du catalogue (`ACT-*`, `AGG-*`, `EXT-*`).
Future<EventStormCatalogItem?> showEventStormCatalogItemDialog(
  BuildContext context, {
  required EventStormCatalogCategory category,
  required Set<String> existingIds,
  EventStormCatalogItem? item,
}) async {
  final idCtrl = TextEditingController(text: item?.id ?? '');
  final nameCtrl = TextEditingController(text: item?.name ?? '');
  var actorType = item?.type ?? EventStormActorType.human;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(
          item == null
              ? 'Ajouter un ${category.label.toLowerCase()} (${category.prefix}-*)'
              : 'Modifier ${item.id}',
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              TextField(
                key: const ValueKey('spec-es-cat-name-field'),
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Nom *',
                  hintText: switch (category) {
                    EventStormCatalogCategory.actor => 'Client',
                    EventStormCatalogCategory.aggregate => 'Commande',
                    EventStormCatalogCategory.externalSystem => 'Stripe',
                  },
                ),
                onChanged: (val) {
                  if (item == null && val.trim().isNotEmpty) {
                    idCtrl.text = EventStormingOperations.nextCatalogId(
                      category.prefix,
                      val,
                      existingIds,
                    );
                  }
                },
              ),
              TextField(
                key: const ValueKey('spec-es-cat-id-field'),
                controller: idCtrl,
                decoration: InputDecoration(
                  labelText: 'Identifiant canonique (${category.prefix}-*) *',
                  hintText: '${category.prefix}-EXEMPLE',
                ),
              ),
              if (category == EventStormCatalogCategory.actor)
                DropdownButtonFormField<EventStormActorType>(
                  initialValue: actorType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Type d’acteur (`type`)',
                  ),
                  items: [
                    for (final t in EventStormActorType.values)
                      DropdownMenuItem(
                        value: t,
                        child: Text(
                          '${t.label} (${t.yamlValue})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => actorType = v);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('spec-es-cat-save-btn'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true) return null;
  final name = nameCtrl.text.trim();
  if (name.isEmpty) return null;
  final id = idCtrl.text.trim().isEmpty
      ? EventStormingOperations.nextCatalogId(
          category.prefix,
          name,
          existingIds,
        )
      : idCtrl.text.trim().toUpperCase();
  return EventStormCatalogItem(
    id: id,
    name: name,
    type: category == EventStormCatalogCategory.actor ? actorType : null,
  );
}

/// Ouvre le dialogue complet d'édition d'une étape chronologique (`EventStormStep`).
Future<EventStormStep?> showEventStormStepDialog(
  BuildContext context, {
  required EventStormDocument document,
  EventStormStep? step,
}) async {
  final nextStepNum =
      step?.step ??
      (document.flow.isEmpty
          ? 1
          : document.sortedSteps.last.step + 1);
  final defaultEvtId =
      step?.domainEvent?.id ?? EventStormingOperations.nextEventId(document);

  final stepNumCtrl = TextEditingController(text: '$nextStepNum');
  final epicCtrl = TextEditingController(text: step?.backlog?.epic ?? '');
  final storyCtrl = TextEditingController(text: step?.backlog?.story ?? '');

  // Déclencheur (`triggered_by`)
  var triggerKind = step?.triggeredBy == null
      ? 'none'
      : step!.triggeredBy!.mode.yamlKey;
  final triggerEventsCtrl = TextEditingController(
    text: step?.triggeredBy?.eventIds.join(', ') ?? '',
  );

  // Read Model
  final rmNameCtrl = TextEditingController(text: step?.readModel?.name ?? '');
  final rmSourceCtrl = TextEditingController(
    text: step?.readModel?.sourceEvents.join(', ') ?? '',
  );
  final rmFieldsCtrl = TextEditingController(
    text: step?.readModel?.fields.join(', ') ?? '',
  );

  // Acteur / Politique
  var selectedActor = step?.actor ?? '';
  final polNameCtrl = TextEditingController(text: step?.policy?.name ?? '');
  final polRuleCtrl = TextEditingController(text: step?.policy?.rule ?? '');

  // Commande + Cible
  final cmdNameCtrl = TextEditingController(text: step?.command.name ?? '');
  final cmdPayloadCtrl = TextEditingController(
    text: step?.command.payload.join(', ') ?? '',
  );
  var selectedAggregate = step?.aggregate ?? '';
  var selectedExternal = step?.externalSystem ?? '';

  // Sortie : domain_event XOR outcomes
  var useOutcomes = step?.hasOutcomes ?? false;
  final evtIdCtrl = TextEditingController(text: defaultEvtId);
  final evtNameCtrl = TextEditingController(text: step?.domainEvent?.name ?? '');
  final evtDataCtrl = TextEditingController(
    text: step?.domainEvent?.data.join(', ') ?? '',
  );

  final outcomeDrafts = <_OutcomeDraft>[
    if (step != null && step.outcomes.isNotEmpty)
      for (final o in step.outcomes)
        _OutcomeDraft(
          condition: TextEditingController(text: o.condition),
          isError: o.isError,
          eventId: TextEditingController(text: o.domainEvent.id),
          eventName: TextEditingController(text: o.domainEvent.name),
          eventData: TextEditingController(text: o.domainEvent.data.join(', ')),
        )
    else ...[
      _OutcomeDraft(
        condition: TextEditingController(text: 'Condition nominale vérifiée'),
        isError: false,
        eventId: TextEditingController(
          text: 'EVT-${nextStepNum.toString().padLeft(2, '0')}A',
        ),
        eventName: TextEditingController(text: ''),
        eventData: TextEditingController(text: ''),
      ),
      _OutcomeDraft(
        condition: TextEditingController(text: 'Cas d’erreur ou refus'),
        isError: true,
        eventId: TextEditingController(
          text: 'EVT-${nextStepNum.toString().padLeft(2, '0')}B',
        ),
        eventName: TextEditingController(text: ''),
        eventData: TextEditingController(text: ''),
      ),
    ],
  ];

  // Hotspots
  final hotspotDrafts = <_HotspotDraft>[
    if (step != null)
      for (final h in step.hotspots)
        _HotspotDraft(
          id: TextEditingController(text: h.id),
          question: TextEditingController(text: h.question),
          severity: h.severity,
          owner: TextEditingController(text: h.owner),
          status: h.status,
        ),
  ];

  final availableEventIds = [for (final e in document.allDomainEvents) e.id];
  String? validationError;

  final result = await showDialog<EventStormStep>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                step == null
                    ? 'Nouvelle étape (Step $nextStepNum)'
                    : 'Modifier Step ${step.step}',
              ),
            ),
            IconButton(
              key: const ValueKey('spec-es-step-help-btn'),
              tooltip: 'Aide : rôle et usage des cartes',
              icon: const Icon(Icons.help_outline_rounded, size: 20),
              onPressed: () => showEventStormCardsHelpDialog(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: 620,
          height: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                if (validationError != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      validationError!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),

                // Étape + Backlog
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: stepNumCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Step *'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: epicCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Backlog Epic',
                          hintText: 'EPIC-01',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: storyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Backlog Story',
                          hintText: 'US-101',
                        ),
                      ),
                    ),
                  ],
                ),

                // Déclencheur causal (`triggered_by`)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: triggerKind,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Déclencheur (`triggered_by`)',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'none',
                            child: Text(
                              'Aucun',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'single',
                            child: Text(
                              'Événement simple (EVT-* / CTX:EVT-*)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'all_of',
                            child: Text(
                              'Synchronisation ET (all_of)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'any_of',
                            child: Text(
                              'Convergence OU (any_of)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => triggerKind = v);
                        },
                      ),
                    ),
                    if (triggerKind != 'none') ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: triggerEventsCtrl,
                          decoration: InputDecoration(
                            labelText: triggerKind == 'single'
                                ? 'ID événement (ex. EVT-01 ou CMD:EVT-02A)'
                                : 'IDs séparés par virgules (min 2)',
                            helperText: availableEventIds.isEmpty
                                ? null
                                : 'Locaux : ${availableEventIds.join(', ')}',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                // Commande (Bleu — obligatoire)
                const Divider(),
                Text(
                  'Commande (Bleu — verbe à l’infinitif)',
                  style: Theme.of(ctx).textTheme.labelLarge,
                ),
                TextField(
                  key: const ValueKey('spec-es-step-cmd-name-field'),
                  controller: cmdNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la commande *',
                    hintText: 'Valider le panier',
                  ),
                ),
                TextField(
                  controller: cmdPayloadCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Payload (champs séparés par virgules)',
                    hintText: 'panier_id, mode_paiement_id',
                  ),
                ),

                // Acteur / Agrégat / Système externe (depuis catalog)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            document.catalog.actors.any(
                              (a) => a.id == selectedActor,
                            )
                            ? selectedActor
                            : '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Acteur (`ACT-*`)',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text(
                              'Aucun',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          for (final a in document.catalog.actors)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.id} · ${a.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setLocal(() => selectedActor = v ?? ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            document.catalog.aggregates.any(
                              (a) => a.id == selectedAggregate,
                            )
                            ? selectedAggregate
                            : '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Agrégat (`AGG-*`)',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text(
                              'Aucun',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          for (final a in document.catalog.aggregates)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.id} · ${a.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setLocal(() => selectedAggregate = v ?? ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            document.catalog.externalSystems.any(
                              (e) => e.id == selectedExternal,
                            )
                            ? selectedExternal
                            : '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Système externe (`EXT-*`)',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text(
                              'Aucun',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          for (final e in document.catalog.externalSystems)
                            DropdownMenuItem(
                              value: e.id,
                              child: Text(
                                '${e.id} · ${e.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setLocal(() => selectedExternal = v ?? ''),
                      ),
                    ),
                  ],
                ),

                // Politique (Violet — optionnel)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Politique réactive (Violet — optionnel)'),
                  initiallyExpanded: step?.policy != null,
                  children: [
                    TextField(
                      controller: polNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nom de la politique',
                        hintText: 'Déclencher l’encaissement',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: polRuleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Règle (`Quand ..., alors ...`)',
                        hintText:
                            'Quand Panier validé, alors Demander le paiement',
                      ),
                    ),
                  ],
                ),

                // Read Model (Vert — optionnel)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Read Model / Écran (Vert — optionnel)'),
                  initiallyExpanded: step?.readModel != null,
                  children: [
                    TextField(
                      controller: rmNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nom du Read Model',
                        hintText: 'Écran récapitulatif panier',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: rmSourceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Événements sources (`source_events`)',
                        hintText: 'EVT-00',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: rmFieldsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Champs affichés (`fields`)',
                        hintText: 'lignes_panier, montant_ttc',
                      ),
                    ),
                  ],
                ),

                // Sortie : domain_event XOR outcomes
                const Divider(),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      'Sortie (Orange — passé composé)',
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Événement')),
                        ButtonSegment(value: true, label: Text('Outcomes (OU)')),
                      ],
                      selected: {useOutcomes},
                      onSelectionChanged: (s) =>
                          setLocal(() => useOutcomes = s.first),
                    ),
                  ],
                ),
                if (!useOutcomes) ...[
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: evtIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ID (`EVT-*`) *',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('spec-es-step-evt-name-field'),
                          controller: evtNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nom au passé composé *',
                            hintText: 'Panier validé',
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: evtDataCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Données émises (`data`)',
                      hintText: 'commande_id, montant_ttc',
                    ),
                  ),
                ] else ...[
                  for (var i = 0; i < outcomeDrafts.length; i++)
                    Card(
                      elevation: 0,
                      color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          spacing: 6,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Branche ${i + 1}',
                                  style: Theme.of(ctx).textTheme.labelMedium,
                                ),
                                const Spacer(),
                                Checkbox(
                                  value: outcomeDrafts[i].isError,
                                  onChanged: (v) => setLocal(
                                    () => outcomeDrafts[i].isError = v == true,
                                  ),
                                ),
                                const Text('Erreur (`is_error`)'),
                                if (outcomeDrafts.length > 2)
                                  IconButton(
                                    iconSize: 16,
                                    onPressed: () => setLocal(
                                      () => outcomeDrafts.removeAt(i),
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                            TextField(
                              controller: outcomeDrafts[i].condition,
                              decoration: const InputDecoration(
                                labelText: 'Condition *',
                              ),
                            ),
                            Row(
                              children: [
                                SizedBox(
                                  width: 110,
                                  child: TextField(
                                    controller: outcomeDrafts[i].eventId,
                                    decoration: const InputDecoration(
                                      labelText: 'ID `EVT-*` *',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: outcomeDrafts[i].eventName,
                                    decoration: const InputDecoration(
                                      labelText: 'Événement (passé composé) *',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TextField(
                              controller: outcomeDrafts[i].eventData,
                              decoration: const InputDecoration(
                                labelText: 'Données (`data`)',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setLocal(() {
                        final letter = String.fromCharCode(
                          65 + (outcomeDrafts.length % 26),
                        );
                        outcomeDrafts.add(
                          _OutcomeDraft(
                            condition: TextEditingController(),
                            isError: false,
                            eventId: TextEditingController(
                              text:
                                  'EVT-${nextStepNum.toString().padLeft(2, '0')}$letter',
                            ),
                            eventName: TextEditingController(),
                            eventData: TextEditingController(),
                          ),
                        );
                      }),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Ajouter une branche outcome'),
                    ),
                  ),
                ],

                // Hotspots (Rose vif)
                const Divider(),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      'Hotspots (Rose vif — ${hotspotDrafts.length})',
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    TextButton.icon(
                      onPressed: () => setLocal(() {
                        final nextNum =
                            document.allHotspots.length +
                            hotspotDrafts.length +
                            1;
                        hotspotDrafts.add(
                          _HotspotDraft(
                            id: TextEditingController(
                              text: 'HS-${nextNum.toString().padLeft(2, '0')}',
                            ),
                            question: TextEditingController(),
                            severity: EventStormHotspotSeverity.medium,
                            owner: TextEditingController(),
                            status: EventStormHotspotStatus.open,
                          ),
                        );
                      }),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Ajouter hotspot'),
                    ),
                  ],
                ),
                for (var i = 0; i < hotspotDrafts.length; i++)
                  Card(
                    elevation: 0,
                    color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        spacing: 6,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 95,
                                child: TextField(
                                  controller: hotspotDrafts[i].id,
                                  decoration: const InputDecoration(
                                    labelText: 'ID `HS-*`',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<
                                  EventStormHotspotSeverity
                                >(
                                  initialValue: hotspotDrafts[i].severity,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Sévérité',
                                  ),
                                  items: [
                                    for (final s
                                        in EventStormHotspotSeverity.values)
                                      DropdownMenuItem(
                                        value: s,
                                        child: Text(
                                          s.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      setLocal(
                                        () => hotspotDrafts[i].severity = v,
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<
                                  EventStormHotspotStatus
                                >(
                                  initialValue: hotspotDrafts[i].status,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Statut',
                                  ),
                                  items: [
                                    for (final s
                                        in EventStormHotspotStatus.values)
                                      DropdownMenuItem(
                                        value: s,
                                        child: Text(
                                          s.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      setLocal(
                                        () => hotspotDrafts[i].status = v,
                                      );
                                    }
                                  },
                                ),
                              ),
                              IconButton(
                                iconSize: 16,
                                onPressed: () => setLocal(
                                  () => hotspotDrafts.removeAt(i),
                                ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          TextField(
                            controller: hotspotDrafts[i].question,
                            decoration: const InputDecoration(
                              labelText: 'Question / risque *',
                            ),
                          ),
                          TextField(
                            controller: hotspotDrafts[i].owner,
                            decoration: const InputDecoration(
                              labelText: 'Owner',
                            ),
                          ),
                        ],
                      ),
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
            key: const ValueKey('spec-es-step-save-btn'),
            onPressed: () {
              try {
                final built = _buildStepFromControllers(
                  stepNumCtrl: stepNumCtrl,
                  epicCtrl: epicCtrl,
                  storyCtrl: storyCtrl,
                  triggerKind: triggerKind,
                  triggerEventsCtrl: triggerEventsCtrl,
                  rmNameCtrl: rmNameCtrl,
                  rmSourceCtrl: rmSourceCtrl,
                  rmFieldsCtrl: rmFieldsCtrl,
                  selectedActor: selectedActor,
                  polNameCtrl: polNameCtrl,
                  polRuleCtrl: polRuleCtrl,
                  cmdNameCtrl: cmdNameCtrl,
                  cmdPayloadCtrl: cmdPayloadCtrl,
                  selectedAggregate: selectedAggregate,
                  selectedExternal: selectedExternal,
                  useOutcomes: useOutcomes,
                  evtIdCtrl: evtIdCtrl,
                  evtNameCtrl: evtNameCtrl,
                  evtDataCtrl: evtDataCtrl,
                  outcomeDrafts: outcomeDrafts,
                  hotspotDrafts: hotspotDrafts,
                );
                Navigator.of(ctx).pop(built);
              } on FormatException catch (e) {
                setLocal(() => validationError = e.message);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );

  return result;
}

/// Ouvre le dialogue d'import ou d'édition directe d'un fichier `.es.yaml`.
Future<String?> showEventStormYamlImportDialog(
  BuildContext context, {
  String initialYaml = '',
  String title = 'Importer un fichier Event Storming (.es.yaml)',
}) async {
  final ctrl = TextEditingController(text: initialYaml);
  String? errorMsg;

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 640,
          height: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              if (errorMsg != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    errorMsg!,
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onErrorContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
              Expanded(
                child: TextField(
                  key: const ValueKey('spec-es-yaml-input-field'),
                  controller: ctrl,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    hintText:
                        '# yaml-language-server: \$schema=./es-dsl.schema.json\nevent_storming:\n  dsl_version: "1.0"\n  ...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('spec-es-yaml-apply-btn'),
            onPressed: () {
              try {
                EventStormingDslCodec.fromYaml(ctrl.text);
                Navigator.of(ctx).pop(ctrl.text);
              } on FormatException catch (e) {
                setLocal(() => errorMsg = e.message);
              }
            },
            child: const Text('Valider & Appliquer'),
          ),
        ],
      ),
    ),
  );

  return result;
}

/// Ouvre le dialogue de consultation/copie du schéma JSON `es-dsl.schema.json`.
Future<void> showEventStormSchemaDialog(BuildContext context) async {
  final schemaJson = EventStormingDslCodec.esDslSchemaJson;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Schéma JSON — es-dsl.schema.json (DSL v1.0)'),
      content: SizedBox(
        width: 640,
        height: 480,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              schemaJson,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: schemaJson));
            ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
              const SnackBar(content: Text('Schéma es-dsl.schema.json copié.')),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copier JSON Schema'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

/// Ouvre le guide visuel expliquant le rôle, l'usage et les conventions de chaque
/// type de carte (post-it) et connecteur de l'atelier Event Storming DSL v1.0.
Future<void> showEventStormCardsHelpDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final colors = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;

      final cards = <_EventStormCardHelpInfo>[
        _EventStormCardHelpInfo(
          badge: 'ACTEUR',
          colorName: 'Petit Jaune · ACT-*',
          requirement: 'Catalogue · Optionnel',
          palette: EventStormPostItColors.actor(isDark),
          role:
              'Représente qui (ou quoi) déclenche une commande : utilisateur humain (human), tâche planifiée/CRON (timer) ou automate interne (system).',
          usage:
              'Déclaré dans l’onglet Catalogue puis référencé par son code ACT-* dans les étapes initiées par un acteur (souvent après consultation d’un Read Model). Omis lorsqu’une étape est déclenchée automatiquement par une Politique.',
          example:
              'ACT-CLIENT · « Client » (human) ou ACT-CRON-RELANCE (timer)',
        ),
        _EventStormCardHelpInfo(
          badge: 'READ MODEL',
          colorName: 'Vert · read_model',
          requirement: 'Optionnel',
          palette: EventStormPostItColors.readModel(isDark),
          role:
              'Vue, écran ou projection de données consultée par l’acteur pour prendre sa décision avant de lancer une commande.',
          usage:
              'Indique les événements sources qui alimentent la vue (source_events) et les champs affichés (fields). Prépare la conception des écrans UX et des DTO de lecture.',
          example:
              '« Écran récapitulatif panier » ← EVT-00 (champs : lignes_panier, montant_ttc)',
        ),
        _EventStormCardHelpInfo(
          badge: 'POLITIQUE',
          colorName: 'Violet · policy',
          requirement: 'Optionnel',
          palette: EventStormPostItColors.policy(isDark),
          role:
              'Règle métier réactive automatique qui réagit à un ou plusieurs événements passés pour déclencher une nouvelle commande sans action humaine directe.',
          usage:
              'Formulée selon le modèle « Quand [événement], alors [commande] ». Le bouton « Promouvoir RG » permet de transformer une politique en règle de gestion RG-xxx.',
          example:
              '« Déclencher l’encaissement » — Quand Panier validé, alors Demander le paiement',
        ),
        _EventStormCardHelpInfo(
          badge: 'COMMANDE',
          colorName: 'Bleu · command',
          requirement: 'Obligatoire',
          palette: EventStormPostItColors.command(isDark),
          role:
              'Intention d’action ou ordre envoyé au système pour provoquer un changement d’état.',
          usage:
              'Cœur de chaque étape. Doit impérativement être formulée avec un verbe à l’infinitif et préciser ses paramètres d’entrée (payload).',
          example:
              '« Valider le panier » (payload : panier_id, mode_paiement_id)',
        ),
        _EventStormCardHelpInfo(
          badge: 'AGRÉGAT',
          colorName: 'Grand Jaune · AGG-*',
          requirement: 'Catalogue · Optionnel',
          palette: EventStormPostItColors.aggregate(isDark),
          role:
              'Entité ou groupe d’entités métier qui reçoit la commande, vérifie les invariants métier et émet les événements de domaine.',
          usage:
              'Déclaré dans le Catalogue (AGG-*). Le bouton « Générer Objets métiers » exploite vos agrégats et événements pour créer/enrichir les objets de l’étape suivante.',
          example: 'AGG-COMMANDE · « Commande », AGG-STOCK · « StockProduit »',
        ),
        _EventStormCardHelpInfo(
          badge: 'SYSTÈME EXTERNE',
          colorName: 'Rose pâle · EXT-*',
          requirement: 'Catalogue · Optionnel',
          palette: EventStormPostItColors.externalSystem(isDark),
          role:
              'Service, API ou partenaire tiers hors du contrôle direct du domaine (prestataire de paiement, service d’e-mailing, ERP, transporteur…).',
          usage:
              'Déclaré dans le Catalogue (EXT-*) puis associé aux étapes qui délèguent ou notifient un outil externe, souvent avec des outcomes succès/échec.',
          example:
              'EXT-STRIPE · « Stripe », EXT-EMAIL · « Service Notification Email »',
        ),
        _EventStormCardHelpInfo(
          badge: 'ÉVÉNEMENT',
          colorName: 'Orange · domain_event',
          requirement: 'Sortie (exclusif avec Outcomes)',
          palette: EventStormPostItColors.domainEvent(isDark),
          role:
              'Fait métier accompli et immuable produit après exécution de la commande. Sert de déclencheur (triggered_by) aux étapes suivantes.',
          usage:
              'Identifié EVT-01, EVT-02… et formulé impérativement au passé composé avec les données émises (data). Utilisé lorsque l’étape produit un résultat unique (sinon utiliser Outcomes).',
          example:
              'EVT-01 · « Panier validé » (data : commande_id, montant_ttc)',
        ),
        _EventStormCardHelpInfo(
          badge: 'OUTCOMES (OU)',
          colorName: 'Orange / Orange foncé · outcomes[]',
          requirement: 'Sortie (min 2 branches)',
          palette: EventStormPostItColors.errorOutcome(isDark),
          role:
              'Embranchement OU exclusif représentant plusieurs issues possibles d’une même commande (cas nominal vs refus ou erreur métier).',
          usage:
              'Remplace domain_event lorsqu’une commande peut aboutir à au moins 2 issues distinctes. Chaque branche porte une condition, un indicateur Erreur (is_error) et son événement (EVT-02A, EVT-02B…).',
          example:
              'EVT-02A « Commande payée » (succès) ou EVT-02B « Paiement refusé » (is_error: true)',
        ),
        _EventStormCardHelpInfo(
          badge: 'HOTSPOT',
          colorName: 'Rose vif · hotspots[]',
          requirement: 'Optionnel (0..n)',
          palette: EventStormPostItColors.hotspot(isDark),
          role:
              'Signale une question ouverte, une zone d’ombre métier, un désaccord ou un risque technique à trancher.',
          usage:
              'Identifié HS-01… avec une sévérité (Faible à Bloquant), un responsable (owner) et un statut (Ouvert / Résolu) activable directement sur la carte.',
          example:
              'HS-01 · « Appliquer le code promo avant ou après les frais de port ? »',
        ),
      ];

      return AlertDialog(
        key: const ValueKey('spec-es-help-dialog'),
        title: Row(
          children: [
            Icon(
              Icons.help_outline_rounded,
              size: 22,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Guide des cartes Event Storming (DSL v1.0)'),
            ),
          ],
        ),
        content: SizedBox(
          width: 720,
          height: 540,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: [
                      Text(
                        'Comment lire une étape sur la frise chronologique ?',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'La frise se lit chronologiquement de gauche à droite (Step 1 → Step 2 → …). '
                        'Chaque colonne suit l’enchaînement causal : Déclencheur → Read Model → Acteur / Politique → Commande → Agrégat / Système externe → Événement (ou Outcomes) + Hotspots.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final card in cards)
                  _EventStormCardHelpTile(info: card),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: [
                      Text(
                        'Connecteurs & structure du document',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '• Déclencheur causal (triggered_by) : relie une étape à un événement simple (EVT-01), un événement d’un autre Bounded Context (CMD:EVT-02A), une synchronisation ET (all_of : attend tous les événements) ou une convergence OU (any_of : déclenché par l’un des événements). Deux étapes partageant le même déclencheur s’exécutent en parallèle.',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        '• Backlog (EPIC / Story) : rattache chaque étape à son Epic et à sa User Story PO.',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        '• Bounded Context (.es.yaml) : 1 contexte borné = 1 fichier YAML autonome avec son propre Catalogue (ACT-*, AGG-*, EXT-*) et sa frise flow[].',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('spec-es-help-close-btn'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      );
    },
  );
}

class _EventStormCardHelpInfo {
  const _EventStormCardHelpInfo({
    required this.badge,
    required this.colorName,
    required this.requirement,
    required this.palette,
    required this.role,
    required this.usage,
    required this.example,
  });

  final String badge;
  final String colorName;
  final String requirement;
  final EventStormPostItColors palette;
  final String role;
  final String usage;
  final String example;
}

class _EventStormCardHelpTile extends StatelessWidget {
  const _EventStormCardHelpTile({required this.info});

  final _EventStormCardHelpInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: info.palette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: info.palette.border, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: info.palette.badgeBackground,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  info.badge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: info.palette.foreground,
                  ),
                ),
              ),
              Text(
                info.colorName,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: info.palette.foreground,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: info.palette.border.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  info.requirement,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(
                color: info.palette.foreground,
              ),
              children: [
                const TextSpan(
                  text: 'Rôle : ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: info.role),
              ],
            ),
          ),
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(
                color: info.palette.foreground,
              ),
              children: [
                const TextSpan(
                  text: 'Usage : ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: info.usage),
              ],
            ),
          ),
          Text.rich(
            TextSpan(
              style: theme.textTheme.labelSmall?.copyWith(
                color: info.palette.foreground.withValues(alpha: 0.9),
                fontStyle: FontStyle.italic,
              ),
              children: [
                const TextSpan(
                  text: 'Exemple : ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.normal,
                  ),
                ),
                TextSpan(text: info.example),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

EventStormStep _buildStepFromControllers({
  required TextEditingController stepNumCtrl,
  required TextEditingController epicCtrl,
  required TextEditingController storyCtrl,
  required String triggerKind,
  required TextEditingController triggerEventsCtrl,
  required TextEditingController rmNameCtrl,
  required TextEditingController rmSourceCtrl,
  required TextEditingController rmFieldsCtrl,
  required String selectedActor,
  required TextEditingController polNameCtrl,
  required TextEditingController polRuleCtrl,
  required TextEditingController cmdNameCtrl,
  required TextEditingController cmdPayloadCtrl,
  required String selectedAggregate,
  required String selectedExternal,
  required bool useOutcomes,
  required TextEditingController evtIdCtrl,
  required TextEditingController evtNameCtrl,
  required TextEditingController evtDataCtrl,
  required List<_OutcomeDraft> outcomeDrafts,
  required List<_HotspotDraft> hotspotDrafts,
}) {
  final stepNum = int.tryParse(stepNumCtrl.text.trim()) ?? 0;
  if (stepNum < 1) {
    throw const FormatException('Le numéro d’étape doit être >= 1.');
  }
  final cmdName = cmdNameCtrl.text.trim();
  if (cmdName.isEmpty) {
    throw const FormatException('Le nom de la commande est obligatoire.');
  }

  EventStormTrigger? trigger;
  final trigTokens = _splitCsv(triggerEventsCtrl.text);
  if (triggerKind == 'single' && trigTokens.isNotEmpty) {
    trigger = EventStormTrigger.single(trigTokens.first);
  } else if (triggerKind == 'all_of') {
    trigger = EventStormTrigger.allOf(trigTokens);
  } else if (triggerKind == 'any_of') {
    trigger = EventStormTrigger.anyOf(trigTokens);
  }

  final epic = epicCtrl.text.trim();
  final story = storyCtrl.text.trim();
  final backlog = (epic.isNotEmpty || story.isNotEmpty)
      ? EventStormBacklog(epic: epic, story: story)
      : null;

  final rmName = rmNameCtrl.text.trim();
  final readModel = rmName.isEmpty
      ? null
      : EventStormReadModel(
          name: rmName,
          sourceEvents: _splitCsv(rmSourceCtrl.text),
          fields: _splitCsv(rmFieldsCtrl.text),
        );

  final polName = polNameCtrl.text.trim();
  final polRule = polRuleCtrl.text.trim();
  final policy = (polName.isNotEmpty || polRule.isNotEmpty)
      ? EventStormPolicy(
          name: polName.isNotEmpty ? polName : polRule,
          rule: polRule.isNotEmpty ? polRule : polName,
        )
      : null;

  EventStormDomainEvent? domainEvent;
  final outcomes = <EventStormOutcome>[];
  if (!useOutcomes) {
    final evtId = evtIdCtrl.text.trim();
    final evtName = evtNameCtrl.text.trim();
    if (evtId.isEmpty || evtName.isEmpty) {
      throw const FormatException(
        'Renseignez l’ID (`EVT-*`) et le nom de l’événement domaine.',
      );
    }
    domainEvent = EventStormDomainEvent(
      id: evtId,
      name: evtName,
      data: _splitCsv(evtDataCtrl.text),
    );
  } else {
    for (final d in outcomeDrafts) {
      final cond = d.condition.text.trim();
      final eId = d.eventId.text.trim();
      final eName = d.eventName.text.trim();
      if (cond.isEmpty || eId.isEmpty || eName.isEmpty) {
        throw const FormatException(
          'Chaque branche outcome doit renseigner condition, ID EVT-* et nom.',
        );
      }
      outcomes.add(
        EventStormOutcome(
          condition: cond,
          isError: d.isError,
          domainEvent: EventStormDomainEvent(
            id: eId,
            name: eName,
            data: _splitCsv(d.eventData.text),
          ),
        ),
      );
    }
  }

  final hotspots = <EventStormHotspot>[
    for (final h in hotspotDrafts)
      if (h.question.text.trim().isNotEmpty)
        EventStormHotspot(
          id: h.id.text.trim().isEmpty ? 'HS-01' : h.id.text.trim(),
          question: h.question.text.trim(),
          severity: h.severity,
          owner: h.owner.text.trim(),
          status: h.status,
        ),
  ];

  final step = EventStormStep(
    step: stepNum,
    backlog: backlog,
    triggeredBy: trigger,
    policy: policy,
    readModel: readModel,
    actor: selectedActor,
    command: EventStormCommand(
      name: cmdName,
      payload: _splitCsv(cmdPayloadCtrl.text),
    ),
    aggregate: selectedAggregate,
    externalSystem: selectedExternal,
    domainEvent: domainEvent,
    outcomes: outcomes,
    hotspots: hotspots,
  );
  step.validate();
  return step;
}

List<String> _splitCsv(String raw) => [
  for (final part in raw.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

class _OutcomeDraft {
  _OutcomeDraft({
    required this.condition,
    required this.isError,
    required this.eventId,
    required this.eventName,
    required this.eventData,
  });

  final TextEditingController condition;
  bool isError;
  final TextEditingController eventId;
  final TextEditingController eventName;
  final TextEditingController eventData;
}

class _HotspotDraft {
  _HotspotDraft({
    required this.id,
    required this.question,
    required this.severity,
    required this.owner,
    required this.status,
  });

  final TextEditingController id;
  final TextEditingController question;
  EventStormHotspotSeverity severity;
  final TextEditingController owner;
  EventStormHotspotStatus status;
}
