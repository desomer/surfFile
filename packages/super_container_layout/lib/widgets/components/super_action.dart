/// Composant bouton / action configurable ([SuperAction]) du catalogue GenUI.
///
/// Supporte les variantes Material 3 et `surface`, les surcharges d'états ([ActionConfigStates]),
/// les liaisons JSON ([JsonTextBinding]) et les comportements au clic ([ComponentBehavior]).
library;

import 'package:material_ui/material_ui.dart';

import '../../theme/theme_color.dart';

import '../../models/automatic_state.dart';
import '../../models/json_text_binding.dart';
import '../../models/super_action_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/states/content_hover_scope.dart';
import '../../super_app.dart';
import '../editing/components/super_action_editor.dart';
import '../editing/dialogs/super_value_json_extract_dialog.dart';
import '../editing/slots/editor_slot.dart';
import 'component_common.dart';
import 'component_property_bindings.dart';
import 'component_state_behavior.dart';
import 'super_action_visual.dart';
import 'super_component.dart';
import 'super_layout/slot_implementation.dart';

export 'super_action_visual.dart';

Object _parseBoundActionProperty(SuperActionProperty property, Object? value) =>
    switch (property) {
      SuperActionProperty.label ||
      SuperActionProperty.tooltip ||
      SuperActionProperty.fontFamily => BoundPropertyParsers.parseString(
        property.name,
        value,
        nonEmptyTrimmed: property == SuperActionProperty.fontFamily,
      ),
      SuperActionProperty.icon => BoundPropertyParsers.parseIcon(
        value,
        SuperActionIcons.isKnown,
      ),
      SuperActionProperty.enabled => BoundPropertyParsers.parseEnabled(value),
      SuperActionProperty.color ||
      SuperActionProperty.iconColor ||
      SuperActionProperty.backgroundColor ||
      SuperActionProperty.borderColor => BoundPropertyParsers.parseColor(value),
      SuperActionProperty.fontSize ||
      SuperActionProperty.iconSize => BoundPropertyParsers.parsePositiveDouble(
        value,
      ),
      SuperActionProperty.radius ||
      SuperActionProperty.borderWidth ||
      SuperActionProperty.elevation =>
        BoundPropertyParsers.parseNonNegativeDouble(value),
      SuperActionProperty.fontWeight => BoundPropertyParsers.parseFontWeight(
        value,
      ),
      SuperActionProperty.italic => BoundPropertyParsers.parseItalic(value),
      SuperActionProperty.textAlign => BoundPropertyParsers.parseTextAlign(
        value,
      ),
    };

/// Interactive button component supporting text, icon, or text+icon content,
/// Material/surface variants, repository property bindings, and automatic/named states.
class SuperAction extends SuperStatefulComponent<SuperActionConfig> {
  const SuperAction({
    required this.id,
    this.config = const SuperActionConfig(),
    this.onPressed,
    this.onConfigChanged,
    this.availableFontFamilies = const [],
    super.behaviours,
    super.key,
  });

  @override
  final String id;
  @override
  final SuperActionConfig config;
  final VoidCallback? onPressed;
  final ValueChanged<SuperActionConfig>? onConfigChanged;
  final List<String> availableFontFamilies;

  @override
  State<SuperAction> createState() => _SuperActionState();
}

