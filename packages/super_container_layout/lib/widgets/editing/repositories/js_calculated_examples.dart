/// Catalogue d'exemples JavaScript pour le wizard des attributs calculés
/// ([CalculatedAttributesDialog]).
///
/// Combine des modèles génériques couvrant l'API QuickJS `(row, ctx, doc)`
/// et des modèles générés dynamiquement depuis la structure réelle du document
/// JSON courant.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Modèle immuable d'un badge d'exemple JavaScript prêt à préremplir l'éditeur.
@immutable
class JsCalculatedExample {
  /// Crée un exemple JavaScript identifié par [id].
  const JsCalculatedExample({
    required this.id,
    required this.label,
    required this.code,
    required this.description,
    this.isSchemaAdapted = false,
  });

  /// Identifiant stable de l'exemple (utilisé notamment pour les clés UI).
  final String id;

  /// Libellé court affiché sur le badge.
  final String label;

  /// Code JavaScript injecté dans le [CodeEditor] au clic sur le badge.
  final String code;

  /// Description affichée en infobulle pour expliciter l'exemple.
  final String description;

  /// Vrai lorsque l'exemple exploite les vrais champs du repository courant.
  final bool isSchemaAdapted;
}

final RegExp _jsIdentifierPattern = RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$');

String _jsMember(String target, String key) {
  if (_jsIdentifierPattern.hasMatch(key)) {
    return '$target.$key';
  }
  return '$target[${jsonEncode(key)}]';
}

String _jsOptionalPropertyAccess(String key) {
  if (_jsIdentifierPattern.hasMatch(key)) {
    return '?.$key';
  }
  return '?.[${jsonEncode(key)}]';
}

Object? _resolveSampleNode(Object? document, String scope) {
  final trimmed = scope.trim();
  if (trimmed.isEmpty) return document;

  Object? current = document;
  final segments = trimmed.split('.');
  for (final segment in segments) {
    if (segment.isEmpty) continue;
    final bracketStart = segment.indexOf('[');
    if (bracketStart < 0) {
      if (current is! Map) return null;
      current = current[segment];
      continue;
    }

    final key = segment.substring(0, bracketStart);
    if (key.isNotEmpty) {
      if (current is! Map) return null;
      current = current[key];
    }
    var rest = segment.substring(bracketStart);
    while (rest.isNotEmpty) {
      if (!rest.startsWith('[')) return null;
      final closeIdx = rest.indexOf(']');
      if (closeIdx < 0) return null;
      final indexToken = rest.substring(1, closeIdx);
      rest = rest.substring(closeIdx + 1);
      if (current is! List || current.isEmpty) return null;
      if (indexToken == '?') {
        final firstMap = current.whereType<Map>().firstOrNull;
        current = firstMap ?? current.first;
      } else {
        final idx = int.tryParse(indexToken);
        if (idx == null || idx < 0 || idx >= current.length) return null;
        current = current[idx];
      }
    }
  }
  return current;
}

