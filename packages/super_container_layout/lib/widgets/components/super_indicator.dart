/// Composant indicateur / icône d'état configurable ([SuperIndicator]) du catalogue GenUI.
///
/// Affiche une icône Material ([MaterialIconCatalog]) avec libellé et badge/surface
/// optionnels, pilotée par les surcharges d'états standards et personnalisés
/// ([IndicatorConfigStates]), les liaisons JSON ([JsonTextBinding]) et les
/// comportements ([ComponentBehavior]).
library;

import 'package:material_ui/material_ui.dart';

import '../../theme/theme_color.dart';

import '../../models/automatic_state.dart';
import '../../models/super_indicator_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/states/content_hover_scope.dart';
import '../../super_app.dart';
import '../editing/components/super_indicator_editor.dart';
import '../editing/slots/editor_slot.dart';
import 'component_common.dart';
import 'component_property_bindings.dart';
import 'component_state_behavior.dart';
import 'super_component.dart';
import 'super_indicator_visual.dart';
import 'super_layout/slot_implementation.dart';

export 'super_indicator_visual.dart';

Object _parseBoundIndicatorProperty(
  SuperIndicatorProperty property,
  Object? value,
) => switch (property) {
  SuperIndicatorProperty.label ||
  SuperIndicatorProperty.tooltip ||
  SuperIndicatorProperty.fontFamily => BoundPropertyParsers.parseString(
    property.name,
    value,
    nonEmptyTrimmed: property == SuperIndicatorProperty.fontFamily,
  ),
  SuperIndicatorProperty.icon => BoundPropertyParsers.parseIcon(
    value,
    SuperIndicatorIcons.isKnown,
  ),
  SuperIndicatorProperty.enabled => BoundPropertyParsers.parseEnabled(value),
  SuperIndicatorProperty.color ||
  SuperIndicatorProperty.iconColor ||
  SuperIndicatorProperty.backgroundColor ||
  SuperIndicatorProperty.borderColor => BoundPropertyParsers.parseColor(value),
  SuperIndicatorProperty.fontSize || SuperIndicatorProperty.iconSize =>
    BoundPropertyParsers.parsePositiveDouble(value),
  SuperIndicatorProperty.radius ||
  SuperIndicatorProperty.borderWidth ||
  SuperIndicatorProperty.elevation =>
    BoundPropertyParsers.parseNonNegativeDouble(value),
  SuperIndicatorProperty.fontWeight => BoundPropertyParsers.parseFontWeight(
    value,
  ),
  SuperIndicatorProperty.italic => BoundPropertyParsers.parseItalic(value),
  SuperIndicatorProperty.textAlign => BoundPropertyParsers.parseTextAlign(
    value,
  ),
};

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

class _SuperIndicatorState extends State<SuperIndicator>
    with
        ComponentStateResolutionMixin<SuperIndicator>,
        ComponentPropertyBindingsMixin<SuperIndicator, SuperIndicatorProperty> {
  final _surface = GlobalKey<EditorSlotState>();
  late final ValueNotifier<SuperIndicatorConfig> _local;
  SuperIndicatorConfig? _editorConfig;

  @override
  List<String> get availableComponentFontFamilies =>
      widget.availableFontFamilies;

  @override
  Object parseBoundProperty(SuperIndicatorProperty property, Object? value) =>
      _parseBoundIndicatorProperty(property, value);

  SuperIndicatorConfig _resolveStates(
    SuperIndicatorConfig saved,
    JsonListScope? scope,
    JsonRepositoryStore? store,
    bool contentHovered, {
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
        if (behaviorDisabled || !source.enabled) AutomaticState.disabled,
        if (behaviorReadOnly) AutomaticState.readOnly,
      };
      var config =
          saved.states?.resolve(
            saved,
            name: stateReader?.stateName,
            isHovered: isComponentHovered,
            isSelected: scope?.selected ?? false,
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
      stateError = 'Combinaison d’états de l’indicateur invalide.';
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
  }

  @override
  void didUpdateWidget(SuperIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.config.copyWith(clearStates: true).validate();
    if (oldWidget.config != widget.config) _local.value = widget.config;
  }

  SuperIndicatorConfig _withBoundProperties(SuperIndicatorConfig config) {
    var result = config;
    for (final entry in boundPropertyValues.entries) {
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
    disposeComponentStateReader();
    disposePropertyBindings();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComponentStateBehavior(
    componentId: widget.id,
    behaviors: widget.behaviours,
    child: Builder(builder: _buildIndicatorContent),
  );

  Widget _buildIndicatorContent(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final repositories = JsonRepositoryScope.maybeOf(context);
    final listScope = JsonListScope.maybeOf(context);
    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    final behaviorDisabled =
        !editing && ComponentBehaviorStateScope.isDisabled(context);
    final behaviorReadOnly =
        !editing && ComponentBehaviorStateScope.isReadOnly(context);
    final configuration =
        registry?.indicatorController(widget.id, fallback: widget.config) ??
        _local;

    return wrapWithComponentHoverRegion(
      ValueListenableBuilder<SuperIndicatorConfig>(
        valueListenable: configuration,
        builder: (context, savedConfig, _) {
          final effective = _resolveStates(
            savedConfig,
            listScope,
            repositories,
            ContentHoverScope.maybeOf(context)?.hovered == true,
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

          final fit = SlotContentFitScope.maybeOf(context);
          final fitWidth = fit?.fitWidth ?? false;
          final fitHeight = fit?.fitHeight ?? false;

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
            onEdit: () => runComponentEditorTransaction<SuperIndicatorConfig>(
              context: context,
              configuration: configuration,
              onConfigChanged: widget.onConfigChanged,
              onFinally: () {
                if (mounted) setState(() => _editorConfig = null);
              },
              showEditor: (initial) => showSuperIndicatorEditor(
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
            ),
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
                ...buildComponentDiagnosticErrors(
                  context,
                  componentPrefix: 'super-indicator',
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
}
