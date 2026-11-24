/// Tableau `SuperTable` affichant et gérant la matrice des compensations
/// d'une Saga ([SagaCompensationSuperTable]).
library;

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/usecase_orchestration_spec.dart';

/// Affiche les 8 colonnes de la matrice de compensation d'une Saga via
/// [SuperTable] avec colonne `Étape` figée à gauche, badges visuels de
/// criticité / idempotence / retry et actions d'édition / suppression par ligne.
class SagaCompensationSuperTable extends StatefulWidget {
  /// Crée une [SuperTable] pour les lignes de compensation [rows] de [sagaId].
  const SagaCompensationSuperTable({
    required this.sagaId,
    required this.rows,
    required this.onEditRow,
    required this.onDeleteRow,
    this.onToggleIdempotent,
    this.onToggleRetryable,
    super.key,
  });

  /// Identifiant unique de la Saga (sert à isoler l'ID du composant `SuperTable`).
  final String sagaId;

  /// Lignes de la matrice des compensations.
  final List<SagaCompensationRow> rows;

  /// Ouvre le formulaire d'édition pour une ligne.
  final ValueChanged<SagaCompensationRow> onEditRow;

  /// Supprime une ligne de la matrice.
  final ValueChanged<SagaCompensationRow> onDeleteRow;

  /// Bascule rapide de `idempotent` au clic sur la puce (optionnel).
  final ValueChanged<SagaCompensationRow>? onToggleIdempotent;

  /// Bascule rapide de `retryable` au clic sur la puce (optionnel).
  final ValueChanged<SagaCompensationRow>? onToggleRetryable;

  @override
  State<SagaCompensationSuperTable> createState() =>
      _SagaCompensationSuperTableState();
}

