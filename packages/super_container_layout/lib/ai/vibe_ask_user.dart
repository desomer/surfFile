/// Modèles immuables de questionnaire de clarification interactif ([VibeAskUserRequest]) pour le chat Vibe IA.
///
/// Permet à l'assistant IA d'émettre un bloc structuré `"askUser"` contenant jusqu'à
/// [VibeAskUserRequest.maxQuestions] questions typées ([VibeAskUserQuestion] / [VibeAskUserFieldType])
/// avant de générer le patch `"vibe"`, puis de formater les réponses utilisateur ou les
/// valeurs par défaut pour le tour de conversation suivant.
library;

import 'package:flutter/foundation.dart';

/// Niveau d'intensité du questionnement préalable (`askUser`) réglable par l'utilisateur.
enum VibeQuestioningLevel {
  /// Aucun questionnement : l'IA génère immédiatement l'écran avec des hypothèses raisonnables.
  none(
    label: 'Aucun',
    tooltip:
        'Aucune question : génération directe avec hypothèses raisonnables',
    maxQuestions: 0,
  ),

  /// Questionnement léger : 1 à 2 questions quelle que soit l'étape.
  light(
    label: 'Léger',
    tooltip: '1 à 2 questions à toute étape',
    maxQuestions: 2,
  ),

  /// Questionnement équilibré par défaut : 2 à 4 questions quelle que soit l'étape.
  balanced(
    label: 'Équilibré',
    tooltip: '2 à 4 questions à toute étape (par défaut)',
    maxQuestions: 4,
  ),

  /// Questionnement approfondi : 4 à 6 questions quelle que soit l'étape pour cadrer disposition, champs, style et actions.
  thorough(
    label: 'Approfondi',
    tooltip:
        '4 à 6 questions à toute étape pour cadrer disposition, champs, style et interactions',
    maxQuestions: 6,
  ),

  /// Questionnement exhaustif : 6 à 10 questions quelle que soit l'étape pour couvrir l'ensemble des détails fonctionnels, visuels et d'interaction.
  exhaustive(
    label: 'Exhaustif',
    tooltip:
        '6 à 10 questions à toute étape pour cadrer structure, données, style, états et interactions',
    maxQuestions: 10,
  );

  /// Construit un niveau de questionnement Vibe IA.
  const VibeQuestioningLevel({
    required this.label,
    required this.tooltip,
    required this.maxQuestions,
  });

  /// Nombre maximal de questions ciblées émises lors d'une demande explicite « + de questions ».
  static const int followUpMaxQuestions = 4;

  /// Libellé court affiché à côté du slider.
  final String label;

  /// Info-bulle explicative du cran.
  final String tooltip;

  /// Nombre maximal de questions autorisées pour ce cran (`0` désactive `askUser`).
  final int maxQuestions;

  /// Résout le [VibeQuestioningLevel] correspondant à une valeur numérique de slider (`0..4`).
  static VibeQuestioningLevel fromSliderValue(double value) {
    final idx = value.round().clamp(0, values.length - 1);
    return values[idx];
  }

