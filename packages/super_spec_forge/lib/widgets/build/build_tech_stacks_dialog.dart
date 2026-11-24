/// Éditeur modal des profils de stacks techniques ([showBuildTechStacksDialog])
/// et sélecteur compact réutilisable ([DomainTechStackSelector]) pour associer
/// une stack technique et sa structure de dossiers à un domaine fonctionnel.
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/build_tech_stack_profile.dart';
import '../../models/domain_catalog.dart';
import '../../services/spec_forge_controller.dart';

final RegExp _stackCodePattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

/// Ouvre l'éditeur de profils de stacks techniques du workspace actif.
Future<void> showBuildTechStacksDialog(
  BuildContext context, {
  required SpecForgeController controller,
  String? initialStackId,
}) => showDialog<void>(
  context: context,
  builder: (_) => _BuildTechStacksDialog(
    controller: controller,
    initialStackId: initialStackId,
  ),
);

/// Sélecteur compact de la stack technique affectée à un domaine, accompagné
/// d'un bouton d'accès rapide à l'éditeur des profils de stacks.
class DomainTechStackSelector extends StatelessWidget {
  /// Crée le sélecteur de stack technique pour un domaine.
  const DomainTechStackSelector({
    required this.techStacks,
    required this.selectedStackId,
    required this.onChanged,
    this.onManageStacks,
    this.dropdownKey,
    this.manageButtonKey,
    super.key,
  });

  /// Profils de stacks disponibles dans le catalogue.
  final List<BuildTechStackProfile> techStacks;

  /// Identifiant de la stack actuellement affectée au domaine, ou `null`.
  final String? selectedStackId;

  /// Déclenché lorsque l'utilisateur change la stack affectée au domaine.
  final ValueChanged<String?> onChanged;

  /// Action optionnelle ouvrant l'éditeur de profils de stacks.
  final VoidCallback? onManageStacks;

  /// Clé optionnelle appliquée au `DropdownButton`.
  final Key? dropdownKey;

  /// Clé optionnelle appliquée au bouton d'ouverture de l'éditeur de stacks.
  final Key? manageButtonKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveValue = techStacks.any((s) => s.id == selectedStackId)
        ? selectedStackId
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: effectiveValue != null
                  ? colors.primary
                  : colors.outlineVariant,
            ),
            color: effectiveValue != null
                ? colors.primaryContainer.withValues(alpha: 0.35)
                : colors.surface,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              key: dropdownKey,
              value: effectiveValue,
              isDense: true,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurface,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      Icon(Icons.layers_clear_outlined, size: 14),
                      Text('Aucune stack'),
                    ],
                  ),
                ),
                for (final stack in techStacks)
                  DropdownMenuItem<String?>(
                    value: stack.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        const Icon(Icons.layers_rounded, size: 14),
                        Text(stack.name),
                      ],
                    ),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
        if (onManageStacks != null)
          Tooltip(
            message: 'Configurer les stacks techniques et structures de dossiers',
            child: OutlinedButton.icon(
              key: manageButtonKey,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: onManageStacks,
              icon: const Icon(Icons.tune_rounded, size: 15),
              label: const Text('Stacks'),
            ),
          ),
      ],
    );
  }
}

class _BuildTechStacksDialog extends StatefulWidget {
  const _BuildTechStacksDialog({
    required this.controller,
    this.initialStackId,
  });

  final SpecForgeController controller;
  final String? initialStackId;

  @override
  State<_BuildTechStacksDialog> createState() => _BuildTechStacksDialogState();
}

