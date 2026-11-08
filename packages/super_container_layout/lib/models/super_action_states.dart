// Surcharges conditionnelles d'états ([ActionConfigStates]) pour un [SuperAction].
//
// Permet de modifier sélectivement des groupes de propriétés ([ActionStateProperty])
// au survol (`hover`), à la sélection de ligne (`selected`), sur état automatique
// ou sur état métier nommé lié à un repository JSON.
part of 'super_action_config.dart';

/// Groupes de propriétés de [SuperActionConfig] surchargeables par état.
enum ActionStateProperty implements ComponentStateProperty<SuperActionProperty> {
  content('Type et variante', [
    'kind',
    'variant',
    'iconPosition',
    'iconSpacing',
  ]),
  textLabel('Libellé', ['label'], SuperActionProperty.label),
  tooltip('Infobulle', ['tooltip'], SuperActionProperty.tooltip),
  icon('Icône', ['icon'], SuperActionProperty.icon),
  enabled('Activation', ['enabled'], SuperActionProperty.enabled),
  fontFamily('Police', ['fontFamily'], SuperActionProperty.fontFamily),
  fontSize('Taille du texte', ['fontSize'], SuperActionProperty.fontSize),
  iconSize('Taille de l’icône', ['iconSize'], SuperActionProperty.iconSize),
  fontWeight('Graisse', ['fontWeight'], SuperActionProperty.fontWeight),
  italic('Italique', ['italic'], SuperActionProperty.italic),
  color('Couleur du contenu', ['color'], SuperActionProperty.color),
  iconColor('Couleur de l’icône', ['iconColor'], SuperActionProperty.iconColor),
  backgroundColor('Couleur de fond', [
    'backgroundColor',
  ], SuperActionProperty.backgroundColor),
  borderColor('Couleur de bordure', [
    'borderColor',
  ], SuperActionProperty.borderColor),
  radius('Rayon', ['radius'], SuperActionProperty.radius),
  borderWidth('Épaisseur de bordure', [
    'borderWidth',
  ], SuperActionProperty.borderWidth),
  elevation('Élévation', ['elevation'], SuperActionProperty.elevation),
  padding('Marges internes', ['horizontalPadding', 'verticalPadding']),
  textAlign('Alignement', ['textAlign'], SuperActionProperty.textAlign),
  letterSpacing('Espacement des lettres', ['letterSpacing']),
  style('Style de surface', ['style']);

  const ActionStateProperty(this.label, this.keys, [this.bindingProperty]);

  @override
  final String label;
  @override
  final List<String> keys;
  @override
  final SuperActionProperty? bindingProperty;
}

/// Surcharge partielle d'un [SuperActionConfig] associée à une liste explicite de [ActionStateProperty].
@immutable
class ActionConfigOverride
    extends
        ComponentConfigOverrideBase<
          SuperActionConfig,
          ActionStateProperty,
          SuperActionProperty
        > {
  ActionConfigOverride({
    SuperActionConfig config = const SuperActionConfig(),
    super.properties,
  }) : super(config: _actionStateLeaf(config));

  ActionConfigOverride copyWith({
    SuperActionConfig? config,
    Set<ActionStateProperty>? properties,
    bool clearProperties = false,
  }) => ActionConfigOverride(
    config: config ?? this.config,
    properties: clearProperties ? const {} : properties ?? this.properties,
  );

  ActionConfigOverride edited(SuperActionConfig next) {
    final leaf = _actionStateLeaf(next);
    return ActionConfigOverride(
      config: leaf,
      properties: computeEditedProperties(
        leaf,
        ActionStateProperty.values,
        (c) => c.propertyBindings,
      ),
    );
  }

  @override
  SuperActionConfig apply(SuperActionConfig base) {
    final bindings = mergePropertyBindings(base, (c) => c.propertyBindings);
    bool has(ActionStateProperty property) => properties.contains(property);
    final content = has(ActionStateProperty.content) ? config : base;
    final pad = has(ActionStateProperty.padding) ? config : base;
    return SuperActionConfig(
      kind: content.kind,
      variant: content.variant,
      iconPosition: content.iconPosition,
      iconSpacing: content.iconSpacing,
      label: has(ActionStateProperty.textLabel) ? config.label : base.label,
      tooltip: has(ActionStateProperty.tooltip) ? config.tooltip : base.tooltip,
      icon: has(ActionStateProperty.icon) ? config.icon : base.icon,
      enabled: has(ActionStateProperty.enabled) ? config.enabled : base.enabled,
      fontFamily: has(ActionStateProperty.fontFamily)
          ? config.fontFamily
          : base.fontFamily,
      fontSize: has(ActionStateProperty.fontSize)
          ? config.fontSize
          : base.fontSize,
      iconSize: has(ActionStateProperty.iconSize)
          ? config.iconSize
          : base.iconSize,
      fontWeight: has(ActionStateProperty.fontWeight)
          ? config.fontWeight
          : base.fontWeight,
      italic: has(ActionStateProperty.italic) ? config.italic : base.italic,
      color: has(ActionStateProperty.color) ? config.color : base.color,
      iconColor: has(ActionStateProperty.iconColor)
          ? config.iconColor
          : base.iconColor,
      backgroundColor: has(ActionStateProperty.backgroundColor)
          ? config.backgroundColor
          : base.backgroundColor,
      borderColor: has(ActionStateProperty.borderColor)
          ? config.borderColor
          : base.borderColor,
      radius: has(ActionStateProperty.radius) ? config.radius : base.radius,
      borderWidth: has(ActionStateProperty.borderWidth)
          ? config.borderWidth
          : base.borderWidth,
      elevation: has(ActionStateProperty.elevation)
          ? config.elevation
          : base.elevation,
      horizontalPadding: pad.horizontalPadding,
      verticalPadding: pad.verticalPadding,
      textAlign: has(ActionStateProperty.textAlign)
          ? config.textAlign
          : base.textAlign,
      letterSpacing: has(ActionStateProperty.letterSpacing)
          ? config.letterSpacing
          : base.letterSpacing,
      style: has(ActionStateProperty.style) ? config.style : base.style,
      propertyBindings: Map.unmodifiable(bindings),
    ).._validateLeaf();
  }

  factory ActionConfigOverride.fromJson(Object? value) {
    final properties = ComponentStateHelpers.parseOverrideProperties(
      value,
      ActionStateProperty.values,
      'Action',
    );
    return ActionConfigOverride(
      config: _readActionStateLeaf((value as Map)['config']),
      properties: properties,
    );
  }
}