  /// Génère la consigne dynamique de tour sans modifier l'instruction système mise en cache.
  String promptDirective({
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    bool planMode = false,
  }) {
    if (forceFollowUpQuestions) {
      return 'NIVEAU DE QUESTIONNEMENT : + de questions demandé '
          '(2 à $followUpMaxQuestions questions complémentaires OBLIGATOIRES) — '
          'Pose impérativement 2 à $followUpMaxQuestions nouvelles questions ciblées et non redondantes '
          'avec "default" via "askUser" (sans répéter les questions déjà posées dans la conversation) '
          'pour approfondir la demande ou affiner l’écran actuel, et renvoie "vibe": null sur ce tour.';
    }
    if (afterAskUserReply) {
      return planMode
          ? 'NIVEAU DE QUESTIONNEMENT : Réponses déjà fournies — '
                'INTERDICTION d’utiliser "askUser" sur ce tour ("askUser": null obligatoire). '
                'Génère directement le plan par lots ("plan") correspondant sans patch "vibe".'
          : 'NIVEAU DE QUESTIONNEMENT : Réponses déjà fournies — '
                'INTERDICTION d’utiliser "askUser" sur ce tour ("askUser": null obligatoire). '
                'Génère directement le patch "vibe" correspondant.';
    }
    final targetAction = planMode
        ? 'de proposer le plan par lots ("plan")'
        : 'de générer "vibe"';
    return switch (this) {
      VibeQuestioningLevel.none =>
        planMode
            ? 'NIVEAU DE QUESTIONNEMENT : 0/4 (Aucun) — '
                  'INTERDICTION d’utiliser "askUser" sur ce tour ("askUser": null obligatoire). '
                  'Génère directement le plan par lots ("plan") en faisant des hypothèses raisonnables sans patch "vibe" '
                  '(ou réponds par "message" si c’est une pure question).'
            : 'NIVEAU DE QUESTIONNEMENT : 0/4 (Aucun) — '
                  'INTERDICTION d’utiliser "askUser" sur ce tour ("askUser": null obligatoire). '
                  'Génère directement le patch "vibe" en faisant des hypothèses raisonnables '
                  '(ou réponds par "message" si c’est une pure question).',
      VibeQuestioningLevel.light =>
        'NIVEAU DE QUESTIONNEMENT : 1/4 (Léger, max 2 questions) — '
            'Quelle que soit l’étape (création initiale, ajout ou modification), utilise ce niveau du slider : '
            'pose 1 à 2 questions courtes avec "default" via "askUser" pour clarifier la demande '
            'avant $targetAction (ou réponds par "message" si c’est une pure question d’information).',
      VibeQuestioningLevel.balanced =>
        'NIVEAU DE QUESTIONNEMENT : 2/4 (Équilibré, max 4 questions) — '
            'Quelle que soit l’étape (création initiale, ajout ou modification), utilise ce niveau du slider : '
            'pose 2 à 4 questions courtes avec "default" via "askUser" pour clarifier les choix '
            'fonctionnels, de disposition ou de style avant $targetAction (ou réponds par "message" si c’est une pure question d’information).',
      VibeQuestioningLevel.thorough =>
        'NIVEAU DE QUESTIONNEMENT : 3/4 (Approfondi, 4 à 6 questions) — '
            'Quelle que soit l’étape (création initiale, ajout ou modification), utilise ce niveau du slider : '
            'pose 4 à 6 questions structurées avec "default" via "askUser" (couvrant disposition, '
            'données/champs, style visuel et interactions) pour cadrer le besoin avant $targetAction '
            '(ou réponds par "message" si c’est une pure question d’information).',
      VibeQuestioningLevel.exhaustive =>
        'NIVEAU DE QUESTIONNEMENT : 4/4 (Exhaustif, 6 à 10 questions) — '
            'Quelle que soit l’étape (création initiale, ajout ou modification), utilise ce niveau du slider : '
            'pose 6 à 10 questions complètes et structurées avec "default" via "askUser" (couvrant architecture, '
            'données/liaisons, hiérarchie visuelle, états de surface, actions et cas limites) avant $targetAction '
            '(ou réponds par "message" si c’est une pure question d’information).',
    };
  }
}

/// Type de champ interactif d'une question de clarification [VibeAskUserQuestion].
enum VibeAskUserFieldType {
  /// Choix unique parmi une liste d'options (`ChoiceChip`, avec option libre éventuelle).
  single,

  /// Choix multiple parmi une liste d'options (`FilterChip`, avec option libre éventuelle).
  multi,

  /// Interrupteur binaire Oui / Non (`Switch`).
  boolean,

  /// Saisie texte libre (`TextField`).
  text;

