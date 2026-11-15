/// Dialogue historique d'extraction des valeurs et de liaison JSON.
library;

export 'json_extract/component_data_wizard.dart'
    show DataTargetElement, collectExistingBindingsFromSlot;
export 'json_extract/extract_contracts.dart'
    show
        ExtractableComponentKind,
        RecurrenceSimilarityMode,
        JsonExtractHierarchyMode,
        ListViewTemplateMode,
        JsonExtractRecurrenceOptions,
        ExtractablePropertyOption,
        ExtractableComponentTarget,
        JsonExtractableState,
        sanitizeJsonAttributeKey,
        ExtractableSlotTargetEntry,
        ExtractableSlotNode,
        AlignedRecurringField,
        DetectedRecurringBlockGroup,
        RecurringGroupUserConfig;
export 'json_extract/extract_detection.dart'
    show
        computeBlockSimilarity,
        collectExtractableTargetsFromSlot,
        detectRecurringBlockGroups;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../editing/history/editor_history.dart';
import '../../editing/slots/editor_slot.dart';
import 'editor_dialog.dart';
import 'editor_dialog_header.dart';
import 'json_extract/component_data_wizard.dart'
    show DataTargetElement, showComponentDataWizardInternal;
import 'json_extract/extract_contracts.dart';
import 'json_extract/extract_detection.dart' show detectRecurringBlockGroups;
import 'json_extract/extract_list_conversion.dart';
import 'json_extract/extract_payload.dart';
import 'json_extract/extract_sections.dart';

/// Dialog displaying the JSON extracted from `SuperValue`, `SuperAction` and
/// `EditableSurface` components, detecting recurring blocks with configurable
/// similarity tolerances, building JSON arrays/trees, and optionally replacing
/// recurring blocks with an automatically bound `SuperListView`.
class SuperValueJsonExtractDialog extends StatefulWidget {
  const SuperValueJsonExtractDialog({
    this.values = const {},
    this.targets = const [],
    this.ownerContext,
    this.rootSlot,
    this.sourceLabel,
    this.store,
    this.initialRecurrenceOptions = const JsonExtractRecurrenceOptions(),
    super.key,
  });

  final Map<String, Object?> values;
  final List<ExtractableComponentTarget> targets;
  final BuildContext? ownerContext;
  final EditorSlotState? rootSlot;
  final String? sourceLabel;
  final JsonRepositoryStore? store;
  final JsonExtractRecurrenceOptions initialRecurrenceOptions;

  static Future<void> show(
    BuildContext context, {
    Map<String, Object?> values = const {},
    List<ExtractableComponentTarget> targets = const [],
    String? sourceLabel,
    BuildContext? target,
    EditorSlotState? rootSlot,
    JsonExtractRecurrenceOptions initialRecurrenceOptions =
        const JsonExtractRecurrenceOptions(),
  }) {
    final store = JsonRepositoryScope.maybeOf(context);
    EditorSlotState? resolvedSlot = rootSlot;
    if (resolvedSlot == null &&
        context is StatefulElement &&
        context.state is EditorSlotState) {
      resolvedSlot = context.state as EditorSlotState;
    }
    return showEditorDialog<void>(
      context: context,
      target: target,
      builder: (_) => SuperValueJsonExtractDialog(
        values: values,
        targets: targets,
        ownerContext: context,
        rootSlot: resolvedSlot,
        sourceLabel: sourceLabel,
        store: store,
        initialRecurrenceOptions: initialRecurrenceOptions,
      ),
    );
  }

  @override
  State<SuperValueJsonExtractDialog> createState() =>
      _SuperValueJsonExtractDialogState();
}

