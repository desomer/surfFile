/// Moteur d'exécution sandboxé JavaScript QuickJS (`flutter_js`) pour
/// `super_backend_editor` : préchargement FFI Windows, contrat `ctx` complet
/// avec rejeu déterministe par journal d'étapes (`step-log replay`) au-dessus de
/// [ProvisionedBackendService], adaptateur [CollectionInvariantHook], bus
/// inspectable d'événements du domaine et générateur de squelettes QuickJS.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:super_backend/super_backend.dart';
import 'package:uuid/uuid.dart';

import '../../models/backend_domain_project.dart';
import '../../models/backend_overlay_config.dart';
import '../../models/domain_design_spec.dart';
import '../../models/json_value_utils.dart';
import '../backend_workspace_store.dart';
import 'provisioned_backend_service.dart';

const Uuid _eventUuid = Uuid();

bool _windowsQuickJsPreloaded = false;

/// Précharge de manière opportuniste `quickjs_c_bridge.dll` sur Windows afin
/// que `getJavascriptRuntime(xhr: false)` fonctionne immédiatement aussi bien
/// sous `flutter test` qu'en exécution Desktop Debug/Release.
bool preloadWindowsQuickJsBridge({
  List<String> additionalCandidates = const <String>[],
}) {
  if (!Platform.isWindows) return false;
  if (_windowsQuickJsPreloaded) return true;

  final cwd = Directory.current.path;
  final sep = Platform.pathSeparator;
  final candidates = <String>[
    ...additionalCandidates,
    'quickjs_c_bridge.dll',
    '$cwd${sep}build${sep}windows${sep}x64${sep}runner${sep}Debug${sep}quickjs_c_bridge.dll',
    '$cwd${sep}build${sep}windows${sep}x64${sep}runner${sep}Release${sep}quickjs_c_bridge.dll',
    '$cwd${sep}packages${sep}super_backend_editor${sep}build${sep}windows${sep}x64${sep}runner${sep}Debug${sep}quickjs_c_bridge.dll',
    '$cwd${sep}packages${sep}super_backend_editor${sep}build${sep}windows${sep}x64${sep}runner${sep}Release${sep}quickjs_c_bridge.dll',
    '$cwd${sep}packages${sep}super_container_layout${sep}build${sep}windows${sep}x64${sep}runner${sep}Debug${sep}quickjs_c_bridge.dll',
    '$cwd${sep}packages${sep}super_container_layout${sep}build${sep}windows${sep}x64${sep}runner${sep}Release${sep}quickjs_c_bridge.dll',
  ];

  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed != 'quickjs_c_bridge.dll' && !File(trimmed).existsSync()) {
      continue;
    }
    try {
      ffi.DynamicLibrary.open(trimmed);
      _windowsQuickJsPreloaded = true;
      return true;
    } catch (_) {
      // Essayer l'emplacement candidat suivant.
    }
  }
  return false;
}

/// Événement métier du domaine émis par un script QuickJS (`ctx.emit`) ou par
/// l'exécution déclarative d'un Use Case CQRS.
@immutable
class EmittedDomainEvent {
  /// Crée un événement métier immuable.
  EmittedDomainEvent({
    required this.id,
    required this.name,
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? emittedAt,
    this.sourceScriptPath,
    this.sourceKind,
  }) : payload = freezeJsonMap(payload),
       emittedAt = (emittedAt ?? DateTime.now().toUtc()).toUtc();

  /// Identifiant unique de l'événement émis.
  final String id;

  /// Nom canonique de l'événement métier (ex. `InvoiceIssued`).
  final String name;

  /// Charge utile JSON immuable associée à l'événement.
  final Map<String, Object?> payload;

  /// Horodatage UTC d'émission.
  final DateTime emittedAt;

  /// Chemin relatif optionnel du script QuickJS émetteur.
  final String? sourceScriptPath;

  /// Catégorie optionnelle de la source d'émission (`useCase`, `modelInvariant`, `saga`, etc.).
  final String? sourceKind;

  /// Vérifie les invariants de l'événement émis.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('EmittedDomainEvent.id requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('EmittedDomainEvent.name requis.');
    }
  }

  /// Retourne une copie modifiée de l'événement.
  EmittedDomainEvent copyWith({
    String? id,
    String? name,
    Map<String, Object?>? payload,
    DateTime? emittedAt,
    String? sourceScriptPath,
    bool clearSourceScriptPath = false,
    String? sourceKind,
    bool clearSourceKind = false,
  }) => EmittedDomainEvent(
    id: id ?? this.id,
    name: name ?? this.name,
    payload: payload ?? this.payload,
    emittedAt: emittedAt ?? this.emittedAt,
    sourceScriptPath: clearSourceScriptPath
        ? null
        : (sourceScriptPath ?? this.sourceScriptPath),
    sourceKind: clearSourceKind ? null : (sourceKind ?? this.sourceKind),
  );

  /// Sérialise l'événement métier en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'payload': payload,
    'emittedAt': emittedAt.toUtc().toIso8601String(),
    if (sourceScriptPath != null && sourceScriptPath!.trim().isNotEmpty)
      'sourceScriptPath': sourceScriptPath,
    if (sourceKind != null && sourceKind!.trim().isNotEmpty)
      'sourceKind': sourceKind,
  };

  /// Désérialise un événement métier depuis JSON.
  factory EmittedDomainEvent.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('EmittedDomainEvent invalide.');
    }
    final rawPath = (raw['sourceScriptPath'] as String?)?.trim();
    final rawKind = (raw['sourceKind'] as String?)?.trim();
    final item = EmittedDomainEvent(
      id: (raw['id'] as String?)?.trim() ?? _eventUuid.v4(),
      name: (raw['name'] as String?)?.trim() ?? '',
      payload: raw['payload'] is Map
          ? freezeJsonMap(raw['payload'] as Map)
          : const <String, Object?>{},
      emittedAt: parseUtcDateTimeOrEpoch(raw['emittedAt']),
      sourceScriptPath: (rawPath == null || rawPath.isEmpty) ? null : rawPath,
      sourceKind: (rawKind == null || rawKind.isEmpty) ? null : rawKind,
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmittedDomainEvent &&
          other.id == id &&
          other.name == name &&
          deepJsonEquals(other.payload, payload) &&
          other.emittedAt == emittedAt &&
          other.sourceScriptPath == sourceScriptPath &&
          other.sourceKind == sourceKind;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    deepJsonHash(payload),
    emittedAt,
    sourceScriptPath,
    sourceKind,
  );
}

