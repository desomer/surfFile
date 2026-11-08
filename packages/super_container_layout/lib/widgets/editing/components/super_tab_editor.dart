/// Fenêtre d'édition d'un composant d'onglets [SuperTab].
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../models/super_tab_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../theme/appearance.dart';
import '../../../theme/container_style.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../repositories/repository_binding_fields.dart';
import '../styles/container_style_editor.dart';
import '../styles/style_editor_panel.dart';
import 'shared/collection_editor_controls.dart';
import 'shared/editor_color_fields.dart';
import 'shared/editor_segmented_field.dart';

/// Ouvre la fenêtre simple des propriétés générales d'un composant [SuperTab]
/// (utilisée sur le menu contextuel du composant `Tab` et de ses zones de contenu).
Future<SuperTabConfig?> showSuperTabEditor({
  required BuildContext context,
  required SuperTabConfig config,
}) {
  final repositories = JsonRepositoryScope.maybeOf(context);
  final scope = JsonListScope.maybeOf(context);
  return runWithDimensionDelegate<SuperTabConfig>(
    context: context,
    runner: (initialTab, dimensionDelegate) => showEditorDialog<SuperTabConfig>(
      context: context,
      target: context,
      builder: (_) => _SuperTabSimpleEditor(
        initialTab: initialTab,
        dimensionDelegate: dimensionDelegate,
        config: config,
        repositories: repositories,
        scope: scope,
      ),
    ),
  );
}

class _SuperTabSimpleEditor extends StatefulWidget {
  const _SuperTabSimpleEditor({
    required this.initialTab,
    required this.dimensionDelegate,
    required this.config,
    required this.repositories,
    required this.scope,
  });

  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;
  final SuperTabConfig config;
  final JsonRepositoryStore? repositories;
  final JsonListScope? scope;

  @override
  State<_SuperTabSimpleEditor> createState() => _SuperTabSimpleEditorState();
}

class _SuperTabSimpleEditorState extends State<_SuperTabSimpleEditor> {
  late SuperTabConfig _draft = widget.config;
  late final TextEditingController _initialIndex = TextEditingController(
    text: '${widget.config.initialIndex}',
  );
  late final TextEditingController _emptyText = TextEditingController(
    text: widget.config.emptyText,
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _initialIndex.dispose();
    _emptyText.dispose();
    super.dispose();
  }

