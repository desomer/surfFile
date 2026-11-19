/// Modèle immuable de pièce jointe ([VibeChatAttachment]) pour le chat Vibe IA.
///
/// Encapsule un fichier image ou texte/JSON joint à un prompt dans [VibeChatDialog]
/// et transmis à [callGemini].
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter/services.dart';

/// Fichier (image ou texte) joint à un message du chat IA Vibe.
@immutable
class VibeChatAttachment {
  /// Crée une pièce jointe immuable à partir de ses métadonnées et octets.
  const VibeChatAttachment({
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.textContent,
    this.path,
  });

  /// Crée une pièce jointe texte à partir d'une chaîne de caractères.
  factory VibeChatAttachment.text({
    required String name,
    required String content,
    String? mimeType,
    String? path,
  }) {
    final resolvedMime = mimeType ?? _textMimeTypeForName(name) ?? 'text/plain';
    return VibeChatAttachment(
      name: name,
      mimeType: resolvedMime,
      bytes: Uint8List.fromList(utf8.encode(content)),
      textContent: content,
      path: path,
    );
  }

  /// Crée une pièce jointe image à partir de ses octets.
  factory VibeChatAttachment.image({
    required String name,
    required Uint8List bytes,
    String? mimeType,
    String? path,
  }) {
    final resolvedMime =
        mimeType ??
        _imageMimeTypeForName(name) ??
        _sniffImageMimeType(bytes) ??
        'image/png';
    return VibeChatAttachment(
      name: name,
      mimeType: resolvedMime,
      bytes: bytes,
      path: path,
    );
  }

  /// Nom d'affichage du fichier joint.
  final String name;

  /// Type MIME de la pièce jointe (ex. `image/png`, `application/json`).
  final String mimeType;

  /// Contenu binaire brut de la pièce jointe.
  final Uint8List bytes;

  /// Contenu texte décodé lorsque la pièce jointe est textuelle.
  final String? textContent;

  /// Chemin disque d'origine éventuel.
  final String? path;

  /// Indique si cette pièce jointe est une image.
  bool get isImage => mimeType.startsWith('image/');

  /// Indique si cette pièce jointe porte un contenu texte.
  bool get isText => textContent != null;

  /// Retourne une copie de cette pièce jointe avec un nouveau [name].
  VibeChatAttachment withName(String name) => VibeChatAttachment(
    name: name,
    mimeType: mimeType,
    bytes: bytes,
    textContent: textContent,
    path: path,
  );

  /// Taille maximale autorisée par pièce jointe encodée (20 Mo).
  static const int maxFileSizeBytes = 20 * 1024 * 1024;

  static const _imageMimeByExtension = <String, String>{
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.webp': 'image/webp',
    '.gif': 'image/gif',
    '.bmp': 'image/bmp',
  };

