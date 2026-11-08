/// Contexte partagé lors de la génération d'un arbre de composants en code Dart.
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/component_behavior.dart';
import '../../../models/component_config.dart';
import '../../../models/json_text_binding.dart';
import '../../../models/native_component_config.dart';
import '../../../models/registry.dart';
import '../../../models/super_action_config.dart';
import '../../../models/super_indicator_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_renderer_config.dart';
import '../../../models/super_separator_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../models/super_table_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../models/super_value_config.dart';
import '../../../theme/appearance.dart';
import '../../../theme/container_fill.dart';
import '../../../theme/container_style.dart';
import '../../../theme/neon_style.dart';
import '../../../theme/style_extras.dart';
import 'component_dart_generator.dart';

/// Contexte partagé lors de la génération d'un arbre de composants en code Dart.
///
/// Expose l'[Appearance] du fragment exporté, le [Registry] ainsi que les
/// utilitaires de formatage d'expressions Dart et de résolution récursive des slots.
class DartCodegenContext {
  DartCodegenContext({
    required this.appearance,
    required this.registry,
    this.rootComponentId,
    this.rootInstanceVariable,
    this.decomposeComponents = false,
  });

  /// Apparence autonome contenant les configurations, styles et comportements à exporter.
  final Appearance appearance;

  /// Registre permettant de résoudre les [ComponentDartGenerator] par type de composant.
  final Registry registry;

  /// Identifiant du composant racine lorsqu'un identifiant dynamique est souhaité.
  final String? rootComponentId;

  /// Nom de variable Dart à utiliser pour l'identifiant d'instance du composant racine (ex. `'id'`).
  final String? rootInstanceVariable;

  /// Indique si les [RegisteredComponent] ayant `decomposableOnExport: true`
  /// doivent être décomposés en widgets standards au lieu d'être appelés via le registre.
  final bool decomposeComponents;

  final Set<String> _visiting = <String>{};

  /// Sous-composants extraits découverts pendant la génération de l'arbre.
  final List<
    ({
      String id,
      String registrationId,
      String label,
      String? slotType,
      bool forceComponentOnExport,
    })
  >
  extractedSubComponents = [];

  final Set<String> _extractedIds = <String>{};

  /// Indique si l'identifiant [id] est résolu sous forme de variable d'instance dynamique.
  bool isDynamicInstanceId(String id) =>
      rootInstanceVariable != null && id == rootComponentId;

  /// Formate l'identifiant [id] sous forme de code Dart (variable [rootInstanceVariable] si dynamique, sinon chaîne littérale).
  String formatInstanceId(String id) =>
      isDynamicInstanceId(id) ? rootInstanceVariable! : formatString(id);

  /// Retourne une chaîne de [count] espaces pour l'indentation.
  String spaces(int count) => ' ' * count;

  /// Indente toutes les lignes de [code] (sauf la première) de [indent] espaces.
  String indentTail(String code, int indent) {
    if (indent <= 0 || !code.contains('\n')) return code;
    final prefix = spaces(indent);
    final lines = code.split('\n');
    return [
      lines.first,
      for (final line in lines.skip(1)) line.isEmpty ? '' : '$prefix$line',
    ].join('\n');
  }

  /// Construit un appel de constructeur ou de fonction Dart multi-lignes ou sur une ligne.
  String formatCall(
    String constructorName,
    List<String> positionalArgs,
    Map<String, String> namedArgs, {
    int indent = 0,
    bool forceMultiline = false,
  }) {
    if (positionalArgs.isEmpty && namedArgs.isEmpty) {
      return '$constructorName()';
    }
    final entries = <String>[
      ...positionalArgs,
      for (final entry in namedArgs.entries) '${entry.key}: ${entry.value}',
    ];
    final singleLine = '$constructorName(${entries.join(', ')})';
    if (!forceMultiline &&
        entries.length == 1 &&
        !singleLine.contains('\n') &&
        singleLine.length <= 72) {
      return singleLine;
    }
    final p = spaces(indent);
    final inner = spaces(indent + 2);
    final buffer = StringBuffer('$constructorName(\n');
    for (final entry in entries) {
      final indented = indentTail(entry, indent + 2);
      buffer.writeln('$inner$indented,');
    }
    buffer.write('$p)');
    return buffer.toString();
  }

  /// Construit une liste littérale Dart (`[...]`).
  String formatList(
    List<String> items, {
    int indent = 0,
    bool isConst = false,
    bool forceMultiline = false,
  }) {
    final prefix = isConst ? 'const ' : '';
    if (items.isEmpty) return '$prefix[]';
    final single = '$prefix[${items.join(', ')}]';
    if (!forceMultiline &&
        !single.contains('\n') &&
        items.length <= 3 &&
        single.length <= 68) {
      return single;
    }
    final p = spaces(indent);
    final inner = spaces(indent + 2);
    final buffer = StringBuffer('$prefix[\n');
    for (final item in items) {
      buffer.writeln('$inner${indentTail(item, indent + 2)},');
    }
    buffer.write('$p]');
    return buffer.toString();
  }

