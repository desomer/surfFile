/// Structure générique de boîte de dialogue à onglets pour les éditeurs ([EditorTabbedWizard]).
library;

import 'dart:async' show FutureOr;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../history/editor_history.dart';
import '../slots/editor_slot.dart';
import '../styles/style_editor_panel.dart' show StyleEditorPanel;
import 'editor_dialog_header.dart';

/// Onglets du wizard unifié d'édition (Propriétés et Taille et marge).
enum EditorWizardTab {
  properties('Propriétés', Icons.tune_rounded),
  dimensions('Taille et marge', Icons.straighten);

  const EditorWizardTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Coordonne l'onglet initial et le délégué de dimension lors de l'ouverture
/// d'un wizard d'édition depuis le menu contextuel ou les badges d'édition.
class EditorWizardNavigation {
  const EditorWizardNavigation._();

  static EditorWizardTab? _pendingTab;
  static EditorDimensionDelegate? _pendingDelegate;

  /// Exécute [action] en demandant l'ouverture du wizard sur [tab], avec un
  /// [delegate] de dimension optionnel.
  static Future<T> openWithTab<T>(
    EditorWizardTab? tab,
    Future<T> Function() action, {
    EditorDimensionDelegate? delegate,
  }) async {
    final prevTab = _pendingTab;
    final prevDelegate = _pendingDelegate;
    if (tab != null) {
      _pendingTab = tab;
    }
    if (delegate != null) {
      _pendingDelegate = delegate;
    }
    try {
      return await action();
    } finally {
      _pendingTab = prevTab;
      _pendingDelegate = prevDelegate;
    }
  }

  /// Consomme l'onglet initial demandé, ou retourne [fallback] (par défaut
  /// [EditorWizardTab.properties]).
  static EditorWizardTab consumeInitialTab([
    EditorWizardTab? explicit,
    EditorWizardTab fallback = EditorWizardTab.properties,
  ]) {
    final pending = _pendingTab;
    _pendingTab = null;
    return explicit ?? pending ?? fallback;
  }

  /// Résout l'onglet initial effectif en revenant à [EditorWizardTab.properties]
  /// si aucun [delegate] de dimension n'est fourni.
  static EditorWizardTab resolveInitialTab(
    EditorWizardTab initialTab,
    EditorDimensionDelegate? delegate,
  ) => initialTab == EditorWizardTab.dimensions && delegate != null
      ? EditorWizardTab.dimensions
      : EditorWizardTab.properties;

  /// Consomme le délégué de dimension explicite ou résout celui attaché au
  /// [context] via l'[EditorSlotAction] inline directe.
  static EditorDimensionDelegate? resolveDimensionDelegate(
    BuildContext context, {
    EditorDimensionDelegate? explicit,
  }) {
    final pending = _pendingDelegate;
    _pendingDelegate = null;
    if (explicit != null) return explicit;
    if (pending != null) return pending;
    final action = findDirectSlotSizeAction(context);
    return action?.dimensionDelegateBuilder?.call();
  }

  /// Recherche l'[EditorSlotAction] inline de taille appartenant directement au
  /// composant de [context], sans remonter au-delà d'un [EditorSlot] parent.
  static EditorSlotAction? findDirectSlotSizeAction(BuildContext context) {
    if (context is! Element || !context.mounted) return null;
    EditorSlotAction? found;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditorSlotAction && widget.inline && widget.enabled) {
        if (widget.showEdit) {
          found = widget;
        }
        return false;
      }
      if (widget is EditorSlot) {
        return false;
      }
      return true;
    });
    return found;
  }

  /// Recherche dans le sous-arbre d'un slot ([slotContext]) le premier
  /// [EditorSlotState] enfant direct qui possède un éditeur de propriétés
  /// (`onEdit != null`).
  static EditorSlotState? findDirectChildEditorSlot(BuildContext? slotContext) {
    if (slotContext is! Element || !slotContext.mounted) return null;
    EditorSlotState? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is EditorSlotAction &&
          widget.inline &&
          widget.enabled &&
          element != slotContext) {
        return;
      }
      if (element is StatefulElement && element.state is EditorSlotState) {
        final state = element.state as EditorSlotState;
        if (state.canEdit && state.widget.onEdit != null) {
          found = state;
        }
        return;
      }
      element.visitChildren(visit);
    }

    if (slotContext is StatefulElement &&
        slotContext.state is EditorSlotState) {
      final state = slotContext.state as EditorSlotState;
      if (state.canEdit && state.widget.onEdit != null) {
        return state;
      }
    }
    slotContext.visitChildElements(visit);
    return found;
  }
}

