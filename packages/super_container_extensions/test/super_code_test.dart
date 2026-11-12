import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart' as flutter_material;
import 'package:flutter_localizations/flutter_localizations.dart' as flutter_localizations;
import 'package:flutter_code_editor/flutter_code_editor.dart';
// ignore: implementation_imports
import 'package:flutter_code_editor/src/code_field/actions/tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/languages/javascript.dart' as javascript;
import 'package:highlight/languages/yaml.dart' as yaml;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_extensions/super_container_extensions.dart';
import 'package:super_container_layout/super_container_layout.dart';

void main() {
  late Directory directory;
  late JsonRepositoryStore store;
  late String repository;

  setUp(() async {
    ensureSuperContainerExtensionCodecsRegistered();
    directory = await Directory.systemTemp.createTemp('super-code-test-');
    store = JsonRepositoryStore(directory);
    await store.create('Scripts');
    repository = await store.idOf('Scripts');
    await store.save(
      'Scripts',
      jsonEncode({
        'source': 'name: demo\nvalue: 42',
        'count': 42,
        'scripts': [
          {'source': 'const first = 1;'},
          {'source': 'const second = 2;'},
        ],
      }),
      expectedText: await store.read('Scripts'),
    );
  });

  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> real(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      await action();
      for (var i = 0; i < 8; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    SuperCodeConfig config, {
    JsonListScope? scope,
  }) => real(tester, () async {
    final code = SuperCode(id: 'editor', config: config);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...flutter_localizations.GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: JsonRepositoryScope(
            store: store,
            child: scope == null
                ? code
                : JsonListScope(
                    repositoryId: scope.repositoryId,
                    indices: scope.indices,
                    placeholder: scope.placeholder,
                    child: code,
                  ),
          ),
        ),
      ),
    );
  });

  CodeEditorState editor(WidgetTester tester) =>
      tester.state(find.byType(CodeEditor));

  test('codecs, compact JSON, patches and reference tracking', () {
    final config = SuperCodeConfig(
      binding: JsonTextBinding(repositoryId: repository, path: 'source'),
      mode: SuperCodeMode.javascript,
      readOnly: true,
    );
    expect(ComponentConfig.fromJson(config.toTypedJson()), config);
    expect(ComponentConfig.fromJson(config.toTypedCompactJson()), config);
    expect(config.referencedBindings, [config.binding]);
    final withError = config.copyWith(
      errorBinding: JsonTextBinding(repositoryId: repository, path: 'error'),
    );
    expect(ComponentConfig.fromJson(withError.toTypedJson()), withError);
    expect(ComponentConfig.fromJson(withError.toTypedCompactJson()), withError);
    expect(withError.referencedBindings, [
      withError.binding,
      withError.errorBinding,
    ]);
    expect(withError.copyWith(clearErrorBinding: true), config);
    expect(
      config.patchFromJson({'readOnly': false}),
      config.copyWith(readOnly: false),
    );
    expect(config.patchFromJson({'binding': null}).binding, isNull);
    expect(config.copyWith(clearBinding: true).binding, isNull);
    expect(const SuperCodeConfig().toTypedCompactJson(), {'type': 'code'});
    expect(
      () => SuperCodeConfig.fromJson({'mode': 'python'}),
      throwsFormatException,
    );
    expect(
      () => SuperCodeConfig.fromJson({'readOnly': 'true'}),
      throwsFormatException,
    );
    expect(
      () => config.patchFromJson({'unknown': true}),
      throwsFormatException,
    );
    final registry = Registry()
      ..bootstrap()
      ..registerAllExtensions();
    expect(registry.registry['Code'], isNotNull);
    codeAddConfigurator.applyDraft(registry, 'editor', config);
    expect(registry.codeController('editor').value, config);
  });

  test('style codecs, validation, compact JSON and partial patches', () {
    const defaultStyle = SuperCodeStyle();
    expect(defaultStyle.toCompactJson(), isEmpty);
    expect(SuperCodeStyle.fromJson(const {}), defaultStyle);

    const customStyle = SuperCodeStyle(
      theme: SuperCodeTheme.dracula,
      fontSize: 18.0,
      lineHeight: 1.8,
      fontFamily: 'Fira Code',
      showLineNumbers: false,
      showFoldingHandles: false,
      transparentBackground: true,
    );
    expect(SuperCodeStyle.fromJson(customStyle.toJson()), customStyle);
    expect(SuperCodeStyle.fromJson(customStyle.toCompactJson()), customStyle);
    expect(customStyle.theme.highlightTheme, isNotEmpty);
    expect(customStyle.theme.isDark, isTrue);

    // Invariant validation
    expect(
      () => const SuperCodeStyle(fontSize: 4.0).validate(),
      throwsFormatException,
    );
    expect(
      () => const SuperCodeStyle(fontSize: 60.0).validate(),
      throwsFormatException,
    );
    expect(
      () => const SuperCodeStyle(lineHeight: 0.5).validate(),
      throwsFormatException,
    );
    expect(
      () => const SuperCodeStyle(fontFamily: '   ').validate(),
      throwsFormatException,
    );
    expect(
      () => SuperCodeStyle.fromJson({'theme': 'unknown'}),
      throwsFormatException,
    );

    // SuperCodeConfig with style
    final config = SuperCodeConfig(
      mode: SuperCodeMode.javascript,
      style: customStyle,
    );
    expect(ComponentConfig.fromJson(config.toTypedJson()), config);
    expect(ComponentConfig.fromJson(config.toTypedCompactJson()), config);

    // PatchFromJson with nested style
    final patched = config.patchFromJson({
      'style': {'fontSize': 20.0, 'theme': 'nord'},
    });
    expect(patched.style.fontSize, 20.0);
    expect(patched.style.theme, SuperCodeTheme.nord);
    expect(patched.style.fontFamily, 'Fira Code');
    expect(patched.style.transparentBackground, isTrue);

    // Dart codegen
    final context = DartCodegenContext(
      appearance: Appearance(),
      registry: Registry(),
    );
    final generated = SuperCodeDartGenerator.formatConfig(context, config);
    expect(generated, contains('SuperCodeTheme.dracula'));
    expect(generated, contains('fontSize: 18.0'));
  });

  testWidgets(
    'loads, saves raw code, switches language and reloads external edits',
    (tester) async {
      final binding = JsonTextBinding(repositoryId: repository, path: 'source');
      await mount(tester, SuperCodeConfig(binding: binding));
      expect(editor(tester).controller.fullText, 'name: demo\nvalue: 42');
      expect(editor(tester).controller.language, same(yaml.yaml));

      await real(tester, () async {
        editor(tester).controller.fullText = 'const answer = 42;\n// not YAML';
        await store.flushBindings();
      });
      expect(
        (await store.readAttribute(binding)).value,
        'const answer = 42;\n// not YAML',
      );

      await mount(
        tester,
        SuperCodeConfig(binding: binding, mode: SuperCodeMode.javascript),
      );
      expect(editor(tester).controller.language, same(javascript.javascript));
      expect(
        editor(tester).controller.fullText,
        'const answer = 42;\n// not YAML',
      );
      await real(tester, () async {
        await store.writeAttribute(
          binding,
          'const updated = true;',
          expectedValue: 'const answer = 42;\n// not YAML',
        );
      });
      expect(editor(tester).controller.fullText, 'const updated = true;');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('master-detail switches targets and flushes the previous draft', (
    tester,
  ) async {
    final binding = JsonTextBinding(
      repositoryId: repository,
      path: 'scripts[?].source',
    );
    await mount(
      tester,
      SuperCodeConfig(binding: binding, mode: SuperCodeMode.javascript),
    );
    expect(editor(tester).controller.fullText, isEmpty);
    expect(tester.widget<CodeField>(find.byType(CodeField)).readOnly, isTrue);
    final selection = store.bindingOf(repository).array('scripts');
    await real(tester, () async => selection.select([], 0));
    expect(editor(tester).controller.fullText, 'const first = 1;');
    await real(tester, () async {
      editor(tester).controller.fullText = 'const changed = 3;';
      selection.select([], 1);
    });
    expect(editor(tester).controller.fullText, 'const second = 2;');
    expect(
      (await store.readAttribute(
        JsonTextBinding(repositoryId: repository, path: 'scripts[0].source'),
      )).value,
      'const changed = 3;',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inherits row binding, and placeholder neither reads nor writes',
    (tester) async {
      const config = SuperCodeConfig(
        binding: JsonTextBinding(path: 'scripts[?].source'),
      );
      await mount(
        tester,
        config,
        scope: JsonListScope(
          repositoryId: repository,
          indices: const [1],
          child: const SizedBox(),
        ),
      );
      expect(editor(tester).controller.fullText, 'const second = 2;');
      await mount(
        tester,
        config,
        scope: JsonListScope(
          repositoryId: repository,
          indices: const [1],
          placeholder: true,
          child: const SizedBox(),
        ),
      );
      expect(editor(tester).controller.fullText, isEmpty);
      expect(tester.widget<CodeField>(find.byType(CodeField)).readOnly, isTrue);
    },
  );

  testWidgets('read-only blocks paste, cut and indentation actions', (
    tester,
  ) async {
    final binding = JsonTextBinding(repositoryId: repository, path: 'source');
    await mount(tester, SuperCodeConfig(binding: binding, readOnly: true));
    final state = editor(tester);
    state.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );
    Actions.of(tester.element(find.byType(CodeField))).invokeAction(
      state.controller.actions[PasteTextIntent]!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    Actions.of(tester.element(find.byType(CodeField))).invokeAction(
      state.controller.actions[CopySelectionTextIntent]!,
      CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
    );
    TabKeyIndentSelection(
      controller: state.controller,
      isReadOnly: () => true,
    ).invoke(const TabKeyIntent());
    await real(tester, () async => store.flushBindings());
    expect(state.controller.fullText, 'name: demo\nvalue: 42');
    expect((await store.readAttribute(binding)).value, 'name: demo\nvalue: 42');
  });

  testWidgets('invalid attribute is reported without overwriting it', (
    tester,
  ) async {
    await mount(
      tester,
      SuperCodeConfig(
        binding: JsonTextBinding(repositoryId: repository, path: 'count'),
      ),
    );
    expect(
      find.text('L’attribut lié doit être une chaîne de texte.'),
      findsOneWidget,
    );
    expect(tester.widget<CodeField>(find.byType(CodeField)).readOnly, isTrue);
    expect(
      (await store.readAttribute(
        JsonTextBinding(repositoryId: repository, path: 'count'),
      )).value,
      42,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('error binding displays a repository attribute read-only', (
    tester,
  ) async {
    final errorPath = JsonTextBinding(repositoryId: repository, path: 'error');
    await real(
      tester,
      () => store.writeAttribute(
        errorPath,
        'Ligne 2 invalide',
        expectedValue: null,
      ),
    );
    await mount(
      tester,
      SuperCodeConfig(
        binding: JsonTextBinding(repositoryId: repository, path: 'source'),
        errorBinding: errorPath,
      ),
    );
    expect(find.text('Ligne 2 invalide'), findsOneWidget);

    await real(
      tester,
      () => store.writeAttribute(
        errorPath,
        '',
        expectedValue: 'Ligne 2 invalide',
      ),
    );
    expect(find.text('Ligne 2 invalide'), findsNothing);
    expect((await store.readAttribute(errorPath)).value, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('right click opens configuration and applies language', (
    tester,
  ) async {
    SuperCodeConfig? saved;
    final initial = SuperCodeConfig(
      binding: JsonTextBinding(repositoryId: repository, path: 'source'),
    );
    await real(tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: [
            ...GlobalMaterialLocalizations.delegates,
            ...flutter_localizations.GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: JsonRepositoryScope(
              store: store,
              child: SuperCode(
                id: 'context-code',
                config: initial,
                onConfigChanged: (value) => saved = value,
              ),
            ),
          ),
        ),
      );
    });
    await tester.tap(find.byType(CodeField), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('style-menu-Code'));
    expect(menu, findsOneWidget);
    await real(tester, () async => tester.tap(menu));
    expect(find.byKey(const ValueKey('super-code-editor')), findsOneWidget);
    await tester.tap(find.text('JavaScript'));
    await tester.pumpAndSettle();
    await real(
      tester,
      () async => tester.tap(find.byKey(const ValueKey('super-code-apply'))),
    );
    expect(saved, initial.copyWith(mode: SuperCodeMode.javascript));
    expect(editor(tester).controller.language, same(javascript.javascript));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog allows changing style and applies theme and options', (
    tester,
  ) async {
    SuperCodeConfig? saved;
    const initial = SuperCodeConfig();
    await real(tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: [
            ...GlobalMaterialLocalizations.delegates,
            ...flutter_localizations.GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: JsonRepositoryScope(
              store: store,
              child: SuperCode(
                id: 'style-code',
                config: initial,
                onConfigChanged: (value) => saved = value,
              ),
            ),
          ),
        ),
      );
    });
    await tester.tap(find.byType(CodeField), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await real(
      tester,
      () async => tester.tap(find.byKey(const ValueKey('style-menu-Code'))),
    );
    expect(find.byKey(const ValueKey('super-code-editor')), findsOneWidget);

    // Toggle line numbers and transparent background switches
    await tester.tap(find.byKey(const ValueKey('super-code-line-numbers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-code-transparent-bg')));
    await tester.pumpAndSettle();

    await real(
      tester,
      () async => tester.tap(find.byKey(const ValueKey('super-code-apply'))),
    );
    expect(saved?.style.showLineNumbers, isFalse);
    expect(saved?.style.transparentBackground, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection toolbar resolves Flutter localizations in app host', (
    tester,
  ) async {
    await real(tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // ignore: deprecated_member_use
          builder: (context, child) => MaterialUiCompatibilityBridge(
            child: child!,
          ),
          home: Scaffold(
            body: JsonRepositoryScope(
              store: store,
              child: SuperCode(
                id: 'toolbar-code',
                config: SuperCodeConfig(
                  binding: JsonTextBinding(
                    repositoryId: repository,
                    path: 'source',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
    await tester.pumpAndSettle();
    final editable = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    editable.requestKeyboard();
    await tester.pump();
    editable.userUpdateTextEditingValue(
      editable.textEditingValue.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 4),
      ),
      SelectionChangedCause.longPress,
    );
    expect(editable.showToolbar(), isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byType(flutter_material.AdaptiveTextSelectionToolbar),
      findsOneWidget,
    );
  });

  testWidgets('large documents use plain text and remain editable', (
    tester,
  ) async {
    final binding = JsonTextBinding(repositoryId: repository, path: 'source');
    final source = List.filled(6000, '// value').join('\n');
    expect(source.length, greaterThan(50000));
    await real(tester, () async {
      await store.writeAttribute(
        binding,
        source,
        expectedValue: 'name: demo\nvalue: 42',
      );
    });
    await mount(
      tester,
      SuperCodeConfig(binding: binding, mode: SuperCodeMode.javascript),
    );
    expect(find.byType(CodeField), findsNothing);
    final field = tester.widget<flutter_material.TextField>(
      find.byType(flutter_material.TextField),
    );
    expect(field.controller!.text, source);
    expect(field.readOnly, isFalse);
    expect(
      find.text('Document volumineux : coloration syntaxique desactivee.'),
      findsOneWidget,
    );
    await real(tester, () async {
      field.onChanged!('$source\n// saved');
      await store.flushBindings();
    });
    expect((await store.readAttribute(binding)).value, '$source\n// saved');
    expect(tester.takeException(), isNull);
  });

  testWidgets('applies customized style and theme to CodeField and CodeTheme', (
    tester,
  ) async {
    const customStyle = SuperCodeStyle(
      theme: SuperCodeTheme.atomOneLight,
      fontSize: 20.0,
      showLineNumbers: false,
      transparentBackground: true,
    );
    await mount(
      tester,
      SuperCodeConfig(
        binding: JsonTextBinding(repositoryId: repository, path: 'source'),
        style: customStyle,
      ),
    );

    final codeField = tester.widget<CodeField>(find.byType(CodeField));
    expect(codeField.textStyle?.fontSize, 20.0);
    expect(codeField.gutterStyle.showLineNumbers, isFalse);
    expect(codeField.background, flutter_material.Colors.transparent);

    final codeTheme = tester.widget<CodeTheme>(find.byType(CodeTheme));
    expect(
      codeTheme.data?.styles['root']?.backgroundColor,
      flutter_material.Colors.transparent,
    );
  });
}
