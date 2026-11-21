/// Atelier à deux volets : source YAML SuperCode et catalogue SuperTreeView.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_extensions/super_container_extensions.dart'
    show SuperCode, SuperCodeConfig;
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../../models/domain_contracts.dart';
import '../spec_split_handle.dart';
import 'contract_entry_view.dart';

const _repo = 'domain_contracts';

/// Éditeur isolé par domaine ; le repository d’interface ne contient que le brouillon local.
class DomainContractsEditor extends StatefulWidget {
  const DomainContractsEditor({
    required this.document,
    required this.onSave,
    required this.onOpen,
    required this.codeFraction,
    required this.onCodeFractionChanged,
    super.key,
  });

  /// Part initiale du volet DSL, rétablie par double-clic sur la poignée.
  static const defaultCodeFraction = 0.30;

  final DomainContracts document;

  /// Part de la largeur occupée par le volet DSL ; conservée par la page
  /// pour survivre au changement de domaine.
  final double codeFraction;
  final ValueChanged<double> onCodeFractionChanged;
  final Future<void> Function(DomainContracts) onSave;

  /// Ouvre la fiche de l'entrée d'ID donné (clic sur son nom souligné).
  final ValueChanged<String> onOpen;

  @override
  State<DomainContractsEditor> createState() => _DomainContractsEditorState();
}

class _DomainContractsEditorState extends State<DomainContractsEditor> {
  final _store = JsonRepositoryStore(Directory.systemTemp);
  final _source = JsonTextBinding(repositoryId: _repo, path: 'source');
  final _error = JsonTextBinding(repositoryId: _repo, path: 'error');
  final _byPath = <String, JsonNode>{};
  Timer? _sourceSyncTimer;
  int _sourceSyncRevision = 0;
  bool _suppressSourceSync = false;
  bool _saving = false;
  final _splitRowKey = GlobalKey();
  double _dragOffset = SpecSplitHandle.width / 2;

