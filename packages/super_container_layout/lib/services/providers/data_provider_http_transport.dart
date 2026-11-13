/// Transport HTTP injectable des providers de données.
///
/// [DataProviderHttpTransport] isole l'accès réseau de `HttpDataProvider` :
/// les tests injectent un transport simulé, l'application utilise
/// [DartIoDataProviderHttpTransport] (`dart:io`). Le transport réel ne suit
/// aucune redirection, borne la taille de la réponse et le temps total, et
/// traduit les erreurs réseau en [DataProviderException] sans jamais citer
/// l'URL complète (elle peut contenir un secret issu de `{{env.NOM}}`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart' show immutable;

import '../../models/providers/data_provider.dart' show DataProviderException;

/// Taille maximale par défaut d'un corps de réponse (10 Mio).
const defaultDataProviderMaxResponseBytes = 10 * 1024 * 1024;

/// Requête HTTP à envoyer par un [DataProviderHttpTransport].
@immutable
class DataProviderHttpRequest {
  /// Crée une requête [method] vers [uri] ; [body] est du texte (JSON) encodé
  /// en UTF-8 par le transport.
  const DataProviderHttpRequest({
    required this.method,
    required this.uri,
    this.headers = const <String, String>{},
    this.body,
    this.timeout = const Duration(seconds: 30),
    this.maxResponseBytes = defaultDataProviderMaxResponseBytes,
  });

  /// Méthode HTTP (`GET` ou `POST`).
  final String method;

  /// Adresse complète, paramètres de requête compris.
  final Uri uri;

  /// En-têtes de la requête.
  final Map<String, String> headers;

  /// Corps texte de la requête, ou `null`.
  final String? body;

  /// Durée maximale de l'échange complet (connexion, envoi, réponse).
  final Duration timeout;

  /// Taille maximale acceptée pour le corps de la réponse, en octets.
  final int maxResponseBytes;
}

/// Réponse HTTP complète d'un [DataProviderHttpTransport].
@immutable
class DataProviderHttpResponse {
  /// Crée une réponse de statut [statusCode] et de corps [body].
  const DataProviderHttpResponse({
    required this.statusCode,
    required this.body,
  });

  /// Code de statut HTTP.
  final int statusCode;

  /// Corps de la réponse décodé en UTF-8.
  final String body;
}

/// Abstraction injectable du transport HTTP utilisée par `HttpDataProvider`.
abstract class DataProviderHttpTransport {
  /// Constructeur de base pour les implémentations de transport.
  const DataProviderHttpTransport();

  /// Envoie [request] et retourne la réponse complète, quel que soit son
  /// statut HTTP.
  ///
  /// Lève une [DataProviderException] si l'échange échoue (réseau, TLS,
  /// délai dépassé, réponse trop volumineuse).
  Future<DataProviderHttpResponse> send(DataProviderHttpRequest request);

  /// Libère les ressources sous-jacentes éventuelles du transport.
  void close({bool force = false}) {}
}

/// Implémentation de [DataProviderHttpTransport] fondée sur `dart:io`.
class DartIoDataProviderHttpTransport extends DataProviderHttpTransport {
  /// Crée un transport `dart:io` ; [httpClient] permet d'injecter un client
  /// configuré (proxy, certificats de test).
  DartIoDataProviderHttpTransport({HttpClient? httpClient})
    : _injectedClient = httpClient;

  /// Délai maximal d'établissement d'une connexion.
  static const Duration connectionTimeout = Duration(seconds: 15);

  final HttpClient? _injectedClient;
  HttpClient? _ownedClient;

  HttpClient _ensureClient() {
    final injected = _injectedClient;
    if (injected != null) return injected;
    return _ownedClient ??= HttpClient()..connectionTimeout = connectionTimeout;
  }

  @override
  Future<DataProviderHttpResponse> send(DataProviderHttpRequest request) async {
    HttpClientRequest? pending;
    var expired = false;
    try {
      return await _exchange(
        request,
        onRequest: (value) => pending = value,
        isExpired: () => expired,
      ).timeout(request.timeout);
    } on TimeoutException {
      expired = true;
      pending?.abort();
      throw DataProviderException(
        'Délai de ${request.timeout.inSeconds} s dépassé '
        '(${request.uri.host}).',
      );
    } on SocketException catch (error) {
      final osMessage = error.osError?.message.trim() ?? '';
      final reason = osMessage.isEmpty ? error.message.trim() : osMessage;
      throw DataProviderException(
        'Connexion impossible à ${request.uri.host}'
        '${reason.isEmpty ? '' : ' : $reason'}.',
      );
    } on TlsException {
      throw DataProviderException(
        'Échec de la connexion sécurisée (TLS) à ${request.uri.host}.',
      );
    } on HttpException catch (error) {
      throw DataProviderException(
        'Réponse HTTP invalide de ${request.uri.host} : ${error.message}.',
      );
    } on FormatException {
      throw const DataProviderException(
        'La requête contient un en-tête invalide.',
      );
    }
  }

  Future<DataProviderHttpResponse> _exchange(
    DataProviderHttpRequest request, {
    required void Function(HttpClientRequest) onRequest,
    required bool Function() isExpired,
  }) async {
    final client = _ensureClient();
    final httpRequest = await client.openUrl(request.method, request.uri);
    onRequest(httpRequest);
    httpRequest.followRedirects = false;
    request.headers.forEach(httpRequest.headers.set);
    final payload = request.body;
    if (payload != null) {
      final bytes = utf8.encode(payload);
      httpRequest.contentLength = bytes.length;
      httpRequest.add(bytes);
    } else if (request.method == 'POST') {
      httpRequest.contentLength = 0;
    }
    final response = await httpRequest.close();
    if (response.contentLength > request.maxResponseBytes) {
      throw _tooLarge(request);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (isExpired()) {
        throw TimeoutException('Délai dépassé', request.timeout);
      }
      builder.add(chunk);
      if (builder.length > request.maxResponseBytes) throw _tooLarge(request);
    }
    return DataProviderHttpResponse(
      statusCode: response.statusCode,
      body: utf8.decode(builder.takeBytes(), allowMalformed: true),
    );
  }

  DataProviderException _tooLarge(DataProviderHttpRequest request) {
    final limit = request.maxResponseBytes;
    final text = limit >= 1024 * 1024
        ? '${limit ~/ (1024 * 1024)} Mio'
        : '$limit octets';
    return DataProviderException('Réponse trop volumineuse (plus de $text).');
  }

  @override
  void close({bool force = false}) {
    _ownedClient?.close(force: force);
    _ownedClient = null;
  }
}
