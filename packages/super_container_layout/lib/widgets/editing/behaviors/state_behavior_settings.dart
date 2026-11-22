/// Panneaux de configuration des actions de comportement de visibilité
/// ([SetVisibilityBehaviorSettings]) et d'état interactif
/// ([SetStateBehaviorSettings]), ainsi que le sélecteur de composant cible
/// partagé ([BehaviorTargetComponentSelector]).
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/component_behavior.dart';
import 'behavior_validator_editor.dart';

/// Sélecteur partagé permettant de cibler le composant lui-même (`null`) ou
/// un autre composant par son identifiant technique (`targetComponentId`).
class BehaviorTargetComponentSelector extends StatefulWidget {
  /// Crée un sélecteur de composant cible.
  const BehaviorTargetComponentSelector({
    required this.targetComponentId,
    required this.availableTargets,
    required this.onChanged,
    this.keyPrefix = 'behavior',
    super.key,
  });

  /// Identifiant du composant cible, ou `null` pour le composant courant.
  final String? targetComponentId;

  /// Composants connus dans l'apparence courante.
  final List<ValidatorTargetComponentOption> availableTargets;

  /// Appelé à chaque changement de cible (`null` = soi-même).
  final ValueChanged<String?> onChanged;

  /// Préfixe de clés de widgets pour les tests.
  final String keyPrefix;

  @override
  State<BehaviorTargetComponentSelector> createState() =>
      _BehaviorTargetComponentSelectorState();
}

class _BehaviorTargetComponentSelectorState
    extends State<BehaviorTargetComponentSelector> {
  late bool _targetOther = widget.targetComponentId != null;
  late final TextEditingController _customIdController = TextEditingController(
    text: widget.targetComponentId ?? '',
  );

  @override
  void didUpdateWidget(BehaviorTargetComponentSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetComponentId != widget.targetComponentId) {
      if (widget.targetComponentId == null) {
        _targetOther = false;
      } else {
        _targetOther = true;
        if (_customIdController.text != widget.targetComponentId) {
          _customIdController.text = widget.targetComponentId!;
        }
      }
    }
  }

  @override
  void dispose() {
    _customIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTargets = widget.availableTargets.isNotEmpty;
    final currentId = widget.targetComponentId;
    final knownTarget = hasTargets &&
        currentId != null &&
        widget.availableTargets.any((option) => option.id == currentId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Composant cible',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          key: ValueKey('${widget.keyPrefix}-target-scope'),
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Ce composant'),
              icon: Icon(Icons.my_location_outlined),
            ),
            ButtonSegment(
              value: true,
              label: Text('Autre composant'),
              icon: Icon(Icons.hub_outlined),
            ),
          ],
          selected: {_targetOther},
          onSelectionChanged: (selection) {
            final other = selection.first;
            setState(() => _targetOther = other);
            if (!other) {
              widget.onChanged(null);
            } else {
              final next = _customIdController.text.trim().isNotEmpty
                  ? _customIdController.text.trim()
                  : widget.availableTargets.firstOrNull?.id ?? '';
              _customIdController.text = next;
              widget.onChanged(next);
            }
          },
        ),
        if (_targetOther) ...[
          const SizedBox(height: 10),
          if (hasTargets) ...[
            DropdownButtonFormField<String>(
              key: ValueKey('${widget.keyPrefix}-target-dropdown'),
              initialValue: knownTarget ? currentId : null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Sélectionner un composant',
              ),
              items: [
                for (final option in widget.availableTargets)
                  DropdownMenuItem(
                    value: option.id,
                    child: Row(
                      children: [
                        Icon(option.icon, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            option.displayLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                _customIdController.text = value;
                widget.onChanged(value);
              },
            ),
            const SizedBox(height: 8),
          ],
          TextFormField(
            key: ValueKey('${widget.keyPrefix}-target-id-field'),
            controller: _customIdController,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Identifiant technique du composant cible',
              hintText: 'ex. card-details ou btn-save',
            ),
            onChanged: (value) => widget.onChanged(value.trim()),
          ),
        ],
      ],
    );
  }
}

/// Panneau de paramétrage d'une action [SetVisibilityAction].
class SetVisibilityBehaviorSettings extends StatelessWidget {
  /// Crée le panneau d'édition pour `setVisibility`.
  const SetVisibilityBehaviorSettings({
    required this.mode,
    required this.targetComponentId,
    required this.maintainSize,
    required this.availableTargets,
    required this.onChanged,
    this.keyPrefix = 'behavior',
    super.key,
  });

