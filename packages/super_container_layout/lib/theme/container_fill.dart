import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../models/json_syntax.dart';
import '../models/json_text_binding.dart';

enum FillType { solid, linear, radial, sweep }

@immutable
class ContainerFill {
  const ContainerFill({
    this.type = FillType.solid,
    this.start = const Color(0xFF5268D9),
    this.end = const Color(0xFFB794F4),
    this.angle = 45,
    this.radius = .8,
    this.imageUrl = '',
    this.imageBinding,
    this.imageFit = BoxFit.cover,
    this.imageOpacity = 1,
  });

  final FillType type;
  final Color start;
  final Color end;
  final double angle;
  final double radius;
  final String imageUrl;
  final JsonTextBinding? imageBinding;
  final BoxFit imageFit;
  final double imageOpacity;

  bool get hasImage => imageUrl.trim().isNotEmpty || imageBinding != null;

  ContainerFill copyWith({
    FillType? type,
    Color? start,
    bool resetStart = false,
    Color? end,
    bool resetEnd = false,
    double? angle,
    double? radius,
    String? imageUrl,
    JsonTextBinding? imageBinding,
    bool clearImageBinding = false,
    BoxFit? imageFit,
    double? imageOpacity,
  }) => ContainerFill(
    type: type ?? this.type,
    start: resetStart ? const Color(0xFF5268D9) : start ?? this.start,
    end: resetEnd ? const Color(0xFFB794F4) : end ?? this.end,
    angle: angle ?? this.angle,
    radius: radius ?? this.radius,
    imageUrl: imageUrl ?? this.imageUrl,
    imageBinding: clearImageBinding ? null : imageBinding ?? this.imageBinding,
    imageFit: imageFit ?? this.imageFit,
    imageOpacity: imageOpacity ?? this.imageOpacity,
  );

