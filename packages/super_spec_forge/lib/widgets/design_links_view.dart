/// Page de liens de l'onglet Design du `NavigationRail` ([DesignLinksView]).
library;

import 'package:material_ui/material_ui.dart';

/// Élément de lien affiché sous forme de carte arrondie dans [DesignLinksView].
@immutable
class DesignLinkItem {
  /// Crée un lien cliquable de la page Design ou Spec.
  const DesignLinkItem({
    required this.id,
    required this.label,
    required this.icon,
    this.subtitle,
    this.tooltip,
  });

  /// Identifiant stable du lien (utilisé pour les clés de test et callbacks).
  final String id;

  /// Libellé affiché dans la carte.
  final String label;

  /// Icône affichée à gauche du libellé.
  final IconData icon;

  /// Sous-titre optionnel affiché sous [label].
  final String? subtitle;

  /// Info-bulle optionnelle au survol.
  final String? tooltip;
}

/// Section repliable regroupant plusieurs [DesignLinkItem].
@immutable
class DesignLinkSection {
  /// Crée une section de liens pour la page Design.
  const DesignLinkSection({
    required this.id,
    required this.title,
    required this.items,
  });

  /// Identifiant stable de la section.
  final String id;

  /// Titre de la section affiché au-dessus de la grille de cartes.
  final String title;

  /// Cartes de liens appartenant à cette section.
  final List<DesignLinkItem> items;
}

/// Vue principale de l'onglet Design présentant des sections repliables de cartes-liens.
class DesignLinksView extends StatefulWidget {
  /// Crée la page de liens Design (ou Spec via [keyPrefix]).
  const DesignLinksView({
    this.sections = defaultSections,
    this.onLinkTap,
    this.keyPrefix = 'design',
    super.key,
  });

  /// Sections par défaut (urbaniste & architecte, puis concepteur backend).
  static const List<DesignLinkSection> defaultSections = <DesignLinkSection>[
    DesignLinkSection(
      id: 'urban_planner_architect',
      title: 'Pour l’urbaniste & architecte',
      items: <DesignLinkItem>[
        DesignLinkItem(
          id: 'domain_management',
          label: 'Gestion des domaines',
          icon: Icons.domain_rounded,
        ),
        DesignLinkItem(
          id: 'systems_services',
          label: 'Systèmes & Services',
          icon: Icons.apps_rounded,
        ),
        DesignLinkItem(
          id: 'system_flow_maps',
          label: 'Cartes des flux système',
          icon: Icons.account_tree_outlined,
        ),
        DesignLinkItem(
          id: 'expert_ai_chat',
          label: 'Discuter avec l’IA experte',
          icon: Icons.chat_bubble_outline_rounded,
        ),
      ],
    ),
    DesignLinkSection(
      id: 'backend_designer',
      title: 'Pour le concepteur backend',
      items: <DesignLinkItem>[
        DesignLinkItem(
          id: 'modeling_dictionary',
          label: 'Dictionnaire technique & Modèle',
          icon: Icons.rule_folder_outlined,
          tooltip:
              'Règles techniques (Id, Ref, Code, Number, dates, booléens) et préférences globales de modélisation',
        ),
        DesignLinkItem(
          id: 'models_contracts',
          label: 'Modèles & Contrats',
          icon: Icons.data_object_rounded,
        ),
        DesignLinkItem(
          id: 'outbound_mapping',
          label: 'Mapping sortant',
          icon: Icons.map_outlined,
        ),
        DesignLinkItem(
          id: 'usecase_orchestration',
          label: 'Cas d’usage & orchestration',
          icon: Icons.check_circle_outline_rounded,
        ),
        DesignLinkItem(
          id: 'inbound_entry_points',
          label: 'Points d’entrée entrants',
          icon: Icons.hub_outlined,
        ),
        DesignLinkItem(
          id: 'infra_adapters',
          label: 'Adaptateurs d’infrastructure',
          icon: Icons.speaker_notes_outlined,
        ),
      ],
    ),
  ];

