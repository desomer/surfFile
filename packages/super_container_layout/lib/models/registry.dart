import 'package:material_ui/material_ui.dart';

import 'component_config.dart';
import 'native_component_config.dart';
import 'super_list_view_config.dart';
import 'super_tab_config.dart';
import 'super_table_config.dart';
import 'super_tree_view_config.dart';
import 'super_chart_config.dart';
import 'super_value_config.dart';
import 'super_action_config.dart';
import '../widgets/components/super_list_view.dart';
import '../widgets/components/super_tab.dart';
import '../widgets/components/super_table.dart';
import '../widgets/components/super_tree_view.dart';
import '../widgets/components/super_chart.dart';
import '../widgets/components/super_value.dart';
import '../widgets/components/super_action.dart';
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
import '../services/pages/editor_page_graph.dart';
import '../widgets/editing/addition/component_add_configurators.dart';
import '../widgets/editing/addition/component_add_wizard.dart';

import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/components/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';

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
  list,
  tab,
  chart,
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
  const EditorConfigRef.list(this.id) : kind = EditorConfigKind.list;
  const EditorConfigRef.tab(this.id) : kind = EditorConfigKind.tab;
  const EditorConfigRef.chart(this.id) : kind = EditorConfigKind.chart;
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
  static List<EditorConfigRef> _chart(String id) => [EditorConfigRef.chart(id)];
  static List<EditorConfigRef> _treeView(String id) => [
    EditorConfigRef.style(id),
    EditorConfigRef.treeView(id),
  ];
  static List<EditorConfigRef> _table(String id) => [
    EditorConfigRef.style(id),
    EditorConfigRef.table(id),
  ];

  /// Contracts of the components installed by [Registry.bootstrap].
  static const superValue = ComponentDuplicationContract(ownedConfigs: _value);
  static const superAction = ComponentDuplicationContract(
    ownedConfigs: _action,
  );
  static const superTab = ComponentDuplicationContract(ownedConfigs: _tab);
  static const superChart = ComponentDuplicationContract(ownedConfigs: _chart);
  static const superTreeView = ComponentDuplicationContract(
    ownedConfigs: _treeView,
  );
  static const superTable = ComponentDuplicationContract(
    ownedConfigs: _table,
  );
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

