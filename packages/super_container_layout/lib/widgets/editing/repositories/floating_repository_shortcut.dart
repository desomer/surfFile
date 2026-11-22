/// Raccourci clavier global (`F2`) et résolution de liaison pour ouvrir l'éditeur JSON flottant.
///
/// Inspecte le composant actuellement sélectionné dans [LayoutSelection] (ou le
/// composant détenant le focus clavier hors mode édition) afin d'extraire son
/// [JsonTextBinding] direct, ou à défaut le premier [JsonTextBinding] trouvé en
/// parcourant ses enfants montés puis ses slots enfants persistés dans
/// [Appearance]. Ouvre le repository correspondant via
/// [openBoundRepositoryOrManager] (avec repli sur [JsonRepositoryManager]).
library;

import 'dart:async' show unawaited;
import 'dart:collection' show Queue;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/component_behavior.dart';
import '../../../models/component_config.dart';
import '../../../models/json_text_binding.dart';
import '../../../models/native_component_config.dart';
import '../../../models/registry.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/super_conditional_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../models/super_table_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../models/super_value_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../super_app.dart';
import '../../../super_page.dart';
import '../../../theme/appearance.dart';
import '../../appearance/appearance_scope.dart';
import '../../components/super_component.dart';
import '../../components/super_layout/layout_selection.dart';
import '../dialogs/json_extract/extract_contracts.dart';
import '../overlay/editor_zoom.dart';
import '../slots/editor_slot.dart';
import 'floating_repository_editor.dart';

