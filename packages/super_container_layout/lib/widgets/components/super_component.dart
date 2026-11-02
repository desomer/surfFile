/// Contrat commun des composants configurables, sans imposer leur gestion d'etat.
library;

import 'package:material_ui/material_ui.dart';

import '../../models/component_behavior.dart';
import '../../models/component_config.dart';

/// Identite, configuration initiale typee et comportements d'une instance.
abstract interface class SuperComponent<C extends ComponentConfig?> {
  /// Identifiant technique ; certains conteneurs l'heritent de leur slot.
  String? get id;

  /// Configuration initiale, avant resolution des surcharges persistantes.
  C get config;

  /// `null` utilise l'apparence ; une liste explicite la remplace.
  List<ComponentBehavior>? get behaviours;
}

/// Base des composants avec etat ; chaque composant conserve son propre State.
abstract class SuperStatefulComponent<C extends ComponentConfig?>
    extends StatefulWidget
    implements SuperComponent<C> {
  const SuperStatefulComponent({this.behaviours, super.key});

  @override
  final List<ComponentBehavior>? behaviours;
}

/// Base des composants sans etat partageant le meme contrat.
abstract class SuperStatelessComponent<C extends ComponentConfig?>
    extends StatelessWidget
    implements SuperComponent<C> {
  const SuperStatelessComponent({this.behaviours, super.key});

  @override
  final List<ComponentBehavior>? behaviours;
}
