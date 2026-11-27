/// Page des modèles et contrats, contextualisée par un domaine du workspace.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart'
    show VibeChatAttachment;

import '../../models/domain_contracts.dart';
import '../../services/spec_forge_controller.dart';
import '../workspace/markdown_viewer_dialog.dart';
import 'contract_domain_layer_view.dart';
import 'contract_entry_view.dart';
import 'design_domain_breadcrumb.dart';
import 'domain_contracts_editor.dart';

/// Affiche le fil d’Ariane et permet de changer de domaine sans quitter la page.
///
/// Le fil d’Ariane pilote un [PageView] : la liste (DSL + catalogue), la fiche
/// d'une entrée ouverte par son nom souligné (chat IA et détail de son objet)
/// puis la couche Domain. La gestion du retour est centralisée par l'`AppBar` du
/// shell via [navigationController], tandis que le fil permet de sauter
/// directement vers un niveau parent ou de changer de domaine.
class ModelsContractsView extends StatefulWidget {
  /// Crée la page à partir des domaines du catalogue actif de [controller].
  const ModelsContractsView({
    required this.controller,
    required this.onBack,
    required this.onManageDomains,
    this.initialDomainId,
    this.onOpenValueObjectsCatalog,
    this.onOpenEntryChanged,
    this.navigationController,
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

  /// Revient aux liens Design lorsque le retour remonte au-dessus de la liste.
  final VoidCallback onBack;

  /// Ouvre le catalogue des domaines quand le workspace n'en a aucun.
  final VoidCallback onManageDomains;

  /// Identifiant optionnel du domaine sélectionné à l'ouverture de la vue.
  final String? initialDomainId;

  /// Ouvre directement le Catalogue des Value Objects sur le domaine courant.
  final ValueChanged<String?>? onOpenValueObjectsCatalog;

  /// Signale au shell la fiche visible, ou le retour à la liste.
  final void Function(String? domainId, String? entryId)? onOpenEntryChanged;

  /// Contrôleur optionnel exposant le niveau courant et la commande retour
  /// à l'`AppBar` centralisée du shell.
  final ModelsContractsNavigationController? navigationController;

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

/// Contrôleur permettant au shell parent de piloter et observer le niveau
/// courant de [ModelsContractsView] pour le bouton retour de l'`AppBar`.
class ModelsContractsNavigationController extends ChangeNotifier {
  int _level = 0;
  VoidCallback? _backCallback;
  Object? _owner;

  /// Niveau courant du fil d'Ariane (`0` = liste, `1` = fiche, `2` = couche Domain).
  int get level => _level;

  void _attach(Object owner, int level, VoidCallback backCallback) {
    _owner = owner;
    _level = level;
    _backCallback = backCallback;
  }

  void _detach(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _backCallback = null;
    _level = 0;
  }

  void _updateLevel(int level) {
    if (_level == level) return;
    _level = level;
    notifyListeners();
  }

  /// Réinitialise le niveau mémorisé sans notifier (appelé lors du changement
  /// d'écran géré par le shell).
  void reset() {
    _level = 0;
  }

  /// Remonte d'un niveau dans [ModelsContractsView], ou revient au menu Design
  /// si l'écran est déjà sur la liste.
  void goBack() {
    _backCallback?.call();
  }
}

class _ModelsContractsViewState extends State<ModelsContractsView> {
  String? _selectedId;

  /// Entrée de la fiche, conservée pendant l'animation de retour à la liste.
  String? _openId;

  /// Niveau du fil d’Ariane, qui est aussi la page du [PageView] :
  /// 0 = liste des modèles et contrats, 1 = fiche de [_openId], 2 = couche Domain.
  int _level = 0;
  double _codeFraction = DomainContractsEditor.defaultCodeFraction;
  final _pages = PageController();

  @override
  void initState() {
    super.initState();
    _selectedId =
        widget.initialDomainId ?? widget.controller.activeDesignDomainId;
    widget.navigationController?._attach(this, _level, _handleBackFromShell);
  }

  @override
  void didUpdateWidget(ModelsContractsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationController != widget.navigationController) {
      oldWidget.navigationController?._detach(this);
      widget.navigationController?._attach(this, _level, _handleBackFromShell);
    }
    if (widget.initialDomainId != null &&
        widget.initialDomainId != oldWidget.initialDomainId) {
      _selectedId = widget.initialDomainId;
      _level = 0;
      _openId = null;
      widget.navigationController?._attach(this, _level, _handleBackFromShell);
      if (_pages.hasClients) {
        _pages.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    widget.navigationController?._detach(this);
    _pages.dispose();
    super.dispose();
  }

  void _handleBackFromShell() {
    final domains = widget.controller.domainCatalog.domains;
    final effectiveId = _selectedId ?? widget.controller.activeDesignDomainId;
    final selected =
        domains.where((domain) => domain.id == effectiveId).firstOrNull ??
        domains.firstOrNull;
    final document = selected?.contracts ?? DomainContracts.empty;
    final opened = document.entryById(_openId);
    _goTo(
      _level - 1,
      domainId: _level > 1 ? selected?.id : null,
      entryId: _level > 1 ? opened?.id : null,
    );
  }

  /// Seul point de navigation : remonter sous la liste sort vers le menu.
  void _goTo(int level, {String? domainId, String? entryId}) {
    if (level < 0) return widget.onBack();
    setState(() {
      _level = level;
      _openId = entryId ?? _openId;
    });
    widget.navigationController?._updateLevel(level);
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
    final effectiveId = _selectedId ?? widget.controller.activeDesignDomainId;
    final selected =
        domains.where((domain) => domain.id == effectiveId).firstOrNull ??
        domains.firstOrNull;
    final document = selected?.contracts ?? DomainContracts.empty;
    final opened = document.entryById(_openId);
    final entry = _level >= 1 ? opened : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesignDomainBreadcrumbBar(
          domains: domains,
          selectedDomain: selected,
          trailing:
              widget.onOpenValueObjectsCatalog != null &&
                  selected != null &&
                  _level == 0
              ? TextButton.icon(
                  key: const ValueKey('models-open-vo-catalog-btn'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () =>
                      widget.onOpenValueObjectsCatalog!(selected.id),
                  icon: const Icon(Icons.diamond_outlined, size: 15),
                  label: Text(
                    'Value Objects (${widget.controller.domainCatalog.resolvedValueObjectsForDomain(selected.id).length})',
                  ),
                )
              : null,
          onDomainSelected: (domain) {
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
            widget.controller.setActiveDesignDomainId(domain.id);
            if (changed) {
              widget.navigationController?._updateLevel(0);
              widget.onOpenEntryChanged?.call(null, null);
            }
          },
          segments: [
            DesignBreadcrumbSegment(
              key: const ValueKey('contracts-list-crumb'),
              label: 'Modèles et contrats',
              isParent: true,
              onTap: _level > 0 ? () => _goTo(0) : null,
            ),
            if (entry != null) ...[
              DesignBreadcrumbSegment(
                key: const ValueKey('contracts-entry-crumb'),
                label: entry.name,
                onTap: _level > 1
                    ? () => _goTo(
                        1,
                        domainId: selected?.id,
                        entryId: entry.id,
                      )
                    : null,
              ),
              DesignBreadcrumbSegment(
                label: (document.details[entry.id] ?? ContractDetails.defaults)
                    .version,
                isSecondary: true,
              ),
              if (_level >= 2)
                const DesignBreadcrumbSegment(label: 'Couche Domain'),
            ],
          ],
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
                        onOpenDomainLayer: (id) =>
                            _goTo(2, domainId: selected.id, entryId: id),
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
                        onOpenValueObjectsCatalog:
                            widget.onOpenValueObjectsCatalog == null
                            ? null
                            : () => widget.onOpenValueObjectsCatalog!(
                                selected.id,
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
