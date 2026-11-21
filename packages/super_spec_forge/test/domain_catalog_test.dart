import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart'
    show VibeChatAttachment;
import 'package:super_spec_forge/super_spec_forge.dart';

class _MemorySecretKeyStorage implements DomainSecretKeyStorage {
  String? value;

  @override
  Future<String?> readKey() async => value;

  @override
  Future<void> writeKey(String encodedKey) async => value = encodedKey;
}

class _MemoryDomainCatalogStore extends DomainCatalogStore {
  _MemoryDomainCatalogStore() : super(Directory('memory_domain_catalog'));

  DomainCatalog catalog = DomainCatalog.empty;

  @override
  Future<DomainCatalog> load() async => catalog;

  @override
  Future<void> save(DomainCatalog next) async {
    next.validate();
    catalog = next;
  }
}

void main() {
  group('DomainCatalog', () {
    test('valide les codes canoniques et les références', () {
      final domain = FunctionalDomain(
        id: 'domain_1',
        domainCode: 'billing-domain',
        name: 'Facturation',
      );
      final environment = LogicalEnvironment(
        id: 'env_1',
        domainId: domain.id,
        environmentCode: 'review-pr-12',
        name: 'Revue 12',
      );
      DomainCatalog(domains: [domain], environments: [environment]).validate();

      expect(
        () => FunctionalDomain(
          id: 'domain_2',
          domainCode: 'Billing_Domain',
          name: 'Invalid',
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => DomainCatalog(
          domains: [domain],
          environments: [
            environment,
            environment.copyWith(id: 'env_2'),
          ],
        ).validate(),
        throwsFormatException,
      );
    });

    test('refuse une valeur claire dans un secret et les clés dupliquées', () {
      const domainId = 'domain_1';
      const environmentId = 'env_1';
      final plain = ConfigurationEntry(
        id: 'config_1',
        domainId: domainId,
        environmentId: environmentId,
        configKey: 'DATABASE_URL',
        entryType: ConfigurationEntryType.plainVariable,
        plainValue: 'postgres://localhost',
      );
      final inconsistent = ConfigurationEntry(
        id: 'config_2',
        domainId: domainId,
        environmentId: environmentId,
        configKey: 'DATABASE_PASSWORD',
        entryType: ConfigurationEntryType.secret,
        plainValue: 'must-not-be-clear',
      );
      expect(inconsistent.validate, throwsFormatException);
      expect(
        () => DomainCatalog(
          domains: const [
            FunctionalDomain(
              id: domainId,
              domainCode: 'billing',
              name: 'Billing',
            ),
          ],
          environments: const [
            LogicalEnvironment(
              id: environmentId,
              domainId: domainId,
              environmentCode: 'dev',
              name: 'Development',
            ),
          ],
          configurationEntries: [
            plain,
            plain.copyWith(id: 'config_2'),
          ],
        ).validate(),
        throwsFormatException,
      );
    });

    test(
      'sérialise et recharge les secrets uniquement sous forme chiffrée',
      () {
        const secret = ConfigurationEntry(
          id: 'secret_1',
          domainId: 'domain_1',
          environmentId: 'env_1',
          configKey: 'DATABASE_PASSWORD',
          entryType: ConfigurationEntryType.secret,
          encryptedValue: 'v1:opaque-ciphertext',
        );
        final catalog = DomainCatalog(
          domains: const [
            FunctionalDomain(
              id: 'domain_1',
              domainCode: 'billing',
              name: 'Billing',
            ),
          ],
          environments: const [
            LogicalEnvironment(
              id: 'env_1',
              domainId: 'domain_1',
              environmentCode: 'dev',
              name: 'Development',
            ),
          ],
          configurationEntries: const [secret],
        );
        final restored = DomainCatalog.fromJson(catalog.toJson());
        expect(
          restored.configurationEntries.single.encryptedValue,
          secret.encryptedValue,
        );
        expect(restored.configurationEntries.single.plainValue, isNull);
      },
    );
  });

  group('DomainSecretCipher', () {
    test('chiffre avec nonce distinct et permet le déchiffrement', () async {
      final keyStorage = _MemorySecretKeyStorage();
      final cipher = DomainSecretCipher(keyStorage: keyStorage);
      const clearText = 'a-sensitive-value';

      final first = await cipher.encrypt(clearText);
      final second = await cipher.encrypt(clearText);

      expect(first, startsWith('v1:'));
      expect(first, isNot(contains(clearText)));
      expect(second, isNot(first));
      expect(await cipher.decrypt(first), clearText);
      expect(await cipher.decrypt(second), clearText);
    });

    test('signale une clé perdue et un ciphertext altéré', () async {
      final keyStorage = _MemorySecretKeyStorage();
      final cipher = DomainSecretCipher(keyStorage: keyStorage);
      final encrypted = await cipher.encrypt('secret');
      final altered = '${encrypted.substring(0, encrypted.length - 2)}AA';

      expect(
        DomainSecretCipher(keyStorage: _MemorySecretKeyStorage())
            .decrypt(encrypted),
        throwsStateError,
      );
      expect(cipher.decrypt(altered), throwsA(isA<Exception>()));
    });
  });

  test('Le catalogue conserve les propriétés et les commentaires du DSL par domaine', () async {
    final directory = await Directory.systemTemp.createTemp(
      'domain_contracts_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = DomainCatalogStore(directory);
    final source = DomainContracts.parse(
      'models:\n  sales: model # ventes\ncomponents:\n',
    );
    final sale = source.groups.first.children.single;
    final updated = source.edit(
      sale,
      'component',
      ContractDetails(
        title: 'Une vente',
        version: '0.0.2',
        states: {ContractStage.validation: ContractStatus.done},
      ),
    );
    await store.save(
      DomainCatalog(
        domains: [
          FunctionalDomain(
            id: 'oms',
            domainCode: 'oms',
            name: 'OMS',
            contracts: updated,
          ),
          const FunctionalDomain(id: 'rh', domainCode: 'rh', name: 'RH'),
        ],
      ),
    );
    final restored = (await store.load()).domains;
    expect(restored.last.contracts, isNull);
    final doc = restored.first.contracts!;
    expect(doc.source, 'models:\n  sales: component # ventes\ncomponents:\n');
    expect(doc.entryById(sale.id)?.type, 'component');
    expect(
      doc.details[sale.id]?.states[ContractStage.validation],
      ContractStatus.done,
    );
    // Bloc déplacé dans une autre rubrique : même ID, mêmes métadonnées.
    final moved = doc.patch(
      'models:\ncomponents:\n  sales: component # ventes\n',
    );
    expect(moved.entryById(sale.id)?.path, 'components.sales');
    expect(moved.details[sale.id]?.title, 'Une vente');
    // Coupé, enregistré, puis recollé : l'ID revient avec ses métadonnées.
    final cut = DomainContracts.fromJson(
      jsonDecode(jsonEncode(moved.patch('models:\ncomponents:\n').toJson())),
    );
    expect(cut.entryById(sale.id), isNull);
    final pasted = cut.patch('models:\n  sales: component\ncomponents:\n');
    expect(pasted.entryById(sale.id)?.path, 'models.sales');
    final renamed = pasted.patch('models:\n  vente: component\ncomponents:\n');
    expect(renamed.entryById(sale.id)?.name, 'vente');
    expect(renamed.details[sale.id]?.title, 'Une vente');
  });

  test('Le détail et le chat d’un modèle suivent son ID et le patch IA est fusionné', () {
    final doc = DomainContracts.parse(
      'models:\n  sales: model\n  client: part\n',
    );
    final sale = doc.groups.single.children.first;
    final client = doc.groups.single.children.last;
    expect(doc.referenceTargetsOf(sale), {client.id: 'client'});
    final created = DomainModelAiAgent.applyPatch(doc.objectFor(sale), {
      'attributes': [
        {'name': 'montant', 'type': 'number', 'required': true},
        {
          'name': 'acheteur',
          'type': 'reference',
          'referenceObjectId': 'Client',
        },
      ],
    }, referenceTargets: doc.referenceTargetsOf(sale));
    expect(created.summary, 'sales (+2 attribut(s))');
    expect(created.object.attributes.last.referenceObjectId, client.id);
    final merged = DomainModelAiAgent.applyPatch(created.object, {
      'attributes': [
        {'name': 'montant', 'type': 'integer'},
      ],
      'removeAttributes': ['ACHETEUR'],
    }, referenceTargets: doc.referenceTargetsOf(sale));
    expect(merged.summary, 'sales (1 mis à jour, -1 supprimé(s))');
    expect(
      merged.object.attributes.single.id,
      created.object.attributes.first.id,
    );
    expect(merged.object.attributes.single.type, BusinessAttributeType.integer);
    expect(
      () => DomainModelAiAgent.applyPatch(created.object, {
        'attributes': [
          {'name': 'x', 'type': 'reference', 'referenceObjectId': 'inconnu'},
        ],
      }, referenceTargets: doc.referenceTargetsOf(sale)),
      throwsFormatException,
    );

    final withModel = doc.withModel(
      sale.id,
      object: created.object,
      chat: [
        SpecChatMessage(
          id: 'm1',
          isUser: true,
          text: 'Ajoute le montant',
          attachments: [
            VibeChatAttachment(
              name: 'note.txt',
              mimeType: 'text/plain',
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ],
        ),
      ],
    );
    // Coupé, enregistré puis recollé : l'objet et le chat reviennent avec l'ID.
    final cut = DomainContracts.fromJson(
      jsonDecode(
        jsonEncode(withModel.patch('models:\n  client: part\n').toJson()),
      ),
    );
    final pasted = cut.patch('models:\n  client: part\n  sales: model\n');
    expect(
      pasted.objectFor(pasted.entryById(sale.id)!).attributes,
      hasLength(2),
    );
    final restoredChat = pasted.chats[sale.id]!.single;
    expect(restoredChat.text, 'Ajoute le montant');
    expect(restoredChat.attachments.single.name, 'note.txt');
    expect(restoredChat.attachments.single.bytes, isEmpty);
    expect(
      () => doc.withModel('absent', chat: const []),
      throwsFormatException,
    );
  });

  test('Le DSL accepte les onze types et ne migre que les valeurs stockées', () {
    const types = [
      'model',
      'part',
      'component',
      'createxdto',
      'updatexdto',
      'xresponsedto',
      'xlistitemdto',
      'xquerydto',
      'eventxpayloaddto',
      'eventxenvelopedto',
      'flatfile',
    ];
    final source =
        'contracts:\n${types.map((t) => '  entry_$t: $t').join('\n')}';
    expect(
      DomainContracts.parse(source).groups.single.children.map((n) => n.type),
      types,
    );
    const legacy =
        'dto:\n  XResponseDto: XResponseDto # XResponseDto\n  event: eventXEnvelopeDto\n';
    expect(() => DomainContracts.parse(legacy), throwsFormatException);
    final restored = DomainContracts.fromJson({
      'source': legacy,
      'details': <String, dynamic>{},
    });
    expect(
      restored.source,
      'dto:\n  XResponseDto: xresponsedto # XResponseDto\n  event: eventxenvelopedto\n',
    );
    // Les anciens catalogues indexaient les métadonnées par chemin.
    final indexedByPath = DomainContracts.fromJson({
      'source': 'models:\n  sales: model\n',
      'details': {'models.sales': ContractDetails(title: 'Ventes').toJson()},
    });
    final sale = indexedByPath.groups.single.children.single;
    expect(indexedByPath.details[sale.id]?.title, 'Ventes');
  });

  test('DomainCatalogStore persiste et relit un catalogue valide', () async {
    final directory = await Directory.systemTemp.createTemp('domain_catalog_');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final store = DomainCatalogStore(directory);
    final catalog = DomainCatalog(
      domains: const [
        FunctionalDomain(
          id: 'domain_1',
          domainCode: 'billing',
          name: 'Billing',
        ),
      ],
      auditLog: [
        AuditLogEntry(
          id: 'audit_1',
          recordedAt: DateTime.utc(2026, 1, 1),
          actorUsername: 'test-user',
          domainId: 'domain_1',
          actionType: DomainAuditAction.create,
          details: 'Domaine créé.',
        ),
      ],
    );

    await store.save(catalog);

    final restored = await store.load();
    expect(restored.domains.single.domainCode, 'billing');
    expect(await store.catalogFile.exists(), isTrue);

    expect(store.save(DomainCatalog.empty), throwsStateError);
  });

  test('DomainEnvExporter trie les clés, échappe les valeurs et exclut les secrets', () {
    const entries = [
      ConfigurationEntry(
        id: 'plain_1',
        domainId: 'domain_1',
        environmentId: 'env_1',
        configKey: 'Z_URL',
        entryType: ConfigurationEntryType.plainVariable,
        plainValue: 'https://example.test/a b',
      ),
      ConfigurationEntry(
        id: 'secret_1',
        domainId: 'domain_1',
        environmentId: 'env_1',
        configKey: 'A_PASSWORD',
        entryType: ConfigurationEntryType.secret,
        encryptedValue: 'v1:ciphertext',
      ),
    ];

    expect(
      DomainEnvExporter.toEnv(entries),
      '# A_PASSWORD=<SECRET_EXCLUDED>\n'
      'Z_URL="https://example.test/a b"\n',
    );
  });

  test('SpecForgeController garde les configurations d’un environnement archivé en lecture seule', () async {
    final controller = SpecForgeController(
      domainCatalogStore: _MemoryDomainCatalogStore(),
    );
    addTearDown(controller.dispose);
    final domain = const FunctionalDomain(
      id: 'domain_1',
      domainCode: 'billing',
      name: 'Billing',
    );
    final environment = const LogicalEnvironment(
      id: 'env_1',
      domainId: 'domain_1',
      environmentCode: 'prod',
      name: 'Production',
    );
    final entry = const ConfigurationEntry(
      id: 'config_1',
      domainId: 'domain_1',
      environmentId: 'env_1',
      configKey: 'LOG_LEVEL',
      entryType: ConfigurationEntryType.plainVariable,
      plainValue: 'info',
    );
    await controller.updateDomainCatalog(
      DomainCatalog(
        domains: [domain],
        environments: [environment],
        configurationEntries: [entry],
      ),
    );
    await controller.updateDomainCatalog(
      controller.domainCatalog.copyWith(
        environments: [
          environment.copyWith(status: LogicalEnvironmentStatus.archived),
        ],
      ),
    );

    expect(
      controller.updateDomainCatalog(
        controller.domainCatalog.copyWith(configurationEntries: const []),
      ),
      throwsStateError,
    );
  });
}
