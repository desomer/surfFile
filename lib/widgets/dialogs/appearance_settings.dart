import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/appearance_settings.dart' as shell;
import 'package:super_container_layout/widgets/styled_surface.dart';
import '../../theme/folder_transition.dart';
import '../../theme/surffile_appearance.dart';
import '../../theme/surffile_appearance_slots.dart';

/// SurfFile's catalog, preview and navigation preferences for the generic UI.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  static Future<void> show(BuildContext context) {
    final preferences = SurfFilePreferencesScope.controllerOf(context);
    return shell.showAppearanceDialog(
      context,
      const AppearanceSettings(),
      wrapper: (child) => SurfFilePreferencesScope(
        controller: preferences,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = SurfFilePreferencesScope.controllerOf(context);
    return shell.AppearanceSettings(
      defaults: defaultSurfFileAppearance,
      slots: SurfFileAppearanceSlots.values,
      dialogWrapper: (child) => SurfFilePreferencesScope(
        controller: preferences,
        child: child,
      ),
      additionalSections: [
        shell.AppearanceSettingsSection(
          id: 'navigation',
          label: 'Animation de navigation',
          icon: Icons.animation,
          builder: _navigation,
        ),
        shell.AppearanceSettingsSection(
          id: 'file-drag',
          label: 'Glisser-déposer',
          icon: Icons.drag_indicator,
          builder: _fileDrag,
        ),
      ],
      previewBuilder: _preview,
    );
  }
}

Widget _navigation(BuildContext context) {
  final preferences = SurfFilePreferencesScope.controllerOf(context);
  final p = preferences.value;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<FolderTransition>(
        key: const ValueKey('folder-transition-type'),
        initialValue: p.folderTransition,
        decoration: const InputDecoration(labelText: 'Transition de dossier'),
        items: [
          for (final type in FolderTransition.values)
            DropdownMenuItem(value: type, child: Text(type.label)),
        ],
        onChanged: (value) {
          if (value != null) {
            preferences.value = preferences.value.copyWith(folderTransition: value);
          }
        },
      ),
      const SizedBox(height: 16),
      shell.AppearanceSettingsSlider(
        'Durée de la transition (ms)',
        p.folderTransitionDuration,
        SurfFileAppearanceDefaults.minTransitionDuration,
        SurfFileAppearanceDefaults.maxTransitionDuration,
        (value) => preferences.value = preferences.value.copyWith(
          folderTransitionDuration: value,
        ),
      ),
      const Text('S’applique uniquement aux changements de dossier réussis. '
        'Respecte la réduction des animations du système.'),
    ],
  );
}

Widget _fileDrag(BuildContext context) {
  final preferences = SurfFilePreferencesScope.controllerOf(context);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<FileDragMode>(
        key: const ValueKey('file-drag-mode'),
        initialValue: preferences.value.fileDragMode,
        decoration: const InputDecoration(
          labelText: 'Déplacer des fichiers par glisser-déposer',
        ),
        items: [
          for (final mode in FileDragMode.values)
            DropdownMenuItem(value: mode, child: Text(mode.label)),
        ],
        onChanged: (value) {
          if (value != null) {
            preferences.value = preferences.value.copyWith(fileDragMode: value);
          }
        },
      ),
      const SizedBox(height: 8),
      const Text('Ailleurs, glisser trace un cadre de sélection.'),
    ],
  );
}

Widget _preview(BuildContext context) {
  final a = AppearanceScope.of(context);
  return StyledSurface(
    style: a.style('card'),
    fallbackColor: defaultCardColor(context),
    borderColor: Theme.of(context).colorScheme.outlineVariant,
    child: SizedBox(
      height: a.cardHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder, size: a.iconSize, color: a.accent),
          const SizedBox(height: 8),
          Text('Documents', style: TextStyle(
            fontSize: a.fontSize,
            color: foregroundForCard(cardColor(context, a.style('card'))),
          )),
        ],
      ),
    ),
  );
}
