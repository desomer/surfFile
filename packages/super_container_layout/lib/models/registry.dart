import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/slot_implementation.dart';
import 'package:super_container_layout/widgets/super_layout.dart';

class Registry {
  final Map<String, Widget> registry = {};
  final Map<String, ValueNotifier<SuperLayoutConfig>> superLayoutConfigById =
      {};
  final Map<String, ValueNotifier<ContainerStyle>> containerStyleById = {};

  void registerWidget(String key, Widget widget) {
    registry[key] = widget;
  }

  void bootstrap() {
    registry['New Layout'] = Builder(
      builder: (ctx) {
        return BuilderSlot(
          id: 'new-layout',
          label: 'New Layout',
          builder: (ctx) {
            final superapp = SuperApp.of(ctx);
            final registry = superapp.registry;
            registry!.superLayoutConfigById["contB"] ??= ValueNotifier(
              SuperLayoutConfig(),
            );
            var superLayoutConfig =
                superapp.registry!.superLayoutConfigById["contB"]!;
            return SuperLayout(
              config: superLayoutConfig.value,
              onChanged: (value) => superLayoutConfig.value = value,
            );
          },
        );
      },
    );
  }

  Widget getWidget(String key) => registry[key] ?? const SizedBox();
}
