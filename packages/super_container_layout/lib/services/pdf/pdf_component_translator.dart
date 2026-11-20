/// Traducteur hybride ([PdfComponentTranslator]) des composants GenUI vers `package:pdf`.
///
/// Convertit vectoriellement les composants standards (`SuperLayout`, `Card`,
/// `IterableContent`, `SuperValue`, `SuperSeparator`, `SuperIndicator`,
/// `SuperAction`, `SuperConditional`, `SuperListView`, `SuperTable`, `SuperTab`)
/// en widgets `pw.Widget`, et bascule automatiquement sur [PdfRasterFallback]
/// pour les extensions (`SuperChart`, `SuperCode`, etc.) et effets visuels avancés
/// (néon, flou, motifs, images complexes).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/component_config.dart';
import '../../models/json_text_binding.dart';
import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/super_action_config.dart';
import '../../models/super_conditional_config.dart';
import '../../models/super_indicator_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_list_view_config.dart';
import '../../models/super_separator_config.dart';
import '../../models/super_tab_config.dart';
import '../../models/super_table_config.dart';
import '../../models/super_value_config.dart';
import '../../theme/appearance.dart';
import '../../theme/container_fill.dart';
import '../../theme/container_style.dart';
import '../../theme/style_extras.dart';
import '../../theme/theme_color.dart';
import '../repositories/json_list_scope.dart';
import '../repositories/json_repository_store.dart';
import 'pdf_font_resolver.dart';
import 'pdf_raster_fallback.dart';

/// Contexte d'exécution transmis pendant la traduction PDF d'une feuille A4.
class PdfTranslationContext {
  /// Crée un contexte de traduction PDF.
  PdfTranslationContext({
    required this.buildContext,
    required this.appearance,
    required this.registry,
    required this.repositoryStore,
    required this.flutterTheme,
    required this.fontResolver,
    this.rasterPixelRatio = 3.0,
    this.customRasterCapture,
  });

  /// Contexte Flutter appelant (fournit `Overlay` et portées pour le fallback raster).
  final BuildContext? buildContext;

  /// Instantané de l'apparence courante.
  final Appearance appearance;

  /// Registre des composants.
  final Registry? registry;

  /// Magasin des repositories JSON actifs.
  final JsonRepositoryStore? repositoryStore;

  /// Thème Material effectif de la feuille papier courante.
  final ThemeData flutterTheme;

  /// Résolveur de polices TrueType embarquées.
  final PdfFontResolver fontResolver;

  /// Densité de capture utilisée lors d'un fallback raster.
  final double rasterPixelRatio;

  /// Hook optionnel de capture raster pour les tests.
  final PdfRasterCaptureCallback? customRasterCapture;

  /// Nombre d'éléments ayant basculé en capture raster durant la génération.
  int rasterFallbackCount = 0;

  /// Schéma de couleurs résolu de la feuille.
  ColorScheme get colorScheme => flutterTheme.colorScheme;
}

/// Traduit récursivement un arbre GenUI `Appearance.components` en `pw.Widget`.
class PdfComponentTranslator {
  /// Crée un traducteur lié à [ctx].
  PdfComponentTranslator(this.ctx);

  /// Contexte partagé de la génération PDF.
  final PdfTranslationContext ctx;

  /// Traduit le slot [slotId] (type [slotType]) dans une contrainte de taille [availableSize].
  Future<pw.Widget> translateSlot({
    required String slotId,
    required String slotType,
    required Size availableSize,
    JsonListScope? listScope,
    Set<String> visited = const {},
  }) async {
    if (visited.contains(slotId)) {
      return pw.SizedBox.shrink();
    }
    final nextVisited = {...visited, slotId};
    final config = ctx.appearance.components[slotId];
    final style = ctx.appearance.styles[slotId];
    final shortType = _shortType(slotType, config);

    if (style != null && _requiresRasterStyle(style)) {
      return _rasterize(
        componentId: slotId,
        slotType: slotType,
        size: availableSize,
        listScope: listScope,
      );
    }

    pw.Widget content;
    switch (shortType) {
      case 'Layout':
        final layout = config is SuperLayoutConfig
            ? config
            : const SuperLayoutConfig();
        content = await _translateLayout(
          layout: layout,
          availableSize: availableSize,
          listScope: listScope,
          visited: nextVisited,
        );
      case 'Card':
      case 'IterableContent':
        content = await _translateCardOrNative(
          id: slotId,
          config: config is NativeComponentConfig ? config : null,
          availableSize: availableSize,
          listScope: listScope,
          visited: nextVisited,
        );
      case 'Value':
        content = await _translateValue(
          config: config is SuperValueConfig
              ? config
              : const SuperValueConfig(),
          listScope: listScope,
        );
      case 'Separator':
        content = await _translateSeparator(
          config: config is SuperSeparatorConfig
              ? config
              : const SuperSeparatorConfig(),
          listScope: listScope,
        );
      case 'Indicator':
        content = await _translateIndicator(
          config: config is SuperIndicatorConfig
              ? config
              : const SuperIndicatorConfig(),
          listScope: listScope,
        );
      case 'Action':
        content = await _translateAction(
          config: config is SuperActionConfig
              ? config
              : const SuperActionConfig(),
          listScope: listScope,
        );
      case 'Conditional':
        content = await _translateConditional(
          config: config is SuperConditionalConfig
              ? config
              : SuperConditionalConfig(),
          availableSize: availableSize,
          listScope: listScope,
          visited: nextVisited,
        );
      case 'ListView':
        content = await _translateListView(
          id: slotId,
          config: config is SuperListViewConfig
              ? config
              : const SuperListViewConfig(),
          availableSize: availableSize,
          listScope: listScope,
          visited: nextVisited,
        );
      case 'Table':
        content = await _translateTable(
          config: config is SuperTableConfig ? config : SuperTableConfig(),
          availableSize: availableSize,
          listScope: listScope,
          visited: nextVisited,
        );
      case 'Tab':
        content = await _translateTab(
          config: config is SuperTabConfig ? config : SuperTabConfig(),
          availableSize: availableSize,
          listScope: listScope,
          visited: nextVisited,
        );
      default:
        // Extensions (`SuperChart`, `SuperCode`, etc.) ou composants personnalisés.
        if (config is NativeComponentConfig) {
          content = await _translateCardOrNative(
            id: slotId,
            config: config,
            availableSize: availableSize,
            listScope: listScope,
            visited: nextVisited,
          );
        } else {
          return _rasterize(
            componentId: slotId,
            slotType: slotType,
            size: availableSize,
            listScope: listScope,
          );
        }
    }

    if (style != null && style != const ContainerStyle()) {
      final hasVisibleDecoration =
          style.color != null ||
          style.fill.type != FillType.solid ||
          style.borderWidth > 0 ||
          (style.borderWidths != null &&
              (style.borderWidths!.top > 0 ||
                  style.borderWidths!.right > 0 ||
                  style.borderWidths!.bottom > 0 ||
                  style.borderWidths!.left > 0));
      if (shortType == 'Card' &&
          (config is! NativeComponentConfig || config.placements.isEmpty) &&
          hasVisibleDecoration &&
          style.padding == 0 &&
          style.paddingInsets == null) {
        content = pw.SizedBox(height: 24);
      }
      content = _wrapWithStyle(content, style);
    }
    return content;
  }

