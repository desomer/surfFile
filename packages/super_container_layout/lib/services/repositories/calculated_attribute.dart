/// Attributs calculés des repositories : contexte typé, cache par génération
/// et graphe de dépendances partagé par le store, sans persistance des fonctions.
library;

import 'dart:async';

import '../../models/calculated_attribute_definition.dart';
import '../../models/json_text_binding.dart';
import '../diagnostics/debug_entry.dart';
import '../inspection/vibe_debug_capture.dart';
import 'js_calculated_attribute_runtime.dart';

/// Origine d'un attribut calculé déclaré sur un repository.
enum CalculatedAttributeSource {
  /// Fonction Dart enregistrée par code via `RepositoryImpl.addCalculatedAttribute`.
  dart,

  /// Formule JavaScript persistée ou déclarée via `CalculatedAttributeDefinition`.
  js,
}

/// Fonction Dart synchrone ou asynchrone d'un attribut calculé.
typedef CalculatedAttributeFunction = FutureOr<Object?> Function(
  CalculatedAttributeContext context,
);

/// Description d'un calcul disponible dans les formulaires de liaison.
class CalculatedAttributeDescriptor {
  /// Décrit un calcul racine ou un calcul relatif à un modèle de ligne.
  const CalculatedAttributeDescriptor({
    required this.name,
    this.scope,
    this.source = CalculatedAttributeSource.dart,
    this.description,
  });

  /// Nom sans le marqueur `@`.
  final String name;

  /// Modèle de ligne JSON, ou `null` pour un calcul racine.
  final String? scope;

  /// Origine de l'attribut calculé (`dart` ou `js`).
  final CalculatedAttributeSource source;

  /// Description optionnelle fournie sur les définitions JavaScript.
  final String? description;

  /// Vrai lorsque ce calcul est défini en JavaScript.
  bool get isJs => source == CalculatedAttributeSource.js;

  /// Chemin modèle utilisable dans une liaison, sans exécuter le calcul.
  String get path => scope == null ? '@$name' : '$scope.@$name';
}

/// Lectures d'un calcul avec suivi automatique des dépendances.
///
/// Les chemins sont relatifs à [scopePath]. Un [repositoryId] explicitement
/// fourni à un getter désigne toujours la racine du repository demandé.
/// Les défauts ne remplacent que `null`/absent, jamais une erreur.
class CalculatedAttributeContext {
  CalculatedAttributeContext._(this._engine, this._run);

  final CalculatedAttributeEngine _engine;
  final _Calculation _run;

  /// Repository qui porte ce calcul.
  String get repositoryId => _run.key.repositoryId;

  /// Chemin concret de la ligne, vide pour un calcul racine.
  String get scopePath => _run.scope;

  /// Façade immédiate ; une lecture asynchrone indisponible est une erreur.
  late final sync = SynchronousCalculatedAttributeContext._(this);

  /// Lit une valeur JSON ou calculée, éventuellement dans un autre repository.
  ///
  /// Les `[?]` sont résolus avec les indices de la ligne courante.
  FutureOr<Object?> getValue(String path, {String? repositoryId}) {
    if (_run.stale) {
      throw const FormatException('Le calcul a été invalidé.');
    }
    final parsed = JsonAttributePath(path);
    final resolved = parsed
        .resolve(
          scopePath.isEmpty ? const [] : JsonAttributePath(scopePath).indices,
        )
        .toString();
    final target = repositoryId ?? this.repositoryId;
    final absolute = repositoryId != null || scopePath.isEmpty
        ? resolved
        : '$scopePath.$resolved';
    return _engine._readValue(target, absolute, caller: _run);
  }

  /// Lit une chaîne, sans conversion implicite.
  FutureOr<String?> getString(
    String path, {
    String? repositoryId,
    String? defaultValue,
  }) => _getTyped<String>(
    path,
    (v) => v is String ? v : null,
    repositoryId: repositoryId,
    defaultValue: defaultValue,
  );

