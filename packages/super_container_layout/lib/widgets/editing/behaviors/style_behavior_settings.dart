/// Panneau de configuration d'une action de changement de style runtime
/// ([SetStyleBehaviorSettings]).
///
/// Permet de choisir la cible (`self` ou `targetComponentId`), l'opération
/// (`apply`, `toggle`, `reset`), un état nommé optionnel (`namedState`) et les
/// propriétés visuelles (couleurs `ThemeColor` / hex via [EditorColorTile],
/// bordure, rayon, opacité, élévation, typographie et durée d'animation).
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/component_behavior.dart';
import '../styles/editor_color_tile.dart';
import 'behavior_validator_editor.dart';
import 'state_behavior_settings.dart';

/// Panneau d'édition visuelle pour une [SetStyleAction].
class SetStyleBehaviorSettings extends StatefulWidget {
  /// Crée le panneau de configuration pour `setStyle`.
  const SetStyleBehaviorSettings({
    required this.operation,
    required this.style,
    required this.targetComponentId,
    required this.durationMs,
    required this.availableTargets,
    required this.availableNamedStates,
    required this.onChanged,
    this.keyPrefix = 'behavior',
    super.key,
  });

  final BehaviorStyleOperation operation;
  final BehaviorStylePatch style;
  final String? targetComponentId;
  final int durationMs;
  final List<ValidatorTargetComponentOption> availableTargets;
  final List<String> availableNamedStates;
  final void Function({
    BehaviorStyleOperation? operation,
    BehaviorStylePatch? style,
    String? targetComponentId,
    bool clearTargetComponentId,
    int? durationMs,
  })
  onChanged;
  final String keyPrefix;

  @override
  State<SetStyleBehaviorSettings> createState() =>
      _SetStyleBehaviorSettingsState();
}

class _SetStyleBehaviorSettingsState extends State<SetStyleBehaviorSettings> {
  late final TextEditingController _namedStateController =
      TextEditingController(text: widget.style.namedState ?? '');
  late final TextEditingController _borderWidthController =
      TextEditingController(text: _fmt(widget.style.borderWidth));
  late final TextEditingController _radiusController = TextEditingController(
    text: _fmt(widget.style.radius),
  );
  late final TextEditingController _elevationController = TextEditingController(
    text: _fmt(widget.style.elevation),
  );
  late final TextEditingController _fontSizeController = TextEditingController(
    text: _fmt(widget.style.fontSize),
  );
  late final TextEditingController _durationController = TextEditingController(
    text: widget.durationMs == 0 ? '' : '${widget.durationMs}',
  );

  static String _fmt(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble() ? '${value.round()}' : '$value';
  }

  void _syncController(TextEditingController controller, String expected) {
    if (controller.text != expected) {
      controller.text = expected;
    }
  }

