/// Éditeur visuel de validateur de comportement ([BehaviorValidatorEditor]) et
/// descripteur de composant ciblable ([ValidatorTargetComponentOption]).
///
/// Permet de configurer un [BehaviorValidator] en mode « Aucune condition »,
/// « Condition simple » ([ValueBehaviorValidator], avec négation optionnelle
/// [NotBehaviorValidator]) ou « Plusieurs conditions (ET / OU) »
/// ([AllBehaviorValidator] / [AnyBehaviorValidator]), avec aperçu français en direct.
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../../models/behaviours/behavior_validator.dart';
import '../../../models/json_text_binding.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../repositories/repository_binding_fields.dart';

/// Option de composant sélectionnable dans l'éditeur de validateur (« Autre composant »).
@immutable
class ValidatorTargetComponentOption {
  /// Crée une option de composant cible pour un validateur.
  const ValidatorTargetComponentOption({
    required this.id,
    required this.label,
    required this.typeLabel,
    required this.icon,
  });

  /// Identifiant technique unique du composant dans `Appearance.components`.
  final String id;

  /// Libellé humain (issu de `slotLabels` ou de la configuration du composant).
  final String label;

  /// Libellé court du type de composant (ex. `Valeur / Champ`, `Tableau`).
  final String typeLabel;

  /// Icône représentative du composant.
  final IconData icon;

  /// Libellé combiné affichant le nom humain et l'identifiant technique.
  String get displayLabel {
    final trimmed = label.trim();
    if (trimmed.isEmpty || trimmed == id) return id;
    return '$trimmed ($id)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidatorTargetComponentOption &&
          other.id == id &&
          other.label == label &&
          other.typeLabel == typeLabel &&
          other.icon == icon;

  @override
  int get hashCode => Object.hash(id, label, typeLabel, icon);
}

enum _ValidatorEditorMode { none, simple, composite }

enum _CompositeCombinator { all, any }

class _SimpleRuleDraft {
  _SimpleRuleDraft({
    this.source = BehaviorValueSource.self,
    this.operator = BehaviorValidatorOperator.isFill,
    String targetComponentId = '',
    this.binding,
    Object? expectedValue,
    this.negated = false,
    this.rawFallback,
  }) : _originalExpectedValue = expectedValue,
       _originalExpectedText = _formatExpectedValue(expectedValue),
       targetController = TextEditingController(text: targetComponentId),
       valueController = TextEditingController(
         text: _formatExpectedValue(expectedValue),
       );

  factory _SimpleRuleDraft.fromValidator(BehaviorValidator validator) {
    var negated = false;
    var current = validator;
    if (current is NotBehaviorValidator) {
      negated = true;
      current = current.validator;
    }
    if (current is ValueBehaviorValidator) {
      return _SimpleRuleDraft(
        source: current.source,
        operator: current.operator,
        targetComponentId: current.targetComponentId ?? '',
        binding: current.binding,
        expectedValue: current.expectedValue,
        negated: negated,
      );
    }
    return _SimpleRuleDraft(rawFallback: validator);
  }

  BehaviorValueSource source;
  BehaviorValidatorOperator operator;
  JsonTextBinding? binding;
  bool negated;

  /// Validateur exotique (ex. composite imbriqué) préservé tel quel s'il ne
  /// correspond pas à une règle simple.
  final BehaviorValidator? rawFallback;

  final Object? _originalExpectedValue;
  final String _originalExpectedText;
  final TextEditingController targetController;
  final TextEditingController valueController;

  void dispose() {
    targetController.dispose();
    valueController.dispose();
  }

  static String _formatExpectedValue(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return jsonEncode(value);
  }

  Object? _parseExpectedValue() {
    final text = valueController.text;
    if (text == _originalExpectedText && _originalExpectedValue != null) {
      return _originalExpectedValue;
    }
    if (operator == BehaviorValidatorOperator.matchesRegex ||
        operator == BehaviorValidatorOperator.startsWith) {
      return text;
    }
    final trimmed = text.trim();
    if (operator == BehaviorValidatorOperator.greaterThan ||
        operator == BehaviorValidatorOperator.lessThan) {
      if (trimmed.isEmpty) return null;
      final asInt = int.tryParse(trimmed);
      if (asInt != null && trimmed == '$asInt') return asInt;
      final asDouble = double.tryParse(trimmed.replaceAll(',', '.'));
      if (asDouble != null && asDouble.isFinite) return asDouble;
      return text;
    }
    if (trimmed.isNotEmpty) {
      final asInt = int.tryParse(trimmed);
      if (asInt != null && trimmed == '$asInt') return asInt;
      final asDouble = double.tryParse(trimmed.replaceAll(',', '.'));
      if (asDouble != null &&
          RegExp(r'^-?\d+(?:[.,]\d+)$').hasMatch(trimmed)) {
        return asDouble;
      }
      if (trimmed == 'true') return true;
      if (trimmed == 'false') return false;
    }
    return text;
  }

