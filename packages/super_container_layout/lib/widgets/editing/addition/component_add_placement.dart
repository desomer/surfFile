/// Panneau de sélection de la zone, position relative et taille d’insertion.
library;

import 'package:material_ui/material_ui.dart';

import 'component_add_contracts.dart';
import 'component_add_size_fields.dart';
import 'insertion_plan.dart';

/// Panneau de placement recevant les choix et callbacks du wizard.
class ComponentAddPlacementPanel extends StatelessWidget {
  /// Crée le panneau sans déplacer l’état des étapes ni les contrôleurs.
  const ComponentAddPlacementPanel({
    required this.keyPrefix,
    required this.usesRelativePlacements,
    required this.placements,
    required this.selectedPlacement,
    required this.targets,
    required this.target,
    required this.beforeId,
    required this.customSize,
    required this.size,
    required this.onCustomSizeChanged,
    required this.onTargetChanged,
    required this.onBeforeChanged,
    required this.onPlacementSelected,
    required this.onSetHoveredPreview,
    required this.onClearHoveredPreview,
    required this.onSizeChanged,
    super.key,
  });

  /// Préfixe des clés de compatibilité des contrôles d’ajout.
  final String keyPrefix;

  /// Indique si l’étape utilise les placements relatifs aux cibles.
  final bool usesRelativePlacements;

  /// Placements relatifs compatibles avec le candidat.
  final List<ComponentAddPlacement> placements;

  /// Placement relatif courant, s’il en existe un.
  final ComponentAddPlacement? selectedPlacement;

  /// Cibles compatibles avec le candidat.
  final List<ComponentAddTarget> targets;

  /// Cible de zone actuellement choisie.
  final ComponentAddTarget? target;

  /// Identifiant du frère devant lequel insérer, ou `null` pour la fin.
  final String? beforeId;

  /// Indique si le wizard doit appliquer les dimensions personnalisées.
  final bool customSize;

  /// Brouillon de taille dont le propriétaire est le wizard.
  final ComponentAddSizeDraft size;

  /// Signale le changement d’activation de la taille personnalisée.
  final ValueChanged<bool> onCustomSizeChanged;

  /// Signale le changement de cible au wizard.
  final ValueChanged<String?> onTargetChanged;

  /// Signale le changement de position parmi les frères.
  final ValueChanged<String?> onBeforeChanged;

  /// Signale le choix d’un placement relatif.
  final ValueChanged<String> onPlacementSelected;

  /// Active l’aperçu correspondant à l’option survolée.
  final ValueChanged<ComponentAddPlacementPreview?> onSetHoveredPreview;

  /// Efface l’aperçu courant, si celui-ci correspond à l’option survolée.
  final void Function([ComponentAddPlacementPreview? expected])
  onClearHoveredPreview;

