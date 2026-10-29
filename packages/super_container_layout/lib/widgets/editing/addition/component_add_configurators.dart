import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/native_component_config.dart';
import '../../../models/native_property_descriptor.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../models/super_chart_config.dart';
import '../../../models/super_value_config.dart';
import '../../../models/super_action_config.dart';
import '../../../theme/container_style.dart';
import '../../components/super_layout/super_layout.dart';
import 'component_add_wizard.dart';
import 'forms/chart_add_form.dart';
import 'forms/container_add_form.dart';
import 'forms/expansible_add_form.dart';
import 'forms/list_view_add_form.dart';
import 'forms/menu_anchor_add_form.dart';
import 'forms/super_action_add_form.dart';
import 'forms/super_value_add_form.dart';
import 'forms/tab_add_form.dart';
import 'forms/tree_view_add_form.dart';

export '../repositories/repository_binding_fields.dart'
    show RepositoryBindingFields;
export 'forms/chart_add_form.dart' show ChartAddForm;
export 'forms/container_add_form.dart' show ContainerAddForm;
export 'forms/expansible_add_form.dart' show ExpansibleAddForm;
export 'forms/list_view_add_form.dart' show ListViewAddForm;
export 'forms/menu_anchor_add_form.dart' show MenuAnchorAddForm;
export 'forms/super_action_add_form.dart' show SuperActionAddForm;
export 'forms/super_value_add_form.dart' show SuperValueAddForm;
export 'forms/tab_add_form.dart' show TabAddForm;
export 'forms/tree_view_add_form.dart' show TreeViewAddForm;

/// Add wizard settings of a `SuperValue`, written to `Registry.valueController`.
ComponentAddConfigurator<SuperValueConfig> superValueAddConfigurator(
  List<String> availableFontFamilies,
) => ComponentAddConfigurator<SuperValueConfig>(
  initial: (_) => const SuperValueConfig(),
  builder: (context, draft, onChanged) => SuperValueAddForm(
    draft: draft,
    onChanged: onChanged,
    availableFontFamilies: availableFontFamilies,
  ),
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
      return 'Configuration de la valeur invalide.';
    }
  },
  summary: (draft) => [
    if (draft.kind != SuperValueKind.text)
      ('Type', draft.kind == SuperValueKind.checkbox ? 'Checkbox' : 'Switch'),
    ('Mode', draft.mode == SuperValueMode.input ? 'Saisie' : 'Affichage'),
    if (!draft.kind.isBoolean && draft.initialText.isNotEmpty)
      ('Texte initial', draft.initialText),
    if (draft.kind.isBoolean) ('Valeur initiale', _yes(draft.initialBool)),
    if (draft.label.isNotEmpty) ('Libellé du champ', draft.label),
    if (!draft.kind.isBoolean && draft.placeholder.isNotEmpty)
      ('Texte indicatif', draft.placeholder),
    if (draft.fontSize != null) ('Taille du texte', '${draft.fontSize}'),
    ('Alignement', _alignLabel(draft.textAlign)),
    ('Liaison', _bindingLabel(draft.binding)),
  ],
  apply: (registry, id, draft) => registry.valueController(id).value = draft,
  readBinding: (draft) => draft.binding,
  writeBinding: (draft, binding) =>
      draft.copyWith(binding: binding, clearBinding: binding == null),
  bindingKeyPrefix: 'add-value',
  bindingPathHint: 'client.nom ou clients[?].nom',
  bindingHelp: 'Le repository fournit la valeur (liaison bidirectionnelle).',
);