  ({BehaviorValidator? validator, String? error}) build() {
    if (rawFallback != null) {
      try {
        rawFallback!.validate();
        return (validator: rawFallback, error: null);
      } on FormatException catch (e) {
        return (validator: null, error: e.message);
      }
    }

    final targetId = targetController.text.trim();
    final base = ValueBehaviorValidator(
      source: source,
      operator: operator,
      targetComponentId: source == BehaviorValueSource.component
          ? targetId
          : null,
      binding: source == BehaviorValueSource.binding ? binding : null,
      expectedValue: operator.requiresValue ? _parseExpectedValue() : null,
    );
    final BehaviorValidator result = negated
        ? NotBehaviorValidator(validator: base)
        : base;
    try {
      result.validate();
      return (validator: result, error: null);
    } on FormatException catch (error) {
      return (validator: null, error: error.message);
    }
  }
}

/// Éditeur complet permettant de créer ou modifier un [BehaviorValidator].
class BehaviorValidatorEditor extends StatefulWidget {
  /// Crée un éditeur de validateur de comportement.
  const BehaviorValidatorEditor({
    required this.validator,
    required this.onChanged,
    this.availableTargets = const [],
    this.store,
    this.listScope,
    this.keyPrefix = 'behavior',
    this.infoBanner,
    super.key,
  });

  /// Validateur courant (`null` signifie « Aucune condition »).
  final BehaviorValidator? validator;

  /// Callback invoqué à chaque modification avec le validateur produit (ou `null`)
  /// et un booléen indiquant si la configuration courante est valide.
  final void Function(BehaviorValidator? validator, bool isValid) onChanged;

  /// Composants disponibles sur la page/apparence pour la source « Autre composant ».
  final List<ValidatorTargetComponentOption> availableTargets;

  /// Store de repositories JSON pour la source « Liaison repository ».
  final JsonRepositoryStore? store;

  /// Contexte de liste englobant pour les liaisons `[?]`.
  final JsonListScope? listScope;

  /// Préfixe utilisé pour les clés de test déterministes.
  final String keyPrefix;

  /// Bannière d'information optionnelle affichée en tête de l'éditeur.
  final String? infoBanner;

  @override
  State<BehaviorValidatorEditor> createState() =>
      _BehaviorValidatorEditorState();
}

class _BehaviorValidatorEditorState extends State<BehaviorValidatorEditor> {
  _ValidatorEditorMode _mode = _ValidatorEditorMode.none;
  _CompositeCombinator _combinator = _CompositeCombinator.all;
  bool _compositeNegated = false;
  late _SimpleRuleDraft _simpleDraft;
  final List<_SimpleRuleDraft> _compositeDrafts = [];
  BehaviorValidator? _lastEmittedValidator;

  @override
  void initState() {
    super.initState();
    _simpleDraft = _SimpleRuleDraft();
    _loadFromValidator(widget.validator);
    _lastEmittedValidator = widget.validator;
  }

  @override
  void didUpdateWidget(covariant BehaviorValidatorEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.validator != oldWidget.validator &&
        widget.validator != _lastEmittedValidator) {
      _disposeDrafts();
      _simpleDraft = _SimpleRuleDraft();
      _loadFromValidator(widget.validator);
      _lastEmittedValidator = widget.validator;
    }
  }

  void _disposeDrafts() {
    _simpleDraft.dispose();
    for (final draft in _compositeDrafts) {
      draft.dispose();
    }
    _compositeDrafts.clear();
  }

  @override
  void dispose() {
    _disposeDrafts();
    super.dispose();
  }

