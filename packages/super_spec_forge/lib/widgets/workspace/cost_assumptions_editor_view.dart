/// Atelier de l'étape Coûts 1 : Équipe, Grille TJM, Abaques T-shirt PERT et Accélération IA ([CostAssumptionsEditorView]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/cost/cost_forge_spec.dart';
import '../../models/enterprise_rate_card.dart';
import '../../services/cost_calculator.dart';
import '../../services/spec_forge_controller.dart';

/// Éditeur de l'étape 1 du wizard d'estimation de coût IT : devise, mode de delivery,
/// grille des profils TJM, abaques T-shirt PERT, ratios transverses et simulateur d'accélération IA.
class CostAssumptionsEditorView extends StatelessWidget {
  /// Crée la vue d'édition des hypothèses et de la grille TJM du projet.
  const CostAssumptionsEditorView({
    required this.controller,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    if (project == null) return const SizedBox.shrink();

    final spec = project.costSpec;
    final summary = CostCalculator.compute(spec);
    final avgRate = EnterpriseRateCard(
      currency: spec.currency,
      hoursPerDay: spec.hoursPerDay,
      defaultDeliveryMode: spec.deliveryMode,
      profiles: spec.profiles,
      tshirtPresets: spec.tshirtPresets,
      transverseRatios: spec.transverseRatios,
      aiProductivity: spec.aiProductivity,
    ).averageDailyRate(spec.deliveryMode);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      key: const ValueKey('cost-assumptions-editor-view'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Équipe, Grille TJM & Hypothèses FinOps',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('cost-import-enterprise-rates-btn'),
                    onPressed: () async {
                      final changed =
                          await controller.applyEnterpriseRateCardToProject();
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text(
                            changed
                                ? 'Grille TJM d’entreprise appliquée au projet.'
                                : 'Le projet utilise déjà la grille TJM d’entreprise.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Importer Grille Entreprise'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('cost-promote-enterprise-rates-btn'),
                    onPressed: () async {
                      await controller.promoteProjectRateCardToEnterprise();
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Grille du projet enregistrée comme standard Entreprise.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.upload_rounded, size: 16),
                    label: const Text('Sauver en Grille Entreprise'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricBadgeCard(
                label: 'TJM moyen (${spec.deliveryMode.label})',
                value: CostCalculator.formatAmount(avgRate, spec.currency),
                subtitle: '${spec.profiles.length} profils · ${spec.hoursPerDay} h/j',
                icon: Icons.badge_outlined,
                colors: colors,
              ),
              _MetricBadgeCard(
                label: 'Charge Build Cible',
                value: CostCalculator.formatDays(
                  summary.fullLot.effectiveTotalDays,
                ),
                subtitle: CostCalculator.formatAmount(
                  summary.fullLot.effectiveTotalCost,
                  spec.currency,
                ),
                icon: Icons.work_outline_rounded,
                colors: colors,
              ),
              _MetricBadgeCard(
                label: 'Gain Accélération IA',
                value: spec.aiProductivity.enabled
                    ? '-${CostCalculator.formatDays(summary.fullLot.aiSavedDays)}'
                    : 'Désactivé',
                subtitle: spec.aiProductivity.enabled
                    ? 'Économie : ${CostCalculator.formatAmount(summary.fullLot.aiSavedCost, spec.currency)}'
                    : 'Mode ingénierie classique',
                icon: Icons.bolt_rounded,
                colors: colors,
                highlight: spec.aiProductivity.enabled &&
                    summary.fullLot.aiSavedCost > 0,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildGeneralSettingsCard(context, spec, theme, colors),
          const SizedBox(height: 16),
          _buildAiProductivityCard(context, spec, theme, colors),
          const SizedBox(height: 16),
          _buildProfilesCard(context, spec, theme, colors),
          const SizedBox(height: 16),
          _buildPresetsAndRatiosCard(context, spec, theme, colors),
        ],
      ),
    );
  }

  Widget _buildGeneralSettingsCard(
    BuildContext context,
    CostForgeSpec spec,
    ThemeData theme,
    ColorScheme colors,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paramètres contractuels & volumétrie',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<CostCurrency>(
                    key: const ValueKey('cost-currency-dropdown'),
                    initialValue: spec.currency,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Devise',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in CostCurrency.values)
                        DropdownMenuItem(
                          value: c,
                          child: Text(
                            c.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (next) {
                      if (next != null) {
                        controller.updateCostSpec(spec.copyWith(currency: next));
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<CostDeliveryMode>(
                    key: const ValueKey('cost-delivery-mode-dropdown'),
                    initialValue: spec.deliveryMode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Mode de réalisation',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final m in CostDeliveryMode.values)
                        DropdownMenuItem(
                          value: m,
                          child: Text(
                            m.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (next) {
                      if (next != null) {
                        controller.updateCostSpec(
                          spec.copyWith(deliveryMode: next),
                        );
                      }
                    },
                  ),
                ),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Heures/jour :', style: theme.textTheme.bodyMedium),
                    for (final h in const <double>[7.0, 7.5, 8.0])
                      ChoiceChip(
                        label: Text('${h.toStringAsFixed(1)} h'),
                        selected: (spec.hoursPerDay - h).abs() < 0.05,
                        onSelected: (_) => controller.updateCostSpec(
                          spec.copyWith(hoursPerDay: h),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Cible utilisateurs :', style: theme.textTheme.bodyMedium),
                    for (final u in const <int>[100, 1000, 10000, 50000])
                      ChoiceChip(
                        label: Text('$u'),
                        selected: spec.targetUsersCount == u,
                        onSelected: (_) => controller.updateCostSpec(
                          spec.copyWith(targetUsersCount: u),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiProductivityCard(
    BuildContext context,
    CostForgeSpec spec,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final ai = spec.aiProductivity;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Simulateur d’accélération d’ingénierie assistée par IA',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  key: const ValueKey('cost-ai-boost-switch'),
                  value: ai.enabled,
                  onChanged: (val) => controller.updateCostSpec(
                    spec.copyWith(aiProductivity: ai.copyWith(enabled: val)),
                  ),
                ),
              ],
            ),
            if (ai.enabled) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _GainSliderTile(
                    label: 'Backend & Métier',
                    value: ai.backendGainPct,
                    onChanged: (v) => controller.updateCostSpec(
                      spec.copyWith(
                        aiProductivity: ai.copyWith(backendGainPct: v),
                      ),
                    ),
                  ),
                  _GainSliderTile(
                    label: 'Frontend & UX',
                    value: ai.frontendUxGainPct,
                    onChanged: (v) => controller.updateCostSpec(
                      spec.copyWith(
                        aiProductivity: ai.copyWith(frontendUxGainPct: v),
                      ),
                    ),
                  ),
                  _GainSliderTile(
                    label: 'Data & Intégrations',
                    value: ai.dataIntegrationGainPct,
                    onChanged: (v) => controller.updateCostSpec(
                      spec.copyWith(
                        aiProductivity: ai.copyWith(dataIntegrationGainPct: v),
                      ),
                    ),
                  ),
                  _GainSliderTile(
                    label: 'QA / BDD & Tests',
                    value: ai.qaTestingGainPct,
                    onChanged: (v) => controller.updateCostSpec(
                      spec.copyWith(
                        aiProductivity: ai.copyWith(qaTestingGainPct: v),
                      ),
                    ),
                  ),
                  _GainSliderTile(
                    label: 'DevSecOps & Cloud',
                    value: ai.devSecOpsGainPct,
                    onChanged: (v) => controller.updateCostSpec(
                      spec.copyWith(
                        aiProductivity: ai.copyWith(devSecOpsGainPct: v),
                      ),
                    ),
                  ),
                  _GainSliderTile(
                    label: 'Pilotage & Specs',
                    value: ai.pmSpecsGainPct,
                    onChanged: (v) => controller.updateCostSpec(
                      spec.copyWith(
                        aiProductivity: ai.copyWith(pmSpecsGainPct: v),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfilesCard(
    BuildContext context,
    CostForgeSpec spec,
    ThemeData theme,
    ColorScheme colors,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Grille des profils & TJM (${spec.profiles.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('cost-add-profile-btn'),
                  onPressed: () => _showProfileDialog(context, spec),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Ajouter un profil'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final profile in spec.profiles)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                leading: Chip(
                  label: Text(profile.code),
                  visualDensity: VisualDensity.compact,
                ),
                title: Text(
                  '${profile.name} (${profile.seniority})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${profile.discipline.label} · Interne : ${CostCalculator.formatAmount(profile.internalDailyRate, spec.currency)} · ESN : ${CostCalculator.formatAmount(profile.externalDailyRate, spec.currency)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Actif : ${CostCalculator.formatAmount(profile.effectiveDailyRate(spec.deliveryMode), spec.currency)}/j',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Modifier le profil',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () =>
                          _showProfileDialog(context, spec, existing: profile),
                    ),
                    if (spec.profiles.length > 1)
                      IconButton(
                        tooltip: 'Supprimer le profil',
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        onPressed: () {
                          final next = spec.profiles
                              .where((p) => p.id != profile.id)
                              .toList();
                          controller.updateCostSpec(
                            spec.copyWith(profiles: next),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetsAndRatiosCard(
    BuildContext context,
    CostForgeSpec spec,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final r = spec.transverseRatios;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ratios transverses & Abaques T-shirt (jours/homme PERT)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _GainSliderTile(
                  label: 'Pilotage / Chefferie',
                  value: r.projectManagementPct,
                  max: 50,
                  onChanged: (v) => controller.updateCostSpec(
                    spec.copyWith(
                      transverseRatios: r.copyWith(projectManagementPct: v),
                    ),
                  ),
                ),
                _GainSliderTile(
                  label: 'Architecture & DevOps',
                  value: r.architectureDevOpsPct,
                  max: 50,
                  onChanged: (v) => controller.updateCostSpec(
                    spec.copyWith(
                      transverseRatios: r.copyWith(architectureDevOpsPct: v),
                    ),
                  ),
                ),
                _GainSliderTile(
                  label: 'Recette & QA transverse',
                  value: r.transverseQaPct,
                  max: 50,
                  onChanged: (v) => controller.updateCostSpec(
                    spec.copyWith(
                      transverseRatios: r.copyWith(transverseQaPct: v),
                    ),
                  ),
                ),
                _GainSliderTile(
                  label: 'Contingence / Aléas',
                  value: r.contingencyPct,
                  max: 50,
                  onChanged: (v) => controller.updateCostSpec(
                    spec.copyWith(
                      transverseRatios: r.copyWith(contingencyPct: v),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final preset in spec.tshirtPresets)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Text(
                      '${preset.size.code} : ${preset.optimisticDays}/${preset.mostLikelyDays}/${preset.pessimisticDays} j/h '
                      '(PERT ${CostCalculator.formatDays(preset.expectedDays)})',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProfileDialog(
    BuildContext context,
    CostForgeSpec spec, {
    CostProfileRate? existing,
  }) async {
    final codeCtrl = TextEditingController(
      text: existing?.code ?? 'PRF-${spec.profiles.length + 1}',
    );
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final senCtrl = TextEditingController(
      text: existing?.seniority ?? 'Senior',
    );
    final intCtrl = TextEditingController(
      text: (existing?.internalDailyRate ?? 520).toStringAsFixed(0),
    );
    final extCtrl = TextEditingController(
      text: (existing?.externalDailyRate ?? 750).toStringAsFixed(0),
    );
    var discipline = existing?.discipline ?? CostDiscipline.backend;

    final saved = await showDialog<CostProfileRate>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: Text(
            existing == null ? 'Nouveau profil TJM' : 'Modifier ${existing.code}',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Code (ex. PRF-BACK)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Intitulé du profil'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: senCtrl,
                    decoration: const InputDecoration(labelText: 'Séniorité'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<CostDiscipline>(
                    initialValue: discipline,
                    decoration: const InputDecoration(labelText: 'Discipline'),
                    items: [
                      for (final d in CostDiscipline.values)
                        DropdownMenuItem(value: d, child: Text(d.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) setModal(() => discipline = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: intCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'TJM Interne (${spec.currency.symbol})',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: extCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'TJM ESN (${spec.currency.symbol})',
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
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final internal =
                    (double.tryParse(intCtrl.text.replaceAll(',', '.')) ?? 500)
                        .clamp(0.0, 100000.0);
                final external =
                    (double.tryParse(extCtrl.text.replaceAll(',', '.')) ?? 700)
                        .clamp(0.0, 100000.0);
                Navigator.of(ctx).pop(
                  CostProfileRate(
                    id: existing?.id ?? 'prof_${shortid.generate()}',
                    code: codeCtrl.text.trim().isEmpty
                        ? 'PRF-NEW'
                        : codeCtrl.text.trim(),
                    name: name,
                    seniority: senCtrl.text.trim().isEmpty
                        ? 'Confirmé'
                        : senCtrl.text.trim(),
                    discipline: discipline,
                    internalDailyRate: internal,
                    externalDailyRate: external,
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
    final nextProfiles = List<CostProfileRate>.from(spec.profiles);
    final idx = nextProfiles.indexWhere((p) => p.id == saved.id);
    if (idx >= 0) {
      nextProfiles[idx] = saved;
    } else {
      nextProfiles.add(saved);
    }
    await controller.updateCostSpec(spec.copyWith(profiles: nextProfiles));
  }
}

class _MetricBadgeCard extends StatelessWidget {
  const _MetricBadgeCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.colors,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final ColorScheme colors;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 245,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight
            ? colors.primaryContainer.withValues(alpha: 0.45)
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                const SizedBox(height: 2),
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
          ),
        ],
      ),
    );
  }
}

class _GainSliderTile extends StatelessWidget {
  const _GainSliderTile({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 60.0,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double max;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                '${value.round()} %',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(0.0, max),
            min: 0.0,
            max: max,
            divisions: max.round(),
            onChanged: (v) => onChanged(v.roundToDouble()),
          ),
        ],
      ),
    );
  }
}
