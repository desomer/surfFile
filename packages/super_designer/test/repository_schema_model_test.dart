import 'package:flutter_test/flutter_test.dart';
import 'package:super_designer/repository_schema_model.dart';
import 'package:super_designer/yaml2jsonschemas_parser.dart';

void main() {
  test('restores IDs and editable fields when the YAML is patched', () {
    const source = '''
User:
  status: string(enum)
  email: email
''';
    const updatedSource = '''
User:
  status: string(enum)
  email: email
  age: int
''';
    final parser = Yaml2JsonSchemasParser();
    final original = parser.model('source', source);
    final root = original.nodes.single;
    final status = root.children.first;
    final savedRoot = root.toJson();
    final savedStatus =
        (savedRoot['children'] as List<Object?>).first as Map<String, Object?>;
    savedRoot['title'] = 'Utilisateur';
    savedRoot['isRequired'] = false;
    savedStatus['title'] = 'État';
    savedStatus['isSearchable'] = false;
    savedStatus['properties'] = {
      'enum': ['active', 'blocked'],
      'description': 'Valeurs autorisées',
    };
    final saved = <Object?>[savedRoot];

    final restored = RepositorySchemaModel(parser)..restore(saved);
    final first = restored.patch(source, saved);
    final firstRoot = first.single as Map<String, Object?>;
    final firstStatus =
        (firstRoot['children'] as List<Object?>).first as Map<String, Object?>;
    expect(firstRoot['id'], root.id);
    expect(firstRoot['title'], 'Utilisateur');
    expect(firstRoot['isRequired'], isFalse);
    expect(firstStatus['id'], status.id);
    expect(firstStatus['title'], 'État');
    expect(firstStatus['isSearchable'], isFalse);
    expect(firstStatus['properties'], {
      'enum': ['active', 'blocked'],
      'description': 'Valeurs autorisées',
    });

    firstStatus['title'] = 'Statut modifié';
    final updated = restored.patch(updatedSource, first);
    final updatedRoot = updated.single as Map<String, Object?>;
    final updatedChildren = updatedRoot['children'] as List<Object?>;
    final updatedStatus = updatedChildren.first as Map<String, Object?>;
    expect(updatedRoot['id'], root.id);
    expect(updatedStatus['id'], status.id);
    expect(updatedStatus['title'], 'Statut modifié');
    expect(updatedStatus['isSearchable'], isFalse);
    expect(updatedStatus['properties'], {
      'enum': ['active', 'blocked'],
      'description': 'Valeurs autorisées',
    });
    expect(updatedChildren, hasLength(3));
  });

  test('invalid YAML does not discard restored nodes or their metadata', () {
    const source = 'User:\n  name: string';
    final parser = Yaml2JsonSchemasParser();
    final original = parser.model('source', source);
    final savedRoot = original.nodes.single.toJson()..['title'] = 'Utilisateur';
    final saved = <Object?>[savedRoot];
    final restored = RepositorySchemaModel(parser)..restore(saved);

    expect(() => restored.patch('User: [', saved), throwsFormatException);
    final valid = restored.patch(source, saved).single as Map<String, Object?>;
    expect(valid['id'], original.nodes.single.id);
    expect(valid['title'], 'Utilisateur');
  });

  test('rejects malformed or duplicate persisted nodes', () {
    final model = RepositorySchemaModel(Yaml2JsonSchemasParser());
    expect(() => model.restore([{}]), throwsFormatException);
    expect(
      () => model.restore([
        {'id': 'same', 'name': 'First', 'type': 'string'},
        {'id': 'same', 'name': 'Second', 'type': 'string'},
      ]),
      throwsFormatException,
    );
    expect(
      () => model.restore([
        {
          'id': 'id',
          'name': 'First',
          'type': 'string',
          'children': 'not a list',
        },
      ]),
      throwsFormatException,
    );
  });
}
