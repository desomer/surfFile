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
import '../repositories/repository_binding_fields.dart';
import '../styles/container_style_editor.dart';
import '../styles/style_editor_panel.dart';
import '../styles/style_extras_controls.dart' show StyleSliderField;

/// Ouvre la fenêtre simple des propriétés générales d'un composant [SuperTab]
/// (utilisée sur le menu contextuel du composant `Tab` et de ses zones de contenu).
Future<SuperTabConfig?> showSuperTabEditor({
  required BuildContext context,
  required SuperTabConfig config,
}) {
  final repositories = JsonRepositoryScope.maybeOf(context);
  final scope = JsonListScope.maybeOf(context);
  return showEditorDialog<SuperTabConfig>(
    context: context,
    target: context,
    builder: (_) => _SuperTabSimpleEditor(
      config: config,
      repositories: repositories,
      scope: scope,
    ),
  );
}

class _SuperTabSimpleEditor extends StatefulWidget {
  const _SuperTabSimpleEditor({
    required this.config,
    required this.repositories,
    required this.scope,
  });

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

  Future<void> _apply() async {
    final parsedIndex = int.tryParse(_initialIndex.text.trim());
    if (parsedIndex == null || parsedIndex < 0) {
      setState(() => _error = 'L’index initial doit être un entier >= 0.');
      return;
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
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException {
      if (mounted) setState(() => _error = 'Impossible de lire le repository.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDynamic = _draft.mode == SuperTabMode.dynamic;
    return AlertDialog(
      key: const ValueKey('super-tab-settings'),
      title: const Text('Configurer les onglets'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              DropdownButtonFormField<SuperTabMode>(
                key: const ValueKey('super-tab-mode'),
                initialValue: _draft.mode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Mode des onglets',
                ),
                items: const [
                  DropdownMenuItem(
                    value: SuperTabMode.static,
                    child: Text('Statique (onglets fixes)'),
                  ),
                  DropdownMenuItem(
                    value: SuperTabMode.dynamic,
                    child: Text('Dynamique (tableau JSON du repository)'),
                  ),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    setState(() => _draft = _draft.copyWith(mode: mode));
                  }
                },
              ),
              DropdownButtonFormField<SuperTabBarPosition>(
                key: const ValueKey('super-tab-position'),
                initialValue: _draft.tabBarPosition,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Position de la barre d’onglets',
                ),
                items: const [
                  DropdownMenuItem(
                    value: SuperTabBarPosition.top,
                    child: Text('En haut'),
                  ),
                  DropdownMenuItem(
                    value: SuperTabBarPosition.bottom,
                    child: Text('En bas'),
                  ),
                ],
                onChanged: (pos) {
                  if (pos != null) {
                    setState(
                      () => _draft = _draft.copyWith(tabBarPosition: pos),
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('super-tab-apply'),
          onPressed: _busy ? null : _apply,
          child: const Text('Appliquer'),
        ),
      ],
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
    return await showEditorDialog<SuperTabConfig>(
      context: context,
      target: context,
      preferredWidth: dockWidth,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (_) => _SuperTabBarStyleEditor(
        config: config,
        label: label,
        accent: accent,
        dockWidth: dockWidth,
        onPreviewChanged: onPreviewChanged,
      ),
    );
  } finally {
    onPreviewChanged?.call(null);
    dockWidth.dispose();
  }
}

class _SuperTabBarStyleEditor extends StatefulWidget {
  const _SuperTabBarStyleEditor({
    required this.config,
    required this.label,
    required this.accent,
    required this.dockWidth,
    this.onPreviewChanged,
  });

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
  late bool _dense = StyleEditorPanel.preferredDense;

  void _update(SuperTabConfig next) {
    setState(() => _draft = next);
    widget.onPreviewChanged?.call(next);
  }

  void _updateStyle(ContainerStyle style) {
    _update(_draft.copyWith(tabBarStyle: style));
  }

  void _apply() {
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
            DropdownButtonFormField<SuperTabBarPosition>(
              key: const ValueKey('super-tab-bar-position'),
              initialValue: _draft.tabBarPosition,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Position de la barre d’onglets',
              ),
              items: const [
                DropdownMenuItem(
                  value: SuperTabBarPosition.top,
                  child: Text('En haut'),
                ),
                DropdownMenuItem(
                  value: SuperTabBarPosition.bottom,
                  child: Text('En bas'),
                ),
              ],
              onChanged: (pos) {
                if (pos != null) {
                  _update(_draft.copyWith(tabBarPosition: pos));
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
            DropdownButtonFormField<TabAlignment?>(
              key: const ValueKey('super-tab-alignment'),
              initialValue: _draft.tabAlignment,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Alignement des onglets',
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Automatique'),
                ),
                if (!_draft.isScrollable)
                  const DropdownMenuItem(
                    value: TabAlignment.fill,
                    child: Text('Étirer (fill)'),
                  ),
                if (_draft.isScrollable) ...const [
                  DropdownMenuItem(
                    value: TabAlignment.start,
                    child: Text('Début (start)'),
                  ),
                  DropdownMenuItem(
                    value: TabAlignment.startOffset,
                    child: Text('Début décalé (startOffset)'),
                  ),
                ],
                const DropdownMenuItem(
                  value: TabAlignment.center,
                  child: Text('Centré (center)'),
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
            DropdownButtonFormField<SuperTabIndicatorKind>(
              key: const ValueKey('super-tab-indicator-kind'),
              initialValue: _draft.indicatorKind,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Style de l’indicateur',
              ),
              items: const [
                DropdownMenuItem(
                  value: SuperTabIndicatorKind.underline,
                  child: Text('Soulignement (Underline)'),
                ),
                DropdownMenuItem(
                  value: SuperTabIndicatorKind.box,
                  child: Text('Pilule / Boîte remplie (Box)'),
                ),
                DropdownMenuItem(
                  value: SuperTabIndicatorKind.none,
                  child: Text('Aucun indicateur'),
                ),
              ],
              onChanged: (kind) {
                if (kind != null) {
                  _update(_draft.copyWith(indicatorKind: kind));
                }
              },
            ),
            if (_draft.indicatorKind != SuperTabIndicatorKind.none) ...[
              DropdownButtonFormField<TabBarIndicatorSize>(
                key: const ValueKey('super-tab-indicator-size'),
                initialValue: _draft.indicatorSize,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Largeur de l’indicateur',
                ),
                items: const [
                  DropdownMenuItem(
                    value: TabBarIndicatorSize.tab,
                    child: Text('Toute la largeur de l’onglet (tab)'),
                  ),
                  DropdownMenuItem(
                    value: TabBarIndicatorSize.label,
                    child: Text('Largeur du contenu (label)'),
                  ),
                ],
                onChanged: (size) {
                  if (size != null) {
                    _update(_draft.copyWith(indicatorSize: size));
                  }
                },
              ),
              styleColorTile(
                'Couleur de l’indicateur',
                _draft.indicatorColor ?? scheme.primary,
                (color) => _update(_draft.copyWith(indicatorColor: color)),
                key: const ValueKey('super-tab-indicator-color'),
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

    return AlertDialog(
      key: const ValueKey('super-tab-bar-style-settings'),
      insetPadding: const EdgeInsets.all(24),
      constraints: BoxConstraints(maxWidth: width + 48),
      content: SizedBox(
        width: width,
        height: height,
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
      actions: [
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