  /// Résout [imageUrl] en [ImageProvider] compatible avec les URLs réseau
  /// (dont WebP et SVG), les Data URIs (`data:image/...`), les chaînes Base64
  /// brutes et le code SVG inline.
  ImageProvider<Object>? imageProvider() {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) return null;
    return _resolveSurfaceImageProvider(trimmed);
  }

  DecorationImage? decorationImage({
    double opacity = 1,
    ImageErrorListener? onError,
  }) {
    final effectiveOpacity = (imageOpacity * opacity).clamp(0.0, 1.0);
    if (effectiveOpacity <= 0) return null;
    final provider = imageProvider();
    if (provider == null) return null;
    return DecorationImage(
      image: provider,
      fit: imageFit,
      opacity: effectiveOpacity,
      onError: onError ?? (_, _) {},
    );
  }

  Gradient? gradient({double opacity = 1}) {
    final colors = [
      start.withValues(alpha: start.a * opacity),
      end.withValues(alpha: end.a * opacity),
    ];
    final radians = angle * math.pi / 180;
    return switch (type) {
      FillType.solid => null,
      FillType.linear => LinearGradient(
        begin: Alignment(-math.cos(radians), -math.sin(radians)),
        end: Alignment(math.cos(radians), math.sin(radians)),
        colors: colors,
      ),
      FillType.radial => RadialGradient(colors: colors, radius: radius),
      FillType.sweep => SweepGradient(
        colors: colors,
        transform: GradientRotation(radians),
      ),
    };
  }

  Map<String, Object> toJson() => {
    'type': type.name,
    'start': start.toARGB32(),
    'end': end.toARGB32(),
    'angle': angle,
    'radius': radius,
    if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
    if (imageBinding != null) 'imageBinding': imageBinding!.toJson(),
    if (imageFit != BoxFit.cover) 'imageFit': imageFit.name,
    if (imageOpacity != 1) 'imageOpacity': imageOpacity,
  };

  Map<String, Object> toCompactJson() => {
    'type': type.name,
    'start': JsonColor.toHex(start),
    'end': JsonColor.toHex(end),
    if (type != FillType.solid && angle != 45) 'angle': angle,
    if (type == FillType.radial && radius != .8) 'radius': radius,
    if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
    if (imageBinding != null) 'imageBinding': imageBinding!.toCompactJson(),
    if (imageFit != BoxFit.cover) 'imageFit': imageFit.name,
    if (imageOpacity != 1) 'imageOpacity': imageOpacity,
  };

  static ContainerFill fromJson(
    Object? value, {
    ContainerFill fallback = const ContainerFill(),
  }) {
    if (value == null) return fallback;
    if (value is! Map) throw const FormatException('Style de fond invalide.');
    final type = switch (value['type'] ?? fallback.type.name) {
      'solid' => FillType.solid,
      'linear' => FillType.linear,
      'radial' => FillType.radial,
      'sweep' => FillType.sweep,
      _ => throw const FormatException('Type de dégradé invalide.'),
    };
    Color color(String key, Color defaultColor) {
      if (!value.containsKey(key) || value[key] == null) return defaultColor;
      try {
        return JsonColor.parse(value[key], key);
      } on FormatException {
        throw FormatException('Couleur de dégradé invalide : $key.');
      }
    }

    double number(String key, double min, double max, double defaultVal) {
      final number = value[key] ?? defaultVal;
      if (number is! num || !number.isFinite || number < min || number > max) {
        throw FormatException('Paramètre de dégradé invalide : $key.');
      }
      return number.toDouble();
    }

    final rawImageUrl = value['imageUrl'] ?? fallback.imageUrl;
    if (rawImageUrl is! String) {
      throw const FormatException('URL d’image de fond invalide.');
    }
    final imageBinding = value.containsKey('imageBinding')
        ? (value['imageBinding'] == null
              ? null
              : JsonTextBinding.fromJson(value['imageBinding']))
        : fallback.imageBinding;
    final rawImageFit = value['imageFit'] ?? fallback.imageFit.name;
    final imageFit = rawImageFit is String
        ? BoxFit.values.where((fit) => fit.name == rawImageFit).firstOrNull
        : null;
    if (imageFit == null) {
      throw const FormatException('Mode d’ajustement d’image invalide.');
    }

    return ContainerFill(
      type: type,
      start: color('start', fallback.start),
      end: color('end', fallback.end),
      angle: number('angle', 0, 360, fallback.angle),
      radius: number('radius', .1, 2, fallback.radius),
      imageUrl: rawImageUrl,
      imageBinding: imageBinding,
      imageFit: imageFit,
      imageOpacity: number('imageOpacity', 0, 1, fallback.imageOpacity),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContainerFill &&
          other.type == type &&
          other.start.toARGB32() == start.toARGB32() &&
          other.end.toARGB32() == end.toARGB32() &&
          other.angle == angle &&
          other.radius == radius &&
          other.imageUrl == imageUrl &&
          other.imageBinding == imageBinding &&
          other.imageFit == imageFit &&
          other.imageOpacity == imageOpacity);

  @override
  int get hashCode => Object.hash(
    type,
    start.toARGB32(),
    end.toARGB32(),
    angle,
    radius,
    imageUrl,
    imageBinding,
    imageFit,
    imageOpacity,
  );
}

typedef _SimpleDecoderCallback = Future<ui.Codec> Function(
  ui.ImmutableBuffer buffer,
);

/// [MemoryImage] dont l'égalité repose sur le contenu des octets ([bytes])
/// afin d'éviter de recharger l'image à chaque reconstruction de widget.
@immutable
class SurfaceMemoryImage extends MemoryImage {
  const SurfaceMemoryImage(super.bytes, {super.scale = 1.0});

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is SurfaceMemoryImage &&
        other.scale == scale &&
        listEquals(other.bytes, bytes);
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(bytes), scale);
}

