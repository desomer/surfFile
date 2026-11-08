/// Composant séparateur ou espaceur configurable ([SuperSeparator]) du catalogue GenUI.
///
/// Permet d'insérer un espaceur (`spacer`) ou un trait de séparation (`divider`)
/// horizontal ou vertical, avec ou sans libellé (`start`, `center`, `end`),
/// style de trait (`solid`, `dashed`, `dotted`), liaisons JSON ([JsonTextBinding])
/// et surcharges d'états ([SeparatorConfigStates]).
library;

import 'package:material_ui/material_ui.dart';

import '../../models/automatic_state.dart';
import '../../models/super_separator_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/states/content_hover_scope.dart';
import '../../super_app.dart';
import '../editing/components/super_separator_editor.dart';
import '../editing/slots/editor_slot.dart';
import 'component_common.dart';
import 'component_property_bindings.dart';
import 'super_component.dart';
import 'super_layout/slot_implementation.dart';
import 'super_separator_visual.dart';

export 'super_separator_visual.dart';

Object _parseBoundSeparatorProperty(
  SuperSeparatorProperty property,
  Object? value,
) => switch (property) {
  SuperSeparatorProperty.label ||
  SuperSeparatorProperty.fontFamily => BoundPropertyParsers.parseString(
    property.name,
    value,
    nonEmptyTrimmed: property == SuperSeparatorProperty.fontFamily,
  ),
  SuperSeparatorProperty.lineColor ||
  SuperSeparatorProperty.color => BoundPropertyParsers.parseColor(value),
  SuperSeparatorProperty.thickness || SuperSeparatorProperty.fontSize =>
    BoundPropertyParsers.parsePositiveDouble(
      value,
      errorMessage:
          'La taille ou épaisseur liée doit être un nombre positif.',
    ),
  SuperSeparatorProperty.extent ||
  SuperSeparatorProperty.indent ||
  SuperSeparatorProperty.endIndent =>
    BoundPropertyParsers.parseNonNegativeDouble(value),
  SuperSeparatorProperty.fontWeight => BoundPropertyParsers.parseFontWeight(
    value,
  ),
  SuperSeparatorProperty.italic => BoundPropertyParsers.parseItalic(value),
};

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

class _SuperSeparatorState extends State<SuperSeparator>
    with
        ComponentStateResolutionMixin<SuperSeparator>,
        ComponentPropertyBindingsMixin<SuperSeparator, SuperSeparatorProperty> {
  final _surface = GlobalKey<EditorSlotState>();
  late final ValueNotifier<SuperSeparatorConfig> _local;
  SuperSeparatorConfig? _editorConfig;

  @override
  List<String> get availableComponentFontFamilies =>
      widget.availableFontFamilies;

  @override
  Object parseBoundProperty(SuperSeparatorProperty property, Object? value) =>
      _parseBoundSeparatorProperty(property, value);

  SuperSeparatorConfig _resolveStates(
    SuperSeparatorConfig saved,
    JsonListScope? scope,
    JsonRepositoryStore? store,
    bool contentHovered,
  ) {
    syncSurfaceStateReader(saved.states?.binding, scope, store);
    try {
      automaticActiveStates = {
        if (contentHovered) AutomaticState.contentHover,
      };
      final config =
          saved.states?.resolve(
            saved,
            name: stateReader?.stateName,
            isHovered: isComponentHovered,
            isSelected: scope?.selected ?? false,
            activeStates: automaticActiveStates,
          ) ??
          saved;
      config.validate();
      return config;
    } on FormatException catch (error) {
      stateError = error.message;
    } on ArgumentError {
      stateError = 'Combinaison d’états du séparateur invalide.';
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

  SuperSeparatorConfig _withBoundProperties(SuperSeparatorConfig config) {
    var result = config;
    for (final entry in boundPropertyValues.entries) {
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
    disposeComponentStateReader();
    disposePropertyBindings();
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

    return wrapWithComponentHoverRegion(
      ValueListenableBuilder<SuperSeparatorConfig>(
        valueListenable: configuration,
        builder: (context, savedConfig, _) {
          final effective = _resolveStates(
            savedConfig,
            listScope,
            repositories,
            ContentHoverScope.maybeOf(context)?.hovered == true,
          );
          observePropertyBindings(
            effective.propertyBindings,
            listScope,
            repositories,
          );
          final config = _editorConfig ?? _withBoundProperties(effective);
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
            color: config.color,
            letterSpacing: config.letterSpacing,
          );

          final fit = SlotContentFitScope.maybeOf(context);
          final fitWidth = fit?.fitWidth ?? false;
          final fitHeight = fit?.fitHeight ?? false;

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
            exportConfig: () => configuration.value,
            behaviors: widget.behaviours,
            label: 'Separator',
            menuType: 'Separator',
            eventComponentType: 'separator',
            menuTooltip: () => formatSuperSeparatorTooltip(
              title: _surface.currentState?.titleLabel ?? 'Separator',
              config: config,
            ),
            onEdit: () => runComponentEditorTransaction<SuperSeparatorConfig>(
              context: context,
              configuration: configuration,
              onConfigChanged: widget.onConfigChanged,
              onFinally: () {
                if (mounted) setState(() => _editorConfig = null);
              },
              showEditor: (initial) => showSuperSeparatorEditor(
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
                ...buildComponentDiagnosticErrors(
                  context,
                  componentPrefix: 'super-separator',
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
