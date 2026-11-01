/// Configurateur d'assistant d'ajout ([chartAddConfigurator]) pour un composant [SuperChart].
library;

import 'package:super_container_layout/super_container_layout.dart';

import '../../../extensions_registry.dart';
import '../../../models/super_chart_config.dart';
import 'forms/chart_add_form.dart';

export 'forms/chart_add_form.dart' show ChartAddForm;

String _yes(bool value) => value ? 'oui' : 'non';

String _bindingLabel(JsonTextBinding? binding) => binding == null
    ? 'Aucune'
    : '${binding.repositoryId ?? 'Repository hérité'} · ${binding.path}';

/// Paramètres de l'assistant d'ajout pour un `SuperChart`, écrits dans `Registry.chartController`.
final chartAddConfigurator = ComponentAddConfigurator<SuperChartConfig>(
  initial: (_) => const SuperChartConfig(),
  builder: (context, draft, onChanged) =>
      ChartAddForm(draft: draft, onChanged: onChanged),
  validate: (draft) {
    if (draft.binding?.path.trim().isEmpty ?? false) {
      return 'Chemin de liaison requis.';
    }
    try {
      draft.validate();
      return null;
    } on FormatException catch (error) {
      return error.message;
    } on Object {
      return 'Configuration du graphique invalide.';
    }
  },
  summary: (draft) => [
    ('Type', draft.kind.label),
    if (draft.labelPath.isNotEmpty) ('Axe X / Libellé', draft.labelPath),
    (
      'Séries',
      draft.series.map((s) => '${s.label} (${s.valuePath})').join(', '),
    ),
    ('Légende', _yes(draft.showLegend)),
    ('Grille', _yes(draft.showGrid)),
    ('Sélection synchronisée', _yes(draft.enableSelection)),
    ('Liaison', _bindingLabel(draft.binding)),
  ],
  apply: (registry, id, draft) => registry.chartController(id).value = draft,
  readBinding: (draft) => draft.binding,
  writeBinding: (draft, binding) =>
      draft.copyWith(binding: binding, clearBinding: binding == null),
  bindingKeyPrefix: 'add-chart',
  bindingPathHint: 'ventes ou clients[?].commandes',
  bindingHelp:
      'Chaque élément du tableau fournit un point ou une catégorie du graphique.',
);
