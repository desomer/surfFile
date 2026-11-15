/// Catalogue ordonné des constructeurs de composants fournis par défaut.
library;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/widgets/components/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';

import '../services/codegen/component_dart_generators.dart';
import '../widgets/components/native/super_app_bar.dart';
import '../widgets/components/native/super_bottom_app_bar.dart';
import '../widgets/components/native/super_bottom_navigation_bar.dart';
import '../widgets/components/native/super_expansible.dart';
import '../widgets/components/native/super_menu_anchor.dart';
import '../widgets/components/native/super_navigation_rail.dart';
import '../widgets/components/super_action.dart';
import '../widgets/components/super_conditional.dart';
import '../widgets/components/super_indicator.dart';
import '../widgets/components/super_layout/iterable_content.dart';
import '../widgets/components/super_list_view.dart';
import '../widgets/components/super_renderer.dart';
import '../widgets/components/super_separator.dart';
import '../widgets/components/super_table.dart';
import '../widgets/components/super_tab.dart';
import '../widgets/components/super_tree_view.dart';
import '../widgets/components/super_value.dart';
import '../widgets/editing/addition/component_add_configurators.dart';
import '../widgets/editing/addition/component_add_contracts.dart';
import '../widgets/editing/components/super_renderer_editor.dart';
import 'component_duplication_contract.dart';
import 'component_registration.dart';
import 'registry_previews.dart';