class _SuperValueJsonExtractDialogState
    extends State<SuperValueJsonExtractDialog> {
  late final TextEditingController _json;
  late final TextEditingController _repoName;
  late final Map<(ExtractableComponentKind, String), Set<String>>
  _selectedProps;
  late JsonExtractRecurrenceOptions _recurrenceOptions;
  List<DetectedRecurringBlockGroup> _detectedGroups = const [];
  final Map<String, RecurringGroupUserConfig> _groupConfigs = {};
  final Map<String, TextEditingController> _groupKeyControllers = {};
  final Map<(String, String), Set<String>> _selectedGroupFieldProps = {};
  bool _showRecurrenceSettings = false;
  JsonRepositoryStore? _ownedStore;
  bool _autoBind = true;
  String? _status;
  String? _error;
  bool _busy = false;

  EditorSlotState? get _effectiveRootSlot {
    if (widget.rootSlot != null && widget.rootSlot!.mounted) {
      return widget.rootSlot;
    }
    final ctx = widget.ownerContext;
    if (ctx is StatefulElement && ctx.mounted && ctx.state is EditorSlotState) {
      return ctx.state as EditorSlotState;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _recurrenceOptions = widget.initialRecurrenceOptions;
    _selectedProps = {
      for (final target in widget.targets)
        (target.kind, target.id): {
          for (final prop in target.properties)
            if (prop.defaultSelected) prop.id,
        },
    };
    _refreshDetectedGroups(initial: true);
    final initialMap = widget.targets.isNotEmpty || _detectedGroups.isNotEmpty
        ? _buildExtractedPayload().json
        : widget.values;
    _json = TextEditingController(
      text: '${const JsonEncoder.withIndent('  ').convert(initialMap)}\n',
    );
    _repoName = TextEditingController(
      text: _defaultRepositoryName(widget.sourceLabel),
    );
  }

  void _refreshDetectedGroups({bool initial = false}) {
    final slot = _effectiveRootSlot;
    if (slot == null) {
      _detectedGroups = const [];
      return;
    }
    final groups = detectRecurringBlockGroups(
      slot,
      options: _recurrenceOptions,
    );
    _detectedGroups = groups;
    for (final group in groups) {
      final previous = _groupConfigs[group.id];
      final effectiveConfig =
          previous?.copyWith(
            convertToListView: initial
                ? _recurrenceOptions.autoConvertToListView
                : previous.convertToListView,
          ) ??
          RecurringGroupUserConfig(
            enabled: true,
            convertToListView: _recurrenceOptions.autoConvertToListView,
            arrayKey: group.defaultArrayKey,
            axis: group.inferredAxis,
            templateMode: _recurrenceOptions.templateMode,
          );
      _groupConfigs[group.id] = effectiveConfig;
      _groupKeyControllers.putIfAbsent(
        group.id,
        () => TextEditingController(text: effectiveConfig.arrayKey),
      );
      for (final field in group.fields) {
        final key = (group.id, field.fieldKey);
        final selectedSet = _selectedGroupFieldProps.putIfAbsent(
          key,
          () => {
            for (final prop in field.properties)
              if (prop.defaultSelected) prop.id,
          },
        );
        if (_recurrenceOptions.autoSelectDivergentProperties) {
          selectedSet.addAll(field.divergentPropertyIds);
        }
        // Keep template target's _selectedProps synchronized
        if (field.templateTarget case final tpl?) {
          _selectedProps[(tpl.kind, tpl.id)] = Set<String>.of(selectedSet);
        }
      }
    }
  }

  void _updateRecurrenceOptions(JsonExtractRecurrenceOptions next) {
    if (next == _recurrenceOptions) return;
    setState(() {
      _status = null;
      _error = null;
      _recurrenceOptions = next;
      _refreshDetectedGroups();
      _syncJsonText();
    });
  }

  void _updateGroupConfig(String groupId, RecurringGroupUserConfig next) {
    setState(() {
      _status = null;
      _error = null;
      _groupConfigs[groupId] = next;
      _syncJsonText();
    });
  }

  void _syncJsonText() {
    final payload = _buildExtractedPayload();
    _json.text =
        '${const JsonEncoder.withIndent('  ').convert(payload.json)}\n';
  }

  ExtractedPayload _buildExtractedPayload() => ExtractPayloadBuilder.build(
    targets: widget.targets,
    selectedProps: _selectedProps,
    detectedGroups: _detectedGroups,
    groupConfigs: _groupConfigs,
    selectedGroupFieldProps: _selectedGroupFieldProps,
    recurrenceOptions: _recurrenceOptions,
  );
  void _toggleProperty(
    ExtractableComponentTarget target,
    String propertyId,
    bool selected,
  ) {
    setState(() {
      _status = null;
      _error = null;
      final set = _selectedProps.putIfAbsent((
        target.kind,
        target.id,
      ), () => <String>{});
      if (selected) {
        set.add(propertyId);
      } else {
        set.remove(propertyId);
      }
      _syncJsonText();
    });
  }

  void _toggleGroupFieldProperty(
    DetectedRecurringBlockGroup group,
    AlignedRecurringField field,
    String propertyId,
    bool selected,
  ) {
    setState(() {
      _status = null;
      _error = null;
      final set = _selectedGroupFieldProps.putIfAbsent((
        group.id,
        field.fieldKey,
      ), () => <String>{});
      if (selected) {
        set.add(propertyId);
      } else {
        set.remove(propertyId);
      }
      if (field.templateTarget case final tpl?) {
        _selectedProps[(tpl.kind, tpl.id)] = Set<String>.of(set);
      }
      _syncJsonText();
    });
  }

  static String _defaultRepositoryName(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final sanitized = raw
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\.+'), '_');
    return sanitized;
  }

  @override
  void dispose() {
    _ownedStore?.dispose();
    _json.dispose();
    _repoName.dispose();
    for (final ctrl in _groupKeyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _json.text));
    if (!mounted) return;
    setState(() {
      _error = null;
      _status = 'Copié dans le presse-papiers.';
    });
  }

  /// Convertit un [DetectedRecurringBlockGroup] en une `SuperListView` liée à
  /// [arrayPath], conserve et lie la 1re occurrence comme gabarit (`template`),
  /// et supprime les occurrences `1..N-1` de la disposition parente.
  Future<void> _createRepository() async {
    if (_busy) return;
    final name = _repoName.text.trim();
    if (name.isEmpty) {
      setState(() {
        _status = null;
        _error = 'Indiquez un nom de repository.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final decoded = jsonDecode(_json.text);
      final store =
          widget.store ?? (_ownedStore ??= JsonRepositoryStore.defaultStore());
      final existingNames = await store.list();
      final existingMatch = existingNames
          .where((entry) => entry.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      if (existingMatch != null) {
        final previousText = await store.read(existingMatch);
        Object? merged = decoded;
        try {
          final previousDecoded = jsonDecode(previousText);
          if (previousDecoded is Map && decoded is Map) {
            merged = <String, Object?>{
              for (final entry in previousDecoded.entries)
                entry.key.toString(): entry.value,
              for (final entry in decoded.entries)
                entry.key.toString(): entry.value,
            };
          }
        } on FormatException {
          merged = decoded;
        }
        final formatted =
            '${const JsonEncoder.withIndent('  ').convert(merged)}\n';
        await store.save(existingMatch, formatted, expectedText: previousText);
      } else {
        final formatted =
            '${const JsonEncoder.withIndent('  ').convert(decoded)}\n';
        await store.create(name);
        await store.save(name, formatted, expectedText: '{}\n');
      }
      final targetName = existingMatch ?? name;
      final repoId = await store.idOf(targetName);
      var convertedListsCount = 0;

      if (!mounted) return;
      if (_autoBind &&
          (widget.targets.isNotEmpty || _detectedGroups.isNotEmpty)) {
        final payload = _buildExtractedPayload();
        final ownerCtx =
            (widget.ownerContext != null && widget.ownerContext!.mounted)
            ? widget.ownerContext!
            : context;
        final history =
            (ownerCtx.mounted
                ? EditorHistoryScope.controllerOf(ownerCtx)
                : null) ??
            (mounted ? EditorHistoryScope.controllerOf(context) : null);
        history?.beginTransaction();
        try {
          // 1. Bind standalone targets
          for (final target in widget.targets) {
            final propPaths = payload.paths[(target.kind, target.id)];
            if (propPaths == null || propPaths.isEmpty) continue;
            target.applyBindings({
              for (final entry in propPaths.entries)
                entry.key: JsonTextBinding(
                  repositoryId: repoId,
                  path: entry.value,
                ),
            });
          }

          // 2. Bind or convert recurring block groups
          for (final group in _detectedGroups) {
            final cfg = _groupConfigs[group.id];
            if (cfg == null || !cfg.enabled) continue;
            final arrayPath = payload.groupArrayPaths[group.id];
            if (arrayPath == null || arrayPath.isEmpty) continue;

            if (cfg.convertToListView) {
              if (!ownerCtx.mounted) return;
              final converted = ExtractListConverter.convert(
                ownerContext: ownerCtx,
                group: group,
                userConfig: cfg,
                repoId: repoId,
                arrayPath: arrayPath,
                groupFieldRelativePaths: payload.groupFieldRelativePaths,
              );
              if (converted) convertedListsCount++;
            } else {
              // Bind each occurrence in-place to arrayPath[i].field
              for (
                var occIdx = 0;
                occIdx < group.occurrences.length;
                occIdx++
              ) {
                for (final field in group.fields) {
                  final relPaths = payload
                      .groupFieldRelativePaths[(group.id, field.fieldKey)];
                  if (relPaths == null || relPaths.isEmpty) continue;
                  final target = field.occurrenceTargets[occIdx];
                  if (target == null) continue;
                  target.applyBindings({
                    for (final entry in relPaths.entries)
                      entry.key: JsonTextBinding(
                        repositoryId: repoId,
                        path: '$arrayPath[$occIdx].${entry.value}',
                      ),
                  });
                }
              }
            }
          }
        } finally {
          history?.commitTransaction();
        }
      }
      if (!mounted) return;
      setState(() {
        if (!_autoBind || (widget.targets.isEmpty && _detectedGroups.isEmpty)) {
          _status = 'Repository « $targetName » créé.';
        } else if (convertedListsCount > 0) {
          _status =
              'Repository « $targetName » enregistré, liaisons appliquées et '
              '$convertedListsCount ListView créée${convertedListsCount > 1 ? 's' : ''}.';
        } else {
          _status =
              'Repository « $targetName » enregistré et liaisons appliquées.';
        }
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _error = 'Erreur de fichier : ${error.message}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildRecurrenceSettingsPanel() => ExtractRecurrenceSettingsPanel(
    options: _recurrenceOptions,
    busy: _busy,
    onOptionsChanged: _updateRecurrenceOptions,
  );

  Widget _buildRecurringGroupCard(DetectedRecurringBlockGroup group) =>
      RecurringBlockGroupCard(
        group: group,
        config: _groupConfigs[group.id]!,
        arrayKeyController: _groupKeyControllers[group.id]!,
        selectedFieldProps: {
          for (final field in group.fields)
            field.fieldKey:
                _selectedGroupFieldProps[(group.id, field.fieldKey)] ??
                const <String>{},
        },
        busy: _busy,
        onConfigChanged: _updateGroupConfig,
        onToggleGroupFieldProperty: _toggleGroupFieldProperty,
      );
  @override
  Widget build(BuildContext context) {
    final title = widget.sourceLabel == null || widget.sourceLabel!.isEmpty
        ? 'Extraire en JSON'
        : 'Extraire en JSON : ${widget.sourceLabel}';
    final scheme = Theme.of(context).colorScheme;
    final activeGroups = [
      for (final group in _detectedGroups)
        if (_groupConfigs[group.id]?.enabled ?? true) group,
    ];
    final coveredByActiveGroups = <(ExtractableComponentKind, String)>{
      for (final group in activeGroups) ...group.coveredTargetKeys,
    };
    final standaloneTargets = [
      for (final target in widget.targets)
        if (!coveredByActiveGroups.contains((target.kind, target.id))) target,
    ];
    final hasAnyTargets =
        widget.targets.isNotEmpty || _detectedGroups.isNotEmpty;

    return AlertDialog(
      key: const ValueKey('super-value-extract-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: EditorDialogHeader(label: title),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasAnyTargets || _effectiveRootSlot != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _detectedGroups.isEmpty
                            ? 'Propriétés à extraire'
                            : 'Propriétés & Blocs récurrents (${_detectedGroups.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey(
                        'super-value-extract-recurrence-settings-toggle',
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                      onPressed: () => setState(
                        () =>
                            _showRecurrenceSettings = !_showRecurrenceSettings,
                      ),
                      icon: Icon(
                        _showRecurrenceSettings
                            ? Icons.expand_less
                            : Icons.tune_outlined,
                        size: 16,
                      ),
                      label: Text(
                        _showRecurrenceSettings
                            ? 'Masquer paramètres'
                            : 'Similarité & Options',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                if (_showRecurrenceSettings) ...[
                  const SizedBox(height: 6),
                  _buildRecurrenceSettingsPanel(),
                ],
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: _showRecurrenceSettings ? 180 : 260,
                  ),
                  child: SingleChildScrollView(
                    key: const ValueKey('super-value-extract-targets'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final group in _detectedGroups)
                          _buildRecurringGroupCard(group),
                        for (final target in standaloneTargets)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${target.displayName} (${target.kind.label})',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          'clé : ${target.baseJsonKey}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                                fontFamily: 'monospace',
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final prop in target.properties)
                                          FilterChip(
                                            key: ValueKey(
                                              'super-value-extract-prop-${target.id}-${prop.id}',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            selected:
                                                (_selectedProps[(
                                                          target.kind,
                                                          target.id,
                                                        )] ??
                                                        const {})
                                                    .contains(prop.id),
                                            label: Text(
                                              '${prop.label} : ${prop.value}',
                                            ),
                                            onSelected: _busy
                                                ? null
                                                : (selected) => _toggleProperty(
                                                    target,
                                                    prop.id,
                                                    selected,
                                                  ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 140,
                child: TextField(
                  key: const ValueKey('super-value-extract-json'),
                  controller: _json,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: 'JSON extrait',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (hasAnyTargets) ...[
                const SizedBox(height: 4),
                CheckboxListTile(
                  key: const ValueKey('super-value-extract-auto-bind'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _autoBind,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _autoBind = value ?? true),
                  title: const Text(
                    'Lier automatiquement les propriétés sélectionnées au repository',
                  ),
                ),
              ],
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('super-value-extract-repo-name'),
                controller: _repoName,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Nom du repository',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: _busy ? null : (_) => _createRepository(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  key: const ValueKey('super-value-extract-error'),
                  style: TextStyle(color: scheme.error),
                ),
              ],
              if (_status != null) ...[
                const SizedBox(height: 6),
                Text(
                  _status!,
                  key: const ValueKey('super-value-extract-status'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('super-value-extract-copy'),
          onPressed: _copy,
          icon: const Icon(Icons.copy),
          label: const Text('Copier'),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('super-value-extract-create-repo'),
          onPressed: _busy ? null : _createRepository,
          icon: const Icon(Icons.storage_outlined),
          label: Text(
            _autoBind && hasAnyTargets
                ? 'Valider et lier'
                : 'Créer un repository',
          ),
        ),
        FilledButton(
          key: const ValueKey('super-value-extract-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

/// Ouvre le sélecteur de données puis le dialogue historique d'extraction.
Future<void> showComponentDataWizard({
  required BuildContext context,
  required List<DataTargetElement> targets,
  BuildContext? target,
}) => showComponentDataWizardInternal(
  context: context,
  targets: targets,
  target: target,
  onExtract: (selectedTarget, latestTargets) =>
      SuperValueJsonExtractDialog.show(
        selectedTarget.slot.context,
        targets: latestTargets,
        sourceLabel: selectedTarget.slot.titleLabel,
        target: selectedTarget.slot.context,
        rootSlot: selectedTarget.slot,
      ),
);
