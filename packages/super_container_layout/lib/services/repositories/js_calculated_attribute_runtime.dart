/// Runtime JavaScript pour les attributs calculés des repositories.
///
/// Fournit l'abstraction [JsCalculatedEvaluator] ainsi que son implémentation
/// embarquée [QuickJsCalculatedEvaluator] (QuickJS via `flutter_js` sur
/// Windows Desktop), exposant l'API `(row, ctx, doc)` avec suivi automatique
/// des dépendances et résolution synchrone/asynchrone compatible avec
/// [CalculatedAttributeEngine].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';

import 'calculated_attribute.dart';

/// Interface d'évaluation d'une formule JavaScript pour un attribut calculé.
abstract interface class JsCalculatedEvaluator {
  /// Évalue [code] dans le contexte [context].
  ///
  /// [scopeData] représente la valeur JSON de la ligne courante (ou le
  /// document racine pour un calcul racine) et [rootData] le document racine
  /// complet du repository porteur du calcul.
  FutureOr<Object?> evaluate({
    required String code,
    required Object? scopeData,
    required Object? rootData,
    required CalculatedAttributeContext context,
  });

  /// Libère les ressources natives associées au runtime.
  void dispose();
}

/// Exception levée lors d'une erreur de syntaxe ou d'exécution JavaScript.
class JsCalculationException extends FormatException {
  /// Crée une exception de calcul JavaScript avec un message affichable.
  const JsCalculationException(super.message);
}

typedef _CtxReadRequest = ({
  String kind,
  String path,
  String? repositoryId,
  bool hasDefault,
  Object? defaultValue,
});

/// Évaluateur QuickJS embarqué s'appuyant sur `flutter_js` ([QuickJsRuntime2]).
class QuickJsCalculatedEvaluator implements JsCalculatedEvaluator {
  /// Crée un évaluateur QuickJS ; [runtimeFactory] permet d'injecter un
  /// runtime personnalisé dans les tests.
  QuickJsCalculatedEvaluator({JavascriptRuntime Function()? runtimeFactory})
    : _runtimeFactory = runtimeFactory ?? (() => QuickJsRuntime2());

  final JavascriptRuntime Function() _runtimeFactory;
  JavascriptRuntime? _runtime;
  bool _bootstrapped = false;
  bool _disposed = false;

  static const int _maxResolutionPasses = 64;