/// Contrat d'édition pour l'onglet « Taille et marge » d'un composant ou d'une zone.
abstract class EditorDimensionDelegate {
  /// Titre affiché dans l'en-tête lorsque l'onglet « Taille et marge » est actif.
  String get title;

  /// Notifieur optionnel du nom de l'instance pour rafraîchir l'en-tête.
  ValueListenable<String>? get labelListenable => null;

  /// Nom brut éditable lors du renommage depuis l'en-tête.
  String? get editableLabel => null;

  /// Callback de renommage de l'instance.
  ValueChanged<String>? get onLabelChanged => null;

  /// Largeur préférée du contenu de l'onglet « Taille et marge ».
  double get contentWidth => 560;

  /// Synchronise le nom de l'instance lorsqu'il est modifié depuis l'onglet
  /// « Propriétés ».
  void syncLabel(String value) {}

  /// Valide les champs de dimension. Retourne `true` si tout est valide.
  bool validate() => true;

  /// Applique les dimensions lors de la confirmation du wizard (« Appliquer »).
  void apply() {}

  /// Restaure les dimensions et le nom initiaux lors de l'annulation (« Annuler »).
  void restore();

  /// Construit le contenu du formulaire de l'onglet « Taille et marge ».
  Widget buildContent(BuildContext context);

  /// Construit les boutons d'action supplémentaires propres à l'onglet
  /// « Taille et marge » (ex: « Taille et marge par défaut » ou « Réinitialiser »).
  List<Widget> buildExtraActions(
    BuildContext context, {
    required VoidCallback onResetAndClose,
  }) => const [];

  /// Libère les ressources (contrôleurs, écouteurs).
  void dispose() {}
}

/// Barre des 2 onglets (« Propriétés » et « Taille et marge ») du wizard d'édition.
///
/// N'utilise pas [TabBar] afin de supporter nativement la désactivation
/// individuelle d'un onglet et de ne pas interférer avec les composants `TabBar`.
class EditorWizardTabBar extends StatelessWidget {
  const EditorWizardTabBar({
    required this.selectedTab,
    required this.onTabSelected,
    this.propertiesEnabled = true,
    this.dimensionsEnabled = true,
    super.key,
  });

  final EditorWizardTab selectedTab;
  final ValueChanged<EditorWizardTab> onTabSelected;
  final bool propertiesEnabled;
  final bool dimensionsEnabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget buildTab(EditorWizardTab tab, {required bool enabled}) {
      final selected = selectedTab == tab;
      final key = switch (tab) {
        EditorWizardTab.properties => const ValueKey(
          'editor-wizard-tab-properties',
        ),
        EditorWizardTab.dimensions => const ValueKey(
          'editor-wizard-tab-dimensions',
        ),
      };
      final foreground = !enabled
          ? scheme.onSurface.withValues(alpha: 0.38)
          : selected
          ? scheme.primary
          : scheme.onSurfaceVariant;
      final background = selected
          ? scheme.primaryContainer.withValues(alpha: 0.45)
          : Colors.transparent;
      return Expanded(
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(8),
            mouseCursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onTap: enabled ? () => onTabSelected(tab) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  bottom: BorderSide(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2.0,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tab.icon, size: 15, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('editor-wizard-tabs'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          buildTab(EditorWizardTab.properties, enabled: propertiesEnabled),
          const SizedBox(width: 4),
          buildTab(EditorWizardTab.dimensions, enabled: dimensionsEnabled),
        ],
      ),
    );
  }
}

