/// Éditeur des comportements interactifs ([ComponentBehaviorWizard]) d'un composant.
///
/// Permet d'ajouter, activer/désactiver, modifier ou supprimer des comportements
/// ([ComponentBehavior]) organisés autour de leurs 3 paramètres explicites :
/// 1. Événement déclencheur ([BehaviorEvent]) ;
/// 2. Action à exécuter ([BehaviorAction]) ;
/// 3. Validateur optionnel ([BehaviorValidator]).
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shortid/shortid.dart';

import '../../../models/component_behavior.dart';
import '../../../models/component_config.dart';
import '../../../models/datasources/datasource_config.dart';
import '../../../models/editor_page_config.dart';
import '../../../models/json_text_binding.dart';
import '../../../models/native_component_config.dart';
import '../../../models/super_action_config.dart';
import '../../../models/super_conditional_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../models/super_table_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../models/super_value_config.dart';
import '../../../services/diagnostics/debug_entry.dart';
import '../../../services/inspection/vibe_debug_capture.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_schema_field_resolver.dart';
import '../../../super_app.dart';
import '../../../theme/appearance.dart';
import '../../appearance/appearance_scope.dart';
import '../../components/super_layout/super_layout.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';
import '../dialogs/editor_target_selector.dart';
import '../history/editor_history.dart';
import '../repositories/repository_binding_fields.dart';
import '../slots/editor_slot.dart';
import 'behavior_event_picker.dart';
import 'behavior_validator_editor.dart';
import 'datasource_action_settings.dart';
import 'search_provider_settings.dart';

export 'behavior_event_picker.dart';
export 'behavior_validator_editor.dart';

/// Élément cible pouvant recevoir un comportement.
@immutable
class BehaviorTargetElement implements EditorTargetItem {
  /// Crée une cible de comportement pour l'assistant.
  const BehaviorTargetElement({
    required this.id,
    required this.label,
    this.slot,
    this.icon,
    this.depth = 0,
    this.existingBehaviors = const [],
  });

  @override
  final String id;
  @override
  final String label;
  @override
  final EditorSlotState? slot;
  @override
  final IconData? icon;
  @override
  final int depth;

  /// Comportements déjà associés à cet élément.
  final List<ComponentBehavior> existingBehaviors;
}

/// Étapes du wizard d'ajout et d'édition de comportement.
enum BehaviorWizardStage {
  /// Étape 1 : sélection du composant cible et gestion des comportements existants.
  target('Élément'),

  /// Étape 2 : choix de l'événement déclencheur ([BehaviorEvent]).
  event('Événement'),

  /// Étape 3 : choix et paramétrage de l'action ([BehaviorAction]).
  action('Action'),

  /// Étape 4 : configuration du validateur conditionnel ([BehaviorValidator]).
  validator('Validateur'),

  /// Étape 5 : récapitulatif complet avant application.
  summary('Récapitulatif');

  const BehaviorWizardStage(this.title);

  /// Libellé français affiché dans le bandeau du stepper.
  final String title;
}

