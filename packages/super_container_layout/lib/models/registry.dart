/// Registre central des composants ([Registry]) et contrats de duplication du designer.
///
/// Maintient le catalogue des constructeurs de composants (`Registry.bootstrap`),
/// les `ValueNotifier` de configuration par identifiant d'instance et leur
/// synchronisation bidirectionnelle avec [Appearance].
library;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';

import 'component_config.dart';
import 'component_extension.dart';
import 'native_component_config.dart';
import 'super_list_view_config.dart';
import 'super_conditional_config.dart';
import 'super_tab_config.dart';
import 'super_table_config.dart';
import 'super_tree_view_config.dart';
import 'super_value_config.dart';
import 'super_action_config.dart';
import 'super_indicator_config.dart';
import 'super_separator_config.dart';
import '../widgets/components/super_renderer.dart';
import '../widgets/editing/components/super_renderer_editor.dart';
import '../widgets/components/super_list_view.dart';
import '../widgets/components/super_conditional.dart';
import '../widgets/components/super_tab.dart';
import '../widgets/components/super_table.dart';
import '../widgets/components/super_tree_view.dart';
import '../widgets/components/super_value.dart';
import '../widgets/components/super_action.dart';
import '../widgets/components/super_indicator.dart';
import '../widgets/components/super_separator.dart';
import '../widgets/components/super_layout/iterable_content.dart';

import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/scaffold_page_config.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/widgets/components/native/super_app_bar.dart';

import '../widgets/components/native/super_bottom_app_bar.dart';
import '../widgets/components/native/super_bottom_navigation_bar.dart';
import '../widgets/components/native/super_expansible.dart';
import '../widgets/components/native/super_menu_anchor.dart';
import '../widgets/components/native/super_navigation_rail.dart';
import '../services/codegen/component_dart_generators.dart';
import '../services/codegen/dart_code_generator.dart';
import '../services/pages/editor_page_graph.dart';
import '../widgets/editing/addition/component_add_configurators.dart';
import '../widgets/editing/addition/component_add_wizard.dart';

import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/components/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';

part 'registry_previews.dart';

/// Contexte d'instanciation contenant l'identifiant unique `id` du composant à construire.
class XuiBuildCtx {
  XuiBuildCtx({required this.id});

  final String id;
}

/// Persisted configuration maps of an `Appearance` that a design graph uses.
enum EditorConfigKind {
  layout,
  style,
  component,
  nativeComponent,
  scaffoldPage,
  value,
  action,
  indicator,
  separator,
  list,
  tab,
  conditional,
  treeView,
  table,
}

/// Key of one persisted configuration entry, e.g. `layouts[id]`.
@immutable
class EditorConfigRef {
  const EditorConfigRef(this.kind, this.id);

  const EditorConfigRef.layout(this.id) : kind = EditorConfigKind.layout;
  const EditorConfigRef.style(this.id) : kind = EditorConfigKind.style;
  const EditorConfigRef.component(this.id) : kind = EditorConfigKind.component;
  const EditorConfigRef.nativeComponent(this.id)
    : kind = EditorConfigKind.nativeComponent;
  const EditorConfigRef.scaffoldPage(this.id)
    : kind = EditorConfigKind.scaffoldPage;
  const EditorConfigRef.value(this.id) : kind = EditorConfigKind.value;
  const EditorConfigRef.action(this.id) : kind = EditorConfigKind.action;
  const EditorConfigRef.indicator(this.id) : kind = EditorConfigKind.indicator;
  const EditorConfigRef.separator(this.id) : kind = EditorConfigKind.separator;
  const EditorConfigRef.list(this.id) : kind = EditorConfigKind.list;
  const EditorConfigRef.tab(this.id) : kind = EditorConfigKind.tab;
  const EditorConfigRef.conditional(this.id)
    : kind = EditorConfigKind.conditional;
  const EditorConfigRef.treeView(this.id) : kind = EditorConfigKind.treeView;
  const EditorConfigRef.table(this.id) : kind = EditorConfigKind.table;

  final EditorConfigKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is EditorConfigRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => '${kind.name}:$id';
}

/// Copies one persisted configuration of a duplicated instance.
///
/// [value] is the source `SuperLayoutConfig`, `ContainerStyle`,
/// `NativeComponentConfig`, `ScaffoldPageConfig`, `SuperValueConfig` or
/// `SuperListViewConfig`; the result must have the same type. [remap] returns
/// the new ID of every instance/configuration ID owned by the duplicated graph
/// and returns other IDs unchanged.
typedef EditorConfigCopier = Object Function(
  EditorConfigRef source,
  Object value,
  String Function(String id) remap,
);

/// Explicit contract allowing a design graph to duplicate a component.
///
/// It only describes persisted data: duplication never reads runtime
/// controllers, text fields or widget state. Components without a contract
/// are refused by `EditorPageGraph.duplicate`.
@immutable
class ComponentDuplicationContract {
  const ComponentDuplicationContract({
    this.ownedConfigs = _noConfigs,
    this.copyConfig,
  });

  /// Component that persists nothing under its instance ID.
  const ComponentDuplicationContract.stateless() : this();

  /// Configurations owned by an instance. Must be a pure derivation of
  /// `instanceId`, returning the same kinds in the same order for every ID,
  /// so that the copy is found again by the new instance ID.
  final List<EditorConfigRef> Function(String instanceId) ownedConfigs;

  /// Custom copy; null uses the built-in structural copy of each kind.
  final EditorConfigCopier? copyConfig;