/// [ImageProvider] en mémoire dédié au rendu d'images vectorielles SVG.
@immutable
class SvgMemoryImage extends MemoryImage {
  const SvgMemoryImage(super.bytes, {super.scale = 1.0});

  static const int _codecVersion = 2;
  final int _version = _codecVersion;

  /// Contenu XML du document SVG.
  String get svgString => utf8.decode(bytes, allowMalformed: true);

  @override
  Future<SvgMemoryImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<SvgMemoryImage>(this);

  @override
  ImageStreamCompleter loadBuffer(
    MemoryImage key,
    DecoderBufferCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _decodeSvgCodec(key.bytes),
    scale: key.scale,
    debugLabel: 'SvgMemoryImage(${describeIdentity(key.bytes)})',
  );

  @override
  ImageStreamCompleter loadImage(
    MemoryImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _decodeSvgCodec(key.bytes),
    scale: key.scale,
    debugLabel: 'SvgMemoryImage(${describeIdentity(key.bytes)})',
  );

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is SvgMemoryImage &&
        other._version == _version &&
        other.scale == scale &&
        listEquals(other.bytes, bytes);
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(bytes), scale, _version);
}

/// Implémentation de [NetworkImage] supportant à la fois les formats matriciels
/// (PNG, JPEG, WebP, GIF, BMP...) et le format vectoriel SVG.
@immutable
class SurfaceNetworkImage extends ImageProvider<NetworkImage>
    implements NetworkImage {
  const SurfaceNetworkImage(
    this.url, {
    this.scale = 1.0,
    this.headers,
    this.webHtmlElementStrategy = WebHtmlElementStrategy.never,
  });

  static const int _codecVersion = 2;
  final int _version = _codecVersion;

  @override
  final String url;

  @override
  final double scale;

  @override
  final Map<String, String>? headers;

  @override
  final WebHtmlElementStrategy webHtmlElementStrategy;

  @override
  Future<SurfaceNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<SurfaceNetworkImage>(this);

  @override
  ImageStreamCompleter loadBuffer(
    NetworkImage key,
    DecoderBufferCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(
        key as SurfaceNetworkImage,
        chunkEvents,
        decode: decode,
      ),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<NetworkImage>('Image key', key),
      ],
    );
  }

  @override
  ImageStreamCompleter loadImage(
    NetworkImage key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(
        key as SurfaceNetworkImage,
        chunkEvents,
        decode: decode,
      ),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<NetworkImage>('Image key', key),
      ],
    );
  }

  static final HttpClient _sharedHttpClient = HttpClient()
    ..autoUncompress = false;

  static HttpClient get _httpClient {
    HttpClient? client;
    assert(() {
      if (debugNetworkImageHttpClientProvider != null) {
        client = debugNetworkImageHttpClientProvider!();
      }
      return true;
    }());
    return client ?? _sharedHttpClient;
  }

  Future<ui.Codec> _loadAsync(
    SurfaceNetworkImage key,
    StreamController<ImageChunkEvent> chunkEvents, {
    required _SimpleDecoderCallback decode,
  }) async {
    try {
      assert(key == this);
      final Uri resolved = Uri.base.resolve(key.url);
      final HttpClientRequest request = await _httpClient.getUrl(resolved);
      headers?.forEach((String name, String value) {
        request.headers.add(name, value);
      });
      final HttpClientResponse response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<List<int>>(<int>[]);
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: resolved,
        );
      }

      final Uint8List bytes = await consolidateHttpClientResponseBytes(
        response,
        onBytesReceived: (int cumulative, int? total) {
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: cumulative,
              expectedTotalBytes: total,
            ),
          );
        },
      );
      if (bytes.lengthInBytes == 0) {
        throw Exception('NetworkImage is an empty file: $resolved');
      }

      final String? mimeType = response.headers.contentType?.mimeType
          .toLowerCase();
      final bool isSvg =
          (mimeType != null && mimeType.contains('svg')) ||
          _looksLikeSvgBytes(bytes) ||
          (_hasSvgExtension(resolved) && !_hasRasterImageMagicBytes(bytes));
      if (isSvg) {
        return await _decodeSvgCodec(bytes);
      }
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (e) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      unawaited(
        chunkEvents.close().catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'painting library',
              context: ErrorDescription(
                'while closing chunkEvents stream in SurfaceNetworkImage.load',
              ),
            ),
          );
        }),
      );
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is SurfaceNetworkImage &&
        other._version == _version &&
        other.url == url &&
        other.scale == scale &&
        mapEquals(other.headers, headers);
  }

  @override
  int get hashCode => Object.hash(
    url,
    scale,
    const MapEquality<String, String>().hash(headers),
    _version,
  );

  @override
  String toString() =>
      '${objectRuntimeType(this, 'NetworkImage')}("$url", scale: ${scale.toStringAsFixed(1)}, webHtmlElementStrategy: ${webHtmlElementStrategy.name}, headers: $headers)';
}

