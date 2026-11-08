// Surcharges conditionnelles d'états ([IndicatorConfigStates]) pour un [SuperIndicator].
//
// Permet de modifier sélectivement des groupes de propriétés ([IndicatorStateProperty])
// au survol (`hover`), à la sélection de ligne (`selected`), sur état automatique
// ou sur état métier nommé lié à un repository JSON.
part of 'super_indicator_config.dart';

/// Groupes de propriétés de [SuperIndicatorConfig] surchargeables par état.
enum IndicatorStateProperty
    implements ComponentStateProperty<SuperIndicatorProperty> {
  content('Disposition', ['iconPosition', 'iconSpacing']),
  icon('Icône', ['icon'], SuperIndicatorProperty.icon),
  textLabel('Libellé', ['label'], SuperIndicatorProperty.label),
  tooltip('Infobulle', ['tooltip'], SuperIndicatorProperty.tooltip),
  enabled('Activation', ['enabled'], SuperIndicatorProperty.enabled),
  fontFamily('Police', ['fontFamily'], SuperIndicatorProperty.fontFamily),
  fontSize('Taille du texte', ['fontSize'], SuperIndicatorProperty.fontSize),
  iconSize('Taille de l’icône', ['iconSize'], SuperIndicatorProperty.iconSize),
  fontWeight('Graisse', ['fontWeight'], SuperIndicatorProperty.fontWeight),
  italic('Italique', ['italic'], SuperIndicatorProperty.italic),
  color('Couleur du contenu', ['color'], SuperIndicatorProperty.color),
  iconColor('Couleur de l’icône', [
    'iconColor',
  ], SuperIndicatorProperty.iconColor),
  backgroundColor('Couleur de fond', [
    'backgroundColor',
  ], SuperIndicatorProperty.backgroundColor),
  borderColor('Couleur de bordure', [
    'borderColor',
  ], SuperIndicatorProperty.borderColor),
  radius('Rayon', ['radius'], SuperIndicatorProperty.radius),
  borderWidth('Épaisseur de bordure', [
    'borderWidth',
  ], SuperIndicatorProperty.borderWidth),
  elevation('Élévation', ['elevation'], SuperIndicatorProperty.elevation),
  padding('Marges internes', ['horizontalPadding', 'verticalPadding']),
  textAlign('Alignement', ['textAlign'], SuperIndicatorProperty.textAlign),
  letterSpacing('Espacement des lettres', ['letterSpacing']),
  style('Style de surface', ['style']);

  const IndicatorStateProperty(this.label, this.keys, [this.bindingProperty]);

  @override
  final String label;
  @override
  final List<String> keys;
  @override
  final SuperIndicatorProperty? bindingProperty;
}

/// Surcharge partielle d'un [SuperIndicatorConfig] associée à une liste explicite de [IndicatorStateProperty].
@immutable
class IndicatorConfigOverride
    extends
        ComponentConfigOverrideBase<
          SuperIndicatorConfig,
          IndicatorStateProperty,
          SuperIndicatorProperty
        > {
  IndicatorConfigOverride({
    SuperIndicatorConfig config = const SuperIndicatorConfig(),
    super.properties,
  }) : super(config: _indicatorStateLeaf(config));

  IndicatorConfigOverride copyWith({
    SuperIndicatorConfig? config,
    Set<IndicatorStateProperty>? properties,
    bool clearProperties = false,
  }) => IndicatorConfigOverride(
    config: config ?? this.config,
    properties: clearProperties ? const {} : properties ?? this.properties,
  );

  IndicatorConfigOverride edited(SuperIndicatorConfig next) {
    final leaf = _indicatorStateLeaf(next);
    return IndicatorConfigOverride(
      config: leaf,
      properties: computeEditedProperties(
        leaf,
        IndicatorStateProperty.values,
        (c) => c.propertyBindings,
      ),
    );
  }

  @override
  SuperIndicatorConfig apply(SuperIndicatorConfig base) {
    final bindings = mergePropertyBindings(base, (c) => c.propertyBindings);
    bool has(IndicatorStateProperty property) => properties.contains(property);
    final content = has(IndicatorStateProperty.content) ? config : base;
    final pad = has(IndicatorStateProperty.padding) ? config : base;
    return SuperIndicatorConfig(
      iconPosition: content.iconPosition,
      iconSpacing: content.iconSpacing,
      icon: has(IndicatorStateProperty.icon) ? config.icon : base.icon,
      label: has(IndicatorStateProperty.textLabel) ? config.label : base.label,
      tooltip: has(IndicatorStateProperty.tooltip)
          ? config.tooltip
          : base.tooltip,
      enabled: has(IndicatorStateProperty.enabled)
          ? config.enabled
          : base.enabled,
      fontFamily: has(IndicatorStateProperty.fontFamily)
          ? config.fontFamily
          : base.fontFamily,
      fontSize: has(IndicatorStateProperty.fontSize)
          ? config.fontSize
          : base.fontSize,
      iconSize: has(IndicatorStateProperty.iconSize)
          ? config.iconSize
          : base.iconSize,
      fontWeight: has(IndicatorStateProperty.fontWeight)
          ? config.fontWeight
          : base.fontWeight,
      italic: has(IndicatorStateProperty.italic) ? config.italic : base.italic,
      color: has(IndicatorStateProperty.color) ? config.color : base.color,
      iconColor: has(IndicatorStateProperty.iconColor)
          ? config.iconColor
          : base.iconColor,
      backgroundColor: has(IndicatorStateProperty.backgroundColor)
          ? config.backgroundColor
          : base.backgroundColor,
      borderColor: has(IndicatorStateProperty.borderColor)
          ? config.borderColor
          : base.borderColor,
      radius: has(IndicatorStateProperty.radius) ? config.radius : base.radius,
      borderWidth: has(IndicatorStateProperty.borderWidth)
          ? config.borderWidth
          : base.borderWidth,
      elevation: has(IndicatorStateProperty.elevation)
          ? config.elevation
          : base.elevation,
      horizontalPadding: pad.horizontalPadding,
      verticalPadding: pad.verticalPadding,
      textAlign: has(IndicatorStateProperty.textAlign)
          ? config.textAlign
          : base.textAlign,
      letterSpacing: has(IndicatorStateProperty.letterSpacing)
          ? config.letterSpacing
          : base.letterSpacing,
      style: has(IndicatorStateProperty.style) ? config.style : base.style,
      propertyBindings: Map.unmodifiable(bindings),
    ).._validateLeaf();
  }

  factory IndicatorConfigOverride.fromJson(Object? value) {
    final properties = ComponentStateHelpers.parseOverrideProperties(
      value,
      IndicatorStateProperty.values,
      'Indicator',
    );
    return IndicatorConfigOverride(
      config: _readIndicatorStateLeaf((value as Map)['config']),
      properties: properties,
    );
  }
}

