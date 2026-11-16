/// Modélisation de l'usage déclaré d'un composant ([ComponentUsage]).
///
/// L'usage est une métadonnée d'édition saisie dans le dialogue « Renommer le
/// composant » ou proposée par l'assistant IA (uniquement pour les composants
/// sans liaison de données) : il qualifie le rôle fonctionnel d'une instance
/// (texte d'explication traduit, données dynamiques ou statiques, saisie,
/// action…). Il est stocké à plat par identifiant d'instance dans
/// `Appearance.usages` et n'influence pas le rendu.
library;

import 'package:material_ui/material_ui.dart';

/// Rôle fonctionnel déclaré pour un composant.
enum ComponentUsageKind {
  /// Texte d'explication destiné à être traduit (clé de traduction requise).
  explanation(
    'Texte d\'explication (traduction)',
    'Libellé, titre ou aide traduisible via une clé de traduction',
    Icons.translate,
  ),

  /// Valeur issue des données de l'application, susceptible de changer.
  dynamicData(
    'Données dynamiques',
    'Valeur issue des données de l\'application',
    Icons.sync_alt,
  ),

  /// Contenu fixe non traduit (référence, code, valeur constante).
  staticData(
    'Données statiques',
    'Contenu fixe, non traduit et indépendant des données',
    Icons.text_snippet_outlined,
  ),

  /// Champ ou contrôle modifié par l'utilisateur.
  userInput(
    'Saisie utilisateur',
    'Champ, choix ou contrôle modifié par l\'utilisateur',
    Icons.edit_note,
  ),

  /// Élément déclenchant une action ou une navigation.
  action(
    'Action / navigation',
    'Bouton, lien ou élément déclenchant une action',
    Icons.touch_app_outlined,
  ),

  /// Conteneur structurant la mise en page.
  layout(
    'Structure / mise en page',
    'Conteneur ou zone organisant d\'autres composants',
    Icons.dashboard_outlined,
  ),

  /// Élément purement visuel (icône, image, séparateur).
  decoration(
    'Décoration / illustration',
    'Icône, image ou séparateur purement visuel',
    Icons.palette_outlined,
  ),

  /// Message d'état, d'erreur, de chargement ou de résultat.
  feedback(
    'Retour d\'état / message',
    'Message d\'erreur, de chargement, de vide ou de succès',
    Icons.feedback_outlined,
  );

  const ComponentUsageKind(this.label, this.description, this.icon);

  /// Libellé affiché dans l'éditeur.
  final String label;

  /// Explication courte affichée sous le libellé.
  final String description;

  /// Icône illustrant l'usage.
  final IconData icon;

