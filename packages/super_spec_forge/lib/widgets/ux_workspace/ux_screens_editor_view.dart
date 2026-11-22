/// Atelier structuré de l'étape UX 3 : schémas directeurs d'écrans, blueprint interactif des zones, actions RG et états UX ([UxScreensEditorView]).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/business_object_spec.dart';
import '../../models/business_rule_spec.dart';
import '../../models/json_schema_constraints.dart';
import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_forge_stage.dart';
import '../../models/spec_vision.dart';
import '../../models/ux/ux_forge_spec.dart';
import '../../models/ux/ux_navigation_spec.dart';
import '../../models/ux/ux_screen_spec.dart';
import '../../services/spec_forge_controller.dart';

/// Atelier interactif de conception des écrans applicatifs (`SCR-xxx`), de leur
/// découpage spatial cardinal (`north`, `west`, `center`, `east`, `south`), de leurs
/// liaisons aux objets métiers/attributs et de leurs actions rattachées aux règles `RG-xxx`.
class UxScreensEditorView extends StatefulWidget {
  /// Construit l'atelier d'édition des écrans UX connecté au [controller].
  const UxScreensEditorView({
    required this.controller,
    this.onJumpToSpecStage,
    super.key,
  });

  /// Contrôleur principal de la forge de spécifications et du volet UX.
  final SpecForgeController controller;

  /// Callback optionnel de saut contextuel vers une étape du wizard métier ([SpecForgeStage]).
  final void Function(SpecForgeStage stage, {String? objectId})?
  onJumpToSpecStage;

  @override
  State<UxScreensEditorView> createState() => _UxScreensEditorViewState();
}