  static const _textMimeByExtension = <String, String>{
    '.txt': 'text/plain',
    '.text': 'text/plain',
    '.log': 'text/plain',
    '.md': 'text/markdown',
    '.markdown': 'text/markdown',
    '.json': 'application/json',
    '.jsonc': 'application/json',
    '.yaml': 'text/yaml',
    '.yml': 'text/yaml',
    '.csv': 'text/csv',
    '.xml': 'application/xml',
    '.svg': 'image/svg+xml',
    '.html': 'text/html',
    '.htm': 'text/html',
    '.css': 'text/css',
    '.dart': 'text/plain',
    '.js': 'text/javascript',
    '.mjs': 'text/javascript',
    '.jsx': 'text/javascript',
    '.ts': 'text/plain',
    '.tsx': 'text/plain',
    '.py': 'text/plain',
    '.sql': 'text/plain',
    '.ini': 'text/plain',
    '.cfg': 'text/plain',
    '.conf': 'text/plain',
    '.toml': 'text/plain',
    '.env': 'text/plain',
    '.sh': 'text/plain',
    '.ps1': 'text/plain',
    '.bat': 'text/plain',
    '.c': 'text/plain',
    '.cc': 'text/plain',
    '.cpp': 'text/plain',
    '.h': 'text/plain',
    '.hpp': 'text/plain',
    '.cs': 'text/plain',
    '.java': 'text/plain',
    '.kt': 'text/plain',
    '.kts': 'text/plain',
    '.go': 'text/plain',
    '.rs': 'text/plain',
    '.rb': 'text/plain',
    '.php': 'text/plain',
    '.swift': 'text/plain',
  };

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty);
    return segments.isEmpty ? path : segments.last;
  }

  static String? _extension(String name) {
    final base = _fileName(name);
    final dot = base.lastIndexOf('.');
    if (dot < 0) return null;
    return base.substring(dot).toLowerCase();
  }

  static String? _imageMimeTypeForName(String name) =>
      _imageMimeByExtension[_extension(name)];

  static String? _textMimeTypeForName(String name) =>
      _textMimeByExtension[_extension(name)];

  static String? _sniffImageMimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'image/bmp';
    }
    return null;
  }

  /// Charge un fichier image ou texte depuis [path].
  static Future<VibeChatAttachment> fromPath(String path) =>
      fromFile(File(path));

  /// Charge un fichier image ou texte depuis [file].
  static Future<VibeChatAttachment> fromFile(File file) async {
    final name = _fileName(file.path);
    if (!await file.exists()) {
      throw FormatException('Fichier introuvable : "$name".');
    }
    final length = await file.length();
    if (length > maxFileSizeBytes) {
      throw FormatException(
        'Le fichier "$name" dépasse la taille maximale autorisée (20 Mo).',
      );
    }
    final bytes = await file.readAsBytes();
    return fromBytes(bytes, name: name, path: file.path);
  }

  /// Crée une pièce jointe à partir d'octets bruts et d'un nom de fichier.
  static VibeChatAttachment fromBytes(
    Uint8List bytes, {
    required String name,
    String? path,
  }) {
    if (bytes.length > maxFileSizeBytes) {
      throw FormatException(
        'Le fichier "$name" dépasse la taille maximale autorisée (20 Mo).',
      );
    }
    final imageMime = _imageMimeTypeForName(name) ?? _sniffImageMimeType(bytes);
    if (imageMime != null) {
      return VibeChatAttachment(
        name: name,
        mimeType: imageMime,
        bytes: bytes,
        path: path,
      );
    }

    final knownTextMime = _textMimeTypeForName(name);
    if (_looksBinary(bytes)) {
      throw FormatException(
        'Format de fichier non pris en charge ("$name"). '
        'Importez une image (PNG, JPG, WEBP, GIF, BMP) ou un fichier texte.',
      );
    }

    final String decoded;
    try {
      decoded = utf8.decode(bytes);
    } on FormatException {
      if (knownTextMime != null) {
        return VibeChatAttachment(
          name: name,
          mimeType: knownTextMime,
          bytes: bytes,
          textContent: latin1.decode(bytes),
          path: path,
        );
      }
      throw FormatException(
        'Format de fichier non pris en charge ("$name"). '
        'Importez une image ou un fichier texte encodé en UTF-8.',
      );
    }

    return VibeChatAttachment(
      name: name,
      mimeType: knownTextMime ?? 'text/plain',
      bytes: bytes,
      textContent: decoded,
      path: path,
    );
  }

  static bool _looksBinary(Uint8List bytes) {
    final sampleLength = bytes.length < 4096 ? bytes.length : 4096;
    for (var i = 0; i < sampleLength; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  /// Ouvre le sélecteur de fichiers natif (sur Windows) et retourne les
  /// pièces jointes sélectionnées.
  static Future<List<VibeChatAttachment>> pickFiles() async {
    if (!Platform.isWindows) return const [];
    final paths = await Isolate.run(_pickFilesWin32);
    if (paths.isEmpty) return const [];
    final attachments = <VibeChatAttachment>[];
    for (final path in paths) {
      attachments.add(await fromPath(path));
    }
    return attachments;
  }

  /// Indique si le presse-papiers système contient actuellement des fichiers
  /// copiés (`CF_HDROP`) ou une image copiée en mémoire (capture d'écran,
  /// « Copier l'image » navigateur, éditeur graphique) sans écraser un collage
  /// de texte ordinaire lors d'un `Ctrl+V`.
  static bool hasClipboardImageOrFiles() {
    if (!Platform.isWindows) return false;
    return _hasClipboardImageOrFilesWin32();
  }

  /// Importe uniquement les fichiers copiés (`CF_HDROP`) ou l'image présente
  /// en mémoire dans le presse-papiers (sans repli sur le texte brut).
  ///
  /// Ordre de priorité :
  /// 1. Fichiers copiés dans l'explorateur Windows (`CF_HDROP`).
  /// 2. Image copiée en mémoire (`PNG`, `WEBP`, `JPEG`, `GIF`, `CF_DIBV5`, `CF_DIB` converti en PNG).
  static Future<List<VibeChatAttachment>> fromClipboardImagesOrFiles() async {
    if (!Platform.isWindows) return const [];

    final droppedPaths = _readClipboardFilesWin32();
    if (droppedPaths.isNotEmpty) {
      final attachments = <VibeChatAttachment>[];
      for (final path in droppedPaths) {
        if (await FileSystemEntity.isFile(path)) {
          attachments.add(await fromPath(path));
        }
      }
      if (attachments.isNotEmpty) return attachments;
    }

    final imageAttachment = await _readClipboardImageAttachment();
    if (imageAttachment != null) {
      return [imageAttachment];
    }
    return const [];
  }

  /// Importe des pièces jointes depuis le presse-papiers selon l'ordre :
  /// 1. Fichiers copiés dans l'explorateur Windows (`CF_HDROP`).
  /// 2. Image présente dans le presse-papiers (`PNG`, `WEBP`, `JPEG`, `GIF`, `CF_DIBV5`, `CF_DIB` converti en PNG).
  /// 3. Chemins de fichiers présents dans le texte du presse-papiers.
  /// 4. Contenu texte du presse-papiers comme pièce jointe texte/JSON.
  static Future<List<VibeChatAttachment>> fromClipboard() async {
    final media = await fromClipboardImagesOrFiles();
    if (media.isNotEmpty) return media;

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final rawText = data?.text;
    if (rawText == null || rawText.trim().isEmpty) {
      return const [];
    }

    final candidatePaths = _extractCandidatePaths(rawText);
    if (candidatePaths.isNotEmpty) {
      final existingFiles = <File>[];
      for (final candidate in candidatePaths) {
        final file = File(candidate);
        if (await file.exists()) {
          existingFiles.add(file);
        }
      }
      if (existingFiles.length == candidatePaths.length) {
        final attachments = <VibeChatAttachment>[];
        for (final file in existingFiles) {
          attachments.add(await fromFile(file));
        }
        return attachments;
      }
    }

    final trimmed = rawText.trim();
    final isJson =
        (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
    return [
      VibeChatAttachment.text(
        name: isJson ? 'presse-papiers.json' : 'presse-papiers.txt',
        content: rawText,
        mimeType: isJson ? 'application/json' : 'text/plain',
      ),
    ];
  }

  static String _defaultClipboardImageName(String mimeType) =>
      switch (mimeType) {
        'image/jpeg' => 'presse-papiers.jpg',
        'image/webp' => 'presse-papiers.webp',
        'image/gif' => 'presse-papiers.gif',
        _ => 'presse-papiers.png',
      };

  static void _ensureMaxSize(Uint8List bytes, String name) {
    if (bytes.length > maxFileSizeBytes) {
      throw FormatException(
        'L’image du presse-papiers ("$name") dépasse la taille maximale autorisée (20 Mo).',
      );
    }
  }

  static Future<VibeChatAttachment?> _readClipboardImageAttachment() async {
    final payload = _readClipboardImagePayloadWin32();
    if (payload == null) return null;

    if (!payload.isDib) {
      final trimmed = trimEncodedImageBytes(payload.bytes);
      final mime = _sniffImageMimeType(trimmed);
      if (mime != null && mime != 'image/bmp') {
        final name = _defaultClipboardImageName(mime);
        _ensureMaxSize(trimmed, name);
        return VibeChatAttachment.image(
          name: name,
          bytes: trimmed,
          mimeType: mime,
        );
      }
      if (mime == 'image/bmp') {
        final pngBytes = await _decodeBmpToPngViaUi(trimmed);
        if (pngBytes != null) {
          const name = 'presse-papiers.png';
          _ensureMaxSize(pngBytes, name);
          return VibeChatAttachment.image(
            name: name,
            bytes: pngBytes,
            mimeType: 'image/png',
          );
        }
      }
      return null;
    }

    final converted = await _convertDibPayload(payload.bytes);
    if (converted == null) return null;
    final (bytes, mime) = converted;
    final name = _defaultClipboardImageName(mime);
    _ensureMaxSize(bytes, name);
    return VibeChatAttachment.image(name: name, bytes: bytes, mimeType: mime);
  }

  static Future<(Uint8List, String)?> _convertDibPayload(Uint8List dib) async {
    if (dib.length < 40) return null;
    final header = ByteData.sublistView(dib);
    final biSize = header.getUint32(0, Endian.little);
    if (biSize >= 40 && biSize < dib.length) {
      final compression = header.getUint32(16, Endian.little);
      // BI_JPEG = 4, BI_PNG = 5 : flux déjà compressé embarqué après l'en-tête DIB.
      if (compression == 4 || compression == 5) {
        final embedded = trimEncodedImageBytes(
          Uint8List.sublistView(dib, biSize),
        );
        final mime = _sniffImageMimeType(embedded);
        if (mime != null && mime != 'image/bmp') {
          return (embedded, mime);
        }
      }
    }

    final fastPng = await Isolate.run(() => encodeDibToPng(dib));
    if (fastPng != null) {
      return (fastPng, 'image/png');
    }

    final bmpBytes = dibToBmpBytes(dib);
    if (bmpBytes == null) return null;
    final uiPng = await _decodeBmpToPngViaUi(bmpBytes);
    if (uiPng == null) return null;
    return (uiPng, 'image/png');
  }

  static Future<Uint8List?> _decodeBmpToPngViaUi(Uint8List bmpBytes) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bmpBytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  /// Tronque les éventuels octets nuls de bourrage ajoutés par `GlobalSize`
  /// après la fin logique d'un flux PNG, WEBP, JPEG ou GIF.
  @visibleForTesting
  static Uint8List trimEncodedImageBytes(Uint8List bytes) {
    final mime = _sniffImageMimeType(bytes);
    if (mime == 'image/png') {
      var offset = 8;
      final view = ByteData.sublistView(bytes);
      while (offset + 12 <= bytes.length) {
        final length = view.getUint32(offset, Endian.big);
        final nextOffset = offset + 12 + length;
        if (nextOffset > bytes.length) break;
        final isIend =
            bytes[offset + 4] == 0x49 &&
            bytes[offset + 5] == 0x45 &&
            bytes[offset + 6] == 0x4E &&
            bytes[offset + 7] == 0x44;
        offset = nextOffset;
        if (isIend) {
          return offset == bytes.length ? bytes : bytes.sublist(0, offset);
        }
      }
      return bytes;
    }
    if (mime == 'image/webp' && bytes.length >= 12) {
      final riffSize = ByteData.sublistView(bytes).getUint32(4, Endian.little);
      final total = riffSize + 8;
      if (total >= 12 && total < bytes.length) {
        return bytes.sublist(0, total);
      }
      return bytes;
    }
    if (mime == 'image/jpeg' && bytes.length >= 4) {
      var end = bytes.length;
      while (end > 2 && bytes[end - 1] == 0) {
        end--;
      }
      if (end >= 2 &&
          bytes[end - 2] == 0xFF &&
          bytes[end - 1] == 0xD9 &&
          end < bytes.length) {
        return bytes.sublist(0, end);
      }
      return bytes;
    }
    if (mime == 'image/gif' && bytes.length >= 7) {
      var end = bytes.length;
      while (end > 6 && bytes[end - 1] == 0) {
        end--;
      }
      if (bytes[end - 1] == 0x3B && end < bytes.length) {
        return bytes.sublist(0, end);
      }
      return bytes;
    }
    return bytes;
  }

  /// Construit un fichier BMP complet en mémoire (en-tête `BITMAPFILEHEADER` de
  /// 14 octets + données DIB) à partir d'un bloc `CF_DIB` ou `CF_DIBV5`.
  @visibleForTesting
  static Uint8List? dibToBmpBytes(Uint8List dib) {
    final pixelOffsetInDib = _resolveDibPixelOffset(dib);
    if (pixelOffsetInDib == null) return null;
    final totalSize = 14 + dib.length;
    final bmp = Uint8List(totalSize);
    final header = ByteData.sublistView(bmp, 0, 14);
    bmp[0] = 0x42; // 'B'
    bmp[1] = 0x4D; // 'M'
    header.setUint32(2, totalSize, Endian.little);
    header.setUint16(6, 0, Endian.little);
    header.setUint16(8, 0, Endian.little);
    header.setUint32(10, 14 + pixelOffsetInDib, Endian.little);
    bmp.setRange(14, totalSize, dib);
    return bmp;
  }

  /// Convertit en pur Dart un bloc `CF_DIB` / `CF_DIBV5` 24 ou 32 bits
  /// (`BI_RGB`, `BI_BITFIELDS`, `BI_ALPHABITFIELDS`) en image PNG RGBA.
  ///
  /// Retourne `null` pour les formats indexés (1/4/8/16 bits) ou compressés RLE
  /// afin de permettre un repli vers le décodeur natif `dart:ui`.
  @visibleForTesting
  static Uint8List? encodeDibToPng(Uint8List dib) {
    if (dib.length < 40) return null;
    final header = ByteData.sublistView(dib);
    final biSize = header.getUint32(0, Endian.little);
    if (biSize < 40 || biSize > dib.length) return null;

    final width = header.getInt32(4, Endian.little);
    final rawHeight = header.getInt32(8, Endian.little);
    final bitCount = header.getUint16(14, Endian.little);
    final compression = header.getUint32(16, Endian.little);

    if (width <= 0 || rawHeight == 0 || width > 16384) return null;
    final topDown = rawHeight < 0;
    final height = topDown ? -rawHeight : rawHeight;
    if (height <= 0 || height > 16384) return null;
    if (bitCount != 24 && bitCount != 32) return null;
    if (compression != 0 && compression != 3 && compression != 6) return null;

    final pixelOffset = _resolveDibPixelOffset(dib);
    if (pixelOffset == null) return null;
    final rowStride = ((width * bitCount + 31) ~/ 32) * 4;
    final requiredBytes = pixelOffset + rowStride * height;
    if (requiredBytes > dib.length) return null;

    var rMask = 0x00FF0000;
    var gMask = 0x0000FF00;
    var bMask = 0x000000FF;
    var aMask = bitCount == 32 ? 0xFF000000 : 0;

    if (compression == 3 || compression == 6) {
      if (dib.length < 52) return null;
      rMask = header.getUint32(40, Endian.little);
      gMask = header.getUint32(44, Endian.little);
      bMask = header.getUint32(48, Endian.little);
      if (biSize >= 56 || compression == 6) {
        aMask = dib.length >= 56 ? header.getUint32(52, Endian.little) : 0;
      } else {
        aMask = 0;
      }
      if (rMask == 0 && gMask == 0 && bMask == 0) return null;
    }

    final rgbaRowBytes = width * 4;
    final rgbaPixels = Uint8List(rgbaRowBytes * height);
    var hasAnyNonZeroAlpha = false;

    if (bitCount == 24) {
      hasAnyNonZeroAlpha = true;
      for (var y = 0; y < height; y++) {
        final srcRow = topDown ? y : (height - 1 - y);
        var src = pixelOffset + srcRow * rowStride;
        var dst = y * rgbaRowBytes;
        for (var x = 0; x < width; x++) {
          rgbaPixels[dst] = dib[src + 2];
          rgbaPixels[dst + 1] = dib[src + 1];
          rgbaPixels[dst + 2] = dib[src];
          rgbaPixels[dst + 3] = 0xFF;
          src += 3;
          dst += 4;
        }
      }
    } else if (compression == 0) {
      for (var y = 0; y < height; y++) {
        final srcRow = topDown ? y : (height - 1 - y);
        var src = pixelOffset + srcRow * rowStride;
        var dst = y * rgbaRowBytes;
        for (var x = 0; x < width; x++) {
          final a = dib[src + 3];
          if (a != 0) hasAnyNonZeroAlpha = true;
          rgbaPixels[dst] = dib[src + 2];
          rgbaPixels[dst + 1] = dib[src + 1];
          rgbaPixels[dst + 2] = dib[src];
          rgbaPixels[dst + 3] = a;
          src += 4;
          dst += 4;
        }
      }
    } else {
      for (var y = 0; y < height; y++) {
        final srcRow = topDown ? y : (height - 1 - y);
        final rowBase = pixelOffset + srcRow * rowStride;
        var dst = y * rgbaRowBytes;
        for (var x = 0; x < width; x++) {
          final pixel = header.getUint32(rowBase + x * 4, Endian.little);
          final a = aMask == 0 ? 0xFF : _extractMaskedChannel(pixel, aMask);
          if (a != 0) hasAnyNonZeroAlpha = true;
          rgbaPixels[dst] = _extractMaskedChannel(pixel, rMask);
          rgbaPixels[dst + 1] = _extractMaskedChannel(pixel, gMask);
          rgbaPixels[dst + 2] = _extractMaskedChannel(pixel, bMask);
          rgbaPixels[dst + 3] = a;
          dst += 4;
        }
      }
    }

    // Les copies GDI Windows (PrintScreen / BitBlt) laissent souvent l'octet
    // alpha à 0x00 sur tous les pixels d'un DIB 32 bits : on restaure l'opacité.
    if (!hasAnyNonZeroAlpha) {
      for (var i = 3; i < rgbaPixels.length; i += 4) {
        rgbaPixels[i] = 0xFF;
      }
    }

    // Filtrage PNG Sub (type 1) ligne par ligne pour compresser efficacement les captures UI.
    final filteredStride = 1 + rgbaRowBytes;
    final filtered = Uint8List(filteredStride * height);
    for (var y = 0; y < height; y++) {
      final srcLine = y * rgbaRowBytes;
      final dstLine = y * filteredStride;
      filtered[dstLine] = 1; // Filter type 1 = Sub
      filtered[dstLine + 1] = rgbaPixels[srcLine];
      filtered[dstLine + 2] = rgbaPixels[srcLine + 1];
      filtered[dstLine + 3] = rgbaPixels[srcLine + 2];
      filtered[dstLine + 4] = rgbaPixels[srcLine + 3];
      for (var i = 4; i < rgbaRowBytes; i++) {
        filtered[dstLine + 1 + i] =
            (rgbaPixels[srcLine + i] - rgbaPixels[srcLine + i - 4]) & 0xFF;
      }
    }

    final compressed = Uint8List.fromList(zlib.encode(filtered));
    return _assemblePngBytes(width: width, height: height, idat: compressed);
  }

  static int? _resolveDibPixelOffset(Uint8List dib) {
    if (dib.length < 12) return null;
    final header = ByteData.sublistView(dib);
    final biSize = header.getUint32(0, Endian.little);
    if (biSize == 12) {
      // BITMAPCOREHEADER (OS/2)
      final bitCount = header.getUint16(10, Endian.little);
      final paletteBytes = bitCount <= 8 ? (1 << bitCount) * 3 : 0;
      final offset = 12 + paletteBytes;
      return offset <= dib.length ? offset : null;
    }
    if (biSize < 40 || biSize > dib.length || dib.length < 40) return null;

    final width = header.getInt32(4, Endian.little);
    final rawHeight = header.getInt32(8, Endian.little);
    final bitCount = header.getUint16(14, Endian.little);
    final compression = header.getUint32(16, Endian.little);
    final clrUsed = header.getUint32(32, Endian.little);

    var masksBytes = 0;
    if (biSize == 40) {
      if (compression == 3) {
        masksBytes = 12;
      } else if (compression == 6) {
        masksBytes = 16;
      }
    } else if (biSize >= 52 &&
        compression == 3 &&
        width > 0 &&
        rawHeight != 0) {
      // Certains producteurs historiques ajoutent malgré tout 12 octets de
      // masques après un BITMAPV4/V5HEADER : on détecte ce cas via la taille exacte.
      final height = rawHeight < 0 ? -rawHeight : rawHeight;
      final rowStride = ((width * bitCount + 31) ~/ 32) * 4;
      final expectedPixels = rowStride * height;
      if (dib.length == biSize + 12 + expectedPixels) {
        masksBytes = 12;
      }
    }

    final int paletteEntries;
    if (clrUsed > 0) {
      paletteEntries = clrUsed;
    } else if (bitCount > 0 && bitCount <= 8) {
      paletteEntries = 1 << bitCount;
    } else {
      paletteEntries = 0;
    }

    final offset = biSize + masksBytes + paletteEntries * 4;
    return offset <= dib.length ? offset : null;
  }

  static int _extractMaskedChannel(int pixel, int mask) {
    final unsignedMask = mask & 0xFFFFFFFF;
    if (unsignedMask == 0) return 0;
    var shift = 0;
    while (shift < 32 && ((unsignedMask >>> shift) & 1) == 0) {
      shift++;
    }
    final maxVal = unsignedMask >>> shift;
    if (maxVal == 0) return 0;
    final raw = (pixel >>> shift) & maxVal;
    if (maxVal == 0xFF) return raw;
    return ((raw * 255 + (maxVal ~/ 2)) ~/ maxVal).clamp(0, 255);
  }

  static Uint8List _assemblePngBytes({
    required int width,
    required int height,
    required Uint8List idat,
  }) {
    final ihdr = Uint8List(13);
    final ihdrView = ByteData.sublistView(ihdr);
    ihdrView.setUint32(0, width, Endian.big);
    ihdrView.setUint32(4, height, Endian.big);
    ihdr[8] = 8; // bit depth 8
    ihdr[9] = 6; // RGBA
    ihdr[10] = 0; // deflate
    ihdr[11] = 0; // standard filter
    ihdr[12] = 0; // non-interlaced

    final builder = BytesBuilder(copy: false)
      ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    _writePngChunk(builder, const [0x49, 0x48, 0x44, 0x52], ihdr); // IHDR
    _writePngChunk(builder, const [0x49, 0x44, 0x41, 0x54], idat); // IDAT
    _writePngChunk(builder, const [
      0x49,
      0x45,
      0x4E,
      0x44,
    ], Uint8List(0)); // IEND
    return builder.toBytes();
  }

  static void _writePngChunk(
    BytesBuilder builder,
    List<int> type,
    Uint8List data,
  ) {
    final lenBytes = Uint8List(4);
    ByteData.sublistView(lenBytes).setUint32(0, data.length, Endian.big);
    builder
      ..add(lenBytes)
      ..add(type)
      ..add(data);

    var crc = 0xFFFFFFFF;
    for (final b in type) {
      crc = _pngCrcTable[(crc ^ b) & 0xFF] ^ (crc >>> 8);
    }
    for (var i = 0; i < data.length; i++) {
      crc = _pngCrcTable[(crc ^ data[i]) & 0xFF] ^ (crc >>> 8);
    }
    crc = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;

    final crcBytes = Uint8List(4);
    ByteData.sublistView(crcBytes).setUint32(0, crc, Endian.big);
    builder.add(crcBytes);
  }

  static final Uint32List _pngCrcTable = () {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[n] = c;
    }
    return table;
  }();

  static List<String> _extractCandidatePaths(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty || lines.length > 20) return const [];
    final paths = <String>[];
    for (var line in lines) {
      if ((line.startsWith('"') && line.endsWith('"')) ||
          (line.startsWith("'") && line.endsWith("'"))) {
        line = line.substring(1, line.length - 1).trim();
      }
      if (line.isEmpty || line.length > 520) return const [];
      final looksLikePath =
          RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(line) ||
          line.startsWith(r'\\') ||
          line.startsWith('/');
      if (!looksLikePath) return const [];
      paths.add(line);
    }
    return paths;
  }
}