  /// Résout un [VibeAskUserFieldType] à partir d'une valeur JSON brute et de ses alias courants.
  ///
  /// Lorsque [raw] est `null` ou non reconnu, retourne [VibeAskUserFieldType.single]
  /// si [hasOptions] vaut `true`, sinon [VibeAskUserFieldType.text].
  static VibeAskUserFieldType fromJson(Object? raw, {bool hasOptions = false}) {
    if (raw is VibeAskUserFieldType) {
      return raw;
    }
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      switch (normalized) {
        case 'single':
        case 'singlechoice':
        case 'single_choice':
        case 'single-choice':
        case 'enum':
        case 'choice':
        case 'select':
        case 'radio':
          return VibeAskUserFieldType.single;
        case 'multi':
        case 'multichoice':
        case 'multi_choice':
        case 'multi-choice':
        case 'multiselect':
        case 'multi_select':
        case 'multi-select':
        case 'array':
        case 'checkbox':
        case 'checkboxes':
          return VibeAskUserFieldType.multi;
        case 'boolean':
        case 'bool':
        case 'toggle':
        case 'switch':
        case 'yesno':
        case 'yes_no':
        case 'yes-no':
          return VibeAskUserFieldType.boolean;
        case 'text':
        case 'string':
        case 'input':
        case 'freetext':
        case 'free_text':
        case 'free-text':
          return VibeAskUserFieldType.text;
      }
    }
    return hasOptions ? VibeAskUserFieldType.single : VibeAskUserFieldType.text;
  }
}

/// Question individuelle d'un questionnaire de clarification [VibeAskUserRequest].
@immutable
class VibeAskUserQuestion {
  /// Construit une question immuable de clarification Vibe IA.
  VibeAskUserQuestion({
    required this.id,
    required this.title,
    this.description,
    this.type = VibeAskUserFieldType.text,
    List<String> options = const <String>[],
    Object? defaultValue,
    bool? allowOther,
  }) : options = List<String>.unmodifiable(_cleanUniqueStrings(options)),
       defaultValue = _normalizeDefaultForType(type, defaultValue),
       allowOther =
           allowOther ??
           (type == VibeAskUserFieldType.single ||
               type == VibeAskUserFieldType.multi);

  /// Identifiant stable de la question dans la carte de réponses.
  final String id;

  /// Intitulé principal affiché à l'utilisateur.
  final String title;

  /// Précision ou aide contextuelle facultative sous l'intitulé.
  final String? description;

  /// Type de contrôle interactif à afficher pour cette question.
  final VibeAskUserFieldType type;

  /// Liste immuable d'options uniques nettoyées pour les types [VibeAskUserFieldType.single] et [VibeAskUserFieldType.multi].
  final List<String> options;

  /// Valeur par défaut typée (`String?` pour `single`/`text`, `List<String>?` immuable pour `multi`, `bool?` pour `boolean`).
  final Object? defaultValue;

  /// Indique si l'utilisateur peut saisir une réponse personnalisée (« Autre »).
  final bool allowOther;

  /// Calcule la réponse initiale effective pré-remplie pour cette question.
  Object effectiveInitialAnswer() {
    switch (type) {
      case VibeAskUserFieldType.single:
        final def = defaultValue is String
            ? (defaultValue as String).trim()
            : null;
        if (def != null && def.isNotEmpty) {
          return def;
        }
        return options.isNotEmpty ? options.first : '';
      case VibeAskUserFieldType.multi:
        final def = defaultValue is List<String>
            ? defaultValue as List<String>
            : const <String>[];
        return List<String>.unmodifiable(def);
      case VibeAskUserFieldType.boolean:
        return (defaultValue is bool) ? defaultValue as bool : false;
      case VibeAskUserFieldType.text:
        return (defaultValue is String) ? defaultValue as String : '';
    }
  }

  /// Formate proprement en français une valeur de réponse [value] pour le récapitulatif.
  String formatAnswerValue(Object? value) {
    if (value is bool) {
      return value ? 'Oui' : 'Non';
    }
    if (value is Iterable) {
      final items = value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      return items.isEmpty ? 'Aucun' : items.join(', ');
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? 'Non précisé' : trimmed;
    }
    if (value == null) {
      return 'Non précisé';
    }
    final text = value.toString().trim();
    return text.isEmpty ? 'Non précisé' : text;
  }

