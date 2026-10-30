import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../../models/component_behavior.dart';
import '../../../super_app.dart';
import '../../../theme/appearance.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../dialogs/editor_target_selector.dart';
import '../history/editor_history.dart';

/// Element cible pouvant recevoir un comportement.
@immutable
class BehaviorTargetElement implements EditorTargetItem {
  const BehaviorTargetElement({
    required this.id,
    required this.label,
    this.icon,
    this.depth = 0,
    this.existingBehaviors = const [],
  });

  final String id;
  final String label;
  final IconData? icon;
  final int depth;
  final List<ComponentBehavior> existingBehaviors;
}

/// Etapes du wizard d'ajout de comportement.
enum BehaviorWizardStage {
  target('Element'),
  catalog('Comportement'),
  settings('Configuration'),
  summary('Recapitulatif');

  const BehaviorWizardStage(this.title);
  final String title;
}

/// Ouvre le wizard de comportements pour choisir un element cible et son action.
Future<ComponentBehavior?> showComponentBehaviorWizard({
  required BuildContext context,
  required List<BehaviorTargetElement> targets,
  BuildContext? target,
  String title = 'Ajouter un comportement',
  String keyPrefix = 'behavior',
}) async {
  if (targets.isEmpty) return null;
  final widthNotifier = ValueNotifier(640.0);
  try {
    return await showEditorDialog<ComponentBehavior>(
      context: context,
      target: target,
      preferredWidth: widthNotifier,
      builder: (_) => ComponentBehaviorWizard(
        ownerContext: context,
        title: title,
        keyPrefix: keyPrefix,
        targets: targets,
      ),
    );
  } finally {
    widthNotifier.dispose();
  }
}

/// Ouvre l'editeur/wizard de comportements pour un composant donne.
Future<void> showComponentBehaviorEditor({
  required BuildContext context,
  required String componentId,
  required String componentLabel,
  List<BehaviorTargetElement>? targets,
}) async {
  final appearance = AppearanceScope.controllerOf(context)?.value;
  final effectiveTargets =
      targets ??
      [
        BehaviorTargetElement(
          id: componentId,
          label: componentLabel,
          existingBehaviors: appearance?.behaviorsFor(componentId) ?? const [],
        ),
      ];
  await showComponentBehaviorWizard(
    context: context,
    targets: effectiveTargets,
  );
}

class ComponentBehaviorWizard extends StatefulWidget {
  const ComponentBehaviorWizard({
    required this.ownerContext,
    required this.title,
    required this.keyPrefix,
    required this.targets,
    super.key,
  });

  final BuildContext ownerContext;
  final String title;
  final String keyPrefix;
  final List<BehaviorTargetElement> targets;

  @override
  State<ComponentBehaviorWizard> createState() =>
      _ComponentBehaviorWizardState();
}

