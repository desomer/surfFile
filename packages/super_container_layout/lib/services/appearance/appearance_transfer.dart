import 'dart:convert';

import 'appearance_codec.dart';
import '../../theme/appearance.dart';

enum TransferGroup {
  styles('Styles'),
  layouts('Dispositions');

  const TransferGroup(this.label);
  final String label;
}

/// Transfers generic groups through the application's injected codec.
class AppearanceTransfer {
  const AppearanceTransfer._();
  static const format = 'super_container_layout.appearance';
  static TransferGroup _groupOf(String key) =>
      key == 'components' || key == 'pageCatalog'
      ? TransferGroup.layouts
      : TransferGroup.styles;

  static String export(
    Appearance appearance,
    Set<TransferGroup> groups, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    if (groups.isEmpty) {
      throw ArgumentError.value(groups, 'groups', 'No groups selected.');
    }
    final rawCodecData = codec.toJson(appearance)..remove('version');
    return const JsonEncoder.withIndent('  ').convert({
      'format': codec.format,
      'version': codec.schemaVersion,
      'groups': [
        for (final group in TransferGroup.values)
          if (groups.contains(group)) group.name,
      ],
      'data': {
        for (final entry in rawCodecData.entries)
          if (groups.contains(_groupOf(entry.key))) entry.key: entry.value,
      },
    });
  }

  static ({Map<String, Object?> data, int version}) _document(
    String text,
    AppearanceCodec codec,
  ) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Le texte n’est pas un JSON valide.');
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid appearance export.');
    }
    final isPatch =
        json['vibe'] == true ||
        json['merge'] == true ||
        json['mode'] == 'vibe';
    final version = json.containsKey('version')
        ? json['version']
        : (isPatch ? codec.schemaVersion : null);
    if (version is! int) throw const FormatException('Invalid export version.');
    if (json.containsKey('format')) {
      if ((json['format'] != codec.format &&
              json['format'] != AppearanceTransfer.format) ||
          json['data'] is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid appearance export format or data.',
        );
      }
      if (json.containsKey('groups')) {
        final groups = json['groups'];
        if (groups is! List ||
            groups.isEmpty ||
            groups.any((v) => !TransferGroup.values.any((g) => g.name == v))) {
          throw const FormatException('Invalid export groups.');
        }
      }
      return (
        data: codec.normalizeTransfer(
          json['data'] as Map<String, dynamic>,
          version,
        ),
        version: version,
      );
    }
    return (
      data: codec.normalizeTransfer({...json}..remove('version'), version),
      version: version,
    );
  }

  static Set<TransferGroup> groupsIn(
    String text, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final data = _document(text, codec).data;
    final known = {...codec.toJson(codec.defaults).keys}..remove('version');
    final groups = <TransferGroup>{
      for (final key in data.keys)
        if (known.contains(key)) _groupOf(key),
    };
    if (groups.isEmpty) {
      throw const FormatException('No styles or layouts found.');
    }
    return groups;
  }

  static Appearance import(
    Appearance current,
    String text,
    Set<TransferGroup> groups, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final selected = groups.intersection(groupsIn(text, codec: codec));
    if (selected.isEmpty) {
      throw const FormatException('No selected groups to import.');
    }
    final document = _document(text, codec);
    final dataMap = <String, dynamic>{
      for (final e in document.data.entries) e.key: e.value,
    };

    final isMerge =
        dataMap['vibe'] == true ||
        dataMap['merge'] == true ||
        dataMap['mode'] == 'vibe';
    if (isMerge) {
      final filtered = <String, dynamic>{
        for (final entry in dataMap.entries)
          if (entry.key == 'vibe' ||
              entry.key == 'merge' ||
              selected.contains(_groupOf(entry.key)))
            entry.key: entry.value,
      };
      final patched = codec.patchFromJson(current, filtered);
      final encoded = codec.encode(patched);
      final result = codec.decode(encoded);
      codec.restoreAdditional(encoded);
      return result;
    }

    final merged = codec.toJson(current);
    for (final entry in dataMap.entries) {
      if (entry.key == 'version' ||
          entry.key == 'vibe' ||
          entry.key == 'merge') {
        continue;
      }
      if (merged.containsKey(entry.key) &&
          selected.contains(_groupOf(entry.key))) {
        merged[entry.key] = codec.mergeTransferValue(
          entry.key,
          merged[entry.key],
          entry.value,
          document.version,
        );
      }
    }
    for (final key in codec.additionalKeys) {
      if (dataMap.containsKey(key) && selected.contains(_groupOf(key))) {
        merged[key] = dataMap[key];
      }
    }
    final documentText = jsonEncode(merged);
    final result = codec.decode(documentText);
    codec.restoreAdditional(documentText);
    return result;
  }

  /// Applies an incremental GenUI-style surface update onto [current].
  static Appearance applyVibe(
    Appearance current,
    String text, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Le texte n’est pas un JSON valide.');
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid appearance export.');
    }
    final payload = raw['data'] is Map<String, dynamic>
        ? <String, dynamic>{
            ...(raw['data'] as Map<String, dynamic>),
            'merge': true,
          }
        : <String, dynamic>{...raw, 'merge': true};
    return import(
      current,
      jsonEncode(payload),
      const {TransferGroup.styles, TransferGroup.layouts},
      codec: codec,
    );
  }

  /// Exports the flat GenUI JSON representation for AI or transfer.
  static String exportAi(
    Appearance appearance, {
    Set<TransferGroup> groups = const {
      TransferGroup.styles,
      TransferGroup.layouts,
    },
    AppearanceCodec codec = const AppearanceCodec(),
  }) => export(appearance, groups, codec: codec);
}