class _SuperActionState extends State<SuperAction>
    with
        ComponentStateResolutionMixin<SuperAction>,
        ComponentPropertyBindingsMixin<SuperAction, SuperActionProperty>
    implements JsonExtractableState {
  final _surface = GlobalKey<EditorSlotState>();
  late final ValueNotifier<SuperActionConfig> _local;
  SuperActionConfig? _editorConfig;
  final _focusNode = FocusNode();

  @override
  List<String> get availableComponentFontFamilies =>
      widget.availableFontFamilies;

  @override
  Object parseBoundProperty(SuperActionProperty property, Object? value) =>
      _parseBoundActionProperty(property, value);

  SuperActionConfig _resolveStates(
    SuperActionConfig saved,
    JsonListScope? scope,
    JsonRepositoryStore? store,
    bool contentHovered, {
    bool? isSelected,
    bool behaviorDisabled = false,
    bool behaviorReadOnly = false,
  }) {
    syncSurfaceStateReader(saved.states?.binding, scope, store);
    try {
      final source =
          saved.states?.resolve(saved, name: stateReader?.stateName) ??
          saved.copyWith(clearStates: true);
      automaticActiveStates = {
        if (contentHovered) AutomaticState.contentHover,
        if (_focusNode.hasFocus) AutomaticState.focused,
        if (behaviorDisabled || !source.enabled) AutomaticState.disabled,
        if (behaviorReadOnly) AutomaticState.readOnly,
      };
      var config =
          saved.states?.resolve(
            saved,
            name: stateReader?.stateName,
            isHovered: isComponentHovered,
            isSelected: isSelected ?? (scope?.selected ?? false),
            activeStates: automaticActiveStates,
          ) ??
          saved;
      if (behaviorDisabled && config.enabled) {
        config = config.copyWith(enabled: false);
      }
      config.validate();
      return config;
    } on FormatException catch (error) {
      stateError = error.message;
    } on ArgumentError {
      stateError = 'Combinaison d’états de l’action invalide.';
    }
    final fallback = saved.copyWith(clearStates: true);
    return behaviorDisabled && fallback.enabled
        ? fallback.copyWith(enabled: false)
        : fallback;
  }

  @override
  void initState() {
    super.initState();
    widget.config.copyWith(clearStates: true).validate();
    _local = ValueNotifier(widget.config);
    _focusNode.addListener(onComponentStateChanged);
  }

  @override
  void didUpdateWidget(SuperAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.config.copyWith(clearStates: true).validate();
    if (oldWidget.config != widget.config) _local.value = widget.config;
  }

  SuperActionConfig _withBoundProperties(SuperActionConfig config) {
    var result = config;
    for (final entry in boundPropertyValues.entries) {
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
    _focusNode.removeListener(onComponentStateChanged);
    _focusNode.dispose();
    disposeComponentStateReader();
    disposePropertyBindings();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComponentStateBehavior(
    componentId: widget.id,
    behaviors: widget.behaviours,
    child: Builder(builder: _buildActionContent),
  );

  Widget _buildActionContent(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final repositories = JsonRepositoryScope.maybeOf(context);
    final listScope = JsonListScope.maybeOf(context);
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    final behaviorDisabled =
        !editing && ComponentBehaviorStateScope.isDisabled(context);
    final behaviorReadOnly =
        !editing && ComponentBehaviorStateScope.isReadOnly(context);
    final configuration =
        registry?.actionController(widget.id, fallback: widget.config) ??
        _local;

    return wrapWithComponentHoverRegion(
      ValueListenableBuilder<SuperActionConfig>(
        valueListenable: configuration,
        builder: (context, savedConfig, _) {
          final navScope = SuperActionNavigationScope.maybeOf(context);
          final isSelected =
              (listScope?.selected ?? false) || (navScope?.selected ?? false);
          final effective = _resolveStates(
            savedConfig,
            listScope,
            repositories,
            ContentHoverScope.maybeOf(context)?.hovered == true,
            isSelected: isSelected,
            behaviorDisabled: behaviorDisabled,
            behaviorReadOnly: behaviorReadOnly,
          );
          observePropertyBindings(
            effective.propertyBindings,
            listScope,
            repositories,
          );
          var boundConfig = _withBoundProperties(effective);
          if (behaviorDisabled && boundConfig.enabled) {
            boundConfig = boundConfig.copyWith(enabled: false);
          }
          final config = _editorConfig ?? boundConfig;
          final missingFont = isComponentFontMissing(
            config.fontFamily,
            widget.availableFontFamilies,
          );
          final textStyle = buildComponentTextStyle(
            context,
            fontFamily: config.fontFamily,
            missingFont: missingFont,
            fontSize: config.fontSize,
            fontWeight: config.fontWeight,
            italic: config.italic,
            color: config.color.resolveTheme(context),
            letterSpacing: config.letterSpacing,
          );

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

          Future<void> editAction() =>
              runComponentEditorTransaction<SuperActionConfig>(
                context: context,
                configuration: configuration,
                onConfigChanged: widget.onConfigChanged,
                onFinally: () {
                  if (mounted) setState(() => _editorConfig = null);
                },
                showEditor: (initial) => showSuperActionEditor(
                  context: context,
                  config: initial,
                  availableFontFamilies: widget.availableFontFamilies,
                  activeState: stateReader?.stateName,
                  stateError: stateError,
                  isHovered: isComponentHovered,
                  isSelected: listScope?.selected ?? false,
                  allowContentHover: ContentHoverScope.maybeOf(context) != null,
                  activeAutomatic: automaticActiveStates,
                  onPreviewChanged: (draft) {
                    if (mounted) setState(() => _editorConfig = draft);
                  },
                ),
              );

          if (navScope?.part == SuperActionNavigationPart.icon) {
            final hasIcon = config.icon.trim().isNotEmpty;
            Widget iconVisual = hasIcon
                ? Icon(
                    SuperActionIcons.resolve(config.icon),
                    key: ValueKey('super-action-icon-${widget.id}'),
                    size: config.iconSize,
                    color: config.iconColor.resolveTheme(context) ?? config.color.resolveTheme(context),
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
              exportConfig: () => configuration.value,
              behaviors: widget.behaviours,
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
            return EditorSlot(
              key: _surface,
              id: widget.id,
              exportConfig: () => configuration.value,
              behaviors: widget.behaviours,
              label: 'Action',
              menuType: 'Action',
              menuTooltip: () => formatSuperActionTooltip(
                title: _surface.currentState?.titleLabel ?? 'Action',
                config: config,
              ),
              onEdit: editAction,
              child: buildSuperActionTabVisual(
                context: context,
                componentId: widget.id,
                config: config,
                textStyle: textStyle,
              ),
            );
          }

          return EditorSlot(
            key: _surface,
            id: widget.id,
            exportConfig: () => configuration.value,
            behaviors: widget.behaviours,
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
                              behaviours: widget.behaviours,
                            ),
                    ),
                  ),
                ),
                ...buildComponentDiagnosticErrors(
                  context,
                  componentPrefix: 'super-action',
                  componentId: widget.id,
                  stateError: stateError,
                  propertyBindingErrors: propertyBindingErrors,
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
    final navScope = SuperActionNavigationScope.maybeOf(context);
    final isSelected =
        (listScope?.selected ?? false) || (navScope?.selected ?? false);
    final effective = _resolveStates(
      saved,
      listScope,
      repositories,
      ContentHoverScope.maybeOf(context)?.hovered == true,
      isSelected: isSelected,
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
  String get preferredExtractableKey => resolveExtractableComponentKey(
    surface: _surface.currentState,
    fallbackId: widget.id,
    configLabel: _currentEffectiveConfig.label,
    ignoredLabels: const {'Action'},
  );

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
      ...buildTypographyExtractableOptions(
        fontFamily: config.fontFamily,
        color: config.color,
        colorLabel: 'Couleur du texte',
        iconColor: config.iconColor,
        backgroundColor: config.backgroundColor,
        borderColor: config.borderColor,
        fontSize: config.fontSize,
        iconSize: config.iconSize,
        fontWeight: config.fontWeight,
        italic: config.italic,
        textAlign: config.textAlign,
        defaultTextAlign: const SuperActionConfig().textAlign,
        hasTextAlignBinding: config.propertyBindings.containsKey(
          SuperActionProperty.textAlign,
        ),
        radius: config.radius,
        borderWidth: config.borderWidth,
        elevation: config.elevation,
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
            prop: ?bindings[prop.name],
        };
        final next = current.copyWith(propertyBindings: updatedProps);
        if (next == current) return;
        controller.value = next;
        widget.onConfigChanged?.call(next);
      },
    );
  }
}