/// Enregistre les constructeurs standards dans la map du registre, dans leur ordre historique.
void registerBuiltInComponents(
  Map<String, ComponentBuilder> registry, {
  required List<String> availableFontFamilies,
}) {
  registry['Renderer'] = ComponentBuilderDynamic(
    label: 'SuperRenderer / Apparence JSON',
    addFamily: ComponentAddFamily.extended,
    addOrder: 1000,
    menuIcon: Icons.web,
    tags: const {'renderer', 'layout'},
    duplication: ComponentDuplicationContract.component,
    addConfigurator: superRendererAddConfigurator,
    previewBuilder: (_) => const Center(child: Icon(Icons.web, size: 40)),
    dartGenerator: const SuperRendererDartGenerator(),
    dynamicBuilder: (ctx) => SuperRenderer(id: ctx.id),
  );
  registry['Layout'] = ComponentBuilderDynamic(
    addFamily: ComponentAddFamily.standard,
    menuIcon: Icons.dashboard_outlined,
    duplication: ComponentDuplicationContract.newLayout,
    tags: const {'layout'},
    addConfigurator: layoutAddConfigurator,
    previewBuilder: buildLayoutPreview,
    dartGenerator: const SuperLayoutDartGenerator(),
    dynamicBuilder: (xuiCtx) => Builder(
      builder: (ctx) {
        final id = xuiCtx.id;

        return BuilderSlot(
          id: id,
          label: 'Layout',
          builder: (ctx) {
            final superapp = SuperApp.of(ctx);
            final superLayoutConfig = superapp.getLayoutConfigById(id);
            return ValueListenableBuilder<SuperLayoutConfig>(
              valueListenable: superLayoutConfig,
              builder: (context, config, _) => SuperLayout(
                id: id,
                config: config,
                onChanged: (value) => superLayoutConfig.value = value,
              ),
            );
          },
        );
      },
    ),
  );

  registry['Card'] = ComponentBuilderDynamic(
    menuIcon: Icons.crop_square,
    label: 'Card / Container / Image',
    addFamily: ComponentAddFamily.standard,
    duplication: ComponentDuplicationContract.newContainer,
    tags: const {'container'},
    addConfigurator: containerAddConfigurator,
    previewBuilder: buildCardPreview,
    dartGenerator: const SuperCardDartGenerator(),
    dynamicBuilder: (xuiCtx) => Builder(
      builder: (context) {
        final style = SuperApp.of(context).getContainerStyleById(xuiCtx.id);
        return ValueListenableBuilder<ContainerStyle>(
          valueListenable: style,
          builder: (context, value, _) => EditableSurface(
            id: xuiCtx.id,
            label: 'Card',
            menuType: 'Card',
            style: value,
            onStyleChanged: (value) => style.value = value,
          ),
        );
      },
    ),
  );

  registry['Value'] = ComponentBuilderDynamic(
    menuIcon: Icons.text_fields,
    label: 'Text / Input',
    addFamily: ComponentAddFamily.standard,
    duplication: ComponentDuplicationContract.superValue,
    tags: const {'text', 'input'},
    addConfigurator: superValueAddConfigurator(availableFontFamilies),
    previewBuilder: buildValuePreview,
    dartGenerator: const SuperValueDartGenerator(),
    dynamicBuilder: (ctx) =>
        SuperValue(id: ctx.id, availableFontFamilies: availableFontFamilies),
  );

  registry['Action'] = ComponentBuilderDynamic(
    menuIcon: Icons.smart_button_outlined,
    label: 'Action / Button',
    addFamily: ComponentAddFamily.standard,
    duplication: ComponentDuplicationContract.superAction,
    tags: const {'action', 'button', 'input'},
    addConfigurator: superActionAddConfigurator(availableFontFamilies),
    previewBuilder: buildActionPreview,
    dartGenerator: const SuperActionDartGenerator(),
    dynamicBuilder: (ctx) =>
        SuperAction(id: ctx.id, availableFontFamilies: availableFontFamilies),
  );

  registry['Indicator'] = ComponentBuilderDynamic(
    menuIcon: Icons.adjust_outlined,
    label: 'Indicator / Icon',
    addFamily: ComponentAddFamily.standard,
    duplication: ComponentDuplicationContract.superIndicator,
    tags: const {'indicator', 'icon', 'text'},
    addConfigurator: superIndicatorAddConfigurator(availableFontFamilies),
    previewBuilder: buildIndicatorPreview,
    dartGenerator: const SuperIndicatorDartGenerator(),
    dynamicBuilder: (ctx) => SuperIndicator(
      id: ctx.id,
      availableFontFamilies: availableFontFamilies,
    ),
  );

  registry['Separator'] = ComponentBuilderDynamic(
    menuIcon: Icons.horizontal_rule,
    label: 'Separator / Divider / Spacer',
    addFamily: ComponentAddFamily.standard,
    duplication: ComponentDuplicationContract.superSeparator,
    tags: const {'separator', 'divider', 'spacer'},
    addConfigurator: superSeparatorAddConfigurator(availableFontFamilies),
    previewBuilder: buildSeparatorPreview,
    dartGenerator: const SuperSeparatorDartGenerator(),
    dynamicBuilder: (ctx) => SuperSeparator(
      id: ctx.id,
      availableFontFamilies: availableFontFamilies,
    ),
  );

  registry['ApplicationBar'] = ComponentBuilderDynamic(
    menuIcon: Icons.web_asset,
    addFamily: ComponentAddFamily.extended,
    duplication: ComponentDuplicationContract.superAppBar,
    tags: const {'appBar'},
    placementTags: const {'appBar'},
    previewBuilder: buildApplicationBarPreview,
    dartGenerator: const SuperNativeComponentDartGenerator(
      widgetClassName: 'SuperAppBar',
      defaultLabel: 'ApplicationBar',
    ),
    dynamicBuilder: (ctx) => SuperAppBar(id: ctx.id),
  );

  registry['BottomNavigationBar'] = ComponentBuilderDynamic(
    menuIcon: Icons.space_dashboard_outlined,
    addFamily: ComponentAddFamily.extended,
    duplication: ComponentDuplicationContract.superBottomNavigationBar,
    tags: const {'bottomNavigationBar'},
    placementTags: const {'bottomNavigationBar'},
    previewBuilder: buildBottomNavigationBarPreview,
    dartGenerator: const SuperNativeComponentDartGenerator(
      widgetClassName: 'SuperBottomNavigationBar',
      defaultLabel: 'Barre de navigation',
    ),
    dynamicBuilder: (ctx) => SuperBottomNavigationBar(id: ctx.id),
  );

  registry['BottomAppBar'] = ComponentBuilderDynamic(
    menuIcon: Icons.call_to_action_outlined,
    addFamily: ComponentAddFamily.extended,
    duplication: ComponentDuplicationContract.superBottomAppBar,
    tags: const {'bottomNavigationBar', 'bottomAppBar'},
    placementTags: const {'bottomNavigationBar'},
    previewBuilder: buildBottomAppBarPreview,
    dartGenerator: const SuperNativeComponentDartGenerator(
      widgetClassName: 'SuperBottomAppBar',
      defaultLabel: 'Barre basse',
    ),
    dynamicBuilder: (ctx) => SuperBottomAppBar(id: ctx.id),
  );

  registry['NavigationRail'] = ComponentBuilderDynamic(
    menuIcon: Icons.view_sidebar_outlined,
    addFamily: ComponentAddFamily.extended,
    duplication: ComponentDuplicationContract.superNavigationRail,
    tags: const {'navigationRail'},
    previewBuilder: buildNavigationRailPreview,
    dartGenerator: const SuperNativeComponentDartGenerator(
      widgetClassName: 'SuperNavigationRail',
      defaultLabel: 'Rail de navigation',
    ),
    dynamicBuilder: (ctx) => SuperNavigationRail(id: ctx.id),
  );

  registry['Expansible'] = ComponentBuilderDynamic(
    menuIcon: Icons.unfold_more_outlined,
    addFamily: ComponentAddFamily.container,
    duplication: ComponentDuplicationContract.superExpansible,
    tags: const {'container', 'layout', 'expansible'},
    addConfigurator: expansibleAddConfigurator,
    previewBuilder: buildExpansiblePreview,
    dartGenerator: const SuperNativeComponentDartGenerator(
      widgetClassName: 'SuperExpansible',
      defaultLabel: 'Expansible',
    ),
    dynamicBuilder: (ctx) => SuperExpansible(id: ctx.id),
  );

  registry['Menu'] = ComponentBuilderDynamic(
    menuIcon: Icons.menu_open_outlined,
    addFamily: ComponentAddFamily.container,
    duplication: ComponentDuplicationContract.superMenuAnchor,
    tags: const {'container', 'layout', 'menu'},
    addConfigurator: menuAnchorAddConfigurator,
    previewBuilder: buildMenuPreview,
    dartGenerator: const SuperNativeComponentDartGenerator(
      widgetClassName: 'SuperMenuAnchor',
      defaultLabel: 'Menu',
    ),
    dynamicBuilder: (ctx) => SuperMenuAnchor(id: ctx.id),
  );

  registry['Tab'] = ComponentBuilderDynamic(
    menuIcon: Icons.tab_outlined,
    addFamily: ComponentAddFamily.container,
    duplication: ComponentDuplicationContract.superTab,
    tags: const {'container', 'layout', 'tab'},
    addConfigurator: tabAddConfigurator,
    previewBuilder: buildTabPreview,
    dartGenerator: const SuperTabDartGenerator(),
    dynamicBuilder: (ctx) => SuperTab(id: ctx.id),
  );

  registry['Conditional'] = ComponentBuilderDynamic(
    label: 'Conditional / Switch',
    menuIcon: Icons.call_split_outlined,
    addFamily: ComponentAddFamily.container,
    duplication: ComponentDuplicationContract.superConditional,
    tags: const {'container', 'layout', 'conditional', 'data'},
    addConfigurator: conditionalAddConfigurator,
    previewBuilder: buildConditionalPreview,
    dartGenerator: const SuperConditionalDartGenerator(),
    dynamicBuilder: (ctx) => SuperConditional(id: ctx.id),
  );

  registry['IterableContent'] = ComponentBuilderDynamic(
    menuIcon: Icons.article_outlined,
    addFamily: ComponentAddFamily.container,
    duplication: ComponentDuplicationContract.iterableContent,
    tags: const {'container', 'layout'},
    placementTags: const {'list'},
    addConfigurator: containerAddConfigurator,
    previewBuilder: buildIterableContentPreview,
    dartGenerator: const SuperIterableContentDartGenerator(),
    dynamicBuilder: (ctx) => IterableContent(id: ctx.id),
  );
  registry['ListView'] = ComponentBuilderDynamic(
    menuIcon: Icons.view_list,
    addFamily: ComponentAddFamily.container,
    duplication: ComponentDuplicationContract.superListView,
    tags: const {'list', 'layout'},
    addConfigurator: listViewAddConfigurator,
    previewBuilder: buildListViewPreview,
    dartGenerator: const SuperListViewDartGenerator(),
    dynamicBuilder: (xuiCtx) => BuilderSlot(
      id: xuiCtx.id,
      label: 'Liste',
      builder: (_) => SuperListView(id: xuiCtx.id),
    ),
  );

  registry['TreeView'] = ComponentBuilderDynamic(
    menuIcon: Icons.account_tree_outlined,
    label: 'TreeView',
    addFamily: ComponentAddFamily.container,
    duplication: ComponentDuplicationContract.superTreeView,
    tags: const {'tree', 'list', 'layout', 'data'},
    addConfigurator: treeViewAddConfigurator,
    previewBuilder: buildTreeViewPreview,
    dartGenerator: const SuperTreeViewDartGenerator(),
    dynamicBuilder: (ctx) => SuperTreeView(id: ctx.id),
  );

  registry['Table'] = ComponentBuilderDynamic(
    menuIcon: Icons.table_chart_outlined,
    label: 'Table',
    addFamily: ComponentAddFamily.container,
    duplication: ComponentDuplicationContract.superTable,
    tags: const {'table', 'list', 'layout', 'data'},
    addConfigurator: tableAddConfigurator,
    previewBuilder: buildTablePreview,
    dartGenerator: const SuperTableDartGenerator(),
    dynamicBuilder: (ctx) => SuperTable(id: ctx.id),
  );
}
