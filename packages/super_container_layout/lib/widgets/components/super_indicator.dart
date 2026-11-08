/// Composant indicateur / icône d'état configurable ([SuperIndicator]) du catalogue GenUI.
///
/// Affiche une icône Material ([MaterialIconCatalog]) avec libellé et badge/surface
/// optionnels, pilotée par les surcharges d'états standards et personnalisés
/// ([IndicatorConfigStates]), les liaisons JSON ([JsonTextBinding]) et les
/// comportements ([ComponentBehavior]).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/automatic_state.dart';
import '../../models/json_text_binding.dart';
import '../../models/super_indicator_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/states/content_hover_scope.dart';
import '../../services/states/surface_state_binding.dart';
import '../../super_app.dart';
import '../../theme/container_fill.dart';
import '../../theme/style_extras.dart';
import '../editing/components/super_indicator_editor.dart';
import '../editing/history/editor_history.dart';
import '../editing/slots/editor_slot.dart';
import '../surfaces/styled_surface.dart';
import 'super_component.dart';
import 'super_layout/slot_implementation.dart';

Object _parseBoundIndicatorProperty(
  SuperIndicatorProperty property,
  Object? value,
) {
  switch (property) {
    case SuperIndicatorProperty.label:
    case SuperIndicatorProperty.tooltip:
    case SuperIndicatorProperty.fontFamily:
      if (value is! String ||
          (property == SuperIndicatorProperty.fontFamily &&
              value.trim().isEmpty)) {
        throw FormatException(
          'La valeur liée à ${property.name} doit être un texte valide.',
        );
      }
      return value;
    case SuperIndicatorProperty.icon:
      if (value == null || (value is String && value.trim().isEmpty)) {
        return '';
      }
      if (value is! String || !SuperIndicatorIcons.isKnown(value)) {
        throw const FormatException(
          'L’icône liée doit être un identifiant d’icône valide.',
        );
      }
      return value.trim();
    case SuperIndicatorProperty.enabled:
      if (value is bool) return value;
      if (value is String) {
        return switch (value.trim().toLowerCase()) {
          'true' || '1' || 'yes' || 'oui' => true,
          'false' || '0' || 'no' || 'non' => false,
          _ => throw const FormatException(
            'L’état activé lié doit être un booléen (true/false).',
          ),
        };
      }
      throw const FormatException(
        'L’état activé lié doit être un booléen ou un texte.',
      );
    case SuperIndicatorProperty.color:
    case SuperIndicatorProperty.iconColor:
    case SuperIndicatorProperty.backgroundColor:
    case SuperIndicatorProperty.borderColor:
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
    case SuperIndicatorProperty.fontSize:
    case SuperIndicatorProperty.iconSize:
      final number = value is num
          ? value.toDouble()
          : value is String
          ? double.tryParse(value.trim().replaceAll(',', '.'))
          : null;
      if (number == null || !number.isFinite || number <= 0) {
        throw const FormatException(
          'La taille liée doit être un nombre positif.',
        );
      }
      return number;
    case SuperIndicatorProperty.radius:
    case SuperIndicatorProperty.borderWidth:
    case SuperIndicatorProperty.elevation:
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
    case SuperIndicatorProperty.fontWeight:
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
    case SuperIndicatorProperty.italic:
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
    case SuperIndicatorProperty.textAlign:
      if (value is String) {
        final align = TextAlign.values
            .where((candidate) => candidate.name == value.trim().toLowerCase())
            .firstOrNull;
        if (align != null) return align;
      }
      throw const FormatException(
        'L’alignement lié doit être start, end, left, right, center ou justify.',
      );
  }
}

