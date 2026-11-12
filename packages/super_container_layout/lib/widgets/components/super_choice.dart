/// Composant de sélection de valeur parmi une liste de choix ([SuperChoice]).
///
/// Applique les options de [SuperChoiceConfig] (`SegmentedButton`, `DropdownButton`,
/// `RadioListTile`, `FilterChip`, `CheckboxListTile`, `SearchAnchor`), résout
/// les options statiques ou liées à un tableau de repository JSON, et s'intègre
/// au mode édition comme au mode lecture.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/json_text_binding.dart';
import '../../models/super_choice_config.dart';
import '../../models/super_value_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../theme/theme_color.dart';

/// Alias orthographique demandé (`SuperChoise`).
typedef SuperChoise = SuperChoice;

/// Widget de sélection ou d'affichage de choix partagé entre [SuperValue]
/// et l'aperçu isolé de l'éditeur.
class SuperChoice extends StatefulWidget {
  const SuperChoice({
    required this.config,
    required this.controller,
    this.inputKey,
    this.style,
    this.onChanged,
    this.enabled,
    this.readOnly,
    this.bindingError,
    this.focusNode,
    super.key,
  });

  final SuperValueConfig config;
  final TextEditingController controller;
  final Key? inputKey;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final bool? enabled;
  final bool? readOnly;
  final String? bindingError;
  final FocusNode? focusNode;

  /// Formate la valeur courante [rawText] en utilisant les libellés des [options].
  static String formatDisplayText({
    required String rawText,
    required SuperValueConfig config,
    List<SuperChoiceOption>? resolvedOptions,
  }) {
    final options = resolvedOptions ?? config.choice.options;
    final byValue = <String, String>{
      for (final opt in options) opt.value: opt.effectiveLabel,
    };
    if (config.choice.variant.isMultiple) {
      final values = SuperChoiceConfig.parseSelectedValues(rawText);
      if (values.isEmpty) return config.placeholder;
      return values.map((v) => byValue[v] ?? v).join(', ');
    }
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return config.placeholder;
    return byValue[trimmed] ?? trimmed;
  }

  @override
  State<SuperChoice> createState() => _SuperChoiceState();
}

class _SuperChoiceState extends State<SuperChoice> {
  final SearchController _searchController = SearchController();
  JsonTextBinding? _requestedOptionsBinding;
  JsonRepositoryStore? _requestedStore;
  String? _requestedResolveError;
  bool _requestedPlaceholder = false;
  int _optionsGeneration = 0;
  List<SuperChoiceOption>? _dynamicOptions;
  String? _optionsError;
  List<JsonArrayBinding> _selections = const [];

