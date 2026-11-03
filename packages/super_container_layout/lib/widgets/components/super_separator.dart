/// Composant séparateur ou espaceur configurable ([SuperSeparator]) du catalogue GenUI.
///
/// Permet d'insérer un espaceur (`spacer`) ou un trait de séparation (`divider`)
/// horizontal ou vertical, avec ou sans libellé (`start`, `center`, `end`),
/// style de trait (`solid`, `dashed`, `dotted`), liaisons JSON ([JsonTextBinding])
/// et surcharges d'états ([SeparatorConfigStates]).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/automatic_state.dart';
import '../../models/json_text_binding.dart';
import '../../models/super_separator_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/states/content_hover_scope.dart';
import '../../services/states/surface_state_binding.dart';
import '../../super_app.dart';
import '../editing/components/super_separator_editor.dart';
import '../editing/history/editor_history.dart';
import '../editing/slots/editor_slot.dart';
import 'super_component.dart';
import 'super_layout/slot_implementation.dart';

Object _parseBoundSeparatorProperty(
  SuperSeparatorProperty property,
  Object? value,
) {
  switch (property) {
    case SuperSeparatorProperty.label:
    case SuperSeparatorProperty.fontFamily:
      if (value is! String ||
          (property == SuperSeparatorProperty.fontFamily &&
              value.trim().isEmpty)) {
        throw FormatException(
          'La valeur liée à ${property.name} doit être un texte valide.',
        );
      }
      return value;
    case SuperSeparatorProperty.lineColor:
    case SuperSeparatorProperty.color:
      if (value is int && value >= 0 && value <= 0xFFFFFFFF) {
        return Color(value);
      }
      if (value is String) {
        final hex = value.trim().replaceFirst(RegExp(r'^#'), '');
        if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
          return Color(0xFF000000 | int.parse(hex, radix: 16));
        }
        if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) {
          return Color(int.parse(hex, radix: 16));
        }
      }
      throw const FormatException(
        'La couleur liée doit être un entier ARGB ou un hexadécimal RGB/ARGB.',
      );
    case SuperSeparatorProperty.thickness:
    case SuperSeparatorProperty.fontSize:
      final number = value is num
          ? value.toDouble()
          : value is String
          ? double.tryParse(value.trim().replaceAll(',', '.'))
          : null;
      if (number == null || !number.isFinite || number <= 0) {
        throw const FormatException(
          'La taille ou épaisseur liée doit être un nombre positif.',
        );
      }
      return number;
    case SuperSeparatorProperty.extent:
    case SuperSeparatorProperty.indent:
    case SuperSeparatorProperty.endIndent:
      final number = value is num
          ? value.toDouble()
          : value is String
          ? double.tryParse(value.trim().replaceAll(',', '.'))
          : null;
      if (number == null || !number.isFinite || number < 0) {
        throw const FormatException(
          'La dimension liée doit être un nombre positif ou nul.',
        );
      }
      return number;
    case SuperSeparatorProperty.fontWeight:
      final weight = switch (value) {
        int weightValue =>
          FontWeight.values
              .where((weight) => weight.value == weightValue)
              .firstOrNull,
        String text => switch (text.trim().toLowerCase()) {
          'normal' => FontWeight.w400,
          'bold' => FontWeight.w700,
          final value when RegExp(r'^(?:w)?[1-9]00$').hasMatch(value) =>
            FontWeight.values
                .where(
                  (weight) =>
                      weight.value == int.parse(value.replaceFirst('w', '')),
                )
                .firstOrNull,
          _ => null,
        },
        _ => null,
      };
      if (weight == null) {
        throw const FormatException(
          'La graisse liée doit être normal, bold ou une valeur 100–900.',
        );
      }
      return weight;
    case SuperSeparatorProperty.italic:
      if (value is bool) return value;
      if (value is String) {
        return switch (value.trim().toLowerCase()) {
          'true' || 'italic' => true,
          'false' || 'normal' => false,
          _ => throw const FormatException(
            'Le style italique lié doit être true/false ou italic/normal.',
          ),
        };
      }
      throw const FormatException(
        'Le style italique lié doit être un booléen ou un texte.',
      );
  }
}

class _SeparatorLinePainter extends CustomPainter {
  const _SeparatorLinePainter({
    required this.axis,
    required this.color,
    required this.thickness,
    required this.lineStyle,
  });

