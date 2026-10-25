import 'package:material_ui/material_ui.dart';

import 'component_config.dart';
import 'native_component_config.dart';
import 'super_list_view_config.dart';
import 'super_value_config.dart';
import 'super_action_config.dart';
import '../widgets/components/super_list_view.dart';
import '../widgets/components/super_value.dart';
import '../widgets/components/super_action.dart';
import '../widgets/super_layout/iterable_content.dart';

import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/scaffold_page_config.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/widgets/native/super_app_bar.dart';

import '../widgets/native/super_bottom_navigation_bar.dart';
import '../services/pages/editor_page_graph.dart';
import '../widgets/editing/addition/component_add_configurators.dart';
import '../widgets/editing/addition/component_add_wizard.dart';

import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/super_layout/super_layout.dart';
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
  static List<EditorConfigRef> _appBar(String id) => [
    EditorConfigRef.nativeComponent(id),
    // Legacy SuperLayoutConfig still migrated by SuperAppBar.
    EditorConfigRef.layout(id),
  ];

  /// Contracts of the components installed by [Registry.bootstrap].
  static const superValue = ComponentDuplicationContract(ownedConfigs: _value);
  static const superAction = ComponentDuplicationContract(
    ownedConfigs: _action,
  );
  static const superAppBar = ComponentDuplicationContract(
    ownedConfigs: _appBar,
  );
  static const superBottomNavigationBar = ComponentDuplicationContract(
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
    this.tags = const {},
    this.placementTags = const {},
    this.menuIcon,
    this.duplication,
    this.addConfigurator,
  });

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

  Widget getWidget(XuiBuildCtx ctx) {
    return SizedBox.shrink();
  }
}

class RegisteredComponentImpl extends ComponentBuilder {
  RegisteredComponentImpl({
    required this.widget,
    super.tags,
    super.placementTags,
    super.menuIcon,
    super.duplication,
    super.addConfigurator,
  });

  final Widget widget;

  @override
  Widget getWidget(XuiBuildCtx ctx) {
    return widget;
  }
}

class Registry {
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
    } finally {
      _syncing = false;
    }
  }

  void registerFactory(
    String key,
    Widget widget, {
    Set<String> tags = const {},
    IconData? menuIcon,
    ComponentDuplicationContract? duplication,
    ComponentAddConfigurator<Object>? addConfigurator,
  }) {
    registry[key] = ComponentBuilderDynamic(
      tags: tags,
      menuIcon: menuIcon,
      duplication: duplication,
      addConfigurator: addConfigurator,
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

  void bootstrap({List<String> availableFontFamilies = const []}) {
    registry['Value'] = ComponentBuilderDynamic(
      menuIcon: Icons.text_fields,
      duplication: ComponentDuplicationContract.superValue,
      tags: const {'text', 'input'},
      addConfigurator: superValueAddConfigurator(availableFontFamilies),
      dynamicBuilder: (ctx) =>
          SuperValue(id: ctx.id, availableFontFamilies: availableFontFamilies),
    );

    registry['Action'] = ComponentBuilderDynamic(
      menuIcon: Icons.smart_button_outlined,
      duplication: ComponentDuplicationContract.superAction,
      tags: const {'action', 'button', 'input'},
      addConfigurator: superActionAddConfigurator(availableFontFamilies),
      dynamicBuilder: (ctx) =>
          SuperAction(id: ctx.id, availableFontFamilies: availableFontFamilies),
    );

    registry['ApplicationBar'] = ComponentBuilderDynamic(
      menuIcon: Icons.web_asset,
      duplication: ComponentDuplicationContract.superAppBar,
      tags: const {'appBar'},
      placementTags: const {'appBar'},
      dynamicBuilder: (ctx) => SuperAppBar(id: ctx.id),
    );

    registry['BottomNavigationBar'] = ComponentBuilderDynamic(
      menuIcon: Icons.space_dashboard_outlined,
      duplication: ComponentDuplicationContract.superBottomNavigationBar,
      tags: const {'bottomNavigationBar'},
      placementTags: const {'bottomNavigationBar'},
      dynamicBuilder: (ctx) => SuperBottomNavigationBar(id: ctx.id),
    );

    registry['Card'] = ComponentBuilderDynamic(
      menuIcon: Icons.crop_square,
      duplication: ComponentDuplicationContract.newContainer,
      tags: const {'container'},
      addConfigurator: containerAddConfigurator,
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
    registry['IterableContent'] = ComponentBuilderDynamic(
      menuIcon: Icons.article_outlined,
      duplication: ComponentDuplicationContract.iterableContent,
      tags: const {'container', 'layout'},
      placementTags: const {'list'},
      addConfigurator: containerAddConfigurator,
      dynamicBuilder: (ctx) => IterableContent(id: ctx.id),
    );
    registry['ListView'] = ComponentBuilderDynamic(
      menuIcon: Icons.view_list,
      duplication: ComponentDuplicationContract.superListView,
      tags: const {'list', 'layout'},
      addConfigurator: listViewAddConfigurator,
      dynamicBuilder: (xuiCtx) => BuilderSlot(
        id: xuiCtx.id,
        label: 'Liste',
        builder: (_) => SuperListView(id: xuiCtx.id),
      ),
    );
    registry['Layout'] = ComponentBuilderDynamic(
      menuIcon: Icons.dashboard_outlined,
      duplication: ComponentDuplicationContract.newLayout,
      tags: const {'layout'},
      addConfigurator: layoutAddConfigurator,
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
                  config: config,
                  onChanged: (value) => superLayoutConfig.value = value,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget getWidget(String key, XuiBuildCtx ctx) =>
      registry[key]?.getWidget(ctx) ?? const SizedBox();
}

class ComponentBuilderDynamic extends ComponentBuilder {
  final Widget Function(XuiBuildCtx) dynamicBuilder;

  ComponentBuilderDynamic({
    required this.dynamicBuilder,
    super.tags,
    super.placementTags,
    super.menuIcon,
    super.duplication,
    super.addConfigurator,
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