  static const String _bootstrapScript = r'''
(function() {
  if (globalThis.__sclCalcReady) return true;
  const __fnCache = Object.create(null);

  function __compile(source) {
    const key = String(source ?? '');
    if (Object.prototype.hasOwnProperty.call(__fnCache, key)) {
      return __fnCache[key];
    }
    const trimmed = key.trim();
    if (!trimmed) {
      throw new SyntaxError('Le code JavaScript du calcul est vide.');
    }
    let compiled;
    try {
      const exprFn = new Function(
        'row',
        'ctx',
        'doc',
        '"use strict"; return (' + trimmed + ');'
      );
      compiled = function(row, ctx, doc) {
        const value = exprFn(row, ctx, doc);
        return typeof value === 'function' ? value(row, ctx, doc) : value;
      };
    } catch (_) {
      compiled = new Function('row', 'ctx', 'doc', '"use strict"; ' + trimmed);
    }
    __fnCache[key] = compiled;
    return compiled;
  }

  function __appendPath(base, segment) {
    if (/^(0|[1-9][0-9]*)$/.test(segment)) {
      return base + '[' + segment + ']';
    }
    return base ? (base + '.' + segment) : segment;
  }

  function __assertJsonCompatible(value) {
    if (value === undefined || value === null) return null;
    if (typeof value === 'number') {
      if (!Number.isFinite(value)) {
        throw new RangeError('Le calcul JS a retourné un nombre non fini (NaN ou Infinity).');
      }
      return value;
    }
    if (typeof value === 'boolean' || typeof value === 'string') return value;
    if (typeof value === 'function' || typeof value === 'symbol' || typeof value === 'bigint') {
      throw new TypeError('Type JavaScript non sérialisable en JSON : ' + typeof value);
    }
    if (Array.isArray(value)) {
      return value.map(__assertJsonCompatible);
    }
    if (value instanceof Date) {
      return value.toISOString();
    }
    if (typeof value === 'object') {
      const out = {};
      for (const key of Object.keys(value)) {
        const v = value[key];
        if (v !== undefined) {
          out[key] = __assertJsonCompatible(v);
        }
      }
      return out;
    }
    return value;
  }

  globalThis.__sclEvalCalc = function(payloadJson) {
    const payload = JSON.parse(payloadJson);
    const resolved = payload.resolved || {};
    const scopePaths = Object.create(null);
    const rootPaths = Object.create(null);
    const missing = [];
    const seenMissing = Object.create(null);

    function readCtx(kind, path, repoOrOpts, maybeDefault, hasExplicitDefault) {
      let repositoryId = null;
      let defaultValue = undefined;
      let hasDefault = hasExplicitDefault;
      if (repoOrOpts !== null && typeof repoOrOpts === 'object' && !Array.isArray(repoOrOpts)) {
        repositoryId = typeof repoOrOpts.repositoryId === 'string' ? repoOrOpts.repositoryId : null;
        if (Object.prototype.hasOwnProperty.call(repoOrOpts, 'defaultValue')) {
          defaultValue = repoOrOpts.defaultValue;
          hasDefault = true;
        }
      } else {
        if (typeof repoOrOpts === 'string' && repoOrOpts.length > 0) {
          repositoryId = repoOrOpts;
        }
        if (hasExplicitDefault) {
          defaultValue = maybeDefault;
        }
      }
      const key = JSON.stringify([kind, path, repositoryId, hasDefault, hasDefault ? defaultValue : null]);
      if (Object.prototype.hasOwnProperty.call(resolved, key)) {
        const entry = resolved[key];
        if (entry && entry.error) {
          throw new Error(entry.error);
        }
        return entry ? entry.value : null;
      }
      if (!Object.prototype.hasOwnProperty.call(seenMissing, key)) {
        seenMissing[key] = true;
        missing.push({
          key: key,
          kind: kind,
          path: String(path ?? ''),
          repositoryId: repositoryId,
          hasDefault: hasDefault,
          defaultValue: hasDefault ? defaultValue : null,
        });
      }
      const err = new Error('__SCL_DEFERRED__');
      err.__sclDeferred = true;
      throw err;
    }

    function makeProxy(target, basePath, tracker, isRoot) {
      if (target === null || typeof target !== 'object') return target;
      return new Proxy(target, {
        get(obj, prop, receiver) {
          if (typeof prop === 'symbol') {
            return Reflect.get(obj, prop, receiver);
          }
          if (typeof prop === 'string' && prop.startsWith('@')) {
            const calcPath = __appendPath(basePath, prop);
            return readCtx('value', calcPath, isRoot ? payload.repositoryId : null, undefined, false);
          }
          const isArrayIndex = Array.isArray(obj) && /^(0|[1-9][0-9]*)$/.test(prop);
          const nextPath = (typeof prop === 'string' && !(Array.isArray(obj) && typeof obj[prop] === 'function' && !Object.prototype.hasOwnProperty.call(obj, prop)))
            ? __appendPath(basePath, prop)
            : basePath;
          if (typeof prop === 'string' && nextPath && !(Array.isArray(obj) && typeof obj[prop] === 'function' && prop !== 'length')) {
            tracker[isArrayIndex ? nextPath : (prop === 'length' && Array.isArray(obj) ? basePath : nextPath)] = true;
          }
          const val = Reflect.get(obj, prop, receiver);
          if (typeof val === 'function') {
            return val.bind(receiver);
          }
          if (val !== null && typeof val === 'object') {
            return makeProxy(val, nextPath, tracker, isRoot);
          }
          return val;
        },
        set() {
          throw new TypeError('Les données du repository sont en lecture seule dans un calcul.');
        },
        deleteProperty() {
          throw new TypeError('Les données du repository sont en lecture seule dans un calcul.');
        },
      });
    }

    const row = makeProxy(payload.scopeData, '', scopePaths, false);
    const doc = makeProxy(payload.rootData, '', rootPaths, true);
    const ctx = {
      repositoryId: payload.repositoryId,
      scopePath: payload.scopePath,
      get(path, repoOrOpts, defaultValue) {
        return readCtx('value', path, repoOrOpts, defaultValue, arguments.length >= 3);
      },
      getValue(path, repoOrOpts, defaultValue) {
        return readCtx('value', path, repoOrOpts, defaultValue, arguments.length >= 3);
      },
      getString(path, repoOrOpts, defaultValue) {
        return readCtx('string', path, repoOrOpts, defaultValue, arguments.length >= 3);
      },
      getNum(path, repoOrOpts, defaultValue) {
        return readCtx('num', path, repoOrOpts, defaultValue, arguments.length >= 3);
      },
      getInt(path, repoOrOpts, defaultValue) {
        return readCtx('int', path, repoOrOpts, defaultValue, arguments.length >= 3);
      },
      getDouble(path, repoOrOpts, defaultValue) {
        return readCtx('double', path, repoOrOpts, defaultValue, arguments.length >= 3);
      },
      getBool(path, repoOrOpts, defaultValue) {
        return readCtx('bool', path, repoOrOpts, defaultValue, arguments.length >= 3);
      },
      getList(path, repoOrOpts, defaultValue) {
        return readCtx('list', path, repoOrOpts, defaultValue, arguments.length >= 3);
      },
      getObject(path, repoOrOpts, defaultValue) {
        return readCtx('object', path, repoOrOpts, defaultValue, arguments.length >= 3);
      },
    };

    try {
      const fn = __compile(payload.code);
      const raw = fn(row, ctx, doc);
      if (raw && typeof raw.then === 'function') {
        throw new TypeError('Les fonctions JavaScript asynchrones (Promise) ne sont pas supportées ; utilisez ctx.get(...) directement.');
      }
      const normalized = __assertJsonCompatible(raw);
      return JSON.stringify({
        status: 'ok',
        value: normalized,
        scopePaths: Object.keys(scopePaths),
        rootPaths: Object.keys(rootPaths),
      });
    } catch (error) {
      if (error && error.__sclDeferred) {
        return JSON.stringify({
          status: 'deferred',
          missing: missing,
        });
      }
      const message = error && error.message ? String(error.message) : String(error);
      const name = error && error.name ? String(error.name) : 'Error';
      return JSON.stringify({
        status: 'error',
        error: name + ': ' + message,
      });
    }
  };
  globalThis.__sclCalcReady = true;
  return true;
})();
''';