  static List<EditorConfigRef> _noConfigs(String _) => const [];
  static List<EditorConfigRef> _layout(String id) => [
    EditorConfigRef.layout(id),
  ];
  static List<EditorConfigRef> _container(String id) => [
    EditorConfigRef.style(id),
    EditorConfigRef.nativeComponent(id),
  ];
  static List<EditorConfigRef> _value(String id) => [EditorConfigRef.value(id)];
  static List<EditorConfigRef> _action(String id) => [
    EditorConfigRef.action(id),
  ];
  static List<EditorConfigRef> _indicator(String id) => [
    EditorConfigRef.indicator(id),
  ];
  static List<EditorConfigRef> _separator(String id) => [
    EditorConfigRef.separator(id),
  ];
  static List<EditorConfigRef> _list(String id) => [
    EditorConfigRef.layout(id),
    EditorConfigRef.style(id),
    EditorConfigRef.list(id),
  ];
  static List<EditorConfigRef> _iterableContent(String id) => [
    EditorConfigRef.layout(id),
    EditorConfigRef.style(id),
  ];
  static List<EditorConfigRef> _native(String id) => [
    EditorConfigRef.nativeComponent(id),
  ];
  static List<EditorConfigRef> _tab(String id) => [EditorConfigRef.tab(id)];
  static List<EditorConfigRef> _conditional(String id) => [
    EditorConfigRef.conditional(id),
  ];
  static List<EditorConfigRef> _component(String id) => [
    EditorConfigRef.component(id),
  ];
  static List<EditorConfigRef> _treeView(String id) => [
    EditorConfigRef.style(id),
    EditorConfigRef.treeView(id),
  ];
  static List<EditorConfigRef> _table(String id) => [
    EditorConfigRef.style(id),
    EditorConfigRef.table(id),
  ];

  /// Contracts of the components installed by [Registry.bootstrap] and extensions.
  static const component = ComponentDuplicationContract(
    ownedConfigs: _component,
  );
  static const superValue = ComponentDuplicationContract(ownedConfigs: _value);
  static const superAction = ComponentDuplicationContract(
    ownedConfigs: _action,
  );
  static const superIndicator = ComponentDuplicationContract(
    ownedConfigs: _indicator,
  );
  static const superSeparator = ComponentDuplicationContract(
    ownedConfigs: _separator,
  );
  static const superTab = ComponentDuplicationContract(ownedConfigs: _tab);
  static const superConditional = ComponentDuplicationContract(
    ownedConfigs: _conditional,
  );
  static const superTreeView = ComponentDuplicationContract(
    ownedConfigs: _treeView,
  );
  static const superTable = ComponentDuplicationContract(ownedConfigs: _table);
  static const superAppBar = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const superBottomNavigationBar = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const superBottomAppBar = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const superNavigationRail = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const superExpansible = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const superMenuAnchor = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const newContainer = ComponentDuplicationContract(
    ownedConfigs: _container,
  );
  static const newLayout = ComponentDuplicationContract(ownedConfigs: _layout);
  static const iterableContent = ComponentDuplicationContract(
    ownedConfigs: _iterableContent,
  );
  static const superListView = ComponentDuplicationContract(
    ownedConfigs: _list,
  );
}