class _SagaCompensationSuperTableState
    extends State<SagaCompensationSuperTable> {
  static const String _repo = 'saga_compensation_matrix';

  final JsonRepositoryStore _store = JsonRepositoryStore(Directory.systemTemp);
  bool _registered = false;
  List<SagaCompensationRow>? _syncedRows;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SagaCompensationSuperTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  List<Map<String, Object?>> _serializeRows() => [
    for (final row in widget.rows)
      <String, Object?>{
        'id': row.id,
        'step': row.step,
        'nominalAction': row.nominalAction,
        'compensationAction': row.compensationAction,
        'rollbackTrigger': row.rollbackTrigger,
        'criticality': row.criticality.label,
        'idempotent': row.idempotent ? 'Oui' : 'Non',
        'retryable': row.retryable ? 'Oui' : 'Non',
        'timeout': row.timeout,
      },
  ];

  void _sync() {
    if (identical(_syncedRows, widget.rows)) return;
    _syncedRows = widget.rows;
    final serialized = _serializeRows();
    if (_registered) {
      unawaited(_store.replaceArray(_repo, 'rows', serialized));
    } else {
      _store.registerRepository(
        RepositoryImpl(id: _repo, json: {'rows': serialized}),
      );
      _registered = true;
    }
  }

  SagaCompensationRow? _rowOf(BuildContext cellContext) {
    final scope = JsonListScope.maybeOf(cellContext);
    if (scope == null || scope.placeholder || scope.indices.isEmpty) {
      return null;
    }
    final index = scope.indices.last;
    if (index < 0 || index >= widget.rows.length) return null;
    return widget.rows[index];
  }

  Widget _textCell(String field, {FontWeight? fontWeight}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SuperValue(
        id: 'saga-matrix-${widget.sagaId}-$field',
        config: SuperValueConfig(
          mode: SuperValueMode.display,
          fontSize: 12.5,
          fontWeight: fontWeight,
          binding: JsonTextBinding(
            repositoryId: _repo,
            path: 'rows[?].$field',
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tableId = 'saga-compensation-table-${widget.sagaId}';
    final headerStyle = ContainerStyle(
      color: colors.surfaceContainerLow,
      borderColor: colors.outlineVariant,
      borderWidth: 0.5,
    );

    const columns = <SuperTableColumnConfig>[
      SuperTableColumnConfig(id: 'step', title: 'Étape', width: 170),
      SuperTableColumnConfig(
        id: 'nominalAction',
        title: 'Action Nominale',
        width: 185,
      ),
      SuperTableColumnConfig(
        id: 'compensationAction',
        title: 'Action de Compensation (Rollback)',
        width: 225,
      ),
      SuperTableColumnConfig(
        id: 'rollbackTrigger',
        title: 'Déclencheur du Rollback',
        width: 185,
      ),
      SuperTableColumnConfig(id: 'criticality', title: 'Criticité', width: 105),
      SuperTableColumnConfig(
        id: 'idempotent',
        title: 'Idempotente',
        width: 105,
      ),
      SuperTableColumnConfig(id: 'retryable', title: 'Retryable', width: 95),
      SuperTableColumnConfig(id: 'timeout', title: 'Timeout', width: 85),
      SuperTableColumnConfig(id: 'actions', title: 'Actions', width: 92),
    ];

    return Container(
      key: ValueKey('usecase-saga-supertable-${widget.sagaId}'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: JsonRepositoryScope(
        store: _store,
        child: SuperTable(
          id: tableId,
          label: 'Matrice des Compensations',
          config: SuperTableConfig(
            binding: const JsonTextBinding(
              repositoryId: _repo,
              path: 'rows',
            ),
            columns: columns,
            colFreezeLeftCount: 1,
            showHeaderRow: true,
            headerRowHeight: 38,
            rowHeight: 42,
            emptyText: 'Aucune étape de compensation définie.',
            placements: {
              for (final col in columns)
                SuperTableConfig.cellZoneFor(col.id): ['cell:${col.id}'],
            },
            zoneStyles: {
              for (final col in columns)
                SuperTableConfig.headerZoneFor(col.id): headerStyle,
            },
          ),
          cells: {
            'step': _textCell('step', fontWeight: FontWeight.w600),
            'nominalAction': _textCell('nominalAction'),
            'compensationAction': _textCell('compensationAction'),
            'rollbackTrigger': _textCell('rollbackTrigger'),
            'criticality': Builder(
              builder: (cellContext) {
                final row = _rowOf(cellContext);
                if (row == null) return _textCell('criticality');
                final (bg, fg) = switch (row.criticality) {
                  SagaStepCriticality.critical => (
                    colors.errorContainer,
                    colors.onErrorContainer,
                  ),
                  SagaStepCriticality.high => (
                    Colors.orange.withValues(alpha: 0.18),
                    Colors.orange.shade800,
                  ),
                  SagaStepCriticality.medium => (
                    colors.primaryContainer,
                    colors.onPrimaryContainer,
                  ),
                  SagaStepCriticality.low => (
                    colors.surfaceContainerHighest,
                    colors.onSurfaceVariant,
                  ),
                };
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        row.criticality.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            'idempotent': Builder(
              builder: (cellContext) {
                final row = _rowOf(cellContext);
                if (row == null) return _textCell('idempotent');
                return _BoolBadgeCell(
                  value: row.idempotent,
                  onTap: widget.onToggleIdempotent == null
                      ? null
                      : () => widget.onToggleIdempotent!(row),
                );
              },
            ),
            'retryable': Builder(
              builder: (cellContext) {
                final row = _rowOf(cellContext);
                if (row == null) return _textCell('retryable');
                return _BoolBadgeCell(
                  value: row.retryable,
                  onTap: widget.onToggleRetryable == null
                      ? null
                      : () => widget.onToggleRetryable!(row),
                );
              },
            ),
            'timeout': _textCell('timeout'),
            'actions': Builder(
              builder: (cellContext) {
                final row = _rowOf(cellContext);
                if (row == null) return const SizedBox.shrink();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      key: ValueKey('saga-comp-edit-${row.id}'),
                      tooltip: 'Modifier l’étape',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => widget.onEditRow(row),
                    ),
                    IconButton(
                      key: ValueKey('saga-comp-delete-${row.id}'),
                      tooltip: 'Supprimer l’étape',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => widget.onDeleteRow(row),
                    ),
                  ],
                );
              },
            ),
          },
        ),
      ),
    );
  }
}

class _BoolBadgeCell extends StatelessWidget {
  const _BoolBadgeCell({required this.value, this.onTap});

  final bool value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bg = value
        ? Colors.green.withValues(alpha: 0.14)
        : colors.surfaceContainerHighest;
    final fg = value ? Colors.green.shade700 : colors.onSurfaceVariant;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value ? 'Oui' : 'Non',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: onTap == null
            ? badge
            : InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onTap,
                child: badge,
              ),
      ),
    );
  }
}
