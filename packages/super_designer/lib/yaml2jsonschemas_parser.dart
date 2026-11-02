/// Parser du DSL YAML « JSON Schemas Light », orienté humain.
///
/// Chaque clé de premier niveau définit un type nommé (`User:`, `Page:`…) ;
/// ses clés sont des champs. Règles d'un champ :
///
/// | Syntaxe                      | Nœud produit                               |
/// |------------------------------|--------------------------------------------|
/// | `string`, `int`, `uuid`…     | type primitif                              |
/// | `string!`                    | `properties.required = true`               |
/// | `string(enum)`, `int(enum)`  | énumération typée, `properties.enum = []`  |
/// | `enum(a, b, c)`              | type `enum`, `properties.enum = [a, b, c]` |
/// | `User`                       | référence à une définition                 |
/// | `users[]: User`, `User[]`    | `properties.array = true`                  |
/// | `json`                       | structure libre                            |
/// | `A \| B`                     | type `union`, une alternative par enfant   |
/// | `A \| null`                  | `properties.nullable = true`               |
/// | `oneOf:` / `anyOf:` / `allOf:` | type de la composition, un enfant par alternative |
/// | sous-objet YAML              | type `object`, un enfant par champ         |
/// | `when field == value:`       | type `when`, champs conditionnels enfants |
///
/// Un bloc `when` appartient à un objet et référence un champ du même objet.
/// `properties.condition` contient `field`, `operator` (`==`) et `value`
/// (scalaire YAML : texte, nombre, booléen ou null). La condition décrit le
/// schéma ; elle n'est pas évaluée sur des données par ce parser.
///
/// Les valeurs d'une énumération `string(enum)` sont laissées vides pour être
/// saisies plus tard (IHM) ; [mergeProperties] les conserve lors d'un patch.
library;

import 'package:shortid/shortid.dart';
import 'package:yaml/yaml.dart';

import 'json_browser.dart';

/// Convertit le DSL YAML en arbre de [JsonNode] (un nœud racine par
/// définition), réutilisable dans un [JsonModel].
class Yaml2JsonSchemasParser {
  Yaml2JsonSchemasParser({String Function()? generateId})
    : _generateId = generateId ?? shortid.generate;

  /// Types primitifs reconnus.
  static const primitives = {
    'string',
    'int',
    'integer',
    'number',
    'float',
    'double',
    'decimal',
    'bool',
    'boolean',
    'uuid',
    'email',
    'url',
    'uri',
    'date',
    'datetime',
    'time',
    'json',
    'any',
    'null',
  };

  static const _numeric = {
    'int',
    'integer',
    'number',
    'float',
    'double',
    'decimal',
  };

  /// Clés YAML de composition, devenant le type du nœud.
  static const compositions = {'oneOf', 'anyOf', 'allOf'};

  static const objectType = 'object';
  static const unionType = 'union';
  static const enumType = 'enum';
  static const whenType = 'when';

  /// Propriétés dérivées du DSL ; les autres viennent de l'IHM.
  static const dslProperties = {
    'required',
    'nullable',
    'array',
    'enum',
    'condition',
  };

  static final _whenPrefix = RegExp(r'^when(?:\s|$)');
  static final _whenPattern = RegExp(r'^when\s+([A-Za-z_][\w-]*)\s*==\s*(.+)$');
  static final _keyPattern = RegExp(r'^([A-Za-z_][\w-]*)(\[\])?(!)?$');
  static final _termPattern = RegExp(
    r'^([A-Za-z_]\w*)\s*(?:\((.*)\))?\s*(\[\])?\s*(!)?$',
  );

  final String Function() _generateId;
  final Set<String> _ids = {};
  Set<String> _definitions = const {};

  /// Nœuds racines (un par définition) du schéma [yaml].
  ///
  /// Lève une [FormatException] (avec le chemin fautif) si le YAML ou le DSL
  /// est invalide, ou si un type référencé n'est pas défini.
  List<JsonNode> parse(String yaml) => _parse(yaml).nodes;

