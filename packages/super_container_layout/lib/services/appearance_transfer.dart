import 'dart:convert';

import 'appearance_store.dart';
import '../theme/appearance.dart';

/// Ce que contient un export : les styles, les dispositions, ou les deux.
enum TransferGroup {
  styles('Styles'),
  layouts('Dispositions');

  const TransferGroup(this.label);

  final String label;
}

/// Export et import du style et de la disposition, séparément ou ensemble.
///
/// Le fichier est une enveloppe JSON `{format, version, groups, data}` dont
/// `data` reprend les clés du paramétrage enregistré ([AppearanceStore]). Un
/// paramétrage complet brut (sans enveloppe) est aussi accepté à l'import.
class AppearanceTransfer {
  const AppearanceTransfer._();

  static const format = 'surf_file.appearance';

  /// Clés des dispositions ; toutes les autres clés sont des styles.
  static const layoutKeys = {
    'explorerLayout',
    'explorerMainLayout',
    'explorerSidebarLayout',
  };

  static Map<String, Object?> _encoded(Appearance appearance) =>
      Map<String, Object?>.from(
        jsonDecode(AppearanceStore.encode(appearance)) as Map,
      )..remove('version');

  static TransferGroup? _groupOf(String key) =>
      layoutKeys.contains(key) ? TransferGroup.layouts : TransferGroup.styles;

  /// Texte JSON de [appearance] limité à [groups].
  static String export(Appearance appearance, Set<TransferGroup> groups) {
    if (groups.isEmpty) {
      throw ArgumentError.value(groups, 'groups', 'Aucun groupe à exporter');
    }
    final data = {
      for (final MapEntry(:key, :value) in _encoded(appearance).entries)
        if (groups.contains(_groupOf(key))) key: value,
    };
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': AppearanceStore.version,
      'groups': [
        for (final group in TransferGroup.values)
          if (groups.contains(group)) group.name,
      ],
      'data': data,
    });
  }

  static Map<String, Object?> _data(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Le texte n’est pas un JSON valide.');
    }
    if (json is! Map) {
      throw const FormatException('Le fichier n’est pas un export SurfFile.');
    }
    if (json.containsKey('format')) {
      if (json['format'] != format) {
        throw const FormatException('Le fichier n’est pas un export SurfFile.');
      }
      if (json['version'] != AppearanceStore.version) {
        throw const FormatException('Version d’export non prise en charge.');
      }
      final data = json['data'];
      if (data is! Map) {
        throw const FormatException('Le fichier ne contient aucune donnée.');
      }
      return Map<String, Object?>.from(data);
    }
    if (json['version'] == AppearanceStore.version) {
      return Map<String, Object?>.from(json)..remove('version');
    }
    throw const FormatException('Le fichier n’est pas un export SurfFile.');
  }

  /// Groupes présents dans [text] ; une [FormatException] décrit un export
  /// invalide ou sans données.
  static Set<TransferGroup> groupsIn(String text) {
    final data = _data(text);
    final known = _encoded(const Appearance()).keys.toSet();
    final groups = {
      for (final key in data.keys)
        if (known.contains(key)) _groupOf(key)!,
    };
    if (groups.isEmpty) {
      throw const FormatException(
        'Aucun style ni aucune disposition dans ce fichier.',
      );
    }
    return groups;
  }

  /// [current] dont les groupes [groups] sont remplacés par ceux de [text].
  /// Le résultat est entièrement validé : une valeur incorrecte lève une
  /// [FormatException] et ne modifie rien.
  static Appearance import(
    Appearance current,
    String text,
    Set<TransferGroup> groups,
  ) {
    final available = groupsIn(text);
    final selected = groups.intersection(available);
    if (selected.isEmpty) {
      throw const FormatException('Rien à importer pour cette sélection.');
    }
    final merged = _encoded(current);
    for (final MapEntry(:key, :value) in _data(text).entries) {
      if (merged.containsKey(key) && selected.contains(_groupOf(key))) {
        merged[key] = value;
      }
    }
    return AppearanceStore.decode(
      jsonEncode({'version': AppearanceStore.version, ...merged}),
    );
  }
}
