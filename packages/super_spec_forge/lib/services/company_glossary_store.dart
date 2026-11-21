/// Persistance locale du glossaire terminologique d'entreprise ([CompanyGlossaryStore]).
///
/// Stocke le glossaire global dans `<rootDirectory>/company_glossary.json` et
/// l'historique du chat IA dédié dans `<rootDirectory>/company_glossary_chat.json`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/company_glossary.dart';
import '../models/spec_stage_chat.dart';
import 'spec_project_store.dart';

/// Magasin disque persistant le [CompanyGlossary] et son historique IA.
class CompanyGlossaryStore {
  /// Crée un store ancré sur [rootDirectory] (ou `~/.super_spec_forge` par défaut).
  CompanyGlossaryStore([Directory? rootDirectory])
    : rootDirectory = rootDirectory ?? SpecProjectStore.defaultRootDirectory();

  /// Identifiant de format du fichier glossaire.
  static const String glossaryFormat = 'super_spec_forge.company_glossary';

  /// Identifiant de format du fichier chat du glossaire.
  static const String chatFormat = 'super_spec_forge.company_glossary_chat';

  /// Version du format persisté.
  static const int storageVersion = 1;

  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

  /// Dossier racine du magasin.
  final Directory rootDirectory;

  Future<void> _opQueue = Future<void>.value();
  int _tmpCounter = 0;

  File get glossaryFile =>
      File('${rootDirectory.path}${Platform.pathSeparator}company_glossary.json');

  File get chatFile => File(
    '${rootDirectory.path}${Platform.pathSeparator}company_glossary_chat.json',
  );

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
    if (!await glossaryFile.exists()) {
      return CompanyGlossary.empty;
    }
    final raw = jsonDecode(await glossaryFile.readAsString());
    if (raw is! Map) {
      throw const FormatException(
        'company_glossary.json doit être un objet JSON.',
      );
    }
    final payload = raw['data'] is Map ? raw['data'] : raw;
    return CompanyGlossary.fromJson(payload);
  });

  /// Sauvegarde atomiquement [glossary] sur disque.
  Future<void> saveGlossary(CompanyGlossary glossary) {
    glossary.validate();
    return _enqueue(() async {
      await _writeJsonAtomically(glossaryFile, <String, Object?>{
        'format': glossaryFormat,
        'version': storageVersion,
        'data': glossary.toJson(),
      });
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
      await _writeJsonAtomically(chatFile, <String, Object?>{
        'format': chatFormat,
        'version': storageVersion,
        'items': [for (final m in messages) m.toJson()],
      });
    },
  );

  Future<void> _writeJsonAtomically(
    File target,
    Map<String, Object?> payload,
  ) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp.${_tmpCounter++}');
    await tmp.writeAsString(_prettyEncoder.convert(payload), flush: true);
    await tmp.rename(target.path);
  }
}
