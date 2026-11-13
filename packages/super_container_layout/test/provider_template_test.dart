import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/models/providers/provider_template.dart';

void main() {
  const context = ProviderTemplateContext(
    filter: {
      'q': 'café & thé',
      'blank': '  ',
      'page': {'index': 2},
      'tags': ['a', 'b', null],
      'flags': [true, 3],
      'nested': [
        {'x': 1},
      ],
      'active': true,
    },
  );

  String? env(String name) => name == 'PROVIDER_TOKEN' ? 's3cret' : null;

  group('ProviderTemplate.parse', () {
    test('collects filter and env references', () {
      final template = ProviderTemplate.parse(
        'https://api.test/{{ page.index }}?t={{env.PROVIDER_TOKEN}}',
      );
      expect(template.references.map((reference) => reference.label), [
        'page.index',
        'env.PROVIDER_TOKEN',
      ]);
      expect(template.references.first.filterKey, 'page');
      expect(template.references.last.filterKey, '');
    });

    test('rejects unclosed, [?], calculated and invalid env references', () {
      for (final source in [
        'abc {{q',
        '{{items[?].name}}',
        '{{@total}}',
        '{{env.1BAD}}',
        '{{[0]}}',
      ]) {
        expect(
          () => ProviderTemplate.parse(source),
          throwsFormatException,
          reason: source,
        );
      }
    });
  });

  group('ProviderTemplate.render', () {
    test('inserts scalars and joins lists of scalars', () {
      expect(
        ProviderTemplate.parse('{{q}}|{{page.index}}|{{active}}')
            .render(context),
        'café & thé|2|true',
      );
      expect(ProviderTemplate.parse('{{tags}}').render(context), 'a,b');
      expect(ProviderTemplate.parse('{{flags}}').render(context), 'true,3');
    });

    test('encodes only inserted values', () {
      expect(
        ProviderTemplate.parse('/s/{{q}}?x=1').render(context, encode: true),
        '/s/caf%C3%A9%20%26%20th%C3%A9?x=1',
      );
    });

    test('omits blank or missing values unless strict', () {
      expect(ProviderTemplate.parse('a{{blank}}').render(context), isNull);
      expect(ProviderTemplate.parse('a{{missing}}').render(context), isNull);
      expect(
        () =>
            ProviderTemplate.parse('a{{missing}}')
                .render(context, strict: true),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('missing'),
          ),
        ),
      );
    });

    test('a missing env variable is always an error', () {
      const withEnv = ProviderTemplateContext(filter: {});
      expect(
        () => ProviderTemplate.parse('{{env.PROVIDER_TOKEN}}').render(withEnv),
        throwsFormatException,
      );
      expect(
        ProviderTemplate.parse('Bearer {{env.PROVIDER_TOKEN}}')
            .render(ProviderTemplateContext(filter: const {}, env: env)),
        'Bearer s3cret',
      );
    });

    test('refuses objects and lists of objects', () {
      expect(
        () => ProviderTemplate.parse('{{page}}').render(context),
        throwsFormatException,
      );
      expect(
        () => ProviderTemplate.parse('{{nested}}').render(context),
        throwsFormatException,
      );
    });
  });

  group('JSON body', () {
    test('a lone reference keeps its type and missing entries are omitted', () {
      final body = {
        'query': '{{q}}',
        'page': '{{page}}',
        'tags': '{{tags}}',
        'label': 'Page {{page.index}}',
        'skip': '{{missing}}',
        'list': ['{{active}}', '{{blank}}', 4],
        'fixed': null,
      };
      expect(providerBodyReferences(body).map((ref) => ref.key).toSet(), {
        'q',
        'page',
        'tags',
        'page.index',
        'missing',
        'active',
        'blank',
      });
      expect(renderProviderBody(body, context), {
        'query': 'café & thé',
        'page': {'index': 2},
        'tags': ['a', 'b', null],
        'label': 'Page 2',
        'list': [true, 4],
        'fixed': null,
      });
      expect(renderProviderBody('{{missing}}', context), isNull);
    });

    test('rejects non JSON, too deep and too large templates', () {
      expect(() => providerBodyReferences({1: 'x'}), throwsFormatException);
      expect(() => providerBodyReferences(double.nan), throwsFormatException);
      expect(
        () => providerBodyReferences(DateTime(2020)),
        throwsFormatException,
      );
      Object? deep = 'x';
      for (var i = 0; i <= providerBodyMaxDepth; i++) {
        deep = [deep];
      }
      expect(() => providerBodyReferences(deep), throwsFormatException);
      expect(
        () => providerBodyReferences('x' * (providerBodyMaxBytes + 1)),
        throwsFormatException,
      );
    });
  });
}