class _BuildTechStacksDialogState extends State<_BuildTechStacksDialog>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _techStackCtrl = TextEditingController();
  final TextEditingController _foldersCtrl = TextEditingController();
  final TextEditingController _implFoldersCtrl = TextEditingController();
  final TextEditingController _testFoldersCtrl = TextEditingController();
  final TextEditingController _persistenceFoldersCtrl = TextEditingController();
  final TextEditingController _implExtCtrl = TextEditingController();
  final TextEditingController _testExtCtrl = TextEditingController();
  final TextEditingController _persistenceExtCtrl = TextEditingController();

  late final TabController _tabController;
  String? _selectedId;
  bool _creatingNew = false;
  bool _saving = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final stacks = widget.controller.domainCatalog.techStacks;
    final initial =
        stacks.where((s) => s.id == widget.initialStackId).firstOrNull ??
        stacks.firstOrNull;
    if (initial != null) {
      _loadIntoForm(initial);
    } else {
      _startNewStack();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _techStackCtrl.dispose();
    _foldersCtrl.dispose();
    _implFoldersCtrl.dispose();
    _testFoldersCtrl.dispose();
    _persistenceFoldersCtrl.dispose();
    _implExtCtrl.dispose();
    _testExtCtrl.dispose();
    _persistenceExtCtrl.dispose();
    super.dispose();
  }

  void _loadIntoForm(BuildTechStackProfile profile) {
    _selectedId = profile.id;
    _creatingNew = false;
    _feedback = null;
    _codeCtrl.text = profile.code;
    _nameCtrl.text = profile.name;
    _descCtrl.text = profile.description;
    _techStackCtrl.text = profile.technicalStack;
    _foldersCtrl.text = profile.folderStructure;
    _implFoldersCtrl.text = profile.implementationFolderStructure;
    _testFoldersCtrl.text = profile.unitTestFolderStructure;
    _persistenceFoldersCtrl.text = profile.persistenceFolderStructure;
    _implExtCtrl.text = profile.implementationExtension;
    _testExtCtrl.text = profile.unitTestExtension;
    _persistenceExtCtrl.text = profile.persistenceExtension;
  }

  void _startNewStack({BuildTechStackProfile? basedOn}) {
    _selectedId = null;
    _creatingNew = true;
    _feedback = null;
    if (basedOn != null) {
      _codeCtrl.text = '${basedOn.code}-copy';
      _nameCtrl.text = '${basedOn.name} (copie)';
      _descCtrl.text = basedOn.description;
      _techStackCtrl.text = basedOn.technicalStack;
      _foldersCtrl.text = basedOn.folderStructure;
      _implFoldersCtrl.text = basedOn.implementationFolderStructure;
      _testFoldersCtrl.text = basedOn.unitTestFolderStructure;
      _persistenceFoldersCtrl.text = basedOn.persistenceFolderStructure;
      _implExtCtrl.text = basedOn.implementationExtension;
      _testExtCtrl.text = basedOn.unitTestExtension;
      _persistenceExtCtrl.text = basedOn.persistenceExtension;
    } else {
      _codeCtrl.text = '';
      _nameCtrl.text = '';
      _descCtrl.text = '';
      _techStackCtrl.text = '';
      _foldersCtrl.text = '';
      _implFoldersCtrl.text =
          'src/{{domain}}/\n'
          '├── domain/\n'
          '└── application/';
      _testFoldersCtrl.text =
          'test/{{domain}}/\n'
          '├── domain/\n'
          '└── application/';
      _persistenceFoldersCtrl.text =
          'src/{{domain}}/\n'
          '├── domain/ports/outbound/\n'
          '└── infrastructure/persistence/\n'
          'test/{{domain}}/infrastructure/';
      _implExtCtrl.text = '';
      _testExtCtrl.text = '';
      _persistenceExtCtrl.text = '';
    }
  }

  Future<void> _saveCurrent() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final catalog = widget.controller.domainCatalog;
    final trimmedCode = _codeCtrl.text.trim();
    final duplicateCode = catalog.techStacks.any(
      (s) => s.code == trimmedCode && s.id != _selectedId,
    );
    if (duplicateCode) {
      setState(() {
        _feedback = 'Une stack avec le code « $trimmedCode » existe déjà.';
      });
      return;
    }

    final profile = BuildTechStackProfile(
      id: _selectedId ?? 'stack_${shortid.generate()}',
      code: trimmedCode,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      technicalStack: _techStackCtrl.text.trim(),
      folderStructure: _foldersCtrl.text.trim(),
      implementationFolderStructure: _implFoldersCtrl.text.trim(),
      unitTestFolderStructure: _testFoldersCtrl.text.trim(),
      persistenceFolderStructure: _persistenceFoldersCtrl.text.trim(),
      implementationExtension: _implExtCtrl.text.trim(),
      unitTestExtension: _testExtCtrl.text.trim(),
      persistenceExtension: _persistenceExtCtrl.text.trim(),
    );

    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      profile.validate();
      final nextStacks = _creatingNew || _selectedId == null
          ? <BuildTechStackProfile>[...catalog.techStacks, profile]
          : <BuildTechStackProfile>[
              for (final existing in catalog.techStacks)
                if (existing.id == profile.id) profile else existing,
            ];
      await widget.controller.updateDomainCatalog(
        catalog.copyWith(
          techStacks: nextStacks,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _loadIntoForm(profile);
        _feedback = 'Stack « ${profile.name} » enregistrée.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _feedback = error is FormatException ? error.message : '$error';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteCurrent() async {
    final targetId = _selectedId;
    if (_saving || targetId == null) return;
    final catalog = widget.controller.domainCatalog;
    final nextStacks = catalog.techStacks
        .where((s) => s.id != targetId)
        .toList(growable: false);
    final nextDomains = <FunctionalDomain>[
      for (final domain in catalog.domains)
        if (domain.techStackId == targetId)
          domain.copyWith(clearTechStackId: true)
        else
          domain,
    ];

    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      await widget.controller.updateDomainCatalog(
        catalog.copyWith(
          domains: nextDomains,
          techStacks: nextStacks,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      if (!mounted) return;
      setState(() {
        if (nextStacks.isNotEmpty) {
          _loadIntoForm(nextStacks.first);
        } else {
          _startNewStack();
        }
        _feedback = 'Stack supprimée.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _feedback = error is FormatException ? error.message : '$error';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final catalog = widget.controller.domainCatalog;
        final stacks = catalog.techStacks;
        final currentProfile = stacks
            .where((s) => s.id == _selectedId)
            .firstOrNull;

        return Dialog(
          key: const ValueKey('build-tech-stacks-dialog'),
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.maxFinite,
            height: double.maxFinite,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
                  child: Row(
                    children: [
                      Icon(Icons.layers_rounded, color: colors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stacks techniques & structures de dossiers',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Extensions ajoutées en fin de chaque prompt IA selon la stack du domaine.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('tech-stack-close-btn'),
                        tooltip: 'Fermer',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 260,
                        child: Container(
                          color: colors.surfaceContainerLow.withValues(
                            alpha: 0.6,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  8,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Stacks (${stacks.length})',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey('tech-stack-add-btn'),
                                      tooltip: 'Nouvelle stack',
                                      onPressed: _saving
                                          ? null
                                          : () => setState(_startNewStack),
                                      icon: const Icon(Icons.add_rounded),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.all(8),
                                  children: [
                                    for (final stack in stacks)
                                      _buildStackTile(
                                        context,
                                        catalog: catalog,
                                        stack: stack,
                                        selected:
                                            !_creatingNew &&
                                            stack.id == _selectedId,
                                      ),
                                  ],
                                ),
                              ),
                              if (currentProfile != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    0,
                                    10,
                                    10,
                                  ),
                                  child: OutlinedButton.icon(
                                    key: const ValueKey(
                                      'tech-stack-duplicate-btn',
                                    ),
                                    onPressed: _saving
                                        ? null
                                        : () => setState(
                                            () => _startNewStack(
                                              basedOn: currentProfile,
                                            ),
                                          ),
                                    icon: const Icon(
                                      Icons.copy_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Dupliquer cette stack'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _buildEditorForm(
                          theme,
                          colors,
                          currentProfile: currentProfile,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStackTile(
    BuildContext context, {
    required DomainCatalog catalog,
    required BuildTechStackProfile stack,
    required bool selected,
  }) {
    final usedByCount = catalog.domains
        .where((d) => d.techStackId == stack.id)
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: ValueKey('tech-stack-item-${stack.id}'),
          dense: true,
          selected: selected,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          onTap: () => setState(() => _loadIntoForm(stack)),
          leading: const Icon(Icons.layers_rounded, size: 18),
          title: Text(stack.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${stack.code}${usedByCount > 0 ? ' · $usedByCount domaine(s)' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildEditorForm(
    ThemeData theme,
    ColorScheme colors, {
    required BuildTechStackProfile? currentProfile,
  }) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                SizedBox(
                  width: 210,
                  child: TextFormField(
                    key: const ValueKey('tech-stack-code-field'),
                    controller: _codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Code canonique *',
                      hintText: 'java-spring-boot',
                      helperText: 'kebab-case (YAML)',
                      isDense: true,
                    ),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.length < 2 ||
                          trimmed.length > 64 ||
                          !_stackCodePattern.hasMatch(trimmed)) {
                        return 'kebab-case (2 à 64 car.)';
                      }
                      return null;
                    },
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    key: const ValueKey('tech-stack-name-field'),
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom de la stack *',
                      hintText: 'Java 21 / Spring Boot 3',
                      isDense: true,
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? 'Nom requis (2 caractères min.)'
                        : null,
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('tech-stack-description-field'),
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description courte',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(
                key: ValueKey('tech-stack-tab-general'),
                icon: Icon(Icons.layers_rounded, size: 17),
                text: 'Stack technique',
              ),
              Tab(
                key: ValueKey('tech-stack-tab-implementation'),
                icon: Icon(Icons.code_rounded, size: 17),
                text: 'Implémentation',
              ),
              Tab(
                key: ValueKey('tech-stack-tab-unitTest'),
                icon: Icon(Icons.science_outlined, size: 17),
                text: 'Tests unitaires',
              ),
              Tab(
                key: ValueKey('tech-stack-tab-persistence'),
                icon: Icon(Icons.storage_rounded, size: 17),
                text: 'Persistance',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGeneralTab(theme, colors),
                _buildRoleTab(
                  theme: theme,
                  colors: colors,
                  roleTitle: 'Implémentation',
                  roleSubtitle:
                      'Arborescence et consignes ajoutées en fin des prompts de rôle Implémentation (Modèle Domain, Use Case, Saga).',
                  foldersKey: const ValueKey(
                    'tech-stack-folders-implementation-field',
                  ),
                  foldersController: _implFoldersCtrl,
                  extensionKey: const ValueKey(
                    'tech-stack-ext-implementation-field',
                  ),
                  extensionController: _implExtCtrl,
                ),
                _buildRoleTab(
                  theme: theme,
                  colors: colors,
                  roleTitle: 'Tests unitaires',
                  roleSubtitle:
                      'Arborescence et consignes ajoutées en fin des prompts de rôle Tests unitaires (TDD Domain, Application, Saga).',
                  foldersKey: const ValueKey(
                    'tech-stack-folders-unitTest-field',
                  ),
                  foldersController: _testFoldersCtrl,
                  extensionKey: const ValueKey(
                    'tech-stack-ext-unit-test-field',
                  ),
                  extensionController: _testExtCtrl,
                ),
                _buildRoleTab(
                  theme: theme,
                  colors: colors,
                  roleTitle: 'Persistance',
                  roleSubtitle:
                      'Arborescence et consignes ajoutées en fin des prompts de rôle Persistance (Port sortant Repository, Mapper & Adaptateur).',
                  foldersKey: const ValueKey(
                    'tech-stack-folders-persistence-field',
                  ),
                  foldersController: _persistenceFoldersCtrl,
                  extensionKey: const ValueKey(
                    'tech-stack-ext-persistence-field',
                  ),
                  extensionController: _persistenceExtCtrl,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                if (currentProfile != null)
                  TextButton.icon(
                    key: const ValueKey('tech-stack-delete-btn'),
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    onPressed: _saving ? null : _deleteCurrent,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Supprimer'),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: _feedback == null
                      ? const SizedBox.shrink()
                      : Text(
                          _feedback!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  key: const ValueKey('tech-stack-save-btn'),
                  onPressed: _saving ? null : _saveCurrent,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(
                    _creatingNew
                        ? 'Créer la stack'
                        : 'Enregistrer les modifications',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralTab(ThemeData theme, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Text(
            'Décrivez la stack technique globale (injectée dans tous les rôles) et, si besoin, une structure de dossiers commune de repli.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          Expanded(
            flex: 3,
            child: TextFormField(
              key: const ValueKey('tech-stack-technical-field'),
              controller: _techStackCtrl,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                labelText: 'Stack technique (langage, frameworks, outils)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: TextFormField(
              key: const ValueKey('tech-stack-folders-field'),
              controller: _foldersCtrl,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              decoration: const InputDecoration(
                labelText: 'Structure des dossiers commune (repli optionnel)',
                helperText:
                    'Utilisée uniquement lorsqu’un onglet de rôle n’a pas sa propre structure. Supporte {{domain}}.',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleTab({
    required ThemeData theme,
    required ColorScheme colors,
    required String roleTitle,
    required String roleSubtitle,
    required Key foldersKey,
    required TextEditingController foldersController,
    required Key extensionKey,
    required TextEditingController extensionController,
  }) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            roleSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                Expanded(
                  child: TextFormField(
                    key: foldersKey,
                    controller: foldersController,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Structure des dossiers — $roleTitle',
                      helperText:
                          'Utilisez {{domain}} pour injecter automatiquement le code du domaine.',
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    key: extensionKey,
                    controller: extensionController,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      labelText: 'Consignes spécifiques — $roleTitle',
                      helperText:
                          'Ajoutées en fin de prompt après la structure des dossiers.',
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
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
