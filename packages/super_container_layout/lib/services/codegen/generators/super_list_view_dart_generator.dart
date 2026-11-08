/// Générateur de code Dart dédié au composant [SuperListView] (`SuperListViewConfig`).
library;

import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../theme/container_style.dart';
import '../dart_code_generator.dart';
import 'super_layout_dart_generator.dart';

/// Classe de génération de code Dart dédiée à [SuperListView] (`SuperListViewConfig`).
class SuperListViewDartGenerator extends ComponentDartGenerator {
  const SuperListViewDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperListViewConfig>(id) ??
        const SuperListViewConfig();
    final behaviors = context.appearance.behaviorsFor(id);
    final rowId = config.itemId ?? id;
    final templateStyle =
        context.appearance.styles[rowId] ??
        context.appearance.styles[id] ??
        const ContainerStyle();

    final template = config.template;
    final placedIds = <String>[
      for (final zoneIds in template.placements.values) ...zoneIds,
    ];
    final slotEntries = <String>[
      for (final slotId in placedIds)
        context.generateBuilderSlot(
          slotId,
          slotType: template.slotTypes[slotId],
          label: template.slotLabels[slotId],
          preferredSize: template.slotPreferredSizes[slotId],
          indent: indent + 4,
        ),
    ];

    final strippedConfig = config.copyWith(template: const SuperLayoutConfig());
    final args = <String, String>{
      'id': context.formatInstanceId(id),
      if (config.itemId != null) 'itemId': context.formatString(config.itemId!),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (strippedConfig != const SuperListViewConfig())
        'config': formatConfig(
          context,
          strippedConfig,
          indent: indent + 2,
          includeConst: true,
        ),
      if (template != const SuperLayoutConfig())
        'template': SuperLayoutDartGenerator.formatConfig(
          context,
          template,
          indent: indent + 2,
          includeConst: true,
        ),
      if (templateStyle != const ContainerStyle())
        'templateStyle': context.formatContainerStyle(
          templateStyle,
          indent: indent + 2,
          includeConst: context.canContainerStyleBeConst(templateStyle),
        ),
      if (slotEntries.isNotEmpty)
        'slots': context.formatList(
          slotEntries,
          indent: indent + 2,
          forceMultiline: true,
        ),
    };

    return context.formatCall(
      'SuperListView',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperListViewConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperListViewConfig config, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = SuperListViewConfig();
    final args = <String, String>{
      if (config.binding != null)
        'binding': context.formatBinding(config.binding!, indent: indent + 2),
      if (config.axis != d.axis) 'axis': context.formatAxis(config.axis),
      if (config.wrap != d.wrap) 'wrap': '${config.wrap}',
      if (config.wrapSizing != d.wrapSizing)
        'wrapSizing': 'ListWrapSizing.${config.wrapSizing.name}',
      if (config.itemWidth != d.itemWidth)
        'itemWidth': context.formatNum(config.itemWidth),
      if (config.itemSize != null)
        'itemSize': context.formatSlotSizeConstraints(
          config.itemSize!,
          indent: indent + 2,
        ),
      if (config.itemExtent != d.itemExtent)
        'itemExtent': context.formatNum(config.itemExtent),
      if (config.spacing != d.spacing)
        'spacing': context.formatNum(config.spacing),
      if (config.allowAdd != d.allowAdd) 'allowAdd': '${config.allowAdd}',
      if (config.allowRemove != d.allowRemove)
        'allowRemove': '${config.allowRemove}',
      if (config.showScrollbar != d.showScrollbar)
        'showScrollbar': '${config.showScrollbar}',
      if (!config.scrollbarStyle.isDefault)
        'scrollbarStyle': context.formatScrollbarStyle(
          config.scrollbarStyle,
          indent: indent + 2,
        ),
      if (config.animateSelectionAndHover != d.animateSelectionAndHover)
        'animateSelectionAndHover': '${config.animateSelectionAndHover}',
      if (config.emptyText != d.emptyText)
        'emptyText': context.formatString(config.emptyText),
      if (config.template != d.template)
        'template': SuperLayoutDartGenerator.formatConfig(
          context,
          config.template,
          indent: indent + 2,
        ),
      if (config.itemId != null) 'itemId': context.formatString(config.itemId!),
    };
    final prefix = includeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperListViewConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: args.length > 1,
    );
  }
}
