/// Utilitaires de nommage lisible (slugs sûrs Windows/Git) et d'écriture
/// atomique déterministe en fins de ligne LF ([SpecStorageSlug], [SpecStorageIo]).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Générateur de slugs lisibles, déterministes et compatibles Windows/Git.
abstract final class SpecStorageSlug {
  static final RegExp _windowsReservedRegex = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
    caseSensitive: false,
  );

  static const Map<String, String> _accentMap = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'æ': 'ae',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ø': 'o',
    'œ': 'oe',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'ß': 'ss',
  };

  /// Transforme [raw] en slug ASCII propre (sans accents, camelCase découpé,
  /// protégé contre les noms réservés Windows).
  static String slugify(
    String raw, {
    String fallback = 'item',
    String separator = '-',
    int maxLength = 64,
  }) {
    final splitCamel = raw
        .trim()
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([a-z][0-9]+)([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z0-9]+)([A-Z][a-z])'),
          (m) => '${m[1]} ${m[2]}',
        );

    final folded = StringBuffer();
    for (final rune in splitCamel.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      folded.write(_accentMap[ch] ?? ch);
    }

    final escapedSep = RegExp.escape(separator);
    var clean = folded
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), separator)
        .replaceAll(RegExp('$escapedSep+'), separator)
        .replaceAll(RegExp('^$escapedSep+|$escapedSep+\$'), '');

    if (clean.length > maxLength) {
      clean = clean
          .substring(0, maxLength)
          .replaceAll(RegExp('$escapedSep+\$'), '');
    }

    if (clean.isEmpty) {
      clean = fallback;
    }

    if (_windowsReservedRegex.hasMatch(clean)) {
      clean = '$fallback$separator$clean';
    }
    return clean;
  }

  /// Extrait un suffixe court déterministe depuis [id] pour lever les collisions.
  static String shortSuffixFromId(String id) {
    final clean = id
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (clean.length >= 4) {
      return clean.length <= 8
          ? clean
          : clean.substring(clean.length - 8);
    }
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Assigne des noms de fichiers `.json` uniques et déterministes à [items].
  ///
  /// Retourne une map ordonnée `fileName -> item`.
  static Map<String, T> assignUniqueJsonFiles<T>(
    Iterable<T> items, {
    required String Function(T item) labelFor,
    required String Function(T item) idFor,
    String fallback = 'item',
    String separator = '-',
  }) {
    final result = <String, T>{};
    final usedLower = <String>{};

    for (final item in items) {
      final base = slugify(
        labelFor(item),
        fallback: fallback,
        separator: separator,
      );
      var candidate = '$base.json';
      if (!usedLower.add(candidate.toLowerCase())) {
        final suffix = shortSuffixFromId(idFor(item));
        candidate = '${base}__$suffix.json';
        var index = 2;
        while (!usedLower.add(candidate.toLowerCase())) {
          candidate = '${base}__${suffix}_$index.json';
          index++;
        }
      }
      result[candidate] = item;
    }
    return result;
  }
}

/// Utilitaires d'E/S atomiques et déterministes (LF + saut de ligne final).
abstract final class SpecStorageIo {
  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

  /// Sérialise [value] en JSON indenté (2 espaces), fins de ligne LF et
  /// exactement un `\n` final pour limiter les diffs Git.
  static String encodePrettyJson(Object? value) {
    final raw = _prettyEncoder.convert(value).replaceAll('\r\n', '\n');
    return raw.endsWith('\n') ? raw : '$raw\n';
  }

  /// Normalise une chaîne en fins de ligne LF avec saut de ligne final optionnel.
  static String normalizeLf(String text, {bool trailingNewline = true}) {
    final lf = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!trailingNewline) return lf;
    return lf.endsWith('\n') ? lf : '$lf\n';
  }

  /// Écrit atomiquement [content] dans [target] uniquement si le contenu diffère.
  ///
  /// Retourne `true` si une écriture disque a effectivement eu lieu.
  static Future<bool> writeTextAtomicallyIfChanged(
    File target,
    String content, {
    required int Function() nextTmpId,
  }) async {
    if (await target.exists()) {
      try {
        final existing = await target.readAsString();
        if (existing == content) return false;
      } catch (_) {}
    }
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp.${nextTmpId()}');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
    return true;
  }

  /// Écrit atomiquement [payload] en JSON formaté dans [target] si modifié.
  static Future<bool> writeJsonAtomicallyIfChanged(
    File target,
    Object? payload, {
    required int Function() nextTmpId,
  }) => writeTextAtomicallyIfChanged(
    target,
    encodePrettyJson(payload),
    nextTmpId: nextTmpId,
  );

  /// Écrit atomiquement des octets bruts dans [target].
  static Future<void> writeBytesAtomically(
    File target,
    Uint8List bytes, {
    required int Function() nextTmpId,
  }) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp.${nextTmpId()}');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }

  /// Supprime dans [directory] les fichiers [extension] absents de [keepFileNames].
  static Future<void> pruneUnexpectedFiles(
    Directory directory,
    Set<String> keepFileNames, {
    String extension = '.json',
  }) async {
    if (!await directory.exists()) return;
    final lowerKeep = {for (final name in keepFileNames) name.toLowerCase()};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final fileName = fileNameOf(entity.path);
      if (fileName.contains('.tmp.')) continue;
      if (!fileName.toLowerCase().endsWith(extension.toLowerCase())) continue;
      if (!lowerKeep.contains(fileName.toLowerCase())) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  /// Extrait le nom de fichier depuis un chemin.
  static String fileNameOf(String path) {
    final idx = path.lastIndexOf(Platform.pathSeparator);
    final altIdx = path.lastIndexOf('/');
    final cut = idx > altIdx ? idx : altIdx;
    return cut < 0 ? path : path.substring(cut + 1);
  }
}