/// Exception métier levée lorsqu'une assertion `ctx.assert(cond, message)`
/// échoue dans un script QuickJS (traduite en HTTP `422 Unprocessable Entity`).
class BackendScriptAssertionException extends SuperBackendException {
  /// Crée une exception de violation d'invariant métier.
  const BackendScriptAssertionException(
    String message, {
    this.scriptPath,
    super.cause,
  }) : super(
         code: 'domain_invariant_violated',
         message: message,
         statusCode: 422,
       );

  /// Chemin relatif optionnel du script ayant levé l'assertion.
  final String? scriptPath;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'statusCode': statusCode,
    if (scriptPath != null && scriptPath!.trim().isNotEmpty)
      'scriptPath': scriptPath,
  };
}

/// Exception technique levée lorsqu'un script QuickJS échoue par erreur de
/// syntaxe, exception d'exécution ou dépassement du quota d'étapes SCRUD.
class BackendScriptExecutionException extends SuperBackendException {
  /// Crée une exception d'erreur d'exécution QuickJS.
  const BackendScriptExecutionException(
    String message, {
    this.scriptPath,
    super.cause,
  }) : super(
         code: 'script_execution_error',
         message: message,
         statusCode: 500,
       );

  /// Chemin relatif optionnel du script en échec.
  final String? scriptPath;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'statusCode': statusCode,
    if (scriptPath != null && scriptPath!.trim().isNotEmpty)
      'scriptPath': scriptPath,
  };
}

/// Contexte immuable transmis à l'objet global `ctx` lors de l'exécution d'un
/// script QuickJS.
@immutable
class BackendScriptExecutionContext {
  /// Crée un contexte d'exécution QuickJS immuable.
  BackendScriptExecutionContext({
    Object? input = const <String, Object?>{},
    Map<String, String> params = const <String, String>{},
    Map<String, String> query = const <String, String>{},
    Map<String, String> environmentVariables = const <String, String>{},
    this.operation,
    this.scriptPath,
    this.sourceKind,
  }) : input = freezeJsonValue(input ?? const <String, Object?>{}),
       params = Map<String, String>.unmodifiable(Map<String, String>.of(params)),
       query = Map<String, String>.unmodifiable(Map<String, String>.of(query)),
       environmentVariables = Map<String, String>.unmodifiable(
         Map<String, String>.of(environmentVariables),
       );

  /// Charge utile JSON d'entrée exposée sous `ctx.input`.
  final Object? input;

  /// Paramètres extraits du chemin d'URL exposés sous `ctx.params`.
  final Map<String, String> params;

  /// Paramètres de chaîne de requête exposés sous `ctx.query`.
  final Map<String, String> query;

  /// Variables d'environnement et secrets locaux résolus pour `ctx.env(key)`.
  final Map<String, String> environmentVariables;

  /// Nom de l'opération courante exposé sous `ctx.operation` (`create`, `update`, `command`, `query`, etc.).
  final String? operation;

  /// Chemin relatif optionnel du script exécuté.
  final String? scriptPath;

  /// Catégorie optionnelle d'artefact exécuté (`modelInvariant`, `useCase`, `saga`, etc.).
  final String? sourceKind;

  /// Retourne une copie modifiée du contexte.
  BackendScriptExecutionContext copyWith({
    Object? input,
    bool replaceInput = false,
    Map<String, String>? params,
    Map<String, String>? query,
    Map<String, String>? environmentVariables,
    String? operation,
    String? scriptPath,
    String? sourceKind,
  }) => BackendScriptExecutionContext(
    input: replaceInput ? input : (input ?? this.input),
    params: params ?? this.params,
    query: query ?? this.query,
    environmentVariables: environmentVariables ?? this.environmentVariables,
    operation: operation ?? this.operation,
    scriptPath: scriptPath ?? this.scriptPath,
    sourceKind: sourceKind ?? this.sourceKind,
  );

  /// Sérialise le contexte (hors valeurs d'environnement sensibles si non souhaitées).
  Map<String, Object?> toJson() => <String, Object?>{
    'input': input,
    'params': params,
    'query': query,
    if (operation != null) 'operation': operation,
    if (scriptPath != null) 'scriptPath': scriptPath,
    if (sourceKind != null) 'sourceKind': sourceKind,
  };
}

/// Résultat complet et immuable de l'exécution d'un script QuickJS.
@immutable
class BackendScriptExecutionResult {
  /// Crée un résultat d'exécution QuickJS immuable.
  BackendScriptExecutionResult({
    required Object? output,
    List<EmittedDomainEvent> emittedEvents = const <EmittedDomainEvent>[],
    List<String> consoleLogs = const <String>[],
    required this.durationMs,
  }) : output = freezeJsonValue(output),
       emittedEvents = List<EmittedDomainEvent>.unmodifiable(emittedEvents),
       consoleLogs = List<String>.unmodifiable(consoleLogs);

  /// Valeur de retour JSON produite par le script (`null` si `undefined`).
  final Object? output;

  /// Événements du domaine émis via `ctx.emit(...)` lors de la passe finale.
  final List<EmittedDomainEvent> emittedEvents;

  /// Journaux produits via `ctx.log(...)` ou `console.log(...)` lors de la passe finale.
  final List<String> consoleLogs;

  /// Durée totale d'exécution en millisecondes (incluant les étapes SCRUD).
  final int durationMs;

  /// Sérialise le résultat d'exécution en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'output': output,
    'emittedEvents': <Map<String, Object?>>[
      for (final e in emittedEvents) e.toJson(),
    ],
    'consoleLogs': consoleLogs,
    'durationMs': durationMs,
  };
}

/// Interface d'évaluation de scripts métier permettant d'injecter un évaluateur
/// alternatif ou simulé dans les tests unitaires sans FFI.
abstract interface class BackendScriptEvaluator {
  /// Évalue [jsSource] dans [context] en résolvant les accès `ctx.collection(...)`
  /// contre [backendService].
  Future<BackendScriptExecutionResult> evaluate({
    required String jsSource,
    required BackendScriptExecutionContext context,
    required ProvisionedBackendService backendService,
  });

  /// Libère les ressources natives éventuelles de l'évaluateur.
  void dispose();
}

/// Implémentation QuickJS native (`flutter_js`) de [BackendScriptEvaluator]
/// orchestrant le rejeu déterministe par journal d'étapes (`step-log replay`).
class QuickJsBackendScriptEvaluator implements BackendScriptEvaluator {
  /// Crée un évaluateur QuickJS avec plafond d'étapes [maxSteps].
  QuickJsBackendScriptEvaluator({
    JavascriptRuntime Function()? runtimeFactory,
    this.maxSteps = defaultMaxSteps,
  }) : _runtimeFactory = runtimeFactory ?? _defaultRuntimeFactory;

