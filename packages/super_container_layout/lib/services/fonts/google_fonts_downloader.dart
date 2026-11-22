/// Client de téléchargement Google Fonts CSS2 (`dart:io`) pour `super_container_layout`.
///
/// Interroge `fonts.googleapis.com/css2` avec un `User-Agent` retournant des fichiers
/// TrueType (`.ttf`) statiques pour les graisses courantes (`300`..`700`) et italiques,
/// applique 3 niveaux de repli en cas de famille mono-poids ou sans italique, et valide
/// les signatures binaires TTF/OTF avant livraison à [DynamicFontManager].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Réponse HTTP binaire minimale utilisée par [GoogleFontsDownloader].
typedef FontHttpResponse = ({int statusCode, Uint8List bytes});

/// Fonction de transport HTTP GET injectable pour faciliter les tests sans réseau.
typedef FontHttpGet =
    Future<FontHttpResponse> Function(
      Uri uri, {
      Map<String, String>? headers,
    });

/// Variante de police téléchargée en mémoire avec sa graisse et son style italique.
class DownloadedFontVariant {
  /// Crée une variante téléchargée.
  const DownloadedFontVariant({
    required this.weight,
    required this.italic,
    required this.bytes,
    required this.extension,
  });

  /// Graisse OpenType (`100`..`900`).
  final int weight;

  /// Indique si la variante est italique.
  final bool italic;

  /// Octets bruts du fichier `.ttf`/`.otf`.
  final Uint8List bytes;

  /// Extension de fichier normalisée (`ttf` ou `otf`).
  final String extension;
}

/// Résultat brut d'une tentative de téléchargement auprès de Google Fonts.
class GoogleFontsDownloadResponse {
  /// Crée un résultat réussi contenant [variants].
  const GoogleFontsDownloadResponse.success(this.variants)
    : notFound = false,
      error = null;

  /// Crée un résultat indiquant que la police n'existe pas sur Google Fonts.
  const GoogleFontsDownloadResponse.notFound([this.error])
    : notFound = true,
      variants = const [];

  /// Crée un résultat d'échec réseau ou de parsing temporaire.
  const GoogleFontsDownloadResponse.failure(this.error)
    : notFound = false,
      variants = const [];

  /// Indique que la famille est absente du catalogue Google Fonts.
  final bool notFound;

  /// Variantes téléchargées et validées.
  final List<DownloadedFontVariant> variants;

  /// Message d'erreur éventuel.
  final String? error;

  /// Indique si au moins une variante valide a été téléchargée.
  bool get isSuccess => !notFound && error == null && variants.isNotEmpty;
}

/// Téléchargeur Google Fonts CSS2 sans dépendance externe.
class GoogleFontsDownloader {
  /// Crée un téléchargeur avec transport HTTP injectable optionnel [httpGet].
  GoogleFontsDownloader({
    this.httpGet,
    this.requestTimeout = const Duration(seconds: 10),
  });

  /// Taille maximale autorisée par fichier de police (10 Mo).
  static const int maxFontFileBytes = 10 * 1024 * 1024;

  /// Nombre maximal de variantes téléchargées pour une même famille.
  static const int maxVariantsPerFamily = 12;

  /// En-tête `User-Agent` non-WOFF2 incitant Google Fonts CSS2 à fournir des `.ttf`.
  static const String truetypeUserAgent = 'Dart/3.0 (dart:io)';

  /// Fonction HTTP GET optionnelle injectée pour les tests.
  final FontHttpGet? httpGet;

  /// Délai maximal d'une requête HTTP.
  final Duration requestTimeout;

  static final RegExp _fontFaceBlockPattern = RegExp(
    r'@font-face\s*\{([^}]*)\}',
    caseSensitive: false,
  );
  static final RegExp _fontStylePattern = RegExp(
    r'font-style\s*:\s*([a-zA-Z]+)',
    caseSensitive: false,
  );
  static final RegExp _fontWeightPattern = RegExp(
    r'font-weight\s*:\s*(\d{3})',
    caseSensitive: false,
  );
  static final RegExp _srcUrlPattern = RegExp(
    r'''url\(\s*['"]?(https://[^'"\s)]+)['"]?\s*\)(?:\s*format\(\s*['"]([^'"]+)['"]\s*\))?''',
    caseSensitive: false,
  );

  /// Construit les URLs CSS2 candidates par ordre décroissant de richesse de variantes.
  static List<Uri> buildCandidateCssUris(String family) {
    final encoded = Uri.encodeQueryComponent(family.trim());
    return [
      Uri.parse(
        'https://fonts.googleapis.com/css2?family=$encoded:ital,wght@0,300;0,400;0,500;0,600;0,700;1,400;1,700&display=swap',
      ),
      Uri.parse(
        'https://fonts.googleapis.com/css2?family=$encoded:wght@400;500;600;700&display=swap',
      ),
      Uri.parse(
        'https://fonts.googleapis.com/css2?family=$encoded&display=swap',
      ),
    ];
  }

  /// Vérifie si [bytes] commence par une signature TrueType / OpenType valide.
  static bool hasValidFontSignature(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final b0 = bytes[0];
    final b1 = bytes[1];
    final b2 = bytes[2];
    final b3 = bytes[3];
    // TrueType standard : 0x00 0x01 0x00 0x00
    if (b0 == 0x00 && b1 == 0x01 && b2 == 0x00 && b3 == 0x00) return true;
    // OpenType CFF : 'OTTO'
    if (b0 == 0x4F && b1 == 0x54 && b2 == 0x54 && b3 == 0x4F) return true;
    // Apple TrueType : 'true'
    if (b0 == 0x74 && b1 == 0x72 && b2 == 0x75 && b3 == 0x65) return true;
    // TrueType Collection : 'ttcf'
    if (b0 == 0x74 && b1 == 0x74 && b2 == 0x63 && b3 == 0x66) return true;
    return false;
  }

