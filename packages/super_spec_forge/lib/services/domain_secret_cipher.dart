/// Chiffrement AES-256-GCM des secrets du catalogue avec une clé conservée
/// dans le coffre sécurisé natif du système ([DomainSecretCipher]).
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Contrat minimal du stockage système de la clé de chiffrement.
abstract interface class DomainSecretKeyStorage {
  /// Lit la clé encodée, ou `null` si elle n'a pas encore été créée.
  Future<String?> readKey();

  /// Persiste la clé encodée dans le coffre sécurisé.
  Future<void> writeKey(String encodedKey);
}

/// Adaptateur vers le coffre sécurisé natif de Flutter.
class FlutterDomainSecretKeyStorage implements DomainSecretKeyStorage {
  /// Crée l'adaptateur, injectable pour les tests.
  FlutterDomainSecretKeyStorage({
    this._storage = const FlutterSecureStorage(),
  });

  static const String _keyName = 'super_spec_forge.domain_catalog.aes256gcm';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readKey() => _storage.read(key: _keyName);

  @override
  Future<void> writeKey(String encodedKey) =>
      _storage.write(key: _keyName, value: encodedKey);
}

/// Chiffre et déchiffre les valeurs de secrets sans écrire la clé sur disque.
class DomainSecretCipher {
  /// Crée le chiffreur avec un stockage sécurisé système injectable.
  DomainSecretCipher({DomainSecretKeyStorage? keyStorage})
    : _keyStorage = keyStorage ?? FlutterDomainSecretKeyStorage();

  static const String _prefix = 'v1:';
  static final AesGcm _algorithm = AesGcm.with256bits();
  final DomainSecretKeyStorage _keyStorage;

  /// Chiffre [clearText] avec AES-256-GCM et retourne une enveloppe versionnée.
  Future<String> encrypt(String clearText) async {
    final secretKey = await _loadOrCreateKey();
    final box = await _algorithm.encrypt(
      utf8.encode(clearText),
      secretKey: secretKey,
    );
    return '$_prefix${base64Encode(box.concatenation())}';
  }

  /// Déchiffre une enveloppe produite par [encrypt].
  Future<String> decrypt(String encryptedValue) async {
    if (!encryptedValue.startsWith(_prefix)) {
      throw const FormatException('Format de secret chiffré inconnu.');
    }
    final bytes = base64Decode(encryptedValue.substring(_prefix.length));
    final box = SecretBox.fromConcatenation(
      bytes,
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clearBytes = await _algorithm.decrypt(
      box,
      secretKey: await _loadOrCreateKey(createIfMissing: false),
    );
    return utf8.decode(clearBytes);
  }

  Future<SecretKey> _loadOrCreateKey({bool createIfMissing = true}) async {
    final stored = await _keyStorage.readKey();
    if (stored != null) {
      final bytes = base64Decode(stored);
      if (bytes.length != 32) {
        throw const FormatException('La clé de chiffrement stockée est invalide.');
      }
      return SecretKey(bytes);
    }
    if (!createIfMissing) {
      throw StateError('Clé de chiffrement introuvable ; impossible de déchiffrer.');
    }
    final key = await _algorithm.newSecretKey();
    final bytes = await key.extractBytes();
    await _keyStorage.writeKey(base64Encode(bytes));
    return SecretKey(bytes);
  }
}
