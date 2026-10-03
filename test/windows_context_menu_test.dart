import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/models/shell_menu_item.dart';
import 'package:surf_file/services/windows_context_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(WindowsContextMenu.channel, null);
  });

  test('parses labels, states, separators and submenu references', () {
    final item = ShellMenuItem.fromNative({
      'id': 42,
      'label': 'Ouvrir avec',
      'verb': 'openas',
      'enabled': false,
      'checked': true,
      'default': true,
      'nativeOnly': true,
      'submenu': 3,
    });
    expect(item.id, 42);
    expect(item.label, 'Ouvrir avec');
    expect(item.verb, 'openas');
    expect(item.enabled, isFalse);
    expect(item.checked, isTrue);
    expect(item.isDefault, isTrue);
    expect(item.nativeOnly, isTrue);
    expect(item.submenu, 3);
    expect(
        ShellMenuItem.fromNative({
          'id': 0,
          'label': '',
          'separator': true,
        }).separator,
        isTrue);
  });

  test('rejects invalid native command data', () {
    for (final value in [
      null,
      {'id': '42', 'label': 'Ouvrir'},
      {'id': 42, 'label': 'Ouvrir', 'enabled': 'yes'},
      {'id': 42, 'label': 'Ouvrir', 'submenu': '3'},
    ]) {
      expect(() => ShellMenuItem.fromNative(value),
          throwsA(isA<PlatformException>()));
    }
  });

  test('keeps the same native session for submenus and commands', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(WindowsContextMenu.channel,
        (call) async {
      calls.add(call);
      switch (call.method) {
        case 'open':
          return {
            'session': 17,
            'items': [
              {'id': 5, 'label': 'Ouvrir avec', 'submenu': 1},
            ],
          };
        case 'submenu':
          return [
            {'id': 12, 'label': 'Bloc-notes', 'verb': 'open'},
          ];
        default:
          return null;
      }
    });
    final menu = await WindowsContextMenu.open('D:\\Images\\été.txt');
    final items = await menu.submenu(1);
    expect(items.single.id, 12);
    await menu.invoke(items.single.id);
    await menu.rename(9, 'nouveau nom.txt');
    await menu.close();
    expect(calls.map((call) => call.method),
        ['open', 'submenu', 'invoke', 'rename', 'close']);
    expect(calls.first.arguments, {'path': 'D:\\Images\\été.txt'});
    expect(calls[1].arguments, {'session': 17, 'submenu': 1});
    expect(calls[2].arguments, {'session': 17, 'id': 12});
    expect(calls[3].arguments,
        {'session': 17, 'id': 9, 'name': 'nouveau nom.txt'});
    expect(calls.last.arguments, {'session': 17});
  });

  test('releases the native session if menu decoding fails', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(WindowsContextMenu.channel,
        (call) async {
      calls.add(call.method);
      if (call.method == 'open') {
        return {'session': 9, 'items': 'invalid'};
      }
      return null;
    });
    await expectLater(WindowsContextMenu.open('C:\\example.txt'),
        throwsA(isA<PlatformException>()));
    expect(calls, ['open', 'close']);
  });

  test('native menu cancellation does not produce a command', () async {
    messenger.setMockMethodCallHandler(WindowsContextMenu.channel,
        (call) async {
      if (call.method == 'open') return {'session': 1, 'items': []};
      return null;
    });
    final menu = await WindowsContextMenu.open('C:\\example.txt');
    expect(await menu.showNative(), isNull);
    await menu.close();
  });

  test('surfaces command execution errors', () async {
    messenger.setMockMethodCallHandler(WindowsContextMenu.channel,
        (call) async {
      if (call.method == 'open') return {'session': 1, 'items': []};
      throw PlatformException(
          code: 'shell_menu_error', message: 'Access denied');
    });
    final menu = await WindowsContextMenu.open('C:\\example.txt');
    await expectLater(menu.invoke(42), throwsA(isA<PlatformException>()));
  });
}
