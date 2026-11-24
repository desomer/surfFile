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
import '../../models/domain_layer_spec.dart';
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
    this.onOpenDomainLayer,
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

  /// Ouvre directement la couche Domain (Architecture Hexagonale) d'une entrée éligible.
  final ValueChanged<String>? onOpenDomainLayer;

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
  final ValueNotifier<({String? header, String? data})> _hoveredRow =
      ValueNotifier<({String? header, String? data})>((
        header: null,
        data: null,
      ));

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
    _hoveredRow.dispose();
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
                    rowHeight: 28,
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
                      return MouseRegion(
                        opaque: false,
                        onEnter: (_) => _hoveredRow.value = (
                          header: node.path,
                          data: _hoveredRow.value.data,
                        ),
                        onExit: (_) {
                          if (_hoveredRow.value.header == node.path) {
                            _hoveredRow.value = (
                              header: null,
                              data: _hoveredRow.value.data,
                            );
                          }
                        },
                        child: Row(
                          spacing: 6,
                          children: [
                            Icon(
                              node.parent == null
                                  ? Icons.folder
                                  : Icons.data_object,
                              size: 15,
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
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                            if (node.parent != null) _typeBadge(node),
                          ],
                        ),
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
                      final canOpenDomainLayer =
                          widget.onOpenDomainLayer != null &&
                          HexagonalDomainLayerSpec.isEligibleType(node.type);
                      return MouseRegion(
                        opaque: false,
                        onEnter: (_) => _hoveredRow.value = (
                          header: _hoveredRow.value.header,
                          data: node.path,
                        ),
                        onExit: (_) {
                          if (_hoveredRow.value.data == node.path) {
                            _hoveredRow.value = (
                              header: _hoveredRow.value.header,
                              data: null,
                            );
                          }
                        },
                        child: InkWell(
                          key: ValueKey('edit-${node.path}'),
                          onTap: _saving ? null : () => _edit(node),
                          child: Row(
                            spacing: 8,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Tooltip(
                                        waitDuration: const Duration(
                                          milliseconds: 450,
                                        ),
                                        showDuration: const Duration(
                                          seconds: 10,
                                        ),
                                        preferBelow: false,
                                        padding: EdgeInsets.zero,
                                        decoration: const BoxDecoration(
                                          color: Colors.transparent,
                                        ),
                                        richMessage: WidgetSpan(
                                          child: _ContractTitleTooltipCard(
                                            node: node,
                                            documentProvider: () =>
                                                widget.document,
                                          ),
                                        ),
                                        child: Text(
                                          key: ValueKey('title-${node.path}'),
                                          detail.title.isEmpty
                                              ? 'Titre…'
                                              : detail.title,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    if (canOpenDomainLayer)
                                      ValueListenableBuilder<
                                        ({String? header, String? data})
                                      >(
                                        valueListenable: _hoveredRow,
                                        builder: (context, hovered, _) {
                                          final isHovered =
                                              hovered.header == node.path ||
                                              hovered.data == node.path;
                                          if (!isHovered) {
                                            return const SizedBox.shrink();
                                          }
                                          final domainLayerCount = widget
                                              .document
                                              .domainLayerFor(node)
                                              .totalItemsCount;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8,
                                            ),
                                            child: _DomainLayerHoverButton(
                                              key: ValueKey(
                                                'domain-layer-${node.path}',
                                              ),
                                              count: domainLayerCount,
                                              onPressed: _saving
                                                  ? null
                                                  : () {
                                                      _hoveredRow.value = (
                                                        header: null,
                                                        data: null,
                                                      );
                                                      widget.onOpenDomainLayer!(
                                                        node.id,
                                                      );
                                                    },
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                              for (final stage in ContractStage.values)
                                Tooltip(
                                  message:
                                      '${contractStageLabels[stage]} : ${contractStatusLabels[detail.states[stage] ?? ContractStatus.pending]}',
                                  child: Icon(
                                    contractStageIcons[stage],
                                    size: 15,
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
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                node.type,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.white, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _DomainLayerHoverButton extends StatelessWidget {
  const _DomainLayerHoverButton({
    required this.count,
    required this.onPressed,
    super.key,
  });

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Ouvrir la Couche Domain',
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Icon(
                  Icons.hexagon_outlined,
                  size: 13,
                  color: colors.onSecondaryContainer,
                ),
                Text(
                  count > 0 ? 'Couche Domain ($count)' : 'Couche Domain',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContractTitleTooltipCard extends StatelessWidget {
  const _ContractTitleTooltipCard({
    required this.node,
    required this.documentProvider,
  });

  final JsonNode node;
  final DomainContracts Function() documentProvider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final document = documentProvider();
    final liveNode = document.entryById(node.id) ?? node;
    final detail = document.details[liveNode.id] ?? ContractDetails.defaults;
    final spec = document.objects[liveNode.id];
    final description = spec?.description.trim() ?? '';
    final attrCount = spec?.totalAttributeCount ?? 0;
    final relCount = spec?.relations.length ?? 0;
    final isDomainEligible = HexagonalDomainLayerSpec.isEligibleType(
      liveNode.type,
    );
    final domainLayerCount = document.domainLayerFor(liveNode).totalItemsCount;
    final typeColor = contractTypeColor(liveNode.type);
    final titleText = detail.title.trim().isEmpty
        ? 'Sans titre'
        : detail.title.trim();

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 270, maxWidth: 400),
        child: Card(
          key: ValueKey('contract-title-tooltip-${liveNode.path}'),
          elevation: 8,
          shadowColor: colors.shadow.withValues(alpha: 0.35),
          color: colors.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: typeColor.withValues(alpha: 0.55),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DefaultTextStyle(
              style:
                  theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface,
                  ) ??
                  const TextStyle(fontSize: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: typeColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Icon(
                          Icons.data_object_rounded,
                          size: 16,
                          color: typeColor,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titleText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: detail.title.trim().isEmpty
                                    ? colors.onSurfaceVariant
                                    : colors.onSurface,
                              ),
                            ),
                            Text(
                              liveNode.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        spacing: 4,
                        children: [
                          _ContractTooltipPill(
                            label: liveNode.type,
                            bgColor: typeColor,
                            fgColor: Colors.white,
                            borderColor: typeColor,
                          ),
                          _ContractTooltipPill(
                            label: 'v${detail.version}',
                            bgColor: colors.surfaceContainerLow,
                            fgColor: colors.onSurfaceVariant,
                            borderColor: colors.outlineVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final stage in ContractStage.values)
                        Builder(
                          builder: (_) {
                            final status =
                                detail.states[stage] ?? ContractStatus.pending;
                            final statusColor = contractStatusColor(
                              status,
                              colors,
                            );
                            return _ContractTooltipPill(
                              icon: contractStageIcons[stage],
                              label:
                                  '${contractStageLabels[stage]} : ${contractStatusLabels[status]}',
                              bgColor: statusColor.withValues(alpha: 0.12),
                              fgColor: status == ContractStatus.pending
                                  ? colors.onSurfaceVariant
                                  : statusColor,
                              borderColor: statusColor.withValues(alpha: 0.35),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _ContractTooltipPill(
                        icon: Icons.list_alt_rounded,
                        label: '$attrCount attribut(s)',
                        bgColor: colors.surfaceContainerLow,
                        fgColor: colors.onSurface,
                        borderColor: colors.outlineVariant,
                      ),
                      if (relCount > 0)
                        _ContractTooltipPill(
                          icon: Icons.hub_outlined,
                          label: '$relCount relation(s)',
                          bgColor: colors.surfaceContainerLow,
                          fgColor: colors.onSurface,
                          borderColor: colors.outlineVariant,
                        ),
                      if (isDomainEligible)
                        _ContractTooltipPill(
                          icon: Icons.hexagon_outlined,
                          label: domainLayerCount > 0
                              ? 'Couche Domain : $domainLayerCount'
                              : 'Couche Domain : vide',
                          bgColor: colors.secondaryContainer.withValues(
                            alpha: 0.6,
                          ),
                          fgColor: colors.onSecondaryContainer,
                          borderColor: colors.secondary.withValues(alpha: 0.35),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cliquer pour modifier le titre, la version ou les statuts',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContractTooltipPill extends StatelessWidget {
  const _ContractTooltipPill({
    required this.label,
    required this.bgColor,
    required this.fgColor,
    required this.borderColor,
    this.icon,
  });

  final String label;
  final Color bgColor;
  final Color fgColor;
  final Color borderColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            if (icon != null) Icon(icon, size: 12, color: fgColor),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fgColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