  /// Plafond par défaut d'appels `ctx.collection(...)` par exécution de script.
  static const int defaultMaxSteps = 250;

  static const int _maxCachedScripts = 256;

  static JavascriptRuntime _defaultRuntimeFactory() {
    preloadWindowsQuickJsBridge();
    return getJavascriptRuntime(xhr: false);
  }

  final JavascriptRuntime Function() _runtimeFactory;

  /// Nombre maximal d'opérations `ctx.collection(...)` autorisées par exécution.
  final int maxSteps;

  JavascriptRuntime? _runtime;
  bool _bootstrapped = false;
  bool _disposed = false;

  static const String _bootstrapScript = r'''
(function() {
  if (globalThis.__sbeQuickJsReady) return true;

  const __fnCache = Object.create(null);
  let __fnCacheCount = 0;

  function __cloneJson(val) {
    if (val === undefined || val === null) return val;
    if (typeof val !== 'object') return val;
    return JSON.parse(JSON.stringify(val));
  }

  function __formatLogArg(arg) {
    if (typeof arg === 'string') return arg;
    if (arg === undefined) return 'undefined';
    if (arg === null) return 'null';
    if (arg instanceof Error) return arg.message || String(arg);
    try {
      return JSON.stringify(arg);
    } catch (_) {
      return String(arg);
    }
  }

  function __normalizeScriptSource(rawCode) {
    let src = String(rawCode ?? '');
    src = src.replace(
      /(^|\n)(\s*)export\s+default\s+/g,
      '$1$2const __sbeDefaultExport = '
    );
    src = src.replace(
      /(^|\n)(\s*)export\s+function\s+handle\b/g,
      '$1$2function handle'
    );
    return (
      '"use strict";\n' +
      src +
      '\n;\n' +
      'if (typeof __sbeDefaultExport === "function") {\n' +
      '  return __sbeDefaultExport(ctx);\n' +
      '}\n' +
      'if (typeof __sbeDefaultExport !== "undefined") {\n' +
      '  return __sbeDefaultExport;\n' +
      '}\n' +
      'if (typeof handle === "function") {\n' +
      '  return handle(ctx);\n' +
      '}\n'
    );
  }

  function __compileScript(rawCode) {
    const key = String(rawCode ?? '');
    let compiled = __fnCache[key];
    if (compiled) return compiled;
    if (__fnCacheCount >= 256) {
      for (const k in __fnCache) {
        delete __fnCache[k];
      }
      __fnCacheCount = 0;
    }
    const body = __normalizeScriptSource(key);
    compiled = new Function('ctx', body);
    __fnCache[key] = compiled;
    __fnCacheCount++;
    return compiled;
  }

  globalThis.__sbeClearCache = function() {
    for (const k in __fnCache) {
      delete __fnCache[k];
    }
    __fnCacheCount = 0;
    return true;
  };

  globalThis.__sbeRunPass = function(rawPayloadJson) {
    const payload = JSON.parse(rawPayloadJson);
    const resolvedSteps = Array.isArray(payload.resolvedSteps)
      ? payload.resolvedSteps
      : [];
    const envMap = (payload.env && typeof payload.env === 'object')
      ? payload.env
      : Object.create(null);
    const paramsObj = (payload.params && typeof payload.params === 'object')
      ? __cloneJson(payload.params)
      : {};
    const queryObj = (payload.query && typeof payload.query === 'object')
      ? __cloneJson(payload.query)
      : {};
    const inputVal = (payload.input === undefined || payload.input === null)
      ? {}
      : __cloneJson(payload.input);
    const operationVal = typeof payload.operation === 'string'
      ? payload.operation
      : '';

    let stepIndex = 0;
    const emittedEvents = [];
    const consoleLogs = [];

    const appendLog = function() {
      const parts = [];
      for (let i = 0; i < arguments.length; i++) {
        parts.push(__formatLogArg(arguments[i]));
      }
      consoleLogs.push(parts.join(' '));
    };

    function invokeCollectionStep(collectionName, opName, argsList) {
      if (typeof collectionName !== 'string' || collectionName.trim() === '') {
        throw new Error('ctx.collection(name) requiert un nom de collection non vide.');
      }
      const cleanName = collectionName.trim();
      const idx = stepIndex++;
      if (idx < resolvedSteps.length) {
        const entry = resolvedSteps[idx];
        if (entry && entry.error) {
          const err = new Error(String(entry.error.message || 'Erreur collection.'));
          err.code = String(entry.error.code || 'collection_error');
          err.statusCode = Number(entry.error.statusCode || 500);
          err.__sbeStepErrorIndex = idx;
          throw err;
        }
        return entry ? __cloneJson(entry.value) : null;
      }
      throw {
        __sbeDeferred: true,
        collection: cleanName,
        op: opName,
        args: __cloneJson(argsList),
      };
    }

    const ctx = {
      input: inputVal,
      params: Object.freeze(paramsObj),
      query: Object.freeze(queryObj),
      operation: operationVal,
      env(key) {
        if (typeof key !== 'string' || key.length === 0) return null;
        return Object.prototype.hasOwnProperty.call(envMap, key)
          ? String(envMap[key])
          : null;
      },
      log: appendLog,
      assert(cond, message) {
        if (!cond) {
          const msg = (typeof message === 'string' && message.trim() !== '')
            ? message.trim()
            : 'Invariant métier violé.';
          throw {
            __sbeAssertion: true,
            code: 'domain_invariant_violated',
            message: msg,
          };
        }
      },
      emit(eventName, eventPayload) {
        if (typeof eventName !== 'string' || eventName.trim() === '') {
          throw new Error('ctx.emit(eventName, payload) requiert un nom d’événement non vide.');
        }
        let normalized = {};
        if (eventPayload !== undefined && eventPayload !== null) {
          if (typeof eventPayload === 'object' && !Array.isArray(eventPayload)) {
            normalized = __cloneJson(eventPayload);
          } else {
            normalized = { value: __cloneJson(eventPayload) };
          }
        }
        emittedEvents.push({
          name: eventName.trim(),
          payload: normalized,
        });
      },
      collection(name) {
        return {
          search(params) {
            const safeParams = (params === undefined || params === null) ? {} : params;
            return invokeCollectionStep(name, 'search', [safeParams]);
          },
          read(id) {
            return invokeCollectionStep(name, 'read', [String(id ?? '')]);
          },
          create(data) {
            return invokeCollectionStep(name, 'create', [data ?? {}]);
          },
          update(id, patch) {
            return invokeCollectionStep(name, 'update', [String(id ?? ''), patch ?? {}]);
          },
          delete(id) {
            return invokeCollectionStep(name, 'delete', [String(id ?? '')]);
          },
        };
      },
    };

    const previousConsole = globalThis.console;
    globalThis.console = {
      log: appendLog,
      info: appendLog,
      warn: appendLog,
      error: appendLog,
      debug: appendLog,
    };

    try {
      const fn = __compileScript(payload.code);
      const rawOut = fn(ctx);
      const safeOut = rawOut === undefined ? null : __cloneJson(rawOut);
      return JSON.stringify({
        status: 'ok',
        output: safeOut,
        emittedEvents: emittedEvents,
        consoleLogs: consoleLogs,
      });
    } catch (err) {
      if (err && err.__sbeDeferred === true) {
        return JSON.stringify({
          status: 'deferred',
          collection: err.collection,
          op: err.op,
          args: err.args,
        });
      }
      if (err && err.__sbeAssertion === true) {
        return JSON.stringify({
          status: 'assertion_failed',
          message: String(err.message || 'Invariant métier violé.'),
          consoleLogs: consoleLogs,
        });
      }
      if (err && typeof err.__sbeStepErrorIndex === 'number') {
        return JSON.stringify({
          status: 'step_error',
          stepIndex: err.__sbeStepErrorIndex,
          consoleLogs: consoleLogs,
        });
      }
      const name = (err && err.name) ? String(err.name) : 'Error';
      const msg = (err && err.message) ? String(err.message) : String(err);
      return JSON.stringify({
        status: 'error',
        error: name + ': ' + msg,
        consoleLogs: consoleLogs,
      });
    } finally {
      globalThis.console = previousConsole;
    }
  };

  globalThis.__sbeQuickJsReady = true;
  return true;
})();
''';

