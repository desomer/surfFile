/// Atelier structuré de l'étape 1 : Lexique métier / Ubiquitous Language ([LexiconEditorView]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../models/company_glossary.dart';
import '../../models/spec_forge_project.dart';
import '../../models/spec_lexicon.dart';
import '../../services/spec_forge_controller.dart';

/// Vue structurée et éditable du lexique métier ([SpecLexicon]).
class LexiconEditorView extends StatefulWidget {
  /// Crée la vue connectée au [controller].
  const LexiconEditorView({required this.controller, super.key});

  /// Contrôleur principal.
  final SpecForgeController controller;

  @override
  State<LexiconEditorView> createState() => _LexiconEditorViewState();
}

class _LexiconEditorViewState extends State<LexiconEditorView> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();
    final lexicon = project.lexicon;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final query = _search.trim().toLowerCase();
    final filteredTerms = query.isEmpty
        ? lexicon.terms
        : lexicon.terms.where((t) {
            return t.term.toLowerCase().contains(query) ||
                t.definition.toLowerCase().contains(query) ||
                t.domain.toLowerCase().contains(query) ||
                t.synonyms.any((s) => s.toLowerCase().contains(query));
          }).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lexique métier (${lexicon.terms.length})',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Vocabulaire canonique partagé entre cadrage, cahier des charges, objets et règles.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('spec-lexicon-import-company-glossary'),
                  onPressed: () => _importFromCompanyGlossary(context, project),
                  icon: const Icon(Icons.language_rounded, size: 16),
                  label: const Text('Importer glossaire d’entreprise'),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('spec-lexicon-add-term'),
                  onPressed: () => _editTermDialog(context, project),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Nouveau terme'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Filtrer un terme, synonyme ou domaine…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 14),
        if (filteredTerms.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                lexicon.terms.isEmpty
                    ? 'Aucun terme défini pour le moment.\nDiscutez avec l’agent Ubiquitous Language Expert à gauche ou cliquez sur « Nouveau terme ».'
                    : 'Aucun terme ne correspond à « $_search ».',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final term in filteredTerms)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
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
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                term.term,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (term.domain.isNotEmpty)
                                Chip(
                                  label: Text(term.domain),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: ValueKey('spec-lexicon-promote-${term.id}'),
                          tooltip: 'Promouvoir vers le glossaire d’entreprise',
                          icon: const Icon(Icons.publish_rounded, size: 18),
                          onPressed: () async {
                            final res = await widget.controller
                                .promoteLexiconTermToCompanyGlossary(term);
                            if (!context.mounted) return;
                            ScaffoldMessenger.maybeOf(context)
                              ?..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    res.created
                                        ? '« ${term.term} » ajouté au glossaire d’entreprise.'
                                        : '« ${term.term} » mis à jour dans le glossaire d’entreprise.',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () =>
                              _editTermDialog(context, project, existing: term),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          onPressed: () {
                            final next = lexicon.terms
                                .where((t) => t.id != term.id)
                                .toList();
                            widget.controller.updateProject(
                              project.copyWith(
                                lexicon: lexicon.copyWith(terms: next),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    if (term.definition.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(term.definition),
                    ],
                    if (term.synonyms.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Synonymes unifiés :',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          for (final s in term.synonyms)
                            Chip(
                              label: Text(s),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                    if (term.examples.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final ex in term.examples)
                        Text(
                          '• $ex',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StringListCard(
                title: 'Conventions & unités (${lexicon.conventions.length})',
                items: lexicon.conventions,
                emptyText: 'Aucune convention.',
                onAdd: () => _addStringItem(
                  context,
                  title: 'Nouvelle convention',
                  onSave: (val) => widget.controller.updateProject(
                    project.copyWith(
                      lexicon: lexicon.copyWith(
                        conventions: [...lexicon.conventions, val],
                      ),
                    ),
                  ),
                ),
                onRemove: (idx) {
                  final next = List<String>.from(lexicon.conventions)
                    ..removeAt(idx);
                  widget.controller.updateProject(
                    project.copyWith(
                      lexicon: lexicon.copyWith(conventions: next),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _StringListCard(
                title: 'Ambiguïtés levées (${lexicon.ambiguousTerms.length})',
                items: lexicon.ambiguousTerms,
                emptyText: 'Aucune ambiguïté enregistrée.',
                onAdd: () => _addStringItem(
                  context,
                  title: 'Nouveau point d’ambiguïté',
                  onSave: (val) => widget.controller.updateProject(
                    project.copyWith(
                      lexicon: lexicon.copyWith(
                        ambiguousTerms: [...lexicon.ambiguousTerms, val],
                      ),
                    ),
                  ),
                ),
                onRemove: (idx) {
                  final next = List<String>.from(lexicon.ambiguousTerms)
                    ..removeAt(idx);
                  widget.controller.updateProject(
                    project.copyWith(
                      lexicon: lexicon.copyWith(ambiguousTerms: next),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _importFromCompanyGlossary(
    BuildContext context,
    SpecForgeProject project,
  ) async {
    final glossary = widget.controller.companyGlossary;
    if (glossary.terms.isEmpty && glossary.conventions.isEmpty) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Le glossaire d’entreprise est vide. Ajoutez des termes depuis l’onglet Design.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final existingNames = {
      for (final t in project.lexicon.terms) t.term.trim().toLowerCase(),
    };
    final selectedIds = <String>{
      for (final t in glossary.terms)
        if (t.status != CompanyGlossaryStatus.deprecated &&
            !existingNames.contains(t.term.trim().toLowerCase()))
          t.id,
    };
    var overwriteExisting = false;
    var includeConventions = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Importer depuis le glossaire d’entreprise'),
          content: SizedBox(
            width: 520,
            height: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cochez les termes d’entreprise à intégrer dans le lexique de « ${project.name} » :',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final t in glossary.terms)
                        CheckboxListTile(
                          dense: true,
                          value: selectedIds.contains(t.id),
                          title: Text(
                            '${t.term} (${t.status.label})'
                            '${existingNames.contains(t.term.trim().toLowerCase()) ? ' — déjà dans le projet' : ''}',
                          ),
                          subtitle: t.definition.isNotEmpty
                              ? Text(
                                  t.definition,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked == true) {
                                selectedIds.add(t.id);
                              } else {
                                selectedIds.remove(t.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
                const Divider(height: 12),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: overwriteExisting,
                  title: const Text('Mettre à jour les termes déjà présents'),
                  onChanged: (v) =>
                      setDialogState(() => overwriteExisting = v ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: includeConventions,
                  title: const Text('Importer aussi les conventions d’entreprise'),
                  onChanged: (v) =>
                      setDialogState(() => includeConventions = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('spec-lexicon-confirm-company-import'),
              onPressed: selectedIds.isEmpty && !includeConventions
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text('Importer (${selectedIds.length})'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final res = await widget.controller.importCompanyGlossaryToProject(
      termIds: selectedIds.toList(),
      overwriteExisting: overwriteExisting,
      includeConventions: includeConventions,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Lexique mis à jour : +${res.added} terme(s), ${res.updated} mis à jour.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _addStringItem(
    BuildContext context, {
    required String title,
    required ValueChanged<String> onSave,
  }) async {
    final textCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (ok == true && textCtrl.text.trim().isNotEmpty) {
      onSave(textCtrl.text.trim());
    }
    textCtrl.dispose();
  }

  Future<void> _editTermDialog(
    BuildContext context,
    SpecForgeProject project, {
    LexiconTerm? existing,
  }) async {
    final termCtrl = TextEditingController(text: existing?.term ?? '');
    final domainCtrl = TextEditingController(text: existing?.domain ?? '');
    final defCtrl = TextEditingController(text: existing?.definition ?? '');
    final synCtrl = TextEditingController(
      text: existing?.synonyms.join(', ') ?? '',
    );
    final exCtrl = TextEditingController(
      text: existing?.examples.join('\n') ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          existing == null ? 'Nouveau terme métier' : 'Modifier ${existing.term}',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: termCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Terme canonique *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: domainCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Domaine (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: defCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Définition métier',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: synCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Synonymes à unifier (séparés par virgule)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: exCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Exemples (un par ligne)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (saved == true && termCtrl.text.trim().isNotEmpty) {
      final item = LexiconTerm(
        id: existing?.id ?? 'term_${shortid.generate()}',
        term: termCtrl.text.trim(),
        domain: domainCtrl.text.trim(),
        definition: defCtrl.text.trim(),
        synonyms: synCtrl.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        examples: exCtrl.text
            .split(RegExp(r'[\r\n]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      );
      final list = List<LexiconTerm>.from(project.lexicon.terms);
      final idx = list.indexWhere((t) => t.id == item.id);
      if (idx >= 0) {
        list[idx] = item;
      } else {
        list.add(item);
      }
      await widget.controller.updateProject(
        project.copyWith(lexicon: project.lexicon.copyWith(terms: list)),
      );
    }

    termCtrl.dispose();
    domainCtrl.dispose();
    defCtrl.dispose();
    synCtrl.dispose();
    exCtrl.dispose();
  }
}

class _StringListCard extends StatelessWidget {
  const _StringListCard({
    required this.title,
    required this.items,
    required this.emptyText,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<String> items;
  final String emptyText;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: onAdd,
                ),
              ],
            ),
            if (items.isEmpty)
              Text(
                emptyText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              for (var i = 0; i < items.length; i++)
                Row(
                  children: [
                    const Text('• '),
                    Expanded(child: Text(items[i])),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => onRemove(i),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}
