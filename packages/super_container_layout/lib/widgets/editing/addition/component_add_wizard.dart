import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/registry.dart';
import '../../../models/super_layout_config.dart';
import '../../../services/json_list_scope.dart';
import '../../../services/json_repository_scope.dart';
import '../repositories/repository_binding_fields.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';

/// Component-specific settings edited by the add wizard before insertion.
///
/// The draft [T] is created by [initial], edited by [builder], described in
/// the summary by [summary] and written under the new instance ID by [apply]
/// once the wizard is confirmed. [validate] returns a blocking message.
///
/// With [readBinding] and [writeBinding], the wizard adds a dedicated
/// « Liaison » step editing the repository binding of the draft; the
/// settings step is then validated without that binding.
class ComponentAddConfigurator<T extends Object> {
  const ComponentAddConfigurator({
    required this._initial,
    required this._builder,
    required this._summary,
    required this._apply,
    this._validate,
    this._readBinding,
    this._writeBinding,
    this.bindingKeyPrefix = 'add-binding',
    this.bindingPathHint = '',
    this.bindingHelp,
  }) : assert((_readBinding == null) == (_writeBinding == null));

  final T Function(BuildContext context) _initial;
  final Widget Function(BuildContext, T, ValueChanged<T>) _builder;
  final List<(String, String)> Function(T) _summary;
  final void Function(Registry, String, T) _apply;
  final String? Function(T)? _validate;
  final JsonTextBinding? Function(T)? _readBinding;
  final T Function(T, JsonTextBinding?)? _writeBinding;

  /// Key prefix of the repository fields of the « Liaison » step.
  final String bindingKeyPrefix;
  final String bindingPathHint;

  /// Explanation shown under the binding fields when a binding is set.
  final String? bindingHelp;

  bool get supportsBinding => _readBinding != null;

  JsonTextBinding? bindingOf(Object draft) => _readBinding?.call(draft as T);

  Object withBinding(Object draft, JsonTextBinding? binding) =>
      _writeBinding == null ? draft : _writeBinding(draft as T, binding);

  Object initialDraft(BuildContext context) => _initial(context);

  Widget buildDraft(
    BuildContext context,
    Object draft,
    ValueChanged<Object> onChanged,
  ) => _builder(context, draft as T, onChanged);

  List<(String, String)> summarize(Object draft) => _summary(draft as T);

  String? validateDraft(Object draft) => _validate?.call(draft as T);

  void applyDraft(Registry registry, String id, Object draft) =>
      _apply(registry, id, draft as T);
}

/// A component proposed by the add wizard.
class ComponentAddCandidate {
  const ComponentAddCandidate({
    required this.id,
    required this.label,
    this.tags = const {},
    this.configurator,
  });

  /// Value identifying the component for the caller (slot ID or type).
  final String id;
  final String label;
  final Set<String> tags;
  final ComponentAddConfigurator<Object>? configurator;
}

/// A zone or region able to receive the new component.
class ComponentAddTarget {
  const ComponentAddTarget({
    required this.id,
    required this.label,
    this.siblings = const [],
    this.accepts,
    this.replaces = false,
  });

  final String id;
  final String label;

  /// Components already placed, in order, as `(id, label)`.
  final List<(String, String)> siblings;
  final bool Function(Set<String> tags)? accepts;

  /// The target holds a single component, replaced by the addition.
  final bool replaces;

  bool accept(Set<String> tags) => accepts?.call(tags) ?? true;
}

/// Result of the add wizard.
class ComponentAddRequest {
  const ComponentAddRequest({
    required this.component,
    required this.targetId,
    this.beforeId,
    this.label,
    this.size,
    this.draft,
  });

  final ComponentAddCandidate component;
  final String targetId;

  /// Sibling placed after the new component; null appends it.
  final String? beforeId;

  /// Instance label; null keeps the component label.
  final String? label;

  /// Explicit size; null keeps the caller's default sizing.
  final SlotSizeConstraints? size;

  /// Component-specific draft, applied by [applyConfiguration].
  final Object? draft;

  void applyConfiguration(Registry? registry, String instanceId) {
    final configurator = component.configurator;
    final value = draft;
    if (registry != null && configurator != null && value != null) {
      configurator.applyDraft(registry, instanceId, value);
    }
  }
}

