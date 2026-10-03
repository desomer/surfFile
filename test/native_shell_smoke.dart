import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:surf_file/services/windows_context_menu.dart';

// Run with Flutter on Windows, not the mocked flutter_test runner.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('Shell smoke test'))));
  final directory = await Directory.systemTemp.createTemp('surf_file_shell_');
  try {
    final file =
        await File('${directory.path}\\été test.txt').writeAsString('test');
    final menu = await WindowsContextMenu.open(file.path);
    try {
      if (menu.items.isEmpty ||
          !menu.items.any((item) => item.verb.toLowerCase() == 'copy')) {
        throw StateError('The real Windows file menu has no Copy command.');
      }
      for (final item in menu.items) {
        if (item.submenu != null && item.enabled && !item.nativeOnly) {
          await menu.submenu(item.submenu!);
        }
      }
      try {
        await menu.invoke(-1);
        throw StateError('Windows accepted an invalid command.');
      } on PlatformException catch (error) {
        if (error.code != 'invalid_command') rethrow;
      }
      final rename = menu.items.firstWhere((item) => item.verb == 'rename');
      final conflict = await File('${directory.path}\\occupied.txt')
          .writeAsString('keep this content');
      try {
        await menu.rename(rename.id, 'occupied.txt');
        throw StateError('Rename overwrote an existing file.');
      } on PlatformException catch (error) {
        if (error.code != 'shell_menu_error') rethrow;
      }
      if (await conflict.readAsString() != 'keep this content' ||
          !await file.exists()) {
        throw StateError('A failed rename changed the test files.');
      }
      await menu.rename(rename.id, 'renamed.txt');
      if (await file.exists() ||
          await File('${directory.path}\\renamed.txt').readAsString() !=
              'test') {
        throw StateError('The native rename did not preserve the file.');
      }
    } finally {
      await menu.close();
    }
    try {
      await menu.invoke(1);
      throw StateError('Windows accepted a released menu session.');
    } on PlatformException catch (error) {
      if (error.code != 'expired_menu') rethrow;
    }
    final folderMenu = await WindowsContextMenu.open(directory.path);
    try {
      if (folderMenu.items.isEmpty) {
        throw StateError('The real Windows folder menu is empty.');
      }
    } finally {
      await folderMenu.close();
    }
    try {
      await WindowsContextMenu.open('${directory.path}\\missing.txt');
      throw StateError('Windows accepted a nonexistent file.');
    } on PlatformException catch (error) {
      if (error.code != 'shell_menu_error') rethrow;
    }
    stdout.writeln('NATIVE_SHELL_SMOKE_PASSED');
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  } finally {
    await directory.delete(recursive: true);
  }
  exit(exitCode);
}