  @override
  void didUpdateWidget(SetStyleBehaviorSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style.namedState != widget.style.namedState) {
      _syncController(_namedStateController, widget.style.namedState ?? '');
    }
    if (oldWidget.style.borderWidth != widget.style.borderWidth) {
      _syncController(_borderWidthController, _fmt(widget.style.borderWidth));
    }
    if (oldWidget.style.radius != widget.style.radius) {
      _syncController(_radiusController, _fmt(widget.style.radius));
    }
    if (oldWidget.style.elevation != widget.style.elevation) {
      _syncController(_elevationController, _fmt(widget.style.elevation));
    }
    if (oldWidget.style.fontSize != widget.style.fontSize) {
      _syncController(_fontSizeController, _fmt(widget.style.fontSize));
    }
    if (oldWidget.durationMs != widget.durationMs) {
      _syncController(
        _durationController,
        widget.durationMs == 0 ? '' : '${widget.durationMs}',
      );
    }
  }

  @override
  void dispose() {
    _namedStateController.dispose();
    _borderWidthController.dispose();
    _radiusController.dispose();
    _elevationController.dispose();
    _fontSizeController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  double? _parseNonNegative(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null || !parsed.isFinite || parsed < 0) return null;
    return parsed;
  }

  double? _parsePositive(String raw) {
    final parsed = _parseNonNegative(raw);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  void _updateStyle(BehaviorStylePatch next) => widget.onChanged(style: next);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = widget.style;
    final isReset = widget.operation == BehaviorStyleOperation.reset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BehaviorTargetComponentSelector(
          targetComponentId: widget.targetComponentId,
          availableTargets: widget.availableTargets,
          keyPrefix: '${widget.keyPrefix}-style',
          onChanged: (next) => widget.onChanged(
            targetComponentId: next,
            clearTargetComponentId: next == null,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Opération de style',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<BehaviorStyleOperation>(
          key: ValueKey('${widget.keyPrefix}-style-operation'),
          segments: [
            for (final op in BehaviorStyleOperation.values)
              ButtonSegment(
                value: op,
                label: Text(op.label),
                icon: Icon(op.icon),
              ),
          ],
          selected: {widget.operation},
          onSelectionChanged: (selection) =>
              widget.onChanged(operation: selection.first),
        ),
        if (!isReset) ...[
          const SizedBox(height: 14),
          Text(
            'État métier nommé (optionnel)',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (widget.availableNamedStates.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in widget.availableNamedStates)
                  ChoiceChip(
                    label: Text(name),
                    selected: style.namedState == name,
                    onSelected: (selected) {
                      final next = selected ? name : null;
                      _namedStateController.text = next ?? '';
                      _updateStyle(style.copyWith(namedState: next));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextFormField(
            key: ValueKey('${widget.keyPrefix}-style-named-state'),
            controller: _namedStateController,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Nom d’état nommé (states.named)',
              hintText: 'ex. danger, actif, valide…',
            ),
            onChanged: (raw) {
              final trimmed = raw.trim();
              _updateStyle(
                style.copyWith(namedState: trimmed.isEmpty ? null : trimmed),
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Couleurs',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          EditorColorTile(
            tileKey: ValueKey('${widget.keyPrefix}-style-bg-color'),
            label: 'Couleur de fond',
            dense: true,
            color: style.backgroundColor,
            emptySubtitle: 'Inchangée',
            onChanged: (color) =>
                _updateStyle(style.copyWith(backgroundColor: color)),
            onClear: style.backgroundColor == null
                ? null
                : () => _updateStyle(style.copyWith(backgroundColor: null)),
          ),
          const SizedBox(height: 6),
          EditorColorTile(
            tileKey: ValueKey('${widget.keyPrefix}-style-fg-color'),
            label: 'Couleur texte / icône',
            dense: true,
            color: style.foregroundColor,
            emptySubtitle: 'Inchangée',
            onChanged: (color) =>
                _updateStyle(style.copyWith(foregroundColor: color)),
            onClear: style.foregroundColor == null
                ? null
                : () => _updateStyle(style.copyWith(foregroundColor: null)),
          ),
          const SizedBox(height: 6),
          EditorColorTile(
            tileKey: ValueKey('${widget.keyPrefix}-style-border-color'),
            label: 'Couleur de bordure',
            dense: true,
            color: style.borderColor,
            emptySubtitle: 'Inchangée',
            onChanged: (color) =>
                _updateStyle(style.copyWith(borderColor: color)),
            onClear: style.borderColor == null
                ? null
                : () => _updateStyle(style.copyWith(borderColor: null)),
          ),
          const SizedBox(height: 14),
          Text(
            'Bordure, coins, élévation & typographie',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 140,
                child: TextFormField(
                  key: ValueKey('${widget.keyPrefix}-style-border-width'),
                  controller: _borderWidthController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Bordure (px)',
                  ),
                  onChanged: (raw) => _updateStyle(
                    style.copyWith(borderWidth: _parseNonNegative(raw)),
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextFormField(
                  key: ValueKey('${widget.keyPrefix}-style-radius'),
                  controller: _radiusController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Rayon (px)',
                  ),
                  onChanged: (raw) => _updateStyle(
                    style.copyWith(radius: _parseNonNegative(raw)),
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextFormField(
                  key: ValueKey('${widget.keyPrefix}-style-elevation'),
                  controller: _elevationController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Élévation',
                  ),
                  onChanged: (raw) => _updateStyle(
                    style.copyWith(elevation: _parseNonNegative(raw)),
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextFormField(
                  key: ValueKey('${widget.keyPrefix}-style-font-size'),
                  controller: _fontSizeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Police (px)',
                  ),
                  onChanged: (raw) => _updateStyle(
                    style.copyWith(fontSize: _parsePositive(raw)),
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<FontWeight?>(
                  key: ValueKey('${widget.keyPrefix}-style-font-weight'),
                  initialValue: style.fontWeight,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Graisse',
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Inchangée')),
                    DropdownMenuItem(
                      value: FontWeight.w300,
                      child: Text('Légère (w300)'),
                    ),
                    DropdownMenuItem(
                      value: FontWeight.w400,
                      child: Text('Normale (w400)'),
                    ),
                    DropdownMenuItem(
                      value: FontWeight.w500,
                      child: Text('Medium (w500)'),
                    ),
                    DropdownMenuItem(
                      value: FontWeight.w600,
                      child: Text('Semi-gras (w600)'),
                    ),
                    DropdownMenuItem(
                      value: FontWeight.w700,
                      child: Text('Gras (w700)'),
                    ),
                    DropdownMenuItem(
                      value: FontWeight.w800,
                      child: Text('Extra-gras (w800)'),
                    ),
                  ],
                  onChanged: (weight) =>
                      _updateStyle(style.copyWith(fontWeight: weight)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                key: ValueKey('${widget.keyPrefix}-style-opacity-toggle'),
                value: style.opacity != null,
                onChanged: (enabled) => _updateStyle(
                  style.copyWith(opacity: enabled == true ? 0.6 : null),
                ),
              ),
              const Text('Modifier l’opacité'),
              if (style.opacity != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${(style.opacity! * 100).round()} %',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          if (style.opacity != null)
            Slider(
              key: ValueKey('${widget.keyPrefix}-style-opacity-slider'),
              value: style.opacity!.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              divisions: 20,
              label: '${(style.opacity! * 100).round()} %',
              onChanged: (val) => _updateStyle(
                style.copyWith(opacity: double.parse(val.toStringAsFixed(2))),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: 180,
            child: TextFormField(
              key: ValueKey('${widget.keyPrefix}-style-duration'),
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Transition (ms)',
                hintText: '0 = instantané',
              ),
              onChanged: (raw) {
                final trimmed = raw.trim();
                final parsed = trimmed.isEmpty ? 0 : int.tryParse(trimmed);
                if (parsed != null && parsed >= 0) {
                  widget.onChanged(durationMs: parsed);
                }
              },
            ),
          ),
          if (style.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Sélectionnez au moins une propriété de style ou un état nommé.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
        ],
      ],
    );
  }
}