  /// Crée un [JsonModel] nommé [name] à partir du schéma [yaml].
  JsonModel model(String name, String yaml) {
    final result = _parse(yaml);
    return JsonModel(
      name: name,
      json: result.document,
      nodes: result.nodes,
      generateId: _generateId,
    );
  }

  /// Applique le schéma [yaml] à [model] en conservant au maximum les ID
  /// et les propriétés saisies dans l'IHM. En cas d'erreur, [model] reste
  /// inchangé.
  void patch(JsonModel model, String yaml) {
    final result = _parse(yaml);
    model.patchNodes(result.document, result.nodes, merge: mergeProperties);
  }

  /// Propriétés d'un nœud retrouvé : celles de l'IHM sont conservées, celles
  /// du DSL ([dslProperties]) recalculées. Les valeurs d'une énumération
  /// laissées vides par le DSL (`string(enum)`) gardent celles déjà saisies si
  /// le type n'a pas changé.
  static Map<String, Object?> mergeProperties(JsonNode old, JsonNode fresh) {
    final merged = <String, Object?>{
      for (final entry in old.properties.entries)
        if (!dslProperties.contains(entry.key)) entry.key: entry.value,
      ...fresh.properties,
    };
    final oldEnum = old.properties['enum'];
    final freshEnum = fresh.properties['enum'];
    if (freshEnum is List &&
        freshEnum.isEmpty &&
        oldEnum is List &&
        oldEnum.isNotEmpty &&
        old.type == fresh.type) {
      merged['enum'] = List<Object?>.of(oldEnum);
    }
    return merged;
  }

  ({Object? document, List<JsonNode> nodes}) _parse(String yaml) {
    final Object? document;
    try {
      document = _plain(loadYaml(yaml));
    } on YamlException catch (error) {
      throw FormatException(error.toString());
    }
    if (document == null) return (document: null, nodes: const []);
    if (document is! Map<String, Object?>) {
      throw const FormatException(
        'Le schéma doit être un objet YAML de définitions (Nom: …).',
      );
    }
    _ids.clear();
    _definitions = {};
    for (final key in document.keys) {
      final name = _key(key, key).name;
      if (primitives.contains(name) ||
          compositions.contains(name) ||
          {objectType, unionType, enumType, whenType}.contains(name)) {
        throw FormatException('$key : nom de définition réservé.');
      }
      _definitions.add(name);
    }
    final nodes = [
      for (final entry in document.entries)
        _field(entry.key, entry.value, null),
    ];
    for (final node in _walk(nodes)) {
      if (!_isKnown(node.type)) {
        throw FormatException('${node.path} : type inconnu « ${node.type} ».');
      }
      if (node.type == whenType) {
        final condition = node.properties['condition'];
        final parent = node.parent;
        if (condition is! Map<String, Object?> || parent == null) {
          throw FormatException(
            '${node.path} : when attend un bloc conditionnel.',
          );
        }
        if (!parent.children.any(
          (sibling) =>
              sibling.name == condition['field'] && sibling.type != whenType,
        )) {
          throw FormatException(
            '${node.path} : champ de condition inconnu « ${condition['field']} ».',
          );
        }
      }
    }
    return (document: document, nodes: nodes);
  }

  bool _isKnown(String type) =>
      primitives.contains(type) ||
      compositions.contains(type) ||
      type == objectType ||
      type == unionType ||
      type == enumType ||
      type == whenType ||
      _definitions.contains(type);

  static Iterable<JsonNode> _walk(List<JsonNode> nodes) sync* {
    for (final node in nodes) {
      yield node;
      yield* _walk(node.children);
    }
  }

  ({String name, bool array, bool required}) _key(String raw, String where) {
    final match = _keyPattern.firstMatch(raw.trim());
    if (match == null) {
      throw FormatException('$where : nom de champ invalide « $raw ».');
    }
    return (
      name: match[1]!,
      array: match[2] != null,
      required: match[3] != null,
    );
  }

  static String _location(JsonNode? parent, String name) {
    if (parent == null) return name;
    return name.startsWith('[')
        ? '${parent.path}$name'
        : '${parent.path}.$name';
  }

