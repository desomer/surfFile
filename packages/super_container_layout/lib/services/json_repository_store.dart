import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/json_text_binding.dart';

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
  Future<void> _pending = Future.value();
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

  void reportBindingError(String message) {
    if (!_disposed) errors.value = message;
  }

  @override
  void dispose() {
    _disposed = true;
    errors.dispose();
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
        binding.validate();
        final root = _decode(await read(await _nameOf(binding.repositoryId)));
        final value = JsonAttributePath(binding.path).read(root);
        return (value: value, text: value?.toString() ?? '');
      });

  Future<JsonAttributeValue> writeAttribute(
    JsonTextBinding binding,
    String text, {
    required Object? expectedValue,
  }) => _exclusive(() async {
    binding.validate();
    final name = await _nameOf(binding.repositoryId);
    final original = await read(name);
    final root = _decode(original);
    final path = JsonAttributePath(binding.path);
    if (path.read(root) != expectedValue) {
      throw const FormatException(
        'L’attribut lié a été modifié. Rechargez la liaison avant de réessayer.',
      );
    }
    final updated = path.write(root, text, expectedValue);
    await _save(
      name,
      '${const JsonEncoder.withIndent('  ').convert(updated)}\n',
      expectedText: original,
    );
    final value = path.read(updated);
    return (value: value, text: value?.toString() ?? '');
  });

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
}
