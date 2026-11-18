import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  setUp(() {
    debugEntries.clear();
  });

  tearDown(() {
    debugEntries.clear();
  });

  test('saveLog et saveError enregistrent les entrées typées', () {
    saveLog('premier log');
    final trace = StackTrace.fromString('#0 main (file.dart:1:1)');
    saveError('[DART ERROR] boom', trace);

    expect(debugEntries, hasLength(2));
    expect(debugEntries[0].type, DebugEntryType.log);
    expect(debugEntries[0].message, 'premier log');
    expect(debugEntries[0].stackTrace, isNull);

    expect(debugEntries[1].type, DebugEntryType.error);
    expect(debugEntries[1].message, '[DART ERROR] boom');
    expect(debugEntries[1].stackTrace, trace.toString());
  });

  test('saveLog et saveError plafonnent debugEntries à 1000 entrées', () {
    for (var i = 0; i < 1005; i++) {
      saveLog('ligne $i');
    }
    expect(debugEntries, hasLength(1000));
    expect(debugEntries.first.message, 'ligne 5');
    expect(debugEntries.last.message, 'ligne 1004');

    saveError('erreur finale', null);
    expect(debugEntries, hasLength(1000));
    expect(debugEntries.first.message, 'ligne 6');
    expect(debugEntries.last.type, DebugEntryType.error);
    expect(debugEntries.last.message, 'erreur finale');
  });
}
