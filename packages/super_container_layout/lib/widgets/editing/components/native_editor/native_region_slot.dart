/// Contrats de région ([NativeRegion]) et slots d'adaptation de taille préférée
/// ([NativePreferredSizeWidget], [NativeWidgetSlot], [NativeInstanceSlot]) pour
/// les composants Material natifs édités par `NativeComponentEditor`.
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/component_tag_filter.dart';
import '../../../../models/native_component_config.dart';
import '../../../components/super_layout/slot_implementation.dart';
import '../../slots/editor_slot.dart';

/// Permet à un parent natif de suivre la hauteur préférée éditée d'un enfant.
abstract interface class NativePreferredSizeWidget
    implements PreferredSizeWidget {
  /// [Listenable] notifiant les changements de taille préférée de ce widget.
  Listenable? sizeListenable(BuildContext context);

  /// Calcule la taille préférée effective dans le [context] donné.
  Size preferredSizeIn(BuildContext context);
}

/// Conserve la taille réactive d'un widget natif à travers la composition de slots.
class NativeWidgetSlot extends SlotImplementation
    implements NativePreferredSizeWidget {
  /// Crée un [NativeWidgetSlot] enveloppant [child].
  const NativeWidgetSlot({
    required super.id,
    required super.label,
    required this.child,
    super.sizing = SlotSizing.intrinsic,
    super.tags,
    super.menuIcon,
    super.key,
  });

  /// Widget enfant exposant une taille préférée réactive.
  final NativePreferredSizeWidget child;

  @override
  bool get isSliverSlot => super.isSliverSlot || isSliverWidget(child);

  @override
  bool canRenderAsSliver(BuildContext context) => isSliverSlot;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Size preferredSizeIn(BuildContext context) => child.preferredSizeIn(context);

  @override
  Listenable? sizeListenable(BuildContext context) =>
      child.sizeListenable(context);

  @override
  Widget buildSlot(BuildContext context) => child;
}

/// [InstanceSlot] préservant le contrat [NativePreferredSizeWidget] d'un slot natif.
class NativeInstanceSlot extends InstanceSlot
    implements NativePreferredSizeWidget {
  /// Crée un [NativeInstanceSlot] autour de [component].
  NativeInstanceSlot(
    super.component, {
    super.key,
    required super.label,
    required super.onRename,
    required super.onRestore,
    required super.overridden,
  });

  NativePreferredSizeWidget get _native =>
      component as NativePreferredSizeWidget;

  @override
  Size get preferredSize => _native.preferredSize;

  @override
  Size preferredSizeIn(BuildContext context) =>
      _native.preferredSizeIn(context);

  @override
  Listenable? sizeListenable(BuildContext context) =>
      _native.sizeListenable(context);
}

/// Callback appelé lorsqu'un slot est ajouté dans une région d'un composant natif.
typedef NativeSlotAddedCallback = NativeComponentConfig Function(
  NativeComponentConfig config,
  String region,
  String id,
  SlotImplementation slot,
  List<SlotImplementation> siblings,
);

/// Contrat d'édition d'une région de composant natif, indépendant des placements persistés.
class NativeRegion {
  /// Crée la définition d'une région native identifiée par [id] et [label].
  const NativeRegion(
    this.id,
    this.label, {
    this.required = false,
    this.single = false,
    this.axis = Axis.vertical,
    this.expand = true,
    this.stretch = true,
    this.editableFlow = false,
    this.emptySize = const Size(double.infinity, kToolbarHeight),
    this.fillSize,
    this.tagFilter = const ComponentTagFilter(),
    this.menuDestination = EditorMenuDestination.configuration,
  });

  /// Identifiant technique de la région (ex. `leading`, `title`, `actions`, `body`).
  final String id;

  /// Libellé lisible affiché dans l'éditeur.
  final String label;

  /// Indique si la région est toujours active et ne peut pas être désactivée.
  final bool required;

  /// Indique si la région n'accepte qu'un seul slot à la fois.
  final bool single;

  /// Axe par défaut d'empilement des slots dans la région.
  final Axis axis;

  /// Indique si les slots s'étendent sur l'axe principal.
  final bool expand;

  /// Indique si les slots s'étirent sur l'axe transversal.
  final bool stretch;

  /// Indique si l'utilisateur peut configurer l'axe et le flux flex de la région.
  final bool editableFlow;

  /// Taille de repli affichée en mode édition lorsque la région est vide.
  final Size emptySize;

  /// Taille par défaut appliquée aux slots en mode [SlotSizing.fill] sans taille explicite.
  final Size? fillSize;

  /// Filtre de tags restreignant les composants acceptés dans cette région.
  final ComponentTagFilter tagFilter;

  /// Onglet cible du dialogue lors d'un clic sur l'action d'édition de la région.
  final EditorMenuDestination menuDestination;
}
