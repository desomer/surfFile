/// Panneau de recherche, filtrage, prévisualisation et sélection des composants.
library;

import 'package:material_ui/material_ui.dart';

import 'component_add_contracts.dart';

/// Panneau de choix des composants proposés par le wizard.
class ComponentAddChoicePanel extends StatelessWidget {
  /// Crée le panneau et délègue ses changements au propriétaire du wizard.
  const ComponentAddChoicePanel({
    required this.keyPrefix,
    required this.candidates,
    required this.selected,
    required this.selectedFamily,
    required this.query,
    required this.emptyMessage,
    required this.onQueryChanged,
    required this.onFamilySelected,
    required this.onSelect,
    required this.onAddDirectly,
    super.key,
  });

  /// Préfixe des clés de compatibilité des contrôles d’ajout.
  final String keyPrefix;

  /// Candidats compatibles avec la cible courante.
  final List<ComponentAddCandidate> candidates;

  /// Candidat choisi dans l’étape.
  final ComponentAddCandidate? selected;

  /// Famille actuellement sélectionnée, ou `null` pour toutes.
  final ComponentAddFamily? selectedFamily;

  /// Texte courant de recherche.
  final String query;

  /// Message présenté lorsque la cible ne propose aucun candidat.
  final String emptyMessage;

  /// Signale une nouvelle recherche au wizard.
  final ValueChanged<String> onQueryChanged;

  /// Signale une nouvelle famille au wizard.
  final ValueChanged<ComponentAddFamily?> onFamilySelected;

  /// Signale le choix d’un candidat.
  final ValueChanged<ComponentAddCandidate> onSelect;

  /// Signale la demande d’ajout direct d’un candidat.
  final ValueChanged<ComponentAddCandidate> onAddDirectly;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final candidatesInOrder = candidates.indexed.toList()
      ..sort((a, b) {
        final familyOrder = a.$2.family.index.compareTo(b.$2.family.index);
        if (familyOrder != 0) return familyOrder;
        final order = a.$2.addOrder.compareTo(b.$2.addOrder);
        if (order != 0) return order;
        return a.$1.compareTo(b.$1);
      });
    final offered = [for (final (_, candidate) in candidatesInOrder) candidate];
    final families = [
      for (final family in ComponentAddFamily.values)
        if (offered.any((candidate) => candidate.family == family)) family,
    ];
    final familyFiltered = selectedFamily == null
        ? offered
        : [
            for (final candidate in offered)
              if (candidate.family == selectedFamily) candidate,
          ];
    final visible = [
      for (final candidate in familyFiltered)
        if (normalizedQuery.isEmpty ||
            candidate.label.toLowerCase().contains(normalizedQuery) ||
            candidate.family.label.toLowerCase().contains(normalizedQuery) ||
            candidate.tags.any(
              (tag) => tag.toLowerCase().contains(normalizedQuery),
            ))
          candidate,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(emptyMessage),
          )
        else ...[
          TextField(
            key: ValueKey('$keyPrefix-add-search'),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher un composant ou un tag',
            ),
            onChanged: onQueryChanged,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ChoiceChip(
                key: ValueKey('$keyPrefix-add-family-all'),
                label: const Text('Tous'),
                selected: selectedFamily == null,
                onSelected: (_) => onFamilySelected(null),
              ),
              for (final family in families)
                ChoiceChip(
                  key: ValueKey('$keyPrefix-add-family-${family.name}'),
                  label: Text(family.label),
                  selected: selectedFamily == family,
                  onSelected: (value) =>
                      onFamilySelected(value ? family : null),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Aucun composant ne correspond à la recherche.'),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final candidate in visible)
                _ComponentCard(
                  keyPrefix: keyPrefix,
                  candidate: candidate,
                  selected: selected?.id == candidate.id,
                  onTap: () => onSelect(candidate),
                  onAdd: () => onAddDirectly(candidate),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Prévisualisation du composant sélectionné dans l’étape de choix.
class ComponentAddPreview extends StatelessWidget {
  /// Crée une prévisualisation avec la clé historique du wizard.
  const ComponentAddPreview({
    required this.keyPrefix,
    required this.candidate,
    super.key,
  });

  /// Préfixe des clés de compatibilité du wizard.
  final String keyPrefix;

  /// Candidat dont le constructeur de prévisualisation sera exécuté.
  final ComponentAddCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      key: ValueKey('$keyPrefix-add-preview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Aperçu : ${candidate.label}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: Center(
              child: SingleChildScrollView(
                child: Builder(builder: candidate.previewBuilder!),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComponentCard extends StatelessWidget {
  const _ComponentCard({
    required this.keyPrefix,
    required this.candidate,
    required this.selected,
    required this.onTap,
    required this.onAdd,
  });

  final String keyPrefix;
  final ComponentAddCandidate candidate;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  IconData get _icon {
    final tags = candidate.tags;
    if (tags.contains('text') || tags.contains('input')) {
      return Icons.text_fields;
    }
    if (tags.contains('list')) return Icons.view_list_outlined;
    if (tags.contains('layout')) return Icons.dashboard_outlined;
    if (tags.contains('container')) return Icons.crop_square;
    if (tags.contains('appBar')) return Icons.web_asset;
    if (tags.contains('bottomNavigationBar')) return Icons.view_week_outlined;
    return Icons.widgets_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final details = [
      candidate.family.label,
      ...candidate.tags.map((tag) => '#$tag'),
    ].join(' · ');
    return SizedBox(
      width: 240,
      child: Card(
        key: ValueKey('$keyPrefix-add-card-${candidate.id}'),
        margin: EdgeInsets.zero,
        elevation: 0,
        color: selected ? colors.primaryContainer : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
            child: Row(
              children: [
                Icon(_icon, size: 18, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        candidate.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('$keyPrefix-add-slot-${candidate.id}'),
                  tooltip: 'Ajouter directement',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.bolt),
                  onPressed: onAdd,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