/// En-tête réactif d'un [EditorDimensionDelegate] écoutant [EditorDimensionDelegate.labelListenable].
class EditorDimensionHeader extends StatelessWidget {
  const EditorDimensionHeader({required this.delegate, super.key});

  final EditorDimensionDelegate delegate;

  @override
  Widget build(BuildContext context) {
    if (delegate.labelListenable case final listenable?) {
      return ValueListenableBuilder<String>(
        valueListenable: listenable,
        builder: (context, _, _) => EditorDialogHeader(
          label: delegate.title,
          editableLabel: delegate.editableLabel,
          onLabelChanged: delegate.onLabelChanged,
        ),
      );
    }
    return EditorDialogHeader(
      label: delegate.title,
      editableLabel: delegate.editableLabel,
      onLabelChanged: delegate.onLabelChanged,
    );
  }
}

/// Vue complète de l'onglet « Taille et marge » (en-tête + contenu défilant).
class EditorDimensionTabView extends StatelessWidget {
  const EditorDimensionTabView({required this.delegate, super.key});

  final EditorDimensionDelegate delegate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      EditorDimensionHeader(delegate: delegate),
      const SizedBox(height: 8),
      Expanded(
        child: SingleChildScrollView(
          child: delegate.buildContent(context),
        ),
      ),
    ],
  );
}

/// Enveloppe générique d'`AlertDialog` à 2 onglets pour les éditeurs de
/// propriétés qui retournent une configuration ou un booléen.
class EditorTabbedAlertDialog extends StatefulWidget {
  const EditorTabbedAlertDialog({
    this.dialogKey,
    this.applyButtonKey,
    this.cancelButtonKey,
    required this.initialTab,
    required this.propertiesTitle,
    required this.propertiesContentBuilder,
    this.propertiesWidth = 440,
    this.propertiesExtraActions = const [],
    required this.onApply,
    required this.onCancel,
    this.dimensionDelegate,
    this.propertiesEnabled = true,
    this.busy = false,
    super.key,
  });

  final Key? dialogKey;
  final Key? applyButtonKey;
  final Key? cancelButtonKey;
  final EditorWizardTab initialTab;
  final Widget propertiesTitle;
  final WidgetBuilder propertiesContentBuilder;
  final double propertiesWidth;
  final List<Widget> propertiesExtraActions;
  final Future<bool> Function() onApply;
  final VoidCallback onCancel;
  final EditorDimensionDelegate? dimensionDelegate;
  final bool propertiesEnabled;
  final bool busy;

  @override
  State<EditorTabbedAlertDialog> createState() =>
      _EditorTabbedAlertDialogState();
}

class _EditorTabbedAlertDialogState extends State<EditorTabbedAlertDialog> {
  late EditorWizardTab _tab = _resolveTab(widget.initialTab);

  EditorWizardTab _resolveTab(EditorWizardTab requested) {
    if (requested == EditorWizardTab.dimensions &&
        widget.dimensionDelegate != null) {
      return EditorWizardTab.dimensions;
    }
    if (requested == EditorWizardTab.properties && widget.propertiesEnabled) {
      return EditorWizardTab.properties;
    }
    if (widget.propertiesEnabled) return EditorWizardTab.properties;
    return EditorWizardTab.dimensions;
  }