  /// Sérialise la question dans une carte JSON compatible avec [tryFromJson].
  Map<String, Object?> toJson() =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        'id': id,
        'title': title,
        if (description != null && description!.isNotEmpty)
          'description': description,
        'type': type.name,
        if (options.isNotEmpty) 'options': options,
        if (defaultValue != null) 'default': defaultValue,
        'allowOther': allowOther,
      });

  /// Tente de désérialiser une [VibeAskUserQuestion] depuis un objet JSON brut tolérant.
  ///
  /// Retourne `null` si [raw] n'est pas une carte valide ou ne possède aucun intitulé non vide.
  static VibeAskUserQuestion? tryFromJson(
    Object? raw, {
    String? fallbackId,
    int fallbackIndex = 0,
  }) {
    if (raw is VibeAskUserQuestion) {
      return raw;
    }
    if (raw is! Map) {
      return null;
    }

    final title = _firstNonEmptyString(<Object?>[
      raw['title'],
      raw['question'],
      raw['label'],
      raw['prompt'],
    ]);
    if (title == null) {
      return null;
    }

    final id =
        _firstNonEmptyString(<Object?>[
          raw['id'],
          raw['key'],
          raw['name'],
          fallbackId,
        ]) ??
        'q_${fallbackIndex + 1}';

    final description = _firstNonEmptyString(<Object?>[
      raw['description'],
      raw['subtitle'],
      raw['hint'],
      raw['help'],
    ]);

    final valueToLabel = <String, String>{};
    final parsedOptions = _extractOptions(raw, valueToLabel: valueToLabel);
    final hasOptions = parsedOptions.isNotEmpty;

    final rawType =
        raw['type'] ?? raw['kind'] ?? raw['fieldType'] ?? raw['inputType'];
    var resolvedType =
        (rawType is String &&
            rawType.trim().toLowerCase() == 'string' &&
            hasOptions)
        ? VibeAskUserFieldType.single
        : VibeAskUserFieldType.fromJson(rawType, hasOptions: hasOptions);

    if (!hasOptions &&
        (resolvedType == VibeAskUserFieldType.single ||
            resolvedType == VibeAskUserFieldType.multi)) {
      resolvedType = VibeAskUserFieldType.text;
    }

    final rawDefault = _extractRawDefault(raw);
    final parsedDefault = _parseJsonDefault(
      resolvedType,
      rawDefault,
      valueToLabel: valueToLabel,
    );

    final parsedAllowOther = _parseBool(
      raw['allowOther'] ?? raw['allow_other'],
    );

    return VibeAskUserQuestion(
      id: id,
      title: title,
      description: description,
      type: resolvedType,
      options:
          (resolvedType == VibeAskUserFieldType.single ||
              resolvedType == VibeAskUserFieldType.multi)
          ? parsedOptions
          : const <String>[],
      defaultValue: parsedDefault,
      allowOther: parsedAllowOther,
    );
  }

  /// Compare deux questions par égalité structurelle profonde.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeAskUserQuestion &&
          other.id == id &&
          other.title == title &&
          other.description == description &&
          other.type == type &&
          listEquals(other.options, options) &&
          _defaultEquals(other.defaultValue, defaultValue) &&
          other.allowOther == allowOther;

  /// Code de hachage cohérent avec [operator ==].
  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    type,
    Object.hashAll(options),
    _defaultHash(defaultValue),
    allowOther,
  );

  /// Représentation textuelle de diagnostic de la question.
  @override
  String toString() =>
      'VibeAskUserQuestion(id: $id, type: ${type.name}, title: $title)';

  static List<String> _cleanUniqueStrings(Iterable<String> source) {
    final seen = <String>{};
    final cleaned = <String>[];
    for (final item in source) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        cleaned.add(trimmed);
      }
    }
    return cleaned;
  }

  static Object? _normalizeDefaultForType(
    VibeAskUserFieldType type,
    Object? value,
  ) {
    if (value == null) return null;
    switch (type) {
      case VibeAskUserFieldType.single:
        final trimmed = value.toString().trim();
        return trimmed.isEmpty ? null : trimmed;
      case VibeAskUserFieldType.multi:
        if (value is Iterable) {
          final items = _cleanUniqueStrings(
            value.map((e) => e?.toString() ?? ''),
          );
          return List<String>.unmodifiable(items);
        }
        if (value is String) {
          final trimmed = value.trim();
          return trimmed.isEmpty
              ? null
              : List<String>.unmodifiable(<String>[trimmed]);
        }
        return null;
      case VibeAskUserFieldType.boolean:
        return value is bool ? value : _parseBool(value);
      case VibeAskUserFieldType.text:
        return value is String ? value : value.toString();
    }
  }

  static bool _defaultEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is List<String> && b is List<String>) {
      return listEquals(a, b);
    }
    return a == b;
  }

  static int _defaultHash(Object? value) {
    if (value is List<String>) {
      return Object.hashAll(value);
    }
    return value.hashCode;
  }

  static String? _firstNonEmptyString(List<Object?> candidates) {
    for (final candidate in candidates) {
      if (candidate is String) {
        final trimmed = candidate.trim();
        if (trimmed.isNotEmpty) return trimmed;
      } else if (candidate is num) {
        return candidate.toString();
      }
    }
    return null;
  }

  static List<String> _extractOptions(
    Map<dynamic, dynamic> map, {
    required Map<String, String> valueToLabel,
  }) {
    Object? rawList;
    if (map['options'] is List) {
      rawList = map['options'];
    } else if (map['choices'] is List) {
      rawList = map['choices'];
    } else if (map['enum'] is List) {
      rawList = map['enum'];
    } else if (map['items'] is List) {
      rawList = map['items'];
    } else if (map['items'] is Map) {
      final itemsMap = map['items'] as Map;
      rawList =
          itemsMap['enum'] ??
          itemsMap['options'] ??
          itemsMap['choices'] ??
          itemsMap['oneOf'] ??
          itemsMap['anyOf'];
    } else if (map['oneOf'] is List) {
      rawList = map['oneOf'];
    } else if (map['anyOf'] is List) {
      rawList = map['anyOf'];
    }

    if (rawList is! List) {
      return const <String>[];
    }

    final seen = <String>{};
    final result = <String>[];
    for (final entry in rawList) {
      final extracted = _extractOptionItem(entry, valueToLabel: valueToLabel);
      if (extracted != null && seen.add(extracted)) {
        result.add(extracted);
      }
    }
    return result;
  }

  static String? _extractOptionItem(
    Object? entry, {
    Map<String, String>? valueToLabel,
  }) {
    if (entry is String) {
      final trimmed = entry.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (entry is num) {
      return entry.toString();
    }
    if (entry is Map) {
      final label = _firstNonEmptyString(<Object?>[
        entry['label'],
        entry['title'],
        entry['value'],
        entry['const'],
        entry['name'],
        entry['text'],
      ]);
      final rawVal = _firstNonEmptyString(<Object?>[
        entry['value'],
        entry['const'],
      ]);
      if (label != null && rawVal != null && valueToLabel != null) {
        valueToLabel[rawVal] = label;
      }
      return label;
    }
    return null;
  }

  static Object? _extractRawDefault(Map<dynamic, dynamic> map) {
    for (final key in const <String>['default', 'defaultValue', 'initial']) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key];
      }
    }
    return null;
  }

  static Object? _parseJsonDefault(
    VibeAskUserFieldType type,
    Object? rawDefault, {
    required Map<String, String> valueToLabel,
  }) {
    if (rawDefault == null) return null;
    switch (type) {
      case VibeAskUserFieldType.single:
        if (rawDefault is List) {
          for (final item in rawDefault) {
            final extracted = _extractOptionItem(item);
            if (extracted != null) {
              return valueToLabel[extracted] ?? extracted;
            }
          }
          return null;
        }
        final extracted = _extractOptionItem(rawDefault);
        if (extracted == null) return null;
        return valueToLabel[extracted] ?? extracted;
      case VibeAskUserFieldType.multi:
        if (rawDefault is List) {
          final seen = <String>{};
          final items = <String>[];
          for (final item in rawDefault) {
            final extracted = _extractOptionItem(item);
            if (extracted != null) {
              final mapped = valueToLabel[extracted] ?? extracted;
              if (seen.add(mapped)) {
                items.add(mapped);
              }
            }
          }
          return List<String>.unmodifiable(items);
        }
        final single = _extractOptionItem(rawDefault);
        if (single == null) return null;
        return List<String>.unmodifiable(<String>[
          valueToLabel[single] ?? single,
        ]);
      case VibeAskUserFieldType.boolean:
        return _parseBool(rawDefault);
      case VibeAskUserFieldType.text:
        if (rawDefault is String) {
          return rawDefault;
        }
        if (rawDefault is num || rawDefault is bool) {
          return rawDefault.toString();
        }
        return null;
    }
  }

  static bool? _parseBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) {
      if (raw == 1) return true;
      if (raw == 0) return false;
      return null;
    }
    if (raw is String) {
      switch (raw.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
        case 'oui':
        case 'vrai':
          return true;
        case 'false':
        case '0':
        case 'no':
        case 'non':
        case 'faux':
          return false;
      }
    }
    return null;
  }
}

