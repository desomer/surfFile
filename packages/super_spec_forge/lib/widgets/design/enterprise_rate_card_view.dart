/// Éditeur Desktop partagé de la Grille TJM & Abaques IT d'entreprise ([EnterpriseRateCardView]).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/enterprise_rate_card.dart';
import '../../services/enterprise_rate_card_store.dart';
import '../../services/spec_forge_controller.dart';

/// Vue dédiée au paramétrage global de la **Grille TJM & Abaques IT d'entreprise**
/// ([SpecForgeController.enterpriseRateCard]) partagée entre tous les projets du workspace.
class EnterpriseRateCardView extends StatefulWidget {
  /// Crée l'éditeur de grille tarifaire d'entreprise connecté au [controller].
  const EnterpriseRateCardView({
    required this.controller,
    this.pickAttachments,
    super.key,
  });

  /// Contrôleur principal exposant [SpecForgeController.enterpriseRateCard].
  final SpecForgeController controller;

  /// Sélecteur optionnel de fichiers pour l'import JSON (remplace [VibeChatAttachment.pickFiles] en test).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  @override
  State<EnterpriseRateCardView> createState() => _EnterpriseRateCardViewState();
}

class _EnterpriseRateCardViewState extends State<EnterpriseRateCardView> {
  static const List<CostTShirtSize> _standardSizes = <CostTShirtSize>[
    CostTShirtSize.xs,
    CostTShirtSize.s,
    CostTShirtSize.m,
    CostTShirtSize.l,
    CostTShirtSize.xl,
  ];

  static const List<double> _presetHoursPerDay = <double>[7.0, 7.5, 8.0];

  Future<void> _updateCard(
    EnterpriseRateCard next, {
    bool recordUndo = true,
  }) async {
    await widget.controller.updateEnterpriseRateCard(
      next,
      recordUndo: recordUndo,
    );
  }