/// Descripteur et constructeur de base d'un type de composant enregistré dans le [Registry].
class ComponentBuilder {
  ComponentBuilder({
    this.label,
    this.tags = const {},
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

/// Registre central associant les types de composants et synchronisant leurs `ValueNotifier` par ID avec [Appearance].
class Registry {
  static const List<String> defaultAvailableFontFamilies = [
    'Segoe UI',
    'Roboto',
    'Arial',
    'Verdana',
    'Tahoma',
    'Trebuchet MS',
    'Georgia',
    'Times New Roman',
    'Consolas',
    'Courier New',
    'monospace',
  ];

  final Map<String, ComponentBuilder> registry = {};
  final Map<String, RegisteredComponent> components = {};

  /// Options d'export de composant par identifiant d'instance (configurées via « Configure as... »).
  final Map<String, ComponentExportOptions> exportOptionsById = {};
  final Map<String, ValueNotifier<SuperLayoutConfig>> superLayoutConfigById =
      {};
  final Map<String, ValueNotifier<ContainerStyle>> containerStyleById = {};
  final Map<String, ValueNotifier<ComponentConfig>> componentConfigById = {};
  final Map<String, ValueNotifier<ScaffoldPageConfig>> scaffoldPageConfigById =
      {};
  final Map<String, ValueNotifier<NativeComponentConfig>>
  nativeComponentConfigById = {};
  ValueNotifier<Appearance>? _appearance;
  bool _syncing = false;
  final Map<String, SuperLayoutConfig> _layoutDefaults = {};
  final Map<String, ContainerStyle> _styleDefaults = {};
  final Map<String, ComponentConfig> _componentDefaults = {};
  final Map<String, ComponentConfig Function(Appearance)> _componentReaders =
      {};
  final Map<String, ValueNotifier<SuperValueConfig>> valueConfigById = {};
  final Map<String, SuperValueConfig> _valueDefaults = {};
  final Map<String, ValueNotifier<SuperActionConfig>> actionConfigById = {};
  final Map<String, SuperActionConfig> _actionDefaults = {};
  final Map<String, ValueNotifier<SuperIndicatorConfig>> indicatorConfigById =
      {};
  final Map<String, SuperIndicatorConfig> _indicatorDefaults = {};
  final Map<String, ValueNotifier<SuperSeparatorConfig>> separatorConfigById =
      {};
  final Map<String, SuperSeparatorConfig> _separatorDefaults = {};
  final Map<String, ValueNotifier<SuperListViewConfig>> listConfigById = {};
  final Map<String, SuperListViewConfig> _listDefaults = {};
  final Map<String, ValueNotifier<SuperTabConfig>> tabConfigById = {};
  final Map<String, SuperTabConfig> _tabDefaults = {};
  final Map<String, ValueNotifier<SuperConditionalConfig>>
  conditionalConfigById = {};
  final Map<String, SuperConditionalConfig> _conditionalDefaults = {};
  final Map<String, ValueNotifier<SuperTreeViewConfig>> treeViewConfigById = {};
  final Map<String, SuperTreeViewConfig> _treeViewDefaults = {};
  final Map<String, ValueNotifier<SuperTableConfig>> tableConfigById = {};
  final Map<String, SuperTableConfig> _tableDefaults = {};
  final Map<String, NativeComponentConfig> _nativeDefaults = {};
  final Map<String, NativeComponentConfig? Function(Appearance)>
  _nativeMigrations = {};
  final Set<String> _scaffoldBridges = {};
  final Map<Listenable, VoidCallback> _listeners = {};

  Set<String> get instantiatedComponentIds => {
    ...superLayoutConfigById.keys,
    ...componentConfigById.keys,
    ...nativeComponentConfigById.keys,
    ...valueConfigById.keys,
    ...actionConfigById.keys,
    ...indicatorConfigById.keys,
    ...separatorConfigById.keys,
    ...listConfigById.keys,
    ...tabConfigById.keys,
    ...conditionalConfigById.keys,
    ...treeViewConfigById.keys,
    ...tableConfigById.keys,
  };

  /// Includes runtime defaults that have not yet been persisted.
  /// Reading this snapshot does not notify controllers or save preferences.
  Appearance appearanceSnapshot(Appearance current) {
    final components = <String, ComponentConfig>{
      for (final entry in superLayoutConfigById.entries)
        entry.key: entry.value.value,
      for (final entry in componentConfigById.entries)
        entry.key: entry.value.value,
      for (final entry in nativeComponentConfigById.entries)
        entry.key: entry.value.value,
      for (final entry in valueConfigById.entries) entry.key: entry.value.value,
      for (final entry in actionConfigById.entries)
        entry.key: entry.value.value,
      for (final entry in indicatorConfigById.entries)
        entry.key: entry.value.value,
      for (final entry in separatorConfigById.entries)
        entry.key: entry.value.value,
      for (final entry in listConfigById.entries) entry.key: entry.value.value,
      for (final entry in tabConfigById.entries) entry.key: entry.value.value,
      for (final entry in conditionalConfigById.entries)
        entry.key: entry.value.value,
      for (final entry in treeViewConfigById.entries)
        entry.key: entry.value.value,
      for (final entry in tableConfigById.entries) entry.key: entry.value.value,
      ...current.components,
    };
    // A list and its row layout share an ID.
    for (final entry in superLayoutConfigById.entries) {
      final component = components[entry.key];
      if (component is SuperListViewConfig &&
          !current.components.containsKey(entry.key)) {
        components[entry.key] = component.copyWith(template: entry.value.value);
      }
    }
    return current.copyWith(
      components: components,
      styles: {
        for (final entry in containerStyleById.entries)
          entry.key: entry.value.value,
        ...current.styles,
      },
    );
  }

  void bindAppearance(ValueNotifier<Appearance> controller) {
    unbindAppearance();
    _appearance = controller;
    controller.addListener(_readAppearance);
    for (final entry in superLayoutConfigById.entries.toList()) {
      layoutController(entry.key, fallback: entry.value.value);
    }
    for (final entry in containerStyleById.entries.toList()) {
      styleController(entry.key, fallback: entry.value.value);
    }
    for (final entry in componentConfigById.entries.toList()) {
      _componentDefaults[entry.key] = entry.value.value;
      _attachComponentListener(entry.key, entry.value);
    }
    for (final entry in scaffoldPageConfigById.entries.toList()) {
      scaffoldPageController(entry.key, fallback: entry.value.value);
    }
    for (final entry in nativeComponentConfigById.entries.toList()) {
      nativeComponentController(entry.key, fallback: entry.value.value);
    }
    for (final entry in valueConfigById.entries.toList()) {
      valueController(entry.key, fallback: entry.value.value);
    }
    for (final entry in actionConfigById.entries.toList()) {
      actionController(entry.key, fallback: entry.value.value);
    }
    for (final entry in indicatorConfigById.entries.toList()) {
      indicatorController(entry.key, fallback: entry.value.value);
    }
    for (final entry in separatorConfigById.entries.toList()) {
      separatorController(entry.key, fallback: entry.value.value);
    }
    for (final entry in listConfigById.entries.toList()) {
      listController(entry.key, fallback: entry.value.value);
    }
    for (final entry in tabConfigById.entries.toList()) {
      _tabDefaults[entry.key] = entry.value.value;
      tabController(entry.key, fallback: entry.value.value);
    }
    for (final entry in conditionalConfigById.entries.toList()) {
      _conditionalDefaults[entry.key] = entry.value.value;
      conditionalController(entry.key, fallback: entry.value.value);
    }
    for (final entry in treeViewConfigById.entries.toList()) {
      _treeViewDefaults[entry.key] = entry.value.value;
      treeViewController(entry.key, fallback: entry.value.value);
    }
    for (final entry in tableConfigById.entries.toList()) {
      _tableDefaults[entry.key] = entry.value.value;
      tableController(entry.key, fallback: entry.value.value);
    }
    _readAppearance();
  }

  /// Deletes, from the bound [Appearance], the configurations recursively
  /// owned by the unplaced slot instance [id] (see
  /// [EditorPageGraph.removeInstance]).
  void purgeInstance(String id, String type, EditorConfigKind containerKind) {
    final appearance = _appearance;
    if (appearance == null) return;
    appearance.value = EditorPageGraph.removeInstance(
      appearance: appearance.value,
      registry: this,
      instanceId: id,
      type: type,
      containerKind: containerKind,
    );
  }

  void unbindAppearance() {
    _appearance?.removeListener(_readAppearance);
    for (final entry in _listeners.entries) {
      entry.key.removeListener(entry.value);
    }
    _listeners.clear();
    _appearance = null;
  }

  /// Libere les controleurs possedes par ce registre et detache l'apparence.
  ///
  /// L'hote ne doit appeler cette methode qu'apres demontage de ses composants.
  void dispose() {
    unbindAppearance();
    final controllers = <ChangeNotifier>{
      ...superLayoutConfigById.values,
      ...containerStyleById.values,
      ...componentConfigById.values,
      ...scaffoldPageConfigById.values,
      ...nativeComponentConfigById.values,
      ...valueConfigById.values,
      ...actionConfigById.values,
      ...indicatorConfigById.values,
      ...separatorConfigById.values,
      ...listConfigById.values,
      ...tabConfigById.values,
      ...conditionalConfigById.values,
      ...treeViewConfigById.values,
      ...tableConfigById.values,
    };
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  ValueNotifier<T> _bindTypedController<T extends Object>(
    String id, {
    required T fallback,
    required Map<String, T> defaults,
    required Map<String, ValueNotifier<T>> controllers,
    required T Function(Appearance appearance, String id, T fallback) read,
    required Appearance Function(Appearance appearance, String id, T value)
    write,
    void Function(T value)? validate,
  }) {
    validate?.call(fallback);
    defaults.putIfAbsent(id, () => fallback);
    final notifier = controllers.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance == null ? fallback : read(_appearance!.value, id, fallback),
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void onChanged() {
        validate?.call(notifier.value);
        if (!_syncing) {
          _appearance!.value = write(_appearance!.value, id, notifier.value);
        }
      }

      _listeners[notifier] = onChanged;
      notifier.addListener(onChanged);
    }
    return notifier;
  }

  ValueNotifier<SuperLayoutConfig> layoutController(
    String id, {
    SuperLayoutConfig fallback = const SuperLayoutConfig(),
  }) => _bindTypedController(
    id,
    fallback: fallback,
    defaults: _layoutDefaults,
    controllers: superLayoutConfigById,
    read: (a, k, f) => a.layout(k, fallback: f),
    write: (a, k, v) => a.withLayout(k, v),
  );

  ValueNotifier<ContainerStyle> styleController(
    String id, {
    ContainerStyle fallback = const ContainerStyle(),
  }) => _bindTypedController(
    id,
    fallback: fallback,
    defaults: _styleDefaults,
    controllers: containerStyleById,
    read: (a, k, f) => a.style(k, fallback: f),
    write: (a, k, v) => a.withStyle(k, v),
  );

  ValueNotifier<ScaffoldPageConfig> scaffoldPageController(
    String id, {
    ScaffoldPageConfig? fallback,
  }) {
    final initial = fallback ?? ScaffoldPageConfig();
    final native = nativeComponentController(
      id,
      fallback: initial.native,
      legacy: (appearance) =>
          appearance.tryComponent<ScaffoldPageConfig>(id)?.native,
    );
    final notifier = scaffoldPageConfigById.putIfAbsent(
      id,
      () => ValueNotifier(ScaffoldPageConfig.fromNative(native.value)),
    );
    if (_scaffoldBridges.add(id)) {
      native.addListener(() {
        if (!identical(notifier.value.native, native.value)) {
          notifier.value = ScaffoldPageConfig.fromNative(native.value);
        }
      });
      notifier.addListener(() {
        if (!identical(native.value, notifier.value.native)) {
          native.value = notifier.value.native;
        }
      });
    }
    return notifier;
  }

  void _readAppearance() {
    final appearance = _appearance!.value;
    _syncing = true;
    try {
      for (final entry in superLayoutConfigById.entries) {
        entry.value.value = appearance.layout(
          entry.key,
          fallback: _layoutDefaults[entry.key] ?? const SuperLayoutConfig(),
        );
      }
      for (final entry in containerStyleById.entries) {
        entry.value.value = appearance.style(
          entry.key,
          fallback: _styleDefaults[entry.key] ?? const ContainerStyle(),
        );
      }
      for (final entry in componentConfigById.entries) {
        final reader = _componentReaders[entry.key];
        entry.value.value = reader != null
            ? reader(appearance)
            : appearance.component(
                entry.key,
                fallback: _componentDefaults[entry.key]!,
              );
      }
      for (final entry in nativeComponentConfigById.entries) {
        entry.value.value = _nativeValue(appearance, entry.key);
      }
      for (final entry in valueConfigById.entries) {
        entry.value.value = appearance.valueComponent(
          entry.key,
          fallback: _valueDefaults[entry.key]!,
        );
      }
      for (final entry in actionConfigById.entries) {
        entry.value.value = appearance.actionComponent(
          entry.key,
          fallback: _actionDefaults[entry.key]!,
        );
      }
      for (final entry in indicatorConfigById.entries) {
        entry.value.value = appearance.indicatorComponent(
          entry.key,
          fallback: _indicatorDefaults[entry.key]!,
        );
      }
      for (final entry in separatorConfigById.entries) {
        entry.value.value = appearance.separatorComponent(
          entry.key,
          fallback: _separatorDefaults[entry.key]!,
        );
      }
      for (final entry in listConfigById.entries) {
        entry.value.value = appearance.listComponent(
          entry.key,
          fallback: _listDefaults[entry.key]!,
        );
      }
      for (final entry in tabConfigById.entries) {
        entry.value.value = appearance.tabComponent(
          entry.key,
          fallback: _tabDefaults[entry.key]!,
        );
      }
      for (final entry in conditionalConfigById.entries) {
        entry.value.value = appearance.conditionalComponent(
          entry.key,
          fallback: _conditionalDefaults[entry.key]!,
        );
      }
      for (final entry in treeViewConfigById.entries) {
        entry.value.value = appearance.treeViewComponent(
          entry.key,
          fallback: _treeViewDefaults[entry.key]!,
        );
      }
      for (final entry in tableConfigById.entries) {
        entry.value.value = appearance.tableComponent(
          entry.key,
          fallback: _tableDefaults[entry.key]!,
        );
      }
    } finally {
      _syncing = false;
    }
  }

  void registerFactory(
    String key,
    Widget widget, {
    String? label,
    Set<String> tags = const {},
    IconData? menuIcon,
    ComponentDuplicationContract? duplication,
    ComponentAddConfigurator<Object>? addConfigurator,
    WidgetBuilder? previewBuilder,
  }) {
    registry[key] = ComponentBuilderDynamic(
      label: label,
      tags: tags,
      menuIcon: menuIcon,
      duplication: duplication,
      addConfigurator: addConfigurator,
      previewBuilder: previewBuilder,
      dynamicBuilder: (xuiCtx) => widget,
    );
  }

  void _attachComponentListener(
    String id,
    ValueNotifier<ComponentConfig> notifier,
  ) {
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        notifier.value.validate();
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withComponent(
            id,
            notifier.value,
          );
        }
      }

      _listeners[notifier] = write;
      notifier.addListener(write);
    }
  }

