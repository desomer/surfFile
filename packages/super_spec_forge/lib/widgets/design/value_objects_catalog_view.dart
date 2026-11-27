/// Page Design « Catalogue des Value Objects » (Architecture Hexagonale)
/// ([ValueObjectsCatalogView]) : double portée Shared Kernel / Domaine,
/// chat IA dédié, presets DDD, détection Primitive Obsession et éditeur complet.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart'
    show VibeChatAttachment;

import '../../models/business_object_spec.dart';
import '../../models/domain_catalog.dart';
import '../../models/value_object_spec.dart';
import '../../services/exporters/spec_super_designer_exporter.dart';
import '../../services/spec_forge_controller.dart';
import '../../services/value_object_primitive_detector.dart';
import '../spec_split_handle.dart';
import '../workspace/attribute_constraints_editor.dart';
import 'design_domain_breadcrumb.dart';
import 'value_object_editor_dialog.dart';
import 'value_objects_chat_pane.dart';

/// Atelier complet de conception et gouvernance des Value Objects hexagonaux
/// (Shared Kernel transverse + Value Objects par domaine fonctionnel).
class ValueObjectsCatalogView extends StatefulWidget {
  /// Crée la vue connectée au [controller].
  const ValueObjectsCatalogView({
    required this.controller,
    required this.onBack,
    required this.onManageDomains,
    this.initialDomainId,
    this.initialScope,
    this.onDomainChanged,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Retour au menu Design.
  final VoidCallback onBack;

  /// Ouvre la gestion des domaines.
  final VoidCallback onManageDomains;

  /// Domaine présélectionné à l'ouverture.
  final String? initialDomainId;

  /// Portée présélectionnée (`domain` par défaut si au moins un domaine existe, sinon `shared`).
  final ValueObjectScope? initialScope;

  /// Notifie le parent d'un changement de domaine.
  final ValueChanged<String?>? onDomainChanged;

  /// Sélecteurs injectables de pièces jointes (tests).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<ValueObjectsCatalogView> createState() =>
      _ValueObjectsCatalogViewState();
}

class _ValueObjectsCatalogViewState extends State<ValueObjectsCatalogView> {
  static const double _defaultChatFraction = 0.34;

  final GlobalKey _splitKey = GlobalKey();
  double _chatFraction = _defaultChatFraction;
  double _dragOffset = SpecSplitHandle.width / 2;

  String? _selectedDomainId;
  late ValueObjectScope _scope;
  String? _selectedVoId;
  String _searchQuery = '';
  ValueObjectKind? _kindFilter;

  @override
  void initState() {
    super.initState();
    final domains = widget.controller.domainCatalog.domains;
    _selectedDomainId =
        widget.initialDomainId ??
        widget.controller.activeDesignDomainId ??
        domains.firstOrNull?.id;
    _scope =
        widget.initialScope ??
        (domains.isEmpty ? ValueObjectScope.shared : ValueObjectScope.domain);
  }

  @override
  void didUpdateWidget(ValueObjectsCatalogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDomainId != null &&
        widget.initialDomainId != oldWidget.initialDomainId) {
      _selectedDomainId = widget.initialDomainId;
    }
  }

  FunctionalDomain? _resolveSelectedDomain(DomainCatalog catalog) {
    final domains = catalog.domains;
    if (domains.isEmpty) return null;
    final effectiveId =
        _selectedDomainId ?? widget.controller.activeDesignDomainId;
    return domains.where((d) => d.id == effectiveId).firstOrNull ??
        domains.first;
  }

  Future<void> _openEditor({
    ValueObjectSpec? existing,
    required ValueObjectScope scope,
    required FunctionalDomain? domain,
  }) async {
    final available = widget.controller.domainCatalog
        .resolvedValueObjectsForDomain(domain?.id);
    final result = await showValueObjectEditorDialog(
      context,
      existing: existing,
      availableValueObjects: available,
      scopeLabel: scope == ValueObjectScope.shared
          ? 'Shared Kernel'
          : domain?.name,
    );
    if (result == null || !mounted) return;
    try {
      await widget.controller.upsertValueObject(
        result,
        scope: scope,
        domainId: domain?.id,
      );
      if (mounted) {
        setState(() => _selectedVoId = result.id);
      }
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _duplicateVo(
    ValueObjectSpec vo, {
    required ValueObjectScope scope,
    required FunctionalDomain? domain,
  }) async {
    final baseName = '${vo.technicalName}Copy';
    final existing = scope == ValueObjectScope.shared
        ? widget.controller.domainCatalog.sharedValueObjects
        : (domain?.valueObjects ?? const <ValueObjectSpec>[]);
    final taken = {for (final item in existing) item.technicalName.toLowerCase()};
    var tech = baseName;
    for (var i = 2; taken.contains(tech.toLowerCase()); i++) {
      tech = '$baseName$i';
    }
    final copy = vo.copyWith(
      id: 'vo_${shortid.generate()}',
      technicalName: tech,
      name: '${vo.name} (copie)',
    );
    await widget.controller.upsertValueObject(
      copy,
      scope: scope,
      domainId: domain?.id,
    );
    if (mounted) setState(() => _selectedVoId = copy.id);
  }

  Future<void> _confirmDeleteVo(
    ValueObjectSpec vo, {
    required ValueObjectScope scope,
    required FunctionalDomain? domain,
    required List<ValueObjectUsageRef> usages,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Supprimer ${vo.technicalName} ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(
              'Le Value Object « ${vo.name} » (${vo.technicalName}) sera retiré de ${scope == ValueObjectScope.shared ? 'Shared Kernel' : '« ${domain?.name ?? ''} »'}.',
            ),
            if (usages.isNotEmpty)
              Text(
                'Attention : ce Value Object est actuellement référencé dans ${usages.length} attribut(s) : '
                '${usages.take(5).map((u) => '${u.entryName}.${u.attributeName}').join(', ')}'
                '${usages.length > 5 ? '…' : ''}.',
                style: TextStyle(
                  color: Theme.of(dialogCtx).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('vo-delete-confirm-btn'),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.deleteValueObject(
      vo.id,
      scope: scope,
      domainId: domain?.id,
    );
    if (mounted && _selectedVoId == vo.id) {
      setState(() => _selectedVoId = null);
    }
  }

  Future<void> _openPresetsDialog({
    required ValueObjectScope scope,
    required FunctionalDomain? domain,
  }) async {
    final existing = scope == ValueObjectScope.shared
        ? widget.controller.domainCatalog.sharedValueObjects
        : (domain?.valueObjects ?? const <ValueObjectSpec>[]);
    final taken = {for (final v in existing) v.technicalName.toLowerCase()};
    final presets = ValueObjectPresets.standardPresets;
    final selected = <String>{
      for (final p in presets)
        if (!taken.contains(p.technicalName.toLowerCase())) p.id,
    };

    final chosen = await showDialog<List<ValueObjectSpec>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AlertDialog(
          title: Text(
            'Importer des presets DDD (${scope == ValueObjectScope.shared ? 'Shared Kernel' : domain?.name ?? ''})',
          ),
          content: SizedBox(
            width: 560,
            height: 440,
            child: ListView.builder(
              itemCount: presets.length,
              itemBuilder: (_, index) {
                final p = presets[index];
                final alreadyPresent = taken.contains(
                  p.technicalName.toLowerCase(),
                );
                return CheckboxListTile(
                  key: ValueKey('vo-preset-${p.technicalName}'),
                  dense: true,
                  value: alreadyPresent || selected.contains(p.id),
                  onChanged: alreadyPresent
                      ? null
                      : (v) => setLocal(() {
                          if (v == true) {
                            selected.add(p.id);
                          } else {
                            selected.remove(p.id);
                          }
                        }),
                  title: Text(
                    '${p.technicalName} — ${p.name}${alreadyPresent ? ' (déjà présent)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${p.kind.label} · ${p.formatStructureSummary()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('vo-presets-import-confirm'),
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogCtx, [
                      for (final p in presets)
                        if (selected.contains(p.id)) p,
                    ]),
              child: Text('Importer (${selected.length})'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    final count = await widget.controller.importValueObjectPresets(
      chosen,
      scope: scope,
      domainId: domain?.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$count Value Object(s) importé(s).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openPrimitiveAuditDialog(FunctionalDomain domain) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => ListenableBuilder(
        listenable: widget.controller,
        builder: (dialogCtx, _) {
          final catalog = widget.controller.domainCatalog;
          final suggestions = ValueObjectPrimitiveDetector.detectForDomain(
            catalog,
            domain.id,
          );
          final available = catalog.resolvedValueObjectsForDomain(domain.id);
          return AlertDialog(
            title: Text(
              'Audit Primitive Obsession — ${domain.name} (${suggestions.length})',
            ),
            content: SizedBox(
              width: 680,
              height: 460,
              child: suggestions.isEmpty
                  ? const Center(
                      child: Text(
                        'Aucun candidat Primitive Obsession détecté sur les modèles du domaine.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: suggestions.length,
                      itemBuilder: (_, index) {
                        final s = suggestions[index];
                        final isExisting =
                            s.matchKind ==
                            PrimitiveObsessionMatchKind.existingCatalogVo;
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              '${s.entryName}.${s.attribute.name} (${s.attribute.type.dslKeyword}) → ${s.proposedSpec.technicalName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(s.reason),
                            trailing: FilledButton.tonal(
                              key: ValueKey(
                                'vo-audit-apply-${s.entryId}-${s.attribute.id}',
                              ),
                              onPressed: () async {
                                final result =
                                    await showPromoteToValueObjectDialog(
                                      dialogCtx,
                                      attribute: s.attribute,
                                      availableValueObjects: available,
                                      suggestedSpec: s.proposedSpec,
                                      suggestedExisting: s.matchedVo,
                                      initialScope: s.suggestedScope,
                                    );
                                if (result == null) return;
                                await widget.controller
                                    .promoteAttributeToValueObject(
                                      domainId: domain.id,
                                      entryId: s.entryId,
                                      attributePath: s.attributePath,
                                      valueObject: result.valueObject,
                                      scope: result.scope,
                                      createIfMissing: !result.useExisting,
                                    );
                              },
                              child: Text(
                                isExisting ? 'Réutiliser' : 'Promouvoir',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
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
        final selectedDomain = _resolveSelectedDomain(catalog);
        final effectiveScope =
            (_scope == ValueObjectScope.domain && selectedDomain == null)
            ? ValueObjectScope.shared
            : _scope;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesignDomainBreadcrumbBar(
              domains: domains,
              selectedDomain: selectedDomain,
              onDomainSelected: (domain) {
                setState(() {
                  _selectedDomainId = domain.id;
                  if (_scope == ValueObjectScope.domain) {
                    _selectedVoId = null;
                  }
                });
                widget.controller.setActiveDesignDomainId(domain.id);
                widget.onDomainChanged?.call(domain.id);
              },
              segments: [
                const DesignBreadcrumbSegment(
                  key: ValueKey('vo-catalog-crumb'),
                  label: 'Catalogue des Value Objects',
                  isParent: true,
                ),
                DesignBreadcrumbSegment(
                  label: effectiveScope == ValueObjectScope.shared
                      ? 'Shared Kernel'
                      : (selectedDomain?.name ?? 'Domaine'),
                  isSecondary: true,
                ),
              ],
            ),
            Expanded(
              child: _buildSplitWorkspace(
                context,
                catalog: catalog,
                selectedDomain: selectedDomain,
                effectiveScope: effectiveScope,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSplitWorkspace(
    BuildContext context, {
    required DomainCatalog catalog,
    required FunctionalDomain? selectedDomain,
    required ValueObjectScope effectiveScope,
  }) {
    final colors = Theme.of(context).colorScheme;
    final chatPane = ValueObjectsChatPane(
      key: ValueKey(
        '${effectiveScope.name}/${effectiveScope == ValueObjectScope.domain ? selectedDomain?.id ?? '' : 'shared'}',
      ),
      controller: widget.controller,
      scope: effectiveScope,
      domain: selectedDomain,
      onCollapse: () => setState(() => _chatFraction = 0),
      pickAttachments: widget.pickAttachments,
      pasteAttachments: widget.pasteAttachments,
      hasClipboardMedia: widget.hasClipboardMedia,
      pasteClipboardMedia: widget.pasteClipboardMedia,
    );
    final rightPane = _buildCatalogWorkspace(
      context,
      catalog: catalog,
      selectedDomain: selectedDomain,
      effectiveScope: effectiveScope,
    );

    if (_chatFraction <= 0) {
      return Row(
        children: [
          Container(
            key: const ValueKey('vo-chat-collapsed'),
            width: 38,
            color: colors.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              spacing: 8,
              children: [
                IconButton(
                  key: const ValueKey('vo-chat-expand'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Afficher le chat IA',
                  onPressed: () =>
                      setState(() => _chatFraction = _defaultChatFraction),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                Icon(
                  Icons.diamond_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: rightPane),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, bounds) {
        final totalWidth = bounds.maxWidth;
        final minChat = 260.0;
        final minRight = 460.0;
        final usable = math.max(0.0, totalWidth - SpecSplitHandle.width);
        final chatWidth = (usable * _chatFraction)
            .clamp(
              math.min(minChat, usable),
              math.max(minChat, usable - minRight),
            )
            .toDouble();
        return Row(
          key: _splitKey,
          children: [
            SizedBox(width: chatWidth, child: chatPane),
            SpecSplitHandle(
              onHorizontalDragDown: (details) {
                final box =
                    _splitKey.currentContext?.findRenderObject() as RenderBox?;
                if (box == null) return;
                final localX = box.globalToLocal(details.globalPosition).dx;
                _dragOffset = localX - chatWidth;
              },
              onHorizontalDragUpdate: (details) {
                final box =
                    _splitKey.currentContext?.findRenderObject() as RenderBox?;
                if (box == null || usable <= 0) return;
                final localX = box.globalToLocal(details.globalPosition).dx;
                final next = ((localX - _dragOffset) / usable).clamp(0.18, 0.55);
                setState(() => _chatFraction = next);
              },
              onDoubleTap: () =>
                  setState(() => _chatFraction = _defaultChatFraction),
            ),
            Expanded(child: rightPane),
          ],
        );
      },
    );
  }

  Widget _buildCatalogWorkspace(
    BuildContext context, {
    required DomainCatalog catalog,
    required FunctionalDomain? selectedDomain,
    required ValueObjectScope effectiveScope,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scopeVos = effectiveScope == ValueObjectScope.shared
        ? catalog.sharedValueObjects
        : (selectedDomain?.valueObjects ?? const <ValueObjectSpec>[]);

    final query = _searchQuery.trim().toLowerCase();
    final filteredVos = [
      for (final vo in scopeVos)
        if ((_kindFilter == null || vo.kind == _kindFilter) &&
            (query.isEmpty ||
                vo.technicalName.toLowerCase().contains(query) ||
                vo.name.toLowerCase().contains(query) ||
                vo.category.toLowerCase().contains(query) ||
                vo.description.toLowerCase().contains(query)))
          vo,
    ];

    final selectedVo =
        filteredVos.where((v) => v.id == _selectedVoId).firstOrNull ??
        scopeVos.where((v) => v.id == _selectedVoId).firstOrNull ??
        filteredVos.firstOrNull;

    final domainCount = selectedDomain?.valueObjects.length ?? 0;
    final sharedCount = catalog.sharedValueObjects.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.surfaceContainerLowest,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<ValueObjectScope>(
                key: const ValueKey('vo-scope-segmented'),
                segments: [
                  ButtonSegment(
                    value: ValueObjectScope.domain,
                    enabled: selectedDomain != null,
                    icon: const Icon(Icons.domain_rounded, size: 16),
                    label: Text(
                      selectedDomain == null
                          ? 'Domaine (aucun)'
                          : '${selectedDomain.name} ($domainCount)',
                    ),
                  ),
                  ButtonSegment(
                    value: ValueObjectScope.shared,
                    icon: const Icon(Icons.hub_outlined, size: 16),
                    label: Text('Shared Kernel ($sharedCount)'),
                  ),
                ],
                selected: {effectiveScope},
                onSelectionChanged: (sel) => setState(() {
                  _scope = sel.first;
                  _selectedVoId = null;
                }),
              ),
              SizedBox(
                width: 210,
                child: TextField(
                  key: const ValueKey('vo-search-field'),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    hintText: 'Filtrer…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              DropdownButton<ValueObjectKind?>(
                key: const ValueKey('vo-kind-filter'),
                value: _kindFilter,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Toutes formes')),
                  DropdownMenuItem(
                    value: ValueObjectKind.scalar,
                    child: Text('Scalaires'),
                  ),
                  DropdownMenuItem(
                    value: ValueObjectKind.composite,
                    child: Text('Composites'),
                  ),
                ],
                onChanged: (v) => setState(() => _kindFilter = v),
              ),
              FilledButton.icon(
                key: const ValueKey('vo-add-btn'),
                onPressed: () => _openEditor(
                  scope: effectiveScope,
                  domain: selectedDomain,
                ),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Nouveau VO'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('vo-presets-btn'),
                onPressed: () => _openPresetsDialog(
                  scope: effectiveScope,
                  domain: selectedDomain,
                ),
                icon: const Icon(Icons.auto_awesome_mosaic_outlined, size: 16),
                label: const Text('Presets DDD'),
              ),
              if (effectiveScope == ValueObjectScope.domain &&
                  selectedDomain != null)
                OutlinedButton.icon(
                  key: const ValueKey('vo-audit-primitive-btn'),
                  onPressed: () => _openPrimitiveAuditDialog(selectedDomain),
                  icon: const Icon(Icons.troubleshoot_rounded, size: 16),
                  label: const Text('Audit Primitive Obsession'),
                ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 300,
                child: _buildMasterList(
                  context,
                  catalog: catalog,
                  filteredVos: filteredVos,
                  selectedVo: selectedVo,
                  effectiveScope: effectiveScope,
                  selectedDomain: selectedDomain,
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: selectedVo == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 10,
                            children: [
                              Icon(
                                Icons.diamond_outlined,
                                size: 40,
                                color: colors.outline,
                              ),
                              Text(
                                'Aucun Value Object dans ${effectiveScope == ValueObjectScope.shared ? 'le Shared Kernel' : '« ${selectedDomain?.name ?? ''} »'}.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () => _openPresetsDialog(
                                      scope: effectiveScope,
                                      domain: selectedDomain,
                                    ),
                                    icon: const Icon(
                                      Icons.auto_awesome_mosaic_outlined,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Importer des presets DDD',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _openEditor(
                                      scope: effectiveScope,
                                      domain: selectedDomain,
                                    ),
                                    icon: const Icon(Icons.add_rounded, size: 16),
                                    label: const Text('Créer manuellement'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildDetailPane(
                        context,
                        catalog: catalog,
                        vo: selectedVo,
                        effectiveScope: effectiveScope,
                        selectedDomain: selectedDomain,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMasterList(
    BuildContext context, {
    required DomainCatalog catalog,
    required List<ValueObjectSpec> filteredVos,
    required ValueObjectSpec? selectedVo,
    required ValueObjectScope effectiveScope,
    required FunctionalDomain? selectedDomain,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final inheritedShared =
        effectiveScope == ValueObjectScope.domain && selectedDomain != null
        ? [
            for (final svo in catalog.sharedValueObjects)
              if (!selectedDomain.valueObjects.any(
                (d) =>
                    d.technicalName.toLowerCase() ==
                    svo.technicalName.toLowerCase(),
              ))
                svo,
          ]
        : const <ValueObjectSpec>[];

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        if (filteredVos.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Aucun Value Object correspondant.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final vo in filteredVos)
            Builder(
              builder: (context) {
                final isSelected = selectedVo?.id == vo.id;
                final usageCount = ValueObjectPrimitiveDetector.findUsages(
                  catalog,
                  vo,
                  scope: effectiveScope,
                  ownerDomainId: selectedDomain?.id,
                ).length;
                return Card(
                  key: ValueKey('vo-list-item-${vo.technicalName}'),
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 6),
                  color: isSelected
                      ? colors.primaryContainer.withValues(alpha: 0.55)
                      : colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isSelected
                          ? colors.primary
                          : colors.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    onTap: () => setState(() => _selectedVoId = vo.id),
                    leading: Icon(
                      vo.isComposite
                          ? Icons.view_module_outlined
                          : Icons.diamond_outlined,
                      size: 18,
                      color: isSelected ? colors.primary : colors.onSurface,
                    ),
                    title: Text(
                      vo.technicalName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${vo.name} · ${vo.kind.label}'
                      '${usageCount > 0 ? ' · $usageCount usage(s)' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
        if (inheritedShared.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Hérités du Shared Kernel (${inheritedShared.length})',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final svo in inheritedShared)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                Icons.hub_outlined,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              title: Text(svo.technicalName),
              subtitle: Text(
                svo.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 16),
              onTap: () => setState(() {
                _scope = ValueObjectScope.shared;
                _selectedVoId = svo.id;
              }),
            ),
        ],
      ],
    );
  }

  Widget _buildDetailPane(
    BuildContext context, {
    required DomainCatalog catalog,
    required ValueObjectSpec vo,
    required ValueObjectScope effectiveScope,
    required FunctionalDomain? selectedDomain,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final usages = ValueObjectPrimitiveDetector.findUsages(
      catalog,
      vo,
      scope: effectiveScope,
      ownerDomainId: selectedDomain?.id,
    );
    final visibleVos = catalog.valueObjectsForDomain(selectedDomain?.id);
    final schemaMap = SpecSuperDesignerExporter.valueObjectToJsonSchema(
      vo,
      valueObjects: visibleVos,
      scope: effectiveScope,
    );

    return ListView(
      key: ValueKey('vo-detail-${vo.id}'),
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        vo.technicalName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(vo.kind.label),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(effectiveScope.label),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${vo.category} · v${vo.version}'),
                      ),
                    ],
                  ),
                  Text(
                    vo.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (vo.description.isNotEmpty)
                    Text(vo.description, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            Wrap(
              spacing: 4,
              children: [
                IconButton(
                  key: const ValueKey('vo-detail-edit-btn'),
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openEditor(
                    existing: vo,
                    scope: effectiveScope,
                    domain: selectedDomain,
                  ),
                ),
                IconButton(
                  key: const ValueKey('vo-detail-duplicate-btn'),
                  tooltip: 'Dupliquer',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () => _duplicateVo(
                    vo,
                    scope: effectiveScope,
                    domain: selectedDomain,
                  ),
                ),
                if (effectiveScope == ValueObjectScope.domain &&
                    selectedDomain != null)
                  IconButton(
                    key: const ValueKey('vo-detail-promote-shared-btn'),
                    tooltip: 'Promouvoir vers le Shared Kernel',
                    icon: const Icon(Icons.drive_file_move_outlined),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      try {
                        await widget.controller.moveValueObjectScope(
                          vo.id,
                          fromScope: ValueObjectScope.domain,
                          fromDomainId: selectedDomain.id,
                          toScope: ValueObjectScope.shared,
                        );
                        if (mounted) {
                          setState(() {
                            _scope = ValueObjectScope.shared;
                            _selectedVoId = vo.id;
                          });
                        }
                      } on FormatException catch (e) {
                        messenger
                          ?..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    },
                  )
                else if (effectiveScope == ValueObjectScope.shared &&
                    selectedDomain != null)
                  IconButton(
                    key: const ValueKey('vo-detail-move-domain-btn'),
                    tooltip: 'Déplacer vers ${selectedDomain.name}',
                    icon: const Icon(Icons.subdirectory_arrow_right_rounded),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      try {
                        await widget.controller.moveValueObjectScope(
                          vo.id,
                          fromScope: ValueObjectScope.shared,
                          toScope: ValueObjectScope.domain,
                          toDomainId: selectedDomain.id,
                        );
                        if (mounted) {
                          setState(() {
                            _scope = ValueObjectScope.domain;
                            _selectedVoId = vo.id;
                          });
                        }
                      } on FormatException catch (e) {
                        messenger
                          ?..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    },
                  ),
                IconButton(
                  key: const ValueKey('vo-detail-delete-btn'),
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _confirmDeleteVo(
                    vo,
                    scope: effectiveScope,
                    domain: selectedDomain,
                    usages: usages,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: colors.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(
                  vo.isScalar
                      ? 'Structure scalaire & validation'
                      : 'Champs immuables & règles inter-champs',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (vo.isScalar) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          'Primitif : ${vo.primitiveType.label} (${vo.primitiveType.dslKeyword})',
                        ),
                      ),
                      for (final badge in vo.schemaConstraints.describeBadges())
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(badge),
                        ),
                      for (final rule in vo.normalizationRules)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.cleaning_services_outlined, size: 14),
                          label: Text(rule),
                        ),
                    ],
                  ),
                  if (vo.enumValues.isNotEmpty)
                    Text('Valeurs autorisées : ${vo.enumValues.join(', ')}'),
                ] else ...[
                  for (final f in vo.fields)
                    Row(
                      spacing: 8,
                      children: [
                        const Icon(Icons.subdirectory_arrow_right_rounded, size: 15),
                        Text(
                          f.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            '${f.type == BusinessAttributeType.valueObject ? 'VO(${f.valueObjectId})' : f.type.dslKeyword}${f.required ? '!' : ''}',
                          ),
                        ),
                        if (f.description.isNotEmpty)
                          Expanded(
                            child: Text(
                              f.description,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (vo.crossFieldRules.isNotEmpty) ...[
                    const Divider(),
                    Text(
                      'Règles inter-champs',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    for (final rule in vo.crossFieldRules) Text('• $rule'),
                  ],
                ],
                if (vo.constraints.isNotEmpty)
                  Text(
                    'Invariants : ${vo.constraints}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          color: colors.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(
                  'Exemples valides (${vo.validExamples.length}) & Contre-exemples TDD (${vo.invalidExamples.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (vo.examples.isEmpty)
                  Text(
                    'Aucun exemple renseigné.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  )
                else
                  for (final ex in vo.examples)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Icon(
                          ex.isValid
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 16,
                          color: ex.isValid ? Colors.green : colors.error,
                        ),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: theme.textTheme.bodySmall,
                              children: [
                                TextSpan(
                                  text: ex.value.isEmpty
                                      ? '(vide)'
                                      : ex.value,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (ex.reason.isNotEmpty)
                                  TextSpan(
                                    text: ' — ${ex.reason}',
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          color: colors.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Text(
                  'Utilisations dans les modèles (${usages.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (usages.isEmpty)
                  Text(
                    'Non encore référencé par un modèle.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final u in usages)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            '${u.domainName} › ${u.entryName}.${u.attributeName}',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        AttributeSchemaPreviewCard(
          title: 'Aperçu JSON Schema Draft 2020-12 (${vo.technicalName})',
          schemaMap: schemaMap,
          badges: [
            vo.kind.label,
            effectiveScope.label,
            '${vo.validExamples.length} valide(s)',
            '${vo.invalidExamples.length} invalide(s)',
          ],
        ),
      ],
    );
  }
}
