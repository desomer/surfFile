import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:surf_file/widgets/explorer_breadcrumbs.dart';
import 'package:surf_file/widgets/explorer_toolbar.dart';

void main() {
  for (final width in [320.0, 600.0, 1100.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('toolbar retains actions at $width in $brightness',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = ValueNotifier(const Appearance());
        addTearDown(controller.dispose);
        final actions = <String>[];
        String? query;
        await tester.pumpWidget(AppearanceScope(
          controller: controller,
          child: MaterialApp(
            theme: controller.value.theme(brightness),
            home: Scaffold(
              body: ExplorerToolbar(
                canGoBack: true,
                canGoForward: true,
                canGoUp: true,
                onBack: () => actions.add('back'),
                onForward: () => actions.add('forward'),
                onUp: () => actions.add('up'),
                onRefresh: () => actions.add('refresh'),
                onCreateFolder: () => actions.add('create'),
                onSearchChanged: (value) => query = value,
              ),
            ),
          ),
        ));
        for (final tooltip in [
          'Retour',
          'Suivant',
          'Dossier parent',
          'Actualiser',
        ]) {
          await tester.tap(find.byTooltip(tooltip));
        }
        await tester.tap(width < 660
            ? find.byTooltip('Nouveau dossier')
            : find.text('Nouveau dossier'));
        await tester.enterText(find.byType(TextField), 'documents');
        expect(query, 'documents');
        expect(actions, ['back', 'forward', 'up', 'refresh', 'create']);
        expect(find.byTooltip('Paramètres d’apparence'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('unavailable navigation remains disabled', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExplorerToolbar(
          canGoBack: false,
          canGoUp: false,
          onBack: () => fail('Back must be disabled'),
          onUp: () => fail('Parent must be disabled'),
          onRefresh: () {},
          onCreateFolder: () {},
          onSearchChanged: (_) {},
        ),
      ),
    ));
    for (final tooltip in ['Retour', 'Suivant', 'Dossier parent']) {
      expect(
          tester
              .widget<IconButton>(find.byWidgetPredicate((widget) =>
                  widget is IconButton && widget.tooltip == tooltip))
              .onPressed,
          isNull);
    }
  });

  testWidgets('breadcrumbs highlight current folder without navigating',
      (tester) async {
    String? destination;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExplorerBreadcrumbs(
          path: 'C:\\Users\\Documents',
          onNavigate: (value) => destination = value,
        ),
      ),
    ));
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
    await tester.tap(find.text('Documents'));
    expect(destination, isNull);
    await tester.tap(find.text('Users'));
    expect(destination, 'C:\\Users');
    expect(tester.takeException(), isNull);
  });
}
