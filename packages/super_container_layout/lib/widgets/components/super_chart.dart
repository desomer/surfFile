/// Composant graphique `SuperChart` basé sur `fl_chart` et lié aux repositories JSON.
///
/// Supporte 5 types de graphiques :
/// * [SuperChartKind.line] (`LineChart` : courbes et aires) ;
/// * [SuperChartKind.bar] (`BarChart` : barres groupées ou empilées) ;
/// * [SuperChartKind.pie] (`PieChart` : camembert et donut) ;
/// * [SuperChartKind.scatter] (`ScatterChart` : nuage de points) ;
/// * [SuperChartKind.radar] (`RadarChart` : radar / toile).
///
/// ## Liaison aux repositories et sélection Maître / Détail
///
/// Le graphique lit son tableau JSON via [SuperChartConfig.binding] et résout
/// les jokers `[?]` grâce à [JsonListScope.resolveSelected]. Un clic sur un
/// point, une barre, une part, un spot, une entrée radar ou une puce de
/// catégorie sélectionne la ligne correspondante dans le [JsonArrayBinding]
/// du tableau (si [SuperChartConfig.enableSelection] est activé), et met en
/// valeur l'élément actuellement sélectionné.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show kSecondaryMouseButton, kTouchSlop;
import 'package:material_ui/material_ui.dart';

import '../../models/json_text_binding.dart';
import '../../models/super_chart_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../super_app.dart';
import '../editing/components/super_chart_editor.dart';
import '../editing/history/editor_history.dart';
import '../editing/slots/editor_slot.dart';
import 'super_layout/slot_implementation.dart';

/// Point de données normalisé extrait pour une ligne du tableau JSON.
@immutable
class _ChartRowPoint {
  const _ChartRowPoint({
    required this.index,
    required this.label,
    required this.yValues,
    required this.xValues,
  });

  final int index;
  final String label;

  /// Valeur Y par série (indexée sur `config.series`).
  final List<double> yValues;

  /// Valeur X numérique par série (indexée sur `config.series`).
  final List<double> xValues;
}

/// Source de tableau JSON résolue pour [SuperChart].
@immutable
class _ChartSource {
  const _ChartSource({
    this.binding,
    this.error,
    this.unselected = false,
    this.parents = const [],
    this.arrays = const [],
  });

  final JsonTextBinding? binding;
  final String? error;
  final bool unselected;
  final List<int> parents;
  final List<JsonArrayBinding> arrays;

  @override
  bool operator ==(Object other) =>
      other is _ChartSource &&
      other.binding == binding &&
      other.error == error &&
      other.unselected == unselected &&
      listEquals(other.parents, parents) &&
      listEquals(other.arrays, arrays);

  @override
  int get hashCode => Object.hash(
    binding,
    error,
    unselected,
    Object.hashAll(parents),
    Object.hashAll(arrays),
  );
}

/// Widget de graphique `fl_chart` configurable et lié aux repositories JSON.
class SuperChart extends StatefulWidget implements SliverCapableWidget {
  const SuperChart({
    required this.id,
    this.config = const SuperChartConfig(),
    this.onConfigChanged,
    super.key,
  });

  /// Identifiant de persistance dans `Appearance.components`.
  final String id;

  /// Configuration initiale avant celle persistée dans l'apparence.
  final SuperChartConfig config;

  /// Appelé après validation de la boîte de dialogue d'édition.
  final ValueChanged<SuperChartConfig>? onConfigChanged;

  @override
  State<SuperChart> createState() => _SuperChartState();
}

