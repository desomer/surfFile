/// Boîte de dialogue principale de configuration de l'apparence ([AppearanceSettings]).
///
/// Permet de régler le thème clair/sombre, la couleur d'accent, les dimensions,
/// la typographie, le fondu de défilement, la transparence de fenêtre et les slots de style.
library;

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/responsive_layout_config.dart';
import '../../services/appearance/appearance_store.dart';
import '../../theme/appearance.dart';
import '../../theme/appearance_slot.dart';
import '../../theme/default_appearance.dart';
import '../editing/components/shared/editor_number_field.dart';
import 'appearance_style_section.dart';
import '../editing/history/editor_history.dart';
import '../editing/dialogs/editor_dialog.dart';
import '../editing/dialogs/editor_dialog_header.dart';
import 'appearance_scope.dart';

/// Captured by the caller before opening a route, then applied to every dialog.
typedef AppearanceDialogWrapper = Widget Function(Widget child);

/// Section personnalisée additionnelle affichée dans la boîte de dialogue [AppearanceSettings].
@immutable
class AppearanceSettingsSection {
  const AppearanceSettingsSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
  });
  final String id;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

/// Generic appearance controls with injected application catalogs and content.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({
    this.defaults,
    this.slots = const [],
    this.additionalSections = const [],
    this.additionalControls,
    this.previewBuilder,
    this.resetAdditional,
    this.dialogWrapper,
    super.key,
  });
  final Appearance Function()? defaults;
  final List<AppearanceSlot> slots;
  final List<AppearanceSettingsSection> additionalSections;
  final WidgetBuilder? additionalControls;
  final WidgetBuilder? previewBuilder;

  /// Overrides the codec's additional reset; it is never called twice.
  final VoidCallback? resetAdditional;
  final AppearanceDialogWrapper? dialogWrapper;

  static Future<void> show(
    BuildContext context, {
    Appearance Function()? defaults,
    List<AppearanceSlot> slots = const [],
    List<AppearanceSettingsSection> additionalSections = const [],
    WidgetBuilder? additionalControls,
    WidgetBuilder? previewBuilder,
    VoidCallback? resetAdditional,
    AppearanceDialogWrapper? dialogWrapper,
  }) => showAppearanceDialog(
    context,
    AppearanceSettings(
      defaults: defaults,
      slots: slots,
      additionalSections: additionalSections,
      additionalControls: additionalControls,
      previewBuilder: previewBuilder,
      resetAdditional: resetAdditional,
      dialogWrapper: dialogWrapper,
    ),
    wrapper: dialogWrapper,
  );

  @override
  Widget build(BuildContext context) {
    final controller = AppearanceScope.controllerOf(context);
    if (controller == null) {
      throw StateError('Appearance controller unavailable.');
    }
    final a = controller.value;
    final sections = [
      AppearanceSettingsSection(
        id: 'accent',
        label: 'Couleur d’accent',
        icon: Icons.palette_outlined,
        builder: (context) => _controls([
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('clear-accent-color'),
              onPressed: () {
                final codec = AppearanceServicesScope.codecOf(context);
                final defaultAccent =
                    (defaults?.call() ?? codec.defaults).accent;
                controller.value = controller.value.copyWith(
                  accent: defaultAccent,
                );
              },
              icon: const Icon(Icons.format_color_reset_outlined, size: 18),
              label: const Text('Retirer la couleur'),
            ),
          ),
          ColorPicker(
            key: const ValueKey('picker-Couleur d’accent'),
            color: AppearanceScope.of(context).accent,
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
          const SizedBox(height: 16),
          _window(context),
        ]),
      ),
      AppearanceSettingsSection(
        id: 'responsive',
        label: 'Conteneur & Breakpoints',
        icon: Icons.aspect_ratio_outlined,
        builder: _responsiveLayout,
      ),
      if (a is DefaultAppearance) ...[
        AppearanceSettingsSection(
          id: 'layout',
          label: 'Dimensions et espacement',
          icon: Icons.dashboard_outlined,
          builder: _dimensions,
        ),
        AppearanceSettingsSection(
          id: 'text',
          label: 'Texte et icônes',
          icon: Icons.text_fields,
          builder: _text,
        ),
      ],
      ...additionalSections,
      if (a is DefaultAppearance)
        AppearanceSettingsSection(
          id: 'scrollFade',
          label: 'Fondu des fichiers',
          icon: Icons.gradient_rounded,
          builder: _scrollFade,
        ),
    ];
    return AlertDialog(
      title: const EditorDialogHeader(label: 'Apparence'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    tooltip: 'Clair',
                    label: Text('Clair'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    tooltip: 'Sombre',
                    label: Text('Sombre'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    tooltip: 'Système',
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
                  for (final section in sections)
                    OutlinedButton.icon(
                      key: ValueKey('appearance-section-${section.id}'),
                      icon: Icon(section.icon),
                      label: Text(section.label),
                      onPressed: () => showAppearanceDialog(
                        context,
                        _SectionDialog(section),
                        wrapper: dialogWrapper,
                      ),
                    ),
                  for (final slot in slots)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.brush_outlined),
                      label: Text(slot.label),
                      onPressed: () => showAppearanceDialog(
                        context,
                        AppearanceStyleSection(slot, defaults: defaults),
                        wrapper: dialogWrapper,
                      ),
                    ),
                ],
              ),
              if (additionalControls != null) additionalControls!(context),
              if (previewBuilder != null) ...[
                const SizedBox(height: 20),
                const Text('Aperçu'),
                const SizedBox(height: 8),
                previewBuilder!(context),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final codec = AppearanceServicesScope.codecOf(context);
            (resetAdditional ?? codec.resetAdditional)();
            controller.value = defaults?.call() ?? codec.defaults;
          },
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