// ---------------------------------------------------------------------------
// Implémentation Win32 FFI sans dépendance externe (comdlg32 / shell32 / user32)
// ---------------------------------------------------------------------------

final class _OpenFileNameW extends Struct {
  @Uint32()
  external int lStructSize;
  @IntPtr()
  external int hwndOwner;
  @IntPtr()
  external int hInstance;
  external Pointer<Uint16> lpstrFilter;
  external Pointer<Uint16> lpstrCustomFilter;
  @Uint32()
  external int nMaxCustFilter;
  @Uint32()
  external int nFilterIndex;
  external Pointer<Uint16> lpstrFile;
  @Uint32()
  external int nMaxFile;
  external Pointer<Uint16> lpstrFileTitle;
  @Uint32()
  external int nMaxFileTitle;
  external Pointer<Uint16> lpstrInitialDir;
  external Pointer<Uint16> lpstrTitle;
  @Uint32()
  external int flags;
  @Uint16()
  external int nFileOffset;
  @Uint16()
  external int nFileExtension;
  external Pointer<Uint16> lpstrDefExt;
  @IntPtr()
  external int lCustData;
  @IntPtr()
  external int lpfnHook;
  external Pointer<Uint16> lpTemplateName;
  external Pointer<Void> pvReserved;
  @Uint32()
  external int dwReserved;
  @Uint32()
  external int flagsEx;
}