  Future<pw.Widget> _rasterize({
    required String componentId,
    required String slotType,
    required Size size,
    JsonListScope? listScope,
  }) async {
    final targetSize = Size(
      size.width.isFinite && size.width > 16 ? size.width : 480.0,
      size.height.isFinite && size.height > 16 ? size.height : 240.0,
    );
    final Uint8List? bytes = await PdfRasterFallback.captureComponent(
      context: ctx.buildContext,
      appearance: ctx.appearance,
      registry: ctx.registry,
      repositoryStore: ctx.repositoryStore,
      theme: ctx.flutterTheme,
      componentId: componentId,
      slotType: slotType,
      logicalSize: targetSize,
      listScope: listScope,
      pixelRatio: ctx.rasterPixelRatio,
      customCapture: ctx.customRasterCapture,
    );
    if (bytes == null || bytes.isEmpty) {
      return pw.Container(
        width: targetSize.width,
        height: targetSize.height,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(
          componentId,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      );
    }
    ctx.rasterFallbackCount++;
    return pw.Image(
      pw.MemoryImage(bytes),
      width: targetSize.width,
      height: targetSize.height,
      fit: pw.BoxFit.contain,
    );
  }

  Future<pw.Widget> _translateCardOrNative({
    required String id,
    required NativeComponentConfig? config,
    required Size availableSize,
    required JsonListScope? listScope,
    required Set<String> visited,
  }) async {
    if (config == null || config.placements.isEmpty) {
      return pw.SizedBox.shrink();
    }
    final children = <pw.Widget>[];
    for (final entry in config.placements.entries) {
      if (!config.isEnabled(entry.key)) continue;
      for (final childId in entry.value) {
        final childType = config.slotTypeOf(childId);
        final childWidget = await translateSlot(
          slotId: childId,
          slotType: childType,
          availableSize: availableSize,
          listScope: listScope,
          visited: visited,
        );
        children.add(
          _applySlotConstraints(
            childWidget,
            config.slotSizeConstraints[childId],
            config.slotPreferredSizes[childId],
            availableSize,
          ),
        );
      }
    }
    if (children.isEmpty) return pw.SizedBox.shrink();
    if (children.length == 1) return children.first;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: children,
    );
  }