  final BehaviorVisibilityMode mode;
  final String? targetComponentId;
  final bool maintainSize;
  final List<ValidatorTargetComponentOption> availableTargets;
  final void Function({
    BehaviorVisibilityMode? mode,
    String? targetComponentId,
    bool clearTargetComponentId,
    bool? maintainSize,
  })
  onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showMaintainSize =
        mode == BehaviorVisibilityMode.hide ||
        mode == BehaviorVisibilityMode.toggle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BehaviorTargetComponentSelector(
          targetComponentId: targetComponentId,
          availableTargets: availableTargets,
          keyPrefix: '$keyPrefix-visibility',
          onChanged: (next) => onChanged(
            targetComponentId: next,
            clearTargetComponentId: next == null,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Action de visibilité',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final candidate in BehaviorVisibilityMode.values)
              ChoiceChip(
                key: ValueKey('$keyPrefix-visibility-${candidate.name}'),
                avatar: Icon(candidate.icon, size: 16),
                label: Text(candidate.label),
                selected: mode == candidate,
                onSelected: (_) => onChanged(mode: candidate),
              ),
          ],
        ),
        if (showMaintainSize) ...[
          const SizedBox(height: 10),
          SwitchListTile(
            key: ValueKey('$keyPrefix-visibility-maintain-size'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Conserver l’espace lorsqu’il est masqué'),
            subtitle: const Text(
              'Le composant devient invisible sans provoquer de décalage de mise en page.',
            ),
            value: maintainSize,
            onChanged: (next) => onChanged(maintainSize: next),
          ),
        ],
      ],
    );
  }
}

/// Panneau de paramétrage d'une action [SetStateAction].
class SetStateBehaviorSettings extends StatelessWidget {
  /// Crée le panneau d'édition pour `setState`.
  const SetStateBehaviorSettings({
    required this.state,
    required this.operation,
    required this.value,
    required this.targetComponentId,
    required this.availableTargets,
    required this.onChanged,
    this.keyPrefix = 'behavior',
    super.key,
  });

  final BehaviorInteractiveState state;
  final BehaviorStateOperation operation;
  final bool value;
  final String? targetComponentId;
  final List<ValidatorTargetComponentOption> availableTargets;
  final void Function({
    BehaviorInteractiveState? state,
    BehaviorStateOperation? operation,
    bool? value,
    String? targetComponentId,
    bool clearTargetComponentId,
  })
  onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabledState = state == BehaviorInteractiveState.disabled;

    final choices =
        <(String id, String label, IconData icon, BehaviorStateOperation op, bool val)>[
          (
            'set-true',
            isDisabledState ? 'Désactiver (inactif)' : 'Passer en lecture seule',
            state.icon,
            BehaviorStateOperation.set,
            true,
          ),
          (
            'set-false',
            isDisabledState ? 'Réactiver (interactif)' : 'Autoriser la modification',
            isDisabledState ? Icons.check_circle_outline : Icons.edit_outlined,
            BehaviorStateOperation.set,
            false,
          ),
          (
            'toggle',
            'Basculer',
            Icons.swap_horiz_outlined,
            BehaviorStateOperation.toggle,
            true,
          ),
          (
            'reset',
            'Réinitialiser',
            Icons.restart_alt,
            BehaviorStateOperation.reset,
            true,
          ),
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BehaviorTargetComponentSelector(
          targetComponentId: targetComponentId,
          availableTargets: availableTargets,
          keyPrefix: '$keyPrefix-state',
          onChanged: (next) => onChanged(
            targetComponentId: next,
            clearTargetComponentId: next == null,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'État ciblé',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<BehaviorInteractiveState>(
          key: ValueKey('$keyPrefix-state-kind'),
          segments: [
            for (final candidate in BehaviorInteractiveState.values)
              ButtonSegment(
                value: candidate,
                label: Text(candidate.label),
                icon: Icon(candidate.icon),
              ),
          ],
          selected: {state},
          onSelectionChanged: (selection) =>
              onChanged(state: selection.first),
        ),
        const SizedBox(height: 14),
        Text(
          'Action à appliquer',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              ChoiceChip(
                key: ValueKey('$keyPrefix-state-${choice.$1}'),
                avatar: Icon(choice.$3, size: 16),
                label: Text(choice.$2),
                selected:
                    operation == choice.$4 &&
                    (choice.$4 != BehaviorStateOperation.set ||
                        value == choice.$5),
                onSelected: (_) =>
                    onChanged(operation: choice.$4, value: choice.$5),
              ),
          ],
        ),
      ],
    );
  }
}
