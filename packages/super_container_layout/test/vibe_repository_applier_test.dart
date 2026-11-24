import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_scope_helpers.dart';

class _GuideJsEvaluator
    implements JsCalculatedEvaluator, JsRepositoryActionEvaluator {
  @override
  FutureOr<Object?> evaluate({
    required String code,
    required Object? scopeData,
    required Object? rootData,
    required CalculatedAttributeContext context,
  }) {
    if (code.contains('row.montantHt') && code.contains('row.tauxTva')) {
      final row = scopeData! as Map<String, Object?>;
      final ht = (row['montantHt'] as num?)?.toDouble() ?? 0;
      final tva = (row['tauxTva'] as num?)?.toDouble() ?? 0.2;
      return (ht * (1 + tva) * 100).roundToDouble() / 100;
    }
    return null;
  }

  @override
  FutureOr<List<JsRepositoryScriptWrite>> executeAction({
    required String code,
    required Object? rootData,
    required Map<String, Object?> eventData,
    required String repositoryId,
  }) {
    final writes = <JsRepositoryScriptWrite>[];
    final pattern = RegExp(
      r"ctx\.set\(\s*'([^']+)'\s*,\s*('[^']*'|true|false|-?\d+(?:\.\d+)?)\s*\)",
    );
    for (final match in pattern.allMatches(code)) {
      final path = match.group(1)!;
      final rawVal = match.group(2)!;
      final Object? val = rawVal.startsWith("'")
          ? rawVal.substring(1, rawVal.length - 1)
          : jsonDecode(rawVal);
      writes.add((path: path, value: val));
    }
    return writes;
  }

  @override
  void invalidateDocument([String? repositoryId]) {}

  @override
  void dispose() {}
}

({Directory dir, JsonRepositoryStore store}) _createTempStore([
  String prefix = 'vibe_repository_applier_test_',
]) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  final store = JsonRepositoryStore(dir);
  addTearDown(() async {
    store.dispose();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });
  return (dir: dir, store: store);
}

bool _containsKeyStartingWithAt(Object? node) {
  if (node is Map) {
    for (final entry in node.entries) {
      if (entry.key.toString().startsWith('@')) return true;
      if (_containsKeyStartingWithAt(entry.value)) return true;
    }
  } else if (node is List) {
    for (final item in node) {
      if (_containsKeyStartingWithAt(item)) return true;
    }
  }
  return false;
}