  final Axis axis;
  final Color color;
  final double thickness;
  final SuperSeparatorLineStyle lineStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (thickness <= 0 || color.a == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = lineStyle == SuperSeparatorLineStyle.dotted
          ? StrokeCap.round
          : StrokeCap.butt;

    final isHorizontal = axis == Axis.horizontal;
    final length = isHorizontal ? size.width : size.height;
    if (length <= 0) return;
    final crossCenter = (isHorizontal ? size.height : size.width) / 2;

    Offset pointAt(double mainOffset) => isHorizontal
        ? Offset(mainOffset, crossCenter)
        : Offset(crossCenter, mainOffset);

    if (lineStyle == SuperSeparatorLineStyle.solid) {
      canvas.drawLine(pointAt(0), pointAt(length), paint);
      return;
    }

    final dash = lineStyle == SuperSeparatorLineStyle.dotted
        ? math.max(1.0, thickness)
        : math.max(4.0, thickness * 3);
    final gap = lineStyle == SuperSeparatorLineStyle.dotted
        ? math.max(2.0, thickness * 2)
        : math.max(3.0, thickness * 2);
    var offset = 0.0;
    while (offset < length) {
      final end = math.min(offset + dash, length);
      canvas.drawLine(pointAt(offset), pointAt(end), paint);
      offset += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SeparatorLinePainter oldDelegate) =>
      axis != oldDelegate.axis ||
      color != oldDelegate.color ||
      thickness != oldDelegate.thickness ||
      lineStyle != oldDelegate.lineStyle;
}

class _SeparatorLineSegment extends StatelessWidget {
  const _SeparatorLineSegment({
    required this.axis,
    required this.color,
    required this.thickness,
    required this.lineStyle,
  });

  final Axis axis;
  final Color color;
  final double thickness;
  final SuperSeparatorLineStyle lineStyle;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: axis == Axis.horizontal
        ? Size(double.infinity, thickness)
        : Size(thickness, double.infinity),
    painter: _SeparatorLinePainter(
      axis: axis,
      color: color,
      thickness: thickness,
      lineStyle: lineStyle,
    ),
  );
}

