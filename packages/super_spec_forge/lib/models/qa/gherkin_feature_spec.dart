/// Modèles immuables des fonctionnalités BDD Gherkin, scénarios, plans de scénarios et étapes ([GherkinFeatureSpec], [GherkinScenarioSpec], [GherkinExamplesTable], [GherkinStep], [GherkinStepKeyword]).
library;

import 'package:flutter/foundation.dart';

import 'qa_forge_stage.dart';

/// Mot-clé logique d'une instruction Gherkin indépendamment de la langue d'export.
enum GherkinStepKeyword {
  /// Précondition initiale (`Étant donné` / `Given`).
  given('Étant donné'),

  /// Action ou événement déclencheur (`Quand` / `When`).
  when('Quand'),

  /// Résultat observable attendu (`Alors` / `Then`).
  then('Alors'),

  /// Clause additionnelle de même nature (`Et` / `And`).
  and('Et'),

  /// Clause restrictive ou d'opposition (`Mais` / `But`).
  but('Mais');

  /// Construit un mot-clé d'étape Gherkin.
  const GherkinStepKeyword(this.label);

  /// Libellé français par défaut.
  final String label;

  /// Retourne le mot-clé Gherkin localisé pour [lang].
  String keywordFor(GherkinKeywordLanguage lang) => switch (this) {
    GherkinStepKeyword.given => lang.givenKeyword,
    GherkinStepKeyword.when => lang.whenKeyword,
    GherkinStepKeyword.then => lang.thenKeyword,
    GherkinStepKeyword.and => lang.andKeyword,
    GherkinStepKeyword.but => lang.butKeyword,
  };

  /// Résout un mot-clé Gherkin depuis JSON (anglais ou français), avec repli sur [given].
  static GherkinStepKeyword fromJson(Object? raw) {
    if (raw is String) {
      final cleaned = raw
          .trim()
          .toLowerCase()
          .replaceAll('’', "'")
          .replaceAll(RegExp(r'[:\s]+$'), '')
          .replaceAll(RegExp(r'\s+'), ' ');
      for (final kw in GherkinStepKeyword.values) {
        if (kw.name == cleaned || kw.label.toLowerCase() == cleaned) {
          return kw;
        }
      }
      switch (cleaned) {
        case 'given':
        case 'étant donné':
        case 'etant donne':
        case 'étant donné que':
        case 'etant donne que':
        case "étant donné qu'":
        case "etant donne qu'":
        case 'étant donnée':
        case 'etant donnee':
        case 'étant donnés':
        case 'etant donnes':
        case 'étant données':
        case 'etant donnees':
        case 'soit':
        case 'sachant':
        case 'sachant que':
          return GherkinStepKeyword.given;
        case 'when':
        case 'quand':
        case 'lorsque':
        case "lorsqu'":
          return GherkinStepKeyword.when;
        case 'then':
        case 'alors':
          return GherkinStepKeyword.then;
        case 'and':
        case 'et':
        case '*':
          return GherkinStepKeyword.and;
        case 'but':
        case 'mais':
          return GherkinStepKeyword.but;
      }
    }
    return GherkinStepKeyword.given;
  }
}

/// Instruction atomique Gherkin (`Given` / `When` / `Then` / `And` / `But`) avec table ou bloc texte optionnels.
@immutable
class GherkinStep {
  /// Construit une étape Gherkin immuable.
  GherkinStep({
    required this.id,
    this.keyword = GherkinStepKeyword.given,
    required this.text,
    List<List<String>> dataTable = const <List<String>>[],
    this.docString = '',
  }) : dataTable = _freezeStringMatrix(dataTable);

  /// Identifiant unique de l'étape dans son contexte ou scénario.
  final String id;

  /// Mot-clé Gherkin de l'étape.
  final GherkinStepKeyword keyword;

  /// Énoncé de l'étape sans le mot-clé initial (peut contenir des variables `<var>`).
  final String text;