/// Opens the add wizard: component, settings, placement, repository binding
/// (only for components whose configurator supports it) and summary, where the
/// instance name can be edited.
///
/// [candidates] are those accepted by the initial target. The returned request
/// is null when the wizard is cancelled. Each card keeps the historical
/// `$keyPrefix-add-slot-<id>` key on its « Ajouter directement » button, which
/// adds the component with its default settings.
Future<ComponentAddRequest?> showComponentAddWizard({
  required BuildContext context,
  required String title,
  required String keyPrefix,
  required List<ComponentAddCandidate> candidates,
  required List<ComponentAddTarget> targets,
  required String initialTargetId,
  BuildContext? target,
  bool editableLabel = true,
  String emptyMessage = 'Aucun composant disponible.',
}) async {
  final width = ValueNotifier(640.0);
  // The dialog route may sit above the page scopes: forward them so the
  // configurators can offer repository bindings.
  final repositories = context
      .getInheritedWidgetOfExactType<JsonRepositoryScope>()
      ?.store;
  final listScope = context.getInheritedWidgetOfExactType<JsonListScope>();
  try {
    return await showEditorDialog<ComponentAddRequest>(
      context: context,
      target: target,
      preferredWidth: width,
      builder: (_) {
        Widget child = ComponentAddWizard(
          title: title,
          keyPrefix: keyPrefix,
          candidates: candidates,
          targets: targets,
          initialTargetId: initialTargetId,
          editableLabel: editableLabel,
          emptyMessage: emptyMessage,
        );
        if (listScope != null) {
          child = JsonListScope(
            repositoryId: listScope.repositoryId,
            indices: listScope.indices,
            placeholder: listScope.placeholder,
            child: child,
          );
        }
        if (repositories != null) {
          child = JsonRepositoryScope(store: repositories, child: child);
        }
        return child;
      },
    );
  } finally {
    width.dispose();
  }
}

class ComponentAddWizard extends StatefulWidget {
  const ComponentAddWizard({
    required this.title,
    required this.keyPrefix,
    required this.candidates,
    required this.targets,
    required this.initialTargetId,
    this.editableLabel = true,
    this.emptyMessage = 'Aucun composant disponible.',
    super.key,
  });

  final String title;
  final String keyPrefix;
  final List<ComponentAddCandidate> candidates;
  final List<ComponentAddTarget> targets;
  final String initialTargetId;
  final bool editableLabel;
  final String emptyMessage;

  @override
  State<ComponentAddWizard> createState() => _ComponentAddWizardState();
}

class _ComponentAddWizardState extends State<ComponentAddWizard> {
  static const _doubleTap = Duration(milliseconds: 400);

  int _step = 0;
  String _query = '';
  ComponentAddCandidate? _selected;
  String? _lastTap;
  DateTime? _lastTapTime;

  late String _targetId = widget.initialTargetId;
  String? _beforeId;
  final _label = TextEditingController();
  bool _customSize = false;
  final _size = _SizeDraft();
  final _drafts = <String, Object>{};

  @override
  void dispose() {
    _label.dispose();
    _size.dispose();
    super.dispose();
  }

  ComponentAddTarget get _target =>
      widget.targets.where((target) => target.id == _targetId).firstOrNull ??
      widget.targets.first;

  List<ComponentAddTarget> _targetsFor(ComponentAddCandidate candidate) => [
    for (final target in widget.targets)
      if (target.id == widget.initialTargetId || target.accept(candidate.tags))
        target,
  ];

  Object? _draftOf(ComponentAddCandidate candidate) {
    final configurator = candidate.configurator;
    if (configurator == null) return null;
    return _drafts.putIfAbsent(
      candidate.id,
      () => configurator.initialDraft(context),
    );
  }

  void _select(ComponentAddCandidate candidate) {
    final now = DateTime.now();
    final repeated =
        _lastTap == candidate.id &&
        _lastTapTime != null &&
        now.difference(_lastTapTime!) <= _doubleTap;
    _lastTap = candidate.id;
    _lastTapTime = now;
    if (repeated) {
      _addDirectly(candidate);
      return;
    }
    setState(() {
      if (_selected?.id != candidate.id) {
        _selected = candidate;
        if (!_targetsFor(candidate).any((target) => target.id == _targetId)) {
          _targetId = widget.initialTargetId;
        }
        _beforeId = null;
      }
    });
  }

  void _addDirectly(ComponentAddCandidate candidate) {
    Navigator.of(context).pop(
      ComponentAddRequest(
        component: candidate,
        targetId: widget.initialTargetId,
      ),
    );
  }

