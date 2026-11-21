/// Studio avancé de gestion du Dictionnaire technique & Préférences globales de modélisation ([ModelDictionaryView]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/business_object_model_preferences.dart';
import '../../models/technical_modeling_rule.dart';
import '../../services/exporters/model_dictionary_codec.dart';
import '../../services/spec_forge_controller.dart';

enum _DictionarySection {
  naming(
    id: 'naming',
    label: 'Langues & Nommage',
    subtitle: 'Langues, casse des attributs et valeurs d’énumération',
    icon: Icons.translate_rounded,
  ),
  identifiers(
    id: 'identifiers',
    label: 'Id · Ref · Code · Number',
    subtitle: 'Matrice d’arbitrage des identifiants et clés étrangères',
    icon: Icons.fingerprint_rounded,
  ),
  types(
    id: 'types',
    label: 'Dates, Booléens & Unités',
    subtitle: '*At vs *Date, is*/has*/can*, suffixes d’unités',
    icon: Icons.schedule_rounded,
  ),
  lifecycle(
    id: 'lifecycle',
    label: 'Audit, Soft-delete & Version',
    subtitle: 'Horodatages, suppression logique et concurrence optimiste',
    icon: Icons.history_toggle_off_rounded,
  ),
  schema(
    id: 'schema',
    label: 'Contraintes JSON Schema',
    subtitle: 'Rigueur, nullabilité, relations et longueurs max par défaut',
    icon: Icons.schema_outlined,
  ),
  rules(
    id: 'rules',
    label: 'Dictionnaire des règles',
    subtitle: 'Catalogue complet et règles techniques personnalisées',
    icon: Icons.menu_book_rounded,
  ),
  locale(
    id: 'locale',
    label: 'Régional & Consignes IA',
    subtitle: 'Profil géographique, monétaire et directives libres',
    icon: Icons.public_rounded,
  );

