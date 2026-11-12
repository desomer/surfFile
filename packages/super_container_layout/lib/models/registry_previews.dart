// Aperçus visuels des composants du [Registry] affichés dans l'assistant d'ajout.
part of 'registry.dart';

BoxDecoration _previewBoxDecoration(
  ColorScheme colors, {
  Color? color,
  Color? borderColor,
  double radius = 8,
  List<BoxShadow>? boxShadow,
}) => BoxDecoration(
  color: color ?? colors.surfaceContainerLow,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: borderColor ?? colors.outlineVariant),
  boxShadow: boxShadow,
);

Widget _previewZoneBox(
  BuildContext context,
  String label, {
  bool highlighted = false,
}) {
  final colors = Theme.of(context).colorScheme;
  return Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: _previewBoxDecoration(
      colors,
      color: highlighted ? colors.primaryContainer : colors.surfaceContainerLow,
      borderColor: highlighted ? colors.primary : colors.outlineVariant,
      radius: 6,
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
        color: highlighted
            ? colors.onPrimaryContainer
            : colors.onSurfaceVariant,
      ),
    ),
  );
}

Widget _buildLayoutPreview(BuildContext context) => IgnorePointer(
  child: SizedBox(
    height: 92,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _previewZoneBox(context, 'Nord'),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _previewZoneBox(context, 'Ouest')),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: _previewZoneBox(context, 'Centre', highlighted: true),
              ),
              const SizedBox(width: 4),
              Expanded(child: _previewZoneBox(context, 'Est')),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _previewZoneBox(context, 'Sud'),
      ],
    ),
  ),
);

Widget _buildValuePreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Texte affiché', style: theme.textTheme.bodyMedium),
        SizedBox(
          width: 180,
          child: InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Champ de saisie',
              border: OutlineInputBorder(),
            ),
            child: Text(
              'Valeur…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: true, onChanged: (_) {}),
            Switch(value: true, onChanged: (_) {}),
          ],
        ),
      ],
    ),
  );
}

Widget _buildActionPreview(BuildContext context) => IgnorePointer(
  child: Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilledButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.play_arrow, size: 16),
        label: const Text('Action principale'),
      ),
      OutlinedButton(onPressed: () {}, child: const Text('Secondaire')),
      IconButton.filledTonal(
        onPressed: () {},
        icon: const Icon(Icons.bolt, size: 18),
      ),
    ],
  ),
);

Widget _buildIndicatorPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return IgnorePointer(
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 22,
          color: Colors.green.shade600,
        ),
        Icon(
          Icons.warning_amber_rounded,
          size: 22,
          color: Colors.orange.shade700,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: colors.onSecondaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                'Statut',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildSeparatorPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return IgnorePointer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: colors.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Section',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: Divider(color: colors.outlineVariant)),
          ],
        ),
        const SizedBox(height: 6),
        Divider(color: colors.outlineVariant),
      ],
    ),
  );
}

Widget _buildCardPreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: _previewBoxDecoration(
        colors,
        color: colors.surface,
        radius: 12,
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.crop_square, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Card', style: theme.textTheme.titleSmall),
                Text(
                  'Surface stylable (couleur, bordure, rayon, marges)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
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

Widget _buildApplicationBarPreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _previewBoxDecoration(
        colors,
        color: colors.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Icon(Icons.menu, size: 18, color: colors.onSurface),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Barre d’application',
              style: theme.textTheme.titleSmall,
            ),
          ),
          Icon(Icons.search, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Icon(Icons.more_vert, size: 18, color: colors.onSurfaceVariant),
        ],
      ),
    ),
  );
}

Widget _buildBottomNavigationBarPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget item(IconData icon, String label, {bool selected = false}) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? colors.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 16,
            color: selected
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? colors.onSurface : colors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
  return IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: _previewBoxDecoration(colors, color: colors.surfaceContainer),
      child: Row(
        children: [
          item(Icons.home_outlined, 'Accueil', selected: true),
          item(Icons.search_outlined, 'Recherche'),
          item(Icons.person_outline, 'Profil'),
        ],
      ),
    ),
  );
}

Widget _buildBottomAppBarPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return IgnorePointer(
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _previewBoxDecoration(colors, color: colors.surfaceContainer),
      child: Row(
        children: [
          Icon(Icons.menu, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Icon(Icons.search, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Icon(Icons.favorite_border, size: 18, color: colors.onSurfaceVariant),
          const Spacer(),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.add, size: 16, color: colors.onPrimaryContainer),
          ),
        ],
      ),
    ),
  );
}

