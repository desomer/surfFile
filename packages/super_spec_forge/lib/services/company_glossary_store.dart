/// Persistance locale du glossaire terminologique d'entreprise ([CompanyGlossaryStore]).
///
/// Stocke le glossaire global dans un découpage adapté à Git :
/// - `<rootDirectory>/glossary/glossary.json` (conventions, ambiguïtés, date) ;
/// - `<rootDirectory>/glossary/terms/<slug>.json` (1 fichier par terme + `_order.json`) ;
/// - `<rootDirectory>/glossary/chat.json` (historique du chat IA dédié).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/company_glossary.dart';
import '../models/spec_stage_chat.dart';
import 'spec_project_store.dart';
import 'spec_storage_slug.dart';

/// Magasin disque persistant le [CompanyGlossary] et son historique IA.
class CompanyGlossaryStore {
  /// Crée un store ancré sur [rootDirectory] (ou `~/.super_spec_forge` par défaut).
  CompanyGlossaryStore([Directory? rootDirectory])
    : rootDirectory = rootDirectory ?? SpecProjectStore.defaultRootDirectory();

  /// Identifiant de format du fichier glossaire principal.
  static const String glossaryFormat = 'super_spec_forge.company_glossary';

  /// Identifiant de format d'un fichier terme unitaire.
  static const String termFormat = 'super_spec_forge.company_glossary_term';

  /// Identifiant de format d'un fichier d'ordre `_order.json`.
  static const String orderFormat = 'super_spec_forge.order';

  /// Identifiant de format du fichier chat du glossaire.
  static const String chatFormat = 'super_spec_forge.company_glossary_chat';

  /// Version courante du format persisté.
  static const int storageVersion = 3;

  /// Dossier racine du workspace.
  final Directory rootDirectory;

  Future<void> _opQueue = Future<void>.value();
  int _tmpCounter = 0;