  String? get _labelValue {
    final value = _label.text.trim();
    return !widget.editableLabel || value.isEmpty || value == _selected?.label
        ? null
        : value;
  }

  String? get _settingsError {
    final candidate = _selected;
    final draft = candidate == null ? null : _draftOf(candidate);
    if (candidate != null && draft != null) {
      final configurator = candidate.configurator!;
      // The binding is validated by its own step.
      return configurator.validateDraft(configurator.withBinding(draft, null));
    }
    return null;
  }

  String? get _bindingError {
    final candidate = _selected;
    final draft = candidate == null ? null : _draftOf(candidate);
    if (candidate == null || draft == null) return null;
    final configurator = candidate.configurator!;
    final binding = configurator.bindingOf(draft);
    if (binding != null && binding.path.trim().isEmpty) {
      return 'Chemin de liaison requis.';
    }
    return configurator.validateDraft(draft);
  }

  bool get _hasBindingStep => _selected?.configurator?.supportsBinding ?? false;

  /// The « Liaison » step stays visible but is skipped for components
  /// without repository binding: the Stepper needs a constant step count.
  bool _enabled(_WizardStage stage) =>
      stage != _WizardStage.binding || _hasBindingStep;

  _WizardStage get _stage => _WizardStage.values[_step];

  int get _nextStep {
    var step = _step + 1;
    while (step < _WizardStage.values.length - 1 &&
        !_enabled(_WizardStage.values[step])) {
      step++;
    }
    return step;
  }

  int get _previousStep {
    var step = _step - 1;
    while (step > 0 && !_enabled(_WizardStage.values[step])) {
      step--;
    }
    return step;
  }

  bool get _canContinue => switch (_stage) {
    _WizardStage.component => _selected != null,
    _WizardStage.settings => _settingsError == null,
    _WizardStage.placement => !_customSize || _size.error == null,
    _WizardStage.binding => _bindingError == null,
    _WizardStage.summary => true,
  };

  void _next() {
    if (!_canContinue) return;
    if (_stage != _WizardStage.summary) {
      setState(() => _step = _nextStep);
      return;
    }
    final candidate = _selected!;
    Navigator.of(context).pop(
      ComponentAddRequest(
        component: candidate,
        targetId: _target.id,
        beforeId: _target.replaces ? null : _beforeId,
        label: _labelValue,
        size: _customSize ? _size.value : null,
        draft: _draftOf(candidate),
      ),
    );
  }

  void _back() {
    if (_step > 0) setState(() => _step = _previousStep);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildDialog(context, compact: constraints.maxHeight < 480),
  );

