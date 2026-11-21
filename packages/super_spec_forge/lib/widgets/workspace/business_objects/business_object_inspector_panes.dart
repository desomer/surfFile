/// Panneaux d'inspection d'objet métier et d'attribut dans l'atelier Objets métiers
/// ([BusinessObjectInspectorPane], [AttributeInspectorPane], [EnumValuesTable]).
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../../models/business_object_spec.dart';
import '../../../models/spec_forge_project.dart';
import '../../../services/business_object_operations.dart';
import '../../../services/exporters/spec_super_designer_exporter.dart';
import '../../../services/spec_forge_controller.dart';
import '../attribute_constraints_editor.dart';

/// Panneau inspecteur détaillé d'un [BusinessObjectSpec].
class BusinessObjectInspectorPane extends StatelessWidget {
  /// Construit le panneau inspecteur d'objet métier.
  const BusinessObjectInspectorPane({
    required this.project,
    required this.object,
    required this.controller,
    required this.onEditMeta,
    required this.onAddAttribute,
    required this.onEditAttribute,
    required this.onDeleteAttribute,
    super.key,
  });

  /// Projet parent.
  final SpecForgeProject project;

  /// Objet métier sélectionné.
  final BusinessObjectSpec object;

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Action d'édition des métadonnées de l'objet.
  final VoidCallback onEditMeta;

  /// Action d'ajout d'un attribut racine.
  final VoidCallback onAddAttribute;

  /// Action d'édition d'un attribut.
  final ValueChanged<BusinessAttribute> onEditAttribute;