  /// Sections à afficher sur la page.
  final List<DesignLinkSection> sections;

  /// Callback optionnel déclenché lors du clic sur une carte.
  ///
  /// S'il est omis, un [SnackBar] de retour visuel est affiché.
  final ValueChanged<DesignLinkItem>? onLinkTap;

  /// Préfixe utilisé pour les [ValueKey] des en-têtes de section et cartes.
  final String keyPrefix;

  @override
  State<DesignLinksView> createState() => _DesignLinksViewState();
}

class _DesignLinksViewState extends State<DesignLinksView> {
  final Set<String> _collapsedSectionIds = <String>{};

  void _toggleSection(String sectionId) {
    setState(() {
      if (!_collapsedSectionIds.remove(sectionId)) {
        _collapsedSectionIds.add(sectionId);
      }
    });
  }

  void _handleItemTap(BuildContext context, DesignLinkItem item) {
    final callback = widget.onLinkTap;
    if (callback != null) {
      callback(item);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${item.label} — bientôt disponible'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.sections.length; i++) ...[
              if (i > 0) const SizedBox(height: 28),
              _buildSection(context, theme, colors, widget.sections[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    DesignLinkSection section,
  ) {
    final isCollapsed = _collapsedSectionIds.contains(section.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: ValueKey('${widget.keyPrefix}-section-header-${section.id}'),
          onTap: () => _toggleSection(section.id),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  section.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedRotation(
                  turns: isCollapsed ? -0.25 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.arrow_circle_down_outlined,
                    size: 22,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
          child: isCollapsed
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 14,
                    children: [
                      for (final item in section.items)
                        _DesignLinkPillCard(
                          item: item,
                          keyPrefix: widget.keyPrefix,
                          onTap: () => _handleItemTap(context, item),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _DesignLinkPillCard extends StatefulWidget {
  const _DesignLinkPillCard({
    required this.item,
    required this.keyPrefix,
    required this.onTap,
  });

  final DesignLinkItem item;
  final String keyPrefix;
  final VoidCallback onTap;

  @override
  State<_DesignLinkPillCard> createState() => _DesignLinkPillCardState();
}

class _DesignLinkPillCardState extends State<_DesignLinkPillCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final topColor = isDark
        ? Color.lerp(
            colors.surfaceContainerHighest,
            colors.onSurface,
            _hovered ? 0.16 : 0.10,
          )!
        : Color.lerp(
            colors.surfaceContainerLowest,
            colors.primary,
            _hovered ? 0.07 : 0.02,
          )!;
    final bottomColor = isDark
        ? Color.lerp(
            colors.surfaceContainerHigh,
            colors.surfaceContainer,
            _hovered ? 0.10 : 0.45,
          )!
        : Color.lerp(
            colors.surfaceContainerHigh,
            colors.surfaceContainer,
            _hovered ? 0.25 : 0.55,
          )!;
    final borderColor = isDark
        ? colors.outline.withValues(alpha: _hovered ? 0.85 : 0.55)
        : (_hovered
              ? colors.primary.withValues(alpha: 0.55)
              : colors.outlineVariant);

    final card = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        constraints: const BoxConstraints(
          minWidth: 252,
          maxWidth: 252,
          minHeight: 64,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topColor, bottomColor],
          ),
          border: Border.all(color: borderColor, width: 1.15),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: isDark ? 0.22 : 0.06),
              blurRadius: _hovered ? 10 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('${widget.keyPrefix}-link-${widget.item.id}'),
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    widget.item.icon,
                    size: 24,
                    color: colors.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: widget.item.subtitle == null
                        ? Text(
                            widget.item.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              height: 1.25,
                              color: colors.onSurface,
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  height: 1.25,
                                  color: colors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.item.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: colors.onSurface.withValues(alpha: 0.85),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final tooltip = widget.item.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: card);
    }
    return card;
  }
}