  JavascriptRuntime _ensureRuntime() {
    if (_disposed) {
      throw const BackendScriptExecutionException(
        'Le moteur QuickJS a déjà été fermé.',
      );
    }
    var runtime = _runtime;
    if (runtime == null) {
      try {
        runtime = _runtimeFactory();
      } on Object catch (error) {
        throw BackendScriptExecutionException(
          'Impossible d’initialiser le runtime QuickJS : $error',
          cause: error,
        );
      }
      _runtime = runtime;
      _bootstrapped = false;
    }
    if (!_bootstrapped) {
      final initResult = runtime.evaluate(_bootstrapScript);
      if (initResult.isError) {
        throw BackendScriptExecutionException(
          'Échec d’initialisation du bootstrap QuickJS : ${initResult.stringResult}',
        );
      }
      _bootstrapped = true;
    }
    return runtime;
  }

  @override
  Future<BackendScriptExecutionResult> evaluate({
    required String jsSource,
    required BackendScriptExecutionContext context,
    required ProvisionedBackendService backendService,
  }) async {
    final stopwatch = Stopwatch()..start();
    final runtime = _ensureRuntime();
    final resolvedSteps = <Map<String, Object?>>[];
    final stepExceptions = <int, Object>{};

    while (true) {
      if (_disposed) {
        throw BackendScriptExecutionException(
          'Le moteur QuickJS a été fermé en cours d’exécution.',
          scriptPath: context.scriptPath,
        );
      }
      if (resolvedSteps.length > maxSteps) {
        throw BackendScriptExecutionException(
          'Dépassement du nombre maximal d’appels ctx.collection ($maxSteps).',
          scriptPath: context.scriptPath,
        );
      }

      final payloadJson = jsonEncode(<String, Object?>{
        'code': jsSource,
        'input': context.input,
        'params': context.params,
        'query': context.query,
        'env': context.environmentVariables,
        'operation': context.operation ?? '',
        'resolvedSteps': resolvedSteps,
      });

      final evalResult = runtime.evaluate(
        'globalThis.__sbeRunPass(${jsonEncode(payloadJson)})',
      );
      if (evalResult.isError) {
        throw BackendScriptExecutionException(
          'Erreur d’évaluation QuickJS : ${evalResult.stringResult}',
          scriptPath: context.scriptPath,
        );
      }

      final rawText = evalResult.rawResult is String
          ? evalResult.rawResult as String
          : evalResult.stringResult;
      final Object? decoded;
      try {
        decoded = jsonDecode(rawText);
      } on FormatException catch (error) {
        throw BackendScriptExecutionException(
          'Réponse JSON interne QuickJS invalide : $rawText',
          scriptPath: context.scriptPath,
          cause: error,
        );
      }
      if (decoded is! Map<String, Object?>) {
        throw BackendScriptExecutionException(
          'Enveloppe interne QuickJS invalide.',
          scriptPath: context.scriptPath,
        );
      }

      final status = decoded['status'] as String? ?? 'error';
      switch (status) {
        case 'ok':
          stopwatch.stop();
          final nowUtc = DateTime.now().toUtc();
          final events = <EmittedDomainEvent>[];
          if (decoded['emittedEvents'] case final List rawEvents) {
            for (final item in rawEvents) {
              if (item is! Map) continue;
              final name = (item['name'] as String?)?.trim() ?? '';
              if (name.isEmpty) continue;
              events.add(
                EmittedDomainEvent(
                  id: _eventUuid.v4(),
                  name: name,
                  payload: item['payload'] is Map
                      ? freezeJsonMap(item['payload'] as Map)
                      : const <String, Object?>{},
                  emittedAt: nowUtc,
                  sourceScriptPath: context.scriptPath,
                  sourceKind: context.sourceKind ?? context.operation,
                ),
              );
            }
          }
          final logs = <String>[
            if (decoded['consoleLogs'] case final List rawLogs)
              for (final log in rawLogs) '$log',
          ];
          return BackendScriptExecutionResult(
            output: decoded['output'],
            emittedEvents: events,
            consoleLogs: logs,
            durationMs: stopwatch.elapsedMilliseconds,
          );

        case 'assertion_failed':
          throw BackendScriptAssertionException(
            (decoded['message'] as String?)?.trim().isNotEmpty == true
                ? (decoded['message'] as String).trim()
                : 'Invariant métier violé.',
            scriptPath: context.scriptPath,
          );

        case 'step_error':
          final stepIdx = (decoded['stepIndex'] as num?)?.toInt() ?? -1;
          final original = stepExceptions[stepIdx];
          if (original is SuperBackendException) {
            throw original;
          }
          if (original != null) {
            throw BackendScriptExecutionException(
              original.toString(),
              scriptPath: context.scriptPath,
              cause: original,
            );
          }
          throw BackendScriptExecutionException(
            'Erreur d’étape collection non résolue (#$stepIdx).',
            scriptPath: context.scriptPath,
          );

        case 'error':
          throw BackendScriptExecutionException(
            decoded['error']?.toString() ?? 'Erreur JavaScript inconnue.',
            scriptPath: context.scriptPath,
          );

        case 'deferred':
          final collection = (decoded['collection'] as String?)?.trim() ?? '';
          final op = (decoded['op'] as String?)?.trim() ?? '';
          final args = decoded['args'] is List
              ? decoded['args'] as List
              : const <Object?>[];
          final currentIdx = resolvedSteps.length;
          if (currentIdx >= maxSteps) {
            throw BackendScriptExecutionException(
              'Dépassement du nombre maximal d’appels ctx.collection ($maxSteps).',
              scriptPath: context.scriptPath,
            );
          }
          try {
            final stepVal = await _executeCollectionStep(
              backendService: backendService,
              collection: collection,
              op: op,
              args: args,
            );
            resolvedSteps.add(<String, Object?>{'value': stepVal});
          } on SuperBackendException catch (error) {
            stepExceptions[currentIdx] = error;
            resolvedSteps.add(<String, Object?>{
              'error': <String, Object?>{
                'code': error.code,
                'message': error.message,
                'statusCode': error.statusCode,
              },
            });
          } on Object catch (error) {
            stepExceptions[currentIdx] = error;
            resolvedSteps.add(<String, Object?>{
              'error': <String, Object?>{
                'code': 'collection_step_error',
                'message': error.toString(),
                'statusCode': 500,
              },
            });
          }

        default:
          throw BackendScriptExecutionException(
            'Statut QuickJS inattendu : $status',
            scriptPath: context.scriptPath,
          );
      }

      if (resolvedSteps.length > _maxCachedScripts && _runtime != null) {
        // Garde de sécurité sur le cache de fonctions compilées.
      }
    }
  }

