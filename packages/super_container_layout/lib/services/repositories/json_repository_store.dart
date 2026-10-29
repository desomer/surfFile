import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/json_text_binding.dart';
import '../../theme/appearance.dart';
import 'json_repository_binding.dart';

typedef JsonRepositoryEntry = ({String name, String id});
typedef JsonAttributeValue = ({Object? value, String text});

/// One repository is one named JSON file, without an application envelope.
class JsonRepositoryStore extends ChangeNotifier {
  JsonRepositoryStore(this.directory);

  factory JsonRepositoryStore.defaultStore() {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw FileSystemException('Dossier utilisateur introuvable.');
    }
    return JsonRepositoryStore(
      Directory(
        '$home${Platform.pathSeparator}.super_container_layout'
        '${Platform.pathSeparator}repositories',
      ),
    );
  }

  final Directory directory;
  final errors = ValueNotifier<String?>(null);

  final _bindings = <String, JsonRepositoryBinding>{};
  final _activeBindings = <Object, Set<String>>{};

  /// Runtime selections and bound components of [repositoryId]'s arrays.
  JsonRepositoryBinding bindingOf(String repositoryId) => _bindings.putIfAbsent(
    repositoryId,
    () => JsonRepositoryBinding(repositoryId),
  );

  /// Enregistre les identifiants de repositories utilisés par un bind actif [owner].
  void registerBindings(Object owner, Iterable<String?> repositoryIds) {
    final ids = {
      for (final id in repositoryIds)
        if (id != null && id.isNotEmpty) id,
    };
    if (ids.isEmpty) {
      _activeBindings.remove(owner);
    } else {
      _activeBindings[owner] = ids;
    }
  }

  /// Désenregistre les liaisons actives associées à [owner].
  void unregisterBindings(Object owner) => _activeBindings.remove(owner);

  /// Indique si [repositoryId] est actuellement utilisé par un bind actif du store.
  bool isRepositoryBound(String repositoryId) =>
      (_bindings[repositoryId]?.isBound ?? false) ||
      _activeBindings.values.any((ids) => ids.contains(repositoryId));

  /// Indique si le repository [name] est utilisé par un bind actif du store
  /// ou par une liaison configurée dans [appearance].
  Future<bool> isRepositoryInUse(String name, {Appearance? appearance}) =>
      _exclusive(() => _isRepositoryInUse(name, appearance: appearance));

  Future<bool> _isRepositoryInUse(String name, {Appearance? appearance}) async {
    final idFile = _idFile(name);
    if (await FileSystemEntity.type(idFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    final id = (await idFile.readAsString()).trim();
    if (id.isEmpty) return false;
    return isRepositoryBound(id) || (appearance?.usesRepository(id) ?? false);
  }
  Future<void> _pending = Future.value();
  final _flushers = <Future<void> Function()>{};
  bool _disposed = false;

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Live bindings register their pending-write flush here, so that a list
  /// can save drafts before it moves or removes array elements.
  void addFlusher(Future<void> Function() flush) => _flushers.add(flush);

  void removeFlusher(Future<void> Function() flush) => _flushers.remove(flush);

  Future<void> flushBindings() =>
      Future.wait([for (final flush in _flushers.toList()) flush()]);

  void reportBindingError(String message) {
    if (!_disposed) errors.value = message;
  }

  @override
  void dispose() {
    _disposed = true;
    errors.dispose();
    for (final binding in _bindings.values) {
      binding.dispose();
    }
    super.dispose();
  }

  static String validateName(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name.endsWith('.') ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
        RegExp(
          r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
          caseSensitive: false,
        ).hasMatch(name)) {
      throw const FormatException('Nom de repository invalide.');
    }
    return name;
  }

  File _file(String name) => File(
    '${directory.path}${Platform.pathSeparator}${validateName(name)}.json',
  );

  File _idFile(String name) => File('${_file(name).path}.id');

  /// Assigned once, outside the editable JSON, and preserved when renamed.
  /// Existing repositories receive their ID on first access.
  Future<String> idOf(String name) => _exclusive(() => _idOf(name));

  Future<String> _idOf(String name) async {
    await read(name);
    final file = _idFile(name);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await file.create(exclusive: true);
      await file.writeAsString(id, flush: true);
      return id;
    }
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Fichier d’identifiant invalide.', file.path);
    }
    final id = await file.readAsString();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const FormatException(
        'Identifiant technique corrompu : restaurez le fichier .json.id '
        'depuis une sauvegarde.',
      );
    }
    return id;
  }

  Future<List<String>> list() async {
    await directory.create(recursive: true);
    final names = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final filename = entity.uri.pathSegments.last;
      names.add(filename.substring(0, filename.length - 5));
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Future<List<JsonRepositoryEntry>> catalog() => _exclusive(_catalog);

  Future<List<JsonRepositoryEntry>> _catalog() async {
    final entries = <JsonRepositoryEntry>[];
    final ids = <String>{};
    for (final name in await list()) {
      final id = await _idOf(name);
      if (!ids.add(id)) {
        throw const FormatException('ID technique de repository dupliqué.');
      }
      entries.add((name: name, id: id));
    }
    return entries;
  }

  Future<String> _nameOf(String id) async {
    final matches = (await _catalog()).where((entry) => entry.id == id);
    if (matches.isEmpty) {
      throw const FormatException('Repository lié introuvable.');
    }
    return matches.single.name;
  }

  Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      // Parser diagnostics can contain repository data, including passwords.
      throw const FormatException('Le repository contient un JSON invalide.');
    }
  }

  Future<JsonAttributeValue> readAttribute(JsonTextBinding binding) =>
      _exclusive(() async {
        binding.validateResolved();
        final root = _decode(await read(await _nameOf(binding.repositoryId!)));
        final value = JsonAttributePath(binding.path).read(root);
        return (value: value, text: value?.toString() ?? '');
      });

  Future<JsonAttributeValue> writeAttribute(
    JsonTextBinding binding,
    String text, {
    required Object? expectedValue,
    bool asBool = false,
  }) => _exclusive(() async {
    binding.validateResolved();
    final name = await _nameOf(binding.repositoryId!);
    final original = await read(name);
    final root = _decode(original);
    final path = JsonAttributePath(binding.path);
    if (path.read(root) != expectedValue) {
      throw const FormatException(
        'L’attribut lié a été modifié. Rechargez la liaison avant de réessayer.',
      );
    }
    final updated = path.write(root, text, expectedValue, asBool: asBool);
    await _save(
      name,
      '${const JsonEncoder.withIndent('  ').convert(updated)}\n',
      expectedText: original,
    );
    final value = path.read(updated);
    return (value: value, text: value?.toString() ?? '');
  });

  /// Elements of the array at [path]; a missing attribute is an empty list.
  Future<List<Object?>> readArray(String repositoryId, String path) =>
      _exclusive(() async {
        final binding = JsonTextBinding(repositoryId: repositoryId, path: path)
          ..validateResolved();
        final root = _decode(await read(await _nameOf(repositoryId)));
        return List<Object?>.unmodifiable(
          _array(JsonAttributePath(binding.path).readNode(root)),
        );
      });

  static List<Object?> _array(Object? node) {
    if (node == null) return const [];
    if (node is! List) {
      throw const FormatException(
        'Le chemin de la liste doit désigner un tableau JSON.',
      );
    }
    return node;
  }

  /// Reads a JSON tree root at [path] (either a JSON array of node objects or
  /// a single root JSON object).
  Future<({List<Object?> nodes, bool singleRootObject})> readTreeNodes(
    String repositoryId,
    String path,
  ) => _exclusive(() async {
    final binding = JsonTextBinding(repositoryId: repositoryId, path: path)
      ..validateResolved();
    final root = _decode(await read(await _nameOf(repositoryId)));
    final node = JsonAttributePath(binding.path).readNode(root);
    if (node == null) {
      return (nodes: const <Object?>[], singleRootObject: false);
    }
    if (node is List) {
      return (
        nodes: List<Object?>.unmodifiable(node),
        singleRootObject: false,
      );
    }
    if (node is Map<String, dynamic>) {
      return (
        nodes: List<Object?>.unmodifiable([node]),
        singleRootObject: true,
      );
    }
    throw const FormatException(
      'Le chemin du TreeView doit désigner un tableau ou un objet JSON.',
    );
  });

  /// Appends a blank copy of the last element, or `{}` to an empty array.
  Future<int> appendArrayItem(
    String repositoryId,
    String path, {
    required int expectedLength,
  }) => _updateArray(repositoryId, path, (items) {
    if (items.length != expectedLength) _arrayConflict();
    return [...items, items.isEmpty ? <String, dynamic>{} : blank(items.last)];
  });

  Future<int> removeArrayItem(
    String repositoryId,
    String path,
    int index, {
    required Object? expectedItem,
  }) => _updateArray(repositoryId, path, (items) {
    if (index < 0 ||
        index >= items.length ||
        !jsonEquals(items[index], expectedItem)) {
      _arrayConflict();
    }
    return [...items]..removeAt(index);
  });

  static Never _arrayConflict() => throw const FormatException(
    'La liste a été modifiée. Rechargez-la avant de réessayer.',
  );

  Future<int> _updateArray(
    String repositoryId,
    String path,
    List<Object?> Function(List<Object?>) change,
  ) => _exclusive(() async {
    final binding = JsonTextBinding(repositoryId: repositoryId, path: path)
      ..validateResolved();
    final name = await _nameOf(repositoryId);
    final original = await read(name);
    final root = _decode(original);
    final attribute = JsonAttributePath(binding.path);
    final items = change(_array(attribute.readNode(root)));
    final updated = attribute.replaceNode(root, items);
    await _save(
      name,
      '${const JsonEncoder.withIndent('  ').convert(updated)}\n',
      expectedText: original,
    );
    return items.length;
  });

  /// Same structure with empty values: "", 0, false, [] and null.
  static Object? blank(Object? value) => switch (value) {
    String() => '',
    num() => 0,
    bool() => false,
    List() => <Object?>[],
    Map() => <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: blank(entry.value),
    },
    _ => null,
  };

  static bool jsonEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.entries.every(
            (entry) =>
                b.containsKey(entry.key) &&
                jsonEquals(entry.value, b[entry.key]),
          );
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!jsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  Future<void> _checkAvailable(String name) async {
    final normalized = validateName(name).toLowerCase();
    if ((await list()).any((entry) => entry.toLowerCase() == normalized) ||
        await FileSystemEntity.type(_file(name).path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        await FileSystemEntity.type(_idFile(name).path, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw const FormatException('Un repository porte déjà ce nom.');
    }
  }

  Future<String> read(String name) async {
    final file = _file(name);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Fichier JSON introuvable ou lien refusé.',
        file.path,
      );
    }
    return file.readAsString();
  }

  Future<void> create(String name) => _exclusive(() async {
    await _checkAvailable(name);
    await _file(name).create(exclusive: true);
    await _file(name).writeAsString('{}\n', flush: true);
    await _idOf(name);
    _changed();
  });

  Future<void> save(String name, String text, {required String expectedText}) =>
      _exclusive(() => _save(name, text, expectedText: expectedText));

  Future<void> _save(
    String name,
    String text, {
    required String expectedText,
  }) async {
    jsonDecode(text);
    if (await read(name) != expectedText) {
      throw const FormatException(
        'Le fichier a été modifié sur le disque. '
        'Copiez vos modifications puis rechargez le repository.',
      );
    }
    await _idOf(name);
    await _file(name).writeAsString(text, flush: true);
    _changed();
  }

  Future<void> rename(String name, String newName) => _exclusive(() async {
    final validated = validateName(newName);
    if (name == validated) return;
    await _checkAvailable(validated);
    await _idOf(name);
    final metadata = await _idFile(name).rename(_idFile(validated).path);
    try {
      await _file(name).rename(_file(validated).path);
    } on FileSystemException {
      await metadata.rename(_idFile(name).path);
      rethrow;
    }
    _changed();
  });

  Future<void> delete(String name, {Appearance? appearance}) =>
      _exclusive(() async {
        final validated = validateName(name);
        final file = _file(validated);
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw FileSystemException(
            'Fichier JSON introuvable ou lien refusé.',
            file.path,
          );
        }
        final idFile = _idFile(validated);
        final idType = await FileSystemEntity.type(
          idFile.path,
          followLinks: false,
        );
        if (idType != FileSystemEntityType.notFound &&
            idType != FileSystemEntityType.file) {
          throw FileSystemException(
            'Fichier d’identifiant invalide.',
            idFile.path,
          );
        }
        String? id;
        if (idType == FileSystemEntityType.file) {
          id = (await idFile.readAsString()).trim();
        }
        if (id != null &&
            id.isNotEmpty &&
            (isRepositoryBound(id) ||
                (appearance?.usesRepository(id) ?? false))) {
          throw FormatException(
            'Impossible de supprimer « $validated » : '
            'ce repository est encore utilisé par un bind de l’application.',
          );
        }
        await file.delete();
        if (idType == FileSystemEntityType.file) {
          await idFile.delete();
        }
        final binding = id == null ? null : _bindings[id];
        if (binding != null) {
          for (final array in binding.arrays) {
            array.clear();
          }
        }
        _changed();
      });
}
