/// Modèles immuables de statut et de variantes pour le chargement dynamique de polices.
///
/// Utilisés par [DynamicFontManager], [GoogleFontsDownloader], [PdfFontResolver] et
/// les composants UI (`DesignSystemCatalogDialog`, éditeurs de typographie) pour suivre
/// la disponibilité et les fichiers `.ttf`/`.otf` mis en cache pour chaque famille.
library;

import 'package:flutter/foundation.dart' show immutable, listEquals;

/// État de disponibilité d'une famille de polices dans le moteur `super_container_layout`.
enum DynamicFontStatus {
  /// Police libre (SIL OFL) embarquée directement dans les assets du package.
  bundled,

  /// Police système ou déclarée nativement dans la liste par défaut du registre.
  system,

  /// Police téléchargée ou rechargée depuis le cache disque et enregistrée via `FontLoader`.
  loaded,

  /// Téléchargement ou chargement depuis le cache en cours.
  loading,

  /// Police introuvable sur Google Fonts (ex. police propriétaire ou nom inconnu).
  notFound,

  /// Échec réseau, format binaire invalide ou erreur d'enregistrement temporaire.
  failed;

  /// Indique si la police est prête à être utilisée au rendu Flutter.
  bool get isAvailable =>
      this == bundled || this == system || this == loaded;

  /// Indique si un téléchargement ou réessai peut être tenté.
  bool get canDownload => this == notFound || this == failed;
}

/// Métadonnées immuables d'un fichier de variante typographique stocké en cache.
@immutable
class DynamicFontVariantFile {
  /// Crée une description de variante typographique pour [fileName].
  const DynamicFontVariantFile({
    required this.fileName,
    this.weight = 400,
    this.italic = false,
  });

  /// Nom du fichier `.ttf`/`.otf` relatif au dossier de cache de la famille.
  final String fileName;

  /// Graisse numérique OpenType (`100`..`900`, `400` par défaut).
  final int weight;

  /// Indique s'il s'agit d'une variante italique.
  final bool italic;

  /// Sérialise cette variante au format JSON pour `manifest.json`.
  Map<String, Object?> toJson() => <String, Object?>{
    'fileName': fileName,
    'weight': weight,
    'italic': italic,
  };

  /// Reconstruit une [DynamicFontVariantFile] depuis un objet JSON.
  factory DynamicFontVariantFile.fromJson(Map<String, Object?> json) {
    final fileName = (json['fileName'] as String? ?? '').trim();
    if (fileName.isEmpty) {
      throw const FormatException('fileName manquant dans DynamicFontVariantFile');
    }
    final rawWeight = json['weight'];
    final weight = rawWeight is num
        ? rawWeight.toInt().clamp(100, 900)
        : 400;
    final italic = json['italic'] == true;
    return DynamicFontVariantFile(
      fileName: fileName,
      weight: weight,
      italic: italic,
    );
  }

  /// Retourne une copie modifiée de cette variante.
  DynamicFontVariantFile copyWith({
    String? fileName,
    int? weight,
    bool? italic,
  }) => DynamicFontVariantFile(
    fileName: fileName ?? this.fileName,
    weight: weight ?? this.weight,
    italic: italic ?? this.italic,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DynamicFontVariantFile &&
          fileName == other.fileName &&
          weight == other.weight &&
          italic == other.italic;

  @override
  int get hashCode => Object.hash(fileName, weight, italic);
}

/// État suivi par [DynamicFontManager] pour une famille de polices donnée.
@immutable
class DynamicFontEntry {
  /// Crée une entrée d'état pour [family].
  DynamicFontEntry({
    required this.family,
    required this.status,
    List<DynamicFontVariantFile> variants = const [],
    this.cacheDirectoryPath,
    this.fromCache = false,
    this.error,
  }) : variants = List<DynamicFontVariantFile>.unmodifiable(variants);

  /// Nom canonique de la famille de polices (ex. `"Space Grotesk"`).
  final String family;

  /// État courant de la famille.
  final DynamicFontStatus status;

  /// Variantes `.ttf`/`.otf` associées dans le cache disque.
  final List<DynamicFontVariantFile> variants;

  /// Chemin absolu du dossier de cache disque contenant [variants], si présent.
  final String? cacheDirectoryPath;

  /// Indique si la police a été chargée depuis le cache disque sans appel réseau.
  final bool fromCache;

  /// Message d'erreur éventuel lorsque [status] vaut [DynamicFontStatus.failed] ou [DynamicFontStatus.notFound].
  final String? error;

  /// Retourne une copie mise à jour de cette entrée.
  DynamicFontEntry copyWith({
    String? family,
    DynamicFontStatus? status,
    List<DynamicFontVariantFile>? variants,
    String? cacheDirectoryPath,
    bool clearCacheDirectoryPath = false,
    bool? fromCache,
    String? error,
    bool clearError = false,
  }) => DynamicFontEntry(
    family: family ?? this.family,
    status: status ?? this.status,
    variants: variants ?? this.variants,
    cacheDirectoryPath: clearCacheDirectoryPath
        ? null
        : (cacheDirectoryPath ?? this.cacheDirectoryPath),
    fromCache: fromCache ?? this.fromCache,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DynamicFontEntry &&
          family == other.family &&
          status == other.status &&
          listEquals(variants, other.variants) &&
          cacheDirectoryPath == other.cacheDirectoryPath &&
          fromCache == other.fromCache &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
    family,
    status,
    Object.hashAll(variants),
    cacheDirectoryPath,
    fromCache,
    error,
  );
}

/// Résultat immuable d'une opération de chargement ou téléchargement de police.
@immutable
class DynamicFontLoadResult {
  /// Crée un résultat de chargement pour [family].
  const DynamicFontLoadResult({
    required this.family,
    required this.status,
    this.loadedFileCount = 0,
    this.fromCache = false,
    this.error,
  });

  /// Nom canonique de la famille demandée.
  final String family;

  /// Statut final après l'opération.
  final DynamicFontStatus status;

  /// Nombre de fichiers `.ttf`/`.otf` enregistrés pour cette famille.
  final int loadedFileCount;

  /// Indique si le chargement provenait du cache disque local.
  final bool fromCache;

  /// Message d'erreur éventuel.
  final String? error;

  /// Indique si la police est désormais disponible au rendu.
  bool get isAvailable => status.isAvailable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DynamicFontLoadResult &&
          family == other.family &&
          status == other.status &&
          loadedFileCount == other.loadedFileCount &&
          fromCache == other.fromCache &&
          error == other.error;

  @override
  int get hashCode =>
      Object.hash(family, status, loadedFileCount, fromCache, error);
}