void main() {
  group('REPOSITORY_JSON_AI_GUIDE.md executable validation', () {
    test('documente les sections clés et exécute de bout en bout la recette finale ("repositories" + "vibe") sans erreur', () async {
      final guideFile = File('REPOSITORY_JSON_AI_GUIDE.md').existsSync()
          ? File('REPOSITORY_JSON_AI_GUIDE.md')
          : File('packages/super_container_layout/REPOSITORY_JSON_AI_GUIDE.md');
      expect(guideFile.existsSync(), isTrue);
      final content = guideFile.readAsStringSync();

      expect(content, contains('"repositories"'));
      expect(content, contains('@'));
      expect(content, contains('JsonAttributePath'));
      expect(content, contains('blank'));
      expect(content, contains('RepositoryImpl'));
      expect(content, contains('addCalculatedAttribute'));

      final jsonBlocks = RegExp(r'```json\s*([\s\S]*?)\s*```')
          .allMatches(content)
          .map((m) => m.group(1)!)
          .toList();
      expect(jsonBlocks, isNotEmpty);

      final recipeRaw = jsonBlocks.last;
      final decodedRecipe = jsonDecode(recipeRaw) as Map<String, dynamic>;
      expect(decodedRecipe.keys.toList(), ['message', 'repositories', 'vibe']);

      final (:store, dir: _) = _createTempStore('vibe_guide_recipe_');
      final tx = VibeRepositoryTurnTransaction(store);

      final rawRepositories =
          decodedRecipe['repositories'] as Map<String, dynamic>;
      final aliases = await tx.applyRepositoriesPatch(rawRepositories);

      final actualId = aliases['crm_clients'];
      expect(actualId, isNotNull);
      expect(actualId, matches(RegExp(r'^[0-9a-f]{32}$')));

      final rawVibe = decodedRecipe['vibe'] as Map<String, dynamic>;
      final rewrittenVibe = tx.rewriteVibePatchBindings(rawVibe);
      final updated = AppearanceTransfer.applyVibe(
        Appearance(),
        jsonEncode(rewrittenVibe),
      );

      // Vérifie la réécriture effective des bindings vers le vrai ID 32 hex
      expect(
        updated.valueComponent('search-clients').binding,
        JsonTextBinding(repositoryId: actualId, path: 'filters.recherche'),
      );
      expect(
        updated.listComponent('list-clients').binding,
        JsonTextBinding(repositoryId: actualId, path: 'clients'),
      );
      expect(
        updated.valueComponent('field-nom').binding,
        JsonTextBinding(repositoryId: actualId, path: 'clients[?].nom'),
      );
      final fieldStatut = updated.valueComponent('field-statut');
      expect(
        fieldStatut.binding,
        JsonTextBinding(repositoryId: actualId, path: 'clients[?].statut'),
      );
      expect(
        fieldStatut.choice.optionsBinding,
        JsonTextBinding(repositoryId: actualId, path: 'options.statuts'),
      );
      expect(
        updated.valueComponent('field-ca').binding,
        JsonTextBinding(repositoryId: actualId, path: 'clients[?].caAnnuel'),
      );
      expect(
        updated.valueComponent('field-auto').binding,
        JsonTextBinding(
          repositoryId: actualId,
          path: 'clients[?].facturationAuto',
        ),
      );

      // Les composants du template de liste conservent leur repositoryId hérité (null)
      expect(
        updated.valueComponent('row-nom').binding,
        const JsonTextBinding(path: 'clients[?].nom'),
      );
      expect(
        updated.indicatorComponent('row-statut').states?.binding,
        const JsonTextBinding(path: 'clients[?].statut'),
      );

      // Le behavior bindZoneSize réécrit est valide et pointe sur l'ID 32 hex réel
      final rawBehaviors =
          (rewrittenVibe['behaviors'] as Map)['mainLayout'] as List;
      expect(rawBehaviors, hasLength(1));
      final decodedBehavior = ComponentBehavior.fromJson(
        Map<String, dynamic>.from(rawBehaviors.single as Map),
      );
      final zoneAction = decodedBehavior.action as ZoneSizeBindingAction;
      expect(
        zoneAction.binding,
        JsonTextBinding(repositoryId: actualId, path: 'ui.westWidth'),
      );

      // Le store contient bien les lignes de la recette finale
      final storedClients = await store.readArray(actualId!, 'clients');
      final expectedClients =
          ((rawRepositories['crm_clients'] as Map)['data'] as Map)['clients']
              as List;
      expect(storedClients, hasLength(expectedClients.length));
      expect(storedClients, expectedClients);
    });
  });

  group('BEHAVIOR_JSON_AI_GUIDE.md executable validation', () {
    test('documente tous les événements, validateurs, 16 actions et CollectionViewTransform, et exécute la recette finale de bout en bout', () async {
      final guideFile = File('BEHAVIOR_JSON_AI_GUIDE.md').existsSync()
          ? File('BEHAVIOR_JSON_AI_GUIDE.md')
          : File('packages/super_container_layout/BEHAVIOR_JSON_AI_GUIDE.md');
      expect(guideFile.existsSync(), isTrue);
      final content = guideFile.readAsStringSync();

      for (final event in BehaviorEvent.values) {
        expect(
          content,
          contains('"${event.name}"'),
          reason: 'BehaviorEvent.${event.name} doit être documenté.',
        );
      }
      for (final op in BehaviorValidatorOperator.values) {
        expect(
          content,
          contains('"${op.shortName}"'),
          reason:
              'BehaviorValidatorOperator.${op.shortName} doit être documenté.',
        );
      }
      for (final composite in ['"all"', '"any"', '"not"']) {
        expect(content, contains(composite));
      }
      for (final item in BehaviorCatalog.items) {
        expect(
          content,
          contains('"${item.actionType}"'),
          reason: 'Action "${item.actionType}" doit être documentée.',
        );
      }
      expect(content, contains('CollectionViewTransform'));
      expect(content, contains('ctx.set'));

      final jsonBlocks = RegExp(r'```json\s*([\s\S]*?)\s*```')
          .allMatches(content)
          .map((m) => m.group(1)!)
          .toList();
      expect(jsonBlocks, isNotEmpty);

      final recipeRaw = jsonBlocks.last;
      final decodedRecipe = jsonDecode(recipeRaw) as Map<String, dynamic>;
      expect(decodedRecipe.keys.toList(), ['message', 'repositories', 'vibe']);

      final dir = Directory.systemTemp.createTempSync('vibe_behavior_guide_');
      final store = JsonRepositoryStore(dir, jsEvaluator: _GuideJsEvaluator());
      addTearDown(() async {
        store.dispose();
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final tx = VibeRepositoryTurnTransaction(store);
      final rawRepositories =
          decodedRecipe['repositories'] as Map<String, dynamic>;
      final aliases = await tx.applyRepositoriesPatch(rawRepositories);

      final actualId = aliases['pilotage_dossiers'];
      expect(actualId, isNotNull);
      expect(actualId, matches(RegExp(r'^[0-9a-f]{32}$')));

      final rawVibe = decodedRecipe['vibe'] as Map<String, dynamic>;
      final rewrittenVibe = tx.rewriteVibePatchBindings(rawVibe);
      final updated = AppearanceTransfer.applyVibe(
        Appearance(),
        jsonEncode(rewrittenVibe),
      );

      // Vérifie la réécriture des alias dans runJavaScript, addArrayItem, bindState, bindZoneSize et validateurs
      final toggleSidebar =
          updated.behaviorsFor('btn-toggle-sidebar').single.action
              as RunJavaScriptAction;
      expect(toggleSidebar.repositoryId, actualId);

      final validateBehavior = updated
          .behaviorsFor('btn-validate-dossier')
          .last;
      final validateJs = validateBehavior.action as RunJavaScriptAction;
      expect(validateJs.repositoryId, actualId);
      final allValidator = validateBehavior.validator! as AllBehaviorValidator;
      final statusGuard =
          allValidator.validators.last as ValueBehaviorValidator;
      expect(
        statusGuard.binding,
        JsonTextBinding(repositoryId: actualId, path: 'dossiers[?].statut'),
      );

      final addAction =
          updated.behaviorsFor('btn-add-dossier').single.action
              as AddArrayItemAction;
      expect(
        addAction.binding,
        JsonTextBinding(repositoryId: actualId, path: 'dossiers'),
      );

      // Vérifie aussi la réécriture d'expectedBinding en chaîne courte "<alias>:..."
      final expectedRewritten = rewriteVibePatchRepositoryAliases(
        {
          'behaviors': {
            'list-dossiers': [
              {
                'id': 'b-min-ht',
                'event': 'onBinding',
                'action': {
                  'type': 'filterCollection',
                  'predicate': {
                    'type': 'bindingGreaterThan',
                    'binding': 'dossiers[?].montantHt',
                    'expectedBinding': 'pilotage_dossiers:ui.westWidth',
                  },
                },
              },
            ],
          },
        },
        {'pilotage_dossiers': actualId!},
      );
      final parsedExpected = ComponentBehavior.fromJson(
        Map<String, dynamic>.from(
          ((expectedRewritten['behaviors'] as Map)['list-dossiers'] as List)
                  .single
              as Map,
        ),
      );
      final pred =
          (parsedExpected.action as FilterCollectionAction).predicate!
              as ValueBehaviorValidator;
      expect(
        pred.expectedBinding,
        JsonTextBinding(repositoryId: actualId, path: 'ui.westWidth'),
      );

      // Vérifie la préservation de behaviors["list-dossiers:item"] dans un scope Vibe
      const listScope = VibeChatScope(
        componentId: 'list-dossiers',
        label: 'Liste des dossiers',
      );
      final exportedScoped = jsonDecode(
        VibeScopeHelpers.exportScopedAi(updated, listScope),
      ) as Map<String, dynamic>;
      expect(
        (exportedScoped['behaviors'] as Map).containsKey('list-dossiers:item'),
        isTrue,
      );
      final filteredScoped = VibeScopeHelpers.filterPatchToScope(updated, {
        'behaviors': {
          'list-dossiers:item': [
            {
              'id': 'b-row-tap',
              'event': 'onTap',
              'action': {'type': 'goToPage', 'pagePath': '/detail'},
            },
          ],
        },
      }, listScope);
      expect(
        (filteredScoped['behaviors'] as Map).containsKey('list-dossiers:item'),
        isTrue,
      );

      // Vérifie le calcul @montantTtc sur la première ligne (12500 * 1.2 = 15000)
      final ttc0 = await store.readAttribute(
        JsonTextBinding(
          repositoryId: actualId,
          path: 'dossiers[0].@montantTtc',
        ),
      );
      expect(ttc0.value, 15000.0);

      // Sélectionne la ligne 0 et exécute le script de validation sur le repository
      store.bindingOf(actualId).array('dossiers').select(const [], 0);
      await store.runJavaScriptAction(
        repositoryId: actualId,
        code: validateJs.code,
      );
      final dossiersAfter = await store.readArray(actualId, 'dossiers');
      final firstAfter = dossiersAfter.first as Map;
      expect(firstAfter['statut'], 'valide');
      expect(firstAfter['verrouille'], true);
    });
  });

  group('VibeRepositoryPromptFormatter.formatStoreContext', () {
    test('retourne emptyStoreMessage lorsque le store est vide', () async {
      final (:store, dir: _) = _createTempStore('vibe_prompt_empty_');
      expect(
        await VibeRepositoryPromptFormatter.formatStoreContext(store),
        VibeRepositoryPromptFormatter.emptyStoreMessage,
      );
    });

    test('formate un store mixte (memory avec addCalculatedAttribute, persistent, file > 5 items) avec kind, calculatedAttributes, truncatedArrays et sans clé @ dans data', () async {
      final (:store, dir: _) = _createTempStore('vibe_prompt_mixed_');

      // 1. RepositoryImpl mémoire avec attributs calculés racine et par ligne
      final memoryRepo = RepositoryImpl(
        id: 'facture_mem',
        json: <String, Object?>{
          'remise': 0.1,
          'articles': <Object?>[
            <String, Object?>{'id': 'A1', 'qte': 2, 'pu': 50.0},
            <String, Object?>{'id': 'A2', 'qte': 1, 'pu': 120.0},
          ],
        },
      );
      memoryRepo.addCalculatedAttribute(
        'montantHt',
        scope: 'articles[?]',
        (ctx) =>
            (ctx.sync.getInt('qte', defaultValue: 0)!) *
            (ctx.sync.getDouble('pu', defaultValue: 0.0)!),
      );
      memoryRepo.addCalculatedAttribute('totalBrut', (ctx) => 220.0);
      store.registerRepository(memoryRepo);

      // 2. RepositoryImpl persistant
      final persistentRepo = RepositoryImpl(
        id: 'prefs_persist',
        json: <String, Object?>{
          'ui': <String, Object?>{'westWidth': 280, 'dark': true},
        },
      );
      await store.registerPersistentRepository(persistentRepo);

      // 3. Repository fichier contenant un tableau de > 5 éléments (8 éléments)
      const fileRepoId = '0123456789abcdef0123456789abcdef';
      await store.createWithId(
        'Catalogue Produits',
        id: fileRepoId,
        initialDocument: <String, Object?>{
          'produits': <Object?>[
            for (var i = 1; i <= 8; i++)
              <String, Object?>{
                'id': 'PRD-$i',
                'nom': 'Produit $i',
                'stock': i * 10,
              },
          ],
        },
      );

      final formatted = await VibeRepositoryPromptFormatter.formatStoreContext(
        store,
        maxArrayItems: 5,
      );
      expect(
        formatted,
        startsWith('${VibeRepositoryPromptFormatter.sectionHeader}\n'),
      );

      final jsonPart = formatted.substring(
        VibeRepositoryPromptFormatter.sectionHeader.length + 1,
      );
      final descriptors = (jsonDecode(jsonPart) as List)
          .cast<Map<String, dynamic>>();
      expect(descriptors, hasLength(3));

      final byId = <String, Map<String, dynamic>>{
        for (final d in descriptors) d['id'] as String: d,
      };

      final memDesc = byId['facture_mem']!;
      expect(memDesc['kind'], 'memory');
      expect(
        memDesc['calculatedAttributes'],
        containsAll(<String>['articles[?].@montantHt', '@totalBrut']),
      );
      expect(memDesc.containsKey('truncatedArrays'), isFalse);
      expect(_containsKeyStartingWithAt(memDesc['data']), isFalse);

      final persistDesc = byId['prefs_persist']!;
      expect(persistDesc['kind'], 'persistent');
      expect(persistDesc.containsKey('calculatedAttributes'), isFalse);
      expect(_containsKeyStartingWithAt(persistDesc['data']), isFalse);

      final fileDesc = byId[fileRepoId]!;
      expect(fileDesc['name'], 'Catalogue Produits');
      expect(fileDesc['kind'], 'file');
      expect(fileDesc['truncatedArrays'], <String, dynamic>{'produits': 8});
      final sampledProduits =
          (fileDesc['data'] as Map<String, dynamic>)['produits'] as List;
      expect(sampledProduits, hasLength(5));
      expect((sampledProduits.first as Map)['id'], 'PRD-1');
      expect((sampledProduits.last as Map)['id'], 'PRD-5');
      expect(_containsKeyStartingWithAt(fileDesc['data']), isFalse);
    });
  });

  group('VibeRepositoryPatchValidator', () {
    test('rejette toute clé commençant par @ à la racine, dans un sous-objet ou dans un tableau', () {
      expect(
        () => VibeRepositoryPatchValidator.parseEntry('crm_clients', {
          '@total': 100,
        }),
        throwsFormatException,
      );
      expect(
        () => VibeRepositoryPatchValidator.parseEntry('crm_clients', {
          'mode': 'merge',
          'data': {
            'stats': {'@marge': 0.25},
          },
        }),
        throwsFormatException,
      );
      expect(
        () => VibeRepositoryPatchValidator.parseEntry('crm_clients', {
          'articles': [
            {'id': 'A1', '@montant': 42},
          ],
        }),
        throwsFormatException,
      );
    });

    test('rejette les clés contenant ".", "[", "]", "?" ou espace', () {
      for (final badKey in <String>[
        'client.nom',
        'clients[0',
        'clients0]',
        'estActif?',
        'nom client',
        'nom\tclient',
      ]) {
        expect(
          () => VibeRepositoryPatchValidator.parseEntry('crm_clients', {
            'data': {badKey: 'valeur'},
          }),
          throwsFormatException,
          reason: 'La clé "$badKey" aurait dû être rejetée.',
        );
      }
    });

    test('rejette une racine data qui est une List ou un primitif, ainsi qu\'un mode inconnu', () {
      for (final invalidData in <Object?>[
        <Object?>[
          {'id': 1},
        ],
        'chaine',
        42,
        true,
        null,
      ]) {
        expect(
          () => VibeRepositoryPatchValidator.parseEntry('crm_clients', {
            'name': 'CRM',
            'mode': 'merge',
            'data': invalidData,
          }),
          throwsFormatException,
        );
        expect(
          () => VibeRepositoryPatchValidator.parseEntry(
            'crm_clients',
            invalidData,
          ),
          throwsFormatException,
        );
      }

      expect(
        () => VibeRepositoryPatchValidator.parseEntry('crm_clients', {
          'mode': 'append',
          'data': {'ok': 1},
        }),
        throwsFormatException,
      );
      expect(
        () => VibeRepositoryPatchValidator.parseEntry('crm_clients', {
          'mode': 123,
          'data': {'ok': 1},
        }),
        throwsFormatException,
      );
      expect(
        () => VibeRepositoryPatchValidator.validateAndParse('pas_une_map'),
        throwsFormatException,
      );
    });

    test('accepte l\'enveloppe explicite {"name", "mode", "data"} et le raccourci objet direct', () {
      final explicit = VibeRepositoryPatchValidator.parseEntry('crm_clients', {
        'name': 'CRM Clients',
        'mode': 'replace',
        'data': {
          'ui': {'activeTab': 0},
          'clients': [
            {'id': 'C1', 'nom': 'Alice'},
          ],
        },
      });
      expect(explicit.key, 'crm_clients');
      expect(explicit.name, 'CRM Clients');
      expect(explicit.mode, VibeRepositoryPatchMode.replace);
      expect((explicit.data['clients'] as List).single, {
        'id': 'C1',
        'nom': 'Alice',
      });

      final shorthand = VibeRepositoryPatchValidator.parseEntry('app_state', {
        'ui': {'westWidth': 300},
        'items': <Object?>[],
      });
      expect(shorthand.key, 'app_state');
      expect(shorthand.name, isNull);
      expect(shorthand.mode, VibeRepositoryPatchMode.merge);
      expect(shorthand.data, {
        'ui': {'westWidth': 300},
        'items': <Object?>[],
      });
    });
  });

  group('VibeRepositoryTurnTransaction & EditorHistoryController', () {
    test('crée via alias snake_case, applique merge de façon idempotente en streaming SSE et réécrit toutes les liaisons sans altérer les préfixes système', () async {
      final (:store, dir: _) = _createTempStore('vibe_tx_sse_');
      final existingId = await store.createWithId(
        'Settings',
        id: 'fedcba9876543210fedcba9876543210',
        initialDocument: <String, Object?>{
          'ui': <String, Object?>{'theme': 'pro', 'westWidth': 260},
          'keepMe': true,
        },
      );

      final tx = VibeRepositoryTurnTransaction(store, random: Random(42));

      // Palier SSE 1 : création de crm_clients
      final map1 = await tx.applyRepositoriesPatch(<String, dynamic>{
        'crm_clients': <String, Object?>{
          'name': 'CRM Clients',
          'mode': 'merge',
          'data': <String, Object?>{
            'clients': <Object?>[
              <String, Object?>{'id': 'C1', 'nom': 'Alice'},
            ],
          },
        },
      });
      final crmActualId = map1['crm_clients']!;
      expect(crmActualId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(crmActualId, isNot(existingId));

      // Palier SSE 2 : ré-application cumulative sur crm_clients + modification de Settings
      final map2 = await tx.applyRepositoriesPatch(<String, dynamic>{
        'crm_clients': <String, Object?>{
          'name': 'CRM Clients',
          'mode': 'merge',
          'data': <String, Object?>{
            'clients': <Object?>[
              <String, Object?>{'id': 'C1', 'nom': 'Alice'},
              <String, Object?>{'id': 'C2', 'nom': 'Bruno'},
            ],
          },
        },
        existingId: <String, Object?>{
          'mode': 'merge',
          'data': <String, Object?>{
            'ui': <String, Object?>{'westWidth': 310},
            'transientField': 'palier2',
          },
        },
      });
      expect(map2['crm_clients'], crmActualId);

      // Validation finale : merge repart bien de la baseline de Settings (pas de fuite de transientField)
      // et conserve exactement le même ID 32 hex pour crm_clients sans créer de fichier dupliqué.
      final mapFinal = await tx.applyRepositoriesPatch(<String, dynamic>{
        'crm_clients': <String, Object?>{
          'name': 'CRM Clients',
          'mode': 'merge',
          'data': <String, Object?>{
            'options': <String, Object?>{
              'statuts': <Object?>[
                <String, Object?>{'value': 'actif', 'label': 'Actif'},
              ],
            },
            'clients': <Object?>[
              <String, Object?>{'id': 'C1', 'nom': 'Alice'},
              <String, Object?>{'id': 'C2', 'nom': 'Bruno'},
            ],
          },
        },
        existingId: <String, Object?>{
          'mode': 'merge',
          'data': <String, Object?>{
            'ui': <String, Object?>{'westWidth': 340},
          },
        },
      });
      expect(mapFinal['crm_clients'], crmActualId);
      expect(await store.list(), ['CRM Clients', 'Settings']);

      final settingsDoc =
          await store.readDocument(existingId) as Map<String, Object?>;
      expect(settingsDoc, <String, Object?>{
        'ui': <String, Object?>{'theme': 'pro', 'westWidth': 340},
        'keepMe': true,
      });

      final crmDoc =
          await store.readDocument(crmActualId) as Map<String, Object?>;
      expect((crmDoc['clients'] as List), hasLength(2));
      expect(
        ((crmDoc['options'] as Map)['statuts'] as List).single,
        <String, Object?>{'value': 'actif', 'label': 'Actif'},
      );

      // Vérification exhaustive de rewriteVibePatchBindings
      final rawVibe = <String, dynamic>{
        'styles': <String, Object?>{
          'hero': <String, Object?>{
            'color': 'theme:surface',
            'fill': <String, Object?>{
              'imageUrl': 'https://cdn.example.com/banner.png',
              'imageBinding': 'crm_clients:branding.bannerUrl',
            },
            'propertyBindings': <String, Object?>{
              'borderColor': 'crm_clients:branding.borderHex',
              'imageUrl': 'https://cdn.example.com/static.png',
            },
          },
        },
        'components': <String, Object?>{
          'mainLayout': <String, Object?>{
            'type': 'layout',
            'placements': <String, Object?>{
              'center': <Object?>[
                <String, Object?>{'id': 'tabs', 'type': 'registry:Tab'},
                <String, Object?>{'id': 'cond', 'type': 'registry:Conditional'},
              ],
            },
          },
          'tabs': <String, Object?>{
            'type': 'tab',
            'mode': 'dynamic',
            'binding': 'crm_clients:categories',
            'dynamicTab': <String, Object?>{
              'label': 'crm_clients:categories[?].nom',
              'icon': 'crm_clients:categories[?].icone',
              'binding': 'crm_clients:categories[?].sousItems',
            },
          },
          'cond': <String, Object?>{
            'type': 'conditional',
            'binding': <String, Object?>{
              'repositoryId': 'crm_clients',
              'path': 'ui.mode',
            },
            'placements': <String, Object?>{
              'case:detail': <Object?>[
                <String, Object?>{'id': 'choice', 'type': 'registry:Value'},
              ],
            },
          },
          'choice': <String, Object?>{
            'type': 'value',
            'kind': 'choice',
            'mode': 'input',
            'text': 'crm_clients:texte_statique_non_touche',
            'color': 'theme:primary',
            'binding': 'crm_clients:clients[?].statut',
            'errorBinding': 'crm_clients:errors.statut',
            'choice': <String, Object?>{
              'optionsBinding': 'crm_clients:options.statuts',
            },
            'propertyBindings': <String, Object?>{
              'label': 'crm_clients:labels.statut',
              'color': 'theme:onSurface',
            },
          },
        },
      };

      final rewritten = tx.rewriteVibePatchBindings(rawVibe);
      final heroStyle =
          (rewritten['styles'] as Map)['hero'] as Map<String, dynamic>;
      expect(heroStyle['color'], 'theme:surface');
      expect(
        (heroStyle['fill'] as Map)['imageUrl'],
        'https://cdn.example.com/banner.png',
      );
      expect(
        (heroStyle['fill'] as Map)['imageBinding'],
        '$crmActualId:branding.bannerUrl',
      );
      expect(
        (heroStyle['propertyBindings'] as Map)['borderColor'],
        '$crmActualId:branding.borderHex',
      );
      expect(
        (heroStyle['propertyBindings'] as Map)['imageUrl'],
        'https://cdn.example.com/static.png',
      );

      final comps = rewritten['components'] as Map<String, dynamic>;
      expect(
        (((comps['mainLayout'] as Map)['placements'] as Map)['center'] as List)
            .first,
        <String, Object?>{'id': 'tabs', 'type': 'registry:Tab'},
      );
      final tabs = comps['tabs'] as Map<String, dynamic>;
      expect(tabs['binding'], '$crmActualId:categories');
      expect(
        (tabs['dynamicTab'] as Map)['label'],
        '$crmActualId:categories[?].nom',
      );
      expect(
        (tabs['dynamicTab'] as Map)['icon'],
        '$crmActualId:categories[?].icone',
      );
      expect(
        (tabs['dynamicTab'] as Map)['binding'],
        '$crmActualId:categories[?].sousItems',
      );

      final cond = comps['cond'] as Map<String, dynamic>;
      expect(cond['binding'], <String, Object?>{
        'repositoryId': crmActualId,
        'path': 'ui.mode',
      });
      expect(((cond['placements'] as Map).containsKey('case:detail')), isTrue);

      final choice = comps['choice'] as Map<String, dynamic>;
      expect(choice['text'], 'crm_clients:texte_statique_non_touche');
      expect(choice['color'], 'theme:primary');
      expect(choice['binding'], '$crmActualId:clients[?].statut');
      expect(choice['errorBinding'], '$crmActualId:errors.statut');
      expect(
        (choice['choice'] as Map)['optionsBinding'],
        '$crmActualId:options.statuts',
      );
      expect(
        (choice['propertyBindings'] as Map)['label'],
        '$crmActualId:labels.statut',
      );
      expect((choice['propertyBindings'] as Map)['color'], 'theme:onSurface');
    });

    test('rollback() supprime les fichiers créés et restaure exactement les repositories préexistants (fichier et RepositoryImpl)', () async {
      final (:store, dir: tempDir) = _createTempStore('vibe_tx_rollback_');

      final initialMemJson = <String, Object?>{
        'counter': 10,
        'nested': <String, Object?>{'flag': true, 'label': 'Initial'},
      };
      store.registerRepository(
        RepositoryImpl(id: 'host_state', json: initialMemJson),
      );

      final initialFileJson = <String, Object?>{
        'items': <Object?>[
          <String, Object?>{'id': 'I1', 'qty': 3},
        ],
      };
      const fileId = 'aaaa1111bbbb2222cccc3333dddd4444';
      await store.createWithId(
        'Inventaire',
        id: fileId,
        initialDocument: initialFileJson,
      );

      final tx = VibeRepositoryTurnTransaction(store);
      final aliases = await tx.applyRepositoriesPatch(<String, dynamic>{
        'nouveau_repo': <String, Object?>{
          'name': 'Nouveau Repo',
          'mode': 'merge',
          'data': <String, Object?>{
            'lignes': <Object?>[
              <String, Object?>{'id': 'L1'},
            ],
          },
        },
        'host_state': <String, Object?>{
          'mode': 'merge',
          'data': <String, Object?>{
            'counter': 99,
            'nested': <String, Object?>{'flag': false},
            'added': 'extra',
          },
        },
        fileId: <String, Object?>{
          'mode': 'replace',
          'data': <String, Object?>{'items': <Object?>[]},
        },
      });

      final createdId = aliases['nouveau_repo']!;
      expect(tx.hasChanges, isTrue);
      expect(
        File('${tempDir.path}${Platform.pathSeparator}Nouveau Repo.json')
            .existsSync(),
        isTrue,
      );
      expect(
        File('${tempDir.path}${Platform.pathSeparator}Nouveau Repo.json.id')
            .existsSync(),
        isTrue,
      );

      await tx.rollback();

      expect(tx.hasChanges, isFalse);
      expect(tx.aliasToActualId, isEmpty);
      expect(
        File('${tempDir.path}${Platform.pathSeparator}Nouveau Repo.json')
            .existsSync(),
        isFalse,
      );
      expect(
        File('${tempDir.path}${Platform.pathSeparator}Nouveau Repo.json.id')
            .existsSync(),
        isFalse,
      );
      final catalogAfter = await store.catalog();
      expect(catalogAfter.any((e) => e.id == createdId), isFalse);
      expect(await store.readDocument('host_state'), initialMemJson);
      expect(await store.readDocument(fileId), initialFileJson);
    });

    test('intègre EditorHistoryController (undoAsync / redoAsync) avec Appearance modifiée ainsi que lors d\'une transaction purement repository en préservant le même ID 32 hex', () async {
      final (:store, dir: _) = _createTempStore('vibe_tx_history_');

      store.registerRepository(
        RepositoryImpl(
          id: 'app_repo',
          json: <String, Object?>{'title': 'Avant'},
        ),
      );

      final appearance = ValueNotifier<Appearance>(Appearance());
      final editMode = ValueNotifier<bool>(true);
      final history = EditorHistoryController(
        appearance: appearance,
        editMode: editMode,
      );
      addTearDown(appearance.dispose);
      addTearDown(editMode.dispose);
      addTearDown(history.dispose);

      final initialAppearance = appearance.value;

      // 1. Transaction combinant Appearance + création et mise à jour de repositories
      history.beginTransaction();
      final tx1 = VibeRepositoryTurnTransaction(store, random: Random(7));
      final aliases1 = await tx1.applyRepositoriesPatch(<String, dynamic>{
        'crm_clients': <String, Object?>{
          'name': 'CRM Clients',
          'mode': 'merge',
          'data': <String, Object?>{
            'clients': <Object?>[
              <String, Object?>{'id': 'C1', 'nom': 'Claire'},
            ],
          },
        },
        'app_repo': <String, Object?>{
          'mode': 'merge',
          'data': <String, Object?>{'title': 'Après Tour 1'},
        },
      });
      final crmId = aliases1['crm_clients']!;
      expect(crmId, matches(RegExp(r'^[0-9a-f]{32}$')));

      final rewrittenVibe = tx1.rewriteVibePatchBindings(<String, dynamic>{
        'components': <String, Object?>{
          'mainLayout': <String, Object?>{
            'type': 'layout',
            'slotLabels': <String, Object?>{'client-nom': 'Nom du client'},
            'placements': <String, Object?>{
              'center': <Object?>[
                <String, Object?>{'id': 'client-nom', 'type': 'registry:Value'},
              ],
            },
          },
          'client-nom': <String, Object?>{
            'type': 'value',
            'binding': 'crm_clients:clients[?].nom',
          },
        },
      });
      appearance.value = AppearanceTransfer.applyVibe(
        appearance.value,
        jsonEncode(rewrittenVibe),
      );
      final callbacks1 = tx1.buildHistoryCallbacks();
      expect(callbacks1, isNotNull);
      history.addTransactionSideEffect(
        undo: callbacks1!.undo,
        redo: callbacks1.redo,
      );
      history.commitTransaction();

      final tour1Appearance = appearance.value;
      expect(history.canUndo, isTrue);
      expect(
        tour1Appearance.valueComponent('client-nom').binding,
        JsonTextBinding(repositoryId: crmId, path: 'clients[?].nom'),
      );

      await history.undoAsync();
      expect(appearance.value, initialAppearance);
      expect((await store.catalog()).any((e) => e.id == crmId), isFalse);
      expect(await store.readDocument('app_repo'), <String, Object?>{
        'title': 'Avant',
      });
      expect(history.canRedo, isTrue);

      await history.redoAsync();
      expect(appearance.value, tour1Appearance);
      expect(
        appearance.value.valueComponent('client-nom').binding?.repositoryId,
        crmId,
      );
      expect((await store.catalog()).any((e) => e.id == crmId), isTrue);
      expect(await store.idOf('CRM Clients'), crmId);
      expect(await store.readArray(crmId, 'clients'), <Object?>[
        <String, Object?>{'id': 'C1', 'nom': 'Claire'},
      ]);
      expect(await store.readDocument('app_repo'), <String, Object?>{
        'title': 'Après Tour 1',
      });

      // 2. Transaction modifiant uniquement un repository sans toucher à Appearance
      final appearanceBeforeRepoOnly = appearance.value;
      history.beginTransaction();
      final tx2 = VibeRepositoryTurnTransaction(store, random: Random(99));
      final aliases2 = await tx2.applyRepositoriesPatch(<String, dynamic>{
        'notes_internes': <String, Object?>{
          'name': 'Notes Internes',
          'mode': 'merge',
          'data': <String, Object?>{
            'notes': <Object?>[
              <String, Object?>{'id': 'N1', 'texte': 'Relancer client'},
            ],
          },
        },
        crmId: <String, Object?>{
          'mode': 'merge',
          'data': <String, Object?>{
            'clients': <Object?>[
              <String, Object?>{'id': 'C1', 'nom': 'Claire'},
              <String, Object?>{'id': 'C2', 'nom': 'Marc'},
            ],
          },
        },
      });
      final notesId = aliases2['notes_internes']!;
      expect(notesId, matches(RegExp(r'^[0-9a-f]{32}$')));

      final callbacks2 = tx2.buildHistoryCallbacks()!;
      history.addTransactionSideEffect(
        undo: callbacks2.undo,
        redo: callbacks2.redo,
      );
      history.commitTransaction();

      expect(identical(appearance.value, appearanceBeforeRepoOnly), isTrue);
      expect((await store.catalog()).any((e) => e.id == notesId), isTrue);
      expect(await store.readArray(crmId, 'clients'), hasLength(2));

      await history.undoAsync();
      expect(identical(appearance.value, appearanceBeforeRepoOnly), isTrue);
      expect((await store.catalog()).any((e) => e.id == notesId), isFalse);
      expect(await store.readArray(crmId, 'clients'), <Object?>[
        <String, Object?>{'id': 'C1', 'nom': 'Claire'},
      ]);

      await history.redoAsync();
      expect(identical(appearance.value, appearanceBeforeRepoOnly), isTrue);
      expect((await store.catalog()).any((e) => e.id == notesId), isTrue);
      expect(await store.idOf('Notes Internes'), notesId);
      expect(await store.readArray(notesId, 'notes'), <Object?>[
        <String, Object?>{'id': 'N1', 'texte': 'Relancer client'},
      ]);
      expect(await store.readArray(crmId, 'clients'), hasLength(2));
    });
  });

  group('Garde anti-collision de clé racine & auto-redirection', () {
    test(
      'VibeRepositoryPatchValidator rejette les clés UI réservées et ne crée jamais vibe.json',
      () async {
        for (final forbiddenKey in const <String>[
          'vibe',
          'components',
          'styles',
          'behaviors',
          'usages',
          'pageCatalog',
          'responsiveLayout',
        ]) {
          expect(
            () => VibeRepositoryPatchValidator.parseEntry(forbiddenKey, {
              'data': {'foo': 'bar'},
            }),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                contains('Clé UI racine réservée'),
              ),
            ),
            reason: 'La clé "$forbiddenKey" doit être rejetée.',
          );
        }

        final (:store, dir: _) = _createTempStore('vibe_forbidden_key_');
        final tx = VibeRepositoryTurnTransaction(store);

        await expectLater(
          tx.applyRepositoriesPatch(<String, dynamic>{
            'vibe': <String, Object?>{
              'data': <String, Object?>{
                'components': <String, Object?>{
                  'dash-header': <String, Object?>{'type': 'value'},
                },
              },
            },
          }),
          throwsFormatException,
        );
        expect(await store.catalog(), isEmpty);

        // En mode streaming partiel, la clé "vibe" est rejetée sans polluer le store
        // tandis qu'un vrai repository voisin est bien appliqué.
        final partial = await tx.applyRepositoriesPatchPartial(<String, dynamic>{
          'vibe': <String, Object?>{
            'data': <String, Object?>{'components': <String, Object?>{}},
          },
          'crm_comptes': <String, Object?>{
            'name': 'CRM Comptes',
            'mode': 'merge',
            'data': <String, Object?>{'comptes': <Object?>[]},
          },
        });
        expect(partial.appliedEntries.keys, ['crm_comptes']);
        expect(partial.rejectedEntries, hasLength(1));
        expect(partial.rejectedEntries.single.key, 'vibe');
        final catalog = await store.catalog();
        expect(catalog.map((e) => e.name), ['CRM Comptes']);
      },
    );

    test(
      'VibeRepositoryApplier.sanitizeResponseEnvelope redirige repositories["vibe"] et repositories["components"] quand la racine vibe est absente',
      () {
        // Cas 1 : repositories.vibe.data -> racine vibe, repositories supprimé
        final case1 = VibeRepositoryApplier.sanitizeResponseEnvelope({
          'message': 'Dashboard généré.',
          'repositories': {
            'vibe': {
              'data': {
                'components': {
                  'mainLayout': {'type': 'layout'},
                },
                'styles': {
                  'card-kpi': {'radius': 12},
                },
              },
            },
          },
        });
        expect(case1.warnings, hasLength(1));
        expect(case1.response.containsKey('repositories'), isFalse);
        expect(
          (case1.response['vibe'] as Map<String, dynamic>).keys,
          unorderedEquals(['components', 'styles']),
        );

        // Cas 2 : repositories.vibe direct + vrai repository frère conservé
        final case2 = VibeRepositoryApplier.sanitizeResponseEnvelope({
          'message': 'Dashboard + CRM.',
          'repositories': {
            'crm_clients': {
              'name': 'CRM',
              'data': {'clients': []},
            },
            'vibe': {
              'components': {
                'mainLayout': {'type': 'layout'},
              },
            },
          },
        });
        expect(case2.warnings, hasLength(1));
        expect(
          (case2.response['repositories'] as Map<String, dynamic>).keys,
          ['crm_clients'],
        );
        expect(
          ((case2.response['vibe'] as Map<String, dynamic>)['components']
                  as Map)
              .containsKey('mainLayout'),
          isTrue,
        );

        // Cas 3 : repositories.components & repositories.styles sans racine vibe
        final case3 = VibeRepositoryApplier.sanitizeResponseEnvelope({
          'message': 'Clés UI à plat dans repositories.',
          'repositories': {
            'components': {
              'mainLayout': {'type': 'layout'},
            },
            'styles': {
              'background': {'color': 'theme:surface'},
            },
          },
        });
        expect(case3.warnings, hasLength(1));
        expect(case3.response.containsKey('repositories'), isFalse);
        expect(
          (case3.response['vibe'] as Map<String, dynamic>).keys,
          unorderedEquals(['components', 'styles']),
        );

        // Cas 4 : racine vibe déjà présente -> aucune redirection silencieuse (sera rejeté par le validateur)
        final originalCollision = <String, dynamic>{
          'message': 'Collision ambiguë.',
          'repositories': {
            'vibe': {
              'data': {
                'components': {'other': {'type': 'value'}},
              },
            },
          },
          'vibe': {
            'components': {'mainLayout': {'type': 'layout'}},
          },
        };
        final case4 = VibeRepositoryApplier.sanitizeResponseEnvelope(
          originalCollision,
        );
        expect(case4.warnings, isEmpty);
        expect(
          (case4.response['repositories'] as Map).containsKey('vibe'),
          isTrue,
        );
      },
    );

    test(
      'les guides IA documentent les 3 règles anti-collision, placements exhaustifs et IDs existants',
      () {
        final repoGuide = File('REPOSITORY_JSON_AI_GUIDE.md').existsSync()
            ? File('REPOSITORY_JSON_AI_GUIDE.md').readAsStringSync()
            : File(
                'packages/super_container_layout/REPOSITORY_JSON_AI_GUIDE.md',
              ).readAsStringSync();
        final screenGuide = File('SCREEN_JSON_AI_GUIDE.md').existsSync()
            ? File('SCREEN_JSON_AI_GUIDE.md').readAsStringSync()
            : File(
                'packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md',
              ).readAsStringSync();

        expect(repoGuide, contains('Règle d\'or anti-collision de clé racine'));
        expect(
          repoGuide,
          contains('Réutilisation prioritaire des IDs de repository existants'),
        );
        expect(
          screenGuide,
          contains('Règle d\'or anti-collision de clé racine'),
        );
        expect(
          screenGuide,
          contains('Contrôle d\'exhaustivité des placements descendants'),
        );
      },
    );
  });
}