  static Future<Object?> _executeCollectionStep({
    required ProvisionedBackendService backendService,
    required String collection,
    required String op,
    required List<dynamic> args,
  }) async {
    switch (op) {
      case 'search':
        final rawParams = args.isNotEmpty ? args.first : null;
        Map<String, Object?>? paramsMap;
        if (rawParams is Map && rawParams.isNotEmpty) {
          paramsMap = <String, Object?>{
            for (final e in rawParams.entries) '${e.key}': e.value,
          };
        }
        final includeSoftDeleted = paramsMap?.remove('includeSoftDeleted') == true;
        final page = await backendService.search(
          collection,
          parameters: (paramsMap == null || paramsMap.isEmpty)
              ? null
              : paramsMap,
          includeSoftDeleted: includeSoftDeleted,
        );
        return page.toJson();

      case 'read':
        final id = args.isNotEmpty ? '${args.first ?? ''}'.trim() : '';
        if (id.isEmpty) return null;
        try {
          return await backendService.read(collection, id);
        } on EntityNotFoundException {
          return null;
        }

      case 'create':
        final rawData = args.isNotEmpty ? args.first : null;
        if (rawData is! Map) {
          throw const InvalidJsonPayloadException(
            'ctx.collection(name).create(data) attend un objet JSON.',
          );
        }
        final dataMap = <String, Object?>{
          for (final e in rawData.entries) '${e.key}': e.value,
        };
        return backendService.create(collection, dataMap);

      case 'update':
        final id = args.isNotEmpty ? '${args.first ?? ''}'.trim() : '';
        final rawPatch = args.length > 1 ? args[1] : null;
        if (rawPatch is! Map) {
          throw const InvalidJsonPayloadException(
            'ctx.collection(name).update(id, patch) attend un objet JSON.',
          );
        }
        final patchMap = <String, Object?>{
          for (final e in rawPatch.entries) '${e.key}': e.value,
        };
        return backendService.update(collection, id, patchMap, merge: true);

      case 'delete':
        final id = args.isNotEmpty ? '${args.first ?? ''}'.trim() : '';
        if (id.isEmpty) return false;
        try {
          return await backendService.delete(collection, id);
        } on EntityNotFoundException {
          return false;
        }

      default:
        throw InvalidQueryException(
          'Opération ctx.collection inconnue : « $op ».',
        );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bootstrapped = false;
    final runtime = _runtime;
    _runtime = null;
    runtime?.dispose();
  }
}

/// Orchestrateur haut niveau d'exécution QuickJS rattaché à un domaine :
/// résolution des variables d'environnement et secrets locaux, chargement des
/// scripts depuis le disque ([BackendWorkspaceStore]) ou la mémoire, hook
/// d'invariants pour [ProvisionedBackendService] et bus inspectable d'événements.
class BackendQuickJsEngine extends ChangeNotifier {
  /// Crée un moteur d'orchestration QuickJS pour [backendService].
  BackendQuickJsEngine({
    required this.backendService,
    this.workspaceStore,
    BackendDomainProject? project,
    Map<String, Map<String, String>> localSecretValues =
        const <String, Map<String, String>>{},
    Map<String, String> inMemoryScripts = const <String, String>{},
    BackendScriptEvaluator? evaluator,
    this.maxEventLogEntries = 500,
    this.onChanged,
  }) : _project = project,
       _localSecretValues = freezeNestedStringMap(localSecretValues),
       _ownsEvaluator = evaluator == null,
       _evaluator = evaluator ?? QuickJsBackendScriptEvaluator() {
    for (final entry in inMemoryScripts.entries) {
      _inMemoryScripts[_normalizePathKey(entry.key)] = entry.value;
    }
  }

  /// Service SCRUD provisionné sous-jacent.
  final ProvisionedBackendService backendService;

  /// Magasin disque optionnel permettant de charger les fichiers sous `scripts/`.
  final BackendWorkspaceStore? workspaceStore;

  /// Nombre maximal d'événements métier conservés dans [eventLog].
  final int maxEventLogEntries;

  /// Callback optionnel invoqué à chaque mise à jour du journal d'événements.
  final VoidCallback? onChanged;

  final BackendScriptEvaluator _evaluator;
  final bool _ownsEvaluator;
  final Map<String, String> _inMemoryScripts = <String, String>{};
  final List<EmittedDomainEvent> _eventLog = <EmittedDomainEvent>[];
  final StreamController<EmittedDomainEvent> _eventStreamController =
      StreamController<EmittedDomainEvent>.broadcast();

  BackendDomainProject? _project;
  Map<String, Map<String, String>> _localSecretValues;

  /// Projet de domaine associé, s'il a été fourni.
  BackendDomainProject? get project => _project;

  /// Évaluateur de scripts sous-jacent.
  BackendScriptEvaluator get evaluator => _evaluator;

  /// Journal borné des événements du domaine émis (ordre chronologique).
  List<EmittedDomainEvent> get eventLog =>
      List<EmittedDomainEvent>.unmodifiable(_eventLog);

