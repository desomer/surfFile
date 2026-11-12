/// Générateur de code Dart dédié au composant [SuperValue] (`SuperValueConfig`).
library;

import '../../../models/super_choice_config.dart';
import '../../../models/super_text_field_config.dart';
import '../../../models/super_value_config.dart';
import '../dart_code_generator.dart';

/// Classe de génération de code Dart dédiée à [SuperValue] (`SuperValueConfig`).
class SuperValueDartGenerator extends ComponentDartGenerator {
  const SuperValueDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperValueConfig>(id) ??
        const SuperValueConfig();
    final behaviors = context.appearance.behaviorsFor(id);
    final isDynamic = context.isDynamicInstanceId(id);
    final canWidgetBeConst =
        !isDynamic && behaviors.isEmpty && config.states == null;

    final args = <String, String>{
      'id': context.formatInstanceId(id),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (config != const SuperValueConfig())
        'config': formatConfig(
          context,
          config,
          indent: indent + 2,
          includeConst: !canWidgetBeConst && config.states == null,
        ),
    };

    final prefix = canWidgetBeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperValue',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  /// Formate un [SuperValueConfig] en omettant les valeurs par défaut.
  static String formatConfig(
    DartCodegenContext context,
    SuperValueConfig config, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = SuperValueConfig();
    final canBeConst = includeConst && config.states == null;
    final args = <String, String>{
      if (config.mode != d.mode) 'mode': 'SuperValueMode.${config.mode.name}',
      if (config.kind != d.kind) 'kind': 'SuperValueKind.${config.kind.name}',
      if (config.initialText != d.initialText)
        'initialText': context.formatString(config.initialText),
      if (config.initialBool != d.initialBool)
        'initialBool': '${config.initialBool}',
      if (config.label != d.label) 'label': context.formatString(config.label),
      if (config.placeholder != d.placeholder)
        'placeholder': context.formatString(config.placeholder),
      if (config.enabled != d.enabled) 'enabled': '${config.enabled}',
      if (config.readOnly != d.readOnly) 'readOnly': '${config.readOnly}',
      if (config.obscureText != d.obscureText)
        'obscureText': '${config.obscureText}',
      if (config.minLines != d.minLines) 'minLines': '${config.minLines}',
      if (config.maxLines != d.maxLines) 'maxLines': '${config.maxLines}',
      if (config.fontFamily != null)
        'fontFamily': context.formatString(config.fontFamily!),
      if (config.fontSize != null)
        'fontSize': context.formatNum(config.fontSize!),
      if (config.fontWeight != null)
        'fontWeight': context.formatFontWeight(config.fontWeight!),
      if (config.italic != null) 'italic': '${config.italic}',
      if (config.color != null)
        'color': context.formatColor(config.color!, includeConst: !canBeConst),
      if (config.textAlign != d.textAlign)
        'textAlign': context.formatTextAlign(config.textAlign),
      if (config.lineHeight != null)
        'lineHeight': context.formatNum(config.lineHeight!),
      if (config.letterSpacing != null)
        'letterSpacing': context.formatNum(config.letterSpacing!),
      if (config.binding != null)
        'binding': context.formatBinding(
          config.binding!,
          indent: indent + 2,
          includeConst: !canBeConst && config.states != null,
        ),
      if (config.propertyBindings.isNotEmpty)
        'propertyBindings': context.formatPropertyBindings(
          'SuperValueProperty',
          config.propertyBindings,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (config.field != d.field)
        'field': _formatTextFieldConfig(
          context,
          config.field,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (config.choice != d.choice)
        'choice': _formatChoiceConfig(
          context,
          config.choice,
          indent: indent + 2,
          includeConst: !canBeConst,
        ),
      if (config.states != null)
        'states': _formatValueStates(
          context,
          config.states!,
          indent: indent + 2,
        ),
    };
    final prefix = canBeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperValueConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: args.length > 1,
    );
  }

  static String _formatTextFieldConfig(
    DartCodegenContext context,
    SuperTextFieldConfig field, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = SuperTextFieldConfig();
    final args = <String, String>{
      if (field.variant != d.variant)
        'variant': 'TextFieldVariant.${field.variant.name}',
      if (field.fillColor != null)
        'fillColor': context.formatColor(field.fillColor!),
      if (field.focusFillColor != null)
        'focusFillColor': context.formatColor(field.focusFillColor!),
      if (field.disabledFillColor != null)
        'disabledFillColor': context.formatColor(field.disabledFillColor!),
      if (field.errorFillColor != null)
        'errorFillColor': context.formatColor(field.errorFillColor!),
      if (field.borderColor != null)
        'borderColor': context.formatColor(field.borderColor!),
      if (field.focusBorderColor != null)
        'focusBorderColor': context.formatColor(field.focusBorderColor!),
      if (field.disabledBorderColor != null)
        'disabledBorderColor': context.formatColor(field.disabledBorderColor!),
      if (field.errorBorderColor != null)
        'errorBorderColor': context.formatColor(field.errorBorderColor!),
      if (field.radius != null) 'radius': context.formatNum(field.radius!),
      if (field.borderWidth != null)
        'borderWidth': context.formatNum(field.borderWidth!),
      if (field.horizontalPadding != null)
        'horizontalPadding': context.formatNum(field.horizontalPadding!),
      if (field.verticalPadding != null)
        'verticalPadding': context.formatNum(field.verticalPadding!),
      if (field.dense != null) 'dense': '${field.dense}',
      if (field.prefixText != d.prefixText)
        'prefixText': context.formatString(field.prefixText),
      if (field.suffixText != d.suffixText)
        'suffixText': context.formatString(field.suffixText),
      if (field.prefixIcon != null)
        'prefixIcon': 'TextFieldIcon.${field.prefixIcon!.name}',
      if (field.suffixIcon != null)
        'suffixIcon': 'TextFieldIcon.${field.suffixIcon!.name}',
      if (field.suffix != d.suffix)
        'suffix': 'TextFieldSuffix.${field.suffix.name}',
      if (field.helperText != d.helperText)
        'helperText': context.formatString(field.helperText),
      if (field.errorText != d.errorText)
        'errorText': context.formatString(field.errorText),
      if (field.showCounter != d.showCounter)
        'showCounter': '${field.showCounter}',
      if (field.maxLength != null) 'maxLength': '${field.maxLength}',
      if (field.filter != d.filter)
        'filter': 'TextFieldFilter.${field.filter.name}',
      if (field.pattern != d.pattern)
        'pattern': context.formatString(field.pattern),
      if (field.keyboard != d.keyboard)
        'keyboard': 'TextFieldKeyboard.${field.keyboard.name}',
      if (field.action != d.action)
        'action': 'TextFieldAction.${field.action.name}',
      if (field.capitalization != d.capitalization)
        'capitalization': 'TextCapitalization.${field.capitalization.name}',
      if (field.verticalAlign != d.verticalAlign)
        'verticalAlign': 'TextFieldVerticalAlign.${field.verticalAlign.name}',
      if (field.floatingLabel != null)
        'floatingLabel': 'FloatingLabelBehavior.${field.floatingLabel!.name}',
      if (field.autocorrect != d.autocorrect)
        'autocorrect': '${field.autocorrect}',
      if (field.suggestions != d.suggestions)
        'suggestions': '${field.suggestions}',
    };
    final prefix = includeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperTextFieldConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  static String _formatChoiceOption(
    DartCodegenContext context,
    SuperChoiceOption option, {
    int indent = 0,
    bool includeConst = false,
  }) {
    final args = <String, String>{
      'value': context.formatString(option.value),
      if (option.label.isNotEmpty) 'label': context.formatString(option.label),
      if (option.icon != null) 'icon': context.formatString(option.icon!),
    };
    final prefix = includeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperChoiceOption',
      const [],
      args,
      indent: indent,
    );
  }

  static String _formatChoiceConfig(
    DartCodegenContext context,
    SuperChoiceConfig choice, {
    int indent = 0,
    bool includeConst = false,
  }) {
    const d = SuperChoiceConfig();
    final args = <String, String>{
      if (choice.variant != d.variant)
        'variant': 'ChoiceVariant.${choice.variant.name}',
      if (choice.options.isNotEmpty)
        'options': context.formatList(
          [
            for (final opt in choice.options)
              _formatChoiceOption(
                context,
                opt,
                indent: indent + 4,
                includeConst: false,
              ),
          ],
          indent: indent + 2,
        ),
      if (choice.optionsBinding != null)
        'optionsBinding': context.formatBinding(
          choice.optionsBinding!,
          indent: indent + 2,
          includeConst: false,
        ),
      if (choice.optionValueKey != d.optionValueKey)
        'optionValueKey': context.formatString(choice.optionValueKey),
      if (choice.optionLabelKey != d.optionLabelKey)
        'optionLabelKey': context.formatString(choice.optionLabelKey),
      if (choice.optionIconKey != d.optionIconKey)
        'optionIconKey': context.formatString(choice.optionIconKey),
      if (choice.allowEmpty != d.allowEmpty)
        'allowEmpty': '${choice.allowEmpty}',
      if (choice.dense != null) 'dense': '${choice.dense}',
      if (choice.direction != d.direction)
        'direction': 'Axis.${choice.direction.name}',
      if (choice.spacing != d.spacing)
        'spacing': context.formatNum(choice.spacing),
      if (choice.showCheckmark != d.showCheckmark)
        'showCheckmark': '${choice.showCheckmark}',
      if (choice.searchHint != d.searchHint)
        'searchHint': context.formatString(choice.searchHint),
      if (choice.helperText != d.helperText)
        'helperText': context.formatString(choice.helperText),
      if (choice.errorText != d.errorText)
        'errorText': context.formatString(choice.errorText),
      if (choice.fillColor != null)
        'fillColor': context.formatColor(choice.fillColor!),
      if (choice.selectedColor != null)
        'selectedColor': context.formatColor(choice.selectedColor!),
      if (choice.borderColor != null)
        'borderColor': context.formatColor(choice.borderColor!),
      if (choice.radius != null) 'radius': context.formatNum(choice.radius!),
      if (choice.borderWidth != null)
        'borderWidth': context.formatNum(choice.borderWidth!),
    };
    final prefix = includeConst ? 'const ' : '';
    return context.formatCall(
      '${prefix}SuperChoiceConfig',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }

  static String _formatValueOverride(
    DartCodegenContext context,
    ValueConfigOverride override, {
    int indent = 0,
  }) {
    return context.formatCall(
      'ValueConfigOverride',
      const [],
      {
        'config': formatConfig(
          context,
          override.config,
          indent: indent + 2,
          includeConst: true,
        ),
        if (override.properties.isNotEmpty)
          'properties': context.formatSet(
            override.properties.map((p) => 'ValueStateProperty.${p.name}'),
            indent: indent + 2,
            isConst: true,
          ),
      },
      indent: indent,
      forceMultiline: true,
    );
  }

  static String _formatValueStates(
    DartCodegenContext context,
    ValueConfigStates states, {
    int indent = 0,
  }) {
    final args = <String, String>{
      if (states.binding != null)
        'binding': context.formatBinding(
          states.binding!,
          indent: indent + 2,
          includeConst: true,
        ),
      if (states.named.isNotEmpty)
        'named': context.formatMap(
          {
            for (final entry in states.named.entries)
              context.formatString(entry.key): formatConfig(
                context,
                entry.value,
                indent: indent + 4,
              ),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (states.namedProperties.values.any((s) => s.isNotEmpty))
        'namedProperties': context.formatMap(
          {
            for (final entry in states.namedProperties.entries)
              if (entry.value.isNotEmpty)
                context.formatString(entry.key): context.formatSet(
                  entry.value.map((p) => 'ValueStateProperty.${p.name}'),
                  indent: indent + 4,
                ),
          },
          indent: indent + 2,
          isConst: true,
        ),
      if (states.hover != null)
        'hover': _formatValueOverride(
          context,
          states.hover!,
          indent: indent + 2,
        ),
      if (states.selected != null)
        'selected': _formatValueOverride(
          context,
          states.selected!,
          indent: indent + 2,
        ),
      if (states.automatic.isNotEmpty)
        'automatic': context.formatMap({
          for (final entry in states.automatic.entries)
            'AutomaticState.${entry.key.name}': _formatValueOverride(
              context,
              entry.value,
              indent: indent + 4,
            ),
        }, indent: indent + 2),
    };
    return context.formatCall(
      'ValueConfigStates',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}