  /// Sous-dossier `glossary/`.
  Directory get glossaryDirectory =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}glossary');

  /// Sous-dossier `glossary/terms/`.
  Directory get termsDirectory =>
      Directory('${glossaryDirectory.path}${Platform.pathSeparator}terms');

  /// Fichier principal `glossary/glossary.json` (conventions et ambiguïtés).
  File get glossaryFile =>
      File('${glossaryDirectory.path}${Platform.pathSeparator}glossary.json');

  /// Fichier `glossary/terms/_order.json`.
  File get termsOrderFile =>
      File('${termsDirectory.path}${Platform.pathSeparator}_order.json');

  /// Fichier `glossary/chat.json`.
  File get chatFile =>
      File('${glossaryDirectory.path}${Platform.pathSeparator}chat.json');

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final prev = _opQueue;
    final completer = Completer<void>();
    final next = prev.catchError((_) {}).then((_) => action());
    _opQueue = completer.future;
    return next.whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
  }

  /// Charge le glossaire d'entreprise depuis le disque (retourne [CompanyGlossary.empty] si absent).
  Future<CompanyGlossary> loadGlossary() => _enqueue(() async {
    final hasMain = await glossaryFile.exists();
    final hasTermsDir = await termsDirectory.exists();
    if (!hasMain && !hasTermsDir) {
      return CompanyGlossary.empty;
    }

    var conventions = const <String>[];
    var ambiguousTerms = const <String>[];
    DateTime? updatedAt;

    if (hasMain) {
      final raw = jsonDecode(await glossaryFile.readAsString());
      if (raw is! Map) {
        throw const FormatException(
          'glossary/glossary.json doit être un objet JSON.',
        );
      }
      final payload = raw['data'] is Map ? raw['data'] as Map : raw;
      conventions = [
        if (payload['conventions'] is List)
          for (final item in payload['conventions'] as List)
            if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
      ambiguousTerms = [
        if (payload['ambiguousTerms'] is List)
          for (final item in payload['ambiguousTerms'] as List)
            if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
      final rawUpdatedAt = payload['updatedAt'];
      if (rawUpdatedAt is String && rawUpdatedAt.trim().isNotEmpty) {
        updatedAt = DateTime.tryParse(rawUpdatedAt)?.toUtc();
      }
    }

    final terms = await _loadTerms();
    return CompanyGlossary(
      terms: terms,
      conventions: conventions,
      ambiguousTerms: ambiguousTerms,
      updatedAt: updatedAt,
    );
  });

  Future<List<CompanyGlossaryTerm>> _loadTerms() async {
    if (!await termsDirectory.exists()) return const <CompanyGlossaryTerm>[];
    final files = <File>[];
    await for (final entity in termsDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = SpecStorageIo.fileNameOf(entity.path);
      if (name.contains('.tmp.') ||
          name == '_order.json' ||
          !name.toLowerCase().endsWith('.json')) {
        continue;
      }
      files.add(entity);
    }
    files.sort(
      (a, b) => SpecStorageIo.fileNameOf(a.path)
          .toLowerCase()
          .compareTo(SpecStorageIo.fileNameOf(b.path).toLowerCase()),
    );

    final parsed = await Future.wait<CompanyGlossaryTerm>(
      files.map((file) async {
        final decoded = jsonDecode(await file.readAsString());
        final payload = (decoded is Map && decoded['data'] is Map)
            ? decoded['data']
            : decoded;
        return CompanyGlossaryTerm.fromJson(payload);
      }),
    );

    if (!await termsOrderFile.exists()) return parsed;
    try {
      final rawOrder = jsonDecode(await termsOrderFile.readAsString());
      final ids = rawOrder is Map ? rawOrder['ids'] : null;
      if (ids is! List) return parsed;
      final byId = <String, CompanyGlossaryTerm>{
        for (final term in parsed) term.id: term,
      };
      final ordered = <CompanyGlossaryTerm>[];
      final placed = <String>{};
      for (final rawId in ids) {
        if (rawId is! String) continue;
        final item = byId[rawId];
        if (item != null && placed.add(rawId)) {
          ordered.add(item);
        }
      }
      for (final term in parsed) {
        if (placed.add(term.id)) {
          ordered.add(term);
        }
      }
      return ordered;
    } catch (_) {
      return parsed;
    }
  }

  /// Sauvegarde incrémentalement et atomiquement [glossary] sur disque.
  Future<void> saveGlossary(CompanyGlossary glossary) {
    glossary.validate();
    return _enqueue(() async {
      await SpecStorageIo.writeJsonAtomicallyIfChanged(
        glossaryFile,
        <String, Object?>{
          'format': glossaryFormat,
          'version': storageVersion,
          'data': <String, Object?>{
            'conventions': glossary.conventions,
            'ambiguousTerms': glossary.ambiguousTerms,
            if (glossary.updatedAt != null)
              'updatedAt': glossary.updatedAt!.toUtc().toIso8601String(),
          },
        },
        nextTmpId: () => _tmpCounter++,
      );

      final fileMap = SpecStorageSlug.assignUniqueJsonFiles<CompanyGlossaryTerm>(
        glossary.terms,
        labelFor: (t) => t.term,
        idFor: (t) => t.id,
        fallback: 'term',
        separator: '-',
      );

      final keepFiles = <String>{...fileMap.keys};
      final writes = <Future<bool>>[];
      if (glossary.terms.isNotEmpty) {
        keepFiles.add('_order.json');
        writes.add(
          SpecStorageIo.writeJsonAtomicallyIfChanged(
            termsOrderFile,
            <String, Object?>{
              'format': orderFormat,
              'version': storageVersion,
              'ids': [for (final t in glossary.terms) t.id],
            },
            nextTmpId: () => _tmpCounter++,
          ),
        );
      }

      for (final entry in fileMap.entries) {
        writes.add(
          SpecStorageIo.writeJsonAtomicallyIfChanged(
            File('${termsDirectory.path}${Platform.pathSeparator}${entry.key}'),
            <String, Object?>{
              'format': termFormat,
              'version': storageVersion,
              'data': entry.value.toJson(),
            },
            nextTmpId: () => _tmpCounter++,
          ),
        );
      }

      if (writes.isNotEmpty) {
        await Future.wait(writes);
      }
      await SpecStorageIo.pruneUnexpectedFiles(termsDirectory, keepFiles);
    });
  }

  /// Charge l'historique du chat IA dédié au glossaire d'entreprise.
  Future<List<SpecChatMessage>> loadChatMessages() => _enqueue(() async {
    if (!await chatFile.exists()) {
      return const <SpecChatMessage>[];
    }
    final raw = jsonDecode(await chatFile.readAsString());
    if (raw is! Map) {
      return const <SpecChatMessage>[];
    }
    final rawItems = raw['items'];
    if (rawItems is! List) {
      return const <SpecChatMessage>[];
    }
    return List<SpecChatMessage>.unmodifiable([
      for (final item in rawItems) SpecChatMessage.fromJson(item),
    ]);
  });

  /// Sauvegarde atomiquement l'historique [messages] du chat IA du glossaire.
  Future<void> saveChatMessages(List<SpecChatMessage> messages) => _enqueue(
    () async {
      await SpecStorageIo.writeJsonAtomicallyIfChanged(
        chatFile,
        <String, Object?>{
          'format': chatFormat,
          'version': storageVersion,
          'items': [for (final m in messages) m.toJson()],
        },
        nextTmpId: () => _tmpCounter++,
      );
    },
  );
}
