/// Contrats partagés par l’assistant d’ajout et les configurateurs de composants.
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/component_tag_filter.dart';
import '../../../models/json_text_binding.dart';
import '../../../models/registry.dart';
import '../../../models/super_layout_config.dart';
import 'insertion_plan.dart';

/// Famille affichée dans les filtres de l’assistant d’ajout de composants.
enum ComponentAddFamily {
  standard('Standard'),
  extended('Étendu'),
  container('Container'),
  composed('Composé'),
  user('Utilisateur');

  const ComponentAddFamily(this.label);

  /// Libellé français présenté dans le wizard.
  final String label;
}

/// Component-specific settings edited by the add wizard before insertion.
///
/// The draft [T] is created by [initial], edited by [builder], described in
/// the summary by [summary] and written under the new instance ID by [apply]
/// once the wizard is confirmed. [validate] returns a blocking message.
///
/// With [readBinding] and [writeBinding], the wizard adds a dedicated
/// « Liaison » step editing the repository binding of the draft; the
/// settings step is then validated without that binding.
class ComponentAddConfigurator<T extends Object> {
  const ComponentAddConfigurator({
    required this._initial,
    required this._builder,
    required this._summary,
    required this._apply,
    this._validate,
    this._readBinding,
    this._writeBinding,
    this.bindingKeyPrefix = 'add-binding',
    this.bindingPathHint = '',
    this.bindingHelp,
  }) : assert((_readBinding == null) == (_writeBinding == null));

  final T Function(BuildContext context) _initial;
  final Widget Function(BuildContext, T, ValueChanged<T>) _builder;
  final List<(String, String)> Function(T) _summary;
  final void Function(Registry, String, T) _apply;
  final String? Function(T)? _validate;
  final JsonTextBinding? Function(T)? _readBinding;
  final T Function(T, JsonTextBinding?)? _writeBinding;

  /// Key prefix of the repository fields of the « Liaison » step.
  final String bindingKeyPrefix;
  final String bindingPathHint;

  /// Explanation shown under the binding fields when a binding is set.
  final String? bindingHelp;

  bool get supportsBinding => _readBinding != null;

  JsonTextBinding? bindingOf(Object draft) => _readBinding?.call(draft as T);

  Object withBinding(Object draft, JsonTextBinding? binding) =>
      _writeBinding == null ? draft : _writeBinding(draft as T, binding);

  Object initialDraft(BuildContext context) => _initial(context);

  Widget buildDraft(
    BuildContext context,
    Object draft,
    ValueChanged<Object> onChanged,
  ) => _builder(context, draft as T, onChanged);

  List<(String, String)> summarize(Object draft) => _summary(draft as T);

  String? validateDraft(Object draft) => _validate?.call(draft as T);

  void applyDraft(Registry registry, String id, Object draft) =>
      _apply(registry, id, draft as T);
}

/// A component proposed by the add wizard.
class ComponentAddCandidate {
  const ComponentAddCandidate({
    required this.id,
    required this.label,
    this.family = ComponentAddFamily.user,
    this.addOrder = 0,
    this.tags = const {},
    this.placementTags = const {},
    this.configurator,
    this.previewBuilder,
  });

  /// Value identifying the component for the caller (slot ID or type).
  final String id;
  final String label;

  /// Famille utilisée pour filtrer et classer ce composant dans le wizard.
  final ComponentAddFamily family;

  /// Ordre croissant dans la famille ; à égalité, l'ordre initial est conservé.
  final int addOrder;
  final Set<String> tags;

  /// Restricts the component to targets dedicated to one of these tags; see
  /// [ComponentTagFilter.fits].
  final Set<String> placementTags;
  final ComponentAddConfigurator<Object>? configurator;

  /// Optional preview widget builder shown when this candidate is selected.
  final WidgetBuilder? previewBuilder;

  /// Whether the component fits a target dedicated to [zoneTags] whose filter
  /// is [accepts].
  bool fitsIn(Set<String> zoneTags, bool Function(Set<String>) accepts) =>
      accepts(tags) && ComponentTagFilter.fits(placementTags, zoneTags);
}

/// A zone or region able to receive the new component.
class ComponentAddTarget {
  const ComponentAddTarget({
    required this.id,
    required this.label,
    this.siblings = const [],
    this.accepts,
    this.zoneTags = const {},
    this.replaces = false,
    this.preview,
    this.previewFor,
  });

  final String id;
  final String label;

  /// Components already placed, in order, as `(id, label)`.
  final List<(String, String)> siblings;
  final bool Function(Set<String> tags)? accepts;