  void _loadFromValidator(BehaviorValidator? validator) {
    _compositeDrafts.clear();
    _compositeNegated = false;

    if (validator == null) {
      _mode = _ValidatorEditorMode.none;
      _compositeDrafts.addAll([_SimpleRuleDraft(), _SimpleRuleDraft()]);
      return;
    }

    var current = validator;
    var outerNegated = false;
    if (current is NotBehaviorValidator &&
        (current.validator is AllBehaviorValidator ||
            current.validator is AnyBehaviorValidator)) {
      outerNegated = true;
      current = current.validator;
    }

    if (current is AllBehaviorValidator) {
      _mode = _ValidatorEditorMode.composite;
      _combinator = _CompositeCombinator.all;
      _compositeNegated = outerNegated;
      for (final child in current.validators) {
        _compositeDrafts.add(_SimpleRuleDraft.fromValidator(child));
      }
      if (_compositeDrafts.isEmpty) {
        _compositeDrafts.add(_SimpleRuleDraft());
      }
      return;
    }

    if (current is AnyBehaviorValidator) {
      _mode = _ValidatorEditorMode.composite;
      _combinator = _CompositeCombinator.any;
      _compositeNegated = outerNegated;
      for (final child in current.validators) {
        _compositeDrafts.add(_SimpleRuleDraft.fromValidator(child));
      }
      if (_compositeDrafts.isEmpty) {
        _compositeDrafts.add(_SimpleRuleDraft());
      }
      return;
    }

    _mode = _ValidatorEditorMode.simple;
    _simpleDraft.dispose();
    _simpleDraft = _SimpleRuleDraft.fromValidator(validator);
    _compositeDrafts.addAll([
      _SimpleRuleDraft.fromValidator(validator),
      _SimpleRuleDraft(),
    ]);
  }

  ({BehaviorValidator? validator, String? error, bool isValid})
  _evaluateCurrent() {
    switch (_mode) {
      case _ValidatorEditorMode.none:
        return (validator: null, error: null, isValid: true);
      case _ValidatorEditorMode.simple:
        final result = _simpleDraft.build();
        return (
          validator: result.validator,
          error: result.error,
          isValid: result.error == null && result.validator != null,
        );
      case _ValidatorEditorMode.composite:
        if (_compositeDrafts.isEmpty) {
          return (
            validator: null,
            error: 'Ajoutez au moins une condition.',
            isValid: false,
          );
        }
        final builtChildren = <BehaviorValidator>[];
        for (var i = 0; i < _compositeDrafts.length; i++) {
          final res = _compositeDrafts[i].build();
          if (res.error != null || res.validator == null) {
            return (
              validator: null,
              error: 'Condition ${i + 1} : ${res.error ?? 'incomplète'}',
              isValid: false,
            );
          }
          builtChildren.add(res.validator!);
        }
        BehaviorValidator composite = _combinator == _CompositeCombinator.all
            ? AllBehaviorValidator(validators: builtChildren)
            : AnyBehaviorValidator(validators: builtChildren);
        if (_compositeNegated) {
          composite = NotBehaviorValidator(validator: composite);
        }
        try {
          composite.validate();
          return (validator: composite, error: null, isValid: true);
        } on FormatException catch (error) {
          return (validator: null, error: error.message, isValid: false);
        }
    }
  }

  void _emitCurrent() {
    final evaluated = _evaluateCurrent();
    _lastEmittedValidator = evaluated.validator;
    widget.onChanged(evaluated.validator, evaluated.isValid);
  }

  void _switchMode(_ValidatorEditorMode next) {
    if (next == _mode) return;
    setState(() {
      if (next == _ValidatorEditorMode.composite && _compositeDrafts.isEmpty) {
        _compositeDrafts.addAll([_SimpleRuleDraft(), _SimpleRuleDraft()]);
      }
      _mode = next;
    });
    _emitCurrent();
  }

  void _addCompositeRule() {
    setState(() {
      _compositeDrafts.add(_SimpleRuleDraft());
    });
    _emitCurrent();
  }

