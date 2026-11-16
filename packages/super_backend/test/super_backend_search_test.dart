import 'package:super_backend/super_backend.dart';
import 'package:test/test.dart';

void _runSearchTests(String label, CollectionStore Function() factory) {
  group('Search SCRUD ($label)', () {
    late SuperBackend backend;
    late CollectionApi users;

    setUp(() async {
      backend = SuperBackend(store: factory());
      await backend.init();
      users = backend.collection('users');

      await users.create({
        'name': 'Alice',
        'age': 30,
        'active': true,
        'role': 'admin',
        'notes': '100% fiable_top',
        'address': {'city': 'Lyon', 'country': 'FR'},
      }, id: 'u1');
      await users.create({
        'name': 'Bob',
        'age': 25,
        'active': false,
        'role': 'viewer',
        'notes': null,
        'address': {'city': 'Paris', 'country': 'FR'},
      }, id: 'u2');
      await users.create({
        'name': 'Charlie',
        'age': 40,
        'active': true,
        'role': 'editor',
        'address': {'city': 'Bordeaux', 'country': 'FR'},
      }, id: 'u3');
      await users.create({
        'name': 'Diane',
        'age': 35,
        'active': true,
        'role': 'editor',
        'address': {'city': 'Nantes', 'country': 'FR'},
      }, id: 'u4');
      await users.create({
        'name': 'Éric',
        'age': 28,
        'active': false,
        'role': 'viewer',
        'address': {'city': 'Lille', 'country': 'FR'},
      }, id: 'u5');
    });

    tearDown(() async {
      await backend.close();
    });

    test(
      'pagination mode page (page 1, 2, 3) et enveloppe Datasource',
      () async {
        final p1 = await users.search(
          parameters: {'page': 1, 'size': 2, 'sort': 'age'},
        );
        expect(p1.total, 5);
        expect(p1.page, 1);
        expect(p1.pageSize, 2);
        expect(p1.pageCount, 3);
        expect(p1.hasPrevious, isFalse);
        expect(p1.hasNext, isTrue);
        expect(p1.nextCursor, isNotNull);
        expect(p1.items.map((e) => e['name']).toList(), ['Bob', 'Éric']);

        final p2 = await users.search(
          parameters: {'page': 2, 'size': 2, 'sort': 'age'},
        );
        expect(p2.hasPrevious, isTrue);
        expect(p2.hasNext, isTrue);
        expect(p2.items.map((e) => e['name']).toList(), ['Alice', 'Diane']);

        final p3 = await users.search(
          parameters: {'page': 3, 'size': 2, 'sort': 'age'},
        );
        expect(p3.hasPrevious, isTrue);
        expect(p3.hasNext, isFalse);
        expect(p3.nextCursor, isNull);
        expect(p3.items.map((e) => e['name']).toList(), ['Charlie']);

        final envelope = p1.toJson();
        expect(envelope['total'], 5);
        expect((envelope['items'] as List).length, 2);
        expect(envelope['nextCursor'], p1.nextCursor);
      },
    );

    test('pagination mode offset et cursor', () async {
      final byOffset = await users.search(
        parameters: {'offset': 1, 'limit': 2, 'sort': '-age'},
      );
      expect(byOffset.offset, 1);
      expect(byOffset.hasPrevious, isTrue);
      expect(byOffset.hasNext, isTrue);
      expect(byOffset.items.map((e) => e['name']).toList(), ['Diane', 'Alice']);

      final c1 = await users.search(
        request: ScrudSearchRequest(
          pagination: const ScrudPagination(
            mode: ScrudPaginationMode.cursor,
            pageSize: 2,
          ),
          sort: const ScrudSortOrder('address.city', ScrudSortDirection.asc),
        ),
      );
      expect(c1.items.map((e) => e['name']).toList(), ['Charlie', 'Éric']);
      expect(c1.nextCursor, isNotNull);

      final c2 = await users.search(
        parameters: {
          'cursor': c1.nextCursor,
          'limit': 2,
          'sort': 'address.city',
        },
      );
      expect(c2.items.map((e) => e['name']).toList(), ['Alice', 'Diane']);
      expect(c2.nextCursor, isNotNull);

      final c3 = await users.search(
        parameters: {
          'cursor': c2.nextCursor,
          'limit': 2,
          'sort': 'address.city',
        },
      );
      expect(c3.items.map((e) => e['name']).toList(), ['Bob']);
      expect(c3.hasNext, isFalse);
      expect(c3.nextCursor, isNull);
    });

    test(
      'filtres opérateurs (eq, ne, contains, startsWith, range, in, null)',
      () async {
        final activeAdmins = await users.search(
          parameters: {'active': true, 'role': 'admin'},
        );
        expect(activeAdmins.total, 1);
        expect(activeAdmins.items.single['name'], 'Alice');

        final older = await users.search(
          parameters: {'age__gte': 35, 'sort': 'age'},
        );
        expect(older.items.map((e) => e['name']).toList(), [
          'Diane',
          'Charlie',
        ]);

        final youngerThan30 = await users.search(
          parameters: {'age__lt': 30, 'sort': 'age'},
        );
        expect(youngerThan30.items.map((e) => e['name']).toList(), [
          'Bob',
          'Éric',
        ]);

        final likePercent = await users.search(
          parameters: {'notes__contains': '100% fiable_'},
        );
        expect(likePercent.total, 1);
        expect(likePercent.items.single['name'], 'Alice');

        final byCityPrefix = await users.search(
          parameters: {'address.city__startsWith': 'ly'},
        );
        expect(byCityPrefix.items.map((e) => e['name']).toList(), ['Alice']);

        final byInList = await users.search(
          parameters: {
            'role__in': ['admin', 'editor'],
            'sort': 'name',
          },
        );
        expect(byInList.items.map((e) => e['name']).toList(), [
          'Alice',
          'Charlie',
          'Diane',
        ]);

        final withNotes = await users.search(
          request: ScrudSearchRequest(
            filters: const [
              ScrudFilter(
                field: 'notes',
                operator: ScrudFilterOperator.isNotNull,
              ),
            ],
          ),
        );
        expect(withNotes.items.map((e) => e['name']).toList(), ['Alice']);

        final withoutNotes = await users.search(
          request: ScrudSearchRequest(
            filters: const [
              ScrudFilter(field: 'notes', operator: ScrudFilterOperator.isNull),
            ],
            sort: const ScrudSortOrder('name'),
          ),
        );
        expect(withoutNotes.items.map((e) => e['name']).toList(), [
          'Bob',
          'Charlie',
          'Diane',
          'Éric',
        ]);
      },
    );

    test(
      'recherche texte libre q sur les valeurs imbriquées et booléens',
      () async {
        final cityMatch = await users.search(parameters: {'q': 'bordeaux'});
        expect(cityMatch.total, 1);
        expect(cityMatch.items.single['name'], 'Charlie');

        final inactive = await users.search(
          parameters: {'q': 'false', 'sort': 'name'},
        );
        expect(inactive.items.map((e) => e['name']).toList(), ['Bob', 'Éric']);
      },
    );
  });
}

void main() {
  _runSearchTests('Memory', MemoryCollectionStore.new);
  _runSearchTests('SQLite :memory:', SqliteCollectionStore.inMemory);
}
