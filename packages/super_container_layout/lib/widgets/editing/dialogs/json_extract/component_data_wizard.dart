/// Sélecteur de cible et commandes pour l'extraction ou l'ouverture des repositories.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../../models/json_text_binding.dart';
import '../../../../models/super_action_config.dart';
import '../../../../models/super_list_view_config.dart';
import '../../../../models/super_tab_config.dart';
import '../../../../models/super_table_config.dart';
import '../../../../models/super_tree_view_config.dart';
import '../../../../models/super_value_config.dart';
import '../../../../services/repositories/json_list_scope.dart';
import '../../../../services/repositories/json_repository_scope.dart';
import '../../../../services/repositories/json_repository_store.dart';
import '../../../../theme/appearance.dart';
import '../../repositories/floating_repository_editor.dart';
import '../../repositories/json_repository_manager.dart';
import '../editor_dialog.dart';
import '../editor_dialog_header.dart';
import '../editor_target_selector.dart';
import '../../slots/editor_slot.dart';
import 'extract_contracts.dart';
import 'extract_detection.dart';

/// Élément cible affiché dans le sélecteur « Donnée… » de la barre du menu contextuel.
@immutable
class DataTargetElement implements EditorTargetItem {
  const DataTargetElement({
    required this.id,
    required this.label,
    required this.slot,
    this.icon,
    this.depth = 0,
    this.extractableTargets = const [],
    this.recurringGroups = const [],
    this.existingBindings = const [],
  });

  @override
  final String id;
  @override
  final String label;
  @override
  final EditorSlotState slot;
  @override
  final IconData? icon;
  @override
  final int depth;
  final List<ExtractableComponentTarget> extractableTargets;
  final List<DetectedRecurringBlockGroup> recurringGroups;
  final List<JsonTextBinding> existingBindings;

  bool get hasExtractable =>
      extractableTargets.isNotEmpty || recurringGroups.isNotEmpty;

  bool get hasExistingBindings => existingBindings.isNotEmpty;

  String? get firstBoundRepositoryId {
    for (final b in existingBindings) {
      if (b.repositoryId != null && b.repositoryId!.isNotEmpty) {
        return b.repositoryId;
      }
    }
    return null;
  }
}

/// Collecte toutes les liaisons [JsonTextBinding] déjà configurées sur [slot]
/// ou dans le sous-arbre de [slot].
List<JsonTextBinding> collectExistingBindingsFromSlot(EditorSlotState slot) {
  if (!slot.mounted) return const [];
  final appearance =
      AppearanceScope.controllerOf(slot.context)?.value ??
      AppearanceScope.of(slot.context);
  final bindings = <JsonTextBinding>[];
  final seen = <JsonTextBinding>{};

  void addBinding(JsonTextBinding? b) {
    if (b != null && b.path.trim().isNotEmpty && seen.add(b)) {
      bindings.add(b);
    }
  }

  // Enclosing list/tree scope repository if inherited
  final enclosingScope = JsonListScope.maybeOf(slot.context);

  void inspectId(String id) {
    if (id.isEmpty) return;
    final comp = appearance.components[id];
    switch (comp) {
      case final SuperValueConfig v:
        addBinding(v.binding);
        v.propertyBindings.values.forEach(addBinding);
        addBinding(v.states?.binding);
      case final SuperActionConfig a:
        a.propertyBindings.values.forEach(addBinding);
        addBinding(a.states?.binding);
      case final SuperListViewConfig l:
        addBinding(l.binding);
      case final SuperTableConfig t:
        addBinding(t.binding);
      case final SuperTreeViewConfig tr:
        addBinding(tr.binding);
      case final SuperTabConfig tb:
        addBinding(tb.binding);
      default:
        comp?.referencedBindings.forEach(addBinding);
    }
    final st = appearance.styles[id];
    if (st != null) {
      addBinding(st.imageBinding);
      st.propertyBindings.values.forEach(addBinding);
      addBinding(st.states?.binding);
    }
  }

  inspectId(slot.effectiveComponentId);
  void visit(Element el) {
    if (el is StatefulElement) {
      final st = el.state;
      if (st is EditorSlotState && st.mounted) {
        inspectId(st.effectiveComponentId);
      } else if (st case final JsonExtractableState extractable
          when extractable.isExtractableMounted) {
        inspectId(extractable.extractableId);
      }
    }
    el.visitChildren(visit);
  }

  slot.context.visitChildElements(visit);

  // Resolve inherited repository IDs from enclosing JsonListScope when possible
  if (enclosingScope?.repositoryId != null) {
    return [
      for (final b in bindings)
        b.repositoryId == null
            ? JsonTextBinding(
                repositoryId: enclosingScope!.repositoryId,
                path: b.path,
              )
            : b,
    ];
  }
  return bindings;
}

