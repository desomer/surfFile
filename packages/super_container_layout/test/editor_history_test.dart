import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_layout/widgets/style_edit_banner.dart';

void main() {
  test('undo and redo restore snapshots and discard a stale redo branch', () {
    final appearance = ValueNotifier<Appearance>(Appearance());
    final editMode = ValueNotifier(true);
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: editMode,
    );
    addTearDown(appearance.dispose);
    addTearDown(editMode.dispose);
    addTearDown(history.dispose);

    appearance.value = appearance.value.copyWith(accent: Colors.red);
    expect(history.canUndo, isTrue);
    history.undo();
    expect(appearance.value.accent, const Color(0xFF5268D9));
    expect(history.canRedo, isTrue);

    history.redo();
    expect(appearance.value.accent, Colors.red);
    appearance.value = appearance.value.copyWith(accent: Colors.green);
    expect(history.canRedo, isFalse);
  });

  test('a transaction groups continuous updates into a single undo step', () {
    final appearance = ValueNotifier<Appearance>(Appearance());
    final editMode = ValueNotifier(true);
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: editMode,
    );
    addTearDown(appearance.dispose);
    addTearDown(editMode.dispose);
    addTearDown(history.dispose);

    history.beginTransaction();
    appearance.value = appearance.value.copyWith(backgroundOpacity: .8);
    appearance.value = appearance.value.copyWith(backgroundOpacity: .4);
    history.commitTransaction();

    history.undo();
    expect(appearance.value.backgroundOpacity, 1);
    expect(history.canUndo, isFalse);
    history.redo();
    expect(appearance.value.backgroundOpacity, .4);
  });

  test('changes outside edit mode clear history instead of being captured', () {
    final appearance = ValueNotifier<Appearance>(Appearance());
    final editMode = ValueNotifier(true);
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: editMode,
    );
    addTearDown(appearance.dispose);
    addTearDown(editMode.dispose);
    addTearDown(history.dispose);

    appearance.value = appearance.value.copyWith(accent: Colors.red);
    editMode.value = false;
    appearance.value = appearance.value.copyWith(accent: Colors.green);
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
  });

  testWidgets('the edit banner exposes working undo and redo actions', (
    tester,
  ) async {
    final appearance = ValueNotifier<Appearance>(Appearance());
    final editMode = ValueNotifier(true);
    final history = EditorHistoryController(
      appearance: appearance,
      editMode: editMode,
    );
    addTearDown(appearance.dispose);
    addTearDown(editMode.dispose);
    addTearDown(history.dispose);

    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: EditorHistoryScope(
          controller: history,
          child: StyleEditScope(
            controller: editMode,
            child: MaterialApp(
              builder: (context, child) => Stack(
                children: [
                  child!,
                  const Positioned.fill(child: StyleEditBanner()),
                ],
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => appearance.value = appearance.value
                        .copyWith(accent: Colors.red),
                    child: const Text('Change'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Change'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('style-edit-banner-undo')));
    await tester.pump();
    expect(appearance.value.accent, const Color(0xFF5268D9));

    await tester.tap(find.byKey(const ValueKey('style-edit-banner-redo')));
    await tester.pump();
    expect(appearance.value.accent, Colors.red);
    expect(tester.takeException(), isNull);
  });
}
