import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/ai/call_gemini.dart';

void main() {
  tearDown(() {
    resetGeminiApiKeyCache();
    dotenv.clean();
  });

  test('resolveGeminiApiKey résout la clé depuis un fichier env ou l\'environnement', () async {
    final key = await resolveGeminiApiKey();
    expect(key, isNotEmpty);
    expect(dotenv.isInitialized, isTrue);
    expect(dotenv.env['GEMINI_API_KEY'], equals(key));
  });

  test(
    'discoverGeminiApiKeyForTesting résout la clé depuis --dart-define',
    () async {
      final key = await discoverGeminiApiKeyForTesting(
        environment: const {},
        dartDefineKey: '  define-test-key  ',
        currentDirectoryPath: Directory.systemTemp.path,
      );
      expect(key, equals('define-test-key'));
      expect(dotenv.env['GEMINI_API_KEY'], equals('define-test-key'));
    },
  );

  test('discoverGeminiApiKeyForTesting trouve env à côté de l\'exécutable même hors du dépôt', () async {
    final tempRoot = await Directory.systemTemp.createTemp('gemini_exe_dir_');
    addTearDown(() => tempRoot.delete(recursive: true));

    final cwdDir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}unrelated_cwd',
    )..createSync();
    final releaseDir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}Release',
    )..createSync();
    File('${releaseDir.path}${Platform.pathSeparator}.env').writeAsStringSync(
      'GEMINI_API_KEY=exe-sibling-key\nGEMINI_MODEL=gemini-flash-latest\n',
    );

    final key = await discoverGeminiApiKeyForTesting(
      environment: const {},
      currentDirectoryPath: cwdDir.path,
      executablePath:
          '${releaseDir.path}${Platform.pathSeparator}super_designer.exe',
      isWeb: false,
    );

    expect(key, equals('exe-sibling-key'));
    expect(dotenv.env['GEMINI_API_KEY'], equals('exe-sibling-key'));
    expect(dotenv.env['GEMINI_MODEL'], equals('gemini-flash-latest'));
  });

  test('discoverGeminiApiKeyForTesting remonte depuis l\'exécutable et ignore un env sans clé', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'gemini_exe_ancestors_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    final sep = Platform.pathSeparator;
    final emptyCwd = Directory('${tempRoot.path}${sep}other_cwd')..createSync();
    File('${emptyCwd.path}${sep}env').writeAsStringSync('OTHER_VAR=1\n');

    final packageDir = Directory(
      '${tempRoot.path}${sep}packages${sep}super_designer',
    )..createSync(recursive: true);
    File('${packageDir.path}${sep}env')
        .writeAsStringSync('GEMINI_API_KEY=ancestor-key\n');

    final releaseDir = Directory(
      '${packageDir.path}${sep}build${sep}windows${sep}x64${sep}runner${sep}Release',
    )..createSync(recursive: true);

    final key = await discoverGeminiApiKeyForTesting(
      environment: const {},
      currentDirectoryPath: emptyCwd.path,
      executablePath: '${releaseDir.path}${sep}super_designer.exe',
      isWeb: false,
    );

    expect(key, equals('ancestor-key'));
    expect(dotenv.env['GEMINI_API_KEY'], equals('ancestor-key'));
  });

  test('discoverGeminiApiKeyForTesting cherche aussi dans le dossier utilisateur .super_container_layout', () async {
    final tempRoot = await Directory.systemTemp.createTemp('gemini_home_dir_');
    addTearDown(() => tempRoot.delete(recursive: true));

    final sep = Platform.pathSeparator;
    final cwdDir = Directory('${tempRoot.path}${sep}cwd')..createSync();
    final homeDir = Directory('${tempRoot.path}${sep}home')..createSync();
    final configDir = Directory('${homeDir.path}$sep.super_container_layout')
      ..createSync();
    File('${configDir.path}${sep}env')
        .writeAsStringSync('GEMINI_API_KEY=home-config-key\n');

    final key = await discoverGeminiApiKeyForTesting(
      environment: const {},
      currentDirectoryPath: cwdDir.path,
      executablePath: '${cwdDir.path}${sep}super_designer.exe',
      homeDirectoryPath: homeDir.path,
      isWeb: false,
    );

    expect(key, equals('home-config-key'));
    expect(dotenv.env['GEMINI_API_KEY'], equals('home-config-key'));
  });
}
