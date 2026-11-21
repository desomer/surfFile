/// Modèles d'affichage d'arbre, thème visuel des nœuds et en-tête sticky des repositories
/// d'objets métiers ([BusinessObjectTreeSelectionTarget], [RepoTreeEntry], [RepoStickyHeaderDelegate]).
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/business_object_spec.dart';

/// Métadonnées de sélection d'un nœud de `SuperTreeView` dans l'atelier objets métiers.
class BusinessObjectTreeSelectionTarget {
  /// Construit une cible de sélection de nœud.
  const BusinessObjectTreeSelectionTarget({
    required this.nodePath,
    required this.objectId,
    required this.relationId,
    required this.attributePath,
    required this.isRootObject,
    required this.isRelation,
    required this.isArray,
    required this.isRequired,
    required this.attrType,
    required this.totalAttributes,
    required this.estimatedMaxRows,
    required this.typeIcon,
    required this.displayType,
  });

  /// Chemin `nodes[...]` dans `SuperTreeView`.
  final String nodePath;

  /// Identifiant de l'objet métier propriétaire.
  final String objectId;

  /// Identifiant de la relation si le nœud représente une relation.
  final String relationId;

  /// Chemin d'IDs d'attribut depuis la racine de l'objet.
  final List<String> attributePath;

  /// Vrai s'il s'agit du nœud racine d'un objet.
  final bool isRootObject;

  /// Vrai s'il s'agit d'une relation.
  final bool isRelation;

  /// Vrai si l'attribut est un tableau.
  final bool isArray;

  /// Vrai si l'attribut/relation est requis.
  final bool isRequired;

  /// Nom du type (`BusinessAttributeType.name`).
  final String attrType;

  /// Nombre total d'attributs (pour les objets racines).
  final int totalAttributes;

  /// Nombre estimé de lignes (pour les tableaux imbriqués).
  final int? estimatedMaxRows;

  /// Type d'icône (`container`, `value`, etc.).
  final String typeIcon;

  /// Libellé de type affiché.
  final String displayType;
}

/// Entrée de repository associée à un [BusinessObjectSpec] dans la vue arbre.
class RepoTreeEntry {
  /// Construit une entrée d'arbre pour un objet métier.
  const RepoTreeEntry({
    required this.object,
    required this.repoId,
    required this.repoAlias,
    required this.isSchemaValid,
    required this.schemaIssueCount,
    required this.childNodes,
    required this.targetsByNodePath,
  });

  /// Objet métier modélisé.
  final BusinessObjectSpec object;

  /// Identifiant technique du repository dans le store local d'arbre.
  final String repoId;

  /// Alias snake_case du repository.
  final String repoAlias;

  /// Vrai si le document de seed est valide face au JSON Schema généré.
  final bool isSchemaValid;

  /// Nombre d'anomalies JSON Schema relevées.
  final int schemaIssueCount;

  /// Nœuds enfants affichés dans `SuperTreeView`.
  final List<Map<String, Object?>> childNodes;

  /// Index des métadonnées par `nodePath`.
  final Map<String, BusinessObjectTreeSelectionTarget> targetsByNodePath;
}