  /// Extrait les variantes (URL, graisse, italique) depuis une feuille CSS Google Fonts.
  static List<({Uri uri, int weight, bool italic, String extension})>
  parseCssFontFaces(String css) {
    final results = <({Uri uri, int weight, bool italic, String extension})>[];
    final seenUrls = <String>{};

    for (final block in _fontFaceBlockPattern.allMatches(css)) {
      final body = block.group(1) ?? '';
      final styleMatch = _fontStylePattern.firstMatch(body);
      final italic =
          (styleMatch?.group(1) ?? '').toLowerCase() == 'italic';
      final weightMatch = _fontWeightPattern.firstMatch(body);
      final weight = int.tryParse(weightMatch?.group(1) ?? '') ?? 400;

      for (final urlMatch in _srcUrlPattern.allMatches(body)) {
        final rawUrl = urlMatch.group(1)!.trim();
        final format = (urlMatch.group(2) ?? '').toLowerCase();
        final lowerUrl = rawUrl.toLowerCase();

        final isTrueType =
            format == 'truetype' || lowerUrl.endsWith('.ttf');
        final isOpenType =
            format == 'opentype' || lowerUrl.endsWith('.otf');
        if (!isTrueType && !isOpenType) continue;

        final uri = Uri.tryParse(rawUrl);
        if (uri == null || uri.scheme != 'https') continue;
        if (!seenUrls.add(rawUrl)) continue;

        results.add((
          uri: uri,
          weight: weight.clamp(100, 900),
          italic: italic,
          extension: isOpenType ? 'otf' : 'ttf',
        ));
        if (results.length >= maxVariantsPerFamily) {
          return results;
        }
      }
    }
    return results;
  }

  /// Télécharge les variantes TrueType/OpenType de [family] depuis Google Fonts.
  Future<GoogleFontsDownloadResponse> download(String family) async {
    final trimmed = family.trim();
    if (trimmed.isEmpty) {
      return const GoogleFontsDownloadResponse.notFound('Nom de police vide.');
    }

    String? cssContent;
    var allNotFound = true;
    String? lastError;

    for (final uri in buildCandidateCssUris(trimmed)) {
      try {
        final response = await _get(
          uri,
          headers: const <String, String>{
            'User-Agent': truetypeUserAgent,
            'Accept': 'text/css,*/*;q=0.1',
          },
        );
        if (response.statusCode == 200) {
          cssContent = utf8.decode(response.bytes, allowMalformed: true);
          allNotFound = false;
          break;
        }
        if (response.statusCode == 400 || response.statusCode == 404) {
          continue;
        }
        allNotFound = false;
        lastError = 'HTTP ${response.statusCode} lors de la requête Google Fonts.';
        break;
      } catch (error) {
        allNotFound = false;
        lastError = 'Erreur réseau Google Fonts : $error';
        break;
      }
    }

    if (cssContent == null) {
      if (allNotFound) {
        return GoogleFontsDownloadResponse.notFound(
          'Police « $trimmed » introuvable sur Google Fonts.',
        );
      }
      return GoogleFontsDownloadResponse.failure(
        lastError ?? 'Impossible de joindre Google Fonts.',
      );
    }

    final descriptors = parseCssFontFaces(cssContent);
    if (descriptors.isEmpty) {
      return GoogleFontsDownloadResponse.failure(
        'Aucune variante TrueType/OpenType exploitable trouvée pour « $trimmed ».',
      );
    }

    final downloaded = <DownloadedFontVariant>[];
    String? binaryError;

    for (final descriptor in descriptors) {
      try {
        final response = await _get(
          descriptor.uri,
          headers: const <String, String>{'User-Agent': truetypeUserAgent},
        );
        if (response.statusCode != 200) {
          binaryError = 'HTTP ${response.statusCode} sur ${descriptor.uri.path}';
          continue;
        }
        final bytes = response.bytes;
        if (bytes.length > maxFontFileBytes || !hasValidFontSignature(bytes)) {
          binaryError = 'Fichier de police invalide ou trop volumineux.';
          continue;
        }
        downloaded.add(
          DownloadedFontVariant(
            weight: descriptor.weight,
            italic: descriptor.italic,
            bytes: bytes,
            extension: descriptor.extension,
          ),
        );
      } catch (error) {
        binaryError = 'Échec du téléchargement d’une variante : $error';
      }
    }

    if (downloaded.isEmpty) {
      return GoogleFontsDownloadResponse.failure(
        binaryError ?? 'Aucune variante valide téléchargée pour « $trimmed ».',
      );
    }

    return GoogleFontsDownloadResponse.success(downloaded);
  }

  Future<FontHttpResponse> _get(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final injected = httpGet;
    if (injected != null) {
      return injected(uri, headers: headers);
    }
    final client = HttpClient()..connectionTimeout = requestTimeout;
    try {
      final request = await client.getUrl(uri).timeout(requestTimeout);
      headers?.forEach(request.headers.set);
      final response = await request.close().timeout(requestTimeout);
      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.timeout(requestTimeout)) {
        total += chunk.length;
        if (total > maxFontFileBytes) {
          throw const FormatException('Réponse HTTP trop volumineuse.');
        }
        builder.add(chunk);
      }
      return (statusCode: response.statusCode, bytes: builder.takeBytes());
    } finally {
      client.close(force: true);
    }
  }
}
