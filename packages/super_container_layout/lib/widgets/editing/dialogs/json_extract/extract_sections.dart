/// Sections de réglages et de configuration des groupes récurrents du dialogue.
library;

import 'package:material_ui/material_ui.dart';

import '../../history/editor_history.dart';
import 'extract_contracts.dart';

/// Contrôles de détection et d'organisation du JSON récurrent.
class ExtractRecurrenceSettingsPanel extends StatelessWidget {
  /// Crée les réglages associés à [options].
  const ExtractRecurrenceSettingsPanel({
    required this.options,
    required this.busy,
    required this.onOptionsChanged,
    super.key,
  });

  /// Options de détection actuellement sélectionnées.
  final JsonExtractRecurrenceOptions options;

  /// Désactive les contrôles pendant une sauvegarde.
  final bool busy;

  /// Transmet les nouvelles options au dialogue propriétaire.
  final ValueChanged<JsonExtractRecurrenceOptions> onOptionsChanged;

  @override
  Widget build(BuildContext context) {
    final opts = options;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('super-value-extract-recurrence-panel'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tolérance de similarité & Arborescence JSON',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  'Min. ${opts.minOccurrences} blocs',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SegmentedButton<RecurrenceSimilarityMode>(
              key: const ValueKey('super-value-extract-similarity-mode'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                for (final mode in RecurrenceSimilarityMode.values)
                  ButtonSegment(
                    value: mode,
                    tooltip: mode.description,
                    label: Text(
                      mode.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
              selected: {opts.similarityMode},
              onSelectionChanged: busy
                  ? null
                  : (selected) => onOptionsChanged(
                      opts.copyWith(similarityMode: selected.single),
                    ),
            ),
            if (opts.similarityMode == RecurrenceSimilarityMode.flexible) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'Seuil de similarité : ${(opts.similarityThreshold * 100).round()}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Expanded(
                    child: EditorHistorySlider(
                      sliderKey: const ValueKey(
                        'super-value-extract-similarity-threshold',
                      ),
                      valueScale: 100,
                      integer: true,
                      unit: '%',
                      min: 0.50,
                      max: 1.0,
                      divisions: 50,
                      value: opts.similarityThreshold.clamp(0.50, 1.0),
                      onChanged: busy
                          ? null
                          : (val) => onOptionsChanged(
                              opts.copyWith(similarityThreshold: val),
                            ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<JsonExtractHierarchyMode>(
                    key: const ValueKey('super-value-extract-hierarchy-mode'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: [
                      for (final mode in JsonExtractHierarchyMode.values)
                        ButtonSegment(
                          value: mode,
                          tooltip: mode.description,
                          label: Text(
                            mode.label,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                    selected: {opts.hierarchyMode},
                    onSelectionChanged: busy
                        ? null
                        : (selected) => onOptionsChanged(
                            opts.copyWith(hierarchyMode: selected.single),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<int>(
                  key: const ValueKey('super-value-extract-min-occurrences'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: 2,
                      tooltip: 'Au moins 2 blocs similaires',
                      label: Text('≥2', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 3,
                      tooltip: 'Au moins 3 blocs similaires',
                      label: Text('≥3', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 4,
                      tooltip: 'Au moins 4 blocs similaires',
                      label: Text('≥4', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {opts.minOccurrences.clamp(2, 4)},
                  onSelectionChanged: busy
                      ? null
                      : (selected) => onOptionsChanged(
                          opts.copyWith(minOccurrences: selected.single),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                FilterChip(
                  key: const ValueKey('super-value-extract-opt-contiguous'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: opts.contiguousOnly,
                  label: const Text('Blocs contigus uniquement'),
                  onSelected: busy
                      ? null
                      : (v) =>
                            onOptionsChanged(opts.copyWith(contiguousOnly: v)),
                ),
                FilterChip(
                  key: const ValueKey('super-value-extract-opt-leaf-slots'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: opts.includeSingleLeafSlots,
                  label: const Text('Inclure composants simples'),
                  onSelected: busy
                      ? null
                      : (v) => onOptionsChanged(
                          opts.copyWith(includeSingleLeafSlots: v),
                        ),
                ),
                FilterChip(
                  key: const ValueKey(
                    'super-value-extract-opt-ignore-container',
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: opts.ignoreContainerType,
                  label: const Text('Ignorer type de conteneur'),
                  onSelected: busy
                      ? null
                      : (v) => onOptionsChanged(
                          opts.copyWith(ignoreContainerType: v),
                        ),
                ),
                FilterChip(
                  key: const ValueKey('super-value-extract-opt-same-zones'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: opts.requireSameZoneStructure,
                  label: const Text('Mêmes zones internes'),
                  onSelected: busy
                      ? null
                      : (v) => onOptionsChanged(
                          opts.copyWith(requireSameZoneStructure: v),
                        ),
                ),
                FilterChip(
                  key: const ValueKey(
                    'super-value-extract-opt-divergent-props',
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: opts.autoSelectDivergentProperties,
                  label: const Text('Auto-sélectionner propriétés variables'),
                  onSelected: busy
                      ? null
                      : (v) => onOptionsChanged(
                          opts.copyWith(autoSelectDivergentProperties: v),
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

/// Carte de réglage d'un groupe de blocs récurrents détecté.
class RecurringBlockGroupCard extends StatelessWidget {
  /// Crée une carte à partir de [group] et de sa configuration courante.
  const RecurringBlockGroupCard({
    required this.group,
    required this.config,
    required this.arrayKeyController,
    required this.selectedFieldProps,
    required this.busy,
    required this.onConfigChanged,
    required this.onToggleGroupFieldProperty,
    super.key,
  });

  /// Groupe détecté représenté par la carte.
  final DetectedRecurringBlockGroup group;

  /// Configuration éditable du groupe.
  final RecurringGroupUserConfig config;

  /// Contrôleur du champ contenant la clé du tableau.
  final TextEditingController arrayKeyController;

  /// Propriétés cochées, indexées par clé de champ.
  final Map<String, Set<String>> selectedFieldProps;

  /// Désactive les contrôles pendant une sauvegarde.
  final bool busy;

  /// Transmet une configuration de groupe mise à jour.
  final void Function(String groupId, RecurringGroupUserConfig config)
  onConfigChanged;

  /// Transmet la modification d'une propriété de champ récurrent.
  final void Function(
    DetectedRecurringBlockGroup group,
    AlignedRecurringField field,
    String propertyId,
    bool selected,
  )
  onToggleGroupFieldProperty;

  @override
  Widget build(BuildContext context) {
    final cfg = config;
    final keyController = arrayKeyController;
    final scheme = Theme.of(context).colorScheme;
    final simPercent = (group.similarityScore * 100).round();

    return Padding(
      key: ValueKey('super-value-extract-group-${group.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cfg.enabled
              ? scheme.primaryContainer.withValues(alpha: 0.22)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: cfg.enabled
                ? scheme.primary.withValues(alpha: 0.65)
                : scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.repeat,
                    size: 16,
                    color: cfg.enabled
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Bloc récurrent : ${group.occurrences.length} × ${group.blockDisplayName}',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Similarité $simPercent%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Switch(
                    key: ValueKey(
                      'super-value-extract-group-enable-${group.id}',
                    ),
                    value: cfg.enabled,
                    onChanged: busy
                        ? null
                        : (v) => onConfigChanged(
                            group.id,
                            cfg.copyWith(enabled: v),
                          ),
                  ),
                ],
              ),
              if (cfg.enabled) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        key: ValueKey(
                          'super-value-extract-group-key-${group.id}',
                        ),
                        controller: keyController,
                        enabled: !busy,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Clé du tableau JSON',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => onConfigChanged(
                          group.id,
                          cfg.copyWith(arrayKey: val),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      key: ValueKey(
                        'super-value-extract-group-listview-${group.id}',
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: const Icon(Icons.view_list, size: 15),
                      selected: cfg.convertToListView,
                      label: const Text('Remplacer par ListView'),
                      onSelected: busy
                          ? null
                          : (v) => onConfigChanged(
                              group.id,
                              cfg.copyWith(convertToListView: v),
                            ),
                    ),
                  ],
                ),
                if (cfg.convertToListView) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        key: ValueKey(
                          'super-value-extract-group-axis-${group.id}',
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(
                          cfg.wrap
                              ? Icons.wrap_text
                              : cfg.axis == Axis.vertical
                              ? Icons.swap_vert
                              : Icons.swap_horiz,
                          size: 14,
                        ),
                        label: Text(
                          cfg.wrap
                              ? 'Disposition : Wrap'
                              : cfg.axis == Axis.vertical
                              ? 'Disposition : Verticale'
                              : 'Disposition : Horizontale',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: busy
                            ? null
                            : () {
                                if (!cfg.wrap && cfg.axis == Axis.vertical) {
                                  onConfigChanged(
                                    group.id,
                                    cfg.copyWith(
                                      axis: Axis.horizontal,
                                      wrap: false,
                                    ),
                                  );
                                } else if (!cfg.wrap &&
                                    cfg.axis == Axis.horizontal) {
                                  onConfigChanged(
                                    group.id,
                                    cfg.copyWith(
                                      axis: Axis.vertical,
                                      wrap: true,
                                    ),
                                  );
                                } else {
                                  onConfigChanged(
                                    group.id,
                                    cfg.copyWith(
                                      axis: Axis.vertical,
                                      wrap: false,
                                    ),
                                  );
                                }
                              },
                      ),
                      if (group.canUnwrapContainer)
                        ActionChip(
                          key: ValueKey(
                            'super-value-extract-group-template-mode-${group.id}',
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          avatar: const Icon(Icons.layers_outlined, size: 14),
                          tooltip: cfg.templateMode.description,
                          label: Text(
                            cfg.templateMode.label,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: busy
                              ? null
                              : () => onConfigChanged(
                                  group.id,
                                  cfg.copyWith(
                                    templateMode:
                                        cfg.templateMode ==
                                            ListViewTemplateMode.preserveBlock
                                        ? ListViewTemplateMode.unwrapContainer
                                        : ListViewTemplateMode.preserveBlock,
                                  ),
                                ),
                        ),
                      FilterChip(
                        key: ValueKey(
                          'super-value-extract-group-allow-add-${group.id}',
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected: cfg.allowAdd,
                        label: const Text(
                          'Bouton Ajouter',
                          style: TextStyle(fontSize: 11),
                        ),
                        onSelected: busy
                            ? null
                            : (v) => onConfigChanged(
                                group.id,
                                cfg.copyWith(allowAdd: v),
                              ),
                      ),
                      FilterChip(
                        key: ValueKey(
                          'super-value-extract-group-allow-remove-${group.id}',
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected: cfg.allowRemove,
                        label: const Text(
                          'Bouton Supprimer',
                          style: TextStyle(fontSize: 11),
                        ),
                        onSelected: busy
                            ? null
                            : (v) => onConfigChanged(
                                group.id,
                                cfg.copyWith(allowRemove: v),
                              ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                for (final field in group.fields)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${field.displayName} (${field.kind.label})',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              '${cfg.arrayKey}[?].${field.fieldKey}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final prop in field.properties)
                              () {
                                final firstVal =
                                    field.occurrenceValues.first[prop.id];
                                final lastVal =
                                    field.occurrenceValues.last[prop.id];
                                final varies = field.divergentPropertyIds
                                    .contains(prop.id);
                                final previewText = varies
                                    ? '${prop.label} : $firstVal … $lastVal'
                                    : '${prop.label} : $firstVal';
                                final isSelected =
                                    (selectedFieldProps[field.fieldKey] ??
                                            const {})
                                        .contains(prop.id);
                                return FilterChip(
                                  key: ValueKey(
                                    'super-value-extract-group-prop-${group.id}-${field.fieldKey}-${prop.id}',
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  selected: isSelected,
                                  label: Text(previewText),
                                  onSelected: busy
                                      ? null
                                      : (sel) => onToggleGroupFieldProperty(
                                          group,
                                          field,
                                          prop.id,
                                          sel,
                                        ),
                                );
                              }(),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
