import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/material_icon_catalog.dart';
import '../dialogs/editor_dialog.dart';

/// Résultat d'une sélection dans [showMaterialIconPickerDialog].
///
/// Un résultat `null` retourné par le dialogue signifie que l'utilisateur a
/// annulé, tandis qu'un `MaterialIconPickerResult(null)` signifie qu'il a
/// choisi « Aucune icône » (quand `nullable: true`).
@immutable
class MaterialIconPickerResult {
  const MaterialIconPickerResult(this.id);

  final String? id;
}

/// Ouvre une boîte de dialogue permettant de rechercher et filtrer une icône Material.
Future<MaterialIconPickerResult?> showMaterialIconPickerDialog({
  required BuildContext context,
  String? selectedId,
  String title = 'Choisir une icône',
  bool nullable = false,
  String emptyLabel = 'Thème / aucune',
  Iterable<String>? allowedIds,
}) => showEditorDialog<MaterialIconPickerResult>(
  context: context,
  builder: (context) => _MaterialIconPickerDialog(
    selectedId: selectedId,
    title: title,
    nullable: nullable,
    emptyLabel: emptyLabel,
    allowedIds: allowedIds,
  ),
);

/// Champ de formulaire affichant l'icône Material sélectionnée et ouvrant
/// [showMaterialIconPickerDialog] au clic.
class MaterialIconPickerField extends StatelessWidget {
  const MaterialIconPickerField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.nullable = false,
    this.emptyLabel = 'Thème / aucune',
    this.isDense = false,
    this.showId = true,
    this.allowedIds,
    this.dialogTitle,
    super.key,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool nullable;
  final String emptyLabel;
  final bool isDense;
  final bool showId;
  final Iterable<String>? allowedIds;
  final String? dialogTitle;

  Future<void> _openPicker(BuildContext context) async {
    final result = await showMaterialIconPickerDialog(
      context: context,
      selectedId: value,
      title: dialogTitle ?? label,
      nullable: nullable,
      emptyLabel: emptyLabel,
      allowedIds: allowedIds,
    );
    if (result == null) return;
    onChanged(result.id);
  }

  @override
  Widget build(BuildContext context) {
    final entry = MaterialIconCatalog.tryGet(value);
    final scheme = Theme.of(context).colorScheme;
    final hasValue = value != null && value!.trim().isNotEmpty;
    final displayLabel = !hasValue
        ? emptyLabel
        : entry != null
        ? (showId ? '${entry.label} (${entry.id})' : entry.label)
        : value!;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openPicker(context),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: label,
          isDense: isDense,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (nullable && hasValue)
                IconButton(
                  tooltip: 'Aucune icône',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.clear),
                ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.manage_search, size: 20),
              ),
            ],
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasValue
                  ? (entry?.icon ?? Icons.touch_app_outlined)
                  : Icons.block_outlined,
              size: 18,
              color: hasValue ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayLabel,
                overflow: TextOverflow.ellipsis,
                style: hasValue
                    ? null
                    : TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialIconPickerDialog extends StatefulWidget {
  const _MaterialIconPickerDialog({
    required this.selectedId,
    required this.title,
    required this.nullable,
    required this.emptyLabel,
    this.allowedIds,
  });

  final String? selectedId;
  final String title;
  final bool nullable;
  final String emptyLabel;
  final Iterable<String>? allowedIds;

  @override
  State<_MaterialIconPickerDialog> createState() =>
      _MaterialIconPickerDialogState();
}

class _MaterialIconPickerDialogState extends State<_MaterialIconPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  MaterialIconCategory? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MaterialIconCategory> _availableCategories() {
    final allowed = widget.allowedIds?.toSet();
    if (allowed == null) return MaterialIconCategory.values;
    final present = <MaterialIconCategory>{
      for (final entry in MaterialIconCatalog.entries)
        if (allowed.contains(entry.id)) entry.category,
    };
    return [
      for (final category in MaterialIconCategory.values)
        if (present.contains(category)) category,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(640.0, math.max(320.0, screen.width - 64));
    final height = math.min(560.0, math.max(320.0, screen.height - 96));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final query = _searchController.text;
    final categories = _availableCategories();
    final results = MaterialIconCatalog.search(
      query: query,
      category: _selectedCategory,
      allowedIds: widget.allowedIds,
    );

    return AlertDialog(
      key: const ValueKey('material-icon-picker-dialog'),
      insetPadding: const EdgeInsets.all(24),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          const Icon(Icons.interests_outlined, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title,
              style: textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${results.length} icône${results.length > 1 ? 's' : ''}',
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('material-icon-picker-close'),
            tooltip: 'Fermer',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('material-icon-picker-search'),
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Rechercher une icône (ex: ajouter, dossier, mail, search)…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey(
                          'material-icon-picker-clear-search',
                        ),
                        tooltip: 'Effacer la recherche',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(_searchController.clear),
                        icon: const Icon(Icons.clear, size: 18),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  key: const ValueKey('material-icon-category-all'),
                  label: const Text('Toutes'),
                  selected: _selectedCategory == null,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
                for (final category in categories)
                  ChoiceChip(
                    key: ValueKey('material-icon-category-${category.name}'),
                    label: Text(category.label),
                    selected: _selectedCategory == category,
                    visualDensity: VisualDensity.compact,
                    onSelected: (selected) => setState(
                      () => _selectedCategory = selected ? category : null,
                    ),
                  ),
              ],
            ),
            if (widget.nullable) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  key: const ValueKey('material-icon-picker-none'),
                  avatar: Icon(
                    Icons.block_outlined,
                    size: 16,
                    color: widget.selectedId == null
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  label: Text(widget.emptyLabel),
                  backgroundColor: widget.selectedId == null
                      ? scheme.primaryContainer.withValues(alpha: 0.5)
                      : null,
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(const MaterialIconPickerResult(null)),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 40,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Aucune icône ne correspond à « $query ».',
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      key: const ValueKey('material-icon-picker-grid'),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 112,
                            mainAxisExtent: 78,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final item = results[index];
                        final selected = item.id == widget.selectedId?.trim();
                        return _IconTile(
                          entry: item,
                          selected: selected,
                          onTap: () =>
                              Navigator.of(context)
                                  .pop(MaterialIconPickerResult(item.id)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final MaterialIconEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '${entry.label} (${entry.id})',
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('material-icon-option-${entry.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  entry.icon,
                  size: 24,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                ),
                const SizedBox(height: 6),
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