  const _DictionarySection({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
}

/// Vue avancée de l'onglet Design permettant de configurer le dictionnaire
/// technique de modélisation et les préférences globales héritées par tous les projets.
class ModelDictionaryView extends StatefulWidget {
  /// Crée la vue connectée au [controller].
  const ModelDictionaryView({
    required this.controller,
    required this.onBack,
    this.pickAttachments,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Callback de retour vers la grille des cartes Design.
  final VoidCallback onBack;

  /// Sélecteur optionnel de fichiers pour l'import JSON.
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  @override
  State<ModelDictionaryView> createState() => _ModelDictionaryViewState();
}

class _ModelDictionaryViewState extends State<ModelDictionaryView> {
  static const Set<String> _presetLangCodes = {
    'fr',
    'en',
    'es',
    'de',
    'it',
    'pt',
  };

  _DictionarySection _section = _DictionarySection.identifiers;
  bool _showLivePreview = true;
  String _ruleSearch = '';
  TechnicalRuleCategory? _ruleCategoryFilter;

  late final TextEditingController _attrCustomCtrl;
  late final TextEditingController _enumCustomCtrl;
  late final TextEditingController _contentCustomCtrl;
  late final TextEditingController _customLocaleCtrl;
  late final TextEditingController _customInstructionsCtrl;
  late final TextEditingController _codeMaxCtrl;
  late final TextEditingController _labelMaxCtrl;
  late final TextEditingController _descMaxCtrl;

  @override
  void initState() {
    super.initState();
    final prefs = widget.controller.modelPreferences;
    _attrCustomCtrl = TextEditingController(
      text: _presetLangCodes.contains(prefs.attributeLanguage)
          ? ''
          : prefs.attributeLanguage,
    );
    _enumCustomCtrl = TextEditingController(
      text: _presetLangCodes.contains(prefs.enumLanguage)
          ? ''
          : prefs.enumLanguage,
    );
    _contentCustomCtrl = TextEditingController(
      text: _presetLangCodes.contains(prefs.contentLanguage)
          ? ''
          : prefs.contentLanguage,
    );
    _customLocaleCtrl = TextEditingController(text: prefs.customLocaleLabel);
    _customInstructionsCtrl = TextEditingController(
      text: prefs.customInstructions,
    );
    _codeMaxCtrl = TextEditingController(text: '${prefs.defaultCodeMaxLength}');
    _labelMaxCtrl = TextEditingController(
      text: '${prefs.defaultLabelMaxLength}',
    );
    _descMaxCtrl = TextEditingController(
      text: '${prefs.defaultDescriptionMaxLength}',
    );
  }

  @override
  void dispose() {
    _attrCustomCtrl.dispose();
    _enumCustomCtrl.dispose();
    _contentCustomCtrl.dispose();
    _customLocaleCtrl.dispose();
    _customInstructionsCtrl.dispose();
    _codeMaxCtrl.dispose();
    _labelMaxCtrl.dispose();
    _descMaxCtrl.dispose();
    super.dispose();
  }

  void _syncControllersFrom(BusinessObjectModelPreferences prefs) {
    final codeTxt = '${prefs.defaultCodeMaxLength}';
    if (_codeMaxCtrl.text != codeTxt) _codeMaxCtrl.text = codeTxt;
    final labelTxt = '${prefs.defaultLabelMaxLength}';
    if (_labelMaxCtrl.text != labelTxt) _labelMaxCtrl.text = labelTxt;
    final descTxt = '${prefs.defaultDescriptionMaxLength}';
    if (_descMaxCtrl.text != descTxt) _descMaxCtrl.text = descTxt;
    if (_customLocaleCtrl.text != prefs.customLocaleLabel) {
      _customLocaleCtrl.text = prefs.customLocaleLabel;
    }
    if (_customInstructionsCtrl.text != prefs.customInstructions) {
      _customInstructionsCtrl.text = prefs.customInstructions;
    }
  }

  Future<void> _updatePrefs(BusinessObjectModelPreferences next) async {
    await widget.controller.updateModelPreferences(next);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.controller.modelPreferences;
    final project = widget.controller.project;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activeRulesCount = prefs.technicalRules.where((r) => r.enabled).length;

    return Column(
      key: const ValueKey('model-dictionary-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(
          context,
          theme,
          colors,
          prefs,
          activeRulesCount,
          hasActiveProjectWithObjects:
              project != null && project.businessObjects.isNotEmpty,
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final canShowPreview =
                  _showLivePreview && constraints.maxWidth >= 980;
              final compactNav = constraints.maxWidth < 760;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionNav(
                    theme,
                    colors,
                    prefs,
                    compact: compactNav,
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                    child: _buildActiveSection(context, theme, colors, prefs),
                  ),
                  if (canShowPreview) ...[
                    const VerticalDivider(width: 1, thickness: 1),
                    SizedBox(
                      width: 370,
                      child: _buildLivePreviewPane(theme, colors, prefs),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs,
    int activeRulesCount, {
    required bool hasActiveProjectWithObjects,
  }) {
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
              OutlinedButton.icon(
                key: const ValueKey('design-subview-back-btn'),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Design'),
              ),
              const SizedBox(width: 14),
              Icon(Icons.rule_folder_outlined, size: 22, color: colors.primary),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dictionnaire technique & Modèle',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${prefs.formatCompactButtonSummary()} · $activeRulesCount règle(s) active(s) · Héritage global tous projets',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Annuler',
                icon: const Icon(Icons.undo_rounded, size: 18),
                onPressed: widget.controller.canUndoModelPreferences
                    ? () async {
                        await widget.controller.undoModelPreferences();
                        _syncControllersFrom(widget.controller.modelPreferences);
                      }
                    : null,
              ),
              IconButton(
                tooltip: 'Rétablir',
                icon: const Icon(Icons.redo_rounded, size: 18),
                onPressed: widget.controller.canRedoModelPreferences
                    ? () async {
                        await widget.controller.redoModelPreferences();
                        _syncControllersFrom(widget.controller.modelPreferences);
                      }
                    : null,
              ),
              if (hasActiveProjectWithObjects)
                OutlinedButton.icon(
                  key: const ValueKey('model-dict-apply-case-project-btn'),
                  onPressed: () => _applyCaseToActiveProject(context),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: const Text('Appliquer la casse au projet'),
                ),
              OutlinedButton.icon(
                key: const ValueKey('model-dict-import-export-btn'),
                onPressed: () => _openImportExportDialog(context, prefs),
                icon: const Icon(Icons.import_export_rounded, size: 16),
                label: const Text('Importer / Exporter'),
              ),
              TextButton.icon(
                key: const ValueKey('model-dict-reset-btn'),
                onPressed: prefs.isDefault
                    ? null
                    : () async {
                        await widget.controller.resetModelPreferencesToDefaults();
                        _syncControllersFrom(
                          BusinessObjectModelPreferences.defaults,
                        );
                      },
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Réinitialiser'),
              ),
              IconButton(
                key: const ValueKey('model-dict-toggle-preview-btn'),
                tooltip: _showLivePreview
                    ? 'Masquer l’aperçu live'
                    : 'Afficher l’aperçu live',
                icon: Icon(
                  _showLivePreview
                      ? Icons.visibility_rounded
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _showLivePreview = !_showLivePreview),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionNav(
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs, {
    required bool compact,
  }) {
    return Container(
      key: const ValueKey('model-dict-section-nav'),
      width: compact ? 76 : 310,
      color: colors.surfaceContainerLow.withValues(alpha: 0.65),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        children: [
          for (final sec in _DictionarySection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: InkWell(
                key: ValueKey('model-dict-section-${sec.id}'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _section = sec),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _section == sec
                        ? colors.primaryContainer.withValues(alpha: 0.72)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sec.icon,
                        size: 20,
                        color: _section == sec
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sec == _DictionarySection.rules
                                    ? '${sec.label} (${prefs.technicalRules.length})'
                                    : sec.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: _section == sec
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: _section == sec
                                      ? colors.onPrimaryContainer
                                      : colors.onSurface,
                                ),
                              ),
                              Text(
                                sec.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: _section == sec
                                      ? colors.onPrimaryContainer.withValues(
                                          alpha: 0.85,
                                        )
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs,
  ) => switch (_section) {
    _DictionarySection.naming => _buildNamingSection(theme, colors, prefs),
    _DictionarySection.identifiers =>
      _buildIdentifiersSection(theme, colors, prefs),
    _DictionarySection.types => _buildTypesUnitsSection(theme, colors, prefs),
    _DictionarySection.lifecycle =>
      _buildLifecycleSection(theme, colors, prefs),
    _DictionarySection.schema => _buildSchemaSection(theme, colors, prefs),
    _DictionarySection.rules =>
      _buildRulesDictionarySection(context, theme, colors, prefs),
    _DictionarySection.locale => _buildLocaleSection(theme, colors, prefs),
  };

  Widget _buildNamingSection(
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs,
  ) {
    final attrChoice = _presetLangCodes.contains(prefs.attributeLanguage)
        ? prefs.attributeLanguage
        : 'custom';
    final enumChoice = _presetLangCodes.contains(prefs.enumLanguage)
        ? prefs.enumLanguage
        : 'custom';
    final contentChoice = _presetLangCodes.contains(prefs.contentLanguage)
        ? prefs.contentLanguage
        : 'custom';

    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _SectionTitle(
          title: 'Langues & Conventions de casse',
          subtitle:
              'Sépare la langue des identifiants techniques (JSON/YAML) de celle des libellés, descriptions et exemples.',
        ),
        const SizedBox(height: 16),
        _PreferenceCard(
          title: 'Langues de modélisation',
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('model-dict-attr-lang-dropdown'),
                initialValue: attrChoice,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Langue des attributs et identifiants techniques',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final lang in BusinessObjectModelPreferences.commonLanguages)
                    DropdownMenuItem(
                      value: lang.code,
                      child: Text('${lang.label} (${lang.code})'),
                    ),
                  const DropdownMenuItem(
                    value: 'custom',
                    child: Text('Autre langue…'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  if (v != 'custom') {
                    _updatePrefs(prefs.copyWith(attributeLanguage: v));
                  } else if (_attrCustomCtrl.text.trim().isNotEmpty) {
                    _updatePrefs(
                      prefs.copyWith(
                        attributeLanguage: _attrCustomCtrl.text.trim(),
                      ),
                    );
                  }
                },
              ),
              if (attrChoice == 'custom') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _attrCustomCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Code ou nom de langue personnalisé',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    if (v.trim().isNotEmpty) {
                      _updatePrefs(prefs.copyWith(attributeLanguage: v.trim()));
                    }
                  },
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('model-dict-enum-lang-dropdown'),
                initialValue: enumChoice,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Langue des valeurs d’énumération & codes d’états',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final lang in BusinessObjectModelPreferences.commonLanguages)
                    DropdownMenuItem(
                      value: lang.code,
                      child: Text('${lang.label} (${lang.code})'),
                    ),
                  const DropdownMenuItem(
                    value: 'custom',
                    child: Text('Autre langue…'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  if (v != 'custom') {
                    _updatePrefs(prefs.copyWith(enumLanguage: v));
                  } else if (_enumCustomCtrl.text.trim().isNotEmpty) {
                    _updatePrefs(
                      prefs.copyWith(enumLanguage: _enumCustomCtrl.text.trim()),
                    );
                  }
                },
              ),
              if (enumChoice == 'custom') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _enumCustomCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Langue personnalisée des enums',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    if (v.trim().isNotEmpty) {
                      _updatePrefs(prefs.copyWith(enumLanguage: v.trim()));
                    }
                  },
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('model-dict-content-lang-dropdown'),
                initialValue: contentChoice,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Langue des titres, descriptions et exemples',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final lang in BusinessObjectModelPreferences.commonLanguages)
                    DropdownMenuItem(
                      value: lang.code,
                      child: Text('${lang.label} (${lang.code})'),
                    ),
                  const DropdownMenuItem(
                    value: 'custom',
                    child: Text('Autre langue…'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  if (v != 'custom') {
                    _updatePrefs(prefs.copyWith(contentLanguage: v));
                  } else if (_contentCustomCtrl.text.trim().isNotEmpty) {
                    _updatePrefs(
                      prefs.copyWith(
                        contentLanguage: _contentCustomCtrl.text.trim(),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PreferenceCard(
          title: 'Casse & Structure des noms',
          child: Column(
            children: [
              DropdownButtonFormField<AttributeNamingCase>(
                key: const ValueKey('model-dict-attr-case-dropdown'),
                initialValue: prefs.attributeCase,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Casse des attributs et relations',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in AttributeNamingCase.values)
                    DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${c.label} (ex. ${c.exampleForLanguage(prefs.attributeLanguage)})',
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _updatePrefs(prefs.copyWith(attributeCase: v));
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<EnumValueNamingCase>(
                key: const ValueKey('model-dict-enum-case-dropdown'),
                initialValue: prefs.enumCase,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Casse des valeurs d’énumération & états',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in EnumValueNamingCase.values)
                    DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${c.label} (ex. ${c.exampleForLanguage(prefs.enumLanguage)})',
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _updatePrefs(prefs.copyWith(enumCase: v));
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Entités au singulier, tableaux au pluriel'),
                subtitle: const Text(
                  'Ex. `Order` / `lines[]` plutôt que `Orders` / `line[]`.',
                ),
                value: prefs.singularObjectsPluralCollections,
                onChanged: (v) => _updatePrefs(
                  prefs.copyWith(singularObjectsPluralCollections: v),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdentifiersSection(
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs,
  ) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _SectionTitle(
          title: 'Identifiants : quand mettre Id, Ref, Code, Number ou Key',
          subtitle:
              'Règles d’arbitrage sémantique et technique entre clé primaire, clé étrangère, référence externe, code nomenclature et numéro métier.',
        ),
        const SizedBox(height: 16),
        _PreferenceCard(
          title: 'Clés primaires & Relations',
          child: Column(
            children: [
              DropdownButtonFormField<PrimaryIdStrategy>(
                key: const ValueKey('model-dict-id-strategy-dropdown'),
                initialValue: prefs.idStrategy,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Stratégie de clé primaire',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in PrimaryIdStrategy.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) {
                  if (v != null) _updatePrefs(prefs.copyWith(idStrategy: v));
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ForeignKeyNamingStyle>(
                key: const ValueKey('model-dict-fk-style-dropdown'),
                initialValue: prefs.foreignKeyStyle,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Nommage des clés étrangères',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final f in ForeignKeyNamingStyle.values)
                    DropdownMenuItem(value: f, child: Text(f.label)),
                ],
                onChanged: (v) {
                  if (v != null) {
                    _updatePrefs(prefs.copyWith(foreignKeyStyle: v));
                  }
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('model-dict-enforce-id-ref-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Imposer la distinction stricte Id / Ref / Code / Number / Key',
                ),
                subtitle: const Text(
                  'Guide le Domain Modeler et active la détection de confusion (*Number typé uuid) dans l’audit.',
                ),
                value: prefs.enforceIdRefCodeNumberDistinction,
                onChanged: (v) => _updatePrefs(
                  prefs.copyWith(enforceIdRefCodeNumberDistinction: v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Matrice de décision rapide : Id vs Ref vs Code vs Number vs Key',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: const [
            _IdentifierDecisionCard(
              badge: '*Id',
              title: 'Identifiant technique interne',
              whenToUse:
                  'Clé primaire technique générée (UUID/ULID/Int) ou clé étrangère relationnelle interne.',
              avoid:
                  'Numéro de facture lu par le client, code pays/devise ou référence partenaire.',
              formatHint: 'uuid / ULID (readOnly: true)',
              examples: 'id, customerId, orderId',
              accentColor: Colors.indigo,
            ),
            _IdentifierDecisionCard(
              badge: '*Ref',
              title: 'Référence externe / tiers',
              whenToUse:
                  'Identifiant provenant d’un partenaire, transporteur, ERP ou document fourni par le client.',
              avoid:
                  'Clé étrangère interne ou numéro généré par votre application.',
              formatHint: 'string (maxLength: 64..128)',
              examples: 'externalRef, trackingRef, poRef',
              accentColor: Colors.teal,
            ),
            _IdentifierDecisionCard(
              badge: '*Code',
              title: 'Code nomenclature court',
              whenToUse:
                  'Valeur courte normalisée d’un référentiel stable (pays, devise, TVA, SKU, motif).',
              avoid:
                  'Séquence chronologique de documents (ex. FAC-2026-001).',
              formatHint: r'string (^[A-Z0-9_-]+$, maxLength: 64)',
              examples: 'countryCode, currencyCode, skuCode',
              accentColor: Colors.deepPurple,
            ),
            _IdentifierDecisionCard(
              badge: '*Number',
              title: 'Numéro séquentiel métier',
              whenToUse:
                  'Numéro lisible généré selon une règle métier ou légale (facture, devis, BL, contrat).',
              avoid:
                  'Clé étrangère entre tables ou compteur de lignes (*Count).',
              formatHint: 'string (unique: true, pattern structuré)',
              examples: 'invoiceNumber, quoteNumber, orderNumber',
              accentColor: Colors.amber,
            ),
            _IdentifierDecisionCard(
              badge: '*Key',
              title: 'Clé fonctionnelle / idempotence',
              whenToUse:
                  'Clé d’idempotence API, clé de partition, slug stable ou clé de routage URL-safe.',
              avoid: 'Clé primaire standard d’une entité métier.',
              formatHint: r'string (^[a-z0-9._:-]+$)',
              examples: 'idempotencyKey, tenantKey',
              accentColor: Colors.blueGrey,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTypesUnitsSection(
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs,
  ) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _SectionTitle(
          title: 'Dates, Booléens & Unités explicites',
          subtitle:
              'Évite les ambiguïtés de fuseau horaire, de négations booléennes et d’unités de mesure.',
        ),
        const SizedBox(height: 16),
        _PreferenceCard(
          title: 'Dates & Horodatages',
          child: DropdownButtonFormField<DateTimeSuffixPolicy>(
            key: const ValueKey('model-dict-datetime-policy-dropdown'),
            initialValue: prefs.dateTimeSuffixPolicy,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Convention *At vs *Date',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in DateTimeSuffixPolicy.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) {
              if (v != null) {
                _updatePrefs(prefs.copyWith(dateTimeSuffixPolicy: v));
              }
            },
          ),
        ),
        const SizedBox(height: 14),
        _PreferenceCard(
          title: 'Booléens',
          child: DropdownButtonFormField<BooleanPrefixPolicy>(
            key: const ValueKey('model-dict-boolean-policy-dropdown'),
            initialValue: prefs.booleanPrefixPolicy,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Préfixes booléens',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in BooleanPrefixPolicy.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) {
              if (v != null) {
                _updatePrefs(prefs.copyWith(booleanPrefixPolicy: v));
              }
            },
          ),
        ),
        const SizedBox(height: 14),
        _PreferenceCard(
          title: 'Quantités, Durées & Unités',
          child: DropdownButtonFormField<UnitSuffixPolicy>(
            key: const ValueKey('model-dict-unit-policy-dropdown'),
            initialValue: prefs.unitSuffixPolicy,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Représentation des unités',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in UnitSuffixPolicy.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) {
              if (v != null) _updatePrefs(prefs.copyWith(unitSuffixPolicy: v));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLifecycleSection(
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs,
  ) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _SectionTitle(
          title: 'Audit, Soft-delete & Concurrence optimiste',
          subtitle:
              'Champs techniques injectés sur les agrégats racines pour la traçabilité, la suppression logique et le contrôle de version.',
        ),
        const SizedBox(height: 16),
        _PreferenceCard(
          title: 'Champs d’audit automatiques',
          child: DropdownButtonFormField<AuditFieldsPreset>(
            key: const ValueKey('model-dict-audit-preset-dropdown'),
            initialValue: prefs.auditPreset,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Préréglage d’audit',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final a in AuditFieldsPreset.values)
                DropdownMenuItem(value: a, child: Text(a.label)),
            ],
            onChanged: (v) {
              if (v != null) _updatePrefs(prefs.copyWith(auditPreset: v));
            },
          ),
        ),
        const SizedBox(height: 14),
        _PreferenceCard(
          title: 'Suppression logique (Soft-delete)',
          child: DropdownButtonFormField<SoftDeleteStrategy>(
            key: const ValueKey('model-dict-softdelete-dropdown'),
            initialValue: prefs.softDeleteStrategy,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Stratégie de soft-delete',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final s in SoftDeleteStrategy.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) {
              if (v != null) {
                _updatePrefs(prefs.copyWith(softDeleteStrategy: v));
              }
            },
          ),
        ),
        const SizedBox(height: 14),
        _PreferenceCard(
          title: 'Concurrence optimiste',
          child: DropdownButtonFormField<OptimisticLockingStrategy>(
            key: const ValueKey('model-dict-optimistic-lock-dropdown'),
            initialValue: prefs.optimisticLockingStrategy,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Stratégie de versionnement',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final o in OptimisticLockingStrategy.values)
                DropdownMenuItem(value: o, child: Text(o.label)),
            ],
            onChanged: (v) {
              if (v != null) {
                _updatePrefs(prefs.copyWith(optimisticLockingStrategy: v));
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSchemaSection(
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs,
  ) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _SectionTitle(
          title: 'Contraintes & Bornes JSON Schema par défaut',
          subtitle:
              'Rigueur de validation, nullabilité, style des relations et longueurs maximales recommandées.',
        ),
        const SizedBox(height: 16),
        _PreferenceCard(
          title: 'Rigueur, Nullabilité & Relations',
          child: Column(
            children: [
              DropdownButtonFormField<JsonSchemaStrictness>(
                key: const ValueKey('model-dict-schema-strictness-dropdown'),
                initialValue: prefs.schemaStrictness,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Rigueur JSON Schema',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in JsonSchemaStrictness.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) {
                  if (v != null) {
                    _updatePrefs(prefs.copyWith(schemaStrictness: v));
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<NullabilityStyle>(
                key: const ValueKey('model-dict-nullability-dropdown'),
                initialValue: prefs.nullabilityStyle,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Nullabilité des champs optionnels',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final n in NullabilityStyle.values)
                    DropdownMenuItem(value: n, child: Text(n.label)),
                ],
                onChanged: (v) {
                  if (v != null) {
                    _updatePrefs(prefs.copyWith(nullabilityStyle: v));
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<RelationModelingStyle>(
                key: const ValueKey('model-dict-relation-style-dropdown'),
                initialValue: prefs.relationStyle,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Style de modélisation des relations',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final r in RelationModelingStyle.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) {
                  if (v != null) {
                    _updatePrefs(prefs.copyWith(relationStyle: v));
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PreferenceCard(
          title: 'Affichage dans « Arbre & Inspecteur »',
          child: SwitchListTile(
            key: const ValueKey('model-dict-single-expanded-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Un seul objet métier ouvert à la fois'),
            subtitle: const Text(
              'Déplier un repository dans « Arbre & Inspecteur » replie automatiquement les autres.',
            ),
            value: prefs.singleExpandedBusinessObject,
            onChanged: (v) => _updatePrefs(
              prefs.copyWith(singleExpandedBusinessObject: v),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _PreferenceCard(
          title: 'Longueurs maximales par défaut (`maxLength`)',
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('model-dict-code-maxlen-field'),
                  controller: _codeMaxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Codes / Réf (min 4)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null && parsed >= 4) {
                      _updatePrefs(
                        prefs.copyWith(defaultCodeMaxLength: parsed),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('model-dict-label-maxlen-field'),
                  controller: _labelMaxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Libellés / Noms (min 8)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null && parsed >= 8) {
                      _updatePrefs(
                        prefs.copyWith(defaultLabelMaxLength: parsed),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('model-dict-desc-maxlen-field'),
                  controller: _descMaxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Descriptions (min 16)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null && parsed >= 16) {
                      _updatePrefs(
                        prefs.copyWith(defaultDescriptionMaxLength: parsed),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRulesDictionarySection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs,
  ) {
    final filtered = prefs.technicalRules.where((r) {
      if (_ruleCategoryFilter != null && r.category != _ruleCategoryFilter) {
        return false;
      }
      return r.matchesQuery(_ruleSearch);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _SectionTitle(
              title: 'Dictionnaire des règles techniques (${prefs.technicalRules.length})',
              subtitle:
                  'Chaque règle active est injectée dans les instructions du Domain Modeler IA.',
            ),
            FilledButton.icon(
              key: const ValueKey('model-dict-add-rule-btn'),
              onPressed: () => _editRuleDialog(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nouvelle règle'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('model-dict-rules-search'),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Filtrer par motif (*Id, *Ref, *Number…), règle ou exemple…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _ruleSearch = v),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilterChip(
              label: Text('Toutes (${prefs.technicalRules.length})'),
              selected: _ruleCategoryFilter == null,
              onSelected: (_) => setState(() => _ruleCategoryFilter = null),
            ),
            for (final cat in TechnicalRuleCategory.values)
              FilterChip(
                label: Text(cat.label),
                selected: _ruleCategoryFilter == cat,
                onSelected: (_) => setState(
                  () => _ruleCategoryFilter =
                      _ruleCategoryFilter == cat ? null : cat,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Aucune règle ne correspond aux critères.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          for (final rule in filtered)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: rule.enabled
                      ? colors.outlineVariant
                      : colors.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                            rule.suffixOrPattern,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rule.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                rule.category.label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          key: ValueKey('model-dict-rule-toggle-${rule.id}'),
                          value: rule.enabled,
                          onChanged: (val) => widget.controller
                              .upsertTechnicalRule(rule.copyWith(enabled: val)),
                        ),
                        IconButton(
                          key: ValueKey('model-dict-rule-edit-${rule.id}'),
                          tooltip: 'Modifier',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () =>
                              _editRuleDialog(context, existing: rule),
                        ),
                        IconButton(
                          key: ValueKey('model-dict-rule-delete-${rule.id}'),
                          tooltip: 'Supprimer',
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          onPressed: () =>
                              widget.controller.deleteTechnicalRule(rule.id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Quand l’utiliser : ${rule.whenToUse}'),
                    if (rule.whenNotToUse.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'À éviter : ${rule.whenNotToUse}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ],
                    if (rule.recommendedType.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Format recommandé : ${rule.recommendedType}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: colors.primary,
                        ),
                      ),
                    ],
                    if (rule.goodExamples.isNotEmpty ||
                        rule.badExamples.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final g in rule.goodExamples)
                            Chip(
                              avatar: Icon(
                                Icons.check_circle_outline_rounded,
                                size: 14,
                                color: colors.primary,
                              ),
                              label: Text(g),
                              visualDensity: VisualDensity.compact,
                            ),
                          for (final b in rule.badExamples)
                            Chip(
                              avatar: Icon(
                                Icons.cancel_outlined,
                                size: 14,
                                color: colors.error,
                              ),
                              backgroundColor: colors.errorContainer.withValues(
                                alpha: 0.45,
                              ),
                              label: Text(b),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildLocaleSection(
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs,
  ) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _SectionTitle(
          title: 'Profil régional, Monétaire & Consignes libres',
          subtitle:
              'Formats régionaux des exemples/seeds et instructions d’architecture complémentaires pour l’IA.',
        ),
        const SizedBox(height: 16),
        _PreferenceCard(
          title: 'Profil géographique & Monétaire',
          child: Column(
            children: [
              DropdownButtonFormField<ModelLocaleProfile>(
                key: const ValueKey('model-dict-locale-dropdown'),
                initialValue: prefs.localeProfile,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Profil régional des exemples & formats',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final l in ModelLocaleProfile.values)
                    DropdownMenuItem(value: l, child: Text(l.label)),
                ],
                onChanged: (v) {
                  if (v != null) _updatePrefs(prefs.copyWith(localeProfile: v));
                },
              ),
              if (prefs.localeProfile == ModelLocaleProfile.custom) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _customLocaleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Libellé régional personnalisé (ex. Canada FR/CAD)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) =>
                      _updatePrefs(prefs.copyWith(customLocaleLabel: v.trim())),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<CurrencyRepresentation>(
                key: const ValueKey('model-dict-currency-dropdown'),
                initialValue: prefs.currencyStyle,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Représentation des montants monétaires',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in CurrencyRepresentation.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) {
                  if (v != null) _updatePrefs(prefs.copyWith(currencyStyle: v));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PreferenceCard(
          title: 'Consignes libres d’architecture pour le Domain Modeler',
          child: TextField(
            key: const ValueKey('model-dict-custom-instructions-field'),
            controller: _customInstructionsCtrl,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText:
                  'Ex. Séparer systématiquement AdresseFacturation et AdresseLivraison ; utiliser des montants HT + taux TVA explicite…',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                _updatePrefs(prefs.copyWith(customInstructions: v)),
          ),
        ),
      ],
    );
  }

  Widget _buildLivePreviewPane(
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences prefs,
  ) {
    final sampleSchema = _buildSamplePreviewJson(prefs);
    final promptText = prefs.toPromptDirective();

    return DefaultTabController(
      length: 2,
      child: Container(
        color: colors.surfaceContainerLow.withValues(alpha: 0.45),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(
                children: [
                  Icon(Icons.preview_rounded, size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aperçu live du modèle généré',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Exemple JSON'),
                Tab(text: 'Prompt IA'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: SelectableText(
                      key: const ValueKey('model-dict-live-json-preview'),
                      sampleSchema,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: SelectableText(
                      key: const ValueKey('model-dict-live-prompt-preview'),
                      promptText,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        height: 1.4,
                      ),
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

  String _buildSamplePreviewJson(BusinessObjectModelPreferences prefs) {
    String fmt(String raw) => prefs.attributeCase.formatIdentifier(raw);
    String fmtEnum(String raw) => prefs.enumCase.formatValue(raw);

    final isFrAttr = prefs.attributeLanguage.toLowerCase().startsWith('fr');
    final orderNumberKey = fmt(isFrAttr ? 'numeroCommande' : 'orderNumber');
    final extRefKey = fmt(isFrAttr ? 'referenceExterne' : 'externalRef');
    final currencyKey = fmt(isFrAttr ? 'codeDevise' : 'currencyCode');
    final customerFkKey = switch (prefs.foreignKeyStyle) {
      ForeignKeyNamingStyle.suffixId => fmt(
        isFrAttr ? 'clientId' : 'customerId',
      ),
      ForeignKeyNamingStyle.prefixId => fmt(
        isFrAttr ? 'idClient' : 'idCustomer',
      ),
      ForeignKeyNamingStyle.semanticOnly => fmt(
        isFrAttr ? 'client' : 'customer',
      ),
    };
    final deliveryDateKey = fmt(
      prefs.dateTimeSuffixPolicy == DateTimeSuffixPolicy.strictAtAndDate
          ? (isFrAttr ? 'livraisonDate' : 'deliveryDate')
          : (isFrAttr ? 'dateLivraison' : 'deliveryAt'),
    );
    final validatedAtKey = fmt(isFrAttr ? 'valideAt' : 'validatedAt');
    final urgentKey = fmt(
      prefs.booleanPrefixPolicy == BooleanPrefixPolicy.free
          ? (isFrAttr ? 'urgent' : 'urgent')
          : (isFrAttr ? 'estUrgent' : 'isUrgent'),
    );
    final totalKey = switch (prefs.currencyStyle) {
      CurrencyRepresentation.integerCents => fmt(
        isFrAttr ? 'montantTotalCents' : 'totalAmountCents',
      ),
      _ => fmt(isFrAttr ? 'montantTotal' : 'totalAmount'),
    };

    final sample = <String, Object?>{
      if (prefs.idStrategy != PrimaryIdStrategy.businessKeyOnly)
        fmt('id'): switch (prefs.idStrategy) {
          PrimaryIdStrategy.uuid => '550e8400-e29b-41d4-a716-446655440000',
          PrimaryIdStrategy.ulid => '01JFA9X3K9P2M8Q7R5T6V1W2YZ',
          PrimaryIdStrategy.autoIncrementInt => 42,
          _ => 'id_001',
        },
      orderNumberKey: 'CMD-2026-0042',
      extRefKey: 'ERP-PARTNER-9812',
      customerFkKey: '8a1c3f10-12ab-4cd5-90ef-1234567890ab',
      currencyKey: prefs.localeProfile.currencyCode,
      fmt('status'): fmtEnum(isFrAttr ? 'en_cours' : 'pending_approval'),
      urgentKey: false,
      deliveryDateKey: '2026-12-01',
      validatedAtKey: '2026-11-21T10:15:00Z',
      totalKey: switch (prefs.currencyStyle) {
        CurrencyRepresentation.integerCents => 14950,
        CurrencyRepresentation.decimal => 149.50,
        CurrencyRepresentation.amountWithCurrencyObject => {
          'amount': 149.50,
          'currency': prefs.localeProfile.currencyCode,
        },
      },
      if (prefs.auditPreset != AuditFieldsPreset.none) ...{
        fmt('createdAt'): '2026-11-21T09:00:00Z',
        fmt('updatedAt'): '2026-11-21T10:15:00Z',
      },
      if (prefs.softDeleteStrategy == SoftDeleteStrategy.isDeletedFlag ||
          prefs.softDeleteStrategy == SoftDeleteStrategy.both)
        fmt('isDeleted'): false,
      if (prefs.softDeleteStrategy == SoftDeleteStrategy.deletedAtTimestamp ||
          prefs.softDeleteStrategy == SoftDeleteStrategy.both ||
          prefs.auditPreset == AuditFieldsPreset.softDelete)
        fmt('deletedAt'): null,
      if (prefs.optimisticLockingStrategy ==
              OptimisticLockingStrategy.integerVersion ||
          prefs.auditPreset == AuditFieldsPreset.fullAudit)
        fmt('version'): 1,
      if (prefs.optimisticLockingStrategy ==
          OptimisticLockingStrategy.etagString)
        fmt('etag'): 'W/"rev-1"',
    };

    return const JsonEncoder.withIndent('  ').convert(sample);
  }

  Future<void> _applyCaseToActiveProject(BuildContext context) async {
    final changed = await widget.controller.applyModelCaseToActiveProject(
      applyAttributeCase: true,
      applyEnumCase: true,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            changed
                ? 'Casse des attributs et enums appliquée au projet actif.'
                : 'Les objets du projet actif respectent déjà cette casse.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openImportExportDialog(
    BuildContext context,
    BusinessObjectModelPreferences prefs,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ModelDictionaryImportExportDialog(
        controller: widget.controller,
        preferences: prefs,
        pickAttachments: widget.pickAttachments,
      ),
    );
    if (mounted) {
      _syncControllersFrom(widget.controller.modelPreferences);
    }
  }

  Future<void> _editRuleDialog(
    BuildContext context, {
    TechnicalModelingRule? existing,
  }) async {
    final saved = await showDialog<TechnicalModelingRule>(
      context: context,
      builder: (_) => _EditTechnicalRuleDialog(existing: existing),
    );
    if (saved != null) {
      await widget.controller.upsertTechnicalRule(saved);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({required this.title, required this.child});

  final String title;
  final Widget child;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _IdentifierDecisionCard extends StatelessWidget {
  const _IdentifierDecisionCard({
    required this.badge,
    required this.title,
    required this.whenToUse,
    required this.avoid,
    required this.formatHint,
    required this.examples,
    required this.accentColor,
  });

  final String badge;
  final String title;
  final String whenToUse;
  final String avoid;
  final String formatHint;
  final String examples;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      width: 286,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Quand : $whenToUse',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'À éviter : $avoid',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.error,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Format : $formatHint',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Ex : $examples',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditTechnicalRuleDialog extends StatefulWidget {
  const _EditTechnicalRuleDialog({this.existing});

  final TechnicalModelingRule? existing;

  @override
  State<_EditTechnicalRuleDialog> createState() =>
      _EditTechnicalRuleDialogState();
}

class _EditTechnicalRuleDialogState extends State<_EditTechnicalRuleDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _patternCtrl;
  late final TextEditingController _whenCtrl;
  late final TextEditingController _avoidCtrl;
  late final TextEditingController _typeCtrl;
  late final TextEditingController _goodCtrl;
  late final TextEditingController _badCtrl;
  late TechnicalRuleCategory _category;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nameCtrl = TextEditingController(text: ex?.name ?? '');
    _patternCtrl = TextEditingController(text: ex?.suffixOrPattern ?? '');
    _whenCtrl = TextEditingController(text: ex?.whenToUse ?? '');
    _avoidCtrl = TextEditingController(text: ex?.whenNotToUse ?? '');
    _typeCtrl = TextEditingController(text: ex?.recommendedType ?? '');
    _goodCtrl = TextEditingController(text: ex?.goodExamples.join(', ') ?? '');
    _badCtrl = TextEditingController(text: ex?.badExamples.join(', ') ?? '');
    _category = ex?.category ?? TechnicalRuleCategory.custom;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _patternCtrl.dispose();
    _whenCtrl.dispose();
    _avoidCtrl.dispose();
    _typeCtrl.dispose();
    _goodCtrl.dispose();
    _badCtrl.dispose();
    super.dispose();
  }

  List<String> _split(String raw) => raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final ex = widget.existing;
    return AlertDialog(
      title: Text(
        ex == null
            ? 'Nouvelle règle technique'
            : 'Modifier « ${ex.suffixOrPattern} »',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const ValueKey('model-dict-rule-field-name'),
                      controller: _nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nom de la règle *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('model-dict-rule-field-pattern'),
                      controller: _patternCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Motif / Suffixe *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<TechnicalRuleCategory>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Catégorie',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in TechnicalRuleCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('model-dict-rule-field-when'),
                controller: _whenCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Quand l’utiliser *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('model-dict-rule-field-avoid'),
                controller: _avoidCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Quand NE PAS l’utiliser',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('model-dict-rule-field-type'),
                controller: _typeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Type / Format JSON Schema recommandé',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('model-dict-rule-field-good'),
                controller: _goodCtrl,
                decoration: const InputDecoration(
                  labelText: 'Bons exemples (séparés par virgule)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('model-dict-rule-field-bad'),
                controller: _badCtrl,
                decoration: const InputDecoration(
                  labelText: 'Contre-exemples (séparés par virgule)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('model-dict-rule-save-btn'),
          onPressed: () {
            final name = _nameCtrl.text.trim();
            final pattern = _patternCtrl.text.trim();
            final when = _whenCtrl.text.trim();
            if (name.isEmpty || pattern.isEmpty || when.isEmpty) return;
            Navigator.pop(
              context,
              TechnicalModelingRule(
                id: ex?.id ?? 'rule_${shortid.generate()}',
                name: name,
                suffixOrPattern: pattern,
                category: _category,
                whenToUse: when,
                whenNotToUse: _avoidCtrl.text.trim(),
                recommendedType: _typeCtrl.text.trim(),
                goodExamples: _split(_goodCtrl.text),
                badExamples: _split(_badCtrl.text),
                enabled: ex?.enabled ?? true,
                isBuiltIn: ex?.isBuiltIn ?? false,
              ),
            );
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _ModelDictionaryImportExportDialog extends StatefulWidget {
  const _ModelDictionaryImportExportDialog({
    required this.controller,
    required this.preferences,
    this.pickAttachments,
  });

  final SpecForgeController controller;
  final BusinessObjectModelPreferences preferences;
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  @override
  State<_ModelDictionaryImportExportDialog> createState() =>
      _ModelDictionaryImportExportDialogState();
}

class _ModelDictionaryImportExportDialogState
    extends State<_ModelDictionaryImportExportDialog> {
  String _exportFormat = 'json';
  late final TextEditingController _pathCtrl;
  final _importCtrl = TextEditingController();
  BusinessObjectModelPreferences? _parsed;
  String? _importError;
  String? _statusMsg;

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController(text: _defaultPath('json'));
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _importCtrl.dispose();
    super.dispose();
  }

  String _defaultPath(String ext) {
    final sep = Platform.pathSeparator;
    return '${widget.controller.modelDictionaryStore.rootDirectory.path}${sep}exports${sep}model_dictionary.$ext';
  }

  String _exportContent() => _exportFormat == 'md'
      ? ModelDictionaryCodec.toMarkdown(widget.preferences)
      : ModelDictionaryCodec.toJsonString(widget.preferences);

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
      final parsed = ModelDictionaryCodec.parseJson(raw);
      setState(() {
        _parsed = parsed;
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
    final content = _exportContent();
    return AlertDialog(
      title: const Text('Importer / Exporter le dictionnaire technique'),
      content: SizedBox(
        width: 660,
        height: 450,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Exporter'),
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
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('JSON'),
                              selected: _exportFormat == 'json',
                              onSelected: (_) => setState(() {
                                _exportFormat = 'json';
                                _pathCtrl.text = _defaultPath('json');
                              }),
                            ),
                            ChoiceChip(
                              label: const Text('Markdown (.md)'),
                              selected: _exportFormat == 'md',
                              onSelected: (_) => setState(() {
                                _exportFormat = 'md';
                                _pathCtrl.text = _defaultPath('md');
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                content,
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
                                controller: _pathCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Chemin de sauvegarde',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: content),
                                );
                                if (mounted) {
                                  setState(
                                    () => _statusMsg =
                                        'Copié dans le presse-papiers.',
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copier'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () async {
                                final f = File(_pathCtrl.text.trim());
                                await f.parent.create(recursive: true);
                                await f.writeAsString(content);
                                if (mounted) {
                                  setState(
                                    () => _statusMsg = 'Enregistré : ${f.path}',
                                  );
                                }
                              },
                              icon: const Icon(Icons.save_alt_rounded, size: 16),
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
                              color: Theme.of(context).colorScheme.primary,
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
                            icon: const Icon(Icons.upload_file_rounded, size: 16),
                            label: const Text('Charger un fichier JSON…'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('model-dict-import-text'),
                            controller: _importCtrl,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              hintText: 'Collez ici le JSON exporté…',
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
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          )
                        else if (_parsed != null)
                          Text(
                            'JSON valide : ${_parsed!.technicalRules.length} règle(s) technique(s).',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            key: const ValueKey('model-dict-apply-import-btn'),
                            onPressed: _parsed == null
                                ? null
                                : () async {
                                    await widget.controller
                                        .updateModelPreferences(_parsed!);
                                    if (context.mounted) {
                                      Navigator.pop(context);
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
