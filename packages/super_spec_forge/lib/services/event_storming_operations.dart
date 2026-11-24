/// Opérations métier déterministes pour l'Event Storming DSL v1.0
/// ([EventStormingOperations]) : amorçage depuis le Cahier des charges,
/// synthèse/enrichissement des objets métiers depuis les agrégats (`AGG-*`) &
/// événements (`EVT-*` / `outcomes`), promotion des politiques en règles
/// `RG-xxx` et import de fichiers `.es.yaml`.
library;

import 'package:shortid/shortid.dart';

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/event_storming_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_forge_project.dart';
import 'exporters/event_storming_dsl_codec.dart';

/// Services déterministes manipulant [EventStormingSpec] (DSL v1.0) et ses
/// passerelles avec [SpecCahierDesCharges], [BusinessObjectSpec] et
/// [BusinessRuleSpec].
abstract final class EventStormingOperations {
  /// Génère le prochain identifiant d'événement `EVT-xx` non utilisé dans [doc].
  static String nextEventId(EventStormDocument doc) {
    final pattern = RegExp(r'^EVT-(\d+)[A-Z]?$', caseSensitive: false);
    var maxIndex = 0;
    for (final evt in doc.allDomainEvents) {
      final match = pattern.firstMatch(evt.id.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'EVT-${(maxIndex + 1).toString().padLeft(2, '0')}';
  }

  /// Génère le prochain identifiant de hotspot `HS-xx` non utilisé dans [doc].
  static String nextHotspotId(EventStormDocument doc) {
    final pattern = RegExp(r'^HS-(\d+)$', caseSensitive: false);
    var maxIndex = 0;
    for (final entry in doc.allHotspots) {
      final match = pattern.firstMatch(entry.hotspot.id.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'HS-${(maxIndex + 1).toString().padLeft(2, '0')}';
  }

  /// Génère un identifiant de catalogue canonique (`ACT-*`, `AGG-*` ou `EXT-*`)
  /// unique dans [existingIds].
  static String nextCatalogId(
    String prefix,
    String name,
    Set<String> existingIds,
  ) {
    final token = _foldAccents(name)
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = '$prefix-${token.isEmpty ? 'ITEM' : token}';
    if (!existingIds.contains(base)) return base;
    var suffix = 2;
    while (existingIds.contains('${base}_$suffix')) {
      suffix++;
    }
    return '${base}_$suffix';
  }

  /// Génère un slug de fichier unique pour un Bounded Context.
  static String nextDocumentId(
    String boundedContextName,
    List<EventStormDocument> existing,
  ) {
    final base = _toSlug(boundedContextName);
    final used = {for (final d in existing) d.id.toLowerCase()};
    if (!used.contains(base)) return base;
    var idx = 2;
    while (used.contains('$base-$idx')) {
      idx++;
    }
    return '$base-$idx';
  }

  /// Génère le prochain code séquentiel `RG-xxx` non utilisé dans [existing].
  static String nextRuleCode(List<BusinessRuleSpec> existing) {
    final pattern = RegExp(r'^RG-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final rule in existing) {
      final match = pattern.firstMatch(rule.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'RG-${(maxIndex + 1).toString().padLeft(3, '0')}';
  }

  /// Parse un contenu `.es.yaml` et l'ajoute ou met à jour dans [current].
  static ({EventStormingSpec updated, EventStormDocument document, bool createdNew})
  upsertDocumentFromYaml(
    EventStormingSpec current,
    String yamlContent, {
    String? idHint,
  }) {
    final parsed = EventStormingDslCodec.fromYaml(yamlContent, idHint: idHint);
    final docs = List<EventStormDocument>.from(current.documents);
    final existingIdx = docs.indexWhere(
      (d) =>
          d.id.toLowerCase() == parsed.id.toLowerCase() ||
          d.meta.boundedContext.toLowerCase() ==
              parsed.meta.boundedContext.toLowerCase(),
    );
    if (existingIdx >= 0) {
      final normalized = parsed.copyWith(id: docs[existingIdx].id);
      docs[existingIdx] = normalized;
      final updated = current.copyWith(documents: docs);
      updated.validate();
      return (updated: updated, document: normalized, createdNew: false);
    }
    final uniqueId = nextDocumentId(parsed.id, docs);
    final normalized = parsed.copyWith(id: uniqueId);
    docs.add(normalized);
    final updated = current.copyWith(documents: docs);
    updated.validate();
    return (updated: updated, document: normalized, createdNew: true);
  }

  /// Initialise 1 [EventStormDocument] (`.es.yaml`) par module / Bounded Context
  /// du [SpecCahierDesCharges] non encore couvert, avec `meta`, `catalog`
  /// (`ACT-*`, `AGG-*`) et `flow[]` chronologique (incluant `outcomes` si des
  /// flux alternatifs existent).
  static ({
    EventStormingSpec updated,
    int addedDocumentsCount,
    int addedStepsCount,
  })
  seedFromCahierDesCharges(SpecForgeProject project) {
    final current = project.eventStorming;
    final cdc = project.cahierDesCharges;
    if (!cdc.hasContent) {
      return (updated: current, addedDocumentsCount: 0, addedStepsCount: 0);
    }

    final docs = List<EventStormDocument>.from(current.documents);
    final today = _todayIsoDate();
    final domainName = project.name.trim().isEmpty
        ? 'Domaine métier'
        : project.name.trim();

    final modules = cdc.modules.isNotEmpty
        ? cdc.modules
        : <SpecModule>[
            SpecModule(
              id: 'mod_principal',
              name: domainName,
              description: 'Contexte principal du projet',
            ),
          ];

    var addedDocs = 0;
    var addedSteps = 0;
    final usedUseCaseIds = <String>{};
    final usedReqIds = <String>{};

    for (var mIdx = 0; mIdx < modules.length; mIdx++) {
      final mod = modules[mIdx];
      final existingDoc = current.findDocument(mod.name);
      if (existingDoc != null && existingDoc.flow.isNotEmpty) {
        continue;
      }

      final modReqs = cdc.functionalRequirements
          .where((r) => r.moduleId == mod.id || modules.length == 1)
          .where((r) => !usedReqIds.contains(r.id))
          .toList();

      final modUseCases = cdc.useCases.where((uc) {
        if (usedUseCaseIds.contains(uc.id)) return false;
        if (modules.length == 1) return true;
        final matched = _matchRequirementsForTitle(modReqs, uc.title);
        return matched.isNotEmpty || mIdx == 0;
      }).toList();

      if (modUseCases.isEmpty && modReqs.isEmpty) {
        continue;
      }

      final actors = <EventStormCatalogItem>[];
      final aggregates = <EventStormCatalogItem>[];
      final usedCatalogIds = <String>{};
      final actorIdByName = <String, String>{};
      final aggIdByName = <String, String>{};

      String ensureActor(String rawName) {
        final clean = rawName.trim().isEmpty ? 'Utilisateur' : rawName.trim();
        final key = clean.toLowerCase();
        return actorIdByName.putIfAbsent(key, () {
          final id = nextCatalogId('ACT', clean, usedCatalogIds);
          usedCatalogIds.add(id);
          actors.add(
            EventStormCatalogItem(
              id: id,
              name: clean,
              type: EventStormActorType.human,
            ),
          );
          return id;
        });
      }

      String ensureAggregate(String rawName) {
        final clean = rawName.trim().isEmpty ? mod.name : rawName.trim();
        final key = clean.toLowerCase();
        return aggIdByName.putIfAbsent(key, () {
          final id = nextCatalogId('AGG', clean, usedCatalogIds);
          usedCatalogIds.add(id);
          aggregates.add(EventStormCatalogItem(id: id, name: clean));
          return id;
        });
      }

      final steps = <EventStormStep>[];
      var hsCounter = 0;
      String? previousMainEventId;
      final epicCode = 'EPIC-${(mIdx + 1).toString().padLeft(2, '0')}';

      if (modUseCases.isNotEmpty) {
        for (final uc in modUseCases) {
          usedUseCaseIds.add(uc.id);
          final stepNum = steps.length + 1;
          final actorPersona = project.vision.personas
              .where((p) => p.id == uc.actorId || p.name == uc.actorId)
              .firstOrNull;
          final actorId = ensureActor(
            actorPersona?.name ??
                (uc.actorId.trim().isNotEmpty ? uc.actorId : 'Utilisateur'),
          );
          final aggId = ensureAggregate(
            _guessAggregateTitle(uc.title, fallback: mod.name),
          );
          final matchedReqs = _matchRequirementsForTitle(modReqs, uc.title);
          for (final r in matchedReqs) {
            usedReqIds.add(r.id);
          }
          final storyCode = matchedReqs.isNotEmpty
              ? matchedReqs.first.code
              : 'US-${(mIdx + 1) * 100 + stepNum}';

          final cmdName = _toInfinitiveCommand(uc.title);
          final successEventName = uc.postconditions.isNotEmpty
              ? _toPastEvent(uc.postconditions.first)
              : _toPastEvent(uc.title);

          final hotspots = <EventStormHotspot>[];
          if (uc.alternativeFlows.length > 1) {
            hsCounter++;
            hotspots.add(
              EventStormHotspot(
                id: 'HS-${hsCounter.toString().padLeft(2, '0')}',
                question:
                    'Préciser le traitement complet des cas alternatifs : ${uc.alternativeFlows.skip(1).join(' ; ')} ?',
                severity: EventStormHotspotSeverity.medium,
                owner: 'Product Owner',
                status: EventStormHotspotStatus.open,
              ),
            );
          }

          final hasAlternativeOutcome = uc.alternativeFlows.isNotEmpty;
          final baseEvtNum = stepNum.toString().padLeft(2, '0');

          final step = hasAlternativeOutcome
              ? EventStormStep(
                  step: stepNum,
                  backlog: EventStormBacklog(epic: epicCode, story: storyCode),
                  triggeredBy: previousMainEventId != null
                      ? EventStormTrigger.single(previousMainEventId)
                      : null,
                  readModel: uc.preconditions.isNotEmpty
                      ? EventStormReadModel(
                          name: 'Vue ${uc.title}',
                          fields: uc.preconditions,
                        )
                      : null,
                  actor: actorId,
                  command: EventStormCommand(
                    name: cmdName,
                    payload: _inferPayloadFromFlow(uc.mainFlow),
                  ),
                  aggregate: aggId,
                  outcomes: <EventStormOutcome>[
                    EventStormOutcome(
                      condition: 'Règles métier respectées',
                      isError: false,
                      domainEvent: EventStormDomainEvent(
                        id: 'EVT-${baseEvtNum}A',
                        name: successEventName,
                      ),
                    ),
                    EventStormOutcome(
                      condition: uc.alternativeFlows.first,
                      isError: true,
                      domainEvent: EventStormDomainEvent(
                        id: 'EVT-${baseEvtNum}B',
                        name: _toErrorPastEvent(uc.title),
                        data: const <String>['motif_rejet'],
                      ),
                    ),
                  ],
                  hotspots: hotspots,
                )
              : EventStormStep(
                  step: stepNum,
                  backlog: EventStormBacklog(epic: epicCode, story: storyCode),
                  triggeredBy: previousMainEventId != null
                      ? EventStormTrigger.single(previousMainEventId)
                      : null,
                  readModel: uc.preconditions.isNotEmpty
                      ? EventStormReadModel(
                          name: 'Vue ${uc.title}',
                          fields: uc.preconditions,
                        )
                      : null,
                  actor: actorId,
                  command: EventStormCommand(
                    name: cmdName,
                    payload: _inferPayloadFromFlow(uc.mainFlow),
                  ),
                  aggregate: aggId,
                  domainEvent: EventStormDomainEvent(
                    id: 'EVT-$baseEvtNum',
                    name: successEventName,
                  ),
                  hotspots: hotspots,
                );

          steps.add(step);
          previousMainEventId = step.emittedEvents.first.id;
          addedSteps++;
        }
      } else {
        for (final req in modReqs) {
          usedReqIds.add(req.id);
          final stepNum = steps.length + 1;
          final actorPersona = req.actorIds.isNotEmpty
              ? project.vision.personas
                    .where((p) => p.id == req.actorIds.first)
                    .firstOrNull
              : null;
          final actorId = ensureActor(actorPersona?.name ?? 'Utilisateur');
          final aggId = ensureAggregate(
            _guessAggregateTitle(req.title, fallback: mod.name),
          );
          final hotspots = <EventStormHotspot>[];
          if (req.acceptanceCriteria.isEmpty) {
            hsCounter++;
            hotspots.add(
              EventStormHotspot(
                id: 'HS-${hsCounter.toString().padLeft(2, '0')}',
                question:
                    'Quels sont les critères d’acceptation et cas d’erreur pour « ${req.title} » ?',
                severity: EventStormHotspotSeverity.medium,
                owner: 'Product Owner',
                status: EventStormHotspotStatus.open,
              ),
            );
          }

          final evtId = 'EVT-${stepNum.toString().padLeft(2, '0')}';
          steps.add(
            EventStormStep(
              step: stepNum,
              backlog: EventStormBacklog(epic: epicCode, story: req.code),
              triggeredBy: previousMainEventId != null
                  ? EventStormTrigger.single(previousMainEventId)
                  : null,
              actor: actorId,
              command: EventStormCommand(name: _toInfinitiveCommand(req.title)),
              aggregate: aggId,
              domainEvent: EventStormDomainEvent(
                id: evtId,
                name: _toPastEvent(req.title),
              ),
              hotspots: hotspots,
            ),
          );
          previousMainEventId = evtId;
          addedSteps++;
        }
      }

      if (steps.isEmpty) continue;

      final docId = existingDoc?.id ?? nextDocumentId(mod.name, docs);
      final doc = EventStormDocument(
        id: docId,
        meta: EventStormMeta(
          domain: domainName,
          boundedContext: mod.name,
          format: EventStormFormat.processModeling,
          date: today,
          facilitator: 'Product Owner',
        ),
        catalog: EventStormCatalog(actors: actors, aggregates: aggregates),
        flow: steps,
      );

      if (existingDoc != null) {
        final idx = docs.indexWhere((d) => d.id == existingDoc.id);
        if (idx >= 0) docs[idx] = doc;
      } else {
        docs.add(doc);
        addedDocs++;
      }
    }

    if (addedDocs == 0 && addedSteps == 0) {
      return (updated: current, addedDocumentsCount: 0, addedStepsCount: 0);
    }

    final updated = current.copyWith(documents: docs);
    updated.validate();
    return (
      updated: updated,
      addedDocumentsCount: addedDocs,
      addedStepsCount: addedSteps,
    );
  }

  /// Synthétise ou enrichit les [BusinessObjectSpec] (et leurs cycles de vie)
  /// à partir des agrégats (`catalog.aggregates` / `step.aggregate`),
  /// commandes (`payload`) et événements domaine (`data`, y compris dans `outcomes`)
  /// de [SpecForgeProject.eventStorming].
  static ({
    SpecForgeProject project,
    int createdObjectsCount,
    int enrichedObjectsCount,
  })
  synthesizeBusinessObjectsFromEventStorming(SpecForgeProject project) {
    final es = project.eventStorming;
    if (!es.hasContent) {
      return (
        project: project,
        createdObjectsCount: 0,
        enrichedObjectsCount: 0,
      );
    }

    final objects = List<BusinessObjectSpec>.from(project.businessObjects);
    final accumulators = <String, _AggregateAccumulator>{};

    for (final doc in es.documents) {
      for (final agg in doc.catalog.aggregates) {
        final key = _normalizeKey(agg.name);
        accumulators.putIfAbsent(
          key,
          () => _AggregateAccumulator(
            catalogId: agg.id,
            displayName: agg.name,
            boundedContext: doc.meta.boundedContext,
          ),
        );
      }

      for (final step in doc.sortedSteps) {
        if (step.aggregate.isEmpty) continue;
        final catalogItem = doc.catalog.findAggregate(step.aggregate);
        final displayName = catalogItem?.name ?? step.aggregate;
        final key = _normalizeKey(displayName);
        final acc = accumulators.putIfAbsent(
          key,
          () => _AggregateAccumulator(
            catalogId: step.aggregate,
            displayName: displayName,
            boundedContext: doc.meta.boundedContext,
          ),
        );
        acc.commands.add(step.command.name);
        acc.payloadFields.addAll(step.command.payload);
        for (final evt in step.emittedEvents) {
          acc.events.add(evt.name);
          acc.payloadFields.addAll(evt.data);
        }
      }
    }

    if (accumulators.isEmpty) {
      return (
        project: project,
        createdObjectsCount: 0,
        enrichedObjectsCount: 0,
      );
    }

    var createdCount = 0;
    var enrichedCount = 0;

    for (final acc in accumulators.values) {
      final existingIdx = _findMatchingObjectIndex(
        objects,
        displayName: acc.displayName,
      );

      if (existingIdx < 0) {
        final techName = _toPascalIdentifier(acc.displayName);
        final objId = _shortId('obj');
        final attrs = <BusinessAttribute>[
          BusinessAttribute(
            id: _shortId('attr'),
            name: 'id',
            type: BusinessAttributeType.uuid,
            required: true,
            unique: true,
            description: 'Identifiant unique de ${acc.displayName}',
          ),
        ];

        final seenAttrNames = <String>{'id'};
        for (final rawField in acc.payloadFields) {
          final cleanName = _toCamelIdentifier(rawField);
          if (cleanName.isEmpty || !seenAttrNames.add(cleanName.toLowerCase())) {
            continue;
          }
          attrs.add(
            BusinessAttribute(
              id: _shortId('attr'),
              name: cleanName,
              type: _inferAttributeType(cleanName),
              description:
                  'Attribut issu des commandes/événements Event Storming (${acc.catalogId})',
            ),
          );
        }

        final states = <LifecycleState>[];
        final transitions = <LifecycleTransition>[];
        if (acc.events.isNotEmpty) {
          states.add(
            const LifecycleState(
              name: 'initial',
              label: 'Initial',
              isInitial: true,
              description: 'État initial avant le premier événement domaine',
            ),
          );
          var prevState = 'initial';
          final eventList = acc.events.toList();
          for (var i = 0; i < eventList.length; i++) {
            final evtName = eventList[i];
            final stateName = _toSnakeIdentifier(evtName);
            if (stateName.isEmpty || states.any((s) => s.name == stateName)) {
              continue;
            }
            states.add(
              LifecycleState(
                name: stateName,
                label: evtName,
                isTerminal: i == eventList.length - 1,
                description: 'État atteint suite à l’événement « $evtName »',
              ),
            );
            final trigger = i < acc.commands.length
                ? acc.commands.elementAt(i)
                : evtName;
            transitions.add(
              LifecycleTransition(
                id: _shortId('tr'),
                fromState: prevState,
                toState: stateName,
                trigger: trigger,
                guardSummary: 'Émet l’événement $evtName',
              ),
            );
            prevState = stateName;
          }
          if (!seenAttrNames.contains('statut')) {
            attrs.add(
              BusinessAttribute(
                id: _shortId('attr'),
                name: 'statut',
                type: BusinessAttributeType.enumeration,
                required: true,
                enumValues: [for (final s in states) s.name],
                defaultValue: states.first.name,
                description: 'État courant du cycle de vie',
              ),
            );
          }
        }

        objects.add(
          BusinessObjectSpec(
            id: objId,
            name: acc.displayName,
            technicalName: techName,
            description:
                'Agrégat ${acc.catalogId} identifié dans le Bounded Context « ${acc.boundedContext} ».',
            aggregateRoot: true,
            attributes: attrs,
            lifecycleStates: states,
            lifecycleTransitions: transitions,
          ),
        );
        createdCount++;
      } else {
        final existing = objects[existingIdx];
        final nextAttrs = List<BusinessAttribute>.from(existing.attributes);
        final seenNames = <String>{
          for (final a in nextAttrs) a.name.toLowerCase(),
        };
        var changed = false;
        for (final rawField in acc.payloadFields) {
          final cleanName = _toCamelIdentifier(rawField);
          if (cleanName.isEmpty || !seenNames.add(cleanName.toLowerCase())) {
            continue;
          }
          nextAttrs.add(
            BusinessAttribute(
              id: _shortId('attr'),
              name: cleanName,
              type: _inferAttributeType(cleanName),
              description:
                  'Attribut découvert lors de l’Event Storming (${acc.catalogId})',
            ),
          );
          changed = true;
        }

        final nextStates = List<LifecycleState>.from(existing.lifecycleStates);
        final nextTransitions = List<LifecycleTransition>.from(
          existing.lifecycleTransitions,
        );
        if (nextStates.isEmpty && acc.events.isNotEmpty) {
          nextStates.add(
            const LifecycleState(
              name: 'initial',
              label: 'Initial',
              isInitial: true,
            ),
          );
          var prev = 'initial';
          for (final evtName in acc.events) {
            final stateName = _toSnakeIdentifier(evtName);
            if (stateName.isEmpty ||
                nextStates.any((s) => s.name == stateName)) {
              continue;
            }
            nextStates.add(LifecycleState(name: stateName, label: evtName));
            nextTransitions.add(
              LifecycleTransition(
                id: _shortId('tr'),
                fromState: prev,
                toState: stateName,
                trigger: evtName,
              ),
            );
            prev = stateName;
          }
          changed = true;
        }

        if (changed) {
          objects[existingIdx] = existing.copyWith(
            attributes: nextAttrs,
            lifecycleStates: nextStates,
            lifecycleTransitions: nextTransitions,
          );
          enrichedCount++;
        }
      }
    }

    if (createdCount == 0 && enrichedCount == 0) {
      return (
        project: project,
        createdObjectsCount: 0,
        enrichedObjectsCount: 0,
      );
    }

    final nextProject = project.copyWith(businessObjects: objects);
    nextProject.validate();
    return (
      project: nextProject,
      createdObjectsCount: createdCount,
      enrichedObjectsCount: enrichedCount,
    );
  }

  /// Promeut la `policy` d'une étape Event Storming en règle de gestion `RG-xxx`
  /// de catégorie [BusinessRuleCategory.trigger].
  static ({SpecForgeProject project, BusinessRuleSpec rule, bool createdNew})
  promotePolicyToBusinessRule(
    SpecForgeProject project, {
    required String documentId,
    required int stepNumber,
  }) {
    final doc = project.eventStorming.findDocument(documentId);
    if (doc == null) {
      throw FormatException(
        'Document Event Storming introuvable : $documentId',
      );
    }
    final step = doc.findStep(stepNumber);
    if (step == null || step.policy == null) {
      throw FormatException(
        'Aucune politique trouvée à l’étape $stepNumber du contexte « ${doc.meta.boundedContext} ».',
      );
    }
    final policy = step.policy!;

    final targetObjIds = <String>[];
    if (step.aggregate.isNotEmpty) {
      final aggItem = doc.catalog.findAggregate(step.aggregate);
      final aggName = aggItem?.name ?? step.aggregate;
      final objIdx = _findMatchingObjectIndex(
        project.businessObjects,
        displayName: aggName,
      );
      if (objIdx >= 0) {
        targetObjIds.add(project.businessObjects[objIdx].id);
      }
    }

    final triggerText = step.triggeredBy != null
        ? 'Sur ${step.triggeredBy!.summaryLabel} (${doc.meta.boundedContext})'
        : '${doc.meta.boundedContext} — Étape ${step.step}';
    final effectText =
        'Commande : ${step.command.name}'
        '${step.externalSystem.isNotEmpty ? ' via ${doc.catalog.findExternalSystem(step.externalSystem)?.name ?? step.externalSystem}' : ''}';

    final rules = List<BusinessRuleSpec>.from(project.businessRules);
    final existingIdx = rules.indexWhere(
      (r) =>
          r.title.trim().toLowerCase() == policy.name.trim().toLowerCase() ||
          r.description.trim().toLowerCase() == policy.rule.trim().toLowerCase(),
    );

    if (existingIdx >= 0) {
      final existing = rules[existingIdx];
      final updatedRule = existing.copyWith(
        trigger: existing.trigger.isEmpty ? triggerText : existing.trigger,
        effect: existing.effect.isEmpty ? effectText : existing.effect,
        targetObjectIds: existing.targetObjectIds.isEmpty
            ? targetObjIds
            : existing.targetObjectIds,
      );
      rules[existingIdx] = updatedRule;
      final nextProject = project.copyWith(businessRules: rules);
      nextProject.validate();
      return (project: nextProject, rule: updatedRule, createdNew: false);
    }

    final code = nextRuleCode(rules);
    final rule = BusinessRuleSpec(
      id: _shortId('rule'),
      code: code,
      title: policy.name,
      category: BusinessRuleCategory.trigger,
      priority: BusinessRulePriority.high,
      description: policy.rule,
      targetObjectIds: targetObjIds,
      trigger: triggerText,
      condition: step.backlog != null && step.backlog!.isNotEmpty
          ? 'Backlog ${[if (step.backlog!.epic.isNotEmpty) step.backlog!.epic, if (step.backlog!.story.isNotEmpty) step.backlog!.story].join(' / ')}'
          : 'Condition vérifiée sur événement déclencheur',
      effect: effectText,
    );
    rules.add(rule);

    final nextProject = project.copyWith(businessRules: rules);
    nextProject.validate();
    return (project: nextProject, rule: rule, createdNew: true);
  }

  static int _findMatchingObjectIndex(
    List<BusinessObjectSpec> objects, {
    required String displayName,
  }) {
    final nameKey = _normalizeKey(displayName);
    final pascalKey = _toPascalIdentifier(displayName).toLowerCase();
    for (var i = 0; i < objects.length; i++) {
      final obj = objects[i];
      if (_normalizeKey(obj.name) == nameKey ||
          obj.technicalName.toLowerCase() == pascalKey) {
        return i;
      }
    }
    return -1;
  }

  static List<FunctionalRequirement> _matchRequirementsForTitle(
    List<FunctionalRequirement> reqs,
    String title,
  ) {
    final tokens = title
        .toLowerCase()
        .split(RegExp(r'[^a-zà-ÿ0-9]+'))
        .where((t) => t.length >= 4)
        .toSet();
    if (tokens.isEmpty) return const <FunctionalRequirement>[];
    return reqs.where((r) {
      final text = '${r.title} ${r.description}'.toLowerCase();
      return tokens.any(text.contains);
    }).toList();
  }

  static String _toInfinitiveCommand(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Exécuter l’action';
    if (EventStormingDslCodec.looksLikeInfinitiveCommand(trimmed)) {
      return trimmed;
    }
    return 'Traiter $trimmed';
  }

  static String _toPastEvent(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Action effectuée';
    if (EventStormingDslCodec.looksLikePastDomainEvent(trimmed)) {
      return trimmed;
    }
    return '$trimmed traité';
  }

  static String _toErrorPastEvent(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Action refusée';
    return '$trimmed rejeté';
  }

  static List<String> _inferPayloadFromFlow(List<String> mainFlow) {
    if (mainFlow.isEmpty) return const <String>[];
    final fields = <String>[];
    for (final line in mainFlow.take(3)) {
      final slug = _toSnakeIdentifier(line);
      if (slug.isNotEmpty && !fields.contains(slug)) {
        fields.add(slug);
      }
    }
    return fields;
  }

  static String _guessAggregateTitle(String title, {required String fallback}) {
    final words = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 4)
        .toList();
    if (words.length >= 2) {
      return words.last;
    }
    return fallback.trim().isEmpty ? 'Agrégat' : fallback.trim();
  }

  static String _todayIsoDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static String _normalizeKey(String raw) =>
      _foldAccents(raw).trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static String _toSlug(String raw) {
    final cleaned = _foldAccents(raw)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'bounded-context' : cleaned;
  }

  static List<String> _asciiWords(String raw) {
    final folded = _foldAccents(raw);
    return folded
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static String _toPascalIdentifier(String raw) {
    final words = _asciiWords(raw);
    if (words.isEmpty) return 'AgregatMetier';
    final joined = [
      for (final w in words)
        '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
    ].join();
    return RegExp(r'^[0-9]').hasMatch(joined) ? 'Obj$joined' : joined;
  }

  static String _toCamelIdentifier(String raw) {
    final cleanField = raw.split(':').first.trim();
    final words = _asciiWords(cleanField);
    if (words.isEmpty) return '';
    final first = words.first.toLowerCase();
    final rest = [
      for (final w in words.skip(1))
        '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
    ].join();
    final id = '$first$rest';
    return RegExp(r'^[0-9]').hasMatch(id) ? 'attr$id' : id;
  }

  static String _toSnakeIdentifier(String raw) {
    final words = _asciiWords(raw);
    if (words.isEmpty) return '';
    return words.map((w) => w.toLowerCase()).join('_');
  }

  static BusinessAttributeType _inferAttributeType(String name) {
    final lower = name.toLowerCase();
    if (lower == 'id' || lower.endsWith('id') || lower.endsWith('uuid')) {
      return BusinessAttributeType.uuid;
    }
    if (lower.contains('email')) return BusinessAttributeType.email;
    if (lower.contains('url')) return BusinessAttributeType.url;
    if (lower.endsWith('le') ||
        lower.endsWith('at') ||
        lower.contains('date') ||
        lower.contains('heure')) {
      return BusinessAttributeType.datetime;
    }
    if (lower.contains('montant') ||
        lower.contains('prix') ||
        lower.contains('taux') ||
        lower.contains('total')) {
      return BusinessAttributeType.number;
    }
    if (lower.contains('quantite') ||
        lower.contains('nombre') ||
        lower.contains('count') ||
        lower.contains('delai')) {
      return BusinessAttributeType.integer;
    }
    if (lower.startsWith('est') ||
        lower.startsWith('is') ||
        lower.startsWith('has')) {
      return BusinessAttributeType.boolean;
    }
    return BusinessAttributeType.string;
  }

  static String _foldAccents(String input) {
    const map = <String, String>{
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'í': 'i',
      'ô': 'o',
      'ö': 'o',
      'ó': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ú': 'u',
      'ç': 'c',
      'À': 'A',
      'Â': 'A',
      'Ä': 'A',
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'Î': 'I',
      'Ï': 'I',
      'Ô': 'O',
      'Ö': 'O',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'Ç': 'C',
    };
    final buf = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }

  static String _shortId(String prefix) {
    final token = shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return '${prefix}_${token.isEmpty ? DateTime.now().microsecondsSinceEpoch : token}';
  }
}

class _AggregateAccumulator {
  _AggregateAccumulator({
    required this.catalogId,
    required this.displayName,
    required this.boundedContext,
  });

  final String catalogId;
  final String displayName;
  final String boundedContext;
  final Set<String> commands = <String>{};
  final Set<String> events = <String>{};
  final Set<String> payloadFields = <String>{};
}