enum _DataWizardAction {
  extractAndBind,
  openRepositoryManager,
  openFloatingRepository,
}

final _defaultFloatingStores = Expando<_DefaultFloatingStore>();

class _DefaultFloatingStore {
  _DefaultFloatingStore(this.overlay);

  final OverlayState overlay;
  final JsonRepositoryStore store = JsonRepositoryStore.defaultStore();
  int references = 0;

  void release() {
    if (--references != 0) return;
    _defaultFloatingStores[overlay] = null;
    store.dispose();
  }
}

Future<void> _openBoundRepository(
  BuildContext context,
  DataTargetElement target,
) async {
  final id = target.firstBoundRepositoryId;
  if (id == null) {
    await JsonRepositoryManager.show(context);
    return;
  }
  if (!target.slot.mounted) return;
  var store =
      JsonRepositoryScope.maybeOf(target.slot.context) ??
      JsonRepositoryScope.maybeOf(context);
  _DefaultFloatingStore? owned;
  if (store == null) {
    final overlay = Overlay.of(context, rootOverlay: true);
    owned = _defaultFloatingStores[overlay] ??= _DefaultFloatingStore(overlay);
    owned.references++;
    store = owned.store;
  }
  var opened = false;
  try {
    final catalog = await store.catalog();
    final entry = catalog.where((entry) => entry.id == id).firstOrNull;
    if (entry == null) {
      throw const FormatException('Repository lié introuvable.');
    }
    final text = await store.read(entry.name);
    if (!context.mounted || !target.slot.mounted) return;
    opened = openFloatingRepositoryEditor(
      context,
      store: store,
      repositoryId: id,
      name: entry.name,
      text: text,
      onClosed: owned?.release,
    );
  } on FormatException catch (error) {
    if (context.mounted) await _showRepositoryOpenError(context, error.message);
  } on FileSystemException catch (error) {
    if (context.mounted) {
      await _showRepositoryOpenError(
        context,
        'Erreur de fichier : ${error.message}',
      );
    }
  } finally {
    if (!opened) owned?.release();
  }
}

Future<void> _showRepositoryOpenError(BuildContext context, String message) =>
    showEditorDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Impossible d’ouvrir le repository'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );

/// Orchestre le sélecteur de données et délègue l'extraction au dialogue appelant.
Future<void> showComponentDataWizardInternal({
  required BuildContext context,
  required List<DataTargetElement> targets,
  required Future<void> Function(
    DataTargetElement target,
    List<ExtractableComponentTarget> extractableTargets,
  )
  onExtract,
  BuildContext? target,
}) async {
  if (targets.isEmpty) {
    await JsonRepositoryManager.show(context);
    return;
  }

  final chosen = await showEditorDialog<(DataTargetElement, _DataWizardAction)>(
    context: context,
    target: target,
    builder: (_) =>
        _ComponentDataWizardDialog(ownerContext: context, targets: targets),
  );

  if (chosen == null || !context.mounted) return;
  final (selectedTarget, action) = chosen;
  if (action == _DataWizardAction.openRepositoryManager) {
    await JsonRepositoryManager.show(
      context,
      initialRepositoryId: selectedTarget.firstBoundRepositoryId,
    );
    return;
  }
  if (action == _DataWizardAction.openFloatingRepository) {
    await _openBoundRepository(context, selectedTarget);
    return;
  }

  if (!selectedTarget.slot.mounted) return;
  final latestTargets = collectExtractableTargetsFromSlot(selectedTarget.slot);
  await onExtract(selectedTarget, latestTargets);
}

class _ComponentDataWizardDialog extends StatefulWidget {
  const _ComponentDataWizardDialog({
    required this.ownerContext,
    required this.targets,
  });

  final BuildContext ownerContext;
  final List<DataTargetElement> targets;

  @override
  State<_ComponentDataWizardDialog> createState() =>
      _ComponentDataWizardDialogState();
}

