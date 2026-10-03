import 'package:flutter/services.dart';

class ShellMenuItem {
  const ShellMenuItem({
    required this.id,
    required this.label,
    this.verb = '',
    this.enabled = true,
    this.separator = false,
    this.checked = false,
    this.isDefault = false,
    this.nativeOnly = false,
    this.submenu,
  });

  final int id;
  final String label;
  final String verb;
  final bool enabled;
  final bool separator;
  final bool checked;
  final bool isDefault;
  final bool nativeOnly;
  final int? submenu;

  factory ShellMenuItem.fromNative(Object? value) {
    if (value is! Map ||
        value['id'] is! int ||
        value['label'] is! String ||
        (value['verb'] != null && value['verb'] is! String) ||
        (value['submenu'] != null && value['submenu'] is! int)) {
      throw PlatformException(
        code: 'invalid_menu_item',
        message: 'Windows a renvoyé une commande invalide.',
      );
    }
    bool flag(String name, bool fallback) {
      final flag = value[name];
      if (flag == null) return fallback;
      if (flag is bool) return flag;
      throw PlatformException(
        code: 'invalid_menu_item',
        message: 'Windows a renvoyé un état de commande invalide.',
      );
    }

    return ShellMenuItem(
      id: value['id'] as int,
      label: value['label'] as String,
      verb: value['verb'] as String? ?? '',
      enabled: flag('enabled', true),
      separator: flag('separator', false),
      checked: flag('checked', false),
      isDefault: flag('default', false),
      nativeOnly: flag('nativeOnly', false),
      submenu: value['submenu'] as int?,
    );
  }
}
