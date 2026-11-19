/// Menu contextuel du mode édition ([EditorContextMenu]) et portée [VibeChatScope].
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../../../models/json_syntax.dart';
import '../addition/insertion_plan.dart';
import '../dialogs/editor_tabbed_wizard.dart';

/// Type de destination ouverte par le clic principal dans le menu contextuel (style ou paramètres).
enum EditorMenuDestination { style, configuration }

/// Cible individuelle (composant ou zone) incluse dans un [VibeChatScope].
@immutable
class VibeChatScopeTarget {
  /// Crée une cible individuelle pour un scope Vibe IA.
  const VibeChatScopeTarget({
    required this.componentId,
    required this.label,
    this.zoneId,
    this.zoneLabel,
    this.parentComponentId,
  });

  /// Identifiant technique du composant ciblé.
  final String componentId;

  /// Libellé lisible du composant ciblé.
  final String label;

  /// Identifiant technique optionnel de la zone ou région ciblée dans [componentId].
  final String? zoneId;

  /// Libellé lisible optionnel de [zoneId].
  final String? zoneLabel;

  /// Identifiant technique optionnel du conteneur parent dans la hiérarchie.
  final String? parentComponentId;

  /// Identifiant canonique du composant dans `Appearance.components`.
  String get canonicalComponentId => VibeChatScope.canonicalizeId(componentId);

  /// Identifiant canonique du conteneur parent, ou `null` s'il est absent ou identique.
  String? get canonicalParentComponentId {
    final p = parentComponentId?.trim();
    if (p == null || p.isEmpty) return null;
    final canonical = VibeChatScope.canonicalizeId(p);
    return canonical == canonicalComponentId ? null : canonical;
  }

  /// Description concise et lisible de cette cible.
  String get displayLabel {
    final z = zoneLabel?.trim();
    if (z != null && z.isNotEmpty) {
      if (label.toLowerCase().contains(z.toLowerCase())) return label;
      return '$label — zone $z';
    }
    if (zoneId != null && zoneId!.isNotEmpty) {
      return '$label — zone $zoneId';
    }
    return label;
  }

  @override
  bool operator ==(Object other) =>
      other is VibeChatScopeTarget &&
      other.componentId == componentId &&
      other.label == label &&
      other.zoneId == zoneId &&
      other.zoneLabel == zoneLabel &&
      other.parentComponentId == parentComponentId;

  @override
  int get hashCode => Object.hash(
    componentId,
    label,
    zoneId,
    zoneLabel,
    parentComponentId,
  );

  @override
  String toString() =>
      'VibeChatScopeTarget(componentId: $componentId, zoneId: $zoneId, '
      'parentComponentId: $parentComponentId, label: $displayLabel)';
}

/// Target scope when launching or filtering the Vibe AI assistant from a
/// context menu entry or a lasso selection (either a single component/zone or
/// multiple targets).
@immutable
class VibeChatScope {
  const VibeChatScope({
    required this.componentId,
    required this.label,
    this.zoneId,
    this.zoneLabel,
    this.parentComponentId,
    this.additionalTargets = const <VibeChatScopeTarget>[],
  });

  /// Construit un [VibeChatScope] à partir d'une liste non vide de cibles dédupliquées.
  factory VibeChatScope.fromTargets(List<VibeChatScopeTarget> targets) {
    if (targets.isEmpty) {
      throw ArgumentError.value(
        targets,
        'targets',
        'Au moins une cible est requise pour créer un VibeChatScope.',
      );
    }
    final unique = <VibeChatScopeTarget>[];
    final seen = <(String, String?)>{};
    for (final target in targets) {
      final key = (target.canonicalComponentId, target.zoneId);
      if (seen.add(key)) {
        unique.add(target);
      }
    }
    final first = unique.first;
    return VibeChatScope(
      componentId: first.componentId,
      label: first.label,
      zoneId: first.zoneId,
      zoneLabel: first.zoneLabel,
      parentComponentId: first.parentComponentId,
      additionalTargets: unique.length > 1
          ? List<VibeChatScopeTarget>.unmodifiable(unique.sublist(1))
          : const <VibeChatScopeTarget>[],
    );
  }

  /// Technical identifier of the primary target component (e.g. layout, card,
  /// list, native component, value, action).
  final String componentId;

  /// Human-readable label of the primary target component.
  final String label;

  /// Optional technical zone/region identifier within [componentId] (e.g.
  /// `'center'`, `'west'`, `'body'`, `'appBar'`).
  final String? zoneId;

