/// Atelier structuré de l'étape UX 2 : Shell applicatif, identité visuelle
/// avec aperçu live Material 3 & typographie, arborescence des routes et matrice
/// d'accès ([UxNavigationEditorView]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/business_rule_spec.dart';
import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_vision.dart';
import '../../models/ux/ux_navigation_spec.dart';
import '../../services/spec_forge_controller.dart';

/// Vue d'édition de [UxNavigationSpec] combinant configuration du shell,
/// graine de thème visuel Material 3 avec aperçu temps réel, et catalogue
/// hiérarchique des routes ([UxRouteNode]).
class UxNavigationEditorView extends StatefulWidget {
  /// Crée l'atelier d'architecture et navigation connecté au [controller].
  const UxNavigationEditorView({required this.controller, super.key});

  /// Contrôleur principal orchestrant l'état du projet et l'historique Undo/Redo.
  final SpecForgeController controller;

  @override
  State<UxNavigationEditorView> createState() => _UxNavigationEditorViewState();
}

class _UxNavigationEditorViewState extends State<UxNavigationEditorView> {
  static const List<String> _presetFonts = <String>[
    'Inter',
    'Plus Jakarta Sans',
    'Geist',
    'Rubik',
    'Nunito',
    'JetBrains Mono',
  ];

  static const List<({String hex, String label})> _presetAccents = <({
    String hex,
    String label,
  })>[
    (hex: '#3F51B5', label: 'Indigo'),
    (hex: '#2563EB', label: 'Bleu'),
    (hex: '#0D9488', label: 'Teal'),
    (hex: '#059669', label: 'Émeraude'),
    (hex: '#7C3AED', label: 'Violet'),
    (hex: '#D97706', label: 'Ambre'),
    (hex: '#E11D48', label: 'Rubis'),
    (hex: '#475569', label: 'Ardoise'),
  ];

  late final TextEditingController _accentHexCtrl;
  late final TextEditingController _voiceGuidelinesCtrl;
  late final FocusNode _accentFocusNode;
  late final FocusNode _voiceFocusNode;
  Brightness? _previewBrightnessOverride;

  @override
  void initState() {
    super.initState();
    final initialVisual =
        widget.controller.project?.uxSpec.navigation.visualTheme ??
        UxVisualThemeSeed.defaults;
    _accentHexCtrl = TextEditingController(text: initialVisual.accentHex);
    _voiceGuidelinesCtrl = TextEditingController(
      text: initialVisual.uxVoiceGuidelines,
    );
    _accentFocusNode = FocusNode()..addListener(_onAccentFocusChanged);
    _voiceFocusNode = FocusNode();
    widget.controller.addListener(_syncControllersFromModel);
  }

