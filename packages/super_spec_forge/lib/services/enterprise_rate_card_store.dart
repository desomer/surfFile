/// Persistance locale et codec JSON de la grille tarifaire d'entreprise ([EnterpriseRateCardStore], [EnterpriseRateCardCodec]).
///
/// Stocke le référentiel FinOps global du workspace dans un fichier adapté à Git :
/// - `<rootDirectory>/enterprise_rates/rate_card.json`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/enterprise_rate_card.dart';
import 'spec_project_store.dart';
import 'spec_storage_slug.dart';

/// Magasin disque persistant la grille tarifaire d'entreprise ([EnterpriseRateCard])
/// à l'échelle globale du workspace.
class EnterpriseRateCardStore {
  /// Crée un store ancré sur [rootDirectory] (ou `~/.super_spec_forge` par défaut).
  EnterpriseRateCardStore([Directory? rootDirectory])
    : rootDirectory = rootDirectory ?? SpecProjectStore.defaultRootDirectory();

  /// Identifiant de format du fichier JSON de la grille tarifaire d'entreprise.
  static const String fileFormat = 'super_spec_forge.enterprise_rate_card';

  /// Version courante du format persisté.
  static const int storageVersion = 1;

  /// Dossier racine du workspace.
  final Directory rootDirectory;

  Future<void> _opQueue = Future<void>.value();
  int _tmpCounter = 0;

  /// Sous-dossier `enterprise_rates/`.
  Directory get ratesDirectory => Directory(
    '${rootDirectory.path}${Platform.pathSeparator}enterprise_rates',
  );

  /// Alias vers le sous-dossier `enterprise_rates/`.
  Directory get enterpriseRatesDirectory => ratesDirectory;

  /// Fichier JSON de la grille tarifaire (`enterprise_rates/rate_card.json`).
  File get rateCardFile =>
      File('${ratesDirectory.path}${Platform.pathSeparator}rate_card.json');

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

  /// Charge la grille tarifaire d'entreprise depuis le disque
  /// (retourne [EnterpriseRateCard.defaults] si le fichier est absent).
  Future<EnterpriseRateCard> load() => _enqueue(() async {
    if (!await rateCardFile.exists()) {
      return EnterpriseRateCard.defaults;
    }
    final raw = jsonDecode(await rateCardFile.readAsString());
    if (raw is! Map) {
      throw const FormatException(
        'enterprise_rates/rate_card.json doit être un objet JSON.',
      );
    }
    return _decodeFromMap(raw);
  });

  /// Valide et sauvegarde atomiquement [card] sur disque uniquement si son contenu a changé.
  Future<void> save(EnterpriseRateCard card) {
    card.validate();
    return _enqueue(() async {
      await SpecStorageIo.writeJsonAtomicallyIfChanged(
        rateCardFile,
        <String, Object?>{
          'format': fileFormat,
          'version': storageVersion,
          'data': card.toJson(),
        },
        nextTmpId: () => _tmpCounter++,
      );
    });
  }

  /// Sérialise [card] en JSON indenté (LF + saut de ligne final) avec enveloppe `{format, version, data}`.
  static String encodePrettyJson(EnterpriseRateCard card) {
    card.validate();
    return SpecStorageIo.encodePrettyJson(<String, Object?>{
      'format': fileFormat,
      'version': storageVersion,
      'data': card.toJson(),
    });
  }

  /// Désérialise une chaîne JSON vers [EnterpriseRateCard] validée
  /// (supporte l'enveloppe `{format, version, data}` comme un objet direct).
  static EnterpriseRateCard decodeJsonString(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) {
      throw const FormatException(
        'Le contenu JSON de la grille tarifaire est vide.',
      );
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      throw const FormatException(
        'Le document JSON de la grille tarifaire doit être un objet.',
      );
    }
    return _decodeFromMap(decoded);
  }

  static EnterpriseRateCard _decodeFromMap(Map<dynamic, dynamic> raw) {
    final unwrapped = raw['data'] is Map ? raw['data'] as Map : raw;
    final Object payload =
        (!unwrapped.containsKey('notes') &&
            unwrapped['assumptionsNotes'] is String)
        ? <Object?, Object?>{
            ...unwrapped,
            'notes': unwrapped['assumptionsNotes'],
          }
        : unwrapped;
    final parsed = EnterpriseRateCard.fromJson(payload);
    parsed.validate();
    return parsed;
  }
}

/// Codec utilitaire d'import/export JSON pour [EnterpriseRateCard].
abstract final class EnterpriseRateCardCodec {
  /// Sérialise [card] en JSON indenté ré-importable.
  static String encodePrettyJson(EnterpriseRateCard card) =>
      EnterpriseRateCardStore.encodePrettyJson(card);

  /// Désérialise une chaîne JSON vers [EnterpriseRateCard] validée.
  static EnterpriseRateCard decodeJsonString(String rawJson) =>
      EnterpriseRateCardStore.decodeJsonString(rawJson);

  /// Alias d'export JSON aligné sur les autres codecs du workspace.
  static String toJsonString(EnterpriseRateCard card) =>
      EnterpriseRateCardStore.encodePrettyJson(card);

  /// Alias d'import JSON aligné sur les autres codecs du workspace.
  static EnterpriseRateCard parseJson(String rawJson) =>
      EnterpriseRateCardStore.decodeJsonString(rawJson);
}
