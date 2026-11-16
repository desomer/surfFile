/// Exceptions métier et techniques du package `super_backend`.
///
/// Toutes les erreurs prévisibles (collection ou identifiant invalide,
/// entité introuvable, conflit d'identifiant, requête mal formée ou JSON
/// invalide) héritent de [SuperBackendException] avec un code stable et un
/// code HTTP indicatif facilitant le diagnostic et le mapping vers une couche
/// distante ou `DatasourceConfig`.
library;

/// Exception de base levée par `super_backend`.
class SuperBackendException implements Exception {
  /// Crée une exception métier avec un [code] stable, un [message] lisible
  /// et un [statusCode] indicatif.
  const SuperBackendException({
    required this.code,
    required this.message,
    this.statusCode = 500,
    this.cause,
  });

  /// Code d'erreur machine stable (ex. `entity_not_found`).
  final String code;

  /// Message explicatif lisible par l'utilisateur ou le développeur.
  final String message;

  /// Code de statut indicatif (400, 404, 409, 500…).
  final int statusCode;

  /// Cause sous-jacente éventuelle.
  final Object? cause;

  /// Représentation JSON sérialisable de l'erreur.
  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'statusCode': statusCode,
  };

  @override
  String toString() => 'SuperBackendException($code, $statusCode): $message';
}

/// Levée lorsque le nom d'une collection est vide ou contient des caractères
/// non autorisés.
class InvalidCollectionException extends SuperBackendException {
  /// Crée une erreur pour le nom de collection [collection].
  const InvalidCollectionException(String collection)
    : super(
        code: 'invalid_collection',
        message:
            'Nom de collection invalide « $collection » : lettres, chiffres, '
            '« _ » et « - » attendus (1 à 64 caractères).',
        statusCode: 400,
      );
}

/// Levée lorsque l'identifiant d'entité est vide, trop long ou contient des
/// caractères de contrôle.
class InvalidEntityIdException extends SuperBackendException {
  /// Crée une erreur pour l'identifiant [entityId].
  const InvalidEntityIdException(String entityId)
    : super(
        code: 'invalid_entity_id',
        message:
            'Identifiant d’entité invalide « $entityId » : chaîne non vide '
            'de 1 à 256 caractères sans caractère de contrôle attendue.',
        statusCode: 400,
      );
}

/// Levée lorsque la charge utile JSON d'une entité n'est pas valide ou ne
/// peut pas être encodée en objet JSON.
class InvalidJsonPayloadException extends SuperBackendException {
  /// Crée une erreur de charge utile JSON.
  const InvalidJsonPayloadException(String message, {super.cause})
    : super(code: 'invalid_json_payload', message: message, statusCode: 400);
}

/// Levée lorsque les paramètres de recherche, de tri, de filtrage ou de
/// pagination sont invalides.
class InvalidQueryException extends SuperBackendException {
  /// Crée une erreur de requête invalide.
  const InvalidQueryException(String message, {super.cause})
    : super(code: 'invalid_query', message: message, statusCode: 400);
}

/// Levée lorsqu'une entité demandée (`read`, `update`, `delete`) n'existe pas
/// dans la collection ciblée.
class EntityNotFoundException extends SuperBackendException {
  /// Crée une erreur « entité introuvable » pour [collection] et [entityId].
  const EntityNotFoundException({
    required this.collection,
    required this.entityId,
  }) : super(
         code: 'entity_not_found',
         message:
             'Entité « $entityId » introuvable dans la collection '
             '« $collection ».',
         statusCode: 404,
       );

  /// Collection ciblée.
  final String collection;

  /// Identifiant d'entité recherché.
  final String entityId;
}

/// Levée lors d'une création (`create`) avec un identifiant déjà présent dans
/// la collection (sans `upsert: true`).
class EntityAlreadyExistsException extends SuperBackendException {
  /// Crée une erreur de conflit pour [collection] et [entityId].
  const EntityAlreadyExistsException({
    required this.collection,
    required this.entityId,
  }) : super(
         code: 'entity_already_exists',
         message:
             'L’entité « $entityId » existe déjà dans la collection '
             '« $collection ».',
         statusCode: 409,
       );

  /// Collection ciblée.
  final String collection;

  /// Identifiant déjà occupé.
  final String entityId;
}

/// Levée lorsqu'une opération est appelée sur un store non initialisé ou déjà
/// fermé.
class BackendNotInitializedException extends SuperBackendException {
  /// Crée une erreur d'état de cycle de vie du store.
  const BackendNotInitializedException([
    String message = 'Le store backend doit être initialisé via init() et ne pas être fermé.',
  ]) : super(
         code: 'backend_not_initialized',
         message: message,
         statusCode: 500,
       );
}
