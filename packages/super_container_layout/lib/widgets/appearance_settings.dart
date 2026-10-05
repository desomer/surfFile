import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/appearance.dart';
import '../services/appearance_store.dart';

/// Generic theme/window settings. Applications supply their own extra controls.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({this.defaults, this.additionalControls, super.key});
  final Appearance Function()? defaults;
  final WidgetBuilder? additionalControls;
  static Future<void> show(
    BuildContext context, {
    Appearance Function()? defaults,
    WidgetBuilder? additionalControls,
  }) {
    final controller = AppearanceScope.controllerOf(context);
    if (controller == null) {
      throw StateError('Appearance controller unavailable.');
    }
    final codec = AppearanceServicesScope.codecOf(context);
    return showDialog<void>(
      context: context,
      builder: (_) => AppearanceScope(
        controller: controller,
        child: AppearanceSettings(
          defaults: defaults ?? () => codec.defaults,
          additionalControls: additionalControls,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppearanceScope.controllerOf(context)!;
    final a = controller.value;
    return AlertDialog(
      title: const Text('Apparence'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Système'),
                  ),
                ],
                selected: {a.mode},
                onSelectionChanged: (value) => controller.value = controller
                    .value
                    .copyWith(mode: value.single),
              ),
              ColorPicker(
                color: a.accent,
                enableOpacity: true,
                onColorChanged: (color) =>
                    controller.value = controller.value.copyWith(accent: color),
              ),
              const Text('Opacité de la fenêtre'),
              Slider(
                value: a.windowOpacity,
                min: .2,
                max: 1,
                onChanged: (value) => controller.value = controller.value
                    .copyWith(windowOpacity: value),
              ),
              if (additionalControls != null) additionalControls!(context),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => controller.value =
              defaults?.call() ??
              AppearanceServicesScope.codecOf(context).defaults,
          child: const Text('Réinitialiser'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