/// Collection des surcharges d'états (`named`, `hover`, `selected`, `automatic`) d'un [SuperActionConfig].
@immutable
class ActionConfigStates
    extends
        ComponentConfigStatesBase<
          SuperActionConfig,
          ActionStateProperty,
          SuperActionProperty,
          ActionConfigOverride
        > {
  ActionConfigStates({
    super.binding,
    super.named,
    super.namedProperties,
    super.hover,
    super.selected,
    super.automatic,
    super.order,
  }) : super(context: 'Action', toLeaf: _actionStateLeaf);

  static const hoverKey = ComponentStateHelpers.hoverKey;
  static const selectedKey = ComponentStateHelpers.selectedKey;

  @override
  SuperActionConfig clearStatesOf(SuperActionConfig base) =>
      base.copyWith(clearStates: true);

  @override
  ActionConfigOverride buildOverride(
    SuperActionConfig config,
    Set<ActionStateProperty> properties,
  ) => ActionConfigOverride(config: config, properties: properties);

  ActionConfigStates copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<String, SuperActionConfig>? named,
    Map<String, Set<ActionStateProperty>>? namedProperties,
    bool clearNamed = false,
    ActionConfigOverride? hover,
    bool clearHover = false,
    ActionConfigOverride? selected,
    bool clearSelected = false,
    Map<AutomaticState, ActionConfigOverride>? automatic,
    List<String>? order,
    bool clearOrder = false,
  }) {
    final nextNamed = clearNamed
        ? <String, SuperActionConfig>{}
        : named ?? this.named;
    return ActionConfigStates(
      binding: clearBinding ? null : binding ?? this.binding,
      named: nextNamed,
      namedProperties:
          namedProperties ??
          {
            for (final name in nextNamed.keys)
              name: this.namedProperties[name] ?? {},
          },
      hover: clearHover ? null : hover ?? this.hover,
      selected: clearSelected ? null : selected ?? this.selected,
      automatic: automatic ?? this.automatic,
      order: clearOrder
          ? null
          : order ??
                ComponentStateHelpers.filterCopiedOrder(
                  this.order,
                  (automatic ?? this.automatic).keys,
                  nextNamed,
                ),
    );
  }

  void _validateAgainst(SuperActionConfig base) =>
      validateStatesAgainst(base, (c) => c._validateLeaf());

  factory ActionConfigStates.fromJson(Object? value) =>
      ComponentStateHelpers.parseStatesJson(
        value: value,
        context: 'Action',
        readLeaf: _readActionStateLeaf,
        parseOverride: ActionConfigOverride.fromJson,
        build: ActionConfigStates.new,
      );
}

SuperActionConfig _actionStateLeaf(SuperActionConfig config) =>
    ComponentStateHelpers.ensureStateLeaf(
      config,
      states: config.states,
      normalize: (c) => c.copyWith(
        propertyBindings: Map.unmodifiable(c.propertyBindings),
      ),
      context: 'Action',
    );

SuperActionConfig _readActionStateLeaf(Object? value) =>
    ComponentStateHelpers.readStateLeaf(
      value,
      fromJson: SuperActionConfig.fromJson,
      toLeaf: _actionStateLeaf,
      context: 'Action',
    );