  JavascriptRuntime _ensureRuntime() {
    if (_disposed) {
      throw const FormatException('Le runtime JavaScript est fermé.');
    }
    var runtime = _runtime;
    if (runtime == null) {
      try {
        runtime = _runtimeFactory();
      } on Object catch (error) {
        throw JsCalculationException(
          'Impossible d’initialiser le moteur QuickJS : $error',
        );
      }
      _runtime = runtime;
      _bootstrapped = false;
    }
    if (!_bootstrapped) {
      final initResult = runtime.evaluate(_bootstrapScript);
      if (initResult.isError) {
        throw JsCalculationException(
          'Initialisation QuickJS impossible : ${initResult.stringResult}',
        );
      }
      _bootstrapped = true;
    }
    return runtime;
  }

  @override
  FutureOr<Object?> evaluate({
    required String code,
    required Object? scopeData,
    required Object? rootData,
    required CalculatedAttributeContext context,
  }) {
    final runtime = _ensureRuntime();
    final resolved = <String, Map<String, Object?>>{};
    var pass = 0;

    FutureOr<Object?> step() {
      while (true) {
        if (_disposed) {
          throw const FormatException('Le runtime JavaScript est fermé.');
        }
        if (++pass > _maxResolutionPasses) {
          throw const JsCalculationException(
            'Trop de dépendances imbriquées dans le calcul JavaScript.',
          );
        }
        final payloadJson = jsonEncode(<String, Object?>{
          'code': code,
          'scopeData': scopeData,
          'rootData': rootData,
          'repositoryId': context.repositoryId,
          'scopePath': context.scopePath,
          'resolved': resolved,
        });
        final evalResult = runtime.evaluate(
          'globalThis.__sclEvalCalc(${jsonEncode(payloadJson)})',
        );
        if (evalResult.isError) {
          throw JsCalculationException(
            'Erreur JavaScript : ${evalResult.stringResult}',
          );
        }
        final rawText = evalResult.rawResult is String
            ? evalResult.rawResult as String
            : evalResult.stringResult;
        final Object? decoded;
        try {
          decoded = jsonDecode(rawText);
        } on FormatException {
          throw JsCalculationException(
            'Réponse interne QuickJS invalide : $rawText',
          );
        }
        if (decoded is! Map<String, dynamic>) {
          throw const JsCalculationException('Réponse interne QuickJS invalide.');
        }
        final status = decoded['status'];
        if (status == 'error') {
          throw JsCalculationException(
            decoded['error']?.toString() ?? 'Erreur JavaScript inconnue.',
          );
        }
        if (status == 'ok') {
          final scopePaths = decoded['scopePaths'];
          final rootPaths = decoded['rootPaths'];
          final trackedFutures = <Future<Object?>>[];
          void track(FutureOr<Object?> readResult) {
            if (readResult is Future<Object?>) {
              trackedFutures.add(readResult);
            }
          }

          if (scopePaths is List) {
            for (final rawPath in scopePaths) {
              if (rawPath is String && rawPath.isNotEmpty) {
                track(context.getValue(rawPath));
              }
            }
          }
          if (rootPaths is List) {
            for (final rawPath in rootPaths) {
              if (rawPath is String && rawPath.isNotEmpty) {
                track(
                  context.getValue(
                    rawPath,
                    repositoryId: context.repositoryId,
                  ),
                );
              }
            }
          }
          final resultValue = decoded['value'];
          if (trackedFutures.isEmpty) {
            return resultValue;
          }
          return Future.wait(trackedFutures).then((_) => resultValue);
        }
        if (status == 'deferred') {
          final missing = decoded['missing'];
          if (missing is! List || missing.isEmpty) {
            throw const JsCalculationException(
              'Dépendance JavaScript différée vide.',
            );
          }
          final futures = <Future<void>>[];
          for (final item in missing) {
            if (item is! Map) continue;
            final key = item['key'] as String?;
            final path = item['path'] as String?;
            if (key == null || path == null || path.isEmpty) {
              throw const JsCalculationException(
                'Chemin de dépendance JavaScript invalide.',
              );
            }
            final repoId = item['repositoryId'] as String?;
            final hasDefault = item['hasDefault'] == true;
            final defaultValue = item['defaultValue'];
            final request = (
              kind: item['kind'] as String? ?? 'value',
              path: path,
              repositoryId: repoId,
              hasDefault: hasDefault,
              defaultValue: defaultValue,
            );
            try {
              final readResult = _readTyped(context, request);
              if (readResult is Future<Object?>) {
                futures.add(
                  readResult.then<void>(
                    (val) => resolved[key] = <String, Object?>{'value': val},
                    onError: (Object err, StackTrace _) {
                      if (err is FormatException) {
                        resolved[key] = <String, Object?>{'error': err.message};
                      } else {
                        resolved[key] = <String, Object?>{
                          'error': err.toString(),
                        };
                      }
                    },
                  ),
                );
              } else {
                resolved[key] = <String, Object?>{'value': readResult};
              }
            } on FormatException catch (err) {
              resolved[key] = <String, Object?>{'error': err.message};
            }
          }
          if (futures.isEmpty) continue;
          return Future.wait(futures).then((_) => step());
        }
        throw JsCalculationException('Statut QuickJS inconnu : $status');
      }
    }

    return step();
  }

