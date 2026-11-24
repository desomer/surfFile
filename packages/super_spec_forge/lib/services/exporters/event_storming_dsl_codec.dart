/// Codec YAML `.es.yaml`, schéma JSON Draft 2020-12 (`es-dsl.schema.json`) et
/// validateur structurel & grammatical pour l'**Event Storming DSL v1.0**
/// ([EventStormingDslCodec]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

import '../../models/event_storming_spec.dart';

/// Gravité d'un diagnostic renvoyé par [EventStormingDslCodec.validateDocument].
enum EventStormDslSeverity {
  /// Violation structurelle du schéma DSL v1.0 ou d'intégrité référentielle.
  error,

  /// Anomalie non bloquante (ex. convention grammaticale, référence externe non vérifiable).
  warning,

  /// Suggestion d'amélioration ou information.
  info,
}

/// Diagnostic unitaire produit lors de la validation d'un [EventStormDocument].
@immutable
class EventStormDslDiagnostic {
  /// Construit un diagnostic immuable.
  const EventStormDslDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.stepNumber,
    this.suggestion = '',
  });

  /// Gravité (`error`, `warning`, `info`).
  final EventStormDslSeverity severity;

  /// Code stable (`DSL-ES-*` ou `GRAM-ES-*`).
  final String code;

  /// Description détaillée de l'anomalie.
  final String message;

  /// Numéro d'étape concerné, le cas échéant.
  final int? stepNumber;

  /// Piste de correction suggérée.
  final String suggestion;
}

/// Sérialiseur/parseur `.es.yaml`, générateur `es-dsl.schema.json` et
/// validateur du **Event Storming DSL v1.0**.
abstract final class EventStormingDslCodec {
  /// Nom de fichier canonique du schéma JSON à côté des fichiers `.es.yaml`.
  static const String schemaFileName = 'es-dsl.schema.json';

  /// En-tête YAML Language Server inséré en tête de chaque fichier `.es.yaml`.
  static const String schemaHeaderLine =
      '# yaml-language-server: \$schema=./$schemaFileName';

  /// Expression régulière des identifiants du catalogue (`ACT-*`, `AGG-*`, `EXT-*`).
  static final RegExp catalogIdPattern = RegExp(
    r'^(ACT|AGG|EXT)-[A-Z0-9_-]+$',
  );

  /// Expression régulière d'un identifiant d'événement domaine local (`EVT-01`, `EVT-02A`).
  static final RegExp domainEventIdPattern = RegExp(r'^EVT-[0-9]+[A-Z]?$');

  /// Expression régulière d'une référence `triggered_by` (locale `EVT-01` ou inter-contexte `CMD:EVT-02A`).
  static final RegExp triggerEventRefPattern = RegExp(
    r'^([A-Z0-9_-]+:)?EVT-[0-9]+[A-Z]?$',
  );

  /// Expression régulière d'un identifiant de hotspot (`HS-01`, `HS-12`).
  static final RegExp hotspotIdPattern = RegExp(r'^HS-[0-9]+$');