  Future<void> _applyToActiveProject(BuildContext context) async {
    final project = widget.controller.project;
    if (project == null) return;
    final changed = await widget.controller.applyEnterpriseRateCardToProject();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            changed
                ? 'Grille TJM et abaques appliqués au projet « ${project.name} ».'
                : 'Le projet « ${project.name} » utilise déjà cette grille TJM et ces abaques.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openImportExportDialog(
    BuildContext context,
    EnterpriseRateCard card,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EnterpriseRateCardImportExportDialog(
        controller: widget.controller,
        rateCard: card,
        pickAttachments: widget.pickAttachments,
      ),
    );
  }

  Future<void> _openEditProfileDialog(
    BuildContext context,
    EnterpriseRateCard card, {
    CostProfileRate? existing,
  }) async {
    final saved = await showDialog<CostProfileRate>(
      context: context,
      builder: (_) => _EditCostProfileDialog(
        existing: existing,
        currency: card.currency,
        deliveryMode: card.defaultDeliveryMode,
        existingIds: {for (final p in card.profiles) p.id},
      ),
    );
    if (saved == null) return;

    final nextProfiles = List<CostProfileRate>.from(card.profiles);
    if (existing == null) {
      nextProfiles.add(saved);
    } else {
      final index = nextProfiles.indexWhere((p) => p.id == existing.id);
      if (index >= 0) {
        nextProfiles[index] = saved;
      } else {
        nextProfiles.add(saved);
      }
    }
    await _updateCard(card.copyWith(profiles: nextProfiles));
  }

  Future<void> _deleteProfile(
    EnterpriseRateCard card,
    CostProfileRate target,
  ) async {
    if (card.profiles.length <= 1) return;
    final nextProfiles = card.profiles
        .where((p) => p.id != target.id)
        .toList();
    if (nextProfiles.isEmpty) return;
    await _updateCard(card.copyWith(profiles: nextProfiles));
  }

  Future<void> _updatePreset(
    EnterpriseRateCard card,
    TShirtEffortPreset updatedPreset,
  ) async {
    final nextPresets = <TShirtEffortPreset>[
      for (final size in _standardSizes)
        size == updatedPreset.size ? updatedPreset : card.presetFor(size),
    ];
    await _updateCard(card.copyWith(tshirtPresets: nextPresets));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final card = widget.controller.enterpriseRateCard;
        final project = widget.controller.project;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;

        return DefaultTabController(
          length: 3,
          child: Column(
            key: const ValueKey('enterprise-rate-card-view'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildToolbar(context, theme, colors, card, project?.name),
              Container(
                color: colors.surfaceContainerLow,
                child: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(
                      key: ValueKey('enterprise-tab-profiles'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.badge_outlined, size: 17),
                          SizedBox(width: 8),
                          Text('Profils & TJM'),
                        ],
                      ),
                    ),
                    Tab(
                      key: ValueKey('enterprise-tab-tshirt'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.straighten_rounded, size: 17),
                          SizedBox(width: 8),
                          Text('Abaques T-shirt (PERT j/h)'),
                        ],
                      ),
                    ),
                    Tab(
                      key: ValueKey('enterprise-tab-ratios-ai'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, size: 17),
                          SizedBox(width: 8),
                          Text('Ratios transverses & Gains IA'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildProfilesTab(context, theme, colors, card),
                    _buildTShirtTab(theme, colors, card),
                    _buildRatiosAndAiTab(theme, colors, card),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    EnterpriseRateCard card,
    String? activeProjectName,
  ) {
    final avgRate = _formatAmount(card.averageDailyRate());
    final subtitle =
        '${card.profiles.length} profil(s) · TJM moyen $avgRate ${card.currency.symbol}/j (${card.defaultDeliveryMode.label}) · ${_formatEditableNumber(card.hoursPerDay)} h/j';

    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.payments_outlined,
                size: 22,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grille TJM & Abaques IT d’entreprise',
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('enterprise-undo-btn'),
                tooltip: 'Annuler',
                icon: const Icon(Icons.undo_rounded, size: 18),
                onPressed: widget.controller.canUndoEnterpriseRateCard
                    ? widget.controller.undoEnterpriseRateCard
                    : null,
              ),
              IconButton(
                key: const ValueKey('enterprise-redo-btn'),
                tooltip: 'Rétablir',
                icon: const Icon(Icons.redo_rounded, size: 18),
                onPressed: widget.controller.canRedoEnterpriseRateCard
                    ? widget.controller.redoEnterpriseRateCard
                    : null,
              ),
              OutlinedButton.icon(
                key: const ValueKey('enterprise-import-export-btn'),
                onPressed: () => _openImportExportDialog(context, card),
                icon: const Icon(Icons.import_export_rounded, size: 16),
                label: const Text('Importer / Exporter'),
              ),
              TextButton.icon(
                key: const ValueKey('enterprise-reset-btn'),
                onPressed: card.isDefault
                    ? null
                    : widget.controller.resetEnterpriseRateCardToDefaults,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Réinitialiser'),
              ),
              if (activeProjectName != null)
                FilledButton.icon(
                  key: const ValueKey('enterprise-apply-to-project-btn'),
                  onPressed: () => _applyToActiveProject(context),
                  icon: const Icon(Icons.sync_alt_rounded, size: 16),
                  label: Text(
                    'Appliquer au projet « $activeProjectName »',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfilesTab(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    EnterpriseRateCard card,
  ) {
    final avgInternal = _averageOf(
      card.profiles,
      (p) => p.internalDailyRate,
    );
    final avgExternal = _averageOf(
      card.profiles,
      (p) => p.externalDailyRate,
    );
    final avgEffective = card.averageDailyRate();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _EnterpriseSectionCard(
          title: 'Paramètres généraux de valorisation',
          subtitle:
              'Devise de référence, durée d’une journée/homme et mode contractuel appliqué par défaut aux nouveaux chiffrages.',
          child: Wrap(
            spacing: 16,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Devise par défaut',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<CostCurrency>(
                      key: const ValueKey('enterprise-currency-dropdown'),
                      value: card.currency,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        for (final currency in CostCurrency.values)
                          DropdownMenuItem(
                            value: currency,
                            child: Text(currency.label),
                          ),
                      ],
                      onChanged: (next) {
                        if (next != null) {
                          _updateCard(card.copyWith(currency: next));
                        }
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 260,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Mode de delivery par défaut',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<CostDeliveryMode>(
                      key: const ValueKey('enterprise-delivery-mode-dropdown'),
                      value: card.defaultDeliveryMode,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        for (final mode in CostDeliveryMode.values)
                          DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ),
                      ],
                      onChanged: (next) {
                        if (next != null) {
                          _updateCard(card.copyWith(defaultDeliveryMode: next));
                        }
                      },
                    ),
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    child: _SyncedNumberField(
                      fieldKey: const ValueKey(
                        'enterprise-hours-per-day-field',
                      ),
                      label: 'Heures / jour',
                      suffixText: 'h/j',
                      value: card.hoursPerDay,
                      min: 0.5,
                      max: 24.0,
                      onChanged: (val) =>
                          _updateCard(card.copyWith(hoursPerDay: val)),
                    ),
                  ),
                  for (final preset in _presetHoursPerDay)
                    ChoiceChip(
                      key: ValueKey(
                        'enterprise-hours-chip-${preset.toStringAsFixed(1)}',
                      ),
                      label: Text('${_formatEditableNumber(preset)} h/j'),
                      selected: (card.hoursPerDay - preset).abs() < 0.001,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) =>
                          _updateCard(card.copyWith(hoursPerDay: preset)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _EnterpriseSectionCard(
          title: 'Catalogue des profils & TJM (${card.profiles.length})',
          subtitle:
              'Moyennes arithmétiques : Interne ${_formatAmount(avgInternal)} ${card.currency.symbol}/j · '
              'Externe ESN ${_formatAmount(avgExternal)} ${card.currency.symbol}/j · '
              'Effectif (${card.defaultDeliveryMode.label}) ${_formatAmount(avgEffective)} ${card.currency.symbol}/j',
          trailing: FilledButton.tonalIcon(
            key: const ValueKey('enterprise-add-profile-btn'),
            onPressed: () => _openEditProfileDialog(context, card),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
            label: const Text('Ajouter un profil'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < card.profiles.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _ProfileRateRow(
                  profile: card.profiles[i],
                  currency: card.currency,
                  deliveryMode: card.defaultDeliveryMode,
                  hoursPerDay: card.hoursPerDay,
                  canDelete: card.profiles.length > 1,
                  onEdit: () => _openEditProfileDialog(
                    context,
                    card,
                    existing: card.profiles[i],
                  ),
                  onDelete: () => _deleteProfile(card, card.profiles[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTShirtTab(
    ThemeData theme,
    ColorScheme colors,
    EnterpriseRateCard card,
  ) {
    final avgDailyRate = card.averageDailyRate();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _EnterpriseSectionCard(
          title: 'Calibrage PERT 3 points par taille T-shirt (XS à XL)',
          subtitle:
              'Formule PERT : Charge espérée = (O + 4 × M + P) / 6 jours/homme, avec la contrainte 0 ≤ Optimiste (O) ≤ Nominal (M) ≤ Pessimiste (P).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _standardSizes.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _TShirtPresetRow(
                  preset: card.presetFor(_standardSizes[i]),
                  hoursPerDay: card.hoursPerDay,
                  averageDailyRate: avgDailyRate,
                  currency: card.currency,
                  onChanged: (updated) => _updatePreset(card, updated),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRatiosAndAiTab(
    ThemeData theme,
    ColorScheme colors,
    EnterpriseRateCard card,
  ) {
    final ratios = card.transverseRatios;
    final ai = card.aiProductivity;
    final totalTransversePct =
        ratios.projectManagementPct +
        ratios.architectureDevOpsPct +
        ratios.transverseQaPct;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _EnterpriseSectionCard(
          title: 'Ratios forfaitaires d’activités transverses & Aléas',
          subtitle:
              'Surcharge transverse hors contingence : +${_formatEditableNumber(totalTransversePct)} % · '
              'Provision aléas : +${_formatEditableNumber(ratios.contingencyPct)} % (plage autorisée 0 à 200 %).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PercentageSliderRow(
                sliderKey: const ValueKey('enterprise-ratio-pm-slider'),
                fieldKey: const ValueKey('enterprise-ratio-pm-field'),
                label: 'Pilotage, Cérémonies Agile & Cadrage Produit',
                subtitle: 'Gestion de projet, backlog, ateliers métier et PO',
                icon: Icons.flag_outlined,
                value: ratios.projectManagementPct,
                maxAllowed: 200.0,
                defaultSliderMax: 100.0,
                onChanged: (val, {required recordUndo}) => _updateCard(
                  card.copyWith(
                    transverseRatios: ratios.copyWith(
                      projectManagementPct: val,
                    ),
                  ),
                  recordUndo: recordUndo,
                ),
              ),
              const Divider(height: 20),
              _PercentageSliderRow(
                sliderKey: const ValueKey('enterprise-ratio-arch-slider'),
                fieldKey: const ValueKey('enterprise-ratio-arch-field'),
                label: 'Architecture transverse & Socle DevSecOps',
                subtitle: 'CI/CD, observabilité, sécurité et revues d’archi',
                icon: Icons.lan_outlined,
                value: ratios.architectureDevOpsPct,
                maxAllowed: 200.0,
                defaultSliderMax: 100.0,
                onChanged: (val, {required recordUndo}) => _updateCard(
                  card.copyWith(
                    transverseRatios: ratios.copyWith(
                      architectureDevOpsPct: val,
                    ),
                  ),
                  recordUndo: recordUndo,
                ),
              ),
              const Divider(height: 20),
              _PercentageSliderRow(
                sliderKey: const ValueKey('enterprise-ratio-qa-slider'),
                fieldKey: const ValueKey('enterprise-ratio-qa-field'),
                label: 'Recette transverse & Homologation E2E',
                subtitle: 'Tests d’intégration bout-en-bout, UAT et TNR',
                icon: Icons.fact_check_outlined,
                value: ratios.transverseQaPct,
                maxAllowed: 200.0,
                defaultSliderMax: 100.0,
                onChanged: (val, {required recordUndo}) => _updateCard(
                  card.copyWith(
                    transverseRatios: ratios.copyWith(transverseQaPct: val),
                  ),
                  recordUndo: recordUndo,
                ),
              ),
              const Divider(height: 20),
              _PercentageSliderRow(
                sliderKey: const ValueKey(
                  'enterprise-ratio-contingency-slider',
                ),
                fieldKey: const ValueKey('enterprise-ratio-contingency-field'),
                label: 'Provision pour aléas & Contingence d’intégration',
                subtitle: 'Marge d’incertitude technique et fonctionnelle',
                icon: Icons.shield_outlined,
                value: ratios.contingencyPct,
                maxAllowed: 200.0,
                defaultSliderMax: 100.0,
                onChanged: (val, {required recordUndo}) => _updateCard(
                  card.copyWith(
                    transverseRatios: ratios.copyWith(contingencyPct: val),
                  ),
                  recordUndo: recordUndo,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _EnterpriseSectionCard(
          title: 'Gains de productivité par ingénierie assistée par IA',
          subtitle:
              'Décote d’effort appliquée par discipline sur les lots WBS éligibles à l’accélération IA (0 à 80 %).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile.adaptive(
                key: const ValueKey('enterprise-ai-enabled-switch'),
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  Icons.auto_awesome_rounded,
                  color: ai.enabled ? colors.primary : colors.onSurfaceVariant,
                ),
                title: const Text(
                  'Activer l’accélération IA par défaut',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  ai.enabled
                      ? 'Les gains par pôle ci-dessous réduisent la charge nette des lots éligibles.'
                      : 'Désactivé — aucune décote IA appliquée (charge nette = charge brute).',
                ),
                value: ai.enabled,
                onChanged: (enabled) => _updateCard(
                  card.copyWith(aiProductivity: ai.copyWith(enabled: enabled)),
                ),
              ),
              const Divider(height: 20),
              _PercentageSliderRow(
                sliderKey: const ValueKey('enterprise-ai-backend-slider'),
                fieldKey: const ValueKey('enterprise-ai-backend-field'),
                label: 'Backend & Métier',
                subtitle: 'Services domaine, règles de gestion et APIs métier',
                icon: Icons.dns_outlined,
                value: ai.backendGainPct,
                maxAllowed: 80.0,
                defaultSliderMax: 80.0,
                enabled: ai.enabled,
                onChanged: (val, {required recordUndo}) => _updateCard(
                  card.copyWith(
                    aiProductivity: ai.copyWith(backendGainPct: val),
                  ),
                  recordUndo: recordUndo,
                ),
              ),
              const Divider(height: 16),
              _PercentageSliderRow(
                sliderKey: const ValueKey('enterprise-ai-frontend-slider'),
                fieldKey: const ValueKey('enterprise-ai-frontend-field'),
                label: 'Frontend & UX/UI',
                subtitle: 'Écrans, parcours, formulaires et composants visuels',
                icon: Icons.web_outlined,
                value: ai.frontendUxGainPct,
                maxAllowed: 80.0,
                defaultSliderMax: 80.0,
                enabled: ai.enabled,
                onChanged: (val, {required recordUndo}) => _updateCard(
                  card.copyWith(
                    aiProductivity: ai.copyWith(frontendUxGainPct: val),
                  ),
                  recordUndo: recordUndo,
                ),
              ),
              const Divider(height: 16),
              _PercentageSliderRow(
                sliderKey: const ValueKey('enterprise-ai-data-slider'),
                fieldKey: const ValueKey('enterprise-ai-data-field'),
                label: 'Data & Intégrations',
                subtitle:
                    'Modèles relationnels/JSON, migrations et connecteurs',
                icon: Icons.storage_outlined,
                value: ai.dataIntegrationGainPct,
                maxAllowed: 80.0,
                defaultSliderMax: 80.0,
                enabled: ai.enabled,
                onChanged: (val, {required recordUndo}) => _updateCard(
                  card.copyWith(
                    aiProductivity: ai.copyWith(dataIntegrationGainPct: val),
                  ),
                  recordUndo: recordUndo,
                ),
              ),
              const Divider(height: 16),
              _PercentageSliderRow(
                sliderKey: const ValueKey('enterprise-ai-qa-slider'),
                fieldKey: const ValueKey('enterprise-ai-qa-field'),
                label: 'QA, BDD & Automatisation des tests',
                subtitle:
                    'Scénarios Gherkin, suites TDD, fixtures et harnais E2E',
                icon: Icons.science_outlined,
                value: ai.qaTestingGainPct,
                maxAllowed: 80.0,
                defaultSliderMax: 80.0,
                enabled: ai.enabled,
                onChanged: (val, {required recordUndo}) => _updateCard(
                  card.copyWith(
                    aiProductivity: ai.copyWith(qaTestingGainPct: val),
                  ),
                  recordUndo: recordUndo,
                ),
              ),
              const Divider(height: 16),
              _PercentageSliderRow(
                sliderKey: const ValueKey('enterprise-ai-devops-slider'),
                fieldKey: const ValueKey('enterprise-ai-devops-field'),
                label: 'Architecture & DevSecOps',
                subtitle: 'IaC Terraform/Docker, pipelines CI/CD et durcissement',
                icon: Icons.cloud_sync_outlined,
                value: ai.devSecOpsGainPct,
                maxAllowed: 80.0,
                defaultSliderMax: 80.0,
                enabled: ai.enabled,
                onChanged: (val, {required recordUndo}) => _updateCard(
                  card.copyWith(
                    aiProductivity: ai.copyWith(devSecOpsGainPct: val),
                  ),
                  recordUndo: recordUndo,
                ),
              ),
              const Divider(height: 16),
              _PercentageSliderRow(
                sliderKey: const ValueKey('enterprise-ai-pm-slider'),
                fieldKey: const ValueKey('enterprise-ai-pm-field'),
                label: 'Pilotage & Spécifications',
                subtitle:
                    'Rédaction documentaire, synthèse métier et suivi produit',
                icon: Icons.description_outlined,
                value: ai.pmSpecsGainPct,
                maxAllowed: 80.0,
                defaultSliderMax: 80.0,
                enabled: ai.enabled,
                onChanged: (val, {required recordUndo}) => _updateCard(
                  card.copyWith(
                    aiProductivity: ai.copyWith(pmSpecsGainPct: val),
                  ),
                  recordUndo: recordUndo,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _EnterpriseSectionCard(
          title: 'Notes & Conventions financières d’entreprise',
          subtitle:
              'Règles internes d’imputation CAPEX/OPEX, barèmes de sous-traitance ou hypothèses transmises aux agents FinOps IA.',
          child: _SyncedTextField(
            fieldKey: const ValueKey('enterprise-notes-field'),
            value: card.notes,
            maxLines: 4,
            labelText: 'Conventions & directives FinOps d’entreprise',
            hintText:
                'Ex. TJM hors taxes, indexation annuelle 2,5 %, hébergement souverain SecNumCloud privilégié…',
            onChanged: (notes) => _updateCard(card.copyWith(notes: notes)),
          ),
        ),
      ],
    );
  }
}

class _EnterpriseSectionCard extends StatelessWidget {
  const _EnterpriseSectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProfileRateRow extends StatelessWidget {
  const _ProfileRateRow({
    required this.profile,
    required this.currency,
    required this.deliveryMode,
    required this.hoursPerDay,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final CostProfileRate profile;
  final CostCurrency currency;
  final CostDeliveryMode deliveryMode;
  final double hoursPerDay;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveDaily = profile.effectiveDailyRate(deliveryMode);
    final hourly = hoursPerDay > 0 ? effectiveDaily / hoursPerDay : 0.0;

    return InkWell(
      key: ValueKey('enterprise-profile-row-${profile.id}'),
      onTap: onEdit,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    profile.code,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _SmallBadge(
                            label: profile.seniority,
                            backgroundColor: colors.secondaryContainer,
                            foregroundColor: colors.onSecondaryContainer,
                          ),
                          _SmallBadge(
                            label: profile.discipline.label,
                            backgroundColor: colors.surfaceContainerHighest,
                            foregroundColor: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _RateMetricColumn(
                  label: 'Interne',
                  value:
                      '${_formatAmount(profile.internalDailyRate)} ${currency.symbol}/j',
                ),
                _RateMetricColumn(
                  label: 'Externe ESN',
                  value:
                      '${_formatAmount(profile.externalDailyRate)} ${currency.symbol}/j',
                ),
                _RateMetricColumn(
                  label: 'Retenu (${deliveryMode.label})',
                  value:
                      '${_formatAmount(effectiveDaily)} ${currency.symbol}/j',
                  subValue: '${_formatAmount(hourly)} ${currency.symbol}/h',
                  highlighted: true,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: ValueKey('enterprise-edit-profile-${profile.id}'),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Modifier le profil',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: onEdit,
                    ),
                    IconButton(
                      key: ValueKey('enterprise-delete-profile-${profile.id}'),
                      visualDensity: VisualDensity.compact,
                      tooltip: canDelete
                          ? 'Supprimer le profil'
                          : 'Au moins un profil doit être conservé',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: canDelete ? colors.error : null,
                      ),
                      onPressed: canDelete ? onDelete : null,
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
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RateMetricColumn extends StatelessWidget {
  const _RateMetricColumn({
    required this.label,
    required this.value,
    this.subValue,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final String? subValue;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
            color: highlighted ? colors.primary : colors.onSurface,
          ),
        ),
        if (subValue != null)
          Text(
            subValue!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _TShirtPresetRow extends StatelessWidget {
  const _TShirtPresetRow({
    required this.preset,
    required this.hoursPerDay,
    required this.averageDailyRate,
    required this.currency,
    required this.onChanged,
  });

  final TShirtEffortPreset preset;
  final double hoursPerDay;
  final double averageDailyRate;
  final CostCurrency currency;
  final ValueChanged<TShirtEffortPreset> onChanged;

  void _applyOptimistic(double rawO) {
    final nextO = rawO < 0.0 ? 0.0 : rawO;
    final nextM = preset.mostLikelyDays < nextO ? nextO : preset.mostLikelyDays;
    final nextP = preset.pessimisticDays < nextM
        ? nextM
        : preset.pessimisticDays;
    onChanged(
      preset.copyWith(
        optimisticDays: nextO,
        mostLikelyDays: nextM,
        pessimisticDays: nextP,
      ),
    );
  }

  void _applyMostLikely(double rawM, {required bool normalizeLower}) {
    final cleanM = rawM < 0.0 ? 0.0 : rawM;
    if (!normalizeLower && cleanM < preset.optimisticDays) {
      return;
    }
    final nextO = preset.optimisticDays > cleanM
        ? cleanM
        : preset.optimisticDays;
    final nextP = preset.pessimisticDays < cleanM
        ? cleanM
        : preset.pessimisticDays;
    onChanged(
      preset.copyWith(
        optimisticDays: nextO,
        mostLikelyDays: cleanM,
        pessimisticDays: nextP,
      ),
    );
  }

  void _applyPessimistic(double rawP, {required bool normalizeLower}) {
    final cleanP = rawP < 0.0 ? 0.0 : rawP;
    if (!normalizeLower && cleanP < preset.mostLikelyDays) {
      return;
    }
    final nextM = preset.mostLikelyDays > cleanP
        ? cleanP
        : preset.mostLikelyDays;
    final nextO = preset.optimisticDays > nextM ? nextM : preset.optimisticDays;
    onChanged(
      preset.copyWith(
        optimisticDays: nextO,
        mostLikelyDays: nextM,
        pessimisticDays: cleanP,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sizeKey = preset.size.name;
    final pertDays = preset.expectedDays;
    final pertHours = pertDays * hoursPerDay;
    final estCost = pertDays * averageDailyRate;

    return Container(
      key: ValueKey('enterprise-tshirt-card-$sizeKey'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 190,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.primaryContainer,
                  child: Text(
                    preset.size.code,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    preset.size.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 130,
                child: _SyncedNumberField(
                  fieldKey: ValueKey('enterprise-tshirt-$sizeKey-o'),
                  label: 'Optimiste (O)',
                  suffixText: 'j/h',
                  value: preset.optimisticDays,
                  min: 0.0,
                  max: 1000.0,
                  onChanged: _applyOptimistic,
                ),
              ),
              SizedBox(
                width: 130,
                child: _SyncedNumberField(
                  fieldKey: ValueKey('enterprise-tshirt-$sizeKey-m'),
                  label: 'Nominal (M)',
                  suffixText: 'j/h',
                  value: preset.mostLikelyDays,
                  min: 0.0,
                  max: 1000.0,
                  onChanged: (v) => _applyMostLikely(v, normalizeLower: false),
                  onCommit: (v) => _applyMostLikely(v, normalizeLower: true),
                ),
              ),
              SizedBox(
                width: 130,
                child: _SyncedNumberField(
                  fieldKey: ValueKey('enterprise-tshirt-$sizeKey-p'),
                  label: 'Pessimiste (P)',
                  suffixText: 'j/h',
                  value: preset.pessimisticDays,
                  min: 0.0,
                  max: 1000.0,
                  onChanged: (v) => _applyPessimistic(v, normalizeLower: false),
                  onCommit: (v) => _applyPessimistic(v, normalizeLower: true),
                ),
              ),
            ],
          ),
          Container(
            key: ValueKey('enterprise-tshirt-$sizeKey-pert'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PERT : ${_formatPertDays(pertDays)} j/h',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSecondaryContainer,
                  ),
                ),
                Text(
                  '${_formatEditableNumber(pertHours)} h · ≈ ${_formatAmount(estCost)} ${currency.symbol}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSecondaryContainer.withValues(alpha: 0.85),
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

class _PercentageSliderRow extends StatefulWidget {
  const _PercentageSliderRow({
    required this.sliderKey,
    required this.fieldKey,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.maxAllowed,
    required this.defaultSliderMax,
    required this.onChanged,
    this.enabled = true,
  });

  final Key sliderKey;
  final Key fieldKey;
  final String label;
  final String subtitle;
  final IconData icon;
  final double value;
  final double maxAllowed;
  final double defaultSliderMax;
  final void Function(double value, {required bool recordUndo}) onChanged;
  final bool enabled;

  @override
  State<_PercentageSliderRow> createState() => _PercentageSliderRowState();
}

class _PercentageSliderRowState extends State<_PercentageSliderRow> {
  bool _recordedUndoInDrag = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sliderMax = widget.value > widget.defaultSliderMax
        ? widget.maxAllowed
        : widget.defaultSliderMax;
    final clampedSliderVal = widget.value.clamp(0.0, sliderMax);

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.55,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final header = Row(
            children: [
              Icon(widget.icon, size: 19, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final controls = Row(
            children: [
              Expanded(
                child: Slider(
                  key: widget.sliderKey,
                  value: clampedSliderVal,
                  min: 0.0,
                  max: sliderMax,
                  divisions: sliderMax.round(),
                  label: '${_formatEditableNumber(clampedSliderVal)} %',
                  onChangeStart: widget.enabled
                      ? (_) => _recordedUndoInDrag = false
                      : null,
                  onChanged: widget.enabled
                      ? (val) {
                          final rounded = (val * 2.0).round() / 2.0;
                          final shouldRecord = !_recordedUndoInDrag;
                          _recordedUndoInDrag = true;
                          widget.onChanged(rounded, recordUndo: shouldRecord);
                        }
                      : null,
                  onChangeEnd: widget.enabled
                      ? (_) => _recordedUndoInDrag = false
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: _SyncedNumberField(
                  fieldKey: widget.fieldKey,
                  label: 'Taux',
                  suffixText: '%',
                  value: widget.value,
                  min: 0.0,
                  max: widget.maxAllowed,
                  enabled: widget.enabled,
                  onChanged: (val) => widget.onChanged(val, recordUndo: true),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, const SizedBox(height: 8), controls],
            );
          }

          return Row(
            children: [
              Expanded(flex: 5, child: header),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: controls),
            ],
          );
        },
      ),
    );
  }
}

class _SyncedNumberField extends StatefulWidget {
  const _SyncedNumberField({
    required this.fieldKey,
    required this.label,
    required this.suffixText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onCommit,
    this.enabled = true,
  });

  final Key fieldKey;
  final String label;
  final String suffixText;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onCommit;
  final bool enabled;

  @override
  State<_SyncedNumberField> createState() => _SyncedNumberFieldState();
}

class _SyncedNumberFieldState extends State<_SyncedNumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  double? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _lastEmitted = widget.value;
    _controller = TextEditingController(
      text: _formatEditableNumber(widget.value),
    );
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _SyncedNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _lastEmitted) {
      _lastEmitted = widget.value;
      final formatted = _formatEditableNumber(widget.value);
      if (_controller.text != formatted) {
        _controller.text = formatted;
      }
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitCurrentText();
    }
  }

  double? _parse(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null || !parsed.isFinite) return null;
    return parsed.clamp(widget.min, widget.max);
  }

  void _commitCurrentText() {
    final parsed = _parse(_controller.text);
    if (parsed == null) {
      _controller.text = _formatEditableNumber(widget.value);
      return;
    }
    _lastEmitted = parsed;
    if (widget.onCommit != null) {
      widget.onCommit!(parsed);
    } else {
      widget.onChanged(parsed);
    }
    final normalized = _formatEditableNumber(parsed);
    if (_controller.text != normalized) {
      _controller.text = normalized;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffixText,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (raw) {
        final parsed = _parse(raw);
        if (parsed != null) {
          _lastEmitted = parsed;
          widget.onChanged(parsed);
        }
      },
      onSubmitted: (_) => _commitCurrentText(),
    );
  }
}

class _SyncedTextField extends StatefulWidget {
  const _SyncedTextField({
    required this.fieldKey,
    required this.value,
    required this.labelText,
    required this.hintText,
    required this.onChanged,
    this.maxLines = 3,
  });

  final Key fieldKey;
  final String value;
  final String labelText;
  final String hintText;
  final ValueChanged<String> onChanged;
  final int maxLines;

  @override
  State<_SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<_SyncedTextField> {
  late final TextEditingController _controller;
  String _lastEmitted = '';

  @override
  void initState() {
    super.initState();
    _lastEmitted = widget.value;
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _lastEmitted) {
      _lastEmitted = widget.value;
      if (_controller.text != widget.value) {
        _controller.text = widget.value;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (text) {
        _lastEmitted = text;
        widget.onChanged(text);
      },
    );
  }
}

class _EditCostProfileDialog extends StatefulWidget {
  const _EditCostProfileDialog({
    required this.currency,
    required this.deliveryMode,
    required this.existingIds,
    this.existing,
  });

  final CostProfileRate? existing;
  final CostCurrency currency;
  final CostDeliveryMode deliveryMode;
  final Set<String> existingIds;

  @override
  State<_EditCostProfileDialog> createState() => _EditCostProfileDialogState();
}

class _EditCostProfileDialogState extends State<_EditCostProfileDialog> {
  static const List<String> _seniorityPresets = <String>[
    'Junior',
    'Confirmé',
    'Senior',
    'Lead',
    'Principal',
  ];

  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _seniorityCtrl;
  late final TextEditingController _internalRateCtrl;
  late final TextEditingController _externalRateCtrl;
  late CostDiscipline _discipline;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _codeCtrl = TextEditingController(text: ex?.code ?? 'PRF-CUSTOM');
    _nameCtrl = TextEditingController(text: ex?.name ?? '');
    _seniorityCtrl = TextEditingController(text: ex?.seniority ?? 'Confirmé');
    _internalRateCtrl = TextEditingController(
      text: _formatEditableNumber(ex?.internalDailyRate ?? 520.0),
    );
    _externalRateCtrl = TextEditingController(
      text: _formatEditableNumber(ex?.externalDailyRate ?? 750.0),
    );
    _discipline = ex?.discipline ?? CostDiscipline.backend;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _seniorityCtrl.dispose();
    _internalRateCtrl.dispose();
    _externalRateCtrl.dispose();
    super.dispose();
  }

  double? _parseNonNegative(String raw) {
    final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite || parsed < 0.0) return null;
    return parsed;
  }

  String _generateUniqueId() {
    var candidate = 'prof_${shortid.generate()}';
    var counter = 2;
    while (widget.existingIds.contains(candidate)) {
      candidate = 'prof_${shortid.generate()}_$counter';
      counter++;
    }
    return candidate;
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'L’intitulé du profil est obligatoire.');
      return;
    }
    final internalRate = _parseNonNegative(_internalRateCtrl.text);
    final externalRate = _parseNonNegative(_externalRateCtrl.text);
    if (internalRate == null || externalRate == null) {
      setState(
        () => _errorText =
            'Les TJM interne et externe doivent être des nombres positifs ou nuls.',
      );
      return;
    }
    final rawCode = _codeCtrl.text.trim();
    final rawSeniority = _seniorityCtrl.text.trim();
    final profile = CostProfileRate(
      id: widget.existing?.id ?? _generateUniqueId(),
      code: rawCode.isEmpty ? 'PRF' : rawCode.toUpperCase(),
      name: name,
      seniority: rawSeniority.isEmpty ? 'Confirmé' : rawSeniority,
      discipline: _discipline,
      internalDailyRate: internalRate,
      externalDailyRate: externalRate,
    );
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final sym = widget.currency.symbol;

    return AlertDialog(
      title: Text(isEditing ? 'Modifier le profil TJM' : 'Ajouter un profil TJM'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('enterprise-profile-code-field'),
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Code profil (ex. PRF-BACK)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const ValueKey('enterprise-profile-name-field'),
                      controller: _nameCtrl,
                      autofocus: !isEditing,
                      decoration: const InputDecoration(
                        labelText: 'Intitulé du profil *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Discipline principale',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CostDiscipline>(
                    key: const ValueKey(
                      'enterprise-profile-discipline-dropdown',
                    ),
                    value: _discipline,
                    isExpanded: true,
                    isDense: true,
                    items: [
                      for (final d in CostDiscipline.values)
                        DropdownMenuItem(value: d, child: Text(d.label)),
                    ],
                    onChanged: (next) {
                      if (next != null) setState(() => _discipline = next);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('enterprise-profile-seniority-field'),
                controller: _seniorityCtrl,
                decoration: const InputDecoration(
                  labelText: 'Séniorité',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final preset in _seniorityPresets)
                    ActionChip(
                      label: Text(preset),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _seniorityCtrl.text = preset),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey(
                        'enterprise-profile-internal-rate-field',
                      ),
                      controller: _internalRateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'TJM interne ($sym/j) *',
                        suffixText: '$sym/j',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey(
                        'enterprise-profile-external-rate-field',
                      ),
                      controller: _externalRateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'TJM externe ESN ($sym/j) *',
                        suffixText: '$sym/j',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('enterprise-profile-save-btn'),
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _EnterpriseRateCardImportExportDialog extends StatefulWidget {
  const _EnterpriseRateCardImportExportDialog({
    required this.controller,
    required this.rateCard,
    this.pickAttachments,
  });

  final SpecForgeController controller;
  final EnterpriseRateCard rateCard;
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  @override
  State<_EnterpriseRateCardImportExportDialog> createState() =>
      _EnterpriseRateCardImportExportDialogState();
}

class _EnterpriseRateCardImportExportDialogState
    extends State<_EnterpriseRateCardImportExportDialog> {
  late final TextEditingController _pathCtrl;
  final _importCtrl = TextEditingController();
  EnterpriseRateCard? _parsed;
  String? _importError;
  String? _statusMsg;

  @override
  void initState() {
    super.initState();
    final sep = Platform.pathSeparator;
    final root = widget.controller.enterpriseRateCardStore.rootDirectory.path;
    _pathCtrl = TextEditingController(
      text: '$root${sep}exports${sep}enterprise_rate_card.json',
    );
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _importCtrl.dispose();
    super.dispose();
  }

  void _validateImport() {
    final raw = _importCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _parsed = null;
        _importError = null;
      });
      return;
    }
    try {
      final decoded = EnterpriseRateCardStore.decodeJsonString(raw);
      if (decoded.profiles.isEmpty) {
        setState(() {
          _parsed = null;
          _importError = 'La grille importée doit contenir au moins un profil.';
        });
        return;
      }
      setState(() {
        _parsed = decoded;
        _importError = null;
      });
    } catch (e) {
      setState(() {
        _parsed = null;
        _importError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exportedJson = EnterpriseRateCardStore.encodePrettyJson(
      widget.rateCard,
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AlertDialog(
      title: const Text('Importer / Exporter la grille TJM d’entreprise'),
      content: SizedBox(
        width: 660,
        height: 440,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Exporter (JSON)'),
                  Tab(text: 'Importer (JSON)'),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.outlineVariant),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                exportedJson,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey(
                                  'enterprise-export-path-field',
                                ),
                                controller: _pathCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Chemin de sauvegarde JSON',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              key: const ValueKey('enterprise-export-copy-btn'),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: exportedJson),
                                );
                                if (mounted) {
                                  setState(
                                    () => _statusMsg =
                                        'JSON copié dans le presse-papiers.',
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copier'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              key: const ValueKey('enterprise-export-save-btn'),
                              onPressed: () async {
                                try {
                                  final file = File(_pathCtrl.text.trim());
                                  await file.parent.create(recursive: true);
                                  await file.writeAsString(exportedJson);
                                  if (mounted) {
                                    setState(
                                      () => _statusMsg =
                                          'Enregistré : ${file.path}',
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(
                                      () => _statusMsg = 'Erreur : $e',
                                    );
                                  }
                                }
                              },
                              icon: const Icon(
                                Icons.save_alt_rounded,
                                size: 16,
                              ),
                              label: const Text('Enregistrer'),
                            ),
                          ],
                        ),
                        if (_statusMsg != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _statusMsg!,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: const ValueKey('enterprise-import-pick-btn'),
                            onPressed: () async {
                              final picker =
                                  widget.pickAttachments ??
                                  VibeChatAttachment.pickFiles;
                              final picked = await picker();
                              if (!mounted || picked.isEmpty) return;
                              final txt = picked.first.textContent;
                              if (txt != null) {
                                _importCtrl.text = txt;
                                _validateImport();
                              }
                            },
                            icon: const Icon(
                              Icons.upload_file_rounded,
                              size: 16,
                            ),
                            label: const Text('Charger un fichier JSON…'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('enterprise-import-text'),
                            controller: _importCtrl,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              hintText:
                                  'Collez ici le JSON de la grille tarifaire…',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => _validateImport(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_importError != null)
                          Text(
                            _importError!,
                            style: TextStyle(
                              color: colors.error,
                              fontSize: 12,
                            ),
                          )
                        else if (_parsed != null)
                          Text(
                            'JSON valide : ${_parsed!.profiles.length} profil(s), '
                            'TJM moyen ${_formatAmount(_parsed!.averageDailyRate())} ${_parsed!.currency.symbol}/j.',
                            style: theme.textTheme.bodySmall,
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            key: const ValueKey('enterprise-apply-import-btn'),
                            onPressed: _parsed == null
                                ? null
                                : () async {
                                    await widget.controller
                                        .updateEnterpriseRateCard(_parsed!);
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Appliquer'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

double _averageOf(
  List<CostProfileRate> profiles,
  double Function(CostProfileRate profile) selector,
) {
  if (profiles.isEmpty) return 0.0;
  final sum = profiles.fold<double>(0.0, (acc, p) => acc + selector(p));
  return sum / profiles.length;
}

String _formatAmount(double amount) {
  if (!amount.isFinite) return '0';
  final rounded = (amount * 100.0).round() / 100.0;
  if ((rounded - rounded.roundToDouble()).abs() < 0.005) {
    return rounded.round().toString();
  }
  return rounded.toStringAsFixed(2);
}

String _formatPertDays(double days) {
  if (!days.isFinite) return '0';
  final rounded = (days * 100.0).round() / 100.0;
  if ((rounded - rounded.roundToDouble()).abs() < 0.005) {
    return rounded.round().toString();
  }
  if (((rounded * 10.0) - (rounded * 10.0).roundToDouble()).abs() < 0.005) {
    return rounded.toStringAsFixed(1);
  }
  return rounded.toStringAsFixed(2);
}

String _formatEditableNumber(double value) {
  if (!value.isFinite) return '0';
  final rounded = (value * 100.0).round() / 100.0;
  if ((rounded - rounded.roundToDouble()).abs() < 0.001) {
    return rounded.round().toString();
  }
  return rounded
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