  @override
  void didUpdateWidget(covariant UxNavigationEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncControllersFromModel);
      widget.controller.addListener(_syncControllersFromModel);
      _syncControllersFromModel(force: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncControllersFromModel);
    _accentFocusNode
      ..removeListener(_onAccentFocusChanged)
      ..dispose();
    _voiceFocusNode.dispose();
    _accentHexCtrl.dispose();
    _voiceGuidelinesCtrl.dispose();
    super.dispose();
  }

  void _onAccentFocusChanged() {
    if (_accentFocusNode.hasFocus) return;
    final project = widget.controller.project;
    if (project == null) return;
    final currentVisual = project.uxSpec.navigation.visualTheme;
    final normalized = UxVisualThemeSeed.normalizeAccentHex(
      _accentHexCtrl.text,
      fallback: currentVisual.accentHex,
    );
    if (_accentHexCtrl.text != normalized) {
      _accentHexCtrl.text = normalized;
    }
    if (normalized != currentVisual.accentHex) {
      _updateVisualTheme(project, currentVisual.copyWith(accentHex: normalized));
    }
  }

  void _syncControllersFromModel({bool force = false}) {
    final visual = widget.controller.project?.uxSpec.navigation.visualTheme;
    if (visual == null) return;
    if ((force || !_accentFocusNode.hasFocus) &&
        _accentHexCtrl.text != visual.accentHex) {
      _accentHexCtrl.text = visual.accentHex;
    }
    if ((force || !_voiceFocusNode.hasFocus) &&
        _voiceGuidelinesCtrl.text != visual.uxVoiceGuidelines) {
      _voiceGuidelinesCtrl.text = visual.uxVoiceGuidelines;
    }
  }

  String _generateShortId(String prefix) {
    final raw = shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final token = raw.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : raw;
    return '${prefix}_$token';
  }

  static String _slugify(String input) {
    final lower = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return lower.isEmpty ? 'page' : lower;
  }

  static Color _parseHexColor(String rawHex) {
    final normalized = UxVisualThemeSeed.normalizeAccentHex(rawHex);
    final rgb = int.tryParse(normalized.substring(1), radix: 16) ?? 0x3F51B5;
    return Color(0xFF000000 | rgb);
  }

  static String _colorToHex(Color color) {
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  Future<void> _updateNavigation(
    SpecForgeProject project,
    UxNavigationSpec nextNav,
  ) => widget.controller.updateUxSpec(
    project.uxSpec.copyWith(navigation: nextNav),
  );

  Future<void> _updateVisualTheme(
    SpecForgeProject project,
    UxVisualThemeSeed nextTheme,
  ) => _updateNavigation(
    project,
    project.uxSpec.navigation.copyWith(visualTheme: nextTheme),
  );

  Future<void> _seedRoutesFromModules(SpecForgeProject project) async {
    final nav = project.uxSpec.navigation;
    final nextRoutes = List<UxRouteNode>.from(nav.routes);
    final usedIds = <String>{for (final r in nextRoutes) r.id};
    final usedNonModalPaths = <String>{
      for (final r in nextRoutes)
        if (!r.pageType.isModal) r.path,
    };

    String uniqueRouteId(String base) {
      if (usedIds.add(base)) return base;
      var suffix = 2;
      while (!usedIds.add('${base}_$suffix')) {
        suffix++;
      }
      return '${base}_$suffix';
    }

    String uniqueNonModalPath(String base) {
      final normalized = UxRouteNode.normalizePath(base);
      if (usedNonModalPaths.add(normalized)) return normalized;
      final stem = normalized == '/' ? '/accueil' : normalized;
      var suffix = 2;
      while (!usedNonModalPaths.add('$stem-$suffix')) {
        suffix++;
      }
      return '$stem-$suffix';
    }

    String? firstCreatedId;
    var homeRouteId = nav.homeRouteId;

    final existingHome = nextRoutes
        .where((r) => !r.pageType.isModal && r.path == '/')
        .firstOrNull;
    if (existingHome == null) {
      final homeNode = UxRouteNode(
        id: uniqueRouteId('route_accueil'),
        path: uniqueNonModalPath('/'),
        title: 'Accueil',
        iconName: 'home_outlined',
        pageType: EditorPageType.standard,
        showInPrimaryNav: true,
      );
      nextRoutes.insert(0, homeNode);
      firstCreatedId ??= homeNode.id;
      if (homeRouteId.trim().isEmpty ||
          !nextRoutes.any((r) => r.id == homeRouteId)) {
        homeRouteId = homeNode.id;
      }
    } else if (homeRouteId.trim().isEmpty ||
        !nextRoutes.any((r) => r.id == homeRouteId)) {
      homeRouteId = existingHome.id;
    }

    for (final module in project.cahierDesCharges.modules) {
      final alreadyMapped = nextRoutes.any((r) => r.moduleId == module.id);
      if (alreadyMapped) continue;
      final slug = _slugify(module.name);
      final node = UxRouteNode(
        id: uniqueRouteId('route_$slug'),
        path: uniqueNonModalPath('/$slug'),
        title: module.name,
        iconName: 'widgets_outlined',
        pageType: EditorPageType.standard,
        moduleId: module.id,
        showInPrimaryNav: true,
      );
      nextRoutes.add(node);
      firstCreatedId ??= node.id;
    }

    await _updateNavigation(
      project,
      nav.copyWith(routes: nextRoutes, homeRouteId: homeRouteId),
    );
    if (firstCreatedId != null) {
      widget.controller.focusUxItem(routeId: firstCreatedId);
    }
  }

  Future<void> _openRouteDialog(
    BuildContext context,
    SpecForgeProject project, {
    UxRouteNode? existing,
  }) async {
    final result = await showDialog<UxRouteNode>(
      context: context,
      builder: (_) => _RouteFormDialog(
        project: project,
        existing: existing,
        generatedId: existing?.id ?? _generateShortId('route'),
      ),
    );
    if (result == null) return;
    final freshProject = widget.controller.project ?? project;
    final nav = freshProject.uxSpec.navigation;
    final nextRoutes = List<UxRouteNode>.from(nav.routes);
    final idx = nextRoutes.indexWhere((r) => r.id == result.id);
    if (idx >= 0) {
      nextRoutes[idx] = result;
    } else {
      nextRoutes.add(result);
    }
    final nextHomeId =
        nav.homeRouteId.trim().isEmpty &&
            !result.pageType.isModal &&
            (result.path == '/' || nextRoutes.length == 1)
        ? result.id
        : nav.homeRouteId;
    await _updateNavigation(
      freshProject,
      nav.copyWith(routes: nextRoutes, homeRouteId: nextHomeId),
    );
    if (existing == null) {
      widget.controller.focusUxItem(routeId: result.id);
    }
  }

  Future<void> _deleteRoute(
    SpecForgeProject project,
    UxRouteNode route,
  ) async {
    final nav = project.uxSpec.navigation;
    final nextRoutes = [
      for (final item in nav.routes)
        if (item.id != route.id)
          item.parentRouteId == route.id
              ? item.copyWith(parentRouteId: '')
              : item,
    ];
    final nextHomeId = nav.homeRouteId == route.id
        ? (nextRoutes.where((r) => !r.pageType.isModal).firstOrNull?.id ?? '')
        : nav.homeRouteId;
    await _updateNavigation(
      project,
      nav.copyWith(routes: nextRoutes, homeRouteId: nextHomeId),
    );
    if (widget.controller.focusedRouteId == route.id) {
      widget.controller.focusUxItem(routeId: nextRoutes.firstOrNull?.id);
    }
  }

  List<({UxRouteNode route, int depth})> _buildOrderedRouteTree(
    List<UxRouteNode> routes,
  ) {
    final byId = <String, UxRouteNode>{for (final r in routes) r.id: r};
    final childrenByParent = <String, List<UxRouteNode>>{};
    final roots = <UxRouteNode>[];

    for (final route in routes) {
      final parentId = route.parentRouteId.trim();
      if (parentId.isEmpty || parentId == route.id || !byId.containsKey(parentId)) {
        roots.add(route);
      } else {
        (childrenByParent[parentId] ??= <UxRouteNode>[]).add(route);
      }
    }

    final result = <({UxRouteNode route, int depth})>[];
    final visited = <String>{};

    void visit(UxRouteNode node, int depth) {
      if (!visited.add(node.id)) return;
      result.add((route: node, depth: depth));
      final children = childrenByParent[node.id];
      if (children != null) {
        for (final child in children) {
          visit(child, depth + 1);
        }
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }
    for (final route in routes) {
      if (!visited.contains(route.id)) {
        visit(route, 0);
      }
    }
    return result;
  }

  SpecModule? _findModule(SpecForgeProject project, String moduleId) {
    if (moduleId.trim().isEmpty) return null;
    for (final module in project.cahierDesCharges.modules) {
      if (module.id == moduleId) return module;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      key: const ValueKey('ux-navigation-editor-view'),
      listenable: widget.controller,
      builder: (context, _) {
        final project = widget.controller.project;
        if (project == null) return const SizedBox.shrink();

        final nav = project.uxSpec.navigation;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 22,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Architecture & Navigation',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildShellAndThemeSection(context, project: project, nav: nav),
              const SizedBox(height: 16),
              _buildRoutesSection(context, project: project, nav: nav),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShellAndThemeSection(
    BuildContext context, {
    required SpecForgeProject project,
    required UxNavigationSpec nav,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined, size: 19, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Shell applicatif & Identité visuelle',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final controls = _buildShellAndThemeControls(
                  context,
                  project: project,
                  nav: nav,
                );
                final livePreview = _buildLiveThemePreviewCard(
                  context,
                  visualTheme: nav.visualTheme,
                );

                if (constraints.maxWidth >= 760) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: controls),
                      const SizedBox(width: 16),
                      Expanded(flex: 5, child: livePreview),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    controls,
                    const SizedBox(height: 16),
                    livePreview,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShellAndThemeControls(
    BuildContext context, {
    required SpecForgeProject project,
    required UxNavigationSpec nav,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visual = nav.visualTheme;
    final effectiveHomeRouteId = nav.routes.any((r) => r.id == nav.homeRouteId)
        ? nav.homeRouteId
        : '';
    final fontChoices = _presetFonts.contains(visual.fontFamily)
        ? _presetFonts
        : <String>[visual.fontFamily, ..._presetFonts];
    final sliderRadius = visual.cardRadius.clamp(4.0, 24.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<UxShellPattern>(
                key: ValueKey('shell_${nav.shellPattern.name}'),
                initialValue: nav.shellPattern,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Pattern de Shell',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final pattern in UxShellPattern.values)
                    DropdownMenuItem(
                      value: pattern,
                      child: Text(
                        pattern.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _updateNavigation(project, nav.copyWith(shellPattern: val));
                  }
                },
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                key: ValueKey(
                  'home_${effectiveHomeRouteId}_${nav.routes.length}',
                ),
                initialValue: effectiveHomeRouteId,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Route d’accueil',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text(
                      'Automatique',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final route in nav.routes)
                    DropdownMenuItem(
                      value: route.id,
                      child: Text(
                        '${route.path} — ${route.title}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) => _updateNavigation(
                  project,
                  nav.copyWith(homeRouteId: val ?? ''),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilterChip(
              key: const ValueKey('ux-nav-has-appbar-chip'),
              label: const Text('Barre supérieure (AppBar)'),
              selected: nav.hasAppBar,
              visualDensity: VisualDensity.compact,
              onSelected: (v) =>
                  _updateNavigation(project, nav.copyWith(hasAppBar: v)),
            ),
            FilterChip(
              key: const ValueKey('ux-nav-has-breadcrumbs-chip'),
              label: const Text('Fil d’Ariane'),
              selected: nav.hasBreadcrumbs,
              visualDensity: VisualDensity.compact,
              onSelected: (v) =>
                  _updateNavigation(project, nav.copyWith(hasBreadcrumbs: v)),
            ),
            FilterChip(
              key: const ValueKey('ux-nav-has-global-search-chip'),
              label: const Text('Recherche globale'),
              selected: nav.hasGlobalSearch,
              visualDensity: VisualDensity.compact,
              onSelected: (v) =>
                  _updateNavigation(project, nav.copyWith(hasGlobalSearch: v)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final preset in _presetAccents)
              _AccentSwatchButton(
                key: ValueKey('ux-accent-swatch-${preset.hex}'),
                hex: preset.hex,
                tooltip: '${preset.label} (${preset.hex})',
                color: _parseHexColor(preset.hex),
                selected:
                    visual.accentHex.toUpperCase() == preset.hex.toUpperCase(),
                onTap: () {
                  _accentHexCtrl.text = preset.hex;
                  _updateVisualTheme(
                    project,
                    visual.copyWith(accentHex: preset.hex),
                  );
                },
              ),
            SizedBox(
              width: 132,
              child: TextField(
                key: const ValueKey('ux-accent-hex-input'),
                controller: _accentHexCtrl,
                focusNode: _accentFocusNode,
                decoration: InputDecoration(
                  labelText: 'Accent Hex',
                  hintText: '#3F51B5',
                  isDense: true,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _parseHexColor(visual.accentHex),
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.outlineVariant),
                      ),
                    ),
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (raw) {
                  final stripped = raw.trim().startsWith('#')
                      ? raw.trim().substring(1)
                      : raw.trim();
                  if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(stripped)) {
                    final normalized = '#${stripped.toUpperCase()}';
                    _updateVisualTheme(
                      project,
                      visual.copyWith(accentHex: normalized),
                    );
                  }
                },
                onSubmitted: (raw) {
                  final normalized = UxVisualThemeSeed.normalizeAccentHex(
                    raw,
                    fallback: visual.accentHex,
                  );
                  _accentHexCtrl.text = normalized;
                  _updateVisualTheme(
                    project,
                    visual.copyWith(accentHex: normalized),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              key: const ValueKey('ux-theme-mode-segmented'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(
                  value: 'system',
                  icon: Icon(Icons.brightness_auto_outlined, size: 16),
                  label: Text('Système'),
                ),
                ButtonSegment(
                  value: 'light',
                  icon: Icon(Icons.light_mode_outlined, size: 16),
                  label: Text('Clair'),
                ),
                ButtonSegment(
                  value: 'dark',
                  icon: Icon(Icons.dark_mode_outlined, size: 16),
                  label: Text('Sombre'),
                ),
              ],
              selected: <String>{visual.themeMode},
              onSelectionChanged: (selection) {
                final nextMode = UxVisualThemeSeed.normalizeThemeMode(
                  selection.first,
                );
                _updateVisualTheme(
                  project,
                  visual.copyWith(themeMode: nextMode),
                );
              },
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                key: ValueKey('surface_${visual.surfaceSystem}'),
                initialValue: visual.surfaceSystem,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Système de surface',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'material',
                    child: Text(
                      'Material 3',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'liquidGlass',
                    child: Text(
                      'Liquid Glass',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'neumorphism',
                    child: Text(
                      'Neumorphism',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _updateVisualTheme(
                      project,
                      visual.copyWith(surfaceSystem: val),
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String>(
                key: ValueKey('font_${visual.fontFamily}'),
                initialValue: visual.fontFamily,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Police typographique',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final font in fontChoices)
                    DropdownMenuItem(
                      value: font,
                      child: Text(font, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (val) {
                  if (val != null && val.trim().isNotEmpty) {
                    _updateVisualTheme(
                      project,
                      visual.copyWith(fontFamily: val),
                    );
                  }
                },
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<UxDensityProfile>(
                key: ValueKey('density_${visual.density.name}'),
                initialValue: visual.density,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Densité spatiale',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final profile in UxDensityProfile.values)
                    DropdownMenuItem(
                      value: profile,
                      child: Text(
                        profile.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _updateVisualTheme(project, visual.copyWith(density: val));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Flexible(
              child: Text(
                'Rayon des cartes : ${visual.cardRadius.round()} px',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('ux-card-radius-slider'),
                value: sliderRadius,
                min: 4,
                max: 24,
                divisions: 20,
                label: '${sliderRadius.round()} px',
                onChanged: (val) => _updateVisualTheme(
                  project,
                  visual.copyWith(cardRadius: val.roundToDouble()),
                ),
              ),
            ),
          ],
        ),
        TextField(
          key: const ValueKey('ux-voice-guidelines-input'),
          controller: _voiceGuidelinesCtrl,
          focusNode: _voiceFocusNode,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Ton éditorial, micro-copie & accessibilité UX',
            hintText:
                'Ex. Verbes d’action directs à l’infinitif, messages d’erreur explicites orientés solution',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (val) => _updateVisualTheme(
            project,
            visual.copyWith(uxVoiceGuidelines: val.trim()),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveThemePreviewCard(
    BuildContext context, {
    required UxVisualThemeSeed visualTheme,
  }) {
    final hostTheme = Theme.of(context);
    final defaultBrightness = switch (visualTheme.themeMode) {
      'dark' => Brightness.dark,
      'light' => Brightness.light,
      _ => hostTheme.brightness,
    };
    final previewBrightness = _previewBrightnessOverride ?? defaultBrightness;
    final parsedAccentColor = _parseHexColor(visualTheme.accentHex);
    final previewScheme = ColorScheme.fromSeed(
      seedColor: parsedAccentColor,
      brightness: previewBrightness,
    );

    final (double cardPadding, double lineSpacing) = switch (visualTheme.density) {
      UxDensityProfile.compact => (12.0, 5.0),
      UxDensityProfile.comfortable => (16.0, 8.0),
      UxDensityProfile.spacious => (20.0, 12.0),
    };

    final swatches = <({String name, Color bg, Color fg})>[
      (
        name: 'primary',
        bg: previewScheme.primary,
        fg: previewScheme.onPrimary,
      ),
      (
        name: 'primaryContainer',
        bg: previewScheme.primaryContainer,
        fg: previewScheme.onPrimaryContainer,
      ),
      (
        name: 'secondaryContainer',
        bg: previewScheme.secondaryContainer,
        fg: previewScheme.onSecondaryContainer,
      ),
      (
        name: 'surface',
        bg: previewScheme.surface,
        fg: previewScheme.onSurface,
      ),
      (
        name: 'surfaceContainerLow',
        bg: previewScheme.surfaceContainerLow,
        fg: previewScheme.onSurface,
      ),
      (
        name: 'errorContainer',
        bg: previewScheme.errorContainer,
        fg: previewScheme.onErrorContainer,
      ),
    ];

    return Container(
      key: const ValueKey('ux-live-theme-preview-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: previewScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: previewScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Aperçu Live M3 & Typographie',
                style: hostTheme.textTheme.labelLarge?.copyWith(
                  color: previewScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SegmentedButton<Brightness>(
                key: const ValueKey('ux-preview-brightness-toggle'),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: Brightness.light,
                    icon: Icon(Icons.light_mode_outlined, size: 14),
                    label: Text('Clair'),
                  ),
                  ButtonSegment(
                    value: Brightness.dark,
                    icon: Icon(Icons.dark_mode_outlined, size: 14),
                    label: Text('Sombre'),
                  ),
                ],
                selected: <Brightness>{previewBrightness},
                onSelectionChanged: (sel) => setState(
                  () => _previewBrightnessOverride = sel.first,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final swatch in swatches)
                Container(
                  width: 118,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: swatch.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: previewScheme.outlineVariant.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        swatch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: visualTheme.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: swatch.fg,
                        ),
                      ),
                      Text(
                        _colorToHex(swatch.bg),
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          color: swatch.fg.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              color: visualTheme.surfaceSystem == 'liquidGlass'
                  ? previewScheme.surface.withValues(alpha: 0.82)
                  : previewScheme.surface,
              borderRadius: BorderRadius.circular(visualTheme.cardRadius),
              border: Border.all(
                color: visualTheme.surfaceSystem == 'liquidGlass'
                    ? previewScheme.primary.withValues(alpha: 0.35)
                    : previewScheme.outlineVariant,
              ),
              boxShadow: visualTheme.surfaceSystem == 'neumorphism'
                  ? [
                      BoxShadow(
                        color: previewScheme.shadow.withValues(alpha: 0.14),
                        blurRadius: 10,
                        offset: const Offset(3, 3),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Titre d’écran (24px)',
                  style: TextStyle(
                    fontFamily: visualTheme.fontFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: previewScheme.onSurface,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: lineSpacing),
                Text(
                  'Titre de Carte (17px)',
                  style: TextStyle(
                    fontFamily: visualTheme.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: previewScheme.onSurface,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: lineSpacing),
                Text(
                  'Corps métier (13.5px) — Aperçu réaliste de la hiérarchie Desktop en police ${visualTheme.fontFamily}.',
                  style: TextStyle(
                    fontFamily: visualTheme.fontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: previewScheme.onSurface,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: lineSpacing),
                Text(
                  'Métadonnée (11.5px) · Rayon ${visualTheme.cardRadius.round()}px · ${visualTheme.density.label}',
                  style: TextStyle(
                    fontFamily: visualTheme.fontFamily,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: previewScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: lineSpacing + 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: previewScheme.primary,
                        borderRadius: BorderRadius.circular(
                          (visualTheme.cardRadius * 0.6).clamp(6.0, 14.0),
                        ),
                      ),
                      child: Text(
                        'Action primaire',
                        style: TextStyle(
                          fontFamily: visualTheme.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: previewScheme.onPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: previewScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(
                          (visualTheme.cardRadius * 0.6).clamp(6.0, 14.0),
                        ),
                      ),
                      child: Text(
                        visualTheme.surfaceSystem,
                        style: TextStyle(
                          fontFamily: visualTheme.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: previewScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutesSection(
    BuildContext context, {
    required SpecForgeProject project,
    required UxNavigationSpec nav,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final orderedTree = _buildOrderedRouteTree(nav.routes);
    final focusedRouteId = widget.controller.focusedRouteId;
    final selectedRouteId = nav.routes.any((r) => r.id == focusedRouteId)
        ? focusedRouteId
        : orderedTree.firstOrNull?.route.id;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.alt_route_rounded, size: 20, color: colors.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Arborescence des routes & Matrice d’accès (${nav.routes.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('ux-seed-routes-from-modules-btn'),
                      onPressed: () => _seedRoutesFromModules(project),
                      icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
                      label: const Text('Générer depuis les modules'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('ux-add-route-btn'),
                      onPressed: () => _openRouteDialog(context, project),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('+ Nouvelle route'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (orderedTree.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.signpost_outlined,
                      size: 30,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Aucune route applicative définie',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Initialisez l’arborescence en un clic avec « Générer depuis les modules » ou ajoutez vos écrans et modales manuellement.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  for (final entry in orderedTree)
                    _RouteTreeTile(
                      key: ValueKey('ux-route-tile-${entry.route.id}'),
                      route: entry.route,
                      depth: entry.depth,
                      isSelected: selectedRouteId == entry.route.id,
                      isHome: nav.homeRouteId == entry.route.id,
                      moduleName: _findModule(
                        project,
                        entry.route.moduleId,
                      )?.name,
                      personas: project.vision.personas,
                      onSelect: () => widget.controller.focusUxItem(
                        routeId: entry.route.id,
                      ),
                      onSetHome: entry.route.pageType.isModal
                          ? null
                          : () => _updateNavigation(
                              project,
                              nav.copyWith(homeRouteId: entry.route.id),
                            ),
                      onEdit: () => _openRouteDialog(
                        context,
                        project,
                        existing: entry.route,
                      ),
                      onDelete: () => _deleteRoute(project, entry.route),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AccentSwatchButton extends StatelessWidget {
  const _AccentSwatchButton({
    super.key,
    required this.hex,
    required this.tooltip,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final String tooltip;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? colors.onSurface : colors.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: selected
              ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _RouteTreeTile extends StatelessWidget {
  const _RouteTreeTile({
    super.key,
    required this.route,
    required this.depth,
    required this.isSelected,
    required this.isHome,
    required this.moduleName,
    required this.personas,
    required this.onSelect,
    required this.onSetHome,
    required this.onEdit,
    required this.onDelete,
  });

  final UxRouteNode route;
  final int depth;
  final bool isSelected;
  final bool isHome;
  final String? moduleName;
  final List<SpecPersona> personas;
  final VoidCallback onSelect;
  final VoidCallback? onSetHome;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  IconData _resolveIcon(String iconName, EditorPageType fallbackType) =>
      switch (iconName.trim()) {
        'home_outlined' || 'home' => Icons.home_outlined,
        'dashboard_outlined' || 'dashboard' => Icons.dashboard_outlined,
        'widgets_outlined' || 'widgets' => Icons.widgets_outlined,
        'list_alt_outlined' || 'list' => Icons.list_alt_outlined,
        'people_outline' || 'people' => Icons.people_outline,
        'shopping_bag_outlined' || 'cart' => Icons.shopping_bag_outlined,
        'receipt_long_outlined' || 'receipt' => Icons.receipt_long_outlined,
        'analytics_outlined' || 'analytics' => Icons.analytics_outlined,
        'settings_outlined' || 'settings' => Icons.settings_outlined,
        'folder_outlined' || 'folder' => Icons.folder_outlined,
        'description_outlined' => Icons.description_outlined,
        'web_asset_outlined' => Icons.web_asset_outlined,
        _ => fallbackType.icon,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final indent = (depth * 24.0).clamp(0.0, 96.0);
    final allowedCount = route.allowedPersonaIds.length;
    final allowedNames = [
      for (final pid in route.allowedPersonaIds)
        personas.where((p) => p.id == pid).firstOrNull?.name ?? pid,
    ];

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 8),
      child: Material(
        color: isSelected
            ? colors.primaryContainer.withValues(alpha: 0.42)
            : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? colors.primary : colors.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (depth > 0) ...[
                  Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  _resolveIcon(route.iconName, route.pageType),
                  size: 19,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          route.path,
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ),
                      Text(
                        route.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isHome)
                        Tooltip(
                          message: 'Route d’accueil',
                          child: Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      _RouteChip(
                        icon: route.pageType.icon,
                        label: route.pageType.label,
                        bg: colors.surface,
                        fg: colors.onSurface,
                      ),
                      _RouteChip(
                        icon: route.showInPrimaryNav
                            ? Icons.menu_open_rounded
                            : Icons.visibility_off_outlined,
                        label: route.showInPrimaryNav
                            ? 'Nav primaire'
                            : 'Hors nav',
                        bg: route.showInPrimaryNav
                            ? colors.primaryContainer
                            : colors.surfaceContainerHighest,
                        fg: route.showInPrimaryNav
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                      if (moduleName != null || route.moduleId.isNotEmpty)
                        _RouteChip(
                          icon: Icons.widgets_outlined,
                          label: moduleName ?? route.moduleId,
                          bg: colors.tertiaryContainer,
                          fg: colors.onTertiaryContainer,
                        ),
                      Tooltip(
                        message: allowedCount == 0
                            ? 'Accessible à tous les personas'
                            : 'Personas autorisés : ${allowedNames.join(', ')}',
                        child: _RouteChip(
                          icon: allowedCount == 0
                              ? Icons.public_rounded
                              : Icons.lock_person_outlined,
                          label: allowedCount == 0
                              ? 'Tous personas'
                              : '$allowedCount persona${allowedCount > 1 ? 's' : ''}',
                          bg: colors.surface,
                          fg: colors.onSurfaceVariant,
                        ),
                      ),
                      if (route.permissionRuleIds.isNotEmpty)
                        _RouteChip(
                          icon: Icons.gavel_rounded,
                          label: '${route.permissionRuleIds.length} RG',
                          bg: colors.surfaceContainerHighest,
                          fg: colors.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
                if (!isHome && onSetHome != null)
                  IconButton(
                    tooltip: 'Définir comme route d’accueil',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.star_border_rounded, size: 18),
                    onPressed: onSetHome,
                  ),
                IconButton(
                  key: ValueKey('ux-edit-route-btn-${route.id}'),
                  tooltip: 'Modifier la route',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
                IconButton(
                  key: ValueKey('ux-delete-route-btn-${route.id}'),
                  tooltip: 'Supprimer la route',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: colors.error,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteChip extends StatelessWidget {
  const _RouteChip({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteFormDialog extends StatefulWidget {
  const _RouteFormDialog({
    required this.project,
    required this.existing,
    required this.generatedId,
  });

  final SpecForgeProject project;
  final UxRouteNode? existing;
  final String generatedId;

  @override
  State<_RouteFormDialog> createState() => _RouteFormDialogState();
}

class _RouteFormDialogState extends State<_RouteFormDialog> {
  static const List<String> _iconSuggestions = <String>[
    'home_outlined',
    'dashboard_outlined',
    'widgets_outlined',
    'list_alt_outlined',
    'people_outline',
    'shopping_bag_outlined',
    'receipt_long_outlined',
    'analytics_outlined',
    'settings_outlined',
    'web_asset_outlined',
  ];

  late final TextEditingController _pathCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _iconCtrl;
  late EditorPageType _pageType;
  late String _moduleId;
  late String _parentRouteId;
  late bool _showInPrimaryNav;
  late Set<String> _allowedPersonaIds;
  late Set<String> _permissionRuleIds;
  bool _pathManuallyEdited = false;
  String? _titleError;
  String? _pathError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _pathCtrl = TextEditingController(text: existing?.path ?? '/');
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _iconCtrl = TextEditingController(
      text: existing?.iconName ?? 'web_asset_outlined',
    );
    _pageType = existing?.pageType ?? EditorPageType.standard;
    _moduleId = widget.project.cahierDesCharges.modules.any(
          (m) => m.id == existing?.moduleId,
        )
        ? (existing?.moduleId ?? '')
        : '';
    final candidateParents = _availableParentRoutes();
    _parentRouteId = candidateParents.any((r) => r.id == existing?.parentRouteId)
        ? (existing?.parentRouteId ?? '')
        : '';
    _showInPrimaryNav = existing?.showInPrimaryNav ?? !_pageType.isModal;
    _allowedPersonaIds = Set<String>.from(
      existing?.allowedPersonaIds ?? const <String>[],
    );
    _permissionRuleIds = Set<String>.from(
      existing?.permissionRuleIds ?? const <String>[],
    );
    _pathManuallyEdited = existing != null;
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _titleCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  List<UxRouteNode> _availableParentRoutes() {
    final allRoutes = widget.project.uxSpec.navigation.routes;
    final selfId = widget.existing?.id;
    if (selfId == null) return allRoutes;

    final descendants = <String>{selfId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final route in allRoutes) {
        if (!descendants.contains(route.id) &&
            descendants.contains(route.parentRouteId)) {
          descendants.add(route.id);
          changed = true;
        }
      }
    }
    return allRoutes.where((r) => !descendants.contains(r.id)).toList();
  }

  void _submit() {
    final trimmedTitle = _titleCtrl.text.trim();
    final normalizedPath = UxRouteNode.normalizePath(_pathCtrl.text);

    String? nextTitleError;
    String? nextPathError;
    if (trimmedTitle.isEmpty) {
      nextTitleError = 'L’intitulé de la route est requis.';
    }
    if (normalizedPath.isEmpty || !normalizedPath.startsWith('/')) {
      nextPathError = 'Le chemin doit commencer par « / ».';
    } else if (!_pageType.isModal) {
      final duplicate = widget.project.uxSpec.navigation.routes.any(
        (r) =>
            r.id != widget.generatedId &&
            !r.pageType.isModal &&
            r.path.toLowerCase() == normalizedPath.toLowerCase(),
      );
      if (duplicate) {
        nextPathError =
            'Une autre route non modale utilise déjà « $normalizedPath ».';
      }
    }

    if (nextTitleError != null || nextPathError != null) {
      setState(() {
        _titleError = nextTitleError;
        _pathError = nextPathError;
      });
      return;
    }

    final trimmedIcon = _iconCtrl.text.trim();
    final node = UxRouteNode(
      id: widget.generatedId,
      path: normalizedPath,
      title: trimmedTitle,
      iconName: trimmedIcon.isEmpty ? 'web_asset_outlined' : trimmedIcon,
      pageType: _pageType,
      moduleId: _moduleId,
      parentRouteId: _parentRouteId,
      showInPrimaryNav: _showInPrimaryNav,
      allowedPersonaIds: _allowedPersonaIds.toList(),
      permissionRuleIds: _permissionRuleIds.toList(),
    );
    Navigator.pop(context, node);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modules = widget.project.cahierDesCharges.modules;
    final personas = widget.project.vision.personas;
    final parentChoices = _availableParentRoutes();
    final sortedRules = List<BusinessRuleSpec>.from(
      widget.project.businessRules,
    )..sort((a, b) {
      final aPerm = a.category == BusinessRuleCategory.permission ? 0 : 1;
      final bPerm = b.category == BusinessRuleCategory.permission ? 0 : 1;
      if (aPerm != bPerm) return aPerm.compareTo(bPerm);
      return a.code.compareTo(b.code);
    });

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nouvelle route applicative'
            : 'Modifier ${widget.existing!.path}',
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _titleCtrl,
                      autofocus: widget.existing == null,
                      decoration: InputDecoration(
                        labelText: 'Intitulé *',
                        errorText: _titleError,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        if (_titleError != null) {
                          setState(() => _titleError = null);
                        }
                        if (!_pathManuallyEdited && val.trim().isNotEmpty) {
                          _pathCtrl.text =
                              '/${_UxNavigationEditorViewState._slugify(val)}';
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _pathCtrl,
                      decoration: InputDecoration(
                        labelText: 'Chemin *',
                        hintText: '/commandes',
                        errorText: _pathError,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        _pathManuallyEdited = true;
                        if (_pathError != null) {
                          setState(() => _pathError = null);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<EditorPageType>(
                      key: ValueKey('route_page_type_${_pageType.name}'),
                      initialValue: _pageType,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Type de page',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final t in EditorPageType.values)
                          DropdownMenuItem(
                            value: t,
                            child: Row(
                              children: [
                                Icon(t.icon, size: 17),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    t.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() {
                          final wasModal = _pageType.isModal;
                          _pageType = val;
                          if (val.isModal && !wasModal) {
                            _showInPrimaryNav = false;
                          } else if (!val.isModal && wasModal) {
                            _showInPrimaryNav = true;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _iconCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nom d’icône Material',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final iconName in _iconSuggestions)
                    ActionChip(
                      label: Text(iconName),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _iconCtrl.text = iconName),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('route_mod_$_moduleId'),
                      initialValue: _moduleId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Module fonctionnel',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text(
                            'Aucun module',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        for (final mod in modules)
                          DropdownMenuItem(
                            value: mod.id,
                            child: Text(
                              mod.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) =>
                          setState(() => _moduleId = val ?? ''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('route_parent_$_parentRouteId'),
                      initialValue: _parentRouteId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Route parente',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text(
                            'Aucune (racine)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        for (final parent in parentChoices)
                          DropdownMenuItem(
                            value: parent.id,
                            child: Text(
                              '${parent.path} — ${parent.title}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) =>
                          setState(() => _parentRouteId = val ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Afficher dans la navigation primaire'),
                subtitle: const Text(
                  'Inclut cette entrée dans le rail ou la barre principale du shell.',
                ),
                value: _showInPrimaryNav,
                onChanged: (val) => setState(() => _showInPrimaryNav = val),
              ),
              if (personas.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Personas autorisés (vide = accès ouvert à tous)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final persona in personas)
                      FilterChip(
                        label: Text(persona.name),
                        selected: _allowedPersonaIds.contains(persona.id),
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _allowedPersonaIds.add(persona.id);
                          } else {
                            _allowedPersonaIds.remove(persona.id);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              if (sortedRules.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Règles d’habilitation & de permission liées',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final rule in sortedRules)
                      FilterChip(
                        avatar: rule.category == BusinessRuleCategory.permission
                            ? const Icon(Icons.verified_user_outlined, size: 15)
                            : null,
                        label: Text('${rule.code} · ${rule.title}'),
                        selected:
                            _permissionRuleIds.contains(rule.id) ||
                            _permissionRuleIds.contains(rule.code),
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) => setState(() {
                          _permissionRuleIds.remove(rule.code);
                          if (selected) {
                            _permissionRuleIds.add(rule.id);
                          } else {
                            _permissionRuleIds.remove(rule.id);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
