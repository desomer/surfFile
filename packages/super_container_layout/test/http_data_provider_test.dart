import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/providers/data_provider.dart';
import 'package:super_container_layout/models/providers/http_provider_config.dart';
import 'package:super_container_layout/services/providers/data_provider_http_transport.dart';
import 'package:super_container_layout/services/providers/http_data_provider.dart';

class _FakeTransport extends DataProviderHttpTransport {
  _FakeTransport(this.response);

  DataProviderHttpResponse response;
  final requests = <DataProviderHttpRequest>[];

  @override
  Future<DataProviderHttpResponse> send(DataProviderHttpRequest request) async {
    requests.add(request);
    return response;
  }
}

const _target = JsonTextBinding(repositoryId: 'results', path: 'rows');

HttpProviderConfig _config(
  HttpRequestTemplate request, {
  String? filter = 'filter',
  String? responsePath,
}) => HttpProviderConfig(
  id: 'clients',
  label: 'Clients',
  filterRepositoryId: filter,
  target: _target,
  request: request,
  responsePath: responsePath,
);

String? _env(String name) => name == 'PROVIDER_TOKEN' ? 's3cret' : null;

void main() {
  group('HttpProviderConfig', () {
    test('round-trips through JSON and compact JSON', () {
      final config = HttpProviderConfig(
        id: 'clients',
        label: 'Clients',
        filterRepositoryId: 'filter',
        target: _target,
        loading: const JsonTextBinding(repositoryId: 'filter', path: 'busy'),
        error: const JsonTextBinding(repositoryId: 'filter', path: 'error'),
        autoSearch: const ProviderAutoSearch(debounceMs: 300, onStart: true),
        request: HttpRequestTemplate(
          method: 'POST',
          url: 'https://api.test/clients',
          headers: {'Authorization': 'Bearer {{env.PROVIDER_TOKEN}}'},
          query: {'limit': '20'},
          body: {'q': '{{q}}'},
          autoParams: false,
          timeoutMs: 5000,
        ),
        responsePath: 'data.items',
      );
      final restored = HttpProviderConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())),
      );
      expect(restored.toJson(), config.toJson());
      expect(
        HttpProviderConfig.fromJson(
          jsonDecode(jsonEncode(config.toCompactJson())),
        ).toJson(),
        config.toJson(),
      );
    });

    test('rejects unknown keys and unsafe requests', () {
      final valid = _config(HttpRequestTemplate(url: 'https://api.test/x'));
      final json = valid.toJson()..['extra'] = true;
      expect(() => HttpProviderConfig.fromJson(json), throwsFormatException);

      for (final url in [
        'ftp://api.test/x',
        'https://{{host}}/x',
        'https://api.{{env.PROVIDER_TOKEN}}.test/x',
        'https://user:pw@api.test/x',
        'https://api.test/a b',
      ]) {
        expect(
          () => _config(HttpRequestTemplate(url: url)).validate(),
          throwsFormatException,
          reason: url,
        );
      }
      expect(
        () => _config(
          HttpRequestTemplate(url: 'https://api.test', body: {'a': 1}),
        ).validate(),
        throwsFormatException,
      );
      expect(
        () =>
            _config(HttpRequestTemplate(url: 'https://api.test', timeoutMs: 10))
                .validate(),
        throwsFormatException,
      );
    });

    test('filter references require a filter repository', () {
      expect(
        () => _config(
          HttpRequestTemplate(url: 'https://api.test/{{q}}'),
          filter: null,
        ).validate(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('repository de filtre'),
          ),
        ),
      );
      _config(
        HttpRequestTemplate(
          url: 'https://api.test',
          headers: {'X-Key': '{{env.PROVIDER_TOKEN}}'},
        ),
        filter: null,
      ).validate();
    });
  });

  group('HttpDataProvider', () {
    test('GET merges URL, automatic and explicit parameters', () async {
      final transport = _FakeTransport(
        const DataProviderHttpResponse(statusCode: 200, body: '[{"id": 1}]'),
      );
      final provider = HttpDataProvider(
        _config(
          HttpRequestTemplate(
            url: 'https://api.test/search/{{city}}?fixed=1',
            headers: {'Authorization': 'Bearer {{env.PROVIDER_TOKEN}}'},
            query: {'limit': '{{size}}', 'empty': '{{missing}}'},
          ),
        ),
        transport: transport,
        env: _env,
      );

      final rows = await provider.fetch({
        'city': 'Saint Malo',
        'size': 20,
        'q': 'dupont',
        'tags': ['a', 'b'],
        'blank': '',
        'object': {'x': 1},
        'fixed': 'ignored',
      });

      expect(rows, [
        {'id': 1},
      ]);
      final request = transport.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/search/Saint%20Malo');
      expect(request.uri.queryParametersAll, {
        'fixed': ['1'],
        'q': ['dupont'],
        'tags': ['a', 'b'],
        'limit': ['20'],
      });
      expect(request.headers, {
        'Authorization': 'Bearer s3cret',
        'Accept': 'application/json',
      });
      expect(request.body, isNull);
    });

    test('POST sends the typed body template or the parameters', () async {
      final transport = _FakeTransport(
        const DataProviderHttpResponse(statusCode: 200, body: '{"id": 1}'),
      );
      final templated = HttpDataProvider(
        _config(
          HttpRequestTemplate(
            method: 'POST',
            url: 'https://api.test/search',
            body: {'page': '{{page}}', 'q': '{{q}}', 'skip': '{{missing}}'},
          ),
        ),
        transport: transport,
      );
      expect(await templated.fetch({'page': 2, 'q': 'x'}), [
        {'id': 1},
      ]);
      expect(jsonDecode(transport.requests.last.body!), {'page': 2, 'q': 'x'});
      expect(
        transport.requests.last.headers['Content-Type'],
        'application/json; charset=utf-8',
      );

      final automatic = HttpDataProvider(
        _config(
          HttpRequestTemplate(method: 'POST', url: 'https://api.test/s/{{id}}'),
        ),
        transport: transport,
      );
      await automatic.fetch({'id': 7, 'q': 'y', 'tags': <Object?>[]});
      expect(transport.requests.last.uri.path, '/s/7');
      expect(jsonDecode(transport.requests.last.body!), {
        'q': 'y',
        'tags': <Object?>[],
      });
    });

    test(
      'extracts rows with responsePath and reports response errors',
      () async {
        final transport = _FakeTransport(
          const DataProviderHttpResponse(
            statusCode: 200,
            body: '\uFEFF{"data": {"items": [1, 2]}}',
          ),
        );
        HttpDataProvider provider(String? path) => HttpDataProvider(
          _config(
            HttpRequestTemplate(url: 'https://api.test/x'),
            responsePath: path,
          ),
          transport: transport,
        );

        expect(await provider('data.items').fetch(const {}), [1, 2]);
        await expectLater(
          provider('data.missing').fetch(const {}),
          throwsA(isA<DataProviderException>()),
        );

        Future<String> failure(int status, String body) async {
          transport.response = DataProviderHttpResponse(
            statusCode: status,
            body: body,
          );
          try {
            await provider(null).fetch(const {});
          } on DataProviderException catch (error) {
            return error.message;
          }
          fail('Une DataProviderException était attendue.');
        }

        expect(await failure(302, ''), 'Redirection non suivie (HTTP 302).');
        expect(await failure(500, ''), 'Erreur HTTP 500.');
        expect(
          await failure(404, '  Not\n found ${'x' * 300}'),
          allOf(startsWith('Erreur HTTP 404 : Not found xxx'), endsWith('…')),
        );
        expect(await failure(200, 'not json'), contains('JSON'));
        expect(await failure(200, '  '), contains('vide'));
        expect(await failure(200, '42'), contains('tableau ou un objet'));
        transport.response = const DataProviderHttpResponse(
          statusCode: 204,
          body: '',
        );
        expect(await provider(null).fetch(const {}), isEmpty);
      },
    );

    test('request errors never reveal the URL or the headers', () async {
      final transport = _FakeTransport(
        const DataProviderHttpResponse(statusCode: 200, body: '[]'),
      );
      final missingEnv = HttpDataProvider(
        _config(
          HttpRequestTemplate(
            url: 'https://api.test/x?key={{env.PROVIDER_TOKEN}}',
          ),
        ),
        transport: transport,
        env: (_) => null,
      );
      final blankUrl = HttpDataProvider(
        _config(HttpRequestTemplate(url: 'https://api.test/{{q}}')),
        transport: transport,
        env: _env,
      );
      for (final (provider, parameters) in [
        (missingEnv, const <String, Object?>{}),
        (blankUrl, const <String, Object?>{'q': ' '}),
      ]) {
        await expectLater(
          provider.fetch(parameters),
          throwsA(
            isA<DataProviderException>().having(
              (error) => error.message,
              'message',
              allOf(
                startsWith('Requête invalide'),
                isNot(contains('api.test')),
              ),
            ),
          ),
        );
      }
      expect(transport.requests, isEmpty);
    });

    test('only PROVIDER_ variables are resolved by default', () {
      expect(defaultProviderEnv('PATH'), isNull);
      expect(defaultProviderEnv('USERPROFILE'), isNull);
    });
  });

  group('DartIoDataProviderHttpTransport', () {
    late HttpServer server;
    late DartIoDataProviderHttpTransport transport;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      transport = DartIoDataProviderHttpTransport();
      server.listen((request) async {
        final response = request.response;
        try {
          switch (request.uri.path) {
            case '/redirect':
              response
                ..statusCode = HttpStatus.found
                ..headers.set(HttpHeaders.locationHeader, '/ok');
            case '/large':
              response.write('x' * 2048);
            case '/slow':
              await Future<void>.delayed(const Duration(seconds: 2));
              response.write('[]');
            default:
              final body = await utf8.decodeStream(request);
              response.write(
                jsonEncode({
                  'method': request.method,
                  'body': body,
                  'accept': request.headers.value(HttpHeaders.acceptHeader),
                }),
              );
          }
          await response.close();
        } on Object {
          // Client parti (délai dépassé) ou serveur fermé.
        }
      });
    });

    tearDown(() async {
      transport.close(force: true);
      await server.close(force: true);
    });

    Uri uri(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test('sends the request and returns the raw response', () async {
      final response = await transport.send(
        DataProviderHttpRequest(
          method: 'POST',
          uri: uri('/ok'),
          headers: const {'Accept': 'application/json'},
          body: '{"q":"é"}',
        ),
      );
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), {
        'method': 'POST',
        'body': '{"q":"é"}',
        'accept': 'application/json',
      });
    });

    test('does not follow redirects', () async {
      final response = await transport.send(
        DataProviderHttpRequest(method: 'GET', uri: uri('/redirect')),
      );
      expect(response.statusCode, HttpStatus.found);
    });

    test('bounds the response size and the duration', () async {
      await expectLater(
        transport.send(
          DataProviderHttpRequest(
            method: 'GET',
            uri: uri('/large'),
            maxResponseBytes: 1024,
          ),
        ),
        throwsA(
          isA<DataProviderException>().having(
            (error) => error.message,
            'message',
            contains('trop volumineuse'),
          ),
        ),
      );
      await expectLater(
        transport.send(
          DataProviderHttpRequest(
            method: 'GET',
            uri: uri('/slow?token=secret'),
            timeout: const Duration(milliseconds: 200),
          ),
        ),
        throwsA(
          isA<DataProviderException>().having(
            (error) => error.message,
            'message',
            allOf(contains('Délai'), isNot(contains('secret'))),
          ),
        ),
      );
    });

    test('reports connection failures without the full URL', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      await expectLater(
        transport.send(
          DataProviderHttpRequest(
            method: 'GET',
            uri: Uri.parse('http://127.0.0.1:$port/x?token=secret'),
          ),
        ),
        throwsA(
          isA<DataProviderException>().having(
            (error) => error.message,
            'message',
            allOf(contains('Connexion impossible'), isNot(contains('secret'))),
          ),
        ),
      );
    });
  });
}
