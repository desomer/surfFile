import 'dart:io';

import 'package:super_backend/super_backend.dart';
import 'package:test/test.dart';

void main() {
  test('SqliteCollectionStore persiste les entités JSON sur disque après réouverture', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'super_backend_disk_',
    );
    final dbPath =
        '${tempDir.path}${Platform.pathSeparator}nested${Platform.pathSeparator}data.db';

    try {
      final firstBackend = SuperBackend(store: SqliteCollectionStore(dbPath));
      await firstBackend.init();
      await firstBackend.create('invoices', {
        'number': 'INV-001',
        'amount': 1250.5,
        'paid': false,
      }, id: 'inv-1');
      await firstBackend.create('invoices', {
        'number': 'INV-002',
        'amount': 400.0,
        'paid': true,
      }, id: 'inv-2');
      await firstBackend.close();

      final secondBackend = SuperBackend(store: SqliteCollectionStore(dbPath));
      await secondBackend.init();
      expect(await secondBackend.count('invoices'), 2);

      final inv1 = await secondBackend.read('invoices', 'inv-1');
      expect(inv1['number'], 'INV-001');
      expect(inv1['amount'], 1250.5);

      await secondBackend.update('invoices', 'inv-1', {
        'paid': true,
      }, merge: true);
      final paid = await secondBackend.search(
        'invoices',
        parameters: {'paid': true, 'sort': 'number'},
      );
      expect(paid.total, 2);
      expect(paid.items.map((e) => e['id']).toList(), ['inv-1', 'inv-2']);

      await secondBackend.close();
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
