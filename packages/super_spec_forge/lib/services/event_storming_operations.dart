/// Opérations métier déterministes pour l'Event Storming ([EventStormingOperations]) :
/// amorçage depuis le Cahier des charges, synthèse/enrichissement des objets métiers
/// depuis les agrégats & événements, et promotion des politiques en règles `RG-xxx`.
library;

import 'package:shortid/shortid.dart';

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/event_storming_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_forge_project.dart';

/// Services déterministes manipulant [EventStormingSpec] et ses passerelles
/// avec [SpecCahierDesCharges], [BusinessObjectSpec] et [BusinessRuleSpec].
abstract final class EventStormingOperations {
  /// Génère le prochain code séquentiel `ES-xxx` non utilisé dans [existing].
  static String nextFlowCode(List<EventStormBoard> existing) {
    final pattern = RegExp(r'^ES-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final flow in existing) {
      final match = pattern.firstMatch(flow.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'ES-${(maxIndex + 1).toString().padLeft(3, '0')}';
  }

  /// Génère le prochain code séquentiel `BC-xxx` non utilisé dans [existing].
  static String nextBoundedContextCode(List<EventStormBoundedContext> existing) {
    final pattern = RegExp(r'^BC-(\d+)$', caseSensitive: false);
    var maxIndex = existing.length;
    for (final bc in existing) {
      final match = pattern.firstMatch(bc.code.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!) ?? 0;
        if (parsed > maxIndex) maxIndex = parsed;
      }
    }
    return 'BC-${(maxIndex + 1).toString().padLeft(3, '0')}';
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

  /// Initialise des Bounded Contexts et flux Event Storming à partir des modules,
  /// cas d'usage et exigences du [SpecCahierDesCharges] non encore couverts.
  static ({
    EventStormingSpec updated,
    int addedFlowsCount,
    int addedContextsCount,
  })
  seedFromCahierDesCharges(SpecForgeProject project) {
    final current = project.eventStorming;
    final cdc = project.cahierDesCharges;

    final contexts = List<EventStormBoundedContext>.from(
      current.boundedContexts,
    );
    final contextIdByModuleId = <String, String>{};
    var addedContextsCount = 0;

    for (final mod in cdc.modules) {
      final existing = current.findBoundedContext(mod.name);
      if (existing != null) {
        contextIdByModuleId[mod.id] = existing.id;
        continue;
      }
      final alreadyInAdded = contexts
          .where((bc) => bc.name.toLowerCase() == mod.name.trim().toLowerCase())
          .firstOrNull;
      if (alreadyInAdded != null) {
        contextIdByModuleId[mod.id] = alreadyInAdded.id;
        continue;
      }
      final bc = EventStormBoundedContext(
        id: _shortId('bc'),
        code: nextBoundedContextCode(contexts),
        name: mod.name,
        description: mod.description,
      );
      contexts.add(bc);
      contextIdByModuleId[mod.id] = bc.id;
      addedContextsCount++;
    }

    final coveredUseCases = <String>{
      for (final f in current.flows)
        for (final ucId in f.useCaseIds) ucId.trim().toLowerCase(),
    };
    final coveredReqCodes = <String>{
      for (final f in current.flows)
        for (final reqId in f.requirementIds) reqId.trim().toLowerCase(),
    };

    final flows = List<EventStormBoard>.from(current.flows);
    var addedFlowsCount = 0;

    for (final uc in cdc.useCases) {
      if (coveredUseCases.contains(uc.id.toLowerCase()) ||
          coveredUseCases.contains(uc.title.toLowerCase())) {
        continue;
      }
      final actorPersona = project.vision.personas
          .where((p) => p.id == uc.actorId || p.name == uc.actorId)
          .firstOrNull;
      final actorName = actorPersona?.name ??
          (uc.actorId.trim().isNotEmpty ? uc.actorId.trim() : 'Utilisateur');
      final matchedReqs = _matchRequirementsForTitle(
        cdc.functionalRequirements,
        uc.title,
      );
      final reqCodes = [for (final r in matchedReqs) r.code];
      final bcId = matchedReqs.isNotEmpty
          ? (contextIdByModuleId[matchedReqs.first.moduleId] ?? '')
          : (contexts.isNotEmpty ? contexts.first.id : '');

      final flow = _buildStarterFlow(
        code: nextFlowCode(flows),
        title: uc.title,
        description: uc.mainFlow.isNotEmpty
            ? uc.mainFlow.join(' → ')
            : 'Flux issu du cas d’usage « ${uc.title} ».',
        actorName: actorName,
        actorId: actorPersona?.id ?? uc.actorId,
        commandTitle: _toCommandTitle(uc.title),
        aggregateTitle: _guessAggregateTitle(
          uc.title,
          fallback: matchedReqs.isNotEmpty
              ? _moduleNameFor(cdc.modules, matchedReqs.first.moduleId)
              : 'Dossier',
        ),
        eventTitle: uc.postconditions.isNotEmpty
            ? uc.postconditions.first
            : _toPastEventTitle(uc.title),
        hotspotTitle: uc.alternativeFlows.isNotEmpty
            ? 'Cas alternatif à détailler : ${uc.alternativeFlows.first}'
            : '',
        boundedContextId: bcId,
        requirementIds: reqCodes,
        useCaseIds: [uc.id],
      );
      flows.add(flow);
      addedFlowsCount++;
      for (final r in reqCodes) {
        coveredReqCodes.add(r.toLowerCase());
      }
    }

    if (addedFlowsCount == 0 && cdc.useCases.isEmpty) {
      for (final req in cdc.functionalRequirements) {
        if (coveredReqCodes.contains(req.code.toLowerCase()) ||
            coveredReqCodes.contains(req.id.toLowerCase())) {
          continue;
        }
        final actorPersona = req.actorIds.isNotEmpty
            ? project.vision.personas
                  .where((p) => p.id == req.actorIds.first)
                  .firstOrNull
            : null;
        final bcId = contextIdByModuleId[req.moduleId] ?? '';
        final flow = _buildStarterFlow(
          code: nextFlowCode(flows),
          title: '${req.code} — ${req.title}',
          description: req.description,
          actorName: actorPersona?.name ?? 'Utilisateur',
          actorId: actorPersona?.id ?? '',
          commandTitle: _toCommandTitle(req.title),
          aggregateTitle: _guessAggregateTitle(
            req.title,
            fallback: _moduleNameFor(cdc.modules, req.moduleId),
          ),
          eventTitle: _toPastEventTitle(req.title),
          hotspotTitle: req.acceptanceCriteria.isEmpty
              ? 'Critères d’acceptation et cas limites à préciser'
              : '',
          boundedContextId: bcId,
          requirementIds: [req.code],
          useCaseIds: const <String>[],
        );
        flows.add(flow);
        addedFlowsCount++;
      }
    }

    if (addedFlowsCount == 0 && addedContextsCount == 0) {
      return (updated: current, addedFlowsCount: 0, addedContextsCount: 0);
    }

    final updated = current.copyWith(
      boundedContexts: contexts,
      flows: flows,
    );
    updated.validate();
    return (
      updated: updated,
      addedFlowsCount: addedFlowsCount,
      addedContextsCount: addedContextsCount,
    );
  }

  /// Synthétise ou enrichit les [BusinessObjectSpec] (et leurs cycles de vie)
  /// à partir des agrégats, commandes et événements de [SpecForgeProject.eventStorming].
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
    final updatedFlows = List<EventStormBoard>.from(es.flows);
    var createdCount = 0;
    var enrichedCount = 0;

    // Regroupe les informations observées par clé d'agrégat normalisée.
    final aggregateAccumulators = <String, _AggregateAccumulator>{};

    for (var fIdx = 0; fIdx < es.flows.length; fIdx++) {
      final flow = es.flows[fIdx];
      final sorted = flow.sortedNodes;
      final aggNodes = sorted
          .where((n) => n.kind == EventStormNodeKind.aggregate)
          .toList();

      for (final aggNode in aggNodes) {
        final key = _normalizeKey(
          aggNode.targetObjectId.isNotEmpty
              ? aggNode.targetObjectId
              : aggNode.title,
        );
        final acc = aggregateAccumulators.putIfAbsent(
          key,
          () => _AggregateAccumulator(
            displayName: aggNode.title,
            targetObjectId: aggNode.targetObjectId,
          ),
        );
        acc.nodeRefs.add((flowIndex: fIdx, nodeId: aggNode.id));
        if (aggNode.description.isNotEmpty && acc.description.isEmpty) {
          acc.description = aggNode.description;
        }

        // Collecte les commandes entrantes et événements émis liés à cet agrégat.
        final incomingCommands = <EventStormNode>[];
        final outgoingEvents = <EventStormNode>[];
        for (final link in flow.links) {
          if (link.toNodeId == aggNode.id) {
            final src = flow.nodes
                .where((n) => n.id == link.fromNodeId)
                .firstOrNull;
            if (src != null && src.kind == EventStormNodeKind.command) {
              incomingCommands.add(src);
            }
          }
          if (link.fromNodeId == aggNode.id) {
            final dst = flow.nodes
                .where((n) => n.id == link.toNodeId)
                .firstOrNull;
            if (dst != null && dst.kind == EventStormNodeKind.domainEvent) {
              outgoingEvents.add(dst);
            }
          }
        }
        // Fallback par proximité chronologique si aucun lien explicite.
        if (incomingCommands.isEmpty && outgoingEvents.isEmpty) {
          for (final n in sorted) {
            if (n.kind == EventStormNodeKind.command &&
                (n.targetObjectId == aggNode.targetObjectId &&
                        aggNode.targetObjectId.isNotEmpty ||
                    n.sequenceOrder <= aggNode.sequenceOrder + 1)) {
              incomingCommands.add(n);
            } else if (n.kind == EventStormNodeKind.domainEvent &&
                (n.targetObjectId == aggNode.targetObjectId &&
                        aggNode.targetObjectId.isNotEmpty ||
                    n.sequenceOrder >= aggNode.sequenceOrder)) {
              outgoingEvents.add(n);
            }
          }
        }

        for (final cmd in incomingCommands) {
          acc.commands.add(cmd.title);
          acc.payloadFields.addAll(cmd.payloadFields);
        }
        for (final evt in outgoingEvents) {
          acc.events.add(evt.title);
          acc.payloadFields.addAll(evt.payloadFields);
        }
      }
    }

    if (aggregateAccumulators.isEmpty) {
      return (
        project: project,
        createdObjectsCount: 0,
        enrichedObjectsCount: 0,
      );
    }

    for (final acc in aggregateAccumulators.values) {
      final existingIdx = _findMatchingObjectIndex(
        objects,
        targetObjectId: acc.targetObjectId,
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
              description: 'Attribut issu des événements/commandes Event Storming',
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
            final evtTitle = eventList[i];
            final stateName = _toSnakeIdentifier(evtTitle);
            if (stateName.isEmpty || states.any((s) => s.name == stateName)) {
              continue;
            }
            states.add(
              LifecycleState(
                name: stateName,
                label: evtTitle,
                isTerminal: i == eventList.length - 1,
                description: 'État atteint suite à l’événement $evtTitle',
              ),
            );
            final trigger = i < acc.commands.length
                ? acc.commands.elementAt(i)
                : evtTitle;
            transitions.add(
              LifecycleTransition(
                id: _shortId('tr'),
                fromState: prevState,
                toState: stateName,
                trigger: trigger,
                guardSummary: 'Émet l’événement $evtTitle',
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

        final newObj = BusinessObjectSpec(
          id: objId,
          name: acc.displayName,
          technicalName: techName,
          description: acc.description.isNotEmpty
              ? acc.description
              : 'Agrégat identifié lors de l’Event Storming.',
          aggregateRoot: true,
          attributes: attrs,
          lifecycleStates: states,
          lifecycleTransitions: transitions,
        );
        objects.add(newObj);
        createdCount++;
        _linkNodesToObject(updatedFlows, acc.nodeRefs, objId);
      } else {
        final existing = objects[existingIdx];
        var nextAttrs = List<BusinessAttribute>.from(existing.attributes);
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
              description: 'Attribut découvert lors de l’Event Storming',
            ),
          );
          changed = true;
        }

        var nextStates = List<LifecycleState>.from(existing.lifecycleStates);
        var nextTransitions = List<LifecycleTransition>.from(
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
          for (final evtTitle in acc.events) {
            final stateName = _toSnakeIdentifier(evtTitle);
            if (stateName.isEmpty ||
                nextStates.any((s) => s.name == stateName)) {
              continue;
            }
            nextStates.add(
              LifecycleState(name: stateName, label: evtTitle),
            );
            nextTransitions.add(
              LifecycleTransition(
                id: _shortId('tr'),
                fromState: prev,
                toState: stateName,
                trigger: evtTitle,
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
        _linkNodesToObject(updatedFlows, acc.nodeRefs, existing.id);
      }
    }

    final nextProject = project.copyWith(
      businessObjects: objects,
      eventStorming: es.copyWith(flows: updatedFlows),
    );
    nextProject.validate();
    return (
      project: nextProject,
      createdObjectsCount: createdCount,
      enrichedObjectsCount: enrichedCount,
    );
  }

  /// Promeut une carte Politique (`policy`) d'un flux Event Storming en règle de gestion
  /// `RG-xxx` de catégorie `trigger` et lie `linkedRuleId` sur le nœud source.
  static ({SpecForgeProject project, BusinessRuleSpec rule, bool createdNew})
  promotePolicyToBusinessRule(
    SpecForgeProject project, {
    required String flowId,
    required String nodeId,
  }) {
    final flowIdx = project.eventStorming.flows.indexWhere((f) => f.id == flowId);
    if (flowIdx < 0) {
      throw FormatException('Flux Event Storming introuvable : $flowId');
    }
    final flow = project.eventStorming.flows[flowIdx];
    final nodeIdx = flow.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIdx < 0) {
      throw FormatException('Carte Event Storming introuvable : $nodeId');
    }
    final node = flow.nodes[nodeIdx];

    final incomingEvents = <String>[];
    final outgoingCommands = <String>[];
    for (final link in flow.links) {
      if (link.toNodeId == node.id) {
        final src = flow.nodes
            .where((n) => n.id == link.fromNodeId)
            .firstOrNull;
        if (src != null) incomingEvents.add(src.title);
      }
      if (link.fromNodeId == node.id) {
        final dst = flow.nodes
            .where((n) => n.id == link.toNodeId)
            .firstOrNull;
        if (dst != null) outgoingCommands.add(dst.title);
      }
    }

    final targetObjIds = <String>{
      if (node.targetObjectId.trim().isNotEmpty) node.targetObjectId.trim(),
      for (final n in flow.nodes)
        if (n.kind == EventStormNodeKind.aggregate &&
            n.targetObjectId.trim().isNotEmpty)
          n.targetObjectId.trim(),
    }.toList();

    final triggerText = incomingEvents.isNotEmpty
        ? 'Sur événement : ${incomingEvents.join(', ')}'
        : 'Flux ${flow.code} — ${flow.title}';
    final effectText = outgoingCommands.isNotEmpty
        ? 'Déclencher : ${outgoingCommands.join(', ')}'
        : (node.description.isNotEmpty ? node.description : node.title);

    final rules = List<BusinessRuleSpec>.from(project.businessRules);
    final existingIdx = node.linkedRuleId.trim().isEmpty
        ? -1
        : rules.indexWhere(
            (r) =>
                r.id.toLowerCase() == node.linkedRuleId.trim().toLowerCase() ||
                r.code.toLowerCase() == node.linkedRuleId.trim().toLowerCase(),
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
      title: node.title,
      category: BusinessRuleCategory.trigger,
      priority: BusinessRulePriority.high,
      description: node.description.isNotEmpty
          ? node.description
          : 'Règle réactive issue de la politique Event Storming (${flow.code}).',
      targetObjectIds: targetObjIds,
      trigger: triggerText,
      condition: node.notes.isNotEmpty
          ? node.notes
          : 'Condition vérifiée lors de l’événement déclencheur',
      effect: effectText,
    );
    rules.add(rule);

    final updatedNodes = List<EventStormNode>.from(flow.nodes)
      ..[nodeIdx] = node.copyWith(linkedRuleId: rule.code);
    final updatedFlows = List<EventStormBoard>.from(project.eventStorming.flows)
      ..[flowIdx] = flow.copyWith(nodes: updatedNodes);

    final nextProject = project.copyWith(
      businessRules: rules,
      eventStorming: project.eventStorming.copyWith(flows: updatedFlows),
    );
    nextProject.validate();
    return (project: nextProject, rule: rule, createdNew: true);
  }

  static EventStormBoard _buildStarterFlow({
    required String code,
    required String title,
    required String description,
    required String actorName,
    required String actorId,
    required String commandTitle,
    required String aggregateTitle,
    required String eventTitle,
    required String hotspotTitle,
    required String boundedContextId,
    required List<String> requirementIds,
    required List<String> useCaseIds,
  }) {
    final actorNodeId = _shortId('esn');
    final cmdNodeId = _shortId('esn');
    final aggNodeId = _shortId('esn');
    final evtNodeId = _shortId('esn');
    final hotNodeId = _shortId('esn');

    final nodes = <EventStormNode>[
      EventStormNode(
        id: actorNodeId,
        code: 'ACT-01',
        kind: EventStormNodeKind.actor,
        title: actorName,
        sequenceOrder: 1,
        boundedContextId: boundedContextId,
        actorId: actorId,
      ),
      EventStormNode(
        id: cmdNodeId,
        code: 'CMD-01',
        kind: EventStormNodeKind.command,
        title: commandTitle,
        sequenceOrder: 2,
        boundedContextId: boundedContextId,
        actorId: actorId,
      ),
      EventStormNode(
        id: aggNodeId,
        code: 'AGG-01',
        kind: EventStormNodeKind.aggregate,
        title: aggregateTitle,
        sequenceOrder: 3,
        boundedContextId: boundedContextId,
      ),
      EventStormNode(
        id: evtNodeId,
        code: 'EVT-01',
        kind: EventStormNodeKind.domainEvent,
        title: eventTitle,
        sequenceOrder: 4,
        boundedContextId: boundedContextId,
        isPivotal: true,
      ),
      if (hotspotTitle.isNotEmpty)
        EventStormNode(
          id: hotNodeId,
          code: 'HOT-01',
          kind: EventStormNodeKind.hotspot,
          title: hotspotTitle,
          sequenceOrder: 5,
          boundedContextId: boundedContextId,
        ),
    ];

    final links = <EventStormLink>[
      EventStormLink(
        id: _shortId('esl'),
        fromNodeId: actorNodeId,
        toNodeId: cmdNodeId,
        kind: EventStormLinkKind.triggers,
      ),
      EventStormLink(
        id: _shortId('esl'),
        fromNodeId: cmdNodeId,
        toNodeId: aggNodeId,
        kind: EventStormLinkKind.handles,
      ),
      EventStormLink(
        id: _shortId('esl'),
        fromNodeId: aggNodeId,
        toNodeId: evtNodeId,
        kind: EventStormLinkKind.emits,
      ),
      if (hotspotTitle.isNotEmpty)
        EventStormLink(
          id: _shortId('esl'),
          fromNodeId: evtNodeId,
          toNodeId: hotNodeId,
          kind: EventStormLinkKind.flags,
        ),
    ];

    return EventStormBoard(
      id: _shortId('es'),
      code: code,
      title: title,
      description: description,
      boundedContextIds: boundedContextId.isEmpty
          ? const <String>[]
          : <String>[boundedContextId],
      requirementIds: requirementIds,
      useCaseIds: useCaseIds,
      nodes: nodes,
      links: links,
    );
  }

  static void _linkNodesToObject(
    List<EventStormBoard> flows,
    List<({int flowIndex, String nodeId})> refs,
    String objectId,
  ) {
    for (final ref in refs) {
      final flow = flows[ref.flowIndex];
      final nIdx = flow.nodes.indexWhere((n) => n.id == ref.nodeId);
      if (nIdx < 0) continue;
      final node = flow.nodes[nIdx];
      if (node.targetObjectId == objectId) continue;
      final nextNodes = List<EventStormNode>.from(flow.nodes)
        ..[nIdx] = node.copyWith(targetObjectId: objectId);
      flows[ref.flowIndex] = flow.copyWith(nodes: nextNodes);
    }
  }

  static int _findMatchingObjectIndex(
    List<BusinessObjectSpec> objects, {
    required String targetObjectId,
    required String displayName,
  }) {
    final targetKey = targetObjectId.trim().toLowerCase();
    final nameKey = _normalizeKey(displayName);
    final pascalKey = _toPascalIdentifier(displayName).toLowerCase();
    for (var i = 0; i < objects.length; i++) {
      final obj = objects[i];
      if (targetKey.isNotEmpty &&
          (obj.id.toLowerCase() == targetKey ||
              obj.technicalName.toLowerCase() == targetKey)) {
        return i;
      }
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

  static String _moduleNameFor(List<SpecModule> modules, String moduleId) =>
      modules.where((m) => m.id == moduleId).firstOrNull?.name ?? 'Dossier';

  static String _toCommandTitle(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? 'ExecuterAction' : trimmed;
  }

  static String _toPastEventTitle(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'ActionEffectuee';
    return '$trimmed (effectué)';
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

  static String _normalizeKey(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

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
    if (lower == 'id' || lower.endsWith('uuid')) {
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
    required this.displayName,
    required this.targetObjectId,
  });

  final String displayName;
  final String targetObjectId;
  String description = '';
  final Set<String> commands = <String>{};
  final Set<String> events = <String>{};
  final Set<String> payloadFields = <String>{};
  final List<({int flowIndex, String nodeId})> nodeRefs = [];
}