  Widget _buildDialog(
    BuildContext context, {
    required bool compact,
  }) => AlertDialog(
    key: ValueKey('${widget.keyPrefix}-add-wizard'),
    insetPadding: compact
        ? const EdgeInsets.all(4)
        : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    titlePadding: compact ? const EdgeInsets.fromLTRB(16, 8, 16, 0) : null,
    actionsPadding: compact ? const EdgeInsets.fromLTRB(16, 0, 16, 8) : null,
    title: EditorDialogHeader(label: widget.title),
    contentPadding: EdgeInsets.fromLTRB(8, compact ? 4 : 12, 8, 0),
    content: SizedBox(
      width: 640,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: LayoutBuilder(
          builder: (context, constraints) => Stepper(
            key: ValueKey('${widget.keyPrefix}-add-stepper'),
            type: StepperType.horizontal,
            currentStep: _step,
            elevation: 0,
            onStepTapped: (step) {
              if (!_enabled(_WizardStage.values[step])) return;
              if (step < _step || (step == _nextStep && _canContinue)) {
                setState(() => _step = step);
              }
            },
            controlsBuilder: (_, _) => const SizedBox.shrink(),
            steps: _steps(
              context,
              allTitles: _titlesFit(context, constraints.maxWidth),
            ),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        key: ValueKey('${widget.keyPrefix}-add-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
      ),
      if (_step > 0)
        TextButton(
          key: ValueKey('${widget.keyPrefix}-add-back'),
          onPressed: _back,
          child: const Text('Précédent'),
        ),
      FilledButton(
        key: ValueKey('${widget.keyPrefix}-add-next'),
        onPressed: _canContinue ? _next : null,
        child: Text(_stage == _WizardStage.summary ? 'Appliquer' : 'Suivant'),
      ),
    ],
  );

  /// Whether every step title fits in the horizontal Stepper header, whose
  /// titles cannot shrink: 24 px padding per side, then per step a 24 px icon
  /// and a 12 px gap, plus 16 px between steps.
  bool _titlesFit(BuildContext context, double width) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    var needed = 48.0 + (_WizardStage.values.length - 1) * 16;
    for (final stage in _WizardStage.values) {
      final painter = TextPainter(
        text: TextSpan(text: stage.title, style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      needed += 36 + painter.width;
      painter.dispose();
    }
    return needed <= width;
  }

  /// Steps of the Stepper; with [allTitles] false only the current title is
  /// written, the others keep their number and a tooltip.
  List<Step> _steps(BuildContext context, {required bool allTitles}) => [
    for (final (index, stage) in _WizardStage.values.indexed)
      Step(
        title: allTitles || index == _step
            ? Text(
                stage.title,
                key: ValueKey('${widget.keyPrefix}-add-step-${stage.name}'),
              )
            : Tooltip(
                key: ValueKey('${widget.keyPrefix}-add-step-${stage.name}'),
                message: stage.title,
                child: const SizedBox(width: 4, height: 24),
              ),
        isActive: _step >= index && _enabled(stage),
        state: !_enabled(stage)
            ? StepState.disabled
            : _step > index
            ? StepState.complete
            : StepState.indexed,
        content: _step != index
            ? const SizedBox.shrink()
            : switch (stage) {
                _WizardStage.component => _buildChoice(context),
                _ when _selected == null => const SizedBox.shrink(),
                _WizardStage.settings => _buildSettings(context, _selected!),
                _WizardStage.placement => _buildPlacement(context, _selected!),
                _WizardStage.binding => _buildBinding(context, _selected!),
                _WizardStage.summary => _buildSummary(context, _selected!),
              },
      ),
  ];

  Widget _buildChoice(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final visible = [
      for (final candidate in widget.candidates)
        if (query.isEmpty ||
            candidate.label.toLowerCase().contains(query) ||
            candidate.tags.any((tag) => tag.toLowerCase().contains(query)))
          candidate,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(widget.emptyMessage),
          )
        else ...[
          TextField(
            key: ValueKey('${widget.keyPrefix}-add-search'),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher un composant ou un tag',
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Aucun composant ne correspond à la recherche.'),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final candidate in visible)
                _ComponentCard(
                  keyPrefix: widget.keyPrefix,
                  candidate: candidate,
                  selected: _selected?.id == candidate.id,
                  onTap: () => _select(candidate),
                  onAdd: () => _addDirectly(candidate),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSettings(BuildContext context, ComponentAddCandidate candidate) {
    final theme = Theme.of(context);
    final draft = _draftOf(candidate);
    final error = _settingsError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Paramètres de ${candidate.label}',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        if (candidate.configurator case final configurator? when draft != null)
          configurator.buildDraft(
            context,
            draft,
            (value) => setState(() => _drafts[candidate.id] = value),
          )
        else
          Text('Aucun paramètre spécifique.', style: theme.textTheme.bodySmall),
        if (error != null)
          Text(
            error,
            key: ValueKey('${widget.keyPrefix}-add-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
      ],
    );
  }

  Widget _buildPlacement(
    BuildContext context,
    ComponentAddCandidate candidate,
  ) {
    final theme = Theme.of(context);
    final targets = _targetsFor(candidate);
    final target = _target;
    final error = _customSize ? _size.error : null;
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
    return Column(
      key: ValueKey('${widget.keyPrefix}-add-placement'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('Emplacement', [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('${widget.keyPrefix}-add-target'),
                  initialValue: target.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Zone',
                  ),
                  items: [
                    for (final option in targets)
                      DropdownMenuItem(
                        value: option.id,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _targetId = value ?? widget.initialTargetId;
                    _beforeId = null;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: target.replaces
                    ? Text(
                        target.siblings.isEmpty
                            ? 'Composant unique'
                            : 'Remplace le contenu actuel',
                        style: theme.textTheme.bodySmall,
                      )
                    : DropdownButtonFormField<String?>(
                        key: ValueKey(
                          '${widget.keyPrefix}-add-position-${target.id}',
                        ),
                        initialValue: _beforeId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Position',
                        ),
                        items: [
                          for (final (id, label) in target.siblings)
                            DropdownMenuItem(
                              value: id,
                              child: Text(
                                'Avant $label',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('À la fin'),
                          ),
                        ],
                        onChanged: (value) => setState(() => _beforeId = value),
                      ),
              ),
            ],
          ),
        ]),
        section('Taille', [
          SwitchListTile(
            key: ValueKey('${widget.keyPrefix}-add-custom-size'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Définir une taille'),
            subtitle: const Text('Sinon, taille par défaut de la zone'),
            value: _customSize,
            onChanged: (value) => setState(() => _customSize = value),
          ),
          if (_customSize)
            _SizeFields(
              keyPrefix: widget.keyPrefix,
              draft: _size,
              onChanged: () => setState(() {}),
            ),
        ]),
        if (error != null)
          Text(
            error,
            key: ValueKey('${widget.keyPrefix}-add-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
      ],
    );
  }

  Widget _buildBinding(BuildContext context, ComponentAddCandidate candidate) {
    final theme = Theme.of(context);
    final configurator = candidate.configurator!;
    final draft = _draftOf(candidate)!;
    final binding = configurator.bindingOf(draft);
    final error = _bindingError;
    return Column(
      key: ValueKey('${widget.keyPrefix}-add-binding'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Liaison de ${candidate.label} au repository',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Facultatif : choisissez un repository et le chemin de la donnée, '
          'ou laissez « Sans liaison ».',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        RepositoryBindingFields(
          keyPrefix: configurator.bindingKeyPrefix,
          binding: binding,
          pathHint: configurator.bindingPathHint,
          onChanged: (value) => setState(
            () => _drafts[candidate.id] = configurator.withBinding(
              _draftOf(candidate)!,
              value,
            ),
          ),
        ),
        if (binding != null && configurator.bindingHelp != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              configurator.bindingHelp!,
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              key: ValueKey('${widget.keyPrefix}-add-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context, ComponentAddCandidate candidate) {
    final target = _target;
    final position = target.replaces
        ? (target.siblings.isEmpty ? 'Unique' : 'Remplace le contenu actuel')
        : _beforeId == null
        ? 'À la fin'
        : 'Avant ${target.siblings.where((s) => s.$1 == _beforeId).firstOrNull?.$2 ?? _beforeId}';
    final draft = _draftOf(candidate);
    final lines = <(String, String)>[
      ('Composant', candidate.label),
      if (candidate.tags.isNotEmpty) ('Tags', candidate.tags.join(', ')),
      ('Zone', target.label),
      ('Position', position),
      ('Taille', _customSize ? _size.describe() : 'Par défaut'),
      if (candidate.configurator case final configurator? when draft != null)
        ...configurator.summarize(draft),
    ];
    final theme = Theme.of(context);
    return Column(
      key: ValueKey('${widget.keyPrefix}-add-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editableLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              key: ValueKey('${widget.keyPrefix}-add-label'),
              controller: _label,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Nom du composant',
                hintText: candidate.label,
                helperText: 'Vide : nom du composant',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        for (final (name, value) in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(name, style: theme.textTheme.labelLarge),
                ),
                Expanded(child: Text(value)),
              ],
            ),
          ),
      ],
    );
  }
}

enum _WizardStage {
  component('Composant'),
  settings('Paramètres'),
  placement('Emplacement'),
  binding('Liaison'),
  summary('Résumé');

  const _WizardStage(this.title);

  final String title;
}

class _ComponentCard extends StatelessWidget {
  const _ComponentCard({
    required this.keyPrefix,
    required this.candidate,
    required this.selected,
    required this.onTap,
    required this.onAdd,
  });

  final String keyPrefix;
  final ComponentAddCandidate candidate;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  IconData get _icon {
    final tags = candidate.tags;
    if (tags.contains('text') || tags.contains('input')) {
      return Icons.text_fields;
    }
    if (tags.contains('list')) return Icons.view_list_outlined;
    if (tags.contains('layout')) return Icons.dashboard_outlined;
    if (tags.contains('container')) return Icons.crop_square;
    if (tags.contains('appBar')) return Icons.web_asset;
    if (tags.contains('bottomNavigationBar')) return Icons.view_week_outlined;
    return Icons.widgets_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 140,
      child: Card(
        key: ValueKey('$keyPrefix-add-card-${candidate.id}'),
        margin: EdgeInsets.zero,
        elevation: 0,
        color: selected ? colors.primaryContainer : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
            child: Row(
              children: [
                Icon(_icon, size: 18, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        candidate.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (candidate.tags.isNotEmpty)
                        Text(
                          candidate.tags.map((tag) => '#$tag').join(' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('$keyPrefix-add-slot-${candidate.id}'),
                  tooltip: 'Ajouter directement',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.bolt),
                  onPressed: onAdd,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Text fields of the optional size step, with their units.
class _SizeDraft {
  static const fields = [
    ('preferredWidth', 'Largeur préférée'),
    ('preferredHeight', 'Hauteur préférée'),
    ('minWidth', 'Largeur min'),
    ('minHeight', 'Hauteur min'),
    ('maxWidth', 'Largeur max'),
    ('maxHeight', 'Hauteur max'),
  ];

  final controllers = {
    for (final (key, _) in fields) key: TextEditingController(),
  };
  final units = {for (final (key, _) in fields) key: SlotSizeUnit.pixels};
  SlotPercentBasis basis = SlotPercentBasis.zone;

  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  /// Parsed dimension; throws [FormatException] for an invalid value.
  SlotDimension? dimension(String key) {
    final text = controllers[key]!.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value < 0) {
      throw const FormatException('Nombre positif attendu.');
    }
    if (units[key] == SlotSizeUnit.percent && value > 100) {
      throw const FormatException('Pourcentage entre 0 et 100 attendu.');
    }
    return SlotDimension(value, units[key]!);
  }

  String? get error {
    try {
      final value = this.value;
      for (final (min, max, name) in [
        (value.minWidth, value.maxWidth, 'largeur'),
        (value.minHeight, value.maxHeight, 'hauteur'),
      ]) {
        if (min != null &&
            max != null &&
            min.unit == max.unit &&
            min.value > max.value) {
          return 'La $name minimale dépasse la maximale.';
        }
      }
      return null;
    } on FormatException catch (error) {
      return 'Taille invalide : ${error.message}';
    }
  }

  SlotSizeConstraints get value => SlotSizeConstraints(
    preferredWidth: dimension('preferredWidth'),
    preferredHeight: dimension('preferredHeight'),
    minWidth: dimension('minWidth'),
    minHeight: dimension('minHeight'),
    maxWidth: dimension('maxWidth'),
    maxHeight: dimension('maxHeight'),
    percentBasis: basis,
  );

  String describe() {
    final parts = [
      for (final (key, label) in fields)
        if (controllers[key]!.text.trim().isNotEmpty)
          '$label ${controllers[key]!.text.trim()}'
              '${units[key] == SlotSizeUnit.percent ? ' %' : ' px'}',
    ];
    if (parts.isEmpty) return 'Aucune contrainte';
    final percent = units.values.contains(SlotSizeUnit.percent);
    return [
      ...parts,
      if (percent)
        basis == SlotPercentBasis.zone ? '% de la zone' : '% du layout',
    ].join(', ');
  }
}

class _SizeFields extends StatelessWidget {
  const _SizeFields({
    required this.keyPrefix,
    required this.draft,
    required this.onChanged,
  });

  final String keyPrefix;
  final _SizeDraft draft;
  final VoidCallback onChanged;

  Widget _field(String key, String label) => Row(
    children: [
      Expanded(
        child: TextField(
          key: ValueKey('$keyPrefix-add-size-$key'),
          controller: draft.controllers[key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(isDense: true, labelText: label),
          onChanged: (_) => onChanged(),
        ),
      ),
      DropdownButton<SlotSizeUnit>(
        key: ValueKey('$keyPrefix-add-size-unit-$key'),
        value: draft.units[key],
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: SlotSizeUnit.pixels, child: Text('px')),
          DropdownMenuItem(value: SlotSizeUnit.percent, child: Text('%')),
        ],
        onChanged: (value) {
          if (value == null) return;
          draft.units[key] = value;
          onChanged();
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < _SizeDraft.fields.length; i += 2)
        Row(
          children: [
            Expanded(
              child: _field(_SizeDraft.fields[i].$1, _SizeDraft.fields[i].$2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(
                _SizeDraft.fields[i + 1].$1,
                _SizeDraft.fields[i + 1].$2,
              ),
            ),
          ],
        ),
      if (draft.units.values.contains(SlotSizeUnit.percent))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SegmentedButton<SlotPercentBasis>(
            key: ValueKey('$keyPrefix-add-size-basis'),
            segments: const [
              ButtonSegment(
                value: SlotPercentBasis.zone,
                label: Text('% de la zone'),
              ),
              ButtonSegment(
                value: SlotPercentBasis.layout,
                label: Text('% du layout'),
              ),
            ],
            selected: {draft.basis},
            onSelectionChanged: (value) {
              draft.basis = value.single;
              onChanged();
            },
          ),
        ),
    ],
  );
}