class _UxScreensEditorViewState extends State<UxScreensEditorView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  UxScreenSpec? _resolveSelectedScreen(UxForgeSpec ux) {
    if (ux.screens.isEmpty) return null;
    final focusedId = widget.controller.focusedScreenId;
    if (focusedId != null && focusedId.trim().isNotEmpty) {
      for (final s in ux.screens) {
        if (s.id == focusedId) return s;
      }
      final found = ux.findScreen(focusedId);
      if (found != null) return found;
    }
    return ux.screens.first;
  }

  UxLayoutZoneName _resolveSelectedZone(UxScreenSpec? screen) {
    final focused = widget.controller.focusedScreenZone;
    if (focused != null) return focused;
    if (screen == null) return UxLayoutZoneName.center;
    for (final z in screen.zones) {
      if (z.enabled) return z.zone;
    }
    if (screen.zones.isNotEmpty) return screen.zones.first.zone;
    return UxLayoutZoneName.center;
  }

  UxLayoutZoneName _defaultInitialZoneFor(UxScreenSpec screen) {
    for (final z in screen.zones) {
      if (z.enabled) return z.zone;
    }
    if (screen.zones.isNotEmpty) return screen.zones.first.zone;
    return UxLayoutZoneName.center;
  }

  Future<void> _replaceScreen(
    SpecForgeProject project,
    UxScreenSpec updatedScreen,
  ) async {
    final nextScreens = <UxScreenSpec>[
      for (final s in project.uxSpec.screens)
        if (s.id == updatedScreen.id) updatedScreen else s,
    ];
    await widget.controller.updateUxSpec(
      project.uxSpec.copyWith(screens: nextScreens),
    );
  }

  Future<void> _deleteScreen(
    BuildContext context,
    SpecForgeProject project,
    UxScreenSpec target,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer l’écran ?'),
        content: Text(
          'Voulez-vous supprimer le schéma d’écran « ${target.code} — ${target.name} » ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final nextScreens = project.uxSpec.screens
        .where((s) => s.id != target.id)
        .toList();
    await widget.controller.updateUxSpec(
      project.uxSpec.copyWith(screens: nextScreens),
    );
    if (!mounted) return;
    final fallback = nextScreens.firstOrNull;
    widget.controller.focusUxItem(
      journeyId: widget.controller.focusedJourneyId,
      routeId: fallback != null && fallback.routeId.isNotEmpty
          ? fallback.routeId
          : widget.controller.focusedRouteId,
      screenId: fallback?.id,
      zone: fallback != null ? _defaultInitialZoneFor(fallback) : null,
    );
  }

  Future<void> _seedScreensFromRoutes(
    BuildContext context,
    SpecForgeProject project,
  ) async {
    final ux = project.uxSpec;
    final routes = ux.navigation.routes;
    if (routes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aucune route n’est définie à l’étape Architecture & Navigation.',
          ),
        ),
      );
      return;
    }

    final orphanRoutes = routes
        .where((r) => !ux.screens.any((s) => _screenMatchesRoute(s, r)))
        .toList();
    if (orphanRoutes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toutes les routes disposent déjà d’un écran associé.'),
        ),
      );
      return;
    }

    final nextScreens = List<UxScreenSpec>.from(ux.screens);
    final usedIds = <String>{for (final s in nextScreens) s.id};
    UxScreenSpec? firstCreated;

    for (final route in orphanRoutes) {
      final code = _nextScreenCode(nextScreens);
      final pattern = _inferPatternForRoute(route, ux.navigation);
      final slug = _slugifyIdentifier(route.title, fallback: 'screen');
      final screenId = _uniqueId('scr_$slug', usedIds);
      usedIds.add(screenId);

      final created = UxScreenSpec(
        id: screenId,
        code: code,
        name: route.title,
        routeId: route.id,
        pattern: pattern,
        purpose: 'Écran associé à la route ${route.path} (${route.title}).',
        personaIds: route.allowedPersonaIds,
        zones: UxScreenSpec.defaultZonesForPattern(pattern),
        states: UxScreenStatesSpec(
          emptyStateTitle: 'Aucune donnée à afficher sur ${route.title}',
        ),
      );
      firstCreated ??= created;
      nextScreens.add(created);
    }

    await widget.controller.updateUxSpec(ux.copyWith(screens: nextScreens));
    if (!mounted || firstCreated == null) return;

    widget.controller.focusUxItem(
      journeyId: widget.controller.focusedJourneyId,
      routeId: firstCreated.routeId,
      screenId: firstCreated.id,
      zone: _defaultInitialZoneFor(firstCreated),
    );
  }

  Future<void> _openCreateScreenDialog(
    BuildContext context,
    SpecForgeProject project,
  ) async {
    final created = await showDialog<UxScreenSpec>(
      context: context,
      builder: (ctx) => _ScreenMetaDialog(project: project),
    );
    if (created == null || !mounted) return;

    final currentProject = widget.controller.project ?? project;
    final nextScreens = <UxScreenSpec>[
      ...currentProject.uxSpec.screens,
      created,
    ];
    await widget.controller.updateUxSpec(
      currentProject.uxSpec.copyWith(screens: nextScreens),
    );
    if (!mounted) return;
    widget.controller.focusUxItem(
      journeyId: widget.controller.focusedJourneyId,
      routeId: created.routeId.isNotEmpty
          ? created.routeId
          : widget.controller.focusedRouteId,
      screenId: created.id,
      zone: _defaultInitialZoneFor(created),
    );
  }

  Future<void> _openEditScreenMetaDialog(
    BuildContext context,
    SpecForgeProject project,
    UxScreenSpec screen,
  ) async {
    final updated = await showDialog<UxScreenSpec>(
      context: context,
      builder: (ctx) => _ScreenMetaDialog(project: project, existing: screen),
    );
    if (updated == null || !mounted) return;

    final currentProject = widget.controller.project ?? project;
    await _replaceScreen(currentProject, updated);
    if (!mounted) return;
    widget.controller.focusUxItem(
      journeyId: widget.controller.focusedJourneyId,
      routeId: updated.routeId.isNotEmpty
          ? updated.routeId
          : widget.controller.focusedRouteId,
      screenId: updated.id,
      zone:
          widget.controller.focusedScreenZone ??
          _defaultInitialZoneFor(updated),
    );
  }

  Future<void> _openQuickAddObjectDialog(
    BuildContext context,
    SpecForgeProject project,
  ) async {
    final created = await showDialog<BusinessObjectSpec>(
      context: context,
      builder: (ctx) => _QuickAddObjectDialog(project: project),
    );
    if (created == null || !mounted) return;
    await widget.controller.upsertBusinessObjectFromUx(created);
  }

  Future<void> _openQuickAddAttributeDialog(
    BuildContext context,
    SpecForgeProject project,
    UxScreenSpec? selectedScreen,
  ) async {
    if (project.businessObjects.isEmpty) {
      final createObjectFirst = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Aucun objet métier défini'),
          content: const Text(
            'Créez d’abord un objet métier avant de lui ajouter un attribut.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Fermer'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('+ Objet métier'),
            ),
          ],
        ),
      );
      if (createObjectFirst == true && context.mounted) {
        await _openQuickAddObjectDialog(context, project);
      }
      return;
    }

    final preselectedObj =
        selectedScreen != null &&
            selectedScreen.primaryObjectId.trim().isNotEmpty
        ? project.findBusinessObject(selectedScreen.primaryObjectId)
        : null;

    final result =
        await showDialog<({String objectId, BusinessAttribute attribute})>(
          context: context,
          builder: (ctx) => _QuickAddAttributeDialog(
            project: project,
            initialObjectId: preselectedObj?.id,
          ),
        );
    if (result == null || !mounted) return;

    await widget.controller.upsertBusinessAttributeFromUx(
      objectId: result.objectId,
      attribute: result.attribute,
    );
  }

  Future<void> _openQuickAddRuleDialog(
    BuildContext context,
    SpecForgeProject project,
    UxScreenSpec? selectedScreen,
  ) async {
    final preselectedObj =
        selectedScreen != null &&
            selectedScreen.primaryObjectId.trim().isNotEmpty
        ? project.findBusinessObject(selectedScreen.primaryObjectId)
        : null;

    final created = await showDialog<BusinessRuleSpec>(
      context: context,
      builder: (ctx) => _QuickAddRuleDialog(
        project: project,
        initialTargetObjectId: preselectedObj?.id,
      ),
    );
    if (created == null || !mounted) return;
    await widget.controller.upsertBusinessRuleFromUx(created);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final project = widget.controller.project;
        if (project == null) {
          return const SizedBox.shrink(key: ValueKey('ux-screens-editor-view'));
        }

        final ux = project.uxSpec;
        final selectedScreen = _resolveSelectedScreen(ux);
        final selectedZone = _resolveSelectedZone(selectedScreen);
        final theme = Theme.of(context);
        final colors = theme.colorScheme;

        return Container(
          key: const ValueKey('ux-screens-editor-view'),
          color: colors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopToolbar(context, project, selectedScreen, theme, colors),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final masterPane = _buildMasterList(
                      context,
                      project,
                      selectedScreen,
                      theme,
                      colors,
                    );
                    final detailPane = selectedScreen == null
                        ? _buildEmptyWorkspace(context, project, theme, colors)
                        : _buildDetailWorkspace(
                            context,
                            project,
                            selectedScreen,
                            selectedZone,
                            theme,
                            colors,
                          );
                    if (constraints.maxWidth >= 560) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 260, child: masterPane),
                          const VerticalDivider(width: 1),
                          Expanded(child: detailPane),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: math.min(160, constraints.maxHeight * 0.3),
                          child: masterPane,
                        ),
                        const Divider(height: 1),
                        Expanded(child: detailPane),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopToolbar(
    BuildContext context,
    SpecForgeProject project,
    UxScreenSpec? selectedScreen,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final orphanCount = project.uxSpec.navigation.routes
        .where(
          (r) => !project.uxSpec.screens.any((s) => _screenMatchesRoute(s, r)),
        )
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
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
                  Icon(
                    Icons.dashboard_customize_outlined,
                    size: 20,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Écrans, Zones & Interactions',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CompactBadge(
                    label: '${project.uxSpec.screens.length}',
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tooltip(
                    message: orphanCount > 0
                        ? 'Générer $orphanCount écran(s) depuis les routes non couvertes'
                        : 'Générer un écran par défaut pour chaque route sans écran',
                    child: OutlinedButton.icon(
                      key: const ValueKey('ux-seed-screens-from-routes-btn'),
                      onPressed: () => _seedScreensFromRoutes(context, project),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                      label: const Text('Créer depuis les routes'),
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('ux-add-screen-btn'),
                    onPressed: () => _openCreateScreenDialog(context, project),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('+ Nouvel écran'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Pont Métier :',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('ux-quick-add-object-btn'),
                onPressed: () => _openQuickAddObjectDialog(context, project),
                icon: const Icon(Icons.hub_outlined, size: 15),
                label: const Text('+ Objet métier'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('ux-quick-add-attribute-btn'),
                onPressed: () => _openQuickAddAttributeDialog(
                  context,
                  project,
                  selectedScreen,
                ),
                icon: const Icon(Icons.playlist_add_rounded, size: 16),
                label: const Text('+ Attribut métier'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('ux-quick-add-rule-btn'),
                onPressed: () =>
                    _openQuickAddRuleDialog(context, project, selectedScreen),
                icon: const Icon(Icons.gavel_rounded, size: 15),
                label: const Text('+ Règle RG'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (widget.onJumpToSpecStage != null) ...[
                TextButton.icon(
                  key: const ValueKey('ux-jump-to-business-objects-btn'),
                  onPressed: () {
                    final rawObjId = selectedScreen?.primaryObjectId.trim();
                    final resolvedObjId = (rawObjId == null || rawObjId.isEmpty)
                        ? null
                        : (project.findBusinessObject(rawObjId)?.id ??
                              rawObjId);
                    widget.onJumpToSpecStage!(
                      SpecForgeStage.businessObjects,
                      objectId: resolvedObjId,
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('Objets métiers ↗'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('ux-jump-to-business-rules-btn'),
                  onPressed: () =>
                      widget.onJumpToSpecStage!(SpecForgeStage.businessRules),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('Règles RG ↗'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMasterList(
    BuildContext context,
    SpecForgeProject project,
    UxScreenSpec? selectedScreen,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final screens = project.uxSpec.screens;
    if (screens.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Aucun écran défini.\nCliquez sur « Créer depuis les routes » ou « + Nouvel écran ».',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: screens.length,
      itemBuilder: (context, index) {
        final screen = screens[index];
        final isSelected = selectedScreen?.id == screen.id;
        final route = screen.routeId.trim().isNotEmpty
            ? project.uxSpec.navigation.findRoute(screen.routeId)
            : null;
        final routeBadge =
            route?.path ??
            (screen.routeId.trim().isNotEmpty ? screen.routeId : 'Sans route');
        final primaryObj = screen.primaryObjectId.trim().isNotEmpty
            ? project.findBusinessObject(screen.primaryObjectId)
            : null;
        final primaryObjLabel =
            primaryObj?.name ??
            (screen.primaryObjectId.trim().isNotEmpty
                ? screen.primaryObjectId
                : null);

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          color: isSelected
              ? colors.primaryContainer.withValues(alpha: 0.45)
              : colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isSelected ? colors.primary : colors.outlineVariant,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('ux-screen-master-card-${screen.id}'),
            onTap: () {
              final nextZone =
                  widget.controller.focusedScreenId == screen.id &&
                      widget.controller.focusedScreenZone != null
                  ? widget.controller.focusedScreenZone
                  : _defaultInitialZoneFor(screen);
              widget.controller.focusUxItem(
                journeyId: widget.controller.focusedJourneyId,
                routeId: screen.routeId.isNotEmpty
                    ? screen.routeId
                    : widget.controller.focusedRouteId,
                screenId: screen.id,
                zone: nextZone,
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _CompactBadge(
                        label: screen.code,
                        backgroundColor: isSelected
                            ? colors.primary
                            : colors.secondaryContainer,
                        foregroundColor: isSelected
                            ? colors.onPrimary
                            : colors.onSecondaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          routeBadge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    screen.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _CompactBadge(
                        label: screen.pattern.label,
                        backgroundColor: colors.surfaceContainerHighest,
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                      if (primaryObjLabel != null)
                        _CompactBadge(
                          icon: Icons.hub_outlined,
                          label: primaryObjLabel,
                          backgroundColor: colors.tertiaryContainer.withValues(
                            alpha: 0.65,
                          ),
                          foregroundColor: colors.onTertiaryContainer,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyWorkspace(
    BuildContext context,
    SpecForgeProject project,
    ThemeData theme,
    ColorScheme colors,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.space_dashboard_outlined,
                size: 48,
                color: colors.primary.withValues(alpha: 0.75),
              ),
              const SizedBox(height: 12),
              Text(
                'Aucun schéma directeur d’écran',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Initialisez automatiquement vos écrans depuis les routes de navigation ou créez un premier écran manuellement.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _seedScreensFromRoutes(context, project),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                    label: const Text('Créer depuis les routes'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openCreateScreenDialog(context, project),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('+ Nouvel écran'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailWorkspace(
    BuildContext context,
    SpecForgeProject project,
    UxScreenSpec screen,
    UxLayoutZoneName selectedZone,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final route = screen.routeId.trim().isNotEmpty
        ? project.uxSpec.navigation.findRoute(screen.routeId)
        : null;
    final primaryObj = screen.primaryObjectId.trim().isNotEmpty
        ? project.findBusinessObject(screen.primaryObjectId)
        : null;

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final maxHeaderHeight = (outerConstraints.maxHeight - 120).clamp(
          56.0,
          260.0,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête de métadonnées de l'écran sélectionné
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeaderHeight),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final metaColumn = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _CompactBadge(
                              label: screen.code,
                              backgroundColor: colors.primaryContainer,
                              foregroundColor: colors.onPrimaryContainer,
                            ),
                            Text(
                              screen.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            _CompactBadge(
                              icon: Icons.grid_view_rounded,
                              label: screen.pattern.label,
                              backgroundColor: colors.secondaryContainer,
                              foregroundColor: colors.onSecondaryContainer,
                            ),
                            if (route != null)
                              _CompactBadge(
                                icon: Icons.route_outlined,
                                label: '${route.path} · ${route.title}',
                                backgroundColor: colors.surfaceContainerHighest,
                                foregroundColor: colors.onSurfaceVariant,
                              )
                            else if (screen.routeId.trim().isNotEmpty)
                              _CompactBadge(
                                icon: Icons.link_off_rounded,
                                label: screen.routeId,
                                backgroundColor: colors.errorContainer,
                                foregroundColor: colors.onErrorContainer,
                              ),
                            if (primaryObj != null)
                              _CompactBadge(
                                icon: Icons.hub_outlined,
                                label:
                                    '${primaryObj.name} (${primaryObj.technicalName})',
                                backgroundColor: colors.tertiaryContainer,
                                foregroundColor: colors.onTertiaryContainer,
                              )
                            else if (screen.primaryObjectId.trim().isNotEmpty)
                              _CompactBadge(
                                icon: Icons.hub_outlined,
                                label: screen.primaryObjectId,
                                backgroundColor: colors.errorContainer,
                                foregroundColor: colors.onErrorContainer,
                              ),
                          ],
                        ),
                        if (screen.purpose.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            screen.purpose,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (screen.personaIds.isNotEmpty ||
                            screen.useCaseIds.isNotEmpty ||
                            screen.requirementIds.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final pid in screen.personaIds)
                                _CompactBadge(
                                  icon: Icons.person_outline_rounded,
                                  label:
                                      _resolvePersonaLabel(project, pid) ?? pid,
                                  backgroundColor:
                                      colors.surfaceContainerHighest,
                                  foregroundColor: colors.onSurfaceVariant,
                                ),
                              for (final ucid in screen.useCaseIds)
                                _CompactBadge(
                                  icon: Icons.play_circle_outline_rounded,
                                  label:
                                      _resolveUseCaseLabel(project, ucid) ??
                                      ucid,
                                  backgroundColor:
                                      colors.surfaceContainerHighest,
                                  foregroundColor: colors.onSurfaceVariant,
                                ),
                              for (final reqId in screen.requirementIds)
                                _CompactBadge(
                                  icon: Icons.check_circle_outline_rounded,
                                  label:
                                      _resolveRequirementCode(project, reqId) ??
                                      reqId,
                                  backgroundColor:
                                      colors.surfaceContainerHighest,
                                  foregroundColor: colors.onSurfaceVariant,
                                ),
                            ],
                          ),
                        ],
                      ],
                    );
                    final actionButtons = Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('ux-edit-screen-meta-btn'),
                          onPressed: () => _openEditScreenMetaDialog(
                            context,
                            project,
                            screen,
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Métadonnées'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Supprimer cet écran',
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _deleteScreen(context, project, screen),
                        ),
                      ],
                    );
                    if (constraints.maxWidth >= 440) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: metaColumn),
                          const SizedBox(width: 8),
                          actionButtons,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        metaColumn,
                        const SizedBox(height: 8),
                        actionButtons,
                      ],
                    );
                  },
                ),
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: 'Zones & Blueprint'),
                Tab(text: 'Actions & RG (${screen.actions.length})'),
                const Tab(text: 'États UX'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: switch (_tabController.index) {
                0 => _ZonesBlueprintTab(
                  project: project,
                  screen: screen,
                  selectedZone: selectedZone,
                  onSelectZone: (zone) => widget.controller.focusUxItem(
                    journeyId: widget.controller.focusedJourneyId,
                    routeId: screen.routeId.isNotEmpty
                        ? screen.routeId
                        : widget.controller.focusedRouteId,
                    screenId: screen.id,
                    zone: zone,
                  ),
                  onUpdateScreen: (updated) => _replaceScreen(project, updated),
                ),
                1 => _ScreenActionsTab(
                  project: project,
                  screen: screen,
                  onUpdateScreen: (updated) => _replaceScreen(project, updated),
                ),
                _ => _ScreenStatesTab(
                  project: project,
                  screen: screen,
                  onUpdateScreen: (updated) => _replaceScreen(project, updated),
                ),
              },
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// TAB 1 — ZONES & BLUEPRINT INTERACTIF
// =============================================================================

class _ZonesBlueprintTab extends StatelessWidget {
  const _ZonesBlueprintTab({
    required this.project,
    required this.screen,
    required this.selectedZone,
    required this.onSelectZone,
    required this.onUpdateScreen,
  });

  final SpecForgeProject project;
  final UxScreenSpec screen;
  final UxLayoutZoneName selectedZone;
  final ValueChanged<UxLayoutZoneName> onSelectZone;
  final Future<void> Function(UxScreenSpec updated) onUpdateScreen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Schéma spatial interactif (~230px)
        Container(
          key: const ValueKey('ux-screen-zone-blueprint'),
          height: 232,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: _BlueprintZoneBox(
                  zone: UxLayoutZoneName.north,
                  zoneSpec: screen.zoneFor(UxLayoutZoneName.north),
                  isSelected: selectedZone == UxLayoutZoneName.north,
                  compactHorizontal: true,
                  onTap: () => onSelectZone(UxLayoutZoneName.north),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _BlueprintZoneBox(
                        zone: UxLayoutZoneName.west,
                        zoneSpec: screen.zoneFor(UxLayoutZoneName.west),
                        isSelected: selectedZone == UxLayoutZoneName.west,
                        compactHorizontal: false,
                        onTap: () => onSelectZone(UxLayoutZoneName.west),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 5,
                      child: _BlueprintZoneBox(
                        zone: UxLayoutZoneName.center,
                        zoneSpec: screen.zoneFor(UxLayoutZoneName.center),
                        isSelected: selectedZone == UxLayoutZoneName.center,
                        compactHorizontal: false,
                        onTap: () => onSelectZone(UxLayoutZoneName.center),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: _BlueprintZoneBox(
                        zone: UxLayoutZoneName.east,
                        zoneSpec: screen.zoneFor(UxLayoutZoneName.east),
                        isSelected: selectedZone == UxLayoutZoneName.east,
                        compactHorizontal: false,
                        onTap: () => onSelectZone(UxLayoutZoneName.east),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 48,
                child: _BlueprintZoneBox(
                  zone: UxLayoutZoneName.south,
                  zoneSpec: screen.zoneFor(UxLayoutZoneName.south),
                  isSelected: selectedZone == UxLayoutZoneName.south,
                  compactHorizontal: true,
                  onTap: () => onSelectZone(UxLayoutZoneName.south),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ZoneInspectorCard(
          project: project,
          screen: screen,
          zone: selectedZone,
          zoneSpec: screen.zoneFor(selectedZone),
          onUpdateScreen: onUpdateScreen,
        ),
      ],
    );
  }
}

class _BlueprintZoneBox extends StatelessWidget {
  const _BlueprintZoneBox({
    required this.zone,
    required this.zoneSpec,
    required this.isSelected,
    required this.compactHorizontal,
    required this.onTap,
  });

  final UxLayoutZoneName zone;
  final UxScreenZoneSpec? zoneSpec;
  final bool isSelected;
  final bool compactHorizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isEnabled = zoneSpec != null && zoneSpec!.enabled;
    final slots = zoneSpec?.slots ?? const <UxZoneWidgetSlot>[];

    final bgColor = isEnabled
        ? colors.primaryContainer.withValues(alpha: isSelected ? 0.55 : 0.25)
        : colors.surfaceContainerHighest.withValues(
            alpha: isSelected ? 0.42 : 0.16,
          );
    final solidBorderColor = isSelected
        ? colors.primary
        : colors.primary.withValues(alpha: 0.48);

    final badges = <String>[
      if (zoneSpec?.sizePx != null) '${_formatNum(zoneSpec!.sizePx!)}px',
      if (zoneSpec != null) (zoneSpec!.axis == 'row' ? 'row' : 'col'),
      if (zoneSpec?.scrollable == true) 'scroll',
    ];

    Widget content;
    if (compactHorizontal) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(
              isEnabled
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 13,
              color: isEnabled ? colors.primary : colors.outline,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                zone.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isEnabled
                      ? colors.onSurface
                      : colors.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
            ),
            if (badges.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  badges.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: slots.isEmpty
                  ? Text(
                      isEnabled ? 'Aucun bloc' : 'Inactive',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: Row(
                        children: [
                          for (var i = 0; i < slots.length; i++) ...[
                            if (i > 0) const SizedBox(width: 4),
                            _MiniSlotPill(slot: slots[i], colors: colors),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isEnabled
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 13,
                  color: isEnabled ? colors.primary : colors.outline,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    zone.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isEnabled
                          ? colors.onSurface
                          : colors.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                ),
                if (badges.isNotEmpty)
                  Flexible(
                    child: Text(
                      badges.join('·'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Expanded(
              child: slots.isEmpty
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        isEnabled ? 'Aucun bloc configuré' : 'Zone inactive',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final slot in slots)
                            _MiniSlotPill(slot: slot, colors: colors),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    final borderRadius = BorderRadius.circular(9);
    final tappable = Material(
      key: ValueKey('ux-blueprint-zone-${zone.name}'),
      color: bgColor,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, borderRadius: borderRadius, child: content),
    );

    if (isEnabled) {
      return DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: solidBorderColor,
            width: isSelected ? 2.0 : 1.2,
          ),
        ),
        child: tappable,
      );
    }

    return CustomPaint(
      foregroundPainter: _DashedRoundedBorderPainter(
        color: isSelected
            ? colors.primary
            : colors.outline.withValues(alpha: 0.65),
        strokeWidth: isSelected ? 1.8 : 1.1,
        radius: 9,
      ),
      child: tappable,
    );
  }
}

class _MiniSlotPill extends StatelessWidget {
  const _MiniSlotPill({required this.slot, required this.colors});

  final UxZoneWidgetSlot slot;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        slot.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(strokeWidth / 2);

    final path = Path()..addRRect(rrect);
    const dashLength = 5.0;
    const gapLength = 3.5;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.radius != radius;
}

class _ZoneInspectorCard extends StatefulWidget {
  const _ZoneInspectorCard({
    required this.project,
    required this.screen,
    required this.zone,
    required this.zoneSpec,
    required this.onUpdateScreen,
  });

  final SpecForgeProject project;
  final UxScreenSpec screen;
  final UxLayoutZoneName zone;
  final UxScreenZoneSpec? zoneSpec;
  final Future<void> Function(UxScreenSpec updated) onUpdateScreen;

  @override
  State<_ZoneInspectorCard> createState() => _ZoneInspectorCardState();
}

class _ZoneInspectorCardState extends State<_ZoneInspectorCard> {
  late final TextEditingController _sizeCtrl;
  late final FocusNode _sizeFocus;

  @override
  void initState() {
    super.initState();
    _sizeCtrl = TextEditingController(text: _initialSizeText(widget.zoneSpec));
    _sizeFocus = FocusNode()
      ..addListener(() {
        if (!_sizeFocus.hasFocus) {
          _commitSizePx();
        }
      });
  }

  @override
  void didUpdateWidget(covariant _ZoneInspectorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screen.id != widget.screen.id ||
        oldWidget.zone != widget.zone ||
        oldWidget.zoneSpec?.sizePx != widget.zoneSpec?.sizePx) {
      final nextText = _initialSizeText(widget.zoneSpec);
      if (_sizeCtrl.text != nextText) {
        _sizeCtrl.text = nextText;
      }
    }
  }

  @override
  void dispose() {
    _sizeFocus.dispose();
    _sizeCtrl.dispose();
    super.dispose();
  }

  String _initialSizeText(UxScreenZoneSpec? spec) =>
      spec?.sizePx != null ? _formatNum(spec!.sizePx!) : '';

  UxScreenZoneSpec _effectiveZoneSpec() =>
      widget.zoneSpec ??
      UxScreenZoneSpec(
        zone: widget.zone,
        enabled: false,
        sizePx: _defaultSizeForZone(widget.zone),
        axis:
            (widget.zone == UxLayoutZoneName.north ||
                widget.zone == UxLayoutZoneName.south)
            ? 'row'
            : 'column',
      );

  Future<void> _saveZoneSpec(UxScreenZoneSpec updatedZone) async {
    final ordered = <UxScreenZoneSpec>[];
    var replaced = false;
    for (final existing in widget.screen.zones) {
      if (existing.zone == widget.zone) {
        ordered.add(updatedZone);
        replaced = true;
      } else {
        ordered.add(existing);
      }
    }
    if (!replaced) {
      ordered.add(updatedZone);
    }
    await widget.onUpdateScreen(widget.screen.copyWith(zones: ordered));
  }

  Future<void> _commitSizePx() async {
    if (widget.zone == UxLayoutZoneName.center) return;
    final raw = _sizeCtrl.text.trim();
    final base = _effectiveZoneSpec();
    if (raw.isEmpty) {
      if (widget.zoneSpec != null && widget.zoneSpec!.sizePx != null) {
        await _saveZoneSpec(base.copyWith(clearSizePx: true));
      }
      return;
    }
    final parsed = double.tryParse(raw);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      _sizeCtrl.text = _initialSizeText(widget.zoneSpec);
      return;
    }
    if (widget.zoneSpec?.sizePx == parsed) return;
    await _saveZoneSpec(
      base.copyWith(enabled: widget.zoneSpec?.enabled ?? true, sizePx: parsed),
    );
  }

  Future<void> _openSlotDialog({UxZoneWidgetSlot? existing}) async {
    final currentZone = _effectiveZoneSpec();
    final usedSlotIds = <String>{for (final s in currentZone.slots) s.id};
    final edited = await showDialog<UxZoneWidgetSlot>(
      context: context,
      builder: (ctx) => _ZoneSlotDialog(
        project: widget.project,
        screen: widget.screen,
        usedSlotIds: usedSlotIds,
        existing: existing,
      ),
    );
    if (edited == null || !mounted) return;

    final nextSlots = List<UxZoneWidgetSlot>.from(currentZone.slots);
    if (existing == null) {
      nextSlots.add(edited);
    } else {
      final idx = nextSlots.indexWhere((s) => s.id == existing.id);
      if (idx >= 0) {
        nextSlots[idx] = edited;
      } else {
        nextSlots.add(edited);
      }
    }

    await _saveZoneSpec(currentZone.copyWith(enabled: true, slots: nextSlots));
  }

  Future<void> _deleteSlot(UxZoneWidgetSlot slot) async {
    final currentZone = _effectiveZoneSpec();
    final nextSlots = currentZone.slots.where((s) => s.id != slot.id).toList();
    await _saveZoneSpec(currentZone.copyWith(slots: nextSlots));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final spec = _effectiveZoneSpec();
    final isEnabled = widget.zoneSpec != null && widget.zoneSpec!.enabled;
    final isHorizontalEdge =
        widget.zone == UxLayoutZoneName.north ||
        widget.zone == UxLayoutZoneName.south;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête de l'inspecteur de zone
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.layers_outlined,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Inspecteur — Zone ${widget.zone.label} (${widget.zone.name})',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CompactBadge(
                      label: isEnabled ? 'Active' : 'Inactive',
                      backgroundColor: isEnabled
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                      foregroundColor: isEnabled
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Zone active', style: theme.textTheme.labelMedium),
                    const SizedBox(width: 6),
                    Switch(
                      key: const ValueKey('ux-zone-enabled-switch'),
                      value: isEnabled,
                      onChanged: (val) => _saveZoneSpec(
                        spec.copyWith(
                          enabled: val,
                          sizePx:
                              spec.sizePx ?? _defaultSizeForZone(widget.zone),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Paramètres spatiaux de la zone
            Wrap(
              spacing: 14,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'column',
                      icon: Icon(Icons.view_agenda_outlined, size: 15),
                      label: Text('Colonne'),
                    ),
                    ButtonSegment<String>(
                      value: 'row',
                      icon: Icon(Icons.view_week_outlined, size: 15),
                      label: Text('Ligne'),
                    ),
                  ],
                  selected: <String>{spec.axis},
                  onSelectionChanged: (sel) {
                    final nextAxis = sel.first;
                    _saveZoneSpec(
                      spec.copyWith(
                        enabled: widget.zoneSpec?.enabled ?? true,
                        axis: nextAxis,
                      ),
                    );
                  },
                ),
                FilterChip(
                  label: const Text('Défilement (scrollable)'),
                  selected: spec.scrollable,
                  onSelected: (val) => _saveZoneSpec(
                    spec.copyWith(
                      enabled: widget.zoneSpec?.enabled ?? true,
                      scrollable: val,
                    ),
                  ),
                ),
                if (widget.zone != UxLayoutZoneName.center)
                  SizedBox(
                    width: 155,
                    child: TextField(
                      key: const ValueKey('ux-zone-size-px-field'),
                      controller: _sizeCtrl,
                      focusNode: _sizeFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onSubmitted: (_) => _commitSizePx(),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: isHorizontalEdge
                            ? 'Hauteur (px)'
                            : 'Largeur (px)',
                        hintText: 'Auto',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Appliquer la dimension',
                          icon: const Icon(Icons.check_rounded, size: 16),
                          onPressed: _commitSizePx,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            // Liste des slots de la zone
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Blocs fonctionnels (${spec.slots.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('ux-add-zone-slot-btn'),
                  onPressed: () => _openSlotDialog(),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('+ Ajouter un bloc'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (spec.slots.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Aucun bloc fonctionnel dans la zone ${widget.zone.label}. Ajoutez un bloc pour projeter vos objets et attributs métiers.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              )
            else
              Column(
                children: [
                  for (final slot in spec.slots)
                    _ZoneSlotTile(
                      project: widget.project,
                      screen: widget.screen,
                      slot: slot,
                      onEdit: () => _openSlotDialog(existing: slot),
                      onDelete: () => _deleteSlot(slot),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoneSlotTile extends StatelessWidget {
  const _ZoneSlotTile({
    required this.project,
    required this.screen,
    required this.slot,
    required this.onEdit,
    required this.onDelete,
  });

  final SpecForgeProject project;
  final UxScreenSpec screen;
  final UxZoneWidgetSlot slot;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final explicitObj = slot.businessObjectId.trim().isNotEmpty
        ? project.findBusinessObject(slot.businessObjectId)
        : null;
    final inheritedObj =
        slot.businessObjectId.trim().isEmpty &&
            screen.primaryObjectId.trim().isNotEmpty
        ? project.findBusinessObject(screen.primaryObjectId)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _CompactBadge(
                      label: slot.kind.label,
                      backgroundColor: colors.secondaryContainer,
                      foregroundColor: colors.onSecondaryContainer,
                    ),
                    Text(
                      slot.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (explicitObj != null)
                      _CompactBadge(
                        icon: Icons.hub_outlined,
                        label: explicitObj.name,
                        backgroundColor: colors.tertiaryContainer,
                        foregroundColor: colors.onTertiaryContainer,
                      )
                    else if (slot.businessObjectId.trim().isNotEmpty)
                      _CompactBadge(
                        icon: Icons.hub_outlined,
                        label: slot.businessObjectId,
                        backgroundColor: colors.errorContainer,
                        foregroundColor: colors.onErrorContainer,
                      )
                    else if (inheritedObj != null)
                      _CompactBadge(
                        icon: Icons.hub_outlined,
                        label: '${inheritedObj.name} (écran)',
                        backgroundColor: colors.surfaceContainerHighest,
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Modifier ce bloc',
                icon: const Icon(Icons.edit_outlined, size: 17),
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Supprimer ce bloc',
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
              ),
            ],
          ),
          if (slot.attributeNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final attr in slot.attributeNames)
                  _CompactBadge(
                    label: attr,
                    backgroundColor: colors.surface,
                    foregroundColor: colors.onSurface,
                  ),
              ],
            ),
          ],
          if (slot.summary.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              slot.summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 2 — ACTIONS & RÈGLES DE GESTION (RG-xxx)
// =============================================================================

class _ScreenActionsTab extends StatelessWidget {
  const _ScreenActionsTab({
    required this.project,
    required this.screen,
    required this.onUpdateScreen,
  });

  final SpecForgeProject project;
  final UxScreenSpec screen;
  final Future<void> Function(UxScreenSpec updated) onUpdateScreen;

  Future<void> _openActionDialog(
    BuildContext context, {
    UxScreenAction? existing,
  }) async {
    final usedIds = <String>{for (final a in screen.actions) a.id};
    final edited = await showDialog<UxScreenAction>(
      context: context,
      builder: (ctx) => _ScreenActionDialog(
        project: project,
        usedActionIds: usedIds,
        existing: existing,
      ),
    );
    if (edited == null || !context.mounted) return;

    final nextActions = List<UxScreenAction>.from(screen.actions);
    if (existing == null) {
      nextActions.add(edited);
    } else {
      final idx = nextActions.indexWhere((a) => a.id == existing.id);
      if (idx >= 0) {
        nextActions[idx] = edited;
      } else {
        nextActions.add(edited);
      }
    }
    await onUpdateScreen(screen.copyWith(actions: nextActions));
  }

  Future<void> _deleteAction(UxScreenAction action) async {
    final nextActions = screen.actions.where((a) => a.id != action.id).toList();
    await onUpdateScreen(screen.copyWith(actions: nextActions));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final primaryActions = screen.actions
        .where((a) => a.hierarchy == UxActionHierarchy.primary)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Actions exposées & Règles RG (${screen.actions.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('ux-add-screen-action-btn'),
              onPressed: () => _openActionDialog(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('+ Ajouter une action'),
            ),
          ],
        ),
        if (primaryActions.length > 1) ...[
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('ux-multiple-primary-actions-warning'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.errorContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.error.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: colors.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Attention : ${primaryActions.length} actions « Primaire » sont définies (${primaryActions.map((a) => a.label).join(', ')}). Limitez-vous à une seule action primaire (CTA principal) par écran.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (screen.actions.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Aucune action définie sur cet écran.\nAjoutez des actions métier (validation, création, suppression, navigation) et reliez-les aux règles de gestion RG-xxx.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final action in screen.actions)
            _ActionCard(
              project: project,
              action: action,
              onEdit: () => _openActionDialog(context, existing: action),
              onDelete: () => _deleteAction(action),
            ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.project,
    required this.action,
    required this.onEdit,
    required this.onDelete,
  });

  final SpecForgeProject project;
  final UxScreenAction action;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final (badgeBg, badgeFg, badgeLabel) = switch (action.hierarchy) {
      UxActionHierarchy.primary => (
        colors.primary,
        colors.onPrimary,
        'Primaire',
      ),
      UxActionHierarchy.secondary => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
        'Secondaire',
      ),
      UxActionHierarchy.destructive => (
        colors.errorContainer,
        colors.onErrorContainer,
        'Destructrice',
      ),
      UxActionHierarchy.inline => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        'En ligne',
      ),
    };

    final targetRoute = action.targetRouteId.trim().isNotEmpty
        ? project.uxSpec.navigation.findRoute(action.targetRouteId)
        : null;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _CompactBadge(
                        label: badgeLabel,
                        backgroundColor: badgeBg,
                        foregroundColor: badgeFg,
                      ),
                      Text(
                        action.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (action.targetRouteId.trim().isNotEmpty)
                        _CompactBadge(
                          icon: Icons.arrow_forward_rounded,
                          label: targetRoute != null
                              ? '${targetRoute.path} (${targetRoute.title})'
                              : action.targetRouteId,
                          backgroundColor: targetRoute != null
                              ? colors.tertiaryContainer
                              : colors.errorContainer,
                          foregroundColor: targetRoute != null
                              ? colors.onTertiaryContainer
                              : colors.onErrorContainer,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Modifier l’action',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Supprimer l’action',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
            if (action.businessRuleIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final ruleRef in action.businessRuleIds)
                    Builder(
                      builder: (context) {
                        final rule = _resolveRule(project, ruleRef);
                        return Tooltip(
                          message: rule != null
                              ? '${rule.code} — ${rule.title}'
                              : ruleRef,
                          child: _CompactBadge(
                            icon: Icons.gavel_rounded,
                            label: rule != null ? rule.code : ruleRef,
                            backgroundColor: rule != null
                                ? colors.surfaceContainerHighest
                                : colors.errorContainer,
                            foregroundColor: rule != null
                                ? colors.onSurface
                                : colors.onErrorContainer,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
            if (action.confirmationMessage.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Confirmation : « ${action.confirmationMessage} »',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TAB 3 — ÉTATS UX (VIDE, CHARGEMENT, ERREURS, LECTURE SEULE)
// =============================================================================

class _ScreenStatesTab extends StatefulWidget {
  const _ScreenStatesTab({
    required this.project,
    required this.screen,
    required this.onUpdateScreen,
  });

  final SpecForgeProject project;
  final UxScreenSpec screen;
  final Future<void> Function(UxScreenSpec updated) onUpdateScreen;

  @override
  State<_ScreenStatesTab> createState() => _ScreenStatesTabState();
}

class _ScreenStatesTabState extends State<_ScreenStatesTab> {
  static const List<(String, String)> _standardLoadingPatterns = [
    ('skeleton', 'Squelette structurel (skeleton)'),
    ('spinner', 'Indicateur circulaire (spinner)'),
    ('progressive', 'Chargement progressif par blocs (progressive)'),
    ('optimistic', 'Mise à jour optimiste instantanée (optimistic)'),
  ];

  late final TextEditingController _emptyTitleCtrl;
  late final TextEditingController _emptyCtaCtrl;
  late final TextEditingController _errorHandlingCtrl;
  late final FocusNode _emptyTitleFocus;
  late final FocusNode _emptyCtaFocus;
  late final FocusNode _errorFocus;
  late String _loadingPattern;
  late List<String> _readOnlyRuleIds;

  @override
  void initState() {
    super.initState();
    final states = widget.screen.states;
    _emptyTitleCtrl = TextEditingController(text: states.emptyStateTitle);
    _emptyCtaCtrl = TextEditingController(text: states.emptyStateCta);
    _errorHandlingCtrl = TextEditingController(text: states.errorHandling);
    _loadingPattern = states.loadingPattern.trim().isEmpty
        ? 'skeleton'
        : states.loadingPattern.trim();
    _readOnlyRuleIds = List<String>.from(states.readOnlyRuleIds);

    _emptyTitleFocus = FocusNode()..addListener(_onFieldBlur);
    _emptyCtaFocus = FocusNode()..addListener(_onFieldBlur);
    _errorFocus = FocusNode()..addListener(_onFieldBlur);
  }

  void _onFieldBlur() {
    if (!_emptyTitleFocus.hasFocus &&
        !_emptyCtaFocus.hasFocus &&
        !_errorFocus.hasFocus) {
      _commitStatesIfChanged();
    }
  }

  @override
  void didUpdateWidget(covariant _ScreenStatesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screen.id != widget.screen.id ||
        oldWidget.screen.states != widget.screen.states) {
      final s = widget.screen.states;
      if (_emptyTitleCtrl.text != s.emptyStateTitle) {
        _emptyTitleCtrl.text = s.emptyStateTitle;
      }
      if (_emptyCtaCtrl.text != s.emptyStateCta) {
        _emptyCtaCtrl.text = s.emptyStateCta;
      }
      if (_errorHandlingCtrl.text != s.errorHandling) {
        _errorHandlingCtrl.text = s.errorHandling;
      }
      _loadingPattern = s.loadingPattern.trim().isEmpty
          ? 'skeleton'
          : s.loadingPattern.trim();
      _readOnlyRuleIds = List<String>.from(s.readOnlyRuleIds);
    }
  }

  @override
  void dispose() {
    _emptyTitleFocus.dispose();
    _emptyCtaFocus.dispose();
    _errorFocus.dispose();
    _emptyTitleCtrl.dispose();
    _emptyCtaCtrl.dispose();
    _errorHandlingCtrl.dispose();
    super.dispose();
  }

  UxScreenStatesSpec _buildDraftStates() => UxScreenStatesSpec(
    emptyStateTitle: _emptyTitleCtrl.text.trim(),
    emptyStateCta: _emptyCtaCtrl.text.trim(),
    loadingPattern: _loadingPattern.trim().isEmpty
        ? 'skeleton'
        : _loadingPattern.trim(),
    errorHandling: _errorHandlingCtrl.text.trim(),
    readOnlyRuleIds: _readOnlyRuleIds,
  );

  Future<void> _commitStatesIfChanged() async {
    final nextStates = _buildDraftStates();
    if (nextStates == widget.screen.states) return;
    await widget.onUpdateScreen(widget.screen.copyWith(states: nextStates));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final loadingOptions = <(String, String)>[
      ..._standardLoadingPatterns,
      if (!_standardLoadingPatterns.any((p) => p.$1 == _loadingPattern))
        (_loadingPattern, _loadingPattern),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'États transitoires, vides & lecture seule',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('ux-states-empty-title-field'),
                  controller: _emptyTitleCtrl,
                  focusNode: _emptyTitleFocus,
                  onSubmitted: (_) => _commitStatesIfChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Titre de l’état vide (emptyStateTitle)',
                    hintText: 'Ex. Aucune commande enregistrée pour le moment',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('ux-states-empty-cta-field'),
                  controller: _emptyCtaCtrl,
                  focusNode: _emptyCtaFocus,
                  onSubmitted: (_) => _commitStatesIfChanged(),
                  decoration: const InputDecoration(
                    labelText:
                        'Appel à l’action de l’état vide (emptyStateCta)',
                    hintText: 'Ex. Créer une première commande',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Pattern de chargement (loadingPattern)',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final (value, tooltip) in loadingOptions)
                      Tooltip(
                        message: tooltip,
                        child: ChoiceChip(
                          key: ValueKey('ux-loading-pattern-$value'),
                          label: Text(value),
                          selected: _loadingPattern == value,
                          onSelected: (selected) {
                            if (!selected) return;
                            setState(() => _loadingPattern = value);
                            _commitStatesIfChanged();
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('ux-states-error-handling-field'),
                  controller: _errorHandlingCtrl,
                  focusNode: _errorFocus,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Gestion des erreurs & reprise (errorHandling)',
                    hintText: 'Ex. Bandeau non bloquant avec bouton Réessayer et conservation de la saisie locale',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Règles de lecture seule (readOnlyRuleIds)',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.project.businessRules.isEmpty)
                  Text(
                    'Aucune règle de gestion définie dans le projet. Utilisez « + Règle RG » dans la barre supérieure pour en créer une.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final rule in widget.project.businessRules)
                        FilterChip(
                          key: ValueKey('ux-readonly-rule-chip-${rule.id}'),
                          label: Text('${rule.code} · ${rule.title}'),
                          selected: _containsRuleRef(_readOnlyRuleIds, rule),
                          onSelected: (selected) {
                            setState(() {
                              _readOnlyRuleIds = _toggleRuleRef(
                                _readOnlyRuleIds,
                                rule,
                                selected: selected,
                              );
                            });
                            _commitStatesIfChanged();
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const ValueKey('ux-save-screen-states-btn'),
                    onPressed: _commitStatesIfChanged,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Enregistrer les états UX'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// DIALOGUES — CRÉATION / ÉDITION D'ÉCRAN, SLOT, ACTION & ENRICHISSEMENT MÉTIER
// =============================================================================

class _ScreenMetaDialog extends StatefulWidget {
  const _ScreenMetaDialog({required this.project, this.existing});

  final SpecForgeProject project;
  final UxScreenSpec? existing;

  @override
  State<_ScreenMetaDialog> createState() => _ScreenMetaDialogState();
}

class _ScreenMetaDialogState extends State<_ScreenMetaDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _purposeCtrl;
  late String _routeId;
  late UxScreenPattern _pattern;
  late String _primaryObjectId;
  late List<String> _personaIds;
  late List<String> _useCaseIds;
  late List<String> _requirementIds;
  bool _resetZonesToPattern = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final ux = widget.project.uxSpec;

    _codeCtrl = TextEditingController(
      text: existing?.code ?? _nextScreenCode(ux.screens),
    );
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _purposeCtrl = TextEditingController(text: existing?.purpose ?? '');

    final rawRouteId = existing?.routeId.trim() ?? '';
    _routeId = rawRouteId.isEmpty
        ? ''
        : (ux.navigation.findRoute(rawRouteId)?.id ?? rawRouteId);

    _pattern = existing?.pattern ?? UxScreenPattern.masterDetail;

    final rawObjId = existing?.primaryObjectId.trim() ?? '';
    _primaryObjectId = rawObjId.isEmpty
        ? ''
        : (widget.project.findBusinessObject(rawObjId)?.id ?? rawObjId);

    _personaIds = List<String>.from(existing?.personaIds ?? const <String>[]);
    _useCaseIds = List<String>.from(existing?.useCaseIds ?? const <String>[]);
    _requirementIds = List<String>.from(
      existing?.requirementIds ?? const <String>[],
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Le nom de l’écran est obligatoire.');
      return;
    }
    final code = _codeCtrl.text.trim().isEmpty
        ? _nextScreenCode(widget.project.uxSpec.screens)
        : _codeCtrl.text.trim();

    final existing = widget.existing;
    final usedIds = <String>{
      for (final s in widget.project.uxSpec.screens) s.id,
    };
    final id =
        existing?.id ??
        _uniqueId(
          'scr_${_slugifyIdentifier(name, fallback: 'screen')}',
          usedIds,
        );

    List<UxScreenZoneSpec> zones;
    if (existing == null || _resetZonesToPattern) {
      final defaults = UxScreenSpec.defaultZonesForPattern(_pattern);
      zones = _primaryObjectId.isEmpty
          ? defaults
          : [
              for (final z in defaults)
                z.copyWith(
                  slots: [
                    for (final slot in z.slots)
                      if (_slotSupportsObjectBinding(slot.kind))
                        slot.copyWith(businessObjectId: _primaryObjectId)
                      else
                        slot,
                  ],
                ),
            ];
    } else {
      zones = existing.zones;
    }

    final result = UxScreenSpec(
      id: id,
      code: code,
      name: name,
      routeId: _routeId,
      pattern: _pattern,
      purpose: _purposeCtrl.text.trim(),
      personaIds: _personaIds,
      useCaseIds: _useCaseIds,
      requirementIds: _requirementIds,
      primaryObjectId: _primaryObjectId,
      zones: zones,
      actions: existing?.actions ?? const <UxScreenAction>[],
      states:
          existing?.states ??
          UxScreenStatesSpec(
            emptyStateTitle: 'Aucun élément à afficher sur $name',
          ),
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final routes = widget.project.uxSpec.navigation.routes;
    final objects = widget.project.businessObjects;
    final personas = widget.project.vision.personas;
    final useCases = widget.project.cahierDesCharges.useCases;
    final requirements = widget.project.cahierDesCharges.functionalRequirements;

    final routeItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '',
        child: Text('Aucune route associée', overflow: TextOverflow.ellipsis),
      ),
      for (final r in routes)
        DropdownMenuItem<String>(
          value: r.id,
          child: Text(
            '${r.path} — ${r.title}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (_routeId.isNotEmpty && !routes.any((r) => r.id == _routeId))
        DropdownMenuItem<String>(
          value: _routeId,
          child: Text(
            '$_routeId (introuvable)',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];

    final objectItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '',
        child: Text(
          'Aucun objet métier principal',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      for (final o in objects)
        DropdownMenuItem<String>(
          value: o.id,
          child: Text(
            '${o.name} (${o.technicalName})',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (_primaryObjectId.isNotEmpty &&
          !objects.any((o) => o.id == _primaryObjectId))
        DropdownMenuItem<String>(
          value: _primaryObjectId,
          child: Text(
            '$_primaryObjectId (introuvable)',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];

    return AlertDialog(
      title: Text(
        isEditing
            ? 'Métadonnées de ${widget.existing!.code}'
            : 'Nouvel écran UX',
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: TextField(
                      key: const ValueKey('ux-screen-code-field'),
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ux-screen-name-field'),
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nom de l’écran *',
                        errorText: _errorText,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('ux-screen-route-dropdown'),
                initialValue: _routeId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Route associée (routeId)',
                  border: OutlineInputBorder(),
                ),
                items: routeItems,
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _routeId = val;
                    if (_nameCtrl.text.trim().isEmpty && val.isNotEmpty) {
                      final matched = routes
                          .where((r) => r.id == val)
                          .firstOrNull;
                      if (matched != null) {
                        _nameCtrl.text = matched.title;
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UxScreenPattern>(
                key: const ValueKey('ux-screen-pattern-dropdown'),
                initialValue: _pattern,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Pattern spatial',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final p in UxScreenPattern.values)
                    DropdownMenuItem<UxScreenPattern>(
                      value: p,
                      child: Text(p.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _pattern = val);
                },
              ),
              if (isEditing) ...[
                const SizedBox(height: 6),
                CheckboxListTile(
                  key: const ValueKey('ux-screen-reset-zones-checkbox'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _resetZonesToPattern,
                  title: const Text(
                    'Réinitialiser les zones selon le pattern sélectionné',
                  ),
                  onChanged: (val) =>
                      setState(() => _resetZonesToPattern = val ?? false),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('ux-screen-primary-object-dropdown'),
                initialValue: _primaryObjectId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Objet métier principal (primaryObjectId)',
                  border: OutlineInputBorder(),
                ),
                items: objectItems,
                onChanged: (val) {
                  if (val != null) setState(() => _primaryObjectId = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('ux-screen-purpose-field'),
                controller: _purposeCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Intention fonctionnelle (purpose)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (personas.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Personas cibles',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in personas)
                      FilterChip(
                        label: Text(p.name),
                        selected: _containsAlias(_personaIds, [p.id, p.name]),
                        onSelected: (sel) => setState(() {
                          _personaIds = _toggleAlias(_personaIds, p.id, [
                            p.id,
                            p.name,
                          ], selected: sel);
                        }),
                      ),
                  ],
                ),
              ],
              if (useCases.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Cas d’usage couverts',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final uc in useCases)
                      FilterChip(
                        label: Text(uc.title),
                        selected: _containsAlias(_useCaseIds, [
                          uc.id,
                          uc.title,
                        ]),
                        onSelected: (sel) => setState(() {
                          _useCaseIds = _toggleAlias(_useCaseIds, uc.id, [
                            uc.id,
                            uc.title,
                          ], selected: sel);
                        }),
                      ),
                  ],
                ),
              ],
              if (requirements.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Exigences fonctionnelles (EXF-xxx)',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final req in requirements)
                      FilterChip(
                        label: Text('${req.code} · ${req.title}'),
                        selected: _containsAlias(_requirementIds, [
                          req.id,
                          req.code,
                        ]),
                        onSelected: (sel) => setState(() {
                          final canonical = req.code.trim().isNotEmpty
                              ? req.code.trim()
                              : req.id;
                          _requirementIds = _toggleAlias(
                            _requirementIds,
                            canonical,
                            [req.id, req.code],
                            selected: sel,
                          );
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('ux-screen-meta-save-btn'),
          onPressed: _submit,
          child: Text(isEditing ? 'Enregistrer' : 'Créer'),
        ),
      ],
    );
  }
}

class _ZoneSlotDialog extends StatefulWidget {
  const _ZoneSlotDialog({
    required this.project,
    required this.screen,
    required this.usedSlotIds,
    this.existing,
  });

  final SpecForgeProject project;
  final UxScreenSpec screen;
  final Set<String> usedSlotIds;
  final UxZoneWidgetSlot? existing;

  @override
  State<_ZoneSlotDialog> createState() => _ZoneSlotDialogState();
}

class _ZoneSlotDialogState extends State<_ZoneSlotDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late UxWidgetKind _kind;
  late String _businessObjectId;
  late List<String> _attributeNames;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _kind = existing?.kind ?? UxWidgetKind.detailCard;
    _titleCtrl = TextEditingController(text: existing?.title ?? _kind.label);
    _summaryCtrl = TextEditingController(text: existing?.summary ?? '');

    final rawObj = existing != null
        ? existing.businessObjectId.trim()
        : widget.screen.primaryObjectId.trim();
    _businessObjectId = rawObj.isEmpty
        ? ''
        : (widget.project.findBusinessObject(rawObj)?.id ?? rawObj);

    _attributeNames = List<String>.from(
      existing?.attributeNames ?? const <String>[],
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  List<BusinessAttribute> _availableAttributes() {
    if (_businessObjectId.isEmpty) return const <BusinessAttribute>[];
    final obj = widget.project.findBusinessObject(_businessObjectId);
    return obj?.attributes ?? const <BusinessAttribute>[];
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = 'Le titre du bloc est obligatoire.');
      return;
    }
    final id =
        widget.existing?.id ??
        _uniqueId(
          'slot_${_slugifyIdentifier(title, fallback: 'bloc')}',
          widget.usedSlotIds,
        );

    Navigator.of(context).pop(
      UxZoneWidgetSlot(
        id: id,
        title: title,
        kind: _kind,
        businessObjectId: _businessObjectId,
        attributeNames: _attributeNames,
        summary: _summaryCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final objects = widget.project.businessObjects;
    final availableAttrs = _availableAttributes();
    final availableAttrNames = <String>{for (final a in availableAttrs) a.name};

    final objectItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '',
        child: Text('Aucun objet métier lié', overflow: TextOverflow.ellipsis),
      ),
      for (final o in objects)
        DropdownMenuItem<String>(
          value: o.id,
          child: Text(
            '${o.name} (${o.technicalName})',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (_businessObjectId.isNotEmpty &&
          !objects.any((o) => o.id == _businessObjectId))
        DropdownMenuItem<String>(
          value: _businessObjectId,
          child: Text(
            '$_businessObjectId (introuvable)',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Ajouter un bloc dans la zone'
            : 'Modifier « ${widget.existing!.title} »',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('ux-slot-title-field'),
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Titre du bloc *',
                  errorText: _errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UxWidgetKind>(
                key: const ValueKey('ux-slot-kind-dropdown'),
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Famille de composant (UxWidgetKind)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final k in UxWidgetKind.values)
                    DropdownMenuItem<UxWidgetKind>(
                      value: k,
                      child: Text(k.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  final previousDefault = _kind.label;
                  setState(() {
                    if (_titleCtrl.text.trim().isEmpty ||
                        _titleCtrl.text.trim() == previousDefault) {
                      _titleCtrl.text = val.label;
                    }
                    _kind = val;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('ux-slot-object-dropdown'),
                initialValue: _businessObjectId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Objet métier lié (businessObjectId)',
                  border: OutlineInputBorder(),
                ),
                items: objectItems,
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _businessObjectId = val;
                    final nextObj = val.isEmpty
                        ? null
                        : widget.project.findBusinessObject(val);
                    final validNames = <String>{
                      if (nextObj != null)
                        for (final a in nextObj.attributes) a.name,
                    };
                    _attributeNames = _attributeNames
                        .where(validNames.contains)
                        .toList();
                  });
                },
              ),
              const SizedBox(height: 14),
              Text(
                'Attributs métiers projetés (attributeNames)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              if (availableAttrs.isEmpty)
                Text(
                  _businessObjectId.isEmpty
                      ? 'Sélectionnez un objet métier pour choisir ses attributs.'
                      : 'Cet objet métier ne possède pas encore d’attributs.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final attr in availableAttrs)
                      Tooltip(
                        message:
                            '${attr.type.label}${attr.required ? ' (requis)' : ''}${attr.description.isNotEmpty ? ' — ${attr.description}' : ''}',
                        child: FilterChip(
                          key: ValueKey('ux-slot-attr-chip-${attr.name}'),
                          label: Text(attr.name),
                          selected: _attributeNames.contains(attr.name),
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              if (!_attributeNames.contains(attr.name)) {
                                _attributeNames = [
                                  ..._attributeNames,
                                  attr.name,
                                ];
                              }
                            } else {
                              _attributeNames = _attributeNames
                                  .where((n) => n != attr.name)
                                  .toList();
                            }
                          }),
                        ),
                      ),
                    for (final extra in _attributeNames.where(
                      (n) => !availableAttrNames.contains(n),
                    ))
                      FilterChip(
                        label: Text(extra),
                        selected: true,
                        onSelected: (_) => setState(() {
                          _attributeNames = _attributeNames
                              .where((n) => n != extra)
                              .toList();
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('ux-slot-summary-field'),
                controller: _summaryCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Résumé / consignes d’agencement',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('ux-slot-save-btn'),
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _ScreenActionDialog extends StatefulWidget {
  const _ScreenActionDialog({
    required this.project,
    required this.usedActionIds,
    this.existing,
  });

  final SpecForgeProject project;
  final Set<String> usedActionIds;
  final UxScreenAction? existing;

  @override
  State<_ScreenActionDialog> createState() => _ScreenActionDialogState();
}

class _ScreenActionDialogState extends State<_ScreenActionDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _confirmCtrl;
  late UxActionHierarchy _hierarchy;
  late String _targetRouteId;
  late List<String> _businessRuleIds;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _labelCtrl = TextEditingController(text: existing?.label ?? '');
    _confirmCtrl = TextEditingController(
      text: existing?.confirmationMessage ?? '',
    );
    _hierarchy = existing?.hierarchy ?? UxActionHierarchy.secondary;

    final rawRoute = existing?.targetRouteId.trim() ?? '';
    _targetRouteId = rawRoute.isEmpty
        ? ''
        : (widget.project.uxSpec.navigation.findRoute(rawRoute)?.id ??
              rawRoute);

    _businessRuleIds = List<String>.from(
      existing?.businessRuleIds ?? const <String>[],
    );
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) {
      setState(() => _errorText = 'Le libellé de l’action est obligatoire.');
      return;
    }
    final id =
        widget.existing?.id ??
        _uniqueId(
          'act_${_slugifyIdentifier(label, fallback: 'action')}',
          widget.usedActionIds,
        );

    Navigator.of(context).pop(
      UxScreenAction(
        id: id,
        label: label,
        hierarchy: _hierarchy,
        businessRuleIds: _businessRuleIds,
        targetRouteId: _targetRouteId,
        confirmationMessage: _confirmCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routes = widget.project.uxSpec.navigation.routes;
    final rules = widget.project.businessRules;

    final routeItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '',
        child: Text('Aucune navigation', overflow: TextOverflow.ellipsis),
      ),
      for (final r in routes)
        DropdownMenuItem<String>(
          value: r.id,
          child: Text(
            '${r.path} — ${r.title}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (_targetRouteId.isNotEmpty &&
          !routes.any((r) => r.id == _targetRouteId))
        DropdownMenuItem<String>(
          value: _targetRouteId,
          child: Text(
            '$_targetRouteId (introuvable)',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nouvelle action d’écran'
            : 'Modifier « ${widget.existing!.label} »',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('ux-action-label-field'),
                controller: _labelCtrl,
                decoration: InputDecoration(
                  labelText: 'Libellé du bouton / action *',
                  errorText: _errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UxActionHierarchy>(
                key: const ValueKey('ux-action-hierarchy-dropdown'),
                initialValue: _hierarchy,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Hiérarchie visuelle',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final h in UxActionHierarchy.values)
                    DropdownMenuItem<UxActionHierarchy>(
                      value: h,
                      child: Text(h.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _hierarchy = val);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('ux-action-route-dropdown'),
                initialValue: _targetRouteId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Route ou modale cible (targetRouteId)',
                  border: OutlineInputBorder(),
                ),
                items: routeItems,
                onChanged: (val) {
                  if (val != null) setState(() => _targetRouteId = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('ux-action-confirm-field'),
                controller: _confirmCtrl,
                decoration: const InputDecoration(
                  labelText:
                      'Message de confirmation (si sensible/destructrice)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Règles de gestion liées (RG-xxx)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              if (rules.isEmpty)
                Text(
                  'Aucune règle RG définie dans le projet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final rule in rules)
                      FilterChip(
                        key: ValueKey('ux-action-rule-chip-${rule.id}'),
                        label: Text('${rule.code} · ${rule.title}'),
                        selected: _containsRuleRef(_businessRuleIds, rule),
                        onSelected: (sel) => setState(() {
                          _businessRuleIds = _toggleRuleRef(
                            _businessRuleIds,
                            rule,
                            selected: sel,
                          );
                        }),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('ux-action-save-btn'),
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _QuickAddObjectDialog extends StatefulWidget {
  const _QuickAddObjectDialog({required this.project});

  final SpecForgeProject project;

  @override
  State<_QuickAddObjectDialog> createState() => _QuickAddObjectDialogState();
}

class _QuickAddObjectDialogState extends State<_QuickAddObjectDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _techCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  bool _techEditedManually = false;
  bool _aggregateRoot = true;
  String? _nameError;
  String? _techError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _techCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    if (!_techEditedManually) {
      _techCtrl.text = value.trim().isEmpty
          ? ''
          : BusinessAttribute.toPascalCaseDslIdentifier(value);
    }
    if (_nameError != null || _techError != null) {
      setState(() {
        _nameError = null;
        _techError = null;
      });
    }
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final tech = _techCtrl.text.trim().isEmpty && name.isNotEmpty
        ? BusinessAttribute.toPascalCaseDslIdentifier(name)
        : _techCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _nameError = 'Le nom métier est obligatoire.');
      return;
    }
    if (!BusinessAttribute.isValidDslIdentifier(tech)) {
      setState(
        () => _techError = 'Identifiant ASCII requis ([A-Za-z_][A-Za-z0-9_-]*, sans accent ni espace).',
      );
      return;
    }
    final duplicate = widget.project.businessObjects.any(
      (o) =>
          o.technicalName.toLowerCase() == tech.toLowerCase() ||
          o.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      setState(
        () => _techError =
            'Un objet métier portant ce nom ou identifiant existe déjà.',
      );
      return;
    }

    final usedIds = <String>{
      for (final o in widget.project.businessObjects) o.id,
    };
    final objectId = _uniqueId(
      'obj_${BusinessAttribute.normalizeDslIdentifier(tech, fallback: 'objet').toLowerCase()}',
      usedIds,
    );

    final created = BusinessObjectSpec(
      id: objectId,
      name: name,
      technicalName: tech,
      description: _descCtrl.text.trim(),
      aggregateRoot: _aggregateRoot,
      attributes: <BusinessAttribute>[
        BusinessAttribute(
          id: 'attr_id_${_shortToken()}',
          name: 'id',
          type: BusinessAttributeType.uuid,
          required: true,
          unique: true,
          description: 'Identifiant unique',
        ),
      ],
    );

    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvel objet métier (depuis UX)'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('ux-quick-object-name-field'),
                controller: _nameCtrl,
                onChanged: _onNameChanged,
                decoration: InputDecoration(
                  labelText: 'Nom métier *',
                  hintText: 'Ex. Commande client',
                  errorText: _nameError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('ux-quick-object-tech-field'),
                controller: _techCtrl,
                onChanged: (_) {
                  _techEditedManually = true;
                  if (_techError != null) setState(() => _techError = null);
                },
                decoration: InputDecoration(
                  labelText: 'Nom technique PascalCase *',
                  hintText: 'Ex. CommandeClient',
                  errorText: _techError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('ux-quick-object-desc-field'),
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description fonctionnelle',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Agrégat racine (aggregateRoot)'),
                subtitle: const Text(
                  'Créé avec un attribut clé « id: uuid! » par défaut.',
                ),
                value: _aggregateRoot,
                onChanged: (val) => setState(() => _aggregateRoot = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('ux-quick-object-save-btn'),
          onPressed: _submit,
          child: const Text('Créer l’objet'),
        ),
      ],
    );
  }
}

class _QuickAddAttributeDialog extends StatefulWidget {
  const _QuickAddAttributeDialog({required this.project, this.initialObjectId});

  final SpecForgeProject project;
  final String? initialObjectId;

  @override
  State<_QuickAddAttributeDialog> createState() =>
      _QuickAddAttributeDialogState();
}

class _QuickAddAttributeDialogState extends State<_QuickAddAttributeDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _maskCtrl = TextEditingController();
  final TextEditingController _exampleCtrl = TextEditingController();
  late String _objectId;
  BusinessAttributeType _type = BusinessAttributeType.string;
  bool _required = false;
  bool _xSearchable = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final objects = widget.project.businessObjects;
    final candidate = widget.initialObjectId;
    _objectId = (candidate != null && objects.any((o) => o.id == candidate))
        ? candidate
        : objects.first.id;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _maskCtrl.dispose();
    _exampleCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Le nom d’attribut est obligatoire.');
      return;
    }
    if (!BusinessAttribute.isValidDslIdentifier(name)) {
      setState(
        () => _nameError = 'Identifiant ASCII requis ([A-Za-z_][A-Za-z0-9_-]*, sans accent ni espace).',
      );
      return;
    }

    final targetObj = widget.project.businessObjects
        .where((o) => o.id == _objectId)
        .firstOrNull;
    if (targetObj == null) return;
    if (targetObj.attributes.any((a) => a.name == name)) {
      setState(
        () => _nameError =
            'L’attribut « $name » existe déjà sur « ${targetObj.name} ».',
      );
      return;
    }
    if (targetObj.totalAttributeCount >=
        BusinessObjectSpec.maxAttributesPerObject) {
      setState(
        () => _nameError =
            'Plafond de ${BusinessObjectSpec.maxAttributesPerObject} attributs atteint sur cet objet.',
      );
      return;
    }

    final trimmedMask = _maskCtrl.text.trim();
    final trimmedExample = _exampleCtrl.text.trim();
    final extraKeywords = <String, Object?>{
      if (trimmedMask.isNotEmpty) 'x-mask': trimmedMask,
      if (_xSearchable) 'x-searchable': true,
    };

    final attribute = BusinessAttribute(
      id: 'attr_${name}_${_shortToken()}',
      name: name,
      type: _type,
      required: _required,
      description: _descCtrl.text.trim(),
      schemaConstraints: JsonSchemaConstraints(
        examples: trimmedExample.isEmpty
            ? const <Object?>[]
            : <Object?>[_coerceExampleForType(trimmedExample, _type)],
        extraKeywords: extraKeywords,
      ),
    );

    Navigator.of(context).pop((objectId: _objectId, attribute: attribute));
  }

  @override
  Widget build(BuildContext context) {
    final objects = widget.project.businessObjects;

    return AlertDialog(
      title: const Text('Nouvel attribut métier (depuis UX)'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('ux-quick-attr-object-dropdown'),
                initialValue: _objectId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Objet métier cible *',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final o in objects)
                    DropdownMenuItem<String>(
                      value: o.id,
                      child: Text(
                        '${o.name} (${o.technicalName})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _objectId = val;
                      _nameError = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: const ValueKey('ux-quick-attr-name-field'),
                      controller: _nameCtrl,
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Nom ASCII (DSL) *',
                        hintText: 'Ex. montantTotal',
                        errorText: _nameError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<BusinessAttributeType>(
                      key: const ValueKey('ux-quick-attr-type-dropdown'),
                      initialValue: _type,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final t in BusinessAttributeType.values)
                          DropdownMenuItem<BusinessAttributeType>(
                            value: t,
                            child: Text(
                              '${t.label} (${t.dslKeyword})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _type = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('ux-quick-attr-desc-field'),
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description fonctionnelle',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ux-quick-attr-mask-field'),
                      controller: _maskCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Masque (x-mask)',
                        hintText: 'Ex. AA-###-AA',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ux-quick-attr-example-field'),
                      controller: _exampleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Valeur d’exemple',
                        hintText: 'Ex. CMD-2026-001',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  FilterChip(
                    key: const ValueKey('ux-quick-attr-required-chip'),
                    label: const Text('Obligatoire (required)'),
                    selected: _required,
                    onSelected: (val) => setState(() => _required = val),
                  ),
                  FilterChip(
                    key: const ValueKey('ux-quick-attr-searchable-chip'),
                    label: const Text('Recherchable (x-searchable)'),
                    selected: _xSearchable,
                    onSelected: (val) => setState(() => _xSearchable = val),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('ux-quick-attr-save-btn'),
          onPressed: _submit,
          child: const Text('Ajouter l’attribut'),
        ),
      ],
    );
  }
}

class _QuickAddRuleDialog extends StatefulWidget {
  const _QuickAddRuleDialog({
    required this.project,
    this.initialTargetObjectId,
  });

  final SpecForgeProject project;
  final String? initialTargetObjectId;

  @override
  State<_QuickAddRuleDialog> createState() => _QuickAddRuleDialogState();
}

class _QuickAddRuleDialogState extends State<_QuickAddRuleDialog> {
  late final TextEditingController _codeCtrl;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _triggerCtrl = TextEditingController();
  final TextEditingController _conditionCtrl = TextEditingController();
  final TextEditingController _effectCtrl = TextEditingController();
  final TextEditingController _errorMsgCtrl = TextEditingController();
  BusinessRuleCategory _category = BusinessRuleCategory.validation;
  BusinessRulePriority _priority = BusinessRulePriority.high;
  late Set<String> _targetObjectIds;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(
      text: _nextRuleCode(widget.project.businessRules),
    );
    _targetObjectIds = <String>{
      if (widget.initialTargetObjectId != null &&
          widget.project.businessObjects.any(
            (o) => o.id == widget.initialTargetObjectId,
          ))
        widget.initialTargetObjectId!,
    };
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    _triggerCtrl.dispose();
    _conditionCtrl.dispose();
    _effectCtrl.dispose();
    _errorMsgCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'L’intitulé de la règle est obligatoire.');
      return;
    }
    final code = _codeCtrl.text.trim().isEmpty
        ? _nextRuleCode(widget.project.businessRules)
        : _codeCtrl.text.trim();
    final usedIds = <String>{
      for (final r in widget.project.businessRules) r.id,
    };
    final ruleId = _uniqueId(
      'rule_${_slugifyIdentifier(code, fallback: 'rg')}',
      usedIds,
    );

    final created = BusinessRuleSpec(
      id: ruleId,
      code: code,
      title: title,
      category: _category,
      priority: _priority,
      targetObjectIds: _targetObjectIds.toList(),
      trigger: _triggerCtrl.text.trim(),
      condition: _conditionCtrl.text.trim(),
      effect: _effectCtrl.text.trim(),
      errorMessage: _errorMsgCtrl.text.trim(),
    );

    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final objects = widget.project.businessObjects;

    return AlertDialog(
      title: const Text('Nouvelle règle de gestion RG (depuis UX)'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      key: const ValueKey('ux-quick-rule-code-field'),
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<BusinessRuleCategory>(
                      key: const ValueKey('ux-quick-rule-category-dropdown'),
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Catégorie',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in BusinessRuleCategory.values)
                          DropdownMenuItem<BusinessRuleCategory>(
                            value: c,
                            child: Text(
                              c.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _category = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<BusinessRulePriority>(
                      key: const ValueKey('ux-quick-rule-priority-dropdown'),
                      initialValue: _priority,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Priorité',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in BusinessRulePriority.values)
                          DropdownMenuItem<BusinessRulePriority>(
                            value: p,
                            child: Text(
                              p.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _priority = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('ux-quick-rule-title-field'),
                controller: _titleCtrl,
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                },
                decoration: InputDecoration(
                  labelText: 'Intitulé de la règle *',
                  errorText: _titleError,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (objects.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Objets métiers ciblés',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final o in objects)
                      FilterChip(
                        label: Text(o.name),
                        selected: _targetObjectIds.contains(o.id),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _targetObjectIds.add(o.id);
                          } else {
                            _targetObjectIds.remove(o.id);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('ux-quick-rule-trigger-field'),
                controller: _triggerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Quand (déclencheur)',
                  hintText: 'Ex. Soumission du formulaire de validation',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('ux-quick-rule-condition-field'),
                controller: _conditionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Si (condition)',
                  hintText: 'Ex. montantTotal <= 0',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('ux-quick-rule-effect-field'),
                controller: _effectCtrl,
                decoration: const InputDecoration(
                  labelText: 'Alors (effet / blocage)',
                  hintText: 'Ex. Refuser l’enregistrement',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('ux-quick-rule-error-field'),
                controller: _errorMsgCtrl,
                decoration: const InputDecoration(
                  labelText: 'Message d’erreur affiché',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('ux-quick-rule-save-btn'),
          onPressed: _submit,
          child: const Text('Créer la règle'),
        ),
      ],
    );
  }
}

// =============================================================================
// COMPOSANTS PARTAGÉS & UTILITAIRES INTERNES
// =============================================================================

class _CompactBadge extends StatelessWidget {
  const _CompactBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.icon,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foregroundColor),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _screenMatchesRoute(UxScreenSpec screen, UxRouteNode route) {
  final raw = screen.routeId.trim();
  if (raw.isEmpty) return false;
  final lower = raw.toLowerCase();
  if (route.id.toLowerCase() == lower) return true;
  final normalized = UxRouteNode.normalizePath(raw).toLowerCase();
  return route.path.toLowerCase() == lower ||
      route.path.toLowerCase() == normalized;
}

UxScreenPattern _inferPatternForRoute(
  UxRouteNode route,
  UxNavigationSpec navigation,
) {
  if (route.pageType == EditorPageType.a4Document) {
    return UxScreenPattern.documentA4;
  }
  if (route.pageType.isModal) {
    return UxScreenPattern.form;
  }
  final lowerTitle = route.title.toLowerCase();
  final lowerPath = route.path.toLowerCase();
  if (lowerTitle.contains('dashboard') ||
      lowerTitle.contains('tableau de bord') ||
      lowerPath == '/dashboard') {
    return UxScreenPattern.dashboard;
  }
  if (navigation.homeRouteId == route.id &&
      route.path == '/' &&
      (lowerTitle.contains('accueil') || lowerTitle.contains('pilotage'))) {
    return UxScreenPattern.dashboard;
  }
  return UxScreenPattern.masterDetail;
}

String _nextScreenCode(Iterable<UxScreenSpec> existing) {
  var maxIndex = 0;
  final pattern = RegExp(r'^SCR-(\d+)$', caseSensitive: false);
  final seenCodes = <String>{};
  for (final screen in existing) {
    seenCodes.add(screen.code.trim().toUpperCase());
    final match = pattern.firstMatch(screen.code.trim());
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!) ?? 0;
      if (parsed > maxIndex) maxIndex = parsed;
    }
  }
  var next = math.max(maxIndex + 1, existing.length + 1);
  while (seenCodes.contains('SCR-${next.toString().padLeft(3, '0')}')) {
    next++;
  }
  return 'SCR-${next.toString().padLeft(3, '0')}';
}

String _nextRuleCode(Iterable<BusinessRuleSpec> existing) {
  var maxIndex = 0;
  final pattern = RegExp(r'^RG-(\d+)$', caseSensitive: false);
  final seenCodes = <String>{};
  for (final rule in existing) {
    seenCodes.add(rule.code.trim().toUpperCase());
    final match = pattern.firstMatch(rule.code.trim());
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!) ?? 0;
      if (parsed > maxIndex) maxIndex = parsed;
    }
  }
  var next = math.max(maxIndex + 1, existing.length + 1);
  while (seenCodes.contains('RG-${next.toString().padLeft(3, '0')}')) {
    next++;
  }
  return 'RG-${next.toString().padLeft(3, '0')}';
}

double? _defaultSizeForZone(UxLayoutZoneName zone) => switch (zone) {
  UxLayoutZoneName.north => 64,
  UxLayoutZoneName.south => 56,
  UxLayoutZoneName.west => 320,
  UxLayoutZoneName.east => 300,
  UxLayoutZoneName.center => null,
};

bool _slotSupportsObjectBinding(UxWidgetKind kind) => switch (kind) {
  UxWidgetKind.kpiRow ||
  UxWidgetKind.dataTable ||
  UxWidgetKind.masterList ||
  UxWidgetKind.treeView ||
  UxWidgetKind.detailCard ||
  UxWidgetKind.formSection ||
  UxWidgetKind.chart => true,
  UxWidgetKind.tabGroup ||
  UxWidgetKind.toolbar ||
  UxWidgetKind.searchFilterBar ||
  UxWidgetKind.statusBanner => false,
};

String _formatNum(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

String _shortToken() =>
    shortid.generate().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

String _slugifyIdentifier(String raw, {required String fallback}) {
  final normalized = BusinessAttribute.normalizeDslIdentifier(
    raw,
    fallback: fallback,
  ).toLowerCase();
  return normalized.isEmpty ? fallback : normalized;
}

String _uniqueId(String base, Set<String> existingIds) {
  if (!existingIds.contains(base)) return base;
  final withToken = '${base}_${_shortToken()}';
  if (!existingIds.contains(withToken)) return withToken;
  var suffix = 2;
  while (existingIds.contains('${base}_$suffix')) {
    suffix++;
  }
  return '${base}_$suffix';
}

Object _coerceExampleForType(String raw, BusinessAttributeType type) =>
    switch (type) {
      BusinessAttributeType.integer => int.tryParse(raw) ?? raw,
      BusinessAttributeType.number => num.tryParse(raw) ?? raw,
      BusinessAttributeType.boolean => switch (raw.toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => raw,
      },
      _ => raw,
    };

BusinessRuleSpec? _resolveRule(SpecForgeProject project, String ref) {
  final needle = ref.trim().toLowerCase();
  if (needle.isEmpty) return null;
  for (final rule in project.businessRules) {
    if (rule.id.toLowerCase() == needle ||
        (rule.code.trim().isNotEmpty &&
            rule.code.trim().toLowerCase() == needle)) {
      return rule;
    }
  }
  return null;
}

bool _containsRuleRef(List<String> refs, BusinessRuleSpec rule) =>
    _containsAlias(refs, <String>[
      rule.id,
      if (rule.code.trim().isNotEmpty) rule.code.trim(),
    ]);

List<String> _toggleRuleRef(
  List<String> refs,
  BusinessRuleSpec rule, {
  required bool selected,
}) {
  final canonical = rule.code.trim().isNotEmpty ? rule.code.trim() : rule.id;
  return _toggleAlias(refs, canonical, <String>[
    rule.id,
    rule.code,
  ], selected: selected);
}

bool _containsAlias(List<String> refs, Iterable<String> aliases) {
  final lowered = <String>{
    for (final a in aliases)
      if (a.trim().isNotEmpty) a.trim().toLowerCase(),
  };
  return refs.any((r) => lowered.contains(r.trim().toLowerCase()));
}

List<String> _toggleAlias(
  List<String> refs,
  String canonical,
  Iterable<String> aliases, {
  required bool selected,
}) {
  final lowered = <String>{
    for (final a in aliases)
      if (a.trim().isNotEmpty) a.trim().toLowerCase(),
  };
  final filtered = refs
      .where((r) => !lowered.contains(r.trim().toLowerCase()))
      .toList();
  if (selected) {
    filtered.add(canonical);
  }
  return filtered;
}

String? _resolvePersonaLabel(SpecForgeProject project, String ref) {
  final needle = ref.trim().toLowerCase();
  for (final SpecPersona p in project.vision.personas) {
    if (p.id.toLowerCase() == needle || p.name.toLowerCase() == needle) {
      return p.name;
    }
  }
  return null;
}

String? _resolveUseCaseLabel(SpecForgeProject project, String ref) {
  final needle = ref.trim().toLowerCase();
  for (final UseCaseSpec uc in project.cahierDesCharges.useCases) {
    if (uc.id.toLowerCase() == needle || uc.title.toLowerCase() == needle) {
      return uc.title;
    }
  }
  return null;
}

String? _resolveRequirementCode(SpecForgeProject project, String ref) {
  final needle = ref.trim().toLowerCase();
  for (final FunctionalRequirement r
      in project.cahierDesCharges.functionalRequirements) {
    if (r.id.toLowerCase() == needle ||
        (r.code.trim().isNotEmpty && r.code.trim().toLowerCase() == needle)) {
      return r.code.trim().isNotEmpty ? r.code.trim() : r.id;
    }
  }
  return null;
}