  /// Construit un ensemble littéral Dart (`{...}`).
  String formatSet(
    Iterable<String> items, {
    int indent = 0,
    bool isConst = false,
  }) {
    final list = items.toList();
    final prefix = isConst ? 'const ' : '';
    if (list.isEmpty) return '$prefix<Never>{}';
    final single = '$prefix{${list.join(', ')}}';
    if (!single.contains('\n') && single.length <= 68) {
      return single;
    }
    final p = spaces(indent);
    final inner = spaces(indent + 2);
    final buffer = StringBuffer('$prefix{\n');
    for (final item in list) {
      buffer.writeln('$inner${indentTail(item, indent + 2)},');
    }
    buffer.write('$p}');
    return buffer.toString();
  }

  /// Construit une Map littérale Dart (`{k: v, ...}`).
  String formatMap(
    Map<String, String> entries, {
    int indent = 0,
    bool isConst = false,
    bool forceMultiline = true,
  }) {
    final prefix = isConst ? 'const ' : '';
    if (entries.isEmpty) return '$prefix{}';
    if (!forceMultiline && entries.length == 1) {
      final first = entries.entries.first;
      final single = '$prefix{${first.key}: ${first.value}}';
      if (!single.contains('\n') && single.length <= 68) {
        return single;
      }
    }
    final p = spaces(indent);
    final inner = spaces(indent + 2);
    final buffer = StringBuffer('$prefix{\n');
    for (final entry in entries.entries) {
      final valueCode = indentTail(entry.value, indent + 2);
      buffer.writeln('$inner${entry.key}: $valueCode,');
    }
    buffer.write('$p}');
    return buffer.toString();
  }

  /// Formate une chaîne de caractères en littéral Dart échappé (`'...'`).
  String formatString(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
    return "'$escaped'";
  }

  /// Formate un nombre en privilégiant la notation entière lorsque la valeur est ronde.
  String formatNum(num value) {
    if (value is int) return '$value';
    final d = value.toDouble();
    if (d == d.roundToDouble()) return '${d.round()}';
    return '$d';
  }

  /// Formate une couleur en expression `Color(0xAARRGGBB)`.
  String formatColor(Color color, {bool includeConst = false}) {
    final hex = color
        .toARGB32()
        .toRadixString(16)
        .toUpperCase()
        .padLeft(8, '0');
    return '${includeConst ? 'const ' : ''}Color(0x$hex)';
  }

  /// Formate un [FontWeight] en constante Flutter (`FontWeight.w400`, `FontWeight.bold`, etc.).
  String formatFontWeight(FontWeight weight) => switch (weight) {
    FontWeight.w100 => 'FontWeight.w100',
    FontWeight.w200 => 'FontWeight.w200',
    FontWeight.w300 => 'FontWeight.w300',
    FontWeight.w400 => 'FontWeight.w400',
    FontWeight.w500 => 'FontWeight.w500',
    FontWeight.w600 => 'FontWeight.w600',
    FontWeight.w700 => 'FontWeight.bold',
    FontWeight.w800 => 'FontWeight.w800',
    FontWeight.w900 => 'FontWeight.w900',
    _ => 'FontWeight.w${weight.value}',
  };

  /// Formate un [Axis] en expression Dart.
  String formatAxis(Axis axis) => 'Axis.${axis.name}';

  /// Formate un [TextAlign] en expression Dart.
  String formatTextAlign(TextAlign align) => 'TextAlign.${align.name}';

  /// Formate un [EdgeInsets] en expression Dart concise.
  String formatEdgeInsets(EdgeInsets insets, {bool includeConst = false}) {
    final prefix = includeConst ? 'const ' : '';
    if (insets.left == insets.right &&
        insets.top == insets.bottom &&
        insets.left == insets.top) {
      if (insets.left == 0) return '${prefix}EdgeInsets.zero';
      return '${prefix}EdgeInsets.all(${formatNum(insets.left)})';
    }
    if (insets.left == insets.right && insets.top == insets.bottom) {
      final args = <String>[
        if (insets.left != 0) 'horizontal: ${formatNum(insets.left)}',
        if (insets.top != 0) 'vertical: ${formatNum(insets.top)}',
      ];
      return '${prefix}EdgeInsets.symmetric(${args.join(', ')})';
    }
    return '${prefix}EdgeInsets.fromLTRB('
        '${formatNum(insets.left)}, '
        '${formatNum(insets.top)}, '
        '${formatNum(insets.right)}, '
        '${formatNum(insets.bottom)})';
  }