class ComponentBuilder {
  ComponentBuilder({
    this.label,
    this.tags = const {},
    this.placementTags = const {},
    this.menuIcon,
    this.duplication,
    this.addConfigurator,
    this.previewBuilder,
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

  Widget getWidget(XuiBuildCtx ctx) {
    return SizedBox.shrink();
  }
}

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
  });

  final Widget widget;

  @override
  Widget getWidget(XuiBuildCtx ctx) {
    return widget;
  }
}

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
  final Map<String, ValueNotifier<SuperValueConfig>> valueConfigById = {};
  final Map<String, SuperValueConfig> _valueDefaults = {};
  final Map<String, ValueNotifier<SuperActionConfig>> actionConfigById = {};
  final Map<String, SuperActionConfig> _actionDefaults = {};
  final Map<String, ValueNotifier<SuperListViewConfig>> listConfigById = {};
  final Map<String, SuperListViewConfig> _listDefaults = {};
  final Map<String, ValueNotifier<SuperTabConfig>> tabConfigById = {};
  final Map<String, SuperTabConfig> _tabDefaults = {};
  final Map<String, ValueNotifier<SuperChartConfig>> chartConfigById = {};
  final Map<String, SuperChartConfig> _chartDefaults = {};
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
    ...listConfigById.keys,
    ...tabConfigById.keys,
    ...chartConfigById.keys,
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
      for (final entry in listConfigById.entries) entry.key: entry.value.value,
      for (final entry in tabConfigById.entries) entry.key: entry.value.value,
      for (final entry in chartConfigById.entries) entry.key: entry.value.value,
      for (final entry in treeViewConfigById.entries)
        entry.key: entry.value.value,
      for (final entry in tableConfigById.entries)
        entry.key: entry.value.value,
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
      componentController<ComponentConfig>(
        entry.key,
        fallback: entry.value.value,
      );
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
    for (final entry in listConfigById.entries.toList()) {
      listController(entry.key, fallback: entry.value.value);
    }
    for (final entry in tabConfigById.entries.toList()) {
      _tabDefaults[entry.key] = entry.value.value;
      tabController(entry.key, fallback: entry.value.value);
    }
    for (final entry in chartConfigById.entries.toList()) {
      _chartDefaults[entry.key] = entry.value.value;
      chartController(entry.key, fallback: entry.value.value);
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

  ValueNotifier<SuperLayoutConfig> layoutController(
    String id, {
    SuperLayoutConfig fallback = const SuperLayoutConfig(),
  }) {
    _layoutDefaults.putIfAbsent(id, () => fallback);
    final notifier = superLayoutConfigById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance?.value.layout(id, fallback: fallback) ?? fallback,
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withLayout(
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

  ValueNotifier<ContainerStyle> styleController(
    String id, {
    ContainerStyle fallback = const ContainerStyle(),
  }) {
    _styleDefaults.putIfAbsent(id, () => fallback);
    final notifier = containerStyleById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance?.value.style(id, fallback: fallback) ?? fallback,
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withStyle(id, notifier.value);
        }
      }

      _listeners[notifier] = write;
      notifier.addListener(write);
    }
    return notifier;
  }

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
        entry.value.value = appearance.component(
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
      for (final entry in chartConfigById.entries) {
        entry.value.value = appearance.chartComponent(
          entry.key,
          fallback: _chartDefaults[entry.key]!,
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

  ValueNotifier<T> componentController<T extends ComponentConfig>(
    String id, {
    required T fallback,
  }) {
    fallback.validate();
    _componentDefaults.putIfAbsent(id, () => fallback);
    final notifier = componentConfigById.putIfAbsent(
      id,
      () => ValueNotifier<T>(
        _appearance?.value.component<T>(id, fallback: fallback) ?? fallback,
      ),
    );
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
    return notifier as ValueNotifier<T>;
  }

  ValueNotifier<SuperValueConfig> valueController(
    String id, {
    SuperValueConfig fallback = const SuperValueConfig(),
  }) {
    fallback.validate();
    _valueDefaults.putIfAbsent(id, () => fallback);
    final notifier = valueConfigById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance?.value.valueComponent(id, fallback: fallback) ?? fallback,
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        notifier.value.validate();
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withValueComponent(
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

  ValueNotifier<SuperActionConfig> actionController(
    String id, {
    SuperActionConfig fallback = const SuperActionConfig(),
  }) {
    fallback.validate();
    _actionDefaults.putIfAbsent(id, () => fallback);
    final notifier = actionConfigById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance?.value.actionComponent(id, fallback: fallback) ?? fallback,
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        notifier.value.validate();
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withActionComponent(
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

  ValueNotifier<SuperListViewConfig> listController(
    String id, {
    SuperListViewConfig fallback = const SuperListViewConfig(),
  }) {
    fallback.validate();
    _listDefaults.putIfAbsent(id, () => fallback);
    final notifier = listConfigById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance?.value.listComponent(id, fallback: fallback) ?? fallback,
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        notifier.value.validate();
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withListComponent(
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

  ValueNotifier<SuperTabConfig> tabController(
    String id, {
    SuperTabConfig? fallback,
  }) {
    final initial = fallback ?? SuperTabConfig();
    initial.validate();
    _tabDefaults.putIfAbsent(id, () => initial);
    final notifier = tabConfigById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance?.value.tabComponent(id, fallback: initial) ?? initial,
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        notifier.value.validate();
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withTabComponent(
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

  ValueNotifier<SuperChartConfig> chartController(
    String id, {
    SuperChartConfig fallback = const SuperChartConfig(),
  }) {
    fallback.validate();
    _chartDefaults.putIfAbsent(id, () => fallback);
    final notifier = chartConfigById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance?.value.chartComponent(id, fallback: fallback) ?? fallback,
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        notifier.value.validate();
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withChartComponent(
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

  ValueNotifier<SuperTreeViewConfig> treeViewController(
    String id, {
    SuperTreeViewConfig? fallback,
  }) {
    final initial = fallback ?? SuperTreeViewConfig();
    initial.validate();
    _treeViewDefaults.putIfAbsent(id, () => initial);
    final notifier = treeViewConfigById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance?.value.treeViewComponent(id, fallback: initial) ?? initial,
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        notifier.value.validate();
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withTreeViewComponent(
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

  ValueNotifier<SuperTableConfig> tableController(
    String id, {
    SuperTableConfig? fallback,
  }) {
    final initial = fallback ?? SuperTableConfig();
    initial.validate();
    _tableDefaults.putIfAbsent(id, () => initial);
    final notifier = tableConfigById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance?.value.tableComponent(id, fallback: initial) ?? initial,
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        notifier.value.validate();
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withTableComponent(
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
    components[key] = component;
  }

  RegisteredComponent component(String key) {
    final result = components[key];
    if (result == null) {
      throw StateError('Composant inconnu : $key');
    }
    return result;
  }

  void bootstrap({
    List<String> availableFontFamilies = defaultAvailableFontFamilies,
  }) {
    registry['Layout'] = ComponentBuilderDynamic(
      menuIcon: Icons.dashboard_outlined,
      duplication: ComponentDuplicationContract.newLayout,
      tags: const {'layout'},
      addConfigurator: layoutAddConfigurator,
      previewBuilder: _buildLayoutPreview,
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

    registry['Value'] = ComponentBuilderDynamic(
      menuIcon: Icons.text_fields,
      label: 'Text / Input',
      duplication: ComponentDuplicationContract.superValue,
      tags: const {'text', 'input'},
      addConfigurator: superValueAddConfigurator(availableFontFamilies),
      previewBuilder: _buildValuePreview,
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
      dynamicBuilder: (ctx) =>
          SuperAction(id: ctx.id, availableFontFamilies: availableFontFamilies),
    );

    registry['Card'] = ComponentBuilderDynamic(
      menuIcon: Icons.crop_square,
      label: 'Card / Image',
      duplication: ComponentDuplicationContract.newContainer,
      tags: const {'container'},
      addConfigurator: containerAddConfigurator,
      previewBuilder: _buildCardPreview,
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

    registry['ApplicationBar'] = ComponentBuilderDynamic(
      menuIcon: Icons.web_asset,
      duplication: ComponentDuplicationContract.superAppBar,
      tags: const {'appBar'},
      placementTags: const {'appBar'},
      previewBuilder: _buildApplicationBarPreview,
      dynamicBuilder: (ctx) => SuperAppBar(id: ctx.id),
    );

    registry['BottomNavigationBar'] = ComponentBuilderDynamic(
      menuIcon: Icons.space_dashboard_outlined,
      duplication: ComponentDuplicationContract.superBottomNavigationBar,
      tags: const {'bottomNavigationBar'},
      placementTags: const {'bottomNavigationBar'},
      previewBuilder: _buildBottomNavigationBarPreview,
      dynamicBuilder: (ctx) => SuperBottomNavigationBar(id: ctx.id),
    );

    registry['BottomAppBar'] = ComponentBuilderDynamic(
      menuIcon: Icons.call_to_action_outlined,
      duplication: ComponentDuplicationContract.superBottomAppBar,
      tags: const {'bottomNavigationBar', 'bottomAppBar'},
      placementTags: const {'bottomNavigationBar'},
      previewBuilder: _buildBottomAppBarPreview,
      dynamicBuilder: (ctx) => SuperBottomAppBar(id: ctx.id),
    );

    registry['NavigationRail'] = ComponentBuilderDynamic(
      menuIcon: Icons.view_sidebar_outlined,
      duplication: ComponentDuplicationContract.superNavigationRail,
      tags: const {'navigationRail'},
      previewBuilder: _buildNavigationRailPreview,
      dynamicBuilder: (ctx) => SuperNavigationRail(id: ctx.id),
    );

    registry['Expansible'] = ComponentBuilderDynamic(
      menuIcon: Icons.unfold_more_outlined,
      duplication: ComponentDuplicationContract.superExpansible,
      tags: const {'container', 'layout', 'expansible'},
      addConfigurator: expansibleAddConfigurator,
      previewBuilder: _buildExpansiblePreview,
      dynamicBuilder: (ctx) => SuperExpansible(id: ctx.id),
    );

    registry['Menu'] = ComponentBuilderDynamic(
      menuIcon: Icons.menu_open_outlined,
      duplication: ComponentDuplicationContract.superMenuAnchor,
      tags: const {'container', 'layout', 'menu'},
      addConfigurator: menuAnchorAddConfigurator,
      previewBuilder: _buildMenuPreview,
      dynamicBuilder: (ctx) => SuperMenuAnchor(id: ctx.id),
    );

    registry['Tab'] = ComponentBuilderDynamic(
      menuIcon: Icons.tab_outlined,
      duplication: ComponentDuplicationContract.superTab,
      tags: const {'container', 'layout', 'tab'},
      addConfigurator: tabAddConfigurator,
      previewBuilder: _buildTabPreview,
      dynamicBuilder: (ctx) => SuperTab(id: ctx.id),
    );

    registry['Chart'] = ComponentBuilderDynamic(
      menuIcon: Icons.insert_chart_outlined,
      label: 'Chart / Graphique',
      duplication: ComponentDuplicationContract.superChart,
      tags: const {'chart', 'data'},
      addConfigurator: chartAddConfigurator,
      previewBuilder: _buildChartPreview,
      dynamicBuilder: (ctx) => SuperChart(id: ctx.id),
    );

    registry['IterableContent'] = ComponentBuilderDynamic(
      menuIcon: Icons.article_outlined,
      duplication: ComponentDuplicationContract.iterableContent,
      tags: const {'container', 'layout'},
      placementTags: const {'list'},
      addConfigurator: containerAddConfigurator,
      previewBuilder: _buildIterableContentPreview,
      dynamicBuilder: (ctx) => IterableContent(id: ctx.id),
    );
    registry['ListView'] = ComponentBuilderDynamic(
      menuIcon: Icons.view_list,
      duplication: ComponentDuplicationContract.superListView,
      tags: const {'list', 'layout'},
      addConfigurator: listViewAddConfigurator,
      previewBuilder: _buildListViewPreview,
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
      dynamicBuilder: (ctx) => SuperTreeView(id: ctx.id),
    );

    registry['Table'] = ComponentBuilderDynamic(
      menuIcon: Icons.table_chart_outlined,
      label: 'Table',
      duplication: ComponentDuplicationContract.superTable,
      tags: const {'table', 'list', 'layout', 'data'},
      addConfigurator: tableAddConfigurator,
      previewBuilder: _buildTablePreview,
      dynamicBuilder: (ctx) => SuperTable(id: ctx.id),
    );
  }

  Widget getWidget(String key, XuiBuildCtx ctx) =>
      registry[key]?.getWidget(ctx) ?? const SizedBox();
}

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
  });

  @override
  Widget getWidget(XuiBuildCtx ctx) => dynamicBuilder(ctx);
}

class RegisteredComponent {
  const RegisteredComponent({
    required this.label,
    required this.builder,
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
  });

  final String label;
  final WidgetBuilder builder;

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
    builder: builder,
    tags: tags,
    menuIcon: menuIcon,
  );
}

Widget _previewZoneBox(
  BuildContext context,
  String label, {
  bool highlighted = false,
}) {
  final colors = Theme.of(context).colorScheme;
  return Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: highlighted ? colors.primaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: highlighted ? colors.primary : colors.outlineVariant,
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
        color: highlighted
            ? colors.onPrimaryContainer
            : colors.onSurfaceVariant,
      ),
    ),
  );
}

Widget _buildLayoutPreview(BuildContext context) => IgnorePointer(
  child: SizedBox(
    height: 92,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _previewZoneBox(context, 'Nord'),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _previewZoneBox(context, 'Ouest')),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: _previewZoneBox(context, 'Centre', highlighted: true),
              ),
              const SizedBox(width: 4),
              Expanded(child: _previewZoneBox(context, 'Est')),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _previewZoneBox(context, 'Sud'),
      ],
    ),
  ),
);

Widget _buildValuePreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Texte affiché', style: theme.textTheme.bodyMedium),
        SizedBox(
          width: 180,
          child: InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Champ de saisie',
              border: OutlineInputBorder(),
            ),
            child: Text(
              'Valeur…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: true, onChanged: (_) {}),
            Switch(value: true, onChanged: (_) {}),
          ],
        ),
      ],
    ),
  );
}

Widget _buildActionPreview(BuildContext context) => IgnorePointer(
  child: Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilledButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.play_arrow, size: 16),
        label: const Text('Action principale'),
      ),
      OutlinedButton(onPressed: () {}, child: const Text('Secondaire')),
      IconButton.filledTonal(
        onPressed: () {},
        icon: const Icon(Icons.bolt, size: 18),
      ),
    ],
  ),
);

