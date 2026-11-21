/// Dialogue modal à 4 onglets « Préférences du modèle » pour paramétrer les conventions
/// de nommage, clés/audit, rigueur JSON Schema, profil régional et consignes IA
/// ([showBusinessObjectModelPreferencesDialog]).
library;

import 'package:material_ui/material_ui.dart';

import '../../models/business_object_model_preferences.dart';

/// Résultat renvoyé lors de la validation du dialogue « Préférences du modèle ».
typedef ModelPreferencesDialogResult = ({
  BusinessObjectModelPreferences preferences,
  bool applyAttributeCaseToExisting,
  bool applyEnumCaseToExisting,
});

/// Ouvre le panneau unifié à 4 onglets « Préférences du modèle ».
Future<ModelPreferencesDialogResult?> showBusinessObjectModelPreferencesDialog(
  BuildContext context, {
  required BusinessObjectModelPreferences initialPreferences,
  required bool hasExistingObjects,
}) => showDialog<ModelPreferencesDialogResult>(
  context: context,
  builder: (_) => _ModelPreferencesDialog(
    initialPreferences: initialPreferences,
    hasExistingObjects: hasExistingObjects,
  ),
);

class _ModelPreferencesDialog extends StatefulWidget {
  const _ModelPreferencesDialog({
    required this.initialPreferences,
    required this.hasExistingObjects,
  });

  final BusinessObjectModelPreferences initialPreferences;
  final bool hasExistingObjects;

  @override
  State<_ModelPreferencesDialog> createState() =>
      _ModelPreferencesDialogState();
}

class _ModelPreferencesDialogState extends State<_ModelPreferencesDialog> {
  static const Set<String> _presetLangCodes = {
    'fr',
    'en',
    'es',
    'de',
    'it',
    'pt',
  };

  late String _attrLangChoice;
  late String _enumLangChoice;
  late String _contentLangChoice;
  late TextEditingController _attrCustomCtrl;
  late TextEditingController _enumCustomCtrl;
  late TextEditingController _contentCustomCtrl;
  late TextEditingController _customLocaleCtrl;
  late TextEditingController _customInstructionsCtrl;

  late AttributeNamingCase _attributeCase;
  late EnumValueNamingCase _enumCase;
  late bool _singularPlural;
  late PrimaryIdStrategy _idStrategy;
  late ForeignKeyNamingStyle _foreignKeyStyle;
  late AuditFieldsPreset _auditPreset;
  late JsonSchemaStrictness _schemaStrictness;
  late NullabilityStyle _nullabilityStyle;
  late RelationModelingStyle _relationStyle;
  late ModelLocaleProfile _localeProfile;
  late CurrencyRepresentation _currencyStyle;
  late bool _singleExpandedBusinessObject;

