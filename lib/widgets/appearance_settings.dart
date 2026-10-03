import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/appearance.dart';
import '../theme/folder_transition.dart';
import 'styled_surface.dart';

enum _Section {
  accent('Couleur d’accent', Icons.palette_outlined),
  layout('Dimensions et espacement', Icons.dashboard_outlined),
  text('Texte et icônes', Icons.text_fields),
  navigation('Animation de navigation', Icons.animation),
  scrollFade('Fondu des fichiers', Icons.gradient_rounded),
  window('Transparence de la fenêtre', Icons.window_outlined);

  const _Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  static Future<void> show(BuildContext context) async {
    final controller = AppearanceScope.controllerOf(context);
    if (controller == null) {
      throw StateError('Le contrôleur d’apparence est indisponible.');
    }
    await _showPopup(context, controller, const AppearanceSettings());
  }

  static Future<void> _showPopup(
    BuildContext context,
    ValueNotifier<Appearance> controller,
    Widget child,
  ) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      builder: (context) => AppearanceScope(
        controller: controller,
        child: ValueListenableBuilder<Appearance>(
          valueListenable: controller,
          builder: (context, appearance, _) {
            final brightness = switch (appearance.mode) {
              ThemeMode.light => Brightness.light,
              ThemeMode.dark => Brightness.dark,
              ThemeMode.system => MediaQuery.platformBrightnessOf(context),
            };
            return Theme(data: appearance.theme(brightness), child: child);
          },
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final section in _Section.values)
                    OutlinedButton.icon(
                      icon: Icon(section.icon),
                      label: Text(section.label),
                      onPressed: () => _showPopup(
                        context,
                        controller,
                        _AppearanceSection(section),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Aperçu'),
              const SizedBox(height: 8),
              StyledSurface(
                style: a.cardStyle,
                fallbackColor: Appearance.defaultCardColor(context),
                borderColor: Theme.of(context).colorScheme.outlineVariant,
                child: SizedBox(
                  height: a.cardHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder, size: a.iconSize, color: a.accent),
                      const SizedBox(height: 8),
                      Text(
                        'Documents',
                        style: TextStyle(
                          fontSize: a.fontSize,
                          color: Appearance.foreground(
                            a.cardBackground(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => controller.value = const Appearance(),
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

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection(this.section);
  final _Section section;

  @override
  Widget build(BuildContext context) {
    final controller = AppearanceScope.controllerOf(context)!;
    final a = controller.value;
    final List<Widget> controls = switch (section) {
      _Section.accent => [
        ColorPicker(
          key: const ValueKey('picker-Couleur d’accent'),
          color: a.accent,
          onColorChanged: (color) =>
              controller.value = controller.value.copyWith(accent: color),
          enableOpacity: true,
          showColorCode: true,
          showEditIconButton: true,
          opacitySubheading: const Text('Opacité'),
          pickersEnabled: const {
            ColorPickerType.both: true,
            ColorPickerType.primary: false,
            ColorPickerType.accent: false,
            ColorPickerType.wheel: true,
          },
          pickerTypeLabels: const {
            ColorPickerType.both: 'Palette',
            ColorPickerType.wheel: 'Roue',
          },
        ),
      ],
      _Section.layout => [
        _StyleSlider(
          'Hauteur des cartes',
          a.cardHeight,
          142,
          300,
          (value) =>
              controller.value = controller.value.copyWith(cardHeight: value),
        ),
        _StyleSlider(
          'Largeur des cartes',
          a.cardWidth,
          180,
          360,
          (value) =>
              controller.value = controller.value.copyWith(cardWidth: value),
        ),
        _StyleSlider(
          'Hauteur des lignes',
          a.rowHeight,
          Appearance.minRowHeight,
          Appearance.maxRowHeight,
          (value) =>
              controller.value = controller.value.copyWith(rowHeight: value),
        ),
        _StyleSlider(
          'Espacement',
          a.spacing,
          Appearance.minSpacing,
          Appearance.maxSpacing,
          (value) =>
              controller.value = controller.value.copyWith(spacing: value),
        ),
      ],
      _Section.text => [
        _StyleSlider(
          'Taille du texte',
          a.fontSize,
          10,
          16,
          (value) =>
              controller.value = controller.value.copyWith(fontSize: value),
        ),
        _StyleSlider(
          'Taille des icônes',
          a.iconSize,
          24,
          64,
          (value) =>
              controller.value = controller.value.copyWith(iconSize: value),
        ),
      ],
      _Section.scrollFade => [
        SwitchListTile(
          title: const Text('Activer le fondu'),
          value: a.scrollFadeEnabled,
          onChanged: (value) => controller.value = controller.value.copyWith(
            scrollFadeEnabled: value,
          ),
        ),
        const Text(
          'Le fondu apparaît uniquement aux bords où il reste des fichiers '
          'à faire défiler, en liste comme en grille.',
        ),
        const SizedBox(height: 16),
        if (a.scrollFadeEnabled)
          _StyleSlider(
            'Hauteur du fondu (px)',
            a.scrollFadeExtent,
            Appearance.minScrollFadeExtent,
            Appearance.maxScrollFadeExtent,
            (value) => controller.value = controller.value.copyWith(
              scrollFadeExtent: value,
            ),
          ),
        TextButton(
          onPressed: () => controller.value = controller.value.copyWith(
            scrollFadeEnabled: true,
            scrollFadeExtent: 28,
          ),
          child: const Text('Réinitialiser le fondu'),
        ),
      ],
      _Section.navigation => [
        DropdownButtonFormField<FolderTransition>(
          key: const ValueKey('folder-transition-type'),
          initialValue: a.folderTransition,
          decoration: const InputDecoration(labelText: 'Transition de dossier'),
          items: [
            for (final type in FolderTransition.values)
              DropdownMenuItem(value: type, child: Text(type.label)),
          ],
          onChanged: (value) {
            if (value != null) {
              controller.value = controller.value.copyWith(
                folderTransition: value,
              );
            }
          },
        ),
        const SizedBox(height: 16),
        _StyleSlider(
          'Durée de la transition (ms)',
          a.folderTransitionDuration,
          Appearance.minTransitionDuration,
          Appearance.maxTransitionDuration,
          (value) => controller.value = controller.value.copyWith(
            folderTransitionDuration: value,
          ),
        ),
        const Text(
          'S’applique uniquement aux changements de dossier réussis. '
          'Respecte la réduction des animations du système.',
        ),
      ],
      _Section.window => [
        const Text(
          'Atténue toute la fenêtre, y compris le texte et les icônes. '
          'Pour ne rendre transparent que le fond, éditez le style du fond '
          '(pinceau de la barre d’outils, puis clic droit).',
        ),
        _StyleSlider(
          'Opacité de la fenêtre',
          a.windowOpacity,
          .2,
          1,
          (value) => controller.value = controller.value.copyWith(
            windowOpacity: value,
          ),
        ),
      ],
    };
    return AlertDialog(
      title: Text(section.label),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: controls,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Retour'),
        ),
      ],
    );
  }
}

class _StyleSlider extends StatelessWidget {
  const _StyleSlider(
    this.label,
    this.value,
    this.min,
    this.max,
    this.onChanged,
  );
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('$label : ${value.toStringAsFixed(1)}'),
      Slider(
        key: ValueKey(label),
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    ],
  );
}