/// Résout l'identifiant du repository JSON lié au composant sélectionné (ou à
/// défaut au premier de ses enfants liés), en mode édition comme hors mode édition.
///
/// Retourne `null` si aucun composant n'est sélectionné ou si aucune liaison
/// vers un repository JSON n'est trouvée dans le sous-arbre cible.
String? resolveSelectedBoundRepositoryId(
  BuildContext context, {
  Appearance? appearance,
  Registry? registry,
  BuildContext? targetOverride,
}) {
  final target = _resolveTargetRoot(context, targetOverride: targetOverride);
  if (target == null) return null;
  final rootElement = target.element;
  if (!rootElement.mounted) return null;

  final resolvedAppearance =
      appearance ??
      AppearanceScope.controllerOf(rootElement)?.value ??
      AppearanceScope.controllerOf(context)?.value ??
      Appearance();
  final resolvedRegistry =
      registry ??
      SuperApp.maybeOf(rootElement)?.registry ??
      SuperApp.maybeOf(context)?.registry;
  final snapshot = resolvedRegistry != null
      ? resolvedRegistry.appearanceSnapshot(resolvedAppearance)
      : resolvedAppearance;

  final initialInheritedRepo =
      JsonListScope.maybeOf(rootElement)?.repositoryId ??
      _enclosingCollectionRepositoryId(rootElement, snapshot);

  final elementQueue = Queue<(Element, String?)>()
    ..add((rootElement, initialInheritedRepo));
  final persistedRoots =
      <({String id, String? zoneId, String? inheritedRepoId})>[];
  final visitedComponentIds = <String>{};

  while (elementQueue.isNotEmpty) {
    final (el, parentRepoId) = elementQueue.removeFirst();
    if (!el.mounted) continue;

    var currentRepoId = JsonListScope.maybeOf(el)?.repositoryId ?? parentRepoId;

    if (el is StatefulElement) {
      final state = el.state;
      if (state is EditorSlotState && state.mounted) {
        final id = state.effectiveComponentId;
        final zoneId = state.widget.zoneId;
        if (zoneId != null && zoneId.isNotEmpty) {
          final zoneRepo = _resolveZoneBindingRepositoryId(
            id: id,
            zoneId: zoneId,
            snapshot: snapshot,
            fallbackBehaviors: state.widget.behaviors,
            inheritedRepoId: currentRepoId,
          );
          if (zoneRepo != null) return zoneRepo;
          if (id.isNotEmpty) {
            persistedRoots.add((
              id: id,
              zoneId: zoneId,
              inheritedRepoId: currentRepoId,
            ));
          }
        } else {
          if (id.isNotEmpty) visitedComponentIds.add(id);
          final directRepo = _resolveComponentRepositoryId(
            id: id,
            snapshot: snapshot,
            fallbackBehaviors: state.widget.behaviors,
            inheritedRepoId: currentRepoId,
          );
          if (directRepo != null) return directRepo;
          currentRepoId = _collectionRepositoryId(
            snapshot.components[id],
            currentRepoId,
          );
          if (id.isNotEmpty) {
            persistedRoots.add((
              id: id,
              zoneId: null,
              inheritedRepoId: currentRepoId,
            ));
          }
        }
      } else if (state case final JsonExtractableState extractable
          when extractable.isExtractableMounted) {
        final id = extractable.extractableId;
        if (id.isNotEmpty) {
          visitedComponentIds.add(id);
          final directRepo = _resolveComponentRepositoryId(
            id: id,
            snapshot: snapshot,
            inheritedRepoId: currentRepoId,
          );
          if (directRepo != null) return directRepo;
        }
      }
    }

    if (el.widget case final SuperComponent<ComponentConfig?> comp
        when comp is! SuperPage) {
      final id = comp.id ?? '';
      if (id.isNotEmpty) visitedComponentIds.add(id);
      final directRepo = _resolveComponentRepositoryId(
        id: id,
        snapshot: snapshot,
        fallbackConfig: comp.config,
        fallbackBehaviors: comp.behaviours,
        inheritedRepoId: currentRepoId,
      );
      if (directRepo != null) return directRepo;
      currentRepoId = _collectionRepositoryId(
        (id.isNotEmpty ? snapshot.components[id] : null) ?? comp.config,
        currentRepoId,
      );
      if (id.isNotEmpty) {
        persistedRoots.add((
          id: id,
          zoneId: null,
          inheritedRepoId: currentRepoId,
        ));
      }
    }

    el.visitChildElements((child) {
      elementQueue.add((child, currentRepoId));
    });
  }

  // Parcours en largeur de secours sur les enfants persistés non montés
  // (onglets inactifs, branches conditionnelles, listes vides, panneaux repliés).
  final persistedQueue = Queue<(String, String?)>();
  for (final root in persistedRoots) {
    for (final childId in _persistedChildSlotIds(
      root.id,
      snapshot,
      zoneId: root.zoneId,
    )) {
      persistedQueue.add((childId, root.inheritedRepoId));
    }
  }

  while (persistedQueue.isNotEmpty) {
    final (id, parentRepoId) = persistedQueue.removeFirst();
    if (id.isEmpty) continue;
    if (visitedComponentIds.add(id)) {
      final repo = _resolveComponentRepositoryId(
        id: id,
        snapshot: snapshot,
        inheritedRepoId: parentRepoId,
      );
      if (repo != null) return repo;
    }
    final nextRepoId = _collectionRepositoryId(
      snapshot.components[id],
      parentRepoId,
    );
    for (final childId in _persistedChildSlotIds(id, snapshot)) {
      if (!visitedComponentIds.contains(childId)) {
        persistedQueue.add((childId, nextRepoId));
      }
    }
  }

  return null;
}

/// Ouvre l'éditeur JSON flottant du repository lié au composant sélectionné
/// (ou au premier de ses enfants liés), ou ouvre [JsonRepositoryManager] si
/// aucune liaison n'est trouvée.
Future<void> openSelectedComponentRepositoryEditor(
  BuildContext context, {
  JsonRepositoryStore? store,
  Appearance? appearance,
  Registry? registry,
}) {
  final target = _resolveTargetRoot(context);
  final repositoryId = target == null
      ? null
      : resolveSelectedBoundRepositoryId(
          context,
          appearance: appearance,
          registry: registry,
          targetOverride: target.element,
        );
  return openBoundRepositoryOrManager(
    context,
    repositoryId: repositoryId,
    targetContext: target?.element,
    store: store,
  );
}

