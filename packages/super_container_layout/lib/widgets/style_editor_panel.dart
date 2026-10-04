import 'package:material_ui/material_ui.dart';

/// Groupe de propriétés d'un éditeur de style : une carte au centre et une
/// entrée dans la liste de gauche.
class StyleEditorSection {
  const StyleEditorSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.child,
    this.tag = '',
    this.count,
    this.half = false,
  });

  final String id;
  final String title;
  final IconData icon;
  final Widget child;

  /// Propriété Flutter correspondante, affichée en petit à droite du titre.
  final String tag;

  /// Nombre de réglages, affiché dans la liste de gauche.
  final int? count;

  /// Deux sections `half` consécutives partagent une ligne.
  final bool half;
}

/// Éditeur en trois zones : liste des groupes, cartes de réglages et
/// prévisualisation. En dessous de [wideBreakpoint], la liste devient une
/// rangée de puces et la prévisualisation passe au-dessus des cartes.
class StyleEditorPanel extends StatefulWidget {
  const StyleEditorPanel({
    required this.sections,
    required this.preview,
    this.onReset,
    super.key,
  });

  final List<StyleEditorSection> sections;
  final Widget preview;
  final VoidCallback? onReset;

  static const wideBreakpoint = 860.0;
  static const sidebarWidth = 190.0;
  static const previewWidth = 300.0;

  @override
  State<StyleEditorPanel> createState() => _StyleEditorPanelState();
}

class _StyleEditorPanelState extends State<StyleEditorPanel> {
  final _keys = <String, GlobalKey>{};
  String? _current;

  GlobalKey _key(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  String get _selected =>
      _current ?? (widget.sections.isEmpty ? '' : widget.sections.first.id);

  void _go(String id) {
    setState(() => _current = id);
    final context = _key(id).currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  /// Met en évidence la dernière section dont le haut a atteint la zone
  /// visible.
  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final viewport = notification.context?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return false;
    String? current;
    for (final section in widget.sections) {
      final box = _keys[section.id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top <= 24 || current == null) current = section.id;
    }
    if (current != null && current != _current) {
      setState(() => _current = current);
    }
    return false;
  }

  List<Widget> _rows(bool paired) {
    final rows = <Widget>[];
    final sections = widget.sections;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final next = i + 1 < sections.length ? sections[i + 1] : null;
      if (paired && section.half && next != null && next.half) {
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _card(section)),
              const SizedBox(width: 12),
              Expanded(child: _card(next)),
            ],
          ),
        );
        i++;
      } else {
        rows.add(_card(section));
      }
      rows.add(const SizedBox(height: 12));
    }
    return rows;
  }

  Widget _card(StyleEditorSection section) =>
      _StyleCard(key: _key(section.id), section: section);

  Widget _cards({required bool wide}) => LayoutBuilder(
    builder: (context, constraints) => NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(right: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!wide) ...[widget.preview, const SizedBox(height: 12)],
            ..._rows(constraints.maxWidth >= 520),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= StyleEditorPanel.wideBreakpoint;
      if (!wide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Chips(
              sections: widget.sections,
              selected: _selected,
              onSelected: _go,
              onReset: widget.onReset,
            ),
            const SizedBox(height: 8),
            Expanded(child: _cards(wide: false)),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: StyleEditorPanel.sidebarWidth,
            child: _Sidebar(
              sections: widget.sections,
              selected: _selected,
              onSelected: _go,
              onReset: widget.onReset,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: _cards(wide: true)),
          const SizedBox(width: 16),
          SizedBox(
            width: StyleEditorPanel.previewWidth,
            child: SingleChildScrollView(child: widget.preview),
          ),
        ],
      );
    },
  );
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({required this.section, super.key});

  final StyleEditorSection section;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey('style-card-${section.id}'),
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  flex: 3,
                  child: Text(
                    section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                if (section.tag.isNotEmpty)
                  Flexible(
                    flex: 2,
                    child: Text(
                      section.tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11,
                        color: scheme.onSurfaceVariant.withValues(alpha: .7),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            section.child,
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.sections,
    required this.selected,
    required this.onSelected,
    required this.onReset,
  });

  final List<StyleEditorSection> sections;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            'PROPRIÉTÉS',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: .8,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final section in sections)
                _SidebarItem(
                  section: section,
                  selected: section.id == selected,
                  onTap: () => onSelected(section.id),
                ),
            ],
          ),
        ),
        Divider(color: scheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Du visuel au code',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Text(
            'Chaque réglage correspond à une propriété du style.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ),
        if (onReset != null)
          TextButton(
            onPressed: onReset,
            child: const Text('Réinitialiser ce style'),
          ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final StyleEditorSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        key: ValueKey('style-nav-${section.id}'),
        color: selected
            ? scheme.primaryContainer.withValues(alpha: .6)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(section.icon, size: 16, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: selected ? scheme.primary : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (section.count != null)
                  Text(
                    '${section.count}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: .7),
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

class _Chips extends StatelessWidget {
  const _Chips({
    required this.sections,
    required this.selected,
    required this.onSelected,
    required this.onReset,
  });

  final List<StyleEditorSection> sections;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              key: ValueKey('style-nav-${section.id}'),
              avatar: Icon(section.icon, size: 15),
              label: Text(section.title),
              selected: section.id == selected,
              onSelected: (_) => onSelected(section.id),
            ),
          ),
        if (onReset != null)
          TextButton(
            onPressed: onReset,
            child: const Text('Réinitialiser ce style'),
          ),
      ],
    ),
  );
}

/// Curseur étiqueté dont la valeur s'affiche dans une pastille.
class StyleSliderField extends StatelessWidget {
  const StyleSliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = ' dp',
    this.sliderKey,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String unit;
  final Key? sliderKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${value.toStringAsFixed(1)}$unit',
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
              ),
            ),
          ],
        ),
        Slider(
          key: sliderKey,
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Interrupteur compact pour un réglage de carte.
class StyleSwitchField extends StatelessWidget {
  const StyleSwitchField({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontSize: 13)),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(fontSize: 11)),
    value: value,
    onChanged: onChanged,
  );
}

/// Deux champs côte à côte.
class StylePair extends StatelessWidget {
  const StylePair(this.first, this.second, {super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: first),
      const SizedBox(width: 12),
      Expanded(child: second),
    ],
  );
}
