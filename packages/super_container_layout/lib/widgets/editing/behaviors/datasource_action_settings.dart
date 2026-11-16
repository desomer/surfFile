/// Configuration de l'action « Commande de datasource » ([DatasourceActionSettings]).
///
/// Étape du wizard de comportements qui liste les datasources du registre
/// (`store.datasources`), propose les commandes qu'elles supportent
/// (recherche, pagination, tri, Create / Read / Update / Delete) et ouvre le
/// gestionnaire de datasources pour en créer ou en modifier une.
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';

import '../../../models/behaviours/datasource_action.dart';
import '../../../models/datasources/datasource_config.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../datasources/datasource_manager.dart';

/// Saisie en cours de l'action : la datasource, la commande et, pour le tri,
/// le champ et le sens (`null` pour alterner).
typedef DatasourceActionDraft = ({
  String? datasourceId,
  DatasourceCommand command,
  String field,
  DatasourceSortDirection? direction,
});

/// Choix de la datasource et de la commande d'une action `datasource`.
class DatasourceActionSettings extends StatefulWidget {
  /// Crée le sélecteur ; [onChanged] reçoit chaque nouvelle saisie.
  const DatasourceActionSettings({
    required this.store,
    required this.value,
    required this.onChanged,
    this.managerContext,
    super.key,
  });

  /// Saisie vide : aucune datasource, recherche.
  static const DatasourceActionDraft empty = (
    datasourceId: null,
    command: DatasourceCommand.search,
    field: '',
    direction: null,
  );

  /// Store dont les datasources sont proposées.
  final JsonRepositoryStore? store;

  /// Saisie courante.
  final DatasourceActionDraft value;

  /// Appelé avec la nouvelle saisie.
  final ValueChanged<DatasourceActionDraft> onChanged;

  /// Contexte depuis lequel ouvrir le gestionnaire de datasources (il doit
  /// voir le même `JsonRepositoryScope` que [store]) ; défaut : ce widget.
  final BuildContext? managerContext;

  /// Action décrite par [draft], ou le message expliquant pourquoi elle est
  /// incomplète ; [config] (la datasource choisie, si connue) vérifie que la
  /// commande et le champ trié sont acceptés.
  static ({DatasourceAction? action, String? error}) actionOf(
    DatasourceActionDraft draft, [
    DatasourceConfig? config,
  ]) {
    final id = draft.datasourceId;
    if (id == null) return (action: null, error: 'Choisissez une datasource.');
    final command = draft.command;
    if (config != null && !config.supports(command)) {
      return (
        action: null,
        error:
            'La datasource « ${config.label} » ne supporte pas la commande '
            '« ${command.label} ».',
      );
    }
    final sort = command == DatasourceCommand.sort;
    final field = draft.field.trim();
    final action = DatasourceAction(
      datasourceId: id,
      command: command,
      field: sort ? (field.isEmpty ? null : field) : null,
      direction: sort ? draft.direction : null,
    );
    try {
      action.validate();
    } on FormatException catch (error) {
      return (action: null, error: error.message);
    }
    final allowed = config?.search?.sort;
    if (sort && allowed != null && !allowed.allows(field)) {
      return (
        action: null,
        error: 'Champ « $field » non triable : ${allowed.fields.join(', ')}.',
      );
    }
    return (action: action, error: null);
  }

  @override
  State<DatasourceActionSettings> createState() =>
      _DatasourceActionSettingsState();
}