  JsonNode _field(String rawKey, Object? value, JsonNode? parent) {
    if (_whenPrefix.hasMatch(rawKey.trim())) {
      return _when(rawKey.trim(), value, parent);
    }
    final key = _key(rawKey, _location(parent, rawKey));
    final node = _typed(key.name, value, parent);
    if (key.array) node.properties['array'] = true;
    if (key.required) node.properties['required'] = true;
    return node;
  }

  JsonNode _when(String name, Object? value, JsonNode? parent) {
    final where = _location(parent, name);
    final match = _whenPattern.firstMatch(name);
    if (parent == null || match == null) {
      throw FormatException(
        '$where : condition attendue : when champ == valeur.',
      );
    }
    if (value is! Map<String, Object?> || value.isEmpty) {
      throw FormatException(
        '$where : when attend un objet de champs non vide.',
      );
    }
    final literal = match[2]!.trim();
    final Object? expected;
    try {
      expected = loadYaml(literal);
    } on YamlException catch (error) {
      throw FormatException('$where : valeur de condition invalide : $error');
    }
    final quoted = literal.startsWith('"') || literal.startsWith("'");
    if ((expected != null &&
            expected is! String &&
            expected is! num &&
            expected is! bool) ||
        (expected is String &&
            !quoted &&
            !RegExp(r'^[A-Za-z_][\w-]*$').hasMatch(literal))) {
      throw FormatException(
        '$where : la condition attend une valeur scalaire.',
      );
    }
    final node = _object(name, value, parent, type: whenType);
    node.properties['condition'] = <String, Object?>{
      'field': match[1]!,
      'operator': '==',
      'value': expected,
    };
    return node;
  }

  JsonNode _object(
    String name,
    Map<String, Object?> value,
    JsonNode? parent, {
    String type = objectType,
  }) {
    final node = _node(name, type, value, parent);
    node.children.addAll([
      for (final entry in value.entries) _field(entry.key, entry.value, node),
    ]);
    return node;
  }

  /// Nœud d'une valeur YAML : expression, objet ou composition.
  JsonNode _typed(String name, Object? value, JsonNode? parent) {
    final where = _location(parent, name);
    switch (value) {
      case null:
        return _expression(name, 'null', parent);
      case String():
        return _expression(name, value, parent);
      case Map<String, Object?>():
        final kinds = value.keys.where(compositions.contains).toList();
        if (kinds.isEmpty) {
          return _object(name, value, parent);
        }
        if (value.length != 1) {
          throw FormatException(
            '$where : ${kinds.first} doit être la seule clé de l’objet.',
          );
        }
        return _composition(name, kinds.single, value, parent);
      case List():
        throw FormatException(
          '$where : liste inattendue, utilisez oneOf, anyOf ou allOf.',
        );
      default:
        throw FormatException('$where : type attendu, « $value » trouvé.');
    }
  }

  JsonNode _composition(
    String name,
    String kind,
    Map<String, Object?> value,
    JsonNode? parent,
  ) {
    final node = _node(name, kind, value, parent);
    final where = _location(parent, name);
    final alternatives = switch (value[kind]) {
      final String text => _split(text, '|'),
      final List<Object?> items => items,
      _ => throw FormatException(
        '$where : $kind attend une liste d’alternatives.',
      ),
    };
    if (alternatives.isEmpty) {
      throw FormatException('$where : $kind sans alternative.');
    }
    for (var i = 0; i < alternatives.length; i++) {
      node.children.add(_typed('[$i]', alternatives[i], node));
    }
    return node;
  }

