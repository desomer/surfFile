import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/widgets/slot_implementation.dart';
import 'package:super_container_layout/widgets/super_layout.dart';

class Registry {
  final Map<String, Widget> registry = {};
  final Map<String, RegisteredComponent> components = {};
  final Map<String, ValueNotifier<SuperLayoutConfig>> superLayoutConfigById =
      {};
  final Map<String, ValueNotifier<ContainerStyle>> containerStyleById = {};
  ValueNotifier<Appearance>? _appearance;
  bool _syncing = false;
  final Map<String, SuperLayoutConfig> _layoutDefaults = {};
  final Map<String, ContainerStyle> _styleDefaults = {};
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
    } finally {
      _syncing = false;
    }
  }

  void registerWidget(String key, Widget widget) {
    registry[key] = widget;
  }

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

  void bootstrap() {
    registry['New Layout'] = Builder(
      builder: (ctx) {
        return BuilderSlot(
          id: 'new-layout',
          label: 'New Layout',
          builder: (ctx) {
            final superapp = SuperApp.of(ctx);
            final superLayoutConfig = superapp.getLayoutConfigById('contB');
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
    );
  }

  Widget getWidget(String key) => registry[key] ?? const SizedBox();
}

class RegisteredComponent {
  const RegisteredComponent({
    required this.label,
    required this.builder,
    this.slotId,
    this.sizing = SlotSizing.fill,
    this.isAvailable,
  });

  final String label;
  final WidgetBuilder builder;

  /// Identifiant historique, conservé dans les dispositions existantes.
  final String? slotId;
  final SlotSizing sizing;
  final bool Function(BuildContext)? isAvailable;

  BuilderSlot createSlot(String id, {bool visible = true}) => BuilderSlot(
    id: id,
    label: label,
    sizing: sizing,
    visible: visible,
    builder: builder,
  );
}