/// Construit le rendu visuel d'un [SuperIndicator] (partagé entre le widget
/// runtime et l'aperçu de l'éditeur).
Widget buildSuperIndicatorVisual({
  required BuildContext context,
  required SuperIndicatorConfig config,
  required TextStyle textStyle,
  Key? surfaceKey,
  Key? labelKey,
  Key? iconKey,
}) {
  final scheme = Theme.of(context).colorScheme;
  final align = switch (config.textAlign) {
    TextAlign.start || TextAlign.left => MainAxisAlignment.start,
    TextAlign.end || TextAlign.right => MainAxisAlignment.end,
    _ => MainAxisAlignment.center,
  };
  final hasIcon = config.icon.trim().isNotEmpty;
  final hasLabel = config.label.trim().isNotEmpty;
  final iconData = hasIcon ? SuperIndicatorIcons.resolve(config.icon) : null;
  final effectiveIconColor = config.iconColor ?? config.color ?? scheme.primary;
  final effectiveIconSize = config.iconSize ?? 24.0;

  final iconWidget = hasIcon
      ? Icon(
          iconData,
          key: iconKey,
          size: effectiveIconSize,
          color: effectiveIconColor,
        )
      : SizedBox(
          key: iconKey,
          width: effectiveIconSize,
          height: effectiveIconSize,
        );

  final fg = config.color ?? scheme.onSurface;
  final textWidget = hasLabel
      ? Text(
          config.label,
          key: labelKey,
          style: textStyle.copyWith(color: fg),
          textAlign: config.textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )
      : null;

  final Widget innerContent = !hasLabel
      ? iconWidget
      : Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: align,
          children: !hasIcon
              ? [Flexible(child: textWidget!)]
              : config.iconPosition == SuperIndicatorIconPosition.leading
              ? [
                  iconWidget,
                  SizedBox(width: config.iconSpacing),
                  Flexible(child: textWidget!),
                ]
              : [
                  Flexible(child: textWidget!),
                  SizedBox(width: config.iconSpacing),
                  iconWidget,
                ],
        );

  final hasCustomSurface =
      config.backgroundColor != null ||
      config.borderColor != null ||
      config.radius != null ||
      config.borderWidth != null ||
      config.elevation != null ||
      config.style.color != null ||
      config.style.borderColor != null ||
      config.style.borderWidth > 0 ||
      config.style.borderWidths != null ||
      config.style.elevation > 0 ||
      config.style.fill.type != FillType.solid ||
      config.style.hasImage ||
      config.style.neon != null ||
      config.style.shadow != null ||
      config.style.hasInnerShadow ||
      config.style.effectiveBackdropBlur > 0 ||
      config.style.pattern != SurfacePattern.none ||
      config.style.hoverEffect ||
      (config.style.transform != null && !config.style.transform!.isIdentity);

  final pad =
      config.horizontalPadding != null || config.verticalPadding != null
      ? EdgeInsets.symmetric(
          horizontal: config.horizontalPadding ?? (hasLabel ? 10 : 6),
          vertical: config.verticalPadding ?? 6,
        )
      : config.style.padding > 0 || config.style.paddingInsets != null
      ? config.style.contentPadding
      : hasCustomSurface
      ? EdgeInsets.symmetric(horizontal: hasLabel ? 10 : 6, vertical: 6)
      : EdgeInsets.zero;

  Widget indicator;
  if (hasCustomSurface) {
    final surfaceStyle = config.style.copyWith(
      color: config.backgroundColor ?? config.style.color,
      borderColor: config.borderColor ?? config.style.borderColor,
      radius: config.radius ?? config.style.radius,
      borderWidth: config.borderWidth ?? config.style.borderWidth,
      elevation: config.elevation ?? config.style.elevation,
    );
    indicator = Padding(
      padding: surfaceStyle.outerMargin,
      child: StyledSurface(
        key: surfaceKey,
        style: surfaceStyle,
        fallbackColor:
            config.backgroundColor ??
            surfaceStyle.color ??
            Colors.transparent,
        borderColor: config.borderColor ?? scheme.outline,
        child: Padding(
          padding: pad,
          child: IconTheme.merge(
            data: IconThemeData(
              color: effectiveIconColor,
              size: effectiveIconSize,
            ),
            child: DefaultTextStyle.merge(
              style: textStyle.copyWith(color: fg),
              child: innerContent,
            ),
          ),
        ),
      ),
    );
  } else {
    indicator = Padding(
      key: surfaceKey,
      padding: config.style.outerMargin + pad,
      child: IconTheme.merge(
        data: IconThemeData(color: effectiveIconColor, size: effectiveIconSize),
        child: DefaultTextStyle.merge(
          style: textStyle.copyWith(color: fg),
          child: innerContent,
        ),
      ),
    );
  }

  if (!config.enabled) {
    indicator = Opacity(opacity: 0.45, child: indicator);
  }
  if (config.tooltip.trim().isNotEmpty) {
    indicator = Tooltip(message: config.tooltip, child: indicator);
  }
  return indicator;
}

