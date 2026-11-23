/// Boîte de dialogue de choix et de comparaison avant injection des exemples
/// des cartes vertes d'Example Mapping dans le JSON Schema d'un objet métier
/// ([ExampleInjectionDialog]).
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../services/example_mapping_operations.dart';

/// Résultat validé par l'utilisateur dans [ExampleInjectionDialog].
typedef ExampleInjectionSelection = ({
  Map<String, List<Object?>> selectedByAttributePath,
  ExampleInjectionMode mode,
});

/// Modale affichant côte à côte les exemples actuels d'un objet métier et les
/// valeurs candidates issues des cartes vertes, avec choix de sélection et de mode.
class ExampleInjectionDialog extends StatefulWidget {
  /// Crée la modale à partir d'un aperçu [preview].
  const ExampleInjectionDialog({required this.preview, super.key});

  /// Aperçu précalculé entre l'objet cible et la story.
  final ExampleInjectionPreview preview;

  /// Ouvre la modale et retourne la sélection confirmée ou `null` si annulée.
  static Future<ExampleInjectionSelection?> show(
    BuildContext context, {
    required ExampleInjectionPreview preview,
  }) => showDialog<ExampleInjectionSelection>(
    context: context,
    builder: (_) => ExampleInjectionDialog(preview: preview),
  );

  @override
  State<ExampleInjectionDialog> createState() => _ExampleInjectionDialogState();
}

class _ExampleInjectionDialogState extends State<ExampleInjectionDialog> {
  ExampleInjectionMode _mode = ExampleInjectionMode.append;
  late final Map<String, Set<int>> _selectedIndicesByPath;

  @override
  void initState() {
    super.initState();
    _selectedIndicesByPath = <String, Set<int>>{
      for (final comp in widget.preview.attributeComparisons)
        comp.attributePath: <int>{
          for (var i = 0; i < comp.candidates.length; i++)
            if (!comp.candidates[i].alreadyPresent) i,
        },
    };
  }

  bool get _hasAnyCandidates =>
      widget.preview.attributeComparisons.any((c) => c.hasCandidates);

  void _selectNewOnly() {
    setState(() {
      for (final comp in widget.preview.attributeComparisons) {
        _selectedIndicesByPath[comp.attributePath] = <int>{
          for (var i = 0; i < comp.candidates.length; i++)
            if (!comp.candidates[i].alreadyPresent) i,
        };
      }
    });
  }

  void _selectAllCandidates() {
    setState(() {
      for (final comp in widget.preview.attributeComparisons) {
        _selectedIndicesByPath[comp.attributePath] = <int>{
          for (var i = 0; i < comp.candidates.length; i++) i,
        };
      }
    });
  }

  void _clearSelection() {
    setState(() {
      for (final comp in widget.preview.attributeComparisons) {
        _selectedIndicesByPath[comp.attributePath] = <int>{};
      }
    });
  }

  List<Object?> _selectedValuesFor(AttributeExampleComparison comp) {
    final indices = _selectedIndicesByPath[comp.attributePath] ?? const <int>{};
    return [
      for (var i = 0; i < comp.candidates.length; i++)
        if (indices.contains(i)) comp.candidates[i].value,
    ];
  }