  /// Lit un nombre entier ou décimal.
  FutureOr<num?> getNum(
    String path, {
    String? repositoryId,
    num? defaultValue,
  }) => _getTyped<num>(
    path,
    (v) => v is num ? v : null,
    repositoryId: repositoryId,
    defaultValue: defaultValue,
  );

  /// Lit un entier sans tronquer une valeur décimale.
  FutureOr<int?> getInt(
    String path, {
    String? repositoryId,
    int? defaultValue,
  }) => _getTyped<int>(
    path,
    (v) => v is int ? v : null,
    repositoryId: repositoryId,
    defaultValue: defaultValue,
  );

  /// Lit un nombre en double, en convertissant aussi les entiers.
  FutureOr<double?> getDouble(
    String path, {
    String? repositoryId,
    double? defaultValue,
  }) => _getTyped<double>(
    path,
    (v) => v is num ? v.toDouble() : null,
    repositoryId: repositoryId,
    defaultValue: defaultValue,
  );

  /// Lit un booléen sans conversion implicite.
  FutureOr<bool?> getBool(
    String path, {
    String? repositoryId,
    bool? defaultValue,
  }) => _getTyped<bool>(
    path,
    (v) => v is bool ? v : null,
    repositoryId: repositoryId,
    defaultValue: defaultValue,
  );

  /// Lit un tableau d'objets JSON à clés chaînes.
  ///
  /// Lève une [FormatException] si un élément n'est pas un objet JSON.
  FutureOr<List<Map<String, Object?>>?> getList(
    String path, {
    String? repositoryId,
    List<Map<String, Object?>>? defaultValue,
  }) => _getTyped<List<Map<String, Object?>>>(
    path,
    (value) {
      if (value is! List<Object?>) return null;
      final objects = <Map<String, Object?>>[];
      for (final element in value) {
        if (element is! Map<String, Object?>) return null;
        objects.add(element);
      }
      return List<Map<String, Object?>>.unmodifiable(objects);
    },
    repositoryId: repositoryId,
    defaultValue: defaultValue,
  );

  /// Lit un objet JSON à clés chaînes sous forme de Map.
  FutureOr<Map<String, Object?>?> getObject(
    String path, {
    String? repositoryId,
    Map<String, Object?>? defaultValue,
  }) => _getTyped<Map<String, Object?>>(
    path,
    (v) => v is Map<String, Object?> ? v : null,
    repositoryId: repositoryId,
    defaultValue: defaultValue,
  );

  FutureOr<T?> _getTyped<T>(
    String path,
    T? Function(Object) convert, {
    String? repositoryId,
    T? defaultValue,
  }) {
    T? read(Object? value) {
      if (value == null) return defaultValue;
      final result = convert(value);
      if (result != null) return result;
      throw FormatException('L’attribut « $path » doit être de type $T.');
    }

    final value = getValue(path, repositoryId: repositoryId);
    return value is Future<Object?> ? value.then(read) : read(value);
  }
}

/// Façade typée des lectures synchrones d'un calcul.
///
/// Une dépendance async déjà en cache est accessible ; sinon une
/// [FormatException] explicite invite à utiliser les getters asynchrones.
class SynchronousCalculatedAttributeContext {
  SynchronousCalculatedAttributeContext._(this._context);
  final CalculatedAttributeContext _context;

  T _immediate<T>(FutureOr<T> value) {
    if (value is Future<T>) {
      value.ignore();
      throw const FormatException(
        'Dépendance asynchrone indisponible : utilisez await ctx.getValue/get…().',
      );
    }
    return value;
  }

  /// Lit immédiatement une valeur, ou signale une dépendance asynchrone.
  Object? getValue(String path, {String? repositoryId}) =>
      _immediate(_context.getValue(path, repositoryId: repositoryId));

  /// Lit immédiatement une chaîne nullable.
  String? getString(
    String path, {
    String? repositoryId,
    String? defaultValue,
  }) => _immediate(
    _context.getString(
      path,
      repositoryId: repositoryId,
      defaultValue: defaultValue,
    ),
  );

  /// Lit immédiatement un nombre nullable.
  num? getNum(String path, {String? repositoryId, num? defaultValue}) =>
      _immediate(
        _context.getNum(
          path,
          repositoryId: repositoryId,
          defaultValue: defaultValue,
        ),
      );