class _SuperChartState extends State<SuperChart> {
  final _surface = GlobalKey<EditorSlotState>();
  PointerDownEvent? _secondaryDown;
  int _secondaryButtons = 0;
  bool _secondaryMoved = false;
  late final ValueNotifier<SuperChartConfig> _localConfig;
  JsonRepositoryStore? _store;
  _ChartSource? _source;
  String? _configPath;
  JsonArrayBinding? _selection;
  List<JsonArrayBinding> _listened = const [];
  List<Object?>? _items;
  String? _error;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.config.validate();
    _localConfig = ValueNotifier(widget.config);
  }

  @override
  void didUpdateWidget(SuperChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.config != widget.config) {
      _localConfig.value = widget.config;
    }
  }

  @override
  void dispose() {
    _generation++;
    _store?.unregisterBindings(this);
    _store?.removeListener(_reload);
    _listen(const []);
    _localConfig.dispose();
    super.dispose();
  }

  String? get _template {
    final path = _configPath;
    return path == null ? null : JsonAttributePath(path).toString();
  }

  _ChartSource _resolve(
    SuperChartConfig config,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final binding = config.binding;
    if (binding == null) return const _ChartSource();
    try {
      final resolved = JsonListScope.resolveSelected(binding, scope, store);
      return _ChartSource(
        binding: resolved.binding,
        unselected: resolved.binding == null,
        parents: resolved.indices,
        arrays: resolved.arrays,
      );
    } on FormatException catch (error) {
      return _ChartSource(error: error.message);
    }
  }

  void _listen(List<JsonArrayBinding> arrays) {
    for (final array in _listened) {
      array.removeListener(_selectionChanged);
    }
    _listened = arrays;
    for (final array in arrays) {
      array.addListener(_selectionChanged);
    }
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  void _observe(_ChartSource source, JsonRepositoryStore? store) {
    if (_source == source && identical(_store, store)) return;
    if (_source != source) {
      _items = null;
      _error = null;
    }
    _source = source;
    if (!identical(_store, store)) {
      _store?.unregisterBindings(this);
      _store?.removeListener(_reload);
      _store = store?..addListener(_reload);
    }
    final binding = source.binding;
    _store?.registerBindings(this, [binding?.repositoryId]);
    _selection = binding == null || store == null
        ? null
        : store.bindingOf(binding.repositoryId!).array(_template!);
    _listen([?_selection, ...source.arrays]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final binding = _source?.binding;
    final store = _store;
    if (binding == null || store == null) {
      setState(() {
        _items = null;
        _loading = false;
        _error =
            _source?.error ??
            (store == null && _source?.unselected == true
                ? 'Service de repositories indisponible.'
                : null);
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await store.readArray(binding.repositoryId!, binding.path);
      if (!mounted || generation != _generation) return;
      final selected = _selection?.indexFor(_source!.parents);
      if (selected != null && selected >= items.length) {
        _selection!.clear();
      }
      setState(() {
        _items = items;
        _error = null;
      });
    } on FormatException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.message);
      }
    } on FileSystemException {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Impossible de lire le repository lié.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  int? get _selectedIndex {
    final source = _source;
    if (source == null) return null;
    return _selection?.indexFor(source.parents);
  }

  bool _isSelected(int index) => _selectedIndex == index;

  void _select(int index, SuperChartConfig config) {
    if (!config.enableSelection) return;
    final source = _source;
    if (source == null || index < 0) return;
    final maxCount = _items?.length ?? 0;
    if (index >= maxCount) return;
    _selection?.select(source.parents, index);
  }

  Future<void> _edit(ValueNotifier<SuperChartConfig> configuration) async {
    final history = EditorHistoryScope.controllerOf(context);
    history?.beginTransaction();
    SuperChartConfig? result;
    try {
      result = await showSuperChartEditor(
        context: context,
        config: configuration.value,
      );
      if (result != null && mounted && result != configuration.value) {
        configuration.value = result;
        widget.onConfigChanged?.call(result);
      }
    } finally {
      if (result != null) {
        history?.commitTransaction();
      } else {
        history?.cancelTransaction();
      }
    }
  }

  static double? _toDouble(Object? raw) {
    if (raw is num) {
      final d = raw.toDouble();
      return d.isFinite ? d : null;
    }
    if (raw is String) {
      final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    if (raw is bool) {
      return raw ? 1.0 : 0.0;
    }
    return null;
  }

  static Object? _readRelative(Object? item, String relativePath) {
    final trimmed = relativePath.trim();
    if (trimmed.isEmpty) return item;
    try {
      return JsonAttributePath(trimmed).read(item);
    } on FormatException {
      return null;
    }
  }

  List<_ChartRowPoint> _extractPoints(
    SuperChartConfig config,
    List<Object?> rawItems,
  ) {
    final points = <_ChartRowPoint>[];
    for (var i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      String label = '${i + 1}';
      if (config.labelPath.trim().isNotEmpty) {
        final rawLabel = _readRelative(item, config.labelPath);
        if (rawLabel != null && rawLabel.toString().trim().isNotEmpty) {
          label = rawLabel.toString().trim();
        }
      } else if (item is Map && item['label'] != null) {
        label = item['label'].toString();
      }
      final yValues = <double>[];
      final xValues = <double>[];
      for (final s in config.series) {
        final rawY = _readRelative(item, s.valuePath);
        yValues.add(_toDouble(rawY) ?? 0.0);
        if (s.secondaryValuePath.trim().isNotEmpty) {
          final rawX = _readRelative(item, s.secondaryValuePath);
          xValues.add(_toDouble(rawX) ?? i.toDouble());
        } else {
          xValues.add(i.toDouble());
        }
      }
      points.add(
        _ChartRowPoint(
          index: i,
          label: label,
          yValues: yValues,
          xValues: xValues,
        ),
      );
    }
    return points;
  }

  List<_ChartRowPoint> _demoPoints(SuperChartConfig config) {
    const labels = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai'];
    const basePatterns = [
      [18.0, 32.0, 24.0, 45.0, 38.0],
      [12.0, 20.0, 28.0, 30.0, 42.0],
      [8.0, 15.0, 19.0, 25.0, 31.0],
    ];
    return [
      for (var i = 0; i < labels.length; i++)
        _ChartRowPoint(
          index: i,
          label: labels[i],
          yValues: [
            for (var s = 0; s < config.series.length; s++)
              basePatterns[s % basePatterns.length][i],
          ],
          xValues: [
            for (var s = 0; s < config.series.length; s++) i.toDouble(),
          ],
        ),
    ];
  }

  Color _seriesColor(SuperChartConfig config, int seriesIndex) {
    final explicit = config.series[seriesIndex].color;
    if (explicit != null) return explicit;
    return defaultChartSeriesPalette[seriesIndex %
        defaultChartSeriesPalette.length];
  }

  Color _categoryColor(int categoryIndex) =>
      defaultChartSeriesPalette[categoryIndex %
          defaultChartSeriesPalette.length];

  FlTitlesData _buildCartesianTitles(
    BuildContext context,
    SuperChartConfig config,
    List<_ChartRowPoint> points,
  ) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return FlTitlesData(
      show: config.showAxisLabels || config.showAxisTitles,
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        axisNameWidget:
            config.showAxisTitles && config.xAxisTitle.trim().isNotEmpty
            ? Text(config.xAxisTitle, style: textStyle)
            : null,
        axisNameSize:
            config.showAxisTitles && config.xAxisTitle.trim().isNotEmpty
            ? 20
            : 16,
        sideTitles: SideTitles(
          showTitles: config.showAxisLabels,
          reservedSize: 28,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final idx = value.round();
            if ((value - idx).abs() > 0.01 || idx < 0 || idx >= points.length) {
              return const SizedBox.shrink();
            }
            final isSel = _isSelected(idx);
            return SideTitleWidget(
              meta: meta,
              child: Text(
                points[idx].label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle?.copyWith(
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  color: isSel
                      ? Theme.of(context).colorScheme.primary
                      : textStyle.color,
                ),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        axisNameWidget:
            config.showAxisTitles && config.yAxisTitle.trim().isNotEmpty
            ? Text(config.yAxisTitle, style: textStyle)
            : null,
        axisNameSize:
            config.showAxisTitles && config.yAxisTitle.trim().isNotEmpty
            ? 22
            : 16,
        sideTitles: SideTitles(
          showTitles: config.showAxisLabels,
          reservedSize: 40,
          getTitlesWidget: (value, meta) {
            if (value == meta.max || value == meta.min) {
              // Évite le chevauchement aux extrémités si trop proche.
            }
            return SideTitleWidget(
              meta: meta,
              child: Text(meta.formattedValue, style: textStyle, maxLines: 1),
            );
          },
        ),
      ),
    );
  }

  FlGridData _buildGrid(BuildContext context, SuperChartConfig config) {
    final lineColor = Theme.of(context).colorScheme.outlineVariant
        .withValues(alpha: 0.45);
    return FlGridData(
      show: config.showGrid,
      getDrawingHorizontalLine: (_) => FlLine(color: lineColor, strokeWidth: 1),
      getDrawingVerticalLine: (_) => FlLine(color: lineColor, strokeWidth: 1),
    );
  }

  Widget _buildLineChart(
    BuildContext context,
    SuperChartConfig config,
    List<_ChartRowPoint> points,
  ) {
    final colors = Theme.of(context).colorScheme;
    final lineBars = <LineChartBarData>[];
    for (var s = 0; s < config.series.length; s++) {
      final series = config.series[s];
      final color = _seriesColor(config, s);
      final spots = [
        for (var i = 0; i < points.length; i++)
          FlSpot(points[i].xValues[s], points[i].yValues[s]),
      ];
      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: series.isCurved,
          color: color,
          barWidth: series.strokeWidth,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: series.showDots,
            getDotPainter: (spot, percent, barData, index) {
              final selected = _isSelected(index);
              return FlDotCirclePainter(
                radius: selected ? series.radius + 3 : series.radius,
                color: selected ? colors.primary : color,
                strokeWidth: selected ? 2.5 : 1.5,
                strokeColor: colors.surface,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: series.belowBarArea,
            color: color.withValues(alpha: 0.18),
          ),
        ),
      );
    }

    return LineChart(
      key: ValueKey('super-chart-line-${widget.id}'),
      LineChartData(
        minY: config.minY,
        maxY: config.maxY,
        gridData: _buildGrid(context, config),
        titlesData: _buildCartesianTitles(context, config, points),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: colors.outlineVariant),
            left: BorderSide(color: colors.outlineVariant),
          ),
        ),
        lineBarsData: lineBars,
        lineTouchData: LineTouchData(
          enabled: config.enableTooltips || config.enableSelection,
          handleBuiltInTouches: config.enableTooltips,
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response?.lineBarSpots != null) {
              final first = response!.lineBarSpots!.firstOrNull;
              if (first != null) {
                _select(first.spotIndex, config);
              }
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => [
              for (final spot in touchedSpots)
                LineTooltipItem(
                  '${spot.barIndex < config.series.length ? config.series[spot.barIndex].label : ''}: '
                  '${spot.y == spot.y.roundToDouble() ? spot.y.toInt() : spot.y.toStringAsFixed(2)}',
                  TextStyle(
                    color: colors.onInverseSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart(
    BuildContext context,
    SuperChartConfig config,
    List<_ChartRowPoint> points,
  ) {
    final colors = Theme.of(context).colorScheme;
    final groups = <BarChartGroupData>[];

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final selected = _isSelected(i);
      if (config.barStacked && config.series.length > 1) {
        var cumulative = 0.0;
        final stackItems = <BarChartRodStackItem>[];
        for (var s = 0; s < config.series.length; s++) {
          final nextVal = cumulative + math.max(0.0, point.yValues[s]);
          stackItems.add(
            BarChartRodStackItem(cumulative, nextVal, _seriesColor(config, s)),
          );
          cumulative = nextVal;
        }
        groups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: cumulative,
                width: config.series.first.radius * 2.5,
                rodStackItems: stackItems,
                borderRadius: BorderRadius.circular(4),
                borderSide: selected
                    ? BorderSide(color: colors.onSurface, width: 2)
                    : BorderSide.none,
              ),
            ],
          ),
        );
      } else {
        groups.add(
          BarChartGroupData(
            x: i,
            barsSpace: 4,
            barRods: [
              for (var s = 0; s < config.series.length; s++)
                BarChartRodData(
                  toY: point.yValues[s],
                  color: _seriesColor(config, s),
                  width: config.series[s].radius * 2.2,
                  borderRadius: BorderRadius.circular(4),
                  borderSide: selected
                      ? BorderSide(color: colors.onSurface, width: 2)
                      : BorderSide.none,
                ),
            ],
          ),
        );
      }
    }

    return BarChart(
      key: ValueKey('super-chart-bar-${widget.id}'),
      BarChartData(
        minY: config.minY,
        maxY: config.maxY,
        gridData: _buildGrid(context, config),
        titlesData: _buildCartesianTitles(context, config, points),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: colors.outlineVariant),
            left: BorderSide(color: colors.outlineVariant),
          ),
        ),
        barGroups: groups,
        barTouchData: BarTouchData(
          enabled: config.enableTooltips || config.enableSelection,
          handleBuiltInTouches: config.enableTooltips,
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response?.spot != null) {
              _select(response!.spot!.touchedBarGroupIndex, config);
            }
          },
        ),
      ),
    );
  }

  Widget _buildPieChart(
    BuildContext context,
    SuperChartConfig config,
    List<_ChartRowPoint> points,
  ) {
    final colors = Theme.of(context).colorScheme;
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final val = math.max(0.0, point.yValues.first);
      final selected = _isSelected(i);
      final color = _categoryColor(i);
      sections.add(
        PieChartSectionData(
          value: val <= 0 ? 0.001 : val,
          color: color,
          radius: selected ? 66.0 : 56.0,
          showTitle: config.showAxisLabels,
          title: point.label,
          titleStyle: TextStyle(
            fontSize: selected ? 12 : 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          borderSide: selected
              ? BorderSide(color: colors.onSurface, width: 2.5)
              : BorderSide.none,
        ),
      );
    }

    return PieChart(
      key: ValueKey('super-chart-pie-${widget.id}'),
      PieChartData(
        centerSpaceRadius: config.pieCenterSpaceRadius,
        sectionsSpace: config.pieSectionsSpace,
        sections: sections,
        pieTouchData: PieTouchData(
          enabled: config.enableTooltips || config.enableSelection,
          touchCallback: (event, response) {
            if (event is FlTapUpEvent &&
                response?.touchedSection != null &&
                response!.touchedSection!.touchedSectionIndex >= 0) {
              _select(response.touchedSection!.touchedSectionIndex, config);
            }
          },
        ),
      ),
    );
  }

  Widget _buildScatterChart(
    BuildContext context,
    SuperChartConfig config,
    List<_ChartRowPoint> points,
  ) {
    final colors = Theme.of(context).colorScheme;
    final spots = <ScatterSpot>[];
    final spotRowIndices = <int>[];

    for (var s = 0; s < config.series.length; s++) {
      final series = config.series[s];
      final color = _seriesColor(config, s);
      for (var i = 0; i < points.length; i++) {
        final selected = _isSelected(i);
        spots.add(
          ScatterSpot(
            points[i].xValues[s],
            points[i].yValues[s],
            dotPainter: FlDotCirclePainter(
              radius: selected ? series.radius + 3 : series.radius,
              color: color,
              strokeWidth: selected ? 2.5 : 1.0,
              strokeColor: selected ? colors.onSurface : colors.surface,
            ),
          ),
        );
        spotRowIndices.add(i);
      }
    }

    return ScatterChart(
      key: ValueKey('super-chart-scatter-${widget.id}'),
      ScatterChartData(
        minY: config.minY,
        maxY: config.maxY,
        gridData: _buildGrid(context, config),
        titlesData: _buildCartesianTitles(context, config, points),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: colors.outlineVariant),
            left: BorderSide(color: colors.outlineVariant),
          ),
        ),
        scatterSpots: spots,
        scatterTouchData: ScatterTouchData(
          enabled: config.enableTooltips || config.enableSelection,
          handleBuiltInTouches: config.enableTooltips,
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response?.touchedSpot != null) {
              final spotIdx = response!.touchedSpot!.spotIndex;
              if (spotIdx >= 0 && spotIdx < spotRowIndices.length) {
                _select(spotRowIndices[spotIdx], config);
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildRadarChart(
    BuildContext context,
    SuperChartConfig config,
    List<_ChartRowPoint> points,
  ) {
    final colors = Theme.of(context).colorScheme;
    // RadarDataSet requiert au moins 3 entrées dans fl_chart.
    final paddedPoints = [...points];
    while (paddedPoints.length < 3) {
      final idx = paddedPoints.length;
      paddedPoints.add(
        _ChartRowPoint(
          index: idx,
          label: '-',
          yValues: List<double>.filled(config.series.length, 0.0),
          xValues: List<double>.filled(config.series.length, idx.toDouble()),
        ),
      );
    }

    final dataSets = <RadarDataSet>[
      for (var s = 0; s < config.series.length; s++)
        RadarDataSet(
          fillColor: _seriesColor(config, s).withValues(alpha: 0.22),
          borderColor: _seriesColor(config, s),
          borderWidth: config.series[s].strokeWidth,
          entryRadius: config.series[s].radius,
          dataEntries: [
            for (final p in paddedPoints) RadarEntry(value: p.yValues[s]),
          ],
        ),
    ];

    return RadarChart(
      key: ValueKey('super-chart-radar-${widget.id}'),
      RadarChartData(
        dataSets: dataSets,
        radarBackgroundColor: Colors.transparent,
        borderData: FlBorderData(show: false),
        radarBorderData: BorderSide(color: colors.outlineVariant),
        tickBorderData: BorderSide(
          color: config.showGrid ? colors.outlineVariant : Colors.transparent,
        ),
        gridBorderData: BorderSide(
          color: config.showGrid ? colors.outlineVariant : Colors.transparent,
        ),
        tickCount: 3,
        ticksTextStyle: TextStyle(
          fontSize: 10,
          color: config.showAxisLabels
              ? colors.onSurfaceVariant
              : Colors.transparent,
        ),
        titleTextStyle: TextStyle(fontSize: 11, color: colors.onSurface),
        getTitle: (index, angle) {
          if (!config.showAxisLabels ||
              index < 0 ||
              index >= paddedPoints.length) {
            return const RadarChartTitle(text: '');
          }
          return RadarChartTitle(text: paddedPoints[index].label, angle: 0);
        },
        radarTouchData: RadarTouchData(
          enabled: config.enableSelection,
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response?.touchedSpot != null) {
              final entryIndex = response!.touchedSpot!.touchedRadarEntryIndex;
              if (entryIndex >= 0 && entryIndex < points.length) {
                _select(entryIndex, config);
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildLegendAndCategoryChips(
    BuildContext context,
    SuperChartConfig config,
    List<_ChartRowPoint> points,
    bool isBoundData,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        if (config.showLegend && config.kind != SuperChartKind.pie)
          Wrap(
            key: ValueKey('super-chart-legend-${widget.id}'),
            spacing: 12,
            runSpacing: 4,
            children: [
              for (var s = 0; s < config.series.length; s++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _seriesColor(config, s),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      config.series[s].label,
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
            ],
          ),
        if (points.isNotEmpty &&
            (config.kind == SuperChartKind.pie ||
                (isBoundData && config.enableSelection)))
          Wrap(
            key: ValueKey('super-chart-categories-${widget.id}'),
            spacing: 6,
            runSpacing: 4,
            children: [
              for (var i = 0; i < points.length; i++)
                InkWell(
                  key: ValueKey('super-chart-item-${widget.id}-$i'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: isBoundData && config.enableSelection
                      ? () => _select(i, config)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _isSelected(i)
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest.withValues(
                              alpha: 0.6,
                            ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isSelected(i)
                            ? colors.primary
                            : colors.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (config.kind == SuperChartKind.pie) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _categoryColor(i),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          points[i].label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: _isSelected(i)
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: _isSelected(i)
                                ? colors.onPrimaryContainer
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    SuperChartConfig config,
    bool placeholder,
  ) {
    final colors = Theme.of(context).colorScheme;
    final unbound = config.binding == null;

    if (!placeholder && !unbound && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                key: ValueKey('super-chart-error-${widget.id}'),
                style: TextStyle(color: colors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Recharger le graphique'),
              ),
            ],
          ),
        ),
      );
    }

    if (!placeholder && !unbound && _source?.unselected == true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Aucune ligne sélectionnée.',
            key: ValueKey('super-chart-message-${widget.id}'),
          ),
        ),
      );
    }

    final List<_ChartRowPoint> points;
    final bool isBoundData;
    if (placeholder || unbound) {
      if (!config.showDemoWhenUnbound) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Graphique non lié : choisissez un tableau dans les réglages.',
              key: ValueKey('super-chart-message-${widget.id}'),
            ),
          ),
        );
      }
      points = _demoPoints(config);
      isBoundData = false;
    } else {
      final rawItems = _items;
      if (rawItems == null) {
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return const SizedBox.shrink();
      }
      if (rawItems.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              config.emptyText,
              key: ValueKey('super-chart-message-${widget.id}'),
            ),
          ),
        );
      }
      points = _extractPoints(config, rawItems);
      isBoundData = true;
    }

    final chartWidget = switch (config.kind) {
      SuperChartKind.line => _buildLineChart(context, config, points),
      SuperChartKind.bar => _buildBarChart(context, config, points),
      SuperChartKind.pie => _buildPieChart(context, config, points),
      SuperChartKind.scatter => _buildScatterChart(context, config, points),
      SuperChartKind.radar => _buildRadarChart(context, config, points),
    };

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (config.showLegend ||
              (isBoundData && config.enableSelection && points.isNotEmpty)) ...[
            _buildLegendAndCategoryChips(context, config, points, isBoundData),
            const SizedBox(height: 8),
          ],
          Expanded(child: chartWidget),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = SuperApp.maybeOf(context);
    final registry = app?.registry;
    final configuration =
        registry?.chartController(widget.id, fallback: widget.config) ??
        _localConfig;
    final scope = JsonListScope.maybeOf(context);
    final store = JsonRepositoryScope.maybeOf(context);
    final isSliver = SliverSlotScope.isSliver(context);
    final canConfigure = StyleEditScope.controllerOf(context)?.value ?? true;

    return ValueListenableBuilder<SuperChartConfig>(
      valueListenable: configuration,
      builder: (context, config, _) {
        final placeholder = scope?.placeholder ?? false;
        _configPath = config.binding?.path;
        if (!placeholder) _observe(_resolve(config, scope, store), store);

        // fl_chart's RenderBaseChart registers its own TapGestureRecognizer
        // (including onSecondaryTapDown/Up) and wins the GestureArena before
        // EditorSlot's GestureDetector. Listen to raw pointer events so right
        // clicks over the chart canvas always open the context menu.
        final body = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if (event.buttons == kSecondaryMouseButton) {
              _secondaryDown = event;
              _secondaryButtons = event.buttons;
              _secondaryMoved = false;
            }
          },
          onPointerMove: (event) {
            final down = _secondaryDown;
            if (down != null &&
                down.pointer == event.pointer &&
                (event.position - down.position).distance > kTouchSlop) {
              _secondaryMoved = true;
            }
          },
          onPointerUp: (event) {
            final down = _secondaryDown;
            final buttons = _secondaryButtons;
            final moved = _secondaryMoved;
            _secondaryDown = null;
            _secondaryButtons = 0;
            _secondaryMoved = false;
            if (down == null ||
                down.pointer != event.pointer ||
                moved ||
                (event.position - down.position).distance > kTouchSlop) {
              return;
            }
            if (canConfigure && buttons == kSecondaryMouseButton) {
              _surface.currentState?.openMenu(event.position);
            }
          },
          onPointerCancel: (_) {
            _secondaryDown = null;
            _secondaryButtons = 0;
            _secondaryMoved = false;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boundedHeight = constraints.hasBoundedHeight;
              final content = _buildBody(context, config, placeholder);
              return boundedHeight
                  ? content
                  : SizedBox(height: 240, child: content);
            },
          ),
        );

        return EditorSlot(
          key: _surface,
          id: widget.id,
          label: 'Graphique',
          menuType: 'Chart',
          menuIcon: Icons.insert_chart_outlined,
          menuTooltip: () => formatSuperChartTooltip(
            title:
                _surface.currentState?.titleLabel ??
                editorComponentLabelOf(context)?.label ??
                'Graphique',
            config: config,
          ),
          onEdit: () => _edit(configuration),
          child: isSliver
              ? SliverToBoxAdapter(
                  child: SliverSlotScope(
                    enabled: false,
                    child: SizedBox(height: 260, child: body),
                  ),
                )
              : body,
        );
      },
    );
  }
}
