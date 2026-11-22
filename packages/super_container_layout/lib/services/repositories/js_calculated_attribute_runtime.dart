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

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_js/flutter_js.dart';

import '../../models/json_text_binding.dart';
import 'calculated_attribute.dart';

/// Interface d'évaluation d'une formule JavaScript pour un attribut calculé.
abstract class JsCalculatedEvaluator {
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

  /// Invalide le document mis en cache pour [repositoryId], ou l'ensemble des
  /// documents si [repositoryId] vaut `null`.
  void invalidateDocument([String? repositoryId]) {}

  /// Libère les ressources natives associées au runtime.
  void dispose();
}

/// Évaluateur optionnel des scripts JavaScript associés aux comportements.
abstract interface class JsRepositoryActionEvaluator {
  /// Exécute un script de comportement et retourne ses demandes d'écriture.
  FutureOr<List<JsRepositoryScriptWrite>> executeAction({
    required String code,
    required Object? rootData,
    required Map<String, Object?> eventData,
    required String repositoryId,
  });

  /// Libère les ressources natives associées au runtime.
  void dispose();
}

/// Écriture JSON demandée par un script de comportement.
typedef JsRepositoryScriptWrite = ({String path, Object? value});

/// Suppression d'un élément de tableau demandée par un script de comportement.
///
/// Lorsque [index] vaut `null`, [arrayPath] contient déjà le modèle de chemin
/// suivi d'un `[?]` à résoudre à l'exécution via `ctx.remove(...)`.
typedef JsRepositoryScriptRemoval = ({String arrayPath, int? index});

/// Sélection d'un élément de tableau demandée par un script de comportement.
typedef JsRepositoryScriptSelection = ({
  String arrayPath,
  int index,
  String? repositoryId,
});

/// Résultat structuré d'un script d'action JavaScript sur les repositories.
class JsRepositoryActionResult {
  /// Crée un résultat regroupant écritures, suppressions et sélections.
  const JsRepositoryActionResult({
    this.writes = const [],
    this.removals = const [],
    this.selections = const [],
  });

  /// Écritures JSON demandées via `ctx.set(path, value)`.
  final List<JsRepositoryScriptWrite> writes;

  /// Suppressions d'éléments de tableau demandées via `ctx.removeAt` / `ctx.remove`.
  final List<JsRepositoryScriptRemoval> removals;

  /// Sélections d'éléments de tableau demandées via `ctx.select`.
  final List<JsRepositoryScriptSelection> selections;

  /// Vrai si le script n'a demandé aucune écriture, suppression ni sélection.
  bool get isEmpty => writes.isEmpty && removals.isEmpty && selections.isEmpty;
}

/// Callback de lecture utilisé par `ctx.get(...)` dans un script d'action.
typedef JsRepositoryScriptReader = FutureOr<Object?> Function(
  String path,
  String? repositoryId,
);