  /// Signale au wizard un changement des champs de taille.
  final VoidCallback onSizeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = customSize ? size.error : null;

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );

    return Column(
      key: ValueKey('$keyPrefix-add-placement'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (usesRelativePlacements)
          section('Emplacement', [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _relativePlacements(context),
                ),
              ),
            ),
          ])
        else
          section('Emplacement', [_zonePlacement(context)]),
        section('Taille', [
          SwitchListTile(
            key: ValueKey('$keyPrefix-add-custom-size'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Définir une taille'),
            subtitle: const Text('Sinon, taille par défaut de la zone'),
            value: customSize,
            onChanged: onCustomSizeChanged,
          ),
          if (customSize)
            ComponentAddSizeFields(
              keyPrefix: keyPrefix,
              draft: size,
              onChanged: onSizeChanged,
            ),
        ]),
        if (error != null)
          Text(
            error,
            key: ValueKey('$keyPrefix-add-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
      ],
    );
  }

  Widget _zonePlacement(BuildContext context) {
    final theme = Theme.of(context);
    final currentTarget = target;
    if (currentTarget == null) {
      return Text('Aucune zone disponible.', style: theme.textTheme.bodySmall);
    }
    final endPreview = currentTarget.resolvePreview(null);
    final siblingPreviews = {
      for (final (id, _) in currentTarget.siblings)
        id: currentTarget.resolvePreview(id),
    };
    final targetPreviews = {
      for (final option in targets)
        option.id: option.resolvePreview(
          option.id == currentTarget.id && !option.replaces ? beforeId : null,
        ),
    };
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('$keyPrefix-add-target'),
            initialValue: currentTarget.id,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, labelText: 'Zone'),
            selectedItemBuilder: (_) => [
              for (final option in targets)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(option.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            items: [
              for (final option in targets)
                DropdownMenuItem(
                  value: option.id,
                  onTap: onClearHoveredPreview,
                  child: MouseRegion(
                    hitTestBehavior: HitTestBehavior.opaque,
                    onEnter: (_) =>
                        onSetHoveredPreview(targetPreviews[option.id]),
                    onExit: (_) =>
                        onClearHoveredPreview(targetPreviews[option.id]),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(option.label),
                    ),
                  ),
                ),
            ],
            onChanged: onTargetChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: currentTarget.replaces
              ? MouseRegion(
                  onEnter: (_) => onSetHoveredPreview(endPreview),
                  onExit: (_) => onClearHoveredPreview(endPreview),
                  child: Text(
                    currentTarget.siblings.isEmpty
                        ? 'Composant unique'
                        : 'Remplace le contenu actuel',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : DropdownButtonFormField<String?>(
                  key: ValueKey('$keyPrefix-add-position-${currentTarget.id}'),
                  initialValue: beforeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Position',
                  ),
                  selectedItemBuilder: (_) => [
                    for (final (_, label) in currentTarget.siblings)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Avant $label',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('À la fin'),
                    ),
                  ],
                  items: [
                    for (final (id, label) in currentTarget.siblings)
                      DropdownMenuItem(
                        value: id,
                        onTap: onClearHoveredPreview,
                        child: MouseRegion(
                          hitTestBehavior: HitTestBehavior.opaque,
                          onEnter: (_) =>
                              onSetHoveredPreview(siblingPreviews[id]),
                          onExit: (_) =>
                              onClearHoveredPreview(siblingPreviews[id]),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Avant $label',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    DropdownMenuItem<String?>(
                      value: null,
                      onTap: onClearHoveredPreview,
                      child: MouseRegion(
                        hitTestBehavior: HitTestBehavior.opaque,
                        onEnter: (_) => onSetHoveredPreview(endPreview),
                        onExit: (_) => onClearHoveredPreview(endPreview),
                        child: const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('À la fin'),
                        ),
                      ),
                    ),
                  ],
                  onChanged: onBeforeChanged,
                ),
        ),
      ],
    );
  }

  List<Widget> _relativePlacements(BuildContext context) {
    final theme = Theme.of(context);
    final selected = selectedPlacement;
    final groups = <(String, List<ComponentAddPlacement>)>[];
    for (final option in placements) {
      if (groups.lastOrNull case (final group, final options)
          when group == option.group) {
        options.add(option);
      } else {
        groups.add((option.group, [option]));
      }
    }
    return [
      for (final (group, options) in groups) ...[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(group, style: theme.textTheme.labelLarge),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in options)
              MouseRegion(
                onEnter: (_) => onSetHoveredPreview(option.preview),
                onExit: (_) => onClearHoveredPreview(option.preview),
                child: Tooltip(
                  message: option.hint ?? option.label,
                  child: ChoiceChip(
                    key: ValueKey('$keyPrefix-add-placement-${option.id}'),
                    avatar: Icon(option.icon, size: 16),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(option.label),
                    selected: selected?.id == option.id,
                    onSelected: (_) => onPlacementSelected(option.id),
                  ),
                ),
              ),
          ],
        ),
      ],
      if (selected?.hint case final hint?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            hint,
            key: ValueKey('$keyPrefix-add-placement-hint'),
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }
}
