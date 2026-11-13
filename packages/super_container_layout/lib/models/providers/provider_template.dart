/// Gabarits `{{...}}` des providers de données : analyse et rendu.
///
/// Un gabarit insère dans une URL, un en-tête, un paramètre de requête ou un
/// corps JSON des valeurs lues dans le repository de filtre d'un provider
/// (`{{q}}`, `{{page.index}}`) ou dans l'environnement (`{{env.PROVIDER_TOKEN}}`).
/// Le moteur est pur (aucune I/O) : [ProviderTemplate] porte la syntaxe,
/// [ProviderTemplateContext] fournit les valeurs, et `HttpProviderConfig`
/// l'utilise pour valider ses champs avant que `HttpDataProvider` ne l'exécute.
///
/// ## Syntaxe
///
/// * `{{chemin}}` : chemin `JsonAttributePath` sans `[?]` dans le document de
///   filtre ;
/// * `{{env.NOM}}` : variable d'environnement (`env.` est un préfixe réservé) ;
/// * dans un corps JSON, une chaîne qui est *exactement* `{{x}}` garde le type
///   de la valeur lue (nombre, booléen, tableau, objet).
///
/// Une valeur de filtre absente ou vide fait omettre l'entrée qui la contient
/// (paramètre de requête, champ du corps, en-tête) mais produit une erreur
/// dans l'URL. Une variable d'environnement introuvable est toujours une
/// erreur : un secret manquant ne doit pas partir silencieusement sans
/// authentification.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../json_text_binding.dart';

/// Résout la variable d'environnement [name] ; `null` si elle est absente ou
/// non autorisée.
typedef ProviderEnvResolver = String? Function(String name);

final _placeholderPattern = RegExp(r'\{\{([^{}]*)\}\}');
final _envNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$');
final _firstSegmentPattern = RegExp(r'^[^.\[]+');

/// Profondeur maximale d'un gabarit de corps JSON.
const providerBodyMaxDepth = 16;

/// Taille maximale (JSON encodé) d'un gabarit de corps.
const providerBodyMaxBytes = 64 * 1024;

/// Référence `{{...}}` : attribut du filtre ou variable d'environnement.
@immutable
class ProviderTemplateReference {
  const ProviderTemplateReference._({required this.isEnv, required this.key});

  /// Décode le contenu d'un `{{...}}`.
  ///
  /// Lève une [FormatException] si ce n'est ni un chemin de filtre résolu
  /// (sans `[?]` ni `@calculé`) ni un nom de variable d'environnement valide.
  factory ProviderTemplateReference.parse(String expression) {
    final trimmed = expression.trim();
    if (trimmed.startsWith('env.')) {
      final name = trimmed.substring(4);
      if (!_envNamePattern.hasMatch(name)) {
        throw FormatException(
          'Variable d’environnement invalide : {{$trimmed}}.',
        );
      }
      return ProviderTemplateReference._(isEnv: true, key: name);
    }
    try {
      final path = JsonAttributePath(trimmed)..requireResolved();
      final canonical = path.toString();
      if (path.calculated != null || canonical.startsWith('[')) {
        throw const FormatException('chemin non lisible dans un filtre');
      }
      return ProviderTemplateReference._(isEnv: false, key: canonical);
    } on FormatException {
      throw FormatException(
        'Gabarit invalide : {{$trimmed}} doit être un chemin du filtre '
        '(sans [?]) ou {{env.NOM}}.',
      );
    }
  }

  /// Vrai pour `{{env.NOM}}`.
  final bool isEnv;

  /// Nom de la variable d'environnement, ou chemin canonique de l'attribut du
  /// filtre.
  final String key;

  /// Clé de premier niveau du filtre lue par cette référence (vide pour une
  /// variable d'environnement).
  String get filterKey =>
      isEnv ? '' : _firstSegmentPattern.firstMatch(key)?.group(0) ?? key;