/// Add wizard settings of a `SuperAction`, written to `Registry.actionController`.
ComponentAddConfigurator<SuperActionConfig> superActionAddConfigurator(
  List<String> availableFontFamilies,
) => ComponentAddConfigurator<SuperActionConfig>(
  initial: (_) => const SuperActionConfig(),
  builder: (context, draft, onChanged) => SuperActionAddForm(
    draft: draft,
    onChanged: onChanged,
    availableFontFamilies: availableFontFamilies,
  ),
  validate: (draft) {
    try {
      draft.validate();
      return null;
    } on FormatException catch (error) {
      return error.message;
    } on Object {
      return 'Configuration de l’action invalide.';
    }
  },
  summary: (draft) => [
    (
      'Type',
      switch (draft.kind) {
        SuperActionKind.text => 'Texte',
        SuperActionKind.icon => 'Icône',
        SuperActionKind.textAndIcon => 'Texte et icône',
      },
    ),
    ('Variante', draft.variant.name),
    if (draft.kind.hasText && draft.label.isNotEmpty) ('Libellé', draft.label),
    if (draft.kind.hasIcon)
      (
        'Icône',
        draft.icon.trim().isEmpty
            ? 'Aucune'
            : SuperActionIcons.labelOf(draft.icon),
      ),
    if (draft.fontSize != null) ('Taille du texte', '${draft.fontSize}'),
    if (draft.iconSize != null) ('Taille de l’icône', '${draft.iconSize}'),
    ('Alignement', _alignLabel(draft.textAlign)),
  ],
  apply: (registry, id, draft) => registry.actionController(id).value = draft,
);

/// Add wizard settings of a `SuperListView`, written to `Registry.listController`.
final listViewAddConfigurator = ComponentAddConfigurator<SuperListViewConfig>(
  initial: (_) => const SuperListViewConfig(),
  builder: (context, draft, onChanged) =>
      ListViewAddForm(draft: draft, onChanged: onChanged),
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
      return 'Configuration de la liste invalide.';
    }
  },
  summary: (draft) => [
    (
      'Disposition',
      draft.wrap
          ? 'Wrap'
          : draft.axis == Axis.vertical
          ? 'Verticale'
          : 'Horizontale',
    ),
    if (draft.wrap) ('Largeur des items', '${draft.itemWidth}'),
    ('Taille des items', '${draft.itemExtent}'),
    ('Espacement', '${draft.spacing}'),
    (
      'Ajout / suppression',
      '${_yes(draft.allowAdd)} / ${_yes(draft.allowRemove)}',
    ),
    ('Liste vide', draft.emptyText),
    ('Liaison', _bindingLabel(draft.binding)),
  ],
  apply: (registry, id, draft) => registry.listController(id).value = draft,
  readBinding: (draft) => draft.binding,
  writeBinding: (draft, binding) =>
      draft.copyWith(binding: binding, clearBinding: binding == null),
  bindingKeyPrefix: 'add-list',
  bindingPathHint: 'clients ou clients[?].commandes',
  bindingHelp: 'Chaque élément du tableau devient une ligne de la liste.',
);

/// Add wizard settings of a `SuperTreeView`, written to `Registry.treeViewController`.
final treeViewAddConfigurator =
    ComponentAddConfigurator<SuperTreeViewConfig>(
      initial: (_) => SuperTreeViewConfig(),
      builder: (context, draft, onChanged) =>
          TreeViewAddForm(draft: draft, onChanged: onChanged),
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
          return 'Configuration du TreeView invalide.';
        }
      },
      summary: (draft) => [
        ('Clé enfants', draft.childrenKey),
        ('Largeur Header', '${draft.headerSize}'),
        ('Hauteur ligne', '${draft.rowHeight}'),
        ('Déplié par défaut', _yes(draft.initiallyExpanded)),
        ('Connecteurs', _yes(draft.showConnectors)),
        ('Liaison', _bindingLabel(draft.binding)),
      ],
      apply: (registry, id, draft) =>
          registry.treeViewController(id).value = draft,
      readBinding: (draft) => draft.binding,
      writeBinding: (draft, binding) =>
          draft.copyWith(binding: binding, clearBinding: binding == null),
      bindingKeyPrefix: 'add-tree',
      bindingPathHint: 'nodes ou clients[?].categories',
      bindingHelp:
          'Tableau ou objet JSON de nœuds récursifs affichés dans le TreeView.',
    );

