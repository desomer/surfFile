/// Page des modèles et contrats, contextualisée par un domaine du workspace.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/components/internal_widget/widget_breadcrumb.dart'
    show TriangleClipper;

import 'package:super_container_layout/super_container_layout.dart'
    show VibeChatAttachment;

import '../../models/domain_contracts.dart';
import '../../services/spec_forge_controller.dart';
import '../workspace/markdown_viewer_dialog.dart';
import 'contract_domain_layer_view.dart';
import 'contract_entry_view.dart';
import 'domain_contracts_editor.dart';

/// Affiche le fil d’Ariane et permet de changer de domaine sans quitter la page.
///
/// Le fil d’Ariane pilote un [PageView] : la liste (DSL + catalogue) puis la
/// fiche d'une entrée ouverte par son nom souligné (chat IA et détail de son
/// objet). La flèche remonte d'un niveau du fil, l'icône de grille revient au
/// menu Design.
class ModelsContractsView extends StatefulWidget {
  /// Crée la page à partir des domaines du catalogue actif de [controller].
  const ModelsContractsView({
    required this.controller,
    required this.onBack,
    required this.onManageDomains,
    this.initialDomainId,
    this.onOpenEntryChanged,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    this.schemaViewerSurfaceBuilder,
    this.schemaBrowserLauncher,
    super.key,
  });

  /// Fournit les domaines et persiste chaque document dans son domaine
  /// d'origine, même après un changement de sélection.
  final SpecForgeController controller;

  /// Revient aux liens Design (icône de grille, ou flèche depuis la liste).
  final VoidCallback onBack;

  /// Ouvre le catalogue des domaines quand le workspace n'en a aucun.
  final VoidCallback onManageDomains;

  /// Identifiant optionnel du domaine sélectionné à l'ouverture de la vue.
  final String? initialDomainId;

  /// Signale au shell la fiche visible, ou le retour à la liste.
  final void Function(String? domainId, String? entryId)? onOpenEntryChanged;

  /// Remplacent les accès fichiers et presse-papiers du chat (tests).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  /// Constructeur optionnel pour remplacer la WebView dans l'onglet « Repository » d'une fiche (tests).
  final SpecMarkdownViewerSurfaceBuilder? schemaViewerSurfaceBuilder;

  /// Lanceur navigateur optionnel pour l'ouverture du `.html` généré d'une fiche (tests).
  final SpecMarkdownBrowserLauncher? schemaBrowserLauncher;

  @override
  State<ModelsContractsView> createState() => _ModelsContractsViewState();
}

class _ModelsContractsViewState extends State<ModelsContractsView> {
  String? _selectedId;

  /// Entrée de la fiche, conservée pendant l'animation de retour à la liste.
  String? _openId;