/// Retourne l'icône et la palette associées à un nœud d'arbre [meta].
({IconData icon, Color fgColor, Color bgColor, Color borderColor})
visualForBusinessObjectNode(
  BusinessObjectTreeSelectionTarget? meta,
  ColorScheme colors,
  Brightness brightness,
) {
  final isDark = brightness == Brightness.dark;
  if (meta == null) {
    return (
      icon: Icons.label_outline_rounded,
      fgColor: colors.onSurfaceVariant,
      bgColor: colors.surfaceContainerHighest,
      borderColor: colors.outlineVariant,
    );
  }
  final overLimit =
      (meta.isRootObject &&
          meta.totalAttributes > BusinessObjectSpec.maxAttributesPerObject) ||
      (meta.isArray &&
          meta.estimatedMaxRows != null &&
          meta.estimatedMaxRows! > BusinessObjectSpec.maxEmbeddedArrayRows);
  if (overLimit) {
    return (
      icon: meta.isRootObject ? Icons.hub_rounded : Icons.view_list_rounded,
      fgColor: colors.onErrorContainer,
      bgColor: colors.errorContainer,
      borderColor: colors.error,
    );
  }
  if (meta.isRootObject) {
    return (
      icon: Icons.hub_rounded,
      fgColor: colors.onPrimaryContainer,
      bgColor: colors.primaryContainer,
      borderColor: colors.primary.withValues(alpha: 0.55),
    );
  }
  if (meta.isRelation) {
    return (
      icon: Icons.link_rounded,
      fgColor: colors.onTertiaryContainer,
      bgColor: colors.tertiaryContainer,
      borderColor: colors.tertiary.withValues(alpha: 0.55),
    );
  }
  if (meta.isArray) {
    final fg = isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
    final bg = isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
    final border = isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
    return (
      icon: Icons.view_list_rounded,
      fgColor: fg,
      bgColor: bg,
      borderColor: border.withValues(alpha: 0.65),
    );
  }
  if (meta.attrType == 'object' || meta.typeIcon == 'container') {
    return (
      icon: Icons.data_object_rounded,
      fgColor: colors.onSecondaryContainer,
      bgColor: colors.secondaryContainer,
      borderColor: colors.secondary.withValues(alpha: 0.55),
    );
  }
  if (meta.attrType == 'enumeration') {
    final fg = isDark ? const Color(0xFF5EEAD4) : const Color(0xFF115E59);
    final bg = isDark ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1);
    final border = isDark ? const Color(0xFF14B8A6) : const Color(0xFF0D9488);
    return (
      icon: Icons.list_alt_rounded,
      fgColor: fg,
      bgColor: bg,
      borderColor: border.withValues(alpha: 0.65),
    );
  }
  if (meta.attrType == 'reference') {
    final fg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF);
    final bg = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE);
    final border = isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
    return (
      icon: Icons.north_east_rounded,
      fgColor: fg,
      bgColor: bg,
      borderColor: border.withValues(alpha: 0.65),
    );
  }

  final scalarIcon = switch (meta.attrType) {
    'integer' || 'number' => Icons.tag_rounded,
    'boolean' => Icons.toggle_on_outlined,
    'date' || 'datetime' => Icons.calendar_today_outlined,
    'uuid' => Icons.fingerprint_rounded,
    'email' => Icons.alternate_email_rounded,
    'url' => Icons.language_rounded,
    _ => Icons.short_text_rounded,
  };
  return (
    icon: scalarIcon,
    fgColor: colors.onSurface,
    bgColor: colors.surfaceContainerHighest,
    borderColor: colors.outline.withValues(alpha: 0.55),
  );
}