Widget _buildCardPreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.crop_square, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Card', style: theme.textTheme.titleSmall),
                Text(
                  'Surface stylable (couleur, bordure, rayon, marges)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildApplicationBarPreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.menu, size: 18, color: colors.onSurface),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Barre d’application',
              style: theme.textTheme.titleSmall,
            ),
          ),
          Icon(Icons.search, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Icon(Icons.more_vert, size: 18, color: colors.onSurfaceVariant),
        ],
      ),
    ),
  );
}

Widget _buildBottomNavigationBarPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget item(IconData icon, String label, {bool selected = false}) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? colors.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 16,
            color: selected
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? colors.onSurface : colors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
  return IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          item(Icons.home_outlined, 'Accueil', selected: true),
          item(Icons.search_outlined, 'Recherche'),
          item(Icons.person_outline, 'Profil'),
        ],
      ),
    ),
  );
}

Widget _buildBottomAppBarPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return IgnorePointer(
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.menu, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Icon(Icons.search, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Icon(Icons.favorite_border, size: 18, color: colors.onSurfaceVariant),
          const Spacer(),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.add, size: 16, color: colors.onPrimaryContainer),
          ),
        ],
      ),
    ),
  );
}

Widget _buildNavigationRailPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return IgnorePointer(
    child: SizedBox(
      height: 84,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: colors.onSecondaryContainer,
                  ),
                ),
                Icon(
                  Icons.analytics_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _previewZoneBox(context, 'Contenu de la destination'),
          ),
        ],
      ),
    ),
  );
}

