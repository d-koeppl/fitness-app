// The detail sheets' chart: one or more series over the same buckets, a
// labelled y-axis, and a crosshair. The port of fitness-dashboard's
// web/components/MetricChart.tsx, drawn with fl_chart.
//
// The axis is the whole point — a sparkline shows a shape, this shows the
// numbers the shape is made of. Several series share one y-axis and are
// never given a second one: two scales on one plot make the reader believe
// a correlation that only comes from where the axes happened to line up.
// Load, fitness and fatigue are all in the same unit, so one axis is also
// the honest one.
//
// fl_chart draws bars and lines in different charts, so a mixed chart is a
// BarChart with a LineChart laid over it on the same y-range and the same
// reserved gutters. The bars are spaced around their slots and the line
// runs from -0.5 to n-0.5, which puts point i at the centre of bar i in
// both. The crosshair and the pointer handling are this widget's own, over
// the whole plot, so the pointer only has to be nearest a bucket.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/key_metrics.dart';
import '../../domain/series.dart';
import '../theme/palette.dart';

class ChartSeries {
  const ChartSeries({required this.key, required this.color, required this.mark, required this.buckets});

  final String key;
  final Color color;
  final ChartMark mark;
  final List<Bucket> buckets;
}

/// The web chart's 320 × 176 frame, kept as a ratio so the plot is the same
/// shape at every width.
const _aspect = 320 / 176;
const _padLeft = 4.0;
const _padTop = 10.0;

/// Room for the y-axis labels, on the right — where the newest data is,
/// which is where the eye already is. Wide enough for "12.5k" or "7.4h".
const _axisWidth = 40.0;

/// Room under the plot for the x-axis labels, so they are never clipped.
const _xBand = 18.0;

class MetricChart extends StatelessWidget {
  const MetricChart({
    super.key,
    required this.series,
    required this.labels,
    required this.formatTick,
    required this.minStep,
    this.domain,
    required this.active,
    required this.onActiveChange,
    required this.semanticLabel,
  });

  /// All series share the buckets, so they share the x-axis by construction.
  final List<ChartSeries> series;

  /// One per bucket; null where no tick should be drawn.
  final List<String?> labels;
  final String Function(num value) formatTick;

  /// The finest step [formatTick] renders exactly — keeps the labels honest
  /// about their spacing (see niceScale).
  final double minStep;
  final (double, double)? domain;
  final int? active;
  final ValueChanged<int?> onActiveChange;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final n = math.max(series.isEmpty ? 0 : series.first.buckets.length, 1);
    final values = [
      for (final s in series)
        for (final b in s.buckets)
          if (b.value != null) b.value!,
    ];
    final scale = niceScale(
      values,
      zeroBased: series.any((s) => s.mark == ChartMark.bar),
      minStep: minStep,
      domain: domain,
      // A pinned 0–100 domain wants quarters; asking for 4 ticks would land
      // on a step of 50 and label only 0 / 50 / 100.
      targetTicks: domain != null ? 5 : 4,
    );
    final step = scale.ticks.length > 1 ? scale.ticks[1] - scale.ticks[0] : scale.hi - scale.lo;
    final bars = series.where((s) => s.mark == ChartMark.bar).toList();
    final lines = series.where((s) => s.mark == ChartMark.line).toList();
    // Past a couple of weeks the dots merge into a bead chain; the line
    // carries the shape and the crosshair carries the values.
    final showDots = n <= 14 && lines.length <= 2;

    final axisStyle = TypeScale.labelSmall.copyWith(
      color: p.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      fontFeatures: TypeScale.tabular,
    );

    Widget tick(double value, TitleMeta meta) {
      final match = scale.ticks.where((t) => (t - value).abs() < step / 1000);
      if (match.isEmpty) return const SizedBox.shrink();
      return SideTitleWidget(
        meta: meta,
        space: 7,
        child: Text(formatTick(match.first), style: axisStyle),
      );
    }

    Widget label(double value, TitleMeta meta) {
      final i = value.round();
      if ((value - i).abs() > 1e-6 || i < 0 || i >= labels.length || labels[i] == null) {
        return const SizedBox.shrink();
      }
      return SideTitleWidget(
        meta: meta,
        space: 3,
        child: Text(labels[i]!, style: axisStyle.copyWith(color: active == i ? p.onSurface : p.onSurfaceVariant)),
      );
    }

    Widget nothing(double value, TitleMeta meta) => const SizedBox.shrink();

