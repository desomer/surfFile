import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:surf_file/services/appearance_transfer.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/widgets/dialogs/appearance_transfer_dialog.dart';
import 'package:super_container_layout/widgets/super_container.dart';

import 'package:super_container_layout/widgets/style_edit_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final custom = Appearance(
    accent: const Color(0xFF00796B),
    fontSize: 15,
    layouts: {
      'explorer': SurfFileAppearanceDefaults.defaultExplorerLayout.withSwap(
        SuperLayoutZone.west,
      ),
    },
  );
  const both = {TransferGroup.styles, TransferGroup.layouts};

  Future<ValueNotifier<Appearance>> pumpDialog(
    WidgetTester tester, {
    Appearance? appearance,
  }) async {
    final controller = ValueNotifier(appearance ?? Appearance());
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppearanceTransferDialog(controller: controller)),
      ),
    );
    return controller;
  }

  // Les E/S de fichier avancent par étapes : on alterne attente réelle et pump.
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
  }

  String exportText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('transfer-export-text')))
      .controller!
      .text;

  Future<void> openImport(WidgetTester tester) async {
    await tester.tap(find.text('Importer').first);
    await tester.pumpAndSettle();
  }

  Future<void> typeImport(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('transfer-import-text')),
      text,
    );
    await tester.pump();
  }

  bool selected(WidgetTester tester, String key) =>
      tester.widget<FilterChip>(find.byKey(ValueKey(key))).selected;

  testWidgets('export contains both groups by default and follows the chips', (
    tester,
  ) async {
    await pumpDialog(tester, appearance: custom);
    var json = jsonDecode(exportText(tester)) as Map;
    expect(json['groups'], ['styles', 'layouts']);

    await tester.tap(find.byKey(const ValueKey('transfer-export-styles')));
    await tester.pump();
    json = jsonDecode(exportText(tester)) as Map;
    expect(json['groups'], ['layouts']);
    expect((json['data'] as Map).keys.toSet(), AppearanceTransfer.layoutKeys);

    // Le dernier groupe ne peut pas être décoché.
    await tester.tap(find.byKey(const ValueKey('transfer-export-layouts')));
    await tester.pump();
    expect(selected(tester, 'transfer-export-layouts'), isTrue);

    await tester.tap(find.byKey(const ValueKey('transfer-export-styles')));
    await tester.tap(find.byKey(const ValueKey('transfer-export-layouts')));
    await tester.pump();
    json = jsonDecode(exportText(tester)) as Map;
    expect(json['groups'], ['styles']);
    expect((json['data'] as Map).containsKey('explorerLayout'), isFalse);
  });

  testWidgets('copy puts the export in the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpDialog(tester, appearance: custom);
    await tester.tap(find.byKey(const ValueKey('transfer-copy')));
    await tester.pumpAndSettle();
    expect(copied, exportText(tester));
    expect(find.byKey(const ValueKey('transfer-status')), findsOneWidget);
  });

  testWidgets('import applies only the checked groups', (tester) async {
    final controller = await pumpDialog(tester);
    await openImport(tester);
    expect(find.byKey(const ValueKey('transfer-apply')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('transfer-apply')))
          .onPressed,
      isNull,
    );

    await typeImport(tester, AppearanceTransfer.export(custom, both));
    expect(selected(tester, 'transfer-import-styles'), isTrue);
    expect(selected(tester, 'transfer-import-layouts'), isTrue);

    await tester.tap(find.byKey(const ValueKey('transfer-import-styles')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('transfer-apply')));
    await tester.pumpAndSettle();

    expect(controller.value.layout('explorer'), custom.layout('explorer'));
    expect(controller.value.accent, Appearance().accent);
    expect(find.byKey(const ValueKey('appearance-transfer')), findsNothing);
  });

  testWidgets('a group missing from the text cannot be checked', (
    tester,
  ) async {
    final controller = await pumpDialog(tester);
    await openImport(tester);
    await typeImport(
      tester,
      AppearanceTransfer.export(custom, {TransferGroup.styles}),
    );
    expect(selected(tester, 'transfer-import-styles'), isTrue);
    expect(selected(tester, 'transfer-import-layouts'), isFalse);
    await tester.tap(find.byKey(const ValueKey('transfer-import-layouts')));
    await tester.pump();
    expect(selected(tester, 'transfer-import-layouts'), isFalse);

    await tester.tap(find.byKey(const ValueKey('transfer-apply')));
    await tester.pumpAndSettle();
    expect(controller.value.accent, custom.accent);
    expect(controller.value.layout('explorer'), SurfFileAppearanceDefaults.defaultExplorerLayout);
  });

  testWidgets('an invalid text shows the reason and imports nothing', (
    tester,
  ) async {
    final controller = await pumpDialog(tester);
    await openImport(tester);
    await typeImport(tester, 'ceci n\'est pas du json');
    expect(find.text('Le texte n’est pas un JSON valide.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('transfer-apply')))
          .onPressed,
      isNull,
    );

    // Une valeur incorrecte est refusée à l'application, sans rien changer.
    await typeImport(
      tester,
      jsonEncode({
        'format': AppearanceTransfer.format,
        'version': 2,
        'groups': ['styles'],
        'data': {'mode': 'sepia'},
      }),
    );
    await tester.tap(find.byKey(const ValueKey('transfer-apply')));
    await tester.pumpAndSettle();
    expect(find.text('Invalid theme or window preferences.'), findsOneWidget);
    expect(controller.value.mode, Appearance().mode);
    expect(find.byKey(const ValueKey('appearance-transfer')), findsOneWidget);
  });

  testWidgets('a file can be written then read back', (tester) async {
    final directory = Directory.systemTemp.createTempSync('surf_file_xfer_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}style.json';
    await pumpDialog(tester, appearance: custom);
    await tester.enterText(find.byKey(const ValueKey('transfer-file')), path);

    await tester.tap(find.byKey(const ValueKey('transfer-save')));
    await settleIo(tester);
    expect(File(path).existsSync(), isTrue);
    expect(File(path).readAsStringSync(), exportText(tester));

    await openImport(tester);
    await tester.tap(find.byKey(const ValueKey('transfer-read')));
    await settleIo(tester);
    expect(selected(tester, 'transfer-import-styles'), isTrue);
    expect(selected(tester, 'transfer-import-layouts'), isTrue);

    // Un fichier absent est signalé sans erreur.
    await tester.enterText(
      find.byKey(const ValueKey('transfer-file')),
      '${directory.path}${Platform.pathSeparator}absent.json',
    );
    await tester.tap(find.byKey(const ValueKey('transfer-read')));
    await settleIo(tester);
    expect(find.textContaining('Lecture impossible'), findsOneWidget);
  });

  testWidgets('the edit-mode banner opens the dialog', (tester) async {
    final controller = ValueNotifier(custom);
    final editMode = ValueNotifier(true);
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(controller.dispose);
    addTearDown(editMode.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppearanceScope(
        controller: controller,
        child: StyleEditScope(
          controller: editMode,
          child: MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) => Stack(
              children: [
                Positioned.fill(child: child!),
                Positioned.fill(
                  child: StyleEditBanner(navigatorKey: navigator),
                ),
              ],
            ),
            home: const Scaffold(),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('appearance-transfer')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-transfer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('appearance-transfer')), findsOneWidget);
    expect(find.byKey(const ValueKey('transfer-export-text')), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('appearance-transfer')), findsNothing);
  });
}