  /// Lit immédiatement un entier nullable.
  int? getInt(String path, {String? repositoryId, int? defaultValue}) =>
      _immediate(
        _context.getInt(
          path,
          repositoryId: repositoryId,
          defaultValue: defaultValue,
        ),
      );

  /// Lit immédiatement un double nullable.
  double? getDouble(
    String path, {
    String? repositoryId,
    double? defaultValue,
  }) => _immediate(
    _context.getDouble(
      path,
      repositoryId: repositoryId,
      defaultValue: defaultValue,
    ),
  );

  /// Lit immédiatement un booléen nullable.
  bool? getBool(String path, {String? repositoryId, bool? defaultValue}) =>
      _immediate(
        _context.getBool(
          path,
          repositoryId: repositoryId,
          defaultValue: defaultValue,
        ),
      );

  /// Lit immédiatement un tableau nullable d'objets JSON à clés chaînes.
  List<Map<String, Object?>>? getList(
    String path, {
    String? repositoryId,
    List<Map<String, Object?>>? defaultValue,
  }) => _immediate(
    _context.getList(
      path,
      repositoryId: repositoryId,
      defaultValue: defaultValue,
    ),
  );

  /// Lit immédiatement un objet JSON nullable sous forme de Map.
  Map<String, Object?>? getObject(
    String path, {
    String? repositoryId,
    Map<String, Object?>? defaultValue,
  }) => _immediate(
    _context.getObject(
      path,
      repositoryId: repositoryId,
      defaultValue: defaultValue,
    ),
  );
}

typedef _Key = ({String repositoryId, String path});

class _Calculation {
  _Calculation(this.key, this.scope, {this.isJs = false}) {
    completion.future.ignore();
  }

  final _Key key;
  final String scope;
  final bool isJs;
  final completion = Completer<Object?>();
  final dependencies = <_Key>{};
  final documents = <String, FutureOr<Object?>>{};
  bool stale = false;
  bool settled = false;
  bool asynchronous = false;
  Object? value;
  Object? error;
  StackTrace? stack;
}

/// Runtime des calculs et de leurs dépendances, isolé par store.
///
/// Une entrée contient une génération, son résultat (ou erreur) et les
/// dépendances collectées, même pendant une attente asynchrone.
class CalculatedAttributeEngine {
  /// Construit un moteur autonome pour un seul document (API du lot 1).
  CalculatedAttributeEngine(
    Map<String, CalculatedAttributeFunction> functions, {
    required Object? Function() document,
    required this._onAsyncValue,
    JsCalculatedEvaluator? jsEvaluator,
  }) : _document = ((_) => document()),
       _injectedJsEvaluator = jsEvaluator {
    registerRepository('', functions);
  }

  /// Construit le moteur partagé par les repositories d'un store.
  CalculatedAttributeEngine.forStore({
    required this._document,
    required this._onAsyncValue,
    JsCalculatedEvaluator? jsEvaluator,
  }) : _injectedJsEvaluator = jsEvaluator;

  final FutureOr<Object?> Function(String) _document;
  final void Function() _onAsyncValue;
  final JsCalculatedEvaluator? _injectedJsEvaluator;
  JsCalculatedEvaluator? _ownedJsEvaluator;
  final _dartDefinitions = <String, Map<String, CalculatedAttributeFunction>>{};
  final _jsDefinitions = <String, Map<String, CalculatedAttributeDefinition>>{};
  final _runs = <_Key, _Calculation>{};
  bool _disposed = false;

  JsCalculatedEvaluator get _jsEvaluator =>
      _injectedJsEvaluator ??
      (_ownedJsEvaluator ??= QuickJsCalculatedEvaluator());

  /// Valide un nom de calcul, sans `@`.
  static String validateName(String name) {
    if (!RegExp(r'^[a-zA-Z0-9_]{1,64}$').hasMatch(name)) {
      throw FormatException('Nom d’attribut calculé invalide : « $name ».');
    }
    return name;
  }

