/// Bibliothèque publique du package `super_designer`.
///
/// Réexporte l'intégralité du moteur `super_container_layout`, les extensions
/// `super_container_extensions` (dont `SuperChart`) ainsi que l'application
/// autonome [SuperDesignerApp] ([TestApp]).
library;

export 'package:super_container_extensions/super_container_extensions.dart';
export 'package:super_container_layout/super_container_layout.dart';

export 'main.dart'
    show SuperDesignerApp, TestApp, createSuperDesignerRegistry, main;