  /// Niveau du fil d’Ariane, qui est aussi la page du [PageView] :
  /// 0 = liste des modèles et contrats, 1 = fiche de [_openId].
  int _level = 0;
  double _codeFraction = DomainContractsEditor.defaultCodeFraction;
  final _menu = MenuController();
  final _pages = PageController();

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialDomainId;
  }

  @override
  void didUpdateWidget(ModelsContractsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDomainId != null &&
        widget.initialDomainId != oldWidget.initialDomainId) {
      _selectedId = widget.initialDomainId;
      _level = 0;
      _openId = null;
      if (_pages.hasClients) {
        _pages.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Seul point de navigation : remonter sous la liste sort vers le menu.
  void _goTo(int level, {String? domainId, String? entryId}) {
    if (level < 0) return widget.onBack();
    setState(() {
      _level = level;
      _openId = entryId ?? _openId;
    });
    widget.onOpenEntryChanged?.call(domainId, entryId);
    if (_pages.hasClients) {
      unawaited(
        _pages.animateToPage(
          level,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final domains = widget.controller.domainCatalog.domains;
    final selected =
        domains.where((domain) => domain.id == _selectedId).firstOrNull ??
        domains.firstOrNull;
    final document = selected?.contracts ?? DomainContracts.empty;
    final opened = document.entryById(_openId);
    final entry = _level >= 1 ? opened : null;
    const navy = Color(0xFF132F43);
    const textStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: const Color(0xFF10171B),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  tooltip: switch (_level) {
                    0 => 'Retour au menu Design',
                    1 => 'Retour à la liste des modèles et contrats',
                    _ => 'Retour à la fiche du modèle',
                  },
                  onPressed: () => _goTo(
                    _level - 1,
                    domainId: _level > 1 ? selected?.id : null,
                    entryId: _level > 1 ? opened?.id : null,
                  ),
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: 'Menu Design',
                  onPressed: widget.onBack,
                  color: Colors.white,
                  icon: const Icon(Icons.apps),
                ),
                ColoredBox(
                  color: navy,
                  child: MenuAnchor(
                    controller: _menu,
                    menuChildren: [
                      for (final domain in domains)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: ChoiceChip(
                            label: Text(
                              domain.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                            tooltip: '${domain.name} · ${domain.domainCode}',
                            selected: domain.id == selected?.id,
                            onSelected: (_) {
                              final changed = domain.id != selected?.id;
                              if (changed && _pages.hasClients) {
                                _pages.jumpToPage(0);
                              }
                              setState(() {
                                if (changed) {
                                  _level = 0;
                                  _openId = null;
                                }
                                _selectedId = domain.id;
                              });
                              if (changed) {
                                widget.onOpenEntryChanged?.call(null, null);
                              }
                              _menu.close();
                            },
                          ),
                        ),
                    ],
                    builder: (context, menu, _) => ClipPath(
                      clipper: TriangleClipper(false),
                      child: Material(
                        color: selected == null
                            ? Colors.blueGrey
                            : Colors.blue.shade700,
                        child: Tooltip(
                          message: 'Choisir un domaine',
                          child: InkWell(
                            onTap: selected == null
                                ? null
                                : () =>
                                      menu.isOpen ? menu.close() : menu.open(),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 0, 26, 0),
                              child: SizedBox(
                                height: 44,
                                child: Row(
                                  spacing: 6,
                                  children: [
                                    const Icon(
                                      Icons.domain,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 220,
                                      ),
                                      child: Text(
                                        selected?.name ?? 'Aucun domaine',
                                        style: textStyle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (selected != null)
                                      const Icon(
                                        Icons.arrow_drop_down,
                                        color: Colors.white,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ClipPath(
                  clipper: TriangleClipper(false),
                  child: Material(
                    color: navy,
                    child: InkWell(
                      key: const ValueKey('contracts-list-crumb'),
                      onTap: _level > 0 ? () => _goTo(0) : null,
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.only(left: 8, right: 28),
                        child: const Text(
                          'Liste des modèles et contrats',
                          style: textStyle,
                        ),
                      ),
                    ),
                  ),
                ),
                if (entry != null) ...[
                  ClipPath(
                    clipper: TriangleClipper(false),
                    child: Material(
                      color: _level > 1 ? navy : Colors.blueGrey.shade800,
                      child: InkWell(
                        key: const ValueKey('contracts-entry-crumb'),
                        onTap: _level > 1
                            ? () => _goTo(
                                1,
                                domainId: selected?.id,
                                entryId: entry.id,
                              )
                            : null,
                        child: Container(
                          height: 44,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.only(left: 10, right: 26),
                          child: Text(entry.name, style: textStyle),
                        ),
                      ),
                    ),
                  ),
                  ClipPath(
                    clipper: TriangleClipper(false),
                    child: Container(
                      color: Colors.blueGrey.shade800,
                      height: 44,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.only(left: 10, right: 26),
                      child: Text(
                        (document.details[entry.id] ?? ContractDetails.defaults)
                            .version,
                        style: textStyle,
                      ),
                    ),
                  ),
                  if (_level >= 2)
                    ClipPath(
                      clipper: TriangleClipper(false),
                      child: Container(
                        color: Colors.blueGrey.shade800,
                        height: 44,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.only(left: 10, right: 26),
                        child: const Text('Couche Domain', style: textStyle),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: selected == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 12,
                      children: [
                        Text(
                          'Ajoutez un domaine pour commencer.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey('contracts-manage-domains-btn'),
                          onPressed: widget.onManageDomains,
                          icon: const Icon(Icons.domain),
                          label: const Text('Gestion des domaines'),
                        ),
                      ],
                    ),
                  ),
                )
              : PageView(
                  controller: _pages,
                  // Navigation par le lien et le fil d’Ariane uniquement :
                  // le glisser reste au split et au défilement de l'arbre.
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _KeepAlive(
                      child: DomainContractsEditor(
                        key: ValueKey(selected.id),
                        document: document,
                        onOpen: (id) =>
                            _goTo(1, domainId: selected.id, entryId: id),
                        onSave: (next) => widget.controller
                            .updateDomainContracts(selected.id, next),
                        codeFraction: _codeFraction,
                        onCodeFractionChanged: (value) =>
                            setState(() => _codeFraction = value),
                      ),
                    ),
                    if (opened == null)
                      const Center(child: Text('Cette entrée n’existe plus.'))
                    else
                      ContractEntryView(
                        key: const ValueKey('contract-entry-page'),
                        controller: widget.controller,
                        domainId: selected.id,
                        document: document,
                        entry: opened,
                        onOpenDomainLayer: () => _goTo(
                          2,
                          domainId: selected.id,
                          entryId: opened.id,
                        ),
                        pickAttachments: widget.pickAttachments,
                        pasteAttachments: widget.pasteAttachments,
                        hasClipboardMedia: widget.hasClipboardMedia,
                        pasteClipboardMedia: widget.pasteClipboardMedia,
                        schemaViewerSurfaceBuilder:
                            widget.schemaViewerSurfaceBuilder,
                        schemaBrowserLauncher: widget.schemaBrowserLauncher,
                      ),
                    if (opened == null)
                      const Center(child: Text('Cette entrée n’existe plus.'))
                    else
                      ContractDomainLayerView(
                        key: const ValueKey('contract-domain-layer-page'),
                        controller: widget.controller,
                        domainId: selected.id,
                        document: document,
                        entry: opened,
                        onBackToModel: () => _goTo(
                          1,
                          domainId: selected.id,
                          entryId: opened.id,
                        ),
                        pickAttachments: widget.pickAttachments,
                        pasteAttachments: widget.pasteAttachments,
                        hasClipboardMedia: widget.hasClipboardMedia,
                        pasteClipboardMedia: widget.pasteClipboardMedia,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Garde l'éditeur (brouillon DSL, synchro en attente, défilement) vivant
/// pendant l'affichage de la fiche.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