typedef _GlobalAllocNative = Pointer<Void> Function(
  Uint32 uFlags,
  IntPtr dwBytes,
);
typedef _GlobalAllocDart = Pointer<Void> Function(int uFlags, int dwBytes);

typedef _GlobalFreeNative = Pointer<Void> Function(Pointer<Void> hMem);
typedef _GlobalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);

typedef _GlobalLockNative = Pointer<Uint8> Function(IntPtr hMem);
typedef _GlobalLockDart = Pointer<Uint8> Function(int hMem);

typedef _GlobalUnlockNative = Int32 Function(IntPtr hMem);
typedef _GlobalUnlockDart = int Function(int hMem);

typedef _GlobalSizeNative = IntPtr Function(IntPtr hMem);
typedef _GlobalSizeDart = int Function(int hMem);

typedef _GetOpenFileNameWNative = Int32 Function(Pointer<_OpenFileNameW> ofn);
typedef _GetOpenFileNameWDart = int Function(Pointer<_OpenFileNameW> ofn);

typedef _IsClipboardFormatAvailableNative = Int32 Function(Uint32 format);
typedef _IsClipboardFormatAvailableDart = int Function(int format);

typedef _RegisterClipboardFormatWNative = Uint32 Function(
  Pointer<Uint16> lpszFormat,
);
typedef _RegisterClipboardFormatWDart = int Function(
  Pointer<Uint16> lpszFormat,
);