  @override
  void dispose() {
    _listenSelections(const []);
    _requestedStore?.removeListener(_onStoreChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _listenSelections(List<JsonArrayBinding> selections) {
    if (listEquals(_selections, selections)) return;
    for (final selection in _selections) {
      selection.removeListener(_onSelectionChanged);
    }
    _selections = selections;
    for (final selection in selections) {
      selection.addListener(_onSelectionChanged);
    }
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _onStoreChanged() {
    _reloadDynamicOptions();
  }

  void _observeOptionsBinding(
    SuperChoiceConfig choice,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final rawBinding = choice.optionsBinding;
    if (rawBinding == null) {
      _listenSelections(const []);
      if (_requestedStore != null) {
        _requestedStore!.removeListener(_onStoreChanged);
        _requestedStore = null;
      }
      _requestedOptionsBinding = null;
      _requestedResolveError = null;
      _requestedPlaceholder = false;
      _dynamicOptions = null;
      _optionsError = null;
      return;
    }

    JsonTextBinding? resolvedBinding;
    String? resolveError;
    var placeholder = false;
    var selections = const <JsonArrayBinding>[];

    if (scope?.placeholder ?? false) {
      placeholder = true;
    } else {
      try {
        final resolved = JsonListScope.resolveSelected(
          rawBinding,
          scope,
          store,
        );
        resolvedBinding = resolved.binding;
        placeholder = resolved.binding == null;
        selections = resolved.arrays;
      } on FormatException catch (error) {
        resolveError = error.message;
      }
    }

    _listenSelections(selections);
    if (_requestedStore != store) {
      _requestedStore?.removeListener(_onStoreChanged);
      _requestedStore = store;
      _requestedStore?.addListener(_onStoreChanged);
    }

    if (_requestedOptionsBinding == resolvedBinding &&
        _requestedResolveError == resolveError &&
        _requestedPlaceholder == placeholder) {
      return;
    }

    _requestedOptionsBinding = resolvedBinding;
    _requestedResolveError = resolveError;
    _requestedPlaceholder = placeholder;

    if (resolveError != null) {
      _dynamicOptions = const [];
      _optionsError = resolveError;
      return;
    }
    if (placeholder || resolvedBinding == null) {
      _dynamicOptions = const [];
      _optionsError = null;
      return;
    }
    if (store == null) {
      _dynamicOptions = const [];
      _optionsError = 'Service de repositories indisponible.';
      return;
    }

    final cached = store.peekArray(
      resolvedBinding.repositoryId!,
      resolvedBinding.path,
    );
    if (cached != null) {
      _dynamicOptions = choice.extractOptionsFromJsonArray(cached);
      _optionsError = null;
    }

    _reloadDynamicOptions();
  }

  void _reloadDynamicOptions() {
    final resolved = _requestedOptionsBinding;
    final store = _requestedStore;
    if (resolved == null || store == null) return;
    final generation = ++_optionsGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _optionsGeneration) return;
      try {
        final array = await store.readArray(
          resolved.repositoryId!,
          resolved.path,
        );
        if (!mounted || generation != _optionsGeneration) return;
        final extracted = widget.config.choice.extractOptionsFromJsonArray(
          array,
        );
        if (!listEquals(_dynamicOptions, extracted) || _optionsError != null) {
          setState(() {
            _dynamicOptions = extracted;
            _optionsError = null;
          });
        }
      } on FormatException catch (error) {
        if (!mounted || generation != _optionsGeneration) return;
        setState(() {
          _dynamicOptions = const [];
          _optionsError = error.message;
        });
      } on FileSystemException {
        if (!mounted || generation != _optionsGeneration) return;
        setState(() {
          _dynamicOptions = const [];
          _optionsError = 'Impossible de lire les options du repository.';
        });
      }
    });
  }

  List<SuperChoiceOption> _resolveOptions(SuperChoiceConfig choice) {
    if (choice.optionsBinding != null) {
      return _dynamicOptions ?? choice.options;
    }
    return choice.options;
  }

  void _setSingleValue(String nextValue) {
    if (widget.controller.text == nextValue) return;
    widget.controller.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
    widget.onChanged?.call(nextValue);
  }

  void _toggleMultiValue(
    String optionValue,
    bool selected,
    List<SuperChoiceOption> availableOptions,
  ) {
    final current = SuperChoiceConfig.parseSelectedValues(
      widget.controller.text,
    ).toSet();
    if (selected) {
      current.add(optionValue);
    } else {
      current.remove(optionValue);
    }
    final ordered = <String>[
      for (final opt in availableOptions)
        if (current.remove(opt.value)) opt.value,
      ...current,
    ];
    final encoded = SuperChoiceConfig.encodeSelectedValues(ordered);
    if (widget.controller.text == encoded) return;
    widget.controller.value = TextEditingValue(
      text: encoded,
      selection: TextSelection.collapsed(offset: encoded.length),
    );
    widget.onChanged?.call(encoded);
  }

  InputBorder _buildBorder(
    Color color,
    double? width,
    double? radius, {
    bool outlined = true,
  }) {
    final side = BorderSide(color: color, width: width ?? 1.0);
    final borderRadius = BorderRadius.circular(radius ?? 8.0);
    return outlined
        ? OutlineInputBorder(borderSide: side, borderRadius: borderRadius)
        : UnderlineInputBorder(borderSide: side, borderRadius: borderRadius);
  }