  Future<bool> _apply() async {
    final parsedIndex = int.tryParse(_initialIndex.text.trim());
    if (parsedIndex == null || parsedIndex < 0) {
      setState(() => _error = 'L’index initial doit être un entier >= 0.');
      return false;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = _draft.copyWith(
        initialIndex: parsedIndex,
        emptyText: _emptyText.text,
      )..validate();
      final binding = config.binding;
      final scope = widget.scope;
      if (binding != null && !(scope?.placeholder ?? false)) {
        if (binding.path.trim().isEmpty) {
          throw const FormatException('Chemin de liaison requis.');
        }
        final store = widget.repositories;
        if (store != null && config.mode == SuperTabMode.dynamic) {
          final resolved = JsonListScope.resolveSelected(
            binding,
            scope,
            store,
          ).binding;
          if (resolved != null) {
            await store.readArray(resolved.repositoryId!, resolved.path);
          }
        }
      }
      if (mounted) Navigator.of(context).pop(config);
      return true;
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    } on FileSystemException {
      if (mounted) setState(() => _error = 'Impossible de lire le repository.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDynamic = _draft.mode == SuperTabMode.dynamic;
    return EditorTabbedAlertDialog(
      dialogKey: const ValueKey('super-tab-settings'),
      initialTab: widget.initialTab,
      dimensionDelegate: widget.dimensionDelegate,
      propertiesTitle: const Text('Configurer les onglets'),
      propertiesWidth: 440,
      busy: _busy,
      onApply: _apply,
      onCancel: () => Navigator.of(context).pop(),
      propertiesContentBuilder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          EditorSegmentedField.tabMode(
            buttonKey: const ValueKey('super-tab-mode'),
            spacing: 12,
            value: _draft.mode,
            onChanged: (mode) =>
                setState(() => _draft = _draft.copyWith(mode: mode)),
          ),
          EditorSegmentedField.tabBarPosition(
            buttonKey: const ValueKey('super-tab-position'),
            spacing: 12,
            value: _draft.tabBarPosition,
            onChanged: (pos) =>
                setState(() => _draft = _draft.copyWith(tabBarPosition: pos)),
          ),
          EditorSwitchTile(
            tileKey: const ValueKey('super-tab-scrollable'),
            title: 'Onglets défilables',
            subtitle:
                'Défilement horizontal au lieu d’étirer sur toute la largeur',
            value: _draft.isScrollable,
            onChanged: (value) =>
                setState(() => _draft = _draft.copyWith(isScrollable: value)),
          ),
          TextFormField(
            key: const ValueKey('super-tab-initial-index'),
            controller: _initialIndex,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Index d’onglet initial',
            ),
          ),
          if (isDynamic) ...[
            ...buildCollectionMutationSwitches(
              keyPrefix: 'super-tab',
              allowAdd: _draft.allowAdd,
              onAllowAddChanged: (value) =>
                  setState(() => _draft = _draft.copyWith(allowAdd: value)),
              allowRemove: _draft.allowRemove,
              onAllowRemoveChanged: (value) =>
                  setState(() => _draft = _draft.copyWith(allowRemove: value)),
              addTitle: 'Autoriser l’ajout d’onglet',
              removeTitle: 'Autoriser la suppression d’onglet',
            ),
            TextFormField(
              key: const ValueKey('super-tab-empty-text'),
              controller: _emptyText,
              decoration: const InputDecoration(
                labelText: 'Message si aucun onglet',
              ),
            ),
          ],
              const Divider(),
              Text(
                isDynamic
                    ? 'Tableau JSON source des onglets'
                    : 'Liaison optionnelle de l’index actif',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              RepositoryBindingFields(
                keyPrefix: 'super-tab-binding',
                binding: _draft.binding,
                store: widget.repositories,
                listScope: widget.scope,
                pathHint: isDynamic
                    ? 'categories ou clients[?].commandes'
                    : 'ui.ongletActif',
                onChanged: (binding) => setState(
                  () => _draft = _draft.copyWith(
                    binding: binding,
                    clearBinding: binding == null,
                  ),
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const ValueKey('super-tab-editor-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
    );
  }
}

/// Ouvre le panneau complet d'édition de style de la `TabBar` (exclusivement
/// sur la zone « Onglets » du composant [SuperTab]).
Future<SuperTabConfig?> showSuperTabBarStyleEditor({
  required BuildContext context,
  required SuperTabConfig config,
  String label = 'Onglets',
  ValueChanged<SuperTabConfig?>? onPreviewChanged,
}) async {
  final accent = AppearanceScope.of(context).accent;
  final dockWidth = ValueNotifier(
    StyleEditorPanel.preferredDense ? 680.0 : 1080.0,
  );
  try {
    return await runWithDimensionDelegate<SuperTabConfig>(
      context: context,
      runner: (initialTab, dimensionDelegate) =>
          showEditorDialog<SuperTabConfig>(
            context: context,
            target: context,
            preferredWidth: dockWidth,
            barrierDismissible: true,
            barrierColor: Colors.transparent,
            builder: (_) => _SuperTabBarStyleEditor(
              initialTab: initialTab,
              dimensionDelegate: dimensionDelegate,
              config: config,
              label: label,
              accent: accent,
              dockWidth: dockWidth,
              onPreviewChanged: onPreviewChanged,
            ),
          ),
    );
  } finally {
    onPreviewChanged?.call(null);
    dockWidth.dispose();
  }
}

class _SuperTabBarStyleEditor extends StatefulWidget {
  const _SuperTabBarStyleEditor({
    required this.initialTab,
    required this.dimensionDelegate,
    required this.config,
    required this.label,
    required this.accent,
    required this.dockWidth,
    this.onPreviewChanged,
  });

  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;
  final SuperTabConfig config;
  final String label;
  final Color accent;
  final ValueNotifier<double> dockWidth;
  final ValueChanged<SuperTabConfig?>? onPreviewChanged;

  @override
  State<_SuperTabBarStyleEditor> createState() =>
      _SuperTabBarStyleEditorState();
}

class _SuperTabBarStyleEditorState extends State<_SuperTabBarStyleEditor> {
  late SuperTabConfig _draft = widget.config;

  void _update(SuperTabConfig next) {
    setState(() => _draft = next);
    widget.onPreviewChanged?.call(next);
  }

  void _updateStyle(ContainerStyle style) {
    _update(_draft.copyWith(tabBarStyle: style));
  }

  bool _apply() {
    Navigator.of(context).pop(_draft..validate());
    return true;
  }

  List<StyleEditorSection> _buildTabBarSections(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      StyleEditorSection(
        id: 'tabbar-layout',
        title: 'Barre d’onglets',
        tag: 'TabBar',
        icon: Icons.tab_outlined,
        count: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            EditorSegmentedField.tabBarPosition(
              buttonKey: const ValueKey('super-tab-bar-position'),
              spacing: 10,
              value: _draft.tabBarPosition,
              onChanged: (pos) => _update(_draft.copyWith(tabBarPosition: pos)),
            ),
            EditorSwitchTile(
              tileKey: const ValueKey('super-tab-bar-scrollable'),
              title: 'Onglets défilables',
              subtitle:
                  'Défilement horizontal au lieu d’étirer sur toute la largeur',
              value: _draft.isScrollable,
              onChanged: (value) => _update(
                _draft.copyWith(
                  isScrollable: value,
                  clearTabAlignment:
                      !value && _draft.tabAlignment != TabAlignment.fill,
                ),
              ),
            ),
            EditorSegmentedField<TabAlignment?>(
              buttonKey: const ValueKey('super-tab-alignment'),
              label: 'Alignement des onglets',
              spacing: 10,
              value: _draft.tabAlignment,
              options: [
                const EditorSegmentOption<TabAlignment?>(
                  value: null,
                  label: 'Automatique',
                  icon: Icons.hdr_auto_outlined,
                  iconSize: 14,
                  flexibleIcon: true,
                ),
                if (!_draft.isScrollable)
                  const EditorSegmentOption<TabAlignment?>(
                    value: TabAlignment.fill,
                    label: 'Étirer (fill)',
                    icon: Icons.format_align_justify,
                    iconSize: 14,
                    flexibleIcon: true,
                  ),
                if (_draft.isScrollable) ...const [
                  EditorSegmentOption<TabAlignment?>(
                    value: TabAlignment.start,
                    label: 'Début (start)',
                    icon: Icons.format_align_left,
                    iconSize: 14,
                    flexibleIcon: true,
                  ),
                  EditorSegmentOption<TabAlignment?>(
                    value: TabAlignment.startOffset,
                    label: 'Début décalé (startOffset)',
                    icon: Icons.format_indent_increase,
                    iconSize: 14,
                    flexibleIcon: true,
                  ),
                ],
                const EditorSegmentOption<TabAlignment?>(
                  value: TabAlignment.center,
                  label: 'Centré (center)',
                  icon: Icons.format_align_center,
                  iconSize: 14,
                  flexibleIcon: true,
                ),
              ],
              onChanged: (alignment) => _update(
                _draft.copyWith(
                  tabAlignment: alignment,
                  clearTabAlignment: alignment == null,
                ),
              ),
            ),
            StyleSliderField(
              label: 'Espacement horizontal des onglets',
              value: _draft.labelHorizontalPadding ?? 16,
              min: 0,
              max: 48,
              unit: ' dp',
              sliderKey: const ValueKey('super-tab-label-padding'),
              onChanged: (value) =>
                  _update(_draft.copyWith(labelHorizontalPadding: value)),
            ),
            if (_draft.labelHorizontalPadding != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _update(
                    _draft.copyWith(clearLabelHorizontalPadding: true),
                  ),
                  child: const Text('Espacement automatique'),
                ),
              ),
          ],
        ),
      ),
      StyleEditorSection(
        id: 'tabbar-indicator',
        title: 'Indicateur & Séparateur',
        tag: 'indicator / divider',
        icon: Icons.linear_scale,
        count: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            EditorSegmentedField.tabIndicatorKind(
              buttonKey: const ValueKey('super-tab-indicator-kind'),
              spacing: 10,
              value: _draft.indicatorKind,
              onChanged: (kind) => _update(_draft.copyWith(indicatorKind: kind)),
            ),
            if (_draft.indicatorKind != SuperTabIndicatorKind.none) ...[
              EditorSegmentedField<TabBarIndicatorSize>(
                buttonKey: const ValueKey('super-tab-indicator-size'),
                label: 'Largeur de l’indicateur',
                spacing: 10,
                value: _draft.indicatorSize,
                options: const [
                  EditorSegmentOption(
                    value: TabBarIndicatorSize.tab,
                    label: 'Toute la largeur de l’onglet (tab)',
                    icon: Icons.swap_horiz,
                  ),
                  EditorSegmentOption(
                    value: TabBarIndicatorSize.label,
                    label: 'Largeur du contenu (label)',
                    icon: Icons.text_fields,
                  ),
                ],
                onChanged: (size) =>
                    _update(_draft.copyWith(indicatorSize: size)),
              ),
              ThemeResetColorTile(
                label: 'Couleur de l’indicateur',
                effectiveColor: _draft.indicatorColor ?? scheme.primary,
                isOverridden: _draft.indicatorColor != null,
                tileKey: const ValueKey('super-tab-indicator-color'),
                resetLabel: 'Couleur d’indicateur du thème',
                onChanged: (color) =>
                    _update(_draft.copyWith(indicatorColor: color)),
                onClear: () =>
                    _update(_draft.copyWith(clearIndicatorColor: true)),
              ),
              if (_draft.indicatorKind == SuperTabIndicatorKind.underline)
                StyleSliderField(
                  label: 'Épaisseur de l’indicateur',
                  value: _draft.indicatorWeight,
                  min: 1,
                  max: 12,
                  unit: ' dp',
                  sliderKey: const ValueKey('super-tab-indicator-weight'),
                  onChanged: (value) =>
                      _update(_draft.copyWith(indicatorWeight: value)),
                ),
              StyleSliderField(
                label: 'Rayon de l’indicateur',
                value: _draft.indicatorRadius,
                min: 0,
                max: 32,
                unit: ' dp',
                sliderKey: const ValueKey('super-tab-indicator-radius'),
                onChanged: (value) =>
                    _update(_draft.copyWith(indicatorRadius: value)),
              ),
              StyleSliderField(
                label: 'Marge horizontale de l’indicateur',
                value: _draft.indicatorHorizontalPadding,
                min: 0,
                max: 32,
                unit: ' dp',
                sliderKey: const ValueKey('super-tab-indicator-hpad'),
                onChanged: (value) => _update(
                  _draft.copyWith(indicatorHorizontalPadding: value),
                ),
              ),
              StyleSliderField(
                label: 'Marge verticale de l’indicateur',
                value: _draft.indicatorVerticalPadding,
                min: 0,
                max: 16,
                unit: ' dp',
                sliderKey: const ValueKey('super-tab-indicator-vpad'),
                onChanged: (value) =>
                    _update(_draft.copyWith(indicatorVerticalPadding: value)),
              ),
            ],
            const Divider(),
            StyleSliderField(
              label: 'Hauteur du trait de séparation (0 = masqué)',
              value: _draft.dividerHeight ?? 1,
              min: 0,
              max: 8,
              unit: ' dp',
              sliderKey: const ValueKey('super-tab-divider-height'),
              onChanged: (value) =>
                  _update(_draft.copyWith(dividerHeight: value)),
            ),
            ThemeResetColorTile(
              label: 'Couleur du séparateur',
              effectiveColor: _draft.dividerColor ?? scheme.outlineVariant,
              isOverridden:
                  _draft.dividerColor != null || _draft.dividerHeight != null,
              tileKey: const ValueKey('super-tab-divider-color'),
              resetLabel: 'Séparateur par défaut',
              onChanged: (color) =>
                  _update(_draft.copyWith(dividerColor: color)),
              onClear: () => _update(
                _draft.copyWith(
                  clearDividerColor: true,
                  clearDividerHeight: true,
                ),
              ),
            ),
          ],
        ),
      ),
      StyleEditorSection(
        id: 'tabbar-colors',
        title: 'Couleurs des onglets',
        tag: 'labelColor / overlayColor',
        icon: Icons.palette_outlined,
        count: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            ThemeResetColorTile(
              label: 'Onglet sélectionné (texte & icône)',
              effectiveColor: _draft.labelColor ?? scheme.primary,
              isOverridden: _draft.labelColor != null,
              tileKey: const ValueKey('super-tab-label-color'),
              resetLabel: 'Couleur active du thème',
              onChanged: (color) =>
                  _update(_draft.copyWith(labelColor: color)),
              onClear: () => _update(_draft.copyWith(clearLabelColor: true)),
            ),
            ThemeResetColorTile(
              label: 'Onglets non sélectionnés (texte & icône)',
              effectiveColor:
                  _draft.unselectedLabelColor ?? scheme.onSurfaceVariant,
              isOverridden: _draft.unselectedLabelColor != null,
              tileKey: const ValueKey('super-tab-unselected-label-color'),
              resetLabel: 'Couleur inactive du thème',
              onChanged: (color) =>
                  _update(_draft.copyWith(unselectedLabelColor: color)),
              onClear: () =>
                  _update(_draft.copyWith(clearUnselectedLabelColor: true)),
            ),
            ThemeResetColorTile(
              label: 'Voile au survol / clic (overlay)',
              effectiveColor:
                  _draft.overlayColor ?? scheme.primary.withValues(alpha: 0.12),
              isOverridden: _draft.overlayColor != null,
              tileKey: const ValueKey('super-tab-overlay-color'),
              resetLabel: 'Voile du thème par défaut',
              onChanged: (color) =>
                  _update(_draft.copyWith(overlayColor: color)),
              onClear: () => _update(_draft.copyWith(clearOverlayColor: true)),
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return EditorStyleWizardDialog(
      dialogKey: const ValueKey('super-tab-bar-style-settings'),
      applyButtonKey: const ValueKey('super-tab-bar-style-apply'),
      initialTab: widget.initialTab,
      dimensionDelegate: widget.dimensionDelegate,
      minHeight: 320.0,
      verticalMargin: 260.0,
      onWidthChanged: (value) => widget.dockWidth.value = value,
      onApply: _apply,
      propertiesBuilder: (context, dense, onDenseChanged) =>
          ContainerStyleEditor.fromStyle(
            label: widget.label,
            dense: dense,
            onDenseChanged: onDenseChanged,
            style: _draft.tabBarStyle,
            onStyleChanged: _updateStyle,
            defaultSolidColor: colors.surface,
            defaultBorderColor: colors.outlineVariant,
            accent: widget.accent,
            onReset: () => _update(
              _draft.copyWith(
                tabBarStyle: const ContainerStyle(),
                indicatorKind: SuperTabIndicatorKind.underline,
                indicatorSize: TabBarIndicatorSize.tab,
                clearIndicatorColor: true,
                indicatorWeight: 2.0,
                indicatorRadius: 0.0,
                indicatorHorizontalPadding: 0.0,
                indicatorVerticalPadding: 0.0,
                clearLabelColor: true,
                clearUnselectedLabelColor: true,
                clearOverlayColor: true,
                clearLabelHorizontalPadding: true,
                clearDividerColor: true,
                clearDividerHeight: true,
                clearTabAlignment: true,
              ),
            ),
            extraSections: _buildTabBarSections(context),
          ),
    );
  }
}