Widget _buildNavigationRailPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return IgnorePointer(
    child: SizedBox(
      height: 84,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: _previewBoxDecoration(
              colors,
              color: colors.surfaceContainer,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: colors.onSecondaryContainer,
                  ),
                ),
                Icon(
                  Icons.analytics_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _previewZoneBox(context, 'Contenu de la destination'),
          ),
        ],
      ),
    ),
  );
}

Widget _buildExpansiblePreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Container(
      decoration: _previewBoxDecoration(colors, color: colors.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'En-tête repliable',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Icon(
                  Icons.expand_less,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _previewZoneBox(context, 'Contenu déplié'),
          ),
        ],
      ),
    ),
  );
}

Widget _buildMenuPreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Row(
      children: [
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.menu_open_outlined, size: 16),
          label: const Text('Menu'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: _previewBoxDecoration(
              colors,
              color: colors.surfaceContainerHigh,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('• Option 1', style: theme.textTheme.bodySmall),
                Text('• Option 2', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildTabPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget tab(String title, {bool selected = false}) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
    ),
  );
  return IgnorePointer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            tab('Onglet 1', selected: true),
            tab('Onglet 2'),
            tab('Onglet 3'),
          ],
        ),
        const SizedBox(height: 6),
        _previewZoneBox(
          context,
          'Contenu de l’onglet actif',
          highlighted: true,
        ),
      ],
    ),
  );
}

Widget _buildConditionalPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget chip(String title, {bool selected = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: selected ? colors.primaryContainer : colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: selected ? colors.primary : colors.outlineVariant,
      ),
    ),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 10,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? colors.onPrimaryContainer : colors.onSurfaceVariant,
      ),
    ),
  );
  return IgnorePointer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.call_split_outlined, size: 15, color: colors.primary),
            const SizedBox(width: 6),
            chip('string', selected: true),
            const SizedBox(width: 4),
            chip('number'),
            const SizedBox(width: 4),
            chip('default'),
          ],
        ),
        const SizedBox(height: 6),
        _previewZoneBox(
          context,
          'Contenu du cas actif (selon binding)',
          highlighted: true,
        ),
      ],
    ),
  );
}

Widget _buildIterableContentPreview(BuildContext context) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return IgnorePointer(
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: _previewBoxDecoration(
        colors,
        color: colors.surface,
        borderColor: colors.primary.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.repeat, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Modèle d’élément répété (ligne / carte de liste)',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildListViewPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget row(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: _previewBoxDecoration(colors, radius: 6),
    child: Row(
      children: [
        Icon(Icons.drag_handle, size: 14, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
  return IgnorePointer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row('Élément de liste 1'),
        const SizedBox(height: 4),
        row('Élément de liste 2'),
        const SizedBox(height: 4),
        row('Élément de liste 3'),
      ],
    ),
  );
}

Widget _buildTreeViewPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget nodeRow(String header, String data, {int depth = 0}) => Padding(
    padding: EdgeInsets.only(left: depth * 16.0),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: _previewBoxDecoration(colors, radius: 6),
      child: Row(
        children: [
          Icon(
            depth == 0 ? Icons.arrow_drop_down : Icons.subdirectory_arrow_right,
            size: 14,
            color: colors.primary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              header,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            width: 1,
            height: 12,
            color: colors.outlineVariant,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          Expanded(child: Text(data, style: const TextStyle(fontSize: 11))),
        ],
      ),
    ),
  );
  return IgnorePointer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        nodeRow('Header (Parent)', 'Data'),
        const SizedBox(height: 4),
        nodeRow('Header (Enfant)', 'Data', depth: 1),
      ],
    ),
  );
}

Widget _buildTablePreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget tableRow(List<String> cells, {bool header = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: _previewBoxDecoration(
      colors,
      color: header
          ? colors.surfaceContainerHighest
          : colors.surfaceContainerLow,
      radius: 4,
    ),
    child: Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 12,
              color: colors.outlineVariant,
              margin: const EdgeInsets.symmetric(horizontal: 6),
            ),
          Expanded(
            child: Text(
              cells[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: header ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    ),
  );
  return IgnorePointer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        tableRow(const ['Col 1', 'Col 2', 'Col 3'], header: true),
        const SizedBox(height: 3),
        tableRow(const ['Val A1', 'Val A2', 'Val A3']),
        const SizedBox(height: 3),
        tableRow(const ['Val B1', 'Val B2', 'Val B3']),
      ],
    ),
  );
}
