import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/appearance.dart';
import '../theme/container_style.dart';
import '../theme/explorer_colors.dart';
import '../theme/neon_style.dart';
import '../theme/folder_transition.dart';
import 'container_style_editor.dart';
import 'neon_surface.dart';

enum _Section {
  accent('Couleur d’accent', Icons.palette_outlined),
  cards('Style des cartes', Icons.style_outlined),
  selectedCards('Style des cartes sélectionnées', Icons.check_box_outlined),
  selectedFolder(
      'Style de la sélection du panneau gauche', Icons.folder_special_outlined),
  background('Fond de l’application', Icons.wallpaper_outlined),
  sidebar('Style du panneau de gauche', Icons.view_sidebar_outlined),
  pathBar('Style de la barre du chemin', Icons.route_outlined),
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

  static Future<void> _showPopup(BuildContext context,
      ValueNotifier<Appearance> controller, Widget child) async {
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
                      value: ThemeMode.system, label: Text('Système')),
                ],
                selected: {a.mode},
                onSelectionChanged: (value) => controller.value =
                    controller.value.copyWith(mode: value.single),
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
                          context, controller, _AppearanceSection(section)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Aperçu'),
              const SizedBox(height: 8),
              NeonSurface(
                style: a.cardNeon,
                accent: a.accent,
                radius: a.radius,
                child: Material(
                  color: a.cardFill.gradient() == null
                      ? a.cardBackground(context)
                      : Colors.transparent,
                  elevation: a.elevation,
                  shadowColor: Colors.black.withValues(alpha: a.shadowOpacity),
                  borderRadius: BorderRadius.circular(a.radius),
                  child: Container(
                    height: a.cardHeight,
                    decoration: BoxDecoration(
                      gradient: a.cardFill.gradient(),
                      borderRadius: BorderRadius.circular(a.radius),
                      border: Border.all(
                        color: a.cardBorderColor ??
                            Theme.of(context).colorScheme.outlineVariant,
                        width: a.borderWidth,
                        style: a.borderWidth == 0
                            ? BorderStyle.none
                            : BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder, size: a.iconSize, color: a.accent),
                        const SizedBox(height: 8),
                        Text('Documents',
                            style: TextStyle(
                                fontSize: a.fontSize,
                                color: Appearance.foreground(
                                    a.cardBackground(context)))),
                      ],
                    ),
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
    final scheme = Theme.of(context).colorScheme;
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
      _Section.cards => [
          ContainerStyleEditor(
            label: section.label,
            collapsible: false,
            value: a.cardFill,
            solidColor: a.cardColor ??
                (scheme.brightness == Brightness.dark
                    ? scheme.surfaceContainerLow
                    : Colors.white),
            onSolidColorChanged: (color) =>
                controller.value = controller.value.copyWith(cardColor: color),
            onChanged: (fill) =>
                controller.value = controller.value.copyWith(cardFill: fill),
            radius: a.radius,
            borderWidth: a.borderWidth,
            borderColor: a.cardBorderColor,
            onBorderColorChanged: (value) => controller.value =
                controller.value.copyWith(cardBorderColor: value),
            onResetBorderColor: () => controller.value =
                controller.value.copyWith(resetCardBorderColor: true),
            elevation: a.elevation,
            shadowOpacity: a.shadowOpacity,
            neon: a.cardNeon,
            accent: a.accent,
            onNeonChanged: (value) =>
                controller.value = controller.value.copyWith(cardNeon: value),
            onRadiusChanged: (value) =>
                controller.value = controller.value.copyWith(radius: value),
            onBorderWidthChanged: (value) => controller.value =
                controller.value.copyWith(borderWidth: value),
            onElevationChanged: (value) =>
                controller.value = controller.value.copyWith(elevation: value),
            onShadowOpacityChanged: (value) => controller.value =
                controller.value.copyWith(shadowOpacity: value),
          ),
          TextButton(
            key: const ValueKey('automatic-Couleur des cartes'),
            onPressed: () => controller.value =
                controller.value.copyWith(resetCardColor: true),
            child: const Text('Couleur unie automatique'),
          ),
        ],
      _Section.sidebar ||
      _Section.pathBar ||
      _Section.selectedCards ||
      _Section.selectedFolder =>
        [
          _surfaceEditor(context, controller),
        ],
      _Section.background => [
          ContainerStyleEditor(
            label: section.label,
            collapsible: false,
            value: a.backgroundFill,
            borderWidth: a.backgroundBorderWidth,
            borderColor: a.backgroundBorderColor,
            onBorderWidthChanged: (value) => controller.value =
                controller.value.copyWith(backgroundBorderWidth: value),
            onBorderColorChanged: (value) => controller.value =
                controller.value.copyWith(backgroundBorderColor: value),
            onResetBorderColor: () => controller.value =
                controller.value.copyWith(resetBackgroundBorderColor: true),
            neon: a.backgroundNeon,
            accent: a.accent,
            onNeonChanged: (value) => controller.value =
                controller.value.copyWith(backgroundNeon: value),
            solidColor: a.backgroundColor ?? scheme.surface,
            opacity: a.backgroundOpacity,
            onSolidColorChanged: (color) => controller.value =
                controller.value.copyWith(backgroundColor: color),
            onChanged: (fill) => controller.value =
                controller.value.copyWith(backgroundFill: fill),
          ),
          TextButton(
            key: const ValueKey('automatic-Arrière-plan'),
            onPressed: () => controller.value =
                controller.value.copyWith(resetBackgroundColor: true),
            child: const Text('Couleur unie automatique'),
          ),
          _StyleSlider(
              'Opacité du fond',
              a.backgroundOpacity,
              0,
              1,
              (value) => controller.value =
                  controller.value.copyWith(backgroundOpacity: value)),
        ],
      _Section.layout => [
          _StyleSlider(
              'Hauteur des cartes',
              a.cardHeight,
              142,
              300,
              (value) => controller.value =
                  controller.value.copyWith(cardHeight: value)),
          _StyleSlider(
              'Largeur des cartes',
              a.cardWidth,
              180,
              360,
              (value) => controller.value =
                  controller.value.copyWith(cardWidth: value)),
          _StyleSlider(
              'Hauteur des lignes',
              a.rowHeight,
              Appearance.minRowHeight,
              Appearance.maxRowHeight,
              (value) => controller.value =
                  controller.value.copyWith(rowHeight: value)),
          _StyleSlider(
              'Espacement',
              a.spacing,
              Appearance.minSpacing,
              Appearance.maxSpacing,
              (value) =>
                  controller.value = controller.value.copyWith(spacing: value)),
        ],
      _Section.text => [
          _StyleSlider(
              'Taille du texte',
              a.fontSize,
              10,
              16,
              (value) => controller.value =
                  controller.value.copyWith(fontSize: value)),
          _StyleSlider(
              'Taille des icônes',
              a.iconSize,
              24,
              64,
              (value) => controller.value =
                  controller.value.copyWith(iconSize: value)),
        ],
      _Section.scrollFade => [
          SwitchListTile(
            title: const Text('Activer le fondu'),
            value: a.scrollFadeEnabled,
            onChanged: (value) => controller.value =
                controller.value.copyWith(scrollFadeEnabled: value),
          ),
          const Text(
              'Le fondu apparaît uniquement aux bords où il reste des fichiers '
              'à faire défiler, en liste comme en grille.'),
          const SizedBox(height: 16),
          if (a.scrollFadeEnabled)
            _StyleSlider(
                'Hauteur du fondu (px)',
                a.scrollFadeExtent,
                Appearance.minScrollFadeExtent,
                Appearance.maxScrollFadeExtent,
                (value) => controller.value =
                    controller.value.copyWith(scrollFadeExtent: value)),
          TextButton(
            onPressed: () => controller.value = controller.value
                .copyWith(scrollFadeEnabled: true, scrollFadeExtent: 28),
            child: const Text('Réinitialiser le fondu'),
          ),
        ],
      _Section.navigation => [
          DropdownButtonFormField<FolderTransition>(
            key: const ValueKey('folder-transition-type'),
            initialValue: a.folderTransition,
            decoration:
                const InputDecoration(labelText: 'Transition de dossier'),
            items: [
              for (final type in FolderTransition.values)
                DropdownMenuItem(value: type, child: Text(type.label)),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.value =
                    controller.value.copyWith(folderTransition: value);
              }
            },
          ),
          const SizedBox(height: 16),
          _StyleSlider(
              'Durée de la transition (ms)',
              a.folderTransitionDuration,
              Appearance.minTransitionDuration,
              Appearance.maxTransitionDuration,
              (value) => controller.value =
                  controller.value.copyWith(folderTransitionDuration: value)),
          const Text(
              'S’applique uniquement aux changements de dossier réussis. '
              'Respecte la réduction des animations du système.'),
        ],
      _Section.window => [
          const Text(
              'Atténue toute la fenêtre, y compris le texte et les icônes. '
              'Pour ne rendre transparent que le fond, utilisez Fond de l’application.'),
          _StyleSlider(
              'Opacité de la fenêtre',
              a.windowOpacity,
              .2,
              1,
              (value) => controller.value =
                  controller.value.copyWith(windowOpacity: value)),
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

  Widget _surfaceEditor(
      BuildContext context, ValueNotifier<Appearance> controller) {
    final sidebar = section == _Section.sidebar;
    final selectedCards = section == _Section.selectedCards;
    final selectedFolder = section == _Section.selectedFolder;
    ContainerStyle current() => switch (section) {
          _Section.selectedCards => controller.value.effectiveSelectedCardStyle,
          _Section.selectedFolder =>
            controller.value.effectiveSelectedFolderStyle,
          _Section.sidebar => controller.value.sidebarStyle,
          _ => controller.value.pathBarStyle,
        };
    void update(ContainerStyle value) {
      controller.value = switch (section) {
        _Section.selectedCards =>
          controller.value.copyWith(selectedCardStyle: value),
        _Section.selectedFolder =>
          controller.value.copyWith(selectedFolderStyle: value),
        _Section.sidebar => controller.value.copyWith(sidebarStyle: value),
        _ => controller.value.copyWith(pathBarStyle: value),
      };
    }

    final style = current();
    final fallback = selectedCards
        ? Theme.of(context).colorScheme.primaryContainer
        : selectedFolder
            ? explorerColor(context, const Color(0xFFE2E7FC),
                Theme.of(context).colorScheme.primaryContainer)
            : explorerColor(
                context,
                sidebar ? const Color(0xFFF1F3F8) : Colors.white,
                Theme.of(context).colorScheme.surfaceContainerLow);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContainerStyleEditor(
          label: section.label,
          collapsible: false,
          value: style.fill,
          solidColor: style.color ?? fallback,
          radius: style.radius,
          borderWidth: style.borderWidth,
          borderColor: style.borderColor ??
              (selectedCards || selectedFolder
                  ? Theme.of(context).colorScheme.primary
                  : sidebar
                      ? Theme.of(context).colorScheme.outlineVariant
                      : explorerColor(context, const Color(0xFFEAECF2),
                          Theme.of(context).colorScheme.outlineVariant)),
          onBorderColorChanged: (value) =>
              update(current().copyWith(borderColor: value)),
          onResetBorderColor: () =>
              update(current().copyWith(resetBorderColor: true)),
          elevation: style.elevation,
          shadowOpacity: style.shadowOpacity,
          neon: style.neon ?? const NeonStyle(),
          accent: controller.value.accent,
          onNeonChanged: (value) => update(current().copyWith(neon: value)),
          onChanged: (value) => update(current().copyWith(fill: value)),
          onSolidColorChanged: (value) =>
              update(current().copyWith(color: value)),
          onRadiusChanged: (value) => update(current().copyWith(radius: value)),
          onBorderWidthChanged: (value) =>
              update(current().copyWith(borderWidth: value)),
          onElevationChanged: (value) =>
              update(current().copyWith(elevation: value)),
          onShadowOpacityChanged: (value) =>
              update(current().copyWith(shadowOpacity: value)),
        ),
        TextButton(
          onPressed: () => update(current().copyWith(resetColor: true)),
          child: const Text('Couleur unie automatique'),
        ),
        TextButton(
          onPressed: () {
            if (selectedCards || selectedFolder) {
              controller.value = controller.value.copyWith(
                resetSelectedCardStyle: selectedCards,
                resetSelectedFolderStyle: selectedFolder,
              );
            } else {
              update(sidebar
                  ? const ContainerStyle()
                  : const ContainerStyle(borderWidth: 1));
            }
          },
          child: const Text('Réinitialiser ce style'),
        ),
      ],
    );
  }
}

class _StyleSlider extends StatelessWidget {
  const _StyleSlider(
      this.label, this.value, this.min, this.max, this.onChanged);
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