/// Add wizard settings of a nested `SuperLayout`.
final layoutAddConfigurator = ComponentAddConfigurator<SuperLayoutConfig>(
  initial: (_) => const SuperLayoutConfig(),
  builder: (context, draft, onChanged) =>
      SuperLayoutEditor(config: draft, onChanged: onChanged),
  summary: (draft) {
    final sides = [
      for (final zone in [
        SuperLayoutZone.north,
        SuperLayoutZone.south,
        SuperLayoutZone.west,
        SuperLayoutZone.east,
      ])
        if (draft.hasSide(zone)) zone.label,
    ];
    return [
      (
        'Disposition',
        draft.positioning == SuperLayoutPositioning.grid ? 'Grille' : 'Zones',
      ),
      ('Côtés', sides.isEmpty ? 'Centre seul' : sides.join(', ')),
    ];
  },
  apply: (registry, id, draft) => registry.layoutController(id).value = draft,
);

/// Add wizard settings of a `NewContainer` style.
final containerAddConfigurator = ComponentAddConfigurator<ContainerStyle>(
  initial: (_) => const ContainerStyle(),
  builder: (context, draft, onChanged) =>
      ContainerAddForm(draft: draft, onChanged: onChanged),
  summary: (draft) => [
    (
      'Couleur',
      draft.color == null
          ? 'Par défaut'
          : '#${draft.color!.toARGB32().toRadixString(16).padLeft(8, '0')}',
    ),
    ('Rayon', draft.radius.toStringAsFixed(0)),
    ('Bordure', draft.borderWidth.toStringAsFixed(0)),
    ('Marge intérieure', draft.padding.toStringAsFixed(0)),
    ('Marge extérieure', draft.margin.toStringAsFixed(0)),
    ('Élévation', draft.elevation.toStringAsFixed(0)),
  ],
  apply: (registry, id, draft) => registry.styleController(id).value = draft,
);

/// Add wizard settings of a `SuperExpansible`, written to `Registry.nativeComponentController`.
final expansibleAddConfigurator =
    ComponentAddConfigurator<NativeComponentConfig>(
      initial: (_) =>
          NativeComponentConfig(regions: const {'header': true, 'body': true}),
      builder: (context, draft, onChanged) =>
          ExpansibleAddForm(draft: draft, onChanged: onChanged),
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
          return 'Configuration de l’expansible invalide.';
        }
      },
      summary: (draft) => [
        ('Ouvert par défaut', _yes(draft.initiallyExpanded ?? false)),
        ('Clic sur l’en-tête', _yes(draft.headerClickToggles ?? true)),
        ('Maintenir l’état', _yes(draft.maintainState ?? true)),
        if (draft.toggleIcon != null && draft.toggleIcon != 'none') ...[
          ('Icône ouvert/fermé', nativeToggleIconLabel(draft.toggleIcon)),
          (
            'Position de l’icône',
            nativeToggleIconPositionLabel(draft.toggleIconPosition),
          ),
        ],
        ('Liaison', _bindingLabel(draft.binding)),
      ],
      apply: (registry, id, draft) =>
          registry.nativeComponentController(id).value = draft,
      readBinding: (draft) => draft.binding,
      writeBinding: (draft, binding) => draft.withBinding(binding),
      bindingKeyPrefix: 'add-expansible',
      bindingPathHint: 'ui.ouvert ou clients[?].ouvert',
      bindingHelp:
          'Le repository fournit et persiste l’état ouvert/fermé (booléen).',
    );

