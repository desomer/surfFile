import 'package:material_ui/material_ui.dart';

import 'native_component_config.dart';
import 'super_text_config.dart';
import '../widgets/super_text.dart';

import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/scaffold_page_config.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/widgets/super_app_bar.dart';

import '../widgets/super_bottom_navigation_bar.dart';

import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/super_layout/super_layout.dart';
import 'package:super_container_layout/widgets/surfaces/super_container.dart';

class XuiBuildCtx {
  XuiBuildCtx({required this.id});

  final String id;
}

/// Persisted configuration maps of an `Appearance` that a design graph uses.
enum EditorConfigKind { layout, style, nativeComponent, scaffoldPage, text }

/// Key of one persisted configuration entry, e.g. `layouts[id]`.
@immutable
class EditorConfigRef {
  const EditorConfigRef(this.kind, this.id);

  const EditorConfigRef.layout(this.id) : kind = EditorConfigKind.layout;
  const EditorConfigRef.style(this.id) : kind = EditorConfigKind.style;
  const EditorConfigRef.nativeComponent(this.id)
    : kind = EditorConfigKind.nativeComponent;
  const EditorConfigRef.scaffoldPage(this.id)
    : kind = EditorConfigKind.scaffoldPage;
  const EditorConfigRef.text(this.id) : kind = EditorConfigKind.text;

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
/// `NativeComponentConfig`, `ScaffoldPageConfig` or `SuperTextConfig`; the
/// result must have the same type. [remap] returns the new ID of every
/// instance/configuration ID owned by the duplicated graph and returns other
/// IDs unchanged.
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
  static List<EditorConfigRef> _style(String id) => [EditorConfigRef.style(id)];
  static List<EditorConfigRef> _text(String id) => [EditorConfigRef.text(id)];
  static List<EditorConfigRef> _native(String id) => [
    EditorConfigRef.nativeComponent(id),
  ];
  static List<EditorConfigRef> _appBar(String id) => [
    EditorConfigRef.nativeComponent(id),
    // Legacy SuperLayoutConfig still migrated by SuperAppBar.
    EditorConfigRef.layout(id),
  ];

  /// Contracts of the components installed by [Registry.bootstrap].
  static const superText = ComponentDuplicationContract(ownedConfigs: _text);
  static const superAppBar = ComponentDuplicationContract(
    ownedConfigs: _appBar,
  );
  static const superBottomNavigationBar = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const newContainer = ComponentDuplicationContract(
    ownedConfigs: _style,
  );
  static const newLayout = ComponentDuplicationContract(ownedConfigs: _layout);
}

class ComponentBuilder {
  ComponentBuilder({this.tags = const {}, this.duplication});

  final Set<String> tags;

  /// Null when the component cannot be duplicated in a design graph.
  final ComponentDuplicationContract? duplication;

  Widget getWidget(XuiBuildCtx ctx) {
    return SizedBox.shrink();
  }
}

