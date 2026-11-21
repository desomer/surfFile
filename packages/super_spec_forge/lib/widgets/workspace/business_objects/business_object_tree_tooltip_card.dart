/// Infobulle riche affichée au survol d'un nœud de `SuperTreeView` ([TreeNodeTooltipCard]).
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../../models/business_object_spec.dart';
import '../../../models/spec_forge_project.dart';
import '../../../services/business_object_operations.dart';

/// Carte d'infobulle détaillée pour un objet, un attribut ou une relation.
class TreeNodeTooltipCard extends StatelessWidget {
  /// Construit une infobulle détaillée.
  const TreeNodeTooltipCard({
    required this.project,
    required this.object,
    required this.attribute,
    required this.attributePath,
    required this.relation,
    required this.visual,
    super.key,
  });

  /// Projet parent.
  final SpecForgeProject project;

  /// Objet métier associé.
  final BusinessObjectSpec object;

  /// Attribut ciblé, le cas échéant.
  final BusinessAttribute? attribute;

  /// Chemin d'IDs d'attribut depuis la racine de l'objet.
  final List<String> attributePath;

  /// Relation ciblée, le cas échéant.
  final BusinessRelation? relation;

  /// Palette et icône du nœud.
  final ({IconData icon, Color fgColor, Color bgColor, Color borderColor})
  visual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 250, maxWidth: 380),
        child: Card(
          key: const ValueKey('spec-tree-node-tooltip-card'),
          elevation: 8,
          shadowColor: colors.shadow.withValues(alpha: 0.35),
          color: colors.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: visual.borderColor, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DefaultTextStyle(
              style:
                  theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface,
                  ) ??
                  const TextStyle(fontSize: 12),
              child: attribute != null
                  ? _buildAttributeContent(theme, colors, attribute!)
                  : (relation != null
                        ? _buildRelationContent(theme, colors, relation!)
                        : _buildObjectContent(theme, colors)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttributeContent(
    ThemeData theme,
    ColorScheme colors,
    BusinessAttribute attr,
  ) {
    final schemaBadges = attr.schemaConstraints.describeBadges();
    final refObj = attr.referenceObjectId.isNotEmpty
        ? project.findBusinessObject(attr.referenceObjectId)
        : null;
    final pathBreadcrumbs = BusinessObjectOperations.resolveAttributePathNames(
      object.attributes,
      attributePath,
    );
    final typeLabel =
        '${attr.type.label} (${attr.type.dslKeyword}${attr.isArray ? '[]' : ''})';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: visual.bgColor,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: visual.borderColor),
              ),
              child: Icon(visual.icon, size: 15, color: visual.fgColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attr.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  Text(
                    '${object.technicalName}.${pathBreadcrumbs.join('.')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _TooltipPill(
              label: typeLabel,
              bgColor: visual.bgColor,
              fgColor: visual.fgColor,
              borderColor: visual.borderColor,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            _TooltipPill(
              label: attr.required ? 'Obligatoire (!)' : 'Optionnel',
              bgColor: attr.required
                  ? colors.errorContainer.withValues(alpha: 0.7)
                  : colors.surfaceContainerLow,
              fgColor: attr.required
                  ? colors.onErrorContainer
                  : colors.onSurfaceVariant,
              borderColor: attr.required
                  ? colors.error.withValues(alpha: 0.4)
                  : colors.outlineVariant,
            ),
            if (attr.nullable)
              _TooltipPill(
                label: 'Nullable (?)',
                bgColor: colors.surfaceContainerLow,
                fgColor: colors.onSurfaceVariant,
                borderColor: colors.outlineVariant,
              ),
            if (attr.unique)
              _TooltipPill(
                label: 'Unique',
                bgColor: colors.secondaryContainer.withValues(alpha: 0.7),
                fgColor: colors.onSecondaryContainer,
                borderColor: colors.secondary.withValues(alpha: 0.4),
              ),
            if (attr.isArray)
              _TooltipPill(
                label: attr.estimatedMaxRows != null
                    ? 'Tableau · max ${attr.estimatedMaxRows} lignes'
                    : 'Tableau ([])',
                bgColor: colors.tertiaryContainer.withValues(alpha: 0.7),
                fgColor: colors.onTertiaryContainer,
                borderColor: colors.tertiary.withValues(alpha: 0.4),
              ),
            if (attr.type == BusinessAttributeType.object)
              _TooltipPill(
                label: '${attr.children.length} sous-champ(s)',
                bgColor: colors.secondaryContainer.withValues(alpha: 0.7),
                fgColor: colors.onSecondaryContainer,
                borderColor: colors.secondary.withValues(alpha: 0.4),
              ),
            if (attr.defaultValue != null &&
                attr.defaultValue!.trim().isNotEmpty)
              _TooltipPill(
                label: 'Défaut : ${attr.defaultValue!.trim()}',
                bgColor: colors.surfaceContainerLow,
                fgColor: colors.onSurface,
                borderColor: colors.outlineVariant,
              ),
          ],
        ),
        if (attr.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            attr.description,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurface),
          ),
        ],
        if (refObj != null || attr.referenceObjectId.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Référence → ${refObj != null ? '${refObj.name} (${refObj.technicalName})' : attr.referenceObjectId}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (attr.enumValues.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...() {
            final names = attr.schemaConstraints.enumNames;
            final formatted = [
              for (var i = 0; i < attr.enumValues.length; i++)
                (i < names.length && names[i].trim().isNotEmpty)
                    ? '${attr.enumValues[i]} (${names[i].trim()})'
                    : attr.enumValues[i],
            ];
            return [
              Text(
                'Valeurs possibles : ${formatted.join(', ')}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ];
          }(),
        ],
        if (attr.constraints.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Contraintes : ${attr.constraints}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        if (attr.schemaConstraints.examples.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Exemples',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.secondary,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            key: const ValueKey('spec-tree-tooltip-examples'),
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final ex in attr.schemaConstraints.examples.take(5))
                _TooltipPill(
                  label: _formatExampleValue(ex),
                  bgColor: colors.secondaryContainer.withValues(alpha: 0.65),
                  fgColor: colors.onSecondaryContainer,
                  borderColor: colors.secondary.withValues(alpha: 0.35),
                ),
              if (attr.schemaConstraints.examples.length > 5)
                _TooltipPill(
                  label: '+${attr.schemaConstraints.examples.length - 5}',
                  bgColor: colors.surfaceContainerLow,
                  fgColor: colors.onSurfaceVariant,
                  borderColor: colors.outlineVariant,
                ),
            ],
          ),
        ],
        if (schemaBadges.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Contraintes JSON Schema',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final badge in schemaBadges)
                _TooltipPill(
                  label: badge,
                  bgColor: colors.primaryContainer.withValues(alpha: 0.55),
                  fgColor: colors.onPrimaryContainer,
                  borderColor: colors.primary.withValues(alpha: 0.35),
                ),
            ],
          ),
        ],
        if (attr.children.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Sous-attributs',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          for (final child in attr.children.take(5))
            Text(
              '• ${child.name} : ${child.type.dslKeyword}${child.isArray ? '[]' : ''}${child.required ? '!' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: colors.onSurface,
              ),
            ),
          if (attr.children.length > 5)
            Text(
              '… +${attr.children.length - 5} autre(s)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildRelationContent(
    ThemeData theme,
    ColorScheme colors,
    BusinessRelation rel,
  ) {
    final target = project.findBusinessObject(rel.targetObjectId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(visual.icon, size: 16, color: visual.fgColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${object.technicalName}.${rel.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _TooltipPill(
              label: 'Relation ${rel.cardinality.symbol}',
              bgColor: visual.bgColor,
              fgColor: visual.fgColor,
              borderColor: visual.borderColor,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Cible : ${target != null ? '${target.name} (${target.technicalName})' : rel.targetObjectId}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
        if (rel.inverseName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Relation inverse : ${rel.inverseName}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        if (rel.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(rel.description, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _buildObjectContent(ThemeData theme, ColorScheme colors) {
    final total = object.totalAttributeCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(visual.icon, size: 16, color: visual.fgColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${object.name} (${object.technicalName})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _TooltipPill(
              label: object.aggregateRoot ? 'Agrégat racine' : 'Entité',
              bgColor: visual.bgColor,
              fgColor: visual.fgColor,
              borderColor: visual.borderColor,
            ),
          ],
        ),
        if (object.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(object.description, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            _TooltipPill(
              label:
                  '$total / ${BusinessObjectSpec.maxAttributesPerObject} attributs',
              bgColor: colors.primaryContainer.withValues(alpha: 0.6),
              fgColor: colors.onPrimaryContainer,
              borderColor: colors.primary.withValues(alpha: 0.35),
            ),
            _TooltipPill(
              label: '${object.relations.length} relation(s)',
              bgColor: colors.surfaceContainerLow,
              fgColor: colors.onSurfaceVariant,
              borderColor: colors.outlineVariant,
            ),
            if (object.lifecycleStates.isNotEmpty)
              _TooltipPill(
                label: '${object.lifecycleStates.length} état(s)',
                bgColor: colors.secondaryContainer.withValues(alpha: 0.6),
                fgColor: colors.onSecondaryContainer,
                borderColor: colors.secondary.withValues(alpha: 0.35),
              ),
          ],
        ),
        if (object.lifecycleStates.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'États : ${object.lifecycleStates.map((s) => s.effectiveLabel).join(' → ')}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _TooltipPill extends StatelessWidget {
  const _TooltipPill({
    required this.label,
    required this.bgColor,
    required this.fgColor,
    required this.borderColor,
  });

  final String label;
  final Color bgColor;
  final Color fgColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fgColor,
        ),
      ),
    );
  }
}

String _formatExampleValue(Object? value) {
  if (value is String) return value;
  return jsonEncode(value);
}