  /// Table de données Gherkin en ligne optionnelle (lignes de cellules texte).
  final List<List<String>> dataTable;

  /// Bloc texte multiligne (`"""`) attaché à l'étape (ex. charge JSON attendue).
  final String docString;

  /// Vérifie les invariants de l'étape Gherkin.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('GherkinStep.id ne peut pas être vide.');
    }
    if (text.trim().isEmpty) {
      throw const FormatException('GherkinStep.text ne peut pas être vide.');
    }
  }

  /// Retourne une copie modifiée.
  GherkinStep copyWith({
    String? id,
    GherkinStepKeyword? keyword,
    String? text,
    List<List<String>>? dataTable,
    String? docString,
  }) => GherkinStep(
    id: id ?? this.id,
    keyword: keyword ?? this.keyword,
    text: text ?? this.text,
    dataTable: dataTable ?? this.dataTable,
    docString: docString ?? this.docString,
  );

  /// Sérialise l'étape Gherkin en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'keyword': keyword.name,
    'text': text,
    'dataTable': dataTable,
    'docString': docString,
  };

  /// Désérialise une étape Gherkin depuis JSON avec valeurs de repli tolérantes.
  factory GherkinStep.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('GherkinStep doit être un objet JSON.');
    }
    final keyword = GherkinStepKeyword.fromJson(raw['keyword']);
    final rawText =
        (raw['text'] as String?)?.trim() ??
        (raw['step'] as String?)?.trim() ??
        (raw['description'] as String?)?.trim() ??
        '';
    final text = rawText.isEmpty ? 'Étape à préciser' : rawText;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final parsedTable = <List<String>>[];
    if (raw['dataTable'] is List) {
      for (final row in raw['dataTable'] as List) {
        if (row is List) {
          parsedTable.add([
            for (final cell in row) cell?.toString().trim() ?? '',
          ]);
        }
      }
    }
    final step = GherkinStep(
      id: rawId.isEmpty ? 'step_${text.hashCode.abs()}' : rawId,
      keyword: keyword,
      text: text,
      dataTable: parsedTable,
      docString: (raw['docString'] as String?) ?? '',
    );
    step.validate();
    return step;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GherkinStep &&
          other.id == id &&
          other.keyword == keyword &&
          other.text == text &&
          _stringMatrixEquals(other.dataTable, dataTable) &&
          other.docString == docString;

  @override
  int get hashCode => Object.hash(
    id,
    keyword,
    text,
    _stringMatrixHash(dataTable),
    docString,
  );
}

/// Table d'exemples paramétrant un `Plan du Scénario` / `Scenario Outline` Gherkin.
@immutable
class GherkinExamplesTable {
  /// Construit une table d'exemples Gherkin immuable.
  GherkinExamplesTable({
    List<String> headers = const <String>[],
    List<List<String>> rows = const <List<String>>[],
  }) : headers = List<String>.unmodifiable(headers),
       rows = _freezeStringMatrix(rows);

  const GherkinExamplesTable._empty()
    : headers = const <String>[],
      rows = const <List<String>>[];

  /// Table d'exemples vide constante.
  static const GherkinExamplesTable empty = GherkinExamplesTable._empty();

  /// Noms des colonnes servant de variables `<colonne>` dans les étapes du scénario.
  final List<String> headers;

  /// Lignes de valeurs concrètes associées aux [headers].
  final List<List<String>> rows;

  /// Vrai si la table ne contient ni en-têtes ni lignes.
  bool get isEmpty => headers.isEmpty && rows.isEmpty;

  /// Vrai si au moins un en-tête ou une ligne d'exemple est défini.
  bool get isNotEmpty => headers.isNotEmpty || rows.isNotEmpty;

