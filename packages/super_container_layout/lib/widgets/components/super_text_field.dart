import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/super_text_config.dart';
import '../../models/super_text_field_config.dart';

/// Shared by the live component and the isolated editor preview.
class SuperTextField extends StatefulWidget {
  const SuperTextField({
    required this.config,
    required this.controller,
    this.inputKey,
    this.style,
    this.onChanged,
    this.enabled,
    this.readOnly,
    this.enableContextMenu = true,
    this.bindingError,
    super.key,
  });

  final SuperTextConfig config;
  final TextEditingController controller;
  final Key? inputKey;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final bool? enabled, readOnly;
  final bool enableContextMenu;
  final String? bindingError;

  @override
  State<SuperTextField> createState() => _SuperTextFieldState();
}

class _SuperTextFieldState extends State<SuperTextField> {
  bool _revealed = false;

  @override
  void didUpdateWidget(SuperTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.config.obscureText != widget.config.obscureText ||
        oldWidget.config.field.suffix != widget.config.field.suffix) {
      _revealed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final field = config.field;
    final enabled = widget.enabled ?? config.enabled;
    final readOnly = widget.readOnly ?? config.readOnly;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).inputDecorationTheme;
    final customizedBorder =
        field.variant != TextFieldVariant.theme ||
        field.radius != null ||
        field.borderWidth != null ||
        field.borderColor != null ||
        field.focusBorderColor != null ||
        field.disabledBorderColor != null ||
        field.errorBorderColor != null;
    InputBorder? border(
      InputBorder? inherited,
      Color color, {
      bool focused = false,
    }) {
      if (!customizedBorder) return null;
      if (field.variant == TextFieldVariant.borderless) return InputBorder.none;
      final side = BorderSide(
        color: color,
        width:
            field.borderWidth ??
            inherited?.borderSide.width ??
            (focused ? 2 : 1),
      );
      final base = inherited ?? theme.border ?? const UnderlineInputBorder();
      final outlined =
          field.variant == TextFieldVariant.outlined ||
          (field.variant == TextFieldVariant.theme &&
              base is OutlineInputBorder);
      final radius = field.radius == null
          ? outlined
                ? base is OutlineInputBorder
                      ? base.borderRadius
                      : BorderRadius.circular(4)
                : base is UnderlineInputBorder
                ? base.borderRadius
                : const BorderRadius.vertical(top: Radius.circular(4))
          : BorderRadius.circular(field.radius!);
      if (field.variant == TextFieldVariant.theme && base == InputBorder.none) {
        return InputBorder.none;
      }
      return outlined
          ? OutlineInputBorder(borderSide: side, borderRadius: radius)
          : UnderlineInputBorder(borderSide: side, borderRadius: radius);
    }