  /// Flux temps réel des événements du domaine émis.
  Stream<EmittedDomainEvent> get eventStream => _eventStreamController.stream;

  /// Met à jour le [BackendDomainProject] ou les valeurs secrètes locales
  /// utilisées lors de la résolution de `ctx.env(key)`.
  void updateProject(
    BackendDomainProject? project, {
    Map<String, Map<String, String>>? localSecretValues,
  }) {
    _project = project;
    if (localSecretValues != null) {
      _localSecretValues = freezeNestedStringMap(localSecretValues);
    }
  }

  /// Enregistre ou remplace un script QuickJS en mémoire (prioritaire sur le disque).
  void setInMemoryScript(String relativeScriptPath, String jsSource) {
    _inMemoryScripts[_normalizePathKey(relativeScriptPath)] = jsSource;
  }

  /// Supprime un script QuickJS précédemment enregistré en mémoire.
  bool removeInMemoryScript(String relativeScriptPath) =>
      _inMemoryScripts.remove(_normalizePathKey(relativeScriptPath)) != null;

  /// Vide l'ensemble des scripts QuickJS enregistrés en mémoire.
  void clearInMemoryScripts() => _inMemoryScripts.clear();

  /// Lit le code source d'un script QuickJS par son chemin relatif sous `scripts/`
  /// (mémoire d'abord, puis [workspaceStore]).
  Future<String?> readScriptSource(String relativeScriptPath) async {
    final normalized = _normalizePathKey(relativeScriptPath);
    if (normalized.isEmpty) return null;
    final inMem = _inMemoryScripts[normalized];
    if (inMem != null) return inMem;
    final store = workspaceStore;
    if (store == null) return null;
    final domainCode =
        _project?.domainCode ?? backendService.overlay.domainCode;
    if (domainCode.trim().isEmpty) return null;
    return store.readScript(domainCode, normalized);
  }

  /// Résout les variables d'environnement fusionnées pour [environmentId] (ou
  /// l'environnement actif) : `plainValue` de `designSpec.configurations`,
  /// surchargé par `overlay.environmentVariableOverrides[envId]`, puis par
  /// `project.localSecretValues[envId]`.
  Map<String, String> resolveEnvironmentVariables([String? environmentId]) {
    final spec = _project?.designSpec ?? backendService.designSpec;
    final overlay = _project?.overlay ?? backendService.overlay;
    final targetEnvId =
        environmentId ??
        overlay.activeEnvironmentId ??
        spec.environments.where((e) => e.status == 'active').firstOrNull?.id ??
        spec.environments.firstOrNull?.id;
    if (targetEnvId == null || targetEnvId.isEmpty) {
      return const <String, String>{};
    }

    final resolved = <String, String>{};
    for (final cfg in spec.configurations) {
      if (cfg.environmentId != targetEnvId) continue;
      if (!cfg.isSecret && cfg.plainValue != null) {
        resolved[cfg.configKey] = cfg.plainValue!;
      }
    }
    final plainOverrides = overlay.environmentVariableOverrides[targetEnvId];
    if (plainOverrides != null) {
      resolved.addAll(plainOverrides);
    }
    final projectSecrets = _project?.localSecretValues[targetEnvId];
    if (projectSecrets != null) {
      resolved.addAll(projectSecrets);
    }
    final explicitSecrets = _localSecretValues[targetEnvId];
    if (explicitSecrets != null) {
      resolved.addAll(explicitSecrets);
    }
    return Map<String, String>.unmodifiable(resolved);
  }

  /// Enregistre manuellement un lot d'événements métier dans [eventLog] et
  /// notifie les écouteurs.
  void recordDomainEvents(Iterable<EmittedDomainEvent> events) {
    var added = false;
    for (final event in events) {
      _eventLog.add(event);
      if (maxEventLogEntries > 0 && _eventLog.length > maxEventLogEntries) {
        _eventLog.removeRange(0, _eventLog.length - maxEventLogEntries);
      }
      if (!_eventStreamController.isClosed) {
        _eventStreamController.add(event);
      }
      added = true;
    }
    if (added) {
      notifyListeners();
      onChanged?.call();
    }
  }

  /// Efface tous les événements enregistrés dans [eventLog].
  void clearEventLog() {
    if (_eventLog.isEmpty) return;
    _eventLog.clear();
    notifyListeners();
    onChanged?.call();
  }

  /// Exécute [jsSource] dans le sandbox QuickJS en injectant automatiquement
  /// les variables d'environnement fusionnées et en publiant les événements émis.
  Future<BackendScriptExecutionResult> executeScript(
    String jsSource, {
    BackendScriptExecutionContext? context,
    String? environmentId,
    bool recordEvents = true,
  }) async {
    final baseEnv = resolveEnvironmentVariables(environmentId);
    final mergedEnv = <String, String>{
      ...baseEnv,
      if (context != null) ...context.environmentVariables,
    };
    final effectiveContext = (context ?? BackendScriptExecutionContext())
        .copyWith(environmentVariables: mergedEnv);

    final result = await _evaluator.evaluate(
      jsSource: jsSource,
      context: effectiveContext,
      backendService: backendService,
    );

    if (recordEvents && result.emittedEvents.isNotEmpty) {
      recordDomainEvents(result.emittedEvents);
    }
    return result;
  }

  /// Charge et exécute le script situé à [relativeScriptPath] (retourne `null`
  /// si le fichier est absent et que [throwIfMissing] vaut `false`).
  Future<BackendScriptExecutionResult?> executeScriptAtPath(
    String relativeScriptPath, {
    BackendScriptExecutionContext? context,
    String? environmentId,
    bool recordEvents = true,
    bool throwIfMissing = false,
  }) async {
    final normalized = _normalizePathKey(relativeScriptPath);
    final source = await readScriptSource(normalized);
    if (source == null) {
      if (throwIfMissing) {
        throw BackendScriptExecutionException(
          'Script QuickJS introuvable : « $normalized ».',
          scriptPath: normalized,
        );
      }
      return null;
    }
    final nextContext = (context ?? BackendScriptExecutionContext()).copyWith(
      scriptPath: context?.scriptPath ?? normalized,
    );
    return executeScript(
      source,
      context: nextContext,
      environmentId: environmentId,
      recordEvents: recordEvents,
    );
  }

