/// Portée réactive [AppearanceScope] exposant le `ValueNotifier<Appearance>`
/// courant aux widgets du package.
///
/// Le modèle [Appearance] reste dans `theme/appearance.dart` ; ce fichier ne
/// contient que le pont `InheritedNotifier` côté widgets.
library;

import 'package:material_ui/material_ui.dart';

import '../../theme/appearance.dart';

/// Portée `InheritedNotifier` exposant le `ValueNotifier<Appearance>` courant aux widgets enfants.
class AppearanceScope extends InheritedNotifier<ValueNotifier<Appearance>> {
  const AppearanceScope({
    required ValueNotifier<Appearance> controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);
  static ValueNotifier<Appearance>? controllerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
  static Appearance of(BuildContext context) =>
      controllerOf(context)?.value ?? Appearance();
}
