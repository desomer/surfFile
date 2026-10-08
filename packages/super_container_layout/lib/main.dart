import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/widgets/appearance_settings.dart';
import 'package:super_container_layout/widgets/super_container.dart';
import 'package:super_container_layout/widgets/super_layout.dart';

export 'package:super_container_layout/models/registry.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    final registry = Registry()..bootstrap();
    registry.registerFactory('A', Center(child: Text('A')));

    return SuperApp(
      title: 'Super Container Layout demo',
      home: getRootWidget(registry),
      registry: registry,
    );
  }

  Widget getRootWidget(Registry registry) {
    return Builder(
      builder: (context) {
        final superapp = SuperApp.of(context);
        var superLayoutConfig = superapp.getLayoutConfigById('contA');

        return SuperContainer(
          slot: AppearanceSlot(
            'Fond',
            name: 'demo-background',
            role: AppearanceSurfaceRole.applicationBackground,
            editShape: false,
            extendedLook: false,
            read: (a) => a.backgroundStyle,
            write: (a, style) => a.withStyle('background', style),
            reset: (a) => a.withStyle('background', null),
          ),
          decorate: false,
          applyPadding: true,
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: ValueListenableBuilder<SuperLayoutConfig>(
                    valueListenable: superLayoutConfig,
                    builder: (context, config, _) => SuperLayout(
                      config: config,
                      onChanged: (value) => superLayoutConfig.value = value,
                      slots: const [],
                    ),
                  ),
                ),
                Positioned(
                  top: 56,
                  right: 16,
                  bottom: 16,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: SingleChildScrollView(child: overlyRight(context)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget overlyRight(BuildContext context) {
    return Builder(
      builder: (context) {
        if (StyleEditScope.controllerOf(context) case final editMode?) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavigationButton(
                key: const ValueKey('style-edit-mode'),
                tooltip: editMode.value
                    ? 'Quitter l’édition du style'
                    : 'Éditer le style (clic droit sur une zone)',
                icon: Icons.brush_outlined,
                selected: editMode.value,
                onPressed: () => editMode.value = !editMode.value,
              ),
              _NavigationButton(
                key: const ValueKey('appearance-settings'),
                tooltip: 'Paramètres d’apparence',
                icon: Icons.settings_outlined,
                onPressed: () => AppearanceSettings.show(context),
              ),
            ],
          );
        }
        return const SizedBox();
      },
    );

    // Removed as it's now handled inside the Builder above.
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    isSelected: selected,
    icon: Icon(icon, size: 20),
    style: IconButton.styleFrom(
      minimumSize: const Size(36, 36),
      maximumSize: const Size(36, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      foregroundColor: selected
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : Theme.of(context).colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