  /// Crée un [CollectionInvariantHook] injectable dans [ProvisionedBackendService]
  /// exécutant tout script d'invariant rattaché à la collection ou à son modèle.
  CollectionInvariantHook createInvariantHook({String? environmentId}) => ({
    required BackendCollectionConfig collection,
    required ImportedContractEntry? contract,
    required Map<String, Object?> entity,
    required String operation,
  }) async {
    final candidatePaths = <String>[];
    void addPath(String? rawPath) {
      if (rawPath == null) return;
      final clean = _normalizePathKey(rawPath);
      if (clean.isNotEmpty && !candidatePaths.contains(clean)) {
        candidatePaths.add(clean);
      }
    }

    addPath(collection.invariantScriptPath);

    final targetIds = <String>{
      collection.id,
      collection.collectionName,
      if (collection.contractEntryId != null &&
          collection.contractEntryId!.trim().isNotEmpty)
        collection.contractEntryId!.trim(),
      if (contract != null) contract.entryId,
    };

    for (final binding in backendService.overlay.scripts) {
      if (!binding.enabled) continue;
      if (binding.targetKind != BackendScriptTargetKind.modelInvariant) {
        continue;
      }
      if (targetIds.contains(binding.targetId)) {
        addPath(binding.scriptPath);
      }
    }

    for (final scriptPath in candidatePaths) {
      await executeScriptAtPath(
        scriptPath,
        environmentId: environmentId,
        context: BackendScriptExecutionContext(
          input: entity,
          operation: operation,
          scriptPath: scriptPath,
          sourceKind: BackendScriptTargetKind.modelInvariant.name,
        ),
      );
    }
  };

  static String _normalizePathKey(String rawPath) => rawPath
      .trim()
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^/+'), '');

  @override
  void dispose() {
    if (_ownsEvaluator) {
      _evaluator.dispose();
    }
    _eventStreamController.close();
    super.dispose();
  }
}

/// Générateur déterministe de squelettes JavaScript QuickJS prêts à l'emploi
/// pour les invariants de modèles, commandes d'agrégats, Use Cases CQRS et Sagas.
abstract final class BackendQuickJsTemplates {
  /// Génère un script d'invariant QuickJS pré-rempli à partir des invariants
  /// déclarés dans la couche Domain de [model].
  static String starterForModelInvariant(ImportedContractEntry model) {
    final buf = StringBuffer()
      ..writeln(
        '// Invariants métier du modèle ${model.technicalName} (${model.effectiveLabel} v${model.version})',
      )
      ..writeln(
        '// Opération courante : ctx.operation ("create" | "update"), entité : ctx.input',
      )
      ..writeln('export default function handle(ctx) {')
      ..writeln('  const entity = ctx.input || {};')
      ..writeln(
        "  ctx.assert(entity !== null && typeof entity === 'object' && !Array.isArray(entity), 'Entité ${escapeJsSingleQuoted(model.technicalName)} invalide.');",
      );

    final invariants = model.invariants;
    if (invariants.isEmpty) {
      buf.writeln(
        '  // Ajoutez vos règles métier avec ctx.assert(condition, "Message explicite");',
      );
    } else {
      for (var i = 0; i < invariants.length; i++) {
        final inv = invariants[i];
        final name = _extractLabel(inv, fallback: 'Invariant_${i + 1}');
        final desc = _extractDescription(inv);
        final msg = desc.isNotEmpty ? '$name : $desc' : name;
        buf
          ..writeln('')
          ..writeln('  // Règle ${i + 1} — ${_sanitizeCommentLine(msg)}')
          ..writeln('  const rule${i + 1}Satisfied = entity !== null;')
          ..writeln(
            "  ctx.assert(rule${i + 1}Satisfied, '${escapeJsSingleQuoted(msg)}');",
          );
      }
    }

    buf
      ..writeln('')
      ..writeln('  return { valid: true, model: \'${escapeJsSingleQuoted(model.technicalName)}\', operation: ctx.operation };')
      ..writeln('}');
    return buf.toString();
  }

  /// Génère un squelette QuickJS pour une commande modifiant l'état (`stateChanging`)
  /// sur l'agrégat [model].
  static String starterForAggregateCommand(
    ImportedContractEntry model,
    Map<String, Object?> methodSpec, {
    String? collectionName,
  }) {
    final methodName = _extractLabel(methodSpec, fallback: 'executeCommand');
    final desc = _extractDescription(methodSpec);
    final targetCollection = (collectionName != null && collectionName.trim().isNotEmpty)
        ? collectionName.trim()
        : _defaultCollectionSlug(model.technicalName);
    final events = _extractEventNames(methodSpec);

    final buf = StringBuffer()
      ..writeln(
        '// Commande d’agrégat ${model.technicalName}.$methodName',
      );
    if (desc.isNotEmpty) {
      buf.writeln('// ${_sanitizeCommentLine(desc)}');
    }
    buf
      ..writeln('export default function handle(ctx) {')
      ..writeln('  const payload = ctx.input || {};')
      ..writeln(
        "  ctx.assert(typeof payload === 'object' && payload !== null, 'Charge utile de commande requise.');",
      )
      ..writeln('  const aggregateId = ctx.params.id || payload.id || null;')
      ..writeln(
        "  const existing = aggregateId ? ctx.collection('${escapeJsSingleQuoted(targetCollection)}').read(aggregateId) : null;",
      );

    for (final ev in events) {
      buf.writeln(
        "  ctx.emit('${escapeJsSingleQuoted(ev)}', { aggregateId: aggregateId, command: '${escapeJsSingleQuoted(methodName)}', input: payload });",
      );
    }

    buf
      ..writeln('  return {')
      ..writeln('    executed: true,')
      ..writeln("    aggregate: '${escapeJsSingleQuoted(model.technicalName)}',")
      ..writeln("    command: '${escapeJsSingleQuoted(methodName)}',")
      ..writeln('    aggregateId: aggregateId,')
      ..writeln('    entity: existing,')
      ..writeln('  };')
      ..writeln('}');
    return buf.toString();
  }

