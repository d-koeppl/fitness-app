// One session's heart rate, drawn the way the Google Health app draws it:
// a trace that changes colour as it crosses a zone, a dotted line where
// each zone starts, and the time spent in each one underneath. The port of
// fitness-dashboard's web/components/HeartRateChart.tsx.
//
// Not HealthChart: the x-axis is minutes inside one session, the points are
// unevenly spaced in time, and the colour of the line is itself a value.
// The trace arrives already thinned by the server, keeping each bucket's
// highest and lowest reading — the peaks are what the colouring is about.

import 'dart:math' as math;

import 'package:fitness_api/fitness_api.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/heart_rate.dart';
import '../theme/palette.dart';

const _aspect = 320 / 176;

/// Narrower than HealthChart's gutter: these labels are always a bare bpm.
const _axisWidth = 34.0;

class HeartRateChart extends StatelessWidget {
  const HeartRateChart({super.key, required this.trace});

  final SessionHeartRateOut trace;

  @override
  Widget build(BuildContext context) {
    final samples = samplesOf(trace);
    // The sheet says what it has to about an empty trace; this just refuses
    // to draw an axis around nothing.
    if (samples.isEmpty) return const SizedBox.shrink();

    final p = Palette.of(context);
    final zones = trace.zones;
    final scale = bpmScale(samples, zones);
    final step = scale.ticks.length > 1 ? scale.ticks[1] - scale.ticks[0] : 10;
    final first = samples.first.$1;
    final last = samples.last.$1;
    final bars = zoneBars(zones);
    final axisStyle = TypeScale.labelSmall.copyWith(
      color: p.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      fontFeatures: TypeScale.tabular,
    );

    final chart = LineChart(
      LineChartData(
        minX: first.toDouble(),
        // A session that somehow holds a single instant still needs a width.
        maxX: math.max(last, first + 1).toDouble(),
        minY: scale.lo.toDouble(),
        maxY: scale.hi.toDouble(),
        lineTouchData: const LineTouchData(enabled: false),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: const AxisTitles(),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _axisWidth,
              interval: step.toDouble(),
              getTitlesWidget: (value, meta) =>
                  scale.ticks.contains(value.round()) && (value - value.round()).abs() < 1e-6
                  ? SideTitleWidget(
                      meta: meta,
                      space: 6,
                      child: Text('${value.round()}', style: axisStyle),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        // Where each zone begins, in that zone's own colour, dotted so it
        // reads as reference rather than as another series. Only boundaries
        // inside the plot: one clamped to the edge would claim a threshold
        // sits where it does not.
        extraLinesData: ExtraLinesData(
          extraLinesOnTop: false,
          horizontalLines: [
            for (final zone in zones)
              if (zone.lowerBpm != null && zone.lowerBpm! > scale.lo && zone.lowerBpm! < scale.hi)
                HorizontalLine(
                  y: zone.lowerBpm!.toDouble(),
                  color: p.zoneColor(zone.zone).withValues(alpha: 0.9),
                  strokeWidth: 1,
                  dashArray: const [1, 4],
                  strokeCap: StrokeCap.round,
                ),
          ],
        ),
        lineBarsData: [
          for (final segment in traceSegments(samples, zones))
            LineChartBarData(
              spots: [for (final (t, bpm) in segment.points) FlSpot(t.toDouble(), bpm.toDouble())],
              color: segment.zone == null ? p.primary.color : p.zoneColor(segment.zone),
              barWidth: 1.5,
              isStrokeCapRound: true,
              isStrokeJoinRound: true,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
      duration: Duration.zero,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Heart rate through the session, ${trace.minBpm}–${trace.maxBpm} bpm',
          child: AspectRatio(
            aspectRatio: _aspect,
            child: Padding(padding: const EdgeInsets.only(left: 4, top: 10), child: chart),
          ),
        ),
        // Start and end only: the reader wants to know when it happened,
        // not to look up a value at 17:04.
        Padding(
          padding: const EdgeInsets.only(left: 4, right: _axisWidth, top: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(fmtOffsetClock(trace.startTs, first), style: axisStyle),
              Text(fmtOffsetClock(trace.startTs, last), style: axisStyle),
            ],
          ),
        ),
        if (bars.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final bar in bars)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: p.zoneColor(bar.zone), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(bar.label, style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (final bar in bars) ...[
            Text(
              '${bar.label} · ${bar.percent}% · ${fmtZoneDuration(bar.seconds)}',
              style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            // A share of the session, so the bars read against each other.
            // A spell too short to see still gets a sliver: a bar at 0% and
            // a zone that is not listed at all are different things.
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: p.surfaceContainerHighest),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: math.max(bar.percent, 1.5) / 100,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: p.zoneColor(bar.zone), borderRadius: BorderRadius.circular(5)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}
