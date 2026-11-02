import 'package:flutter_test/flutter_test.dart';
import 'package:super_designer/json_browser.dart';
import 'package:super_designer/yaml2jsonschemas_parser.dart';

const _example = '''
User:
  id: uuid!
  firstname: string!
  lastname: string!
  age: int
  status : string(enum)

  email: email | null

  tags[]: string

  address:
    street: string!
    city: string!
    zipCode: string!

Company:
  id: uuid!
  name: string!

  employees[]: User

Page:
  title: string!
  content[]: TextBlock | ImageBlock | VideoBlock
  content2:
     oneOf:
       - TextBlock
       - ImageBlock
       - VideoBlock


TextBlock:
  text: string!

ImageBlock:
  url: url!
  alt: string

VideoBlock:
  url: url!

Webhook:
  headers: json
  payload: json

Response:
  data: User | Company | Error

Error:
  code: int(enum)
  level: enum(low, high, 3)
''';

void main() {
  late Yaml2JsonSchemasParser parser;

  setUp(() {
    var next = 0;
    parser = Yaml2JsonSchemasParser(generateId: () => 'id${next++}');
  });

  JsonNode at(List<JsonNode> roots, String path) {
    Iterable<JsonNode> walk(List<JsonNode> nodes) sync* {
      for (final node in nodes) {
        yield node;
        yield* walk(node.children);
      }
    }

    return walk(roots).firstWhere((node) => node.path == path);
  }

  test('parses the example into one root node per definition', () {
    final roots = parser.parse(_example);

    expect(roots.map((node) => node.name), [
      'User',
      'Company',
      'Page',
      'TextBlock',
      'ImageBlock',
      'VideoBlock',
      'Webhook',
      'Response',
      'Error',
    ]);
    expect(roots.every((node) => node.type == 'object'), isTrue);

    final id = at(roots, 'User.id');
    expect(id.type, 'uuid');
    expect(id.properties, {'required': true});
    expect(id.value, 'uuid!');
    expect(at(roots, 'User.age').properties, isEmpty);
    expect(at(roots, 'User.status').type, 'string');
    expect(at(roots, 'User.status').properties, {'enum': []});
    expect(at(roots, 'User.email').type, 'email');
    expect(at(roots, 'User.email').properties, {'nullable': true});
    expect(at(roots, 'User.tags').type, 'string');
    expect(at(roots, 'User.tags').properties, {'array': true});

    final address = at(roots, 'User.address');
    expect(address.type, 'object');
    expect(address.children.map((node) => node.name), [
      'street',
      'city',
      'zipCode',
    ]);
    expect(at(roots, 'User.address.zipCode').properties, {'required': true});

    final employees = at(roots, 'Company.employees');
    expect(employees.type, 'User');
    expect(employees.properties, {'array': true});

    final content = at(roots, 'Page.content');
    expect(content.type, 'union');
    expect(content.properties, {'array': true});
    expect(content.children.map((node) => (node.name, node.type)), [
      ('[0]', 'TextBlock'),
      ('[1]', 'ImageBlock'),
      ('[2]', 'VideoBlock'),
    ]);

    final content2 = at(roots, 'Page.content2');
    expect(content2.type, 'oneOf');
    expect(content2.children.map((node) => node.type), [
      'TextBlock',
      'ImageBlock',
      'VideoBlock',
    ]);

    expect(at(roots, 'Webhook.headers').type, 'json');
    expect(at(roots, 'Response.data').type, 'union');
    expect(at(roots, 'Error.code').type, 'int');
    expect(at(roots, 'Error.code').properties, {'enum': []});
    expect(at(roots, 'Error.level').type, 'enum');
    expect(at(roots, 'Error.level').properties, {
      'enum': ['low', 'high', 3],
    });

    final json = content.toJson();
    expect(json['properties'], {'array': true});
    expect(json['propertiesText'], '{array: true}');
    expect(json['children'], hasLength(3));
    expect(json['description'], 'TextBlock | ImageBlock | VideoBlock');
  });

  test('supports value suffixes, nullable unions and inline compositions', () {
    final roots = parser.parse('''
A:
  ids: uuid[]!
  typed: string(red, "blue, dark")
  scores: number(1, 2.5)
  either: A | B | null
  mixed:
    allOf:
      - A
      - extra: string
  loose:
    anyOf: A | B
  tag!: string
  list[]!:
    name: string
B: json
''');
    expect(at(roots, 'A.ids').properties, {'array': true, 'required': true});
    expect(at(roots, 'A.typed').properties, {
      'enum': ['red', 'blue, dark'],
    });
    expect(at(roots, 'A.scores').properties, {
      'enum': [1, 2.5],
    });
    final either = at(roots, 'A.either');
    expect(either.type, 'union');
    expect(either.properties, {'nullable': true});
    expect(either.children.map((node) => node.type), ['A', 'B']);
    expect(at(roots, 'A.mixed[1]').type, 'object');
    expect(at(roots, 'A.mixed[1].extra').type, 'string');
    expect(at(roots, 'A.loose').type, 'anyOf');
    expect(at(roots, 'A.loose').children, hasLength(2));
    expect(at(roots, 'A.tag').properties, {'required': true});
    expect(at(roots, 'A.list').type, 'object');
    expect(at(roots, 'A.list').properties, {'array': true, 'required': true});
    expect(at(roots, 'B').type, 'json');
    expect(parser.parse(''), isEmpty);
  });

  test('parses conditional fields and exposes their condition in the tree', () {
    final roots = parser.parse('''
Payment:
  paymentType: enum(card, transfer)!
  when paymentType == card:
    cardNumber: string!
    expiryDate: string!
  when paymentType == transfer:
    iban: string!
''');
    final payment = roots.single;
    expect(payment.children.first.properties, {
      'enum': ['card', 'transfer'],
      'required': true,
    });
    final when = payment.children[1];
    expect(when.name, 'when paymentType == card');
    expect(when.type, 'when');
    expect(when.properties, {
      'condition': {'field': 'paymentType', 'operator': '==', 'value': 'card'},
    });
    expect(when.children.map((node) => node.name), [
      'cardNumber',
      'expiryDate',
    ]);
    expect(
      when.children.every((node) => node.properties['required'] == true),
      isTrue,
    );
    expect(when.children.every((node) => identical(node.parent, when)), isTrue);
    expect(when.toJson()['children'], hasLength(2));
    expect(when.toJson()['propertiesText'], contains('value: card'));
    expect(payment.children[2].properties['condition'], {
      'field': 'paymentType',
      'operator': '==',
      'value': 'transfer',
    });
  });

  test(
    'conditions accept scalar literals, forward fields and nested objects',
    () {
      final roots = parser.parse('''
Payment:
  details:
    when enabled == true:
      note: string
    when count == 2:
      note: string
    when label == "credit card":
      note: string
    when label == null:
      note: string
    enabled: bool
    count: int
    label: string | null
''');
      final conditions = roots.single.children.single.children.take(4);
      expect(
        conditions.map(
          (node) => (node.properties['condition'] as Map)['value'],
        ),
        [true, 2, 'credit card', null],
      );
    },
  );

  test('patch updates conditions while keeping IDs and UI properties', () {
    final model = parser.model('Payment', '''
Payment:
  paymentType: enum(card, transfer)!
  when paymentType == card:
    cardNumber: string!
    expiryDate: string!
''');
    final when = model.nodes.single.children.last;
    final cardNumber = when.children.first;
    when.properties['description'] = 'Payment details';
    parser.patch(model, '''
Payment:
  paymentType: enum(card, transfer)!
  when paymentType == transfer:
    cardNumber: string
    expiryDate: string!
''');
    final patched = model.nodes.single.children.last;
    expect(patched.id, when.id);
    expect(patched.children.first.id, cardNumber.id);
    expect(patched.children.first.properties, isEmpty);
    expect(patched.properties['description'], 'Payment details');
    expect(patched.properties['condition'], {
      'field': 'paymentType',
      'operator': '==',
      'value': 'transfer',
    });
    expect(
      () =>
          parser.patch(model, 'Payment:\n  when missing == card:\n    x: int'),
      throwsFormatException,
    );
    expect(identical(model.nodes.single.children.last, patched), isTrue);
  });

  test('rejects invalid conditional blocks with their location', () {
    for (final entry in {
      'when paymentType = card:\n    x: string': 'condition attendue',
      'when paymentType != card:\n    x: string': 'condition attendue',
      'when paymentType == :\n    x: string': 'condition attendue',
      'when missing == card:\n    x: string': 'champ de condition inconnu',
      'when paymentType == card: string': 'objet de champs non vide',
      'when paymentType == card: {}': 'objet de champs non vide',
      'when paymentType == [card]:\n    x: string': 'valeur scalaire',
      'when paymentType == card == transfer:\n    x: string': 'valeur scalaire',
    }.entries) {
      expect(
        () => parser.parse('Payment:\n  paymentType: string\n  ${entry.key}'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('Payment.when'), contains(entry.value)),
          ),
        ),
      );
    }
    expect(() => parser.parse('A: when'), throwsFormatException);
    expect(() => parser.parse('when: {}'), throwsFormatException);
  });

  test('reports invalid schemas with their location', () {
    void fails(String yaml, String message) => expect(
      () => parser.parse(yaml),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains(message),
        ),
      ),
    );

    fails('A:\n  b: Unknown', 'A.b : type inconnu « Unknown »');
    fails('A:\n  c[]: A | Missing', 'A.c[1] : type inconnu « Missing »');
    fails('A:\n  bad key: string', 'nom de champ invalide');
    fails('A:\n  b: [string]', 'A.b : liste inattendue');
    fails('A:\n  b:\n    oneOf: [A]\n    other: string', 'seule clé');
    fails('A:\n  b: int(1, x)', 'n’est pas un nombre');
    fails('A:\n  b: string |', 'expression de type vide');
    fails('string: int', 'nom de définition réservé');
    fails('- A', 'objet YAML de définitions');
    fails('A: [1', 'line');
  });

  test('patch keeps IDs and properties entered in the UI', () {
    final model = parser.model('Schema', '''
User:
  id: uuid!
  status: string(enum)
  email: email
''');
    final user = model.nodes.single;
    final status = at(model.nodes, 'User.status');
    final email = at(model.nodes, 'User.email');
    status.properties['enum'] = ['active', 'blocked'];
    email.properties['description'] = 'Adresse de contact';
    email.properties['required'] = true;

    parser.patch(model, '''
User:
  id: uuid!
  state: string(enum)
  email: email | null
  age: int
''');
    expect(model.nodes.single.id, user.id);

    parser.patch(model, '''
Account:
  id: uuid!
  state: string(enum)
  email: email | null
  age: int
''');

    final account = model.nodes.single;
    expect(account.id, user.id);
    expect(account.name, 'Account');
    final state = at(model.nodes, 'Account.state');
    expect(state.id, status.id);
    expect(state.properties, {
      'enum': ['active', 'blocked'],
    });
    final newEmail = at(model.nodes, 'Account.email');
    expect(newEmail.id, email.id);
    // DSL properties are recomputed, UI properties are kept.
    expect(newEmail.properties, {
      'description': 'Adresse de contact',
      'nullable': true,
    });
    expect(at(model.nodes, 'Account.age').properties, isEmpty);

    parser.patch(model, '''
Account:
  id: uuid!
  state: int(enum)
''');
    expect(at(model.nodes, 'Account.state').properties, {'enum': []});

    expect(
      () => parser.patch(model, 'Account:\n  x: Nope'),
      throwsFormatException,
    );
    expect(model.nodes.single.id, user.id);
  });
}
