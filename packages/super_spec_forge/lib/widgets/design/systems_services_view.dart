/// Page « Systèmes & Services » de l'espace Design, contextualisée par le
/// domaine en cours via son fil d'Ariane ([SystemsServicesView]) : chat IA
/// d'urbaniste à gauche et inventaire structuré par catégorie à droite
/// (Applications externes, Fronts Web/Mobile, BFF, Microservices, Monolithes).
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart'
    show VibeChatAttachment;

import '../../ai/systems_services_ai.dart';
import '../../models/domain_catalog.dart';
import '../../models/spec_forge_project.dart';
import '../../services/event_storming_operations.dart';
import '../../services/spec_forge_controller.dart';
import '../spec_split_handle.dart';
import '../workspace/event_storming/event_storming_step_column.dart'
    show EventStormPostItColors;
import 'design_domain_breadcrumb.dart';
import 'systems_services_chat_pane.dart';

final RegExp _kebabCodePattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

IconData _iconForSystemKind(DomainSystemKind kind) => switch (kind) {
  DomainSystemKind.externalApp => Icons.public_rounded,
  DomainSystemKind.openSourceTool => Icons.handyman_rounded,
  DomainSystemKind.webFront => Icons.web_rounded,
  DomainSystemKind.mobileApp => Icons.smartphone_rounded,
  DomainSystemKind.bff => Icons.mediation_rounded,
  DomainSystemKind.microservice => Icons.dns_outlined,
  DomainSystemKind.monolith => Icons.apartment_rounded,
};

