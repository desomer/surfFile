/// Assistant d'ajout du composant SuperCode avec liaison au repository.
library;

import 'package:super_container_layout/super_container_layout.dart';

import '../../../extensions_registry.dart';
import '../../../models/super_code_config.dart';
import 'forms/code_add_form.dart';

/// Parametres d'ajout et persistance via le controleur du registre.
final codeAddConfigurator = ComponentAddConfigurator<SuperCodeConfig>(
  initial: (_) => const SuperCodeConfig(),
  builder: (context, draft, onChanged) =>
      CodeAddForm(draft: draft, onChanged: onChanged),
  validate: (draft) {
    try {
      draft.validate();
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  },
  summary: (draft) => [
    ('Langage', draft.mode.label),
    ('Lecture seule', draft.readOnly ? 'oui' : 'non'),
    ('Liaison', draft.binding?.path ?? 'Aucune'),
  ],
  apply: (registry, id, draft) => registry.codeController(id).value = draft,
  readBinding: (draft) => draft.binding,
  writeBinding: (draft, binding) =>
      draft.copyWith(binding: binding, clearBinding: binding == null),
  bindingKeyPrefix: 'add-code',
  bindingPathHint: 'scripts[?].source',
  bindingHelp: 'Le code est stocke comme une chaine de texte dans le repository JSON.',
);
