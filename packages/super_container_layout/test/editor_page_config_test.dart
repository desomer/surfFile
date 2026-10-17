import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/models/editor_page_config.dart';
import 'package:super_container_layout/services/appearance_store.dart';
import 'package:super_container_layout/services/appearance_transfer.dart';
import 'package:super_container_layout/services/default_appearance_codec.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/default_appearance.dart';

EditorPageCatalog sampleCatalog() => EditorPageCatalog(
  pages: [
    EditorPageConfig(id: 'second', name: 'Second page', path: '/second'),
    EditorPageConfig(
      id: 'first',
      name: 'First page',
      path: '/first/:item',
      defaultParameters: {'item': 'hello world'},
    ),
  ],
  homePageId: 'first',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'exact DefaultAppearance copyWith and codec prepare retain new page',
    () {
      final appearance = DefaultAppearance().copyWith(
        pageCatalog: EditorPageCatalog(
          pages: [EditorPageConfig(id: 'p', name: 'P', path: '/p')],
        ),
      );
      for (final codec in [
        const AppearanceCodec(),
        const DefaultAppearanceCodec(),
      ]) {
        final prepared = codec.prepare(appearance);
        expect(prepared, isA<DefaultAppearance>());
        expect(prepared.pageCatalog.pages.single.id, 'p');
        expect(prepared.pageCatalog.pages.single.name, 'P');
        expect(prepared.pageCatalog.pages.single.path, '/p');
        expect(prepared.copyWith().pageCatalog.pages.single.id, 'p');
        expect(
          prepared.withPageCatalog(appearance.pageCatalog).pageCatalog,
          same(appearance.pageCatalog),
        );
      }
    },
  );

  test('catalog snapshots collections and copies home explicitly', () {
    final parameters = {'item': 'one'};
    final page = EditorPageConfig(
      id: 'stable',
      name: 'Original',
      path: '/original/:item',
      defaultParameters: parameters,
    );
    final pages = [page];
    final catalog = EditorPageCatalog(pages: pages, homePageId: 'stable');
    parameters.clear();
    pages.clear();
    expect(page.defaultParameters, {'item': 'one'});
    expect(catalog.pages, [page]);
    expect(() => page.defaultParameters.clear(), throwsUnsupportedError);
    expect(() => catalog.pages.clear(), throwsUnsupportedError);
    final renamed = page.copyWith(name: 'Renamed', path: '/renamed/:item');
    expect(renamed.id, page.id);
    expect(renamed.defaultParameters, page.defaultParameters);
    expect(catalog.copyWith(pages: [renamed]).homePageId, 'stable');
    expect(catalog.copyWith(clearHomePage: true).homePageId, isNull);
    expect(EditorPageCatalog().pages, isEmpty);
    expect(const EditorPageCatalog.empty().homePageId, isNull);
  });

  test('catalog JSON round trip retains order, home and parameters', () {
    final catalog = sampleCatalog();
    final restored = EditorPageCatalog.fromJson(
      jsonDecode(jsonEncode(catalog.toJson())),
    );
    expect(restored.toJson(), catalog.toJson());
    expect(restored.pages.map((page) => page.id), ['second', 'first']);
    expect(restored.homePageId, 'first');
    expect(restored.pages.last.defaultParameters, {'item': 'hello world'});
    expect(
      EditorPageConfig.fromJson({
        'id': 'minimal',
        'name': 'Minimal',
        'path': '/',
      }).defaultParameters,
      isEmpty,
    );
  });

  test('constructors reject invalid identities, paths and home references', () {
    for (final fields in [
      ('', 'Name', '/valid'),
      ('  ', 'Name', '/valid'),
      ('id', '  ', '/valid'),
      ('id', 'Name', ''),
      ('id', 'Name', 'relative'),
    ]) {
      expect(
        () => EditorPageConfig(id: fields.$1, name: fields.$2, path: fields.$3),
        throwsArgumentError,
      );
    }
    final page = sampleCatalog().pages.first;
    expect(() => EditorPageCatalog(pages: [page, page]), throwsArgumentError);
    expect(() => EditorPageCatalog(homePageId: 'missing'), throwsArgumentError);
    expect(
      () => page.copyWith(defaultParameters: {' ': 'value'}),
      throwsArgumentError,
    );
    expect(() => sampleCatalog().copyWith(pages: []), throwsArgumentError);
  });

  test('strict JSON rejects malformed catalogs and parameters', () {
    final page = sampleCatalog().pages.first.toJson();
    for (final invalid in <Object?>[
      null,
      [],
      {},
      {'pages': null},
      {'pages': {}},
      {
        'pages': [page],
        'unexpected': true,
      },
      {
        'pages': [page],
        'homePageId': 1,
      },
      {
        'pages': [page],
        'homePageId': 'missing',
      },
      {
        'pages': [page, page],
      },
      {
        'pages': [null],
      },
    ]) {
      expect(
        () => EditorPageCatalog.fromJson(invalid),
        throwsFormatException,
        reason: '$invalid',
      );
    }
    for (final invalid in <Object?>[
      null,
      [],
      {...page, 'id': 1},
      {...page, 'name': ''},
      {...page, 'path': 'relative'},
      {...page, 'unexpected': true},
      {...page, 'defaultParameters': null},
      {...page, 'defaultParameters': []},
      {
        ...page,
        'defaultParameters': {'item': 1},
      },
      {
        ...page,
        'defaultParameters': {'item': null},
      },
      {
        ...page,
        'defaultParameters': {1: 'value'},
      },
      {
        ...page,
        'defaultParameters': {' ': 'value'},
      },
    ]) {
      expect(
        () => EditorPageConfig.fromJson(invalid),
        throwsFormatException,
        reason: '$invalid',
      );
    }
  });

  test(
    'generic and default codecs persist catalog and accept old documents',
    () async {
      for (final codec in [
        const AppearanceCodec(),
        const DefaultAppearanceCodec(),
      ]) {
        final appearance = codec.defaults.withPageCatalog(sampleCatalog());
        final store = AppearanceStore(codec: codec);
        await store.save(appearance);
        final restored = await store.load();
        expect(restored.runtimeType, appearance.runtimeType);
        expect(restored.pageCatalog.toJson(), sampleCatalog().toJson());
        final old = codec.toJson(appearance)..remove('pageCatalog');
        expect(codec.fromJson(old).pageCatalog.pages, isEmpty);
        expect(codec.fromJson(old).pageCatalog.homePageId, isNull);
        for (final invalid in [
          null,
          [],
          {},
          {'pages': false},
        ]) {
          expect(
            () => codec.fromJson({...old, 'pageCatalog': invalid}),
            throwsFormatException,
          );
        }
      }
    },
  );

  test('layout transfer includes catalog, style transfer does not', () {
    const codec = DefaultAppearanceCodec();
    final source = DefaultAppearance(
      cardHeight: 230,
      pageCatalog: sampleCatalog(),
      styles: {'source': const ContainerStyle(radius: 18)},
    );
    final target = DefaultAppearance(
      cardHeight: 190,
      styles: {'target': const ContainerStyle(radius: 9)},
    );
    final layouts = AppearanceTransfer.export(source, {
      TransferGroup.layouts,
    }, codec: codec);
    final styles = AppearanceTransfer.export(source, {
      TransferGroup.styles,
    }, codec: codec);
    expect((jsonDecode(layouts) as Map)['data'], contains('pageCatalog'));
    expect((jsonDecode(styles) as Map)['data'], isNot(contains('pageCatalog')));
    expect(AppearanceTransfer.groupsIn(layouts, codec: codec), {
      TransferGroup.layouts,
    });
    final imported = AppearanceTransfer.import(target, layouts, {
      TransferGroup.layouts,
    }, codec: codec);
    expect(imported, isA<DefaultAppearance>());
    expect(imported.pageCatalog.toJson(), source.pageCatalog.toJson());
    expect((imported as DefaultAppearance).cardHeight, 190);
    expect(imported.styles.keys, target.styles.keys);
    expect(imported.style('target').toJson(), target.style('target').toJson());
    final styleOnly = AppearanceTransfer.import(source, styles, {
      TransferGroup.styles,
    }, codec: codec);
    expect(styleOnly.pageCatalog, isNotNull);
    expect(styleOnly.pageCatalog.toJson(), source.pageCatalog.toJson());
  });

  test('malformed layout imports are rejected without mutating the target', () {
    final target = Appearance(pageCatalog: sampleCatalog());
    final before = AppearanceStore.encode(target);
    final document = jsonDecode(
      AppearanceTransfer.export(target, {TransferGroup.layouts}),
    ) as Map<String, dynamic>;
    (document['data'] as Map)['pageCatalog'] = {
      'pages': target.pageCatalog.toJson()['pages'],
      'homePageId': 'missing',
    };
    expect(
      () => AppearanceTransfer.import(target, jsonEncode(document), {
        TransferGroup.layouts,
      }),
      throwsFormatException,
    );
    expect(AppearanceStore.encode(target), before);
  });

  test('appearance copy helpers retain subtype and reset clears catalog', () {
    final catalog = sampleCatalog();
    final generic = Appearance(pageCatalog: catalog);
    expect(generic.copyWith().pageCatalog, same(catalog));
    expect(generic.withPageCatalog(catalog).pageCatalog, same(catalog));
    expect(generic.resetLayouts().pageCatalog.pages, isEmpty);
    final appearance = DefaultAppearance(cardHeight: 233, pageCatalog: catalog);
    final changed = appearance.withPageCatalog(
      catalog.copyWith(clearHomePage: true),
    );
    expect(changed.cardHeight, 233);
    expect(changed.pageCatalog.homePageId, isNull);
    expect(appearance.copyWith().pageCatalog, same(catalog));
    final reset = appearance.resetLayouts();
    expect(reset, isA<DefaultAppearance>());
    expect(reset.pageCatalog.pages, isEmpty);
    expect(reset.pageCatalog.homePageId, isNull);
    expect(reset.cardHeight, 233);
  });

  test(
    'validation prevents publishing or persisting invalid setter values',
    () async {
      final store = AppearanceStore();
      final errors = <Object>[];
      final controller = PersistentAppearanceController(
        store,
        errors.add,
        validateAppearance: (appearance) {
          if (appearance.pageCatalog.pages.isNotEmpty) {
            throw const FormatException('Routing conflict.');
          }
        },
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final initial = controller.value;
      expect(
        () => controller.value = Appearance(pageCatalog: sampleCatalog()),
        throwsFormatException,
      );
      await controller.saved;
      expect(controller.value, same(initial));
      expect(notifications, 0);
      expect(errors, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).containsKey(store.key),
        isFalse,
      );
      await store.save(Appearance(pageCatalog: sampleCatalog()));
      await expectLater(controller.restore(), throwsFormatException);
      expect(controller.value, same(initial));
      expect(notifications, 0);
      controller.value = Appearance();
      await controller.saved;
      expect(notifications, 1);
      expect((await store.load()).pageCatalog.pages, isEmpty);
    },
  );
}