class _DatasourceActionSettingsState extends State<DatasourceActionSettings> {
  late final TextEditingController _field = TextEditingController(
    text: widget.value.field,
  );

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    if (store != null) {
      unawaited(store.providers.ensureLoaded());
      unawaited(store.datasources.ensureLoaded());
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _emit({
    String? datasourceId,
    DatasourceCommand? command,
    String? field,
    DatasourceSortDirection? direction,
    bool clearDirection = false,
  }) {
    final value = widget.value;
    widget.onChanged((
      datasourceId: datasourceId ?? value.datasourceId,
      command: command ?? value.command,
      field: field ?? _field.text,
      direction: clearDirection ? null : direction ?? value.direction,
    ));
  }

  /// Choisit [config] en conservant la commande si elle reste supportée.
  void _select(DatasourceConfig config) {
    final commands = config.commands;
    final command = commands.contains(widget.value.command)
        ? widget.value.command
        : commands.firstOrNull ?? DatasourceCommand.search;
    _emit(datasourceId: config.id, command: command);
  }

  Future<void> _openManager({bool createNew = false}) async {
    final launcher = widget.managerContext;
    final id = await DatasourceManager.show(
      launcher != null && launcher.mounted ? launcher : context,
      initialDatasourceId: createNew ? null : widget.value.datasourceId,
      createNew: createNew,
    );
    if (id == null || !mounted) return;
    final config = widget.store?.datasources.datasource(id);
    if (config != null) _select(config);
  }

  String _commandHelp(DatasourceCommand command) => switch (command) {
    DatasourceCommand.search =>
      'Relance la recherche depuis la première page avec le filtre courant.',
    DatasourceCommand.refresh => 'Recharge la page affichée.',
    DatasourceCommand.firstPage ||
    DatasourceCommand.previousPage ||
    DatasourceCommand.nextPage => 'Navigue dans les pages de résultats.',
    DatasourceCommand.loadMore =>
      'Ajoute la page suivante à la fin de la liste (« Charger plus »).',
    DatasourceCommand.sort =>
      'Trie sur le champ choisi puis relance la recherche.',
    DatasourceCommand.create =>
      'Crée une entité depuis le filtre du provider Create ; elle est '
          'ajoutée à la liste et sélectionnée.',
    DatasourceCommand.read ||
    DatasourceCommand.update ||
    DatasourceCommand.delete =>
      'Agit sur l’entité courante : la ligne du composant dans une liste, '
          'sinon la ligne sélectionnée, sinon le détail lu par Read.',
  };

  Widget _commandSettings(ThemeData theme, DatasourceConfig config) {
    final commands = config.commands;
    final command = widget.value.command;
    final sort = config.search?.sort;
    final (:action, :error) = DatasourceActionSettings.actionOf(
      widget.value,
      config,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        InputDecorator(
          key: const ValueKey('behavior-datasource-command'),
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Commande',
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<DatasourceCommand>(
              value: commands.contains(command) ? command : null,
              isExpanded: true,
              isDense: true,
              items: [
                for (final candidate in commands)
                  DropdownMenuItem(
                    value: candidate,
                    child: Text(candidate.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) _emit(command: value);
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _commandHelp(command),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (command == DatasourceCommand.sort) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('behavior-datasource-field'),
            controller: _field,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Champ trié',
              helperText: sort == null || sort.fields.isEmpty
                  ? null
                  : 'Champs triables : ${sort.fields.join(', ')}.',
            ),
            onChanged: (value) => _emit(field: value),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            key: const ValueKey('behavior-datasource-direction'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Alterner')),
              ButtonSegment(value: 1, label: Text('Croissant')),
              ButtonSegment(value: 2, label: Text('Décroissant')),
            ],
            selected: {
              switch (widget.value.direction) {
                null => 0,
                DatasourceSortDirection.asc => 1,
                DatasourceSortDirection.desc => 2,
              },
            },
            onSelectionChanged: (selection) => switch (selection.first) {
              1 => _emit(direction: DatasourceSortDirection.asc),
              2 => _emit(direction: DatasourceSortDirection.desc),
              _ => _emit(clearDirection: true),
            },
          ),
        ],
        if (error != null &&
            (command != DatasourceCommand.sort ||
                _field.text.trim().isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              key: const ValueKey('behavior-datasource-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = widget.store;
    if (store == null) {
      return const Text(
        'Service de repositories indisponible : aucune datasource ne peut '
        'être lancée.',
      );
    }
    final registry = store.datasources;
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final datasources = registry.datasources;
        final selected = widget.value.datasourceId == null
            ? null
            : registry.datasource(widget.value.datasourceId!);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Datasource',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Une datasource regroupe les providers Search, Create, Read, '
                'Update et Delete d’une même notion et met à jour la liste et '
                'la sélection après chaque opération.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (datasources.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Aucune datasource : créez-en une pour continuer.',
                    key: ValueKey('behavior-datasource-empty'),
                  ),
                )
              else
                for (final datasource in datasources)
                  ListTile(
                    key: ValueKey('behavior-datasource-${datasource.id}'),
                    dense: true,
                    leading: Icon(
                      datasource.id == widget.value.datasourceId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(datasource.label),
                    subtitle: Text(
                      '${datasource.id} · '
                      '${datasource.operations.map((op) => op.title).join(', ')}'
                      '${registry.isEditable(datasource.id) ? '' : ' · code'}',
                    ),
                    selected: datasource.id == widget.value.datasourceId,
                    onTap: () => _select(datasource),
                  ),
              if (widget.value.datasourceId != null && selected == null)
                Text(
                  'Datasource « ${widget.value.datasourceId} » introuvable.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (selected != null) _commandSettings(theme, selected),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('behavior-datasource-create'),
                    onPressed: () => _openManager(createNew: true),
                    icon: const Icon(Icons.add),
                    label: const Text('Créer une datasource…'),
                  ),
                  if (datasources.isNotEmpty)
                    TextButton.icon(
                      key: const ValueKey('behavior-datasource-manage'),
                      onPressed: _openManager,
                      icon: const Icon(Icons.tune),
                      label: const Text('Gérer les datasources…'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