  /// Génère un handler QuickJS pré-structuré pour le Use Case CQRS [useCase].
  static String starterForUseCase(
    ImportedUseCaseSpec useCase, {
    String? targetCollectionName,
  }) {
    final effectiveCollection =
        (targetCollectionName != null && targetCollectionName.trim().isNotEmpty)
        ? targetCollectionName.trim()
        : (useCase.targetAggregate.trim().isNotEmpty
              ? _defaultCollectionSlug(useCase.targetAggregate)
              : '');

    final buf = StringBuffer()
      ..writeln(
        '// Use Case ${useCase.code} — ${_sanitizeCommentLine(useCase.effectiveTitle)} (${useCase.cqrsType.toUpperCase()})',
      );
    if (useCase.businessGoal.trim().isNotEmpty) {
      buf.writeln('// Objectif : ${_sanitizeCommentLine(useCase.businessGoal)}');
    }
    for (final rule in useCase.businessRules) {
      buf.writeln('// Règle métier : ${_sanitizeCommentLine(rule)}');
    }

    buf.writeln('export default function handle(ctx) {');

    if (useCase.isQuery) {
      if (effectiveCollection.isNotEmpty) {
        buf
          ..writeln(
            "  const page = ctx.collection('${escapeJsSingleQuoted(effectiveCollection)}').search(ctx.query);",
          )
          ..writeln('  return {')
          ..writeln("    useCase: '${escapeJsSingleQuoted(useCase.code)}',")
          ..writeln('    items: page.items,')
          ..writeln('    total: page.total,')
          ..writeln('    page: page.page,')
          ..writeln('    pageSize: page.pageSize,')
          ..writeln('  };');
      } else {
        buf
          ..writeln('  return {')
          ..writeln("    useCase: '${escapeJsSingleQuoted(useCase.code)}',")
          ..writeln('    items: [],')
          ..writeln('    total: 0,')
          ..writeln('    query: ctx.query,')
          ..writeln('  };');
      }
    } else {
      buf
        ..writeln('  const input = ctx.input || {};')
        ..writeln(
          "  ctx.assert(input !== null && typeof input === 'object' && !Array.isArray(input), 'Payload d’entrée invalide pour ${escapeJsSingleQuoted(useCase.code)}.');",
        );

      if (effectiveCollection.isNotEmpty) {
        buf
          ..writeln('  let entity = null;')
          ..writeln('  if (Object.keys(input).length > 0) {')
          ..writeln(
            "    entity = ctx.collection('${escapeJsSingleQuoted(effectiveCollection)}').create(input);",
          )
          ..writeln('  }');
      } else {
        buf.writeln('  const entity = null;');
      }

      for (final eventName in useCase.emittedEvents) {
        buf.writeln(
          "  ctx.emit('${escapeJsSingleQuoted(eventName)}', entity || input);",
        );
      }

      buf
        ..writeln('  return {')
        ..writeln('    executed: true,')
        ..writeln("    useCase: '${escapeJsSingleQuoted(useCase.code)}',")
        ..writeln('    entity: entity,')
        ..writeln('    input: input,')
        ..writeln('  };');
    }

    buf.writeln('}');
    return buf.toString();
  }

  /// Génère un squelette d'orchestration QuickJS pour la Saga [saga].
  static String starterForSaga(ImportedSagaSpec saga) {
    final buf = StringBuffer()
      ..writeln(
        '// Saga ${saga.code} — ${_sanitizeCommentLine(saga.name)} (mode : ${saga.coordinationMode})',
      );
    if (saga.triggerEvent.trim().isNotEmpty) {
      buf.writeln(
        '// Déclencheur : ${_sanitizeCommentLine(saga.triggerEvent)}',
      );
    }
    buf
      ..writeln('export default function handle(ctx) {')
      ..writeln('  const triggerPayload = ctx.input || {};')
      ..writeln(
        "  ctx.log('Démarrage Saga ${escapeJsSingleQuoted(saga.code)}');",
      )
      ..writeln('  const completedSteps = [];');

    for (var i = 0; i < saga.steps.length; i++) {
      final step = saga.steps[i];
      final stepName = _extractLabel(step, fallback: 'step_${i + 1}');
      buf
        ..writeln('  // Étape ${i + 1} : ${_sanitizeCommentLine(stepName)}')
        ..writeln(
          "  completedSteps.push('${escapeJsSingleQuoted(stepName)}');",
        );
    }

    for (var i = 0; i < saga.compensations.length; i++) {
      final comp = saga.compensations[i];
      final compName = _extractLabel(comp, fallback: 'compensation_${i + 1}');
      buf.writeln(
        '  // Compensation déclarée : ${_sanitizeCommentLine(compName)}',
      );
    }

    buf
      ..writeln(
        "  ctx.emit('${escapeJsSingleQuoted(saga.name)}Completed', { saga: '${escapeJsSingleQuoted(saga.code)}', completedSteps: completedSteps, trigger: triggerPayload });",
      )
      ..writeln('  return {')
      ..writeln("    saga: '${escapeJsSingleQuoted(saga.code)}',")
      ..writeln("    mode: '${escapeJsSingleQuoted(saga.coordinationMode)}',")
      ..writeln("    status: 'completed',")
      ..writeln('    completedSteps: completedSteps,')
      ..writeln('  };')
      ..writeln('}');
    return buf.toString();
  }

  /// Échappe une chaîne pour son inclusion sûre dans un littéral JavaScript `'...'`.
  static String escapeJsSingleQuoted(String raw) => raw
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\r', '')
      .replaceAll('\n', ' ');

  static String _sanitizeCommentLine(String raw) =>
      raw.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();

  static String _extractLabel(
    Map<String, Object?> map, {
    required String fallback,
  }) {
    for (final key in const <String>[
      'name',
      'methodName',
      'title',
      'code',
      'action',
      'stepName',
      'id',
    ]) {
      final val = map[key];
      if (val is String && val.trim().isNotEmpty) {
        return val.trim();
      }
    }
    return fallback;
  }

  static String _extractDescription(Map<String, Object?> map) {
    for (final key in const <String>[
      'description',
      'rule',
      'expression',
      'summary',
      'message',
    ]) {
      final val = map[key];
      if (val is String && val.trim().isNotEmpty) {
        return val.trim();
      }
    }
    return '';
  }

  static List<String> _extractEventNames(Map<String, Object?> map) {
    final raw = map['emittedEvents'] ?? map['events'] ?? map['domainEvents'];
    if (raw is String && raw.trim().isNotEmpty) {
      return <String>[raw.trim()];
    }
    if (raw is List) {
      final out = <String>[];
      for (final item in raw) {
        if (item is String && item.trim().isNotEmpty) {
          out.add(item.trim());
        } else if (item is Map) {
          final n = _extractLabel(freezeJsonMap(item), fallback: '');
          if (n.isNotEmpty) out.add(n);
        }
      }
      return out;
    }
    return const <String>[];
  }

  static String _defaultCollectionSlug(String technicalName) {
    final kebab = technicalName
        .trim()
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}-${m[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'),
          (m) => '${m[1]}-${m[2]}',
        )
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (kebab.isEmpty) return 'entities';
    if (kebab.endsWith('s') || kebab.endsWith('x') || kebab.endsWith('z')) {
      return kebab;
    }
    if (kebab.length >= 2 &&
        kebab.endsWith('y') &&
        !'aeiou'.contains(kebab[kebab.length - 2])) {
      return '${kebab.substring(0, kebab.length - 1)}ies';
    }
    return '${kebab}s';
  }
}
