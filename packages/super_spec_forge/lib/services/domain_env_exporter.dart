/// Génération sûre et déterministe d'un export dotenv sans valeur de secret
/// ([DomainEnvExporter]).
library;

import '../models/domain_catalog.dart';

/// Produit un contenu `.env` trié, LF et sans jamais déchiffrer les secrets.
abstract final class DomainEnvExporter {
  /// Exporte les variables en clair et des placeholders commentés pour les secrets.
  static String toEnv(Iterable<ConfigurationEntry> entries) {
    final sorted = entries.toList()
      ..sort((a, b) => a.configKey.compareTo(b.configKey));
    final lines = <String>[];
    for (final entry in sorted) {
      entry.validate();
      if (entry.entryType == ConfigurationEntryType.secret) {
        lines.add('# ${entry.configKey}=<SECRET_EXCLUDED>');
      } else {
        lines.add(
          '${entry.configKey}=${_formatValue(entry.plainValue ?? '')}',
        );
      }
    }
    return lines.isEmpty ? '' : '${lines.join('\n')}\n';
  }

  static String _formatValue(String value) {
    if (value.isEmpty || RegExp(r'''[\s#'"\\]''').hasMatch(value)) {
      final escaped = value
          .replaceAll('\\', r'\\')
          .replaceAll('"', r'\"')
          .replaceAll('\r', r'\r')
          .replaceAll('\n', r'\n');
      return '"$escaped"';
    }
    return value;
  }
}