  ValueNotifier<T> componentController<T extends ComponentConfig>(
    String id, {
    required T fallback,
  }) {
    fallback.validate();
    _componentDefaults.putIfAbsent(id, () => fallback);
    _componentReaders.putIfAbsent(
      id,
      () =>
          (appearance) => appearance.component<T>(
            id,
            fallback: _componentDefaults[id]! as T,
          ),
    );
    final notifier = componentConfigById.putIfAbsent(
      id,
      () => ValueNotifier<T>(
        _appearance?.value.component<T>(id, fallback: fallback) ?? fallback,
      ),
    );
    _attachComponentListener(id, notifier);
    return notifier as ValueNotifier<T>;
  }

  ValueNotifier<SuperValueConfig> valueController(
    String id, {
    SuperValueConfig fallback = const SuperValueConfig(),
  }) => _bindTypedController(
    id,
    fallback: fallback,
    defaults: _valueDefaults,
    controllers: valueConfigById,
    read: (a, k, f) => a.valueComponent(k, fallback: f),
    write: (a, k, v) => a.withValueComponent(k, v),
    validate: (v) => v.validate(),
  );

  ValueNotifier<SuperActionConfig> actionController(
    String id, {
    SuperActionConfig fallback = const SuperActionConfig(),
  }) => _bindTypedController(
    id,
    fallback: fallback,
    defaults: _actionDefaults,
    controllers: actionConfigById,
    read: (a, k, f) => a.actionComponent(k, fallback: f),
    write: (a, k, v) => a.withActionComponent(k, v),
    validate: (v) => v.validate(),
  );

