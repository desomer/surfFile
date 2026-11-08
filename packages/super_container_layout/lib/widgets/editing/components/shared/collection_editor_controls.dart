/// Contrôles et utilitaires partagés entre les éditeurs de collections JSON
/// (`SuperListView`, `SuperTable`, `SuperTreeView`).
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../../models/json_text_binding.dart';
import '../../../../models/super_table_config.dart';
import '../../../../services/repositories/json_list_scope.dart';
import '../../../../services/repositories/json_repository_store.dart';
import '../../repositories/repository_binding_fields.dart'
    show inheritedRepositoryValue;

/// Formate un `double` sans décimale inutile (`12.0` -> `'12'`).
String formatCollectionEditorNumber(double value) =>
    value == value.roundToDouble() ? '${value.toInt()}' : '$value';

/// Parse un `double` depuis un [TextEditingController] ou lève une [FormatException].
double parseCollectionEditorNumber(TextEditingController field) {
  final value = double.tryParse(field.text.trim().replaceAll(',', '.'));
  if (value == null) {
    throw const FormatException('Valeur numérique invalide.');
  }
  return value;
}

/// Construit un [JsonTextBinding] à partir de l'identifiant de repository
/// sélectionné (`''` pour aucun, [inheritedRepositoryValue] pour hérité) et du
/// chemin saisi.
JsonTextBinding? buildCollectionEditorBinding(String repository, String path) =>
    repository.isEmpty
    ? null
    : JsonTextBinding(
        repositoryId: repository == inheritedRepositoryValue
            ? null
            : repository,
        path: path.trim(),
      );

/// Vérifie qu'une liaison de collection JSON [binding] pointe vers une donnée
/// existante dans [store] via [readTarget] (ex: `store.readArray` ou `store.readTreeNodes`).
Future<void> verifyCollectionBindingTarget({
  required JsonTextBinding? binding,
  required JsonListScope? scope,
  required JsonRepositoryStore? store,
  required Future<void> Function(
    JsonRepositoryStore store,
    String repositoryId,
    String path,
  )
  readTarget,
}) async {
  if (binding == null || (scope?.placeholder ?? false)) return;
  if (store == null) {
    throw const FormatException('Service de repositories indisponible.');
  }
  final resolved = JsonListScope.resolveSelected(binding, scope, store).binding;
  if (resolved != null) {
    await readTarget(store, resolved.repositoryId!, resolved.path);
  }
}

/// Champs de sélection du repository et du chemin JSON pour un éditeur de
/// collection (`SuperListView`, `SuperTable`, `SuperTreeView`).
class CollectionRepositorySourceFields extends StatefulWidget {
  /// Crée un [CollectionRepositorySourceFields].
  const CollectionRepositorySourceFields({
    required this.keyPrefix,
    required this.repositories,
    required this.scope,
    required this.repository,
    required this.pathController,
    required this.pathLabel,
    required this.rootHint,
    required this.nestedHint,
    required this.helperText,
    required this.busy,
    required this.onRepositoryChanged,
    required this.onLoadError,
    super.key,
  });

  final String keyPrefix;
  final JsonRepositoryStore? repositories;
  final JsonListScope? scope;
  final String repository;
  final TextEditingController pathController;
  final String pathLabel;
  final String rootHint;
  final String nestedHint;
  final String helperText;
  final bool busy;
  final ValueChanged<String> onRepositoryChanged;
  final ValueChanged<String> onLoadError;

  @override
  State<CollectionRepositorySourceFields> createState() =>
      _CollectionRepositorySourceFieldsState();
}

class _CollectionRepositorySourceFieldsState
    extends State<CollectionRepositorySourceFields> {
  List<JsonRepositoryEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _loadRepositories();
  }

  Future<void> _loadRepositories() async {
    final store = widget.repositories;
    if (store == null) return;
    try {
      final entries = await store.catalog();
      if (mounted) setState(() => _entries = entries);
    } on FormatException catch (error) {
      if (mounted) widget.onLoadError(error.message);
    } on FileSystemException {
      if (mounted) {
        widget.onLoadError('Impossible de charger les repositories.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final depth = widget.scope?.indices.length ?? 0;
    final inheritable =
        widget.scope != null || widget.repository == inheritedRepositoryValue;
    final known =
        widget.repository.isEmpty ||
        widget.repository == inheritedRepositoryValue ||
        _entries.any((entry) => entry.id == widget.repository);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.keyPrefix}-repository'),
          initialValue: widget.repository,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Repository'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Sans liaison')),
            if (inheritable)
              const DropdownMenuItem(
                value: inheritedRepositoryValue,
                child: Text('Hérité de la liste englobante'),
              ),
            for (final entry in _entries)
              DropdownMenuItem(
                value: entry.id,
                child: Text(entry.name, overflow: TextOverflow.ellipsis),
              ),
            if (!known)
              DropdownMenuItem(
                value: widget.repository,
                child: const Text('Repository indisponible'),
              ),
          ],
          onChanged: widget.busy
              ? null
              : (value) => widget.onRepositoryChanged(value ?? ''),
        ),
        TextFormField(
          key: ValueKey('${widget.keyPrefix}-path'),
          controller: widget.pathController,
          enabled: widget.repository.isNotEmpty && !widget.busy,
          decoration: InputDecoration(
            labelText: widget.pathLabel,
            hintText: depth == 0 ? widget.rootHint : widget.nestedHint,
            helperText: widget.helperText,
          ),
          validator: (value) {
            if (widget.repository.isEmpty) return null;
            try {
              JsonAttributePath(value?.trim() ?? '');
              return null;
            } on FormatException catch (error) {
              return error.message;
            }
          },
        ),
      ],
    );
  }
}