/// Questionnaire immuable de clarification interactive émis par l'assistant Vibe IA.
@immutable
class VibeAskUserRequest {
  /// Construit un questionnaire immuable plafonné à [maxQuestions] questions.
  VibeAskUserRequest({required List<VibeAskUserQuestion> questions})
    : questions = List<VibeAskUserQuestion>.unmodifiable(
        questions.length > maxQuestions
            ? questions.take(maxQuestions)
            : questions,
      );

  /// Nombre maximal de questions retenues dans un même questionnaire.
  static const int maxQuestions = 10;

  /// Liste immuable des questions de clarification (au plus [maxQuestions]).
  final List<VibeAskUserQuestion> questions;

  /// Tente de désérialiser un [VibeAskUserRequest] depuis les formats JSON supportés.
  ///
  /// Supporte :
  /// - une carte contenant `'questions'` (ou `'fields'` / `'items'`) sous forme de liste ;
  /// - une liste directe de cartes de questions ;
  /// - un schéma de type JSON Schema contenant une carte `'properties'`.
  ///
  /// Retourne `null` si [raw] vaut `null`, est un `bool`, ou ne produit aucune question valide.
  static VibeAskUserRequest? tryFromJson(Object? raw) {
    if (raw == null || raw is bool) {
      return null;
    }
    if (raw is VibeAskUserRequest) {
      return raw.questions.isEmpty ? null : raw;
    }

    final parsed = <VibeAskUserQuestion>[];
    final seenIds = <String>{};

    void addQuestion(VibeAskUserQuestion? question) {
      if (question == null || parsed.length >= maxQuestions) {
        return;
      }
      var uniqueId = question.id;
      if (!seenIds.add(uniqueId)) {
        var suffix = 2;
        while (!seenIds.add('${question.id}_$suffix')) {
          suffix++;
        }
        uniqueId = '${question.id}_$suffix';
        question = VibeAskUserQuestion(
          id: uniqueId,
          title: question.title,
          description: question.description,
          type: question.type,
          options: question.options,
          defaultValue: question.defaultValue,
          allowOther: question.allowOther,
        );
      }
      parsed.add(question);
    }

    if (raw is List) {
      for (var i = 0; i < raw.length && parsed.length < maxQuestions; i++) {
        addQuestion(VibeAskUserQuestion.tryFromJson(raw[i], fallbackIndex: i));
      }
    } else if (raw is Map) {
      final listCandidate = raw['questions'] is List
          ? raw['questions'] as List
          : (raw['fields'] is List
                ? raw['fields'] as List
                : (raw['items'] is List ? raw['items'] as List : null));

      if (listCandidate != null) {
        for (
          var i = 0;
          i < listCandidate.length && parsed.length < maxQuestions;
          i++
        ) {
          addQuestion(
            VibeAskUserQuestion.tryFromJson(listCandidate[i], fallbackIndex: i),
          );
        }
      }

      if (parsed.isEmpty && raw['properties'] is Map) {
        final props = raw['properties'] as Map;
        var index = 0;
        for (final entry in props.entries) {
          if (parsed.length >= maxQuestions) break;
          addQuestion(
            VibeAskUserQuestion.tryFromJson(
              entry.value,
              fallbackId: entry.key.toString(),
              fallbackIndex: index,
            ),
          );
          index++;
        }
      }

      if (parsed.isEmpty &&
          raw['questions'] == null &&
          raw['fields'] == null &&
          raw['properties'] == null) {
        addQuestion(VibeAskUserQuestion.tryFromJson(raw, fallbackIndex: 0));
      }
    }

    if (parsed.isEmpty) {
      return null;
    }
    return VibeAskUserRequest(questions: parsed);
  }

