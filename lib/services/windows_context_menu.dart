import 'package:flutter/services.dart';

import '../models/shell_menu_item.dart';

class WindowsContextMenu {
  WindowsContextMenu._(this.session, this.items);

  static const channel = MethodChannel('surf_file/context_menu');

  final int session;
  final List<ShellMenuItem> items;

  static List<ShellMenuItem> _parseItems(Object? value) {
    if (value is! List) {
      throw PlatformException(
        code: 'invalid_menu',
        message: 'Windows a renvoyé un menu invalide.',
      );
    }
    return value.map(ShellMenuItem.fromNative).toList();
  }

  static Future<WindowsContextMenu> open(String path) async {
    final response = await channel.invokeMethod<Object?>('open', {
      'path': path,
    });
    if (response is! Map || response['session'] is! int) {
      throw PlatformException(
        code: 'invalid_menu',
        message: 'Windows n’a pas fourni de contexte de menu.',
      );
    }
    final session = response['session'] as int;
    try {
      return WindowsContextMenu._(session, _parseItems(response['items']));
    } on PlatformException {
      await channel.invokeMethod<void>('close', {'session': session});
      rethrow;
    }
  }

  Future<List<ShellMenuItem>> submenu(int id) async {
    return _parseItems(
      await channel.invokeMethod<Object?>('submenu', {
        'session': session,
        'submenu': id,
      }),
    );
  }

  Future<ShellMenuItem?> showNative() async {
    final response = await channel.invokeMethod<Object?>('native', {
      'session': session,
    });
    return response == null ? null : ShellMenuItem.fromNative(response);
  }

  Future<void> invoke(int id) =>
      channel.invokeMethod<void>('invoke', {'session': session, 'id': id});

  Future<void> rename(int id, String name) => channel.invokeMethod<void>(
    'rename',
    {'session': session, 'id': id, 'name': name},
  );

  Future<void> close() =>
      channel.invokeMethod<void>('close', {'session': session});
}