  /// Formate une [Size] en expression Dart.
  String formatSize(Size size, {bool includeConst = false}) {
    final prefix = includeConst ? 'const ' : '';
    final w = size.width.isFinite ? formatNum(size.width) : 'double.infinity';
    final h = size.height.isFinite ? formatNum(size.height) : 'double.infinity';
    return '${prefix}Size($w, $h)';
  }

  /// Formate un [Quad] en expression Dart.
  String formatQuad(Quad quad, {bool includeConst = false}) {
    final prefix = includeConst ? 'const ' : '';
    if (quad.uniform) {
      return '${prefix}Quad.all(${formatNum(quad.top)})';
    }
    return '${prefix}Quad('
        '${formatNum(quad.top)}, '
        '${formatNum(quad.right)}, '
        '${formatNum(quad.bottom)}, '
        '${formatNum(quad.left)})';
  }

  /// Formate un [JsonTextBinding] en expression Dart.
  String formatBinding(
    JsonTextBinding binding, {
    int indent = 0,
    bool includeConst = false,
  }) {
    final repoId = binding.repositoryId;
    final args = <String, String>{
      if (repoId != null && repoId.isNotEmpty)
        'repositoryId': formatString(repoId),
      'path': formatString(binding.path),
    };
    final prefix = includeConst ? 'const ' : '';
    return formatCall(
      '${prefix}JsonTextBinding',
      const [],
      args,
      indent: indent,
      forceMultiline: args.length > 1,
    );
  }

  /// Formate une Map de liaisons de propriétés (`Map<Enum, JsonTextBinding>`).
  String formatPropertyBindings<E extends Enum>(
    String enumTypeName,
    Map<E, JsonTextBinding> bindings, {
    int indent = 0,
    bool includeConst = false,
  }) {
    return formatMap({
      for (final entry in bindings.entries)
        '$enumTypeName.${entry.key.name}': formatBinding(
          entry.value,
          indent: indent + 2,
          includeConst: includeConst,
        ),
    }, indent: indent);
  }