typedef _OpenClipboardNative = Int32 Function(IntPtr hWndNewOwner);
typedef _OpenClipboardDart = int Function(int hWndNewOwner);

typedef _CloseClipboardNative = Int32 Function();
typedef _CloseClipboardDart = int Function();

typedef _GetClipboardDataNative = IntPtr Function(Uint32 uFormat);
typedef _GetClipboardDataDart = int Function(int uFormat);

typedef _DragQueryFileWNative = Uint32 Function(
  IntPtr hDrop,
  Uint32 iFile,
  Pointer<Uint16> lpszFile,
  Uint32 cch,
);
typedef _DragQueryFileWDart = int Function(
  int hDrop,
  int iFile,
  Pointer<Uint16> lpszFile,
  int cch,
);

const int _gmemZeroInit = 0x0040;
const int _ofnExplorer = 0x00080000;
const int _ofnFileMustExist = 0x00001000;
const int _ofnPathMustExist = 0x00000800;
const int _ofnAllowMultiSelect = 0x00000200;
const int _ofnNoChangeDir = 0x00000008;
const int _cfDib = 8;
const int _cfUnicodeText = 13;
const int _cfHdrop = 15;
const int _cfDibV5 = 17;
const int _maxClipboardRawBytes = 128 * 1024 * 1024;

