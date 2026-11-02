/// Formulaire initial et assistant d'ajout du renderer d'apparence.
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/super_renderer_config.dart';
import '../addition/component_add_wizard.dart';
import '../dialogs/editor_dialog.dart';

/// Reglages proposes lors de l'ajout d'un renderer au catalogue.
final superRendererAddConfigurator =
    ComponentAddConfigurator<SuperRendererConfig>(
      initial: (_) => const SuperRendererConfig(),
      builder: (context, draft, onChanged) =>
          SuperRendererForm(config: draft, onChanged: onChanged),
      validate: (draft) {
        try {
          draft.validate();
          return null;
        } on FormatException catch (error) {
          return error.message;
        }
      },
      summary: (draft) => [
        ('Racine', draft.rootId ?? 'Page d\'accueil'),
        ('Document', draft.source.isEmpty ? 'A importer' : 'JSON fourni'),
      ],
      apply: (registry, id, draft) =>
          registry
                  .componentController<SuperRendererConfig>(
                    id,
                    fallback: const SuperRendererConfig(),
                  )
                  .value =
              draft,
    );

/// Edite la source initiale, distincte du document importe en memoire.
Future<SuperRendererConfig?> showSuperRendererEditor(
  BuildContext context,
  SuperRendererConfig config,
) => showEditorDialog<SuperRendererConfig>(
  context: context,
  builder: (_) => _RendererConfigDialog(initial: config),
);

/// Champs reutilises pour l'ajout et la configuration du renderer.
class SuperRendererForm extends StatelessWidget {
  const SuperRendererForm({
    required this.config,
    required this.onChanged,
    super.key,
  });

  final SuperRendererConfig config;
  final ValueChanged<SuperRendererConfig> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextFormField(
        key: const ValueKey('renderer-source'),
        initialValue: config.source,
        minLines: 5,
        maxLines: 10,
        decoration: const InputDecoration(
          labelText: 'JSON initial d\'apparence',
        ),
        onChanged: (value) => onChanged(config.copyWith(source: value)),
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const ValueKey('renderer-root'),
        initialValue: config.rootId,
        decoration: const InputDecoration(
          labelText: 'Page ou composant racine (facultatif)',
        ),
        onChanged: (value) => onChanged(
          config.copyWith(rootId: value, clearRoot: value.trim().isEmpty),
        ),
      ),
      SwitchListTile(
        title: const Text('Afficher la commande d\'import'),
        value: config.showImport,
        onChanged: (value) => onChanged(config.copyWith(showImport: value)),
      ),
      const Text(
        'Les editions du contenu restent en memoire. '
        'L\'application hote decide de leur sauvegarde.',
      ),
    ],
  );
}

class _RendererConfigDialog extends StatefulWidget {
  const _RendererConfigDialog({required this.initial});
  final SuperRendererConfig initial;

  @override
  State<_RendererConfigDialog> createState() => _RendererConfigDialogState();
}

class _RendererConfigDialogState extends State<_RendererConfigDialog> {
  late var _draft = widget.initial;
  String? _error;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Configurer SuperRenderer'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SuperRendererForm(
              config: _draft,
              onChanged: (value) => setState(() => _draft = value),
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          try {
            _draft.validate();
            Navigator.of(context).pop(_draft);
          } on FormatException catch (error) {
            setState(() => _error = error.message);
          }
        },
        child: const Text('Appliquer'),
      ),
    ],
  );
}
