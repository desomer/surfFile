/// Atelier de l'étape Coûts 3 : Coûts Run, Cloud, Licences, APIs/LLM et TMA/MCO ([CostRunEditorView]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/cost/cost_forge_spec.dart';
import '../../models/cost/cost_run_item_spec.dart';
import '../../services/cost_calculator.dart';
import '../../services/spec_forge_controller.dart';

/// Éditeur de l'étape 3 du wizard d'estimation de coût IT : postes récurrents OPEX
/// (Cloud, BDD, APIs tierces, tokens LLM/IA, licences SaaS, sécurité et TMA/MCO).
class CostRunEditorView extends StatefulWidget {
  /// Crée l'éditeur des postes Run OPEX connecté au [controller].
  const CostRunEditorView({
    required this.controller,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  @override
  State<CostRunEditorView> createState() => _CostRunEditorViewState();
}

class _CostRunEditorViewState extends State<CostRunEditorView> {
  CostRunCategory? _categoryFilter;
  CostEnvironmentScope? _envFilter;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();

    final spec = project.costSpec;
    final summary = CostCalculator.compute(spec);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final query = _search.trim().toLowerCase();
    final filtered = spec.runItems.where((item) {
      if (_categoryFilter != null && item.category != _categoryFilter) {
        return false;
      }
      if (_envFilter != null && item.environment != _envFilter) return false;
      if (query.isNotEmpty &&
          !item.code.toLowerCase().contains(query) &&
          !item.name.toLowerCase().contains(query) &&
          !item.description.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();

    final perUserMonthly = spec.targetUsersCount > 0
        ? summary.monthlyRunYear1 / spec.targetUsersCount
        : 0.0;

    return Column(
      key: const ValueKey('cost-run-editor-view'),
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
                'Coûts Run, Cloud & Licences (OPEX)',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('cost-seed-run-btn'),
                    onPressed: () async {
                      final seeded =
                          await widget.controller.seedCostFromProject();
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text(
                            seeded.addedRunCount > 0
                                ? '+${seeded.addedRunCount} poste(s) Run ajoutés.'
                                : 'Le socle Run est déjà présent.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.cloud_sync_outlined, size: 16),
                    label: const Text('Ajouter socle Run'),
                  ),
                  PopupMenuButton<CostRunCategory>(
                    tooltip: 'Ajouter un poste type rapide',
                    onSelected: (cat) => _addQuickPreset(spec, cat),
                    itemBuilder: (_) => [
                      for (final c in CostRunCategory.values)
                        PopupMenuItem(value: c, child: Text('+ ${c.label}')),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.flash_on_rounded, size: 16),
                      label: const Text('Presets rapides'),
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('cost-add-run-btn'),
                    onPressed: () => _openRunDialog(context, spec),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Ajouter un poste Run'),
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
              _RunMetricTile(
                label: 'Run Mensuel (An 1)',
                value: CostCalculator.formatAmount(
                  summary.monthlyRunYear1,
                  spec.currency,
                ),
                subtitle:
                    '${perUserMonthly.toStringAsFixed(2)} ${spec.currency.symbol}/utilisateur (${spec.targetUsersCount})',
                colors: colors,
                highlight: true,
              ),
              _RunMetricTile(
                label: 'Run Annuel (An 1)',
                value: CostCalculator.formatAmount(
                  summary.yearlyRunYear1,
                  spec.currency,
                ),
                subtitle: 'An 3 : ${CostCalculator.formatAmount(summary.yearlyRunYear3, spec.currency)}',
                colors: colors,
              ),
              _RunMetricTile(
                label: 'OPEX Cumulé 3 ans',
                value: CostCalculator.formatAmount(
                  summary.cumulativeRun3Years,
                  spec.currency,
                ),
                subtitle:
                    '5 ans : ${CostCalculator.formatAmount(summary.cumulativeRun5Years, spec.currency, compact: true)}',
                colors: colors,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<CostRunCategory?>(
                value: _categoryFilter,
                hint: const Text('Toutes catégories'),
                items: [
                  const DropdownMenuItem<CostRunCategory?>(
                    value: null,
                    child: Text('Toutes catégories'),
                  ),
                  for (final c in CostRunCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _categoryFilter = v),
              ),
              DropdownButton<CostEnvironmentScope?>(
                value: _envFilter,
                hint: const Text('Tous environnements'),
                items: [
                  const DropdownMenuItem<CostEnvironmentScope?>(
                    value: null,
                    child: Text('Tous environnements'),
                  ),
                  for (final e in CostEnvironmentScope.values)
                    DropdownMenuItem(value: e, child: Text(e.label)),
                ],
                onChanged: (v) => setState(() => _envFilter = v),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Rechercher un poste Run…',
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
                          Icons.cloud_queue_rounded,
                          size: 42,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          spec.runItems.isEmpty
                              ? 'Aucun poste OPEX configuré.'
                              : 'Aucun poste ne correspond aux filtres.',
                          style: theme.textTheme.titleMedium,
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
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return Card(
                      key: ValueKey('cost-run-card-${item.id}'),
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Switch(
                          value: item.enabled,
                          onChanged: (val) {
                            final next = [
                              for (final r in spec.runItems)
                                if (r.id == item.id)
                                  r.copyWith(enabled: val)
                                else
                                  r,
                            ];
                            widget.controller.updateCostSpec(
                              spec.copyWith(runItems: next),
                            );
                          },
                        ),
                        title: Text(
                          '${item.code} — ${item.name}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: item.enabled
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Text(
                          '${item.category.label} · ${item.environment.label} · ${item.billingCycle.label} (${item.quantity} × ${CostCalculator.formatAmount(item.unitCost, spec.currency)})'
                          '${item.annualGrowthPct != 0 ? ' · Croissance ${item.annualGrowthPct.toStringAsFixed(0)} %/an' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${CostCalculator.formatAmount(item.monthlyCost, spec.currency)}/mois',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${CostCalculator.formatAmount(item.yearlyCost, spec.currency)}/an',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Modifier',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () =>
                                  _openRunDialog(context, spec, existing: item),
                            ),
                            IconButton(
                              tooltip: 'Supprimer',
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                              onPressed: () {
                                final next = spec.runItems
                                    .where((r) => r.id != item.id)
                                    .toList();
                                widget.controller.updateCostSpec(
                                  spec.copyWith(runItems: next),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _addQuickPreset(CostForgeSpec spec, CostRunCategory category) {
    final idx = spec.runItems.length + 1;
    final code = 'RUN-${idx.toString().padLeft(3, '0')}';
    final (name, cost, growth) = switch (category) {
      CostRunCategory.cloudInfra => ('Compute & Conteneurs Prod', 350.0, 10.0),
      CostRunCategory.databaseStorage => (
        'Base de données managée & Stockage',
        180.0,
        12.0,
      ),
      CostRunCategory.thirdPartyApi => (
        'Passerelles e-mail, SMS & APIs tierces',
        90.0,
        10.0,
      ),
      CostRunCategory.aiTokensLlm => (
        'Inférence LLM & Embeddings IA',
        220.0,
        15.0,
      ),
      CostRunCategory.saasLicenses => (
        'Outillage CI/CD, Observabilité & APM',
        120.0,
        5.0,
      ),
      CostRunCategory.supportTma => (
        'Forfait MCO / TMA corrective & évolutive',
        1200.0,
        3.0,
      ),
      CostRunCategory.securityCompliance => (
        'Sauvegardes, WAF & Audit Sécurité',
        150.0,
        5.0,
      ),
    };
    final created = CostRunItemSpec(
      id: 'run_${shortid.generate()}',
      code: code,
      name: name,
      category: category,
      environment: CostEnvironmentScope.prod,
      billingCycle: CostBillingCycle.monthly,
      unitCost: cost,
      quantity: 1.0,
      annualGrowthPct: growth,
    );
    widget.controller.updateCostSpec(
      spec.copyWith(runItems: [...spec.runItems, created]),
    );
  }

  Future<void> _openRunDialog(
    BuildContext context,
    CostForgeSpec spec, {
    CostRunItemSpec? existing,
  }) async {
    final idx = spec.runItems.length + 1;
    final codeCtrl = TextEditingController(
      text: existing?.code ?? 'RUN-${idx.toString().padLeft(3, '0')}',
    );
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final unitCtrl = TextEditingController(
      text: (existing?.unitCost ?? 250.0).toStringAsFixed(0),
    );
    final qtyCtrl = TextEditingController(
      text: (existing?.quantity ?? 1.0).toString(),
    );
    final growthCtrl = TextEditingController(
      text: (existing?.annualGrowthPct ?? 5.0).toStringAsFixed(0),
    );
    var category = existing?.category ?? CostRunCategory.cloudInfra;
    var env = existing?.environment ?? CostEnvironmentScope.prod;
    var cycle = existing?.billingCycle ?? CostBillingCycle.monthly;

    final saved = await showDialog<CostRunItemSpec>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: Text(
            existing == null ? 'Nouveau poste Run OPEX' : 'Modifier ${existing.code}',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: codeCtrl,
                          decoration: const InputDecoration(labelText: 'Code'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('cost-run-dialog-name-input'),
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nom du poste *',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<CostRunCategory>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Catégorie'),
                    items: [
                      for (final c in CostRunCategory.values)
                        DropdownMenuItem(value: c, child: Text(c.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) setModal(() => category = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<CostEnvironmentScope>(
                          initialValue: env,
                          decoration: const InputDecoration(
                            labelText: 'Environnement',
                          ),
                          items: [
                            for (final e in CostEnvironmentScope.values)
                              DropdownMenuItem(value: e, child: Text(e.label)),
                          ],
                          onChanged: (v) {
                            if (v != null) setModal(() => env = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<CostBillingCycle>(
                          initialValue: cycle,
                          decoration: const InputDecoration(labelText: 'Cycle'),
                          items: [
                            for (final b in CostBillingCycle.values)
                              DropdownMenuItem(value: b, child: Text(b.label)),
                          ],
                          onChanged: (v) {
                            if (v != null) setModal(() => cycle = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: unitCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Coût unitaire (${spec.currency.symbol})',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantité',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: growthCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Croissance %/an',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes / Dimensionnement',
                    ),
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
              key: const ValueKey('cost-run-dialog-save-btn'),
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final unit =
                    (double.tryParse(unitCtrl.text.replaceAll(',', '.')) ?? 0.0)
                        .clamp(0.0, 1e9);
                final qty =
                    (double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1.0)
                        .clamp(0.0, 1e9);
                final growth =
                    (double.tryParse(growthCtrl.text.replaceAll(',', '.')) ??
                            0.0)
                        .clamp(-50.0, 500.0);
                Navigator.of(ctx).pop(
                  CostRunItemSpec(
                    id: existing?.id ?? 'run_${shortid.generate()}',
                    code: codeCtrl.text.trim().isEmpty
                        ? 'RUN-001'
                        : codeCtrl.text.trim(),
                    name: name,
                    description: descCtrl.text.trim(),
                    category: category,
                    environment: env,
                    billingCycle: cycle,
                    unitCost: unit,
                    quantity: qty,
                    annualGrowthPct: growth,
                    enabled: existing?.enabled ?? true,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (saved == null) return;
    final next = List<CostRunItemSpec>.from(spec.runItems);
    final i = next.indexWhere((r) => r.id == saved.id);
    if (i >= 0) {
      next[i] = saved;
    } else {
      next.add(saved);
    }
    await widget.controller.updateCostSpec(spec.copyWith(runItems: next));
  }
}

class _RunMetricTile extends StatelessWidget {
  const _RunMetricTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.colors,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String subtitle;
  final ColorScheme colors;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 235,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? colors.primaryContainer.withValues(alpha: 0.45)
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
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