Widget _buildExpansiblePreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'En-tête repliable',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Icon(
                  Icons.expand_less,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _previewZoneBox(context, 'Contenu déplié'),
          ),
        ],
      ),
    ),
  );
}

Widget _buildMenuPreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Row(
      children: [
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.menu_open_outlined, size: 16),
          label: const Text('Menu'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('• Option 1', style: theme.textTheme.bodySmall),
                Text('• Option 2', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildTabPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget tab(String title, {bool selected = false}) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
    ),
  );
  return IgnorePointer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            tab('Onglet 1', selected: true),
            tab('Onglet 2'),
            tab('Onglet 3'),
          ],
        ),
        const SizedBox(height: 6),
        _previewZoneBox(
          context,
          'Contenu de l’onglet actif',
          highlighted: true,
        ),
      ],
    ),
  );
}

Widget _buildIterableContentPreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.repeat, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Modèle d’élément répété (ligne / carte de liste)',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildListViewPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget row(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: colors.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(Icons.drag_handle, size: 14, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
  return IgnorePointer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row('Élément de liste 1'),
        const SizedBox(height: 4),
        row('Élément de liste 2'),
        const SizedBox(height: 4),
        row('Élément de liste 3'),
      ],
    ),
  );
}

Widget _buildChartPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget bar(double height, Color color) => Container(
    width: 14,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );
  return IgnorePointer(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          bar(20, colors.primary.withValues(alpha: 0.65)),
          bar(36, colors.primary),
          bar(28, colors.tertiary),
          bar(44, colors.primary),
          bar(32, colors.secondary),
        ],
      ),
    ),
  );
}

