/// Contexte, constructeurs et composants applicatifs du registre de composants.
library;

import 'package:material_ui/material_ui.dart';

import '../services/codegen/core/component_dart_generator.dart';
import '../widgets/components/super_layout/slot_implementation.dart';
import '../widgets/editing/addition/component_add_contracts.dart';
import '../widgets/editing/slots/editor_slot.dart';
import 'component_duplication_contract.dart';

/// Contexte d'instanciation contenant l'identifiant unique `id` du composant à construire.
class XuiBuildCtx {
  XuiBuildCtx({required this.id});

  final String id;
}

/// Descripteur et constructeur de base d'un type de composant du registre.
class ComponentBuilder {
  ComponentBuilder({
    this.label,
    this.tags = const {},
    this.addFamily = ComponentAddFamily.user,
    this.addOrder = 0,
    this.placementTags = const {},
    this.menuIcon,
    this.duplication,
    this.addConfigurator,
    this.previewBuilder,
    this.dartGenerator,
  });

  /// Optional custom label displayed in the component add popup.
  final String? label;

  final Set<String> tags;

  /// Famille utilisée pour filtrer ce composant dans le wizard d’ajout.
  final ComponentAddFamily addFamily;

  /// Ordre croissant dans la famille du wizard, par défaut zéro.
  final int addOrder;

  /// Non-empty for a component dedicated to some zones: the add wizards only
  /// offer zones whose tag filter explicitly includes one of these tags.
  final Set<String> placementTags;

  /// Optional icon for this component's editing context-menu entry.
  final IconData? menuIcon;

  /// Null when the component cannot be duplicated in a design graph.
  final ComponentDuplicationContract? duplication;

  /// Settings proposed by the add wizard; null when there are none.
  final ComponentAddConfigurator<Object>? addConfigurator;

  /// Optional preview widget builder displayed in the component add popup.
  final WidgetBuilder? previewBuilder;

  /// Optional Dart code generator dedicated to this component type.
  final ComponentDartGenerator? dartGenerator;

  Widget getWidget(XuiBuildCtx ctx) {
    return SizedBox.shrink();
  }
}

/// Implémentation de [ComponentBuilder] retournant une instance de widget préconstruite.
class RegisteredComponentImpl extends ComponentBuilder {
  RegisteredComponentImpl({
    required this.widget,
    super.label,
    super.tags,
    super.addFamily,
    super.addOrder,
    super.placementTags,
    super.menuIcon,
    super.duplication,
    super.addConfigurator,
    super.previewBuilder,
    super.dartGenerator,
  });

  final Widget widget;

  @override
  Widget getWidget(XuiBuildCtx ctx) {
    return widget;
  }
}

/// Implémentation de [ComponentBuilder] construisant dynamiquement un widget à partir du [XuiBuildCtx].
class ComponentBuilderDynamic extends ComponentBuilder {
  final Widget Function(XuiBuildCtx) dynamicBuilder;

  ComponentBuilderDynamic({
    required this.dynamicBuilder,
    super.label,
    super.tags,
    super.addFamily,
    super.addOrder,
    super.placementTags,
    super.menuIcon,
    super.duplication,
    super.addConfigurator,
    super.previewBuilder,
    super.dartGenerator,
  });

  @override
  Widget getWidget(XuiBuildCtx ctx) => dynamicBuilder(ctx);
}

/// Portée `InheritedWidget` identifiant la racine d'un [RegisteredComponent] dans l'arbre de widgets.
class RegisteredComponentScope extends InheritedWidget {
  const RegisteredComponentScope({
    required this.componentKey,
    required this.label,
    required this.composable,
    required super.child,
    super.key,
  });

  /// Clé sous laquelle le composant est enregistré dans `_registry.registerComponent(key, ...)`.
  final String componentKey;

  /// Libellé déclaré sur le [RegisteredComponent].
  final String label;

  /// Indique s'il s'agit d'un composant de composition (`RegisteredComponent.composable` / `decomposableOnExport: true`).
  final bool composable;

  /// Retourne le [RegisteredComponentScope] direct (sans traverser un `EditorSlotState` intermédiaire), ou `null`.
  static RegisteredComponentScope? directOf(BuildContext context) {
    final inherited = context
        .getElementForInheritedWidgetOfExactType<RegisteredComponentScope>()
        ?.widget;
    if (inherited is! RegisteredComponentScope) return null;

    var direct = true;
    context.visitAncestorElements((ancestor) {
      if (identical(ancestor.widget, inherited)) return false;
      if (ancestor is StatefulElement && ancestor.state is EditorSlotState) {
        direct = false;
        return false;
      }
      return true;
    });
    return direct ? inherited : null;
  }

  @override
  bool updateShouldNotify(RegisteredComponentScope oldWidget) =>
      componentKey != oldWidget.componentKey ||
      label != oldWidget.label ||
      composable != oldWidget.composable;
}

/// Constructeur de widget pour un [RegisteredComponent] recevant le [BuildContext]
/// et l'identifiant d'instance [id] du slot lors de son placement.
typedef InstanceWidgetBuilder = Widget Function(
  BuildContext context,
  String id,
);