  /// Tags the zone is dedicated to (its filter's `include`).
  final Set<String> zoneTags;

  /// The target holds a single component, replaced by the addition.
  final bool replaces;

  /// Visual preview of the target zone when appending to it.
  final ComponentAddPlacementPreview? preview;

  /// Visual preview for a specific sibling position (`beforeId`, or null for
  /// the end of the zone).
  final ComponentAddPlacementPreview? Function(String? beforeId)? previewFor;

  ComponentAddPlacementPreview? resolvePreview([String? beforeId]) =>
      previewFor?.call(beforeId) ?? preview;

  bool accept(Set<String> tags) => accepts?.call(tags) ?? true;

  bool admits(ComponentAddCandidate candidate) =>
      candidate.fitsIn(zoneTags, accept);
}

/// A position relative to the edited element, offered instead of zones.
class ComponentAddPlacement {
  const ComponentAddPlacement({
    required this.id,
    required this.group,
    required this.label,
    required this.icon,
    this.hint,
    this.accepts,
    this.zoneTags = const {},
    this.preview,
  });

  final String id;

  /// Title of the element the position refers to.
  final String group;
  final String label;
  final IconData icon;

  /// Structural consequence, such as an added wrapper.
  final String? hint;
  final bool Function(Set<String> tags)? accepts;

  /// Tags the receiving zone is dedicated to (its filter's `include`).
  final Set<String> zoneTags;

  /// Visual preview of the placement on the page.
  final ComponentAddPlacementPreview? preview;

  bool accept(Set<String> tags) => accepts?.call(tags) ?? true;

  bool admits(ComponentAddCandidate candidate) =>
      candidate.fitsIn(zoneTags, accept);
}

/// Scope informant les configurateurs d'ajout ([ComponentAddConfigurator]) de la zone ou région ciblée.
class ComponentAddTargetScope extends InheritedWidget {
  const ComponentAddTargetScope({
    required this.targetId,
    required this.targetLabel,
    this.initialTargetId = '',
    this.wizardTitle = '',
    this.zoneTags = const {},
    required super.child,
    super.key,
  });

  /// Identifiant de la zone ciblée (ex: `'tabs'`, `'center'`, `'content'`).
  final String targetId;

  /// Libellé de la zone ciblée (ex: `'Onglets'`, `'Onglet gabarit'`).
  final String targetLabel;

  /// Cible initiale demandée à l'ouverture du wizard.
  final String initialTargetId;

  /// Titre du wizard (ex: `'Ajouter dans Onglets'`).
  final String wizardTitle;

  /// Tags associés à la zone.
  final Set<String> zoneTags;

  static ComponentAddTargetScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ComponentAddTargetScope>();

  /// Indique si la zone cible correspond à la zone des onglets d'une [SuperTab].
  bool get isTabZone {
    final lowerId = targetId.toLowerCase();
    final lowerInit = initialTargetId.toLowerCase();
    final lowerLabel = targetLabel.toLowerCase();
    final lowerTitle = wizardTitle.toLowerCase();
    return lowerId == 'tabs' ||
        lowerInit == 'tabs' ||
        lowerId.contains('tab') ||
        lowerInit.contains('tab') ||
        lowerLabel.contains('onglet') ||
        lowerTitle.contains('onglet');
  }

  @override
  bool updateShouldNotify(ComponentAddTargetScope oldWidget) =>
      targetId != oldWidget.targetId ||
      targetLabel != oldWidget.targetLabel ||
      initialTargetId != oldWidget.initialTargetId ||
      wizardTitle != oldWidget.wizardTitle ||
      zoneTags != oldWidget.zoneTags;
}

/// Result of the add wizard.
class ComponentAddRequest {
  const ComponentAddRequest({
    required this.component,
    required this.targetId,
    this.beforeId,
    this.label,
    this.size,
    this.draft,
    this.placementId,
  });

  final ComponentAddCandidate component;
  final String targetId;

  /// Chosen [ComponentAddPlacement.id], when the wizard offers placements.
  final String? placementId;

  /// Sibling placed after the new component; null appends it.
  final String? beforeId;

  /// Instance label; null keeps the component label.
  final String? label;

  /// Explicit size; null keeps the caller's default sizing.
  final SlotSizeConstraints? size;

  /// Component-specific draft, applied by [applyConfiguration].
  final Object? draft;

  void applyConfiguration(Registry? registry, String instanceId) {
    final configurator = component.configurator;
    final value = draft;
    if (registry != null && configurator != null && value != null) {
      configurator.applyDraft(registry, instanceId, value);
    }
  }
}
