import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../history/editor_history.dart';
import '../slots/editor_slot.dart';
import 'editor_dialog.dart';
import 'editor_dialog_header.dart';

enum ExtractableComponentKind {
  superValue('SuperValue'),
  superAction('SuperAction'),
  surface('Surface');

  const ExtractableComponentKind(this.label);
  final String label;
}

class ExtractablePropertyOption {
  const ExtractablePropertyOption({
    required this.id,
    required this.label,
    required this.value,
    this.defaultSelected = false,
  });

  final String id;
  final String label;
  final Object? value;
  final bool defaultSelected;
}

class ExtractableComponentTarget {
  const ExtractableComponentTarget({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.baseJsonKey,
    required this.properties,
    required this.applyBindings,
  });

  final String id;
  final ExtractableComponentKind kind;
  final String displayName;
  final String baseJsonKey;
  final List<ExtractablePropertyOption> properties;
  final void Function(Map<String, JsonTextBinding> bindings) applyBindings;
}

abstract interface class JsonExtractableState {
  String get extractableId;
  ExtractableComponentKind get extractableKind;
  EditorSlotState? get extractableSurface;
  BuildContext get extractableContext;
  bool get isExtractableMounted;
  String get preferredExtractableKey;
  ExtractableComponentTarget buildExtractableTarget(String assignedBaseKey);
}