  /// Nom du segment calculé, ou `null` pour un chemin JSON ordinaire.
  static String? calculatedNameOf(String path) =>
      JsonAttributePath(path).calculated?.name;

  /// Canonise un scope de ligne source, éventuellement imbriqué.
  static String validateScope(String scope) {
    final path = JsonAttributePath(scope);
    if (path.calculated != null || !path.toString().endsWith('[?]')) {
      throw const FormatException(
        'Le scope doit désigner une ligne JSON, par exemple articles[?].',
      );
    }
    return path.toString();
  }

  /// Enregistre les fonctions Dart sans les exécuter ni écraser les formules JS.
  void registerRepository(
    String repositoryId,
    Map<String, CalculatedAttributeFunction> functions,
  ) {
    final normalized = <String, CalculatedAttributeFunction>{
      for (final entry in functions.entries)
        entry.key.contains('@') ? entry.key : '@${entry.key}': entry.value,
    };
    final existingJs = _jsDefinitions[repositoryId];
    if (existingJs != null) {
      for (final key in normalized.keys) {
        if (existingJs.containsKey(key)) {
          throw FormatException(
            'Collision entre l’attribut calculé Dart « $key » et une formule JS existante.',
          );
        }
      }
    }
    _dartDefinitions[repositoryId] = normalized;
    invalidateForChange('', repositoryId: repositoryId);
  }

  /// Enregistre ou remplace les attributs calculés JavaScript de [repositoryId].
  ///
  /// Préserve les fonctions Dart déjà déclarées et refuse toute collision de chemin.
  void registerJsAttributes(
    String repositoryId,
    Iterable<CalculatedAttributeDefinition> definitions,
  ) {
    final next = <String, CalculatedAttributeDefinition>{};
    final dartDefs = _dartDefinitions[repositoryId];
    for (final def in definitions) {
      def.validate();
      final key = def.path;
      if (next.containsKey(key)) {
        throw FormatException(
          'Attribut calculé JS en double dans « $repositoryId » : $key.',
        );
      }
      if (dartDefs != null && dartDefs.containsKey(key)) {
        throw FormatException(
          'L’attribut calculé « $key » est déjà défini en Dart dans ce repository.',
        );
      }
      next[key] = def;
    }
    if (next.isEmpty) {
      _jsDefinitions.remove(repositoryId);
    } else {
      _jsDefinitions[repositoryId] = next;
    }
    invalidateForChange('', repositoryId: repositoryId);
  }

  /// Supprime uniquement les attributs calculés JavaScript de [repositoryId].
  void clearJsAttributes(String repositoryId) {
    if (_jsDefinitions.remove(repositoryId) != null) {
      invalidateForChange('', repositoryId: repositoryId);
    }
  }

  /// Retourne les définitions JavaScript enregistrées pour [repositoryId].
  List<CalculatedAttributeDefinition> jsAttributesOf(String repositoryId) =>
      List<CalculatedAttributeDefinition>.unmodifiable(
        _jsDefinitions[repositoryId]?.values ?? const [],
      );

  /// Retire toutes les définitions (Dart et JS) et invalide leurs lecteurs.
  void unregisterRepository(String repositoryId) {
    _dartDefinitions.remove(repositoryId);
    _jsDefinitions.remove(repositoryId);
    (_injectedJsEvaluator ?? _ownedJsEvaluator)?.invalidateDocument(
      repositoryId,
    );
    invalidateForChange('', repositoryId: repositoryId);
  }

  /// Catalogue immuable des définitions, sans calcul.
  List<CalculatedAttributeDescriptor> catalog(String repositoryId) =>
      List.unmodifiable([
        for (final key in _dartDefinitions[repositoryId]?.keys ?? <String>[])
          if (JsonAttributePath(key).calculated case final part?)
            CalculatedAttributeDescriptor(
              name: part.name,
              scope: part.scope.isEmpty ? null : part.scope,
              source: CalculatedAttributeSource.dart,
            ),
        for (final def in _jsDefinitions[repositoryId]?.values ??
            <CalculatedAttributeDefinition>[])
          CalculatedAttributeDescriptor(
            name: def.name,
            scope: def.scope,
            source: CalculatedAttributeSource.js,
            description: def.description,
          ),
      ]);

