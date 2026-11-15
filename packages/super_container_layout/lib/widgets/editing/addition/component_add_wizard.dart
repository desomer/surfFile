/// Assistant guidé d'ajout d'un composant ([ComponentAddWizard]) dans une zone ou région.
///
/// Permet de choisir un composant selon les tags, son mode d’insertion et ses réglages.
library;

export 'component_add_contracts.dart'
    show
        ComponentAddFamily,
        ComponentAddConfigurator,
        ComponentAddCandidate,
        ComponentAddTarget,
        ComponentAddPlacement,
        ComponentAddTargetScope,
        ComponentAddRequest;

import 'package:material_ui/material_ui.dart';

import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../repositories/repository_binding_fields.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import 'component_add_choice.dart';
import 'component_add_contracts.dart';
import 'component_add_placement.dart';
import 'component_add_size_fields.dart';
import 'insertion_plan.dart';

/// Opens the add wizard: component, settings, placement, repository binding
/// (only for components whose configurator supports it) and summary, where the
/// instance name can be edited.
///
/// [candidates] are those accepted by the initial target. The returned request
/// is null when the wizard is cancelled. Each card keeps the historical
/// `$keyPrefix-add-slot-<id>` key on its « Ajouter directement » button, which
/// adds the component with its default settings.
///
/// With [placements], the « Emplacement » step offers these positions instead
/// of [targets]; the request then carries the chosen
/// [ComponentAddRequest.placementId].
Future<ComponentAddRequest?> showComponentAddWizard({
  required BuildContext context,
  required String title,
  required String keyPrefix,
  required List<ComponentAddCandidate> candidates,
  List<ComponentAddTarget> targets = const [],
  String initialTargetId = '',
  List<ComponentAddPlacement>? placements,
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
        final initialTarget = targets
            .where((t) => t.id == initialTargetId)
            .firstOrNull;
        Widget child = ComponentAddWizard(
          title: title,
          keyPrefix: keyPrefix,
          candidates: candidates,
          targets: targets,
          initialTargetId: initialTargetId,
          placements: placements,
          editableLabel: editableLabel,
          emptyMessage: emptyMessage,
        );
        child = ComponentAddTargetScope(
          targetId: initialTargetId,
          targetLabel: initialTarget?.label ?? title,
          initialTargetId: initialTargetId,
          wizardTitle: title,
          zoneTags: initialTarget?.zoneTags ?? const {},
          child: child,
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
    EditorInsertionPreview.active.value = null;
    width.dispose();
  }
}

/// Dialogue d'assistant guidé permettant de choisir, prévisualiser et configurer un composant à insérer.
class ComponentAddWizard extends StatefulWidget {
  const ComponentAddWizard({
    required this.title,
    required this.keyPrefix,
    required this.candidates,
    this.targets = const [],
    this.initialTargetId = '',
    this.placements,
    this.editableLabel = true,
    this.emptyMessage = 'Aucun composant disponible.',
    super.key,
  });

  final String title;
  final String keyPrefix;
  final List<ComponentAddCandidate> candidates;
  final List<ComponentAddTarget> targets;
  final String initialTargetId;

  /// Relative positions replacing [targets] in the « Emplacement » step.
  final List<ComponentAddPlacement>? placements;
  final bool editableLabel;
  final String emptyMessage;

  @override
  State<ComponentAddWizard> createState() => _ComponentAddWizardState();
}

class _ComponentAddWizardState extends State<ComponentAddWizard> {
  static const _doubleTap = Duration(milliseconds: 400);

  int _step = 0;
  String _query = '';
  ComponentAddFamily? _selectedFamily;
  ComponentAddCandidate? _selected;
  String? _lastTap;
  DateTime? _lastTapTime;

  late String _targetId = widget.initialTargetId;
  String? _beforeId;
  String? _placementId;
  final _label = TextEditingController();
  bool _customSize = false;
  final _size = ComponentAddSizeDraft();
  final _drafts = <String, Object>{};

  @override
  void dispose() {
    if (EditorInsertionPreview.active.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        EditorInsertionPreview.active.value = null;
      });
    }
    _label.dispose();
    _size.dispose();
    super.dispose();
  }

  void _setHoveredPreview(ComponentAddPlacementPreview? preview) {
    EditorInsertionPreview.active.value = preview;
  }

  void _clearHoveredPreview([ComponentAddPlacementPreview? expected]) {
    if (expected == null ||
        identical(EditorInsertionPreview.active.value, expected)) {
      EditorInsertionPreview.active.value = null;
    }
  }

  ComponentAddTarget? get _target =>
      widget.targets.where((target) => target.id == _targetId).firstOrNull ??
      widget.targets.firstOrNull;

  List<ComponentAddTarget> _targetsFor(ComponentAddCandidate candidate) => [
    for (final target in widget.targets)
      if (target.admits(candidate)) target,
  ];

  List<ComponentAddPlacement> _placementsFor(ComponentAddCandidate candidate) =>
      [
        for (final placement in widget.placements ?? const [])
          if (placement.admits(candidate)) placement,
      ];

  /// Candidates with at least one compatible target or placement.
  List<ComponentAddCandidate> get _offered => [
    for (final candidate in widget.candidates)
      if (widget.placements != null
          ? _placementsFor(candidate).isNotEmpty
          : _targetsFor(candidate).isNotEmpty)
        candidate,
  ];

  ComponentAddPlacement? get _placement {
    final candidate = _selected;
    if (candidate == null) return null;
    final options = _placementsFor(candidate);
    return options.where((option) => option.id == _placementId).firstOrNull ??
        options.firstOrNull;
  }

  Object? _draftOf(ComponentAddCandidate candidate, [BuildContext? ctx]) {
    final configurator = candidate.configurator;
    if (configurator == null) return null;
    return _drafts.putIfAbsent(
      candidate.id,
      () => configurator.initialDraft(ctx ?? context),
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
        if (widget.placements == null &&
            !_targetsFor(candidate).any((target) => target.id == _targetId)) {
          _targetId = _defaultTargetFor(candidate);
        }
        _beforeId = null;
      }
    });
  }

  void _selectFamily(ComponentAddFamily? family) {
    setState(() {
      _selectedFamily = family;
      if (family != null && _selected?.family != family) {
        _selected = null;
        _beforeId = null;
      }
    });
  }

  /// The initial target when compatible, otherwise the first compatible one.
  String _defaultTargetFor(ComponentAddCandidate candidate) {
    final targets = _targetsFor(candidate);
    return targets.any((target) => target.id == widget.initialTargetId)
        ? widget.initialTargetId
        : targets.firstOrNull?.id ?? widget.initialTargetId;
  }

  void _addDirectly(ComponentAddCandidate candidate) {
    final placement = widget.placements == null
        ? null
        : _placementsFor(candidate).firstOrNull;
    if (widget.placements != null && placement == null) return;
    Navigator.of(context).pop(
      ComponentAddRequest(
        component: candidate,
        targetId: widget.placements == null
            ? _defaultTargetFor(candidate)
            : widget.initialTargetId,
        placementId: placement?.id,
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
    _WizardStage.component =>
      _selected != null &&
          (widget.placements == null || _placementsFor(_selected!).isNotEmpty),
    _WizardStage.settings => _settingsError == null,
    _WizardStage.placement =>
      (widget.placements != null ? _placement != null : _target != null) &&
          (!_customSize || _size.error == null),
    _WizardStage.binding => _bindingError == null,
    _WizardStage.summary => true,
  };

  void _next() {
    if (!_canContinue) return;
    _clearHoveredPreview();
    if (_stage != _WizardStage.summary) {
      setState(() => _step = _nextStep);
      return;
    }
    final candidate = _selected!;
    final relative = widget.placements != null;
    final target = _target;
    Navigator.of(context).pop(
      ComponentAddRequest(
        component: candidate,
        targetId: relative
            ? widget.initialTargetId
            : (target?.id ?? widget.initialTargetId),
        beforeId: relative || (target?.replaces ?? false) ? null : _beforeId,
        placementId: relative ? _placement!.id : null,
        label: _labelValue,
        size: _customSize ? _size.value : null,
        draft: _draftOf(candidate),
      ),
    );
  }

  void _back() {
    if (_step > 0) {
      _clearHoveredPreview();
      setState(() => _step = _previousStep);
    }
  }

  @override
  Widget build(BuildContext context) {
    final placement = _placement;
    final target = widget.placements == null ? _target : null;
    final targetId = widget.placements != null
        ? (placement?.id ?? widget.initialTargetId)
        : (target?.id ?? _targetId);
    final targetLabel = widget.placements != null
        ? (placement?.label ?? widget.title)
        : (target?.label ?? widget.title);
    final zoneTags = widget.placements != null
        ? (placement?.zoneTags ?? const <String>{})
        : (target?.zoneTags ?? const <String>{});
    return ComponentAddTargetScope(
      targetId: targetId,
      targetLabel: targetLabel,
      initialTargetId: widget.initialTargetId,
      wizardTitle: widget.title,
      zoneTags: zoneTags,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;
          return _buildDialog(
            context,
            availableHeight: availableHeight,
            compact: availableHeight < 480,
          );
        },
      ),
    );
  }

  Widget _buildDialog(
    BuildContext context, {
    required double availableHeight,
    required bool compact,
  }) {
    final verticalInset = availableHeight * 0.05;
    final targetHeight = availableHeight * 0.9;
    return AlertDialog(
      key: ValueKey('${widget.keyPrefix}-add-wizard'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 40,
        vertical: verticalInset,
      ),
      titlePadding: compact ? const EdgeInsets.fromLTRB(16, 8, 16, 0) : null,
      actionsPadding: compact ? const EdgeInsets.fromLTRB(16, 0, 16, 8) : null,
      title: EditorDialogHeader(label: widget.title),
      contentPadding: EdgeInsets.fromLTRB(8, compact ? 4 : 12, 8, 0),
      content: SizedBox(
        width: 640,
        height: targetHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final allTitles = _titlesFit(context, constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stepper(
                    key: ValueKey('${widget.keyPrefix}-add-stepper'),
                    type: StepperType.horizontal,
                    currentStep: _step,
                    elevation: 0,
                    onStepTapped: (step) {
                      if (!_enabled(_WizardStage.values[step])) return;
                      if (step < _step || (step == _nextStep && _canContinue)) {
                        _clearHoveredPreview();
                        setState(() => _step = step);
                      }
                    },
                    controlsBuilder: (_, _) => const SizedBox.shrink(),
                    steps: _steps(context, allTitles: allTitles),
                  ),
                ),
                if (_stage == _WizardStage.component &&
                    _selected?.previewBuilder != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: ComponentAddPreview(
                      keyPrefix: widget.keyPrefix,
                      candidate: _selected!,
                    ),
                  ),
              ],
            );
          },
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
  }

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

  Widget _buildChoice(BuildContext context) => ComponentAddChoicePanel(
    keyPrefix: widget.keyPrefix,
    candidates: _offered,
    selected: _selected,
    selectedFamily: _selectedFamily,
    query: _query,
    emptyMessage: widget.emptyMessage,
    onQueryChanged: (value) => setState(() => _query = value),
    onFamilySelected: _selectFamily,
    onSelect: _select,
    onAddDirectly: _addDirectly,
  );

  Widget _buildSettings(BuildContext context, ComponentAddCandidate candidate) {
    final theme = Theme.of(context);
    final draft = _draftOf(candidate, context);
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
  ) => ComponentAddPlacementPanel(
    keyPrefix: widget.keyPrefix,
    usesRelativePlacements: widget.placements != null,
    placements: _placementsFor(candidate),
    selectedPlacement: _placement,
    targets: _targetsFor(candidate),
    target: _target,
    beforeId: _beforeId,
    customSize: _customSize,
    size: _size,
    onCustomSizeChanged: (value) => setState(() => _customSize = value),
    onTargetChanged: (value) {
      _clearHoveredPreview();
      setState(() {
        _targetId = value ?? widget.initialTargetId;
        _beforeId = null;
      });
    },
    onBeforeChanged: (value) {
      _clearHoveredPreview();
      setState(() => _beforeId = value);
    },
    onPlacementSelected: (value) => setState(() => _placementId = value),
    onSetHoveredPreview: _setHoveredPreview,
    onClearHoveredPreview: _clearHoveredPreview,
    onSizeChanged: () => setState(() {}),
  );

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
    final placement = widget.placements == null ? null : _placement;
    final target = placement == null ? _target : null;
    final position = target == null
        ? (placement?.label ?? 'Emplacement par défaut')
        : target.replaces
        ? (target.siblings.isEmpty ? 'Unique' : 'Remplace le contenu actuel')
        : _beforeId == null
        ? 'À la fin'
        : 'Avant ${target.siblings.where((s) => s.$1 == _beforeId).firstOrNull?.$2 ?? _beforeId}';
    final draft = _draftOf(candidate);
    final lines = <(String, String)>[
      ('Composant', candidate.label),
      if (candidate.tags.isNotEmpty) ('Tags', candidate.tags.join(', ')),
      if (target != null) ('Zone', target.label),
      if (placement != null) ('Par rapport à', placement.group),
      ('Position', position),
      if (placement?.hint case final hint?) ('Structure', hint),
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