/// Pied de formulaire d'éditeur de collection affichant l'indicateur de
/// progression et le message d'erreur éventuel.
List<Widget> buildCollectionEditorStatusWidgets({
  required BuildContext context,
  required String keyPrefix,
  required bool busy,
  required String? error,
}) => [
  if (busy) const LinearProgressIndicator(),
  if (error != null)
    Text(
      error,
      key: ValueKey('$keyPrefix-editor-error'),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
];

/// Brouillon mutable d'une colonne de [SuperTable] dans l'éditeur.
class SuperTableColumnDraft {
  /// Crée un [SuperTableColumnDraft].
  SuperTableColumnDraft({
    required this.id,
    required String title,
    required double width,
    double fillPercent = SuperTableColumnConfig.defaultFillPercent,
  }) : title = TextEditingController(text: title),
       width = TextEditingController(text: formatCollectionEditorNumber(width)),
       fillPercent = TextEditingController(
         text: formatCollectionEditorNumber(fillPercent),
       );

  final String id;
  final TextEditingController title;
  final TextEditingController width;
  final TextEditingController fillPercent;

  /// Indique si la colonne occupe un pourcentage de l'espace restant (`> 0`).
  bool get hasFill {
    final val = double.tryParse(fillPercent.text.trim().replaceAll(',', '.'));
    return val != null && val > 0;
  }

  /// Convertit le brouillon en [SuperTableColumnConfig] validée.
  SuperTableColumnConfig toConfig() => SuperTableColumnConfig(
    id: id,
    title: title.text.trim(),
    width: parseCollectionEditorNumber(width),
    fillPercent: fillPercent.text.trim().isEmpty
        ? 0.0
        : parseCollectionEditorNumber(fillPercent),
  );

  /// Libère les contrôleurs de texte.
  void dispose() {
    title.dispose();
    width.dispose();
    fillPercent.dispose();
  }
}

/// Liste éditable des colonnes d'un [SuperTable] (ajout, suppression, titre,
/// largeur et pourcentage de remplissage).
class SuperTableColumnsEditor extends StatelessWidget {
  /// Crée un [SuperTableColumnsEditor].
  const SuperTableColumnsEditor({
    required this.columns,
    required this.busy,
    required this.onAddColumn,
    required this.onRemoveColumn,
    super.key,
  });

  final List<SuperTableColumnDraft> columns;
  final bool busy;
  final VoidCallback onAddColumn;
  final ValueChanged<int> onRemoveColumn;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Colonnes (${columns.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          TextButton.icon(
            key: const ValueKey('super-table-add-column'),
            onPressed: busy ? null : onAddColumn,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter une colonne'),
          ),
        ],
      ),
      for (var i = 0; i < columns.length; i++)
        Row(
          key: ValueKey('super-table-col-row-${columns[i].id}'),
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                key: ValueKey('super-table-col-title-${columns[i].id}'),
                controller: columns[i].title,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Titre (${columns[i].id})',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: columns[i].fillPercent,
                builder: (context, _, _) => TextFormField(
                  key: ValueKey('super-table-col-width-${columns[i].id}'),
                  controller: columns[i].width,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: columns[i].hasFill
                        ? 'Largeur min (px)'
                        : 'Largeur (px)',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: ValueKey('super-table-col-fill-${columns[i].id}'),
                controller: columns[i].fillPercent,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Reste (%)',
                  suffixText: '%',
                ),
              ),
            ),
            IconButton(
              key: ValueKey('super-table-col-delete-${columns[i].id}'),
              tooltip: 'Supprimer la colonne',
              onPressed: columns.length <= 1 || busy
                  ? null
                  : () => onRemoveColumn(i),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
    ],
  );
}