/// Ouvre l'assistant pour ajouter, modifier ou supprimer un comportement.
Future<ComponentBehavior?> showComponentBehaviorWizard({
  required BuildContext context,
  required List<BehaviorTargetElement> targets,
  BuildContext? target,
  String title = 'Gérer les comportements',
  String keyPrefix = 'behavior',
}) async {
  if (targets.isEmpty) return null;
  final widthNotifier = ValueNotifier(680.0);
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

/// Interface d'édition des comportements ([ComponentBehavior]) associés à un composant.
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
  ComponentBehavior? _editing;
  String? _saveError;
  BehaviorEvent _selectedEvent = BehaviorEvent.onTap;
  BehaviorCatalogItem _selectedCatalogItem = BehaviorCatalog.goToPage;
  BehaviorValidator? _validator;
  bool _validatorValid = true;
  final _eventIdController = TextEditingController();
  final _customJsonController = TextEditingController(text: '{}');
  String? _selectedPageId;
  String? _selectedPagePath;
  String? _selectedPageName;
  bool _customPath = false;
  late final TextEditingController _customPathController =
      TextEditingController(text: '/');
  final _formKey = GlobalKey<FormState>();
  SuperLayoutZone _zone = SuperLayoutZone.west;
  JsonTextBinding? _zoneBinding;
  SlotSizeUnit _zoneUnit = SlotSizeUnit.pixels;
  final _durationController = TextEditingController(
    text: '${ZoneSizeBindingAction.defaultDurationMs}',
  );
  BehaviorCurve _curve = BehaviorCurve.easeInOut;
  final _tooltipMessage = TextEditingController();
  JsonTextBinding? _tooltipBinding;
  BehaviorBoundState _boundState = BehaviorBoundState.invisible;
  JsonTextBinding? _stateBinding;
  bool _stateWhenValue = true;
  bool _stateMaintainSize = false;
  String? _selectedProviderId;
  DatasourceActionDraft _datasourceDraft = DatasourceActionSettings.empty;
  String? _pdfPageId;
  String? _pdfPageName;
  PdfOutputMode _pdfOutputMode = PdfOutputMode.exportDialog;
  final _pdfFileNameController = TextEditingController();
  JsonTextBinding? _addArrayBinding;
  bool _addArraySelectCreated = true;
  JsonTextBinding? _creationDefaultBinding;
  final _creationDefaultController = TextEditingController();
  final _scriptRepositoryController = TextEditingController();
  final _scriptCodeController = TextEditingController(
    text: "ctx.set('status', 'done');",
  );
  bool _creationDefaultUseNull = false;
  bool? _creationDefaultBool;

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
    VibeDebugCapture.clearComponentDiagnostics(
      'behavior-editor:${_selectedTarget.id}',
    );
    _eventIdController.dispose();
    _customJsonController.dispose();
    _customPathController.dispose();
    _durationController.dispose();
    _tooltipMessage.dispose();
    _pdfFileNameController.dispose();
    _creationDefaultController.dispose();
    _scriptRepositoryController.dispose();
    _scriptCodeController.dispose();
    super.dispose();
  }

  BehaviorWizardStage get _stage => BehaviorWizardStage.values[_step];

  int get _firstStep => _editing == null ? 0 : BehaviorWizardStage.event.index;

  BehaviorCatalogItem? _editorFor(BehaviorAction action) => switch (action) {
    GoToPageAction() => BehaviorCatalog.goToPage,
    EmitEventAction() => BehaviorCatalog.emitEvent,
    TooltipAction() => BehaviorCatalog.onTooltip,
    StateBindingAction() => BehaviorCatalog.bindState,
    ZoneSizeBindingAction() => BehaviorCatalog.zoneSize,
    SearchProviderAction() => BehaviorCatalog.searchProvider,
    DatasourceAction() => BehaviorCatalog.datasource,
    GeneratePdfAction() => BehaviorCatalog.generatePdf,
    AddArrayItemAction() => BehaviorCatalog.addArrayItem,
    CreationDefaultAction() => BehaviorCatalog.creationDefault,
    RunJavaScriptAction() => BehaviorCatalog.runJavaScript,
    _ => null,
  };

  void _editBehavior(ComponentBehavior behavior, BehaviorCatalogItem item) {
    setState(() {
      _editing = behavior;
      _saveError = null;
      _selectedEvent = behavior.event;
      _validator = behavior.validator;
      _validatorValid = true;
      _selectedCatalogItem = item;
      _step = BehaviorWizardStage.event.index;
      switch (behavior.action) {
        case GoToPageAction a:
          _customPath = a.pageId == null;
          _customPathController.text = a.pagePath;
          _selectedPageId = a.pageId;
          _selectedPagePath = a.pagePath;
          _selectedPageName = a.pageName;
        case EmitEventAction a:
          _eventIdController.text = a.eventId;
          _customJsonController.text = jsonEncode(a.custom);
        case TooltipAction a:
          _tooltipMessage.text = a.message;
          _tooltipBinding = a.binding;
        case StateBindingAction a:
          _boundState = a.state;
          _stateBinding = a.binding;
          _stateWhenValue = a.whenValue;
          _stateMaintainSize = a.maintainSize;
        case ZoneSizeBindingAction a:
          _zone = a.zone;
          _zoneBinding = a.binding;
          _zoneUnit = a.unit;
          _durationController.text = '${a.durationMs}';
          _curve = a.curve;
        case SearchProviderAction a:
          _selectedProviderId = a.providerId;
        case DatasourceAction a:
          _datasourceDraft = (
            datasourceId: a.datasourceId,
            command: a.command,
            field: a.field ?? '',
            direction: a.direction,
          );
        case GeneratePdfAction a:
          _pdfPageId = a.pageId;
          _pdfPageName = a.pageName;
          _pdfOutputMode = a.outputMode;
          _pdfFileNameController.text = a.fileName ?? '';
        case AddArrayItemAction a:
          _addArrayBinding = a.binding;
          _addArraySelectCreated = a.selectCreated;
        case CreationDefaultAction a:
          _creationDefaultBinding = a.binding;
          final value = a.defaultValue;
          _creationDefaultUseNull = value == null;
          _creationDefaultBool = value is bool ? value : null;
          _creationDefaultController.text = _creationValueText(value);
        case RunJavaScriptAction a:
          _scriptRepositoryController.text = a.repositoryId ?? '';
          _scriptCodeController.text = a.code;
      }
    });
  }

  String _creationValueText(Object? value) => value is String
      ? value
      : value == null
      ? ''
      : jsonEncode(value);

  bool get _isEvent => _selectedCatalogItem.actionType == 'emitEvent';
  bool get _isTooltip => _selectedCatalogItem.actionType == 'onTooltip';

  String? get _tooltipError {
    try {
      TooltipAction(
        message: _tooltipMessage.text,
        binding: _tooltipBinding,
      ).validate();
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  bool get _isZoneSize => _selectedCatalogItem.actionType == 'bindZoneSize';
  bool get _isBindState => _selectedCatalogItem.actionType == 'bindState';
  bool get _isSearchProvider =>
      _selectedCatalogItem.actionType == 'searchProvider';
  bool get _isDatasource => _selectedCatalogItem.actionType == 'datasource';
  bool get _isGeneratePdf => _selectedCatalogItem.actionType == 'generatePdf';
  bool get _isAddArrayItem => _selectedCatalogItem.actionType == 'addArrayItem';
  bool get _isCreationDefault =>
      _selectedCatalogItem.actionType == 'creationDefault';
  bool get _isJavaScriptAction =>
      _selectedCatalogItem.actionType == 'runJavaScript';

  DatasourceConfig? get _selectedDatasource {
    final id = _datasourceDraft.datasourceId;
    if (id == null) return null;
    final targetContext = _targetSlot?.context ?? widget.ownerContext;
    return JsonRepositoryScope.maybeOf(targetContext)?.datasources
        .datasource(id);
  }

  DatasourceAction? get _datasourceAction => DatasourceActionSettings.actionOf(
    _datasourceDraft,
    _selectedDatasource,
  ).action;

  EditorSlotState? get _targetSlot {
    final slot = _selectedTarget.slot;
    return slot != null && slot.mounted ? slot : null;
  }

  bool _isLayoutTarget(BehaviorTargetElement target) {
    final slot = target.slot;
    if (slot != null &&
        slot.mounted &&
        slot.widget.eventComponentType == 'layout') {
      return true;
    }
    final appearance = AppearanceScope.controllerOf(widget.ownerContext)?.value;
    return appearance?.components[target.id] is SuperLayoutConfig;
  }

  bool _isValueTarget(BehaviorTargetElement target) {
    final slot = target.slot;
    if (slot != null &&
        slot.mounted &&
        slot.widget.eventComponentType == 'value') {
      return true;
    }
    final appearance = AppearanceScope.controllerOf(widget.ownerContext)?.value;
    return appearance?.components[target.id] is SuperValueConfig;
  }

  String? _componentTypeFor(BehaviorTargetElement target) {
    final slot = target.slot;
    if (slot != null &&
        slot.mounted &&
        slot.widget.eventComponentType.isNotEmpty &&
        slot.widget.eventComponentType != 'component') {
      return slot.widget.eventComponentType;
    }
    final appearance = AppearanceScope.controllerOf(widget.ownerContext)?.value;
    final config = appearance?.components[target.id];
    if (config != null) return config.componentType;
    return null;
  }

  List<BehaviorCatalogItem> _catalogItemsFor(
    BehaviorEvent event,
    BehaviorTargetElement target,
  ) => [
    for (final item in BehaviorCatalog.items)
      if (item.supportsEvent(event) &&
          ((_editing?.action.type == item.actionType &&
                  _editing?.event == event) ||
              ((item.actionType != 'bindZoneSize' || _isLayoutTarget(target)) &&
                  (item.actionType != 'creationDefault' ||
                      _isValueTarget(target)))))
        item,
  ];

  List<BehaviorCatalogItem> get _compatibleCatalogItems =>
      _catalogItemsFor(_selectedEvent, _selectedTarget);

  void _onEventSelected(BehaviorEvent event) {
    setState(() {
      _selectedEvent = event;
      final compatible = _catalogItemsFor(event, _selectedTarget);
      if (compatible.isNotEmpty &&
          (!_selectedCatalogItem.supportsEvent(event) ||
              !compatible.any((item) => item.id == _selectedCatalogItem.id))) {
        _selectedCatalogItem = compatible.first;
      }
    });
  }

  void _onTargetSelected(BehaviorTargetElement target) {
    setState(() {
      _selectedTarget = target;
      _saveError = null;
      if (_selectedEvent == BehaviorEvent.onCreate && !_isValueTarget(target)) {
        _selectedEvent = BehaviorEvent.onTap;
      }
      final compatible = _catalogItemsFor(_selectedEvent, target);
      if (compatible.isNotEmpty &&
          !compatible.any((item) => item.id == _selectedCatalogItem.id)) {
        _selectedCatalogItem = compatible.first;
      }
    });
  }

  JsonTextBinding? get _targetValueBinding {
    final appearance = AppearanceScope.controllerOf(widget.ownerContext)?.value;
    final cfg = appearance?.components[_selectedTarget.id];
    return cfg is SuperValueConfig ? cfg.binding : null;
  }

  JsonTextBinding? get _effectiveCreationDefaultBinding =>
      _creationDefaultBinding ?? _targetValueBinding;

  Object? _resolveCreationDefaultValue() {
    if (_creationDefaultUseNull) return null;
    if (_creationDefaultBool != null) return _creationDefaultBool!;
    final text = _creationDefaultController.text;
    if (_editing?.action case CreationDefaultAction(:final defaultValue)) {
      if (text == _creationValueText(defaultValue) &&
          defaultValue != null &&
          defaultValue is! bool) {
        return defaultValue;
      }
    }
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) {
      final asInt = int.tryParse(trimmed);
      if (asInt != null && trimmed == '$asInt') return asInt;
      final asDouble = double.tryParse(trimmed.replaceAll(',', '.'));
      if (asDouble != null && RegExp(r'^-?\d+(?:[.,]\d+)$').hasMatch(trimmed)) {
        return asDouble;
      }
      if (trimmed == 'true') return true;
      if (trimmed == 'false') return false;
    }
    return text;
  }

  /// Côtés visibles du layout ciblé (tous à défaut).
  List<SuperLayoutZone> get _layoutSides {
    final original = _editing?.action;
    final originalZone = original is ZoneSizeBindingAction
        ? original.zone
        : null;
    final zones = _targetSlot?.context
        .findAncestorStateOfType<SuperLayoutState>()
        ?.config
        .visibleZones;
    final sides = [
      for (final zone in SuperLayoutZone.values)
        if (zone.isSide &&
            (zones == null || zones.contains(zone) || originalZone == zone))
          zone,
    ];
    return sides.isEmpty
        ? [
            for (final zone in SuperLayoutZone.values)
              if (zone.isSide) zone,
          ]
        : sides;
  }

  SuperLayoutZone get _effectiveZone {
    final sides = _layoutSides;
    return sides.contains(_zone) ? _zone : sides.first;
  }

  int? get _durationMs {
    final value = int.tryParse(_durationController.text.trim());
    return value == null || value < 0 || value > 10000 ? null : value;
  }

  String get _customJsonText => _customJsonController.text.trim().isEmpty
      ? '{}'
      : _customJsonController.text;

  String? get _customJsonError {
    try {
      final decoded = jsonDecode(_customJsonText);
      if (decoded is! Map<String, dynamic>) return 'Un objet JSON est requis.';
      EmitEventAction(eventId: 'validation', custom: decoded);
      return null;
    } on FormatException catch (error) {
      return 'JSON invalide : ${error.message}';
    } on ArgumentError catch (error) {
      return 'JSON invalide : ${error.message}';
    }
  }

  bool get _isActionSettingsValid => _isTooltip
      ? _tooltipError == null
      : _isSearchProvider
      ? _selectedProviderId != null
      : _isDatasource
      ? _datasourceAction != null
      : _isGeneratePdf
      ? true
      : _isAddArrayItem
      ? _addArrayBinding != null &&
            _addArrayBinding!.path.trim().isNotEmpty &&
            !JsonTextBinding.isCalculatedPath(_addArrayBinding!.path)
      : _isCreationDefault
      ? _effectiveCreationDefaultBinding != null
      : _isJavaScriptAction
      ? _isJavaScriptActionValid
      : _isBindState
      ? _stateBinding != null
      : _isZoneSize
      ? _zoneBinding != null && _durationMs != null
      : _isEvent
      ? _eventIdController.text.trim().isNotEmpty && _customJsonError == null
      : (!_customPath ? _selectedPagePath != null : _isCustomPathValid);

  bool get _canContinue => switch (_stage) {
    BehaviorWizardStage.target => true,
    BehaviorWizardStage.event => _compatibleCatalogItems.isNotEmpty,
    BehaviorWizardStage.action =>
      _compatibleCatalogItems.isNotEmpty && _isActionSettingsValid,
    BehaviorWizardStage.validator => _validatorValid,
    BehaviorWizardStage.summary => _isActionSettingsValid && _validatorValid,
  };

  bool get _isCustomPathValid {
    final text = _customPathController.text.trim();
    return text.isNotEmpty && text.startsWith('/');
  }

  bool get _isJavaScriptActionValid {
    try {
      RunJavaScriptAction(
        code: _scriptCodeController.text,
        repositoryId: _scriptRepositoryController.text.trim().isEmpty
            ? null
            : _scriptRepositoryController.text.trim(),
      ).validate();
      return true;
    } on FormatException {
      return false;
    }
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
    if (_step > _firstStep) setState(() => _step--);
  }

  BehaviorAction _buildDraftAction() {
    final path = _customPath
        ? _customPathController.text.trim()
        : (_selectedPagePath ?? '/');

    return _isTooltip
        ? TooltipAction(message: _tooltipMessage.text, binding: _tooltipBinding)
        : _isSearchProvider
        ? SearchProviderAction(providerId: _selectedProviderId!)
        : _isDatasource
        ? _datasourceAction!
        : _isGeneratePdf
        ? GeneratePdfAction(
            pageId: _pdfPageId,
            pageName: _pdfPageName,
            fileName: _pdfFileNameController.text.trim().isEmpty
                ? null
                : _pdfFileNameController.text.trim(),
            outputMode: _pdfOutputMode,
          )
        : _isAddArrayItem
        ? AddArrayItemAction(
            binding: _addArrayBinding!,
            selectCreated: _addArraySelectCreated,
          )
        : _isCreationDefault
        ? CreationDefaultAction(
            defaultValue: _resolveCreationDefaultValue(),
            binding: _creationDefaultBinding,
          )
        : _isBindState
        ? StateBindingAction(
            state: _boundState,
            binding: _stateBinding!,
            whenValue: _stateWhenValue,
            maintainSize:
                _boundState == BehaviorBoundState.invisible &&
                _stateMaintainSize,
          )
        : _isZoneSize
        ? ZoneSizeBindingAction(
            zone: _effectiveZone,
            binding: _zoneBinding!,
            unit: _zoneUnit,
            durationMs: _durationMs!,
            curve: _curve,
          )
        : _isEvent
        ? EmitEventAction(
            eventId: _eventIdController.text.trim(),
            custom: jsonDecode(_customJsonText) as Map<String, dynamic>,
          )
        : _isJavaScriptAction
        ? RunJavaScriptAction(
            code: _scriptCodeController.text,
            repositoryId: _scriptRepositoryController.text.trim().isEmpty
                ? null
                : _scriptRepositoryController.text.trim(),
          )
        : GoToPageAction(
            pagePath: path,
            pageId: _customPath ? null : _selectedPageId,
            pageName: _customPath ? null : _selectedPageName,
          );
  }

  void _apply() {
    final BehaviorAction action;
    final ComponentBehavior behavior;
    try {
      action = _buildDraftAction();
      behavior = ComponentBehavior(
        id: _editing?.id ?? 'behavior-${shortid.generate()}',
        event: _selectedEvent,
        action: action,
        validator: _validator,
        enabled: _editing?.enabled ?? true,
      );
      behavior.validate();
    } on FormatException catch (error, stack) {
      VibeDebugCapture.recordTypedError(
        message: error.message,
        category: _selectedCatalogItem.actionType == 'runJavaScript'
            ? DebugErrorCategory.javascript
            : DebugErrorCategory.userInput,
        severity: DebugSeverity.warning,
        stackTrace: stack,
        componentId: _selectedTarget.id,
        source: 'ComponentBehaviorEditor.save',
        visibleInUi: true,
      );
      setState(() => _saveError = error.message);
      return;
    }

    final appearanceController = AppearanceScope.controllerOf(
      widget.ownerContext,
    );
    final targetId = _selectedTarget.id;
    if (_editing != null &&
        !(appearanceController?.value
                .behaviorsFor(targetId)
                .any((b) => b.id == behavior.id) ??
            false)) {
      setState(
        () => _saveError = 'Ce comportement n’existe plus sur cet élément.',
      );
      return;
    }
    final history = EditorHistoryScope.controllerOf(widget.ownerContext);
    history?.beginTransaction();
    try {
      if (appearanceController != null) {
        final appearance = appearanceController.value;
        appearanceController.value = _editing == null
            ? appearance.withAddedBehavior(targetId, behavior)
            : appearance.withReplacedBehavior(targetId, behavior);
      }
    } finally {
      history?.commitTransaction();
    }

    Navigator.of(context).pop(behavior);
  }

  void _toggleExistingBehavior(ComponentBehavior behavior, bool enabled) {
    final appearanceController = AppearanceScope.controllerOf(
      widget.ownerContext,
    );
    if (appearanceController == null) return;
    final history = EditorHistoryScope.controllerOf(widget.ownerContext);
    history?.beginTransaction();
    try {
      appearanceController.value = appearanceController.value
          .withReplacedBehavior(
            _selectedTarget.id,
            behavior.copyWith(enabled: enabled),
          );
    } finally {
      history?.commitTransaction();
    }
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
  }

  List<ValidatorTargetComponentOption> _collectValidatorTargets(
    Appearance? appearance,
  ) {
    final slotLabels = <String, String>{};
    if (appearance != null) {
      for (final config in appearance.components.values) {
        final map = switch (config) {
          SuperLayoutConfig c => c.slotLabels,
          NativeComponentConfig c => c.slotLabels,
          SuperConditionalConfig c => c.slotLabels,
          SuperTableConfig c => c.slotLabels,
          SuperTabConfig c => c.slotLabels,
          SuperTreeViewConfig c => c.slotLabels,
          _ => const <String, String>{},
        };
        for (final entry in map.entries) {
          final label = entry.value.trim();
          if (label.isNotEmpty) {
            slotLabels.putIfAbsent(entry.key, () => label);
          }
        }
      }
    }

    final referencedIds = _validator?.referencedComponentIds ?? const {};
    final optionsById = <String, ValidatorTargetComponentOption>{};

    if (appearance != null) {
      for (final entry in appearance.components.entries) {
        final id = entry.key;
        if (id == _selectedTarget.id && !referencedIds.contains(id)) continue;
        final config = entry.value;
        final meta = _componentDisplayMeta(config);
        final humanLabel = _humanLabelForComponent(id, config, slotLabels);
        optionsById[id] = ValidatorTargetComponentOption(
          id: id,
          label: humanLabel,
          typeLabel: meta.typeLabel,
          icon: meta.icon,
        );
      }
    }

    for (final target in widget.targets) {
      if (target.id == _selectedTarget.id &&
          !referencedIds.contains(target.id)) {
        continue;
      }
      optionsById.putIfAbsent(
        target.id,
        () => ValidatorTargetComponentOption(
          id: target.id,
          label: slotLabels[target.id] ?? target.label,
          typeLabel: 'Composant',
          icon: target.icon ?? Icons.widgets_outlined,
        ),
      );
    }

    int priorityOf(String id) {
      final type = appearance?.components[id]?.componentType;
      return switch (type) {
        'value' => 0,
        'list' || 'table' || 'treeView' || 'tab' => 1,
        'action' || 'native' || 'indicator' => 2,
        'layout' || 'scaffold' || 'a4Document' || 'separator' => 4,
        _ => 3,
      };
    }

    final list = optionsById.values.toList();
    list.sort((a, b) {
      final p = priorityOf(a.id).compareTo(priorityOf(b.id));
      if (p != 0) return p;
      return a.displayLabel.toLowerCase().compareTo(
        b.displayLabel.toLowerCase(),
      );
    });
    return list;
  }

  String _humanLabelForComponent(
    String id,
    ComponentConfig config,
    Map<String, String> slotLabels,
  ) {
    final fromSlot = slotLabels[id]?.trim();
    if (fromSlot != null && fromSlot.isNotEmpty) return fromSlot;
    return switch (config) {
      SuperValueConfig c when c.label.trim().isNotEmpty => c.label.trim(),
      SuperValueConfig c when c.placeholder.trim().isNotEmpty =>
        c.placeholder.trim(),
      SuperValueConfig c when c.initialText.trim().isNotEmpty =>
        c.initialText.trim(),
      SuperActionConfig c when c.label.trim().isNotEmpty => c.label.trim(),
      _ => id,
    };
  }

  ({String typeLabel, IconData icon}) _componentDisplayMeta(
    ComponentConfig config,
  ) => switch (config.componentType) {
    'value' => (typeLabel: 'Valeur / Champ', icon: Icons.text_fields_outlined),
    'action' => (
      typeLabel: 'Action / Bouton',
      icon: Icons.smart_button_outlined,
    ),
    'list' => (typeLabel: 'Liste', icon: Icons.list_alt_outlined),
    'table' => (typeLabel: 'Tableau', icon: Icons.table_chart_outlined),
    'treeView' => (
      typeLabel: 'Arborescence',
      icon: Icons.account_tree_outlined,
    ),
    'tab' => (typeLabel: 'Onglets', icon: Icons.tab_outlined),
    'layout' => (typeLabel: 'Layout', icon: Icons.dashboard_outlined),
    'native' => (typeLabel: 'Composant natif', icon: Icons.widgets_outlined),
    'indicator' => (typeLabel: 'Indicateur', icon: Icons.speed_outlined),
    'conditional' => (typeLabel: 'Conditionnel', icon: Icons.rule_outlined),
    'renderer' => (typeLabel: 'Rendu', icon: Icons.code_outlined),
    'separator' => (typeLabel: 'Séparateur', icon: Icons.horizontal_rule),
    'scaffold' => (typeLabel: 'Scaffold', icon: Icons.web_asset_outlined),
    'a4Document' => (
      typeLabel: 'Document A4',
      icon: Icons.description_outlined,
    ),
    final other => (typeLabel: other, icon: Icons.widgets_outlined),
  };

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
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      title: EditorDialogHeader(
        label: _editing == null ? widget.title : 'Modifier un comportement',
      ),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 680,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: LayoutBuilder(
            builder: (context, constraints) => Stepper(
              key: ValueKey('${widget.keyPrefix}-add-stepper'),
              type: StepperType.horizontal,
              currentStep: _step,
              elevation: 0,
              onStepTapped: (step) {
                if (step < _firstStep) return;
                if (step < _step ||
                    ((step == _step + 1 || _editing != null) && _canContinue)) {
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
        if (_saveError case final message?)
          Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextButton(
          key: ValueKey('${widget.keyPrefix}-add-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        if (_step > _firstStep)
          TextButton(
            key: ValueKey('${widget.keyPrefix}-add-back'),
            onPressed: _back,
            child: const Text('Précédent'),
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
        state: index < _firstStep
            ? StepState.disabled
            : _step > index
            ? StepState.complete
            : StepState.indexed,
        content: _step != index
            ? const SizedBox.shrink()
            : switch (stage) {
                BehaviorWizardStage.target => _buildTargetStep(context),
                BehaviorWizardStage.event => _buildEventStep(context),
                BehaviorWizardStage.action => _buildActionStep(context),
                BehaviorWizardStage.validator => _buildValidatorStep(context),
                BehaviorWizardStage.summary => _buildSummaryStep(context),
              },
      ),
  ];

  Widget _buildTargetStep(BuildContext context) {
    final controller = AppearanceScope.controllerOf(widget.ownerContext);
    if (controller == null) return _targetList(context, null);
    return ValueListenableBuilder<Appearance>(
      valueListenable: controller,
      builder: (context, appearance, _) => _targetList(context, appearance),
    );
  }

  Widget _targetList(BuildContext context, Appearance? appearance) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EditorTargetSelector<BehaviorTargetElement>(
          targets: widget.targets,
          selected: _selectedTarget,
          onSelected: _onTargetSelected,
          subtitle:
              'Sélectionnez le composant qui déclenchera ce comportement :',
          itemKeyBuilder: (target) =>
              ValueKey('${widget.keyPrefix}-target-${target.id}'),
          isSelectedPredicate: (target, selected) => target.id == selected.id,
          trailingBuilder: (context, target) {
            final existing =
                appearance?.behaviorsFor(target.id) ?? target.existingBehaviors;
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
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Text(
                  'Comportements de cet élément',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                for (final b in existing)
                  _buildExistingBehaviorCard(context, b, appearance),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildExistingBehaviorCard(
    BuildContext context,
    ComponentBehavior b,
    Appearance? appearance,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final item = _editorFor(b.action);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: b.enabled
          ? colors.surfaceContainerLow
          : colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                b.action.icon,
                color: b.enabled ? colors.primary : colors.outline,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Opacity(
                opacity: b.enabled ? 1.0 : 0.6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _behaviorMetaLine(
                      context,
                      prefix: 'Quand',
                      value: b.event.label,
                      icon: b.event.icon,
                    ),
                    const SizedBox(height: 3),
                    _behaviorMetaLine(
                      context,
                      prefix: 'Si',
                      value: b.validator?.description ?? 'Toujours',
                      icon: b.validator == null
                          ? Icons.check_circle_outline
                          : Icons.verified_user_outlined,
                    ),
                    const SizedBox(height: 3),
                    _behaviorMetaLine(
                      context,
                      prefix: 'Alors',
                      value: '${b.action.label} (${b.action.description})',
                      icon: b.action.icon,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  key: ValueKey('behavior-toggle-${b.id}'),
                  value: b.enabled,
                  onChanged: appearance == null
                      ? null
                      : (enabled) => _toggleExistingBehavior(b, enabled),
                ),
                if (b.event.isImperative)
                  IconButton(
                    icon: const Icon(Icons.play_arrow_outlined),
                    tooltip: 'Tester',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => b.execute(widget.ownerContext),
                  ),
                IconButton(
                  key: ValueKey('behavior-edit-${b.id}'),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: item == null
                      ? 'Aucun éditeur disponible pour cette action'
                      : 'Modifier',
                  visualDensity: VisualDensity.compact,
                  onPressed: item == null || appearance == null
                      ? null
                      : () => _editBehavior(b, item),
                ),
                IconButton(
                  key: ValueKey('behavior-delete-${b.id}'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Supprimer',
                  color: colors.error,
                  visualDensity: VisualDensity.compact,
                  onPressed: appearance == null
                      ? null
                      : () => _removeExistingBehavior(b.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _behaviorMetaLine(
    BuildContext context, {
    required String prefix,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 13, color: colors.onSurfaceVariant),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$prefix : ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                TextSpan(text: value, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventStep(BuildContext context) {
    return BehaviorEventPicker(
      selectedEvent: _selectedEvent,
      componentType: _componentTypeFor(_selectedTarget),
      isLayoutTarget: _isLayoutTarget(_selectedTarget),
      isValueTarget: _isValueTarget(_selectedTarget),
      keyPrefix: widget.keyPrefix,
      onSelected: _onEventSelected,
    );
  }

  Widget _buildActionStep(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final items = _compatibleCatalogItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Action à exécuter',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Chip(
              avatar: Icon(_selectedEvent.icon, size: 16),
              label: Text(
                _selectedEvent.label,
                style: theme.textTheme.labelSmall,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Choisissez et configurez l’action associée à « ${_selectedTarget.label} » :',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        for (final item in items) ...[
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
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected ? colors.primary : colors.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                margin: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _selectedCatalogItem = item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSelected ? colors.primary : colors.outline,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.primary
                                : colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            item.icon,
                            size: 18,
                            color: isSelected
                                ? colors.onPrimary
                                : colors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
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
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        if (items.isNotEmpty) ...[
          const SizedBox(height: 10),
          Material(
            color: colors.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        _selectedCatalogItem.icon,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Paramètres : ${_selectedCatalogItem.title}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  _buildActionSettings(context),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildValidatorStep(BuildContext context) {
    final appearance = AppearanceScope.controllerOf(widget.ownerContext)?.value;
    final targetContext = _targetSlot?.context ?? widget.ownerContext;
    return BehaviorValidatorEditor(
      validator: _validator,
      availableTargets: _collectValidatorTargets(appearance),
      store: JsonRepositoryScope.maybeOf(targetContext),
      listScope: JsonListScope.maybeOf(targetContext),
      keyPrefix: widget.keyPrefix,
      infoBanner: _selectedEvent.isImperative
          ? null
          : 'Note : « ${_selectedEvent.label} » est un événement déclaratif. '
                'Le validateur est optionnel et surtout utilisé avec les '
                'événements impératifs (clic, modification, sélection, etc.).',
      onChanged: (validator, isValid) => setState(() {
        _validator = validator;
        _validatorValid = isValid;
      }),
    );
  }

  Widget _buildActionSettings(BuildContext context) {
    if (_isTooltip) return _buildTooltipSettings(context);
    if (_isSearchProvider) return _buildSearchProviderSettings();
    if (_isDatasource) return _buildDatasourceSettings();
    if (_isGeneratePdf) return _buildGeneratePdfSettings(context);
    if (_isAddArrayItem) return _buildAddArrayItemSettings(context);
    if (_isJavaScriptAction) return _buildJavaScriptSettings(context);
    if (_isCreationDefault) return _buildCreationDefaultSettings(context);
    if (_isBindState) return _buildBindStateSettings(context);
    if (_isEvent) return _buildEventSettings(context);
    if (_isZoneSize) return _buildZoneSizeSettings(context);
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
          Text(
            'Destination du clic',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if ((pageCatalog?.pages.isNotEmpty ?? false) ||
              codedRoutes.isNotEmpty ||
              _selectedPageId != null) ...[
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
                setState(() {
                  _customPath = set.first;
                  if (!_customPath && _selectedPageId == null) {
                    final page = pageCatalog?.pages.firstOrNull;
                    final route = codedRoutes.firstOrNull;
                    if (page != null) {
                      _selectedPageId = page.id;
                      _selectedPagePath = page.path;
                      _selectedPageName = page.name;
                    } else if (route != null) {
                      _selectedPageId = '__route_${route.path}';
                      _selectedPagePath = _selectedPageName = route.path;
                    }
                  }
                });
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
                initialValue: _selectedPageId,
                items: [
                  if (_selectedPageId != null &&
                      !(pageCatalog?.pages.any(
                            (p) => p.id == _selectedPageId,
                          ) ??
                          false) &&
                      !codedRoutes.any(
                        (r) => '__route_${r.path}' == _selectedPageId,
                      ))
                    DropdownMenuItem(
                      value: _selectedPageId,
                      child: Text('Page indisponible : $_selectedPageId'),
                    ),
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

  Widget _buildJavaScriptSettings(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('behavior-script-repository'),
            controller: _scriptRepositoryController,
            decoration: const InputDecoration(
              labelText: 'ID du repository (optionnel)',
              hintText: 'Ex. commandes',
              helperText:
                  'Vide = repository de la liste englobante. Les écritures '
                  'restent dans un seul repository.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('Script JavaScript', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
            'Utilisez ctx.set("chemin", valeur) pour écrire. doc et event '
            '(componentId, componentType, trigger, data) sont en lecture seule ; '
            'les chemins @calcul ne peuvent pas être modifiés.',
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('behavior-script-code'),
            controller: _scriptCodeController,
            minLines: 8,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: "ctx.set('statut', 'terminé');",
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (!_isJavaScriptActionValid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Le script doit contenir du code et l’ID du repository doit '
                'être valide.',
                style: TextStyle(color: theme.colorScheme.error),
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
    BehaviorAction? draftAction;
    try {
      draftAction = _buildDraftAction();
    } catch (_) {
      draftAction = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Récapitulatif du comportement',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.widgets_outlined, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Élément cible : ${_selectedTarget.label} (${_selectedTarget.id})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _summarySectionCard(
          context,
          title: '1. Événement',
          icon: _selectedEvent.icon,
          children: [
            _summaryRow(
              context,
              icon: _selectedEvent.icon,
              label: _selectedEvent.label,
              value: _selectedEvent.description,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _summarySectionCard(
          context,
          title: '2. Validateur',
          icon: _validator == null
              ? Icons.check_circle_outline
              : Icons.verified_user_outlined,
          children: [
            _summaryRow(
              context,
              icon: _validator == null
                  ? Icons.all_inclusive
                  : Icons.rule_outlined,
              label: _validator == null ? 'Condition' : _validator!.label,
              value: _validator == null
                  ? 'Toujours exécuter'
                  : _validator!.description,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _summarySectionCard(
          context,
          title: '3. Action',
          icon: _selectedCatalogItem.icon,
          children: [
            _summaryRow(
              context,
              icon: _selectedCatalogItem.icon,
              label: draftAction?.label ?? _selectedCatalogItem.title,
              value:
                  draftAction?.description ?? _selectedCatalogItem.description,
            ),
            const Divider(height: 16),
            if (_isTooltip)
              _summaryRow(
                context,
                icon: _tooltipBinding == null ? Icons.text_fields : Icons.link,
                label: _tooltipBinding == null ? 'Texte' : 'Liaison',
                value: _tooltipBinding == null
                    ? _tooltipMessage.text
                    : '${_tooltipBinding!.repositoryId ?? 'liste'} : '
                          '${_tooltipBinding!.path}',
              )
            else if (_isSearchProvider)
              _summaryRow(
                context,
                icon: Icons.cloud_sync_outlined,
                label: 'Provider',
                value: _providerSummary,
              )
            else if (_isDatasource) ...[
              _summaryRow(
                context,
                icon: Icons.dataset_outlined,
                label: 'Datasource',
                value: _datasourceSummary,
              ),
              const Divider(height: 16),
              _summaryRow(
                context,
                icon: Icons.play_circle_outline,
                label: 'Commande',
                value: _datasourceCommandSummary,
              ),
            ] else if (_isGeneratePdf) ...[
              _summaryRow(
                context,
                icon: Icons.description_outlined,
                label: 'Page A4 cible',
                value: _pdfPageName ?? _pdfPageId ?? 'Page A4 courante',
              ),
              const Divider(height: 16),
              _summaryRow(
                context,
                icon: Icons.picture_as_pdf_outlined,
                label: 'Mode de sortie',
                value: _pdfOutputMode.label,
              ),
              if (_pdfFileNameController.text.trim().isNotEmpty) ...[
                const Divider(height: 16),
                _summaryRow(
                  context,
                  icon: Icons.insert_drive_file_outlined,
                  label: 'Fichier',
                  value: _pdfFileNameController.text.trim(),
                ),
              ],
            ] else if (_isAddArrayItem) ...[
              _summaryRow(
                context,
                icon: Icons.link,
                label: 'Tableau cible',
                value: _addArrayBinding == null
                    ? '-'
                    : '${_addArrayBinding!.repositoryId ?? 'liste'} : '
                          '${_addArrayBinding!.path}',
              ),
              const Divider(height: 16),
              _summaryRow(
                context,
                icon: Icons.check_circle_outline,
                label: 'Sélection auto',
                value: _addArraySelectCreated ? 'Oui' : 'Non',
              ),
            ] else if (_isCreationDefault) ...[
              _summaryRow(
                context,
                icon: Icons.link,
                label: 'Champ cible',
                value: _effectiveCreationDefaultBinding == null
                    ? '-'
                    : '${_effectiveCreationDefaultBinding!.repositoryId ?? 'liste'} : '
                          '${_effectiveCreationDefaultBinding!.path}',
              ),
              const Divider(height: 16),
              _summaryRow(
                context,
                icon: Icons.add_box_outlined,
                label: 'Valeur par défaut',
                value: '${_resolveCreationDefaultValue()}',
              ),
            ] else if (_isJavaScriptAction) ...[
              _summaryRow(
                context,
                icon: Icons.storage_outlined,
                label: 'Repository',
                value: _scriptRepositoryController.text.trim().isEmpty
                    ? 'Hérité de la liste englobante'
                    : _scriptRepositoryController.text.trim(),
              ),
              const Divider(height: 16),
              _summaryRow(
                context,
                icon: Icons.code,
                label: 'Écriture',
                value: 'ctx.set(chemin, valeur)',
              ),
            ] else if (_isBindState) ...[
              _summaryRow(
                context,
                icon: _boundState.icon,
                label: 'État appliqué',
                value: _boundState.label,
              ),
              const Divider(height: 16),
              _summaryRow(
                context,
                icon: Icons.link,
                label: 'Liaison',
                value: _stateBinding == null
                    ? '-'
                    : '${_stateBinding!.repositoryId ?? 'liste'} : '
                          '${_stateBinding!.path}',
              ),
              const Divider(height: 16),
              _summaryRow(
                context,
                icon: Icons.rule_outlined,
                label: 'Condition',
                value: _stateWhenValue
                    ? 'Quand vrai (true)'
                    : 'Quand faux (false)',
              ),
              if (_boundState == BehaviorBoundState.invisible) ...[
                const Divider(height: 16),
                _summaryRow(
                  context,
                  icon: Icons.aspect_ratio_outlined,
                  label: 'Encombrement',
                  value: _stateMaintainSize
                      ? 'Conserver l’espace'
                      : 'Masquer sans occuper d’espace',
                ),
              ],
            ] else if (_isZoneSize) ...[
              _summaryRow(
                context,
                icon: Icons.view_sidebar_outlined,
                label: 'Zone',
                value: _effectiveZone.label,
              ),
              const Divider(height: 16),
              _summaryRow(
                context,
                icon: Icons.link,
                label: 'Liaison',
                value: _zoneBinding == null
                    ? '-'
                    : '${_zoneBinding!.repositoryId ?? 'liste'} : '
                          '${_zoneBinding!.path} '
                          '(${_zoneUnit == SlotSizeUnit.percent ? '%' : 'px'})',
              ),
              const Divider(height: 16),
              _summaryRow(
                context,
                icon: Icons.animation,
                label: 'Animation',
                value: '${_durationMs ?? '-'} ms, ${_curve.label}',
              ),
            ] else
              _summaryRow(
                context,
                icon: _isEvent ? Icons.bolt : Icons.alt_route,
                label: _isEvent ? 'Événement' : 'Destination',
                value: _isEvent
                    ? _eventIdController.text.trim()
                    : _customPath
                    ? path
                    : (_selectedPageName != null
                          ? '$_selectedPageName ($path)'
                          : path),
              ),
            if (_isEvent) ...[
              const Divider(height: 16),
              _summaryRow(
                context,
                icon: Icons.data_object,
                label: 'Custom JSON',
                value: _customJsonController.text,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _summarySectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
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
            Row(
              children: [
                Icon(icon, size: 16, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  String get _providerSummary {
    final id = _selectedProviderId;
    if (id == null) return '-';
    final targetContext = _targetSlot?.context ?? widget.ownerContext;
    final provider = JsonRepositoryScope.maybeOf(targetContext)?.providers
        .provider(id);
    return provider == null ? id : '${provider.label} ($id)';
  }

  String get _datasourceSummary {
    final id = _datasourceDraft.datasourceId;
    if (id == null) return '-';
    final config = _selectedDatasource;
    return config == null ? id : '${config.label} ($id)';
  }

  String get _datasourceCommandSummary {
    final action = _datasourceAction;
    if (action == null) return '-';
    if (action.command != DatasourceCommand.sort) return action.command.label;
    final direction = switch (action.direction) {
      null => 'sens alterné',
      DatasourceSortDirection.asc => 'croissant',
      DatasourceSortDirection.desc => 'décroissant',
    };
    return '${action.command.label} sur ${action.field} ($direction)';
  }

  Widget _buildDatasourceSettings() {
    final targetContext = _targetSlot?.context ?? widget.ownerContext;
    return DatasourceActionSettings(
      store: JsonRepositoryScope.maybeOf(targetContext),
      value: _datasourceDraft,
      managerContext: targetContext,
      onChanged: (value) => setState(() => _datasourceDraft = value),
    );
  }

  Widget _buildSearchProviderSettings() {
    final targetContext = _targetSlot?.context ?? widget.ownerContext;
    return SearchProviderSettings(
      store: JsonRepositoryScope.maybeOf(targetContext),
      selectedId: _selectedProviderId,
      managerContext: targetContext,
      onSelected: (id) => setState(() => _selectedProviderId = id),
    );
  }

  Widget _buildTooltipSettings(BuildContext context) {
    final targetContext = _targetSlot?.context ?? widget.ownerContext;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('behavior-tooltip-message'),
            controller: _tooltipMessage,
            decoration: const InputDecoration(
              labelText: 'Texte de l’info-bulle',
              helperText: 'Utilisé uniquement sans liaison.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          RepositoryBindingFields(
            keyPrefix: 'behavior-tooltip-binding',
            binding: _tooltipBinding,
            store: JsonRepositoryScope.maybeOf(targetContext),
            listScope: JsonListScope.maybeOf(targetContext),
            pathHint: 'clients[?].description',
            helper: 'Texte du repository ; [?] suit la ligne courante ou sélectionnée.',
            onChanged: (binding) => setState(() => _tooltipBinding = binding),
          ),
          if (_tooltipError case final error?) ...[
            Builder(
              builder: (_) {
                VibeDebugCapture.syncComponentDiagnostic(
                  componentId: 'behavior-editor:${_selectedTarget.id}',
                  sourceKey: 'behavior-editor.tooltipError',
                  active: true,
                  category: DebugErrorCategory.userInput,
                  severity: DebugSeverity.warning,
                  message: error,
                  source: 'ComponentBehaviorEditor.tooltip',
                  visibleInUi: true,
                );
                return const SizedBox(height: 8);
              },
            ),
            Text(
              error,
              key: const ValueKey('behavior-tooltip-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ] else
            Builder(
              builder: (_) {
                VibeDebugCapture.syncComponentDiagnostic(
                  componentId: 'behavior-editor:${_selectedTarget.id}',
                  sourceKey: 'behavior-editor.tooltipError',
                  active: false,
                  category: DebugErrorCategory.userInput,
                  severity: DebugSeverity.warning,
                  message: null,
                  source: 'ComponentBehaviorEditor.tooltip',
                );
                return const SizedBox.shrink();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildGeneratePdfSettings(BuildContext context) {
    final theme = Theme.of(context);
    final appearance = AppearanceScope.controllerOf(widget.ownerContext)?.value;
    final a4Pages = [
      for (final page
          in appearance?.pageCatalog.pages ?? const <EditorPageConfig>[])
        if (page.pageType == EditorPageType.a4Document) page,
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Page Document A4 cible',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            key: const ValueKey('behavior-pdf-page-dropdown'),
            isExpanded: true,
            initialValue: _pdfPageId,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Source A4',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Page A4 courante (ou unique page A4)'),
              ),
              if (_pdfPageId != null && !a4Pages.any((p) => p.id == _pdfPageId))
                DropdownMenuItem<String?>(
                  value: _pdfPageId,
                  child: Text('Page A4 indisponible : $_pdfPageId'),
                ),
              for (final page in a4Pages)
                DropdownMenuItem<String?>(
                  value: page.id,
                  child: Text(
                    '${page.name} (${page.path})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              final page = value == null
                  ? null
                  : a4Pages.where((p) => p.id == value).firstOrNull;
              setState(() {
                _pdfPageId = value;
                _pdfPageName = page?.name;
              });
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Mode de sortie',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<PdfOutputMode>(
            key: const ValueKey('behavior-pdf-output-mode'),
            segments: [
              for (final mode in PdfOutputMode.values)
                ButtonSegment(value: mode, label: Text(mode.label)),
            ],
            selected: {_pdfOutputMode},
            onSelectionChanged: (set) =>
                setState(() => _pdfOutputMode = set.first),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('behavior-pdf-filename'),
            controller: _pdfFileNameController,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Nom de fichier PDF (optionnel)',
              hintText: 'Laisser vide pour utiliser celui de la page A4',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildBindStateSettings(BuildContext context) {
    final theme = Theme.of(context);
    final targetContext = _targetSlot?.context ?? widget.ownerContext;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'État à appliquer',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<BehaviorBoundState>(
            key: const ValueKey('behavior-bind-state-target'),
            segments: [
              for (final state in BehaviorBoundState.values)
                ButtonSegment(
                  value: state,
                  icon: Icon(state.icon),
                  label: Text(state.label),
                ),
            ],
            selected: {_boundState},
            onSelectionChanged: (set) =>
                setState(() => _boundState = set.first),
          ),
          const SizedBox(height: 16),
          Text(
            'Condition sur le booléen lié',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            key: const ValueKey('behavior-bind-state-when'),
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.check_circle_outline),
                label: Text('Quand vrai (true)'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.cancel_outlined),
                label: Text('Quand faux (false)'),
              ),
            ],
            selected: {_stateWhenValue},
            onSelectionChanged: (set) =>
                setState(() => _stateWhenValue = set.first),
          ),
          if (_boundState == BehaviorBoundState.invisible) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('behavior-bind-state-maintain-size'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Conserver l’espace du composant'),
              subtitle: const Text(
                'Masque visuellement le composant tout en gardant sa place dans la mise en page.',
              ),
              value: _stateMaintainSize,
              onChanged: (value) => setState(() => _stateMaintainSize = value),
            ),
          ],
          const SizedBox(height: 16),
          RepositoryBindingFields(
            keyPrefix: 'behavior-bind-state-binding',
            binding: _stateBinding,
            store: JsonRepositoryScope.maybeOf(targetContext),
            listScope: JsonListScope.maybeOf(targetContext),
            pathHint: 'clients[?].estVerrouille',
            helper: 'Booléen du repository (true/false) ; [?] suit la ligne courante ou sélectionnée.',
            onChanged: (binding) => setState(() => _stateBinding = binding),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneSizeSettings(BuildContext context) {
    final theme = Theme.of(context);
    final slotContext = _targetSlot?.context;
    final zone = _effectiveZone;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Zone du layout',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<SuperLayoutZone>(
            key: const ValueKey('behavior-zone-size-zone'),
            segments: [
              for (final side in _layoutSides)
                ButtonSegment(value: side, label: Text(side.label)),
            ],
            selected: {zone},
            onSelectionChanged: (set) => setState(() => _zone = set.first),
          ),
          const SizedBox(height: 16),
          Text(
            'Taille liée',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          RepositoryBindingFields(
            keyPrefix: 'behavior-zone-size-binding',
            binding: _zoneBinding,
            store: slotContext == null
                ? null
                : JsonRepositoryScope.maybeOf(slotContext),
            listScope: slotContext == null
                ? null
                : JsonListScope.maybeOf(slotContext),
            pathHint: 'ui.panneau.largeur',
            helper:
                'Valeur numérique ; 0 ferme la zone, une valeur absente ou '
                'invalide rend la taille de la configuration.',
            onChanged: (binding) => setState(() => _zoneBinding = binding),
          ),
          const SizedBox(height: 12),
          SegmentedButton<SlotSizeUnit>(
            key: const ValueKey('behavior-zone-size-unit'),
            segments: const [
              ButtonSegment(value: SlotSizeUnit.pixels, label: Text('Pixels')),
              ButtonSegment(
                value: SlotSizeUnit.percent,
                label: Text('% du layout'),
              ),
            ],
            selected: {_zoneUnit},
            onSelectionChanged: (set) => setState(() => _zoneUnit = set.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('behavior-zone-size-duration'),
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Durée (ms)',
                    errorText: _durationMs == null ? '0 à 10000 ms.' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<BehaviorCurve>(
                  key: const ValueKey('behavior-zone-size-curve'),
                  initialValue: _curve,
                  decoration: const InputDecoration(labelText: 'Courbe'),
                  items: [
                    for (final curve in BehaviorCurve.values)
                      DropdownMenuItem(value: curve, child: Text(curve.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _curve = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'La zone s’ouvre ou se ferme en animant l’ancienne taille vers la '
            'nouvelle à chaque changement de la valeur liée. Sa poignée de '
            'redimensionnement est masquée tant que la liaison est active.',
          ),
        ],
      ),
    );
  }

  Widget _buildEventSettings(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      TextField(
        key: const ValueKey('behavior-event-id'),
        controller: _eventIdController,
        decoration: InputDecoration(
          labelText: 'ID de l’événement',
          hintText: 'node.changed',
          errorText: _eventIdController.text.trim().isEmpty
              ? 'Un ID est requis.'
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('behavior-event-custom'),
        controller: _customJsonController,
        minLines: 3,
        maxLines: 8,
        decoration: InputDecoration(
          labelText: 'Données personnalisées (objet JSON)',
          errorText: () {
            final jsonError = _customJsonError;
            VibeDebugCapture.syncComponentDiagnostic(
              componentId: 'behavior-editor:${_selectedTarget.id}',
              sourceKey: 'behavior-editor.customJsonError',
              active: jsonError != null,
              category: DebugErrorCategory.userInput,
              severity: DebugSeverity.warning,
              message: jsonError,
              source: 'ComponentBehaviorEditor.customJson',
              visibleInUi: true,
            );
            return jsonError;
          }(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      const Text(
        'Le bus reçoit l’ID du composant, son type et l’événement. '
        'SuperValue fournit les valeurs avant et après dans data. '
        'Le JSON personnalisé reste dans custom, sans écraser ces données.',
      ),
    ],
  );

  Widget _buildAddArrayItemSettings(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final targetContext = _targetSlot?.context ?? widget.ownerContext;
    final store = JsonRepositoryScope.maybeOf(targetContext);
    final listScope = JsonListScope.maybeOf(targetContext);
    final repoId = _addArrayBinding?.repositoryId?.trim().isNotEmpty == true
        ? _addArrayBinding!.repositoryId!.trim()
        : listScope?.repositoryId?.trim();
    final arrayPath = _addArrayBinding?.path.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        RepositoryBindingFields(
          keyPrefix: 'behavior-add-array-binding',
          binding: _addArrayBinding,
          store: store,
          listScope: listScope,
          pathHint: 'clients ou clients[?].commandes',
          helper:
              'Tableau JSON cible dans le repository. Utilise le JSON Schema '
              'associé au repository (et les valeurs par défaut des SuperValue) '
              'pour construire la nouvelle ligne.',
          onChanged: (binding) => setState(() => _addArrayBinding = binding),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('behavior-add-array-select-created'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Sélectionner la nouvelle ligne'),
          subtitle: const Text(
            'Met à jour la sélection Maître/Détail sur l’élément créé',
          ),
          value: _addArraySelectCreated,
          onChanged: (value) => setState(() => _addArraySelectCreated = value),
        ),
        if (store != null &&
            repoId != null &&
            repoId.isNotEmpty &&
            arrayPath.isNotEmpty)
          FutureBuilder<Map<String, Object?>?>(
            future: store.readJsonSchema(repoId),
            builder: (context, snapshot) {
              final schema = snapshot.data;
              if (schema == null) return const SizedBox.shrink();
              final preview = JsonSchemaFieldResolver.buildDefaultArrayItem(
                schema,
                arrayPath,
              );
              if (preview == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Modèle déduit du JSON Schema :',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      const JsonEncoder.withIndent('  ').convert(preview),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildCreationDefaultSettings(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final targetContext = _targetSlot?.context ?? widget.ownerContext;
    final store = JsonRepositoryScope.maybeOf(targetContext);
    final listScope = JsonListScope.maybeOf(targetContext);
    final targetBinding = _targetValueBinding;
    final effectiveBinding = _effectiveCreationDefaultBinding;
    final repoId = effectiveBinding?.repositoryId?.trim().isNotEmpty == true
        ? effectiveBinding!.repositoryId!.trim()
        : listScope?.repositoryId?.trim();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (targetBinding != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Champ lié de la SuperValue : '
                      '${targetBinding.repositoryId ?? 'liste héritée'} : '
                      '${targetBinding.path}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            RepositoryBindingFields(
              keyPrefix: 'behavior-creation-default-binding',
              binding: _creationDefaultBinding,
              store: store,
              listScope: listScope,
              pathHint: 'clients[?].statut',
              helper:
                  'Cette SuperValue n’a pas encore de liaison : indique le '
                  'repository et le chemin du champ cible.',
              onChanged: (binding) =>
                  setState(() => _creationDefaultBinding = binding),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const ValueKey('behavior-creation-default-null'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Valeur nulle (null)'),
            value: _creationDefaultUseNull,
            onChanged: (value) => setState(() {
              _creationDefaultUseNull = value;
              if (value) _creationDefaultBool = null;
            }),
          ),
          if (!_creationDefaultUseNull)
            FutureBuilder<Map<String, Object?>?>(
              future: (store != null && repoId != null && repoId.isNotEmpty)
                  ? store.readJsonSchema(repoId)
                  : Future<Map<String, Object?>?>.value(null),
              builder: (context, snapshot) {
                final schema = snapshot.data;
                final node = (schema != null && effectiveBinding != null)
                    ? JsonSchemaFieldResolver.resolveSchemaNode(
                        schema,
                        effectiveBinding.path,
                      )
                    : null;
                final schemaType = node?['type'];
                final rawEnum = node?['enum'];
                final enumChoices = rawEnum is List
                    ? rawEnum
                          .where((e) => e is String || e is num || e is bool)
                          .toList(growable: false)
                    : const <Object>[];

                if (schemaType == 'boolean') {
                  final boolVal = _creationDefaultBool ?? false;
                  return SwitchListTile(
                    key: const ValueKey('behavior-creation-default-bool'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Valeur booléenne par défaut'),
                    value: boolVal,
                    onChanged: (v) => setState(() => _creationDefaultBool = v),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (enumChoices.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        key: const ValueKey('behavior-creation-default-enum'),
                        isExpanded: true,
                        initialValue:
                            enumChoices
                                .map((e) => e.toString())
                                .contains(_creationDefaultController.text)
                            ? _creationDefaultController.text
                            : null,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          labelText: 'Valeurs autorisées par le schéma (enum)',
                        ),
                        items: [
                          for (final item in enumChoices)
                            DropdownMenuItem(
                              value: item.toString(),
                              child: Text(item.toString()),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _creationDefaultBool = null;
                            _creationDefaultController.text = value;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      key: const ValueKey('behavior-creation-default-value'),
                      controller: _creationDefaultController,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        labelText: 'Valeur par défaut à la création',
                        hintText: node?['default'] != null
                            ? 'Schéma : ${node!['default']}'
                            : 'Ex: Nouveau, 0, true…',
                        helperText: 'Sera convertie automatiquement selon le type du JSON Schema si défini.',
                      ),
                      onChanged: (_) => setState(() {
                        _creationDefaultBool = null;
                      }),
                    ),
                  ],
                );
              },
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
