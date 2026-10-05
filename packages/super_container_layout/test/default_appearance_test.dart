import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('map updates retain reusable preferences and immutable collections', () {
    final appearance = DefaultAppearance(
      cardHeight: 200,
      spacing: 18,
      fontSize: 14,
      scrollFadeEnabled: false,
    );
    final updated = appearance
        .withStyle('panel', const ContainerStyle(radius: 18))
        .withLayout('page', const SuperLayoutConfig(north: false));
    expect(updated.cardHeight, 200);
    expect(updated.spacing, 18);
    expect(updated.fontSize, 14);
    expect(updated.scrollFadeEnabled, isFalse);
    expect(updated.style('panel').radius, 18);
    expect(updated.layout('page').north, isFalse);
    expect(updated.withStyle('panel', null).styles, isEmpty);
    expect(updated.resetLayouts().layouts, isEmpty);
    expect(updated.resetLayouts().cardHeight, 200);
    expect(() => updated.styles.clear(), throwsUnsupportedError);
    expect(() => updated.layouts.clear(), throwsUnsupportedError);
    expect(appearance.styles, isEmpty);
  });

  test('default codec persists all reusable fields and maps', () async {
    const codec = DefaultAppearanceCodec();
    final appearance = DefaultAppearance(
      cardHeight: 201,
      cardWidth: 240,
      rowHeight: 56,
      spacing: 0,
      fontSize: 15,
      iconSize: 38,
      scrollFadeEnabled: false,
      scrollFadeExtent: 0,
      styles: {'custom': const ContainerStyle(radius: 22)},
      layouts: {'custom': const SuperLayoutConfig(east: false)},
    );
    final store = AppearanceStore(codec: codec);
    await store.save(appearance);
    final restored = await store.load();
    expect(restored, isA<DefaultAppearance>());
    expect(codec.encode(restored), codec.encode(appearance));
    expect(codec.fromJson(codec.toJson(appearance)).cardWidth, 240);
  });

  test('codec rejects invalid fields and wrong model explicitly', () {
    const codec = DefaultAppearanceCodec();
    final json = codec.toJson(DefaultAppearance());
    for (final field in ['cardHeight', 'fontSize', 'rowHeight']) {
      expect(() => codec.fromJson({...json, field: -1}), throwsFormatException);
    }
    expect(
      () => codec.fromJson({...json, 'spacing': double.nan}),
      throwsFormatException,
    );
    expect(
      () => codec.fromJson({...json, 'scrollFadeEnabled': 'false'}),
      throwsFormatException,
    );
    expect(() => codec.toJson(Appearance()), throwsArgumentError);
  });
}