/// Composant indicateur affichant une icône (et un libellé / badge optionnel)
/// dont l'apparence évolue selon des états standards (`hover`, `selected`,
/// `contentHover`, `disabled`) et des états métier personnalisés (`named`).
class SuperIndicator extends SuperStatefulComponent<SuperIndicatorConfig> {
  const SuperIndicator({
    required this.id,
    this.config = const SuperIndicatorConfig(),
    this.onConfigChanged,
    this.availableFontFamilies = const [],
    super.behaviours,
    super.key,
  });

  @override
  final String id;
  @override
  final SuperIndicatorConfig config;
  final ValueChanged<SuperIndicatorConfig>? onConfigChanged;
  final List<String> availableFontFamilies;

  @override
  State<SuperIndicator> createState() => _SuperIndicatorState();
}

class _SuperIndicatorState extends State<SuperIndicator> {
  final _surface = GlobalKey<EditorSlotState>();
  late final ValueNotifier<SuperIndicatorConfig> _local;
  Map<SuperIndicatorProperty, Object> _boundPropertyValues = const {};
  Map<SuperIndicatorProperty, String> _propertyBindingErrors = const {};
  List<JsonArrayBinding> _propertySelections = const [];
  Map<SuperIndicatorProperty, JsonTextBinding> _activePropertyBindings =
      const {};
  Map<SuperIndicatorProperty, JsonTextBinding>? _requestedPropertyBindings;
  JsonRepositoryStore? _requestedPropertyStore;
  String? _requestedPropertyRepositoryId;
  String? _requestedPropertyNodePath;
  List<int> _requestedPropertyIndices = const [];
  bool _requestedPropertyPlaceholder = false;
  bool _refreshPropertyBindings = true;
  int _propertyBindingGeneration = 0;

  SuperIndicatorConfig? _editorConfig;
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