/// Opens a dialog with the caller's controller, codec and live theme.
Future<void> showAppearanceDialog(
  BuildContext context,
  Widget child, {
  AppearanceDialogWrapper? wrapper,
}) {
  final controller = AppearanceScope.controllerOf(context);
  if (controller == null) {
    throw StateError('Appearance controller unavailable.');
  }
  final codec = AppearanceServicesScope.codecOf(context);
  return showEditorDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    builder: (_) {
      Widget content = AppearanceServicesScope(
        codec: codec,
        child: AppearanceScope(
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
      return wrapper?.call(content) ?? content;
    },
  );
}

class _SectionDialog extends StatelessWidget {
  const _SectionDialog(this.section);
  final AppearanceSettingsSection section;
  @override
  Widget build(BuildContext context) {
    // Subscribe even when the injected builder only reads its controller.
    AppearanceScope.of(context);
    return AlertDialog(
      title: EditorDialogHeader(label: section.label),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(child: section.builder(context)),
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

DefaultAppearance _defaultAppearance(BuildContext context) {
  final appearance = AppearanceScope.of(context);
  if (appearance is DefaultAppearance) return appearance;
  throw StateError('This section requires DefaultAppearance.');
}

Widget _controls(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: children,
);

Widget _dimensions(BuildContext context) {
  final a = _defaultAppearance(context);
  final c = AppearanceScope.controllerOf(context)!;
  return _controls([
    AppearanceSettingsSlider(
      'Hauteur des cartes',
      a.cardHeight,
      142,
      300,
      (v) => c.value = _defaultAppearance(context).copyWith(cardHeight: v),
    ),
    AppearanceSettingsSlider(
      'Largeur des cartes',
      a.cardWidth,
      180,
      360,
      (v) => c.value = _defaultAppearance(context).copyWith(cardWidth: v),
    ),
    AppearanceSettingsSlider(
      'Hauteur des lignes',
      a.rowHeight,
      DefaultAppearance.minRowHeight,
      DefaultAppearance.maxRowHeight,
      (v) => c.value = _defaultAppearance(context).copyWith(rowHeight: v),
    ),
    AppearanceSettingsSlider(
      'Espacement',
      a.spacing,
      DefaultAppearance.minSpacing,
      DefaultAppearance.maxSpacing,
      (v) => c.value = _defaultAppearance(context).copyWith(spacing: v),
    ),
  ]);
}

Widget _text(BuildContext context) {
  final a = _defaultAppearance(context);
  final c = AppearanceScope.controllerOf(context)!;
  return _controls([
    AppearanceSettingsSlider(
      'Taille du texte',
      a.fontSize,
      10,
      16,
      (v) => c.value = _defaultAppearance(context).copyWith(fontSize: v),
    ),
    AppearanceSettingsSlider(
      'Taille des icônes',
      a.iconSize,
      24,
      64,
      (v) => c.value = _defaultAppearance(context).copyWith(iconSize: v),
    ),
  ]);
}

Widget _scrollFade(BuildContext context) {
  final a = _defaultAppearance(context);
  final c = AppearanceScope.controllerOf(context)!;
  return _controls([
    SwitchListTile(
      title: const EditorDialogHeader(label: 'Activer le fondu'),
      value: a.scrollFadeEnabled,
      onChanged: (v) =>
          c.value = _defaultAppearance(context).copyWith(scrollFadeEnabled: v),
    ),
    const Text(
      'Le fondu apparaît uniquement aux bords où il reste des fichiers '
      'à faire défiler, en liste comme en grille.',
    ),
    const SizedBox(height: 16),
    if (a.scrollFadeEnabled)
      AppearanceSettingsSlider(
        'Hauteur du fondu (px)',
        a.scrollFadeExtent,
        DefaultAppearance.minScrollFadeExtent,
        DefaultAppearance.maxScrollFadeExtent,
        (v) =>
            c.value = _defaultAppearance(context).copyWith(scrollFadeExtent: v),
      ),
    TextButton(
      onPressed: () =>
          c.value = _defaultAppearance(context)
              .copyWith(scrollFadeEnabled: true, scrollFadeExtent: 28),
      child: const Text('Réinitialiser le fondu'),
    ),
  ]);
}

Widget _responsiveLayout(BuildContext context) {
  final appearance = AppearanceScope.of(context);
  final controller = AppearanceScope.controllerOf(context)!;
  final config = appearance.responsiveLayout;
  final scheme = Theme.of(context).colorScheme;

  void update(ResponsiveLayoutConfig next) {
    next.validate();
    controller.value = controller.value.withResponsiveLayout(next);
  }

  Widget numberRow({
    required Key fieldKey,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        EditorNumberField(
          key: fieldKey,
          label: label,
          value: value,
          min: min,
          max: max,
          integer: true,
          unit: 'px',
          onChanged: onChanged,
        ),
      ],
    ),
  );

  return _controls([
    SegmentedButton<PageContainerMode>(
      key: const ValueKey('responsive-container-mode'),
      segments: const [
        ButtonSegment(
          value: PageContainerMode.fullPage,
          label: Text('Pleine page'),
          icon: Icon(Icons.fullscreen),
        ),
        ButtonSegment(
          value: PageContainerMode.constrained,
          label: Text('Conteneur centré'),
          icon: Icon(Icons.view_column_outlined),
        ),
      ],
      selected: {config.containerMode},
      onSelectionChanged: (modes) =>
          update(config.copyWith(containerMode: modes.single)),
    ),
    const SizedBox(height: 8),
    Text(
      config.containerMode.description,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: 16),
    if (config.containerMode == PageContainerMode.constrained) ...[
      Text(
        'Conteneur & Gutters du body',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 8),
      numberRow(
        fieldKey: const ValueKey('responsive-max-width'),
        label: 'Largeur maximale (max-width)',
        value: config.maxWidth,
        min: ResponsiveLayoutConfig.minMaxWidth,
        max: ResponsiveLayoutConfig.maxMaxWidth,
        onChanged: (v) => update(config.copyWith(maxWidth: v)),
      ),
      numberRow(
        fieldKey: const ValueKey('responsive-gutter-mobile'),
        label: 'Gutter Mobile / Tablette',
        value: config.gutters.mobile,
        min: 0,
        max: ResponsiveGuttersConfig.maxGutter,
        onChanged: (v) =>
            update(config.copyWith(gutters: config.gutters.copyWith(mobile: v))),
      ),
      numberRow(
        fieldKey: const ValueKey('responsive-gutter-desktop'),
        label: 'Gutter Desktop / Large Desktop',
        value: config.gutters.desktop,
        min: 0,
        max: ResponsiveGuttersConfig.maxGutter,
        onChanged: (v) => update(
          config.copyWith(gutters: config.gutters.copyWith(desktop: v)),
        ),
      ),
      const SizedBox(height: 16),
    ],
    Text(
      'Seuils des Breakpoints',
      style: Theme.of(context).textTheme.titleSmall,
    ),
    const SizedBox(height: 8),
    numberRow(
      fieldKey: const ValueKey('responsive-bp-mobile'),
      label: 'Mobile (aperçu)',
      value: config.breakpoints.mobileWidth,
      min: 200,
      max: config.breakpoints.tabletMinWidth - 1,
      onChanged: (v) => update(
        config.copyWith(
          breakpoints: config.breakpoints.copyWith(mobileWidth: v),
        ),
      ),
    ),
    numberRow(
      fieldKey: const ValueKey('responsive-bp-tablet'),
      label: 'Tablette (seuil min)',
      value: config.breakpoints.tabletMinWidth,
      min: config.breakpoints.mobileWidth + 1,
      max: config.breakpoints.desktopMinWidth - 1,
      onChanged: (v) => update(
        config.copyWith(
          breakpoints: config.breakpoints.copyWith(tabletMinWidth: v),
        ),
      ),
    ),
    numberRow(
      fieldKey: const ValueKey('responsive-bp-desktop'),
      label: 'Desktop (seuil min)',
      value: config.breakpoints.desktopMinWidth,
      min: config.breakpoints.tabletMinWidth + 1,
      max: config.breakpoints.largeDesktopMinWidth - 1,
      onChanged: (v) => update(
        config.copyWith(
          breakpoints: config.breakpoints.copyWith(desktopMinWidth: v),
        ),
      ),
    ),
    numberRow(
      fieldKey: const ValueKey('responsive-bp-large-desktop'),
      label: 'Large Desktop (seuil min)',
      value: config.breakpoints.largeDesktopMinWidth,
      min: config.breakpoints.desktopMinWidth + 1,
      max: 10000,
      onChanged: (v) => update(
        config.copyWith(
          breakpoints: config.breakpoints.copyWith(largeDesktopMinWidth: v),
        ),
      ),
    ),
    const SizedBox(height: 12),
    Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        key: const ValueKey('responsive-reset'),
        onPressed: config.isDefault
            ? null
            : () => update(const ResponsiveLayoutConfig()),
        child: const Text('Réinitialiser'),
      ),
    ),
  ]);
}

Widget _window(BuildContext context) {
  final c = AppearanceScope.controllerOf(context)!;
  return _controls([
    const Text(
      'Atténue toute la fenêtre, y compris le texte et les icônes. '
      'Pour ne rendre transparent que le fond, éditez le style du fond '
      '(pinceau de la barre d’outils, puis clic droit).',
    ),
    AppearanceSettingsSlider(
      'Opacité de la fenêtre',
      c.value.windowOpacity,
      .2,
      1,
      (v) => c.value = c.value.copyWith(windowOpacity: v),
      allowAboveMax: false,
    ),
  ]);
}

/// Curseur numérique étiqueté utilisé dans les panneaux de réglages d'apparence.
class AppearanceSettingsSlider extends StatelessWidget {
  const AppearanceSettingsSlider(
    this.label,
    this.value,
    this.min,
    this.max,
    this.onChanged, {
    this.allowAboveMax = true,
    super.key,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool allowAboveMax;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label),
      EditorHistorySlider(
        sliderKey: ValueKey(label),
        value: value,
        min: min,
        max: max,
        allowAboveMax: allowAboveMax,
        onChanged: onChanged,
      ),
    ],
  );
}
