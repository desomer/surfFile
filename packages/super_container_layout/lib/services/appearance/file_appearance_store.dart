/// Service de persistance sur fichier ([FileAppearanceStore]) du document [Appearance].
///
/// Implémente [AppearanceStore] en lisant et en écrivant de manière atomique
/// un fichier JSON dédié (typiquement `appearance.json` dans le dossier d'une
/// application sandboxée), avec refus des liens symboliques et déport en `Isolate`
/// au-delà des seuils configurés.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate' show Isolate;
import 'dart:math';

import '../../models/json_numbers.dart';
import '../../theme/appearance.dart';
import 'appearance_store.dart';

Map<String, dynamic> _decodeFileAppearanceInIsolate(String text) {
  final json = jsonDecode(text);
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Document d’apparence invalide.');
  }
  return json;
}

({Map<String, dynamic> raw, String normalized})
_decodeAndNormalizeFileAppearanceInIsolate(String encoded) {
  final decoded = _decodeFileAppearanceInIsolate(encoded);
  final normalized = jsonEncode(JsonNumbers.normalize(decoded));
  return (raw: decoded, normalized: normalized);
}

Future<Map<String, dynamic>> _runDecodeFileAppearanceInIsolate(String text) =>
    Isolate.run(() => _decodeFileAppearanceInIsolate(text));

Future<({Map<String, dynamic> raw, String normalized})>
_runDecodeAndNormalizeFileAppearanceInIsolate(String encoded) =>
    Isolate.run(() => _decodeAndNormalizeFileAppearanceInIsolate(encoded));

/// Magasin d'apparence persistant le document JSON dans un [File] local.
class FileAppearanceStore extends AppearanceStore {
  /// Crée un magasin lisant et écrivant l'apparence dans [file].
  FileAppearanceStore(
    this.file, {
    super.codec,
    super.isolateThresholdBytes,
    super.isolateThresholdEntries,
    this.maxFileBytes = defaultMaxFileBytes,
  }) : super(key: file.path);

  /// Taille maximale autorisée lors de la lecture de [file] (32 Mo).
  static const int defaultMaxFileBytes = 32 * 1024 * 1024;

  /// Fichier JSON cible sur disque (ex. `<appDir>/appearance.json`).
  final File file;

  /// Taille maximale autorisée à la lecture.
  final int maxFileBytes;

  Future<void> _queue = Future<void>.value();

  Future<R> _serial<R>(Future<R> Function() action) {
    final completer = Completer<R>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> _ensureSafeTarget({required bool createParent}) async {
    final parentType = await FileSystemEntity.type(
      file.parent.path,
      followLinks: false,
    );
    if (parentType == FileSystemEntityType.link) {
      throw FileSystemException(
        'Le dossier d’apparence ne peut pas être un lien symbolique.',
        file.parent.path,
      );
    }
    if (parentType == FileSystemEntityType.notFound) {
      if (createParent) {
        await file.parent.create(recursive: true);
      }
    } else if (parentType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Le parent du fichier d’apparence n’est pas un dossier.',
        file.parent.path,
      );
    }

    final targetType = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );
    if (targetType == FileSystemEntityType.link) {
      throw FileSystemException(
        'Le fichier d’apparence ne peut pas être un lien symbolique.',
        file.path,
      );
    }
    if (targetType != FileSystemEntityType.notFound &&
        targetType != FileSystemEntityType.file) {
      throw FileSystemException(
        'La cible d’apparence n’est pas un fichier.',
        file.path,
      );
    }
  }

  Future<String?> _readStoredText() async {
    await _ensureSafeTarget(createParent: false);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    final stat = await file.stat();
    if (stat.size > maxFileBytes) {
      throw FileSystemException(
        'Le fichier d’apparence dépasse la taille maximale autorisée.',
        file.path,
      );
    }
    return file.readAsString(encoding: utf8);
  }

  Future<void> _writeAtomically(String normalized) async {
    await _ensureSafeTarget(createParent: true);
    final suffix = List.generate(
      12,
      (_) => Random().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temp = File('${file.path}.$pid.$suffix.tmp');
    await temp.create(exclusive: true);
    try {
      await temp.writeAsString(normalized, encoding: utf8, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await FileSystemEntity.type(temp.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await temp.delete();
      }
    }
  }

  @override
  Future<Appearance> load() async {
    final stored = await _serial(_readStoredText);
    if (stored == null || stored.trim().isEmpty) {
      codec.resetAdditional();
      return codec.defaults;
    }

    final Appearance result;
    if (stored.length >= isolateThresholdBytes) {
      final decoded = await _runDecodeFileAppearanceInIsolate(stored);
      result = codec.fromJson(decoded);
    } else {
      result = codec.decode(stored);
    }
    codec.restoreAdditional(stored);
    if (codec.needsMigration(stored)) {
      await save(result);
    }
    return result;
  }

  @override
  Future<void> saveEncoded(String encoded) async {
    final String normalized;
    if (encoded.length >= isolateThresholdBytes) {
      final parsed = await _runDecodeAndNormalizeFileAppearanceInIsolate(
        encoded,
      );
      codec.fromJson(parsed.raw);
      normalized = parsed.normalized;
    } else {
      final decoded = _decodeFileAppearanceInIsolate(encoded);
      codec.fromJson(decoded);
      normalized = jsonEncode(JsonNumbers.normalize(decoded));
    }
    await _serial(() => _writeAtomically(normalized));
  }
}
