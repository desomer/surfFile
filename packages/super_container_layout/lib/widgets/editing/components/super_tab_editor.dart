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
import 'shared/editor_color_fields.dart';

Widget _buildTabBarPositionSegment({
  required Key key,
  required SuperTabBarPosition value,
  required ValueChanged<SuperTabBarPosition> onChanged,
}) => SegmentedButton<SuperTabBarPosition>(
  key: key,
  showSelectedIcon: false,
  style: const ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ),
  segments: const [
    ButtonSegment(
      value: SuperTabBarPosition.top,
      tooltip: 'En haut',
      icon: Icon(Icons.vertical_align_top, size: 16),
      label: Text('En haut', overflow: TextOverflow.ellipsis),
    ),
    ButtonSegment(
      value: SuperTabBarPosition.bottom,
      tooltip: 'En bas',
      icon: Icon(Icons.vertical_align_bottom, size: 16),
      label: Text('En bas', overflow: TextOverflow.ellipsis),
    ),
  ],
  selected: {value},
  onSelectionChanged: (selected) {
    if (selected.isNotEmpty) onChanged(selected.first);
  },
);

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
              const Text(
                'Mode des onglets',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              SegmentedButton<SuperTabMode>(
                key: const ValueKey('super-tab-mode'),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: SuperTabMode.static,
                    tooltip: 'Statique (onglets fixes)',
                    icon: Icon(Icons.tab, size: 16),
                    label: Text(
                      'Statique (onglets fixes)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: SuperTabMode.dynamic,
                    tooltip: 'Dynamique (tableau JSON du repository)',
                    icon: Icon(Icons.dynamic_feed, size: 16),
                    label: Text(
                      'Dynamique (tableau JSON du repository)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_draft.mode},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    setState(
                      () => _draft = _draft.copyWith(mode: selected.first),
                    );
                  }
                },
              ),
              const Text(
                'Position de la barre d’onglets',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              _buildTabBarPositionSegment(
                key: const ValueKey('super-tab-position'),
                value: _draft.tabBarPosition,
                onChanged: (pos) =>
                    setState(() => _draft = _draft.copyWith(tabBarPosition: pos)),
              ),
              SwitchListTile(
                key: const ValueKey('super-tab-scrollable'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Onglets défilables'),
                subtitle: const Text(
                  'Défilement horizontal au lieu d’étirer sur toute la largeur',
                ),
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
                SwitchListTile(
                  key: const ValueKey('super-tab-allow-add'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoriser l’ajout d’onglet'),
                  value: _draft.allowAdd,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(allowAdd: value)),
                ),
                SwitchListTile(
                  key: const ValueKey('super-tab-allow-remove'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoriser la suppression d’onglet'),
                  value: _draft.allowRemove,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(allowRemove: value),
                  ),
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
            const Text(
              'Position de la barre d’onglets',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            _buildTabBarPositionSegment(
              key: const ValueKey('super-tab-bar-position'),
              value: _draft.tabBarPosition,
              onChanged: (pos) => _update(_draft.copyWith(tabBarPosition: pos)),
            ),
            SwitchListTile(
              key: const ValueKey('super-tab-bar-scrollable'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Onglets défilables'),
              subtitle: const Text(
                'Défilement horizontal au lieu d’étirer sur toute la largeur',
              ),
              value: _draft.isScrollable,
              onChanged: (value) => _update(
                _draft.copyWith(
                  isScrollable: value,
                  clearTabAlignment:
                      !value && _draft.tabAlignment != TabAlignment.fill,
                ),
              ),
            ),
            const Text(
              'Alignement des onglets',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            SegmentedButton<TabAlignment?>(
              key: const ValueKey('super-tab-alignment'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                const ButtonSegment<TabAlignment?>(
                  value: null,
                  tooltip: 'Automatique',
                  icon: Flexible(
                    flex: 0,
                    child: Icon(Icons.hdr_auto_outlined, size: 14),
                  ),
                  label: Text('Automatique', overflow: TextOverflow.ellipsis),
                ),
                if (!_draft.isScrollable)
                  const ButtonSegment<TabAlignment?>(
                    value: TabAlignment.fill,
                    tooltip: 'Étirer (fill)',
                    icon: Flexible(
                      flex: 0,
                      child: Icon(Icons.format_align_justify, size: 14),
                    ),
                    label: Text(
                      'Étirer (fill)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_draft.isScrollable) ...const [
                  ButtonSegment<TabAlignment?>(
                    value: TabAlignment.start,
                    tooltip: 'Début (start)',
                    icon: Flexible(
                      flex: 0,
                      child: Icon(Icons.format_align_left, size: 14),
                    ),
                    label: Text(
                      'Début (start)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment<TabAlignment?>(
                    value: TabAlignment.startOffset,
                    tooltip: 'Début décalé (startOffset)',
                    icon: Flexible(
                      flex: 0,
                      child: Icon(Icons.format_indent_increase, size: 14),
                    ),
                    label: Text(
                      'Début décalé (startOffset)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const ButtonSegment<TabAlignment?>(
                  value: TabAlignment.center,
                  tooltip: 'Centré (center)',
                  icon: Flexible(
                    flex: 0,
                    child: Icon(Icons.format_align_center, size: 14),
                  ),
                  label: Text(
                    'Centré (center)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {_draft.tabAlignment},
              onSelectionChanged: (selected) {
                final alignment = selected.first;
                _update(
                  _draft.copyWith(
                    tabAlignment: alignment,
                    clearTabAlignment: alignment == null,
                  ),
                );
              },
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
            const Text(
              'Style de l’indicateur',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            SegmentedButton<SuperTabIndicatorKind>(
              key: const ValueKey('super-tab-indicator-kind'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: SuperTabIndicatorKind.underline,
                  tooltip: 'Soulignement (Underline)',
                  icon: Icon(Icons.horizontal_rule, size: 16),
                  label: Text(
                    'Soulignement (Underline)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: SuperTabIndicatorKind.box,
                  tooltip: 'Pilule / Boîte remplie (Box)',
                  icon: Icon(Icons.check_box_outline_blank, size: 16),
                  label: Text(
                    'Pilule / Boîte remplie (Box)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: SuperTabIndicatorKind.none,
                  tooltip: 'Aucun indicateur',
                  icon: Icon(Icons.block, size: 16),
                  label: Text(
                    'Aucun indicateur',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {_draft.indicatorKind},
              onSelectionChanged: (selected) {
                if (selected.isNotEmpty) {
                  _update(_draft.copyWith(indicatorKind: selected.first));
                }
              },
            ),
            if (_draft.indicatorKind != SuperTabIndicatorKind.none) ...[
              const Text(
                'Largeur de l’indicateur',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              SegmentedButton<TabBarIndicatorSize>(
                key: const ValueKey('super-tab-indicator-size'),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: TabBarIndicatorSize.tab,
                    tooltip: 'Toute la largeur de l’onglet (tab)',
                    icon: Icon(Icons.swap_horiz, size: 16),
                    label: Text(
                      'Toute la largeur de l’onglet (tab)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: TabBarIndicatorSize.label,
                    tooltip: 'Largeur du contenu (label)',
                    icon: Icon(Icons.text_fields, size: 16),
                    label: Text(
                      'Largeur du contenu (label)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_draft.indicatorSize},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    _update(_draft.copyWith(indicatorSize: selected.first));
                  }
                },
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