  /// Forme affichable (`env.NOM` ou le chemin).
  String get label => isEnv ? 'env.$key' : key;

  @override
  bool operator ==(Object other) =>
      other is ProviderTemplateReference &&
      other.isEnv == isEnv &&
      other.key == key;

  @override
  int get hashCode => Object.hash(isEnv, key);
}

/// Valeurs disponibles pendant le rendu d'un gabarit.
@immutable
class ProviderTemplateContext {
  /// [filter] est le document de paramètres (objet JSON, éventuellement vide) ;
  /// [env] résout les variables `{{env.NOM}}`.
  const ProviderTemplateContext({required this.filter, this.env});

  /// Document de filtre lu par les références `{{chemin}}`.
  final Object? filter;

  /// Résolveur des variables d'environnement ; sans lui, elles sont toutes
  /// introuvables.
  final ProviderEnvResolver? env;

  /// Valeur brute de [reference] ; `null` si elle est absente ou si la
  /// structure du filtre ne correspond pas au chemin.
  Object? resolve(ProviderTemplateReference reference) {
    if (reference.isEnv) return env?.call(reference.key);
    try {
      return JsonAttributePath(reference.key).readNode(filter);
    } on FormatException {
      return null;
    }
  }
}

/// Valeur sentinelle retournée par [ProviderTemplate.renderValue] pour une
/// entrée à omettre.
const Object providerTemplateOmitted = _Omitted();

class _Omitted {
  const _Omitted();
}

/// Chaîne analysée contenant zéro, une ou plusieurs références `{{...}}`.
@immutable
class ProviderTemplate {
  const ProviderTemplate._(this.source, this._parts);

  /// Analyse [source].
  ///
  /// Lève une [FormatException] si une accolade `{{` n'est pas fermée ou si
  /// une référence est invalide.
  factory ProviderTemplate.parse(String source) {
    final parts = <Object>[];
    var offset = 0;
    for (final match in _placeholderPattern.allMatches(source)) {
      if (match.start > offset) {
        parts.add(source.substring(offset, match.start));
      }
      parts.add(ProviderTemplateReference.parse(match.group(1)!));
      offset = match.end;
    }
    if (offset < source.length) parts.add(source.substring(offset));
    if (parts.whereType<String>().any((literal) => literal.contains('{{'))) {
      throw FormatException('Gabarit non fermé : « $source ».');
    }
    return ProviderTemplate._(source, List.unmodifiable(parts));
  }

  /// Texte d'origine.
  final String source;

  /// Littéraux (`String`) et références ([ProviderTemplateReference]).
  final List<Object> _parts;

  /// Références du gabarit, dans l'ordre.
  List<ProviderTemplateReference> get references =>
      _parts.whereType<ProviderTemplateReference>().toList(growable: false);

  /// Texte rendu, ou `null` si une valeur du filtre est absente ou vide.
  ///
  /// Avec [strict], une valeur du filtre absente lève une [FormatException]
  /// au lieu de retourner `null`. Une variable d'environnement introuvable est
  /// toujours une erreur. [encode] applique l'encodage URL aux valeurs
  /// insérées (pas aux littéraux).
  String? render(
    ProviderTemplateContext context, {
    bool strict = false,
    bool encode = false,
  }) {
    final buffer = StringBuffer();
    for (final part in _parts) {
      if (part is String) {
        buffer.write(part);
        continue;
      }
      final reference = part as ProviderTemplateReference;
      final text = _scalarText(context.resolve(reference), reference);
      if (text == null) {
        if (reference.isEnv) {
          throw FormatException(
            'Variable d’environnement « ${reference.key} » introuvable ou '
            'non autorisée.',
          );
        }
        if (strict) {
          throw FormatException(
            'Le paramètre « ${reference.key} » est vide ou absent.',
          );
        }
        return null;
      }
      buffer.write(encode ? Uri.encodeComponent(text) : text);
    }
    return buffer.toString();
  }