String sanitizeJsonAttributeKey(String raw) {
  final sanitized = raw
      .trim()
      .replaceAll(RegExp(r'[.\[\]\s?]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return sanitized.isEmpty ? 'item' : sanitized;
}

/// Collects all extractable `SuperValue` and `SuperAction` components owned by
/// [slot] or mounted inside [slot]'s subtree.
List<ExtractableComponentTarget> collectExtractableTargetsFromSlot(
  EditorSlotState slot,
) {
  if (!slot.mounted) return const [];
  final statesByKey =
      <(ExtractableComponentKind, String), JsonExtractableState>{};

  JsonExtractableState? direct;
  slot.context.visitAncestorElements((element) {
    if (element is StatefulElement && element.state is JsonExtractableState) {
      final candidate = element.state as JsonExtractableState;
      if (candidate.isExtractableMounted &&
          identical(candidate.extractableSurface, slot)) {
        direct = candidate;
        return false;
      }
    }
    return true;
  });

  void addState(JsonExtractableState state) {
    if (!state.isExtractableMounted) return;
    final mapKey = (state.extractableKind, state.extractableId);
    final existing = statesByKey[mapKey];
    final scope = JsonListScope.maybeOf(state.extractableContext);
    final isPlaceholder = scope?.placeholder ?? false;
    final isSelected = scope?.selected ?? false;
    if (existing == null) {
      statesByKey[mapKey] = state;
    } else {
      final existingScope = JsonListScope.maybeOf(
        existing.extractableContext,
      );
      final existingPlaceholder = existingScope?.placeholder ?? false;
      final existingSelected = existingScope?.selected ?? false;
      if ((existingPlaceholder && !isPlaceholder) ||
          (!existingSelected && isSelected && !isPlaceholder)) {
        statesByKey[mapKey] = state;
      }
    }
  }

  void visit(Element element) {
    if (element is StatefulElement && element.state is JsonExtractableState) {
      final state = element.state as JsonExtractableState;
      addState(state);
      if (state.extractableKind != ExtractableComponentKind.surface) {
        return;
      }
    }
    element.visitChildren(visit);
  }

  if (direct != null) {
    addState(direct!);
    if (direct!.extractableKind == ExtractableComponentKind.surface) {
      slot.context.visitChildElements(visit);
    }
  } else {
    slot.context.visitChildElements(visit);
  }

  if (statesByKey.isEmpty) return const [];
  final usedKeys = <String>{};
  final targets = <ExtractableComponentTarget>[];
  for (final state in statesByKey.values) {
    final baseKey = sanitizeJsonAttributeKey(state.preferredExtractableKey);
    var uniqueKey = baseKey;
    var suffix = 2;
    while (!usedKeys.add(uniqueKey)) {
      uniqueKey = '${baseKey}_$suffix';
      suffix++;
    }
    final target = state.buildExtractableTarget(uniqueKey);
    if (target.properties.isNotEmpty) {
      targets.add(target);
    }
  }
  return targets;
}

/// Dialog displaying the JSON extracted from `SuperValue` and `SuperAction`
/// components, allowing the user to select which existing properties to extract,
/// copy the JSON, or save it as a repository with automatic binding.
class SuperValueJsonExtractDialog extends StatefulWidget {
  const SuperValueJsonExtractDialog({
    this.values = const {},
    this.targets = const [],
    this.ownerContext,
    this.sourceLabel,
    this.store,
    super.key,
  });

  final Map<String, Object?> values;
  final List<ExtractableComponentTarget> targets;
  final BuildContext? ownerContext;
  final String? sourceLabel;
  final JsonRepositoryStore? store;

  static Future<void> show(
    BuildContext context, {
    Map<String, Object?> values = const {},
    List<ExtractableComponentTarget> targets = const [],
    String? sourceLabel,
    BuildContext? target,
  }) {
    final store = JsonRepositoryScope.maybeOf(context);
    return showEditorDialog<void>(
      context: context,
      target: target,
      builder: (_) => SuperValueJsonExtractDialog(
        values: values,
        targets: targets,
        ownerContext: context,
        sourceLabel: sourceLabel,
        store: store,
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
  JsonRepositoryStore? _ownedStore;
  bool _autoBind = true;
  String? _status;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selectedProps = {
      for (final target in widget.targets)
        (target.kind, target.id): {
          for (final prop in target.properties)
            if (prop.defaultSelected) prop.id,
        },
    };
    final initialMap = widget.targets.isNotEmpty
        ? _buildExtractedPayload().json
        : widget.values;
    _json = TextEditingController(
      text: '${const JsonEncoder.withIndent('  ').convert(initialMap)}\n',
    );
    _repoName = TextEditingController(
      text: _defaultRepositoryName(widget.sourceLabel),
    );
  }

  ({
    Map<String, Object?> json,
    Map<(ExtractableComponentKind, String), Map<String, String>> paths,
  })
  _buildExtractedPayload() {
    final json = <String, Object?>{};
    final paths = <(ExtractableComponentKind, String), Map<String, String>>{};
    for (final target in widget.targets) {
      final selectedIds = _selectedProps[(target.kind, target.id)] ?? const {};
      final chosen = [
        for (final prop in target.properties)
          if (selectedIds.contains(prop.id)) prop,
      ];
      if (chosen.isEmpty) continue;
      if (chosen.length == 1) {
        final single = chosen.single;
        json[target.baseJsonKey] = single.value;
        paths[(target.kind, target.id)] = {single.id: target.baseJsonKey};
      } else {
        json[target.baseJsonKey] = {
          for (final prop in chosen) prop.id: prop.value,
        };
        paths[(target.kind, target.id)] = {
          for (final prop in chosen)
            prop.id: '${target.baseJsonKey}.${prop.id}',
        };
      }
    }
    return (json: json, paths: paths);
  }

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
      final payload = _buildExtractedPayload();
      _json.text =
          '${const JsonEncoder.withIndent('  ').convert(payload.json)}\n';
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
      if (_autoBind && widget.targets.isNotEmpty) {
        final payload = _buildExtractedPayload();
        final ownerCtx = widget.ownerContext;
        final history =
            (ownerCtx != null && ownerCtx.mounted
                ? EditorHistoryScope.controllerOf(ownerCtx)
                : null) ??
            (mounted ? EditorHistoryScope.controllerOf(context) : null);
        history?.beginTransaction();
        try {
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
        } finally {
          history?.commitTransaction();
        }
      }
      if (!mounted) return;
      setState(() {
        _status = _autoBind && widget.targets.isNotEmpty
            ? 'Repository « $targetName » enregistré et liaisons appliquées.'
            : 'Repository « $targetName » créé.';
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

  @override
  Widget build(BuildContext context) {
    final title = widget.sourceLabel == null || widget.sourceLabel!.isEmpty
        ? 'Extraire en JSON'
        : 'Extraire en JSON : ${widget.sourceLabel}';
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('super-value-extract-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: EditorDialogHeader(label: title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.targets.isNotEmpty) ...[
              Text(
                'Propriétés à extraire',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  key: const ValueKey('super-value-extract-targets'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final target in widget.targets)
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
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
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
            if (widget.targets.isNotEmpty) ...[
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
              Text(_status!, key: const ValueKey('super-value-extract-status')),
            ],
          ],
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
            _autoBind && widget.targets.isNotEmpty
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