  bool _applyAttributeCaseToExisting = false;
  bool _applyEnumCaseToExisting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _attrCustomCtrl = TextEditingController();
    _enumCustomCtrl = TextEditingController();
    _contentCustomCtrl = TextEditingController();
    _customLocaleCtrl = TextEditingController();
    _customInstructionsCtrl = TextEditingController();
    _loadFrom(widget.initialPreferences);
  }

  void _loadFrom(BusinessObjectModelPreferences prefs) {
    _attrLangChoice = _presetLangCodes.contains(prefs.attributeLanguage)
        ? prefs.attributeLanguage
        : 'custom';
    _enumLangChoice = _presetLangCodes.contains(prefs.enumLanguage)
        ? prefs.enumLanguage
        : 'custom';
    _contentLangChoice = _presetLangCodes.contains(prefs.contentLanguage)
        ? prefs.contentLanguage
        : 'custom';
    _attrCustomCtrl.text = _attrLangChoice == 'custom'
        ? prefs.attributeLanguage
        : '';
    _enumCustomCtrl.text = _enumLangChoice == 'custom'
        ? prefs.enumLanguage
        : '';
    _contentCustomCtrl.text = _contentLangChoice == 'custom'
        ? prefs.contentLanguage
        : '';
    _attributeCase = prefs.attributeCase;
    _enumCase = prefs.enumCase;
    _singularPlural = prefs.singularObjectsPluralCollections;
    _idStrategy = prefs.idStrategy;
    _foreignKeyStyle = prefs.foreignKeyStyle;
    _auditPreset = prefs.auditPreset;
    _schemaStrictness = prefs.schemaStrictness;
    _nullabilityStyle = prefs.nullabilityStyle;
    _relationStyle = prefs.relationStyle;
    _localeProfile = prefs.localeProfile;
    _customLocaleCtrl.text = prefs.customLocaleLabel;
    _currencyStyle = prefs.currencyStyle;
    _singleExpandedBusinessObject = prefs.singleExpandedBusinessObject;
    _customInstructionsCtrl.text = prefs.customInstructions;
    _error = null;
  }

  @override
  void dispose() {
    _attrCustomCtrl.dispose();
    _enumCustomCtrl.dispose();
    _contentCustomCtrl.dispose();
    _customLocaleCtrl.dispose();
    _customInstructionsCtrl.dispose();
    super.dispose();
  }

  BusinessObjectModelPreferences _buildCandidate() =>
      BusinessObjectModelPreferences(
        attributeLanguage: _attrLangChoice == 'custom'
            ? _attrCustomCtrl.text.trim()
            : _attrLangChoice,
        enumLanguage: _enumLangChoice == 'custom'
            ? _enumCustomCtrl.text.trim()
            : _enumLangChoice,
        contentLanguage: _contentLangChoice == 'custom'
            ? _contentCustomCtrl.text.trim()
            : _contentLangChoice,
        attributeCase: _attributeCase,
        enumCase: _enumCase,
        singularObjectsPluralCollections: _singularPlural,
        idStrategy: _idStrategy,
        foreignKeyStyle: _foreignKeyStyle,
        auditPreset: _auditPreset,
        schemaStrictness: _schemaStrictness,
        nullabilityStyle: _nullabilityStyle,
        relationStyle: _relationStyle,
        localeProfile: _localeProfile,
        customLocaleLabel: _customLocaleCtrl.text.trim(),
        currencyStyle: _currencyStyle,
        singleExpandedBusinessObject: _singleExpandedBusinessObject,
        customInstructions: _customInstructionsCtrl.text.trim(),
      );

  void _submit() {
    final candidate = _buildCandidate();
    try {
      candidate.validate();
      Navigator.of(context).pop((
        preferences: candidate,
        applyAttributeCaseToExisting: _applyAttributeCaseToExisting,
        applyEnumCaseToExisting: _applyEnumCaseToExisting,
      ));
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final candidate = _buildCandidate();

    return Dialog(
      key: const ValueKey('spec-objects-prefs-dialog'),
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 720,
        height: 580,
        child: DefaultTabController(
          length: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 10),
                color: colors.surfaceContainerLow,
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Préférences du modèle (Objets métiers & IA)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Transmises au Domain Modeler et appliquées aux exports JSON Schema / Seed.',
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
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Langues & Nommage'),
                  Tab(text: 'Clés & Audit'),
                  Tab(text: 'Schéma & Relations'),
                  Tab(text: 'Régional & Consignes'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildNamingTab(theme, colors),
                    _buildKeysAuditTab(theme, colors),
                    _buildSchemaRelationsTab(theme, colors),
                    _buildLocaleInstructionsTab(theme, colors, candidate),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: colors.error, fontSize: 12),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('spec-objects-prefs-reset'),
                      onPressed: () => setState(
                        () =>
                            _loadFrom(BusinessObjectModelPreferences.defaults),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded, size: 17),
                      label: const Text('Réinitialiser défauts'),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Annuler'),
                        ),
                        FilledButton(
                          key: const ValueKey('spec-objects-prefs-save'),
                          onPressed: _submit,
                          child: const Text('Enregistrer'),
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
    );
  }

  Widget _buildNamingTab(ThemeData theme, ColorScheme colors) {
    final previewLang = _attrLangChoice == 'custom'
        ? _attrCustomCtrl.text.trim()
        : _attrLangChoice;
    final previewEnumLang = _enumLangChoice == 'custom'
        ? _enumCustomCtrl.text.trim()
        : _enumLangChoice;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('spec-objects-attr-lang-dropdown'),
          isExpanded: true,
          initialValue: _attrLangChoice,
          decoration: const InputDecoration(
            labelText: 'Langue des attributs générés',
            helperText: 'name, technicalName, relations',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final lang in BusinessObjectModelPreferences.commonLanguages)
              DropdownMenuItem(
                value: lang.code,
                child: Text(
                  '${lang.label} (${lang.code})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const DropdownMenuItem(
              value: 'custom',
              child: Text('Autre langue…'),
            ),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _attrLangChoice = v;
                _error = null;
              });
            }
          },
        ),
        if (_attrLangChoice == 'custom') ...[
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('spec-objects-attr-lang-custom'),
            controller: _attrCustomCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Langue personnalisée des attributs (ex. Néerlandais)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 14),
        DropdownButtonFormField<AttributeNamingCase>(
          key: const ValueKey('spec-objects-attr-case-dropdown'),
          isExpanded: true,
          initialValue: _attributeCase,
          decoration: const InputDecoration(
            labelText: 'Casse des noms d’attributs & relations',
            helperText: 'Identifiants ASCII stricts sans accent',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final c in AttributeNamingCase.values)
              DropdownMenuItem(
                value: c,
                child: Text(
                  '${c.label} (ex. ${c.exampleForLanguage(previewLang)})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _attributeCase = v);
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: const ValueKey('spec-objects-enum-lang-dropdown'),
          isExpanded: true,
          initialValue: _enumLangChoice,
          decoration: const InputDecoration(
            labelText: 'Langue des valeurs d’enum & états de cycle de vie',
            helperText: 'enumValues et lifecycleStates[*].name',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final lang in BusinessObjectModelPreferences.commonLanguages)
              DropdownMenuItem(
                value: lang.code,
                child: Text(
                  '${lang.label} (${lang.code})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const DropdownMenuItem(
              value: 'custom',
              child: Text('Autre langue…'),
            ),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _enumLangChoice = v;
                _error = null;
              });
            }
          },
        ),
        if (_enumLangChoice == 'custom') ...[
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('spec-objects-enum-lang-custom'),
            controller: _enumCustomCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Langue personnalisée des valeurs d’enum',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 14),
        DropdownButtonFormField<EnumValueNamingCase>(
          key: const ValueKey('spec-objects-enum-case-dropdown'),
          isExpanded: true,
          initialValue: _enumCase,
          decoration: const InputDecoration(
            labelText: 'Casse des valeurs d’enum & états de cycle de vie',
            helperText: 'enumValues et lifecycleStates[*].name',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final c in EnumValueNamingCase.values)
              DropdownMenuItem(
                value: c,
                child: Text(
                  '${c.label} (ex. ${c.exampleForLanguage(previewEnumLang)})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _enumCase = v);
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: const ValueKey('spec-objects-content-lang-dropdown'),
          isExpanded: true,
          initialValue: _contentLangChoice,
          decoration: const InputDecoration(
            labelText: 'Langue des exemples, title, description, etc.',
            helperText: 'title, description, examples, \$comment, constraints',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final lang in BusinessObjectModelPreferences.commonLanguages)
              DropdownMenuItem(
                value: lang.code,
                child: Text(
                  '${lang.label} (${lang.code})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const DropdownMenuItem(
              value: 'custom',
              child: Text('Autre langue…'),
            ),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _contentLangChoice = v;
                _error = null;
              });
            }
          },
        ),
        if (_contentLangChoice == 'custom') ...[
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('spec-objects-content-lang-custom'),
            controller: _contentCustomCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Langue personnalisée des textes & exemples',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 10),
        SwitchListTile(
          key: const ValueKey('spec-objects-singular-plural-switch'),
          contentPadding: EdgeInsets.zero,
          value: _singularPlural,
          onChanged: (v) => setState(() => _singularPlural = v),
          title: const Text(
            'Entités au singulier, tableaux/relations 1:N au pluriel',
          ),
          subtitle: const Text('Ex. Commande / Order et lignes[] / lines[]'),
        ),
        if (widget.hasExistingObjects) ...[
          CheckboxListTile(
            key: const ValueKey('spec-objects-apply-case-existing'),
            contentPadding: EdgeInsets.zero,
            value: _applyAttributeCaseToExisting,
            onChanged: (v) =>
                setState(() => _applyAttributeCaseToExisting = v ?? false),
            title: const Text('Convertir la casse des attributs déjà présents'),
            subtitle: Text('Reformate en ${_attributeCase.label}.'),
          ),
          CheckboxListTile(
            key: const ValueKey('spec-objects-apply-enum-case-existing'),
            contentPadding: EdgeInsets.zero,
            value: _applyEnumCaseToExisting,
            onChanged: (v) =>
                setState(() => _applyEnumCaseToExisting = v ?? false),
            title: const Text(
              'Convertir les enumValues et états déjà présents',
            ),
            subtitle: Text('Reformate selon ${_enumCase.label}.'),
          ),
        ],
      ],
    );
  }

  Widget _buildKeysAuditTab(ThemeData theme, ColorScheme colors) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<PrimaryIdStrategy>(
          key: const ValueKey('spec-objects-id-strategy-dropdown'),
          isExpanded: true,
          initialValue: _idStrategy,
          decoration: const InputDecoration(
            labelText: 'Stratégie d’identifiant primaire',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final s in PrimaryIdStrategy.values)
              DropdownMenuItem(
                value: s,
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _idStrategy = v);
          },
        ),
        const SizedBox(height: 6),
        Text(
          _idStrategy.promptGuidance,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ForeignKeyNamingStyle>(
          key: const ValueKey('spec-objects-fk-style-dropdown'),
          isExpanded: true,
          initialValue: _foreignKeyStyle,
          decoration: const InputDecoration(
            labelText: 'Convention de nommage des clés étrangères',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final f in ForeignKeyNamingStyle.values)
              DropdownMenuItem(
                value: f,
                child: Text(
                  f.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _foreignKeyStyle = v);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<AuditFieldsPreset>(
          key: const ValueKey('spec-objects-audit-preset-dropdown'),
          isExpanded: true,
          initialValue: _auditPreset,
          decoration: const InputDecoration(
            labelText: 'Champs d’audit automatiques (agrégats racines)',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final a in AuditFieldsPreset.values)
              DropdownMenuItem(
                value: a,
                child: Text(
                  a.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _auditPreset = v);
          },
        ),
        const SizedBox(height: 6),
        Text(
          _auditPreset.promptGuidance,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSchemaRelationsTab(ThemeData theme, ColorScheme colors) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<JsonSchemaStrictness>(
          key: const ValueKey('spec-objects-schema-strictness-dropdown'),
          isExpanded: true,
          initialValue: _schemaStrictness,
          decoration: const InputDecoration(
            labelText: 'Niveau de rigueur JSON Schema',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final s in JsonSchemaStrictness.values)
              DropdownMenuItem(
                value: s,
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _schemaStrictness = v);
          },
        ),
        const SizedBox(height: 6),
        Text(
          _schemaStrictness.promptGuidance,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<NullabilityStyle>(
          key: const ValueKey('spec-objects-nullability-dropdown'),
          isExpanded: true,
          initialValue: _nullabilityStyle,
          decoration: const InputDecoration(
            labelText: 'Politique de nullabilité (champs optionnels)',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final n in NullabilityStyle.values)
              DropdownMenuItem(
                value: n,
                child: Text(
                  n.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _nullabilityStyle = v);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<RelationModelingStyle>(
          key: const ValueKey('spec-objects-relation-style-dropdown'),
          isExpanded: true,
          initialValue: _relationStyle,
          decoration: const InputDecoration(
            labelText: 'Style de modélisation des relations 1:1 / 1:N',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final r in RelationModelingStyle.values)
              DropdownMenuItem(
                value: r,
                child: Text(
                  r.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _relationStyle = v);
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const ValueKey('spec-objects-single-expanded-switch'),
          contentPadding: EdgeInsets.zero,
          value: _singleExpandedBusinessObject,
          onChanged: (v) =>
              setState(() => _singleExpandedBusinessObject = v),
          title: const Text('Un seul objet métier ouvert à la fois'),
          subtitle: const Text(
            'Dans « Arbre & Inspecteur », déplier un repository replie automatiquement les autres.',
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Text(
            'Note : les règles strictes de dimensionnement restent toujours actives '
            '(max 200 attributs/objet, max 200 lignes/tableau imbriqué, objet dédié au-delà). '
            'En mode Strict, l’exporteur JSON Schema ajoute automatiquement additionalProperties: false.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildLocaleInstructionsTab(
    ThemeData theme,
    ColorScheme colors,
    BusinessObjectModelPreferences candidate,
  ) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<ModelLocaleProfile>(
          key: const ValueKey('spec-objects-locale-profile-dropdown'),
          isExpanded: true,
          initialValue: _localeProfile,
          decoration: const InputDecoration(
            labelText:
                'Profil régional (exemples, téléphone, code postal, devise)',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final p in ModelLocaleProfile.values)
              DropdownMenuItem(
                value: p,
                child: Text(
                  p.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _localeProfile = v);
          },
        ),
        if (_localeProfile == ModelLocaleProfile.custom) ...[
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('spec-objects-custom-locale-field'),
            controller: _customLocaleCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText:
                  'Détails du profil régional personnalisé (ex. BE / EUR)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 14),
        DropdownButtonFormField<CurrencyRepresentation>(
          key: const ValueKey('spec-objects-currency-style-dropdown'),
          isExpanded: true,
          initialValue: _currencyStyle,
          decoration: const InputDecoration(
            labelText: 'Représentation des montants monétaires',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final c in CurrencyRepresentation.values)
              DropdownMenuItem(
                value: c,
                child: Text(
                  c.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _currencyStyle = v);
          },
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('spec-objects-custom-instructions-field'),
          controller: _customInstructionsCtrl,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Consignes libres d’architecture pour l’IA (optionnel)',
            hintText:
                'Ex. Préfixer les booléens par is/has, dates en UTC ISO-8601…',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Aperçu des directives injectées dans le prompt IA',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          key: const ValueKey('spec-objects-prefs-prompt-preview'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: SelectableText(
            candidate.toPromptDirective(),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