  /// Action de suppression d'un attribut.
  final ValueChanged<BusinessAttribute> onDeleteAttribute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final totalAttrs = object.totalAttributeCount;
    final ratio = (totalAttrs / BusinessObjectSpec.maxAttributesPerObject)
        .clamp(0.0, 1.0);
    final gaugeColor = totalAttrs > BusinessObjectSpec.maxAttributesPerObject
        ? colors.error
        : (totalAttrs >= 160 ? colors.tertiary : colors.primary);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${object.name} (${object.technicalName})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (object.description.isNotEmpty)
                    Text(
                      object.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Modifier l’objet',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditMeta,
            ),
            IconButton(
              tooltip: 'Supprimer l’objet',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                final next = BusinessObjectOperations.removeObject(
                  project.businessObjects,
                  object.id,
                );
                controller.updateProject(
                  project.copyWith(businessObjects: next),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: ratio,
                color: gaugeColor,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$totalAttrs / ${BusinessObjectSpec.maxAttributesPerObject} attributs',
              style: theme.textTheme.labelMedium?.copyWith(
                color: gaugeColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AttributeSchemaPreviewCard(
          title: 'Aperçu JSON Schema (${object.technicalName})',
          schemaMap: SpecSuperDesignerExporter.objectToJsonSchema(
            project,
            object,
          ),
          badges: [
            '$totalAttrs/${BusinessObjectSpec.maxAttributesPerObject} attributs',
            '${object.relations.length} relation(s)',
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              'Attributs & sous-objets (${object.attributes.length} racine)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('spec-objects-add-attr'),
              onPressed: onAddAttribute,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (object.attributes.isEmpty)
          Text(
            'Aucun attribut défini.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          )
        else
          for (final attr in object.attributes)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 6),
              color: colors.surfaceContainerLow,
              child: ListTile(
                dense: true,
                title: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      attr.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Chip(
                      label: Text(
                        attr.isArray
                            ? '${attr.type.dslKeyword}[]'
                            : attr.type.dslKeyword,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (attr.type == BusinessAttributeType.object)
                      Chip(
                        label: Text('${attr.children.length} sous-champ(s)'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (attr.isArray && attr.estimatedMaxRows != null)
                      Chip(
                        label: Text('max ${attr.estimatedMaxRows} lignes'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (attr.schemaConstraints.isNotEmpty)
                      Chip(
                        label: Text(attr.schemaConstraints.formatSummary()),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                subtitle: (attr.description.isEmpty &&
                        attr.schemaConstraints.examples.isEmpty)
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (attr.description.isNotEmpty)
                            Text(attr.description),
                          if (attr.schemaConstraints.examples.isNotEmpty)
                            Text(
                              'Exemples : ${attr.schemaConstraints.examples.map(_formatExampleValue).join(', ')}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.primary,
                                fontFamily: 'monospace',
                              ),
                            ),
                        ],
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      onPressed: () => onEditAttribute(attr),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => onDeleteAttribute(attr),
                    ),
                  ],
                ),
              ),
            ),
        if (object.relations.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Relations (${object.relations.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final rel in object.relations)
            ListTile(
              dense: true,
              leading: const Icon(Icons.link_rounded, size: 18),
              title: Text(
                '${rel.name} → ${project.findBusinessObject(rel.targetObjectId)?.name ?? rel.targetObjectId} (${rel.cardinality.symbol})',
              ),
              subtitle: rel.description.isEmpty ? null : Text(rel.description),
            ),
        ],
        if (object.lifecycleStates.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Cycle de vie (${object.lifecycleStates.length} états)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in object.lifecycleStates)
                Chip(
                  avatar: Icon(
                    s.isInitial
                        ? Icons.play_circle_outline_rounded
                        : (s.isTerminal
                              ? Icons.stop_circle_outlined
                              : Icons.circle_outlined),
                    size: 16,
                  ),
                  label: Text(s.effectiveLabel),
                ),
            ],
          ),
          if (object.lifecycleTransitions.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final tr in object.lifecycleTransitions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${tr.fromState} → ${tr.toState}'
                  '${tr.trigger.isEmpty ? '' : ' (${tr.trigger})'}'
                  '${tr.guardSummary.isEmpty ? '' : ' — Garde : ${tr.guardSummary}'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ],
    );
  }
}

/// Panneau inspecteur détaillé d'un [BusinessAttribute].
class AttributeInspectorPane extends StatelessWidget {
  /// Construit le panneau inspecteur d'attribut.
  const AttributeInspectorPane({
    required this.project,
    required this.object,
    required this.attribute,
    required this.attributePath,
    required this.onBackToObject,
    required this.onEditAttribute,
    required this.onAddChildAttribute,
    required this.onDeleteAttribute,
    required this.onExtractToSeparateObject,
    super.key,
  });

  /// Projet parent.
  final SpecForgeProject project;

  /// Objet métier propriétaire.
  final BusinessObjectSpec object;

  /// Attribut inspecté.
  final BusinessAttribute attribute;

  /// Chemin d'IDs menant à [attribute].
  final List<String> attributePath;

  /// Retourne à la vue de l'objet parent.
  final VoidCallback onBackToObject;

  /// Ouvre le dialogue d'édition de l'attribut.
  final VoidCallback onEditAttribute;

  /// Ajoute un sous-attribut (si type `object`).
  final VoidCallback? onAddChildAttribute;

  /// Supprime l'attribut.
  final VoidCallback onDeleteAttribute;

  /// Extrait un tableau > 200 lignes vers un objet séparé.
  final VoidCallback? onExtractToSeparateObject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onBackToObject,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text(
                    object.technicalName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditAttribute,
            ),
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: onDeleteAttribute,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          attribute.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Chip(
              label: Text(
                '${attribute.type.label} (${attribute.type.dslKeyword})',
              ),
            ),
            if (attribute.required) const Chip(label: Text('Obligatoire (!)')),
            if (attribute.nullable) const Chip(label: Text('Nullable (?)')),
            if (attribute.isArray) const Chip(label: Text('Tableau ([])')),
            if (attribute.isArray && attribute.estimatedMaxRows != null)
              Chip(label: Text('Max ${attribute.estimatedMaxRows} lignes')),
            if (attribute.schemaConstraints.xMask != null)
              Chip(
                key: const ValueKey('spec-attr-inspector-x-mask'),
                avatar: Icon(
                  Icons.password_rounded,
                  size: 15,
                  color: colors.primary,
                ),
                label: Text('x-mask: ${attribute.schemaConstraints.xMask}'),
              ),
            if (attribute.schemaConstraints.xSearchable == true)
              Chip(
                key: const ValueKey('spec-attr-inspector-x-searchable'),
                avatar: Icon(
                  Icons.search_rounded,
                  size: 15,
                  color: colors.primary,
                ),
                label: const Text('x-searchable'),
              ),
            if (attribute.schemaConstraints.xDatabaseIndex == true)
              Chip(
                key: const ValueKey('spec-attr-inspector-x-database-index'),
                avatar: Icon(
                  Icons.storage_rounded,
                  size: 15,
                  color: colors.primary,
                ),
                label: const Text('x-database-index'),
              ),
          ],
        ),
        if (attribute.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(attribute.description),
        ],
        if (attribute.constraints.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Contraintes : ${attribute.constraints}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (attribute.enumValues.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Choix de l’énumération (${attribute.enumValues.length})',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          EnumValuesTable(
            key: const ValueKey('spec-attr-inspector-enum-table'),
            values: attribute.enumValues,
            names: attribute.schemaConstraints.enumNames,
            descriptions: attribute.schemaConstraints.enumDescriptions,
          ),
        ],
        if (attribute.schemaConstraints.examples.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Exemples',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            key: const ValueKey('spec-attr-inspector-examples'),
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final ex in attribute.schemaConstraints.examples)
                Chip(
                  avatar: Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 15,
                    color: colors.primary,
                  ),
                  label: Text(
                    _formatExampleValue(ex),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        if (attribute.referenceObjectId.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Référence vers : ${project.findBusinessObject(attribute.referenceObjectId)?.name ?? attribute.referenceObjectId}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        AttributeSchemaPreviewCard(
          schemaMap: SpecSuperDesignerExporter.attributeToJsonSchema(attribute),
          badges: attribute.schemaConstraints.describeBadges(),
        ),
        if (onExtractToSeparateObject != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Règle tableau imbriqué (max 200 lignes)',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Si ce tableau doit dépasser 200 lignes fonctionnelles, extrayez-le en objet métier séparé relié par relation 1:N.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  key: const ValueKey('spec-objects-extract-array'),
                  onPressed: onExtractToSeparateObject,
                  icon: const Icon(Icons.call_split_rounded, size: 16),
                  label: const Text('Extraire en objet métier dédié'),
                ),
              ],
            ),
          ),
        ],
        if (attribute.type == BusinessAttributeType.object) ...[
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'Sous-attributs (${attribute.children.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onAddChildAttribute != null)
                OutlinedButton.icon(
                  key: const ValueKey('spec-objects-add-subattr'),
                  onPressed: onAddChildAttribute,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Ajouter sous-attribut'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (attribute.children.isEmpty)
            Text(
              'Aucun sous-attribut dans ce sous-objet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            for (final child in attribute.children)
              Card(
                elevation: 0,
                color: colors.surfaceContainerLow,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text(
                    '${child.name} : ${child.type.dslKeyword}${child.isArray ? '[]' : ''}',
                  ),
                  subtitle: child.description.isEmpty
                      ? null
                      : Text(child.description),
                ),
              ),
        ],
      ],
    );
  }
}

