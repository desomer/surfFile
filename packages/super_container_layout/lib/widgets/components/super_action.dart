import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/automatic_state.dart';
import '../../models/component_behavior.dart';
import '../../models/json_syntax.dart';
import '../../models/json_text_binding.dart';
import '../../models/super_action_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/states/content_hover_scope.dart';
import '../../services/states/surface_state_binding.dart';
import '../../super_app.dart';
import '../../theme/appearance.dart';
import '../../theme/container_fill.dart';
import '../../theme/style_extras.dart';
import '../editing/components/super_action_editor.dart';
import '../editing/dialogs/super_value_json_extract_dialog.dart';
import '../editing/history/editor_history.dart';
import '../editing/slots/editor_slot.dart';
import 'super_layout/slot_implementation.dart';
import '../surfaces/styled_surface.dart';

Object _parseBoundActionProperty(SuperActionProperty property, Object? value) {
  switch (property) {
    case SuperActionProperty.label:
    case SuperActionProperty.tooltip:
    case SuperActionProperty.fontFamily:
      if (value is! String ||
          (property == SuperActionProperty.fontFamily &&
              value.trim().isEmpty)) {
        throw FormatException(
          'La valeur liée à ${property.name} doit être un texte valide.',
        );
      }
      return value;
    case SuperActionProperty.icon:
      if (value == null || (value is String && value.trim().isEmpty)) {
        return '';
      }
      if (value is! String || !SuperActionIcons.isKnown(value)) {
        throw const FormatException(
          'L’icône liée doit être un identifiant d’icône valide.',
        );
      }
      return value.trim();
    case SuperActionProperty.enabled:
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
    case SuperActionProperty.color:
    case SuperActionProperty.iconColor:
    case SuperActionProperty.backgroundColor:
    case SuperActionProperty.borderColor:
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
    case SuperActionProperty.fontSize:
    case SuperActionProperty.iconSize:
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
    case SuperActionProperty.radius:
    case SuperActionProperty.borderWidth:
    case SuperActionProperty.elevation:
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
    case SuperActionProperty.fontWeight:
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
    case SuperActionProperty.italic:
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
    case SuperActionProperty.textAlign:
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

/// Construit le rendu visuel d'un [SuperAction] (partagé entre le widget
/// runtime et l'aperçu de l'éditeur).
Widget buildSuperActionVisual({
  required BuildContext context,
  required SuperActionConfig config,
  required TextStyle textStyle,
  required VoidCallback? onPressed,
  FocusNode? focusNode,
  Key? buttonKey,
  Key? labelKey,
  Key? iconKey,
}) {
  final scheme = Theme.of(context).colorScheme;
  final effectiveOnPressed = config.enabled ? (onPressed ?? () {}) : null;
  final align = switch (config.textAlign) {
    TextAlign.start || TextAlign.left => MainAxisAlignment.start,
    TextAlign.end || TextAlign.right => MainAxisAlignment.end,
    _ => MainAxisAlignment.center,
  };
  final hasIcon = config.kind.hasIcon && config.icon.trim().isNotEmpty;
  final iconData = hasIcon ? SuperActionIcons.resolve(config.icon) : null;
  final effectiveIconColor = config.iconColor ?? config.color;
  final iconWidget = hasIcon
      ? Icon(
          iconData,
          key: iconKey,
          size: config.iconSize,
          color: effectiveIconColor,
        )
      : SizedBox(
          key: iconKey,
          width: config.iconSize ?? 20,
          height: config.iconSize ?? 20,
        );
  final textWidget = Text(
    config.label,
    key: labelKey,
    style: textStyle,
    textAlign: config.textAlign,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  final Widget innerContent = switch (config.kind) {
    SuperActionKind.icon => iconWidget,
    SuperActionKind.text => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: align,
      children: [Flexible(child: textWidget)],
    ),
    SuperActionKind.textAndIcon => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: align,
      children: !hasIcon
          ? [Flexible(child: textWidget)]
          : config.iconPosition == SuperActionIconPosition.leading
          ? [
              iconWidget,
              SizedBox(width: config.iconSpacing),
              Flexible(child: textWidget),
            ]
          : [
              Flexible(child: textWidget),
              SizedBox(width: config.iconSpacing),
              iconWidget,
            ],
    ),
  };

  final hasCustomSurface =
      config.variant == SuperActionVariant.surface ||
      config.style.fill.type != FillType.solid ||
      config.style.hasImage ||
      config.style.neon != null ||
      config.style.shadow != null ||
      config.style.hasInnerShadow ||
      config.style.effectiveBackdropBlur > 0 ||
      config.style.pattern != SurfacePattern.none ||
      config.style.hoverEffect ||
      (config.style.transform != null && !config.style.transform!.isIdentity);

  Widget button;
  if (hasCustomSurface) {
    final surfaceStyle = config.style.copyWith(
      color: config.backgroundColor ?? config.style.color,
      borderColor: config.borderColor ?? config.style.borderColor,
      radius: config.radius ?? config.style.radius,
      borderWidth: config.borderWidth ?? config.style.borderWidth,
      elevation: config.elevation ?? config.style.elevation,
    );
    final defaultBg = switch (config.variant) {
      SuperActionVariant.filled || SuperActionVariant.surface => scheme.primary,
      SuperActionVariant.tonal => scheme.secondaryContainer,
      SuperActionVariant.elevated => scheme.surfaceContainerLow,
      SuperActionVariant.outlined ||
      SuperActionVariant.text ||
      SuperActionVariant.icon => Colors.transparent,
    };
    final defaultFg = switch (config.variant) {
      SuperActionVariant.filled ||
      SuperActionVariant.surface => scheme.onPrimary,
      SuperActionVariant.tonal => scheme.onSecondaryContainer,
      SuperActionVariant.elevated ||
      SuperActionVariant.outlined ||
      SuperActionVariant.text => scheme.primary,
      SuperActionVariant.icon => scheme.onSurfaceVariant,
    };
    final pad =
        config.horizontalPadding != null || config.verticalPadding != null
        ? EdgeInsets.symmetric(
            horizontal:
                config.horizontalPadding ??
                (config.kind == SuperActionKind.icon ? 10 : 16),
            vertical: config.verticalPadding ?? 10,
          )
        : surfaceStyle.padding > 0 || surfaceStyle.paddingInsets != null
        ? surfaceStyle.contentPadding
        : EdgeInsets.symmetric(
            horizontal: config.kind == SuperActionKind.icon ? 10 : 16,
            vertical: 10,
          );
    final fg = config.color ?? defaultFg;
    button = Padding(
      padding: surfaceStyle.outerMargin,
      child: StyledSurface(
        key: buttonKey,
        style: surfaceStyle,
        fallbackColor: defaultBg,
        borderColor: config.borderColor ?? scheme.outline,
        child: InkWell(
          focusNode: focusNode,
          borderRadius: surfaceStyle.borderRadius,
          onTap: effectiveOnPressed,
          child: Padding(
            padding: pad,
            child: IconTheme.merge(
              data: IconThemeData(
                color: effectiveIconColor ?? fg,
                size: config.iconSize ?? 20,
              ),
              child: DefaultTextStyle.merge(
                style: textStyle.copyWith(color: fg),
                child: innerContent,
              ),
            ),
          ),
        ),
      ),
    );
    if (!config.enabled) {
      button = Opacity(opacity: 0.45, child: button);
    }
  } else {
    final bg = config.backgroundColor ?? config.style.color;
    final fg = config.color;
    final bColor = config.borderColor ?? config.style.borderColor;
    final bWidth =
        config.borderWidth ??
        (config.style.borderWidth > 0 ? config.style.borderWidth : null);
    final rad =
        config.radius ?? (config.style.radius > 0 ? config.style.radius : null);
    final elev =
        config.elevation ??
        (config.style.elevation > 0 ? config.style.elevation : null);
    final pad =
        config.horizontalPadding != null || config.verticalPadding != null
        ? EdgeInsets.symmetric(
            horizontal:
                config.horizontalPadding ??
                (config.kind == SuperActionKind.icon ? 10 : 16),
            vertical: config.verticalPadding ?? 10,
          )
        : (config.style.padding > 0 || config.style.paddingInsets != null)
        ? config.style.contentPadding
        : null;
    final shape = rad != null || config.style.radii != null
        ? RoundedRectangleBorder(
            borderRadius: rad != null
                ? BorderRadius.circular(rad)
                : config.style.borderRadius,
          )
        : null;
    final side = bColor != null || bWidth != null
        ? BorderSide(color: bColor ?? scheme.outline, width: bWidth ?? 1)
        : null;

    final buttonStyle = ButtonStyle(
      backgroundColor: bg != null ? WidgetStatePropertyAll(bg) : null,
      foregroundColor: fg != null ? WidgetStatePropertyAll(fg) : null,
      iconColor: (effectiveIconColor != null)
          ? WidgetStatePropertyAll(effectiveIconColor)
          : null,
      iconSize: config.iconSize != null
          ? WidgetStatePropertyAll(config.iconSize)
          : null,
      textStyle: WidgetStatePropertyAll(textStyle),
      elevation: elev != null ? WidgetStatePropertyAll(elev) : null,
      padding: pad != null ? WidgetStatePropertyAll(pad) : null,
      shape: shape != null ? WidgetStatePropertyAll(shape) : null,
      side: side != null ? WidgetStatePropertyAll(side) : null,
    );

    button = switch (config.variant) {
      SuperActionVariant.filled => FilledButton(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
      SuperActionVariant.tonal => FilledButton.tonal(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
      SuperActionVariant.elevated => ElevatedButton(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
      SuperActionVariant.outlined => OutlinedButton(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
      SuperActionVariant.text => TextButton(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
      SuperActionVariant.icon =>
        config.kind == SuperActionKind.icon
            ? IconButton(
                key: buttonKey,
                focusNode: focusNode,
                style: buttonStyle,
                iconSize: config.iconSize,
                color: effectiveIconColor,
                onPressed: effectiveOnPressed,
                icon: iconWidget,
              )
            : TextButton(
                key: buttonKey,
                focusNode: focusNode,
                style: buttonStyle,
                onPressed: effectiveOnPressed,
                child: innerContent,
              ),
      SuperActionVariant.surface => FilledButton(
        key: buttonKey,
        focusNode: focusNode,
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: innerContent,
      ),
    };
  }

  if (config.tooltip.trim().isNotEmpty) {
    button = Tooltip(message: config.tooltip, child: button);
  }
  return button;
}

/// Part of a native navigation destination or tab rendered by a [SuperAction].
enum SuperActionNavigationPart { icon, label, tab }

/// Scope instructing a descendant [SuperAction] to render as the icon or label
/// of a native navigation destination (`NavigationRailDestination` or
/// `BottomNavigationBarItem`) while preserving its editor interactions.
class SuperActionNavigationScope extends InheritedWidget {
  const SuperActionNavigationScope({
    required this.part,
    required super.child,
    super.key,
  });

  final SuperActionNavigationPart part;

  static SuperActionNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperActionNavigationScope>();

  @override
  bool updateShouldNotify(SuperActionNavigationScope oldWidget) =>
      part != oldWidget.part;
}

/// Executes [onPressed] and all enabled click [ComponentBehavior]s registered
/// for action [id].
void executeSuperActionClick(
  BuildContext context,
  String id, {
  VoidCallback? onPressed,
}) {
  onPressed?.call();
  final appearance =
      AppearanceScope.controllerOf(context)?.value ??
      AppearanceScope.of(context);
  final behaviors = appearance.behaviorsFor(id);
  for (final behavior in behaviors) {
    if (behavior.enabled && behavior.trigger == BehaviorTrigger.click) {
      behavior.execute(context);
    }
  }
}

/// Interactive button component supporting text, icon, or text+icon content,
/// Material/surface variants, repository property bindings, and automatic/named states.
class SuperAction extends StatefulWidget {
  const SuperAction({
    required this.id,
    this.config = const SuperActionConfig(),
    this.onPressed,
    this.onConfigChanged,
    this.availableFontFamilies = const [],
    super.key,
  });

  final String id;
  final SuperActionConfig config;
  final VoidCallback? onPressed;
  final ValueChanged<SuperActionConfig>? onConfigChanged;
  final List<String> availableFontFamilies;

  @override
  State<SuperAction> createState() => _SuperActionState();
}

class _SuperActionState extends State<SuperAction>
    implements JsonExtractableState {
  final _surface = GlobalKey<EditorSlotState>();
  late final ValueNotifier<SuperActionConfig> _local;
  Map<SuperActionProperty, Object> _boundPropertyValues = const {};
  Map<SuperActionProperty, String> _propertyBindingErrors = const {};
  List<JsonArrayBinding> _propertySelections = const [];
  Map<SuperActionProperty, JsonTextBinding> _activePropertyBindings = const {};
  Map<SuperActionProperty, JsonTextBinding>? _requestedPropertyBindings;
  JsonRepositoryStore? _requestedPropertyStore;
  String? _requestedPropertyRepositoryId;
  List<int> _requestedPropertyIndices = const [];
  bool _requestedPropertyPlaceholder = false;
  bool _refreshPropertyBindings = true;
  int _propertyBindingGeneration = 0;

  SuperActionConfig? _editorConfig;
  SurfaceStateBinding? _stateReader;
  bool _hovered = false;
  String? _stateError;
  final _focusNode = FocusNode();
  Set<AutomaticState> _automaticActive = {};

  void _stateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  SuperActionConfig _resolveStates(
    SuperActionConfig saved,
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
        if (_focusNode.hasFocus) AutomaticState.focused,
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
      _stateError = 'Combinaison d’états de l’action invalide.';
    }
    return saved.copyWith(clearStates: true);
  }

  @override
  void initState() {
    super.initState();
    widget.config.copyWith(clearStates: true).validate();
    _local = ValueNotifier(widget.config);
    _focusNode.addListener(_stateChanged);
  }

  @override
  void didUpdateWidget(SuperAction oldWidget) {
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
    SuperActionConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final bindings = config.propertyBindings;
    final sameBindingContext =
        mapEquals(_requestedPropertyBindings, bindings) &&
        identical(_requestedPropertyStore, store) &&
        _requestedPropertyRepositoryId == scope?.repositoryId &&
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
    final resolved = <SuperActionProperty, JsonTextBinding>{};
    final errors = <SuperActionProperty, String>{};
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
    if (!sameBindingContext) _boundPropertyValues = const {};
    if (store == null) {
      _boundPropertyValues = const {};
      _propertyBindingErrors = {
        ..._propertyBindingErrors,
        for (final property in resolved.keys)
          property: 'Service de repositories indisponible.',
      };
      return;
    }
    unawaited(_loadPropertyBindings(resolved, store, generation));
  }

  Future<void> _loadPropertyBindings(
    Map<SuperActionProperty, JsonTextBinding> bindings,
    JsonRepositoryStore store,
    int generation,
  ) async {
    final values = <SuperActionProperty, Object>{};
    final errors = Map<SuperActionProperty, String>.of(_propertyBindingErrors);
    for (final entry in bindings.entries) {
      try {
        final result = await store.readAttribute(entry.value);
        final value = _parseBoundActionProperty(entry.key, result.value);
        if (entry.key == SuperActionProperty.fontFamily &&
            widget.availableFontFamilies.isNotEmpty &&
            !widget.availableFontFamilies.contains(value)) {
          throw FormatException(
            'La police liée « $value » n’est pas disponible.',
          );
        }
        values[entry.key] = value;
        errors.remove(entry.key);
      } on FormatException catch (error) {
        errors[entry.key] = error.message;
      } on FileSystemException {
        errors[entry.key] = 'Impossible de lire le repository lié.';
      }
      if (!mounted || generation != _propertyBindingGeneration) return;
    }
    setState(() {
      _boundPropertyValues = values;
      _propertyBindingErrors = errors;
    });
  }

  SuperActionConfig _withBoundProperties(SuperActionConfig config) {
    var result = config;
    for (final entry in _boundPropertyValues.entries) {
      result = switch (entry.key) {
        SuperActionProperty.label => result.copyWith(
          label: entry.value as String,
        ),
        SuperActionProperty.tooltip => result.copyWith(
          tooltip: entry.value as String,
        ),
        SuperActionProperty.icon => result.copyWith(
          icon: entry.value as String,
        ),
        SuperActionProperty.enabled => result.copyWith(
          enabled: entry.value as bool,
        ),
        SuperActionProperty.fontFamily => result.copyWith(
          fontFamily: entry.value as String,
        ),
        SuperActionProperty.color => result.copyWith(
          color: entry.value as Color,
        ),
        SuperActionProperty.iconColor => result.copyWith(
          iconColor: entry.value as Color,
        ),
        SuperActionProperty.backgroundColor => result.copyWith(
          backgroundColor: entry.value as Color,
        ),
        SuperActionProperty.borderColor => result.copyWith(
          borderColor: entry.value as Color,
        ),
        SuperActionProperty.fontSize => result.copyWith(
          fontSize: entry.value as double,
        ),
        SuperActionProperty.iconSize => result.copyWith(
          iconSize: entry.value as double,
        ),
        SuperActionProperty.fontWeight => result.copyWith(
          fontWeight: entry.value as FontWeight,
        ),
        SuperActionProperty.italic => result.copyWith(
          italic: entry.value as bool,
        ),
        SuperActionProperty.textAlign => result.copyWith(
          textAlign: entry.value as TextAlign,
        ),
        SuperActionProperty.radius => result.copyWith(
          radius: entry.value as double,
        ),
        SuperActionProperty.borderWidth => result.copyWith(
          borderWidth: entry.value as double,
        ),
        SuperActionProperty.elevation => result.copyWith(
          elevation: entry.value as double,
        ),
      };
    }
    return result;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_stateChanged);
    _focusNode.dispose();
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
        registry?.actionController(widget.id, fallback: widget.config) ??
        _local;

    return MouseRegion(
      opaque: false,
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: ValueListenableBuilder<SuperActionConfig>(
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

          final navScope = SuperActionNavigationScope.maybeOf(context);
          if (navScope?.part == SuperActionNavigationPart.label) {
            return Text(
              config.label,
              key: ValueKey('super-action-label-${widget.id}'),
              style: textStyle,
              textAlign: config.textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          }

          final fit = SlotContentFitScope.maybeOf(context);
          final fitWidth = fit?.fitWidth ?? false;
          final fitHeight = fit?.fitHeight ?? false;

          Future<void> editAction() async {
            final initial = configuration.value;
            SuperActionConfig? result;
            try {
              result = await showSuperActionEditor(
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
            } finally {
              if (mounted) {
                setState(() => _editorConfig = null);
              }
            }
            if (result == null ||
                !context.mounted ||
                result == configuration.value) {
              return;
            }
            final history = EditorHistoryScope.controllerOf(context);
            history?.beginTransaction();
            try {
              configuration.value = result;
            } finally {
              history?.commitTransaction();
            }
            widget.onConfigChanged?.call(result);
          }

          if (navScope?.part == SuperActionNavigationPart.icon) {
            final hasIcon = config.icon.trim().isNotEmpty;
            Widget iconVisual = hasIcon
                ? Icon(
                    SuperActionIcons.resolve(config.icon),
                    key: ValueKey('super-action-icon-${widget.id}'),
                    size: config.iconSize,
                    color: config.iconColor ?? config.color,
                  )
                : SizedBox(
                    key: ValueKey('super-action-icon-${widget.id}'),
                    width: config.iconSize ?? 24,
                    height: config.iconSize ?? 24,
                  );
            if (config.tooltip.trim().isNotEmpty) {
              iconVisual = Tooltip(message: config.tooltip, child: iconVisual);
            }
            return EditorSlot(
              key: _surface,
              id: widget.id,
              label: 'Action',
              menuType: 'Action',
              menuTooltip: () => formatSuperActionTooltip(
                title: _surface.currentState?.titleLabel ?? 'Action',
                config: config,
              ),
              onEdit: editAction,
              child: SizedBox(
                width: 56,
                height: 24,
                child: Center(child: iconVisual),
              ),
            );
          }

          if (navScope?.part == SuperActionNavigationPart.tab) {
            final hasIcon =
                config.kind.hasIcon && config.icon.trim().isNotEmpty;
            final iconWidget = hasIcon
                ? Icon(
                    SuperActionIcons.resolve(config.icon),
                    key: ValueKey('super-action-icon-${widget.id}'),
                    size: config.iconSize ?? 18,
                    color: config.iconColor ?? config.color,
                  )
                : SizedBox(
                    key: ValueKey('super-action-icon-${widget.id}'),
                    width: config.iconSize ?? 18,
                    height: config.iconSize ?? 18,
                  );
            final textWidget = Text(
              config.label,
              key: ValueKey('super-action-label-${widget.id}'),
              style: textStyle,
              textAlign: config.textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
            Widget tabVisual = switch (config.kind) {
              SuperActionKind.icon => iconWidget,
              SuperActionKind.text => textWidget,
              SuperActionKind.textAndIcon =>
                !hasIcon
                    ? textWidget
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children:
                            config.iconPosition ==
                                SuperActionIconPosition.leading
                            ? [
                                iconWidget,
                                SizedBox(width: config.iconSpacing),
                                Flexible(child: textWidget),
                              ]
                            : [
                                Flexible(child: textWidget),
                                SizedBox(width: config.iconSpacing),
                                iconWidget,
                              ],
                      ),
            };
            if (!config.enabled) {
              tabVisual = Opacity(opacity: 0.45, child: tabVisual);
            }
            if (config.tooltip.trim().isNotEmpty) {
              tabVisual = Tooltip(message: config.tooltip, child: tabVisual);
            }
            return EditorSlot(
              key: _surface,
              id: widget.id,
              label: 'Action',
              menuType: 'Action',
              menuTooltip: () => formatSuperActionTooltip(
                title: _surface.currentState?.titleLabel ?? 'Action',
                config: config,
              ),
              onEdit: editAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Center(widthFactor: 1, child: tabVisual),
              ),
            );
          }

          return EditorSlot(
            key: _surface,
            id: widget.id,
            label: 'Action',
            menuType: 'Action',
            menuTooltip: () => formatSuperActionTooltip(
              title: _surface.currentState?.titleLabel ?? 'Action',
              config: config,
            ),
            onEdit: editAction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: fitWidth
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: Center(
                    widthFactor: fitWidth ? 1 : null,
                    heightFactor: fitHeight ? 1 : null,
                    child: buildSuperActionVisual(
                      context: context,
                      config: config,
                      textStyle: textStyle,
                      focusNode: _focusNode,
                      buttonKey: ValueKey('super-action-button-${widget.id}'),
                      labelKey: ValueKey('super-action-label-${widget.id}'),
                      iconKey: ValueKey('super-action-icon-${widget.id}'),
                      onPressed: _editorConfig != null
                          ? () {}
                          : () => executeSuperActionClick(
                              context,
                              widget.id,
                              onPressed: widget.onPressed,
                            ),
                    ),
                  ),
                ),
                if (_stateError != null)
                  Text(
                    _stateError!,
                    key: ValueKey('super-action-state-error-${widget.id}'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                for (final entry in _propertyBindingErrors.entries)
                  Text(
                    'Liaison ${entry.key.name} : ${entry.value}',
                    key: ValueKey(
                      'super-action-property-binding-error-'
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

  SuperActionConfig get _currentEffectiveConfig {
    final registry = SuperApp.maybeOf(context)?.registry;
    final saved =
        (registry?.actionController(widget.id, fallback: widget.config) ??
                _local)
            .value;
    final listScope = JsonListScope.maybeOf(context);
    final repositories = JsonRepositoryScope.maybeOf(context);
    final effective = _resolveStates(
      saved,
      listScope,
      repositories,
      ContentHoverScope.maybeOf(context)?.hovered == true,
    );
    return _withBoundProperties(effective);
  }

  @override
  String get extractableId => widget.id;

  @override
  ExtractableComponentKind get extractableKind =>
      ExtractableComponentKind.superAction;

  @override
  EditorSlotState? get extractableSurface => _surface.currentState;

  @override
  BuildContext get extractableContext => context;

  @override
  bool get isExtractableMounted => mounted;

  @override
  String get preferredExtractableKey {
    final surface = _surface.currentState;
    if (surface != null && surface.mounted && surface.hasCustomLabel) {
      final renamed = surface.titleLabel.trim();
      if (renamed.isNotEmpty) return renamed;
    }
    final instanceLabel = surface?.componentLabel?.label.trim();
    if (instanceLabel != null &&
        instanceLabel.isNotEmpty &&
        instanceLabel != 'Action') {
      return instanceLabel;
    }
    final config = _currentEffectiveConfig;
    final configLabel = config.label.trim();
    if (configLabel.isNotEmpty && configLabel != 'Action') {
      return configLabel;
    }
    return widget.id;
  }

  @override
  ExtractableComponentTarget buildExtractableTarget(String assignedBaseKey) {
    final config = _currentEffectiveConfig;
    final hasTextLabel = config.kind.hasText && config.label.trim().isNotEmpty;
    final hasTooltip = config.tooltip.trim().isNotEmpty;
    final options = <ExtractablePropertyOption>[
      if (hasTextLabel)
        ExtractablePropertyOption(
          id: SuperActionProperty.label.name,
          label: 'Texte',
          value: config.label,
          defaultSelected: true,
        ),
      if (hasTooltip)
        ExtractablePropertyOption(
          id: SuperActionProperty.tooltip.name,
          label: 'Info-bulle',
          value: config.tooltip,
          defaultSelected: !hasTextLabel,
        ),
      if (config.kind.hasIcon && config.icon.trim().isNotEmpty)
        ExtractablePropertyOption(
          id: SuperActionProperty.icon.name,
          label: 'Icône',
          value: config.icon,
          defaultSelected: !hasTextLabel && !hasTooltip,
        ),
      if (!config.enabled ||
          config.propertyBindings.containsKey(SuperActionProperty.enabled))
        ExtractablePropertyOption(
          id: SuperActionProperty.enabled.name,
          label: 'Activé',
          value: config.enabled,
        ),
      if (config.fontFamily != null && config.fontFamily!.trim().isNotEmpty)
        ExtractablePropertyOption(
          id: SuperActionProperty.fontFamily.name,
          label: 'Police',
          value: config.fontFamily!,
        ),
      if (config.color != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.color.name,
          label: 'Couleur du texte',
          value: JsonColor.toHex(config.color!),
        ),
      if (config.iconColor != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.iconColor.name,
          label: 'Couleur de l’icône',
          value: JsonColor.toHex(config.iconColor!),
        ),
      if (config.backgroundColor != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.backgroundColor.name,
          label: 'Couleur de fond',
          value: JsonColor.toHex(config.backgroundColor!),
        ),
      if (config.borderColor != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.borderColor.name,
          label: 'Couleur de bordure',
          value: JsonColor.toHex(config.borderColor!),
        ),
      if (config.fontSize != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.fontSize.name,
          label: 'Taille de police',
          value: config.fontSize!,
        ),
      if (config.iconSize != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.iconSize.name,
          label: 'Taille de l’icône',
          value: config.iconSize!,
        ),
      if (config.fontWeight != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.fontWeight.name,
          label: 'Graisse',
          value: config.fontWeight!.value,
        ),
      if (config.italic != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.italic.name,
          label: 'Italique',
          value: config.italic!,
        ),
      if (config.textAlign != const SuperActionConfig().textAlign ||
          config.propertyBindings.containsKey(SuperActionProperty.textAlign))
        ExtractablePropertyOption(
          id: SuperActionProperty.textAlign.name,
          label: 'Alignement',
          value: config.textAlign.name,
        ),
      if (config.radius != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.radius.name,
          label: 'Rayon',
          value: config.radius!,
        ),
      if (config.borderWidth != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.borderWidth.name,
          label: 'Épaisseur de bordure',
          value: config.borderWidth!,
        ),
      if (config.elevation != null)
        ExtractablePropertyOption(
          id: SuperActionProperty.elevation.name,
          label: 'Élévation',
          value: config.elevation!,
        ),
    ];

    return ExtractableComponentTarget(
      id: widget.id,
      kind: ExtractableComponentKind.superAction,
      displayName: preferredExtractableKey,
      baseJsonKey: assignedBaseKey,
      properties: options,
      applyBindings: (bindings) {
        if (!mounted || bindings.isEmpty) return;
        final registry = SuperApp.maybeOf(context)?.registry;
        final controller =
            registry?.actionController(widget.id, fallback: widget.config) ??
            _local;
        final current = controller.value;
        final updatedProps = <SuperActionProperty, JsonTextBinding>{
          ...current.propertyBindings,
          for (final prop in SuperActionProperty.values)
            if (bindings[prop.name] case final propBinding?) prop: propBinding,
        };
        final next = current.copyWith(propertyBindings: updatedProps);
        if (next == current) return;
        controller.value = next;
        widget.onConfigChanged?.call(next);
      },
    );
  }
}