const List<String> _registeredEncodedImageFormats = <String>[
  'PNG',
  'image/png',
  'image/webp',
  'image/jpeg',
  'JFIF',
  'GIF',
  'image/gif',
];

Map<String, int>? _cachedRegisteredFormats;

Pointer<T> _allocZeroed<T extends NativeType>(
  _GlobalAllocDart globalAlloc,
  int byteCount,
) => globalAlloc(_gmemZeroInit, byteCount).cast<T>();

Pointer<Uint16> _toUtf16(_GlobalAllocDart globalAlloc, List<int> codeUnits) {
  final ptr = _allocZeroed<Uint16>(globalAlloc, (codeUnits.length + 1) * 2);
  for (var i = 0; i < codeUnits.length; i++) {
    ptr[i] = codeUnits[i];
  }
  ptr[codeUnits.length] = 0;
  return ptr;
}

String _readUtf16(Pointer<Uint16> ptr, int start, int maxLen) {
  final units = <int>[];
  for (var i = start; i < maxLen; i++) {
    final unit = ptr[i];
    if (unit == 0) break;
    units.add(unit);
  }
  return String.fromCharCodes(units);
}

List<String> _pickFilesWin32() {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final comdlg32 = DynamicLibrary.open('comdlg32.dll');

  final globalAlloc = kernel32
      .lookupFunction<_GlobalAllocNative, _GlobalAllocDart>('GlobalAlloc');
  final globalFree = kernel32
      .lookupFunction<_GlobalFreeNative, _GlobalFreeDart>('GlobalFree');
  final getOpenFileName = comdlg32
      .lookupFunction<_GetOpenFileNameWNative, _GetOpenFileNameWDart>(
        'GetOpenFileNameW',
      );

  const maxFileChars = 32768;
  final fileBuffer = _allocZeroed<Uint16>(globalAlloc, maxFileChars * 2);
  final filterString =
      'Fichiers pris en charge (Images, Texte)\x00'
      '*.png;*.jpg;*.jpeg;*.webp;*.gif;*.bmp;*.txt;*.md;*.markdown;*.json;*.jsonc;*.yaml;*.yml;*.csv;*.xml;*.svg;*.html;*.htm;*.css;*.dart;*.js;*.ts;*.py;*.sql;*.log;*.ini;*.toml\x00'
      'Images (*.png;*.jpg;*.jpeg;*.webp;*.gif;*.bmp)\x00'
      '*.png;*.jpg;*.jpeg;*.webp;*.gif;*.bmp\x00'
      'Fichiers texte (*.txt;*.md;*.json;*.yaml;*.csv;*.xml;*.html;*.dart)\x00'
      '*.txt;*.md;*.markdown;*.json;*.jsonc;*.yaml;*.yml;*.csv;*.xml;*.html;*.htm;*.css;*.dart;*.js;*.ts;*.py;*.sql;*.log;*.ini;*.toml\x00'
      'Tous les fichiers (*.*)\x00*.*\x00\x00';
  final filterPtr = _toUtf16(globalAlloc, filterString.codeUnits);
  final titlePtr = _toUtf16(
    globalAlloc,
    'Joindre des fichiers (image ou texte) au chat IA'.codeUnits,
  );
  final ofn = _allocZeroed<_OpenFileNameW>(
    globalAlloc,
    sizeOf<_OpenFileNameW>(),
  );

  try {
    ofn.ref
      ..lStructSize = sizeOf<_OpenFileNameW>()
      ..lpstrFilter = filterPtr
      ..nFilterIndex = 1
      ..lpstrFile = fileBuffer
      ..nMaxFile = maxFileChars
      ..lpstrTitle = titlePtr
      ..flags =
          _ofnExplorer |
          _ofnFileMustExist |
          _ofnPathMustExist |
          _ofnAllowMultiSelect |
          _ofnNoChangeDir;

    final accepted = getOpenFileName(ofn);
    if (accepted == 0) return const [];

    final firstSegment = _readUtf16(fileBuffer, 0, maxFileChars);
    if (firstSegment.isEmpty) return const [];

    var offset = firstSegment.length + 1;
    if (offset >= maxFileChars || fileBuffer[offset] == 0) {
      return [firstSegment];
    }

    final directory = firstSegment;
    final files = <String>[];
    while (offset < maxFileChars && fileBuffer[offset] != 0) {
      final name = _readUtf16(fileBuffer, offset, maxFileChars);
      if (name.isEmpty) break;
      final separator = directory.endsWith(r'\') || directory.endsWith('/')
          ? ''
          : r'\';
      files.add('$directory$separator$name');
      offset += name.length + 1;
    }
    return files;
  } finally {
    globalFree(ofn.cast());
    globalFree(titlePtr.cast());
    globalFree(filterPtr.cast());
    globalFree(fileBuffer.cast());
  }
}

List<String> _readClipboardFilesWin32() {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final user32 = DynamicLibrary.open('user32.dll');
    final shell32 = DynamicLibrary.open('shell32.dll');

    final globalAlloc = kernel32
        .lookupFunction<_GlobalAllocNative, _GlobalAllocDart>('GlobalAlloc');
    final globalFree = kernel32
        .lookupFunction<_GlobalFreeNative, _GlobalFreeDart>('GlobalFree');
    final isFormatAvailable = user32
        .lookupFunction<
          _IsClipboardFormatAvailableNative,
          _IsClipboardFormatAvailableDart
        >('IsClipboardFormatAvailable');
    final openClipboard = user32
        .lookupFunction<_OpenClipboardNative, _OpenClipboardDart>(
          'OpenClipboard',
        );
    final closeClipboard = user32
        .lookupFunction<_CloseClipboardNative, _CloseClipboardDart>(
          'CloseClipboard',
        );
    final getClipboardData = user32
        .lookupFunction<_GetClipboardDataNative, _GetClipboardDataDart>(
          'GetClipboardData',
        );
    final dragQueryFile = shell32
        .lookupFunction<_DragQueryFileWNative, _DragQueryFileWDart>(
          'DragQueryFileW',
        );

    if (isFormatAvailable(_cfHdrop) == 0) return const [];
    if (openClipboard(0) == 0) return const [];
    try {
      final hDrop = getClipboardData(_cfHdrop);
      if (hDrop == 0) return const [];
      final count = dragQueryFile(hDrop, 0xFFFFFFFF, nullptr, 0);
      if (count == 0) return const [];

      final results = <String>[];
      for (var i = 0; i < count; i++) {
        final length = dragQueryFile(hDrop, i, nullptr, 0);
        if (length == 0) continue;
        final buffer = _allocZeroed<Uint16>(globalAlloc, (length + 1) * 2);
        try {
          dragQueryFile(hDrop, i, buffer, length + 1);
          final path = _readUtf16(buffer, 0, length + 1);
          if (path.isNotEmpty) results.add(path);
        } finally {
          globalFree(buffer.cast());
        }
      }
      return results;
    } finally {
      closeClipboard();
    }
  } catch (_) {
    return const [];
  }
}

