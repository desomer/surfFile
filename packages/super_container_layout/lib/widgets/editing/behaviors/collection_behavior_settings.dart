/// Formulaires de paramétrage visuel pour les actions de tri
/// ([SortCollectionBehaviorSettings]) et de filtrage
/// ([FilterCollectionBehaviorSettings]) des composants `SuperListView` et `SuperTable`.
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/component_behavior.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import 'behavior_validator_editor.dart';

/// Panneau de configuration d'une [SortCollectionAction] dans le wizard de comportements.
class SortCollectionBehaviorSettings extends StatefulWidget {
  /// Crée le panneau de paramétrage du tri de collection.
  const SortCollectionBehaviorSettings({
    required this.isDeclarative,
    required this.mode,
    required this.criteria,
    required this.targetComponentId,
    required this.availableCollections,
    required this.onChanged,
    this.keyPrefix = 'behavior',
    super.key,
  });

  /// `true` lorsque l'événement choisi est [BehaviorEvent.onBinding].
  final bool isDeclarative;

  /// Mode de tri courant (`set`, `add`, `clear`).
  final CollectionSortMode mode;

  /// Liste ordonnée des critères de tri.
  final List<CollectionSortCriterion> criteria;

  /// Identifiant technique de la collection cible (mode impératif uniquement).
  final String? targetComponentId;

  /// Options de `SuperListView` / `SuperTable` disponibles dans l'apparence.
  final List<ValidatorTargetComponentOption> availableCollections;

  /// Callback invoqué à chaque modification.
  final void Function({
    CollectionSortMode? mode,
    List<CollectionSortCriterion>? criteria,
    String? targetComponentId,
    bool clearTargetComponentId,
  })
  onChanged;

  /// Préfixe de clés de test.
  final String keyPrefix;

  @override
  State<SortCollectionBehaviorSettings> createState() =>
      _SortCollectionBehaviorSettingsState();
}

