import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/theme/folder_transition.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import 'package:surf_file/widgets/dialogs/appearance_settings.dart';

void main() {
  testWidgets(
    'settings forward local preferences through nested dialog routes',
    (tester) async {
      final controller = ValueNotifier(defaultSurfFileAppearance());
      final preferences = ValueNotifier(const SurfFilePreferences());
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: AppearanceScope(
            controller: controller,
            preferences: preferences,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => AppearanceSettings.show(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Animation de navigation'));
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButtonFormField<FolderTransition>>(
        find.byKey(const ValueKey('folder-transition-type')),
      );
      dropdown.onChanged!(FolderTransition.slide);
      await tester.pumpAndSettle();
      tester
          .widget<Slider>(
            find.byKey(const ValueKey('Durée de la transition (ms)')),
          )
          .onChanged!(750);
      await tester.pumpAndSettle();
      expect(preferences.value.folderTransition, FolderTransition.slide);
      expect(preferences.value.folderTransitionDuration, 750);
      await tester.tap(find.text('Retour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sombre'));
      await tester.pumpAndSettle();
      expect(controller.value.mode, ThemeMode.dark);
      await tester.tap(find.text('Réinitialiser'));
      await tester.pumpAndSettle();
      expect(controller.value.mode, ThemeMode.light);
      expect(preferences.value.folderTransition, FolderTransition.none);
      expect(preferences.value.folderTransitionDuration, 220);
      expect(tester.takeException(), isNull);
    },
  );
}
