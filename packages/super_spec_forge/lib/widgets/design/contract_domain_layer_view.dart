/// Page dédiée à la couche Domain (Architecture Hexagonale) d'un objet métier
/// côté Design : volet de chat IA unifié à gauche et les 7 onglets structurés
/// (`Invariants`, `State changing`, `Query`, `Policy Services`, `Factory`,
/// `Domain events`, `Persistence policy`) avec édition manuelle à droite
/// ([ContractDomainLayerView]).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart'
    show VibeChatAttachment;
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../../models/domain_contracts.dart';
import '../../models/domain_layer_spec.dart';
import '../../services/spec_forge_controller.dart';
import '../spec_split_handle.dart';
import 'contract_domain_layer_chat_pane.dart';
import 'contract_entry_view.dart' show contractTypeColor;

List<String> _splitLinesOrCommas(String raw) => [
  for (final part in raw.split(RegExp(r'[\r\n,]+')))
    if (part.trim().isNotEmpty) part.trim(),
];

List<String> _splitLines(String raw) => [
  for (final line in raw.split(RegExp(r'\r?\n')))
    if (line.trim().isNotEmpty) line.trim(),
];

String _joinLines(List<String> items) => items.join('\n');

/// Atelier de la couche Domain (Architecture Hexagonale) d'une entrée [entry]
/// du domaine [domainId].
class ContractDomainLayerView extends StatefulWidget {
  /// Crée la vue Couche Domain pour [entry].
  const ContractDomainLayerView({
    required this.controller,
    required this.domainId,
    required this.document,
    required this.entry,
    required this.onBackToModel,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Identifiant du domaine propriétaire.
  final String domainId;

  /// Document courant du domaine.
  final DomainContracts document;

  /// Entrée DSL ciblée.
  final JsonNode entry;

  /// Retourne à la fiche principale de l'objet métier (niveau 1).
  final VoidCallback onBackToModel;

  /// Sélecteurs optionnels pour le chat IA (tests).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<ContractDomainLayerView> createState() =>
      _ContractDomainLayerViewState();
}

class _ContractDomainLayerViewState extends State<ContractDomainLayerView>
    with SingleTickerProviderStateMixin {
  static const double _defaultChatFraction = 0.36;

  final GlobalKey _splitKey = GlobalKey();
  double _chatFraction = _defaultChatFraction;
  double _dragOffset = SpecSplitHandle.width / 2;
  late final TabController _tabController;

  HexagonalDomainLayerSpec get _layer =>
      widget.document.domainLayerFor(widget.entry);

  DomainLayerTab get _activeTab => DomainLayerTab.values[_tabController.index];

  @override
  void initState() {
    super.initState();
    final initialTab = widget.controller.domainLayerActiveTab(
      widget.domainId,
      widget.entry.id,
    );
    _tabController = TabController(
      length: DomainLayerTab.values.length,
      vsync: this,
      initialIndex: initialTab.index,
    );
    _tabController.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(ContractDomainLayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final storedTab = widget.controller.domainLayerActiveTab(
      widget.domainId,
      widget.entry.id,
    );
    if (_tabController.index != storedTab.index) {
      _tabController.index = storedTab.index;
    }
  }

  void _onTabChanged() {
    if (!mounted) return;
    final nextTab = DomainLayerTab.values[_tabController.index];
    widget.controller.setDomainLayerActiveTab(
      widget.domainId,
      widget.entry.id,
      nextTab,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _saveLayer(HexagonalDomainLayerSpec next) async {
    try {
      next.validate();
      await widget.controller.updateDomainModelLayer(
        widget.domainId,
        widget.entry.id,
        next,
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(e is FormatException ? e.message : '$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final details =
        widget.document.details[widget.entry.id] ?? ContractDetails.defaults;
    final object = widget.document.objectFor(widget.entry);
    final layer = _layer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme, colors, details, object.totalAttributeCount),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) {
              const minLeading = 250.0;
              const minTrailing = 440.0;
              final collapsed = _chatFraction <= 0;
              final available = math.max(
                0.0,
                bounds.maxWidth - SpecSplitHandle.width,
              );
              final roomy = available > minLeading + minTrailing;
              final minFrac = roomy ? minLeading / available : 0.2;
              final maxFrac = roomy
                  ? (available - minTrailing) / available
                  : 0.72;
              final leadingWidth = collapsed
                  ? 38.0
                  : available * _chatFraction.clamp(minFrac, maxFrac);

              return Row(
                key: _splitKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (collapsed)
                    Container(
                      key: const ValueKey('domain-layer-chat-collapsed'),
                      width: 38,
                      color: colors.surfaceContainerLow,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        spacing: 8,
                        children: [
                          IconButton(
                            key: const ValueKey('domain-layer-chat-expand'),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Afficher le chat IA',
                            onPressed: () => setState(
                              () => _chatFraction = _defaultChatFraction,
                            ),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                          Icon(
                            Icons.hexagon_outlined,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      key: const ValueKey('domain-layer-chat-pane'),
                      width: leadingWidth,
                      child: ContractDomainLayerChatPane(
                        key: ValueKey(
                          'domain-layer-chat-${widget.domainId}/${widget.entry.id}',
                        ),
                        controller: widget.controller,
                        domainId: widget.domainId,
                        entryId: widget.entry.id,
                        modelName: widget.entry.name,
                        activeTab: _activeTab,
                        onCollapse: () => setState(() => _chatFraction = 0),
                        pickAttachments: widget.pickAttachments,
                        pasteAttachments: widget.pasteAttachments,
                        hasClipboardMedia: widget.hasClipboardMedia,
                        pasteClipboardMedia: widget.pasteClipboardMedia,
                      ),
                    ),
                  SpecSplitHandle(
                    key: const ValueKey('domain-layer-split-handle'),
                    onDoubleTap: () =>
                        setState(() => _chatFraction = _defaultChatFraction),
                    onHorizontalDragDown: (drag) {
                      final box =
                          _splitKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      _dragOffset = box == null || collapsed
                          ? SpecSplitHandle.width / 2
                          : (box.globalToLocal(drag.globalPosition).dx -
                                    leadingWidth)
                                .clamp(0.0, SpecSplitHandle.width);
                    },
                    onHorizontalDragUpdate: (drag) {
                      final box =
                          _splitKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box == null || available <= 0) return;
                      final width =
                          box.globalToLocal(drag.globalPosition).dx -
                          _dragOffset;
                      if (collapsed) {
                        if (width > 60) {
                          setState(
                            () => _chatFraction = (width / available).clamp(
                              minFrac,
                              maxFrac,
                            ),
                          );
                        }
                      } else if (width < 140) {
                        setState(() => _chatFraction = 0);
                      } else {
                        setState(
                          () => _chatFraction = (width / available).clamp(
                            minFrac,
                            maxFrac,
                          ),
                        );
                      }
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ColoredBox(
                          color: colors.surfaceContainerLow,
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 11,
                            ),
                            indicatorColor: colors.primary,
                            indicatorWeight: 3,
                            tabs: [
                              for (final tab in DomainLayerTab.values)
                                Tab(
                                  key: ValueKey('domain-layer-tab-${tab.name}'),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    spacing: 6,
                                    children: [
                                      Text(tab.label),
                                      if (layer.countForTab(tab) > 0)
                                        _CountBadge(
                                          count: layer.countForTab(tab),
                                          colors: colors,
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildInvariantsTab(theme, colors, layer),
                              _buildStateChangingTab(theme, colors, layer),
                              _buildQueryTab(theme, colors, layer),
                              _buildPolicyServicesTab(theme, colors, layer),
                              _buildFactoryTab(theme, colors, layer),
                              _buildDomainEventsTab(theme, colors, layer),
                              _buildPersistencePolicyTab(theme, colors, layer),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildHeader(
    ThemeData theme,
    ColorScheme colors,
    ContractDetails details,
    int attributeCount,
  ) {
    final entry = widget.entry;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        spacing: 12,
        children: [
          Icon(Icons.hexagon_rounded, size: 26, color: colors.primary),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    Flexible(
                      child: Text(
                        '${entry.name} · Couche Domain',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        entry.type,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: contractTypeColor(entry.type),
                      side: BorderSide.none,
                    ),
                  ],
                ),
                Text(
                  '${details.title.isEmpty ? 'Architecture Hexagonale' : details.title} '
                  '· $attributeCount attribut(s) · v${details.version}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('domain-layer-back-to-model-btn'),
            onPressed: widget.onBackToModel,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Fiche modèle'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabScaffold({
    required ThemeData theme,
    required ColorScheme colors,
    required DomainLayerTab tab,
    required String addButtonLabel,
    required VoidCallback onAdd,
    required bool isEmpty,
    required String emptyHint,
    required List<Widget> children,
    List<Widget> extraHeaderActions = const <Widget>[],
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tab.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    tab.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ...extraHeaderActions,
                  FilledButton.tonalIcon(
                    key: ValueKey('domain-layer-add-${tab.name}'),
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(addButtonLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          size: 32,
                          color: colors.outline,
                        ),
                        Text(
                          emptyHint,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: children.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => children[index],
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Invariants (invariant_behaviors)
  // ---------------------------------------------------------------------------

  Widget _buildInvariantsTab(
    ThemeData theme,
    ColorScheme colors,
    HexagonalDomainLayerSpec layer,
  ) {
    return _buildTabScaffold(
      theme: theme,
      colors: colors,
      tab: DomainLayerTab.invariants,
      addButtonLabel: 'Ajouter un invariant',
      onAdd: () => _editInvariant(layer),
      isEmpty: layer.invariants.isEmpty,
      emptyHint: 'Aucun invariant défini (validateXXX()).\nUtilisez le chat IA à gauche ou cliquez sur « Ajouter un invariant ».',
      children: [
        for (final item in layer.invariants)
          _SectionCard(
            itemId: item.id,
            prefixBadge: item.code.isEmpty ? null : item.code,
            titleFr: item.title,
            descriptionFr: item.description,
            rules: item.effectiveRules,
            associatedMethods: item.effectiveAssociatedMethods,
            tags: [
              for (final attr in item.relatedAttributes) 'attribut: $attr',
              if (item.violationError.isNotEmpty)
                'erreur: ${item.violationError}',
            ],
            onEdit: () => _editInvariant(layer, existing: item),
            onDelete: () => _saveLayer(
              layer.copyWith(
                invariants: [
                  for (final x in layer.invariants)
                    if (x.id != item.id) x,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editInvariant(
    HexagonalDomainLayerSpec layer, {
    DomainInvariantSpec? existing,
  }) async {
    final values = await _FieldFormDialog.show(
      context,
      title: existing == null
          ? 'Nouvel invariant (validateXXX)'
          : 'Modifier ${existing.title}',
      fields: [
        _FieldSpec(
          key: 'title',
          label: 'Titre (FR)',
          hint: 'Validation de l’intégrité de l’identité et du référentiel catalogue',
          initial: existing?.title ?? '',
          required: true,
        ),
        _FieldSpec(
          key: 'description',
          label: 'Descriptif (FR)',
          hint: 'Vérifie la cohérence structurelle des identifiants et références.',
          initial: existing?.description ?? '',
          maxLines: 2,
        ),
        _FieldSpec(
          key: 'rules',
          label: 'Rules (1 règle par ligne)',
          hint: 'L’identifiant id doit être un UUID valide.',
          initial: existing == null ? '' : _joinLines(existing.effectiveRules),
          maxLines: 3,
        ),
        _FieldSpec(
          key: 'associatedMethods',
          label: 'Associated internal methods (EN — 1 méthode validateXXX par ligne)',
          hint: 'validateIdentity(id)\nvalidateCatalogReferences(productId, variantId)',
          initial: existing == null
              ? ''
              : _joinLines(existing.effectiveAssociatedMethods),
          required: true,
          maxLines: 3,
        ),
        _FieldSpec(
          key: 'code',
          label: 'Code (optionnel)',
          hint: 'INV-01',
          initial: existing?.code ?? 'INV-0${layer.invariants.length + 1}',
        ),
        _FieldSpec(
          key: 'relatedAttributes',
          label: 'Attributs du modèle concernés (virgule)',
          hint: 'id, montantHt',
          initial: existing?.relatedAttributes.join(', ') ?? '',
        ),
        _FieldSpec(
          key: 'violationError',
          label: 'Erreur métier levée (optionnel)',
          hint: 'NegativeAmountError',
          initial: existing?.violationError ?? '',
        ),
      ],
    );
    if (values == null || !mounted) return;
    final methods = _splitLines(values['associatedMethods']!);
    final updated = DomainInvariantSpec(
      id: existing?.id ?? 'inv_${shortid.generate()}',
      code: values['code']!,
      title: values['title']!,
      description: values['description']!,
      rules: _splitLines(values['rules']!),
      associatedMethods: methods,
      methodSignature: methods.isNotEmpty ? methods.first : '',
      relatedAttributes: _splitLinesOrCommas(values['relatedAttributes']!),
      violationError: values['violationError']!,
    );
    final list = existing == null
        ? [...layer.invariants, updated]
        : [
            for (final x in layer.invariants)
              if (x.id == existing.id) updated else x,
          ];
    await _saveLayer(layer.copyWith(invariants: list));
  }

  // ---------------------------------------------------------------------------
  // 2. State changing (state_changing_behaviors)
  // ---------------------------------------------------------------------------

  Widget _buildStateChangingTab(
    ThemeData theme,
    ColorScheme colors,
    HexagonalDomainLayerSpec layer,
  ) {
    return _buildTabScaffold(
      theme: theme,
      colors: colors,
      tab: DomainLayerTab.stateChanging,
      addButtonLabel: 'Ajouter un comportement',
      onAdd: () => _editStateChange(layer),
      isEmpty: layer.stateChanges.isEmpty,
      emptyHint: 'Aucun comportement State changing défini.\nDécrivez les règles de changement d’état dans le chat IA ou ajoutez-en un manuellement.',
      children: [
        for (final item in layer.stateChanges)
          _SectionCard(
            itemId: item.id,
            titleFr: item.effectiveTitle,
            descriptionFr: item.description,
            rules: item.effectiveRules,
            associatedMethods: item.effectiveAssociatedMethods,
            tags: [
              for (final attr in item.relatedAttributes) 'attribut: $attr',
              for (final ev in item.emittedEvents) 'event: $ev',
              for (final err in item.domainErrors) 'erreur: $err',
            ],
            onEdit: () => _editStateChange(layer, existing: item),
            onDelete: () => _saveLayer(
              layer.copyWith(
                stateChanges: [
                  for (final x in layer.stateChanges)
                    if (x.id != item.id) x,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editStateChange(
    HexagonalDomainLayerSpec layer, {
    DomainStateChangeSpec? existing,
  }) async {
    final values = await _FieldFormDialog.show(
      context,
      title: existing == null
          ? 'Nouveau comportement State changing'
          : 'Modifier ${existing.effectiveTitle}',
      fields: [
        _FieldSpec(
          key: 'title',
          label: 'Titre (FR)',
          hint: 'Confirmation d’une commande brouillon',
          initial: existing?.effectiveTitle ?? '',
          required: true,
        ),
        _FieldSpec(
          key: 'description',
          label: 'Descriptif (FR)',
          hint: 'Valide la commande et verrouille ses lignes.',
          initial: existing?.description ?? '',
          maxLines: 2,
        ),
        _FieldSpec(
          key: 'rules',
          label: 'Rules — règles de changement d’état & gardes (1 par ligne)',
          hint: 'Passage de BROUILLON vers CONFIRMEE uniquement si montantHt > 0.',
          initial: existing == null ? '' : _joinLines(existing.effectiveRules),
          maxLines: 3,
        ),
        _FieldSpec(
          key: 'associatedMethods',
          label: 'Associated internal methods (EN — 1 méthode par ligne)',
          hint: 'confirmOrder(confirmedAt: DateTime): void',
          initial: existing == null
              ? ''
              : _joinLines(existing.effectiveAssociatedMethods),
          required: true,
          maxLines: 2,
        ),
        _FieldSpec(
          key: 'fromStates',
          label: 'États sources autorisés (virgule)',
          hint: 'BROUILLON',
          initial: existing?.fromStates.join(', ') ?? '',
        ),
        _FieldSpec(
          key: 'toState',
          label: 'État cible',
          hint: 'CONFIRMEE',
          initial: existing?.toState ?? '',
        ),
        _FieldSpec(
          key: 'emittedEvents',
          label: 'Domain events émis (virgule)',
          hint: 'OrderConfirmed',
          initial: existing?.emittedEvents.join(', ') ?? '',
        ),
        _FieldSpec(
          key: 'relatedAttributes',
          label: 'Attributs du modèle concernés (virgule)',
          hint: 'montantHt',
          initial: existing?.relatedAttributes.join(', ') ?? '',
        ),
      ],
    );
    if (values == null || !mounted) return;
    final methods = _splitLines(values['associatedMethods']!);
    final firstSig = methods.isNotEmpty ? methods.first : '';
    final extractedName = firstSig.split('(').first.trim();
    final updated = DomainStateChangeSpec(
      id: existing?.id ?? 'cmd_${shortid.generate()}',
      name: extractedName.isEmpty
          ? (existing?.name ?? 'applyStateChange')
          : extractedName,
      title: values['title']!,
      description: values['description']!,
      rules: _splitLines(values['rules']!),
      associatedMethods: methods,
      methodSignature: firstSig,
      fromStates: _splitLinesOrCommas(values['fromStates']!),
      toState: values['toState']!,
      emittedEvents: _splitLinesOrCommas(values['emittedEvents']!),
      domainErrors: existing?.domainErrors ?? const <String>[],
      relatedAttributes: _splitLinesOrCommas(values['relatedAttributes']!),
    );
    final list = existing == null
        ? [...layer.stateChanges, updated]
        : [
            for (final x in layer.stateChanges)
              if (x.id == existing.id) updated else x,
          ];
    await _saveLayer(layer.copyWith(stateChanges: list));
  }

  // ---------------------------------------------------------------------------
  // 3. Query (query_behaviors)
  // ---------------------------------------------------------------------------

  Widget _buildQueryTab(
    ThemeData theme,
    ColorScheme colors,
    HexagonalDomainLayerSpec layer,
  ) {
    return _buildTabScaffold(
      theme: theme,
      colors: colors,
      tab: DomainLayerTab.query,
      addButtonLabel: 'Ajouter une query',
      onAdd: () => _editQuery(layer),
      isEmpty: layer.queries.isEmpty,
      emptyHint: 'Aucune méthode Query définie (isXXX, canXXX, getXXX, computeXXX).\nAjoutez des états, calculs ou données dérivées sans effet de bord.',
      children: [
        for (final item in layer.queries)
          _SectionCard(
            itemId: item.id,
            titleFr: item.effectiveTitle,
            descriptionFr: item.description,
            rules: item.effectiveRules,
            associatedMethods: item.effectiveAssociatedMethods,
            tags: [
              for (final attr in item.relatedAttributes) 'attribut: $attr',
            ],
            onEdit: () => _editQuery(layer, existing: item),
            onDelete: () => _saveLayer(
              layer.copyWith(
                queries: [
                  for (final x in layer.queries)
                    if (x.id != item.id) x,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editQuery(
    HexagonalDomainLayerSpec layer, {
    DomainQuerySpec? existing,
  }) async {
    final values = await _FieldFormDialog.show(
      context,
      title: existing == null
          ? 'Nouvelle Query (is/can/get/computeXXX)'
          : 'Modifier ${existing.effectiveTitle}',
      fields: [
        _FieldSpec(
          key: 'title',
          label: 'Titre (FR)',
          hint: 'Éligibilité à l’annulation et calculs dérivés',
          initial: existing?.effectiveTitle ?? '',
          required: true,
        ),
        _FieldSpec(
          key: 'description',
          label: 'Descriptif (FR)',
          hint: 'Retourne l’état d’annulabilité et les totaux calculés.',
          initial: existing?.description ?? '',
          maxLines: 2,
        ),
        _FieldSpec(
          key: 'rules',
          label: 'Rules (1 règle ou formule par ligne)',
          hint: 'La commande est annulable tant que statut == BROUILLON.',
          initial: existing == null ? '' : _joinLines(existing.effectiveRules),
          maxLines: 3,
        ),
        _FieldSpec(
          key: 'associatedMethods',
          label: 'Associated internal methods (EN — isXXX, canXXX, getXXX, computeXXX)',
          hint: 'canBeCancelled(): bool\ncomputeTotalTtc(): number',
          initial: existing == null
              ? ''
              : _joinLines(existing.effectiveAssociatedMethods),
          required: true,
          maxLines: 3,
        ),
        _FieldSpec(
          key: 'relatedAttributes',
          label: 'Attributs du modèle concernés (virgule)',
          hint: 'montantHt',
          initial: existing?.relatedAttributes.join(', ') ?? '',
        ),
      ],
    );
    if (values == null || !mounted) return;
    final methods = _splitLines(values['associatedMethods']!);
    final firstSig = methods.isNotEmpty ? methods.first : '';
    final extractedName = firstSig.split('(').first.trim();
    final updated = DomainQuerySpec(
      id: existing?.id ?? 'qry_${shortid.generate()}',
      name: extractedName.isEmpty
          ? (existing?.name ?? 'isEligible')
          : extractedName,
      title: values['title']!,
      description: values['description']!,
      rules: _splitLines(values['rules']!),
      associatedMethods: methods,
      methodSignature: firstSig,
      returnType: existing?.returnType ?? 'bool',
      relatedAttributes: _splitLinesOrCommas(values['relatedAttributes']!),
    );
    final list = existing == null
        ? [...layer.queries, updated]
        : [
            for (final x in layer.queries)
              if (x.id == existing.id) updated else x,
          ];
    await _saveLayer(layer.copyWith(queries: list));
  }

  // ---------------------------------------------------------------------------
  // 4. Policy Services (policy_service_behaviors)
  // ---------------------------------------------------------------------------

  Widget _buildPolicyServicesTab(
    ThemeData theme,
    ColorScheme colors,
    HexagonalDomainLayerSpec layer,
  ) {
    return _buildTabScaffold(
      theme: theme,
      colors: colors,
      tab: DomainLayerTab.policyServices,
      addButtonLabel: 'Ajouter une policy',
      onAdd: () => _editPolicyService(layer),
      isEmpty: layer.policyServices.isEmpty,
      emptyHint: 'Aucun Policy Service défini.\nDéclarez ici les méthodes appliquant des règles complexes aux agrégats ou inter-agrégats.',
      children: [
        for (final item in layer.policyServices)
          _SectionCard(
            itemId: item.id,
            titleFr: item.effectiveTitle,
            descriptionFr: item.description,
            rules: item.effectiveRules,
            associatedMethods: item.effectiveAssociatedMethods,
            tags: [
              for (final col in item.collaborators) 'collab: $col',
              for (final attr in item.relatedAttributes) 'attribut: $attr',
            ],
            onEdit: () => _editPolicyService(layer, existing: item),
            onDelete: () => _saveLayer(
              layer.copyWith(
                policyServices: [
                  for (final x in layer.policyServices)
                    if (x.id != item.id) x,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editPolicyService(
    HexagonalDomainLayerSpec layer, {
    DomainPolicyServiceSpec? existing,
  }) async {
    final values = await _FieldFormDialog.show(
      context,
      title: existing == null
          ? 'Nouveau Policy Service'
          : 'Modifier ${existing.effectiveTitle}',
      fields: [
        _FieldSpec(
          key: 'title',
          label: 'Titre (FR)',
          hint: 'Politique de remise commerciale inter-agrégats',
          initial: existing?.effectiveTitle ?? '',
          required: true,
        ),
        _FieldSpec(
          key: 'description',
          label: 'Descriptif (FR)',
          hint: 'Applique les règles complexes de tarification multi-entités.',
          initial: existing?.description ?? '',
          maxLines: 2,
        ),
        _FieldSpec(
          key: 'rules',
          label: 'Rules (1 règle par ligne)',
          hint: 'Remise plafonnée à 15% pour le segment standard.',
          initial: existing == null ? '' : _joinLines(existing.effectiveRules),
          maxLines: 3,
        ),
        _FieldSpec(
          key: 'associatedMethods',
          label: 'Associated internal methods (EN — 1 méthode par ligne)',
          hint: 'applyVolumeDiscountPolicy(order: CommandeClient, client: Client): number',
          initial: existing == null
              ? ''
              : _joinLines(existing.effectiveAssociatedMethods),
          required: true,
          maxLines: 2,
        ),
        _FieldSpec(
          key: 'collaborators',
          label: 'Collaborateurs / agrégats impliqués (virgule)',
          hint: 'Client, GrilleTarifaire',
          initial: existing?.collaborators.join(', ') ?? '',
        ),
        _FieldSpec(
          key: 'relatedAttributes',
          label: 'Attributs du modèle concernés (virgule)',
          hint: 'montantHt',
          initial: existing?.relatedAttributes.join(', ') ?? '',
        ),
      ],
    );
    if (values == null || !mounted) return;
    final methods = _splitLines(values['associatedMethods']!);
    final firstSig = methods.isNotEmpty ? methods.first : '';
    final extractedName = firstSig.split('(').first.trim();
    final updated = DomainPolicyServiceSpec(
      id: existing?.id ?? 'pol_${shortid.generate()}',
      name: extractedName.isEmpty
          ? (existing?.name ?? 'DomainPolicy')
          : extractedName,
      title: values['title']!,
      description: values['description']!,
      rules: _splitLines(values['rules']!),
      associatedMethods: methods,
      methodSignature: firstSig,
      operation: firstSig,
      collaborators: _splitLinesOrCommas(values['collaborators']!),
      relatedAttributes: _splitLinesOrCommas(values['relatedAttributes']!),
    );
    final list = existing == null
        ? [...layer.policyServices, updated]
        : [
            for (final x in layer.policyServices)
              if (x.id == existing.id) updated else x,
          ];
    await _saveLayer(layer.copyWith(policyServices: list));
  }

  // ---------------------------------------------------------------------------
  // 5. Factory (factory_behaviors)
  // ---------------------------------------------------------------------------

  Widget _buildFactoryTab(
    ThemeData theme,
    ColorScheme colors,
    HexagonalDomainLayerSpec layer,
  ) {
    return _buildTabScaffold(
      theme: theme,
      colors: colors,
      tab: DomainLayerTab.factory,
      addButtonLabel: 'Ajouter une factory',
      onAdd: () => _editFactory(layer),
      isEmpty: layer.factories.isEmpty,
      emptyHint: 'Aucune Factory définie (createXXX(), fromSnapshot(rawData)).\nDécrivez comment créer ou reconstituer une entité valide.',
      children: [
        for (final item in layer.factories)
          _SectionCard(
            itemId: item.id,
            titleFr: item.effectiveTitle,
            descriptionFr: item.description,
            rules: item.effectiveRules,
            associatedMethods: item.effectiveAssociatedMethods,
            tags: [
              for (final attr in item.relatedAttributes) 'attribut: $attr',
              for (final inv in item.enforcedInvariants) 'invariant: $inv',
              for (final ev in item.emittedEvents) 'event: $ev',
            ],
            onEdit: () => _editFactory(layer, existing: item),
            onDelete: () => _saveLayer(
              layer.copyWith(
                factories: [
                  for (final x in layer.factories)
                    if (x.id != item.id) x,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editFactory(
    HexagonalDomainLayerSpec layer, {
    DomainFactorySpec? existing,
  }) async {
    final values = await _FieldFormDialog.show(
      context,
      title: existing == null
          ? 'Nouvelle Factory (createXXX / fromSnapshot)'
          : 'Modifier ${existing.effectiveTitle}',
      fields: [
        _FieldSpec(
          key: 'title',
          label: 'Titre (FR)',
          hint: 'Création et reconstitution d’une commande valide',
          initial: existing?.effectiveTitle ?? '',
          required: true,
        ),
        _FieldSpec(
          key: 'description',
          label: 'Descriptif (FR)',
          hint: 'Instancie l’agrégat valide ou le reconstitue depuis un snapshot.',
          initial: existing?.description ?? '',
          maxLines: 2,
        ),
        _FieldSpec(
          key: 'rules',
          label: 'Rules (1 règle par ligne)',
          hint: 'Initialise l’état à BROUILLON et vérifie les invariants.',
          initial: existing == null ? '' : _joinLines(existing.effectiveRules),
          maxLines: 3,
        ),
        _FieldSpec(
          key: 'associatedMethods',
          label: 'Associated internal methods (EN — createXXX(), fromSnapshot(rawData))',
          hint: 'createDraftOrder(montantHt: number): CommandeClient\nfromSnapshot(rawData)',
          initial: existing == null
              ? ''
              : _joinLines(existing.effectiveAssociatedMethods),
          required: true,
          maxLines: 3,
        ),
        _FieldSpec(
          key: 'initialState',
          label: 'État initial (optionnel)',
          hint: 'BROUILLON',
          initial: existing?.initialState ?? '',
        ),
        _FieldSpec(
          key: 'relatedAttributes',
          label: 'Attributs du modèle initialisés (virgule)',
          hint: 'montantHt',
          initial: existing?.relatedAttributes.join(', ') ?? '',
        ),
      ],
    );
    if (values == null || !mounted) return;
    final methods = _splitLines(values['associatedMethods']!);
    final firstSig = methods.isNotEmpty ? methods.first : '';
    final extractedName = firstSig.split('(').first.trim();
    final updated = DomainFactorySpec(
      id: existing?.id ?? 'fac_${shortid.generate()}',
      name: extractedName.isEmpty
          ? (existing?.name ?? 'createEntity')
          : extractedName,
      title: values['title']!,
      description: values['description']!,
      rules: _splitLines(values['rules']!),
      associatedMethods: methods,
      methodSignature: firstSig,
      initialState: values['initialState']!,
      enforcedInvariants: existing?.enforcedInvariants ?? const <String>[],
      emittedEvents: existing?.emittedEvents ?? const <String>[],
      relatedAttributes: _splitLinesOrCommas(values['relatedAttributes']!),
    );
    final list = existing == null
        ? [...layer.factories, updated]
        : [
            for (final x in layer.factories)
              if (x.id == existing.id) updated else x,
          ];
    await _saveLayer(layer.copyWith(factories: list));
  }

  // ---------------------------------------------------------------------------
  // 6. Domain events (domain_event_behaviors)
  // ---------------------------------------------------------------------------

  Widget _buildDomainEventsTab(
    ThemeData theme,
    ColorScheme colors,
    HexagonalDomainLayerSpec layer,
  ) {
    return _buildTabScaffold(
      theme: theme,
      colors: colors,
      tab: DomainLayerTab.domainEvents,
      addButtonLabel: 'Ajouter un event behavior',
      onAdd: () => _editDomainEvent(layer),
      isEmpty: layer.domainEvents.isEmpty,
      emptyHint: 'Aucun Domain event behavior défini (publishXXX(), onXXX()).\nListez les méthodes publiant ou traitant les événements métier.',
      children: [
        for (final item in layer.domainEvents)
          _SectionCard(
            itemId: item.id,
            titleFr: item.effectiveTitle,
            descriptionFr: item.description,
            rules: item.effectiveRules,
            associatedMethods: item.effectiveAssociatedMethods,
            tags: [
              if (item.trigger.isNotEmpty) 'trigger: ${item.trigger}',
              if (item.contractEntryRef.isNotEmpty)
                'contrat: ${item.contractEntryRef}',
              for (final attr in item.relatedAttributes) 'attribut: $attr',
            ],
            onEdit: () => _editDomainEvent(layer, existing: item),
            onDelete: () => _saveLayer(
              layer.copyWith(
                domainEvents: [
                  for (final x in layer.domainEvents)
                    if (x.id != item.id) x,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editDomainEvent(
    HexagonalDomainLayerSpec layer, {
    DomainEventSpec? existing,
  }) async {
    final values = await _FieldFormDialog.show(
      context,
      title: existing == null
          ? 'Nouveau Domain event behavior (publishXXX / onXXX)'
          : 'Modifier ${existing.effectiveTitle}',
      fields: [
        _FieldSpec(
          key: 'title',
          label: 'Titre (FR)',
          hint: 'Publication de l’événement de confirmation de commande',
          initial: existing?.effectiveTitle ?? '',
          required: true,
        ),
        _FieldSpec(
          key: 'description',
          label: 'Descriptif (FR)',
          hint: 'Notifie les autres contextes qu’une commande a été confirmée.',
          initial: existing?.description ?? '',
          maxLines: 2,
        ),
        _FieldSpec(
          key: 'rules',
          label: 'Rules (1 règle par ligne)',
          hint: 'Publié uniquement après validation complète de l’agrégat.',
          initial: existing == null ? '' : _joinLines(existing.effectiveRules),
          maxLines: 3,
        ),
        _FieldSpec(
          key: 'associatedMethods',
          label: 'Associated internal methods (EN — publishXXX(), onXXX())',
          hint: 'publishOrderConfirmed(id, montantHt)',
          initial: existing == null
              ? ''
              : _joinLines(existing.effectiveAssociatedMethods),
          required: true,
          maxLines: 2,
        ),
        _FieldSpec(
          key: 'trigger',
          label: 'Méthode déclencheuse (optionnel)',
          hint: 'confirmOrder',
          initial: existing?.trigger ?? '',
        ),
        _FieldSpec(
          key: 'relatedAttributes',
          label: 'Attributs du modèle concernés (virgule)',
          hint: 'id, montantHt',
          initial: existing?.relatedAttributes.join(', ') ?? '',
        ),
      ],
    );
    if (values == null || !mounted) return;
    final methods = _splitLines(values['associatedMethods']!);
    final firstSig = methods.isNotEmpty ? methods.first : '';
    final extractedName = firstSig.split('(').first.trim();
    final updated = DomainEventSpec(
      id: existing?.id ?? 'evt_${shortid.generate()}',
      name: extractedName.isEmpty
          ? (existing?.name ?? 'publishDomainEvent')
          : extractedName,
      title: values['title']!,
      description: values['description']!,
      rules: _splitLines(values['rules']!),
      associatedMethods: methods,
      methodSignature: firstSig,
      trigger: values['trigger']!,
      payloadFields: existing?.payloadFields ?? const <String>[],
      contractEntryRef: existing?.contractEntryRef ?? '',
      relatedAttributes: _splitLinesOrCommas(values['relatedAttributes']!),
    );
    final list = existing == null
        ? [...layer.domainEvents, updated]
        : [
            for (final x in layer.domainEvents)
              if (x.id == existing.id) updated else x,
          ];
    await _saveLayer(layer.copyWith(domainEvents: list));
  }

  // ---------------------------------------------------------------------------
  // 7. Persistence policy (persistence_policy_behaviors)
  // ---------------------------------------------------------------------------

  Widget _buildPersistencePolicyTab(
    ThemeData theme,
    ColorScheme colors,
    HexagonalDomainLayerSpec layer,
  ) {
    final policy = layer.persistencePolicy;
    final object = widget.document.objectFor(widget.entry);
    final effectivePortName = policy.repositoryPortName.isEmpty
        ? '${object.technicalName}Repository'
        : policy.repositoryPortName;

    final policyOverviewCard = Card(
      key: const ValueKey('domain-layer-persistence-summary-card'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              children: [
                Icon(Icons.storage_rounded, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Port sortant : $effectivePortName',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('domain-layer-edit-persistence-policy'),
                  tooltip: 'Configurer la politique de persistance',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _editPersistencePolicy(layer),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    'Concurrence : ${policy.concurrencyStrategy.label}',
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('Suppression : ${policy.deletionStrategy.label}'),
                ),
              ],
            ),
            if (policy.aggregateBoundary.isNotEmpty)
              Text(
                'Frontière transactionnelle : ${policy.aggregateBoundary}',
                style: theme.textTheme.bodySmall,
              ),
            if (policy.rules.isNotEmpty) ...[
              Text(
                'Rules:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final rule in policy.rules)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 14,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(rule, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
            ],
            if (policy.consistencyNotes.isNotEmpty)
              Text(
                'Notes & rétention : ${policy.consistencyNotes}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );

    return _buildTabScaffold(
      theme: theme,
      colors: colors,
      tab: DomainLayerTab.persistencePolicy,
      addButtonLabel: 'Ajouter méthode ou règle',
      extraHeaderActions: [
        OutlinedButton.icon(
          key: const ValueKey('domain-layer-configure-persistence-btn'),
          onPressed: () => _editPersistencePolicy(layer),
          icon: const Icon(Icons.tune_rounded, size: 16),
          label: const Text('Configurer la politique'),
        ),
      ],
      onAdd: () => _editPortMethod(layer),
      isEmpty: false,
      emptyHint: '',
      children: [
        policyOverviewCard,
        if (policy.portMethods.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Aucune méthode ni règle unitaire déclarée (CRUD métier, Vérification, Recherche, Pagination, Index de recherche, Contrainte d’unicité…).',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final method in policy.portMethods)
            _SectionCard(
              itemId: method.id,
              prefixBadge: method.category.label,
              titleFr: method.effectiveTitle,
              descriptionFr: method.description,
              rules: method.effectiveRules,
              associatedMethods: method.effectiveAssociatedMethods,
              allowEmptyMethods: true,
              tags: [
                for (final attr in method.relatedAttributes) 'attribut: $attr',
              ],
              onEdit: () => _editPortMethod(layer, existing: method),
              onDelete: () => _saveLayer(
                layer.copyWith(
                  persistencePolicy: policy.copyWith(
                    portMethods: [
                      for (final m in policy.portMethods)
                        if (m.id != method.id) m,
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _editPersistencePolicy(HexagonalDomainLayerSpec layer) async {
    final policy = layer.persistencePolicy;
    final object = widget.document.objectFor(widget.entry);
    final result = await showDialog<DomainPersistencePolicySpec>(
      context: context,
      builder: (_) => _PersistencePolicyDialog(
        initial: policy,
        defaultPortName: '${object.technicalName}Repository',
      ),
    );
    if (result == null || !mounted) return;
    await _saveLayer(layer.copyWith(persistencePolicy: result));
  }

  Future<void> _editPortMethod(
    HexagonalDomainLayerSpec layer, {
    DomainRepositoryMethodSpec? existing,
  }) async {
    final policy = layer.persistencePolicy;
    final object = widget.document.objectFor(widget.entry);
    final updated = await showDialog<DomainRepositoryMethodSpec>(
      context: context,
      builder: (_) => _PersistenceBehaviorDialog(
        existing: existing,
        modelTechnicalName: object.technicalName,
      ),
    );
    if (updated == null || !mounted) return;
    final list = existing == null
        ? [...policy.portMethods, updated]
        : [
            for (final m in policy.portMethods)
              if (m.id == existing.id) updated else m,
          ];
    await _saveLayer(
      layer.copyWith(persistencePolicy: policy.copyWith(portMethods: list)),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.colors});

  final int count;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: colors.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Carte structurée commune aux 7 onglets affichant systématiquement :
/// - le titre,
/// - le descriptif,
/// - `Rules:`,
/// - `Associated internal methods:`.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.itemId,
    required this.titleFr,
    required this.onEdit,
    required this.onDelete,
    this.prefixBadge,
    this.descriptionFr = '',
    this.rules = const <String>[],
    this.associatedMethods = const <String>[],
    this.allowEmptyMethods = false,
    this.tags = const <String>[],
  });

  final String itemId;
  final String titleFr;
  final String? prefixBadge;
  final String descriptionFr;
  final List<String> rules;
  final List<String> associatedMethods;
  final bool allowEmptyMethods;
  final List<String> tags;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cleanDesc = descriptionFr.trim();
    return Card(
      key: ValueKey('domain-layer-card-$itemId'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            // 1. Titre + Descriptif + actions
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (prefixBadge != null && prefixBadge!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                prefixBadge!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                            ),
                          Text(
                            titleFr,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (cleanDesc.isNotEmpty && cleanDesc != titleFr.trim())
                        Text(
                          cleanDesc,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('domain-layer-edit-item-$itemId'),
                  tooltip: 'Modifier',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: ValueKey('domain-layer-delete-item-$itemId'),
                  tooltip: 'Supprimer',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),

            // 2. Rules:
            if (rules.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    'Rules:',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                  for (final rule in rules)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Expanded(
                            child: Text(rule, style: theme.textTheme.bodySmall),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

            // 3. Associated internal methods:
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Text(
                  'Associated internal methods:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
                if (associatedMethods.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final method in associatedMethods)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: 0.65,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colors.outlineVariant.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 6,
                            children: [
                              Icon(
                                Icons.code_rounded,
                                size: 14,
                                color: colors.primary,
                              ),
                              Flexible(
                                child: Text(
                                  method,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                else if (allowEmptyMethods)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.tertiaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Règle sans méthode associée',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),

            if (tags.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tag,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FieldSpec {
  const _FieldSpec({
    required this.key,
    required this.label,
    this.hint = '',
    this.initial = '',
    this.required = false,
    this.maxLines = 1,
  });

  final String key;
  final String label;
  final String hint;
  final String initial;
  final bool required;
  final int maxLines;
}

class _FieldFormDialog extends StatefulWidget {
  const _FieldFormDialog({required this.title, required this.fields});

  final String title;
  final List<_FieldSpec> fields;

  static Future<Map<String, String>?> show(
    BuildContext context, {
    required String title,
    required List<_FieldSpec> fields,
  }) => showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _FieldFormDialog(title: title, fields: fields),
  );

  @override
  State<_FieldFormDialog> createState() => _FieldFormDialogState();
}

class _FieldFormDialogState extends State<_FieldFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.fields)
      f.key: TextEditingController(text: f.initial),
  };

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('domain-layer-item-form-dialog'),
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                for (final (i, field) in widget.fields.indexed)
                  TextFormField(
                    key: ValueKey('domain-layer-field-${field.key}'),
                    controller: _controllers[field.key],
                    autofocus: i == 0,
                    maxLines: field.maxLines,
                    decoration: InputDecoration(
                      labelText: field.label,
                      hintText: field.hint.isEmpty ? null : field.hint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: field.required
                        ? (v) => (v == null || v.trim().isEmpty)
                              ? 'Champ requis.'
                              : null
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('domain-layer-form-save-btn'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, <String, String>{
              for (final e in _controllers.entries) e.key: e.value.text.trim(),
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _PersistenceBehaviorDialog extends StatefulWidget {
  const _PersistenceBehaviorDialog({
    required this.existing,
    required this.modelTechnicalName,
  });

  final DomainRepositoryMethodSpec? existing;
  final String modelTechnicalName;

  @override
  State<_PersistenceBehaviorDialog> createState() =>
      _PersistenceBehaviorDialogState();
}

class _PersistenceBehaviorDialogState
    extends State<_PersistenceBehaviorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late PersistenceBehaviorCategory _category =
      widget.existing?.category ?? PersistenceBehaviorCategory.crud;
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.existing?.effectiveTitle ?? '',
  );
  late final TextEditingController _descCtrl = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final TextEditingController _rulesCtrl = TextEditingController(
    text: widget.existing == null
        ? ''
        : _joinLines(widget.existing!.effectiveRules),
  );
  late final TextEditingController _methodCtrl = TextEditingController(
    text: widget.existing == null
        ? ''
        : _joinLines(widget.existing!.effectiveAssociatedMethods),
  );
  late final TextEditingController _attrsCtrl = TextEditingController(
    text: widget.existing?.relatedAttributes.join(', ') ?? '',
  );

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _rulesCtrl.dispose();
    _methodCtrl.dispose();
    _attrsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('domain-layer-persistence-behavior-dialog'),
      title: Text(
        widget.existing == null
            ? 'Nouvelle méthode ou règle de persistance'
            : 'Modifier ${widget.existing!.effectiveTitle}',
      ),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Catégorie',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<PersistenceBehaviorCategory>(
                      key: const ValueKey(
                        'domain-layer-persistence-category-dropdown',
                      ),
                      value: _category,
                      isDense: true,
                      isExpanded: true,
                      items: [
                        for (final cat in PersistenceBehaviorCategory.values)
                          DropdownMenuItem(value: cat, child: Text(cat.label)),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _category = value);
                      },
                    ),
                  ),
                ),
                TextFormField(
                  key: const ValueKey('domain-layer-persistence-title-field'),
                  controller: _titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Titre (FR)',
                    hintText: 'Rechercher par statut ou contrainte d’unicité sur code',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Champ requis.' : null,
                ),
                TextFormField(
                  key: const ValueKey('domain-layer-persistence-desc-field'),
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descriptif (FR)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                TextFormField(
                  key: const ValueKey('domain-layer-persistence-rules-field'),
                  controller: _rulesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Rules — unicité, index de recherche, transactions (1 par ligne)',
                    hintText: 'Index B-Tree sur statut et dateCreation.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                TextFormField(
                  key: const ValueKey('domain-layer-persistence-method-field'),
                  controller: _methodCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Associated internal methods (EN — 1 par ligne, vide autorisé si règle pure)',
                    hintText:
                        'findByStatus${widget.modelTechnicalName}(status)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                TextFormField(
                  key: const ValueKey('domain-layer-persistence-attrs-field'),
                  controller: _attrsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Attributs du modèle concernés (virgule)',
                    hintText: 'id, montantHt',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('domain-layer-persistence-behavior-save-btn'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final methods = _splitLines(_methodCtrl.text);
            final firstSig = methods.isNotEmpty ? methods.first : '';
            final extractedName = firstSig.isEmpty
                ? ''
                : firstSig.split('(').first.trim();
            Navigator.pop(
              context,
              DomainRepositoryMethodSpec(
                id: widget.existing?.id ?? 'repm_${shortid.generate()}',
                name: extractedName,
                title: _titleCtrl.text.trim(),
                description: _descCtrl.text.trim(),
                rules: _splitLines(_rulesCtrl.text),
                associatedMethods: methods,
                methodSignature: firstSig,
                category: _category,
                relatedAttributes: _splitLinesOrCommas(_attrsCtrl.text),
              ),
            );
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _PersistencePolicyDialog extends StatefulWidget {
  const _PersistencePolicyDialog({
    required this.initial,
    required this.defaultPortName,
  });

  final DomainPersistencePolicySpec initial;
  final String defaultPortName;

  @override
  State<_PersistencePolicyDialog> createState() =>
      _PersistencePolicyDialogState();
}

class _PersistencePolicyDialogState extends State<_PersistencePolicyDialog> {
  late final TextEditingController _portNameCtrl = TextEditingController(
    text: widget.initial.repositoryPortName.isEmpty
        ? widget.defaultPortName
        : widget.initial.repositoryPortName,
  );
  late final TextEditingController _boundaryCtrl = TextEditingController(
    text: widget.initial.aggregateBoundary,
  );
  late final TextEditingController _rulesCtrl = TextEditingController(
    text: _joinLines(widget.initial.rules),
  );
  late final TextEditingController _notesCtrl = TextEditingController(
    text: widget.initial.consistencyNotes,
  );
  late DomainConcurrencyStrategy _concurrency =
      widget.initial.concurrencyStrategy;
  late DomainDeletionStrategy _deletion = widget.initial.deletionStrategy;

  @override
  void dispose() {
    _portNameCtrl.dispose();
    _boundaryCtrl.dispose();
    _rulesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('domain-layer-persistence-policy-dialog'),
      title: const Text('Configurer la Persistence policy'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              TextField(
                key: const ValueKey('domain-layer-policy-port-name'),
                controller: _portNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom du port sortant Repository',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              TextField(
                key: const ValueKey('domain-layer-policy-boundary'),
                controller: _boundaryCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Frontière transactionnelle de l’agrégat',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Stratégie de concurrence',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DomainConcurrencyStrategy>(
                    key: const ValueKey('domain-layer-policy-concurrency'),
                    value: _concurrency,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      for (final item in DomainConcurrencyStrategy.values)
                        DropdownMenuItem(value: item, child: Text(item.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _concurrency = value);
                    },
                  ),
                ),
              ),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Stratégie de suppression / rétention',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DomainDeletionStrategy>(
                    key: const ValueKey('domain-layer-policy-deletion'),
                    value: _deletion,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      for (final item in DomainDeletionStrategy.values)
                        DropdownMenuItem(value: item, child: Text(item.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _deletion = value);
                    },
                  ),
                ),
              ),
              TextField(
                key: const ValueKey('domain-layer-policy-rules'),
                controller: _rulesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Règles globales : contraintes d’unicité, index de recherche & transactions (1 par ligne)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              TextField(
                key: const ValueKey('domain-layer-policy-notes'),
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes & archivage',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
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
          key: const ValueKey('domain-layer-policy-save-btn'),
          onPressed: () => Navigator.pop(
            context,
            widget.initial.copyWith(
              repositoryPortName: _portNameCtrl.text.trim(),
              aggregateBoundary: _boundaryCtrl.text.trim(),
              concurrencyStrategy: _concurrency,
              deletionStrategy: _deletion,
              rules: _splitLines(_rulesCtrl.text),
              consistencyNotes: _notesCtrl.text.trim(),
            ),
          ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