/// Vue Design « Systèmes & Services » permettant de définir, par domaine, la
/// liste des applications externes et Tools openSource (aidant l'Event Storming
/// `EXT-*`), des fronts (Web, App Mobile), des BFF, des (micro)services et des
/// monolithes.
class SystemsServicesView extends StatefulWidget {
  /// Crée la page à partir des domaines du catalogue actif de [controller].
  const SystemsServicesView({
    required this.controller,
    required this.onBack,
    required this.onManageDomains,
    this.initialDomainId,
    this.onDomainChanged,
    this.onOpenEventStorming,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Contrôleur principal portant le catalogue des domaines et le projet actif.
  final SpecForgeController controller;

  /// Revient au menu Design.
  final VoidCallback onBack;

  /// Ouvre la gestion des domaines lorsqu'aucun domaine n'est défini.
  final VoidCallback onManageDomains;

  /// Identifiant optionnel du domaine sélectionné à l'ouverture de la vue.
  final String? initialDomainId;

  /// Notifie le parent lorsqu'un autre domaine est sélectionné.
  final ValueChanged<String?>? onDomainChanged;

  /// Callback optionnelle ouvrant directement l'étape Event Storming du projet Spec actif.
  final VoidCallback? onOpenEventStorming;

  /// Sélecteurs optionnels de pièces jointes et presse-papiers pour le chat IA.
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<SystemsServicesView> createState() => _SystemsServicesViewState();
}

class _SystemsServicesViewState extends State<SystemsServicesView> {
  static const double _defaultChatFraction = 0.36;

  final GlobalKey _splitKey = GlobalKey();
  final TextEditingController _searchCtrl = TextEditingController();
  double _chatFraction = _defaultChatFraction;
  double _dragOffset = SpecSplitHandle.width / 2;
  String? _selectedDomainId;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedDomainId = widget.initialDomainId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selected = _resolveSelectedDomain();
      if (selected != null) {
        widget.onDomainChanged?.call(selected.id);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  FunctionalDomain? _resolveSelectedDomain() {
    final domains = widget.controller.domainCatalog.domains;
    final effectiveId =
        _selectedDomainId ?? widget.controller.activeDesignDomainId;
    return domains.where((d) => d.id == effectiveId).firstOrNull ??
        domains.firstOrNull;
  }

  void _selectDomain(FunctionalDomain domain) {
    if (domain.id == _selectedDomainId &&
        widget.controller.activeDesignDomainId == domain.id) {
      return;
    }
    setState(() => _selectedDomainId = domain.id);
    widget.controller.setActiveDesignDomainId(domain.id);
    widget.onDomainChanged?.call(domain.id);
  }

  Future<void> _saveCatalog(DomainCatalog next) async {
    try {
      await widget.controller.updateDomainCatalog(next);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error is FormatException ? error.message : '$error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  AuditLogEntry _buildAudit(
    String domainId, {
    required DomainAuditAction action,
    required String details,
  }) => AuditLogEntry(
    id: 'audit_${shortid.generate()}',
    recordedAt: DateTime.now().toUtc(),
    actorUsername: 'local-user',
    domainId: domainId,
    actionType: action,
    details: details,
  );

  void _triggerDiscoverWithAi(
    FunctionalDomain domain,
    SpecForgeProject? project,
  ) {
    if (widget.controller.isSending) return;
    if (_chatFraction <= 0) {
      setState(() => _chatFraction = _defaultChatFraction);
    }
    final prompt = project == null
        ? 'Analyse le domaine « ${domain.name} » (${domain.domainCode}) et ses contrats, '
            'puis propose la liste structurée des applications externes et Tools openSource (pour l’Event Storming EXT-*), '
            'des fronts (Web, App Mobile), BFF éventuels et (micro)services ou application monolithique.'
        : 'À partir du projet actif « ${project.name} » (vision, cahier des charges, Event Storming, écrans UX) '
            'et du domaine « ${domain.name} », cartographie les applications externes et Tools openSource (pour alimenter les post-its EXT-*), '
            'les fronts Web & Mobile, les BFF et les (micro)services ou monolithes du domaine.';
    unawaited(
      widget.controller.sendSystemsServicesMessage(domain.id, prompt),
    );
  }

  Future<void> _toggleActive(
    DomainCatalog catalog,
    FunctionalDomain domain,
    Microservice service,
    bool nextActive,
  ) async {
    final updated = service.copyWith(isActive: nextActive);
    final audit = _buildAudit(
      domain.id,
      action: DomainAuditAction.update,
      details:
          '${service.kind.shortLabel} « ${service.name} » ${nextActive ? 'activé' : 'désactivé'}.',
    );
    await _saveCatalog(
      catalog.copyWith(
        microservices: [
          for (final item in catalog.microservices)
            if (item.id == service.id) updated else item,
        ],
        auditLog: [...catalog.auditLog, audit],
        updatedAt: audit.recordedAt,
      ),
    );
  }

  Future<void> _deleteSystemService(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    Microservice service,
  ) async {
    final boundConfigs = catalog.configurationEntries
        .where((c) => c.microserviceId == service.id)
        .length;
    if (boundConfigs > 0) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Suppression impossible : $boundConfigs entrée(s) de configuration d’environnement ciblent « ${service.name} ».',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmation'),
        content: Text(
          'Supprimer « ${service.name} » (${service.kind.label}) du domaine « ${domain.name} » ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('systems-services-confirm-delete-btn'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final audit = _buildAudit(
      domain.id,
      action: DomainAuditAction.delete,
      details: '${service.kind.label} « ${service.name} » supprimé.',
    );
    await _saveCatalog(
      catalog.copyWith(
        microservices: catalog.microservices
            .where((s) => s.id != service.id)
            .toList(),
        auditLog: [...catalog.auditLog, audit],
        updatedAt: audit.recordedAt,
      ),
    );
  }

  Future<void> _editSystemService(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain, {
    Microservice? existing,
    DomainSystemKind? defaultKind,
  }) async {
    final result = await showDialog<Microservice>(
      context: context,
      builder: (ctx) => _SystemServiceEditDialog(
        catalog: catalog,
        domain: domain,
        existing: existing,
        defaultKind:
            existing?.kind ?? defaultKind ?? DomainSystemKind.microservice,
      ),
    );
    if (result == null || !mounted) return;

    final current = widget.controller.domainCatalog;
    final exists = current.microservices.any((s) => s.id == result.id);
    final audit = _buildAudit(
      domain.id,
      action: exists ? DomainAuditAction.update : DomainAuditAction.create,
      details: exists
          ? '${result.kind.label} « ${result.name} » modifié.'
          : '${result.kind.label} « ${result.name} » créé.',
    );
    await _saveCatalog(
      current.copyWith(
        microservices: [
          for (final item in current.microservices)
            if (item.id == result.id) result else item,
          if (!exists) result,
        ],
        auditLog: [...current.auditLog, audit],
        updatedAt: audit.recordedAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final catalog = widget.controller.domainCatalog;
        final domains = catalog.domains;
        final selected = _resolveSelectedDomain();

        return Column(
          key: const ValueKey('systems-services-view'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesignDomainBreadcrumbBar(
              domains: domains,
              selectedDomain: selected,
              onDomainSelected: _selectDomain,
              segments: const [
                DesignBreadcrumbSegment(
                  key: ValueKey('systems-services-crumb'),
                  label: 'Systèmes & Services',
                ),
              ],
            ),
            Expanded(
              child: selected == null
                  ? _buildEmptyDomainsState(context)
                  : _buildDomainWorkspace(context, catalog, selected),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyDomainsState(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Icon(Icons.apps_rounded, size: 42, color: colors.outline),
            Text(
              'Aucun domaine fonctionnel défini.\nCréez d’abord un domaine pour inventorier ses systèmes externes, fronts, BFF et services.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('systems-services-manage-domains-btn'),
              onPressed: widget.onManageDomains,
              icon: const Icon(Icons.domain_rounded),
              label: const Text('Gestion des domaines'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDomainWorkspace(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final project = widget.controller.project;
    final activeFilter = widget.controller.systemsServicesActiveFilter(
      domain.id,
    );
    final domainSystems = catalog.microservices
        .where((s) => s.domainId == domain.id)
        .toList();

    final externalCount = domainSystems
        .where((s) => s.kind.isExternal)
        .length;
    final openSourceCount = domainSystems
        .where((s) => s.kind.isOpenSourceTool)
        .length;
    final frontCount = domainSystems.where((s) => s.kind.isFrontend).length;
    final backendCount = domainSystems.where((s) => s.kind.isBackend).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // En-tête du domaine
        Container(
          color: colors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.apps_rounded, size: 22, color: colors.primary),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Systèmes & Services',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Chip(
                            key: const ValueKey(
                              'systems-services-active-domain-chip',
                            ),
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.domain_rounded, size: 15),
                            label: Text('${domain.name} (${domain.domainCode})'),
                          ),
                          if (!domain.isActive)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: const Text('Inactif'),
                              backgroundColor: colors.errorContainer,
                            ),
                        ],
                      ),
                      Text(
                        '$externalCount app(s) externe(s) (EXT-*) · '
                        '$openSourceCount tool(s) openSource · '
                        '$frontCount front(s) Web/Mobile · '
                        '$backendCount BFF / service(s) / monolithe(s)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (project != null && widget.onOpenEventStorming != null)
                    OutlinedButton.icon(
                      key: const ValueKey(
                        'systems-services-open-event-storming-btn',
                      ),
                      onPressed: widget.onOpenEventStorming,
                      icon: const Icon(Icons.bolt_rounded, size: 16),
                      label: const Text('Event Storming'),
                    ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('systems-services-ai-generate-btn'),
                    onPressed: widget.controller.isSending
                        ? null
                        : () => _triggerDiscoverWithAi(domain, project),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                    label: const Text('Découvrir via l’IA'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('systems-services-add-btn'),
                    onPressed: () => _editSystemService(
                      context,
                      catalog,
                      domain,
                      defaultKind: activeFilter,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: Text(
                      activeFilter == null
                          ? 'Ajouter'
                          : 'Ajouter (${activeFilter.shortLabel})',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Split pane Chat IA (gauche) / Inventaire structuré (droite)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const dividerWidth = SpecSplitHandle.width;
              const collapsedRailWidth = 38.0;
              const minChatWidth = 260.0;
              const minWorkspaceWidth = 380.0;
              final totalWidth = constraints.maxWidth;
              final availableWidth = (totalWidth - dividerWidth).clamp(
                0.0,
                double.infinity,
              );
              final isCollapsed = _chatFraction <= 0.0;
              final chatWidth = isCollapsed
                  ? 0.0
                  : (availableWidth <= minChatWidth + minWorkspaceWidth
                        ? availableWidth * _chatFraction
                        : (availableWidth * _chatFraction).clamp(
                            minChatWidth,
                            availableWidth - minWorkspaceWidth,
                          ));

              return Row(
                key: _splitKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isCollapsed)
                    Container(
                      key: const ValueKey('systems-services-chat-collapsed'),
                      width: collapsedRailWidth,
                      color: colors.surfaceContainerLow,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          IconButton(
                            key: const ValueKey(
                              'systems-services-chat-expand-btn',
                            ),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Afficher l’assistant IA',
                            onPressed: () => setState(
                              () => _chatFraction = _defaultChatFraction,
                            ),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                          const SizedBox(height: 8),
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      width: chatWidth,
                      child: SystemsServicesChatPane(
                        controller: widget.controller,
                        domain: domain,
                        activeFilterKind: activeFilter,
                        onCollapse: () => setState(() => _chatFraction = 0.0),
                        pickAttachments: widget.pickAttachments,
                        pasteAttachments: widget.pasteAttachments,
                        hasClipboardMedia: widget.hasClipboardMedia,
                        pasteClipboardMedia: widget.pasteClipboardMedia,
                      ),
                    ),
                  SpecSplitHandle(
                    key: const ValueKey('systems-services-split-handle'),
                    onDoubleTap: () =>
                        setState(() => _chatFraction = _defaultChatFraction),
                    onHorizontalDragDown: (details) {
                      final box =
                          _splitKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box != null && !isCollapsed) {
                        final localX = box
                            .globalToLocal(details.globalPosition)
                            .dx;
                        _dragOffset = (localX - chatWidth).clamp(
                          0.0,
                          SpecSplitHandle.width,
                        );
                      } else {
                        _dragOffset = SpecSplitHandle.width / 2;
                      }
                    },
                    onHorizontalDragUpdate: (details) {
                      final box =
                          _splitKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box == null || availableWidth <= 0) return;
                      final localX = box
                          .globalToLocal(details.globalPosition)
                          .dx;
                      final nextWidth = localX - _dragOffset;
                      final minFrac =
                          availableWidth > minChatWidth + minWorkspaceWidth
                          ? (minChatWidth / availableWidth)
                          : 0.22;
                      final maxFrac =
                          availableWidth > minChatWidth + minWorkspaceWidth
                          ? ((availableWidth - minWorkspaceWidth) /
                                availableWidth)
                          : 0.68;
                      setState(() {
                        if (isCollapsed) {
                          if (nextWidth > 60) {
                            _chatFraction = (nextWidth / availableWidth).clamp(
                              minFrac,
                              maxFrac,
                            );
                          }
                          return;
                        }
                        if (nextWidth < 140) {
                          _chatFraction = 0.0;
                        } else {
                          _chatFraction = (nextWidth / availableWidth).clamp(
                            minFrac,
                            maxFrac,
                          );
                        }
                      });
                    },
                  ),
                  Expanded(
                    child: _buildSystemsPane(
                      context,
                      catalog,
                      domain,
                      domainSystems,
                      activeFilter,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSystemsPane(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    List<Microservice> domainSystems,
    DomainSystemKind? activeFilter,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final query = _searchQuery.trim().toLowerCase();

    final countByKind = <DomainSystemKind, int>{
      for (final kind in DomainSystemKind.values)
        kind: domainSystems.where((s) => s.kind == kind).length,
    };

    final filtered = domainSystems.where((s) {
      if (activeFilter != null && s.kind != activeFilter) return false;
      if (query.isEmpty) return true;
      return s.name.toLowerCase().contains(query) ||
          s.serviceCode.toLowerCase().contains(query) ||
          s.vendor.toLowerCase().contains(query) ||
          s.description.toLowerCase().contains(query) ||
          s.kind.label.toLowerCase().contains(query);
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    final visibleKinds = activeFilter != null
        ? <DomainSystemKind>[activeFilter]
        : DomainSystemKind.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Barre de recherche et puces de filtrage par catégorie
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              bottom: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              TextField(
                key: const ValueKey('systems-services-search-field'),
                controller: _searchCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  hintText:
                      'Filtrer par nom, code, fournisseur ou description…',
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer le filtre',
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilterChip(
                    key: const ValueKey('systems-services-filter-all'),
                    visualDensity: VisualDensity.compact,
                    label: Text('Tous (${domainSystems.length})'),
                    selected: activeFilter == null,
                    onSelected: (_) => widget.controller
                        .setSystemsServicesActiveFilter(domain.id, null),
                  ),
                  for (final kind in DomainSystemKind.values)
                    FilterChip(
                      key: ValueKey('systems-services-filter-${kind.name}'),
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(_iconForSystemKind(kind), size: 15),
                      label: Text(
                        '${kind.shortLabel} (${countByKind[kind] ?? 0})',
                      ),
                      selected: activeFilter == kind,
                      onSelected: (selected) => widget.controller
                          .setSystemsServicesActiveFilter(
                            domain.id,
                            selected ? kind : null,
                          ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // Liste structurée par catégorie
        Expanded(
          child: domainSystems.isEmpty
              ? _buildEmptyDomainSystems(context, catalog, domain)
              : filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Aucun système ou service ne correspond au filtre actif.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView(
                  key: const ValueKey('systems-services-list'),
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final kind in visibleKinds)
                      if (filtered.any((s) => s.kind == kind)) ...[
                        _buildKindSectionHeader(
                          context,
                          catalog,
                          domain,
                          kind,
                          filtered.where((s) => s.kind == kind).length,
                        ),
                        const SizedBox(height: 8),
                        for (final service in filtered.where(
                          (s) => s.kind == kind,
                        ))
                          _buildSystemCard(
                            context,
                            catalog,
                            domain,
                            service,
                            isDark,
                          ),
                        const SizedBox(height: 16),
                      ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyDomainSystems(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 14,
            children: [
              Icon(Icons.hub_outlined, size: 44, color: colors.primary),
              Text(
                'Aucun système ou service déclaré pour « ${domain.name} »',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Recensez les applications externes (Stripe, email, ERP…), les Tools openSource '
                '(Keycloak, Kafka, MinIO, Meilisearch…) qui alimentent les systèmes externes EXT-* '
                'de l’Event Storming, ainsi que les fronts Web & Mobile, BFF, microservices ou '
                'applications monolithiques.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final kind in DomainSystemKind.values)
                    ActionChip(
                      key: ValueKey('systems-services-empty-add-${kind.name}'),
                      avatar: Icon(_iconForSystemKind(kind), size: 16),
                      label: Text('+ ${kind.shortLabel}'),
                      onPressed: () => _editSystemService(
                        context,
                        catalog,
                        domain,
                        defaultKind: kind,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKindSectionHeader(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    DomainSystemKind kind,
    int count,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Icon(_iconForSystemKind(kind), size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${kind.pluralLabel} ($count)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (kind.isExternal)
                Text(
                  '· Alimente les post-its Rose pâle EXT-* en Event Storming',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              else if (kind.isOpenSourceTool)
                Text(
                  '· Outils open-source auto-hébergés (importables en EXT-* en Event Storming)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        TextButton.icon(
          key: ValueKey('systems-services-section-add-${kind.name}'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () =>
              _editSystemService(context, catalog, domain, defaultKind: kind),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text('Ajouter ${kind.shortLabel}'),
        ),
      ],
    );
  }

  Widget _buildSystemCard(
    BuildContext context,
    DomainCatalog catalog,
    FunctionalDomain domain,
    Microservice service,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final stack = catalog.techStackForService(service);
    final envConfigCount = catalog.configurationEntries
        .where((c) => c.microserviceId == service.id)
        .length;
    final extPalette = EventStormPostItColors.externalSystem(isDark);
    final extSuggestedId = service.kind.isOffTheShelf
        ? EventStormingOperations.nextCatalogId(
            'EXT',
            service.name,
            const <String>{},
          )
        : null;

    return Card(
      key: ValueKey('systems-services-card-${service.id}'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: service.kind.isOffTheShelf
              ? extPalette.border.withValues(alpha: 0.75)
              : colors.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                _iconForSystemKind(service.kind),
                size: 20,
                color: service.isActive ? colors.primary : colors.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 5,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        service.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: service.isActive
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          service.serviceCode,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (extSuggestedId != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: extPalette.background,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: extPalette.border),
                          ),
                          child: Text(
                            extSuggestedId,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              color: extPalette.foreground,
                            ),
                          ),
                        ),
                      if (service.vendor.isNotEmpty)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          avatar: const Icon(Icons.business_rounded, size: 14),
                          label: Text(service.vendor),
                          labelStyle: theme.textTheme.labelSmall,
                        ),
                      if (stack != null)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          avatar: const Icon(Icons.layers_rounded, size: 14),
                          label: Text(stack.name),
                          labelStyle: theme.textTheme.labelSmall,
                        ),
                      if (envConfigCount > 0)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          avatar: const Icon(Icons.tune_rounded, size: 14),
                          label: Text('$envConfigCount var.'),
                          labelStyle: theme.textTheme.labelSmall,
                        ),
                      if (!service.isActive)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          label: const Text('Inactif'),
                          labelStyle: theme.textTheme.labelSmall,
                        ),
                    ],
                  ),
                  if (service.description.isNotEmpty)
                    Text(
                      service.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: service.isActive ? 'Désactiver' : 'Activer',
                  child: Switch(
                    key: ValueKey('systems-services-active-${service.id}'),
                    value: service.isActive,
                    onChanged: (val) =>
                        _toggleActive(catalog, domain, service, val),
                  ),
                ),
                IconButton(
                  key: ValueKey('systems-services-edit-${service.id}'),
                  tooltip: 'Modifier ${service.name}',
                  iconSize: 18,
                  onPressed: () => _editSystemService(
                    context,
                    catalog,
                    domain,
                    existing: service,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: ValueKey('systems-services-delete-${service.id}'),
                  tooltip: 'Supprimer ${service.name}',
                  iconSize: 18,
                  onPressed: () => _deleteSystemService(
                    context,
                    catalog,
                    domain,
                    service,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemServiceEditDialog extends StatefulWidget {
  const _SystemServiceEditDialog({
    required this.catalog,
    required this.domain,
    required this.defaultKind,
    this.existing,
  });

  final DomainCatalog catalog;
  final FunctionalDomain domain;
  final Microservice? existing;
  final DomainSystemKind defaultKind;

  @override
  State<_SystemServiceEditDialog> createState() =>
      _SystemServiceEditDialogState();
}

class _SystemServiceEditDialogState extends State<_SystemServiceEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _vendorCtrl;
  late final TextEditingController _descCtrl;
  late DomainSystemKind _kind;
  late String? _techStackId;
  late bool _isActive;
  bool _codeManuallyEdited = false;
  String? _duplicateError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _kind = existing?.kind ?? widget.defaultKind;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _codeCtrl = TextEditingController(text: existing?.serviceCode ?? '');
    _vendorCtrl = TextEditingController(text: existing?.vendor ?? '');
    _descCtrl = TextEditingController(text: existing?.description ?? '');
    _techStackId = existing?.techStackId ??
        (_kind.isOffTheShelf ? null : widget.domain.techStackId);
    if (_techStackId != null &&
        !widget.catalog.techStacks.any((s) => s.id == _techStackId)) {
      _techStackId = null;
    }
    _isActive = existing?.isActive ?? true;
    _codeManuallyEdited = existing != null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _vendorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String? _validateCode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length < 2 ||
        trimmed.length > 64 ||
        !_kebabCodePattern.hasMatch(trimmed)) {
      return 'Code requis en kebab-case (2 à 64 car., ex. stripe-psp).';
    }
    return null;
  }

  void _submit() {
    setState(() => _duplicateError = null);
    if (!_formKey.currentState!.validate()) return;
    final trimmedCode = _codeCtrl.text.trim();
    final duplicate = widget.catalog.microservices.any(
      (item) =>
          item.domainId == widget.domain.id &&
          item.serviceCode == trimmedCode &&
          item.id != widget.existing?.id,
    );
    if (duplicate) {
      setState(
        () => _duplicateError =
            'Le code « $trimmedCode » est déjà utilisé dans ce domaine.',
      );
      return;
    }

    Navigator.of(context).pop(
      Microservice(
        id: widget.existing?.id ?? 'service_${shortid.generate()}',
        domainId: widget.domain.id,
        serviceCode: trimmedCode,
        name: _nameCtrl.text.trim(),
        kind: _kind,
        description: _descCtrl.text.trim(),
        isActive: _isActive,
        techStackId: _kind.isOffTheShelf ? null : _techStackId,
        vendor: _vendorCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nouveau système ou service'
            : 'Modifier « ${widget.existing!.name} »',
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                DropdownButtonFormField<DomainSystemKind>(
                  key: const ValueKey('systems-services-dialog-kind'),
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Catégorie *',
                  ),
                  items: [
                    for (final kind in DomainSystemKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Row(
                          children: [
                            Icon(_iconForSystemKind(kind), size: 17),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                kind.label,
                                maxLines: 1,
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
                      _kind = val;
                      if (_kind.isOffTheShelf) {
                        _techStackId = null;
                      }
                    });
                  },
                ),
                if (_kind.isOffTheShelf)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.55,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _kind.isExternal
                          ? 'Cette application externe sera proposée comme système externe Rose pâle (`EXT-*`) dans l’Event Storming.'
                          : 'Cet outil open-source (Keycloak, Kafka, MinIO, Meilisearch…) pourra être importé comme système externe (`EXT-*`) dans l’Event Storming.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                TextFormField(
                  key: const ValueKey('systems-services-dialog-name'),
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nom affiché *',
                    hintText: switch (_kind) {
                      DomainSystemKind.externalApp => 'Stripe Paiement',
                      DomainSystemKind.openSourceTool => 'Keycloak IAM',
                      DomainSystemKind.webFront => 'Portail Client Web',
                      DomainSystemKind.mobileApp => 'App Mobile Boutique',
                      DomainSystemKind.bff => 'BFF Mobile Checkout',
                      DomainSystemKind.microservice => 'Service Commandes',
                      DomainSystemKind.monolith => 'Cœur ERP Commandes',
                    },
                  ),
                  validator: (val) => (val?.trim().length ?? 0) < 2
                      ? 'Le nom doit contenir au moins 2 caractères.'
                      : null,
                  onChanged: (val) {
                    if (!_codeManuallyEdited && val.trim().isNotEmpty) {
                      _codeCtrl.text = SystemsServicesAiAgent.normalizeKebabCode(
                        val,
                      );
                    }
                  },
                ),
                TextFormField(
                  key: const ValueKey('systems-services-dialog-code'),
                  controller: _codeCtrl,
                  decoration: InputDecoration(
                    labelText: 'Code technique (kebab-case) *',
                    hintText: _kind.isOpenSourceTool
                        ? 'keycloak-iam'
                        : 'stripe-psp',
                    errorText: _duplicateError,
                  ),
                  validator: _validateCode,
                  onChanged: (_) {
                    _codeManuallyEdited = true;
                    if (_duplicateError != null) {
                      setState(() => _duplicateError = null);
                    }
                  },
                ),
                TextFormField(
                  key: const ValueKey('systems-services-dialog-vendor'),
                  controller: _vendorCtrl,
                  decoration: InputDecoration(
                    labelText: _kind.isExternal
                        ? 'Fournisseur / Éditeur tiers (ex. Stripe, SendGrid, SAP)'
                        : (_kind.isOpenSourceTool
                              ? 'Projet / Communauté / Licence (ex. Apache 2.0, MIT)'
                              : 'Éditeur / Équipe responsable (optionnel)'),
                    hintText: _kind.isExternal
                        ? 'Stripe'
                        : (_kind.isOpenSourceTool ? 'Apache 2.0' : ''),
                  ),
                ),
                if (!_kind.isOffTheShelf &&
                    widget.catalog.techStacks.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    key: const ValueKey('systems-services-dialog-stack'),
                    initialValue: _techStackId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Stack technique (optionnel)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Aucune stack spécifique'),
                      ),
                      for (final stack in widget.catalog.techStacks)
                        DropdownMenuItem<String?>(
                          value: stack.id,
                          child: Text(
                            '${stack.name} (${stack.code})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (val) => setState(() => _techStackId = val),
                  ),
                TextFormField(
                  key: const ValueKey('systems-services-dialog-description'),
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description / Responsabilité',
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('systems-services-dialog-active'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Actif'),
                  value: _isActive,
                  onChanged: (val) => setState(() => _isActive = val),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('systems-services-dialog-save-btn'),
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