  /// Vérifie la cohérence des en-têtes et l'alignement strict des colonnes de chaque ligne.
  void validate() {
    if (rows.isNotEmpty && headers.isEmpty) {
      throw const FormatException(
        'GherkinExamplesTable.headers ne peut pas être vide lorsque des lignes sont présentes.',
      );
    }
    for (final header in headers) {
      if (header.trim().isEmpty) {
        throw const FormatException(
          'GherkinExamplesTable.headers ne peut pas contenir d’en-tête vide.',
        );
      }
    }
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].length != headers.length) {
        throw FormatException(
          'GherkinExamplesTable.rows[$i] contient ${rows[i].length} cellule(s) au lieu de ${headers.length}.',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  GherkinExamplesTable copyWith({
    List<String>? headers,
    List<List<String>>? rows,
  }) => GherkinExamplesTable(
    headers: headers ?? this.headers,
    rows: rows ?? this.rows,
  );

  /// Sérialise la table d'exemples en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'headers': headers,
    'rows': rows,
  };

  /// Désérialise une table d'exemples depuis JSON en alignant avec tolérance la longueur des lignes.
  factory GherkinExamplesTable.fromJson(Object? raw) {
    if (raw == null) return GherkinExamplesTable.empty;
    if (raw is! Map) {
      throw const FormatException(
        'GherkinExamplesTable doit être un objet JSON.',
      );
    }

    final rawHeaders = raw['headers'];
    final parsedHeaders = <String>[];
    if (rawHeaders is List) {
      for (var i = 0; i < rawHeaders.length; i++) {
        final text = rawHeaders[i]?.toString().trim() ?? '';
        parsedHeaders.add(text.isEmpty ? 'col_${i + 1}' : text);
      }
    }

    final rawRows = raw['rows'];
    final rawRowList = rawRows is List ? rawRows : const <Object?>[];

    if (parsedHeaders.isEmpty && rawRowList.isNotEmpty) {
      final first = rawRowList.first;
      if (first is Map && first.isNotEmpty) {
        var idx = 1;
        for (final key in first.keys) {
          final k = key?.toString().trim() ?? '';
          parsedHeaders.add(k.isEmpty ? 'col_$idx' : k);
          idx++;
        }
      } else {
        var maxCols = 0;
        for (final row in rawRowList) {
          if (row is List && row.length > maxCols) {
            maxCols = row.length;
          }
        }
        for (var i = 0; i < maxCols; i++) {
          parsedHeaders.add('col_${i + 1}');
        }
      }
    }

    final normalizedRows = <List<String>>[];
    if (parsedHeaders.isNotEmpty) {
      final targetLen = parsedHeaders.length;
      for (final rawRow in rawRowList) {
        if (rawRow is List) {
          final cells = <String>[
            for (var i = 0; i < targetLen; i++)
              i < rawRow.length ? (rawRow[i]?.toString().trim() ?? '') : '',
          ];
          normalizedRows.add(cells);
        } else if (rawRow is Map) {
          final cells = <String>[
            for (final h in parsedHeaders) rawRow[h]?.toString().trim() ?? '',
          ];
          normalizedRows.add(cells);
        }
      }
    }

    final table = GherkinExamplesTable(
      headers: parsedHeaders,
      rows: normalizedRows,
    );
    table.validate();
    return table;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GherkinExamplesTable &&
          listEquals(other.headers, headers) &&
          _stringMatrixEquals(other.rows, rows);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(headers),
    _stringMatrixHash(rows),
  );
}