final class _ClipboardImagePayload {
  const _ClipboardImagePayload({required this.bytes, required this.isDib});

  final Uint8List bytes;
  final bool isDib;
}

Map<String, int> _getRegisteredImageFormatIds(
  _GlobalAllocDart globalAlloc,
  _GlobalFreeDart globalFree,
  _RegisterClipboardFormatWDart registerFormat,
) {
  final cached = _cachedRegisteredFormats;
  if (cached != null) return cached;
  final resolved = <String, int>{};
  for (final name in _registeredEncodedImageFormats) {
    final namePtr = _toUtf16(globalAlloc, name.codeUnits);
    try {
      final id = registerFormat(namePtr);
      if (id != 0) resolved[name] = id;
    } finally {
      globalFree(namePtr.cast());
    }
  }
  _cachedRegisteredFormats = resolved;
  return resolved;
}

bool _hasClipboardImageOrFilesWin32() {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final user32 = DynamicLibrary.open('user32.dll');

    final globalAlloc = kernel32
        .lookupFunction<_GlobalAllocNative, _GlobalAllocDart>('GlobalAlloc');
    final globalFree = kernel32
        .lookupFunction<_GlobalFreeNative, _GlobalFreeDart>('GlobalFree');
    final isFormatAvailable = user32
        .lookupFunction<
          _IsClipboardFormatAvailableNative,
          _IsClipboardFormatAvailableDart
        >('IsClipboardFormatAvailable');
    final registerFormat = user32
        .lookupFunction<
          _RegisterClipboardFormatWNative,
          _RegisterClipboardFormatWDart
        >('RegisterClipboardFormatW');

    if (isFormatAvailable(_cfHdrop) != 0) return true;

    final formatIds = _getRegisteredImageFormatIds(
      globalAlloc,
      globalFree,
      registerFormat,
    );
    for (final formatName in _registeredEncodedImageFormats) {
      final id = formatIds[formatName];
      if (id != null && isFormatAvailable(id) != 0) {
        return true;
      }
    }

    final hasDib =
        isFormatAvailable(_cfDibV5) != 0 || isFormatAvailable(_cfDib) != 0;
    if (!hasDib) return false;

    // Évite d'intercepter un collage de texte riche (ex. Word/Excel) qui expose
    // simultanément CF_UNICODETEXT et un aperçu GDI CF_DIB sans format PNG dédié.
    return isFormatAvailable(_cfUnicodeText) == 0;
  } catch (_) {
    return false;
  }
}