class _SortCollectionBehaviorSettingsState
    extends State<SortCollectionBehaviorSettings> {
  late final TextEditingController _targetController = TextEditingController(
    text: widget.targetComponentId ?? '',
  );
  final List<TextEditingController> _pathControllers = [];

  @override
  void initState() {
    super.initState();
    _syncPathControllers();
  }

  @override
  void didUpdateWidget(covariant SortCollectionBehaviorSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextTarget = widget.targetComponentId ?? '';
    if (nextTarget != _targetController.text) {
      _targetController.text = nextTarget;
    }
    _syncPathControllers();
  }

  void _syncPathControllers() {
    while (_pathControllers.length < widget.criteria.length) {
      final index = _pathControllers.length;
      _pathControllers.add(
        TextEditingController(text: widget.criteria[index].path),
      );
    }
    while (_pathControllers.length > widget.criteria.length) {
      _pathControllers.removeLast().dispose();
    }
    for (var i = 0; i < widget.criteria.length; i++) {
      if (_pathControllers[i].text != widget.criteria[i].path) {
        _pathControllers[i].text = widget.criteria[i].path;
      }
    }
  }

  @override
  void dispose() {
    _targetController.dispose();
    for (final c in _pathControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _updateCriterion(int index, CollectionSortCriterion next) {
    final updated = List<CollectionSortCriterion>.of(widget.criteria);
    updated[index] = next;
    widget.onChanged(criteria: updated, clearTargetComponentId: false);
  }

  void _addCriterion() {
    final updated = [
      ...widget.criteria,
      const CollectionSortCriterion(path: ''),
    ];
    widget.onChanged(criteria: updated, clearTargetComponentId: false);
  }

  void _removeCriterion(int index) {
    if (widget.criteria.length <= 1) return;
    final updated = List<CollectionSortCriterion>.of(widget.criteria)
      ..removeAt(index);
    widget.onChanged(criteria: updated, clearTargetComponentId: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final allowedModes = widget.isDeclarative
        ? const [CollectionSortMode.set, CollectionSortMode.add]
        : CollectionSortMode.values;
    final effectiveMode = allowedModes.contains(widget.mode)
        ? widget.mode
        : CollectionSortMode.set;
    final allowedDirections = widget.isDeclarative
        ? const [CollectionSortDirection.asc, CollectionSortDirection.desc]
        : CollectionSortDirection.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.isDeclarative) ...[
          _CollectionTargetPicker(
            controller: _targetController,
            availableCollections: widget.availableCollections,
            keyPrefix: '${widget.keyPrefix}-sort-target',
            onChanged: (value) {
              final trimmed = value.trim();
              widget.onChanged(
                targetComponentId: trimmed.isEmpty ? null : trimmed,
                clearTargetComponentId: trimmed.isEmpty,
              );
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<CollectionSortMode>(
            segments: [
              for (final mode in allowedModes)
                ButtonSegment(
                  value: mode,
                  label: Text(
                    mode.label,
                    key: ValueKey('${widget.keyPrefix}-sort-mode-${mode.name}'),
                  ),
                ),
            ],
            selected: {effectiveMode},
            onSelectionChanged: (selection) {
              final next = selection.first;
              widget.onChanged(
                mode: next,
                criteria: next == CollectionSortMode.clear
                    ? const []
                    : widget.criteria.isEmpty
                    ? const [CollectionSortCriterion(path: '')]
                    : widget.criteria,
                clearTargetComponentId: false,
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        if (effectiveMode == CollectionSortMode.clear)
          Text(
            'Réinitialise le tri impératif de la collection cible (revient au tri '
            'déclaratif éventuel ou à l’ordre d’origine du repository).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          )
        else ...[
          Text(
            'Critères de tri',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < widget.criteria.length; i++) ...[
            Builder(
              builder: (context) {
                final criterion = widget.criteria[i];
                final effectiveDir =
                    allowedDirections.contains(criterion.direction)
                    ? criterion.direction
                    : CollectionSortDirection.asc;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Critère ${i + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.primary,
                              ),
                            ),
                            const Spacer(),
                            if (widget.criteria.length > 1)
                              IconButton(
                                key: ValueKey(
                                  '${widget.keyPrefix}-sort-remove-$i',
                                ),
                                icon: const Icon(Icons.delete_outline, size: 18),
                                color: colors.error,
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Supprimer ce critère',
                                onPressed: () => _removeCriterion(i),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          key: ValueKey('${widget.keyPrefix}-sort-path-$i'),
                          controller: _pathControllers[i],
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            labelText: 'Champ à trier (path)',
                            hintText: 'Ex. nom, prix, adresse.ville ou .',
                          ),
                          onChanged: (value) => _updateCriterion(
                            i,
                            criterion.copyWith(path: value),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<CollectionSortDirection>(
                          segments: [
                            for (final dir in allowedDirections)
                              ButtonSegment(
                                value: dir,
                                icon: Icon(dir.icon, size: 16),
                                label: Text(
                                  dir.label,
                                  key: ValueKey(
                                    '${widget.keyPrefix}-sort-dir-$i-${dir.name}',
                                  ),
                                ),
                              ),
                          ],
                          selected: {effectiveDir},
                          onSelectionChanged: (selection) => _updateCriterion(
                            i,
                            criterion.copyWith(direction: selection.first),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: CheckboxListTile(
                                key: ValueKey(
                                  '${widget.keyPrefix}-sort-case-$i',
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text('Sensible à la casse'),
                                value: criterion.caseSensitive,
                                onChanged: (value) => _updateCriterion(
                                  i,
                                  criterion.copyWith(
                                    caseSensitive: value ?? false,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: CheckboxListTile(
                                key: ValueKey(
                                  '${widget.keyPrefix}-sort-nulls-$i',
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text('Vides en dernier'),
                                value: criterion.nullsLast,
                                onChanged: (value) => _updateCriterion(
                                  i,
                                  criterion.copyWith(nullsLast: value ?? true),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: ValueKey('${widget.keyPrefix}-sort-add-criterion'),
              onPressed: _addCriterion,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un critère secondaire'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Panneau de configuration d'une [FilterCollectionAction] dans le wizard de comportements.
class FilterCollectionBehaviorSettings extends StatefulWidget {
  /// Crée le panneau de paramétrage du filtrage de collection.
  const FilterCollectionBehaviorSettings({
    required this.isDeclarative,
    required this.mode,
    required this.predicate,
    required this.targetComponentId,
    required this.filterKey,
    required this.availableCollections,
    required this.availableTargets,
    required this.store,
    required this.listScope,
    required this.onChanged,
    this.keyPrefix = 'behavior',
    super.key,
  });

  /// `true` lorsque l'événement choisi est [BehaviorEvent.onBinding].
  final bool isDeclarative;

  /// Mode d'application (`apply`, `toggle`, `clear`, `clearAll`).
  final CollectionFilterMode mode;

  /// Prédicat [BehaviorValidator] évalué pour chaque ligne.
  final BehaviorValidator? predicate;

  /// Identifiant technique de la collection cible (mode impératif uniquement).
  final String? targetComponentId;

  /// Clé logique optionnelle identifiant ce filtre impératif.
  final String? filterKey;

  /// Collections ciblables (`SuperListView` / `SuperTable`).
  final List<ValidatorTargetComponentOption> availableCollections;

  /// Composants disponibles pour les validateurs du prédicat.
  final List<ValidatorTargetComponentOption> availableTargets;

  /// Store de repositories JSON.
  final JsonRepositoryStore? store;

  /// Contexte de liste englobant éventuel.
  final JsonListScope? listScope;

  /// Callback invoqué à chaque modification.
  final void Function({
    CollectionFilterMode? mode,
    BehaviorValidator? predicate,
    bool clearPredicate,
    bool? predicateValid,
    String? targetComponentId,
    bool clearTargetComponentId,
    String? filterKey,
    bool clearFilterKey,
  })
  onChanged;

  /// Préfixe de clés de test.
  final String keyPrefix;

  @override
  State<FilterCollectionBehaviorSettings> createState() =>
      _FilterCollectionBehaviorSettingsState();
}

class _FilterCollectionBehaviorSettingsState
    extends State<FilterCollectionBehaviorSettings> {
  late final TextEditingController _targetController = TextEditingController(
    text: widget.targetComponentId ?? '',
  );
  late final TextEditingController _filterKeyController = TextEditingController(
    text: widget.filterKey ?? '',
  );

  @override
  void didUpdateWidget(covariant FilterCollectionBehaviorSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextTarget = widget.targetComponentId ?? '';
    if (nextTarget != _targetController.text) {
      _targetController.text = nextTarget;
    }
    final nextKey = widget.filterKey ?? '';
    if (nextKey != _filterKeyController.text) {
      _filterKeyController.text = nextKey;
    }
  }

  @override
  void dispose() {
    _targetController.dispose();
    _filterKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveMode = widget.isDeclarative
        ? CollectionFilterMode.apply
        : widget.mode;
    final needsPredicate =
        effectiveMode == CollectionFilterMode.apply ||
        effectiveMode == CollectionFilterMode.toggle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.isDeclarative) ...[
          _CollectionTargetPicker(
            controller: _targetController,
            availableCollections: widget.availableCollections,
            keyPrefix: '${widget.keyPrefix}-filter-target',
            onChanged: (value) {
              final trimmed = value.trim();
              widget.onChanged(
                targetComponentId: trimmed.isEmpty ? null : trimmed,
                clearTargetComponentId: trimmed.isEmpty,
                clearPredicate: false,
                clearFilterKey: false,
              );
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CollectionFilterMode>(
            key: ValueKey('${widget.keyPrefix}-filter-mode'),
            isExpanded: true,
            initialValue: effectiveMode,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Mode du filtre',
            ),
            items: [
              for (final mode in CollectionFilterMode.values)
                DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
            onChanged: (next) {
              if (next == null) return;
              final clearsPredicate =
                  next == CollectionFilterMode.clear ||
                  next == CollectionFilterMode.clearAll;
              widget.onChanged(
                mode: next,
                clearPredicate: clearsPredicate,
                predicateValid: clearsPredicate ? true : null,
                clearTargetComponentId: false,
                clearFilterKey: next == CollectionFilterMode.clearAll,
              );
            },
          ),
          if (effectiveMode != CollectionFilterMode.clearAll) ...[
            const SizedBox(height: 10),
            TextField(
              key: ValueKey('${widget.keyPrefix}-filter-key'),
              controller: _filterKeyController,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Clé du filtre (optionnel)',
                hintText: 'Ex. search, status (permet de cumuler ou retirer)',
              ),
              onChanged: (value) {
                final trimmed = value.trim();
                widget.onChanged(
                  filterKey: trimmed.isEmpty ? null : trimmed,
                  clearFilterKey: trimmed.isEmpty,
                  clearPredicate: false,
                  clearTargetComponentId: false,
                );
              },
            ),
          ],
          const SizedBox(height: 12),
        ],
        if (!needsPredicate)
          Text(
            effectiveMode == CollectionFilterMode.clearAll
                ? 'Efface tous les filtres impératifs actifs sur la collection cible.'
                : 'Retire uniquement le filtre identifié par cette clé.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          )
        else
          BehaviorValidatorEditor(
            validator: widget.predicate,
            availableTargets: widget.availableTargets,
            store: widget.store,
            listScope: widget.listScope,
            keyPrefix: '${widget.keyPrefix}-filter-predicate',
            infoBanner: widget.isDeclarative
                ? 'Prédicat évalué pour chaque ligne (ex. liaison « statut » égal à « actif »). '
                      'Optionnel ici : si vous laissez « Aucune », le validateur de l’étape suivante '
                      'sera directement évalué par ligne. Si les deux sont renseignés, l’étape suivante '
                      'sert de condition d’activation globale (ex. champ de recherche rempli).'
                : 'Prédicat évalué pour chaque ligne de la collection cible.',
            onChanged: (predicate, isValid) => widget.onChanged(
              predicate: predicate,
              clearPredicate: predicate == null,
              predicateValid: isValid,
              clearTargetComponentId: false,
              clearFilterKey: false,
            ),
          ),
      ],
    );
  }
}

class _CollectionTargetPicker extends StatelessWidget {
  const _CollectionTargetPicker({
    required this.controller,
    required this.availableCollections,
    required this.keyPrefix,
    required this.onChanged,
  });

  final TextEditingController controller;
  final List<ValidatorTargetComponentOption> availableCollections;
  final String keyPrefix;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: ValueKey(keyPrefix),
          controller: controller,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            labelText: 'Liste ou tableau cible (ID)',
            hintText: 'Ex. clients-table (vide = ce composant)',
            prefixIcon: Icon(Icons.table_chart_outlined, size: 18),
          ),
          onChanged: onChanged,
        ),
        if (availableCollections.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in availableCollections)
                ChoiceChip(
                  key: ValueKey('$keyPrefix-option-${option.id}'),
                  avatar: Icon(option.icon, size: 15),
                  label: Text(
                    option.displayLabel,
                    style: theme.textTheme.labelSmall,
                  ),
                  selected: controller.text.trim() == option.id,
                  onSelected: (_) {
                    controller.text = option.id;
                    onChanged(option.id);
                  },
                ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            'Saisissez l’ID du SuperListView ou SuperTable à piloter.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
