/// Exportateur du cahier des charges complet au format Markdown ([SpecMarkdownExporter]).
library;

import '../../models/business_object_spec.dart';
import '../../models/business_rule_spec.dart';
import '../../models/company_glossary.dart';
import '../../models/event_storming_spec.dart';
import '../../models/spec_coherence_issue.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_forge_stage.dart';
import '../cost_calculator.dart';
import '../spec_coherence_analyzer.dart';

/// Génère un document Markdown structuré (avec diagrammes Mermaid) depuis un [SpecForgeProject].
abstract final class SpecMarkdownExporter {
  /// Exporte [project] en cahier des charges Markdown complet.
  ///
  /// Lorsque [companyGlossary] est fourni, le tableau du lexique métier indique
  /// également pour chaque terme s'il existe déjà dans le lexique d'entreprise.
  static String export(
    SpecForgeProject project, {
    CompanyGlossary? companyGlossary,
  }) {
    final buf = StringBuffer()
      ..writeln('# Cahier des charges — ${project.name}')
      ..writeln()
      ..writeln('> Généré par **SuperSpecForge**')
      ..writeln('> Dernière mise à jour : `${project.updatedAt.toIso8601String()}`')
      ..writeln()
      ..writeln('## Idée initiale')
      ..writeln()
      ..writeln(project.initialIdea)
      ..writeln();

    _writeLexicon(buf, project, companyGlossary: companyGlossary);
    _writeVision(buf, project);
    _writeCahierDesCharges(buf, project);
    if (project.isStageEnabled(SpecForgeStage.eventStorming)) {
      _writeEventStorming(buf, project);
    }
    _writeBusinessObjects(buf, project);
    if (project.isStageEnabled(SpecForgeStage.exampleMapping)) {
      _writeExampleMapping(buf, project);
    }
    _writeBusinessRules(buf, project);
    _writeCoherenceReport(buf, project);
    _writeCostSummary(buf, project);

    return buf.toString();
  }

  static void _writeLexicon(
    StringBuffer buf,
    SpecForgeProject project, {
    CompanyGlossary? companyGlossary,
  }) {
    final lex = project.lexicon;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 1. Lexique métier (Ubiquitous Language)')
      ..writeln();
    if (!lex.hasContent) {
      buf
        ..writeln('_Aucun terme métier défini._')
        ..writeln();
      return;
    }
    if (lex.terms.isNotEmpty) {
      if (companyGlossary != null) {
        buf
          ..writeln(
            '| Terme | Définition | Synonymes / Variantes | Domaine | Lexique entreprise |',
          )
          ..writeln('|---|---|---|---|---|');
        for (final t in lex.terms) {
          final match = companyGlossary.matchLexiconTerm(t);
          final companyStatus = switch (match) {
            null => 'Non (absent)',
            CompanyGlossaryMatch(
              kind: CompanyGlossaryMatchKind.exact,
              term: final cgTerm,
            ) =>
              'Oui (${cgTerm.status.label})',
            CompanyGlossaryMatch(
              kind: CompanyGlossaryMatchKind.synonym,
              term: final cgTerm,
            ) =>
              'Oui (synonyme de « ${cgTerm.term} »)',
            CompanyGlossaryMatch(
              kind: CompanyGlossaryMatchKind.forbidden,
              term: final cgTerm,
            ) =>
              'Proscrit → « ${cgTerm.term} »',
          };
          buf.writeln(
            '| **${_esc(t.term)}** | ${_esc(t.definition.isEmpty ? '—' : t.definition)} | ${_esc(t.synonyms.isEmpty ? '—' : t.synonyms.join(', '))} | ${_esc(t.domain.isEmpty ? '—' : t.domain)} | ${_esc(companyStatus)} |',
          );
        }
      } else {
        buf
          ..writeln('| Terme | Définition | Synonymes / Variantes | Domaine |')
          ..writeln('|---|---|---|---|');
        for (final t in lex.terms) {
          buf.writeln(
            '| **${_esc(t.term)}** | ${_esc(t.definition.isEmpty ? '—' : t.definition)} | ${_esc(t.synonyms.isEmpty ? '—' : t.synonyms.join(', '))} | ${_esc(t.domain.isEmpty ? '—' : t.domain)} |',
          );
        }
      }
      buf.writeln();
    }
    if (lex.conventions.isNotEmpty) {
      buf.writeln('### Conventions de vocabulaire & unités');
      for (final c in lex.conventions) {
        buf.writeln('- $c');
      }
      buf.writeln();
    }
    if (lex.ambiguousTerms.isNotEmpty) {
      buf.writeln('### Points d’ambiguïté levés');
      for (final a in lex.ambiguousTerms) {
        buf.writeln('- $a');
      }
      buf.writeln();
    }
  }