  /// Indique si un chemin calculé correspond à une définition enregistrée.
  bool contains(String path, {String repositoryId = ''}) =>
      _definition(repositoryId, _normalize(path)) != null;

  String _normalize(String path) =>
      JsonTextBinding.isCalculatedPath(path) ? path : '@$path';

  ({
    CalculatedAttributeFunction? dartFn,
    CalculatedAttributeDefinition? jsDef,
  })?
  _definition(String repositoryId, String path) {
    final parsed = JsonAttributePath(path);
    final part = parsed.calculated;
    if (part == null) return null;
    final concrete = JsonAttributePath(part.path);
    for (final entry
        in _dartDefinitions[repositoryId]?.entries ??
            <MapEntry<String, CalculatedAttributeFunction>>[]) {
      if (JsonAttributePath(entry.key).matches(concrete)) {
        return (dartFn: entry.value, jsDef: null);
      }
    }
    for (final entry
        in _jsDefinitions[repositoryId]?.entries ??
            <MapEntry<String, CalculatedAttributeDefinition>>[]) {
      if (JsonAttributePath(entry.key).matches(concrete)) {
        return (dartFn: null, jsDef: entry.value);
      }
    }
    return null;
  }

  /// Lecture synchrone opportuniste, ou `null` si indisponible/en erreur.
  ({Object? value})? peek(String path, {String repositoryId = ''}) {
    try {
      final result = _readValue(repositoryId, _normalize(path));
      if (result is Future<Object?>) {
        result.ignore();
        return null;
      }
      return (value: result);
    } on FormatException {
      return null;
    }
  }

  /// Attend la valeur de la génération courante, jamais une valeur périmée.
  Future<Object?> read(String path, {String repositoryId = ''}) async =>
      _readValue(repositoryId, _normalize(path));

  FutureOr<Object?> _readValue(
    String repositoryId,
    String path, {
    _Calculation? caller,
  }) {
    if (_disposed) {
      throw const FormatException('Le moteur de calcul est fermé.');
    }
    final parsed = JsonAttributePath(path)..requireResolved();
    final part = parsed.calculated;
    final key = (
      repositoryId: repositoryId,
      path: part?.path ?? parsed.toString(),
    );
    caller?.dependencies.add(key);
    if (part == null) {
      if (caller == null) {
        throw const FormatException('Un chemin calculé est requis.');
      }
      final document = _getDocument(caller, repositoryId);
      Object? read(Object? root) => _freeze(parsed.readNode(root));
      return document is Future<Object?> ? document.then(read) : read(document);
    }
    if (caller != null && _reaches(key, caller.key, {})) {
      throw FormatException(
        'Cycle d’attributs calculés : ${caller.key.repositoryId}:${caller.key.path}'
        ' -> $repositoryId:${part.path}.',
      );
    }
    final result = _compute(key, part.scope, part.name);
    Object? read(Object? value) =>
        part.suffix == null ? value : part.suffix!.readNode(value);
    return result is Future<Object?> ? result.then(read) : read(result);
  }

  bool _reaches(_Key from, _Key to, Set<_Key> visited) {
    if (from == to) return true;
    if (!visited.add(from)) return false;
    return _runs[from]?.dependencies.any((dep) => _reaches(dep, to, visited)) ??
        false;
  }

  FutureOr<Object?> _getDocument(_Calculation run, String repositoryId) =>
      run.documents.putIfAbsent(repositoryId, () => _document(repositoryId));