  /// Formate une liste de [ComponentBehavior] pour le paramètre `behaviours: [...]`.
  String formatBehaviors(List<ComponentBehavior> behaviors, {int indent = 0}) {
    return formatList(
      [
        for (final behavior in behaviors)
          formatBehavior(behavior, indent: indent + 2),
      ],
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [ComponentBehavior] individuel.
  String formatBehavior(ComponentBehavior behavior, {int indent = 0}) {
    final args = <String, String>{
      'id': formatString(behavior.id),
      'trigger': 'BehaviorTrigger.${behavior.trigger.name}',
      if (!behavior.enabled) 'enabled': 'false',
      'action': formatBehaviorAction(behavior.action, indent: indent + 2),
    };
    return formatCall(
      'ComponentBehavior',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate une [BehaviorAction] polymorphe en expression Dart.
  String formatBehaviorAction(BehaviorAction action, {int indent = 0}) {
    switch (action) {
      case final EmitEventAction emit:
        return formatCall('EmitEventAction', const [], {
          'eventId': formatString(emit.eventId),
          if (emit.custom.isNotEmpty)
            'custom': formatLiteralValue(emit.custom, indent: indent + 2),
        }, indent: indent);
      case final GoToPageAction go:
        return formatCall('const GoToPageAction', const [], {
          'pagePath': formatString(go.pagePath),
          if (go.pageId != null) 'pageId': formatString(go.pageId!),
          if (go.pageName != null) 'pageName': formatString(go.pageName!),
        }, indent: indent);
      case final TooltipAction tooltip:
        return formatCall('const TooltipAction', const [], {
          if (tooltip.message.isNotEmpty)
            'message': formatString(tooltip.message),
          if (tooltip.binding != null)
            'binding': formatBinding(tooltip.binding!, indent: indent + 2),
        }, indent: indent);
      case final ZoneSizeBindingAction zoneSize:
        return formatCall(
          'ZoneSizeBindingAction',
          const [],
          {
            'zone': 'SuperLayoutZone.${zoneSize.zone.name}',
            'binding': formatBinding(
              zoneSize.binding,
              indent: indent + 2,
              includeConst: true,
            ),
            if (zoneSize.unit != SlotSizeUnit.pixels)
              'unit': 'SlotSizeUnit.${zoneSize.unit.name}',
            if (zoneSize.durationMs != ZoneSizeBindingAction.defaultDurationMs)
              'durationMs': '${zoneSize.durationMs}',
            if (zoneSize.curve != BehaviorCurve.easeInOut)
              'curve': 'BehaviorCurve.${zoneSize.curve.name}',
          },
          indent: indent,
          forceMultiline: true,
        );
      default:
        return formatCall(
          'BehaviorActionCatalog.decode',
          [formatLiteralValue(action.toJson(), indent: indent + 2)],
          const {},
          indent: indent,
        );
    }
  }

  /// Formate une valeur JSON arbitraire (`Map`, `List`, `String`, `num`, `bool`, `null`) en littéral Dart.
  String formatLiteralValue(Object? value, {int indent = 0}) => switch (value) {
    null => 'null',
    final bool b => '$b',
    final num n => formatNum(n),
    final String s => formatString(s),
    final List<Object?> list => formatList([
      for (final item in list) formatLiteralValue(item, indent: indent + 2),
    ], indent: indent),
    final Map<Object?, Object?> map => formatMap(
      {
        for (final entry in map.entries)
          formatString('${entry.key}'): formatLiteralValue(
            entry.value,
            indent: indent + 2,
          ),
      },
      indent: indent,
      forceMultiline: map.length > 1,
    ),
    _ => formatString('$value'),
  };

  /// Formate une [SlotDimension] en expression Dart.
  String formatSlotDimension(SlotDimension dim, {bool includeConst = false}) {
    final prefix = includeConst ? 'const ' : '';
    return '${prefix}SlotDimension(${formatNum(dim.value)}, SlotSizeUnit.${dim.unit.name})';
  }

  /// Formate des [SlotSizeConstraints] en omettant les valeurs par défaut.
  String formatSlotSizeConstraints(
    SlotSizeConstraints constraints, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = SlotSizeConstraints();
    final args = <String, String>{
      if (constraints.minWidth != null)
        'minWidth': formatSlotDimension(constraints.minWidth!),
      if (constraints.minHeight != null)
        'minHeight': formatSlotDimension(constraints.minHeight!),
      if (constraints.maxWidth != null)
        'maxWidth': formatSlotDimension(constraints.maxWidth!),
      if (constraints.maxHeight != null)
        'maxHeight': formatSlotDimension(constraints.maxHeight!),
      if (constraints.preferredWidth != null)
        'preferredWidth': formatSlotDimension(constraints.preferredWidth!),
      if (constraints.preferredHeight != null)
        'preferredHeight': formatSlotDimension(constraints.preferredHeight!),
      if (constraints.padding != d.padding)
        'padding': formatNum(constraints.padding),
      if (constraints.paddingInsets != null)
        'paddingInsets': formatEdgeInsets(constraints.paddingInsets!),
      if (constraints.percentBasis != d.percentBasis)
        'percentBasis': 'SlotPercentBasis.${constraints.percentBasis.name}',
      if (constraints.fitContent != null)
        'fitContent': '${constraints.fitContent}',
    };
    final prefix = includeConst ? 'const ' : '';
    return formatCall(
      '${prefix}SlotSizeConstraints',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [ScrollbarStyleConfig] en omettant les valeurs par défaut.
  String formatScrollbarStyle(
    ScrollbarStyleConfig style, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = ScrollbarStyleConfig();
    final args = <String, String>{
      if (style.thumbVisibility != d.thumbVisibility)
        'thumbVisibility': '${style.thumbVisibility}',
      if (style.trackVisibility != d.trackVisibility)
        'trackVisibility': '${style.trackVisibility}',
      if (style.interactive != d.interactive)
        'interactive': '${style.interactive}',
      if (style.thickness != d.thickness)
        'thickness': formatNum(style.thickness),
      if (style.radius != d.radius) 'radius': formatNum(style.radius),
      if (style.mainAxisMargin != d.mainAxisMargin)
        'mainAxisMargin': formatNum(style.mainAxisMargin),
      if (style.crossAxisMargin != d.crossAxisMargin)
        'crossAxisMargin': formatNum(style.crossAxisMargin),
      if (style.thumbColor != null)
        'thumbColor': formatColor(style.thumbColor!),
      if (style.trackColor != null)
        'trackColor': formatColor(style.trackColor!),
      if (style.trackBorderColor != null)
        'trackBorderColor': formatColor(style.trackBorderColor!),
      if (style.side != d.side) 'side': 'ScrollbarSide.${style.side.name}',
    };
    final prefix = includeConst ? 'const ' : '';
    return formatCall(
      '${prefix}ScrollbarStyleConfig',
      const [],
      args,
      indent: indent,
    );
  }

  /// Formate un [ZoneFlowConfig] en omettant les valeurs par défaut.
  String formatZoneFlowConfig(
    ZoneFlowConfig flow, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = ZoneFlowConfig();
    final args = <String, String>{
      if (flow.scrollable != d.scrollable) 'scrollable': '${flow.scrollable}',
      if (flow.showScrollbar != d.showScrollbar)
        'showScrollbar': '${flow.showScrollbar}',
      if (!flow.scrollbarStyle.isDefault)
        'scrollbarStyle': formatScrollbarStyle(
          flow.scrollbarStyle,
          indent: indent + 2,
        ),
      if (flow.expandSlots != d.expandSlots)
        'expandSlots': '${flow.expandSlots}',
      if (flow.mainAxisAlignment != d.mainAxisAlignment)
        'mainAxisAlignment': 'MainAxisAlignment.${flow.mainAxisAlignment.name}',
      if (flow.crossAxisAlignment != d.crossAxisAlignment)
        'crossAxisAlignment':
            'CrossAxisAlignment.${flow.crossAxisAlignment.name}',
      if (flow.spacing != d.spacing) 'spacing': formatNum(flow.spacing),
      if (flow.padding != d.padding) 'padding': formatNum(flow.padding),
      if (flow.paddingInsets != null)
        'paddingInsets': formatEdgeInsets(flow.paddingInsets!),
    };
    final prefix = includeConst ? 'const ' : '';
    return formatCall(
      '${prefix}ZoneFlowConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [GridSlotPosition] en omettant les valeurs par défaut.
  String formatGridSlotPosition(
    GridSlotPosition pos, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = GridSlotPosition();
    final args = <String, String>{
      if (pos.x != d.x) 'x': '${pos.x}',
      if (pos.y != d.y) 'y': '${pos.y}',
      if (pos.width != d.width) 'width': '${pos.width}',
      if (pos.height != d.height) 'height': '${pos.height}',
    };
    final prefix = includeConst ? 'const ' : '';
    return formatCall(
      '${prefix}GridSlotPosition',
      const [],
      args,
      indent: indent,
    );
  }

  /// Formate un [GridLayoutConfig] en omettant les valeurs par défaut.
  String formatGridLayoutConfig(
    GridLayoutConfig grid, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = GridLayoutConfig();
    final args = <String, String>{
      if (grid.columns != d.columns) 'columns': '${grid.columns}',
      if (grid.rowHeight != d.rowHeight) 'rowHeight': formatNum(grid.rowHeight),
      if (grid.gap != d.gap) 'gap': formatNum(grid.gap),
      if (grid.compact != d.compact) 'compact': '${grid.compact}',
      if (grid.items.isNotEmpty)
        'items': formatMap({
          for (final entry in grid.items.entries)
            formatString(entry.key): formatGridSlotPosition(
              entry.value,
              indent: indent + 4,
            ),
        }, indent: indent + 2),
    };
    final prefix = includeConst ? 'const ' : '';
    return formatCall(
      '${prefix}GridLayoutConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [ContainerFill] en omettant les valeurs par défaut.
  String formatContainerFill(
    ContainerFill fill, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = ContainerFill();
    final args = <String, String>{
      if (fill.type != d.type) 'type': 'FillType.${fill.type.name}',
      if (fill.start != d.start) 'start': formatColor(fill.start),
      if (fill.end != d.end) 'end': formatColor(fill.end),
      if (fill.angle != d.angle) 'angle': formatNum(fill.angle),
      if (fill.radius != d.radius) 'radius': formatNum(fill.radius),
      if (fill.imageUrl != d.imageUrl) 'imageUrl': formatString(fill.imageUrl),
      if (fill.imageBinding != null)
        'imageBinding': formatBinding(fill.imageBinding!, indent: indent + 2),
      if (fill.imageFit != d.imageFit)
        'imageFit': 'BoxFit.${fill.imageFit.name}',
      if (fill.imageOpacity != d.imageOpacity)
        'imageOpacity': formatNum(fill.imageOpacity),
    };
    final prefix = includeConst ? 'const ' : '';
    return formatCall('${prefix}ContainerFill', const [], args, indent: indent);
  }

  /// Formate un [NeonStyle] en omettant les valeurs par défaut.
  String formatNeonStyle(
    NeonStyle neon, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = NeonStyle();
    final args = <String, String>{
      if (neon.enabled != d.enabled) 'enabled': '${neon.enabled}',
      if (neon.color != null) 'color': formatColor(neon.color!),
      if (neon.intensity != d.intensity) 'intensity': formatNum(neon.intensity),
    };
    final prefix = includeConst ? 'const ' : '';
    return formatCall('${prefix}NeonStyle', const [], args, indent: indent);
  }

  /// Formate un [ShadowSpec] en omettant les valeurs par défaut.
  String formatShadowSpec(
    ShadowSpec shadow, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = ShadowSpec();
    final args = <String, String>{
      if (shadow.enabled != d.enabled) 'enabled': '${shadow.enabled}',
      if (shadow.color != d.color) 'color': formatColor(shadow.color),
      if (shadow.opacity != d.opacity) 'opacity': formatNum(shadow.opacity),
      if (shadow.blur != d.blur) 'blur': formatNum(shadow.blur),
      if (shadow.spread != d.spread) 'spread': formatNum(shadow.spread),
      if (shadow.dx != d.dx) 'dx': formatNum(shadow.dx),
      if (shadow.dy != d.dy) 'dy': formatNum(shadow.dy),
    };
    final prefix = includeConst ? 'const ' : '';
    return formatCall('${prefix}ShadowSpec', const [], args, indent: indent);
  }

  /// Formate un [TransformSpec] en omettant les valeurs par défaut.
  String formatTransformSpec(
    TransformSpec transform, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = TransformSpec();
    final args = <String, String>{
      if (transform.dx != d.dx) 'dx': formatNum(transform.dx),
      if (transform.dy != d.dy) 'dy': formatNum(transform.dy),
      if (transform.rotation != d.rotation)
        'rotation': formatNum(transform.rotation),
      if (transform.scale != d.scale) 'scale': formatNum(transform.scale),
    };
    final prefix = includeConst ? 'const ' : '';
    return formatCall('${prefix}TransformSpec', const [], args, indent: indent);
  }

  /// Formate un [SelectedSurfaceStyle].
  String formatSelectedSurfaceStyle(
    SelectedSurfaceStyle selected, {
    int indent = 0,
  }) {
    return formatCall(
      'SelectedSurfaceStyle',
      const [],
      {
        if (selected.style != const ContainerStyle())
          'style': formatContainerStyle(
            selected.style,
            indent: indent + 2,
            includeConst: canContainerStyleBeConst(selected.style),
          ),
        if (selected.properties.isNotEmpty)
          'properties': formatSet(
            selected.properties.map((p) => 'SurfaceStyleProperty.${p.name}'),
            indent: indent + 2,
            isConst: true,
          ),
      },
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate des [SurfaceStyleStates].
  String formatSurfaceStyleStates(SurfaceStyleStates states, {int indent = 0}) {
    final args = <String, String>{
      if (states.binding != null)
        'binding': formatBinding(
          states.binding!,
          indent: indent + 2,
          includeConst: true,
        ),
      if (states.named.isNotEmpty)
        'named': formatMap({
          for (final entry in states.named.entries)
            formatString(entry.key): formatContainerStyle(
              entry.value,
              indent: indent + 4,
              includeConst: canContainerStyleBeConst(entry.value),
            ),
        }, indent: indent + 2),
      if (states.namedProperties.values.any((s) => s.isNotEmpty))
        'namedProperties': formatMap(
          {
            for (final entry in states.namedProperties.entries)
              if (entry.value.isNotEmpty)
                formatString(entry.key): formatSet(
                  entry.value.map((p) => 'SurfaceStyleProperty.${p.name}'),
                  indent: indent + 4,
                ),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (states.hover != null)
        'hover': formatSelectedSurfaceStyle(states.hover!, indent: indent + 2),
      if (states.selected != null)
        'selected': formatSelectedSurfaceStyle(
          states.selected!,
          indent: indent + 2,
        ),
      if (states.automatic.isNotEmpty)
        'automatic': formatMap({
          for (final entry in states.automatic.entries)
            'AutomaticState.${entry.key.name}': formatSelectedSurfaceStyle(
              entry.value,
              indent: indent + 4,
            ),
        }, indent: indent + 2),
    };
    return formatCall(
      'SurfaceStyleStates',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Indique si un [ContainerStyle] peut être préfixé par `const`.
  bool canContainerStyleBeConst(ContainerStyle style) => style.states == null;

  /// Formate un [ContainerStyle] en omettant les valeurs par défaut.
  String formatContainerStyle(
    ContainerStyle style, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = ContainerStyle();
    final canBeConst = includeConst && canContainerStyleBeConst(style);
    final args = <String, String>{
      if (style.color != null)
        'color': formatColor(style.color!, includeConst: !canBeConst),
      if (style.fill != d.fill)
        'fill': formatContainerFill(
          style.fill,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (style.radius != d.radius) 'radius': formatNum(style.radius),
      if (style.borderWidth != d.borderWidth)
        'borderWidth': formatNum(style.borderWidth),
      if (style.borderColor != null)
        'borderColor': formatColor(
          style.borderColor!,
          includeConst: !canBeConst,
        ),
      if (style.elevation != d.elevation)
        'elevation': formatNum(style.elevation),
      if (style.shadowOpacity != d.shadowOpacity)
        'shadowOpacity': formatNum(style.shadowOpacity),
      if (style.neon != null)
        'neon': formatNeonStyle(
          style.neon!,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (style.padding != d.padding) 'padding': formatNum(style.padding),
      if (style.margin != d.margin) 'margin': formatNum(style.margin),
      if (style.designSystem != d.designSystem)
        'designSystem': 'DesignSystem.${style.designSystem.name}',
      if (style.interactionEffect != d.interactionEffect)
        'interactionEffect':
            'InteractionEffect.${style.interactionEffect.name}',
      if (style.hoverEffect != d.hoverEffect)
        'hoverEffect': '${style.hoverEffect}',
      if (style.hoverTint != d.hoverTint)
        'hoverTint': 'HoverTint.${style.hoverTint.name}',
      if (style.hoverColor != null)
        'hoverColor': formatColor(style.hoverColor!, includeConst: !canBeConst),
      if (style.radii != null)
        'radii': formatQuad(style.radii!, includeConst: !canBeConst),
      if (style.borderWidths != null)
        'borderWidths': formatQuad(
          style.borderWidths!,
          includeConst: !canBeConst,
        ),
      if (style.borderLine != d.borderLine)
        'borderLine': 'BorderLine.${style.borderLine.name}',
      if (style.shadow != null)
        'shadow': formatShadowSpec(
          style.shadow!,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (style.innerShadow != null)
        'innerShadow': formatShadowSpec(
          style.innerShadow!,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (style.opacity != d.opacity) 'opacity': formatNum(style.opacity),
      if (style.paddingInsets != null)
        'paddingInsets': formatQuad(
          style.paddingInsets!,
          includeConst: !canBeConst,
        ),
      if (style.marginInsets != null)
        'marginInsets': formatQuad(
          style.marginInsets!,
          includeConst: !canBeConst,
        ),
      if (style.backdropBlur != null)
        'backdropBlur': formatNum(style.backdropBlur!),
      if (style.pattern != d.pattern)
        'pattern': 'SurfacePattern.${style.pattern.name}',
      if (style.patternOpacity != d.patternOpacity)
        'patternOpacity': formatNum(style.patternOpacity),
      if (style.transform != null)
        'transform': formatTransformSpec(
          style.transform!,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (style.propertyBindings.isNotEmpty)
        'propertyBindings': formatPropertyBindings(
          'ContainerStyleProperty',
          style.propertyBindings,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (style.states != null)
        'states': formatSurfaceStyleStates(style.states!, indent: indent + 2),
    };
    final prefix = canBeConst ? 'const ' : '';
    return formatCall(
      '${prefix}ContainerStyle',
      const [],
      args,
      indent: indent,
      forceMultiline: args.length > 1,
    );
  }

  /// Résout la clé canonique de [Registry.registry] pour un composant [id] et un [slotType] optionnel.
  String? resolveRegistryType(String id, {String? slotType}) {
    if (slotType != null && slotType.isNotEmpty) {
      final stripped = slotType.startsWith('registry:')
          ? slotType.substring('registry:'.length)
          : slotType;
      if (registry.registry.containsKey(stripped)) {
        return stripped;
      }
      final match = registry.registry.keys
          .where((k) => k.toLowerCase() == stripped.toLowerCase())
          .firstOrNull;
      if (match != null) return match;
    }
    final config = appearance.components[id];
    return switch (config) {
      SuperLayoutConfig() => 'Layout',
      SuperValueConfig() => 'Value',
      SuperActionConfig() => 'Action',
      SuperIndicatorConfig() => 'Indicator',
      SuperSeparatorConfig() => 'Separator',
      SuperListViewConfig() => 'ListView',
      SuperTabConfig() => 'Tab',
      SuperTreeViewConfig() => 'TreeView',
      SuperTableConfig() => 'Table',
      SuperRendererConfig() => 'Renderer',
      NativeComponentConfig() =>
        appearance.styles.containsKey(id)
            ? 'Card'
            : _inferNativeType(id, config),
      final ComponentConfig other =>
        registry.registry.keys
            .where(
              (key) => key.toLowerCase() == other.componentType.toLowerCase(),
            )
            .firstOrNull,
      null => appearance.styles.containsKey(id) ? 'Card' : null,
    };
  }

  String _inferNativeType(String id, NativeComponentConfig config) {
    if (config.placements.containsKey('leading') ||
        config.placements.containsKey('title') ||
        config.placements.containsKey('actions')) {
      return 'ApplicationBar';
    }
    if (config.placements.containsKey('destinations')) {
      return 'BottomNavigationBar';
    }
    if (config.placements.containsKey('header') &&
        config.placements.containsKey('body')) {
      return config.properties.containsKey('consumeOutsideTap') ||
              config.properties.containsKey('alignmentOffsetX') ||
              id.toLowerCase().contains('menu')
          ? 'Menu'
          : 'Expansible';
    }
    return 'Card';
  }

  /// Résout la clé d'un [RegisteredComponent] dans [Registry.components] pour [id] et [slotType].
  String? resolveRegisteredComponentKey(String id, {String? slotType}) {
    final candidates = <String>[
      if (slotType != null && slotType.isNotEmpty) ...[
        slotType,
        if (slotType.startsWith('component:'))
          slotType.substring('component:'.length),
        if (slotType.startsWith('registry:'))
          Uri.decodeComponent(slotType.substring('registry:'.length)),
      ],
      id,
    ];
    for (final candidate in candidates) {
      if (registry.components.containsKey(candidate)) {
        return candidate;
      }
      for (final entry in registry.components.entries) {
        if (entry.value.slotId == candidate) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// Résout le [ComponentDartGenerator] associé à [id] (et au [slotType] éventuel).
  ComponentDartGenerator? resolveGenerator(String id, {String? slotType}) {
    final regType = resolveRegistryType(id, slotType: slotType);
    if (regType != null) {
      final generator = registry.registry[regType]?.dartGenerator;
      if (generator != null) return generator;
    }
    return null;
  }

  /// Génère l'expression Dart du widget pour l'identifiant [id].
  String generateComponentWidget(
    String id, {
    String? slotType,
    String? label,
    int indent = 0,
  }) {
    if (!_visiting.add(id)) {
      return 'const SizedBox.shrink()';
    }
    try {
      // Vérifie si ce sous-composant a été configuré via « Configure as... »
      final exportOpts = registry.exportOptionsFor(id);
      if (id != rootComponentId &&
          exportOpts != null &&
          exportOpts.generateComponentOnExport &&
          (!decomposeComponents || exportOpts.forceComponentOnExport)) {
        final regName = exportOpts.componentName.trim().isNotEmpty
            ? exportOpts.componentName.trim()
            : id;
        if (_extractedIds.add(id)) {
          extractedSubComponents.add((
            id: id,
            registrationId: regName,
            label: (label != null && label.trim().isNotEmpty)
                ? label.trim()
                : regName,
            slotType: slotType,
            forceComponentOnExport: exportOpts.forceComponentOnExport,
          ));
        }
        return 'SuperApp.of(context).registry!.component(${formatString(regName)}).builder(context)';
      }

      if (slotType != null && slotType.startsWith('component:')) {
        final registeredKey = resolveRegisteredComponentKey(
          id,
          slotType: slotType,
        );
        if (registeredKey != null) {
          final registeredComp = registry.components[registeredKey];
          final regExportOpts =
              exportOpts ?? registry.exportOptionsFor(registeredKey);
          final forced = regExportOpts?.forceComponentOnExport ?? false;
          final shouldDecompose =
              decomposeComponents &&
              !forced &&
              (registeredComp?.decomposableOnExport ?? false);
          if (!shouldDecompose) {
            final effectiveRegKey =
                (regExportOpts != null &&
                    regExportOpts.componentName.trim().isNotEmpty)
                ? regExportOpts.componentName.trim()
                : registeredKey;
            return 'SuperApp.of(context).registry!.component(${formatString(effectiveRegKey)}).builder(context)';
          }
          final decomposedGenerator = resolveGenerator(id);
          if (decomposedGenerator != null) {
            return decomposedGenerator.generateWidget(
              this,
              id: id,
              label: label,
              indent: indent,
            );
          }
        }
      }
      final generator = resolveGenerator(id, slotType: slotType);
      if (generator != null) {
        return generator.generateWidget(
          this,
          id: id,
          label: label,
          indent: indent,
        );
      }
      final registeredKey = resolveRegisteredComponentKey(
        id,
        slotType: slotType,
      );
      if (registeredKey != null) {
        return 'SuperApp.of(context).registry!.component(${formatString(registeredKey)}).builder(context)';
      }
      return 'const SizedBox.shrink()';
    } finally {
      _visiting.remove(id);
    }
  }

  /// Génère une entrée `BuilderSlot(id: ..., label: ..., builder: (_) => ...)` pour [id].
  String generateBuilderSlot(
    String id, {
    String? slotType,
    String? label,
    Size? preferredSize,
    int indent = 0,
  }) {
    final effectiveLabel = (label != null && label.trim().isNotEmpty)
        ? label.trim()
        : id;
    final widgetCode = generateComponentWidget(
      id,
      slotType: slotType,
      label: effectiveLabel,
      indent: indent + 2,
    );
    final usesContext = widgetCode.contains('(context)');
    final args = <String, String>{
      'id': formatString(id),
      'label': formatString(effectiveLabel),
      if (preferredSize != null)
        'preferredSize': formatSize(preferredSize, includeConst: true),
      'builder': '(${usesContext ? 'context' : '_'}) => $widgetCode',
    };
    return formatCall(
      'BuilderSlot',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}

/// Service d'export d'une [Appearance] (ou d'un fragment issu de `EditorPageGraph.export`)