  static void _writeVision(StringBuffer buf, SpecForgeProject project) {
    final v = project.vision;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 2. Cadrage & Acteurs')
      ..writeln();
    if (v.ideaSummary.isNotEmpty) {
      buf
        ..writeln('### Résumé du produit')
        ..writeln(v.ideaSummary)
        ..writeln();
    }
    if (v.problemStatement.isNotEmpty) {
      buf
        ..writeln('### Problème adressé')
        ..writeln(v.problemStatement)
        ..writeln();
    }
    if (v.valueProposition.isNotEmpty) {
      buf
        ..writeln('### Proposition de valeur')
        ..writeln(v.valueProposition)
        ..writeln();
    }
    if (v.objectives.isNotEmpty) {
      buf.writeln('### Objectifs');
      for (final obj in v.objectives) {
        buf.writeln('- $obj');
      }
      buf.writeln();
    }
    if (v.personas.isNotEmpty) {
      buf.writeln('### Acteurs & Personas');
      for (final p in v.personas) {
        buf.writeln('#### ${p.name} (`${p.id}`)');
        if (p.role.isNotEmpty) buf.writeln('- **Rôle** : ${p.role}');
        if (p.goals.isNotEmpty) {
          buf.writeln('- **Objectifs** : ${p.goals.join(' ; ')}');
        }
        if (p.painPoints.isNotEmpty) {
          buf.writeln('- **Irritants** : ${p.painPoints.join(' ; ')}');
        }
        buf.writeln();
      }
    }
    if (v.constraints.isNotEmpty) {
      buf.writeln('### Contraintes');
      for (final c in v.constraints) {
        buf.writeln('- $c');
      }
      buf.writeln();
    }
    if (v.outOfScope.isNotEmpty) {
      buf.writeln('### Hors périmètre (V1)');
      for (final o in v.outOfScope) {
        buf.writeln('- $o');
      }
      buf.writeln();
    }
  }

  static void _writeCahierDesCharges(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final cdc = project.cahierDesCharges;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 3. Cahier des charges fonctionnel & non fonctionnel')
      ..writeln();

    if (cdc.modules.isNotEmpty) {
      buf.writeln('### 3.1 Modules fonctionnels');
      for (final m in cdc.modules) {
        buf.writeln(
          '- **${m.name}** (`${m.id}`)${m.description.isEmpty ? '' : ' : ${m.description}'}',
        );
      }
      buf.writeln();
    }

    if (cdc.functionalRequirements.isNotEmpty) {
      buf
        ..writeln('### 3.2 Exigences fonctionnelles')
        ..writeln()
        ..writeln('| Code | Priorité | Exigence | Module | Critères d’acceptation |')
        ..writeln('|---|---|---|---|---|');
      for (final r in cdc.functionalRequirements) {
        final criteria = r.acceptanceCriteria.isEmpty
            ? '—'
            : r.acceptanceCriteria.join('<br>');
        final titleDesc = r.description.isEmpty
            ? '**${r.title}**'
            : '**${r.title}**<br>${r.description}';
        buf.writeln(
          '| `${r.code}` | ${r.priority.code} | ${_esc(titleDesc)} | `${r.moduleId.isEmpty ? '—' : r.moduleId}` | ${_esc(criteria)} |',
        );
      }
      buf.writeln();
    }

    if (cdc.useCases.isNotEmpty) {
      buf.writeln('### 3.3 Cas d’usage clés');
      for (final uc in cdc.useCases) {
        buf.writeln('#### ${uc.title}');
        if (uc.actorId.isNotEmpty) {
          buf.writeln('- **Acteur principal** : `${uc.actorId}`');
        }
        if (uc.preconditions.isNotEmpty) {
          buf.writeln('- **Préconditions** : ${uc.preconditions.join(' ; ')}');
        }
        if (uc.mainFlow.isNotEmpty) {
          buf.writeln('- **Scénario nominal** :');
          for (final step in uc.mainFlow) {
            buf.writeln('  - $step');
          }
        }
        if (uc.alternativeFlows.isNotEmpty) {
          buf.writeln('- **Scénarios alternatifs** :');
          for (final alt in uc.alternativeFlows) {
            buf.writeln('  - $alt');
          }
        }
        if (uc.postconditions.isNotEmpty) {
          buf.writeln('- **Postconditions** : ${uc.postconditions.join(' ; ')}');
        }
        buf.writeln();
      }
    }

    if (cdc.nonFunctionalRequirements.isNotEmpty) {
      buf
        ..writeln('### 3.4 Exigences non fonctionnelles')
        ..writeln()
        ..writeln('| Code | Catégorie | Exigence | Indicateur cible |')
        ..writeln('|---|---|---|---|');
      for (final enf in cdc.nonFunctionalRequirements) {
        final desc = enf.description.isEmpty
            ? enf.title
            : '**${enf.title}** — ${enf.description}';
        buf.writeln(
          '| `${enf.code}` | ${enf.category.label} | ${_esc(desc)} | ${_esc(enf.targetMetric.isEmpty ? '—' : enf.targetMetric)} |',
        );
      }
      buf.writeln();
    }
  }