  FutureOr<Object?> _compute(_Key key, String scope, String name) {
    final cached = _runs[key];
    if (cached != null) return _result(cached);
    final definition = _definition(key.repositoryId, key.path);
    if (definition == null) {
      throw FormatException('Attribut calculé « ${key.path} » introuvable.');
    }
    final run = _Calculation(key, scope, isJs: definition.dartFn == null);
    _runs[key] = run;
    try {
      final document = _getDocument(run, key.repositoryId);
      FutureOr<Object?> invoke(Object? root) {
        final parent = scope.isEmpty
            ? root
            : JsonAttributePath(scope).readNode(root);
        if (parent is! Map<String, Object?>) {
          throw const FormatException(
            'Le scope calculé doit être un objet JSON.',
          );
        }
        if (parent.containsKey('@$name')) {
          throw FormatException(
            'Collision entre la clé JSON et le calcul « @$name ».',
          );
        }
        final context = CalculatedAttributeContext._(this, run);
        if (definition.dartFn case final dartFn?) {
          return dartFn(context);
        }
        return _jsEvaluator.evaluate(
          code: definition.jsDef!.code,
          scopeData: parent,
          rootData: root,
          context: context,
        );
      }

      final result = document is Future<Object?>
          ? document.then(invoke)
          : invoke(document);
      if (result is Future<Object?>) {
        run.asynchronous = true;
        result.then<void>(
          (value) => _settle(run, value),
          onError: (Object error, StackTrace stack) => _fail(run, error, stack),
        );
      } else {
        _settle(run, result);
      }
    } catch (error, stack) {
      _fail(run, error, stack);
    }
    return _result(run);
  }

  /// Évalue ponctuellement une formule JS sans l'enregistrer ni la mettre en cache.
  ///
  /// Utile dans l'éditeur pour tester une expression avant sauvegarde.
  Future<Object?> evaluateAdHocJs({
    required String repositoryId,
    required CalculatedAttributeDefinition definition,
    List<int> indices = const [],
  }) async {
    if (_disposed) {
      throw const FormatException('Le moteur de calcul est fermé.');
    }
    definition.validate();
    final scope = definition.scope == null
        ? ''
        : JsonAttributePath(definition.scope!).resolve(indices).toString();
    final concretePath = scope.isEmpty
        ? '@${definition.name}'
        : '$scope.@${definition.name}';
    final run = _Calculation(
      (repositoryId: repositoryId, path: concretePath),
      scope,
    );
    final root = await _getDocument(run, repositoryId);
    final parent = scope.isEmpty
        ? root
        : JsonAttributePath(scope).readNode(root);
    if (parent is! Map<String, Object?>) {
      throw const FormatException('Le scope calculé doit être un objet JSON.');
    }
    if (parent.containsKey('@${definition.name}')) {
      throw FormatException(
        'Collision entre la clé JSON et le calcul « @${definition.name} ».',
      );
    }
    final result = await _jsEvaluator.evaluate(
      code: definition.code,
      scopeData: parent,
      rootData: root,
      context: CalculatedAttributeContext._(this, run),
    );
    return _freeze(result);
  }

  FutureOr<Object?> _result(_Calculation run) {
    if (!run.settled) return run.completion.future;
    if (run.error case final error?) {
      Error.throwWithStackTrace(error, run.stack!);
    }
    return run.value;
  }

  void _settle(_Calculation run, Object? value) {
    if (run.stale || _disposed) return;
    try {
      run.value = _freeze(value);
      run.settled = true;
      _notify(run);
      run.completion.complete(run.value);
    } catch (error, stack) {
      _fail(run, error, stack);
    }
  }

  void _fail(_Calculation run, Object error, StackTrace stack) {
    if (run.stale || _disposed) return;
    final formatted = error is FormatException
        ? error
        : FormatException(
            'Échec du calcul de « ${run.key.path} » '
            '(${error.runtimeType}).',
          );
    run.error = formatted;
    run.stack = stack;
    run.settled = true;
    final isJsFailure = run.isJs || error is JsCalculationException;
    VibeDebugCapture.recordTypedError(
      message: isJsFailure
          ? '[JS ERROR] Calcul « ${run.key.path} » : ${formatted.message}'
          : 'Calcul « ${run.key.path} » : ${formatted.message}',
      category: isJsFailure
          ? DebugErrorCategory.javascript
          : DebugErrorCategory.binding,
      severity: isJsFailure ? DebugSeverity.critical : DebugSeverity.error,
      stackTrace: stack,
      source: 'CalculatedAttribute(${run.key.repositoryId}:${run.key.path})',
    );
    _notify(run);
    run.completion.completeError(run.error!, stack);
  }