  /// Rendu typé : un gabarit réduit à une seule référence du filtre retourne
  /// la valeur brute (nombre, booléen, tableau, objet) ; sinon le texte de
  /// [render].
  ///
  /// Retourne [providerTemplateOmitted] lorsque la valeur est absente ou vide.
  Object? renderValue(ProviderTemplateContext context) {
    if (_parts.length == 1) {
      final only = _parts.first;
      if (only is ProviderTemplateReference && !only.isEnv) {
        final value = context.resolve(only);
        if (value == null || (value is String && value.trim().isEmpty)) {
          return providerTemplateOmitted;
        }
        return value;
      }
    }
    return render(context) ?? providerTemplateOmitted;
  }

  static String? _scalarText(Object? value, ProviderTemplateReference ref) {
    if (value == null) return null;
    if (value is String) return value.trim().isEmpty ? null : value;
    if (value is bool || value is num) return value.toString();
    if (value is List) {
      final items = <String>[];
      for (final item in value) {
        if (item == null) continue;
        if (item is! String && item is! bool && item is! num) {
          throw FormatException(
            'Le paramètre « ${ref.label} » doit être une valeur simple.',
          );
        }
        final text = _scalarText(item, ref);
        if (text != null) items.add(text);
      }
      return items.isEmpty ? null : items.join(',');
    }
    throw FormatException(
      'Le paramètre « ${ref.label} » doit être une valeur simple.',
    );
  }
}

/// Références de toutes les chaînes d'un gabarit JSON, après avoir vérifié
/// qu'il est un JSON valide (types JSON, profondeur et taille bornées).
///
/// Lève une [FormatException] si le gabarit est invalide.
List<ProviderTemplateReference> providerBodyReferences(Object? body) {
  final references = <ProviderTemplateReference>[];

  void walk(Object? node, int depth) {
    if (depth > providerBodyMaxDepth) {
      throw const FormatException('Le corps de la requête est trop imbriqué.');
    }
    switch (node) {
      case null:
      case bool _:
        return;
      case num number:
        if (!number.isFinite) {
          throw const FormatException('Le corps contient un nombre invalide.');
        }
      case String text:
        references.addAll(ProviderTemplate.parse(text).references);
      case List list:
        for (final item in list) {
          walk(item, depth + 1);
        }
      case Map map:
        for (final entry in map.entries) {
          if (entry.key is! String) {
            throw const FormatException(
              'Les clés du corps doivent être du texte.',
            );
          }
          walk(entry.value, depth + 1);
        }
      default:
        throw const FormatException(
          'Le corps de la requête doit être du JSON.',
        );
    }
  }

  walk(body, 0);
  if (body != null &&
      utf8.encode(jsonEncode(body)).length > providerBodyMaxBytes) {
    throw const FormatException('Le corps de la requête est trop volumineux.');
  }
  return references;
}

/// Rend un gabarit de corps JSON : les chaînes sont des [ProviderTemplate] et
/// les entrées dont la valeur est absente sont omises.
///
/// Retourne `null` si le corps entier est omis.
Object? renderProviderBody(Object? body, ProviderTemplateContext context) {
  Object? render(Object? node) {
    switch (node) {
      case String text:
        return ProviderTemplate.parse(text).renderValue(context);
      case List list:
        final items = <Object?>[];
        for (final item in list) {
          final rendered = render(item);
          if (!identical(rendered, providerTemplateOmitted)) {
            items.add(rendered);
          }
        }
        return items;
      case Map map:
        final result = <String, Object?>{};
        for (final entry in map.entries) {
          final rendered = render(entry.value);
          if (!identical(rendered, providerTemplateOmitted)) {
            result[entry.key as String] = rendered;
          }
        }
        return result;
      default:
        return node;
    }
  }

  final rendered = render(body);
  return identical(rendered, providerTemplateOmitted) ? null : rendered;
}
