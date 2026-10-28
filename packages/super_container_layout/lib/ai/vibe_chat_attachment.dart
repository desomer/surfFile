import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

/// Fichier (image ou texte) joint à un message du chat IA Vibe.
class VibeChatAttachment {
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

  final String name;
  final String mimeType;
  final Uint8List bytes;
  final String? textContent;
  final String? path;

  bool get isImage => mimeType.startsWith('image/');
  bool get isText => textContent != null;

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
    final imageMime =
        _imageMimeTypeForName(name) ?? _sniffImageMimeType(bytes);
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

  /// Importe des pièces jointes depuis le presse-papiers :
  /// 1. Fichiers copiés dans l'explorateur Windows (`CF_HDROP`).
  /// 2. Chemins de fichiers présents dans le texte du presse-papiers.
  /// 3. Contenu texte du presse-papiers comme pièce jointe texte.
  static Future<List<VibeChatAttachment>> fromClipboard() async {
    if (Platform.isWindows) {
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
    }

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

typedef _GetOpenFileNameWNative = Int32 Function(Pointer<_OpenFileNameW> ofn);
typedef _GetOpenFileNameWDart = int Function(Pointer<_OpenFileNameW> ofn);

typedef _IsClipboardFormatAvailableNative = Int32 Function(Uint32 format);
typedef _IsClipboardFormatAvailableDart = int Function(int format);

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
const int _cfHdrop = 15;

Pointer<T> _allocZeroed<T extends NativeType>(
  _GlobalAllocDart globalAlloc,
  int byteCount,
) => globalAlloc(_gmemZeroInit, byteCount).cast<T>();

Pointer<Uint16> _toUtf16(
  _GlobalAllocDart globalAlloc,
  List<int> codeUnits,
) {
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
      final separator =
          directory.endsWith(r'\') || directory.endsWith('/') ? '' : r'\';
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
    final isFormatAvailable = user32.lookupFunction<
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