  ValueNotifier<SuperIndicatorConfig> indicatorController(
    String id, {
    SuperIndicatorConfig fallback = const SuperIndicatorConfig(),
  }) => _bindTypedController(
    id,
    fallback: fallback,
    defaults: _indicatorDefaults,
    controllers: indicatorConfigById,
    read: (a, k, f) => a.indicatorComponent(k, fallback: f),
    write: (a, k, v) => a.withIndicatorComponent(k, v),
    validate: (v) => v.validate(),
  );

  ValueNotifier<SuperSeparatorConfig> separatorController(
    String id, {
    SuperSeparatorConfig fallback = const SuperSeparatorConfig(),
  }) => _bindTypedController(
    id,
    fallback: fallback,
    defaults: _separatorDefaults,
    controllers: separatorConfigById,
    read: (a, k, f) => a.separatorComponent(k, fallback: f),
    write: (a, k, v) => a.withSeparatorComponent(k, v),
    validate: (v) => v.validate(),
  );

  ValueNotifier<SuperListViewConfig> listController(
    String id, {
    SuperListViewConfig fallback = const SuperListViewConfig(),
  }) => _bindTypedController(
    id,
    fallback: fallback,
    defaults: _listDefaults,
    controllers: listConfigById,
    read: (a, k, f) => a.listComponent(k, fallback: f),
    write: (a, k, v) => a.withListComponent(k, v),
    validate: (v) => v.validate(),
  );

  ValueNotifier<SuperTabConfig> tabController(
    String id, {
    SuperTabConfig? fallback,
  }) => _bindTypedController(
    id,
    fallback: fallback ?? SuperTabConfig(),
    defaults: _tabDefaults,
    controllers: tabConfigById,
    read: (a, k, f) => a.tabComponent(k, fallback: f),
    write: (a, k, v) => a.withTabComponent(k, v),
    validate: (v) => v.validate(),
  );

  ValueNotifier<SuperConditionalConfig> conditionalController(
    String id, {
    SuperConditionalConfig? fallback,
  }) => _bindTypedController(
    id,
    fallback: fallback ?? SuperConditionalConfig(),
    defaults: _conditionalDefaults,
    controllers: conditionalConfigById,
    read: (a, k, f) => a.conditionalComponent(k, fallback: f),
    write: (a, k, v) => a.withConditionalComponent(k, v),
    validate: (v) => v.validate(),
  );

  ValueNotifier<SuperTreeViewConfig> treeViewController(
    String id, {
    SuperTreeViewConfig? fallback,
  }) => _bindTypedController(
    id,
    fallback: fallback ?? SuperTreeViewConfig(),
    defaults: _treeViewDefaults,
    controllers: treeViewConfigById,
    read: (a, k, f) => a.treeViewComponent(k, fallback: f),
    write: (a, k, v) => a.withTreeViewComponent(k, v),
    validate: (v) => v.validate(),
  );

  ValueNotifier<SuperTableConfig> tableController(
    String id, {
    SuperTableConfig? fallback,
  }) => _bindTypedController(
    id,
    fallback: fallback ?? SuperTableConfig(),
    defaults: _tableDefaults,
    controllers: tableConfigById,
    read: (a, k, f) => a.tableComponent(k, fallback: f),
    write: (a, k, v) => a.withTableComponent(k, v),
    validate: (v) => v.validate(),
  );

