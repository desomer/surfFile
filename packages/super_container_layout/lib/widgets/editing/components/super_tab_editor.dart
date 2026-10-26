import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../models/super_tab_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../dialogs/editor_dialog.dart';
import '../repositories/repository_binding_fields.dart';

/// Ouvre la fenêtre de réglage pour un composant [SuperTab] ([config]).
Future<SuperTabConfig?> showSuperTabEditor({
  required BuildContext context,
  required SuperTabConfig config,
}) {
  final repositories = JsonRepositoryScope.maybeOf(context);
  final scope = JsonListScope.maybeOf(context);
  return showEditorDialog<SuperTabConfig>(
    context: context,
    target: context,
    builder: (_) => _SuperTabEditor(
      config: config,
      repositories: repositories,
      scope: scope,
    ),
  );
}

class _SuperTabEditor extends StatefulWidget {
  const _SuperTabEditor({
    required this.config,
    required this.repositories,
    required this.scope,
  });

  final SuperTabConfig config;
  final JsonRepositoryStore? repositories;
  final JsonListScope? scope;

  @override
  State<_SuperTabEditor> createState() => _SuperTabEditorState();
}

class _SuperTabEditorState extends State<_SuperTabEditor> {
  late SuperTabConfig _draft = widget.config;
  late final TextEditingController _initialIndex = TextEditingController(
    text: '${widget.config.initialIndex}',
  );
  late final TextEditingController _emptyText = TextEditingController(
    text: widget.config.emptyText,
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _initialIndex.dispose();
    _emptyText.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final parsedIndex = int.tryParse(_initialIndex.text.trim());
    if (parsedIndex == null || parsedIndex < 0) {
      setState(() => _error = 'L’index initial doit être un entier >= 0.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = _draft.copyWith(
        initialIndex: parsedIndex,
        emptyText: _emptyText.text,
      )..validate();
      final binding = config.binding;
      final scope = widget.scope;
      if (binding != null && !(scope?.placeholder ?? false)) {
        if (binding.path.trim().isEmpty) {
          throw const FormatException('Chemin de liaison requis.');
        }
        final store = widget.repositories;
        if (store != null && config.mode == SuperTabMode.dynamic) {
          final resolved = JsonListScope.resolveSelected(
            binding,
            scope,
            store,
          ).binding;
          if (resolved != null) {
            await store.readArray(resolved.repositoryId!, resolved.path);
          }
        }
      }
      if (mounted) Navigator.of(context).pop(config);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException {
      if (mounted) setState(() => _error = 'Impossible de lire le repository.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDynamic = _draft.mode == SuperTabMode.dynamic;
    return AlertDialog(
      key: const ValueKey('super-tab-settings'),
      title: const Text('Configurer les onglets'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              DropdownButtonFormField<SuperTabMode>(
                key: const ValueKey('super-tab-mode'),
                initialValue: _draft.mode,
                decoration: const InputDecoration(
                  labelText: 'Mode des onglets',
                ),
                items: const [
                  DropdownMenuItem(
                    value: SuperTabMode.static,
                    child: Text('Statique (onglets fixes)'),
                  ),
                  DropdownMenuItem(
                    value: SuperTabMode.dynamic,
                    child: Text('Dynamique (tableau JSON du repository)'),
                  ),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    setState(() => _draft = _draft.copyWith(mode: mode));
                  }
                },
              ),
              DropdownButtonFormField<SuperTabBarPosition>(
                key: const ValueKey('super-tab-position'),
                initialValue: _draft.tabBarPosition,
                decoration: const InputDecoration(
                  labelText: 'Position de la barre d’onglets',
                ),
                items: const [
                  DropdownMenuItem(
                    value: SuperTabBarPosition.top,
                    child: Text('En haut'),
                  ),
                  DropdownMenuItem(
                    value: SuperTabBarPosition.bottom,
                    child: Text('En bas'),
                  ),
                ],
                onChanged: (pos) {
                  if (pos != null) {
                    setState(
                      () => _draft = _draft.copyWith(tabBarPosition: pos),
                    );
                  }
                },
              ),
              SwitchListTile(
                key: const ValueKey('super-tab-scrollable'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Onglets défilables'),
                subtitle: const Text(
                  'Défilement horizontal au lieu d’étirer sur toute la largeur',
                ),
                value: _draft.isScrollable,
                onChanged: (value) =>
                    setState(() => _draft = _draft.copyWith(isScrollable: value)),
              ),
              TextFormField(
                key: const ValueKey('super-tab-initial-index'),
                controller: _initialIndex,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Index d’onglet initial',
                ),
              ),
              if (isDynamic) ...[
                SwitchListTile(
                  key: const ValueKey('super-tab-allow-add'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoriser l’ajout d’onglet'),
                  value: _draft.allowAdd,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(allowAdd: value)),
                ),
                SwitchListTile(
                  key: const ValueKey('super-tab-allow-remove'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoriser la suppression d’onglet'),
                  value: _draft.allowRemove,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(allowRemove: value),
                  ),
                ),
                TextFormField(
                  key: const ValueKey('super-tab-empty-text'),
                  controller: _emptyText,
                  decoration: const InputDecoration(
                    labelText: 'Message si aucun onglet',
                  ),
                ),
              ],
              const Divider(),
              Text(
                isDynamic
                    ? 'Tableau JSON source des onglets'
                    : 'Liaison optionnelle de l’index actif',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              RepositoryBindingFields(
                keyPrefix: 'super-tab-binding',
                binding: _draft.binding,
                store: widget.repositories,
                listScope: widget.scope,
                pathHint: isDynamic
                    ? 'categories ou clients[?].commandes'
                    : 'ui.ongletActif',
                onChanged: (binding) => setState(
                  () => _draft = _draft.copyWith(
                    binding: binding,
                    clearBinding: binding == null,
                  ),
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const ValueKey('super-tab-editor-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('super-tab-apply'),
          onPressed: _busy ? null : _apply,
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}
