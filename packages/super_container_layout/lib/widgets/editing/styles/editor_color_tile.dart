/// Sélecteur de couleur partagé des éditeurs : panneau repliable, couleurs
/// personnalisées et références réactives aux rôles Material 3 du thème.
library;

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/json_syntax.dart';
import '../../../theme/theme_color.dart';

/// Édite une couleur fixe ou un rôle sémantique du thème courant.
class EditorColorTile extends StatefulWidget {
  /// Crée le sélecteur commun aux styles et aux propriétés de composants.
  const EditorColorTile({
    required this.label,
    required this.color,
    required this.onChanged,
    this.tileKey,
    this.dense = false,
    this.onClear,
    super.key,
  });

  /// Libellé de la propriété.
  final String label;

  /// Valeur persistée, éventuellement une référence [ThemeColor].
  final Color color;

  /// Reçoit la valeur fixe ou la référence, jamais un instantané implicite.
  final ValueChanged<Color> onChanged;

  /// Clé historique du panneau repliable.
  final Key? tileKey;

  /// Réduit les espacements pour les panneaux de propriétés.
  final bool dense;

  /// Restaure l'héritage du thème ou du parent.
  final VoidCallback? onClear;

  @override
  State<EditorColorTile> createState() => _EditorColorTileState();
}

class _EditorColorTileState extends State<EditorColorTile> {
  late bool _themeMode = widget.color is ThemeColor;
  final _search = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(EditorColorTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color != oldWidget.color) {
      _themeMode = widget.color is ThemeColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reference = widget.color;
    final tileKey = widget.tileKey;
    final role = reference is ThemeColor ? reference.role : null;
    final resolved = resolveThemeColor(reference, scheme);
    final radius = BorderRadius.circular(12);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.dense ? 3 : 6),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: widget.tileKey,
          onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
          shape: const Border(),
          collapsedShape: const Border(),
          dense: widget.dense,
          tilePadding: EdgeInsets.symmetric(
            horizontal: widget.dense ? 12 : 16,
            vertical: 4,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: _ColorSwatch(color: resolved, size: widget.dense ? 30 : 36),
          title: Text(
            widget.label,
            style: theme.textTheme.labelLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            role == null ? JsonColor.toHex(resolved) : 'ColorScheme.${role.name}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: role == null ? scheme.onSurfaceVariant : scheme.primary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onClear != null)
                IconButton(
                  key: tileKey is ValueKey
                      ? ValueKey('${tileKey.value}-clear')
                      : ValueKey('clear-color-${widget.label}'),
                  tooltip: 'Retirer la couleur',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: widget.onClear,
                  icon: const Icon(Icons.format_color_reset_outlined),
                ),
              AnimatedRotation(
                turns: _expanded ? .5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more),
              ),
            ],
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.palette_outlined, size: 18),
                    label: Text('Thème'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.colorize, size: 18),
                    label: Text('Personnalisée'),
                  ),
                ],
                selected: {_themeMode},
                onSelectionChanged: (selection) {
                  final themeMode = selection.single;
                  setState(() => _themeMode = themeMode);
                  if (!themeMode && role != null) widget.onChanged(resolved);
                },
              ),
            ),
            const SizedBox(height: 12),
            if (_themeMode)
              _buildThemeRoles(context, role)
            else
              ColorPicker(
                color: resolved,
                onColorChanged: widget.onChanged,
                enableOpacity: true,
                showColorCode: true,
                showEditIconButton: true,
                opacitySubheading: const Text('Opacité'),
                padding: EdgeInsets.zero,
                width: 28,
                height: 28,
                wheelDiameter: 180,
                pickersEnabled: const {
                  ColorPickerType.both: true,
                  ColorPickerType.primary: false,
                  ColorPickerType.accent: false,
                  ColorPickerType.wheel: true,
                },
                pickerTypeLabels: const {
                  ColorPickerType.both: 'Palette',
                  ColorPickerType.wheel: 'Roue',
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeRoles(BuildContext context, ThemeColorRole? selected) {
    final scheme = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final roles = ThemeColorRole.values.where(
      (role) =>
          '${role.name} ${role.group} ${role.description}'
              .toLowerCase()
              .contains(query),
    ).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ces couleurs suivent automatiquement le thème actif.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            hintText: 'Rechercher un rôle…',
            prefixIcon: Icon(Icons.search, size: 20),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (roles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Aucun rôle correspondant.'),
          )
        else
          SizedBox(
            height: 280,
            child: ListView.builder(
              primary: false,
              itemCount: roles.length,
              itemBuilder: (context, index) {
                final role = roles[index];
                final showGroup = index == 0 || roles[index - 1].group != role.group;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showGroup)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                        child: Text(
                          role.group,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ListTile(
                      key: ValueKey('theme-color-${role.name}'),
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      selected: selected == role,
                      selectedTileColor: scheme.secondaryContainer,
                      selectedColor: scheme.onSecondaryContainer,
                      leading: _ColorSwatch(color: role.resolve(scheme), size: 28),
                      title: Text(role.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(role.description),
                      trailing: selected == role
                          ? const Icon(Icons.check_circle_outline, size: 20)
                          : null,
                      onTap: () => widget.onChanged(ThemeColor(role)),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
}