class RegisteredComponentImpl extends ComponentBuilder {
  RegisteredComponentImpl({
    required this.widget,
    super.tags,
    super.duplication,
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
  final Map<String, ValueNotifier<ScaffoldPageConfig>> scaffoldPageConfigById =
      {};
  final Map<String, ValueNotifier<NativeComponentConfig>>
  nativeComponentConfigById = {};
  ValueNotifier<Appearance>? _appearance;
  bool _syncing = false;
  final Map<String, SuperLayoutConfig> _layoutDefaults = {};
  final Map<String, ContainerStyle> _styleDefaults = {};
  final Map<String, ValueNotifier<SuperTextConfig>> textConfigById = {};
  final Map<String, SuperTextConfig> _textDefaults = {};
  final Map<String, NativeComponentConfig> _nativeDefaults = {};
  final Map<String, NativeComponentConfig? Function(Appearance)>
  _nativeMigrations = {};
  final Set<String> _scaffoldBridges = {};
  final Map<Listenable, VoidCallback> _listeners = {};

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
    for (final entry in scaffoldPageConfigById.entries.toList()) {
      scaffoldPageController(entry.key, fallback: entry.value.value);
    }
    for (final entry in nativeComponentConfigById.entries.toList()) {
      nativeComponentController(entry.key, fallback: entry.value.value);
    }
    for (final entry in textConfigById.entries.toList()) {
      textController(entry.key, fallback: entry.value.value);
    }
    _readAppearance();
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
      legacy: (appearance) => appearance.scaffoldPages[id]?.native,
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
      for (final entry in nativeComponentConfigById.entries) {
        entry.value.value = _nativeValue(appearance, entry.key);
      }
      for (final entry in textConfigById.entries) {
        entry.value.value = appearance.textComponent(
          entry.key,
          fallback: _textDefaults[entry.key]!,
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
    ComponentDuplicationContract? duplication,
  }) {
    registry[key] = ComponentBuilderDynamic(
      tags: tags,
      duplication: duplication,
      dynamicBuilder: (xuiCtx) => widget,
    );
  }

  ValueNotifier<SuperTextConfig> textController(
    String id, {
    SuperTextConfig fallback = const SuperTextConfig(),
  }) {
    fallback.validate();
    _textDefaults.putIfAbsent(id, () => fallback);
    final notifier = textConfigById.putIfAbsent(
      id,
      () => ValueNotifier(
        _appearance?.value.textComponent(id, fallback: fallback) ?? fallback,
      ),
    );
    if (_appearance != null && !_listeners.containsKey(notifier)) {
      void write() {
        notifier.value.validate();
        if (!_syncing) {
          _appearance!.value = _appearance!.value.withTextComponent(
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
      appearance.nativeComponents[id] ??
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
    registry['SuperText'] = ComponentBuilderDynamic(
      duplication: ComponentDuplicationContract.superText,
      tags: const {'text', 'input'},
      dynamicBuilder: (ctx) =>
          SuperText(id: ctx.id, availableFontFamilies: availableFontFamilies),
    );
    registry['SuperAppBar'] = ComponentBuilderDynamic(
      duplication: ComponentDuplicationContract.superAppBar,
      tags: const {'appBar'},
      dynamicBuilder: (ctx) => SuperAppBar(id: ctx.id),
    );
    registry['SuperBottomNavigationBar'] = ComponentBuilderDynamic(
      duplication: ComponentDuplicationContract.superBottomNavigationBar,
      tags: const {'bottomNavigationBar'},
      dynamicBuilder: (ctx) => SuperBottomNavigationBar(id: ctx.id),
    );

    registry['NewContainer'] = ComponentBuilderDynamic(
      duplication: ComponentDuplicationContract.newContainer,
      tags: const {'container'},
      dynamicBuilder: (xuiCtx) => Builder(
        builder: (context) {
          final style = SuperApp.of(context).getContainerStyleById(xuiCtx.id);
          return ValueListenableBuilder<ContainerStyle>(
            valueListenable: style,
            builder: (context, value, _) => SuperContainer(
              label: 'New Container',
              style: value,
              onStyleChanged: (value) => style.value = value,
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
    registry['NewLayout'] = ComponentBuilderDynamic(
      duplication: ComponentDuplicationContract.newLayout,
      tags: const {'layout'},
      dynamicBuilder: (xuiCtx) => Builder(
        builder: (ctx) {
          final id = xuiCtx.id;

          return BuilderSlot(
            id: id,
            label: 'New Layout',
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
    super.duplication,
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
    this.duplication,
  });

  final String label;
  final WidgetBuilder builder;

  /// Identifiant historique, conservé dans les dispositions existantes.
  final String? slotId;
  final SlotSizing sizing;
  final Size? preferredSize;
  final bool Function(BuildContext)? isAvailable;
  final Set<String> tags;

  /// Null when the component cannot be duplicated in a design graph.
  final ComponentDuplicationContract? duplication;

  BuilderSlot createSlot(String id, {bool visible = true}) => BuilderSlot(
    id: id,
    label: label,
    sizing: sizing,
    preferredSize: preferredSize,
    visible: visible,
    builder: builder,
    tags: tags,
  );
}
