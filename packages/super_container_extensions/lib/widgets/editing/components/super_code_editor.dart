/// Dialogue de configuration de SuperCode avec les onglets standard du moteur.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../../models/super_code_config.dart';
import '../addition/forms/code_add_form.dart';

/// Ouvre les reglages de langage, lecture seule et liaison du composant.
Future<SuperCodeConfig?> showSuperCodeEditor({
  required BuildContext context,
  required SuperCodeConfig config,
}) {
  final store = JsonRepositoryScope.maybeOf(context);
  final scope = JsonListScope.maybeOf(context);
  return runWithDimensionDelegate<SuperCodeConfig>(
    context: context,
    runner: (initialTab, dimensionDelegate) => showEditorDialog<SuperCodeConfig>(
      context: context,
      target: context,
      builder: (_) => _CodeEditorDialog(
        config: config,
        store: store,
        scope: scope,
        initialTab: initialTab,
        dimensionDelegate: dimensionDelegate,
      ),
    ),
  );
}

class _CodeEditorDialog extends StatefulWidget {
  const _CodeEditorDialog({
    required this.config,
    required this.store,
    required this.scope,
    required this.initialTab,
    required this.dimensionDelegate,
  });

  final SuperCodeConfig config;
  final JsonRepositoryStore? store;
  final JsonListScope? scope;
  final EditorWizardTab initialTab;
  final EditorDimensionDelegate? dimensionDelegate;

  @override
  State<_CodeEditorDialog> createState() => _CodeEditorDialogState();
}

class _CodeEditorDialogState extends State<_CodeEditorDialog> {
  final _form = GlobalKey<FormState>();
  late SuperCodeConfig _draft = widget.config;
  String? _error;
  bool _busy = false;

  Future<bool> _apply() async {
    if (!_form.currentState!.validate()) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = _draft;
      draft.validate();
      final binding = draft.binding;
      if (binding != null && !(widget.scope?.placeholder ?? false)) {
        final store = widget.store;
        if (store == null) {
          throw const FormatException('Repository indisponible.');
        }
        final resolved = JsonListScope.resolveSelected(binding, widget.scope, store).binding;
        if (resolved != null) {
          final value = (await store.readAttribute(resolved)).value;
          if (value != null && value is! String) {
            throw const FormatException('Le chemin doit cibler une chaine de texte.');
          }
        }
      }
      if (mounted) Navigator.of(context).pop(draft);
      return true;
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    } on FileSystemException {
      if (mounted) setState(() => _error = 'Impossible de lire le repository.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => EditorTabbedAlertDialog(
    dialogKey: const ValueKey('super-code-editor'),
    applyButtonKey: const ValueKey('super-code-apply'),
    initialTab: widget.initialTab,
    dimensionDelegate: widget.dimensionDelegate,
    propertiesTitle: const EditorDialogHeader(label: 'Configurer le code'),
    propertiesWidth: 480,
    busy: _busy,
    onApply: _apply,
    onCancel: () => Navigator.of(context).pop(),
    propertiesContentBuilder: (context) => Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          CodeAddForm(
            draft: _draft,
            onChanged: (value) => setState(() => _draft = value),
          ),
          RepositoryBindingFields(
            keyPrefix: 'super-code-binding',
            binding: _draft.binding,
            store: widget.store,
            listScope: widget.scope,
            pathHint: 'scripts[?].source',
            helper: 'Chaine de texte YAML ou JavaScript. Le code n’est pas execute.',
            onChanged: (binding) => setState(() {
              _draft = _draft.copyWith(binding: binding, clearBinding: binding == null);
            }),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    ),
  );
}