  /// Retourne une copie plafonnée à [limit] questions, ou `null` si [limit] est inférieur ou égal à `0`.
  VibeAskUserRequest? truncate(int limit) {
    if (limit <= 0 || questions.isEmpty) return null;
    if (questions.length <= limit) return this;
    return VibeAskUserRequest(questions: questions.take(limit).toList());
  }

  /// Retourne une carte immuable associant chaque identifiant de question à sa réponse par défaut.
  Map<String, Object?> defaultAnswers() => Map<String, Object?>.unmodifiable({
    for (final q in questions) q.id: q.effectiveInitialAnswer(),
  });

  /// Formate un récapitulatif multi-lignes à puces des réponses fournies.
  String formatDisplaySummary(
    Map<String, Object?> answers, {
    bool usedDefaults = false,
  }) => questions
      .map((q) {
        final rawAnswer = (usedDefaults && !answers.containsKey(q.id))
            ? q.effectiveInitialAnswer()
            : (answers[q.id] ?? q.effectiveInitialAnswer());
        return '• ${q.title} : ${q.formatAnswerValue(rawAnswer)}';
      })
      .join('\n');

  /// Formate le message structuré en français transmis au prochain tour de l'assistant IA.
  String formatPromptReply(
    Map<String, Object?> answers, {
    bool usedDefaults = false,
    bool planMode = false,
  }) {
    final summary = formatDisplaySummary(answers, usedDefaults: usedDefaults);
    final action = planMode
        ? 'Génère maintenant directement le plan par lots ("plan") correspondant '
              'sans patch "vibe" et sans poser de nouvelles questions ("askUser": null).'
        : 'Génère maintenant directement le patch "vibe" correspondant '
              'sans poser de nouvelles questions ("askUser": null).';
    return 'Réponses aux questions de clarification'
        '${usedDefaults ? ' (valeurs par défaut retenues)' : ''} :\n'
        '$summary\n'
        '$action';
  }

  /// Formate le message structuré demandant une série complémentaire de questions après validation de [answers].
  String formatMoreQuestionsPromptReply(Map<String, Object?> answers) {
    final summary = formatDisplaySummary(answers);
    return 'Réponses enregistrées pour cette étape :\n'
        '$summary\n'
        'Ne génère PAS encore le patch "vibe" ("vibe": null obligatoire) : '
        'pose maintenant 2 à ${VibeQuestioningLevel.followUpMaxQuestions} nouvelles questions '
        'complémentaires et non redondantes avec "default" via "askUser" '
        'pour approfondir les points restants.';
  }

  /// Sérialise le questionnaire dans une carte JSON compatible avec [tryFromJson].
  Map<String, Object?> toJson() =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        'questions': List<Map<String, Object?>>.unmodifiable(
          questions.map((q) => q.toJson()),
        ),
      });

  /// Compare deux questionnaires par égalité profonde de leur liste de questions.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeAskUserRequest && listEquals(other.questions, questions);

  /// Code de hachage cohérent avec [operator ==].
  @override
  int get hashCode => Object.hashAll(questions);

  /// Représentation textuelle de diagnostic du questionnaire.
  @override
  String toString() => 'VibeAskUserRequest(questions: ${questions.length})';
}
