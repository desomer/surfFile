import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  group('ComponentUsage', () {
    test('requires an ARB translation key only for explanations', () {
      expect(
        () => const ComponentUsage(kind: ComponentUsageKind.explanation)
            .validate(),
        throwsFormatException,
      );
      for (final key in ['Home', 'home title', '1title', 'titré']) {
        expect(
          () => ComponentUsage.explanation(key).validate(),
          throwsFormatException,
          reason: key,
        );
      }
      expect(
        () => const ComponentUsage(
          kind: ComponentUsageKind.dynamicData,
          translationKey: 'homeTitle',
        ).validate(),
        throwsFormatException,
      );
      const ComponentUsage.explanation('home_title2').validate();
      const ComponentUsage(kind: ComponentUsageKind.staticData).validate();
    });

    test('round-trips through JSON and rejects invalid documents', () {
      const usage = ComponentUsage.explanation('homeTitle');
      expect(usage.toJson(), {
        'kind': 'explanation',
        'translationKey': 'homeTitle',
      });
      expect(ComponentUsage.fromJson(usage.toJson()), usage);
      expect(
        ComponentUsage.fromJson({'kind': 'feedback'}),
        const ComponentUsage(kind: ComponentUsageKind.feedback),
      );
      for (final json in [
        null,
        {'kind': 'unknown'},
        {'kind': 'action', 'extra': 1},
        {'kind': 'explanation'},
        {'kind': 'explanation', 'translationKey': 3},
      ]) {
        expect(
          () => ComponentUsage.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });

    test('suggests lowerCamelCase translation keys from labels', () {
      expect(ComponentUsage.suggestTranslationKey('Titre principal'),
          'titrePrincipal');
      expect(ComponentUsage.suggestTranslationKey('  Élément créé !'),
          'elementCree');
      expect(ComponentUsage.suggestTranslationKey('URL du site'), 'urlDuSite');
      expect(ComponentUsage.suggestTranslationKey('2 colonnes'),
          'text2Colonnes');
      expect(ComponentUsage.suggestTranslationKey('monTitre'), 'monTitre');
      expect(ComponentUsage.suggestTranslationKey(' - '), '');
      for (final label in ['Titre principal', 'Élément créé', '2 colonnes']) {
        expect(
          ComponentUsage.translationKeyError(
            ComponentUsage.suggestTranslationKey(label),
          ),
          isNull,
        );
      }
    });
  });

  group('Appearance.usages', () {
    final appearance = Appearance(
      components: {
        'title': const SuperValueConfig(initialText: 'Titre'),
        'price': const SuperValueConfig(initialText: '0'),
      },
    )
        .withUsage('title', const ComponentUsage.explanation('homeTitle'))
        .withUsage(
          'price',
          const ComponentUsage(kind: ComponentUsageKind.dynamicData),
        );

    test('withUsage sets, keeps identity when unchanged and removes', () {
      expect(appearance.usageFor('title')?.translationKey, 'homeTitle');
      expect(
        appearance.withUsage(
          'price',
          const ComponentUsage(kind: ComponentUsageKind.dynamicData),
        ),
        same(appearance),
      );
      expect(appearance.withUsage('price', null).usages.keys, ['title']);
      expect(
        () => appearance.withUsage(
          'price',
          const ComponentUsage(kind: ComponentUsageKind.explanation),
        ),
        throwsFormatException,
      );
      expect(appearance.resetLayouts().usages, isEmpty);
    });

    test('codec persists usages and stays compatible without them', () {
      const codec = AppearanceCodec();
      final decoded = codec.decode(codec.encode(appearance));
      expect(decoded.usages, appearance.usages);
      expect(codec.toCompactJson(appearance)['usages'], {
        'title': {'kind': 'explanation', 'translationKey': 'homeTitle'},
        'price': {'kind': 'dynamicData'},
      });
      expect(codec.toCompactJson(Appearance()).containsKey('usages'), isFalse);
      final legacy = codec.toJson(Appearance())..remove('usages');
      expect(codec.fromJson(legacy).usages, isEmpty);
      expect(
        () => codec.fromJson({
          ...codec.toJson(Appearance()),
          'usages': {
            'title': {'kind': 'explanation'},
          },
        }),
        throwsFormatException,
      );
      const defaults = DefaultAppearanceCodec();
      expect(
        defaults.decode(defaults.encode(DefaultAppearance(
          usages: appearance.usages,
        ))).usages,
        appearance.usages,
      );
    });

    test('patch merges by ID, deletes with null and drops removed '
        'components', () {
      const codec = AppearanceCodec();
      final patched = codec.patchFromJson(appearance, {
        'usages': {
          'price': null,
          'subtitle': {'kind': 'staticData'},
        },
      });
      expect(patched.usages, {
        'title': const ComponentUsage.explanation('homeTitle'),
        'subtitle': const ComponentUsage(kind: ComponentUsageKind.staticData),
      });
      final removed = codec.patchFromJson(appearance, {
        'components': {'title': null},
      });
      expect(removed.usages.keys, ['price']);
      expect(
        () => codec.patchFromJson(appearance, {
          'usages': {
            'price': {'kind': 'nope'},
          },
        }),
        throwsFormatException,
      );
    });

    test('transfers with layouts and is exposed to the AI prompt', () {
      final layouts = AppearanceTransfer.export(appearance, {
        TransferGroup.layouts,
      });
      expect(
        AppearanceTransfer.import(Appearance(), layouts, {
          TransferGroup.layouts,
        }).usages,
        appearance.usages,
      );
      final styles = AppearanceTransfer.export(appearance, {
        TransferGroup.styles,
      });
      expect(styles, isNot(contains('usages')));
      expect(
        (jsonDecode(AppearanceTransfer.exportCompactAi(appearance))
            as Map<String, Object?>)['usages'],
        {
          'title': {'kind': 'explanation', 'translationKey': 'homeTitle'},
          'price': {'kind': 'dynamicData'},
        },
      );
      final vibe = AppearanceTransfer.applyVibe(
        appearance,
        '{"components": {"price": {"initialText": "1"}}}',
      );
      expect(vibe.usages, appearance.usages);
    });
  });

  group('AI usage proposals', () {
    const price = JsonTextBinding(path: 'product.price');
    final current = Appearance(
      components: {
        'title': const SuperValueConfig(initialText: 'Titre'),
        'hint': const SuperValueConfig(initialText: 'Aide'),
        'subtitle': const SuperValueConfig(initialText: 'Sous-titre'),
        'price': const SuperValueConfig(binding: price),
        'status': SuperValueConfig(
          states: ValueConfigStates(
            hover: ValueConfigOverride(
              config: const SuperValueConfig(binding: price),
              properties: {ValueStateProperty.binding},
            ),
          ),
        ),
        'country': const SuperValueConfig(
          kind: SuperValueKind.choice,
          choice: SuperChoiceConfig(
            optionsBinding: JsonTextBinding(path: 'countries'),
          ),
        ),
        'rows': const SuperListViewConfig(
          binding: JsonTextBinding(path: 'clients'),
        ),
        'save': const SuperActionConfig(
          propertyBindings: {
            SuperActionProperty.label: JsonTextBinding(path: 'labels.save'),
          },
        ),
      },
    )
        .withUsage('title', const ComponentUsage.explanation('homeTitle'))
        .withUsage(
          'price',
          const ComponentUsage(kind: ComponentUsageKind.dynamicData),
        );

    test('apply only to components without binding', () {
      final next = AppearanceTransfer.applyVibe(
        current,
        jsonEncode({
          'components': {
            'subtitle': {'binding': 'product.subtitle'},
          },
          'usages': {
            'title': {'kind': 'explanation', 'translationKey': 'pageTitle'},
            'hint': {'kind': 'explanation', 'translationKey': 'helpHint'},
            'price': {'kind': 'staticData'},
            'status': {'kind': 'feedback'},
            'country': {'kind': 'userInput'},
            'rows': {'kind': 'dynamicData'},
            'save': {'kind': 'action'},
            'subtitle': {'kind': 'staticData'},
          },
        }),
      );
      expect(next.usages, {
        'title': const ComponentUsage.explanation('pageTitle'),
        'hint': const ComponentUsage.explanation('helpHint'),
        'price': const ComponentUsage(kind: ComponentUsageKind.dynamicData),
      });
      expect(
        (next.components['subtitle']! as SuperValueConfig).binding?.path,
        'product.subtitle',
      );
    });

    test('keep a bound usage unless its component is removed', () {
      final kept = AppearanceTransfer.applyVibe(
        current,
        '{"usages": {"price": null, "title": null}}',
      );
      expect(kept.usages.keys, ['price']);
      final removed = AppearanceTransfer.applyVibe(
        current,
        '{"components": {"price": null}}',
      );
      expect(removed.usages.keys, ['title']);
    });

    test('scoped export and patch filter keep only usages of the scope', () {
      final base = AppearanceTransfer.applyVibe(
        Appearance(),
        jsonEncode({
          'components': {
            'outerLayout': {
              'type': 'layout',
              'west': true,
              'placements': {
                'west': [
                  {'id': 'global-nav', 'type': 'registry:Value'},
                ],
              },
            },
            'mainLayout': {
              'type': 'layout',
              'placements': {
                'center': [
                  {'id': 'scoped-title', 'type': 'registry:Value'},
                ],
              },
            },
            'global-nav': {'type': 'value', 'text': 'Navigation'},
            'scoped-title': {'type': 'value', 'text': 'Titre'},
          },
          'usages': {
            'global-nav': {'kind': 'staticData'},
            'scoped-title': {
              'kind': 'explanation',
              'translationKey': 'pageTitle',
            },
          },
        }),
      );
      const scope = VibeChatScope(componentId: 'scoped-title', label: 'Titre');
      expect(
        (jsonDecode(VibeChatDialog.exportScopedAi(base, scope))
            as Map<String, Object?>)['usages'],
        {
          'scoped-title': {'kind': 'explanation', 'translationKey': 'pageTitle'},
        },
      );
      expect(
        VibeChatDialog.filterPatchToScope(base, {
          'usages': {
            'scoped-title': {'kind': 'staticData'},
            'global-nav': {'kind': 'dynamicData'},
          },
        }, scope),
        {
          'usages': {
            'scoped-title': {'kind': 'staticData'},
          },
        },
      );
    });
  });
}