  Future<void> _handleApply() async {
    final delegate = widget.dimensionDelegate;
    if (delegate != null && !delegate.validate()) {
      if (_tab != EditorWizardTab.dimensions) {
        setState(() => _tab = EditorWizardTab.dimensions);
      }
      return;
    }
    if (widget.propertiesEnabled) {
      final ok = await widget.onApply();
      if (!ok) {
        if (_tab != EditorWizardTab.properties && mounted) {
          setState(() => _tab = EditorWizardTab.properties);
        }
        return;
      }
    } else if (delegate != null) {
      delegate.apply();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final delegate = widget.dimensionDelegate;
    final onDimensions = _tab == EditorWizardTab.dimensions && delegate != null;
    final Widget headerWidget = onDimensions
        ? EditorDimensionHeader(delegate: delegate)
        : widget.propertiesTitle;

    return AlertDialog(
      key: widget.dialogKey,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      titlePadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorWizardTabBar(
            selectedTab: _tab,
            propertiesEnabled: widget.propertiesEnabled,
            dimensionsEnabled: delegate != null,
            onTabSelected: (next) {
              if (next != _tab) setState(() => _tab = next);
            },
          ),
          const SizedBox(height: 6),
          headerWidget,
        ],
      ),
      content: SizedBox(
        width: onDimensions ? delegate.contentWidth : widget.propertiesWidth,
        child: SingleChildScrollView(
          child: onDimensions
              ? delegate.buildContent(context)
              : widget.propertiesContentBuilder(context),
        ),
      ),
      actions: [
        if (onDimensions)
          ...delegate.buildExtraActions(
            context,
            onResetAndClose: () {
              if (!widget.propertiesEnabled) {
                Navigator.of(context).pop(true);
              } else {
                _handleApply();
              }
            },
          )
        else
          ...widget.propertiesExtraActions,
        TextButton(
          key: widget.cancelButtonKey,
          onPressed: widget.busy ? null : widget.onCancel,
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: widget.applyButtonKey ??
              (!onDimensions &&
                      widget.dialogKey == const ValueKey('super-tab-settings')
                  ? const ValueKey('super-tab-apply')
                  : !onDimensions &&
                        widget.dialogKey is ValueKey<String> &&
                        (widget.dialogKey! as ValueKey<String>).value.endsWith(
                          '-settings',
                        )
                  ? ValueKey(
                      '${(widget.dialogKey! as ValueKey<String>).value.substring(0, (widget.dialogKey! as ValueKey<String>).value.length - '-settings'.length)}-settings-apply',
                    )
                  : null),
          onPressed: widget.busy ? null : _handleApply,
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}

/// Signature du constructeur de l'onglet « Propriétés » d'un [EditorStyleWizardDialog].
typedef EditorStyleWizardContentBuilder =
    Widget Function(
      BuildContext context,
      bool dense,
      ValueChanged<bool> onDenseChanged,
    );

/// Enveloppe générique d'`AlertDialog` grand format à 2 onglets (« Propriétés »
/// et « Taille et marge ») pour les éditeurs basés sur [StyleEditorPanel] ou
/// `ContainerStyleEditor`.
class EditorStyleWizardDialog extends StatefulWidget {
  /// Crée un [EditorStyleWizardDialog].
  const EditorStyleWizardDialog({
    this.dialogKey,
    this.applyButtonKey,
    required this.initialTab,
    required this.dimensionDelegate,
    required this.propertiesBuilder,
    required this.onApply,
    this.onCancel,
    this.onWidthChanged,
    this.liveError,
    this.liveErrorKey,
    this.secondaryError,
    this.busy = false,
    this.minHeight = 0.0,
    this.verticalMargin = 120.0,
    super.key,
  });

  /// Clé optionnelle de l'`AlertDialog`.
  final Key? dialogKey;

  /// Clé optionnelle du bouton « Appliquer ».
  final Key? applyButtonKey;

  /// Onglet demandé à l'ouverture.
  final EditorWizardTab initialTab;

  /// Délégué de dimensionnement (« Taille et marge ») optionnel.
  final EditorDimensionDelegate? dimensionDelegate;

  /// Construit le contenu de l'onglet « Propriétés » en lui passant l'état `dense`.
  final EditorStyleWizardContentBuilder propertiesBuilder;

  /// Valide et applique les propriétés. Doit retourner `true` si la validation
  /// a réussi (et fermer la boîte de dialogue), ou `false` pour rester ouvert
  /// sur l'onglet « Propriétés ».
  final FutureOr<bool> Function() onApply;

  /// Callback optionnel d'annulation (ferme la boîte par défaut).
  final VoidCallback? onCancel;

  /// Notifié lorsque le mode compact (`680`) ou étendu (`1080`) change.
  final ValueChanged<double>? onWidthChanged;

  /// Message d'erreur principal affiché dans la barre d'actions.
  final String? liveError;

  /// Clé du widget texte affichant [liveError].
  final Key? liveErrorKey;

  /// Message d'erreur secondaire optionnel affiché dans la barre d'actions.
  final String? secondaryError;

  /// Désactive les boutons d'action pendant une validation asynchrone.
  final bool busy;

  /// Hauteur minimale du contenu du dialogue.
  final double minHeight;

  /// Marge verticale soustraite de la hauteur de l'écran.
  final double verticalMargin;

  @override
  State<EditorStyleWizardDialog> createState() =>
      _EditorStyleWizardDialogState();
}

class _EditorStyleWizardDialogState extends State<EditorStyleWizardDialog> {
  late EditorWizardTab _tab = EditorWizardNavigation.resolveInitialTab(
    widget.initialTab,
    widget.dimensionDelegate,
  );
  late bool _dense = StyleEditorPanel.preferredDense;

  Future<void> _handleApply() async {
    final delegate = widget.dimensionDelegate;
    if (delegate != null && !delegate.validate()) {
      if (_tab != EditorWizardTab.dimensions) {
        setState(() => _tab = EditorWizardTab.dimensions);
      }
      return;
    }
    final ok = await widget.onApply();
    if (!ok && mounted && _tab != EditorWizardTab.properties) {
      setState(() => _tab = EditorWizardTab.properties);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(
      _dense ? 680.0 : 1080.0,
      math.max(0.0, screen.width - 96),
    );
    final height = math.max(
      widget.minHeight,
      math.min(680.0, math.max(0.0, screen.height - widget.verticalMargin)),
    );
    final scheme = Theme.of(context).colorScheme;
    final delegate = widget.dimensionDelegate;
    final onDimensions = _tab == EditorWizardTab.dimensions && delegate != null;
    return AlertDialog(
      key: widget.dialogKey,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
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
            if (onDimensions)
              Expanded(child: EditorDimensionTabView(delegate: delegate))
            else
              Expanded(
                child: widget.propertiesBuilder(context, _dense, (value) {
                  setState(() => _dense = value);
                  widget.onWidthChanged?.call(value ? 680 : 1080);
                }),
              ),
          ],
        ),
      ),
      actions: [
        if (onDimensions)
          ...delegate.buildExtraActions(
            context,
            onResetAndClose: _handleApply,
          ),
        if (widget.liveError != null)
          Text(
            widget.liveError!,
            key: widget.liveErrorKey,
            style: TextStyle(color: scheme.error),
          ),
        if (widget.secondaryError != null)
          Text(
            widget.secondaryError!,
            style: TextStyle(color: scheme.error),
          ),
        TextButton(
          onPressed: widget.busy
              ? null
              : (widget.onCancel ?? () => Navigator.of(context).pop()),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: widget.applyButtonKey,
          onPressed: widget.busy ? null : _handleApply,
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}

/// Exécute un dialogue d'édition en lui associant automatiquement le
/// [EditorDimensionDelegate] du contexte et une transaction d'historique
/// unifiée couvrant à la fois les propriétés et les dimensions.
Future<T?> runWithDimensionDelegate<T>({
  required BuildContext context,
  EditorDimensionDelegate? explicitDelegate,
  required Future<T?> Function(
    EditorWizardTab initialTab,
    EditorDimensionDelegate? dimensionDelegate,
  )
  runner,
}) async {
  final initialTab = EditorWizardNavigation.consumeInitialTab();
  final delegate = EditorWizardNavigation.resolveDimensionDelegate(
    context,
    explicit: explicitDelegate,
  );
  final history = EditorHistoryScope.controllerOf(context);
  history?.beginTransaction();
  var committed = false;
  try {
    final result = await runner(initialTab, delegate);
    if (result != null) {
      delegate?.apply();
      history?.commitTransaction();
      committed = true;
    } else {
      delegate?.restore();
      history?.cancelTransaction();
      committed = true;
    }
    return result;
  } finally {
    if (!committed) {
      delegate?.restore();
      history?.cancelTransaction();
    }
    delegate?.dispose();
  }
}
