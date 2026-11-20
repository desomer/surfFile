/// Registre central des composants ([Registry]) et contrats de duplication du designer.
///
/// Maintient le catalogue des constructeurs de composants (`Registry.bootstrap`),
/// les `ValueNotifier` de configuration par identifiant d'instance et leur
/// synchronisation bidirectionnelle avec [Appearance].
library;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/a4_page_config.dart';
import 'package:super_container_layout/models/scaffold_page_config.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/container_style.dart';

import '../services/pages/editor_page_graph.dart';
import '../widgets/editing/addition/component_add_contracts.dart';
import 'component_config.dart';
import 'component_extension.dart';
import 'component_duplication_contract.dart';
import 'component_export_options.dart';
import 'component_registration.dart';
import 'native_component_config.dart';
import 'registry_builtins.dart';
import 'super_action_config.dart';
import 'super_conditional_config.dart';
import 'super_indicator_config.dart';
import 'super_list_view_config.dart';
import 'super_separator_config.dart';
import 'super_tab_config.dart';
import 'super_table_config.dart';
import 'super_tree_view_config.dart';
import 'super_value_config.dart';

export 'component_duplication_contract.dart';
export 'component_export_options.dart';
export 'component_registration.dart';

/// Registre central associant les types de composants et synchronisant leurs `ValueNotifier` par ID avec [Appearance].
class Registry {
  /// Nom du package Flutter déclarant les polices libres embarquées ([bundledPackageFontFamilies]).
  static const String fontPackageName = 'super_container_layout';

  /// Familles de polices libres (SIL OFL) embarquées dans les assets du package `super_container_layout`.
  static const Set<String> bundledPackageFontFamilies = {
    'Inter',
    'Plus Jakarta Sans',
    'Geist',
    'Geist Mono',
    'JetBrains Mono',
    'Rubik',
    'Nunito',
  };

  /// Liste par défaut des familles de polices proposées dans l'éditeur et reconnues au rendu.
  static const List<String> defaultAvailableFontFamilies = [
    'Segoe UI',
    'Inter',
    'Plus Jakarta Sans',
    'Geist',
    'Rubik',
    'Nunito',
    'Roboto',
    'Arial',
    'Verdana',
    'Tahoma',
    'Trebuchet MS',
    'Georgia',
    'Times New Roman',
    'Cascadia Mono',
    'JetBrains Mono',
    'Geist Mono',
    'Consolas',
    'Courier New',
    'monospace',
  ];

  /// Résout le nom effectif de [fontFamily] attendu par [TextStyle] :
  /// préfixe automatiquement `'packages/super_container_layout/<famille>'` pour
  /// les polices embarquées ([bundledPackageFontFamilies]) afin qu'elles s'affichent
  /// dans toute application hôte sans re-déclaration dans son `pubspec.yaml`.
  static String? resolveEffectiveFontFamily(String? fontFamily) {
    if (fontFamily == null || fontFamily.isEmpty) return fontFamily;
    if (bundledPackageFontFamilies.contains(fontFamily)) {
      return 'packages/$fontPackageName/$fontFamily';
    }
    return fontFamily;
  }

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
  final Map<String, ValueNotifier<A4PageConfig>> a4PageConfigById = {};
  final Map<String, A4PageConfig> _a4PageDefaults = {};
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
    ...scaffoldPageConfigById.keys,
    ...a4PageConfigById.keys,
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
      for (final entry in a4PageConfigById.entries)
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
    for (final entry in a4PageConfigById.entries.toList()) {
      _a4PageDefaults[entry.key] = entry.value.value;
      a4PageController(entry.key, fallback: entry.value.value);
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
      ...a4PageConfigById.values,
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
      for (final entry in a4PageConfigById.entries) {
        entry.value.value = appearance.a4Page(
          entry.key,
          fallback: _a4PageDefaults[entry.key]!,
        );
      }
    } finally {
      _syncing = false;
    }
  }

  /// Enregistre une fabrique, classée dans [addFamily] selon [addOrder].
  ///
  /// [placementTags] limite les zones de destination proposées par l'éditeur.
  void registerFactory(
    String key,
    Widget widget, {
    String? label,
    Set<String> tags = const {},
    Set<String> placementTags = const {},
    ComponentAddFamily addFamily = ComponentAddFamily.user,
    int addOrder = 0,
    IconData? menuIcon,
    ComponentDuplicationContract? duplication,
    ComponentAddConfigurator<Object>? addConfigurator,
    WidgetBuilder? previewBuilder,
  }) {
    registry[key] = ComponentBuilderDynamic(
      label: label,
      tags: tags,
      placementTags: placementTags,
      addFamily: addFamily,
      addOrder: addOrder,
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

  ValueNotifier<A4PageConfig> a4PageController(
    String id, {
    A4PageConfig? fallback,
  }) => _bindTypedController(
    id,
    fallback: fallback ?? A4PageConfig.initialForPage(id),
    defaults: _a4PageDefaults,
    controllers: a4PageConfigById,
    read: (a, k, f) => a.a4Page(k, fallback: f),
    write: (a, k, v) => a.withA4Page(k, v),
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
    components[key] =
        component.registeredKey == null &&
            component.runtimeType == RegisteredComponent
        ? component.withRegisteredKey(key)
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
    registerBuiltInComponents(
      registry,
      availableFontFamilies: availableFontFamilies,
    );
  }

  Widget getWidget(String key, XuiBuildCtx ctx) =>
      registry[key]?.getWidget(ctx) ?? const SizedBox();
}