  /// Retrouve un usage depuis son nom JSON, ou `null` s'il est inconnu.
  static ComponentUsageKind? tryParse(String value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

/// Usage déclaré d'une instance de composant.
@immutable
class ComponentUsage {
  /// Crée un usage ; [translationKey] n'est admis que pour
  /// [ComponentUsageKind.explanation], pour lequel il est obligatoire.
  const ComponentUsage({required this.kind, this.translationKey});

  /// Crée un usage de texte d'explication associé à [translationKey].
  const ComponentUsage.explanation(String this.translationKey)
    : kind = ComponentUsageKind.explanation;

  /// Format des clés de traduction (ARB / gen-l10n), ex. `homeTitle`.
  static final translationKeyPattern = RegExp(r'^[a-z][a-zA-Z0-9_]*$');

  /// Rôle fonctionnel du composant.
  final ComponentUsageKind kind;

  /// Clé de traduction du texte d'explication.
  final String? translationKey;

  /// Indique si l'usage exige une clé de traduction.
  bool get requiresTranslationKey => kind == ComponentUsageKind.explanation;

  /// Retourne un message d'erreur si [value] n'est pas une clé valide.
  static String? translationKeyError(String? value) {
    final key = value?.trim() ?? '';
    if (key.isEmpty) return 'La clé de traduction est obligatoire.';
    if (!translationKeyPattern.hasMatch(key)) {
      return 'Format attendu : lowerCamelCase sans espace ni accent '
          '(ex. homeTitle).';
    }
    return null;
  }

  /// Propose une clé de traduction lowerCamelCase dérivée de [label].
  ///
  /// « Titre principal » donne `titrePrincipal` ; une clé commençant par un
  /// chiffre est préfixée par `text`.
  static String suggestTranslationKey(String label) {
    final words = _removeDiacritics(label)
        .split(RegExp(r'[^a-zA-Z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < words.length; i++) {
      final raw = words[i];
      final word = raw.length > 1 && raw == raw.toUpperCase()
          ? raw.toLowerCase()
          : raw;
      final head = i == 0 ? word[0].toLowerCase() : word[0].toUpperCase();
      buffer
        ..write(head)
        ..write(word.substring(1));
    }
    final key = buffer.toString();
    return RegExp(r'^[0-9]').hasMatch(key) ? 'text$key' : key;
  }

  /// Vérifie les invariants de l'usage.
  void validate() {
    if (requiresTranslationKey) {
      final error = translationKeyError(translationKey);
      if (error != null || translationKey != translationKey!.trim()) {
        throw FormatException(error ?? 'Clé de traduction invalide.');
      }
    } else if (translationKey != null) {
      throw FormatException(
        'translationKey est réservé à l\'usage ${ComponentUsageKind.explanation.name}.',
      );
    }
  }

  /// Copie l'usage ; [clearTranslationKey] retire la clé de traduction.
  ComponentUsage copyWith({
    ComponentUsageKind? kind,
    String? translationKey,
    bool clearTranslationKey = false,
  }) => ComponentUsage(
    kind: kind ?? this.kind,
    translationKey: clearTranslationKey
        ? null
        : translationKey ?? this.translationKey,
  );

  /// Sérialise l'usage.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (translationKey != null) 'translationKey': translationKey,
  };

  /// Sérialisation compacte, identique à [toJson] (aucun champ par défaut).
  Map<String, Object?> toCompactJson() => toJson();

  /// Désérialise un usage ; lève une [FormatException] si [json] est invalide.
  factory ComponentUsage.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Un usage doit être un objet JSON.');
    }
    const known = {'kind', 'translationKey'};
    for (final key in json.keys) {
      if (!known.contains(key)) {
        throw FormatException('Propriété d\'usage inconnue : $key.');
      }
    }
    final rawKind = json['kind'];
    final kind = rawKind is String ? ComponentUsageKind.tryParse(rawKind) : null;
    if (kind == null) {
      throw FormatException('Usage inconnu : $rawKind.');
    }
    final rawKey = json['translationKey'];
    if (rawKey != null && rawKey is! String) {
      throw const FormatException('translationKey doit être une chaîne.');
    }
    final usage = ComponentUsage(kind: kind, translationKey: rawKey as String?);
    usage.validate();
    return usage;
  }

  @override
  bool operator ==(Object other) =>
      other is ComponentUsage &&
      other.kind == kind &&
      other.translationKey == translationKey;

  @override
  int get hashCode => Object.hash(kind, translationKey);

  @override
  String toString() => 'ComponentUsage(${kind.name}'
      '${translationKey == null ? '' : ', $translationKey'})';
}

const _diacritics = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae', //
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', //
  'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', //
  'ö': 'o', 'ø': 'o', 'œ': 'oe', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', //
  'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
};

String _removeDiacritics(String value) {
  final buffer = StringBuffer();
  for (final char in value.split('')) {
    final lower = char.toLowerCase();
    final replacement = _diacritics[lower];
    if (replacement == null) {
      buffer.write(char);
    } else {
      buffer.write(
        char == lower ? replacement : replacement.toUpperCase(),
      );
    }
  }
  return buffer.toString();
}
