/// Contrats de slots plaçables et adaptation des composants aux zones de layout.
library;

import 'package:material_ui/material_ui.dart';

import '../component_tooltip.dart';
import '../super_component.dart';
import '../../editing/dialogs/editor_dialog_header.dart';

/// Marqueur des composants capables de produire un sliver dans un slot.
abstract interface class SliverCapableWidget implements Widget {}

/// Indique si [widget] est un sliver natif ou un composant compatible.
bool isSliverWidget(Widget widget) => switch (widget) {
  SliverCapableWidget() => true,
  final SlotImplementation slot => slot.isSliverSlot,
  final KeyedSubtree subtree => isSliverWidget(subtree.child),
  SliverAppBar() ||
  SliverPersistentHeader() ||
  SliverWithKeepAliveWidget() ||
  SliverToBoxAdapter() ||
  SliverPadding() ||
  SliverFillRemaining() ||
  SliverFillViewport() ||
  SliverMainAxisGroup() ||
  SliverCrossAxisGroup() ||
  SliverLayoutBuilder() ||
  SliverOffstage() ||
  SliverOpacity() ||
  SliverSafeArea() ||
  SliverVisibility() ||
  SliverIgnorePointer() => true,
  _ => false,
};

/// Taille qu'un slot demande à la zone qui le reçoit.
enum SlotSizing {
  /// Le slot remplit l'espace restant de sa zone.
  fill,

  /// Le slot prend la hauteur (ou la largeur) que demande son contenu.
  intrinsic,
}

/// Informe les composants imbriqués des axes qui doivent mesurer leur contenu.
class SlotContentFitScope extends InheritedWidget {
  /// Crée une portée de mesure de contenu.
  const SlotContentFitScope({
    required this.fitWidth,
    required this.fitHeight,
    required super.child,
    super.key,
  });

  /// Indique si le contenu doit déterminer la largeur.
  final bool fitWidth;

  /// Indique si le contenu doit déterminer la hauteur.
  final bool fitHeight;

  /// Retourne la portée héritée, si elle existe.
  static SlotContentFitScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SlotContentFitScope>();

  @override
  bool updateShouldNotify(SlotContentFitScope oldWidget) =>
      fitWidth != oldWidget.fitWidth || fitHeight != oldWidget.fitHeight;
}

/// Bloc majeur d'une page, rangé dans une zone grâce à son [id].
///
/// Une sous-classe décrit son contenu dans [buildSlot]. Un bloc avec état
/// l'enveloppe dans son propre widget à état ; un bloc simple peut passer par
/// [BuilderSlot].
abstract class SlotImplementation extends StatelessWidget {
  /// Crée un slot de page.
  const SlotImplementation({
    required this.id,
    required this.label,
    this.sizing = SlotSizing.fill,
    this.preferredSize,
    this.visible = true,
    this.showLabel = true,
    this.labelAlignment = Alignment.topRight,
    this.tags = const {},
    this.menuIcon,
    super.key,
  });

  /// Identifiant stable utilisé par `SuperLayoutConfig.placements`.
  final String id;

  /// Libellé du slot dans les menus et le mode édition.
  final String label;

  /// Tags décrivant le type de contenu du slot.
  final Set<String> tags;

  /// Icône optionnelle des actions de ce slot.
  final IconData? menuIcon;

  /// Politique de partage de l'espace de la zone.
  final SlotSizing sizing;

  /// Dimensions demandées, limitées par l'espace disponible dans la zone.
  final Size? preferredSize;

  /// Indique si le slot est rendu et prend de la place.
  final bool visible;

  /// Indique si le libellé est affiché en mode édition.
  final bool showLabel;

  /// Coin où est placé le libellé du slot en mode édition.
  final Alignment labelAlignment;

  /// Indique si les tags du slot le déclarent compatible avec un sliver.
  bool get isSliverSlot =>
      tags.contains('sliver') ||
      tags.contains('list') ||
      tags.contains('appBar');

  /// Détermine si ce slot peut produire un sliver dans [context].
  bool canRenderAsSliver(BuildContext context) => isSliverSlot;

  /// Construit le contenu du slot.
  @protected
  Widget buildSlot(BuildContext context);

  @override
  Widget build(BuildContext context) {
    final child = buildSlot(context);
    return KeyedSubtree(
      key: ValueKey('slot-$id'),
      child: ComponentTooltip(
        componentId: id,
        behaviors: switch (child) {
          SuperComponent(:final behaviours) => behaviours,
          _ => null,
        },
        child: child,
      ),
    );
  }
}

/// Slot dont le contenu est fourni par une fonction.
class BuilderSlot extends SlotImplementation {
  /// Crée un slot construit par [builder].
  const BuilderSlot({
    required super.id,
    required super.label,
    required this.builder,
    super.sizing,
    super.preferredSize,
    super.visible,
    super.showLabel,
    super.labelAlignment,
    super.tags,
    super.menuIcon,
    super.key,
  });

  /// Construit le contenu du slot.
  final WidgetBuilder builder;

  @override
  bool canRenderAsSliver(BuildContext context) {
    final built = builder(context);
    if (built is SlotImplementation) {
      return built.canRenderAsSliver(context);
    }
    return isSliverWidget(built);
  }

  @override
  Widget buildSlot(BuildContext context) => builder(context);
}

/// Préserve l'état d'un composant tout en exposant son nom d'instance à l'éditeur.
class InstanceSlot extends SlotImplementation {
  /// Crée une vue d'instance autour de [component].
  InstanceSlot(
    this.component, {
    super.key,
    required super.label,
    required this.onRename,
    required this.onRestore,
    required this.overridden,
  }) : super(
         id: component.id,
         sizing: component.sizing,
         preferredSize: component.preferredSize,
         visible: component.visible,
         showLabel: component.showLabel,
         labelAlignment: component.labelAlignment,
         tags: component.tags,
         menuIcon: component.menuIcon,
       );

  /// Composant dont l'état est conservé.
  final SlotImplementation component;

  /// Renomme l'instance.
  final ValueChanged<String> onRename;

  /// Restaure sa configuration par défaut.
  final VoidCallback onRestore;

  /// Indique si la configuration diffère du défaut.
  final bool overridden;

  @override
  bool get isSliverSlot => component.isSliverSlot;

  @override
  bool canRenderAsSliver(BuildContext context) =>
      component.canRenderAsSliver(context);

  @override
  Widget build(BuildContext context) => buildSlot(context);

  @override
  Widget buildSlot(BuildContext context) => EditorComponentLabel(
    id: id,
    label: label,
    onChanged: onRename,
    onRestore: onRestore,
    overridden: overridden,
    menuIcon: menuIcon,
    child: component,
  );
}