Uint8List? _copyClipboardGlobalBytes(
  int format,
  _IsClipboardFormatAvailableDart isFormatAvailable,
  _GetClipboardDataDart getClipboardData,
  _GlobalLockDart globalLock,
  _GlobalUnlockDart globalUnlock,
  _GlobalSizeDart globalSize,
) {
  if (isFormatAvailable(format) == 0) return null;
  final hData = getClipboardData(format);
  if (hData == 0) return null;
  final size = globalSize(hData);
  if (size <= 0 || size > _maxClipboardRawBytes) return null;
  final ptr = globalLock(hData);
  if (ptr == nullptr) return null;
  try {
    return Uint8List.fromList(ptr.asTypedList(size));
  } finally {
    globalUnlock(hData);
  }
}

_ClipboardImagePayload? _readClipboardImagePayloadWin32() {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final user32 = DynamicLibrary.open('user32.dll');

    final globalAlloc = kernel32
        .lookupFunction<_GlobalAllocNative, _GlobalAllocDart>('GlobalAlloc');
    final globalFree = kernel32
        .lookupFunction<_GlobalFreeNative, _GlobalFreeDart>('GlobalFree');
    final globalLock = kernel32
        .lookupFunction<_GlobalLockNative, _GlobalLockDart>('GlobalLock');
    final globalUnlock = kernel32
        .lookupFunction<_GlobalUnlockNative, _GlobalUnlockDart>('GlobalUnlock');
    final globalSize = kernel32
        .lookupFunction<_GlobalSizeNative, _GlobalSizeDart>('GlobalSize');
    final isFormatAvailable = user32
        .lookupFunction<
          _IsClipboardFormatAvailableNative,
          _IsClipboardFormatAvailableDart
        >('IsClipboardFormatAvailable');
    final registerFormat = user32
        .lookupFunction<
          _RegisterClipboardFormatWNative,
          _RegisterClipboardFormatWDart
        >('RegisterClipboardFormatW');
    final openClipboard = user32
        .lookupFunction<_OpenClipboardNative, _OpenClipboardDart>(
          'OpenClipboard',
        );
    final closeClipboard = user32
        .lookupFunction<_CloseClipboardNative, _CloseClipboardDart>(
          'CloseClipboard',
        );
    final getClipboardData = user32
        .lookupFunction<_GetClipboardDataNative, _GetClipboardDataDart>(
          'GetClipboardData',
        );

    final formatIds = _getRegisteredImageFormatIds(
      globalAlloc,
      globalFree,
      registerFormat,
    );

    final hasCandidate =
        _registeredEncodedImageFormats.any((name) {
          final id = formatIds[name];
          return id != null && isFormatAvailable(id) != 0;
        }) ||
        isFormatAvailable(_cfDibV5) != 0 ||
        isFormatAvailable(_cfDib) != 0;
    if (!hasCandidate) return null;

    if (openClipboard(0) == 0) return null;
    try {
      for (final formatName in _registeredEncodedImageFormats) {
        final id = formatIds[formatName];
        if (id == null) continue;
        final bytes = _copyClipboardGlobalBytes(
          id,
          isFormatAvailable,
          getClipboardData,
          globalLock,
          globalUnlock,
          globalSize,
        );
        if (bytes != null &&
            bytes.isNotEmpty &&
            VibeChatAttachment._sniffImageMimeType(bytes) != null) {
          return _ClipboardImagePayload(bytes: bytes, isDib: false);
        }
      }

      for (final dibFormat in const [_cfDibV5, _cfDib]) {
        final dibBytes = _copyClipboardGlobalBytes(
          dibFormat,
          isFormatAvailable,
          getClipboardData,
          globalLock,
          globalUnlock,
          globalSize,
        );
        if (dibBytes != null && dibBytes.length >= 12) {
          return _ClipboardImagePayload(bytes: dibBytes, isDib: true);
        }
      }
      return null;
    } finally {
      closeClipboard();
    }
  } catch (_) {
    return null;
  }
}