    FlTitlesData titles({required bool drawn}) => FlTitlesData(
      leftTitles: const AxisTitles(),
      topTitles: const AxisTitles(),
      rightTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: _axisWidth,
          interval: step,
          getTitlesWidget: drawn ? tick : nothing,
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: _xBand,
          interval: 1,
          getTitlesWidget: drawn ? label : nothing,
        ),
      ),
    );

    return Semantics(
      label: semanticLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = width / _aspect;
          final plotWidth = width - _padLeft - _axisWidth;
          final plotHeight = height - _padTop - _xBand;
          final bandWidth = plotWidth / n;
          final barWidth = (bandWidth - 2).clamp(1.5, 18.0);

          int indexAt(Offset position) => ((position.dx - _padLeft) / bandWidth).floor().clamp(0, n - 1);

          final grid = BarChart(
            BarChartData(
              minY: scale.lo,
              maxY: scale.hi,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(enabled: false),
              borderData: FlBorderData(show: false),
              titlesData: titles(drawn: true),
              // Hairline, one step off the surface, so the grid stays
              // behind the data.
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) => FlLine(color: p.outlineVariant, strokeWidth: 1),
              ),
              barGroups: [
                for (var i = 0; i < n; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      for (final s in bars.isEmpty ? [null] : bars)
                        // Every slot carries a rod, empty or not: the bars
                        // are spaced by their widths, and a missing one
                        // would shift the rest off their buckets.
                        _rod(s, i, scale.lo, barWidth.toDouble(), active),
                    ],
                  ),
              ],
            ),
            duration: Duration.zero,
          );

          final overlay = lines.isEmpty
              ? null
              : LineChart(
                  LineChartData(
                    minX: -0.5,
                    maxX: n - 0.5,
                    minY: scale.lo,
                    maxY: scale.hi,
                    lineTouchData: const LineTouchData(enabled: false),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: titles(drawn: false),
                    clipData: const FlClipData.none(),
                    lineBarsData: [
                      for (final s in lines)
                        _line(s, p.surface, washed: series.length == 1, dots: showDots, active: active),
                    ],
                  ),
                  duration: Duration.zero,
                );

          return MouseRegion(
            onHover: (event) => onActiveChange(indexAt(event.localPosition)),
            onExit: (_) => onActiveChange(null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final i = indexAt(details.localPosition);
                onActiveChange(i == active ? null : i);
              },
              // Horizontal only, so the sheet still scrolls vertically.
              onHorizontalDragStart: (details) => onActiveChange(indexAt(details.localPosition)),
              onHorizontalDragUpdate: (details) => onActiveChange(indexAt(details.localPosition)),
              child: SizedBox(
                width: width,
                height: height,
                child: Padding(
                  padding: const EdgeInsets.only(left: _padLeft, top: _padTop),
                  child: Stack(
                    children: [
                      Positioned.fill(child: grid),
                      // The crosshair: readers aim at a date, not at a 2px line.
                      if (active != null)
                        Positioned(
                          left: (active! + 0.5) * bandWidth - 0.5,
                          top: 0,
                          width: 1,
                          height: plotHeight,
                          child: ColoredBox(color: p.outline),
                        ),
                      if (overlay != null) Positioned.fill(child: overlay),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

BarChartRodData _rod(ChartSeries? s, int i, double baseline, double width, int? active) {
  final value = s?.buckets[i].value;
  if (s == null || value == null) {
    return BarChartRodData(fromY: baseline, toY: baseline, width: width, color: Colors.transparent);
  }
  return BarChartRodData(
    fromY: baseline,
    toY: value,
    width: width,
    color: s.color.withValues(alpha: active == null || active == i ? 1 : 0.4),
    // A rounded cap and square feet: it grows from the baseline.
    borderRadius: BorderRadius.vertical(top: Radius.circular(math.min(3, width / 2))),
  );
}

/// A gap in the data breaks the line rather than being drawn across — the
/// watch was off, and a straight line through would invent readings.
LineChartBarData _line(ChartSeries s, Color ring, {required bool washed, required bool dots, required int? active}) {
  final buckets = s.buckets;
  final newest = buckets.lastIndexWhere((b) => b.value != null);
  bool solo(int i) =>
      (i == 0 || buckets[i - 1].value == null) && (i == buckets.length - 1 || buckets[i + 1].value == null);

  return LineChartBarData(
    spots: [for (final (i, b) in buckets.indexed) b.value == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), b.value!)],
    color: s.color,
    barWidth: 2,
    isStrokeCapRound: true,
    isStrokeJoinRound: true,
    // A wash under a single line reads as "how much"; under several it
    // would just muddy them.
    belowBarData: BarAreaData(show: washed, color: s.color.withValues(alpha: 0.1)),
    dotData: FlDotData(
      checkToShowDot: (spot, _) {
        final i = spot.x.round();
        return dots || i == newest || i == active || solo(i);
      },
      // Each dot carries a ring in the surface colour so it stays legible
      // where it crosses a line or another dot.
      getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
        radius: spot.x.round() == active ? 4.5 : 3,
        color: s.color,
        strokeWidth: 2,
        strokeColor: ring,
      ),
    ),
  );
}