  InputDecoration _buildDecoration({
    required BuildContext context,
    required SuperChoiceConfig choice,
    required bool enabled,
    required String? errorText,
    required Color? fillColor,
    required Color? borderColor,
    bool showBorder = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hasCustomBorder =
        showBorder ||
        choice.borderColor != null ||
        choice.borderWidth != null ||
        choice.radius != null;
    final effectiveBorderColor =
        borderColor ??
        (errorText != null ? scheme.error : scheme.outlineVariant);
    final border = hasCustomBorder
        ? _buildBorder(
            effectiveBorderColor,
            choice.borderWidth,
            choice.radius,
          )
        : InputBorder.none;
    return InputDecoration(
      labelText: widget.config.label.isEmpty ? null : widget.config.label,
      helperText: choice.helperText.isEmpty ? null : choice.helperText,
      errorText: errorText,
      enabled: enabled,
      isDense: choice.dense ?? true,
      filled: fillColor != null,
      fillColor: fillColor,
      border: border,
      enabledBorder: border,
      disabledBorder: hasCustomBorder
          ? _buildBorder(
              effectiveBorderColor.withValues(alpha: 0.38),
              choice.borderWidth,
              choice.radius,
            )
          : InputBorder.none,
      errorBorder: hasCustomBorder
          ? _buildBorder(scheme.error, choice.borderWidth, choice.radius)
          : InputBorder.none,
      contentPadding: hasCustomBorder || fillColor != null
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          : EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repositories = JsonRepositoryScope.maybeOf(context);
    final listScope = JsonListScope.maybeOf(context);
    final config = widget.config;
    final source = config.choice;
    _observeOptionsBinding(source, listScope, repositories);

    final scheme = Theme.of(context).colorScheme;
    final fillColor = resolveOptionalThemeColor(source.fillColor, scheme);
    final selectedColor = resolveOptionalThemeColor(
      source.selectedColor,
      scheme,
    );
    final borderColor = resolveOptionalThemeColor(source.borderColor, scheme);
    final enabled = widget.enabled ?? config.enabled;
    final readOnly = widget.readOnly ?? config.readOnly;
    final interactive =
        config.mode == SuperValueMode.input && enabled && !readOnly;
    final errorText =
        widget.bindingError ??
        _optionsError ??
        (source.errorText.isEmpty ? null : source.errorText);
    final resolvedOptions = _resolveOptions(source);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        if (config.mode == SuperValueMode.display) {
          final displayStr = SuperChoice.formatDisplayText(
            rawText: value.text,
            config: config,
            resolvedOptions: resolvedOptions,
          );
          final displayWidget = Text(
            displayStr,
            key: widget.inputKey,
            style: widget.style,
            textAlign: config.textAlign,
            maxLines: config.maxLines,
            overflow: TextOverflow.ellipsis,
          );
          if (config.label.isEmpty &&
              source.helperText.isEmpty &&
              errorText == null) {
            return displayWidget;
          }
          return InputDecorator(
            decoration: _buildDecoration(
              context: context,
              choice: source,
              enabled: enabled,
              errorText: errorText,
              fillColor: fillColor,
              borderColor: borderColor,
            ),
            child: displayWidget,
          );
        }

        final control = switch (source.variant) {
          ChoiceVariant.segmented => _buildSegmented(
            context: context,
            choice: source,
            options: resolvedOptions,
            currentText: value.text,
            interactive: interactive,
            enabled: enabled,
            errorText: errorText,
            fillColor: fillColor,
            selectedColor: selectedColor,
            borderColor: borderColor,
          ),
          ChoiceVariant.dropdown => _buildDropdown(
            context: context,
            choice: source,
            options: resolvedOptions,
            currentText: value.text,
            interactive: interactive,
            enabled: enabled,
            errorText: errorText,
            fillColor: fillColor,
            borderColor: borderColor,
          ),
          ChoiceVariant.radio => _buildRadioList(
            context: context,
            choice: source,
            options: resolvedOptions,
            currentText: value.text,
            interactive: interactive,
            enabled: enabled,
            errorText: errorText,
            fillColor: fillColor,
            selectedColor: selectedColor,
            borderColor: borderColor,
          ),
          ChoiceVariant.filterChip => _buildFilterChips(
            context: context,
            choice: source,
            options: resolvedOptions,
            currentText: value.text,
            interactive: interactive,
            enabled: enabled,
            errorText: errorText,
            fillColor: fillColor,
            selectedColor: selectedColor,
            borderColor: borderColor,
          ),
          ChoiceVariant.checkboxList => _buildCheckboxList(
            context: context,
            choice: source,
            options: resolvedOptions,
            currentText: value.text,
            interactive: interactive,
            enabled: enabled,
            errorText: errorText,
            fillColor: fillColor,
            selectedColor: selectedColor,
            borderColor: borderColor,
          ),
          ChoiceVariant.searchAnchor => _buildSearchAnchor(
            context: context,
            choice: source,
            options: resolvedOptions,
            currentText: value.text,
            interactive: interactive,
            enabled: enabled,
            errorText: errorText,
            fillColor: fillColor,
            selectedColor: selectedColor,
            borderColor: borderColor,
          ),
        };

        return Focus(
          focusNode: widget.focusNode,
          canRequestFocus: false,
          child: KeyedSubtree(
            key: widget.inputKey,
            child: control,
          ),
        );
      },
    );
  }