  /// Expression d'un champ : `T`, `T!`, `T(enum)`, `T[]`, `A | B | null`…
  JsonNode _expression(String name, String text, JsonNode? parent) {
    final where = _location(parent, name);
    var expression = text.trim();
    var required = false;
    if (expression.endsWith('!')) {
      required = true;
      expression = expression.substring(0, expression.length - 1).trimRight();
    }
    final parts = _split(expression, '|');
    if (parts.isEmpty || parts.any((part) => part.isEmpty)) {
      throw FormatException('$where : expression de type vide dans « $text ».');
    }
    var nullable = false;
    final terms = <_Term>[];
    for (final part in parts) {
      if (part == 'null' && parts.length > 1) {
        nullable = true;
      } else {
        terms.add(_term(part, where));
      }
    }
    final JsonNode node;
    if (terms.length == 1) {
      node = _node(name, terms.single.type, text, parent);
      terms.single.applyTo(node.properties);
    } else {
      node = _node(name, unionType, text, parent);
      for (var i = 0; i < terms.length; i++) {
        final child = _node('[$i]', terms[i].type, terms[i].text, node);
        terms[i].applyTo(child.properties);
        node.children.add(child);
      }
    }
    if (nullable) node.properties['nullable'] = true;
    if (required) node.properties['required'] = true;
    return node;
  }

  _Term _term(String text, String where) {
    final match = _termPattern.firstMatch(text);
    if (match == null) {
      throw FormatException('$where : type invalide « $text ».');
    }
    final type = match[1]!;
    final arguments = match[2]?.trim();
    List<Object?>? values;
    if (arguments != null || type == enumType) {
      if (arguments == null || arguments.isEmpty || arguments == 'enum') {
        if (type == enumType && arguments != null && arguments.isNotEmpty) {
          throw FormatException('$where : enum(…) attend des valeurs.');
        }
        values = [];
      } else {
        values = [
          for (final raw in _split(arguments, ','))
            _enumValue(raw, type, where),
        ];
      }
    }
    return _Term(
      text: text,
      type: type,
      array: match[3] != null,
      required: match[4] != null,
      values: values,
    );
  }

  static Object? _enumValue(String raw, String type, String where) {
    if (raw.isEmpty) {
      throw FormatException('$where : valeur d’énumération vide.');
    }
    final quoted =
        raw.length >= 2 &&
        (raw[0] == '"' || raw[0] == "'") &&
        raw[raw.length - 1] == raw[0];
    if (quoted) return raw.substring(1, raw.length - 1);
    if (_numeric.contains(type)) {
      final number = num.tryParse(raw);
      if (number == null) {
        throw FormatException('$where : « $raw » n’est pas un nombre.');
      }
      return type == 'int' || type == 'integer' ? number.toInt() : number;
    }
    if (type == enumType) {
      return num.tryParse(raw) ??
          switch (raw) {
            'true' => true,
            'false' => false,
            _ => raw,
          };
    }
    return raw;
  }

  /// Découpe [text] sur [separator] hors parenthèses et guillemets.
  static List<String> _split(String text, String separator) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    String? quote;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quote != null) {
        if (char == quote) quote = null;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '(') depth++;
      if (char == ')') depth--;
      if (char == separator && depth == 0) {
        parts.add(text.substring(start, i).trim());
        start = i + 1;
      }
    }
    final last = text.substring(start).trim();
    if (last.isNotEmpty || parts.isNotEmpty) parts.add(last);
    return parts;
  }

  JsonNode _node(String name, String type, Object? value, JsonNode? parent) {
    var id = _generateId();
    while (!_ids.add(id)) {
      id = _generateId();
    }
    return JsonNode(
      id: id,
      name: name,
      type: type,
      value: value,
      parent: parent,
    );
  }

  static Object? _plain(Object? value) => switch (value) {
    Map() => <String, Object?>{
      for (final entry in value.entries) '${entry.key}': _plain(entry.value),
    },
    List() => [for (final item in value) _plain(item)],
    _ => value,
  };
}

class _Term {
  const _Term({
    required this.text,
    required this.type,
    required this.array,
    required this.required,
    required this.values,
  });

  final String text;
  final String type;
  final bool array;
  final bool required;
  final List<Object?>? values;

  void applyTo(Map<String, Object?> properties) {
    if (array) properties['array'] = true;
    if (required) properties['required'] = true;
    if (values != null) properties['enum'] = values;
  }
}