/// Collection des surcharges d'états (`named`, `hover`, `selected`, `automatic`) d'un [SuperIndicatorConfig].
@immutable
class IndicatorConfigStates
    extends
        ComponentConfigStatesBase<
          SuperIndicatorConfig,
          IndicatorStateProperty,
          SuperIndicatorProperty,
          IndicatorConfigOverride
        > {
  IndicatorConfigStates({
    super.binding,
    super.named,
    super.namedProperties,
    super.hover,
    super.selected,
    super.automatic,
    super.order,
  }) : super(context: 'Indicator', toLeaf: _indicatorStateLeaf);

  static const hoverKey = ComponentStateHelpers.hoverKey;
  static const selectedKey = ComponentStateHelpers.selectedKey;

  @override
  SuperIndicatorConfig clearStatesOf(SuperIndicatorConfig base) =>
      base.copyWith(clearStates: true);

  @override
  IndicatorConfigOverride buildOverride(
    SuperIndicatorConfig config,
    Set<IndicatorStateProperty> properties,
  ) => IndicatorConfigOverride(config: config, properties: properties);

  IndicatorConfigStates copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<String, SuperIndicatorConfig>? named,
    Map<String, Set<IndicatorStateProperty>>? namedProperties,
    bool clearNamed = false,
    IndicatorConfigOverride? hover,
    bool clearHover = false,
    IndicatorConfigOverride? selected,
    bool clearSelected = false,
    Map<AutomaticState, IndicatorConfigOverride>? automatic,
    List<String>? order,
    bool clearOrder = false,
  }) {
    final nextNamed = clearNamed
        ? <String, SuperIndicatorConfig>{}
        : named ?? this.named;
    return IndicatorConfigStates(
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

  void _validateAgainst(SuperIndicatorConfig base) =>
      validateStatesAgainst(base, (c) => c._validateLeaf());

  factory IndicatorConfigStates.fromJson(Object? value) =>
      ComponentStateHelpers.parseStatesJson(
        value: value,
        context: 'Indicator',
        readLeaf: _readIndicatorStateLeaf,
        parseOverride: IndicatorConfigOverride.fromJson,
        build: IndicatorConfigStates.new,
      );
}

SuperIndicatorConfig _indicatorStateLeaf(SuperIndicatorConfig config) =>
    ComponentStateHelpers.ensureStateLeaf(
      config,
      states: config.states,
      normalize: (c) => c.copyWith(
        propertyBindings: Map.unmodifiable(c.propertyBindings),
      ),
      context: 'Indicator',
    );

SuperIndicatorConfig _readIndicatorStateLeaf(Object? value) =>
    ComponentStateHelpers.readStateLeaf(
      value,
      fromJson: SuperIndicatorConfig.fromJson,
      toLeaf: _indicatorStateLeaf,
      context: 'Indicator',
    );