  Future<pw.Widget> _translateLayout({
    required SuperLayoutConfig layout,
    required Size availableSize,
    required JsonListScope? listScope,
    required Set<String> visited,
  }) async {
    if (layout.positioning == SuperLayoutPositioning.grid &&
        layout.grid != null) {
      return _translateGridLayout(
        layout: layout,
        grid: layout.grid!,
        availableSize: availableSize,
        listScope: listScope,
        visited: visited,
      );
    }

    Future<pw.Widget?> buildZone(
      SuperLayoutZone visualZone,
      Size zoneSize, {
      bool boundedWidth = true,
      bool boundedHeight = false,
    }) async {
      final contentZone = layout.contentZone(visualZone);
      final ids = layout.placementsOf(contentZone);
      if (ids.isEmpty) return null;
      final axis = layout.axisOf(visualZone);
      final flow = layout.flowOf(visualZone);

      final items = <pw.Widget>[];
      for (var i = 0; i < ids.length; i++) {
        final slotId = ids[i];
        final slotType = layout.slotTypeOf(slotId);
        final constraints = layout.slotSizeConstraints[slotId];
        final preferred = layout.slotPreferredSizes[slotId];
        final slotAvail = _resolveChildAvailableSize(
          zoneSize,
          constraints,
          preferred,
        );
        final translated = await translateSlot(
          slotId: slotId,
          slotType: slotType,
          availableSize: slotAvail,
          listScope: listScope,
          visited: visited,
        );
        var wrapped = _applySlotConstraints(
          translated,
          constraints,
          preferred,
          zoneSize,
        );
        final shouldExpand =
            axis == Axis.horizontal &&
            boundedWidth &&
            (constraints?.fitContent == false ||
                (constraints?.fitContent == null &&
                    flow.expandSlots &&
                    constraints?.preferredWidth == null &&
                    constraints?.preferredHeight == null &&
                    preferred == null));
        if (shouldExpand) {
          wrapped = pw.Expanded(child: wrapped);
        }
        items.add(wrapped);
        if (flow.spacing > 0 && i < ids.length - 1) {
          items.add(
            axis == Axis.horizontal
                ? pw.SizedBox(width: flow.spacing)
                : pw.SizedBox(height: flow.spacing),
          );
        }
      }

      final crossAlign = _pwCrossAxis(flow.crossAxisAlignment);
      pw.Widget zoneWidget;
      if (axis == Axis.horizontal) {
        final safeCross =
            !boundedHeight && crossAlign == pw.CrossAxisAlignment.stretch
            ? pw.CrossAxisAlignment.start
            : crossAlign;
        zoneWidget = pw.Row(
          mainAxisAlignment: _pwMainAxis(flow.mainAxisAlignment),
          crossAxisAlignment: safeCross,
          mainAxisSize: boundedWidth ? pw.MainAxisSize.max : pw.MainAxisSize.min,
          children: items,
        );
      } else {
        final safeCross =
            !boundedWidth && crossAlign == pw.CrossAxisAlignment.stretch
            ? pw.CrossAxisAlignment.start
            : crossAlign;
        zoneWidget = pw.Column(
          mainAxisAlignment: _pwMainAxis(flow.mainAxisAlignment),
          crossAxisAlignment: safeCross,
          mainAxisSize: pw.MainAxisSize.min,
          children: items,
        );
      }

      if (flow.hasPadding) {
        zoneWidget = pw.Padding(
          padding: _pwEdgeInsets(flow.contentPadding),
          child: zoneWidget,
        );
      }
      return zoneWidget;
    }

    final northAuto = layout.isAuto(SuperLayoutZone.north);
    final southAuto = layout.isAuto(SuperLayoutZone.south);
    final westAuto = layout.isAuto(SuperLayoutZone.west);
    final eastAuto = layout.isAuto(SuperLayoutZone.east);

    final northH = layout.north
        ? (northAuto ? 120.0 : layout.northSize)
        : 0.0;
    final southH = layout.south
        ? (southAuto ? 120.0 : layout.southSize)
        : 0.0;
    final westW = layout.west ? (westAuto ? 160.0 : layout.westSize) : 0.0;
    final eastW = layout.east ? (eastAuto ? 160.0 : layout.eastSize) : 0.0;
    final centerW = math.max(40.0, availableSize.width - westW - eastW);
    final centerH = math.max(40.0, availableSize.height - northH - southH);

    final northWidget = layout.north
        ? await buildZone(
            SuperLayoutZone.north,
            Size(availableSize.width, northH),
            boundedWidth: true,
            boundedHeight: !northAuto,
          )
        : null;
    final southWidget = layout.south
        ? await buildZone(
            SuperLayoutZone.south,
            Size(availableSize.width, southH),
            boundedWidth: true,
            boundedHeight: !southAuto,
          )
        : null;
    final westWidget = layout.west
        ? await buildZone(
            SuperLayoutZone.west,
            Size(westW, centerH),
            boundedWidth: !westAuto,
            boundedHeight: false,
          )
        : null;
    final eastWidget = layout.east
        ? await buildZone(
            SuperLayoutZone.east,
            Size(eastW, centerH),
            boundedWidth: !eastAuto,
            boundedHeight: false,
          )
        : null;
    final centerWidget = await buildZone(
      SuperLayoutZone.center,
      Size(centerW, centerH),
      boundedWidth: true,
      boundedHeight: false,
    );

    final middleRowChildren = <pw.Widget>[
      if (westWidget != null)
        westAuto
            ? pw.ConstrainedBox(
                constraints: pw.BoxConstraints(
                  maxWidth: availableSize.width * 0.45,
                ),
                child: westWidget,
              )
            : pw.SizedBox(width: layout.westSize, child: westWidget),
      if (westWidget != null || eastWidget != null)
        pw.Expanded(child: centerWidget ?? pw.SizedBox.shrink())
      else
        centerWidget ?? pw.SizedBox.shrink(),
      if (eastWidget != null)
        eastAuto
            ? pw.ConstrainedBox(
                constraints: pw.BoxConstraints(
                  maxWidth: availableSize.width * 0.45,
                ),
                child: eastWidget,
              )
            : pw.SizedBox(width: layout.eastSize, child: eastWidget),
    ];

    final middle = middleRowChildren.length == 1
        ? middleRowChildren.first
        : pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: middleRowChildren,
          );

