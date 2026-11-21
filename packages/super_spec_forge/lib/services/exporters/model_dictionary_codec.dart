/// Exportateur et importateur JSON / Markdown du dictionnaire technique de modélisation ([ModelDictionaryCodec]).
library;

import 'dart:convert';

import '../../models/business_object_model_preferences.dart';
import '../model_dictionary_store.dart';

/// Sérialise et désérialise [BusinessObjectModelPreferences] et ses règles techniques.
abstract final class ModelDictionaryCodec {
  static const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

  /// Exporte [preferences] en JSON structuré ré-importable.
  static String toJsonString(BusinessObjectModelPreferences preferences) =>
      _prettyJson.convert(<String, Object?>{
        'format': ModelDictionaryStore.fileFormat,
        'version': ModelDictionaryStore.storageVersion,
        'data': preferences.toJson(),
      });

  /// Parse une chaîne JSON vers [BusinessObjectModelPreferences] validées.
  static BusinessObjectModelPreferences parseJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Le contenu JSON est vide.');
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      throw const FormatException(
        'Le document JSON doit être un objet.',
      );
    }
    final payload = decoded['data'] is Map ? decoded['data'] : decoded;
    final parsed = BusinessObjectModelPreferences.fromJson(payload);
    parsed.validate();
    return parsed;
  }

  /// Exporte [preferences] et son dictionnaire technique en documentation Markdown.
  static String toMarkdown(BusinessObjectModelPreferences preferences) {
    final buf = StringBuffer()
      ..writeln('# Dictionnaire technique & Règles de modélisation')
      ..writeln()
      ..writeln('> Référentiel global — SuperSpecForge')
      ..writeln()
      ..writeln('## 1. Conventions générales')
      ..writeln(
        '- **Langue attributs / enum / textes** : '
        '${BusinessObjectModelPreferences.describeLanguage(preferences.attributeLanguage)} / '
        '${BusinessObjectModelPreferences.describeLanguage(preferences.enumLanguage)} / '
        '${BusinessObjectModelPreferences.describeLanguage(preferences.contentLanguage)}',
      )
      ..writeln(
        '- **Casse attributs / enums** : ${preferences.attributeCase.label} / ${preferences.enumCase.label}',
      )
      ..writeln('- **Clé primaire** : ${preferences.idStrategy.label}')
      ..writeln('- **Clés étrangères** : ${preferences.foreignKeyStyle.label}')
      ..writeln(
        '- **Arbitrage Id / Ref / Code / Number** : ${preferences.enforceIdRefCodeNumberDistinction ? 'Strict' : 'Souple'}',
      )
      ..writeln('- **Dates & horodatages** : ${preferences.dateTimeSuffixPolicy.label}')
      ..writeln('- **Booléens** : ${preferences.booleanPrefixPolicy.label}')
      ..writeln('- **Unités & quantités** : ${preferences.unitSuffixPolicy.label}')
      ..writeln('- **Audit** : ${preferences.auditPreset.label}')
      ..writeln('- **Soft-delete** : ${preferences.softDeleteStrategy.label}')
      ..writeln(
        '- **Concurrence optimiste** : ${preferences.optimisticLockingStrategy.label}',
      )
      ..writeln(
        '- **Rigueur JSON Schema** : ${preferences.schemaStrictness.label} '
        '(maxLength défaut : code=${preferences.defaultCodeMaxLength}, '
        'libellé=${preferences.defaultLabelMaxLength}, '
        'description=${preferences.defaultDescriptionMaxLength})',
      )
      ..writeln()
      ..writeln('## 2. Dictionnaire des règles techniques')
      ..writeln();

    if (preferences.technicalRules.isEmpty) {
      buf.writeln('_Aucune règle technique enregistrée._');
      return buf.toString();
    }

    buf
      ..writeln(
        '| Motif | Règle | Catégorie | Actif | Quand l’utiliser | À éviter | Format recommandé | Exemples |',
      )
      ..writeln('|---|---|---|---|---|---|---|---|');
    for (final r in preferences.technicalRules) {
      buf.writeln(
        '| `${_esc(r.suffixOrPattern)}` '
        '| **${_esc(r.name)}** '
        '| ${_esc(r.category.label)} '
        '| ${r.enabled ? 'Oui' : 'Non'} '
        '| ${_esc(r.whenToUse)} '
        '| ${_esc(r.whenNotToUse.isEmpty ? '—' : r.whenNotToUse)} '
        '| ${_esc(r.recommendedType.isEmpty ? '—' : r.recommendedType)} '
        '| ${_esc(r.goodExamples.isEmpty ? '—' : r.goodExamples.join(', '))} |',
      );
    }
    return buf.toString();
  }

  static String _esc(String text) =>
      text.replaceAll('|', r'\|').replaceAll('\n', ' ');
}