  ValueNotifier<NativeComponentConfig> nativeComponentController(
    String id, {
    NativeComponentConfig? fallback,
    NativeComponentConfig? Function(Appearance)? legacy,
  }) {
    final initial = fallback ?? NativeComponentConfig();
    _nativeDefaults.putIfAbsent(id, () => initial);
    if (legacy != null) _nativeMigrations[id] = legacy;
    final notifier = nativeComponentConfigById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance == null ? initial : _nativeValue(_appearance!.value, id),
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withNativeComponent(
            id,
            notifier.value,
          );
        }
      }

      _listeners[notifier] = write;
      notifier.addListener(write);
    }
    return notifier;
  }

  NativeComponentConfig _nativeValue(Appearance appearance, String id) =>
      appearance.tryComponent<NativeComponentConfig>(id) ??
      _nativeMigrations[id]?.call(appearance) ??
      _nativeDefaults[id]!;

  void registerComponent(String key, RegisteredComponent component) {
    if (components.containsKey(key) || registry.containsKey(key)) {
      throw StateError('Composant déjà enregistré : $key');
    }
    components[key] = component.registeredKey == null &&
            component.runtimeType == RegisteredComponent
        ? RegisteredComponent(
            label: component.label,
            builder: component._builder,
            instanceBuilder: component.instanceBuilder,
            slotId: component.slotId,
            sizing: component.sizing,
            preferredSize: component.preferredSize,
            isAvailable: component.isAvailable,
            tags: component.tags,
            placementTags: component.placementTags,
            menuIcon: component.menuIcon,
            duplication: component.duplication,
            addConfigurator: component.addConfigurator,
            previewBuilder: component.previewBuilder,
            decomposableOnExport: component.decomposableOnExport,
            registeredKey: key,
          )
        : component;
  }

  RegisteredComponent component(String key) {
    final result = components[key];
    if (result == null) {
      throw StateError('Composant inconnu : $key');
    }
    return result;
  }

  /// Retourne les options d'export de composant pour l'instance [id], ou `null` si aucune n'est définie.
  ComponentExportOptions? exportOptionsFor(String id) => exportOptionsById[id];

  /// Enregistre ou met à jour les options d'export de composant pour l'instance [id].
  void setExportOptions(String id, ComponentExportOptions options) {
    if (!options.generateComponentOnExport &&
        !options.forceComponentOnExport &&
        options.componentName.trim().isEmpty) {
      exportOptionsById.remove(id);
    } else {
      exportOptionsById[id] = options;
    }
  }

  /// Enregistre une extension de composant ([SuperComponentExtension]) dans ce registre.
  void registerExtension(
    SuperComponentExtension extension, {
    List<String> availableFontFamilies = defaultAvailableFontFamilies,
  }) {
    extension.registerCodecs();
    extension.register(this, availableFontFamilies: availableFontFamilies);
  }

  /// Enregistre plusieurs extensions de composants dans ce registre.
  void registerExtensions(
    Iterable<SuperComponentExtension> extensions, {
    List<String> availableFontFamilies = defaultAvailableFontFamilies,
  }) {
    for (final extension in extensions) {
      registerExtension(
        extension,
        availableFontFamilies: availableFontFamilies,
      );
    }
  }

  void bootstrap({
    List<String> availableFontFamilies = defaultAvailableFontFamilies,
  }) {
    registry['Renderer'] = ComponentBuilderDynamic(
      label: 'SuperRenderer / Apparence JSON',
      menuIcon: Icons.web,
      tags: const {'renderer', 'layout'},
      duplication: ComponentDuplicationContract.component,
      addConfigurator: superRendererAddConfigurator,
      previewBuilder: (_) => const Center(child: Icon(Icons.web, size: 40)),
      dartGenerator: const SuperRendererDartGenerator(),
      dynamicBuilder: (ctx) => SuperRenderer(id: ctx.id),
    );
    registry['Layout'] = ComponentBuilderDynamic(
      menuIcon: Icons.dashboard_outlined,
      duplication: ComponentDuplicationContract.newLayout,
      tags: const {'layout'},
      addConfigurator: layoutAddConfigurator,
      previewBuilder: _buildLayoutPreview,
      dartGenerator: const SuperLayoutDartGenerator(),
      dynamicBuilder: (xuiCtx) => Builder(
        builder: (ctx) {
          final id = xuiCtx.id;

          return BuilderSlot(
            id: id,
            label: 'Layout',
            builder: (ctx) {
              final superapp = SuperApp.of(ctx);
              final superLayoutConfig = superapp.getLayoutConfigById(id);
              return ValueListenableBuilder<SuperLayoutConfig>(
                valueListenable: superLayoutConfig,
                builder: (context, config, _) => SuperLayout(
                  id: id,
                  config: config,
                  onChanged: (value) => superLayoutConfig.value = value,
                ),
              );
            },
          );
        },
      ),
    );

    registry['Card'] = ComponentBuilderDynamic(
      menuIcon: Icons.crop_square,
      label: 'Card / Container / Image',
      duplication: ComponentDuplicationContract.newContainer,
      tags: const {'container'},
      addConfigurator: containerAddConfigurator,
      previewBuilder: _buildCardPreview,
      dartGenerator: const SuperCardDartGenerator(),
      dynamicBuilder: (xuiCtx) => Builder(
        builder: (context) {
          final style = SuperApp.of(context).getContainerStyleById(xuiCtx.id);
          return ValueListenableBuilder<ContainerStyle>(
            valueListenable: style,
            builder: (context, value, _) => EditableSurface(
              id: xuiCtx.id,
              label: 'Card',
              menuType: 'Card',
              style: value,
              onStyleChanged: (value) => style.value = value,
            ),
          );
        },
      ),
    );

    registry['Value'] = ComponentBuilderDynamic(
      menuIcon: Icons.text_fields,
      label: 'Text / Input',
      duplication: ComponentDuplicationContract.superValue,
      tags: const {'text', 'input'},
      addConfigurator: superValueAddConfigurator(availableFontFamilies),
      previewBuilder: _buildValuePreview,
      dartGenerator: const SuperValueDartGenerator(),
      dynamicBuilder: (ctx) =>
          SuperValue(id: ctx.id, availableFontFamilies: availableFontFamilies),
    );

    registry['Action'] = ComponentBuilderDynamic(
      menuIcon: Icons.smart_button_outlined,
      label: 'Action / Button',
      duplication: ComponentDuplicationContract.superAction,
      tags: const {'action', 'button', 'input'},
      addConfigurator: superActionAddConfigurator(availableFontFamilies),
      previewBuilder: _buildActionPreview,
      dartGenerator: const SuperActionDartGenerator(),
      dynamicBuilder: (ctx) =>
          SuperAction(id: ctx.id, availableFontFamilies: availableFontFamilies),
    );

    registry['Indicator'] = ComponentBuilderDynamic(
      menuIcon: Icons.adjust_outlined,
      label: 'Indicator / Icon',
      duplication: ComponentDuplicationContract.superIndicator,
      tags: const {'indicator', 'icon', 'text'},
      addConfigurator: superIndicatorAddConfigurator(availableFontFamilies),
      previewBuilder: _buildIndicatorPreview,
      dartGenerator: const SuperIndicatorDartGenerator(),
      dynamicBuilder: (ctx) => SuperIndicator(
        id: ctx.id,
        availableFontFamilies: availableFontFamilies,
      ),
    );

    registry['Separator'] = ComponentBuilderDynamic(
      menuIcon: Icons.horizontal_rule,
      label: 'Separator / Divider / Spacer',
      duplication: ComponentDuplicationContract.superSeparator,
      tags: const {'separator', 'divider', 'spacer'},
      addConfigurator: superSeparatorAddConfigurator(availableFontFamilies),
      previewBuilder: _buildSeparatorPreview,
      dartGenerator: const SuperSeparatorDartGenerator(),
      dynamicBuilder: (ctx) => SuperSeparator(
        id: ctx.id,
        availableFontFamilies: availableFontFamilies,
      ),
    );

    registry['ApplicationBar'] = ComponentBuilderDynamic(
      menuIcon: Icons.web_asset,
      duplication: ComponentDuplicationContract.superAppBar,
      tags: const {'appBar'},
      placementTags: const {'appBar'},
      previewBuilder: _buildApplicationBarPreview,
      dartGenerator: const SuperNativeComponentDartGenerator(
        widgetClassName: 'SuperAppBar',
        defaultLabel: 'ApplicationBar',
      ),
      dynamicBuilder: (ctx) => SuperAppBar(id: ctx.id),
    );

    registry['BottomNavigationBar'] = ComponentBuilderDynamic(
      menuIcon: Icons.space_dashboard_outlined,
      duplication: ComponentDuplicationContract.superBottomNavigationBar,
      tags: const {'bottomNavigationBar'},
      placementTags: const {'bottomNavigationBar'},
      previewBuilder: _buildBottomNavigationBarPreview,
      dartGenerator: const SuperNativeComponentDartGenerator(
        widgetClassName: 'SuperBottomNavigationBar',
        defaultLabel: 'Barre de navigation',
      ),
      dynamicBuilder: (ctx) => SuperBottomNavigationBar(id: ctx.id),
    );

    registry['BottomAppBar'] = ComponentBuilderDynamic(
      menuIcon: Icons.call_to_action_outlined,
      duplication: ComponentDuplicationContract.superBottomAppBar,
      tags: const {'bottomNavigationBar', 'bottomAppBar'},
      placementTags: const {'bottomNavigationBar'},
      previewBuilder: _buildBottomAppBarPreview,
      dartGenerator: const SuperNativeComponentDartGenerator(
        widgetClassName: 'SuperBottomAppBar',
        defaultLabel: 'Barre basse',
      ),
      dynamicBuilder: (ctx) => SuperBottomAppBar(id: ctx.id),
    );

    registry['NavigationRail'] = ComponentBuilderDynamic(
      menuIcon: Icons.view_sidebar_outlined,
      duplication: ComponentDuplicationContract.superNavigationRail,
      tags: const {'navigationRail'},
      previewBuilder: _buildNavigationRailPreview,
      dartGenerator: const SuperNativeComponentDartGenerator(
        widgetClassName: 'SuperNavigationRail',
        defaultLabel: 'Rail de navigation',
      ),
      dynamicBuilder: (ctx) => SuperNavigationRail(id: ctx.id),
    );

    registry['Expansible'] = ComponentBuilderDynamic(
      menuIcon: Icons.unfold_more_outlined,
      duplication: ComponentDuplicationContract.superExpansible,
      tags: const {'container', 'layout', 'expansible'},
      addConfigurator: expansibleAddConfigurator,
      previewBuilder: _buildExpansiblePreview,
      dartGenerator: const SuperNativeComponentDartGenerator(
        widgetClassName: 'SuperExpansible',
        defaultLabel: 'Expansible',
      ),
      dynamicBuilder: (ctx) => SuperExpansible(id: ctx.id),
    );

    registry['Menu'] = ComponentBuilderDynamic(
      menuIcon: Icons.menu_open_outlined,
      duplication: ComponentDuplicationContract.superMenuAnchor,
      tags: const {'container', 'layout', 'menu'},
      addConfigurator: menuAnchorAddConfigurator,
      previewBuilder: _buildMenuPreview,
      dartGenerator: const SuperNativeComponentDartGenerator(
        widgetClassName: 'SuperMenuAnchor',
        defaultLabel: 'Menu',
      ),
      dynamicBuilder: (ctx) => SuperMenuAnchor(id: ctx.id),
    );

    registry['Tab'] = ComponentBuilderDynamic(
      menuIcon: Icons.tab_outlined,
      duplication: ComponentDuplicationContract.superTab,
      tags: const {'container', 'layout', 'tab'},
      addConfigurator: tabAddConfigurator,
      previewBuilder: _buildTabPreview,
      dartGenerator: const SuperTabDartGenerator(),
      dynamicBuilder: (ctx) => SuperTab(id: ctx.id),
    );

    registry['Conditional'] = ComponentBuilderDynamic(
      label: 'Conditional / Switch',
      menuIcon: Icons.call_split_outlined,
      duplication: ComponentDuplicationContract.superConditional,
      tags: const {'container', 'layout', 'conditional', 'data'},
      addConfigurator: conditionalAddConfigurator,
      previewBuilder: _buildConditionalPreview,
      dartGenerator: const SuperConditionalDartGenerator(),
      dynamicBuilder: (ctx) => SuperConditional(id: ctx.id),
    );

    registry['IterableContent'] = ComponentBuilderDynamic(
      menuIcon: Icons.article_outlined,
      duplication: ComponentDuplicationContract.iterableContent,
      tags: const {'container', 'layout'},
      placementTags: const {'list'},
      addConfigurator: containerAddConfigurator,
      previewBuilder: _buildIterableContentPreview,
      dartGenerator: const SuperIterableContentDartGenerator(),
      dynamicBuilder: (ctx) => IterableContent(id: ctx.id),
    );
    registry['ListView'] = ComponentBuilderDynamic(
      menuIcon: Icons.view_list,
      duplication: ComponentDuplicationContract.superListView,
      tags: const {'list', 'layout'},
      addConfigurator: listViewAddConfigurator,
      previewBuilder: _buildListViewPreview,
      dartGenerator: const SuperListViewDartGenerator(),
      dynamicBuilder: (xuiCtx) => BuilderSlot(
        id: xuiCtx.id,
        label: 'Liste',
        builder: (_) => SuperListView(id: xuiCtx.id),
      ),
    );

    registry['TreeView'] = ComponentBuilderDynamic(
      menuIcon: Icons.account_tree_outlined,
      label: 'TreeView',
      duplication: ComponentDuplicationContract.superTreeView,
      tags: const {'tree', 'list', 'layout', 'data'},
      addConfigurator: treeViewAddConfigurator,
      previewBuilder: _buildTreeViewPreview,
      dartGenerator: const SuperTreeViewDartGenerator(),
      dynamicBuilder: (ctx) => SuperTreeView(id: ctx.id),
    );

    registry['Table'] = ComponentBuilderDynamic(
      menuIcon: Icons.table_chart_outlined,
      label: 'Table',
      duplication: ComponentDuplicationContract.superTable,
      tags: const {'table', 'list', 'layout', 'data'},
      addConfigurator: tableAddConfigurator,
      previewBuilder: _buildTablePreview,
      dartGenerator: const SuperTableDartGenerator(),
      dynamicBuilder: (ctx) => SuperTable(id: ctx.id),
    );
  }

  Widget getWidget(String key, XuiBuildCtx ctx) =>
      registry[key]?.getWidget(ctx) ?? const SizedBox();
}