    if (northWidget == null && southWidget == null) {
      return middle;
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        if (northWidget != null)
          northAuto
              ? northWidget
              : pw.SizedBox(height: layout.northSize, child: northWidget),
        middle,
        if (southWidget != null)
          southAuto
              ? southWidget
              : pw.SizedBox(height: layout.southSize, child: southWidget),
      ],
    );
  }

  Future<pw.Widget> _translateGridLayout({
    required SuperLayoutConfig layout,
    required GridLayoutConfig grid,
    required Size availableSize,
    required JsonListScope? listScope,
    required Set<String> visited,
  }) async {
    if (grid.items.isEmpty) return pw.SizedBox.shrink();
    final colWidth =
        (availableSize.width - grid.gap * (grid.columns - 1)) / grid.columns;
    var maxRow = 0;
    for (final pos in grid.items.values) {
      maxRow = math.max(maxRow, pos.y + pos.height);
    }
    final totalHeight = math.max(
      grid.rowHeight,
      maxRow * grid.rowHeight + math.max(0, maxRow - 1) * grid.gap,
    );
    final positioned = <pw.Widget>[];
    for (final entry in grid.items.entries) {
      final slotId = entry.key;
      final pos = entry.value;
      final left = pos.x * (colWidth + grid.gap);
      final top = pos.y * (grid.rowHeight + grid.gap);
      final width = pos.width * colWidth + (pos.width - 1) * grid.gap;
      final height = pos.height * grid.rowHeight + (pos.height - 1) * grid.gap;
      final child = await translateSlot(
        slotId: slotId,
        slotType: layout.slotTypeOf(slotId),
        availableSize: Size(width, height),
        listScope: listScope,
        visited: visited,
      );
      positioned.add(
        pw.Positioned(
          left: left,
          top: top,
          child: pw.SizedBox(width: width, height: height, child: child),
        ),
      );
    }
    return pw.SizedBox(
      width: availableSize.width,
      height: totalHeight,
      child: pw.Stack(children: positioned),
    );
  }

  Future<pw.Widget> _translateValue({
    required SuperValueConfig config,
    required JsonListScope? listScope,
  }) async {
    String textValue = config.initialText;
    if (config.kind.isBoolean) {
      var boolVal = config.initialBool;
      if (config.binding != null) {
        final raw = await _readBindingRaw(config.binding!, listScope);
        if (raw is bool) boolVal = raw;
      }
      textValue = boolVal ? 'Oui' : 'Non';
    } else if (config.binding != null) {
      final resolved = await _readBindingText(config.binding!, listScope);
      if (resolved != null) textValue = resolved;
    }

    final label = await _resolvePropString(
      config.propertyBindings[SuperValueProperty.label],
      config.label,
      listScope,
    );
    final prefix = await _resolvePropString(
      config.propertyBindings[SuperValueProperty.prefix],
      config.prefix,
      listScope,
    );
    final suffix = await _resolvePropString(
      config.propertyBindings[SuperValueProperty.suffix],
      config.suffix,
      listScope,
    );
    final familyName = await _resolvePropString(
      config.propertyBindings[SuperValueProperty.fontFamily],
      config.fontFamily ?? '',
      listScope,
    );
    final font = await ctx.fontResolver.resolveFamily(
      familyName.isEmpty ? null : familyName,
    );
    final color = _resolveColor(
      config.color ?? ctx.colorScheme.onSurface,
    );
    final fontSize = config.fontSize ?? 12.0;
    final style = pw.TextStyle(
      font: font.variant(
        weight: config.fontWeight,
        style: config.italic == true ? FontStyle.italic : FontStyle.normal,
      ),
      fontFallback: font.fallback,
      fontSize: fontSize,
      color: color,
      height: config.lineHeight,
      letterSpacing: config.letterSpacing,
    );

    final fullText = '$prefix$textValue$suffix';
    final align = _pwTextAlign(config.textAlign);

    final valueText = pw.Text(
      fullText,
      style: style,
      textAlign: align,
      maxLines: config.maxLines <= 0 ? null : config.maxLines,
    );

    if (label.trim().isEmpty) {
      return valueText;
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label,
          style: style.copyWith(
            fontSize: math.max(8.0, fontSize - 2),
            color: _resolveColor(ctx.colorScheme.onSurfaceVariant),
          ),
          textAlign: align,
        ),
        pw.SizedBox(height: 2),
        valueText,
      ],
    );
  }

  Future<pw.Widget> _translateSeparator({
    required SuperSeparatorConfig config,
    required JsonListScope? listScope,
  }) async {
    if (config.kind == SuperSeparatorKind.spacer) {
      return config.axis == Axis.horizontal
          ? pw.SizedBox(height: config.extent)
          : pw.SizedBox(width: config.extent);
    }
    final color = _resolveColor(
      config.lineColor ?? ctx.colorScheme.outlineVariant,
    );
    if (config.axis == Axis.vertical) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(top: config.indent, bottom: config.endIndent),
        child: pw.Container(width: config.thickness, color: color),
      );
    }
    final label = await _resolvePropString(
      config.propertyBindings[SuperSeparatorProperty.label],
      config.label,
      listScope,
    );
    if (label.trim().isEmpty) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(
          left: config.indent,
          right: config.endIndent,
          top: config.extent / 2,
          bottom: config.extent / 2,
        ),
        child: pw.Container(height: config.thickness, color: color),
      );
    }
    final font = await ctx.fontResolver.resolveFamily(config.fontFamily);
    final labelWidget = pw.Text(
      label,
      style: pw.TextStyle(
        font: font.variant(
          weight: config.fontWeight,
          style: config.italic == true ? FontStyle.italic : FontStyle.normal,
        ),
        fontSize: config.fontSize ?? 10.0,
        color: _resolveColor(config.color ?? ctx.colorScheme.onSurfaceVariant),
      ),
    );
    final line = pw.Expanded(
      child: pw.Container(height: config.thickness, color: color),
    );
    return pw.Padding(
      padding: pw.EdgeInsets.only(
        left: config.indent,
        right: config.endIndent,
        top: config.extent / 2,
        bottom: config.extent / 2,
      ),
      child: pw.Row(
        children: switch (config.labelPosition) {
          SuperSeparatorLabelPosition.start => [
            labelWidget,
            pw.SizedBox(width: config.labelSpacing),
            line,
          ],
          SuperSeparatorLabelPosition.center => [
            line,
            pw.SizedBox(width: config.labelSpacing),
            labelWidget,
            pw.SizedBox(width: config.labelSpacing),
            line,
          ],
          SuperSeparatorLabelPosition.end => [
            line,
            pw.SizedBox(width: config.labelSpacing),
            labelWidget,
          ],
        },
      ),
    );
  }

  Future<pw.Widget> _translateIndicator({
    required SuperIndicatorConfig config,
    required JsonListScope? listScope,
  }) async {
    final label = await _resolvePropString(
      config.propertyBindings[SuperIndicatorProperty.label],
      config.label,
      listScope,
    );
    final bg = config.backgroundColor != null
        ? _resolveColor(config.backgroundColor!)
        : null;
    final border = config.borderColor != null
        ? _resolveColor(config.borderColor!)
        : null;
    final fg = _resolveColor(
      config.color ?? config.iconColor ?? ctx.colorScheme.onSurface,
    );
    final font = await ctx.fontResolver.resolveFamily(config.fontFamily);
    final displayText = label.trim().isNotEmpty ? label : config.icon;
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(
        horizontal: config.horizontalPadding ?? 8,
        vertical: config.verticalPadding ?? 4,
      ),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: config.radius != null
            ? pw.BorderRadius.circular(config.radius!)
            : null,
        border: border != null && (config.borderWidth ?? 1) > 0
            ? pw.Border.all(color: border, width: config.borderWidth ?? 1)
            : null,
      ),
      child: pw.Text(
        displayText,
        style: pw.TextStyle(
          font: font.variant(
            weight: config.fontWeight,
            style: config.italic == true ? FontStyle.italic : FontStyle.normal,
          ),
          fontSize: config.fontSize ?? 11,
          color: fg,
        ),
        textAlign: _pwTextAlign(config.textAlign),
      ),
    );
  }

  Future<pw.Widget> _translateAction({
    required SuperActionConfig config,
    required JsonListScope? listScope,
  }) async {
    final label = await _resolvePropString(
      config.propertyBindings[SuperActionProperty.label],
      config.label,
      listScope,
    );
    if (!config.kind.hasText && label.trim().isEmpty) {
      return pw.SizedBox.shrink();
    }
    final bg = _resolveColor(
      config.backgroundColor ?? ctx.colorScheme.primaryContainer,
    );
    final fg = _resolveColor(
      config.color ?? ctx.colorScheme.onPrimaryContainer,
    );
    final font = await ctx.fontResolver.resolveFamily(config.fontFamily);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(config.radius ?? 8),
        border: config.borderColor != null
            ? pw.Border.all(
                color: _resolveColor(config.borderColor!),
                width: config.borderWidth ?? 1,
              )
            : null,
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          font: font.variant(weight: config.fontWeight ?? FontWeight.w500),
          fontSize: config.fontSize ?? 11,
          color: fg,
        ),
      ),
    );
  }

  Future<pw.Widget> _translateConditional({
    required SuperConditionalConfig config,
    required Size availableSize,
    required JsonListScope? listScope,
    required Set<String> visited,
  }) async {
    var activeValue = config.initialCase;
    if (config.binding != null) {
      final text = await _readBindingText(config.binding!, listScope);
      if (text != null) activeValue = text;
    }
    final matchedZone = config.cases.contains(activeValue)
        ? SuperConditionalConfig.caseZoneFor(activeValue)
        : (config.hasDefaultCase ? SuperConditionalConfig.defaultZone : null);
    if (matchedZone == null) {
      return config.emptyText.isEmpty
          ? pw.SizedBox.shrink()
          : pw.Text(config.emptyText);
    }
    final ids = config.placements[matchedZone] ?? const <String>[];
    if (ids.isEmpty) return pw.SizedBox.shrink();
    final widgets = <pw.Widget>[];
    for (final slotId in ids) {
      final child = await translateSlot(
        slotId: slotId,
        slotType: config.slotTypeOf(slotId),
        availableSize: availableSize,
        listScope: listScope,
        visited: visited,
      );
      widgets.add(
        _applySlotConstraints(
          child,
          config.slotSizeConstraints[slotId],
          config.slotPreferredSizes[slotId],
          availableSize,
        ),
      );
    }
    return widgets.length == 1
        ? widgets.first
        : pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisSize: pw.MainAxisSize.min,
            children: widgets,
          );
  }

  Future<pw.Widget> _translateListView({
    required String id,
    required SuperListViewConfig config,
    required Size availableSize,
    required JsonListScope? listScope,
    required Set<String> visited,
  }) async {
    final resolved = await _resolveArrayItems(config.binding, listScope);
    if (resolved == null || resolved.items.isEmpty) {
      return pw.Text(
        config.emptyText,
        style: pw.TextStyle(
          fontSize: 10,
          color: _resolveColor(ctx.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final itemWidgets = <pw.Widget>[];
    for (var i = 0; i < resolved.items.length; i++) {
      final itemScope = JsonListScope(
        repositoryId: resolved.repositoryId,
        indices: [...resolved.parentIndices, i],
        arrayTemplate: resolved.arrayTemplate,
        child: const SizedBox.shrink(),
      );
      final itemLayout = await _translateLayout(
        layout: config.template,
        availableSize: Size(
          config.wrap ? config.itemWidth : availableSize.width,
          config.itemExtent,
        ),
        listScope: itemScope,
        visited: visited,
      );
      final rowStyle =
          ctx.appearance.styles[config.itemId ?? '$id:item'];
      final styledRow =
          rowStyle != null && rowStyle != const ContainerStyle()
          ? _wrapWithStyle(itemLayout, rowStyle)
          : itemLayout;
      itemWidgets.add(
        config.axis == Axis.horizontal || config.wrap
            ? pw.SizedBox(
                width: config.wrap ? config.itemWidth : config.itemExtent,
                child: styledRow,
              )
            : styledRow,
      );
    }

    if (config.wrap) {
      return pw.Wrap(
        spacing: config.spacing,
        runSpacing: config.spacing,
        children: itemWidgets,
      );
    }
    if (config.axis == Axis.horizontal) {
      final spaced = <pw.Widget>[];
      for (var i = 0; i < itemWidgets.length; i++) {
        spaced.add(itemWidgets[i]);
        if (config.spacing > 0 && i < itemWidgets.length - 1) {
          spaced.add(pw.SizedBox(width: config.spacing));
        }
      }
      return pw.Row(children: spaced);
    }
    final spaced = <pw.Widget>[];
    for (var i = 0; i < itemWidgets.length; i++) {
      spaced.add(itemWidgets[i]);
      if (config.spacing > 0 && i < itemWidgets.length - 1) {
        spaced.add(pw.SizedBox(height: config.spacing));
      }
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: spaced,
    );
  }

  Future<pw.Widget> _translateTable({
    required SuperTableConfig config,
    required Size availableSize,
    required JsonListScope? listScope,
    required Set<String> visited,
  }) async {
    final resolved = await _resolveArrayItems(config.binding, listScope);
    final items = resolved?.items ?? const <Object?>[];

    final columnWidths = <int, pw.TableColumnWidth>{};
    for (var c = 0; c < config.columns.length; c++) {
      final col = config.columns[c];
      columnWidths[c] = col.isFill
          ? pw.FlexColumnWidth(col.fillPercent)
          : pw.FixedColumnWidth(col.width);
    }

    Future<pw.Widget> buildCell(
      String zone,
      SuperTableColumnConfig col,
      JsonListScope? cellScope, {
      String? fallbackText,
    }) async {
      final ids = config.placements[zone] ?? const <String>[];
      if (ids.isEmpty) {
        if (fallbackText == null || fallbackText.isEmpty) {
          return pw.SizedBox.shrink();
        }
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(
            fallbackText,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _resolveColor(ctx.colorScheme.onSurface),
            ),
          ),
        );
      }
      final cellChildren = <pw.Widget>[];
      for (final slotId in ids) {
        final child = await translateSlot(
          slotId: slotId,
          slotType: config.slotTypeOf(slotId),
          availableSize: Size(col.width, config.rowHeight),
          listScope: cellScope,
          visited: visited,
        );
        cellChildren.add(child);
      }
      final content = cellChildren.length == 1
          ? cellChildren.first
          : pw.Row(children: cellChildren);
      final zoneStyle = config.zoneStyles[zone];
      final padded = pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: content,
      );
      return zoneStyle != null && zoneStyle != const ContainerStyle()
          ? _wrapWithStyle(padded, zoneStyle)
          : padded;
    }

    final rows = <pw.TableRow>[];
    if (config.showHeaderRow) {
      final headerCells = <pw.Widget>[];
      for (final col in config.columns) {
        headerCells.add(
          await buildCell(
            SuperTableConfig.headerZoneFor(col.id),
            col,
            listScope,
            fallbackText: col.title,
          ),
        );
      }
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: _resolveColor(ctx.colorScheme.surfaceContainerHighest),
          ),
          children: headerCells,
        ),
      );
    }

    if (items.isEmpty && !config.showHeaderRow) {
      return pw.Text(config.emptyText);
    }

    for (var r = 0; r < items.length; r++) {
      final rowScope = resolved == null
          ? listScope
          : JsonListScope(
              repositoryId: resolved.repositoryId,
              indices: [...resolved.parentIndices, r],
              arrayTemplate: resolved.arrayTemplate,
              child: const SizedBox.shrink(),
            );
      final rowCells = <pw.Widget>[];
      for (final col in config.columns) {
        rowCells.add(
          await buildCell(
            SuperTableConfig.cellZoneFor(col.id),
            col,
            rowScope,
          ),
        );
      }
      rows.add(pw.TableRow(children: rowCells));
    }

    if (config.showBottomRow) {
      final bottomCells = <pw.Widget>[];
      for (final col in config.columns) {
        bottomCells.add(
          await buildCell(
            SuperTableConfig.bottomZoneFor(col.id),
            col,
            listScope,
          ),
        );
      }
      rows.add(pw.TableRow(children: bottomCells));
    }

    return pw.Table(
      border: pw.TableBorder.all(
        color: _resolveColor(ctx.colorScheme.outlineVariant),
        width: 0.6,
      ),
      columnWidths: columnWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  Future<pw.Widget> _translateTab({
    required SuperTabConfig config,
    required Size availableSize,
    required JsonListScope? listScope,
    required Set<String> visited,
  }) async {
    final tabs = config.placements[SuperTabConfig.tabsZone] ?? const <String>[];
    if (tabs.isEmpty) return pw.SizedBox.shrink();
    final idx = config.initialIndex.clamp(0, tabs.length - 1);
    final zone = config.mode == SuperTabMode.dynamic
        ? SuperTabConfig.dynamicContentZone
        : SuperTabConfig.contentZoneFor(tabs[idx]);
    final contentIds = config.placements[zone] ?? const <String>[];
    if (contentIds.isEmpty) return pw.SizedBox.shrink();
    final children = <pw.Widget>[];
    for (final slotId in contentIds) {
      children.add(
        await translateSlot(
          slotId: slotId,
          slotType: config.slotTypeOf(slotId),
          availableSize: availableSize,
          listScope: listScope,
          visited: visited,
        ),
      );
    }
    return children.length == 1
        ? children.first
        : pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisSize: pw.MainAxisSize.min,
            children: children,
          );
  }

  pw.Widget _wrapWithStyle(pw.Widget child, ContainerStyle rawStyle) {
    final style = rawStyle.resolveThemeColors(ctx.colorScheme);
    final bgColor = style.color != null
        ? _resolveColor(style.color!)
        : (style.fill.type == FillType.solid ? null : null);
    pw.LinearGradient? gradient;
    if (style.fill.type == FillType.linear) {
      final radians = style.fill.angle * math.pi / 180;
      gradient = pw.LinearGradient(
        begin: pw.Alignment(-math.cos(radians), -math.sin(radians)),
        end: pw.Alignment(math.cos(radians), math.sin(radians)),
        colors: [
          _resolveColor(style.fill.start),
          _resolveColor(style.fill.end),
        ],
      );
    }
    final borderColor = _resolveColor(
      style.borderColor ?? ctx.colorScheme.outlineVariant,
    );
    final widths = style.sideWidths;
    pw.BoxBorder? border;
    if (widths.top > 0 ||
        widths.right > 0 ||
        widths.bottom > 0 ||
        widths.left > 0) {
      border = pw.Border(
        top: widths.top > 0
            ? pw.BorderSide(color: borderColor, width: widths.top)
            : pw.BorderSide.none,
        right: widths.right > 0
            ? pw.BorderSide(color: borderColor, width: widths.right)
            : pw.BorderSide.none,
        bottom: widths.bottom > 0
            ? pw.BorderSide(color: borderColor, width: widths.bottom)
            : pw.BorderSide.none,
        left: widths.left > 0
            ? pw.BorderSide(color: borderColor, width: widths.left)
            : pw.BorderSide.none,
      );
    }
    final radii = style.radii;
    final borderRadius = radii != null
        ? pw.BorderRadius.only(
            topLeft: pw.Radius.circular(radii.top),
            topRight: pw.Radius.circular(radii.right),
            bottomRight: pw.Radius.circular(radii.bottom),
            bottomLeft: pw.Radius.circular(radii.left),
          )
        : (style.radius > 0 ? pw.BorderRadius.circular(style.radius) : null);

    pw.Widget result = pw.Container(
      margin: _pwEdgeInsets(style.outerMargin),
      padding: _pwEdgeInsets(style.contentPadding),
      decoration: pw.BoxDecoration(
        color: gradient == null ? bgColor : null,
        gradient: gradient,
        border: border,
        borderRadius: borderRadius,
      ),
      child: child,
    );
    if (style.opacity < 1) {
      result = pw.Opacity(opacity: style.opacity.clamp(0.0, 1.0), child: result);
    }
    return result;
  }

  pw.Widget _applySlotConstraints(
    pw.Widget child,
    SlotSizeConstraints? constraints,
    Size? preferred,
    Size containerSize,
  ) {
    var current = child;
    if (constraints != null) {
      final pad = constraints.paddingInsets ?? EdgeInsets.all(constraints.padding);
      if (pad != EdgeInsets.zero) {
        current = pw.Padding(padding: _pwEdgeInsets(pad), child: current);
      }
      final w = constraints.preferredWidth?.resolve(containerSize.width);
      final h = constraints.preferredHeight?.resolve(containerSize.height);
      if (w != null || h != null) {
        current = pw.SizedBox(width: w, height: h, child: current);
      }
    } else if (preferred != null) {
      current = pw.SizedBox(
        width: preferred.width.isFinite ? preferred.width : null,
        height: preferred.height.isFinite ? preferred.height : null,
        child: current,
      );
    }
    return current;
  }

  Size _resolveChildAvailableSize(
    Size parentSize,
    SlotSizeConstraints? constraints,
    Size? preferred,
  ) {
    final w =
        constraints?.preferredWidth?.resolve(parentSize.width) ??
        preferred?.width ??
        parentSize.width;
    final h =
        constraints?.preferredHeight?.resolve(parentSize.height) ??
        preferred?.height ??
        parentSize.height;
    return Size(
      w.isFinite && w > 0 ? w : parentSize.width,
      h.isFinite && h > 0 ? h : parentSize.height,
    );
  }

  bool _requiresRasterStyle(ContainerStyle style) =>
      style.neon?.enabled == true ||
      (style.backdropBlur ?? 0) > 0 ||
      style.hasImage ||
      style.pattern != SurfacePattern.none ||
      style.transform != null ||
      style.fill.type == FillType.radial ||
      style.fill.type == FillType.sweep;

  String _shortType(String slotType, ComponentConfig? config) {
    final configType = switch (config) {
      SuperLayoutConfig() => 'Layout',
      SuperValueConfig() => 'Value',
      SuperActionConfig() => 'Action',
      SuperIndicatorConfig() => 'Indicator',
      SuperSeparatorConfig() => 'Separator',
      SuperListViewConfig() => 'ListView',
      SuperTableConfig() => 'Table',
      SuperTabConfig() => 'Tab',
      SuperConditionalConfig() => 'Conditional',
      _ => null,
    };
    if (configType != null) return configType;

    final trimmed = slotType.trim();
    if (trimmed.isNotEmpty) {
      if (trimmed.startsWith('registry:')) {
        return Uri.decodeComponent(trimmed.substring('registry:'.length));
      }
      if (trimmed.startsWith('factory:')) {
        return trimmed.substring('factory:'.length);
      }
      if (trimmed.startsWith('component:')) {
        return trimmed.substring('component:'.length);
      }
      if (config is NativeComponentConfig &&
          trimmed != 'Card' &&
          trimmed != 'IterableContent') {
        return 'Card';
      }
      return trimmed;
    }
    return config is NativeComponentConfig ? 'Card' : 'Unknown';
  }

  Future<String?> _readBindingText(
    JsonTextBinding binding,
    JsonListScope? scope,
  ) async {
    final store = ctx.repositoryStore;
    if (store == null) return null;
    try {
      final selected = JsonListScope.resolveSelected(binding, scope, store);
      if (selected.binding == null) return '';
      final attr = await store.readAttribute(selected.binding!);
      return attr.text;
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _readBindingRaw(
    JsonTextBinding binding,
    JsonListScope? scope,
  ) async {
    final store = ctx.repositoryStore;
    if (store == null) return null;
    try {
      final selected = JsonListScope.resolveSelected(binding, scope, store);
      if (selected.binding == null) return null;
      final attr = await store.readAttribute(selected.binding!);
      return attr.value;
    } catch (_) {
      return null;
    }
  }

  Future<String> _resolvePropString(
    JsonTextBinding? binding,
    String fallback,
    JsonListScope? scope,
  ) async {
    if (binding == null) return fallback;
    return (await _readBindingText(binding, scope)) ?? fallback;
  }

  Future<
    ({String repositoryId, List<int> parentIndices, String arrayTemplate, List<Object?> items})?
  >
  _resolveArrayItems(JsonTextBinding? binding, JsonListScope? scope) async {
    final store = ctx.repositoryStore;
    if (binding == null || store == null) return null;
    try {
      final selected = JsonListScope.resolveSelected(binding, scope, store);
      final concrete = selected.binding;
      if (concrete == null || concrete.repositoryId == null) return null;
      final items = await store.readArray(concrete.repositoryId!, concrete.path);
      return (
        repositoryId: concrete.repositoryId!,
        parentIndices: selected.indices,
        arrayTemplate: binding.path,
        items: items,
      );
    } catch (_) {
      return null;
    }
  }

  PdfColor _resolveColor(Color color) {
    final resolved = resolveThemeColor(color, ctx.colorScheme);
    return PdfColor.fromInt(resolved.toARGB32());
  }

  pw.EdgeInsets _pwEdgeInsets(EdgeInsets e) =>
      pw.EdgeInsets.fromLTRB(e.left, e.top, e.right, e.bottom);

  pw.TextAlign _pwTextAlign(TextAlign align) => switch (align) {
    TextAlign.center => pw.TextAlign.center,
    TextAlign.right || TextAlign.end => pw.TextAlign.right,
    TextAlign.justify => pw.TextAlign.justify,
    _ => pw.TextAlign.left,
  };

  pw.MainAxisAlignment _pwMainAxis(MainAxisAlignment align) => switch (align) {
    MainAxisAlignment.center => pw.MainAxisAlignment.center,
    MainAxisAlignment.end => pw.MainAxisAlignment.end,
    MainAxisAlignment.spaceBetween => pw.MainAxisAlignment.spaceBetween,
    MainAxisAlignment.spaceAround => pw.MainAxisAlignment.spaceAround,
    MainAxisAlignment.spaceEvenly => pw.MainAxisAlignment.spaceEvenly,
    _ => pw.MainAxisAlignment.start,
  };

  pw.CrossAxisAlignment _pwCrossAxis(CrossAxisAlignment align) =>
      switch (align) {
        CrossAxisAlignment.center => pw.CrossAxisAlignment.center,
        CrossAxisAlignment.end => pw.CrossAxisAlignment.end,
        CrossAxisAlignment.stretch => pw.CrossAxisAlignment.stretch,
        _ => pw.CrossAxisAlignment.start,
      };
}