class _SingleFrameInfo implements ui.FrameInfo {
  const _SingleFrameInfo(this.image);

  @override
  final ui.Image image;

  @override
  Duration get duration => Duration.zero;
}

class _SingleFrameCodec implements ui.Codec {
  _SingleFrameCodec(this._image);

  ui.Image? _image;

  @override
  int get frameCount => 1;

  @override
  int get repetitionCount => 0;

  @override
  Future<ui.FrameInfo> getNextFrame() {
    final image = _image;
    if (image == null) {
      return Future<ui.FrameInfo>.error(StateError('Codec has been disposed.'));
    }
    return SynchronousFuture<ui.FrameInfo>(_SingleFrameInfo(image.clone()));
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
  }
}

ImageProvider<Object> _resolveSurfaceImageProvider(String trimmed) {
  if (trimmed.length >= 5 && trimmed.substring(0, 5).toLowerCase() == 'data:') {
    return _resolveDataUriProvider(trimmed);
  }

  if (_looksLikeSvgString(trimmed)) {
    return SvgMemoryImage(Uint8List.fromList(utf8.encode(trimmed)));
  }

  final lower = trimmed.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return SurfaceNetworkImage(trimmed);
  }

  if (lower.startsWith('base64,')) {
    final payload = trimmed.substring(7).trim();
    final decoded = _tryDecodeBase64(payload);
    if (decoded != null) {
      return _looksLikeSvgBytes(decoded)
          ? SvgMemoryImage(decoded)
          : SurfaceMemoryImage(decoded);
    }
    return SurfaceMemoryImage(Uint8List(0));
  }

  final decodedBase64 = _tryDecodeBase64(trimmed);
  if (decodedBase64 != null) {
    if (_looksLikeSvgBytes(decodedBase64)) {
      return SvgMemoryImage(decodedBase64);
    }
    if (_hasRasterImageMagicBytes(decodedBase64)) {
      return SurfaceMemoryImage(decodedBase64);
    }
  }

  return SurfaceNetworkImage(trimmed);
}

ImageProvider<Object> _resolveDataUriProvider(String dataUri) {
  final comma = dataUri.indexOf(',');
  if (comma < 0) {
    return SurfaceMemoryImage(Uint8List(0));
  }
  final metadata = dataUri.substring(5, comma).trim().toLowerCase();
  final payload = dataUri.substring(comma + 1).trim();
  final parts = metadata.split(';').map((part) => part.trim()).toList();
  final mime = parts.isEmpty ? '' : parts.first;
  final isSvgMime = mime.contains('svg');
  final isBase64 = parts.contains('base64');

  if (isBase64) {
    final decoded = _tryDecodeBase64(payload);
    if (decoded == null) {
      return SurfaceMemoryImage(Uint8List(0));
    }
    if (isSvgMime || _looksLikeSvgBytes(decoded)) {
      return SvgMemoryImage(decoded);
    }
    return SurfaceMemoryImage(decoded);
  }

  final text = _decodeDataUriText(payload);
  final textBytes = Uint8List.fromList(utf8.encode(text));
  if (isSvgMime || _looksLikeSvgString(text)) {
    return SvgMemoryImage(textBytes);
  }

  final maybeBase64 = _tryDecodeBase64(payload);
  if (maybeBase64 != null) {
    if (_looksLikeSvgBytes(maybeBase64)) {
      return SvgMemoryImage(maybeBase64);
    }
    if (_hasRasterImageMagicBytes(maybeBase64)) {
      return SurfaceMemoryImage(maybeBase64);
    }
  }

  return SurfaceMemoryImage(textBytes);
}