  /// Optional human-readable label for [zoneId].
  final String? zoneLabel;

  /// Optional technical identifier of the parent container component in the
  /// widget hierarchy, when known at selection time.
  final String? parentComponentId;

  /// Additional targets included alongside the primary target (e.g. from a
  /// lasso selection).
  final List<VibeChatScopeTarget> additionalTargets;

  /// Registered callback by the active `StyleEditBanner` to open its floating
  /// `VibeChatDialog` focused on the requested scope.
  static bool Function(VibeChatScope scope)? onOpenRequested;

  /// Canonicalizes a component/surface ID to its `Appearance.components` key.
  static String canonicalizeId(String id) {
    if (id.endsWith(':layout')) {
      return id.substring(0, id.length - ':layout'.length);
    }
    if (id.endsWith(':item')) {
      return id.substring(0, id.length - ':item'.length);
    }
    return id;
  }

  /// Indique si ce scope cible plusieurs composants ou zones simultanément.
  bool get isMultiTarget => additionalTargets.isNotEmpty;

  /// Cible principale représentée sous forme de [VibeChatScopeTarget].
  VibeChatScopeTarget get primaryTarget => VibeChatScopeTarget(
    componentId: componentId,
    label: label,
    zoneId: zoneId,
    zoneLabel: zoneLabel,
    parentComponentId: parentComponentId,
  );

  /// Ensemble ordonné de toutes les cibles incluses dans ce scope.
  List<VibeChatScopeTarget> get allTargets => additionalTargets.isEmpty
      ? List<VibeChatScopeTarget>.unmodifiable([primaryTarget])
      : List<VibeChatScopeTarget>.unmodifiable([
          primaryTarget,
          ...additionalTargets,
        ]);

  /// Identifiants canoniques de tous les composants ciblés dans `Appearance.components`.
  Set<String> get canonicalComponentIds => Set<String>.unmodifiable({
    canonicalComponentId,
    for (final target in additionalTargets) target.canonicalComponentId,
  });

  /// Canonical component ID in `Appearance.components`.
  String get canonicalComponentId => canonicalizeId(componentId);

  /// Canonical parent component ID in `Appearance.components`, if specified.
  String? get canonicalParentComponentId {
    final p = parentComponentId?.trim();
    if (p == null || p.isEmpty) return null;
    final canonical = canonicalizeId(p);
    return canonical == canonicalComponentId ? null : canonical;
  }

  /// Concise human-readable description of this scope.
  String get displayLabel {
    if (additionalTargets.isEmpty) {
      return primaryTarget.displayLabel;
    }
    final targets = allTargets;
    final preview = targets.take(2).map((t) => t.displayLabel).join(', ');
    final extra = targets.length > 2 ? ', +${targets.length - 2}' : '';
    return '${targets.length} éléments ($preview$extra)';
  }

  @override
  bool operator ==(Object other) =>
      other is VibeChatScope &&
      other.componentId == componentId &&
      other.label == label &&
      other.zoneId == zoneId &&
      other.zoneLabel == zoneLabel &&
      other.parentComponentId == parentComponentId &&
      listEquals(other.additionalTargets, additionalTargets);

  @override
  int get hashCode => Object.hash(
    componentId,
    label,
    zoneId,
    zoneLabel,
    parentComponentId,
    Object.hashAll(additionalTargets),
  );

  @override
  String toString() =>
      'VibeChatScope(componentId: $componentId, zoneId: $zoneId, '
      'parentComponentId: $parentComponentId, '
      'additionalTargets: ${additionalTargets.length}, label: $displayLabel)';
}