  static void _writeEventStorming(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final es = project.eventStorming;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln(
        '## 4. Event Storming (Bounded Contexts, Catalogue & Flux)',
      )
      ..writeln();

    if (!es.hasContent) {
      buf
        ..writeln('_Aucun document Event Storming formalisé._')
        ..writeln();
      return;
    }

    for (var docIdx = 0; docIdx < es.documents.length; docIdx++) {
      final doc = es.documents[docIdx];
      buf
        ..writeln(
          '### 4.${docIdx + 1} ${doc.meta.boundedContext} (`${doc.fileName}`)',
        )
        ..writeln()
        ..writeln(
          '- **Domaine** : ${_esc(doc.meta.domain)} · **Format** : `${doc.meta.format.yamlValue}` · **Date** : `${doc.meta.date}`'
          '${doc.meta.facilitator.isNotEmpty ? ' · **Facilitateur** : ${_esc(doc.meta.facilitator)}' : ''} · **DSL** : `v${doc.dslVersion}`',
        )
        ..writeln();

      if (doc.catalog.isNotEmpty) {
        buf
          ..writeln('#### Légende du mur (`catalog`)')
          ..writeln()
          ..writeln('| Catégorie | ID | Nom | Type |')
          ..writeln('|---|---|---|---|');
        for (final a in doc.catalog.actors) {
          buf.writeln(
            '| Acteur (Petit Jaune) | `${a.id}` | ${_esc(a.name)} | `${a.type?.yamlValue ?? 'human'}` |',
          );
        }
        for (final a in doc.catalog.aggregates) {
          buf.writeln(
            '| Agrégat (Grand Jaune) | `${a.id}` | ${_esc(a.name)} | — |',
          );
        }
        for (final e in doc.catalog.externalSystems) {
          buf.writeln(
            '| Système externe (Rose pâle) | `${e.id}` | ${_esc(e.name)} | — |',
          );
        }
        buf.writeln();
      }

      final steps = doc.sortedSteps;
      if (steps.isEmpty) {
        buf
          ..writeln('_Aucune étape modélisée dans ce Bounded Context._')
          ..writeln();
        continue;
      }

      // Diagramme Mermaid flowchart LR fidèle aux couleurs et passerelles DSL v1.0
      buf
        ..writeln('```mermaid')
        ..writeln('flowchart LR')
        ..writeln(
          '  classDef domainEvent fill:#FF9800,stroke:#E65100,color:#111;',
        )
        ..writeln(
          '  classDef errorEvent fill:#FF7043,stroke:#BF360C,color:#fff;',
        )
        ..writeln(
          '  classDef extEvent fill:#FFE0B2,stroke:#E65100,stroke-dasharray: 5 5,color:#111;',
        )
        ..writeln(
          '  classDef command fill:#2196F3,stroke:#0D47A1,color:#fff;',
        )
        ..writeln(
          '  classDef actor fill:#FFEB3B,stroke:#F57F17,color:#111;',
        )
        ..writeln(
          '  classDef aggregate fill:#FFC107,stroke:#FF6F00,color:#111;',
        )
        ..writeln(
          '  classDef externalSystem fill:#F8BBD0,stroke:#AD1457,color:#111;',
        )
        ..writeln(
          '  classDef policy fill:#BA68C8,stroke:#4A148C,color:#fff;',
        )
        ..writeln(
          '  classDef readModel fill:#66BB6A,stroke:#1B5E20,color:#111;',
        )
        ..writeln(
          '  classDef hotspot fill:#EC407A,stroke:#880E4F,color:#fff;',
        )
        ..writeln(
          '  classDef gateway fill:#ECEFF1,stroke:#455A64,color:#111;',
        );

      final localEventNodeId = <String, String>{};
      for (final step in steps) {
        for (final evt in step.emittedEvents) {
          localEventNodeId[evt.id] = _mermaidNodeId('EVT_${evt.id}');
        }
      }
      final declaredExternalNodes = <String>{};

      String ensureEventNode(String eventRef) {
        final existing = localEventNodeId[eventRef];
        if (existing != null) return existing;
        final nodeId = _mermaidNodeId('XEVT_$eventRef');
        if (declaredExternalNodes.add(nodeId)) {
          buf.writeln(
            '  $nodeId["${_mermaidEsc('[EXT-EVT] $eventRef')}"]:::extEvent',
          );
        }
        return nodeId;
      }

      for (final step in steps) {
        final s = step.step;
        final cmdId = 'S${s}_CMD';
        buf.writeln(
          '  $cmdId["${_mermaidEsc('[CMD #$s] ${step.command.name}')}"]:::command',
        );

        String entryTarget = cmdId;
        if (step.policy != null) {
          final polId = 'S${s}_POL';
          buf.writeln(
            '  $polId["${_mermaidEsc('[POL] ${step.policy!.name}')}"]:::policy',
          );
          buf.writeln('  $polId --> $cmdId');
          entryTarget = polId;
        }

        if (step.actor.isNotEmpty) {
          final actName = doc.catalog.findActor(step.actor)?.name ?? step.actor;
          final actId = 'S${s}_ACT';
          buf.writeln(
            '  $actId["${_mermaidEsc('[ACT] $actName')}"]:::actor',
          );
          buf.writeln('  $actId --> $cmdId');
          if (step.readModel != null) {
            final rmId = 'S${s}_RM';
            buf.writeln(
              '  $rmId["${_mermaidEsc('[RM] ${step.readModel!.name}')}"]:::readModel',
            );
            buf.writeln('  $rmId --> $actId');
          }
        } else if (step.readModel != null) {
          final rmId = 'S${s}_RM';
          buf.writeln(
            '  $rmId["${_mermaidEsc('[RM] ${step.readModel!.name}')}"]:::readModel',
          );
          buf.writeln('  $rmId --> $entryTarget');
        }

        if (step.triggeredBy != null) {
          final trig = step.triggeredBy!;
          switch (trig.mode) {
            case EventStormTriggerMode.single:
              final srcNode = ensureEventNode(trig.eventIds.first);
              buf.writeln('  $srcNode --> $entryTarget');
            case EventStormTriggerMode.allOf:
              final gwId = 'S${s}_AND';
              buf.writeln('  $gwId{"ET (all_of)"}:::gateway');
              for (final ref in trig.eventIds) {
                buf.writeln('  ${ensureEventNode(ref)} --> $gwId');
              }
              buf.writeln('  $gwId --> $entryTarget');
            case EventStormTriggerMode.anyOf:
              final gwId = 'S${s}_OR';
              buf.writeln('  $gwId{"OU (any_of)"}:::gateway');
              for (final ref in trig.eventIds) {
                buf.writeln('  ${ensureEventNode(ref)} --> $gwId');
              }
              buf.writeln('  $gwId --> $entryTarget');
          }
        }

        String emitterNode = cmdId;
        if (step.aggregate.isNotEmpty) {
          final aggName =
              doc.catalog.findAggregate(step.aggregate)?.name ?? step.aggregate;
          final aggId = 'S${s}_AGG';
          buf.writeln(
            '  $aggId["${_mermaidEsc('[AGG] $aggName')}"]:::aggregate',
          );
          buf.writeln('  $cmdId --> $aggId');
          emitterNode = aggId;
        }
        if (step.externalSystem.isNotEmpty) {
          final extName =
              doc.catalog.findExternalSystem(step.externalSystem)?.name ??
              step.externalSystem;
          final extId = 'S${s}_EXT';
          buf.writeln(
            '  $extId["${_mermaidEsc('[EXT] $extName')}"]:::externalSystem',
          );
          buf.writeln('  $emitterNode --> $extId');
          emitterNode = extId;
        }

        if (step.domainEvent != null) {
          final evt = step.domainEvent!;
          final evtNode = localEventNodeId[evt.id]!;
          buf.writeln(
            '  $evtNode["${_mermaidEsc('[${evt.id}] ${evt.name}')}"]:::domainEvent',
          );
          buf.writeln('  $emitterNode --> $evtNode');
        } else if (step.outcomes.isNotEmpty) {
          for (final outcome in step.outcomes) {
            final evt = outcome.domainEvent;
            final evtNode = localEventNodeId[evt.id]!;
            final style = outcome.isError ? 'errorEvent' : 'domainEvent';
            buf.writeln(
              '  $evtNode["${_mermaidEsc('[${evt.id}] ${evt.name}')}"]:::$style',
            );
            buf.writeln(
              '  $emitterNode -->|"${_mermaidEsc(outcome.condition)}"| $evtNode',
            );
          }
        }

        for (final hs in step.hotspots) {
          final hsId = _mermaidNodeId('S${s}_${hs.id}');
          final statusTag = hs.isResolved ? '✓' : '!';
          buf.writeln(
            '  $hsId["${_mermaidEsc('[$statusTag ${hs.id}] ${hs.question}')}"]:::hotspot',
          );
          buf.writeln('  $cmdId -.-> $hsId');
        }
      }

      buf
        ..writeln('```')
        ..writeln()
        ..writeln(
          '| Étape | Backlog | Déclencheur (`triggered_by`) | Read Model / Acteur / Politique | Commande | Cible | Événement(s) / Outcomes | Hotspots |',
        )
        ..writeln('|---|---|---|---|---|---|---|---|');

      for (final step in steps) {
        final backlogText = (step.backlog != null && step.backlog!.isNotEmpty)
            ? [
                if (step.backlog!.epic.isNotEmpty) step.backlog!.epic,
                if (step.backlog!.story.isNotEmpty) step.backlog!.story,
              ].join(' / ')
            : '—';
        final trigText = step.triggeredBy?.summaryLabel ?? '—';
        final leftParts = <String>[
          if (step.readModel != null)
            '**RM** ${step.readModel!.name}'
                '${step.readModel!.fields.isEmpty ? '' : ' (${step.readModel!.fields.join(', ')})'}',
          if (step.actor.isNotEmpty)
            '**ACT** ${doc.catalog.findActor(step.actor)?.name ?? step.actor}',
          if (step.policy != null)
            '**POL** ${step.policy!.name} _(${step.policy!.rule})_',
        ];
        final cmdText =
            '**${step.command.name}**'
            '${step.command.payload.isEmpty ? '' : ' (${step.command.payload.join(', ')})'}';
        final targetParts = <String>[
          if (step.aggregate.isNotEmpty)
            'AGG: ${doc.catalog.findAggregate(step.aggregate)?.name ?? step.aggregate}',
          if (step.externalSystem.isNotEmpty)
            'EXT: ${doc.catalog.findExternalSystem(step.externalSystem)?.name ?? step.externalSystem}',
        ];
        final evtText = step.domainEvent != null
            ? '`${step.domainEvent!.id}` **${step.domainEvent!.name}**'
                '${step.domainEvent!.data.isEmpty ? '' : ' (${step.domainEvent!.data.join(', ')})'}'
            : step.outcomes
                  .map(
                    (o) =>
                        '${o.isError ? '⚠ ' : ''}_Si ${o.condition}_ → `${o.domainEvent.id}` **${o.domainEvent.name}**',
                  )
                  .join('<br>');
        final hsText = step.hotspots.isEmpty
            ? '—'
            : step.hotspots
                  .map(
                    (h) =>
                        '`${h.id}` [${h.severity.yamlValue}/${h.status.yamlValue}] ${h.question}',
                  )
                  .join('<br>');

        buf.writeln(
          '| ${step.step} | ${_esc(backlogText)} | ${_esc(trigText)} | ${_esc(leftParts.isEmpty ? '—' : leftParts.join(' ; '))} | ${_esc(cmdText)} | ${_esc(targetParts.isEmpty ? '—' : targetParts.join(' / '))} | ${_esc(evtText)} | ${_esc(hsText)} |',
        );
      }
      buf.writeln();
    }
  }

  static String _mermaidNodeId(String raw) =>
      raw.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

  static void _writeBusinessObjects(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 5. Objets métiers')
      ..writeln();

    if (project.businessObjects.isEmpty) {
      buf
        ..writeln('_Aucun objet métier modélisé._')
        ..writeln();
      return;
    }

    // Diagramme ER Mermaid
    buf
      ..writeln('```mermaid')
      ..writeln('erDiagram');
    for (final obj in project.businessObjects) {
      buf.writeln('  ${obj.technicalName} {');
      for (final attr in obj.attributes) {
        buf.writeln('    ${attr.type.dslKeyword} ${attr.name}');
      }
      buf.writeln('  }');
    }
    for (final obj in project.businessObjects) {
      for (final rel in obj.relations) {
        final target = project.findBusinessObject(rel.targetObjectId);
        final targetName = target?.technicalName ?? rel.targetObjectId;
        final arrow = switch (rel.cardinality) {
          BusinessRelationCardinality.oneToOne => '||--||',
          BusinessRelationCardinality.oneToMany => '||--o{',
          BusinessRelationCardinality.manyToMany => '}o--o{',
        };
        buf.writeln('  ${obj.technicalName} $arrow $targetName : "${rel.name}"');
      }
    }
    buf
      ..writeln('```')
      ..writeln();

    for (final obj in project.businessObjects) {
      buf.writeln('### ${obj.name} (`${obj.technicalName}`)');
      if (obj.description.isNotEmpty) {
        buf.writeln(obj.description);
      }
      buf.writeln();
      if (obj.attributes.isNotEmpty) {
        buf
          ..writeln(
            '_Volumétrie schéma : ${obj.totalAttributeCount} / ${BusinessObjectSpec.maxAttributesPerObject} attributs_',
          )
          ..writeln()
          ..writeln('| Attribut | Type | Obligatoire | Contraintes / Valeurs | Description |')
          ..writeln('|---|---|---|---|---|');
        void writeRows(List<BusinessAttribute> attrs, String prefix) {
          for (final attr in attrs) {
            final fullName = prefix.isEmpty ? attr.name : '$prefix.${attr.name}';
            final typeLabel = attr.isArray
                ? '${attr.type.dslKeyword}[]'
                : attr.type.dslKeyword;
            final constraints = <String>[
              if (attr.unique) 'unique',
              if (attr.isArray && attr.estimatedMaxRows != null)
                'max ${attr.estimatedMaxRows} lignes',
              if (attr.enumValues.isNotEmpty)
                'enum(${attr.enumValues.join(', ')})',
              if (attr.schemaConstraints.isNotEmpty)
                attr.schemaConstraints.formatSummary(),
              if (attr.constraints.isNotEmpty) attr.constraints,
            ].join(' ; ');
            buf.writeln(
              '| `$fullName` | `$typeLabel` | ${attr.required ? 'Oui' : 'Non'} | ${_esc(constraints.isEmpty ? '—' : constraints)} | ${_esc(attr.description.isEmpty ? '—' : attr.description)} |',
            );
            if (attr.children.isNotEmpty) {
              writeRows(attr.children, attr.isArray ? '$fullName[]' : fullName);
            }
          }
        }
        writeRows(obj.attributes, '');
        buf.writeln();
      }
      if (obj.relations.isNotEmpty) {
        buf.writeln('**Relations :**');
        for (final rel in obj.relations) {
          final target = project.findBusinessObject(rel.targetObjectId);
          final targetName = target?.technicalName ?? rel.targetObjectId;
          buf.writeln(
            '- `${rel.name}` → `$targetName` (${rel.cardinality.symbol})${rel.description.isEmpty ? '' : ' : ${rel.description}'}',
          );
        }
        buf.writeln();
      }
      if (obj.lifecycleStates.isNotEmpty) {
        buf.writeln('**Cycle de vie :**');
        for (final s in obj.lifecycleStates) {
          final flags = <String>[
            if (s.isInitial) 'initial',
            if (s.isTerminal) 'terminal',
          ].join(', ');
          buf.writeln(
            '- `${s.name}` (${s.effectiveLabel})${flags.isEmpty ? '' : ' _[$flags]_'}${s.description.isEmpty ? '' : ' : ${s.description}'}',
          );
        }
        if (obj.lifecycleTransitions.isNotEmpty) {
          buf
            ..writeln()
            ..writeln('```mermaid')
            ..writeln('stateDiagram-v2');
          for (final s in obj.lifecycleStates) {
            if (s.isInitial) buf.writeln('  [*] --> ${s.name}');
          }
          for (final t in obj.lifecycleTransitions) {
            final label = t.trigger.isEmpty ? '' : ' : ${t.trigger}';
            buf.writeln('  ${t.fromState} --> ${t.toState}$label');
          }
          for (final s in obj.lifecycleStates) {
            if (s.isTerminal) buf.writeln('  ${s.name} --> [*]');
          }
          buf.writeln('```');
        }
        buf.writeln();
      }
    }
  }

  static void _writeExampleMapping(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 6. Example Mapping (Stories, Règles, Exemples & Questions)')
      ..writeln();

    if (project.exampleMappings.isEmpty) {
      buf
        ..writeln('_Aucun tableau d’Example Mapping formalisé._')
        ..writeln();
      return;
    }

    for (final story in project.exampleMappings) {
      final obj = story.targetObjectId.isEmpty
          ? null
          : project.findBusinessObject(story.targetObjectId);
      final targetBadge = obj == null
          ? ''
          : ' — Objet : `${obj.technicalName}`';
      buf.writeln('### ${story.code} — ${story.title}$targetBadge');
      if (story.description.isNotEmpty) {
        buf.writeln(story.description);
      }
      if (story.requirementIds.isNotEmpty) {
        buf.writeln('- **Exigences liées** : `${story.requirementIds.join('`, `')}`');
      }
      if (story.rules.isNotEmpty) {
        buf.writeln('- **Règles (Bleu) & Exemples (Vert)** :');
        for (final rule in story.rules) {
          final linked = rule.linkedRuleId.isEmpty
              ? ''
              : ' _(${rule.linkedRuleId})_';
          buf.writeln('  - **[${rule.category.label}] ${rule.title}**$linked');
          for (final ex in rule.examples) {
            final gwt = [
              if (ex.given.isNotEmpty) 'Étant donné ${ex.given}',
              if (ex.when.isNotEmpty) 'Quand ${ex.when}',
              if (ex.then.isNotEmpty) 'Alors ${ex.then}',
            ].join(' ; ');
            buf.writeln(
              '    - _[${ex.kind.label}]_ **${ex.title}**${gwt.isEmpty ? '' : ' : $gwt'}',
            );
          }
        }
      }
      if (story.questions.isNotEmpty) {
        buf.writeln('- **Questions (Rouge)** :');
        for (final q in story.questions) {
          final status = q.resolved ? 'Résolue' : 'Ouverte';
          final ans = q.answer.isEmpty ? '' : ' → _${q.answer}_';
          buf.writeln('  - **[$status]** ${q.question}$ans');
        }
      }
      if (story.refinementNotes.isNotEmpty) {
        buf.writeln(
          '- **Affinages appliqués** : ${story.refinementNotes.join(' ; ')}',
        );
      }
      buf.writeln();
    }
  }

  static void _writeBusinessRules(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 7. Règles de gestion')
      ..writeln();

    if (project.businessRules.isEmpty) {
      buf
        ..writeln('_Aucune règle de gestion formalisée._')
        ..writeln();
      return;
    }

    for (final category in BusinessRuleCategory.values) {
      final rules = project.businessRules
          .where((r) => r.category == category)
          .toList();
      if (rules.isEmpty) continue;
      buf
        ..writeln('### 7.${category.index + 1} ${category.label}')
        ..writeln();
      for (final rule in rules) {
        buf.writeln(
          '#### ${rule.code} — ${rule.title} _(${rule.priority.label})_',
        );
        if (rule.description.isNotEmpty) {
          buf.writeln(rule.description);
        }
        if (rule.targetObjectIds.isNotEmpty || rule.targetAttributes.isNotEmpty) {
          final targets = [
            for (final id in rule.targetObjectIds)
              project.findBusinessObject(id)?.technicalName ?? id,
            ...rule.targetAttributes,
          ];
          buf.writeln('- **Cibles** : `${targets.join('`, `')}`');
        }
        if (rule.trigger.isNotEmpty) {
          buf.writeln('- **Quand** : ${rule.trigger}');
        }
        if (rule.condition.isNotEmpty) {
          buf.writeln('- **Si** : ${rule.condition}');
        }
        if (rule.effect.isNotEmpty) {
          buf.writeln('- **Alors** : ${rule.effect}');
        }
        if (rule.errorMessage.isNotEmpty) {
          buf.writeln('- **Message d’erreur** : « ${rule.errorMessage} »');
        }
        if (rule.examples.isNotEmpty) {
          buf.writeln('- **Exemples** : ${rule.examples.join(' ; ')}');
        }
        buf.writeln();
      }
    }
  }

  static void _writeCoherenceReport(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final local = SpecCoherenceAnalyzer.analyze(project);
    final all = [...local, ...project.coherenceIssues.where((i) => i.source == 'ai')];
    if (all.isEmpty) return;

    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 8. Points de vigilance & Cohérence')
      ..writeln();
    for (final issue in all) {
      final prefix = switch (issue.severity) {
        CoherenceSeverity.error => '[ERREUR]',
        CoherenceSeverity.warning => '[ATTENTION]',
        CoherenceSeverity.info => '[INFO]',
      };
      buf.writeln('- **$prefix ${issue.code} — ${issue.title}** : ${issue.description}');
    }
    buf.writeln();
  }

  static void _writeCostSummary(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    final cost = project.costSpec;
    if (!cost.hasContent) return;

    final summary = CostCalculator.compute(cost);
    final cur = summary.currency;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## Synthèse FinOps — Estimation Build, Run & TCO')
      ..writeln()
      ..writeln(
        '- **Mode contractuel** : ${cost.deliveryMode.label} · **Ingénierie assistée par IA** : ${cost.aiProductivity.enabled ? 'Activée' : 'Désactivée'}',
      )
      ..writeln(
        '- **Build MVP (`Must`)** : ${CostCalculator.formatDays(summary.mvpLot.effectiveTotalDays)} — **${CostCalculator.formatAmount(summary.mvpLot.effectiveTotalCost, cur)}**',
      )
      ..writeln(
        '- **Build Cible (`Must + Should + Could`)** : ${CostCalculator.formatDays(summary.fullLot.effectiveTotalDays)} — **${CostCalculator.formatAmount(summary.fullLot.effectiveTotalCost, cur)}** _(P80 : ${CostCalculator.formatAmount(summary.fullLot.effectiveP80Cost, cur)})_',
      )
      ..writeln(
        '- **Run OPEX Année 1** : ${CostCalculator.formatAmount(summary.yearlyRunYear1, cur)} _(${CostCalculator.formatAmount(summary.monthlyRunYear1, cur)} / mois)_',
      );
    if (summary.riskEmvCost > 0.0) {
      buf.writeln(
        '- **Provision Risques (EMV)** : ${CostCalculator.formatAmount(summary.riskEmvCost, cur)} _(${CostCalculator.formatDays(summary.riskEmvDays)})_',
      );
    }
    buf
      ..writeln(
        '- **TCO 3 ans** : **${CostCalculator.formatAmount(summary.tco3Years, cur)}** _(1 an : ${CostCalculator.formatAmount(summary.tco1Year, cur)} · 5 ans : ${CostCalculator.formatAmount(summary.tco5Years, cur)})_',
      )
      ..writeln();
  }

  static String _esc(String value) =>
      value.replaceAll('|', '\\|').replaceAll('\n', '<br>');

  static String _mermaidEsc(String value) =>
      value.replaceAll('"', "'").replaceAll('\n', ' ').trim();
}