String _decodeDataUriText(String payload) {
  if (!payload.contains('%')) return payload;
  try {
    return Uri.decodeComponent(payload);
  } on ArgumentError {
    return payload.replaceAllMapped(RegExp(r'(?:%[0-9A-Fa-f]{2})+'), (match) {
      try {
        return Uri.decodeComponent(match.group(0)!);
      } on ArgumentError {
        return match.group(0)!;
      }
    });
  }
}

Uint8List? _tryDecodeBase64(String input) {
  final cleaned = input.replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty) return null;
  if (!RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(cleaned)) return null;
  var normalized = cleaned.replaceAll('-', '+').replaceAll('_', '/');
  final mod = normalized.length % 4;
  if (mod == 1) return null;
  if (mod > 0) {
    normalized = normalized.padRight(normalized.length + (4 - mod), '=');
  }
  try {
    final bytes = base64Decode(normalized);
    return bytes.isEmpty ? null : bytes;
  } on FormatException {
    return null;
  }
}

bool _hasSvgExtension(Uri uri) => uri.path.toLowerCase().endsWith('.svg');

bool _looksLikeSvgString(String input) {
  var trimmed = input.trimLeft();
  if (trimmed.startsWith('\uFEFF')) {
    trimmed = trimmed.substring(1).trimLeft();
  }
  if (trimmed.isEmpty || !trimmed.startsWith('<')) return false;
  final head = trimmed.length > 4096 ? trimmed.substring(0, 4096) : trimmed;
  return RegExp(r'<svg[\s>/]', caseSensitive: false).hasMatch(head);
}

bool _looksLikeSvgBytes(Uint8List bytes) {
  if (bytes.isEmpty || _hasRasterImageMagicBytes(bytes)) return false;
  final sampleLength = math.min(bytes.length, 4096);
  final sample = utf8.decode(
    bytes.sublist(0, sampleLength),
    allowMalformed: true,
  );
  return _looksLikeSvgString(sample);
}

bool _hasRasterImageMagicBytes(Uint8List bytes) {
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return true;
  }
  // JPEG: FF D8 FF
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return true;
  }
  // GIF: GIF87a / GIF89a
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61) {
    return true;
  }
  // WebP: RIFF....WEBP
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  // BMP: BM
  if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return true;
  }
  // ICO / CUR: 00 00 01 00 or 00 00 02 00
  if (bytes.length >= 4 &&
      bytes[0] == 0x00 &&
      bytes[1] == 0x00 &&
      (bytes[2] == 0x01 || bytes[2] == 0x02) &&
      bytes[3] == 0x00) {
    return true;
  }
  return false;
}