/// Scénario ou plan de scénario Gherkin doté d'une traçabilité complète Métier + UX + Fixtures.
@immutable
class GherkinScenarioSpec {
  /// Construit un scénario Gherkin immuable en normalisant ses [tags] avec le préfixe `@`.
  GherkinScenarioSpec({
    required this.id,
    this.code = 'SCN',
    required this.title,
    this.isOutline = false,
    List<String> tags = const <String>[],
    List<GherkinStep> steps = const <GherkinStep>[],
    this.examples = GherkinExamplesTable.empty,
    List<String> requirementIds = const <String>[],
    List<String> useCaseIds = const <String>[],
    List<String> businessRuleIds = const <String>[],
    List<String> journeyIds = const <String>[],
    List<String> screenIds = const <String>[],
    List<String> fixtureIds = const <String>[],
  }) : tags = List<String>.unmodifiable(_normalizeTagList(tags)),
       steps = List<GherkinStep>.unmodifiable(steps),
       requirementIds = List<String>.unmodifiable(requirementIds),
       useCaseIds = List<String>.unmodifiable(useCaseIds),
       businessRuleIds = List<String>.unmodifiable(businessRuleIds),
       journeyIds = List<String>.unmodifiable(journeyIds),
       screenIds = List<String>.unmodifiable(screenIds),
       fixtureIds = List<String>.unmodifiable(fixtureIds);

  static final RegExp _outlineVarPattern = RegExp(r'<([A-Za-z0-9_-]+)>');

  /// Identifiant technique unique du scénario (ex. `scn_valider_commande`).
  final String id;

  /// Code métier lisible du scénario (ex. `SCN-001`).
  final String code;

  /// Titre fonctionnel du scénario.
  final String title;

  /// Indique s'il s'agit d'un `Plan du Scénario` (`Scenario Outline`) piloté par [examples].
  final bool isOutline;

  /// Étiquettes Gherkin normalisées avec préfixe `@` (ex. `@smoke`, `@rg-001`).
  final List<String> tags;

  /// Séquence ordonnée des étapes `Given` / `When` / `Then` du scénario.
  final List<GherkinStep> steps;

  /// Table d'exemples associée lorsque [isOutline] vaut `true`.
  final GherkinExamplesTable examples;

  /// Identifiants ou codes des exigences fonctionnelles (`EXF-xxx`) vérifiées.
  final List<String> requirementIds;

  /// Identifiants des cas d'usage (`UseCaseSpec`) exercés.
  final List<String> useCaseIds;

  /// Identifiants ou codes des règles de gestion (`RG-xxx`) testées.
  final List<String> businessRuleIds;

  /// Identifiants ou codes des parcours UX (`JRN-xxx`) couverts.
  final List<String> journeyIds;

  /// Identifiants ou codes des écrans UX (`SCR-xxx`) traversés.
  final List<String> screenIds;

  /// Identifiants ou codes des jeux d'essais (`FIX-xxx`) mobilisés.
  final List<String> fixtureIds;