/// Construit le rendu visuel d'un [SuperSeparator] (partagé entre le widget
/// runtime et l'aperçu de l'éditeur).
Widget buildSuperSeparatorVisual({
  required BuildContext context,
  required SuperSeparatorConfig config,
  required TextStyle textStyle,
  Key? separatorKey,
  Key? labelKey,
}) {
  final scheme = Theme.of(context).colorScheme;
  final dividerTheme = DividerTheme.of(context);
  final isHorizontal = config.axis == Axis.horizontal;
  final hasLabel = config.label.trim().isNotEmpty;
  final fg = config.color ?? scheme.onSurfaceVariant;
  final effectiveTextStyle = textStyle.copyWith(color: fg);

  final indentPadding = isHorizontal
      ? EdgeInsets.only(left: config.indent, right: config.endIndent)
      : EdgeInsets.only(top: config.indent, bottom: config.endIndent);

  if (config.kind == SuperSeparatorKind.spacer) {
    final Widget content = hasLabel
        ? Align(
            alignment: switch (config.labelPosition) {
              SuperSeparatorLabelPosition.start =>
                isHorizontal ? Alignment.centerLeft : Alignment.topCenter,
              SuperSeparatorLabelPosition.center => Alignment.center,
              SuperSeparatorLabelPosition.end =>
                isHorizontal ? Alignment.centerRight : Alignment.bottomCenter,
            },
            child: Text(
              config.label,
              key: labelKey,
              style: effectiveTextStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : const SizedBox.shrink();
    return Padding(
      padding: indentPadding,
      child: SizedBox(
        key: separatorKey,
        width: isHorizontal ? null : config.extent,
        height: isHorizontal ? config.extent : null,
        child: content,
      ),
    );
  }

  final effectiveLineColor =
      config.lineColor ?? dividerTheme.color ?? scheme.outlineVariant;
  final crossExtent = math.max(config.extent, config.thickness);

  if (!hasLabel && config.lineStyle == SuperSeparatorLineStyle.solid) {
    return isHorizontal
        ? Divider(
            key: separatorKey,
            height: crossExtent,
            thickness: config.thickness,
            indent: config.indent,
            endIndent: config.endIndent,
            color: effectiveLineColor,
          )
        : VerticalDivider(
            key: separatorKey,
            width: crossExtent,
            thickness: config.thickness,
            indent: config.indent,
            endIndent: config.endIndent,
            color: effectiveLineColor,
          );
  }

  Widget lineSegment() => Expanded(
    child: _SeparatorLineSegment(
      axis: config.axis,
      color: effectiveLineColor,
      thickness: config.thickness,
      lineStyle: config.lineStyle,
    ),
  );

  if (!hasLabel) {
    return Padding(
      key: separatorKey,
      padding: indentPadding,
      child: SizedBox(
        width: isHorizontal ? double.infinity : crossExtent,
        height: isHorizontal ? crossExtent : double.infinity,
        child: Center(
          child: _SeparatorLineSegment(
            axis: config.axis,
            color: effectiveLineColor,
            thickness: config.thickness,
            lineStyle: config.lineStyle,
          ),
        ),
      ),
    );
  }

  final labelWidget = Flexible(
    flex: 0,
    child: Text(
      config.label,
      key: labelKey,
      style: effectiveTextStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
  final gap = SizedBox(
    width: isHorizontal ? config.labelSpacing : 0,
    height: isHorizontal ? 0 : config.labelSpacing,
  );

  final children = switch (config.labelPosition) {
    SuperSeparatorLabelPosition.start => [
      labelWidget,
      if (config.labelSpacing > 0) gap,
      lineSegment(),
    ],
    SuperSeparatorLabelPosition.center => [
      lineSegment(),
      if (config.labelSpacing > 0) gap,
      labelWidget,
      if (config.labelSpacing > 0) gap,
      lineSegment(),
    ],
    SuperSeparatorLabelPosition.end => [
      lineSegment(),
      if (config.labelSpacing > 0) gap,
      labelWidget,
    ],
  };

  return Padding(
    key: separatorKey,
    padding: indentPadding,
    child: ConstrainedBox(
      constraints: isHorizontal
          ? BoxConstraints(minHeight: crossExtent)
          : BoxConstraints(minWidth: crossExtent),
      child: Flex(
        direction: config.axis,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    ),
  );
}

/// Composant séparateur ou espaceur (`divider` / `spacer`, horizontal ou vertical,
/// avec ou sans libellé) supportant les états standards et personnalisés.
class SuperSeparator extends SuperStatefulComponent<SuperSeparatorConfig> {
  const SuperSeparator({
    required this.id,
    this.config = const SuperSeparatorConfig(),
    this.onConfigChanged,
    this.availableFontFamilies = const [],
    super.behaviours,
    super.key,
  });

  @override
  final String id;
  @override
  final SuperSeparatorConfig config;
  final ValueChanged<SuperSeparatorConfig>? onConfigChanged;
  final List<String> availableFontFamilies;

  @override
  State<SuperSeparator> createState() => _SuperSeparatorState();
}

class _SuperSeparatorState extends State<SuperSeparator> {
  final _surface = GlobalKey<EditorSlotState>();
  late final ValueNotifier<SuperSeparatorConfig> _local;
  Map<SuperSeparatorProperty, Object> _boundPropertyValues = const {};
  Map<SuperSeparatorProperty, String> _propertyBindingErrors = const {};
  List<JsonArrayBinding> _propertySelections = const [];
  Map<SuperSeparatorProperty, JsonTextBinding> _activePropertyBindings =
      const {};
  Map<SuperSeparatorProperty, JsonTextBinding>? _requestedPropertyBindings;
  JsonRepositoryStore? _requestedPropertyStore;
  String? _requestedPropertyRepositoryId;
  String? _requestedPropertyNodePath;
  List<int> _requestedPropertyIndices = const [];
  bool _requestedPropertyPlaceholder = false;
  bool _refreshPropertyBindings = true;
  int _propertyBindingGeneration = 0;

  SuperSeparatorConfig? _editorConfig;
  SurfaceStateBinding? _stateReader;
  bool _hovered = false;
  String? _stateError;
  Set<AutomaticState> _automaticActive = {};

  void _stateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  SuperSeparatorConfig _resolveStates(
    SuperSeparatorConfig saved,
    JsonListScope? scope,
    JsonRepositoryStore? store,
    bool contentHovered,
  ) {
    final binding = saved.states?.binding;
    if (binding == null) {
      _stateReader?.removeListener(_stateChanged);
      _stateReader?.dispose();
      _stateReader = null;
    } else if (_stateReader == null) {
      _stateReader = SurfaceStateBinding(
        store: store,
        binding: binding,
        scope: scope,
        placeholder: scope?.placeholder ?? false,
      )..addListener(_stateChanged);
    } else {
      _stateReader!.reconfigure(
        store: store,
        binding: binding,
        scope: scope,
        placeholder: scope?.placeholder ?? false,
      );
    }
    _stateError = _stateReader?.error;
    try {
      _automaticActive = {if (contentHovered) AutomaticState.contentHover};
      final config =
          saved.states?.resolve(
            saved,
            name: _stateReader?.stateName,
            isHovered: _hovered,
            isSelected: scope?.selected ?? false,
            activeStates: _automaticActive,
          ) ??
          saved;
      config.validate();
      return config;
    } on FormatException catch (error) {
      _stateError = error.message;
    } on ArgumentError {
      _stateError = 'Combinaison d’états du séparateur invalide.';
    }
    return saved.copyWith(clearStates: true);
  }

  @override
  void initState() {
    super.initState();
    widget.config.copyWith(clearStates: true).validate();
    _local = ValueNotifier(widget.config);
  }

  @override
  void didUpdateWidget(SuperSeparator oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.config.copyWith(clearStates: true).validate();
    if (oldWidget.config != widget.config) _local.value = widget.config;
  }

  void _listenPropertySelections(List<JsonArrayBinding> selections) {
    if (listEquals(_propertySelections, selections)) return;
    for (final selection in _propertySelections) {
      selection.removeListener(_propertySelectionChanged);
    }
    _propertySelections = selections;
    for (final selection in selections) {
      selection.addListener(_propertySelectionChanged);
    }
  }

  void _propertySelectionChanged() {
    _refreshPropertyBindings = true;
    if (mounted) setState(() {});
  }

  void _propertyStoreChanged() {
    final store = _requestedPropertyStore;
    if (!mounted || store == null || _activePropertyBindings.isEmpty) return;
    final generation = ++_propertyBindingGeneration;
    unawaited(
      _loadPropertyBindings(_activePropertyBindings, store, generation),
    );
  }

  void _observePropertyBindings(
    SuperSeparatorConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final bindings = config.propertyBindings;
    final sameBindingContext =
        mapEquals(_requestedPropertyBindings, bindings) &&
        identical(_requestedPropertyStore, store) &&
        _requestedPropertyRepositoryId == scope?.repositoryId &&
        _requestedPropertyNodePath == scope?.nodePath &&
        listEquals(_requestedPropertyIndices, scope?.indices ?? const []) &&
        _requestedPropertyPlaceholder == (scope?.placeholder ?? false);
    if (!_refreshPropertyBindings && sameBindingContext) {
      return;
    }
    _refreshPropertyBindings = false;
    _requestedPropertyBindings = Map.of(bindings);
    if (!identical(_requestedPropertyStore, store)) {
      _requestedPropertyStore?.unregisterBindings(this);
      _requestedPropertyStore?.removeListener(_propertyStoreChanged);
      store?.addListener(_propertyStoreChanged);
      _requestedPropertyStore = store;
    }
    _requestedPropertyRepositoryId = scope?.repositoryId;
    _requestedPropertyNodePath = scope?.nodePath;
    _requestedPropertyIndices = List.of(scope?.indices ?? const []);
    _requestedPropertyPlaceholder = scope?.placeholder ?? false;
    final generation = ++_propertyBindingGeneration;
    _propertyBindingErrors = const {};
    if (bindings.isEmpty || (scope?.placeholder ?? false)) {
      store?.unregisterBindings(this);
      _boundPropertyValues = const {};
      _activePropertyBindings = const {};
      _listenPropertySelections(const []);
      return;
    }

    store?.registerBindings(this, [
      for (final b in bindings.values) b.repositoryId ?? scope?.repositoryId,
    ]);

    final selections = <JsonArrayBinding>[];
    final resolved = <SuperSeparatorProperty, JsonTextBinding>{};
    final errors = <SuperSeparatorProperty, String>{};
    for (final entry in bindings.entries) {
      try {
        final result = JsonListScope.resolveSelected(entry.value, scope, store);
        selections.addAll(result.arrays);
        if (result.binding != null) resolved[entry.key] = result.binding!;
      } on FormatException catch (error) {
        errors[entry.key] = error.message;
      }
    }
    _listenPropertySelections(selections.toSet().toList());
    _activePropertyBindings = Map.of(resolved);
    _propertyBindingErrors = errors;
    if (resolved.isEmpty) {
      _boundPropertyValues = const {};
      return;
    }
    if (store == null) {
      _boundPropertyValues = const {};
      _propertyBindingErrors = {
        ..._propertyBindingErrors,
        for (final property in resolved.keys)
          property: 'Service de repositories indisponible.',
      };
      return;
    }
    final syncedValues = <SuperSeparatorProperty, Object>{
      for (final entry in _boundPropertyValues.entries)
        if (resolved.containsKey(entry.key)) entry.key: entry.value,
    };
    for (final entry in resolved.entries) {
      final cached = store.peekAttribute(entry.value);
      if (cached == null) continue;
      try {
        final value = _parseBoundSeparatorProperty(entry.key, cached.value);
        if (entry.key == SuperSeparatorProperty.fontFamily &&
            widget.availableFontFamilies.isNotEmpty &&
            !widget.availableFontFamilies.contains(value)) {
          continue;
        }
        syncedValues[entry.key] = value;
      } on FormatException {
        // Error will be reported by _loadPropertyBindings.
      }
    }
    _boundPropertyValues = syncedValues;
    unawaited(_loadPropertyBindings(resolved, store, generation));
  }

  Future<void> _loadPropertyBindings(
    Map<SuperSeparatorProperty, JsonTextBinding> bindings,
    JsonRepositoryStore store,
    int generation,
  ) async {
    final values = <SuperSeparatorProperty, Object>{};
    final errors = Map<SuperSeparatorProperty, String>.of(
      _propertyBindingErrors,
    );
    final entries = bindings.entries.toList();
    final outcomes = await Future.wait([
      for (final entry in entries)
        () async {
          try {
            final result = await store.readAttribute(entry.value);
            final value = _parseBoundSeparatorProperty(entry.key, result.value);
            if (entry.key == SuperSeparatorProperty.fontFamily &&
                widget.availableFontFamilies.isNotEmpty &&
                !widget.availableFontFamilies.contains(value)) {
              throw FormatException(
                'La police liée « $value » n’est pas disponible.',
              );
            }
            return (property: entry.key, value: value, error: null);
          } on FormatException catch (error) {
            return (property: entry.key, value: null, error: error.message);
          } on FileSystemException {
            return (
              property: entry.key,
              value: null,
              error: 'Impossible de lire le repository lié.',
            );
          }
        }(),
    ]);
    if (!mounted || generation != _propertyBindingGeneration) return;
    for (final outcome in outcomes) {
      if (outcome.error != null) {
        errors[outcome.property] = outcome.error!;
      } else if (outcome.value != null) {
        values[outcome.property] = outcome.value!;
        errors.remove(outcome.property);
      }
    }
    if (mapEquals(_boundPropertyValues, values) &&
        mapEquals(_propertyBindingErrors, errors)) {
      return;
    }
    setState(() {
      _boundPropertyValues = values;
      _propertyBindingErrors = errors;
    });
  }

  SuperSeparatorConfig _withBoundProperties(SuperSeparatorConfig config) {
    var result = config;
    for (final entry in _boundPropertyValues.entries) {
      result = switch (entry.key) {
        SuperSeparatorProperty.label => result.copyWith(
          label: entry.value as String,
        ),
        SuperSeparatorProperty.extent => result.copyWith(
          extent: entry.value as double,
        ),
        SuperSeparatorProperty.thickness => result.copyWith(
          thickness: entry.value as double,
        ),
        SuperSeparatorProperty.indent => result.copyWith(
          indent: entry.value as double,
        ),
        SuperSeparatorProperty.endIndent => result.copyWith(
          endIndent: entry.value as double,
        ),
        SuperSeparatorProperty.lineColor => result.copyWith(
          lineColor: entry.value as Color,
        ),
        SuperSeparatorProperty.color => result.copyWith(
          color: entry.value as Color,
        ),
        SuperSeparatorProperty.fontFamily => result.copyWith(
          fontFamily: entry.value as String,
        ),
        SuperSeparatorProperty.fontSize => result.copyWith(
          fontSize: entry.value as double,
        ),
        SuperSeparatorProperty.fontWeight => result.copyWith(
          fontWeight: entry.value as FontWeight,
        ),
        SuperSeparatorProperty.italic => result.copyWith(
          italic: entry.value as bool,
        ),
      };
    }
    return result;
  }

  @override
  void dispose() {
    _stateReader?.removeListener(_stateChanged);
    _stateReader?.dispose();
    _propertyBindingGeneration++;
    _listenPropertySelections(const []);
    _requestedPropertyStore?.unregisterBindings(this);
    _requestedPropertyStore?.removeListener(_propertyStoreChanged);
    _requestedPropertyStore = null;
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final repositories = JsonRepositoryScope.maybeOf(context);
    final listScope = JsonListScope.maybeOf(context);
    final configuration =
        registry?.separatorController(widget.id, fallback: widget.config) ??
        _local;

    return MouseRegion(
      opaque: false,
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: ValueListenableBuilder<SuperSeparatorConfig>(
        valueListenable: configuration,
        builder: (context, savedConfig, _) {
          final effective = _resolveStates(
            savedConfig,
            listScope,
            repositories,
            ContentHoverScope.maybeOf(context)?.hovered == true,
          );
          _observePropertyBindings(effective, listScope, repositories);
          final config = _editorConfig ?? _withBoundProperties(effective);
          final missingFont =
              config.fontFamily != null &&
              !widget.availableFontFamilies.contains(config.fontFamily);
          final base = DefaultTextStyle.of(context).style;
          final textStyle = base.copyWith(
            fontFamily: missingFont ? null : config.fontFamily,
            fontSize: config.fontSize,
            fontWeight: config.fontWeight,
            fontStyle: config.italic == null
                ? null
                : config.italic!
                ? FontStyle.italic
                : FontStyle.normal,
            color: config.color,
            letterSpacing: config.letterSpacing,
          );

          final fit = SlotContentFitScope.maybeOf(context);
          final fitWidth = fit?.fitWidth ?? false;
          final fitHeight = fit?.fitHeight ?? false;

          Future<void> editSeparator() async {
            final initial = configuration.value;
            final history = EditorHistoryScope.controllerOf(context);
            history?.beginTransaction();
            SuperSeparatorConfig? result;
            try {
              result = await showSuperSeparatorEditor(
                context: context,
                config: initial,
                availableFontFamilies: widget.availableFontFamilies,
                activeState: _stateReader?.stateName,
                stateError: _stateError,
                isHovered: _hovered,
                isSelected: listScope?.selected ?? false,
                allowContentHover: ContentHoverScope.maybeOf(context) != null,
                activeAutomatic: _automaticActive,
                onPreviewChanged: (draft) {
                  if (!mounted) return;
                  setState(() => _editorConfig = draft);
                },
              );
              if (result != null &&
                  context.mounted &&
                  result != configuration.value) {
                configuration.value = result;
                widget.onConfigChanged?.call(result);
              }
            } finally {
              if (mounted) {
                setState(() => _editorConfig = null);
              }
              if (result != null) {
                history?.commitTransaction();
              } else {
                history?.cancelTransaction();
              }
            }
          }

          final isHorizontal = config.axis == Axis.horizontal;
          final visual = buildSuperSeparatorVisual(
            context: context,
            config: config,
            textStyle: textStyle,
            separatorKey: ValueKey('super-separator-visual-${widget.id}'),
            labelKey: ValueKey('super-separator-label-${widget.id}'),
          );

          return EditorSlot(
            key: _surface,
            id: widget.id,
            behaviors: widget.behaviours,
            label: 'Separator',
            menuType: 'Separator',
            eventComponentType: 'separator',
            menuTooltip: () => formatSuperSeparatorTooltip(
              title: _surface.currentState?.titleLabel ?? 'Separator',
              config: config,
            ),
            onEdit: editSeparator,
            child: Column(
              mainAxisSize: isHorizontal ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: isHorizontal
                  ? (fitWidth
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.stretch)
                  : CrossAxisAlignment.center,
              children: [
                Flexible(
                  fit: isHorizontal ? FlexFit.loose : FlexFit.tight,
                  child: Center(
                    widthFactor: !isHorizontal && fitWidth ? 1 : null,
                    heightFactor: isHorizontal && fitHeight ? 1 : null,
                    child: visual,
                  ),
                ),
                if (_stateError != null)
                  Text(
                    _stateError!,
                    key: ValueKey('super-separator-state-error-${widget.id}'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                for (final entry in _propertyBindingErrors.entries)
                  Text(
                    'Liaison ${entry.key.name} : ${entry.value}',
                    key: ValueKey(
                      'super-separator-property-binding-error-'
                      '${entry.key.name}-${widget.id}',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
