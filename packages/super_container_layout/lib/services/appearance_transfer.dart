import 'dart:convert';
import 'appearance_store.dart';
import '../theme/appearance.dart';

enum TransferGroup {
  styles('Styles'), layouts('Dispositions');
  const TransferGroup(this.label);
  final String label;
}

/// Transfers generic groups through the application's injected codec.
class AppearanceTransfer {
  const AppearanceTransfer._();
  static const format = 'super_container_layout.appearance';
  static TransferGroup _groupOf(String key) => key == 'layouts' ? TransferGroup.layouts : TransferGroup.styles;
  static String export(Appearance appearance, Set<TransferGroup> groups, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    if (groups.isEmpty) throw ArgumentError.value(groups, 'groups', 'No groups selected.');
    final data = codec.toJson(appearance)..remove('version');
    return const JsonEncoder.withIndent('  ').convert({
      'format': codec.format, 'version': codec.schemaVersion,
      'groups': [for (final group in TransferGroup.values) if (groups.contains(group)) group.name],
      'data': {for (final entry in data.entries) if (groups.contains(_groupOf(entry.key))) entry.key: entry.value},
    });
  }
  static ({Map<String, Object?> data, int version}) _document(String text, AppearanceCodec codec) {
    final Object? json;
    try { json = jsonDecode(text); }
    on FormatException { throw const FormatException('Le texte n’est pas un JSON valide.'); }
    if (json is! Map<String, dynamic>) throw const FormatException('Invalid appearance export.');
    final version = json['version'];
    if (version is! int) throw const FormatException('Invalid export version.');
    if (json.containsKey('format')) {
      if (json['format'] != codec.format || json['data'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid appearance export format or data.');
      }
      final groups = json['groups'];
      if (groups is! List || groups.isEmpty || groups.any((v) => !TransferGroup.values.any((g) => g.name == v))) {
        throw const FormatException('Invalid export groups.');
      }
      return (data: codec.normalizeTransfer(json['data'] as Map<String, dynamic>, version), version: version);
    }
    return (data: codec.normalizeTransfer({...json}..remove('version'), version), version: version);
  }
  static Set<TransferGroup> groupsIn(String text, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final data = _document(text, codec).data;
    final known = codec.toJson(codec.defaults).keys.toSet()..remove('version');
    final groups = {for (final key in data.keys) if (known.contains(key)) _groupOf(key)};
    if (groups.isEmpty) throw const FormatException('No styles or layouts found.');
    return groups;
  }
  static Appearance import(Appearance current, String text, Set<TransferGroup> groups, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final selected = groups.intersection(groupsIn(text, codec: codec));
    if (selected.isEmpty) throw const FormatException('No selected groups to import.');
    final merged = codec.toJson(current);
    final document = _document(text, codec);
    for (final entry in document.data.entries) {
      if (merged.containsKey(entry.key) && selected.contains(_groupOf(entry.key))) {
        merged[entry.key] = codec.mergeTransferValue(entry.key, merged[entry.key], entry.value, document.version);
      }
    }
    final documentText = jsonEncode(merged);
    final result = codec.decode(documentText);
    codec.restoreAdditional(documentText);
    return result;
  }
}
