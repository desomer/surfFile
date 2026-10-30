import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/super_tab_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../theme/appearance.dart';
import '../../../theme/container_style.dart';
import '../../../theme/neon_style.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../dialogs/editor_tabbed_wizard.dart';
import '../repositories/repository_binding_fields.dart';
import '../styles/container_style_editor.dart';
import '../styles/style_editor_panel.dart';

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
              SegmentedButton<SuperTabBarPosition>(
                key: const ValueKey('super-tab-position'),
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
                selected: {_draft.tabBarPosition},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    setState(
                      () => _draft = _draft.copyWith(
                        tabBarPosition: selected.first,
                      ),
                    );
                  }
                },
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
  late EditorWizardTab _tab =
      widget.initialTab == EditorWizardTab.dimensions &&
          widget.dimensionDelegate != null
      ? EditorWizardTab.dimensions
      : EditorWizardTab.properties;
  late SuperTabConfig _draft = widget.config;
  late bool _dense = StyleEditorPanel.preferredDense;

  void _update(SuperTabConfig next) {
    setState(() => _draft = next);
    widget.onPreviewChanged?.call(next);
  }

  void _updateStyle(ContainerStyle style) {
    _update(_draft.copyWith(tabBarStyle: style));
  }

  void _apply() {
    final delegate = widget.dimensionDelegate;
    if (delegate != null && !delegate.validate()) {
      if (_tab != EditorWizardTab.dimensions) {
        setState(() => _tab = EditorWizardTab.dimensions);
      }
      return;
    }
    Navigator.of(context).pop(_draft..validate());
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
            SegmentedButton<SuperTabBarPosition>(
              key: const ValueKey('super-tab-bar-position'),
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
              selected: {_draft.tabBarPosition},
              onSelectionChanged: (selected) {
                if (selected.isNotEmpty) {
                  _update(_draft.copyWith(tabBarPosition: selected.first));
                }
              },
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
              styleColorTile(
                'Couleur de l’indicateur',
                _draft.indicatorColor ?? scheme.primary,
                (color) => _update(_draft.copyWith(indicatorColor: color)),
                key: const ValueKey('super-tab-indicator-color'),
                onClear: () =>
                    _update(_draft.copyWith(clearIndicatorColor: true)),
              ),
              if (_draft.indicatorColor != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        _update(_draft.copyWith(clearIndicatorColor: true)),
                    child: const Text('Couleur d’indicateur du thème'),
                  ),
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
            styleColorTile(
              'Couleur du séparateur',
              _draft.dividerColor ?? scheme.outlineVariant,
              (color) => _update(_draft.copyWith(dividerColor: color)),
              key: const ValueKey('super-tab-divider-color'),
              onClear: () => _update(_draft.copyWith(clearDividerColor: true)),
            ),
            if (_draft.dividerColor != null || _draft.dividerHeight != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _update(
                    _draft.copyWith(
                      clearDividerColor: true,
                      clearDividerHeight: true,
                    ),
                  ),
                  child: const Text('Séparateur par défaut'),
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
            styleColorTile(
              'Onglet sélectionné (texte & icône)',
              _draft.labelColor ?? scheme.primary,
              (color) => _update(_draft.copyWith(labelColor: color)),
              key: const ValueKey('super-tab-label-color'),
              onClear: () => _update(_draft.copyWith(clearLabelColor: true)),
            ),
            if (_draft.labelColor != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      _update(_draft.copyWith(clearLabelColor: true)),
                  child: const Text('Couleur active du thème'),
                ),
              ),
            styleColorTile(
              'Onglets non sélectionnés (texte & icône)',
              _draft.unselectedLabelColor ?? scheme.onSurfaceVariant,
              (color) => _update(_draft.copyWith(unselectedLabelColor: color)),
              key: const ValueKey('super-tab-unselected-label-color'),
              onClear: () =>
                  _update(_draft.copyWith(clearUnselectedLabelColor: true)),
            ),
            if (_draft.unselectedLabelColor != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _update(
                    _draft.copyWith(clearUnselectedLabelColor: true),
                  ),
                  child: const Text('Couleur inactive du thème'),
                ),
              ),
            styleColorTile(
              'Voile au survol / clic (overlay)',
              _draft.overlayColor ?? scheme.primary.withValues(alpha: 0.12),
              (color) => _update(_draft.copyWith(overlayColor: color)),
              key: const ValueKey('super-tab-overlay-color'),
              onClear: () => _update(_draft.copyWith(clearOverlayColor: true)),
            ),
            if (_draft.overlayColor != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      _update(_draft.copyWith(clearOverlayColor: true)),
                  child: const Text('Voile du thème par défaut'),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(_dense ? 680.0 : 1080.0, screen.width - 96);
    final height = math.max(320.0, math.min(680.0, screen.height - 260));
    final colors = Theme.of(context).colorScheme;
    final style = _draft.tabBarStyle;
    final delegate = widget.dimensionDelegate;
    final onDimensions = _tab == EditorWizardTab.dimensions && delegate != null;
    return AlertDialog(
      key: const ValueKey('super-tab-bar-style-settings'),
      insetPadding: const EdgeInsets.all(24),
      constraints: BoxConstraints(maxWidth: width + 48),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EditorWizardTabBar(
              selectedTab: _tab,
              propertiesEnabled: true,
              dimensionsEnabled: delegate != null,
              onTabSelected: (next) {
                if (next != _tab) setState(() => _tab = next);
              },
            ),
            const SizedBox(height: 12),
            if (onDimensions) ...[
              if (delegate.labelListenable case final listenable?)
                ValueListenableBuilder<String>(
                  valueListenable: listenable,
                  builder: (context, _, _) => EditorDialogHeader(
                    label: delegate.title,
                    editableLabel: delegate.editableLabel,
                    onLabelChanged: delegate.onLabelChanged,
                  ),
                )
              else
                EditorDialogHeader(
                  label: delegate.title,
                  editableLabel: delegate.editableLabel,
                  onLabelChanged: delegate.onLabelChanged,
                ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: delegate.buildContent(context),
                ),
              ),
            ] else
              Expanded(
                child: ContainerStyleEditor(
                  label: widget.label,
                  collapsible: false,
          dense: _dense,
          onDenseChanged: (value) => setState(() {
            _dense = value;
            widget.dockWidth.value = value ? 680 : 1080;
          }),
          style: style,
          onStyle: _updateStyle,
          extended: true,
          value: style.fill,
          solidColor: style.color ?? colors.surface,
          radius: style.radius,
          borderWidth: style.borderWidth,
          borderColor: style.borderColor ?? colors.outlineVariant,
          elevation: style.elevation,
          shadowOpacity: style.shadowOpacity,
          opacity: style.opacity,
          neon: style.neon ?? const NeonStyle(),
          accent: widget.accent,
          onChanged: (fill) => _updateStyle(style.copyWith(fill: fill)),
          onSolidColorChanged: (color) =>
              _updateStyle(style.copyWith(color: color)),
          onRadiusChanged: (radius) =>
              _updateStyle(style.copyWith(radius: radius)),
          onBorderWidthChanged: (borderWidth) =>
              _updateStyle(style.copyWith(borderWidth: borderWidth)),
          onBorderColorChanged: (borderColor) =>
              _updateStyle(style.copyWith(borderColor: borderColor)),
          onResetBorderColor: () =>
              _updateStyle(style.copyWith(resetBorderColor: true)),
          onElevationChanged: (elevation) =>
              _updateStyle(style.copyWith(elevation: elevation)),
          onShadowOpacityChanged: (shadowOpacity) =>
              _updateStyle(style.copyWith(shadowOpacity: shadowOpacity)),
          padding: style.padding,
          margin: style.margin,
          onPaddingChanged: (padding) =>
              _updateStyle(style.copyWith(padding: padding)),
          onMarginChanged: (margin) =>
              _updateStyle(style.copyWith(margin: margin)),
          onNeonChanged: (neon) =>
              _updateStyle(style.copyWith(neon: neon)),
          hoverEffect: style.hoverEffect,
          onHoverEffectChanged: (hover) =>
              _updateStyle(style.copyWith(hoverEffect: hover)),
          hoverTint: style.hoverTint,
          hoverColor: style.hoverColor,
          onHoverTintChanged: (tint) =>
              _updateStyle(style.copyWith(hoverTint: tint)),
          onHoverColorChanged: (color) =>
              _updateStyle(style.copyWith(hoverColor: color)),
          onResetHoverColor: () =>
              _updateStyle(style.copyWith(resetHoverColor: true)),
          interactionEffect: style.interactionEffect,
          onInteractionEffectChanged: (effect) => _updateStyle(
            style.copyWith(interactionEffect: effect),
          ),
          designSystem: style.designSystem,
          onDesignSystemChanged: (system) =>
              _updateStyle(system.apply(style)),
          onResetColor: () =>
              _updateStyle(style.copyWith(resetColor: true)),
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
              ),
          ],
        ),
      ),
      actions: [
        if (onDimensions)
          ...delegate.buildExtraActions(
            context,
            onResetAndClose: _apply,
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('super-tab-bar-style-apply'),
          onPressed: _apply,
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}