/// Construit la liste ordonnée des badges d'exemples JavaScript affichés dans
/// [CalculatedAttributesDialog].
///
/// Les exemples adaptés au document [document] et à la portée [scope] sont
/// placés en tête, suivis d'une palette complète d'exemples génériques couvrant
/// les opérateurs, listes, conditions, `doc`, `ctx` et références `@calcul`.
List<JsCalculatedExample> buildJsCalculatedExamples({
  Object? document,
  String scope = '',
  List<String> sameScopeCalculatedNames = const [],
  List<String> rootCalculatedNames = const [],
  List<String> scopedCalculatedPaths = const [],
  List<String> otherRepositoryIds = const [],
  String? currentAttributeName,
}) {
  final examples = <JsCalculatedExample>[];
  final seenCodes = <String>{};

  void addExample(JsCalculatedExample example) {
    if (seenCodes.add(example.code)) {
      examples.add(example);
    }
  }

  final normalizedScope = scope.trim();
  final sampleNode = _resolveSampleNode(document, normalizedScope);
  final numKeys = <String>[];
  final stringKeys = <String>[];
  final boolKeys = <String>[];
  final listKeys = <String>[];

  if (sampleNode is Map) {
    for (final entry in sampleNode.entries) {
      final key = entry.key.toString();
      if (key.isEmpty || key.startsWith('@')) continue;
      final value = entry.value;
      if (value is num) {
        numKeys.add(key);
      } else if (value is String) {
        stringKeys.add(key);
      } else if (value is bool) {
        boolKeys.add(key);
      } else if (value is List) {
        listKeys.add(key);
      }
    }
  }

  if (numKeys.length >= 2) {
    final a = numKeys[0];
    final b = numKeys[1];
    addExample(
      JsCalculatedExample(
        id: 'schema-product',
        label: '$a × $b',
        code: '(${_jsMember('row', a)} ?? 0) * (${_jsMember('row', b)} ?? 0)',
        description: 'Multiplie les champs numériques $a et $b du JSON courant.',
        isSchemaAdapted: true,
      ),
    );
  }
  if (numKeys.isNotEmpty) {
    final firstNum = numKeys.first;
    addExample(
      JsCalculatedExample(
        id: 'schema-tva',
        label: '$firstNum + TVA 20%',
        code: 'Math.round((${_jsMember('row', firstNum)} ?? 0) * 1.2 * 100) / 100',
        description: 'Applique une TVA de 20 % sur $firstNum avec arrondi.',
        isSchemaAdapted: true,
      ),
    );
  }
  if (stringKeys.length >= 2) {
    final s1 = stringKeys[0];
    final s2 = stringKeys[1];
    addExample(
      JsCalculatedExample(
        id: 'schema-concat',
        label: '$s1 + $s2',
        code:
            '`\${${_jsMember('row', s1)} ?? \'\'} \${${_jsMember('row', s2)} ?? \'\'}`.trim()',
        description: 'Concatène les champs texte $s1 et $s2.',
        isSchemaAdapted: true,
      ),
    );
  } else if (stringKeys.length == 1) {
    final s1 = stringKeys.first;
    addExample(
      JsCalculatedExample(
        id: 'schema-upper',
        label: '$s1 en majuscules',
        code: "String(${_jsMember('row', s1)} ?? '').trim().toUpperCase()",
        description: 'Met en majuscules le champ $s1.',
        isSchemaAdapted: true,
      ),
    );
  }
  if (boolKeys.isNotEmpty) {
    final b1 = boolKeys.first;
    addExample(
      JsCalculatedExample(
        id: 'schema-bool',
        label: 'Statut $b1',
        code: "${_jsMember('row', b1)} ? 'Oui' : 'Non'",
        description: 'Convertit le booléen $b1 en libellé lisible.',
        isSchemaAdapted: true,
      ),
    );
  }
  if (listKeys.isNotEmpty && sampleNode is Map) {
    for (final listKey in listKeys) {
      final listValue = sampleNode[listKey];
      if (listValue is! List) continue;
      String? subNumKey;
      for (final item in listValue) {
        if (item is Map) {
          for (final entry in item.entries) {
            final k = entry.key.toString();
            if (!k.startsWith('@') && entry.value is num) {
              subNumKey = k;
              break;
            }
          }
          if (subNumKey != null) break;
        }
      }
      if (subNumKey != null) {
        addExample(
          JsCalculatedExample(
            id: 'schema-list-sum-$listKey',
            label: 'Somme $listKey.$subNumKey',
            code:
                '(${_jsMember('row', listKey)} ?? []).reduce((acc, item) => acc + (item${_jsOptionalPropertyAccess(subNumKey)} ?? 0), 0)',
            description: 'Additionne $subNumKey sur tous les éléments de $listKey.',
            isSchemaAdapted: true,
          ),
        );
        break;
      }
    }
    final firstList = listKeys.first;
    addExample(
      JsCalculatedExample(
        id: 'schema-list-count',
        label: 'Nb $firstList',
        code: '(${_jsMember('row', firstList)} ?? []).length',
        description: 'Compte le nombre d’éléments dans $firstList.',
        isSchemaAdapted: true,
      ),
    );
  }

  final reusableSameScope = sameScopeCalculatedNames
      .where((name) => name != currentAttributeName && name.isNotEmpty)
      .firstOrNull;
  if (reusableSameScope != null) {
    addExample(
      JsCalculatedExample(
        id: 'schema-reuse-calc',
        label: 'Basé sur @$reusableSameScope',
        code: "(row['@$reusableSameScope'] ?? 0) * 1.2",
        description:
            'Réutilise l’attribut calculé @$reusableSameScope de la même portée.',
        isSchemaAdapted: true,
      ),
    );
  } else {
    final reusableRoot = rootCalculatedNames
        .where((name) => name != currentAttributeName && name.isNotEmpty)
        .firstOrNull;
    if (reusableRoot != null) {
      addExample(
        JsCalculatedExample(
          id: 'schema-reuse-root-calc',
          label: 'Lire @$reusableRoot',
          code: "ctx.getValue('@$reusableRoot', null, 0)",
          description:
              'Lit l’attribut calculé racine @$reusableRoot via ctx.',
          isSchemaAdapted: true,
        ),
      );
    }
  }

  if (normalizedScope.isNotEmpty && document is Map) {
    String? rootNumKey;
    for (final entry in document.entries) {
      final k = entry.key.toString();
      if (!k.startsWith('@') && entry.value is num) {
        rootNumKey = k;
        break;
      }
    }
    if (rootNumKey != null && numKeys.isNotEmpty) {
      final rowNum = numKeys.first;
      addExample(
        JsCalculatedExample(
          id: 'schema-row-with-doc',
          label: '$rowNum × doc.$rootNumKey',
          code:
              '(${_jsMember('row', rowNum)} ?? 0) * (${_jsMember('doc', rootNumKey)} ?? 0)',
          description:
              'Combine le champ de ligne $rowNum avec doc.$rootNumKey à la racine.',
          isSchemaAdapted: true,
        ),
      );
    }
  } else if (normalizedScope.isEmpty && scopedCalculatedPaths.isNotEmpty) {
    for (final calcPath in scopedCalculatedPaths) {
      final dotCalc = calcPath.indexOf('[?].@');
      if (dotCalc <= 0) continue;
      final arrayPrefix = calcPath.substring(0, dotCalc);
      final calcName = calcPath.substring(dotCalc + '[?].@'.length);
      if (arrayPrefix.contains('[?]')) continue;
      addExample(
        JsCalculatedExample(
          id: 'schema-root-agg-$arrayPrefix-$calcName',
          label: 'Total $arrayPrefix.@$calcName',
          code: '''
const items = ${_jsMember('row', arrayPrefix)} ?? [];
let total = 0;
for (let i = 0; i < items.length; i++) {
  total += ctx.getDouble('$arrayPrefix[' + i + '].@$calcName', null, 0);
}
return Math.round(total * 100) / 100;''',
          description:
              'Additionne l’attribut calculé @$calcName sur toutes les lignes de $arrayPrefix.',
          isSchemaAdapted: true,
        ),
      );
      break;
    }
  }

  if (otherRepositoryIds.isNotEmpty) {
    final otherRepoId = otherRepositoryIds.first;
    addExample(
      JsCalculatedExample(
        id: 'schema-cross-repo',
        label: 'Lire $otherRepoId',
        code: "ctx.getNum('taux', ${jsonEncode(otherRepoId)}, 0.2)",
        description:
            'Lit une valeur depuis le repository enregistré $otherRepoId.',
        isSchemaAdapted: true,
      ),
    );
  }

  const genericExamples = <JsCalculatedExample>[
    JsCalculatedExample(
      id: 'gen-product',
      label: 'Produit (a × b)',
      code: '(row.prix ?? 0) * (row.quantite ?? 0)',
      description: 'Multiplication simple avec valeurs par défaut à 0.',
    ),
    JsCalculatedExample(
      id: 'gen-round',
      label: 'Arrondi 2 déc.',
      code: 'Math.round(((row.montant ?? 0) * 1.2) * 100) / 100',
      description: 'Calcul TTC arrondi à deux décimales.',
    ),
    JsCalculatedExample(
      id: 'gen-discount',
      label: 'Remise (%)',
      code:
          'Math.round((row.total ?? 0) * (1 - (row.remise ?? 0) / 100) * 100) / 100',
      description: 'Applique un pourcentage de remise sur un montant.',
    ),
    JsCalculatedExample(
      id: 'gen-ratio',
      label: 'Pourcentage sûr',
      code:
          '(row.total ?? 0) === 0 ? 0 : Math.round(((row.part ?? 0) / row.total) * 1000) / 10',
      description: 'Calcule un pourcentage en évitant toute division par zéro.',
    ),
    JsCalculatedExample(
      id: 'gen-ternary',
      label: 'Ternaire',
      code: "(row.stock ?? 0) > 0 ? 'Disponible' : 'Rupture'",
      description: 'Retourne un libellé conditionnel sur une ligne.',
    ),
    JsCalculatedExample(
      id: 'gen-thresholds',
      label: 'Seuils (if/else)',
      code: '''
const v = row.score ?? 0;
if (v >= 80) return 'Élevé';
if (v >= 50) return 'Moyen';
return 'Faible';''',
      description: 'Classe une valeur numérique selon plusieurs paliers.',
    ),
    JsCalculatedExample(
      id: 'gen-concat',
      label: 'Concaténation',
      code: r"`${row.prenom ?? ''} ${row.nom ?? ''}`.trim()",
      description: 'Assemble plusieurs chaînes de caractères proprement.',
    ),
    JsCalculatedExample(
      id: 'gen-upper',
      label: 'Majuscules',
      code: "String(row.code ?? '').trim().toUpperCase()",
      description: 'Nettoie et met une chaîne en majuscules.',
    ),
    JsCalculatedExample(
      id: 'gen-date-iso',
      label: 'Date YYYY-MM-DD',
      code: "String(row.date ?? '').slice(0, 10)",
      description: 'Extrait la partie date d’un horodatage ISO.',
    ),
    JsCalculatedExample(
      id: 'gen-list-sum',
      label: 'Somme liste',
      code:
          '(row.lignes ?? []).reduce((acc, item) => acc + (item?.montant ?? 0), 0)',
      description: 'Somme d’une propriété numérique dans un tableau.',
    ),
    JsCalculatedExample(
      id: 'gen-list-count-if',
      label: 'Compter si',
      code: '(row.lignes ?? []).filter((item) => Boolean(item?.actif)).length',
      description: 'Compte uniquement les éléments répondant à un critère.',
    ),
    JsCalculatedExample(
      id: 'gen-list-avg',
      label: 'Moyenne liste',
      code: '''
const list = row.notes ?? [];
if (list.length === 0) return 0;
return Math.round((list.reduce((s, n) => s + (Number(n) || 0), 0) / list.length) * 100) / 100;''',
      description: 'Calcule la moyenne sécurisée d’un tableau de nombres.',
    ),
    JsCalculatedExample(
      id: 'gen-list-max',
      label: 'Maximum liste',
      code: '''
const vals = (row.lignes ?? []).map((item) => Number(item?.prix ?? 0) || 0);
return vals.length === 0 ? 0 : Math.max(...vals);''',
      description: 'Retourne la valeur maximale d’un tableau sans erreur si vide.',
    ),
    JsCalculatedExample(
      id: 'gen-list-join',
      label: 'Joindre liste',
      code: "(row.tags ?? []).map((t) => String(t)).join(', ')",
      description: 'Transforme un tableau en liste séparée par des virgules.',
    ),
    JsCalculatedExample(
      id: 'gen-object',
      label: 'Objet JSON',
      code: '''
return {
  libelle: String(row.nom ?? ''),
  total: (row.quantite ?? 0) * (row.prix ?? 0),
};''',
      description: 'Retourne un objet JSON structuré.',
    ),
    JsCalculatedExample(
      id: 'gen-doc-root',
      label: 'Racine doc',
      code: '(row.montant ?? 0) * (1 + (doc.tva ?? 0.2))',
      description: 'Accède à une propriété globale via le paramètre doc.',
    ),
    JsCalculatedExample(
      id: 'gen-ctx-get',
      label: 'ctx.getNum',
      code: "ctx.getNum('parametres.taux', null, 0.2)",
      description: 'Lit un chemin typé avec valeur par défaut via ctx.',
    ),
    JsCalculatedExample(
      id: 'gen-ctx-cross',
      label: 'Inter-repo ctx',
      code: "ctx.getNum('tva', 'config_repo', 0.2)",
      description: 'Lit une donnée depuis un autre repository.',
    ),
    JsCalculatedExample(
      id: 'gen-calc-ref',
      label: 'Autre @calcul',
      code: "(row['@montantHt'] ?? 0) * (1 + ctx.getNum('tva', null, 0.2))",
      description: 'Chaîne un calcul sur un autre attribut calculé @nom.',
    ),
    JsCalculatedExample(
      id: 'gen-arrow-fn',
      label: 'Fonction (row, ctx)',
      code: '''
(row, ctx) => {
  const items = row.articles ?? [];
  let total = 0;
  for (let i = 0; i < items.length; i++) {
    total += ctx.getDouble('articles[' + i + '].@montant', null, 0);
  }
  return Math.round(total * 100) / 100;
}''',
      description: 'Fonction fléchée complète agrégeant des @calculs de lignes.',
    ),
  ];

  for (final example in genericExamples) {
    addExample(example);
  }

  return List<JsCalculatedExample>.unmodifiable(examples);
}
