/// Boîte de dialogue « Configure as... » permettant de configurer le comportement d'un composant lors de l'export en code Dart.
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/registry.dart';
import 'editor_dialog.dart';

/// Affiche la boîte de dialogue « Configure as... » pour l'élément [componentId].
Future<ComponentExportOptions?> showComponentExportConfigDialog({
  required BuildContext context,
  required String componentId,
  required String defaultLabel,
  ComponentExportOptions? initialOptions,
  BuildContext? target,
}) {
  final defaultName =
      (initialOptions?.componentName.trim().isNotEmpty ?? false)
      ? initialOptions!.componentName.trim()
      : componentId.replaceFirst(RegExp(r'-(?:i|[0-9]+)$'), '');

  return showEditorDialog<ComponentExportOptions>(
    context: context,
    target: target ?? context,
    builder: (dialogContext) => ComponentExportConfigDialog(
      componentId: componentId,
      defaultLabel: defaultLabel,
      initialOptions:
          initialOptions?.copyWith(componentName: defaultName) ??
          ComponentExportOptions(componentName: defaultName),
    ),
  );
}

/// Boîte de dialogue permettant d'indiquer si un composant doit générer un
/// `_registry.registerComponent(...)` lors de l'export en code Dart et s'il
/// doit être forcé en composant non décomposable.
class ComponentExportConfigDialog extends StatefulWidget {
  const ComponentExportConfigDialog({
    required this.componentId,
    required this.defaultLabel,
    required this.initialOptions,
    super.key,
  });

  /// Identifiant technique du slot ou du composant ciblé.
  final String componentId;

  /// Libellé courant affiché pour ce composant.
  final String defaultLabel;

  /// Options d'export initiales.
  final ComponentExportOptions initialOptions;

  @override
  State<ComponentExportConfigDialog> createState() =>
      _ComponentExportConfigDialogState();
}

class _ComponentExportConfigDialogState
    extends State<ComponentExportConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialOptions.componentName,
  );
  late bool _generateComponentOnExport =
      widget.initialOptions.generateComponentOnExport;
  late bool _forceComponentOnExport =
      widget.initialOptions.forceComponentOnExport;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    if (_generateComponentOnExport &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      ComponentExportOptions(
        componentName: _nameController.text.trim(),
        generateComponentOnExport: _generateComponentOnExport,
        forceComponentOnExport:
            _generateComponentOnExport && _forceComponentOnExport,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Configure as...'),
          const SizedBox(height: 2),
          Text(
            '${widget.defaultLabel} (${widget.componentId})',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('configure-as-component-name'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom du composant (clé de registre)',
                    helperText:
                        'Identifiant utilisé dans _registry.registerComponent(...)',
                  ),
                  validator: (value) {
                    if (_generateComponentOnExport &&
                        (value == null || value.trim().isEmpty)) {
                      return 'Le nom du composant ne peut pas être vide.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  key: const ValueKey('configure-as-generate-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Générer un composant à l’export de code'),
                  subtitle: const Text(
                    'Extrait cet élément dans un _registry.registerComponent(...) dédié lors de l’export Dart.',
                  ),
                  value: _generateComponentOnExport,
                  onChanged: (value) {
                    setState(() {
                      _generateComponentOnExport = value;
                      if (!value) {
                        _forceComponentOnExport = false;
                      }
                    });
                  },
                ),
                SwitchListTile(
                  key: const ValueKey('configure-as-force-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Forcer en composant à l’export'),
                  subtitle: const Text(
                    'Empêche la décomposition de ce composant même si « Décomposer les composants composés » est activé.',
                  ),
                  value: _forceComponentOnExport,
                  onChanged: (value) {
                    setState(() {
                      _forceComponentOnExport = value;
                      if (value) {
                        _generateComponentOnExport = true;
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('configure-as-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('configure-as-save'),
          onPressed: _save,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