/// Évaluateur enrichi supportant lectures cross-repository (`ctx.get`),
/// suppressions (`ctx.removeAt`/`ctx.remove`) et sélections (`ctx.select`).
abstract interface class JsRepositoryRichActionEvaluator
    implements JsRepositoryActionEvaluator {
  /// Exécute un script de comportement et retourne ses écritures, suppressions
  /// et sélections.
  FutureOr<JsRepositoryActionResult> executeRichAction({
    required String code,
    required Object? rootData,
    required Map<String, Object?> eventData,
    required String repositoryId,
    JsRepositoryScriptReader? readValue,
  });
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
class QuickJsCalculatedEvaluator
    implements JsCalculatedEvaluator, JsRepositoryRichActionEvaluator {
  /// Crée un évaluateur QuickJS ; [runtimeFactory] permet d'injecter un
  /// runtime personnalisé dans les tests.
  QuickJsCalculatedEvaluator({JavascriptRuntime Function()? runtimeFactory})
    : _runtimeFactory = runtimeFactory ?? (() => QuickJsRuntime2());

  final JavascriptRuntime Function() _runtimeFactory;
  JavascriptRuntime? _runtime;
  bool _bootstrapped = false;
  bool _disposed = false;

  static const int _maxResolutionPasses = 64;
  static const int _maxCachedDocs = 64;
  static const int _maxCachedCodes = 1024;

  final _cachedRoots = <String, Object?>{};
  final _codeIds = <String, int>{};
  final _uploadedCodeIds = <int>{};
  int _nextCodeId = 0;
  int _documentUploadCount = 0;

  /// Nombre de synchronisations complètes de documents JSON vers QuickJS.
  @visibleForTesting
  int get debugDocumentUploadCount => _documentUploadCount;

  static const String _bootstrapScript = r'''
(function() {
  if (globalThis.__sclCalcReady) return true;
  const __fnCache = Object.create(null);
  const __fnById = Object.create(null);
  const __codeSourceById = Object.create(null);
  const __docCache = Object.create(null);

  globalThis.__sclSetDoc = function(docKey, docJson) {
    __docCache[String(docKey ?? '')] = JSON.parse(docJson);
    return true;
  };

  globalThis.__sclClearDoc = function(docKey) {
    if (docKey === null || docKey === undefined) {
      for (const key of Object.keys(__docCache)) {
        delete __docCache[key];
      }
    } else {
      delete __docCache[String(docKey)];
    }
    return true;
  };

  globalThis.__sclClearCode = function(codeId) {
    delete __codeSourceById[codeId];
    delete __fnById[codeId];
    return true;
  };

  function __resolveByPath(root, path) {
    if (!path) return root;
    let cur = root;
    const re = /([^.\[\]]+)|\[(\d+)\]/g;
    let match;
    while ((match = re.exec(path)) !== null) {
      if (cur === null || cur === undefined) return null;
      if (match[1] !== undefined) {
        cur = cur[match[1]];
      } else {
        cur = cur[Number(match[2])];
      }
    }
    return cur === undefined ? null : cur;
  }

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

    const rawRoot = Object.prototype.hasOwnProperty.call(payload, 'rootData')
      ? payload.rootData
      : __docCache[String(payload.docKey ?? '')];
    const rawScope = payload.scopeMode === 'root'
      ? rawRoot
      : payload.scopeMode === 'path'
        ? __resolveByPath(rawRoot, payload.scopePath)
        : payload.scopeData;

    const row = makeProxy(rawScope, '', scopePaths, false);
    const doc = makeProxy(rawRoot, '', rootPaths, true);
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
      let fn;
      if (payload.codeId !== undefined && payload.codeId !== null) {
        const id = payload.codeId;
        if (Object.prototype.hasOwnProperty.call(payload, 'code')) {
          __codeSourceById[id] = payload.code;
        }
        if (!Object.prototype.hasOwnProperty.call(__fnById, id)) {
          __fnById[id] = __compile(__codeSourceById[id]);
        }
        fn = __fnById[id];
      } else {
        fn = __compile(payload.code);
      }
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

  globalThis.__sclRunRepositoryAction = function(payloadJson) {
    const payload = JSON.parse(payloadJson);
    const resolved = payload.resolved || {};
    const writes = new Map();
    const removals = [];
    const selections = [];
    const missing = [];
    const seenMissing = Object.create(null);

    function __hasCalculatedSegment(path) {
      return String(path)
        .split('.')
        .some(segment => segment.startsWith('@') || segment.includes('@'));
    }

    function readCtx(kind, path, repoOrOpts, maybeDefault, hasExplicitDefault) {
      let repositoryId = null;
      let defaultValue = undefined;
      let hasDefault = hasExplicitDefault;
      if (repoOrOpts !== null && typeof repoOrOpts === 'object' && !Array.isArray(repoOrOpts)) {
        repositoryId = typeof repoOrOpts.repositoryId === 'string' && repoOrOpts.repositoryId.length > 0
          ? repoOrOpts.repositoryId
          : null;
        if (Object.prototype.hasOwnProperty.call(repoOrOpts, 'defaultValue')) {
          defaultValue = repoOrOpts.defaultValue;
          hasDefault = true;
        }
      } else if (typeof repoOrOpts === 'string') {
        if (repoOrOpts.length > 0) {
          repositoryId = repoOrOpts;
        }
        if (hasExplicitDefault) {
          defaultValue = maybeDefault;
        }
      } else if (hasExplicitDefault) {
        defaultValue = maybeDefault;
      } else if (repoOrOpts !== undefined) {
        defaultValue = repoOrOpts;
        hasDefault = true;
      }
      const key = JSON.stringify([kind, path, repositoryId, hasDefault, hasDefault ? defaultValue : null]);
      if (Object.prototype.hasOwnProperty.call(resolved, key)) {
        const entry = resolved[key];
        if (entry && entry.error) {
          throw new Error(entry.error);
        }
        return readonly(entry ? entry.value : null);
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

    function readonly(value) {
      if (value === null || typeof value !== 'object') return value;
      return new Proxy(value, {
        get(obj, prop, receiver) {
          const result = Reflect.get(obj, prop, receiver);
          if (typeof result === 'function') return result.bind(receiver);
          return readonly(result);
        },
        set() {
          throw new TypeError('Utilisez ctx.set(path, value) pour modifier le repository.');
        },
        deleteProperty() {
          throw new TypeError('Les données du repository sont en lecture seule dans un script.');
        },
        defineProperty() {
          throw new TypeError('Les données du repository sont en lecture seule dans un script.');
        },
        setPrototypeOf() {
          throw new TypeError('Les données du repository sont en lecture seule dans un script.');
        },
      });
    }

    try {
      const ctx = {
        repositoryId: payload.repositoryId,
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
        set(path, value) {
          if (typeof path !== 'string' || path.trim() === '') {
            throw new TypeError('ctx.set attend un chemin JSON non vide.');
          }
          const cleanPath = path.trim();
          if (__hasCalculatedSegment(cleanPath)) {
            throw new TypeError('Les attributs calculés (@) sont en lecture seule.');
          }
          writes.set(cleanPath, __assertJsonCompatible(value));
          return value;
        },
        remove(path) {
          if (typeof path !== 'string' || path.trim() === '') {
            throw new TypeError('ctx.remove attend un chemin d’élément de tableau non vide.');
          }
          const cleanPath = path.trim();
          if (__hasCalculatedSegment(cleanPath)) {
            throw new TypeError('Les attributs calculés (@) sont en lecture seule.');
          }
          const match = /\[(\d+|\?)\]$/.exec(cleanPath);
          if (!match || match.index === 0) {
            throw new TypeError('ctx.remove attend un chemin se terminant par [index] ou [?].');
          }
          const arrayPath = cleanPath.slice(0, match.index);
          const index = match[1] === '?' ? null : Number(match[1]);
          if (index !== null && (!Number.isInteger(index) || index < 0)) {
            throw new RangeError('ctx.remove attend un indice entier positif ou nul.');
          }
          removals.push({arrayPath: arrayPath, index: index});
        },
        removeAt(arrayPath, index) {
          if (typeof arrayPath !== 'string' || arrayPath.trim() === '') {
            throw new TypeError('ctx.removeAt attend un chemin de tableau JSON non vide.');
          }
          const cleanPath = arrayPath.trim();
          if (__hasCalculatedSegment(cleanPath)) {
            throw new TypeError('Les attributs calculés (@) sont en lecture seule.');
          }
          if (typeof index !== 'number' || !Number.isInteger(index) || index < 0) {
            throw new RangeError('ctx.removeAt attend un indice entier positif ou nul.');
          }
          removals.push({arrayPath: cleanPath, index: index});
        },
        select(arrayPath, index, repositoryId) {
          if (typeof arrayPath !== 'string' || arrayPath.trim() === '') {
            throw new TypeError('ctx.select attend un chemin de tableau JSON non vide.');
          }
          const cleanPath = arrayPath.trim();
          if (__hasCalculatedSegment(cleanPath)) {
            throw new TypeError('Les attributs calculés (@) sont en lecture seule.');
          }
          if (typeof index !== 'number' || !Number.isInteger(index) || index < 0) {
            throw new RangeError('ctx.select attend un indice entier positif ou nul.');
          }
          const targetRepo = typeof repositoryId === 'string' && repositoryId.trim() !== ''
            ? repositoryId.trim()
            : null;
          selections.push({arrayPath: cleanPath, index: index, repositoryId: targetRepo});
        },
      };
      const fn = new Function(
        'ctx',
        'doc',
        'event',
        '"use strict"; ' + String(payload.code ?? '')
      );
      fn(ctx, readonly(payload.rootData), readonly(payload.eventData || {}));
      return JSON.stringify({
        status: 'ok',
        writes: Array.from(writes, ([path, value]) => ({path, value})),
        removals: removals,
        selections: selections,
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
      return JSON.stringify({status: 'error', error: name + ': ' + message});
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
  void invalidateDocument([String? repositoryId]) {
    if (_disposed) return;
    if (repositoryId == null) {
      _cachedRoots.clear();
      if (_bootstrapped && _runtime != null) {
        _runtime!.evaluate('globalThis.__sclClearDoc(null)');
      }
    } else if (_cachedRoots.remove(repositoryId) != null &&
        _bootstrapped &&
        _runtime != null) {
      _runtime!.evaluate(
        'globalThis.__sclClearDoc(${jsonEncode(repositoryId)})',
      );
    }
  }

  int _resolveCodeId(String code) {
    final existing = _codeIds.remove(code);
    if (existing != null) {
      _codeIds[code] = existing;
      return existing;
    }
    if (_codeIds.length >= _maxCachedCodes) {
      final oldestKey = _codeIds.keys.first;
      final evicted = _codeIds.remove(oldestKey);
      if (evicted != null) {
        _uploadedCodeIds.remove(evicted);
        if (_bootstrapped && _runtime != null) {
          _runtime!.evaluate('globalThis.__sclClearCode($evicted)');
        }
      }
    }
    final assigned = ++_nextCodeId;
    _codeIds[code] = assigned;
    return assigned;
  }

  void _ensureRootUploaded(
    JavascriptRuntime runtime,
    String docKey,
    Object? rootData,
  ) {
    if (_cachedRoots.containsKey(docKey) &&
        identical(_cachedRoots[docKey], rootData)) {
      final existing = _cachedRoots.remove(docKey);
      _cachedRoots[docKey] = existing;
      return;
    }
    if (_cachedRoots.length >= _maxCachedDocs &&
        !_cachedRoots.containsKey(docKey)) {
      final oldestKey = _cachedRoots.keys.first;
      _cachedRoots.remove(oldestKey);
      runtime.evaluate('globalThis.__sclClearDoc(${jsonEncode(oldestKey)})');
    }
    final encodedDoc = jsonEncode(rootData);
    final setResult = runtime.evaluate(
      'globalThis.__sclSetDoc(${jsonEncode(docKey)}, ${jsonEncode(encodedDoc)})',
    );
    if (setResult.isError) {
      throw JsCalculationException(
        'Synchronisation du document QuickJS impossible : ${setResult.stringResult}',
      );
    }
    _cachedRoots[docKey] = rootData;
    _documentUploadCount++;
  }

  @override
  FutureOr<Object?> evaluate({
    required String code,
    required Object? scopeData,
    required Object? rootData,
    required CalculatedAttributeContext context,
  }) {
    final runtime = _ensureRuntime();
    final docKey = context.repositoryId;
    final codeId = _resolveCodeId(code);
    final String scopeMode;
    if (identical(scopeData, rootData)) {
      scopeMode = 'root';
    } else if (context.scopePath.isNotEmpty &&
        rootData != null &&
        identical(
          scopeData,
          JsonAttributePath(context.scopePath).readNode(rootData),
        )) {
      scopeMode = 'path';
    } else {
      scopeMode = 'inline';
    }
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
        _ensureRootUploaded(runtime, docKey, rootData);
        final sendCode = _uploadedCodeIds.add(codeId);
        final payloadJson = jsonEncode(<String, Object?>{
          'codeId': codeId,
          if (sendCode) 'code': code,
          'docKey': docKey,
          'scopeMode': scopeMode,
          if (scopeMode == 'inline') 'scopeData': scopeData,
          'repositoryId': context.repositoryId,
          'scopePath': context.scopePath,
          if (resolved.isNotEmpty) 'resolved': resolved,
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
          throw const JsCalculationException(
            'Réponse interne QuickJS invalide.',
          );
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
                  context.getValue(rawPath, repositoryId: context.repositoryId),
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

  @override
  FutureOr<List<JsRepositoryScriptWrite>> executeAction({
    required String code,
    required Object? rootData,
    required Map<String, Object?> eventData,
    required String repositoryId,
  }) {
    final result = executeRichAction(
      code: code,
      rootData: rootData,
      eventData: eventData,
      repositoryId: repositoryId,
    );
    if (result is Future<JsRepositoryActionResult>) {
      return result.then((r) => r.writes);
    }
    return result.writes;
  }

  @override
  FutureOr<JsRepositoryActionResult> executeRichAction({
    required String code,
    required Object? rootData,
    required Map<String, Object?> eventData,
    required String repositoryId,
    JsRepositoryScriptReader? readValue,
  }) {
    final runtime = _ensureRuntime();
    final resolved = <String, Map<String, Object?>>{};
    var pass = 0;

    FutureOr<JsRepositoryActionResult> step() {
      while (true) {
        if (_disposed) {
          throw const FormatException('Le runtime JavaScript est fermé.');
        }
        if (++pass > _maxResolutionPasses) {
          throw const JsCalculationException(
            'Trop de dépendances imbriquées dans le script JavaScript.',
          );
        }
        final payload = jsonEncode(<String, Object?>{
          'code': code,
          'rootData': rootData,
          'eventData': eventData,
          'repositoryId': repositoryId,
          if (resolved.isNotEmpty) 'resolved': resolved,
        });
        final result = runtime.evaluate(
          'globalThis.__sclRunRepositoryAction(${jsonEncode(payload)})',
        );
        if (result.isError) {
          throw JsCalculationException(
            'Erreur JavaScript : ${result.stringResult}',
          );
        }
        final rawText = result.rawResult is String
            ? result.rawResult as String
            : result.stringResult;
        final Object? decoded;
        try {
          decoded = jsonDecode(rawText);
        } on FormatException {
          throw const JsCalculationException(
            'Réponse interne du script JavaScript invalide.',
          );
        }
        if (decoded is! Map<String, dynamic>) {
          throw const JsCalculationException(
            'Réponse interne du script JavaScript invalide.',
          );
        }
        final status = decoded['status'];
        if (status == 'error') {
          throw JsCalculationException(
            decoded['error']?.toString() ?? 'Erreur JavaScript inconnue.',
          );
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
                'Chemin de lecture JavaScript invalide.',
              );
            }
            final request = (
              kind: item['kind'] as String? ?? 'value',
              path: path,
              repositoryId: item['repositoryId'] as String?,
              hasDefault: item['hasDefault'] == true,
              defaultValue: item['defaultValue'],
            );
            try {
              final readResult = _resolveActionRead(
                request: request,
                defaultRepositoryId: repositoryId,
                rootData: rootData,
                readValue: readValue,
              );
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
        if (status != 'ok') {
          throw JsCalculationException(
            decoded['error']?.toString() ?? 'Erreur JavaScript inconnue.',
          );
        }

        final rawWrites = decoded['writes'];
        if (rawWrites is! List) {
          throw const JsCalculationException(
            'La liste des écritures JavaScript est invalide.',
          );
        }
        final writes = List<JsRepositoryScriptWrite>.unmodifiable([
          for (final rawWrite in rawWrites)
            if (rawWrite is Map &&
                rawWrite['path'] is String &&
                rawWrite.containsKey('value'))
              (path: rawWrite['path'] as String, value: rawWrite['value'])
            else
              throw const JsCalculationException(
                'Une écriture JavaScript est invalide.',
              ),
        ]);

        final rawRemovals = decoded['removals'];
        if (rawRemovals != null && rawRemovals is! List) {
          throw const JsCalculationException(
            'La liste des suppressions JavaScript est invalide.',
          );
        }
        final removals = List<JsRepositoryScriptRemoval>.unmodifiable([
          if (rawRemovals is List)
            for (final rawRemoval in rawRemovals)
              if (rawRemoval is Map &&
                  rawRemoval['arrayPath'] is String &&
                  (rawRemoval['index'] == null || rawRemoval['index'] is int))
                (
                  arrayPath: rawRemoval['arrayPath'] as String,
                  index: rawRemoval['index'] as int?,
                )
              else
                throw const JsCalculationException(
                  'Une suppression JavaScript est invalide.',
                ),
        ]);

        final rawSelections = decoded['selections'];
        if (rawSelections != null && rawSelections is! List) {
          throw const JsCalculationException(
            'La liste des sélections JavaScript est invalide.',
          );
        }
        final selections = List<JsRepositoryScriptSelection>.unmodifiable([
          if (rawSelections is List)
            for (final rawSelection in rawSelections)
              if (rawSelection is Map &&
                  rawSelection['arrayPath'] is String &&
                  rawSelection['index'] is int &&
                  (rawSelection['repositoryId'] == null ||
                      rawSelection['repositoryId'] is String))
                (
                  arrayPath: rawSelection['arrayPath'] as String,
                  index: rawSelection['index'] as int,
                  repositoryId: rawSelection['repositoryId'] as String?,
                )
              else
                throw const JsCalculationException(
                  'Une sélection JavaScript est invalide.',
                ),
        ]);

        return JsRepositoryActionResult(
          writes: writes,
          removals: removals,
          selections: selections,
        );
      }
    }

    return step();
  }

  static FutureOr<Object?> _resolveActionRead({
    required _CtxReadRequest request,
    required String defaultRepositoryId,
    required Object? rootData,
    required JsRepositoryScriptReader? readValue,
  }) {
    final FutureOr<Object?> rawFutureOr;
    if (readValue != null) {
      rawFutureOr = readValue(request.path, request.repositoryId);
    } else {
      final repoId = request.repositoryId;
      if (repoId != null &&
          repoId.isNotEmpty &&
          repoId != defaultRepositoryId) {
        throw const FormatException(
          'Lecture cross-repository indisponible sans store.',
        );
      }
      final parsed = JsonAttributePath(request.path)..requireResolved();
      if (parsed.calculated != null) {
        throw FormatException(
          'Lecture de l’attribut calculé « ${request.path} » indisponible sans store.',
        );
      }
      rawFutureOr = parsed.readNode(rootData);
    }

    Object? convert(Object? raw) => _convertTypedActionValue(request, raw);

    if (rawFutureOr is Future<Object?>) {
      return rawFutureOr.then(convert);
    }
    return convert(rawFutureOr);
  }

  static Object? _convertTypedActionValue(
    _CtxReadRequest request,
    Object? raw,
  ) {
    final path = request.path;
    switch (request.kind) {
      case 'string':
        if (request.hasDefault && request.defaultValue is! String?) {
          throw const FormatException(
            'defaultValue de ctx.getString doit être une chaîne ou null.',
          );
        }
        if (raw == null) {
          return request.hasDefault ? request.defaultValue as String? : null;
        }
        if (raw is String) return raw;
        throw FormatException('L’attribut « $path » doit être de type String.');
      case 'num':
        if (request.hasDefault && request.defaultValue is! num?) {
          throw const FormatException(
            'defaultValue de ctx.getNum doit être un nombre ou null.',
          );
        }
        if (raw == null) {
          return request.hasDefault ? request.defaultValue as num? : null;
        }
        if (raw is num) return raw;
        throw FormatException('L’attribut « $path » doit être de type num.');
      case 'int':
        if (request.hasDefault && request.defaultValue is! int?) {
          throw const FormatException(
            'defaultValue de ctx.getInt doit être un entier ou null.',
          );
        }
        if (raw == null) {
          return request.hasDefault ? request.defaultValue as int? : null;
        }
        if (raw is int) return raw;
        throw FormatException('L’attribut « $path » doit être de type int.');
      case 'double':
        if (request.hasDefault && request.defaultValue is! num?) {
          throw const FormatException(
            'defaultValue de ctx.getDouble doit être un nombre ou null.',
          );
        }
        if (raw == null) {
          return request.hasDefault
              ? (request.defaultValue as num?)?.toDouble()
              : null;
        }
        if (raw is num) return raw.toDouble();
        throw FormatException('L’attribut « $path » doit être de type double.');
      case 'bool':
        if (request.hasDefault && request.defaultValue is! bool?) {
          throw const FormatException(
            'defaultValue de ctx.getBool doit être un booléen ou null.',
          );
        }
        if (raw == null) {
          return request.hasDefault ? request.defaultValue as bool? : null;
        }
        if (raw is bool) return raw;
        throw FormatException('L’attribut « $path » doit être de type bool.');
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
        if (raw == null) return request.hasDefault ? listDefault : null;
        if (raw is List) {
          return [
            for (final item in raw)
              item is Map
                  ? Map<String, Object?>.from(item)
                  : throw FormatException(
                      'L’attribut « $path » doit être un tableau d’objets.',
                    ),
          ];
        }
        throw FormatException('L’attribut « $path » doit être une liste.');
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
        if (raw == null) return request.hasDefault ? objDefault : null;
        if (raw is Map) return Map<String, Object?>.from(raw);
        throw FormatException('L’attribut « $path » doit être un objet JSON.');
      case 'value':
      default:
        if (raw == null && request.hasDefault) return request.defaultValue;
        return raw;
    }
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
    _cachedRoots.clear();
    _codeIds.clear();
    _uploadedCodeIds.clear();
    final runtime = _runtime;
    _runtime = null;
    runtime?.dispose();
  }
}
