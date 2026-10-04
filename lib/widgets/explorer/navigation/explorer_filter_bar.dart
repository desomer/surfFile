import 'package:material_ui/material_ui.dart';

import '../../../models/explorer_filter.dart';

/// Barre de filtres (date, type, taille, extension) affichée sous la barre
/// d'outils par l'icône filtre.
class ExplorerFilterBar extends StatefulWidget {
  const ExplorerFilterBar({
    required this.filter,
    required this.onChanged,
    required this.onClose,
    this.shown,
    this.total,
    super.key,
  });

  final ExplorerFilter filter;
  final ValueChanged<ExplorerFilter> onChanged;
  final VoidCallback onClose;

  /// Éléments affichés / présents dans le dossier.
  final int? shown;
  final int? total;

  @override
  State<ExplorerFilterBar> createState() => _ExplorerFilterBarState();
}

class _ExplorerFilterBarState extends State<ExplorerFilterBar> {
  late final _extension = TextEditingController(text: widget.filter.extension);

  @override
  void didUpdateWidget(ExplorerFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filter.extension != _extension.text) {
      _extension.text = widget.filter.extension;
    }
  }

  @override
  void dispose() {
    _extension.dispose();
    super.dispose();
  }

  ExplorerFilter get filter => widget.filter;

  Widget _group(String label, List<Widget> chips) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: chip,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const density = VisualDensity(horizontal: -2, vertical: -3);
    return Container(
      key: const ValueKey('explorer-filter-bar'),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        // La hauteur du contenu : borné par une zone, le Column ne doit pas
        // remplir tout l'espace.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _group('DATE', [
            for (final age in FilterAge.values)
              ChoiceChip(
                key: ValueKey('filter-age-${age.name}'),
                label: Text(age.label),
                visualDensity: density,
                selected: filter.age == age,
                onSelected: (_) => widget.onChanged(filter.copyWith(age: age)),
              ),
          ]),
          _group('TYPE', [
            for (final kind in FileKind.values)
              FilterChip(
                key: ValueKey('filter-kind-${kind.name}'),
                avatar: Icon(kind.icon, size: 16),
                label: Text(kind.label),
                visualDensity: density,
                selected: filter.kinds.contains(kind),
                onSelected: (selected) => widget.onChanged(
                  filter.copyWith(
                    kinds: selected
                        ? {...filter.kinds, kind}
                        : ({...filter.kinds}..remove(kind)),
                  ),
                ),
              ),
          ]),
          _group('TAILLE', [
            for (final size in FilterSize.values)
              ChoiceChip(
                key: ValueKey('filter-size-${size.name}'),
                label: Text(size.label),
                visualDensity: density,
                selected: filter.size == size,
                onSelected: (_) =>
                    widget.onChanged(filter.copyWith(size: size)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    'EXT.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  height: 34,
                  child: TextField(
                    key: const ValueKey('filter-extension'),
                    controller: _extension,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'ex. pdf, docx',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (value) =>
                        widget.onChanged(filter.copyWith(extension: value)),
                  ),
                ),
                const Spacer(),
                if (widget.shown != null && widget.total != null)
                  Text(
                    '${widget.shown} / ${widget.total}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 6),
                TextButton.icon(
                  key: const ValueKey('filter-reset'),
                  onPressed: filter.isActive
                      ? () => widget.onChanged(const ExplorerFilter())
                      : null,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Réinitialiser'),
                ),
                IconButton(
                  tooltip: 'Masquer les filtres',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.expand_less_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