/// Implémentation de [ComponentBuilder] construisant dynamiquement un widget à partir du [XuiBuildCtx].
class ComponentBuilderDynamic extends ComponentBuilder {
  final Widget Function(XuiBuildCtx) dynamicBuilder;

  ComponentBuilderDynamic({
    required this.dynamicBuilder,
    super.label,
    super.tags,
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

/// Options d'export en code Dart configurées pour une instance de composant (« Configure as... »).
@immutable
class ComponentExportOptions {
  const ComponentExportOptions({
    this.componentName = '',
    this.generateComponentOnExport = false,
    this.forceComponentOnExport = false,
  });

  /// Nom (clé de registre) utilisé pour `_registry.registerComponent(...)`.
  final String componentName;

  /// Indique que cette instance doit générer un composant dédié lors de l'export en code Dart.
  final bool generateComponentOnExport;

  /// Indique que ce composant ne doit jamais être décomposé lors de l'export (même si « Décomposer les composants composés » est actif).
  final bool forceComponentOnExport;

  ComponentExportOptions copyWith({
    String? componentName,
    bool? generateComponentOnExport,
    bool? forceComponentOnExport,
  }) => ComponentExportOptions(
    componentName: componentName ?? this.componentName,
    generateComponentOnExport:
        generateComponentOnExport ?? this.generateComponentOnExport,
    forceComponentOnExport:
        forceComponentOnExport ?? this.forceComponentOnExport,
  );

  Map<String, Object?> toJson() => {
    'componentName': componentName,
    'generateComponentOnExport': generateComponentOnExport,
    'forceComponentOnExport': forceComponentOnExport,
  };

  factory ComponentExportOptions.fromJson(Map<String, Object?> json) =>
      ComponentExportOptions(
        componentName: (json['componentName'] as String?) ?? '',
        generateComponentOnExport:
            (json['generateComponentOnExport'] as bool?) ?? false,
        forceComponentOnExport:
            (json['forceComponentOnExport'] as bool?) ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is ComponentExportOptions &&
      other.componentName == componentName &&
      other.generateComponentOnExport == generateComponentOnExport &&
      other.forceComponentOnExport == forceComponentOnExport;

  @override
  int get hashCode => Object.hash(
    componentName,
    generateComponentOnExport,
    forceComponentOnExport,
  );
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

/// Définition d'un composant applicatif enregistré dans le [Registry] pour être inséré comme slot.
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