  /// Expression régulière d'une date ISO (`YYYY-MM-DD`).
  static final RegExp isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Schéma JSON Draft 2020-12 officiel de l'Event Storming DSL v1.0.
  static Map<String, Object?> get esDslSchemaMap => <String, Object?>{
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    r'$id': 'https://example.org/es-dsl.schema.json',
    'title': 'Event Storming DSL v1.0',
    'type': 'object',
    'required': <String>['event_storming'],
    'additionalProperties': false,
    'properties': <String, Object?>{
      'event_storming': <String, Object?>{
        'type': 'object',
        'required': <String>['dsl_version', 'meta', 'flow'],
        'additionalProperties': false,
        'properties': <String, Object?>{
          'dsl_version': <String, Object?>{'type': 'string', 'const': '1.0'},
          'meta': <String, Object?>{
            'type': 'object',
            'required': <String>['domain', 'bounded_context', 'format', 'date'],
            'properties': <String, Object?>{
              'domain': <String, Object?>{'type': 'string'},
              'bounded_context': <String, Object?>{'type': 'string'},
              'format': <String, Object?>{
                'type': 'string',
                'enum': <String>[
                  'big_picture',
                  'process_modeling',
                  'design_level',
                ],
              },
              'date': <String, Object?>{'type': 'string', 'format': 'date'},
              'facilitator': <String, Object?>{'type': 'string'},
            },
          },
          'catalog': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'actors': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{r'$ref': r'#/$defs/catalogItem'},
              },
              'aggregates': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{r'$ref': r'#/$defs/catalogItem'},
              },
              'external_systems': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{r'$ref': r'#/$defs/catalogItem'},
              },
            },
          },
          'flow': <String, Object?>{
            'type': 'array',
            'minItems': 1,
            'items': <String, Object?>{r'$ref': r'#/$defs/step'},
          },
        },
      },
    },
    r'$defs': <String, Object?>{
      'catalogItem': <String, Object?>{
        'type': 'object',
        'required': <String>['id', 'name'],
        'properties': <String, Object?>{
          'id': <String, Object?>{
            'type': 'string',
            'pattern': r'^(ACT|AGG|EXT)-[A-Z0-9_-]+$',
          },
          'name': <String, Object?>{'type': 'string'},
          'type': <String, Object?>{
            'type': 'string',
            'enum': <String>['human', 'timer', 'system'],
          },
        },
      },
      'domainEvent': <String, Object?>{
        'type': 'object',
        'required': <String>['id', 'name'],
        'properties': <String, Object?>{
          'id': <String, Object?>{
            'type': 'string',
            'pattern': r'^EVT-[0-9]+[A-Z]?$',
          },
          'name': <String, Object?>{'type': 'string'},
          'data': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
          },
        },
      },
      'eventRef': <String, Object?>{
        'type': 'string',
        'pattern': r'^([A-Z0-9_-]+:)?EVT-[0-9]+[A-Z]?$',
      },
      'step': <String, Object?>{
        'type': 'object',
        'required': <String>['step', 'command'],
        'properties': <String, Object?>{
          'step': <String, Object?>{'type': 'integer', 'minimum': 1},
          'backlog': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'epic': <String, Object?>{'type': 'string'},
              'story': <String, Object?>{'type': 'string'},
            },
          },
          'triggered_by': <String, Object?>{
            'oneOf': <Object?>[
              <String, Object?>{r'$ref': r'#/$defs/eventRef'},
              <String, Object?>{
                'type': 'object',
                'required': <String>['all_of'],
                'additionalProperties': false,
                'properties': <String, Object?>{
                  'all_of': <String, Object?>{
                    'type': 'array',
                    'minItems': 2,
                    'items': <String, Object?>{r'$ref': r'#/$defs/eventRef'},
                  },
                },
              },
              <String, Object?>{
                'type': 'object',
                'required': <String>['any_of'],
                'additionalProperties': false,
                'properties': <String, Object?>{
                  'any_of': <String, Object?>{
                    'type': 'array',
                    'minItems': 2,
                    'items': <String, Object?>{r'$ref': r'#/$defs/eventRef'},
                  },
                },
              },
            ],
          },
          'policy': <String, Object?>{
            'type': 'object',
            'required': <String>['name', 'rule'],
            'properties': <String, Object?>{
              'name': <String, Object?>{'type': 'string'},
              'rule': <String, Object?>{'type': 'string'},
            },
          },
          'read_model': <String, Object?>{
            'type': 'object',
            'required': <String>['name'],
            'properties': <String, Object?>{
              'name': <String, Object?>{'type': 'string'},
              'source_events': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{r'$ref': r'#/$defs/eventRef'},
              },
              'fields': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
              },
            },
          },
          'actor': <String, Object?>{'type': 'string'},
          'command': <String, Object?>{
            'type': 'object',
            'required': <String>['name'],
            'properties': <String, Object?>{
              'name': <String, Object?>{'type': 'string'},
              'payload': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
              },
            },
          },
          'aggregate': <String, Object?>{'type': 'string'},
          'external_system': <String, Object?>{'type': 'string'},
          'domain_event': <String, Object?>{r'$ref': r'#/$defs/domainEvent'},
          'outcomes': <String, Object?>{
            'type': 'array',
            'minItems': 2,
            'items': <String, Object?>{
              'type': 'object',
              'required': <String>['condition', 'domain_event'],
              'properties': <String, Object?>{
                'condition': <String, Object?>{'type': 'string'},
                'is_error': <String, Object?>{'type': 'boolean'},
                'domain_event': <String, Object?>{
                  r'$ref': r'#/$defs/domainEvent',
                },
              },
            },
          },
          'hotspots': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'object',
              'required': <String>['id', 'question', 'severity', 'status'],
              'properties': <String, Object?>{
                'id': <String, Object?>{
                  'type': 'string',
                  'pattern': r'^HS-[0-9]+$',
                },
                'question': <String, Object?>{'type': 'string'},
                'severity': <String, Object?>{
                  'type': 'string',
                  'enum': <String>['low', 'medium', 'high', 'blocker'],
                },
                'owner': <String, Object?>{'type': 'string'},
                'status': <String, Object?>{
                  'type': 'string',
                  'enum': <String>['open', 'resolved'],
                },
              },
            },
          },
        },
        'oneOf': <Object?>[
          <String, Object?>{'required': <String>['domain_event']},
          <String, Object?>{'required': <String>['outcomes']},
        ],
      },
    },
  };

  /// Schéma JSON formaté (indenté à 2 espaces) prêt à être écrit dans `es-dsl.schema.json`.
  static String get esDslSchemaJson =>
      '${const JsonEncoder.withIndent('  ').convert(esDslSchemaMap)}\n';

  /// Sérialise un [EventStormDocument] au format YAML canonique `.es.yaml`.
  static String toYaml(
    EventStormDocument doc, {
    bool includeSchemaHeader = true,
  }) {
    final buf = StringBuffer();
    if (includeSchemaHeader) {
      buf.writeln(schemaHeaderLine);
    }
    buf
      ..writeln('event_storming:')
      ..writeln('  dsl_version: ${_q(doc.dslVersion)}')
      ..writeln()
      ..writeln('  meta:')
      ..writeln('    domain: ${_q(doc.meta.domain)}')
      ..writeln('    bounded_context: ${_q(doc.meta.boundedContext)}')
      ..writeln('    format: ${_q(doc.meta.format.yamlValue)}')
      ..writeln('    date: ${_q(doc.meta.date)}');
    if (doc.meta.facilitator.isNotEmpty) {
      buf.writeln('    facilitator: ${_q(doc.meta.facilitator)}');
    }

    if (doc.catalog.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('  catalog:');
      if (doc.catalog.actors.isNotEmpty) {
        buf.writeln('    actors:');
        for (final actor in doc.catalog.actors) {
          buf
            ..writeln('      - id: ${_q(actor.id)}')
            ..writeln('        name: ${_q(actor.name)}');
          if (actor.type != null) {
            buf.writeln('        type: ${_q(actor.type!.yamlValue)}');
          }
        }
      }
      if (doc.catalog.aggregates.isNotEmpty) {
        buf.writeln('    aggregates:');
        for (final agg in doc.catalog.aggregates) {
          buf
            ..writeln('      - id: ${_q(agg.id)}')
            ..writeln('        name: ${_q(agg.name)}');
        }
      }
      if (doc.catalog.externalSystems.isNotEmpty) {
        buf.writeln('    external_systems:');
        for (final ext in doc.catalog.externalSystems) {
          buf
            ..writeln('      - id: ${_q(ext.id)}')
            ..writeln('        name: ${_q(ext.name)}');
        }
      }
    }

    final steps = doc.sortedSteps;
    buf
      ..writeln()
      ..writeln(steps.isEmpty ? '  flow: []' : '  flow:');
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (i > 0) buf.writeln();
      buf.writeln('    - step: ${step.step}');

      if (step.backlog != null && step.backlog!.isNotEmpty) {
        buf.writeln('      backlog:');
        if (step.backlog!.epic.isNotEmpty) {
          buf.writeln('        epic: ${_q(step.backlog!.epic)}');
        }
        if (step.backlog!.story.isNotEmpty) {
          buf.writeln('        story: ${_q(step.backlog!.story)}');
        }
      }

      if (step.triggeredBy != null) {
        final trig = step.triggeredBy!;
        switch (trig.mode) {
          case EventStormTriggerMode.single:
            buf.writeln('      triggered_by: ${_q(trig.eventIds.first)}');
          case EventStormTriggerMode.allOf:
            buf
              ..writeln('      triggered_by:')
              ..writeln('        all_of: ${_inlineStringList(trig.eventIds)}');
          case EventStormTriggerMode.anyOf:
            buf
              ..writeln('      triggered_by:')
              ..writeln('        any_of: ${_inlineStringList(trig.eventIds)}');
        }
      }

      if (step.policy != null) {
        buf
          ..writeln('      policy:')
          ..writeln('        name: ${_q(step.policy!.name)}')
          ..writeln('        rule: ${_q(step.policy!.rule)}');
      }

      if (step.readModel != null) {
        final rm = step.readModel!;
        buf
          ..writeln('      read_model:')
          ..writeln('        name: ${_q(rm.name)}');
        if (rm.sourceEvents.isNotEmpty) {
          buf.writeln(
            '        source_events: ${_inlineStringList(rm.sourceEvents)}',
          );
        }
        if (rm.fields.isNotEmpty) {
          buf.writeln('        fields: ${_inlineStringList(rm.fields)}');
        }
      }

      if (step.actor.isNotEmpty) {
        buf.writeln('      actor: ${_q(step.actor)}');
      }

      buf
        ..writeln('      command:')
        ..writeln('        name: ${_q(step.command.name)}');
      if (step.command.payload.isNotEmpty) {
        buf.writeln(
          '        payload: ${_inlineStringList(step.command.payload)}',
        );
      }

      if (step.aggregate.isNotEmpty) {
        buf.writeln('      aggregate: ${_q(step.aggregate)}');
      }
      if (step.externalSystem.isNotEmpty) {
        buf.writeln('      external_system: ${_q(step.externalSystem)}');
      }

      if (step.domainEvent != null) {
        final evt = step.domainEvent!;
        buf
          ..writeln('      domain_event:')
          ..writeln('        id: ${_q(evt.id)}')
          ..writeln('        name: ${_q(evt.name)}');
        if (evt.data.isNotEmpty) {
          buf.writeln('        data: ${_inlineStringList(evt.data)}');
        }
      } else if (step.outcomes.isNotEmpty) {
        buf.writeln('      outcomes:');
        for (final outcome in step.outcomes) {
          buf
            ..writeln('        - condition: ${_q(outcome.condition)}')
            ..writeln('          is_error: ${outcome.isError}')
            ..writeln('          domain_event:')
            ..writeln('            id: ${_q(outcome.domainEvent.id)}')
            ..writeln('            name: ${_q(outcome.domainEvent.name)}');
          if (outcome.domainEvent.data.isNotEmpty) {
            buf.writeln(
              '            data: ${_inlineStringList(outcome.domainEvent.data)}',
            );
          }
        }
      }

      if (step.hotspots.isNotEmpty) {
        buf.writeln('      hotspots:');
        for (final hs in step.hotspots) {
          buf
            ..writeln('        - id: ${_q(hs.id)}')
            ..writeln('          question: ${_q(hs.question)}')
            ..writeln('          severity: ${_q(hs.severity.yamlValue)}');
          if (hs.owner.isNotEmpty) {
            buf.writeln('          owner: ${_q(hs.owner)}');
          }
          buf.writeln('          status: ${_q(hs.status.yamlValue)}');
        }
      }
    }

    return buf.toString();
  }

  /// Parse un contenu YAML `.es.yaml` en [EventStormDocument] validé.
  static EventStormDocument fromYaml(String yamlContent, {String? idHint}) {
    final trimmed = yamlContent.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Contenu YAML Event Storming vide.');
    }
    final dynamic parsed;
    try {
      parsed = loadYaml(trimmed);
    } on YamlException catch (e) {
      throw FormatException('Syntaxe YAML invalide : ${e.message}');
    }
    final plain = _toPlainDart(parsed);
    if (plain is! Map) {
      throw const FormatException(
        'Le fichier .es.yaml doit contenir un objet racine `event_storming`.',
      );
    }
    if (!plain.containsKey('event_storming') &&
        !plain.containsKey('dsl_version')) {
      throw const FormatException(
        'Clé racine obligatoire `event_storming` absente du fichier .es.yaml.',
      );
    }
    return EventStormDocument.fromJson(plain, idHint: idHint);
  }

  /// Écrit `es-dsl.schema.json` et un fichier `<slug>.es.yaml` par Bounded Context
  /// dans [targetDirectory].
  static Future<List<File>> writeAllToDirectory(
    EventStormingSpec spec,
    Directory targetDirectory,
  ) async {
    await targetDirectory.create(recursive: true);
    final sep = Platform.pathSeparator;
    final written = <File>[];

    final schemaFile = File('${targetDirectory.path}$sep$schemaFileName');
    await schemaFile.writeAsString(esDslSchemaJson, flush: true);
    written.add(schemaFile);

    for (final doc in spec.documents) {
      final file = File('${targetDirectory.path}$sep${doc.fileName}');
      await file.writeAsString(toYaml(doc), flush: true);
      written.add(file);
    }
    return written;
  }

  /// Valide un [EventStormDocument] vis-à-vis des règles structurelles du schéma
  /// `es-dsl.schema.json`, de l'intégrité référentielle et des conventions grammaticales.
  static List<EventStormDslDiagnostic> validateDocument(
    EventStormDocument doc, {
    List<EventStormDocument>? allDocuments,
  }) {
    final diagnostics = <EventStormDslDiagnostic>[];

    if (doc.dslVersion != EventStormDocument.currentDslVersion) {
      diagnostics.add(
        EventStormDslDiagnostic(
          severity: EventStormDslSeverity.error,
          code: 'DSL-ES-VERSION',
          message:
              'dsl_version "${doc.dslVersion}" invalide (attendu "${EventStormDocument.currentDslVersion}").',
          suggestion: 'Fixez `dsl_version: "1.0"`.',
        ),
      );
    }

    if (!isoDatePattern.hasMatch(doc.meta.date)) {
      diagnostics.add(
        EventStormDslDiagnostic(
          severity: EventStormDslSeverity.error,
          code: 'DSL-ES-DATE',
          message:
              'meta.date "${doc.meta.date}" ne respecte pas le format ISO YYYY-MM-DD.',
          suggestion: 'Utilisez une date au format AAAA-MM-JJ (ex. 2026-11-24).',
        ),
      );
    }

    // Contrôle des patterns ID du catalogue
    final actorIds = <String>{};
    for (final item in doc.catalog.actors) {
      actorIds.add(item.id);
      if (!item.id.startsWith('ACT-') || !catalogIdPattern.hasMatch(item.id)) {
        diagnostics.add(
          EventStormDslDiagnostic(
            severity: EventStormDslSeverity.error,
            code: 'DSL-ES-CATALOG-ID',
            message:
                'Acteur "${item.id}" non conforme au motif ^ACT-[A-Z0-9_-]+\$.',
            suggestion: 'Renommez l’identifiant en majuscules avec le préfixe ACT-.',
          ),
        );
      }
    }
    final aggregateIds = <String>{};
    for (final item in doc.catalog.aggregates) {
      aggregateIds.add(item.id);
      if (!item.id.startsWith('AGG-') || !catalogIdPattern.hasMatch(item.id)) {
        diagnostics.add(
          EventStormDslDiagnostic(
            severity: EventStormDslSeverity.error,
            code: 'DSL-ES-CATALOG-ID',
            message:
                'Agrégat "${item.id}" non conforme au motif ^AGG-[A-Z0-9_-]+\$.',
            suggestion: 'Renommez l’identifiant en majuscules avec le préfixe AGG-.',
          ),
        );
      }
    }
    final externalIds = <String>{};
    for (final item in doc.catalog.externalSystems) {
      externalIds.add(item.id);
      if (!item.id.startsWith('EXT-') || !catalogIdPattern.hasMatch(item.id)) {
        diagnostics.add(
          EventStormDslDiagnostic(
            severity: EventStormDslSeverity.error,
            code: 'DSL-ES-CATALOG-ID',
            message:
                'Système externe "${item.id}" non conforme au motif ^EXT-[A-Z0-9_-]+\$.',
            suggestion: 'Renommez l’identifiant en majuscules avec le préfixe EXT-.',
          ),
        );
      }
    }

    if (doc.flow.isEmpty) {
      diagnostics.add(
        const EventStormDslDiagnostic(
          severity: EventStormDslSeverity.error,
          code: 'DSL-ES-FLOW-EMPTY',
          message:
              'Le bloc `flow` doit contenir au moins une étape (minItems: 1).',
          suggestion:
              'Ajoutez au moins une étape avec sa commande et son événement domaine.',
        ),
      );
      return diagnostics;
    }

    final localEventIds = <String>{};
    final seenHotspotIds = <String>{};
    final externalEventIds = <String>{
      if (allDocuments != null)
        for (final other in allDocuments)
          if (other.id != doc.id)
            for (final evt in other.allDomainEvents) evt.id,
    };

    // Passe 1 : collecte des EVT-* et contrôle d'unicité/pattern
    for (final step in doc.sortedSteps) {
      for (final evt in step.emittedEvents) {
        if (!domainEventIdPattern.hasMatch(evt.id)) {
          diagnostics.add(
            EventStormDslDiagnostic(
              severity: EventStormDslSeverity.error,
              code: 'DSL-ES-EVT-ID',
              stepNumber: step.step,
              message:
                  'Étape ${step.step} : identifiant d’événement "${evt.id}" non conforme (^EVT-[0-9]+[A-Z]?\$).',
              suggestion: 'Utilisez un identifiant du type EVT-01 ou EVT-02A.',
            ),
          );
        }
        if (!localEventIds.add(evt.id)) {
          diagnostics.add(
            EventStormDslDiagnostic(
              severity: EventStormDslSeverity.error,
              code: 'DSL-ES-EVT-DUP',
              stepNumber: step.step,
              message:
                  'Étape ${step.step} : identifiant d’événement "${evt.id}" dupliqué dans ce Bounded Context.',
              suggestion: 'Attribuez un identifiant EVT-* unique à chaque événement.',
            ),
          );
        }
      }
      for (final hs in step.hotspots) {
        if (!hotspotIdPattern.hasMatch(hs.id)) {
          diagnostics.add(
            EventStormDslDiagnostic(
              severity: EventStormDslSeverity.error,
              code: 'DSL-ES-HS-ID',
              stepNumber: step.step,
              message:
                  'Étape ${step.step} : identifiant hotspot "${hs.id}" non conforme (^HS-[0-9]+\$).',
              suggestion: 'Utilisez un identifiant du type HS-01.',
            ),
          );
        }
        if (!seenHotspotIds.add(hs.id)) {
          diagnostics.add(
            EventStormDslDiagnostic(
              severity: EventStormDslSeverity.error,
              code: 'DSL-ES-HS-DUP',
              stepNumber: step.step,
              message:
                  'Étape ${step.step} : identifiant hotspot "${hs.id}" dupliqué.',
              suggestion: 'Attribuez un identifiant HS-* unique à chaque hotspot.',
            ),
          );
        }
      }
    }

    // Passe 2 : intégrité référentielle et conventions grammaticales par étape
    for (final step in doc.sortedSteps) {
      if (step.actor.isNotEmpty && !actorIds.contains(step.actor)) {
        diagnostics.add(
          EventStormDslDiagnostic(
            severity: EventStormDslSeverity.error,
            code: 'DSL-ES-REF-ACTOR',
            stepNumber: step.step,
            message:
                'Étape ${step.step} : acteur "${step.actor}" absent de `catalog.actors`.',
            suggestion:
                'Déclarez "${step.actor}" dans l’onglet Catalogue pour éviter les doublons de nommage.',
          ),
        );
      }
      if (step.aggregate.isNotEmpty && !aggregateIds.contains(step.aggregate)) {
        diagnostics.add(
          EventStormDslDiagnostic(
            severity: EventStormDslSeverity.error,
            code: 'DSL-ES-REF-AGGREGATE',
            stepNumber: step.step,
            message:
                'Étape ${step.step} : agrégat "${step.aggregate}" absent de `catalog.aggregates`.',
            suggestion:
                'Déclarez "${step.aggregate}" dans l’onglet Catalogue.',
          ),
        );
      }
      if (step.externalSystem.isNotEmpty &&
          !externalIds.contains(step.externalSystem)) {
        diagnostics.add(
          EventStormDslDiagnostic(
            severity: EventStormDslSeverity.error,
            code: 'DSL-ES-REF-EXTERNAL',
            stepNumber: step.step,
            message:
                'Étape ${step.step} : système externe "${step.externalSystem}" absent de `catalog.external_systems`.',
            suggestion:
                'Déclarez "${step.externalSystem}" dans l’onglet Catalogue.',
          ),
        );
      }

      // Vérification triggered_by
      if (step.triggeredBy != null) {
        final trig = step.triggeredBy!;
        if (trig.mode != EventStormTriggerMode.single &&
            trig.eventIds.length < 2) {
          diagnostics.add(
            EventStormDslDiagnostic(
              severity: EventStormDslSeverity.error,
              code: 'DSL-ES-TRIGGER-MIN',
              stepNumber: step.step,
              message:
                  'Étape ${step.step} : `${trig.mode.yamlKey}` requiert au moins 2 événements.',
              suggestion:
                  'Renseignez au moins 2 identifiants EVT-* ou passez en déclencheur simple.',
            ),
          );
        }
        for (final ref in trig.eventIds) {
          if (!triggerEventRefPattern.hasMatch(ref)) {
            diagnostics.add(
              EventStormDslDiagnostic(
                severity: EventStormDslSeverity.error,
                code: 'DSL-ES-TRIGGER-FORMAT',
                stepNumber: step.step,
                message:
                    'Étape ${step.step} : `triggered_by` "$ref" non conforme (attendu EVT-xx ou CTX:EVT-xx).',
                suggestion:
                    'Utilisez un identifiant EVT-01 local ou PREFIXE:EVT-02A pour un autre Bounded Context.',
              ),
            );
          } else if (ref.contains(':')) {
            // Référence inter-contexte (ex. CMD:EVT-02A)
            final eventPart = ref.split(':').last;
            if (allDocuments != null &&
                allDocuments.length > 1 &&
                !externalEventIds.contains(eventPart)) {
              diagnostics.add(
                EventStormDslDiagnostic(
                  severity: EventStormDslSeverity.warning,
                  code: 'DSL-ES-TRIGGER-CROSS-BC',
                  stepNumber: step.step,
                  message:
                      'Étape ${step.step} : événement externe "$ref" non trouvé dans les autres Bounded Contexts du projet.',
                  suggestion:
                      'Vérifiez que l’événement "$eventPart" existe bien dans le Bounded Context source.',
                ),
              );
            }
          } else if (!localEventIds.contains(ref)) {
            diagnostics.add(
              EventStormDslDiagnostic(
                severity: EventStormDslSeverity.error,
                code: 'DSL-ES-TRIGGER-MISSING',
                stepNumber: step.step,
                message:
                    'Étape ${step.step} : `triggered_by` référence l’événement local "$ref" introuvable dans ce flux.',
                suggestion:
                    'Ajoutez l’événement "$ref" dans une étape précédente ou préfixez-le (ex. CTX:$ref) s’il provient d’un autre contexte.',
              ),
            );
          }
        }
      }

      // Conventions grammaticales (avertissements non bloquants)
      if (!looksLikeInfinitiveCommand(step.command.name)) {
        diagnostics.add(
          EventStormDslDiagnostic(
            severity: EventStormDslSeverity.warning,
            code: 'GRAM-ES-CMD',
            stepNumber: step.step,
            message:
                'Étape ${step.step} : la commande « ${step.command.name} » ne semble pas débuter par un verbe à l’infinitif.',
            suggestion:
                'Formulez la commande avec un verbe à l’infinitif (ex. « Valider le panier », « Réserver le stock »).',
          ),
        );
      }

      for (final evt in step.emittedEvents) {
        if (!looksLikePastDomainEvent(evt.name)) {
          diagnostics.add(
            EventStormDslDiagnostic(
              severity: EventStormDslSeverity.warning,
              code: 'GRAM-ES-EVT',
              stepNumber: step.step,
              message:
                  'Étape ${step.step} : l’événement « ${evt.name} » (${evt.id}) ne semble pas formulé au passé composé.',
              suggestion:
                  'Formulez l’événement au passé composé (ex. « Panier validé », « Stock réservé », « Paiement refusé »).',
            ),
          );
        }
      }

      if (step.policy != null && !looksLikeWhenThenPolicy(step.policy!.rule)) {
        diagnostics.add(
          EventStormDslDiagnostic(
            severity: EventStormDslSeverity.info,
            code: 'GRAM-ES-POL',
            stepNumber: step.step,
            message:
                'Étape ${step.step} : la règle de politique « ${step.policy!.rule} » ne suit pas le modèle « Quand [événement], alors [commande] ».',
            suggestion:
                'Reformulez en « Quand <Événement>, alors <Commande> ».',
          ),
        );
      }
    }

    return diagnostics;
  }

  /// Heuristique légère vérifiant qu'une commande commence par un verbe à l'infinitif (FR / EN courant).
  static bool looksLikeInfinitiveCommand(String commandName) {
    final trimmed = commandName.trim();
    if (trimmed.isEmpty) return false;
    final firstWord = _extractFirstWord(trimmed).toLowerCase();
    if (firstWord.length < 2) return false;
    // Infinitifs français : -er, -ir, -re, -oir
    if (firstWord.endsWith('er') ||
        firstWord.endsWith('ir') ||
        firstWord.endsWith('re') ||
        firstWord.endsWith('oir') ||
        firstWord.endsWith('ïr')) {
      return true;
    }
    // Verbes d'action anglais courants en DDD
    const englishVerbs = <String>{
      'create',
      'update',
      'delete',
      'remove',
      'add',
      'set',
      'get',
      'validate',
      'verify',
      'confirm',
      'cancel',
      'reject',
      'approve',
      'submit',
      'send',
      'notify',
      'pay',
      'charge',
      'refund',
      'reserve',
      'release',
      'ship',
      'deliver',
      'close',
      'open',
      'start',
      'stop',
      'complete',
      'process',
      'request',
      'assign',
      'archive',
      'publish',
      'schedule',
      'trigger',
      'execute',
      'sync',
      'import',
      'export',
    };
    return englishVerbs.contains(firstWord);
  }

  /// Heuristique légère vérifiant qu'un événement domaine est formulé au passé composé / participe passé (FR / EN).
  static bool looksLikePastDomainEvent(String eventName) {
    final trimmed = eventName.trim();
    if (trimmed.isEmpty) return false;
    // Découpe aussi le PascalCase (ex. "CommandeValidee" -> ["Commande", "Validee"])
    final expanded = trimmed.replaceAllMapped(
      RegExp(r'([a-zà-ÿ0-9])([A-ZÀ-Ý])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    final words = expanded
        .split(RegExp(r'[^A-Za-zÀ-ÿ0-9]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.toLowerCase())
        .toList();
    if (words.isEmpty) return false;
    final last = words.last;
    // Participes passés français avec ou sans accents (ex. validé, payée, annulés, créé, reçu, transmis, fait, ouvert, clos, émis)
    if (RegExp(
      r'(é|ée|és|ées|ee|ees|i|ie|is|ies|u|ue|us|ues|it|ite|its|ites|ait|aite|aits|aites|ert|erte|erts|ertes|int|inte|ints|intes|os|ose|oses|ed)$',
    ).hasMatch(last)) {
      return true;
    }
    // Participes passés irréguliers anglais courants
    const irregularPast = <String>{
      'paid',
      'sent',
      'built',
      'made',
      'done',
      'set',
      'cut',
      'put',
      'sold',
      'held',
      'kept',
      'left',
      'lost',
      'found',
      'bound',
      'chosen',
      'taken',
      'given',
      'written',
      'broken',
      'frozen',
      'withdrawn',
      'split',
    };
    return irregularPast.contains(last);
  }

  /// Vérifie que la règle d'une politique suit la structure « Quand…, alors… » (ou « When…, then… »).
  static bool looksLikeWhenThenPolicy(String rule) {
    final lower = rule.trim().toLowerCase();
    return (lower.startsWith('quand ') && lower.contains('alors')) ||
        (lower.startsWith('when ') && lower.contains('then'));
  }

  static String _extractFirstWord(String input) {
    final expanded = input.replaceAllMapped(
      RegExp(r'([a-zà-ÿ0-9])([A-ZÀ-Ý])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    final match = RegExp(r'[A-Za-zÀ-ÿ]+').firstMatch(expanded);
    return match?.group(0) ?? '';
  }

  static String _q(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\r', '')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }

  static String _inlineStringList(List<String> items) =>
      '[${items.map(_q).join(', ')}]';

  static Object? _toPlainDart(Object? value) {
    if (value is YamlMap) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _toPlainDart(entry.value),
      };
    }
    if (value is YamlList) {
      return <Object?>[for (final item in value) _toPlainDart(item)];
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _toPlainDart(entry.value),
      };
    }
    if (value is List) {
      return <Object?>[for (final item in value) _toPlainDart(item)];
    }
    return value;
  }
}