  static FutureOr<Object?> _readTyped(
    CalculatedAttributeContext context,
    _CtxReadRequest request,
  ) {
    final path = request.path;
    final repoId = request.repositoryId;
    switch (request.kind) {
      case 'string':
        if (request.hasDefault && request.defaultValue is! String?) {
          throw const FormatException(
            'defaultValue de ctx.getString doit être une chaîne ou null.',
          );
        }
        return context.getString(
          path,
          repositoryId: repoId,
          defaultValue: request.defaultValue as String?,
        );
      case 'num':
        if (request.hasDefault && request.defaultValue is! num?) {
          throw const FormatException(
            'defaultValue de ctx.getNum doit être un nombre ou null.',
          );
        }
        return context.getNum(
          path,
          repositoryId: repoId,
          defaultValue: request.defaultValue as num?,
        );
      case 'int':
        if (request.hasDefault && request.defaultValue is! int?) {
          throw const FormatException(
            'defaultValue de ctx.getInt doit être un entier ou null.',
          );
        }
        return context.getInt(
          path,
          repositoryId: repoId,
          defaultValue: request.defaultValue as int?,
        );
      case 'double':
        if (request.hasDefault && request.defaultValue is! num?) {
          throw const FormatException(
            'defaultValue de ctx.getDouble doit être un nombre ou null.',
          );
        }
        return context.getDouble(
          path,
          repositoryId: repoId,
          defaultValue: (request.defaultValue as num?)?.toDouble(),
        );
      case 'bool':
        if (request.hasDefault && request.defaultValue is! bool?) {
          throw const FormatException(
            'defaultValue de ctx.getBool doit être un booléen ou null.',
          );
        }
        return context.getBool(
          path,
          repositoryId: repoId,
          defaultValue: request.defaultValue as bool?,
        );
      case 'list':
        final rawDefault = request.defaultValue;
        List<Map<String, Object?>>? listDefault;
        if (request.hasDefault && rawDefault != null) {
          if (rawDefault is! List) {
            throw const FormatException(
              'defaultValue de ctx.getList doit être un tableau ou null.',
            );
          }
          listDefault = [
            for (final item in rawDefault)
              item is Map
                  ? Map<String, Object?>.from(item)
                  : throw const FormatException(
                      'defaultValue de ctx.getList ne doit contenir que des objets.',
                    ),
          ];
        }
        return context.getList(
          path,
          repositoryId: repoId,
          defaultValue: listDefault,
        );
      case 'object':
        final rawDefault = request.defaultValue;
        Map<String, Object?>? objDefault;
        if (request.hasDefault && rawDefault != null) {
          if (rawDefault is! Map) {
            throw const FormatException(
              'defaultValue de ctx.getObject doit être un objet ou null.',
            );
          }
          objDefault = Map<String, Object?>.from(rawDefault);
        }
        return context.getObject(
          path,
          repositoryId: repoId,
          defaultValue: objDefault,
        );
      case 'value':
      default:
        final value = context.getValue(path, repositoryId: repoId);
        if (!request.hasDefault) return value;
        if (value is Future<Object?>) {
          return value.then((v) => v ?? request.defaultValue);
        }
        return value ?? request.defaultValue;
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
