/// Exportateur du cahier des charges complet au format Markdown ([SpecMarkdownExporter]).
library;

import '../../models/business_object_spec.dart';
import '../../models/business_rule_spec.dart';
import '../../models/spec_coherence_issue.dart';
import '../../models/spec_forge_project.dart';
import '../spec_coherence_analyzer.dart';

/// Génère un document Markdown structuré (avec diagrammes Mermaid) depuis un [SpecForgeProject].
abstract final class SpecMarkdownExporter {
  /// Exporte [project] en cahier des charges Markdown complet.
  static String export(SpecForgeProject project) {
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

    _writeVision(buf, project);
    _writeCahierDesCharges(buf, project);
    _writeBusinessObjects(buf, project);
    _writeBusinessRules(buf, project);
    _writeCoherenceReport(buf, project);

    return buf.toString();
  }

  static void _writeVision(StringBuffer buf, SpecForgeProject project) {
    final v = project.vision;
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 1. Cadrage & Acteurs')
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
      ..writeln('## 2. Cahier des charges fonctionnel & non fonctionnel')
      ..writeln();

    if (cdc.modules.isNotEmpty) {
      buf.writeln('### 2.1 Modules fonctionnels');
      for (final m in cdc.modules) {
        buf.writeln(
          '- **${m.name}** (`${m.id}`)${m.description.isEmpty ? '' : ' : ${m.description}'}',
        );
      }
      buf.writeln();
    }

    if (cdc.functionalRequirements.isNotEmpty) {
      buf
        ..writeln('### 2.2 Exigences fonctionnelles')
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
      buf.writeln('### 2.3 Cas d’usage clés');
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
        ..writeln('### 2.4 Exigences non fonctionnelles')
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

  static void _writeBusinessObjects(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 3. Objets métiers')
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
          ..writeln('| Attribut | Type | Obligatoire | Contraintes / Valeurs | Description |')
          ..writeln('|---|---|---|---|---|');
        for (final attr in obj.attributes) {
          final typeLabel = attr.isArray
              ? '${attr.type.dslKeyword}[]'
              : attr.type.dslKeyword;
          final constraints = <String>[
            if (attr.unique) 'unique',
            if (attr.enumValues.isNotEmpty)
              'enum(${attr.enumValues.join(', ')})',
            if (attr.constraints.isNotEmpty) attr.constraints,
          ].join(' ; ');
          buf.writeln(
            '| `${attr.name}` | `$typeLabel` | ${attr.required ? 'Oui' : 'Non'} | ${_esc(constraints.isEmpty ? '—' : constraints)} | ${_esc(attr.description.isEmpty ? '—' : attr.description)} |',
          );
        }
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

  static void _writeBusinessRules(
    StringBuffer buf,
    SpecForgeProject project,
  ) {
    buf
      ..writeln('---')
      ..writeln()
      ..writeln('## 4. Règles de gestion')
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
        ..writeln('### 4.${category.index + 1} ${category.label}')
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
      ..writeln('## 5. Points de vigilance & Cohérence')
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

  static String _esc(String value) =>
      value.replaceAll('|', '\\|').replaceAll('\n', '<br>');
}
