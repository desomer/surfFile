/// Badge numerique ouvrant une saisie contextuelle commune a tous les editeurs.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../models/json_numbers.dart';

/// Valeur cliquable d'un slider, avec validation dans un petit popup ancre.
class EditorNumberField extends StatelessWidget {
  /// Cree un badge ; les limites du slider restent distinctes des limites de saisie.
  const EditorNumberField({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.integer = false,
    this.scale = 1,
    this.unit = '',
    this.label,
    this.allowAboveMax = false,
    this.allowBelowMin = false,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final bool integer;
  final double scale;
  final String unit;
  final String? label;
  final bool allowAboveMax;
  final bool allowBelowMin;

  String get _formatted => (value * scale).toStringAsFixed(integer ? 0 : 2);

  Future<void> _edit(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final next = await showDialog<double>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      builder: (context) => _EditorNumberPopup(field: this, origin: origin),
    );
    if (context.mounted && next != null && next != value) {
      onChanged?.call(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onChanged == null ? null : () => _edit(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              '$_formatted${unit.trim().isEmpty ? '' : ' ${unit.trim()}'}',
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 11,
                color: onChanged == null
                    ? scheme.onSurface.withValues(alpha: .38)
                    : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorNumberPopup extends StatefulWidget {
  const _EditorNumberPopup({required this.field, required this.origin});

  final EditorNumberField field;
  final Offset origin;

  @override
  State<_EditorNumberPopup> createState() => _EditorNumberPopupState();
}

class _EditorNumberPopupState extends State<_EditorNumberPopup> {
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.field._formatted);
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (!mounted || _submitted) return;
    final field = widget.field;
    final entered = double.tryParse(_text.text.trim().replaceAll(',', '.'));
    String? error;
    if (entered == null || !entered.isFinite) {
      error = 'Nombre invalide';
    } else if (field.integer && entered != entered.roundToDouble()) {
      error = 'Entier requis';
    } else if ((!field.allowBelowMin && entered < field.min * field.scale) ||
        (!field.allowAboveMax && entered > field.max * field.scale)) {
      error = 'Valeur hors limites';
    }
    final next = error == null
        ? JsonNumbers.round(entered! / field.scale)
        : null;
    if (next != null &&
        ((!field.allowBelowMin && next < field.min) ||
            (!field.allowAboveMax && next > field.max))) {
      error = 'Valeur non representable avec deux decimales';
    }
    if (error != null) {
      setState(() => _error = error);
      _focus.requestFocus();
      return;
    }
    _submitted = true;
    Navigator.of(context).pop(next);
  }

  void _cancel() {
    _submitted = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = math.min(220.0, math.max(0.0, media.size.width - 16));
    final left = widget.origin.dx
        .clamp(8.0, math.max(8.0, media.size.width - width - 8))
        .toDouble();
    final top = widget.origin.dy
        .clamp(
          media.padding.top + 8,
          math.max(
            media.padding.top + 8,
            media.size.height - media.viewInsets.bottom - 110,
          ),
        )
        .toDouble();
    final field = widget.field;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  autofocus: true,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: !field.integer,
                    signed: field.min < 0 || field.allowBelowMin,
                  ),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: field.label,
                    suffixText: field.unit.trim().isEmpty
                        ? null
                        : field.unit.trim(),
                    errorText: _error,
                    errorMaxLines: 2,
                  ),
                  onSubmitted: (_) => _commit(),
                  onTapOutside: (_) => _commit(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }
}