/// Intercepte la touche `F2` (en mode édition comme hors mode édition) pour
/// ouvrir l'éditeur JSON flottant associé au composant sélectionné.
class FloatingRepositoryShortcut extends StatefulWidget {
  /// Crée le raccourci clavier `F2` vers l'éditeur JSON flottant.
  const FloatingRepositoryShortcut({
    required this.child,
    this.navigatorKey,
    this.store,
    this.appearance,
    this.registry,
    super.key,
  });

  /// Sous-arbre enveloppé par le raccourci.
  final Widget child;

  /// Clé optionnelle du [Navigator] fournissant le [BuildContext] d'ouverture.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Store de repositories JSON explicite ; utilise [JsonRepositoryScope] sinon.
  final JsonRepositoryStore? store;

  /// Apparence réactive explicite ; utilise [AppearanceScope] sinon.
  final ValueListenable<Appearance>? appearance;

  /// Registre de composants explicite ; utilise [SuperApp] sinon.
  final Registry? registry;

  @override
  State<FloatingRepositoryShortcut> createState() =>
      _FloatingRepositoryShortcutState();
}

class _FloatingRepositoryShortcutState
    extends State<FloatingRepositoryShortcut> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.f2 ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return false;
    }
    if (!mounted) return false;
    final hostContext =
        widget.navigatorKey?.currentState?.overlay?.context ??
        widget.navigatorKey?.currentContext ??
        context;
    if (!hostContext.mounted ||
        (Navigator.maybeOf(hostContext) == null &&
            Overlay.maybeOf(hostContext) == null)) {
      return false;
    }
    if (_opening) return true;
    _opening = true;
    unawaited(
      openSelectedComponentRepositoryEditor(
        hostContext,
        store: widget.store,
        appearance: widget.appearance?.value,
        registry: widget.registry,
      ).whenComplete(() {
        _opening = false;
      }),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

({Element element})? _resolveTargetRoot(
  BuildContext context, {
  BuildContext? targetOverride,
}) {
  if (targetOverride is Element && targetOverride.mounted) {
    return (element: targetOverride);
  }

  final leafId = LayoutSelection.activeLeafId;
  Element? narrowToPreferredLeaf(Element root) {
    if (leafId == null || leafId.isEmpty) return root;
    if (root is StatefulElement && root.state is EditorSlotState) {
      final state = root.state as EditorSlotState;
      if (state.widget.zoneId == null && state.effectiveComponentId == leafId) {
        return root;
      }
    }
    Element? matched;
    void visit(Element el) {
      if (matched != null) return;
      if (el is StatefulElement && el.state is EditorSlotState) {
        final state = el.state as EditorSlotState;
        if (state.mounted &&
            state.widget.zoneId == null &&
            state.effectiveComponentId == leafId) {
          matched = el;
          return;
        }
      }
      el.visitChildren(visit);
    }

    root.visitChildElements(visit);
    return matched ?? root;
  }

  final dialogTarget = EditorZoomScope.controllerOf(context)?.dialog.value?.target;
  if (dialogTarget is Element && dialogTarget.mounted) {
    return (element: narrowToPreferredLeaf(dialogTarget)!);
  }

  final selectionFocus = LayoutSelection.focus.value?.context;
  if (selectionFocus is Element && selectionFocus.mounted) {
    return (element: narrowToPreferredLeaf(selectionFocus)!);
  }

  if (LayoutSelection.path.value.isNotEmpty) {
    final slot = LayoutSelection.resolveSlotForPath(LayoutSelection.path.value);
    if (slot != null && slot.mounted && slot.context is Element) {
      return (element: narrowToPreferredLeaf(slot.context as Element)!);
    }
  }

  final primaryFocus = FocusManager.instance.primaryFocus;
  if (primaryFocus != null && primaryFocus is! FocusScopeNode) {
    final focusedContext = primaryFocus.context;
    if (focusedContext is Element && focusedContext.mounted) {
      Element? componentElement;
      focusedContext.visitAncestorElements((ancestor) {
        final w = ancestor.widget;
        if (w is KeyedSubtree || w is Material) {
          if (w.key case ValueKey<String>(:final value)
              when value.startsWith('floating-repository-')) {
            componentElement = null;
            return false;
          }
        }
        if (w is SuperComponent && w is! SuperPage) {
          componentElement = ancestor;
          return false;
        }
        if (ancestor is StatefulElement && ancestor.state is EditorSlotState) {
          final state = ancestor.state as EditorSlotState;
          if (state.widget.zoneId == null) {
            componentElement = ancestor;
            return false;
          }
        }
        return true;
      });
      if (componentElement != null && componentElement!.mounted) {
        return (element: componentElement!);
      }
    }
  }

  return null;
}

String? _enclosingCollectionRepositoryId(Element element, Appearance snapshot) {
  String? found;
  element.visitAncestorElements((ancestor) {
    String? id;
    ComponentConfig? fallback;
    if (ancestor is StatefulElement && ancestor.state is EditorSlotState) {
      final slot = ancestor.state as EditorSlotState;
      if (slot.widget.zoneId == null) id = slot.effectiveComponentId;
    } else if (ancestor.widget case final SuperComponent<ComponentConfig?> c) {
      id = c.id;
      fallback = c.config;
    }
    final config =
        (id != null && id.isNotEmpty ? snapshot.components[id] : null) ??
        fallback;
    final repo = _collectionRepositoryId(config, null);
    if (repo != null && repo.isNotEmpty) {
      found = repo;
      return false;
    }
    return true;
  });
  return found;
}

String? _resolveBindingRepoId(
  JsonTextBinding? binding,
  String? inheritedRepoId,
) {
  if (binding == null || binding.path.trim().isEmpty) return null;
  final explicit = binding.repositoryId?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final inherited = inheritedRepoId?.trim();
  if (inherited != null && inherited.isNotEmpty) return inherited;
  return null;
}

String? _collectionRepositoryId(
  ComponentConfig? config,
  String? inheritedRepoId,
) {
  final binding = switch (config) {
    SuperListViewConfig(:final binding) => binding,
    SuperTableConfig(:final binding) => binding,
    SuperTreeViewConfig(:final binding) => binding,
    SuperTabConfig(:final binding) => binding,
    _ => null,
  };
  return _resolveBindingRepoId(binding, inheritedRepoId) ?? inheritedRepoId;
}

String? _resolveZoneBindingRepositoryId({
  required String id,
  required String zoneId,
  required Appearance snapshot,
  List<ComponentBehavior>? fallbackBehaviors,
  required String? inheritedRepoId,
}) {
  final behaviors =
      fallbackBehaviors ?? (id.isEmpty ? const [] : snapshot.behaviorsFor(id));
  for (final behavior in behaviors) {
    if (!behavior.enabled) continue;
    if (behavior.action case final ZoneSizeBindingAction zoneAction
        when zoneAction.zone.name == zoneId) {
      final resolved = _resolveBindingRepoId(
        zoneAction.binding,
        inheritedRepoId,
      );
      if (resolved != null) return resolved;
    }
  }
  return null;
}

String? _resolveComponentRepositoryId({
  required String id,
  required Appearance snapshot,
  ComponentConfig? fallbackConfig,
  List<ComponentBehavior>? fallbackBehaviors,
  required String? inheritedRepoId,
}) {
  final config =
      (id.isNotEmpty ? snapshot.components[id] : null) ?? fallbackConfig;
  if (config != null) {
    if (config is SuperValueConfig) {
      for (final primary in [config.binding, config.choice.optionsBinding]) {
        final resolved = _resolveBindingRepoId(primary, inheritedRepoId);
        if (resolved != null) return resolved;
      }
    }
    for (final binding in config.referencedBindings) {
      final resolved = _resolveBindingRepoId(binding, inheritedRepoId);
      if (resolved != null) return resolved;
    }
  }

  if (id.isNotEmpty) {
    final style = snapshot.styles[id];
    if (style != null) {
      for (final binding in [
        style.imageBinding,
        ...style.propertyBindings.values,
        style.states?.binding,
        for (final override in [
          ...?style.states?.named.values,
          ?style.states?.hover?.style,
          ?style.states?.selected?.style,
          ...?style.states?.automatic.values.map((s) => s.style),
        ])
          ...override.propertyBindings.values,
      ]) {
        final resolved = _resolveBindingRepoId(binding, inheritedRepoId);
        if (resolved != null) return resolved;
      }
    }
  }

  final behaviors =
      fallbackBehaviors ?? (id.isEmpty ? const [] : snapshot.behaviorsFor(id));
  for (final behavior in behaviors) {
    if (!behavior.enabled) continue;
    final binding = switch (behavior.action) {
      StateBindingAction(:final binding) => binding,
      TooltipAction(:final binding) => binding,
      ZoneSizeBindingAction(:final binding) => binding,
      _ => null,
    };
    final resolved = _resolveBindingRepoId(binding, inheritedRepoId);
    if (resolved != null) return resolved;
  }

  return null;
}

List<String> _persistedChildSlotIds(
  String id,
  Appearance snapshot, {
  String? zoneId,
}) {
  if (id.isEmpty) return const [];
  final config = snapshot.components[id] ?? snapshot.layouts[id];
  if (config == null) return const [];

  if (zoneId != null && zoneId.isNotEmpty) {
    return switch (config) {
      SuperLayoutConfig() =>
        zoneId == 'grid'
            ? config.grid?.items.keys.toList() ?? const []
            : [
                for (final entry in config.placements.entries)
                  if (entry.key.name == zoneId) ...entry.value,
              ],
      SuperListViewConfig() => [
        for (final entry in config.template.placements.entries)
          if (entry.key.name == zoneId) ...entry.value,
      ],
      ScaffoldPageConfig() => config.native.placements[zoneId] ?? const [],
      NativeComponentConfig() => config.placements[zoneId] ?? const [],
      SuperTabConfig() => config.placements[zoneId] ?? const [],
      SuperConditionalConfig() => config.placements[zoneId] ?? const [],
      SuperTreeViewConfig() => config.placements[zoneId] ?? const [],
      SuperTableConfig() => config.placements[zoneId] ?? const [],
      _ => const [],
    };
  }

  final ordered = <String>[];
  final seen = <String>{};
  void addAll(Iterable<String> ids) {
    for (final slotId in ids) {
      if (slotId.isNotEmpty && seen.add(slotId)) {
        ordered.add(slotId);
      }
    }
  }

  switch (config) {
    case final SuperLayoutConfig layout:
      addAll(layout.placements.values.expand((ids) => ids));
      if (layout.grid case final grid?) addAll(grid.items.keys);
      addAll(layout.slotTypes.keys);
    case final SuperListViewConfig list:
      if (list.itemId case final itemId?) addAll([itemId]);
      addAll(list.template.placements.values.expand((ids) => ids));
      if (list.template.grid case final grid?) addAll(grid.items.keys);
      addAll(list.template.slotTypes.keys);
    case final ScaffoldPageConfig page:
      addAll(page.native.placements.values.expand((ids) => ids));
      addAll(page.native.slotTypes.keys);
    case final NativeComponentConfig native:
      addAll(native.placements.values.expand((ids) => ids));
      addAll(native.slotTypes.keys);
    case final SuperTabConfig tab:
      addAll(tab.placements.values.expand((ids) => ids));
      addAll(tab.slotTypes.keys);
    case final SuperConditionalConfig cond:
      addAll(cond.placements.values.expand((ids) => ids));
      addAll(cond.slotTypes.keys);
    case final SuperTreeViewConfig tree:
      addAll(tree.placements.values.expand((ids) => ids));
      addAll(tree.slotTypes.keys);
    case final SuperTableConfig table:
      addAll(table.placements.values.expand((ids) => ids));
      addAll(table.slotTypes.keys);
    default:
      addAll(config.childSlots.keys);
  }
  return ordered;
}