  /// Normalise une étiquette Gherkin pour qu'elle débute par un unique `@` sans espaces internes.
  static String normalizeTag(String raw) {
    final stripped = raw
        .trim()
        .replaceFirst(RegExp(r'^@+'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    if (stripped.isEmpty) return '';
    return '@$stripped';
  }

  /// Extrait l'ensemble des variables `<nomVar>` référencées dans les [steps] du scénario.
  Set<String> get referencedOutlineVariables {
    final vars = <String>{};
    void collectFrom(String source) {
      if (source.isEmpty) return;
      for (final match in _outlineVarPattern.allMatches(source)) {
        final group = match.group(1);
        if (group != null && group.isNotEmpty) {
          vars.add(group);
        }
      }
    }

    for (final step in steps) {
      collectFrom(step.text);
      collectFrom(step.docString);
      for (final row in step.dataTable) {
        for (final cell in row) {
          collectFrom(cell);
        }
      }
    }
    return Set<String>.unmodifiable(vars);
  }

  /// Vérifie les invariants du scénario, l'unicité des étapes et la table [examples].
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'GherkinScenarioSpec.id ne peut pas être vide.',
      );
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'GherkinScenarioSpec.title ne peut pas être vide.',
      );
    }
    for (final tag in tags) {
      if (!tag.startsWith('@') || tag.length < 2) {
        throw FormatException(
          'Tag Gherkin invalide « $tag » dans le scénario « $title ».',
        );
      }
    }
    final stepIds = <String>{};
    for (final step in steps) {
      step.validate();
      if (!stepIds.add(step.id)) {
        throw FormatException(
          'Étape Gherkin dupliquée « ${step.id} » dans le scénario « $title ».',
        );
      }
    }
    examples.validate();
  }

  /// Retourne une copie modifiée.
  GherkinScenarioSpec copyWith({
    String? id,
    String? code,
    String? title,
    bool? isOutline,
    List<String>? tags,
    List<GherkinStep>? steps,
    GherkinExamplesTable? examples,
    List<String>? requirementIds,
    List<String>? useCaseIds,
    List<String>? businessRuleIds,
    List<String>? journeyIds,
    List<String>? screenIds,
    List<String>? fixtureIds,
  }) => GherkinScenarioSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    title: title ?? this.title,
    isOutline: isOutline ?? this.isOutline,
    tags: tags ?? this.tags,
    steps: steps ?? this.steps,
    examples: examples ?? this.examples,
    requirementIds: requirementIds ?? this.requirementIds,
    useCaseIds: useCaseIds ?? this.useCaseIds,
    businessRuleIds: businessRuleIds ?? this.businessRuleIds,
    journeyIds: journeyIds ?? this.journeyIds,
    screenIds: screenIds ?? this.screenIds,
    fixtureIds: fixtureIds ?? this.fixtureIds,
  );

  /// Sérialise le scénario en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'title': title,
    'isOutline': isOutline,
    'tags': tags,
    'steps': [for (final s in steps) s.toJson()],
    'examples': examples.toJson(),
    'requirementIds': requirementIds,
    'useCaseIds': useCaseIds,
    'businessRuleIds': businessRuleIds,
    'journeyIds': journeyIds,
    'screenIds': screenIds,
    'fixtureIds': fixtureIds,
  };

  /// Désérialise un scénario Gherkin depuis JSON avec normalisation tolérante.
  factory GherkinScenarioSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'GherkinScenarioSpec doit être un objet JSON.',
      );
    }
    final rawTitle =
        (raw['title'] as String?)?.trim() ??
        (raw['name'] as String?)?.trim() ??
        '';
    final title = rawTitle.isEmpty ? 'Scénario sans titre' : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';
    final parsedSteps = _parseUniqueSteps(raw['steps']);
    final examples = GherkinExamplesTable.fromJson(raw['examples']);
    final isOutline = raw['isOutline'] is bool
        ? raw['isOutline'] as bool
        : examples.isNotEmpty;

    final scenario = GherkinScenarioSpec(
      id: rawId.isEmpty ? 'scn_${title.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'SCN' : rawCode,
      title: title,
      isOutline: isOutline,
      tags: _stringList(raw['tags']),
      steps: parsedSteps,
      examples: examples,
      requirementIds: _stringList(raw['requirementIds']),
      useCaseIds: _stringList(raw['useCaseIds']),
      businessRuleIds: _stringList(raw['businessRuleIds']),
      journeyIds: _stringList(raw['journeyIds']),
      screenIds: _stringList(raw['screenIds']),
      fixtureIds: _stringList(raw['fixtureIds']),
    );
    scenario.validate();
    return scenario;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GherkinScenarioSpec &&
          other.id == id &&
          other.code == code &&
          other.title == title &&
          other.isOutline == isOutline &&
          listEquals(other.tags, tags) &&
          listEquals(other.steps, steps) &&
          other.examples == examples &&
          listEquals(other.requirementIds, requirementIds) &&
          listEquals(other.useCaseIds, useCaseIds) &&
          listEquals(other.businessRuleIds, businessRuleIds) &&
          listEquals(other.journeyIds, journeyIds) &&
          listEquals(other.screenIds, screenIds) &&
          listEquals(other.fixtureIds, fixtureIds);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    title,
    isOutline,
    Object.hashAll(tags),
    Object.hashAll(steps),
    examples,
    Object.hashAll(requirementIds),
    Object.hashAll(useCaseIds),
    Object.hashAll(businessRuleIds),
    Object.hashAll(journeyIds),
    Object.hashAll(screenIds),
    Object.hashAll(fixtureIds),
  );
}

