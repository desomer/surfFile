import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  setUp(() {
    clearDebugEntries();
  });

  tearDown(() {
    clearDebugEntries();
  });

  test('saveLog et saveError enregistrent les entrées typées', () {
    saveLog('premier log');
    final trace = StackTrace.fromString('#0 main (file.dart:1:1)');
    saveError('[DART ERROR] boom', trace);

    expect(debugEntries, hasLength(2));
    expect(debugEntries[0].type, DebugEntryType.log);
    expect(debugEntries[0].severity, DebugSeverity.info);
    expect(debugEntries[0].message, 'premier log');
    expect(debugEntries[0].stackTrace, isNull);

    expect(debugEntries[1].type, DebugEntryType.error);
    expect(debugEntries[1].severity, DebugSeverity.error);
    expect(debugEntries[1].category, DebugErrorCategory.system);
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

  test('saveError infère catégorie et sévérité pour binding, js, font, saisie et rendu', () {
    saveError('[JS ERROR] ReferenceError: foo is not defined', null);
    saveError('Police indisponible : ComicMissing.', null);
    saveError('[REPOSITORY ERROR] Attribut introuvable', null);
    saveError('JSON invalide : accolade manquante', null);
    saveError('[FLUTTER ERROR] A RenderFlex overflowed by 12 pixels', null);

    expect(debugEntries[0].category, DebugErrorCategory.javascript);
    expect(debugEntries[0].severity, DebugSeverity.critical);

    expect(debugEntries[1].category, DebugErrorCategory.font);
    expect(debugEntries[1].severity, DebugSeverity.warning);

    expect(debugEntries[2].category, DebugErrorCategory.binding);
    expect(debugEntries[2].severity, DebugSeverity.error);

    expect(debugEntries[3].category, DebugErrorCategory.userInput);
    expect(debugEntries[3].severity, DebugSeverity.warning);

    expect(debugEntries[4].category, DebugErrorCategory.rendering);
    expect(debugEntries[4].severity, DebugSeverity.critical);
  });

  test('syncComponentDiagnostic déduplique les reconstructions et réarme après résolution', () {
    final beforeRev = debugEntriesRevision.value;
    VibeDebugCapture.syncComponentDiagnostic(
      componentId: 'title_1',
      sourceKey: 'font',
      active: true,
      category: DebugErrorCategory.font,
      severity: DebugSeverity.warning,
      message: 'Police indisponible : MissingFont.',
      visibleInUi: true,
    );
    // Reconstruction identique : aucun doublon ajouté.
    VibeDebugCapture.syncComponentDiagnostic(
      componentId: 'title_1',
      sourceKey: 'font',
      active: true,
      category: DebugErrorCategory.font,
      severity: DebugSeverity.warning,
      message: 'Police indisponible : MissingFont.',
      visibleInUi: true,
    );
    expect(debugEntries, hasLength(1));
    expect(debugEntries.single.componentId, 'title_1');
    expect(debugEntries.single.visibleInUi, isTrue);
    expect(debugEntriesRevision.value, greaterThan(beforeRev));

    // Résolution puis réapparition : une nouvelle entrée est enregistrée (hors fenêtre 250ms ou message différent).
    VibeDebugCapture.syncComponentDiagnostic(
      componentId: 'title_1',
      sourceKey: 'font',
      active: false,
      category: DebugErrorCategory.font,
      message: null,
    );
    VibeDebugCapture.syncComponentDiagnostic(
      componentId: 'title_1',
      sourceKey: 'font',
      active: true,
      category: DebugErrorCategory.font,
      severity: DebugSeverity.warning,
      message: 'Police indisponible : OtherMissingFont.',
      visibleInUi: true,
    );
    expect(debugEntries, hasLength(2));
  });

  test('shouldTriggerAutoVerify inclut critical/error/warning et exclut userInput/info', () {
    final now = DateTime.now();
    expect(
      VibeDebugCapture.shouldTriggerAutoVerify(
        DebugEntry(
          timestamp: now,
          type: DebugEntryType.error,
          severity: DebugSeverity.critical,
          category: DebugErrorCategory.javascript,
          message: 'JS crash',
        ),
      ),
      isTrue,
    );
    expect(
      VibeDebugCapture.shouldTriggerAutoVerify(
        DebugEntry(
          timestamp: now,
          type: DebugEntryType.error,
          severity: DebugSeverity.warning,
          category: DebugErrorCategory.font,
          message: 'Police manquante',
        ),
      ),
      isTrue,
    );
    expect(
      VibeDebugCapture.shouldTriggerAutoVerify(
        DebugEntry(
          timestamp: now,
          type: DebugEntryType.error,
          severity: DebugSeverity.warning,
          category: DebugErrorCategory.userInput,
          message: 'Email invalide',
        ),
      ),
      isFalse,
    );
    expect(
      VibeDebugCapture.shouldTriggerAutoVerify(
        DebugEntry(
          timestamp: now,
          type: DebugEntryType.log,
          severity: DebugSeverity.info,
          category: DebugErrorCategory.system,
          message: 'Info',
        ),
      ),
      isFalse,
    );
  });
}