/// Tableau récapitulatif des valeurs d'énumération (`enum`, `x-enumNames`, `x-enumDescriptions`).
class EnumValuesTable extends StatelessWidget {
  /// Construit le tableau d'énumération.
  const EnumValuesTable({
    required this.values,
    required this.names,
    required this.descriptions,
    super.key,
  });

  /// Valeurs techniques.
  final List<String> values;

  /// Libellés humains associés (`x-enumNames`).
  final List<String> names;

  /// Descriptions associées (`x-enumDescriptions`).
  final List<String> descriptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.0),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.8),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          horizontalInside: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: colors.surfaceContainerLow),
            children: [
              _headerCell(theme, 'Valeur (enum)'),
              _headerCell(theme, 'Nom (x-enumNames)'),
              _headerCell(theme, 'Descriptif (x-enumDescriptions)'),
            ],
          ),
          for (var i = 0; i < values.length; i++)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Text(
                    values[i],
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Text(
                    i < names.length && names[i].trim().isNotEmpty
                        ? names[i].trim()
                        : '—',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight:
                          i < names.length && names[i].trim().isNotEmpty
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: i < names.length && names[i].trim().isNotEmpty
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Text(
                    i < descriptions.length && descriptions[i].trim().isNotEmpty
                        ? descriptions[i].trim()
                        : '—',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          i < descriptions.length &&
                              descriptions[i].trim().isNotEmpty
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _headerCell(ThemeData theme, String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    child: Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

String _formatExampleValue(Object? value) {
  if (value is String) return value;
  return jsonEncode(value);
}