/// Action d'encapsulation ou de désencapsulation proposée dans le menu contextuel d'un slot.
class EditorSlotWrapAction {
  const EditorSlotWrapAction({
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onSelected;
}

/// Extra menu action contributed by an editor owner to an `EditorSlot`.
class EditorSlotAction extends InheritedWidget {
  const EditorSlotAction({
    required this.label,
    required this.onEdit,
    required this.enabled,
    this.tooltip,
    this.onRemove,
    this.onSelect,
    this.inline = false,
    this.showEdit = true,
    this.scrollable = false,
    this.fixedHeight = false,
    this.fixedWidth = false,
    this.wrapActions = const [],
    this.insertion,
    this.dimensionDelegateBuilder,
    this.destination = EditorMenuDestination.configuration,
    required super.child,
    super.key,
  });

  final String label;
  final String? tooltip;
  final Future<void> Function() onEdit;
  final bool enabled;
  final Future<void> Function()? onRemove;
  final VoidCallback? onSelect;
  final bool inline;
  final bool showEdit;
  final bool scrollable;
  final bool fixedHeight;
  final bool fixedWidth;
  final List<EditorSlotWrapAction> wrapActions;

  /// Adds a component around this child through the contextual wizard.
  final EditorSlotInsertion? insertion;

  /// Builds the dimension delegate for the unified 2-tab wizard.
  final EditorDimensionDelegate Function()? dimensionDelegateBuilder;
  final EditorMenuDestination destination;

  static List<EditorSlotAction> of(BuildContext context) {
    final actions = <EditorSlotAction>[];
    var hasInlineAction = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditorSlotAction && widget.enabled) {
        if (!widget.inline || !hasInlineAction) actions.add(widget);
        if (widget.inline) hasInlineAction = true;
      }
      return true;
    });
    return actions;
  }

  @override
  bool updateShouldNotify(EditorSlotAction oldWidget) =>
      label != oldWidget.label ||
      tooltip != oldWidget.tooltip ||
      enabled != oldWidget.enabled ||
      onEdit != oldWidget.onEdit ||
      onRemove != oldWidget.onRemove ||
      onSelect != oldWidget.onSelect ||
      wrapActions != oldWidget.wrapActions ||
      insertion != oldWidget.insertion ||
      dimensionDelegateBuilder != oldWidget.dimensionDelegateBuilder ||
      inline != oldWidget.inline ||
      showEdit != oldWidget.showEdit ||
      scrollable != oldWidget.scrollable ||
      fixedHeight != oldWidget.fixedHeight ||
      fixedWidth != oldWidget.fixedWidth ||
      destination != oldWidget.destination;
}

/// Inserts a command at its ancestor position among editor menu entries.
class EditorContextMenuEntry extends InheritedWidget {
  const EditorContextMenuEntry({
    required this.label,
    required this.onSelected,
    required this.enabled,
    this.tooltip,
    this.scrollable = false,
    this.fixedHeight = false,
    this.fixedWidth = false,
    this.destination = EditorMenuDestination.configuration,
    required super.child,
    super.key,
  });

  final String label;
  final String? tooltip;
  final Future<void> Function() onSelected;
  final bool enabled;
  final bool scrollable;
  final bool fixedHeight;
  final bool fixedWidth;
  final EditorMenuDestination destination;

  @override
  bool updateShouldNotify(EditorContextMenuEntry oldWidget) =>
      label != oldWidget.label ||
      tooltip != oldWidget.tooltip ||
      onSelected != oldWidget.onSelected ||
      enabled != oldWidget.enabled ||
      scrollable != oldWidget.scrollable ||
      fixedHeight != oldWidget.fixedHeight ||
      fixedWidth != oldWidget.fixedWidth ||
      destination != oldWidget.destination;
}

final RegExp _tooltipHexColorPattern = RegExp(
  r'#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6})\b',
);

/// Petite pastille de couleur affichée à côté d'une valeur de couleur
/// hexadécimale dans l'infobulle de résumé du menu contextuel de l'éditeur.
class EditorTooltipColorSwatch extends StatelessWidget {
  const EditorTooltipColorSwatch({
    required this.color,
    this.size = 10,
    super.key,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0x99FFFFFF),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _ColorSwatchWidgetSpan extends WidgetSpan {
  const _ColorSwatchWidgetSpan({required super.child})
    : super(alignment: PlaceholderAlignment.middle);

  @override
  void computeToPlainText(
    StringBuffer buffer, {
    bool includeSemanticsLabels = true,
    bool includePlaceholders = true,
  }) {}
}

/// Construit un [InlineSpan] enrichi avec une pastille [EditorTooltipColorSwatch]
/// devant chaque code couleur hexadécimal (`#RRGGBB` ou `#AARRGGBB`), ou `null`
/// si [message] ne contient aucune valeur de couleur.
InlineSpan? buildEditorTooltipRichMessage(String message) {
  final matches = _tooltipHexColorPattern.allMatches(message).toList();
  if (matches.isEmpty) return null;

  final children = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      children.add(TextSpan(text: message.substring(cursor, match.start)));
    }
    final token = match.group(0)!;
    final color = JsonColor.parse(token);
    children.add(
      _ColorSwatchWidgetSpan(
        child: EditorTooltipColorSwatch(color: color),
      ),
    );
    children.add(TextSpan(text: token));
    cursor = match.end;
  }
  if (cursor < message.length) {
    children.add(TextSpan(text: message.substring(cursor)));
  }
  return TextSpan(children: children);
}