/// Add wizard settings of a `SuperMenuAnchor`, written to `Registry.nativeComponentController`.
final menuAnchorAddConfigurator =
    ComponentAddConfigurator<NativeComponentConfig>(
      initial: (_) =>
          NativeComponentConfig(regions: const {'header': true, 'body': true}),
      builder: (context, draft, onChanged) =>
          MenuAnchorAddForm(draft: draft, onChanged: onChanged),
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
          return 'Configuration du menu invalide.';
        }
      },
      summary: (draft) => [
        ('Ouvert par défaut', _yes(draft.initiallyExpanded ?? false)),
        ('Clic sur l’en-tête', _yes(draft.headerClickToggles ?? true)),
        ('Consommer clic extérieur', _yes(draft.consumeOutsideTap ?? false)),
        if (draft.toggleIcon != null && draft.toggleIcon != 'none') ...[
          ('Icône ouvert/fermé', nativeToggleIconLabel(draft.toggleIcon)),
          (
            'Position de l’icône',
            nativeToggleIconPositionLabel(draft.toggleIconPosition),
          ),
        ],
        if (draft.alignmentOffset != null)
          (
            'Décalage',
            '(${draft.alignmentOffset!.dx.toStringAsFixed(0)}, ${draft.alignmentOffset!.dy.toStringAsFixed(0)})',
          ),
        ('Liaison', _bindingLabel(draft.binding)),
      ],
      apply: (registry, id, draft) =>
          registry.nativeComponentController(id).value = draft,
      readBinding: (draft) => draft.binding,
      writeBinding: (draft, binding) => draft.withBinding(binding),
      bindingKeyPrefix: 'add-menu-anchor',
      bindingPathHint: 'ui.menuOuvert ou clients[?].menuOuvert',
      bindingHelp:
          'Le repository fournit et persiste l’état ouvert/fermé du menu (booléen).',
    );

/// Add wizard settings of a `SuperTab`, written to `Registry.tabController`.
final tabAddConfigurator = ComponentAddConfigurator<SuperTabConfig>(
  initial: (_) => SuperTabConfig(),
  builder: (context, draft, onChanged) =>
      TabAddForm(draft: draft, onChanged: onChanged),
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
      return 'Configuration des onglets invalide.';
    }
  },
  summary: (draft) => [
    (
      'Mode',
      draft.mode == SuperTabMode.dynamic ? 'Dynamique' : 'Statique',
    ),
    (
      'Position de la barre',
      draft.tabBarPosition == SuperTabBarPosition.bottom ? 'En bas' : 'En haut',
    ),
    ('Indicateur', draft.indicatorKind.name),
    ('Onglets défilables', _yes(draft.isScrollable)),
    if (draft.mode == SuperTabMode.dynamic)
      (
        'Ajout / suppression',
        '${_yes(draft.allowAdd)} / ${_yes(draft.allowRemove)}',
      ),
    ('Liaison', _bindingLabel(draft.binding)),
  ],
  apply: (registry, id, draft) => registry.tabController(id).value = draft,
  readBinding: (draft) => draft.binding,
  writeBinding: (draft, binding) =>
      draft.copyWith(binding: binding, clearBinding: binding == null),
  bindingKeyPrefix: 'add-tab',
  bindingPathHint: 'categories ou ui.ongletActif',
  bindingHelp:
      'En mode dynamique : tableau JSON générant les onglets. En mode statique : index actif.',
);

/// Add wizard settings of a `SuperChart`, written to `Registry.chartController`.
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
    ('Séries', draft.series.map((s) => '${s.label} (${s.valuePath})').join(', ')),
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

String _yes(bool value) => value ? 'oui' : 'non';

String _bindingLabel(JsonTextBinding? binding) => binding == null
    ? 'Aucune'
    : '${binding.repositoryId ?? 'Repository hérité'} · ${binding.path}';

String _alignLabel(TextAlign align) => switch (align) {
  TextAlign.center => 'Centré',
  TextAlign.end || TextAlign.right => 'Fin',
  TextAlign.justify => 'Justifié',
  _ => 'Début',
};