  SuperIndicatorConfig _resolveStates(
    SuperIndicatorConfig saved,
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
      final source =
          saved.states?.resolve(saved, name: _stateReader?.stateName) ??
          saved.copyWith(clearStates: true);
      _automaticActive = {
        if (contentHovered) AutomaticState.contentHover,
        if (!source.enabled) AutomaticState.disabled,
      };
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
      _stateError = 'Combinaison d’états de l’indicateur invalide.';
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
  void didUpdateWidget(SuperIndicator oldWidget) {
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
    SuperIndicatorConfig config,
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
    final resolved = <SuperIndicatorProperty, JsonTextBinding>{};
    final errors = <SuperIndicatorProperty, String>{};
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
    final syncedValues = <SuperIndicatorProperty, Object>{
      for (final entry in _boundPropertyValues.entries)
        if (resolved.containsKey(entry.key)) entry.key: entry.value,
    };
    for (final entry in resolved.entries) {
      final cached = store.peekAttribute(entry.value);
      if (cached == null) continue;
      try {
        final value = _parseBoundIndicatorProperty(entry.key, cached.value);
        if (entry.key == SuperIndicatorProperty.fontFamily &&
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
    Map<SuperIndicatorProperty, JsonTextBinding> bindings,
    JsonRepositoryStore store,
    int generation,
  ) async {
    final values = <SuperIndicatorProperty, Object>{};
    final errors = Map<SuperIndicatorProperty, String>.of(
      _propertyBindingErrors,
    );
    final entries = bindings.entries.toList();
    final outcomes = await Future.wait([
      for (final entry in entries)
        () async {
          try {
            final result = await store.readAttribute(entry.value);
            final value = _parseBoundIndicatorProperty(entry.key, result.value);
            if (entry.key == SuperIndicatorProperty.fontFamily &&
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

  SuperIndicatorConfig _withBoundProperties(SuperIndicatorConfig config) {
    var result = config;
    for (final entry in _boundPropertyValues.entries) {
      result = switch (entry.key) {
        SuperIndicatorProperty.icon => result.copyWith(
          icon: entry.value as String,
        ),
        SuperIndicatorProperty.label => result.copyWith(
          label: entry.value as String,
        ),
        SuperIndicatorProperty.tooltip => result.copyWith(
          tooltip: entry.value as String,
        ),
        SuperIndicatorProperty.enabled => result.copyWith(
          enabled: entry.value as bool,
        ),
        SuperIndicatorProperty.fontFamily => result.copyWith(
          fontFamily: entry.value as String,
        ),
        SuperIndicatorProperty.color => result.copyWith(
          color: entry.value as Color,
        ),
        SuperIndicatorProperty.iconColor => result.copyWith(
          iconColor: entry.value as Color,
        ),
        SuperIndicatorProperty.backgroundColor => result.copyWith(
          backgroundColor: entry.value as Color,
        ),
        SuperIndicatorProperty.borderColor => result.copyWith(
          borderColor: entry.value as Color,
        ),
        SuperIndicatorProperty.fontSize => result.copyWith(
          fontSize: entry.value as double,
        ),
        SuperIndicatorProperty.iconSize => result.copyWith(
          iconSize: entry.value as double,
        ),
        SuperIndicatorProperty.fontWeight => result.copyWith(
          fontWeight: entry.value as FontWeight,
        ),
        SuperIndicatorProperty.italic => result.copyWith(
          italic: entry.value as bool,
        ),
        SuperIndicatorProperty.textAlign => result.copyWith(
          textAlign: entry.value as TextAlign,
        ),
        SuperIndicatorProperty.radius => result.copyWith(
          radius: entry.value as double,
        ),
        SuperIndicatorProperty.borderWidth => result.copyWith(
          borderWidth: entry.value as double,
        ),
        SuperIndicatorProperty.elevation => result.copyWith(
          elevation: entry.value as double,
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
        registry?.indicatorController(widget.id, fallback: widget.config) ??
        _local;

    return MouseRegion(
      opaque: false,
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: ValueListenableBuilder<SuperIndicatorConfig>(
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

          Future<void> editIndicator() async {
            final initial = configuration.value;
            final history = EditorHistoryScope.controllerOf(context);
            history?.beginTransaction();
            SuperIndicatorConfig? result;
            try {
              result = await showSuperIndicatorEditor(
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

          final align = switch (config.textAlign) {
            TextAlign.start || TextAlign.left => Alignment.centerLeft,
            TextAlign.end || TextAlign.right => Alignment.centerRight,
            _ => Alignment.center,
          };

          return EditorSlot(
            key: _surface,
            id: widget.id,
            exportConfig: () => configuration.value,
            behaviors: widget.behaviours,
            label: 'Indicator',
            menuType: 'Indicator',
            eventComponentType: 'indicator',
            menuTooltip: () => formatSuperIndicatorTooltip(
              title: _surface.currentState?.titleLabel ?? 'Indicator',
              config: config,
            ),
            onEdit: editIndicator,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: fitWidth
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: Align(
                    alignment: align,
                    widthFactor: fitWidth ? 1 : null,
                    heightFactor: fitHeight ? 1 : null,
                    child: buildSuperIndicatorVisual(
                      context: context,
                      config: config,
                      textStyle: textStyle,
                      surfaceKey: ValueKey(
                        'super-indicator-surface-${widget.id}',
                      ),
                      labelKey: ValueKey('super-indicator-label-${widget.id}'),
                      iconKey: ValueKey('super-indicator-icon-${widget.id}'),
                    ),
                  ),
                ),
                if (_stateError != null)
                  Text(
                    _stateError!,
                    key: ValueKey('super-indicator-state-error-${widget.id}'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                for (final entry in _propertyBindingErrors.entries)
                  Text(
                    'Liaison ${entry.key.name} : ${entry.value}',
                    key: ValueKey(
                      'super-indicator-property-binding-error-'
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
