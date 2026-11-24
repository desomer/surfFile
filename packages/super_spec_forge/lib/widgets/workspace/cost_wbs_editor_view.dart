/// Atelier de l'étape Coûts 2 : Chiffrage Build (CAPEX / WBS) par T-shirt, PERT 3 points et jours/homme ([CostWbsEditorView]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/cost/cost_forge_spec.dart';
import '../../models/cost/cost_wbs_item_spec.dart';
import '../../models/enterprise_rate_card.dart';
import '../../models/spec_cahier_des_charges.dart';
import '../../models/spec_forge_project.dart';
import '../../services/cost_calculator.dart';
import '../../services/spec_forge_controller.dart';

enum _WbsEffortInputMode { tshirt, directDays, pert3Points }

/// Éditeur de l'étape 2 du wizard d'estimation de coût IT : découpage WBS traçable,
/// pré-chiffrage automatique depuis la spec, lotissement MoSCoW et saisie en T-shirt / jours/homme / PERT.
class CostWbsEditorView extends StatefulWidget {
  /// Crée l'éditeur WBS connecté au [controller].
  const CostWbsEditorView({
    required this.controller,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  @override
  State<CostWbsEditorView> createState() => _CostWbsEditorViewState();
}

class _CostWbsEditorViewState extends State<CostWbsEditorView> {
  CostScopeFilter _scopeFilter = CostScopeFilter.fullTarget;
  CostDiscipline? _disciplineFilter;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();

    final spec = project.costSpec;
    final summary = CostCalculator.compute(spec);
    final lot = summary.lotFor(_scopeFilter);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final query = _search.trim().toLowerCase();
    final filtered = spec.wbsItems.where((item) {
      if (!_scopeFilter.includes(item.priority)) return false;
      if (_disciplineFilter != null && item.discipline != _disciplineFilter) {
        return false;
      }
      if (query.isNotEmpty &&
          !item.code.toLowerCase().contains(query) &&
          !item.title.toLowerCase().contains(query) &&
          !item.description.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      key: const ValueKey('cost-wbs-editor-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Chiffrage Build (CAPEX / WBS)',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('cost-seed-wbs-btn'),
                    onPressed: () async {
                      final seeded =
                          await widget.controller.seedCostFromProject();
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text(
                            seeded.totalAdded > 0
                                ? 'Pré-chiffrage : +${seeded.addedWbsCount} lots WBS, +${seeded.addedRunCount} postes Run, +${seeded.addedRiskCount} risques.'
                                : 'Tous les artefacts actuels de la spec sont déjà couverts.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                    label: const Text('Pré-chiffrer depuis la Spec'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('cost-add-wbs-btn'),
                    onPressed: () => _openWbsDialog(context, project),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Ajouter un lot WBS'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _KpiChip(
                label: 'WBS Direct (${lot.itemCount} lots)',
                value:
                    '${CostCalculator.formatDays(lot.wbsExpectedDays)} · P80 ${CostCalculator.formatDays(lot.wbsP80Days)}',
                colors: colors,
              ),
              _KpiChip(
                label: 'Charge Totale (${_scopeFilter.label})',
                value: CostCalculator.formatDays(lot.effectiveTotalDays),
                colors: colors,
              ),
              _KpiChip(
                label: 'Budget Build',
                value:
                    '${CostCalculator.formatAmount(lot.effectiveTotalCost, spec.currency)} (P80 : ${CostCalculator.formatAmount(lot.effectiveP80Cost, spec.currency, compact: true)})',
                colors: colors,
                highlight: true,
              ),
              if (spec.aiProductivity.enabled && lot.aiSavedDays > 0)
                _KpiChip(
                  label: 'Économie IA',
                  value:
                      '-${CostCalculator.formatDays(lot.aiSavedDays)} · -${CostCalculator.formatAmount(lot.aiSavedCost, spec.currency, compact: true)}',
                  colors: colors,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in CostScopeFilter.values)
                ChoiceChip(
                  key: ValueKey('cost-scope-chip-${f.name}'),
                  label: Text(f.label),
                  selected: _scopeFilter == f,
                  onSelected: (_) => setState(() => _scopeFilter = f),
                ),
              const SizedBox(width: 8),
              DropdownButton<CostDiscipline?>(
                value: _disciplineFilter,
                hint: const Text('Toutes disciplines'),
                items: [
                  const DropdownMenuItem<CostDiscipline?>(
                    value: null,
                    child: Text('Toutes disciplines'),
                  ),
                  for (final d in CostDiscipline.values)
                    DropdownMenuItem(value: d, child: Text(d.shortLabel)),
                ],
                onChanged: (v) => setState(() => _disciplineFilter = v),
              ),
              SizedBox(
                width: 210,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Filtrer code ou titre…',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calculate_outlined,
                          size: 42,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          spec.wbsItems.isEmpty
                              ? 'Aucun lot WBS chiffré pour le moment.'
                              : 'Aucun lot WBS ne correspond aux filtres actifs.',
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        if (spec.wbsItems.isEmpty)
                          const Text(
                            'Cliquez sur « Pré-chiffrer depuis la Spec » pour générer automatiquement le WBS initial à partir de vos exigences, objets métiers, écrans UX et tests BDD/TDD.',
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _buildWbsCard(
                    context,
                    project,
                    spec,
                    filtered[index],
                    theme,
                    colors,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildWbsCard(
    BuildContext context,
    SpecForgeProject project,
    CostForgeSpec spec,
    CostWbsItemSpec item,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final profile = CostCalculator.resolveItemProfile(item, spec);
    final effDays = CostCalculator.itemEffectiveDays(item, spec);
    final effCost = CostCalculator.itemEffectiveCost(item, spec);
    final traceCount = item.requirementIds.length +
        item.businessObjectIds.length +
        item.uxScreenIds.length +
        item.qaFeatureIds.length +
        item.tddSuiteIds.length;

    return Card(
      key: ValueKey('cost-wbs-card-${item.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      label: Text(item.code),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      label: Text(item.priority.code),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      label: Text(item.discipline.shortLabel),
                      visualDensity: VisualDensity.compact,
                    ),
                    Text(
                      item.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final size in const <CostTShirtSize>[
                      CostTShirtSize.xs,
                      CostTShirtSize.s,
                      CostTShirtSize.m,
                      CostTShirtSize.l,
                      CostTShirtSize.xl,
                    ])
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          final updated =
                              item.withTShirtPreset(spec.presetFor(size));
                          _replaceItem(spec, updated);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: item.tshirtSize == size
                                ? colors.primaryContainer
                                : colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            size.code,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: item.tshirtSize == size
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      '${CostCalculator.formatDays(effDays)} · ${CostCalculator.formatAmount(effCost, spec.currency)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Modifier ce lot WBS',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () =>
                          _openWbsDialog(context, project, existing: item),
                    ),
                    IconButton(
                      tooltip: 'Supprimer ce lot WBS',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () {
                        final next = spec.wbsItems
                            .where((w) => w.id != item.id)
                            .toList();
                        widget.controller.updateCostSpec(
                          spec.copyWith(wbsItems: next),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Profil : ${profile.name} (${CostCalculator.formatAmount(profile.effectiveDailyRate(spec.deliveryMode), spec.currency)}/j) · '
              '${item.isDirectDays ? 'Charge directe fixe : ${CostCalculator.formatDays(item.expectedDays)}' : 'PERT O/M/P : ${item.optimisticDays}/${item.mostLikelyDays}/${item.pessimisticDays} → ${CostCalculator.formatDays(item.expectedDays)}'}'
              '${traceCount > 0 ? ' · $traceCount réf. liées' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(item.description, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  void _replaceItem(CostForgeSpec spec, CostWbsItemSpec updated) {
    final next = [
      for (final w in spec.wbsItems)
        if (w.id == updated.id) updated else w,
    ];
    widget.controller.updateCostSpec(spec.copyWith(wbsItems: next));
  }

  Future<void> _openWbsDialog(
    BuildContext context,
    SpecForgeProject project, {
    CostWbsItemSpec? existing,
  }) async {
    final spec = project.costSpec;
    final nextIndex = spec.wbsItems.length + 1;
    final codeCtrl = TextEditingController(
      text: existing?.code ?? 'WBS-${nextIndex.toString().padLeft(3, '0')}',
    );
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    var mode = existing == null
        ? _WbsEffortInputMode.tshirt
        : (existing.isDirectDays
              ? _WbsEffortInputMode.directDays
              : (existing.tshirtSize == CostTShirtSize.custom
                    ? _WbsEffortInputMode.pert3Points
                    : _WbsEffortInputMode.tshirt));
    var tshirt = existing != null && existing.tshirtSize != CostTShirtSize.custom
        ? existing.tshirtSize
        : CostTShirtSize.m;
    var priority = existing?.priority ?? RequirementPriority.must;
    var discipline = existing?.discipline ?? CostDiscipline.backend;
    var profileId = existing?.profileId ??
        spec.resolveProfileForDiscipline(discipline).id;
    var aiEligible = existing?.aiEligible ?? true;

    final preset = spec.presetFor(tshirt);
    final directCtrl = TextEditingController(
      text: (existing?.expectedDays ?? preset.mostLikelyDays).toStringAsFixed(1),
    );
    final optCtrl = TextEditingController(
      text: (existing?.optimisticDays ?? preset.optimisticDays).toString(),
    );
    final mostCtrl = TextEditingController(
      text: (existing?.mostLikelyDays ?? preset.mostLikelyDays).toString(),
    );
    final pessCtrl = TextEditingController(
      text: (existing?.pessimisticDays ?? preset.pessimisticDays).toString(),
    );

    final saved = await showDialog<CostWbsItemSpec>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: Text(
            existing == null ? 'Nouveau lot Build WBS' : 'Modifier ${existing.code}',
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: codeCtrl,
                          decoration: const InputDecoration(labelText: 'Code'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('cost-wbs-dialog-title-input'),
                          controller: titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Intitulé du lot *',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Hypothèses & livrables inclus',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<RequirementPriority>(
                          initialValue: priority,
                          decoration: const InputDecoration(
                            labelText: 'Lot MoSCoW',
                          ),
                          items: [
                            for (final p in RequirementPriority.values)
                              DropdownMenuItem(
                                value: p,
                                child: Text('${p.code} (${p.label})'),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) setModal(() => priority = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<CostDiscipline>(
                          initialValue: discipline,
                          decoration: const InputDecoration(
                            labelText: 'Discipline',
                          ),
                          items: [
                            for (final d in CostDiscipline.values)
                              DropdownMenuItem(value: d, child: Text(d.label)),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setModal(() {
                                discipline = v;
                                profileId =
                                    spec.resolveProfileForDiscipline(v).id;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: spec.profiles.any((p) => p.id == profileId)
                        ? profileId
                        : spec.profiles.first.id,
                    decoration: const InputDecoration(labelText: 'Profil TJM'),
                    items: [
                      for (final p in spec.profiles)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            '${p.code} — ${p.name} (${CostCalculator.formatAmount(p.effectiveDailyRate(spec.deliveryMode), spec.currency)}/j)',
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setModal(() => profileId = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<_WbsEffortInputMode>(
                    segments: const [
                      ButtonSegment(
                        value: _WbsEffortInputMode.tshirt,
                        label: Text('Taille T-shirt'),
                      ),
                      ButtonSegment(
                        value: _WbsEffortInputMode.directDays,
                        label: Text('Jours/homme (fixe)'),
                      ),
                      ButtonSegment(
                        value: _WbsEffortInputMode.pert3Points,
                        label: Text('PERT 3 points (j/h)'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => setModal(() => mode = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (mode == _WbsEffortInputMode.tshirt)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in const <CostTShirtSize>[
                          CostTShirtSize.xs,
                          CostTShirtSize.s,
                          CostTShirtSize.m,
                          CostTShirtSize.l,
                          CostTShirtSize.xl,
                        ])
                          ChoiceChip(
                            label: Text(
                              '${s.code} (${CostCalculator.formatDays(spec.presetFor(s).expectedDays)})',
                            ),
                            selected: tshirt == s,
                            onSelected: (_) => setModal(() => tshirt = s),
                          ),
                      ],
                    )
                  else if (mode == _WbsEffortInputMode.directDays)
                    TextField(
                      key: const ValueKey('cost-wbs-dialog-direct-days-input'),
                      controller: directCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Charge fixe en jours/homme (j/h)',
                        border: OutlineInputBorder(),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: optCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Optimiste O (j/h)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: mostCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Probable M (j/h)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: pessCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Pessimiste P (j/h)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Éligible à l’accélération IA'),
                    value: aiEligible,
                    onChanged: (v) => setModal(() => aiEligible = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('cost-wbs-dialog-save-btn'),
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                var base = CostWbsItemSpec(
                  id: existing?.id ?? 'wbs_${shortid.generate()}',
                  code: codeCtrl.text.trim().isEmpty
                      ? 'WBS-001'
                      : codeCtrl.text.trim(),
                  title: title,
                  description: descCtrl.text.trim(),
                  discipline: discipline,
                  priority: priority,
                  profileId: profileId,
                  aiEligible: aiEligible,
                  moduleId: existing?.moduleId ?? '',
                  requirementIds: existing?.requirementIds ?? const [],
                  businessObjectIds: existing?.businessObjectIds ?? const [],
                  uxScreenIds: existing?.uxScreenIds ?? const [],
                  qaFeatureIds: existing?.qaFeatureIds ?? const [],
                  tddSuiteIds: existing?.tddSuiteIds ?? const [],
                  origin: existing?.origin ?? 'manual',
                );
                if (mode == _WbsEffortInputMode.tshirt) {
                  base = base.withTShirtPreset(spec.presetFor(tshirt));
                } else if (mode == _WbsEffortInputMode.directDays) {
                  final d = double.tryParse(
                        directCtrl.text.replaceAll(',', '.'),
                      ) ??
                      1.0;
                  base = base.withDirectDays(d);
                } else {
                  final rawO =
                      (double.tryParse(optCtrl.text.replaceAll(',', '.')) ??
                              1.0)
                          .clamp(0.0, 10000.0);
                  final rawM =
                      (double.tryParse(mostCtrl.text.replaceAll(',', '.')) ??
                              rawO)
                          .clamp(0.0, 10000.0);
                  final rawP =
                      (double.tryParse(pessCtrl.text.replaceAll(',', '.')) ??
                              rawM)
                          .clamp(0.0, 10000.0);
                  final sorted = <double>[rawO, rawM, rawP]..sort();
                  base = base.copyWith(
                    tshirtSize: CostTShirtSize.custom,
                    optimisticDays: sorted[0],
                    mostLikelyDays: sorted[1],
                    pessimisticDays: sorted[2],
                  );
                }
                Navigator.of(ctx).pop(base);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (saved == null) return;
    final nextList = List<CostWbsItemSpec>.from(spec.wbsItems);
    final idx = nextList.indexWhere((w) => w.id == saved.id);
    if (idx >= 0) {
      nextList[idx] = saved;
    } else {
      nextList.add(saved);
    }
    await widget.controller.updateCostSpec(spec.copyWith(wbsItems: nextList));
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({
    required this.label,
    required this.value,
    required this.colors,
    this.highlight = false,
  });

  final String label;
  final String value;
  final ColorScheme colors;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? colors.primaryContainer.withValues(alpha: 0.5)
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