  void _notify(_Calculation run) {
    if (!run.asynchronous) return;
    scheduleMicrotask(() {
      if (!_disposed && !run.stale && identical(_runs[run.key], run)) {
        _onAsyncValue();
      }
    });
  }

  /// Invalide les dépendances touchées et leurs lecteurs transitifs.
  ///
  /// Un chemin vide concerne tout le repository. Sans [repositoryId], agit
  /// sur le document du moteur autonome.
  void invalidateForChange(String changedPath, {String repositoryId = ''}) {
    (_injectedJsEvaluator ?? _ownedJsEvaluator)?.invalidateDocument(
      repositoryId,
    );
    final path = changedPath.isEmpty
        ? ''
        : JsonAttributePath(changedPath).toString();
    _invalidate({
      for (final run in _runs.values)
        if ((!run.settled && run.documents.containsKey(repositoryId)) ||
            (run.key.repositoryId == repositoryId &&
                (path.isEmpty ||
                    (run.scope.isNotEmpty && _ancestor(path, run.scope)))) ||
            run.dependencies.any(
              (dep) =>
                  dep.repositoryId == repositoryId &&
                  (path.isEmpty || _overlaps(path, dep.path)),
            ))
          run.key,
    });
  }

  /// Invalide tous les résultats du store.
  void invalidateAll() {
    (_injectedJsEvaluator ?? _ownedJsEvaluator)?.invalidateDocument();
    _invalidate(_runs.keys.toSet());
  }

  /// Invalide un calcul précis et tous ses lecteurs.
  void invalidateCalculation(String repositoryId, String path) {
    final parsed = JsonAttributePath(path)..requireResolved();
    final part = parsed.calculated;
    if (part == null) {
      throw const FormatException('Un chemin calculé est requis.');
    }
    _invalidate({(repositoryId: repositoryId, path: part.path)});
  }

  void _invalidate(Set<_Key> keys) {
    var changed = true;
    while (changed) {
      changed = false;
      for (final run in _runs.values) {
        if (!keys.contains(run.key) && run.dependencies.any(keys.contains)) {
          keys.add(run.key);
          changed = true;
        }
      }
    }
    final invalidated = <_Calculation>[];
    for (final key in keys) {
      final run = _runs.remove(key);
      if (run != null) {
        run.stale = true;
        invalidated.add(run);
      }
    }
    for (final run in invalidated) {
      if (run.settled) continue;
      // Reconnecter les lecteurs sans attendre la terminaison du vieux Future.
      scheduleMicrotask(() {
        Future<Object?>.sync(() {
          if (_disposed) {
            throw const FormatException('Le moteur de calcul est fermé.');
          }
          return _readValue(run.key.repositoryId, run.key.path);
        }).then(run.completion.complete, onError: run.completion.completeError);
      });
    }
  }

  static bool _ancestor(String parent, String child) =>
      parent == child ||
      child.startsWith('$parent.') ||
      child.startsWith('$parent[');

  static bool _overlaps(String a, String b) =>
      _ancestor(a, b) || _ancestor(b, a);

  static Object? _freeze(Object? value) => switch (value) {
    Map<String, dynamic>() => Map<String, Object?>.unmodifiable({
      for (final entry in value.entries) entry.key: _freeze(entry.value),
    }),
    Map() => Map<Object?, Object?>.unmodifiable({
      for (final entry in value.entries) entry.key: _freeze(entry.value),
    }),
    List() => List<Object?>.unmodifiable(value.map(_freeze)),
    _ => value,
  };

  /// Termine les attentes et ignore toute publication ultérieure.
  void dispose() {
    _disposed = true;
    for (final run in _runs.values) {
      run.stale = true;
      if (!run.completion.isCompleted) {
        run.completion.completeError(
          const FormatException('Le moteur de calcul est fermé.'),
        );
      }
    }
    _runs.clear();
    _dartDefinitions.clear();
    _jsDefinitions.clear();
    _ownedJsEvaluator?.dispose();
    _ownedJsEvaluator = null;
  }
}