    Color inheritedColor(InputBorder? value, Color fallback) =>
        value?.borderSide.color ?? fallback;
    final normal =
        field.borderColor ??
        inheritedColor(theme.enabledBorder, scheme.onSurfaceVariant);
    final focus =
        field.focusBorderColor ??
        inheritedColor(theme.focusedBorder, scheme.primary);
    final disabled =
        field.disabledBorderColor ??
        inheritedColor(
          theme.disabledBorder,
          scheme.onSurface.withValues(alpha: .12),
        );
    final error =
        field.errorBorderColor ??
        inheritedColor(theme.errorBorder, scheme.error);
    final hasFill = [
      field.fillColor,
      field.focusFillColor,
      field.disabledFillColor,
      field.errorFillColor,
    ].any((value) => value != null);
    final errorText =
        widget.bindingError ??
        (field.errorText.isEmpty ? null : field.errorText);
    final fill = hasFill
        ? WidgetStateColor.resolveWith((states) {
            final fallback = theme.fillColor ?? scheme.surfaceContainerHighest;
            final inherited = WidgetStateProperty.resolveAs<Color>(
              fallback,
              states,
            );
            if (states.contains(WidgetState.disabled)) {
              return field.disabledFillColor ?? field.fillColor ?? inherited;
            }
            if (states.contains(WidgetState.error) || errorText != null) {
              return field.errorFillColor ?? field.fillColor ?? inherited;
            }
            if (states.contains(WidgetState.focused)) {
              return field.focusFillColor ?? field.fillColor ?? inherited;
            }
            return field.fillColor ?? inherited;
          })
        : null;
    final keyboard = switch (field.keyboard) {
      TextFieldKeyboard.automatic => null,
      TextFieldKeyboard.text => TextInputType.text,
      TextFieldKeyboard.multiline => TextInputType.multiline,
      TextFieldKeyboard.email => TextInputType.emailAddress,
      TextFieldKeyboard.phone => TextInputType.phone,
      TextFieldKeyboard.url => TextInputType.url,
      TextFieldKeyboard.number => TextInputType.number,
      TextFieldKeyboard.decimal => const TextInputType.numberWithOptions(
        decimal: true,
      ),
      TextFieldKeyboard.signedDecimal => const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
    };
    final action = switch (field.action) {
      TextFieldAction.automatic => null,
      TextFieldAction.done => TextInputAction.done,
      TextFieldAction.next => TextInputAction.next,
      TextFieldAction.previous => TextInputAction.previous,
      TextFieldAction.search => TextInputAction.search,
      TextFieldAction.send => TextInputAction.send,
      TextFieldAction.go => TextInputAction.go,
      TextFieldAction.newline => TextInputAction.newline,
    };
    final vertical = switch (field.verticalAlign) {
      TextFieldVerticalAlign.automatic => null,
      TextFieldVerticalAlign.top => TextAlignVertical.top,
      TextFieldVerticalAlign.center => TextAlignVertical.center,
      TextFieldVerticalAlign.bottom => TextAlignVertical.bottom,
    };
    Widget? suffix;
    if (field.suffix == TextFieldSuffix.clear) {
      suffix = ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) => IconButton(
          tooltip: 'Effacer',
          onPressed: enabled && !readOnly && value.text.isNotEmpty
              ? () {
                  widget.controller.clear();
                  widget.onChanged?.call('');
                }
              : null,
          icon: const Icon(Icons.clear),
        ),
      );
    } else if (field.suffix == TextFieldSuffix.visibility &&
        config.obscureText) {
      suffix = IconButton(
        tooltip: _revealed
            ? 'Masquer le mot de passe'
            : 'Afficher le mot de passe',
        onPressed: enabled
            ? () => setState(() => _revealed = !_revealed)
            : null,
        icon: Icon(
          _revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      );
    } else if (field.suffix == TextFieldSuffix.decoration &&
        field.suffixIcon != null) {
      suffix = Icon(field.suffixIcon!.data);
    }
    final padding = theme.contentPadding;
    return TextField(
      key: widget.inputKey,
      controller: widget.controller,
      style: widget.style,
      textAlign: config.textAlign,
      textAlignVertical: vertical,
      enabled: enabled,
      readOnly: readOnly,
      contextMenuBuilder: widget.enableContextMenu
          ? const TextField().contextMenuBuilder
          : null,
      obscureText: config.obscureText && !_revealed,
      enableSuggestions: !config.obscureText && field.suggestions,
      autocorrect: !config.obscureText && field.autocorrect,
      minLines: config.minLines,
      maxLines: config.maxLines,
      maxLength: field.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.truncateAfterCompositionEnds,
      inputFormatters: superTextInputFormatters(field),
      keyboardType: keyboard,
      textInputAction: action,
      textCapitalization: field.capitalization,
      buildCounter: field.showCounter
          ? (
              context, {
              required currentLength,
              required isFocused,
              required maxLength,
            }) => Text(
              maxLength == null
                  ? '$currentLength'
                  : '$currentLength / $maxLength',
              semanticsLabel: maxLength == null
                  ? '$currentLength caractères'
                  : '$currentLength caractères sur $maxLength',
            )
          : (
              context, {
              required currentLength,
              required isFocused,
              required maxLength,
            }) => null,
      decoration: InputDecoration(
        labelText: config.label.isEmpty ? null : config.label,
        hintText: config.placeholder.isEmpty ? null : config.placeholder,
        isDense: field.dense ?? true,
        filled: field.variant == TextFieldVariant.filled || hasFill
            ? true
            : null,
        fillColor: fill,
        border: border(theme.border, normal),
        enabledBorder: border(theme.enabledBorder, normal),
        focusedBorder: border(theme.focusedBorder, focus, focused: true),
        disabledBorder: border(theme.disabledBorder, disabled),
        errorBorder: border(theme.errorBorder, error),
        focusedErrorBorder: border(
          theme.focusedErrorBorder,
          field.errorBorderColor ??
              inheritedColor(theme.focusedErrorBorder, scheme.error),
          focused: true,
        ),
        contentPadding:
            field.horizontalPadding == null && field.verticalPadding == null
            ? null
            : EdgeInsets.symmetric(
                horizontal:
                    field.horizontalPadding ??
                    padding?.resolve(Directionality.of(context)).left ??
                    12,
                vertical:
                    field.verticalPadding ??
                    padding?.resolve(Directionality.of(context)).top ??
                    12,
              ),
        prefixText: field.prefixText.isEmpty ? null : field.prefixText,
        suffixText: field.suffixText.isEmpty ? null : field.suffixText,
        prefixIcon: field.prefixIcon == null
            ? null
            : Icon(field.prefixIcon!.data),
        suffixIcon: suffix,
        helperText: field.helperText.isEmpty ? null : field.helperText,
        errorText: errorText,
        errorMaxLines: 3,
        floatingLabelBehavior: field.floatingLabel,
      ),
      onChanged: widget.onChanged,
    );
  }
}

List<TextInputFormatter> superTextInputFormatters(SuperTextFieldConfig config) {
  if (config.filter == TextFieldFilter.none) return const [];
  final TextInputFormatter formatter;
  switch (config.filter) {
    case TextFieldFilter.none:
      return const [];
    case TextFieldFilter.digits:
      formatter = FilteringTextInputFormatter.digitsOnly;
    case TextFieldFilter.letters:
      formatter = FilteringTextInputFormatter.allow(
        RegExp(r"[\p{L}\p{M} '\u2019\u002D]", unicode: true),
      );
    case TextFieldFilter.pattern:
      config.validate();
      formatter = FilteringTextInputFormatter.allow(
        RegExp(config.pattern, unicode: true),
      );
    case TextFieldFilter.decimal:
      formatter = TextInputFormatter.withFunction(
        (oldValue, newValue) =>
            RegExp(r'^[+-]?[0-9]*(\.[0-9]*)?$').hasMatch(newValue.text)
            ? newValue
            : oldValue,
      );
  }
  return [
    TextInputFormatter.withFunction((oldValue, newValue) {
      if (!newValue.composing.isCollapsed) return newValue;
      return formatter.formatEditUpdate(oldValue, newValue);
    }),
  ];
}