/// Délégué d'en-tête sticky pour chaque carte d'objet métier / repository.
class RepoStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  /// Construit le délégué sticky.
  const RepoStickyHeaderDelegate({
    required this.entry,
    required this.isExpanded,
    required this.isObjectSelected,
    required this.isHeaderHighlighted,
    required this.overAttrLimit,
    required this.borderColor,
    required this.borderWidth,
    required this.theme,
    required this.colors,
    required this.onSelectObject,
    required this.onToggleExpanded,
  });

  /// Hauteur fixe de l'en-tête sticky.
  static const double headerHeight = 62.0;

  /// Entrée de repository affichée.
  final RepoTreeEntry entry;

  /// Vrai si le corps de la carte est déplié.
  final bool isExpanded;

  /// Vrai si cet objet est sélectionné.
  final bool isObjectSelected;

  /// Vrai si l'en-tête est surligné comme sélection active.
  final bool isHeaderHighlighted;

  /// Vrai si le seuil de 200 attributs est dépassé.
  final bool overAttrLimit;

  /// Couleur de bordure.
  final Color borderColor;

  /// Épaisseur de bordure.
  final double borderWidth;

  /// Thème courant.
  final ThemeData theme;

  /// Palette courante.
  final ColorScheme colors;

  /// Callback de sélection de l'objet.
  final VoidCallback onSelectObject;

  /// Callback de dépliage/repliage.
  final VoidCallback onToggleExpanded;

  @override
  double get minExtent => headerHeight;

  @override
  double get maxExtent => headerHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final obj = entry.object;
    final totalAttrs = obj.totalAttributeCount;
    final bgColor = isHeaderHighlighted
        ? Color.alphaBlend(
            colors.primaryContainer.withValues(alpha: 0.42),
            colors.surface,
          )
        : colors.surfaceContainerLow;
    final borderSide = BorderSide(color: borderColor, width: borderWidth);

    return Container(
      key: ValueKey('spec-objects-repo-tile-${obj.id}'),
      height: headerHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: isExpanded
            ? const BorderRadius.vertical(top: Radius.circular(10))
            : BorderRadius.circular(10),
        border: Border.fromBorderSide(borderSide),
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onSelectObject,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 7, 10, 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  key: ValueKey('spec-objects-repo-toggle-${obj.id}'),
                  tooltip: isExpanded ? 'Replier' : 'Déplier',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: onToggleExpanded,
                  icon: Icon(
                    isExpanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            obj.aggregateRoot
                                ? Icons.hub_rounded
                                : Icons.account_tree_outlined,
                            size: 15,
                            color: obj.aggregateRoot
                                ? colors.primary
                                : colors.secondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              obj.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: entry.isSchemaValid
                                  ? colors.secondaryContainer
                                  : colors.errorContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              entry.isSchemaValid
                                  ? 'Valide'
                                  : '${entry.schemaIssueCount} err.',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: entry.isSchemaValid
                                    ? colors.onSecondaryContainer
                                    : colors.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LayoutBuilder(
                        builder: (context, rowConstraints) {
                          final maxChipsWidth =
                              (rowConstraints.maxWidth * 0.58).clamp(
                                0.0,
                                180.0,
                              );
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${entry.repoAlias} · ${obj.technicalName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: maxChipsWidth,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      RepoCardChip(
                                        label: obj.aggregateRoot
                                            ? 'Agrégat'
                                            : 'Entité liée',
                                        bg: obj.aggregateRoot
                                            ? colors.primaryContainer
                                                  .withValues(alpha: 0.7)
                                            : colors.surfaceContainerHighest,
                                        fg: obj.aggregateRoot
                                            ? colors.onPrimaryContainer
                                            : colors.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
                                      RepoCardChip(
                                        label:
                                            '$totalAttrs/${BusinessObjectSpec.maxAttributesPerObject} attr.',
                                        bg: overAttrLimit
                                            ? colors.errorContainer
                                            : colors.surfaceContainerHighest,
                                        fg: overAttrLimit
                                            ? colors.onErrorContainer
                                            : colors.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant RepoStickyHeaderDelegate oldDelegate) {
    return oldDelegate.entry.object != entry.object ||
        oldDelegate.entry.repoAlias != entry.repoAlias ||
        oldDelegate.entry.isSchemaValid != entry.isSchemaValid ||
        oldDelegate.entry.schemaIssueCount != entry.schemaIssueCount ||
        oldDelegate.isExpanded != isExpanded ||
        oldDelegate.isObjectSelected != isObjectSelected ||
        oldDelegate.isHeaderHighlighted != isHeaderHighlighted ||
        oldDelegate.overAttrLimit != overAttrLimit ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.theme.brightness != theme.brightness;
  }
}

/// Badge compact utilisé dans les en-têtes de repository d'objets métiers.
class RepoCardChip extends StatelessWidget {
  /// Construit un badge compact.
  const RepoCardChip({
    required this.label,
    required this.bg,
    required this.fg,
    super.key,
  });

  /// Libellé du badge.
  final String label;

  /// Couleur de fond.
  final Color bg;

  /// Couleur du texte.
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 10.5,
        ),
      ),
    );
  }
}