  ({List<Object?> nextExamples, int deltaCount}) _computeOutcome(
    AttributeExampleComparison comp,
  ) {
    final selected = _selectedValuesFor(comp);
    if (selected.isEmpty) {
      return (nextExamples: comp.existingExamples, deltaCount: 0);
    }
    if (_mode == ExampleInjectionMode.append) {
      final merged = List<Object?>.of(comp.existingExamples);
      var added = 0;
      for (final val in selected) {
        if (!merged.any((e) => _valuesEqual(e, val))) {
          merged.add(val);
          added++;
        }
      }
      return (nextExamples: merged, deltaCount: added);
    }
    final replaced = <Object?>[];
    for (final val in selected) {
      if (!replaced.any((e) => _valuesEqual(e, val))) {
        replaced.add(val);
      }
    }
    final changed = !_listsEqual(comp.existingExamples, replaced);
    return (nextExamples: replaced, deltaCount: changed ? replaced.length : 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final targetObj = widget.preview.targetObject;
    final story = widget.preview.story;

    var totalChangedValues = 0;
    var totalChangedAttrs = 0;
    for (final comp in widget.preview.attributeComparisons) {
      final outcome = _computeOutcome(comp);
      if (outcome.deltaCount > 0) {
        totalChangedValues += outcome.deltaCount;
        totalChangedAttrs++;
      }
    }

    return Dialog(
      key: const ValueKey('spec-em-inject-dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.compare_arrows_rounded,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Comparer et injecter les exemples → ${targetObj?.technicalName ?? 'Objet cible'}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${story.code} · ${story.title}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Barre de choix du mode et actions rapides
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedButton<ExampleInjectionMode>(
                        key: const ValueKey('spec-em-inject-mode-segment'),
                        segments: [
                          for (final mode in ExampleInjectionMode.values)
                            ButtonSegment<ExampleInjectionMode>(
                              value: mode,
                              icon: Icon(
                                mode == ExampleInjectionMode.append
                                    ? Icons.add_circle_outline
                                    : Icons.find_replace_rounded,
                                size: 16,
                              ),
                              label: Text(mode.label),
                            ),
                        ],
                        selected: <ExampleInjectionMode>{_mode},
                        onSelectionChanged: (sel) {
                          if (sel.isEmpty) return;
                          setState(() => _mode = sel.first);
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _mode.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (_hasAnyCandidates)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          key: const ValueKey('spec-em-inject-select-new-btn'),
                          onPressed: _selectNewOnly,
                          child: const Text('Nouveaux uniquement'),
                        ),
                        TextButton(
                          key: const ValueKey('spec-em-inject-select-all-btn'),
                          onPressed: _selectAllCandidates,
                          child: const Text('Tout cocher'),
                        ),
                        TextButton(
                          key: const ValueKey('spec-em-inject-clear-btn'),
                          onPressed: _clearSelection,
                          child: const Text('Tout décocher'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Corps : comparaison par attribut
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.preview.attributeComparisons.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 32,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Aucune valeur d’attribut à comparer pour ${targetObj?.technicalName ?? 'cet objet'}.\n'
                            'Renseignez des « Valeurs d’entrée JSON » ou « Sorties attendues JSON » dans les cartes vertes.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final comp in widget.preview.attributeComparisons) ...[
                      _buildAttributeComparisonCard(
                        context,
                        comp,
                        theme,
                        colors,
                      ),
                      const SizedBox(height: 10),
                    ],
                  if (widget.preview.unmatchedCandidates.isNotEmpty)
                    _buildUnmatchedBanner(
                      context,
                      targetObj?.technicalName ?? 'l’objet',
                      theme,
                      colors,
                    ),
                ],
              ),
            ),

            const Divider(height: 1),
            // Pied de modale
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      totalChangedAttrs > 0
                          ? '$totalChangedValues valeur${totalChangedValues > 1 ? 's' : ''} sur $totalChangedAttrs attribut${totalChangedAttrs > 1 ? 's' : ''} prête${totalChangedAttrs > 1 ? 's' : ''} à être appliquée${totalChangedAttrs > 1 ? 's' : ''}.'
                          : 'Aucune modification sélectionnée.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: totalChangedAttrs > 0
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        fontWeight: totalChangedAttrs > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('spec-em-inject-cancel-btn'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('spec-em-inject-confirm-btn'),
                    onPressed: totalChangedAttrs == 0
                        ? null
                        : () {
                            final selectedMap = <String, List<Object?>>{
                              for (final comp
                                  in widget.preview.attributeComparisons)
                                if (_computeOutcome(comp).deltaCount > 0)
                                  comp.attributePath: _selectedValuesFor(comp),
                            };
                            Navigator.of(context).pop((
                              selectedByAttributePath: selectedMap,
                              mode: _mode,
                            ));
                          },
                    icon: const Icon(
                      Icons.playlist_add_check_rounded,
                      size: 18,
                    ),
                    label: Text(
                      totalChangedValues > 0
                          ? 'Injecter ($totalChangedValues)'
                          : 'Injecter',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttributeComparisonCard(
    BuildContext context,
    AttributeExampleComparison comp,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final outcome = _computeOutcome(comp);
    final hasChange = outcome.deltaCount > 0;
    final selectedIndices =
        _selectedIndicesByPath[comp.attributePath] ?? const <int>{};
    final selectedValues = _selectedValuesFor(comp);

    final statusLabel = hasChange
        ? (_mode == ExampleInjectionMode.append
              ? '+${outcome.deltaCount} à ajouter'
              : 'Remplacement (${outcome.nextExamples.length})')
        : (comp.hasCandidates ? 'Inchangé' : 'Aucune valeur verte');

    return Container(
      key: ValueKey('spec-em-inject-attr-${comp.attributePath}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasChange
            ? colors.primaryContainer.withValues(alpha: 0.16)
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasChange ? colors.primary : colors.outlineVariant,
          width: hasChange ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                comp.attributePath,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  comp.typeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasChange
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: hasChange
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final existingPane = _buildColumnBox(
                title: 'Actuels dans l’objet (${comp.existingExamples.length})',
                theme: theme,
                colors: colors,
                child: comp.existingExamples.isEmpty
                    ? Text(
                        'Aucun exemple enregistré',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final existingVal in comp.existingExamples)
                            _buildExistingValuePill(
                              existingVal,
                              willBeRemoved:
                                  _mode == ExampleInjectionMode.replace &&
                                  selectedValues.isNotEmpty &&
                                  !selectedValues.any(
                                    (s) => _valuesEqual(s, existingVal),
                                  ),
                              theme: theme,
                              colors: colors,
                            ),
                        ],
                      ),
              );

              final candidatesPane = _buildColumnBox(
                title: 'Cartes vertes (${comp.candidates.length})',
                theme: theme,
                colors: colors,
                child: comp.candidates.isEmpty
                    ? Text(
                        'Aucune valeur correspondante dans cette story',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < comp.candidates.length; i++)
                            _buildCandidateChip(
                              comp,
                              i,
                              comp.candidates[i],
                              isSelected: selectedIndices.contains(i),
                              theme: theme,
                              colors: colors,
                            ),
                        ],
                      ),
              );

              if (constraints.maxWidth >= 520) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: existingPane),
                    const SizedBox(width: 10),
                    Expanded(child: candidatesPane),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  existingPane,
                  const SizedBox(height: 8),
                  candidatesPane,
                ],
              );
            },
          ),
          if (comp.hasCandidates) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Text(
                'Après injection : ${outcome.nextExamples.map(_formatValue).join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: hasChange ? colors.primary : colors.onSurfaceVariant,
                  fontWeight: hasChange ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColumnBox({
    required String title,
    required ThemeData theme,
    required ColorScheme colors,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _buildExistingValuePill(
    Object? value, {
    required bool willBeRemoved,
    required ThemeData theme,
    required ColorScheme colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: willBeRemoved
            ? colors.errorContainer.withValues(alpha: 0.5)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _formatValue(value),
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          decoration: willBeRemoved ? TextDecoration.lineThrough : null,
          color: willBeRemoved ? colors.onErrorContainer : colors.onSurface,
        ),
      ),
    );
  }

  Widget _buildCandidateChip(
    AttributeExampleComparison comp,
    int index,
    ExampleCandidateValue candidate, {
    required bool isSelected,
    required ThemeData theme,
    required ColorScheme colors,
  }) {
    final formatted = _formatValue(candidate.value);
    final label = candidate.alreadyPresent
        ? '$formatted (déjà présent)'
        : formatted;

    return Tooltip(
      message: candidate.sources.join('\n'),
      child: FilterChip(
        key: ValueKey('spec-em-inject-candidate-${comp.attributePath}-$index'),
        selected: isSelected,
        onSelected: (checked) {
          setState(() {
            final set = _selectedIndicesByPath.putIfAbsent(
              comp.attributePath,
              () => <int>{},
            );
            if (checked) {
              set.add(index);
            } else {
              set.remove(index);
            }
          });
        },
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: candidate.alreadyPresent && !isSelected
                ? colors.onSurfaceVariant
                : null,
          ),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildUnmatchedBanner(
    BuildContext context,
    String objectTechnicalName,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final entries = widget.preview.unmatchedCandidates.entries;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.tertiary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: colors.tertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Clés des cartes vertes absentes de $objectTechnicalName',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in entries)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${entry.key}: ${entry.value.map((c) => _formatValue(c.value)).join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatValue(Object? value) {
    if (value is String) return '"$value"';
    if (value is List || value is Map) return jsonEncode(value);
    return '$value';
  }

  static bool _listsEqual(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_valuesEqual(a[i], b[i])) return false;
    }
    return true;
  }

  static bool _valuesEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is List && b is List) return _listsEqual(a, b);
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) return false;
        if (!_valuesEqual(entry.value, b[entry.key])) return false;
      }
      return true;
    }
    return a == b;
  }
}
