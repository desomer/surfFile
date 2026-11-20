/// Références et contrats de copie des configurations persistées du registre.
library;

import 'package:material_ui/material_ui.dart';

/// Références des configurations persistées utilisées par le graphe de pages.
enum EditorConfigKind {
  layout,
  style,
  component,
  nativeComponent,
  scaffoldPage,
  a4Page,
  value,
  action,
  indicator,
  separator,
  list,
  tab,
  conditional,
  treeView,
  table,
}

/// Key of one persisted configuration entry, e.g. `layouts[id]`.
@immutable
class EditorConfigRef {
  const EditorConfigRef(this.kind, this.id);

  const EditorConfigRef.layout(this.id) : kind = EditorConfigKind.layout;
  const EditorConfigRef.style(this.id) : kind = EditorConfigKind.style;
  const EditorConfigRef.component(this.id) : kind = EditorConfigKind.component;
  const EditorConfigRef.nativeComponent(this.id)
    : kind = EditorConfigKind.nativeComponent;
  const EditorConfigRef.scaffoldPage(this.id)
    : kind = EditorConfigKind.scaffoldPage;
  const EditorConfigRef.a4Page(this.id) : kind = EditorConfigKind.a4Page;
  const EditorConfigRef.value(this.id) : kind = EditorConfigKind.value;
  const EditorConfigRef.action(this.id) : kind = EditorConfigKind.action;
  const EditorConfigRef.indicator(this.id) : kind = EditorConfigKind.indicator;
  const EditorConfigRef.separator(this.id) : kind = EditorConfigKind.separator;
  const EditorConfigRef.list(this.id) : kind = EditorConfigKind.list;
  const EditorConfigRef.tab(this.id) : kind = EditorConfigKind.tab;
  const EditorConfigRef.conditional(this.id)
    : kind = EditorConfigKind.conditional;
  const EditorConfigRef.treeView(this.id) : kind = EditorConfigKind.treeView;
  const EditorConfigRef.table(this.id) : kind = EditorConfigKind.table;

  final EditorConfigKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is EditorConfigRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => '${kind.name}:$id';
}

/// Copie une configuration persistée lors de la duplication d'une instance.
///
/// La valeur source conserve son type ; `remap` transforme les identifiants
/// possédés par le graphe dupliqué et laisse les autres inchangés.
typedef EditorConfigCopier = Object Function(
  EditorConfigRef source,
  Object value,
  String Function(String id) remap,
);

/// Contrat explicite de duplication d'un composant, limité aux données
/// persistées et indépendant des contrôleurs ou de l'état des widgets.
/// La duplication est refusée pour les composants sans contrat.
@immutable
class ComponentDuplicationContract {
  const ComponentDuplicationContract({
    this.ownedConfigs = _noConfigs,
    this.copyConfig,
  });

  /// Component that persists nothing under its instance ID.
  const ComponentDuplicationContract.stateless() : this();

  /// Configurations owned by an instance. Must be a pure derivation of
  /// `instanceId`, returning the same kinds in the same order for every ID,
  /// so that the copy is found again by the new instance ID.
  final List<EditorConfigRef> Function(String instanceId) ownedConfigs;

  /// Custom copy; null uses the built-in structural copy of each kind.
  final EditorConfigCopier? copyConfig;

  static List<EditorConfigRef> _noConfigs(String _) => const [];
  static List<EditorConfigRef> _layout(String id) => [
    EditorConfigRef.layout(id),
  ];
  static List<EditorConfigRef> _container(String id) => [
    EditorConfigRef.style(id),
    EditorConfigRef.nativeComponent(id),
  ];
  static List<EditorConfigRef> _value(String id) => [EditorConfigRef.value(id)];
  static List<EditorConfigRef> _action(String id) => [
    EditorConfigRef.action(id),
  ];
  static List<EditorConfigRef> _indicator(String id) => [
    EditorConfigRef.indicator(id),
  ];
  static List<EditorConfigRef> _separator(String id) => [
    EditorConfigRef.separator(id),
  ];
  static List<EditorConfigRef> _list(String id) => [
    EditorConfigRef.layout(id),
    EditorConfigRef.style(id),
    EditorConfigRef.list(id),
  ];
  static List<EditorConfigRef> _iterableContent(String id) => [
    EditorConfigRef.layout(id),
    EditorConfigRef.style(id),
  ];
  static List<EditorConfigRef> _native(String id) => [
    EditorConfigRef.nativeComponent(id),
  ];
  static List<EditorConfigRef> _tab(String id) => [EditorConfigRef.tab(id)];
  static List<EditorConfigRef> _conditional(String id) => [
    EditorConfigRef.conditional(id),
  ];
  static List<EditorConfigRef> _component(String id) => [
    EditorConfigRef.component(id),
  ];
  static List<EditorConfigRef> _treeView(String id) => [
    EditorConfigRef.style(id),
    EditorConfigRef.treeView(id),
  ];
  static List<EditorConfigRef> _table(String id) => [
    EditorConfigRef.style(id),
    EditorConfigRef.table(id),
  ];

  /// Contrats de duplication des composants standards et des extensions.
  static const component = ComponentDuplicationContract(
    ownedConfigs: _component,
  );
  static const superValue = ComponentDuplicationContract(ownedConfigs: _value);
  static const superAction = ComponentDuplicationContract(
    ownedConfigs: _action,
  );
  static const superIndicator = ComponentDuplicationContract(
    ownedConfigs: _indicator,
  );
  static const superSeparator = ComponentDuplicationContract(
    ownedConfigs: _separator,
  );
  static const superTab = ComponentDuplicationContract(ownedConfigs: _tab);
  static const superConditional = ComponentDuplicationContract(
    ownedConfigs: _conditional,
  );
  static const superTreeView = ComponentDuplicationContract(
    ownedConfigs: _treeView,
  );
  static const superTable = ComponentDuplicationContract(ownedConfigs: _table);
  static const superAppBar = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const superBottomNavigationBar = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const superBottomAppBar = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const superNavigationRail = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const superExpansible = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const superMenuAnchor = ComponentDuplicationContract(
    ownedConfigs: _native,
  );
  static const newContainer = ComponentDuplicationContract(
    ownedConfigs: _container,
  );
  static const newLayout = ComponentDuplicationContract(ownedConfigs: _layout);
  static const iterableContent = ComponentDuplicationContract(
    ownedConfigs: _iterableContent,
  );
  static const superListView = ComponentDuplicationContract(
    ownedConfigs: _list,
  );
}