/// Définition d'un composant applicatif pouvant être inséré comme slot.
class RegisteredComponent {
  const RegisteredComponent({
    required this.label,
    WidgetBuilder? builder,
    this.instanceBuilder,
    this.slotId,
    this.sizing = SlotSizing.fill,
    this.preferredSize,
    this.isAvailable,
    this.tags = const {},
    this.addFamily = ComponentAddFamily.user,
    this.addOrder = 0,
    this.placementTags = const {},
    this.menuIcon,
    this.duplication,
    this.addConfigurator,
    this.previewBuilder,
    this.decomposableOnExport = false,
    this.registeredKey,
  }) : _builder = builder,
       assert(
         builder != null || instanceBuilder != null,
         'Au moins builder ou instanceBuilder doit être fourni.',
       );

  /// Constructeur nommé pour un composant uniquement composé de composants standards ou d'extensions,
  /// autorisant sa décomposition (inlining) lors d'un export en code Dart.
  const RegisteredComponent.composable({
    required this.label,
    WidgetBuilder? builder,
    this.instanceBuilder,
    this.slotId,
    this.sizing = SlotSizing.fill,
    this.preferredSize,
    this.isAvailable,
    this.tags = const {},
    this.addFamily = ComponentAddFamily.user,
    this.addOrder = 0,
    this.placementTags = const {},
    this.menuIcon,
    this.duplication,
    this.addConfigurator,
    this.previewBuilder,
    this.registeredKey,
  }) : _builder = builder,
       decomposableOnExport = true,
       assert(
         builder != null || instanceBuilder != null,
         'Au moins builder ou instanceBuilder doit être fourni.',
       );

  /// Retourne une copie dont la clé d’enregistrement est [key].
  RegisteredComponent withRegisteredKey(String key) => RegisteredComponent(
    label: label,
    builder: _builder,
    instanceBuilder: instanceBuilder,
    slotId: slotId,
    sizing: sizing,
    preferredSize: preferredSize,
    isAvailable: isAvailable,
    tags: tags,
    addFamily: addFamily,
    addOrder: addOrder,
    placementTags: placementTags,
    menuIcon: menuIcon,
    duplication: duplication,
    addConfigurator: addConfigurator,
    previewBuilder: previewBuilder,
    decomposableOnExport: decomposableOnExport,
    registeredKey: key,
  );

  final String label;
  final WidgetBuilder? _builder;

  /// Constructeur de widget dynamique recevant l'identifiant d'instance du slot.
  final InstanceWidgetBuilder? instanceBuilder;

  /// Indique si ce composant (composé de composants standards ou d'extensions)
  /// peut être décomposé en widgets standards lors de l'export en code Dart.
  final bool decomposableOnExport;

  /// Clé d'enregistrement dans le [Registry] (ex. `'panString'`).
  final String? registeredKey;

  Widget _wrapWithScope(Widget child) {
    final key = registeredKey ?? (label.isNotEmpty ? label : null);
    if (key == null || !decomposableOnExport && registeredKey == null) {
      return child;
    }
    return RegisteredComponentScope(
      componentKey: key,
      label: label,
      composable: decomposableOnExport,
      child: child,
    );
  }

  /// Constructeur historique de widget.
  WidgetBuilder get builder => (context) {
    final raw = _builder != null
        ? _builder(context)
        : instanceBuilder!(
            context,
            slotId ??
                editorComponentLabelOf(context)?.id ??
                registeredKey ??
                (label.isNotEmpty ? label : 'registered-component'),
          );
    return _wrapWithScope(raw);
  };

  /// Identifiant historique, conservé dans les dispositions existantes.
  final String? slotId;
  final SlotSizing sizing;
  final Size? preferredSize;
  final bool Function(BuildContext)? isAvailable;
  final Set<String> tags;

  /// Famille utilisée pour filtrer ce composant dans le wizard d’ajout.
  final ComponentAddFamily addFamily;

  /// Ordre croissant dans la famille du wizard, par défaut zéro.
  final int addOrder;

  /// Non-empty for a component dedicated to some zones: the add wizards only
  /// offer zones whose tag filter explicitly includes one of these tags.
  final Set<String> placementTags;

  /// Optional icon for this component's editing context-menu entry.
  final IconData? menuIcon;

  /// Null when the component cannot be duplicated in a design graph.
  final ComponentDuplicationContract? duplication;

  /// Settings proposed by the add wizard; null when there are none.
  final ComponentAddConfigurator<Object>? addConfigurator;

  /// Optional preview widget builder displayed in the component add popup.
  final WidgetBuilder? previewBuilder;

  BuilderSlot createSlot(String id, {bool visible = true}) => BuilderSlot(
    id: id,
    label: label,
    sizing: sizing,
    preferredSize: preferredSize,
    visible: visible,
    builder: instanceBuilder != null
        ? (context) => _wrapWithScope(instanceBuilder!(context, id))
        : builder,
    tags: tags,
    menuIcon: menuIcon,
  );
}