Future<ui.Codec> _decodeSvgCodec(Uint8List bytes) async {
  var svgText = utf8.decode(bytes, allowMalformed: true).trim();
  if (svgText.startsWith('\uFEFF')) {
    svgText = svgText.substring(1).trimLeft();
  }
  if (!RegExp(r'<svg[\s>/]', caseSensitive: false).hasMatch(svgText)) {
    throw const FormatException('Contenu SVG invalide.');
  }
  final normalized = _normalizeSvg(svgText);
  final pictureInfo = await vg.loadPicture(SvgStringLoader(normalized), null);
  try {
    final size = pictureInfo.size;
    final baseWidth = size.width.isFinite && size.width > 0
        ? size.width
        : 512.0;
    final baseHeight = size.height.isFinite && size.height > 0
        ? size.height
        : 512.0;
    final maxDim = math.max(baseWidth, baseHeight);
    final scaleFactor = maxDim < 512.0
        ? 512.0 / maxDim
        : (maxDim > 2048.0 ? 2048.0 / maxDim : 1.0);
    final targetWidth = math.max(1, (baseWidth * scaleFactor).round());
    final targetHeight = math.max(1, (baseHeight * scaleFactor).round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(targetWidth / baseWidth, targetHeight / baseHeight);
    canvas.drawPicture(pictureInfo.picture);
    final rasterPicture = recorder.endRecording();
    try {
      final image = rasterPicture.toImageSync(targetWidth, targetHeight);
      return _SingleFrameCodec(image);
    } finally {
      rasterPicture.dispose();
    }
  } finally {
    pictureInfo.picture.dispose();
  }
}

final RegExp _cssColorFunctionPattern = RegExp(
  r'color\(\s*[a-zA-Z0-9_-]+\s+'
  r'([+-]?(?:\d+\.?\d*|\.\d+)%?|\bnone\b)\s+'
  r'([+-]?(?:\d+\.?\d*|\.\d+)%?|\bnone\b)\s+'
  r'([+-]?(?:\d+\.?\d*|\.\d+)%?|\bnone\b)'
  r'(?:\s*/\s*([+-]?(?:\d+\.?\d*|\.\d+)%?|\bnone\b))?\s*\)',
  caseSensitive: false,
);

final RegExp _cssVarWithFallbackPattern = RegExp(
  r'var\(\s*--[a-zA-Z0-9_-]+\s*,\s*([^)]+)\)',
  caseSensitive: false,
);

const Set<String> _svgPaintProperties = <String>{
  'fill',
  'stroke',
  'color',
  'stop-color',
  'flood-color',
  'lighting-color',
  'text-decoration-color',
};

String _normalizeSvg(String svg) {
  var result = _ensureSvgDimensions(svg);
  result = _replaceCssColorFunctions(result);
  while (_cssVarWithFallbackPattern.hasMatch(result)) {
    result = result.replaceAllMapped(
      _cssVarWithFallbackPattern,
      (match) => match.group(1)!.trim(),
    );
  }
  result = _sanitizeStyleAttributes(result);
  return result;
}

String _replaceCssColorFunctions(String svg) =>
    svg.replaceAllMapped(_cssColorFunctionPattern, (match) {
      final r = _parseCssColorChannel(match.group(1)!);
      final g = _parseCssColorChannel(match.group(2)!);
      final b = _parseCssColorChannel(match.group(3)!);
      final a = _parseCssColorAlpha(match.group(4));
      if (a >= 1.0) {
        final hex =
            '${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}';
        return '#${hex.toUpperCase()}';
      }
      return 'rgba($r, $g, $b, $a)';
    });

int _parseCssColorChannel(String raw) {
  final trimmed = raw.trim().toLowerCase();
  if (trimmed == 'none' || trimmed.isEmpty) return 0;
  if (trimmed.endsWith('%')) {
    final pct = double.tryParse(trimmed.substring(0, trimmed.length - 1)) ?? 0;
    return (pct.clamp(0.0, 100.0) * 2.55).round().clamp(0, 255);
  }
  final val = double.tryParse(trimmed) ?? 0;
  return (val.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
}

double _parseCssColorAlpha(String? raw) {
  if (raw == null) return 1.0;
  final trimmed = raw.trim().toLowerCase();
  if (trimmed == 'none' || trimmed.isEmpty) return 0.0;
  if (trimmed.endsWith('%')) {
    final pct =
        double.tryParse(trimmed.substring(0, trimmed.length - 1)) ?? 100;
    return (pct / 100.0).clamp(0.0, 1.0);
  }
  final val = double.tryParse(trimmed) ?? 1.0;
  return val.clamp(0.0, 1.0);
}

String _sanitizeStyleAttributes(String svg) => svg.replaceAllMapped(
  RegExp(r'''\bstyle\s*=\s*(?:"([^"]*)"|'([^']*)')''', caseSensitive: false),
  (match) {
    final quote = match.group(1) != null ? '"' : "'";
    final content = match.group(1) ?? match.group(2) ?? '';
    final declarations = <String>[];
    for (final rawDecl in content.split(';')) {
      final decl = rawDecl.trim();
      if (decl.isEmpty) continue;
      final colon = decl.indexOf(':');
      if (colon <= 0) continue;
      final prop = decl.substring(0, colon).trim().toLowerCase();
      var val = decl.substring(colon + 1).trim();
      if (val.toLowerCase().endsWith('!important')) {
        val = val.substring(0, val.length - 10).trim();
      }
      if (_svgPaintProperties.contains(prop) &&
          !_isSupportedSvgPaintValue(val)) {
        continue;
      }
      declarations.add('$prop:$val');
    }
    if (declarations.isEmpty) return '';
    return 'style=$quote${declarations.join(';')}$quote';
  },
);

bool _isSupportedSvgPaintValue(String value) {
  final v = value.trim().toLowerCase();
  if (v.isEmpty) return false;
  if (v == 'none' || v == 'currentcolor' || v == 'inherit') return true;
  if (v.startsWith('#') ||
      v.startsWith('rgb(') ||
      v.startsWith('rgba(') ||
      v.startsWith('hsl(') ||
      v.startsWith('hsla(') ||
      v.startsWith('url(')) {
    return true;
  }
  return RegExp(r'^[a-z]+$').hasMatch(v);
}

String _ensureSvgDimensions(String svg) {
  final svgTagMatch = RegExp(
    r'<svg\b[^>]*>',
    caseSensitive: false,
  ).firstMatch(svg);
  if (svgTagMatch == null) return svg;
  var tag = svgTagMatch.group(0)!;
  var modified = false;

  if (!RegExp(r'\bviewBox\s*=').hasMatch(tag) &&
      RegExp(r'\bviewbox\s*=', caseSensitive: false).hasMatch(tag)) {
    tag = tag.replaceFirst(
      RegExp(r'\bviewbox(\s*=)', caseSensitive: false),
      r'viewBox$1',
    );
    modified = true;
  }

  final hasViewBox = RegExp(r'''\bviewBox\s*=\s*(?:"[^"]+"|'[^']+')''')
      .hasMatch(tag);
  if (!hasViewBox) {
    final width = _extractPositiveSvgLength(tag, 'width');
    final height = _extractPositiveSvgLength(tag, 'height');
    if (width == null || height == null) {
      final w = width ?? 100;
      final h = height ?? 100;
      tag = tag.replaceFirst(
        RegExp(r'^<svg\b', caseSensitive: false),
        '<svg viewBox="0 0 $w $h"',
      );
      modified = true;
    }
  }

  if (!modified) return svg;
  return svg.replaceRange(svgTagMatch.start, svgTagMatch.end, tag);
}

double? _extractPositiveSvgLength(String tag, String attrName) {
  final match = RegExp(
    '\\b$attrName\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')',
    caseSensitive: false,
  ).firstMatch(tag);
  if (match == null) return null;
  final raw = (match.group(1) ?? match.group(2) ?? '').trim();
  if (raw.isEmpty || raw.endsWith('%')) return null;
  final numMatch = RegExp(
    r'^([+-]?(?:\d+\.?\d*|\.\d+))(?:px)?$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (numMatch == null) return null;
  final value = double.tryParse(numMatch.group(1)!);
  return value != null && value.isFinite && value > 0 ? value : null;
}