  void _removeCompositeRule(int index) {
    if (_compositeDrafts.length <= 1) return;
    setState(() {
      final removed = _compositeDrafts.removeAt(index);
      removed.dispose();
    });
    _emitCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final evaluated = _evaluateCurrent();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Condition d’exécution (validateur)',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Conditionnez l’exécution de l’action à l’état de ce composant, '
          'd’un autre composant ou d’une liaison repository.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (widget.infoBanner case final banner?) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    banner,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        SegmentedButton<_ValidatorEditorMode>(
          segments: [
            ButtonSegment(
              value: _ValidatorEditorMode.none,
              icon: const Icon(Icons.block_outlined),
              label: Text(
                'Aucune',
                key: ValueKey('${widget.keyPrefix}-validator-mode-none'),
              ),
            ),
            ButtonSegment(
              value: _ValidatorEditorMode.simple,
              icon: const Icon(Icons.rule_outlined),
              label: Text(
                'Condition simple',
                key: ValueKey('${widget.keyPrefix}-validator-mode-simple'),
              ),
            ),
            ButtonSegment(
              value: _ValidatorEditorMode.composite,
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(
                'Plusieurs (ET / OU)',
                key: ValueKey('${widget.keyPrefix}-validator-mode-composite'),
              ),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) => _switchMode(selection.first),
        ),
        const SizedBox(height: 14),
        if (_mode == _ValidatorEditorMode.simple)
          _buildRuleCard(
            context,
            draft: _simpleDraft,
            ruleKeyPrefix: '${widget.keyPrefix}-validator',
          )
        else if (_mode == _ValidatorEditorMode.composite) ...[
          SegmentedButton<_CompositeCombinator>(
            segments: [
              ButtonSegment(
                value: _CompositeCombinator.all,
                icon: const Icon(Icons.join_inner),
                label: Text(
                  'Toutes (ET)',
                  key: ValueKey('${widget.keyPrefix}-validator-combinator-all'),
                ),
              ),
              ButtonSegment(
                value: _CompositeCombinator.any,
                icon: const Icon(Icons.join_full),
                label: Text(
                  'Au moins une (OU)',
                  key: ValueKey('${widget.keyPrefix}-validator-combinator-any'),
                ),
              ),
            ],
            selected: {_combinator},
            onSelectionChanged: (selection) {
              setState(() => _combinator = selection.first);
              _emitCurrent();
            },
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _compositeDrafts.length; i++) ...[
            _buildRuleCard(
              context,
              draft: _compositeDrafts[i],
              ruleKeyPrefix: '${widget.keyPrefix}-validator-rule-$i',
              headerTitle: 'Condition ${i + 1}',
              onDelete: _compositeDrafts.length > 1
                  ? () => _removeCompositeRule(i)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: ValueKey('${widget.keyPrefix}-validator-add-rule'),
              onPressed: _addCompositeRule,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une condition'),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _buildPreviewBox(context, evaluated),
      ],
    );
  }

  Widget _buildRuleCard(
    BuildContext context, {
    required _SimpleRuleDraft draft,
    required String ruleKeyPrefix,
    String? headerTitle,
    VoidCallback? onDelete,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (draft.rawFallback != null) {
      return Card(
        margin: EdgeInsets.zero,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.account_tree_outlined, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  draft.rawFallback!.description,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: colors.error,
                  tooltip: 'Supprimer cette condition',
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      );
    }

    final allowedOperators = [
      for (final op in BehaviorValidatorOperator.values)
        if (draft.source != BehaviorValueSource.binding ||
            !op.requiresComponent)
          op,
    ];
    final effectiveOperator = allowedOperators.contains(draft.operator)
        ? draft.operator
        : BehaviorValidatorOperator.isFill;

    return Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (headerTitle != null) ...[
              Row(
                children: [
                  Text(
                    headerTitle,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: ValueKey('$ruleKeyPrefix-delete'),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: onDelete != null ? colors.error : colors.outline,
                    tooltip: onDelete != null
                        ? 'Supprimer cette condition'
                        : 'Au moins une condition est requise',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                  ),
                ],
              ),
              const Divider(height: 12),
            ],
            Text(
              'Source à vérifier',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<BehaviorValueSource>(
              segments: [
                for (final source in BehaviorValueSource.values)
                  ButtonSegment(
                    value: source,
                    icon: Icon(source.icon, size: 16),
                    label: Text(
                      source.label,
                      key: ValueKey('$ruleKeyPrefix-source-${source.name}'),
                    ),
                  ),
              ],
              selected: {draft.source},
              onSelectionChanged: (selection) {
                final nextSource = selection.first;
                setState(() {
                  draft.source = nextSource;
                  if (nextSource == BehaviorValueSource.binding &&
                      draft.operator.requiresComponent) {
                    draft.operator = BehaviorValidatorOperator.isFill;
                  }
                });
                _emitCurrent();
              },
            ),
            if (draft.source == BehaviorValueSource.component) ...[
              const SizedBox(height: 12),
              _buildTargetComponentPicker(
                context,
                draft: draft,
                ruleKeyPrefix: ruleKeyPrefix,
              ),
            ] else if (draft.source == BehaviorValueSource.binding) ...[
              const SizedBox(height: 12),
              RepositoryBindingFields(
                keyPrefix: '$ruleKeyPrefix-binding',
                binding: draft.binding,
                store: widget.store,
                listScope: widget.listScope,
                pathHint: 'client.statut',
                helper:
                    'Attribut du repository à tester ; [?] suit la ligne courante ou sélectionnée.',
                onChanged: (binding) {
                  setState(() => draft.binding = binding);
                  _emitCurrent();
                },
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<BehaviorValidatorOperator>(
              key: ValueKey('$ruleKeyPrefix-operator'),
              isExpanded: true,
              initialValue: effectiveOperator,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Opérateur',
              ),
              items: [
                for (final op in allowedOperators)
                  DropdownMenuItem(value: op, child: Text(op.label)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => draft.operator = value);
                _emitCurrent();
              },
            ),
            if (effectiveOperator.requiresValue) ...[
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('$ruleKeyPrefix-value'),
                controller: draft.valueController,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: 'Valeur attendue',
                  hintText: switch (effectiveOperator) {
                    BehaviorValidatorOperator.greaterThan ||
                    BehaviorValidatorOperator.lessThan => 'Ex. 10 ou 3.5',
                    BehaviorValidatorOperator.matchesRegex =>
                      r'Ex. ^[A-Z0-9._%+-]+@',
                    _ => 'Ex. actif, 42, true…',
                  },
                ),
                onChanged: (_) {
                  setState(() {});
                  _emitCurrent();
                },
              ),
            ],
            const SizedBox(height: 6),
            SwitchListTile(
              key: ValueKey('$ruleKeyPrefix-not'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Inverser la condition (NON)'),
              value: draft.negated,
              onChanged: (value) {
                setState(() => draft.negated = value);
                _emitCurrent();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetComponentPicker(
    BuildContext context, {
    required _SimpleRuleDraft draft,
    required String ruleKeyPrefix,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final query = draft.targetController.text.trim().toLowerCase();
    final exactMatch = widget.availableTargets
        .where((o) => o.id == draft.targetController.text.trim())
        .firstOrNull;
    final filtered = [
      for (final option in widget.availableTargets)
        if (query.isEmpty ||
            option.id.toLowerCase().contains(query) ||
            option.label.toLowerCase().contains(query) ||
            option.typeLabel.toLowerCase().contains(query))
          option,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: ValueKey('$ruleKeyPrefix-target'),
          controller: draft.targetController,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            labelText: 'Composant cible (filtrer ou saisir un ID)',
            hintText: 'Ex. email-input',
            prefixIcon: Icon(
              exactMatch?.icon ?? Icons.search,
              size: 18,
            ),
            suffixIcon: draft.targetController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    tooltip: 'Effacer',
                    onPressed: () {
                      setState(() => draft.targetController.clear());
                      _emitCurrent();
                    },
                  )
                : null,
          ),
          onChanged: (_) {
            setState(() {});
            _emitCurrent();
          },
        ),
        if (exactMatch != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 15, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${exactMatch.displayLabel} · ${exactMatch.typeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (widget.availableTargets.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 140),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Aucun composant correspondant dans la page — l’ID saisi '
                      'manuellement sera utilisé.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final option = filtered[index];
                      final isSelected =
                          option.id == draft.targetController.text.trim();
                      return InkWell(
                        key: ValueKey(
                          '$ruleKeyPrefix-target-option-${option.id}',
                        ),
                        onTap: () {
                          setState(() {
                            draft.targetController.text = option.id;
                            draft.targetController.selection =
                                TextSelection.collapsed(
                                  offset: option.id.length,
                                );
                          });
                          _emitCurrent();
                        },
                        child: Container(
                          color: isSelected
                              ? colors.primaryContainer.withValues(alpha: .35)
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                option.icon,
                                size: 16,
                                color: isSelected
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  option.displayLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                option.typeLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewBox(
    BuildContext context,
    ({BehaviorValidator? validator, String? error, bool isValid}) evaluated,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (!evaluated.isValid) {
      return Container(
        key: ValueKey('${widget.keyPrefix}-validator-error'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.errorContainer.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.error),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: colors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                evaluated.error ?? 'Condition incomplète.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          ],
        ),
      );
    }

    final text = evaluated.validator == null
        ? 'Aucune condition — l’action s’exécutera à chaque déclenchement.'
        : 'Si : ${evaluated.validator!.description}';

    return Container(
      key: ValueKey('${widget.keyPrefix}-validator-preview'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: evaluated.validator == null
            ? colors.surfaceContainerLow
            : colors.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: evaluated.validator == null
              ? colors.outlineVariant
              : colors.primary.withValues(alpha: .5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            evaluated.validator == null
                ? Icons.check_circle_outline
                : Icons.verified_user_outlined,
            size: 18,
            color: evaluated.validator == null
                ? colors.onSurfaceVariant
                : colors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: evaluated.validator == null
                    ? FontWeight.normal
                    : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