Widget _buildTreeViewPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget nodeRow(String header, String data, {int depth = 0}) => Padding(
    padding: EdgeInsets.only(left: depth * 16.0),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            depth == 0 ? Icons.arrow_drop_down : Icons.subdirectory_arrow_right,
            size: 14,
            color: colors.primary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              header,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            width: 1,
            height: 12,
            color: colors.outlineVariant,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          Expanded(child: Text(data, style: const TextStyle(fontSize: 11))),
        ],
      ),
    ),
  );
  return IgnorePointer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        nodeRow('Header (Parent)', 'Data'),
        const SizedBox(height: 4),
        nodeRow('Header (Enfant)', 'Data', depth: 1),
      ],
    ),
  );
}

Widget _buildTablePreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget tableRow(List<String> cells, {bool header = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: header ? colors.surfaceContainerHighest : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: colors.outlineVariant),
    ),
    child: Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 12,
              color: colors.outlineVariant,
              margin: const EdgeInsets.symmetric(horizontal: 6),
            ),
          Expanded(
            child: Text(
              cells[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: header ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    ),
  );
  return IgnorePointer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        tableRow(const ['Col 1', 'Col 2', 'Col 3'], header: true),
        const SizedBox(height: 3),
        tableRow(const ['Val A1', 'Val A2', 'Val A3']),
        const SizedBox(height: 3),
        tableRow(const ['Val B1', 'Val B2', 'Val B3']),
      ],
    ),
  );
}
