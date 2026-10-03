import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/services/personal_folders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(PersonalFolders.channel, null);
  });

  test('uses redirected Windows folders without modifying their paths',
      () async {
    final folders = {
      for (final name in PersonalFolders.names)
        name: 'C:\\Users\\Test\\OneDrive\\$name',
    };
    folders['Desktop'] = 'D:\\Dossiers personnels\\Bureau';
    messenger.setMockMethodCallHandler(PersonalFolders.channel, (call) async {
      expect(call.method, 'getPersonalFolders');
      return folders;
    });

    expect(await PersonalFolders.resolve('C:\\Users\\Test'), folders);
  }, skip: !Platform.isWindows);

  test('rejects incomplete Windows folder responses', () async {
    messenger.setMockMethodCallHandler(
      PersonalFolders.channel,
      (call) async => {'Desktop': 'D:\\Bureau'},
    );

    await expectLater(
      PersonalFolders.resolve('C:\\Users\\Test'),
      throwsA(isA<PlatformException>()),
    );
  }, skip: !Platform.isWindows);

  test('reports Windows folder resolution failures', () async {
    messenger.setMockMethodCallHandler(PersonalFolders.channel, (call) async {
      throw PlatformException(code: 'personal_folder_unavailable');
    });

    await expectLater(
      PersonalFolders.resolve('C:\\Users\\Test'),
      throwsA(isA<PlatformException>()),
    );
  }, skip: !Platform.isWindows);
}