class _ComponentBehaviorWizardState extends State<ComponentBehaviorWizard> {
  int _step = 0;
  late BehaviorTargetElement _selectedTarget;
  BehaviorCatalogItem _selectedCatalogItem = BehaviorCatalog.goToPage;
  String? _selectedPageId;
  String? _selectedPagePath;
  String? _selectedPageName;
  bool _customPath = false;
  late final TextEditingController _customPathController =
      TextEditingController(text: '/');
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _selectedTarget = widget.targets.first;
    _initDefaultPage();
  }

  void _initDefaultPage() {
    final appearance = AppearanceScope.controllerOf(widget.ownerContext)?.value;
    final catalog = appearance?.pageCatalog;
    if (catalog != null && catalog.pages.isNotEmpty) {
      final first = catalog.pages.first;
      _selectedPageId = first.id;
      _selectedPagePath = first.path;
      _selectedPageName = first.name;
    } else {
      _customPath = true;
    }
  }

  @override
  void dispose() {
    _customPathController.dispose();
    super.dispose();
  }

  BehaviorWizardStage get _stage => BehaviorWizardStage.values[_step];

  bool get _canContinue => switch (_stage) {
    BehaviorWizardStage.target => true,
    BehaviorWizardStage.catalog => true,
    BehaviorWizardStage.settings =>
      !_customPath ? _selectedPagePath != null : _isCustomPathValid,
    BehaviorWizardStage.summary => true,
  };

  bool get _isCustomPathValid {
    final text = _customPathController.text.trim();
    return text.isNotEmpty && text.startsWith('/');
  }

  void _next() {
    if (!_canContinue) return;
    if (_step < BehaviorWizardStage.values.length - 1) {
      setState(() => _step++);
      return;
    }
    _apply();
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  void _apply() {
    final path = _customPath
        ? _customPathController.text.trim()
        : (_selectedPagePath ?? '/');

    final action = GoToPageAction(
      pagePath: path,
      pageId: _customPath ? null : _selectedPageId,
      pageName: _customPath ? null : _selectedPageName,
    );

    final behavior = ComponentBehavior(
      id: 'behavior-${shortid.generate()}',
      trigger: _selectedCatalogItem.trigger,
      action: action,
    );

    final appearanceController = AppearanceScope.controllerOf(
      widget.ownerContext,
    );
    final history = EditorHistoryScope.controllerOf(widget.ownerContext);
    history?.beginTransaction();
    try {
      if (appearanceController != null) {
        appearanceController.value = appearanceController.value
            .withAddedBehavior(_selectedTarget.id, behavior);
      }
    } finally {
      history?.commitTransaction();
    }

    Navigator.of(context).pop(behavior);
  }

  void _removeExistingBehavior(String behaviorId) {
    final appearanceController = AppearanceScope.controllerOf(
      widget.ownerContext,
    );
    final history = EditorHistoryScope.controllerOf(widget.ownerContext);
    history?.beginTransaction();
    try {
      if (appearanceController != null) {
        appearanceController.value = appearanceController.value
            .withRemovedBehavior(_selectedTarget.id, behaviorId);
      }
    } finally {
      history?.commitTransaction();
    }
    setState(() {});
  }

  bool _titlesFit(BuildContext context, double width) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    var needed = 48.0 + (BehaviorWizardStage.values.length - 1) * 16;
    for (final stage in BehaviorWizardStage.values) {
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: ValueKey('${widget.keyPrefix}-add-wizard'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      title: EditorDialogHeader(label: widget.title),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
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
                if (step < _step || (step == _step + 1 && _canContinue)) {
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
            child: const Text('Precedent'),
          ),
        FilledButton(
          key: ValueKey(
            _stage == BehaviorWizardStage.summary
                ? '${widget.keyPrefix}-add-submit'
                : '${widget.keyPrefix}-add-next',
          ),
          onPressed: _canContinue ? _next : null,
          child: Text(
            _stage == BehaviorWizardStage.summary ? 'Appliquer' : 'Suivant',
          ),
        ),
      ],
    );
  }

  List<Step> _steps(BuildContext context, {required bool allTitles}) => [
    for (final (index, stage) in BehaviorWizardStage.values.indexed)
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
        isActive: _step >= index,
        state: _step > index ? StepState.complete : StepState.indexed,
        content: _step != index
            ? const SizedBox.shrink()
            : switch (stage) {
                BehaviorWizardStage.target => _buildTargetStep(context),
                BehaviorWizardStage.catalog => _buildCatalogStep(context),
                BehaviorWizardStage.settings => _buildSettingsStep(context),
                BehaviorWizardStage.summary => _buildSummaryStep(context),
              },
      ),
  ];

  Widget _buildTargetStep(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appearance = AppearanceScope.controllerOf(widget.ownerContext)?.value;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorTargetSelector<BehaviorTargetElement>(
            targets: widget.targets,
            selected: _selectedTarget,
            onSelected: (target) => setState(() => _selectedTarget = target),
            subtitle:
                'Sélectionnez le composant qui déclenchera ce comportement :',
            itemKeyBuilder: (target) =>
                ValueKey('${widget.keyPrefix}-target-${target.id}'),
            isSelectedPredicate: (target, selected) => target.id == selected.id,
            trailingBuilder: (context, target) {
              final existing =
                  appearance?.behaviorsFor(target.id) ??
                  target.existingBehaviors;
              if (existing.isEmpty) return null;
              return Chip(
                label: Text(
                  '${existing.length} comportement${existing.length > 1 ? 's' : ''}',
                  style: theme.textTheme.labelSmall,
                ),
                padding: EdgeInsets.zero,
              );
            },
          ),
          Builder(
            builder: (context) {
              final existing =
                  appearance?.behaviorsFor(_selectedTarget.id) ??
                  _selectedTarget.existingBehaviors;
              if (existing.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'Comportements deja existants sur cet element :',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final b in existing)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(b.action.icon, color: colors.primary),
                        title: Text(b.action.label),
                        subtitle: Text(
                          '${b.trigger.description} -> ${b.action.description}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow_outlined),
                              tooltip: 'Tester',
                              onPressed: () => b.execute(widget.ownerContext),
                            ),
                            IconButton(
                              key: ValueKey('behavior-delete-${b.id}'),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Supprimer',
                              color: colors.error,
                              onPressed: () => _removeExistingBehavior(b.id),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogStep(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Catalogue de comportements',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sélectionnez l’action à associer à « ${_selectedTarget.label} » :',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in BehaviorCatalog.items) ...[
            Builder(
              builder: (context) {
                final isSelected = _selectedCatalogItem.id == item.id;
                return Card(
                  key: ValueKey('${widget.keyPrefix}-catalog-${item.id}'),
                  elevation: isSelected ? 2 : 0,
                  color: isSelected
                      ? colors.primaryContainer.withValues(alpha: .3)
                      : colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? colors.primary
                          : colors.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _selectedCatalogItem = item),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: isSelected ? colors.primary : colors.outline,
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.primary
                                  : colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              item.icon,
                              size: 22,
                              color: isSelected
                                  ? colors.onPrimary
                                  : colors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  item.description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: Text(
                              item.trigger.description,
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsStep(BuildContext context) {
    final theme = Theme.of(context);
    final appearance = AppearanceScope.controllerOf(widget.ownerContext)?.value;
    final pageCatalog = appearance?.pageCatalog;
    final codedRoutes =
        SuperApp.maybeOf(widget.ownerContext)?.pageRouting?.codedRoutes ??
        const [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Configuration de l’action : ${_selectedCatalogItem.title}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            dense: true,
            leading: const Icon(Icons.touch_app_outlined),
            title: const Text('Declencheur'),
            subtitle: Text(_selectedCatalogItem.trigger.description),
          ),
          const SizedBox(height: 12),
          Text(
            'Destination du clic',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if ((pageCatalog?.pages.isNotEmpty ?? false) ||
              codedRoutes.isNotEmpty) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  tooltip: 'Page du catalogue',
                  label: Text('Page du catalogue'),
                  icon: Icon(Icons.pages_outlined),
                ),
                ButtonSegment(
                  value: true,
                  tooltip: 'Chemin personnalise',
                  label: Text('Chemin personnalise'),
                  icon: Icon(Icons.link),
                ),
              ],
              selected: {_customPath},
              onSelectionChanged: (set) {
                setState(() => _customPath = set.first);
              },
            ),
            const SizedBox(height: 12),
            if (!_customPath)
              DropdownButtonFormField<String>(
                key: const ValueKey('behavior-page-dropdown'),
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Selectionner une page',
                ),
                initialValue:
                    _selectedPageId ??
                    (pageCatalog != null && pageCatalog.pages.isNotEmpty
                        ? pageCatalog.pages.first.id
                        : null),
                items: [
                  if (pageCatalog != null)
                    for (final page in pageCatalog.pages)
                      DropdownMenuItem(
                        value: page.id,
                        child: Text(
                          '${page.name} (${page.path})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  for (final route in codedRoutes)
                    DropdownMenuItem(
                      value: '__route_${route.path}',
                      child: Text(
                        'Route: ${route.label} (${route.path})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  if (value.startsWith('__route_')) {
                    final path = value.replaceFirst('__route_', '');
                    setState(() {
                      _selectedPageId = value;
                      _selectedPagePath = path;
                      _selectedPageName = path;
                    });
                  } else if (pageCatalog != null) {
                    final page = pageCatalog.pages
                        .where((p) => p.id == value)
                        .firstOrNull;
                    if (page != null) {
                      setState(() {
                        _selectedPageId = page.id;
                        _selectedPagePath = page.path;
                        _selectedPageName = page.name;
                      });
                    }
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
          if (_customPath)
            Form(
              key: _formKey,
              child: TextFormField(
                key: const ValueKey('behavior-custom-path-input'),
                controller: _customPathController,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Chemin (URL)',
                  hintText: '/page',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) {
                    return 'Le chemin ne peut pas etre vide.';
                  }
                  if (!text.startsWith('/')) {
                    return 'Le chemin doit commencer par "/".';
                  }
                  return null;
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryStep(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final path = _customPath
        ? _customPathController.text.trim()
        : (_selectedPagePath ?? '/');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Recapitulatif du comportement',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _summaryRow(
                    context,
                    icon: Icons.widgets_outlined,
                    label: 'Element cible',
                    value: '${_selectedTarget.label} (${_selectedTarget.id})',
                  ),
                  const Divider(height: 16),
                  _summaryRow(
                    context,
                    icon: Icons.touch_app_outlined,
                    label: 'Declencheur',
                    value: _selectedCatalogItem.trigger.description,
                  ),
                  const Divider(height: 16),
                  _summaryRow(
                    context,
                    icon: _selectedCatalogItem.icon,
                    label: 'Action',
                    value: _selectedCatalogItem.title,
                  ),
                  const Divider(height: 16),
                  _summaryRow(
                    context,
                    icon: Icons.alt_route,
                    label: 'Destination',
                    value: _customPath
                        ? path
                        : (_selectedPageName != null
                              ? '$_selectedPageName ($path)'
                              : path),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