  double? _splitX(Offset global) {
    final box = _splitRowKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global).dx;
  }

  List<Map<String, Object?>> _tree() {
    _byPath.clear();
    Map<String, Object?> row(JsonNode node, String path) {
      _byPath[path] = node;
      return {
        'name': node.name,
        'type': node.type,
        if (node.parent != null)
          'detail': widget.document.details[node.id]?.toJson(),
        'children': [
          for (final (i, child) in node.children.indexed)
            row(child, '$path.children[$i]'),
        ],
      };
    }

    return [
      for (final (i, group) in widget.document.groups.indexed)
        row(group, 'nodes[$i]'),
    ];
  }

  @override
  void initState() {
    super.initState();
    _store.registerRepository(
      RepositoryImpl(
        id: _repo,
        json: {'source': widget.document.source, 'error': '', 'nodes': _tree()},
        // Seules les saisies du DSL relancent la synchro, pas l'erreur ni l'arbre.
        onChanged: (change) {
          if (change.path == _source.path) _scheduleSourceSync();
        },
      ),
    );
  }

  @override
  void didUpdateWidget(DomainContractsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      unawaited(_store.replaceArray(_repo, 'nodes', _tree()));
    }
  }

  @override
  void dispose() {
    _sourceSyncTimer?.cancel();
    _store.dispose();
    super.dispose();
  }

  /// Affiche [message] dans la zone d'erreur en bas du SuperCode (vide = aucune).
  Future<void> _showError(String? message) async {
    if (!mounted) return;
    await _store.updateValue(_repo, _error.path, (_) => message ?? '');
  }

  static String _failure(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message) =>
      'Enregistrement impossible : $message',
    StateError(:final message) => 'Enregistrement impossible : $message',
    _ => 'Enregistrement impossible : $error',
  };

  void _scheduleSourceSync() {
    if (_suppressSourceSync) return;
    final revision = ++_sourceSyncRevision;
    _sourceSyncTimer?.cancel();
    _sourceSyncTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_syncSource(revision));
    });
  }

  Future<void> _syncSource(int revision) async {
    try {
      await _store.flushBindings();
      final source = (await _store.readAttribute(_source)).text;
      if (!mounted || revision != _sourceSyncRevision) return;
      if (source != widget.document.source) {
        await widget.onSave(widget.document.patch(source));
      }
      if (mounted && revision == _sourceSyncRevision) await _showError(null);
    } on StateError catch (error) {
      if (mounted && revision == _sourceSyncRevision) {
        await _showError(_failure(error));
      }
    } on Exception catch (error) {
      if (mounted && revision == _sourceSyncRevision) {
        await _showError(_failure(error));
      }
    }
  }

  Future<void> _commit([
    JsonNode? node,
    String? type,
    ContractDetails? details,
  ]) async {
    if (_saving) return;
    _sourceSyncTimer?.cancel();
    final revision = ++_sourceSyncRevision;
    setState(() => _saving = true);
    try {
      await _store.flushBindings();
      final draft = (await _store.readAttribute(_source)).text;
      if (!mounted) return;
      final current = widget.document;
      final parsed = draft == current.source ? current : current.patch(draft);
      final next = node == null
          ? parsed
          : parsed.edit(
              parsed.entryById(node.id) ??
                  (throw FormatException('Entrée introuvable : ${node.path}.')),
              type!,
              details!,
            );
      if (next != current) {
        await widget.onSave(next);
      }
      if (mounted && next.source != draft) {
        _suppressSourceSync = true;
        try {
          await _store.writeAttribute(
            _source,
            next.source,
            expectedValue: draft,
          );
        } finally {
          _suppressSourceSync = false;
        }
      }
      await _showError(null);
    } on StateError catch (error) {
      await _showError(_failure(error));
    } on Exception catch (error) {
      await _showError(_failure(error));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (revision != _sourceSyncRevision) {
          _scheduleSourceSync();
        }
      }
    }
  }

  Future<void> _edit(JsonNode node) async {
    final result = await showDialog<({String type, ContractDetails details})>(
      context: context,
      builder: (_) => _ContractForm(
        node: node,
        details: widget.document.details[node.id] ?? ContractDetails.defaults,
      ),
    );
    if (mounted && result != null) {
      await _commit(node, result.type, result.details);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SuperCode(
            id: 'domain-contracts-source',
            config: SuperCodeConfig(
              binding: _source,
              errorBinding: _error,
              readOnly: _saving,
              style: SuperCodeStyle(
                theme: theme.brightness == Brightness.dark
                    ? SuperCodeTheme.monokaiSublime
                    : SuperCodeTheme.atomOneLight,
              ),
            ),
          ),
        ),
      ],
    );
    final tree = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(700, bounds.maxWidth),
                child: SuperTreeView(
                  id: 'domain-contracts-tree',
                  config: SuperTreeViewConfig(
                    binding: JsonTextBinding(
                      repositoryId: _repo,
                      path: 'nodes',
                    ),
                    headerSize: (bounds.maxWidth * 0.42)
                        .clamp(340.0, 460.0)
                        .toDouble(),
                    rowHeight: 38,
                    emptyText: 'Ajoutez une rubrique dans le DSL.',
                    placements: const {
                      'header': ['header'],
                      'data': ['data'],
                    },
                  ),
                  header: Builder(
                    builder: (context) {
                      final node =
                          _byPath[JsonListScope.maybeOf(context)?.nodePath];
                      if (node == null) return const SizedBox.shrink();
                      return Row(
                        spacing: 6,
                        children: [
                          Icon(
                            node.parent == null
                                ? Icons.folder
                                : Icons.data_object,
                            size: 17,
                          ),
                          Expanded(
                            child: node.parent == null
                                ? Text(
                                    node.name,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Align(
                                    alignment: Alignment.centerLeft,
                                    child: InkWell(
                                      key: ValueKey('open-${node.path}'),
                                      onTap: () => widget.onOpen(node.id),
                                      child: Text(
                                        node.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          if (node.parent != null) _typeBadge(node),
                        ],
                      );
                    },
                  ),
                  data: Builder(
                    builder: (context) {
                      final node =
                          _byPath[JsonListScope.maybeOf(context)?.nodePath];
                      if (node == null) return const SizedBox.shrink();
                      if (node.parent == null) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${node.children.length} entrée(s)',
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      }
                      final detail =
                          widget.document.details[node.id] ??
                          ContractDetails.defaults;
                      return InkWell(
                        key: ValueKey('edit-${node.path}'),
                        onTap: _saving ? null : () => _edit(node),
                        child: Row(
                          spacing: 8,
                          children: [
                            Expanded(
                              child: Text(
                                detail.title.isEmpty ? 'Titre…' : detail.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            for (final stage in ContractStage.values)
                              Tooltip(
                                message:
                                    '${contractStageLabels[stage]} : ${contractStatusLabels[detail.states[stage] ?? ContractStatus.pending]}',
                                child: Icon(
                                  contractStageIcons[stage],
                                  size: 16,
                                  color: contractStatusColor(
                                    detail.states[stage],
                                    theme.colorScheme,
                                  ),
                                ),
                              ),
                            Text(detail.version),
                            const Icon(Icons.edit_outlined, size: 14),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return JsonRepositoryScope(
      store: _store,
      child: LayoutBuilder(
        builder: (_, bounds) {
          const minCodeWidth = 240.0;
          const minTreeWidth = 360.0;
          final available = math.max(
            0.0,
            bounds.maxWidth - SpecSplitHandle.width,
          );
          final roomy = available > minCodeWidth + minTreeWidth;
          final minFraction = roomy ? minCodeWidth / available : 0.20;
          final maxFraction = roomy
              ? (available - minTreeWidth) / available
              : 0.72;
          final codeWidth =
              available * widget.codeFraction.clamp(minFraction, maxFraction);
          return Row(
            key: _splitRowKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('domain-contracts-code-pane'),
                width: codeWidth,
                child: code,
              ),
              SpecSplitHandle(
                key: const ValueKey('domain-contracts-split-handle'),
                onDoubleTap: () => widget.onCodeFractionChanged(
                  DomainContractsEditor.defaultCodeFraction,
                ),
                onHorizontalDragDown: (details) {
                  final x = _splitX(details.globalPosition);
                  _dragOffset = x == null
                      ? SpecSplitHandle.width / 2
                      : (x - codeWidth).clamp(0.0, SpecSplitHandle.width);
                },
                onHorizontalDragUpdate: (details) {
                  final x = _splitX(details.globalPosition);
                  if (x == null || available <= 0) return;
                  widget.onCodeFractionChanged(
                    ((x - _dragOffset) / available).clamp(
                      minFraction,
                      maxFraction,
                    ),
                  );
                },
              ),
              Expanded(child: tree),
            ],
          );
        },
      ),
    );
  }

  Widget _typeBadge(JsonNode node) {
    return PopupMenuButton<String>(
      key: ValueKey('type-${node.path}'),
      tooltip: 'Modifier le type de ${node.name}',
      enabled: !_saving,
      initialValue: node.type,
      itemBuilder: (_) => [
        for (final type in DomainContracts.types)
          PopupMenuItem(value: type, child: Text(type)),
      ],
      onSelected: (type) {
        if (type == node.type) return;
        _commit(
          node,
          type,
          widget.document.details[node.id] ?? ContractDetails.defaults,
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: contractTypeColor(node.type),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(node.type, style: const TextStyle(color: Colors.white)),
              const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContractForm extends StatefulWidget {
  const _ContractForm({required this.node, required this.details});
  final JsonNode node;
  final ContractDetails details;

  @override
  State<_ContractForm> createState() => _ContractFormState();
}

class _ContractFormState extends State<_ContractForm> {
  final _form = GlobalKey<FormState>();
  late String _type = widget.node.type;
  late String _title = widget.details.title;
  late String _version = widget.details.version;
  late final _states = Map.of(widget.details.states);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.node.path),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final type in DomainContracts.types)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: (value) => _type = value!,
              ),
              TextFormField(
                initialValue: _title,
                decoration: const InputDecoration(labelText: 'Titre'),
                onChanged: (value) => _title = value,
              ),
              TextFormField(
                initialValue: _version,
                decoration: const InputDecoration(labelText: 'Version'),
                validator: (s) =>
                    ContractDetails.versionPattern.hasMatch(s?.trim() ?? '')
                    ? null
                    : 'Version attendue : x.y.z',
                onChanged: (value) => _version = value.trim(),
              ),
              for (final stage in ContractStage.values)
                DropdownButtonFormField<ContractStatus>(
                  initialValue: _states[stage] ?? ContractStatus.pending,
                  decoration: InputDecoration(
                    labelText: contractStageLabels[stage],
                    icon: Icon(contractStageIcons[stage]),
                  ),
                  items: [
                    for (final status in ContractStatus.values)
                      DropdownMenuItem(
                        value: status,
                        child: Text(contractStatusLabels[status]!),
                      ),
                  ],
                  onChanged: (value) => _states[stage] = value!,
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, (
              type: _type,
              details: ContractDetails(
                title: _title.trim(),
                version: _version,
                states: _states,
              ),
            ));
          }
        },
        child: const Text('Enregistrer'),
      ),
    ],
  );
}