/// Fonctionnalité Gherkin complète (`.feature`) regroupant contexte et scénarios BDD (étape QA 2).
@immutable
class GherkinFeatureSpec {
  /// Construit une fonctionnalité Gherkin immuable en normalisant ses [tags] avec `@`.
  GherkinFeatureSpec({
    required this.id,
    this.code = 'FEAT',
    required this.title,
    this.moduleId = '',
    this.personaId = '',
    this.narrative = '',
    List<String> tags = const <String>[],
    List<GherkinStep> backgroundSteps = const <GherkinStep>[],
    List<GherkinScenarioSpec> scenarios = const <GherkinScenarioSpec>[],
  }) : tags = List<String>.unmodifiable(_normalizeTagList(tags)),
       backgroundSteps = List<GherkinStep>.unmodifiable(backgroundSteps),
       scenarios = List<GherkinScenarioSpec>.unmodifiable(scenarios);

  /// Identifiant technique unique de la feature (ex. `feat_validation_commandes`).
  final String id;

  /// Code métier lisible de la feature (ex. `FEAT-001`).
  final String code;

  /// Titre fonctionnel de la feature.
  final String title;

  /// Identifiant optionnel du `SpecModule` fonctionnel rattaché.
  final String moduleId;

  /// Identifiant optionnel du persona principal concerné.
  final String personaId;

  /// Récit utilisateur (`En tant que... Je veux... Afin de...`).
  final String narrative;

  /// Étiquettes Gherkin de niveau feature normalisées avec `@`.
  final List<String> tags;

  /// Étapes de précondition partagées (`Contexte` / `Background`).
  final List<GherkinStep> backgroundSteps;

  /// Scénarios et plans de scénarios rattachés à cette fonctionnalité.
  final List<GherkinScenarioSpec> scenarios;

  /// Normalise une étiquette Gherkin avec le préfixe `@`.
  static String normalizeTag(String raw) => GherkinScenarioSpec.normalizeTag(raw);