  Widget _wrapWithDecoratorIfNeeded({
    required BuildContext context,
    required SuperChoiceConfig choice,
    required bool enabled,
    required String? errorText,
    required Color? fillColor,
    required Color? borderColor,
    required Widget child,
    bool showBorder = false,
  }) {
    if (widget.config.label.isEmpty &&
        choice.helperText.isEmpty &&
        errorText == null &&
        !showBorder &&
        fillColor == null &&
        borderColor == null) {
      return child;
    }
    return InputDecorator(
      decoration: _buildDecoration(
        context: context,
        choice: choice,
        enabled: enabled,
        errorText: errorText,
        fillColor: fillColor,
        borderColor: borderColor,
        showBorder: showBorder,
      ),
      child: child,
    );
  }

  Widget _buildSegmented({
    required BuildContext context,
    required SuperChoiceConfig choice,
    required List<SuperChoiceOption> options,
    required String currentText,
    required bool interactive,
    required bool enabled,
    required String? errorText,
    required Color? fillColor,
    required Color? selectedColor,
    required Color? borderColor,
  }) {
    final effectiveOptions = options.length >= 2
        ? options.take(5).toList()
        : options.length == 1
        ? [
            options.first,
            const SuperChoiceOption(value: '_option_2', label: 'Option 2'),
          ]
        : SuperChoiceConfig.defaultFallbackOptions;
    final trimmed = currentText.trim();
    final hasValidSelection = effectiveOptions.any(
      (opt) => opt.value == trimmed,
    );
    final selectedSet = <String>{if (hasValidSelection) trimmed};

    final button = SegmentedButton<String>(
      showSelectedIcon: choice.showCheckmark,
      emptySelectionAllowed: true,
      style: ButtonStyle(
        visualDensity: choice.dense == true
            ? VisualDensity.compact
            : choice.dense == false
            ? VisualDensity.standard
            : null,
        textStyle: widget.style != null
            ? WidgetStatePropertyAll(widget.style)
            : null,
        backgroundColor: fillColor != null || selectedColor != null
            ? WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return selectedColor;
                }
                return fillColor;
              })
            : null,
        side: borderColor != null || choice.borderWidth != null
            ? WidgetStatePropertyAll(
                BorderSide(
                  color:
                      borderColor ?? Theme.of(context).colorScheme.outline,
                  width: choice.borderWidth ?? 1.0,
                ),
              )
            : null,
        shape: choice.radius != null
            ? WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(choice.radius!),
                ),
              )
            : null,
      ),
      segments: [
        for (final option in effectiveOptions)
          ButtonSegment<String>(
            value: option.value,
            label: Text(
              option.effectiveLabel,
              style: widget.style,
              overflow: TextOverflow.ellipsis,
            ),
            icon: option.iconData != null ? Icon(option.iconData) : null,
          ),
      ],
      selected: selectedSet,
      onSelectionChanged: interactive && options.isNotEmpty
          ? (next) {
              if (next.isEmpty) {
                if (choice.allowEmpty) _setSingleValue('');
              } else {
                _setSingleValue(next.first);
              }
            }
          : null,
    );

    return _wrapWithDecoratorIfNeeded(
      context: context,
      choice: choice,
      enabled: enabled,
      errorText: errorText,
      fillColor: null,
      borderColor: null,
      child: button,
    );
  }

  Widget _buildDropdown({
    required BuildContext context,
    required SuperChoiceConfig choice,
    required List<SuperChoiceOption> options,
    required String currentText,
    required bool interactive,
    required bool enabled,
    required String? errorText,
    required Color? fillColor,
    required Color? borderColor,
  }) {
    final trimmed = currentText.trim();
    final hasMatch = options.any((opt) => opt.value == trimmed);
    final effectiveValue = hasMatch
        ? trimmed
        : (choice.allowEmpty && trimmed.isEmpty ? '' : null);
    final decoration = _buildDecoration(
      context: context,
      choice: choice,
      enabled: enabled,
      errorText: errorText,
      fillColor: fillColor,
      borderColor: borderColor,
      showBorder: true,
    );

    return InputDecorator(
      decoration: decoration,
      isEmpty: effectiveValue == null || effectiveValue.isEmpty,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveValue,
          isExpanded: true,
          isDense: choice.dense ?? true,
          style: widget.style ?? Theme.of(context).textTheme.bodyMedium,
          hint: widget.config.placeholder.isNotEmpty
              ? Text(
                  widget.config.placeholder,
                  style: widget.style,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          items: [
            if (choice.allowEmpty)
              DropdownMenuItem<String>(
                value: '',
                child: Text(
                  widget.config.placeholder.isNotEmpty
                      ? widget.config.placeholder
                      : 'Aucun',
                  style: widget.style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            for (final option in options)
              DropdownMenuItem<String>(
                value: option.value,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (option.iconData != null) ...[
                      Icon(option.iconData, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        option.effectiveLabel,
                        style: widget.style,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: interactive && options.isNotEmpty
              ? (next) => _setSingleValue(next ?? '')
              : null,
        ),
      ),
    );
  }

  Widget _buildRadioList({
    required BuildContext context,
    required SuperChoiceConfig choice,
    required List<SuperChoiceOption> options,
    required String currentText,
    required bool interactive,
    required bool enabled,
    required String? errorText,
    required Color? fillColor,
    required Color? selectedColor,
    required Color? borderColor,
  }) {
    final effectiveOptions = options.isNotEmpty
        ? options
        : SuperChoiceConfig.defaultFallbackOptions;
    final trimmed = currentText.trim();
    final tiles = [
      for (final option in effectiveOptions)
        RadioListTile<String>(
          key: ValueKey('super-choice-radio-${option.value}'),
          value: option.value,
          // ignore: deprecated_member_use
          groupValue: trimmed,
          toggleable: choice.allowEmpty,
          dense: choice.dense ?? true,
          visualDensity: choice.dense == true ? VisualDensity.compact : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          activeColor: selectedColor,
          tileColor: fillColor,
          shape: choice.radius != null
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(choice.radius!),
                )
              : null,
          secondary: option.iconData != null ? Icon(option.iconData) : null,
          title: Text(
            option.effectiveLabel,
            style: widget.style,
            overflow: TextOverflow.ellipsis,
          ),
          // ignore: deprecated_member_use
          onChanged: interactive && options.isNotEmpty
              ? (next) => _setSingleValue(next ?? '')
              : null,
        ),
    ];

    final listBody = choice.direction == Axis.horizontal
        ? Wrap(
            spacing: choice.spacing,
            runSpacing: choice.spacing,
            children: [
              for (final tile in tiles)
                 IntrinsicWidth(child: tile),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: tiles,
          );

    return _wrapWithDecoratorIfNeeded(
      context: context,
      choice: choice,
      enabled: enabled,
      errorText: errorText,
      fillColor: fillColor,
      borderColor: borderColor,
      child: listBody,
    );
  }

  Widget _buildFilterChips({
    required BuildContext context,
    required SuperChoiceConfig choice,
    required List<SuperChoiceOption> options,
    required String currentText,
    required bool interactive,
    required bool enabled,
    required String? errorText,
    required Color? fillColor,
    required Color? selectedColor,
    required Color? borderColor,
  }) {
    final effectiveOptions = options.isNotEmpty
        ? options
        : SuperChoiceConfig.defaultFallbackOptions;
    final selectedSet = SuperChoiceConfig.parseSelectedValues(
      currentText,
    ).toSet();

    final chips = [
      for (final option in effectiveOptions)
        FilterChip(
          key: ValueKey('super-choice-chip-${option.value}'),
          selected: selectedSet.contains(option.value),
          showCheckmark: choice.showCheckmark,
          visualDensity: choice.dense == true ? VisualDensity.compact : null,
          backgroundColor: fillColor,
          selectedColor: selectedColor,
          side: borderColor != null || choice.borderWidth != null
              ? BorderSide(
                  color:
                      borderColor ?? Theme.of(context).colorScheme.outline,
                  width: choice.borderWidth ?? 1.0,
                )
              : null,
          shape: choice.radius != null
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(choice.radius!),
                )
              : null,
          avatar: option.iconData != null
              ? Icon(option.iconData, size: 16)
              : null,
          label: Text(option.effectiveLabel, style: widget.style),
          onSelected: interactive && options.isNotEmpty
              ? (selected) =>
                    _toggleMultiValue(option.value, selected, options)
              : null,
        ),
    ];

    final body = choice.direction == Axis.vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) SizedBox(height: choice.spacing),
                chips[i],
              ],
            ],
          )
        : Wrap(
            spacing: choice.spacing,
            runSpacing: choice.spacing,
            children: chips,
          );

    return _wrapWithDecoratorIfNeeded(
      context: context,
      choice: choice,
      enabled: enabled,
      errorText: errorText,
      fillColor: null,
      borderColor: null,
      child: body,
    );
  }

  Widget _buildCheckboxList({
    required BuildContext context,
    required SuperChoiceConfig choice,
    required List<SuperChoiceOption> options,
    required String currentText,
    required bool interactive,
    required bool enabled,
    required String? errorText,
    required Color? fillColor,
    required Color? selectedColor,
    required Color? borderColor,
  }) {
    final effectiveOptions = options.isNotEmpty
        ? options
        : SuperChoiceConfig.defaultFallbackOptions;
    final selectedSet = SuperChoiceConfig.parseSelectedValues(
      currentText,
    ).toSet();

    final tiles = [
      for (final option in effectiveOptions)
        CheckboxListTile(
          key: ValueKey('super-choice-checkbox-${option.value}'),
          value: selectedSet.contains(option.value),
          controlAffinity: ListTileControlAffinity.leading,
          dense: choice.dense ?? true,
          visualDensity: choice.dense == true ? VisualDensity.compact : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          activeColor: selectedColor,
          tileColor: fillColor,
          shape: choice.radius != null
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(choice.radius!),
                )
              : null,
          secondary: option.iconData != null ? Icon(option.iconData) : null,
          title: Text(
            option.effectiveLabel,
            style: widget.style,
            overflow: TextOverflow.ellipsis,
          ),
          onChanged: interactive && options.isNotEmpty
              ? (selected) => _toggleMultiValue(
                  option.value,
                  selected ?? false,
                  options,
                )
              : null,
        ),
    ];

    final listBody = choice.direction == Axis.horizontal
        ? Wrap(
            spacing: choice.spacing,
            runSpacing: choice.spacing,
            children: [
              for (final tile in tiles) IntrinsicWidth(child: tile),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: tiles,
          );

    return _wrapWithDecoratorIfNeeded(
      context: context,
      choice: choice,
      enabled: enabled,
      errorText: errorText,
      fillColor: fillColor,
      borderColor: borderColor,
      child: listBody,
    );
  }

  Widget _buildSearchAnchor({
    required BuildContext context,
    required SuperChoiceConfig choice,
    required List<SuperChoiceOption> options,
    required String currentText,
    required bool interactive,
    required bool enabled,
    required String? errorText,
    required Color? fillColor,
    required Color? selectedColor,
    required Color? borderColor,
  }) {
    final trimmed = currentText.trim();
    final selectedOption = options
        .where((opt) => opt.value == trimmed)
        .firstOrNull;
    final displayLabel = selectedOption?.effectiveLabel ?? trimmed;
    final hasValue = displayLabel.isNotEmpty;
    final hint = choice.searchHint.isNotEmpty
        ? choice.searchHint
        : widget.config.placeholder.isNotEmpty
        ? widget.config.placeholder
        : 'Rechercher…';

    return SearchAnchor(
      searchController: _searchController,
      viewHintText: hint,
      builder: (context, controller) {
        final decoration = _buildDecoration(
          context: context,
          choice: choice,
          enabled: enabled,
          errorText: errorText,
          fillColor: fillColor,
          borderColor: borderColor,
          showBorder: true,
        );
        return InkWell(
          key: const ValueKey('super-choice-search-trigger'),
          borderRadius: BorderRadius.circular(choice.radius ?? 8.0),
          onTap: interactive && options.isNotEmpty
              ? () {
                  controller.text = '';
                  controller.openView();
                }
              : null,
          child: InputDecorator(
            decoration: decoration.copyWith(
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (choice.allowEmpty && hasValue && interactive)
                    IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => _setSingleValue(''),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.search, size: 20),
                  ),
                ],
              ),
            ),
            isEmpty: !hasValue && widget.config.placeholder.isEmpty,
            child: Row(
              children: [
                if (selectedOption?.iconData != null) ...[
                  Icon(selectedOption!.iconData, size: 18),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    hasValue
                        ? displayLabel
                        : (widget.config.placeholder.isNotEmpty
                              ? widget.config.placeholder
                              : hint),
                    style: hasValue
                        ? widget.style
                        : (widget.style ??
                                  Theme.of(context).textTheme.bodyMedium)
                              ?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      suggestionsBuilder: (context, controller) {
        final query = controller.text.trim().toLowerCase();
        final filtered = query.isEmpty
            ? options
            : options
                  .where(
                    (opt) =>
                        opt.effectiveLabel.toLowerCase().contains(query) ||
                        opt.value.toLowerCase().contains(query),
                  )
                  .toList();
        return [
          if (choice.allowEmpty)
            ListTile(
              leading: const Icon(Icons.clear),
              title: Text(
                widget.config.placeholder.isNotEmpty
                    ? widget.config.placeholder
                    : 'Aucun',
              ),
              selected: trimmed.isEmpty,
              onTap: () {
                controller.closeView('');
                _setSingleValue('');
              },
            ),
          for (final option in filtered)
            ListTile(
              key: ValueKey('super-choice-search-item-${option.value}'),
              leading: option.iconData != null
                  ? Icon(option.iconData)
                  : null,
              title: Text(option.effectiveLabel),
              subtitle:
                  option.label.isNotEmpty && option.label != option.value
                  ? Text(option.value)
                  : null,
              selected: option.value == trimmed,
              selectedTileColor: selectedColor?.withValues(alpha: 0.16),
              trailing: option.value == trimmed
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                controller.closeView(option.effectiveLabel);
                _setSingleValue(option.value);
              },
            ),
        ];
      },
    );
  }
}