class _ComponentDataWizardDialogState
    extends State<_ComponentDataWizardDialog> {
  late DataTargetElement _selectedTarget;
  late _DataWizardAction _selectedAction;

  @override
  void initState() {
    super.initState();
    // Default to the first target that has extractable data or existing bindings,
    // or fallback to targets.first.
    _selectedTarget =
        widget.targets
            .where((t) => t.hasExtractable || t.hasExistingBindings)
            .firstOrNull ??
        widget.targets.first;
    _selectedAction = _defaultActionFor(_selectedTarget);
  }

  _DataWizardAction _defaultActionFor(DataTargetElement target) {
    if (target.hasExtractable) return _DataWizardAction.extractAndBind;
    return _DataWizardAction.openRepositoryManager;
  }

  void _selectTarget(DataTargetElement target) {
    setState(() {
      _selectedTarget = target;
      if (!_selectedTarget.hasExtractable &&
          _selectedAction == _DataWizardAction.extractAndBind) {
        _selectedAction = _DataWizardAction.openRepositoryManager;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AlertDialog(
      key: const ValueKey('data-wizard-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      title: const EditorDialogHeader(label: 'Données & Liaisons JSON'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: EditorTargetSelector<DataTargetElement>(
                    targets: widget.targets,
                    selected: _selectedTarget,
                    onSelected: _selectTarget,
                    subtitle:
                        'Sélectionnez le composant ou le conteneur parent sur lequel '
                        'extraire des données ou gérer les liaisons existantes :',
                    itemKeyBuilder: (target) =>
                        ValueKey('data-target-${target.label}'),
                    subtitleBuilder: (context, target) {
                      final extractCount = target.extractableTargets.length;
                      final recurringCount = target.recurringGroups.length;
                      final bindingCount = target.existingBindings.length;
                      return Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (extractCount > 0)
                            _DataBadge(
                              icon: Icons.data_object,
                              label:
                                  '$extractCount propriété${extractCount > 1 ? 's' : ''} extractible${extractCount > 1 ? 's' : ''}',
                              background: colors.primaryContainer,
                              foreground: colors.onPrimaryContainer,
                            ),
                          if (recurringCount > 0)
                            _DataBadge(
                              icon: Icons.repeat,
                              label:
                                  '$recurringCount bloc${recurringCount > 1 ? 's' : ''} récurrent${recurringCount > 1 ? 's' : ''}',
                              background: colors.tertiaryContainer,
                              foreground: colors.onTertiaryContainer,
                            ),
                          if (bindingCount > 0)
                            _DataBadge(
                              icon: Icons.link,
                              label:
                                  '$bindingCount liaison${bindingCount > 1 ? 's' : ''} active${bindingCount > 1 ? 's' : ''} (${target.existingBindings.first.path})',
                              background: colors.secondaryContainer,
                              foreground: colors.onSecondaryContainer,
                              onTap: () => Navigator.of(context).pop((
                                target,
                                _DataWizardAction.openFloatingRepository,
                              )),
                            ),
                          if (extractCount == 0 &&
                              recurringCount == 0 &&
                              bindingCount == 0)
                            Text(
                              'Aucune propriété extractible directe',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Action à effectuer',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ActionOptionCard(
                      cardKey: const ValueKey('data-wizard-action-extract'),
                      icon: Icons.data_object,
                      title: 'Extraire & lier en JSON…',
                      subtitle: _selectedTarget.hasExtractable
                          ? 'Extrait les valeurs, détecte les répétitions et crée une ListView'
                          : 'Aucune propriété extractible sur cet élément',
                      selected:
                          _selectedAction == _DataWizardAction.extractAndBind,
                      enabled: _selectedTarget.hasExtractable,
                      onTap: () => setState(
                        () =>
                            _selectedAction = _DataWizardAction.extractAndBind,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionOptionCard(
                      cardKey: const ValueKey(
                        'data-wizard-action-repo-manager',
                      ),
                      icon: Icons.storage_outlined,
                      title: 'Gestionnaire de repositories…',
                      subtitle: _selectedTarget.hasExistingBindings
                          ? 'Modifier le repository lié (${_selectedTarget.existingBindings.first.path})'
                          : 'Parcourir, créer ou éditer les fichiers JSON',
                      selected:
                          _selectedAction ==
                          _DataWizardAction.openRepositoryManager,
                      enabled: true,
                      highlighted: _selectedTarget.hasExistingBindings,
                      onTap: () => setState(
                        () => _selectedAction =
                            _DataWizardAction.openRepositoryManager,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('data-wizard-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          key: const ValueKey('data-wizard-continue'),
          onPressed: () =>
              Navigator.of(context).pop((_selectedTarget, _selectedAction)),
          icon: Icon(
            _selectedAction == _DataWizardAction.extractAndBind
                ? Icons.data_object
                : Icons.storage_outlined,
            size: 18,
          ),
          label: Text(
            _selectedAction == _DataWizardAction.extractAndBind
                ? 'Extraire & lier…'
                : 'Ouvrir le gestionnaire…',
          ),
        ),
      ],
    );
  }
}

class _DataBadge extends StatelessWidget {
  const _DataBadge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return badge;
    return Tooltip(
      message: 'Ouvrir le gestionnaire de repositories',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: badge,
        ),
      ),
    );
  }
}

class _ActionOptionCard extends StatelessWidget {
  const _ActionOptionCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.highlighted = false,
  });

  final Key cardKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? colors.primaryContainer.withValues(alpha: 0.45)
              : highlighted
              ? colors.tertiaryContainer.withValues(alpha: 0.25)
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? colors.primary
                : highlighted
                ? colors.tertiary
                : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: cardKey,
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: selected
                          ? colors.primary
                          : highlighted
                          ? colors.tertiary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