  /// Vérifie les invariants de la feature, de son contexte et de ses scénarios.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'GherkinFeatureSpec.id ne peut pas être vide.',
      );
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'GherkinFeatureSpec.title ne peut pas être vide.',
      );
    }
    for (final tag in tags) {
      if (!tag.startsWith('@') || tag.length < 2) {
        throw FormatException(
          'Tag Gherkin invalide « $tag » dans la feature « $title ».',
        );
      }
    }
    final bgStepIds = <String>{};
    for (final step in backgroundSteps) {
      step.validate();
      if (!bgStepIds.add(step.id)) {
        throw FormatException(
          'Étape de contexte dupliquée « ${step.id} » dans la feature « $title ».',
        );
      }
    }
    final scenarioIds = <String>{};
    for (final scenario in scenarios) {
      scenario.validate();
      if (!scenarioIds.add(scenario.id)) {
        throw FormatException(
          'Scénario Gherkin dupliqué « ${scenario.id} » dans la feature « $title ».',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  GherkinFeatureSpec copyWith({
    String? id,
    String? code,
    String? title,
    String? moduleId,
    String? personaId,
    String? narrative,
    List<String>? tags,
    List<GherkinStep>? backgroundSteps,
    List<GherkinScenarioSpec>? scenarios,
  }) => GherkinFeatureSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    title: title ?? this.title,
    moduleId: moduleId ?? this.moduleId,
    personaId: personaId ?? this.personaId,
    narrative: narrative ?? this.narrative,
    tags: tags ?? this.tags,
    backgroundSteps: backgroundSteps ?? this.backgroundSteps,
    scenarios: scenarios ?? this.scenarios,
  );

  /// Sérialise la feature Gherkin en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'title': title,
    'moduleId': moduleId,
    'personaId': personaId,
    'narrative': narrative,
    'tags': tags,
    'backgroundSteps': [for (final s in backgroundSteps) s.toJson()],
    'scenarios': [for (final sc in scenarios) sc.toJson()],
  };

  /// Désérialise une feature Gherkin depuis JSON avec valeurs de repli tolérantes.
  factory GherkinFeatureSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'GherkinFeatureSpec doit être un objet JSON.',
      );
    }
    final rawTitle =
        (raw['title'] as String?)?.trim() ??
        (raw['name'] as String?)?.trim() ??
        '';
    final title = rawTitle.isEmpty ? 'Fonctionnalité sans titre' : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';

    final parsedScenarios = <GherkinScenarioSpec>[];
    final seenScenarioIds = <String>{};
    if (raw['scenarios'] is List) {
      for (final item in raw['scenarios'] as List) {
        var scenario = GherkinScenarioSpec.fromJson(item);
        if (!seenScenarioIds.add(scenario.id)) {
          var suffix = 2;
          while (!seenScenarioIds.add('${scenario.id}_$suffix')) {
            suffix++;
          }
          scenario = scenario.copyWith(id: '${scenario.id}_$suffix');
        }
        parsedScenarios.add(scenario);
      }
    }

    final feature = GherkinFeatureSpec(
      id: rawId.isEmpty ? 'feat_${title.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'FEAT' : rawCode,
      title: title,
      moduleId: (raw['moduleId'] as String?)?.trim() ?? '',
      personaId: (raw['personaId'] as String?)?.trim() ?? '',
      narrative: (raw['narrative'] as String?)?.trim() ?? '',
      tags: _stringList(raw['tags']),
      backgroundSteps: _parseUniqueSteps(raw['backgroundSteps']),
      scenarios: parsedScenarios,
    );
    feature.validate();
    return feature;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GherkinFeatureSpec &&
          other.id == id &&
          other.code == code &&
          other.title == title &&
          other.moduleId == moduleId &&
          other.personaId == personaId &&
          other.narrative == narrative &&
          listEquals(other.tags, tags) &&
          listEquals(other.backgroundSteps, backgroundSteps) &&
          listEquals(other.scenarios, scenarios);

  @override
  int get hashCode => Object.hash(
    id,
    code,
    title,
    moduleId,
    personaId,
    narrative,
    Object.hashAll(tags),
    Object.hashAll(backgroundSteps),
    Object.hashAll(scenarios),
  );
}

List<GherkinStep> _parseUniqueSteps(Object? raw) {
  if (raw is! List) return const <GherkinStep>[];
  final parsed = <GherkinStep>[];
  final seenIds = <String>{};
  for (final item in raw) {
    var step = GherkinStep.fromJson(item);
    if (!seenIds.add(step.id)) {
      var suffix = 2;
      while (!seenIds.add('${step.id}_$suffix')) {
        suffix++;
      }
      step = step.copyWith(id: '${step.id}_$suffix');
    }
    parsed.add(step);
  }
  return parsed;
}

List<String> _normalizeTagList(Iterable<String> rawTags) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in rawTags) {
    final normalized = GherkinScenarioSpec.normalizeTag(raw);
    if (normalized.isNotEmpty && seen.add(normalized)) {
      result.add(normalized);
    }
  }
  return result;
}

List<List<String>> _freezeStringMatrix(List<List<String>> rows) {
  if (rows.isEmpty) return const <List<String>>[];
  return List<List<String>>.unmodifiable([
    for (final row in rows) List<String>.unmodifiable(row),
  ]);
}

bool _stringMatrixEquals(List<List<String>> a, List<List<String>> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!listEquals(a[i], b[i])) return false;
  }
  return true;
}

int _stringMatrixHash(List<List<String>> matrix) =>
    Object.hashAll(matrix.map(Object.hashAll));

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
