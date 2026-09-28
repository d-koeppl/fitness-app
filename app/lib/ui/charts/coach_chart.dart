// A chart the coach drew in a reply (ADR-035): a ```chart block, parsed by
// lib/domain/coach_chart.dart. Line and bar charts go through HealthChart,
// the detail sheets' chart, so a chart in a reply reads like every other
// chart in the app — one labelled y-axis, gaps for missing values, and the
// crosshair. Its lines stay straight: the x-axis may be categories. A pie is fl_chart's own, with its shares written out beside it.
//
// A block that does not parse is shown as its source with the reason, as
// the web did for a Mermaid diagram it could not render: the model wrote
// it freehand, so a bad one is a bad reply, not a bug here.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/coach_chart.dart';
import '../../domain/format.dart';
import '../../domain/key_metrics.dart';
import '../theme/palette.dart';
import 'health_chart.dart';

/// How many x-axis labels fit under a phone-width chart.
const _maxTicks = 6;

class CoachChartView extends StatefulWidget {
  const CoachChartView({super.key, required this.source, required this.fallback});

  final String source;

  /// How the block is shown when it cannot be drawn (its source, as code).
  final Widget Function(String source) fallback;

  @override
  State<CoachChartView> createState() => _CoachChartViewState();
}

class _CoachChartViewState extends State<CoachChartView> {
  int? _active;
  late CoachChartResult _parsed = parseCoachChart(widget.source);

  @override
  void didUpdateWidget(CoachChartView old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _parsed = parseCoachChart(widget.source);
      _active = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final chart = _parsed.chart;
    if (chart == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Could not draw this chart: ${_parsed.error}',
            style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          widget.fallback(widget.source),
        ],
      );
    }

    final colors = _seriesColors(p);
    final digits = _digits(chart);
    String fmt(num v) => fmtNumber(v, digits);
    final unit = chart.unit == null ? '' : ' ${chart.unit}';

    final Widget plot;
    final List<Widget> legend;
    if (chart.type == CoachChartType.pie) {
      final values = chart.series.first.values;
      final total = values.fold<double>(0, (sum, v) => sum + (v ?? 0));
      plot = AspectRatio(
        aspectRatio: 2,
        child: PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 28,
            sections: [
              for (final (i, v) in values.indexed)
                if (v != null && v > 0)
                  PieChartSectionData(value: v, color: colors[i % colors.length], radius: 44, showTitle: false),
            ],
          ),
        ),
      );
      legend = [
        for (final (i, label) in chart.labels.indexed)
          _LegendEntry(
            color: colors[i % colors.length],
            text: values[i] == null
                ? '$label: —'
                : '$label: ${fmt(values[i]!)}$unit'
                      '${total > 0 ? ' (${jsRound(values[i]! / total * 100)}%)' : ''}',
          ),
      ];
    } else {
      final n = chart.labels.length;
      final every = (n / _maxTicks).ceil();
      plot = HealthChart(
        series: [
          for (final (i, s) in chart.series.indexed)
            HealthSeries(
              values: s.values,
              color: colors[i % colors.length],
              mark: chart.type == CoachChartType.bar ? ChartMark.bar : ChartMark.line,
              // The x-axis may be categories, not days.
              smooth: false,
            ),
        ],
        labels: [for (var i = 0; i < n; i++) (i % every == 0 || i == n - 1) ? chart.labels[i] : null],
        formatTick: fmt,
        minStep: math.pow(10, -digits).toDouble(),
        active: _active,
        onActiveChange: (i) => setState(() => _active = i),
        semanticLabel: chart.title ?? 'Chart',
      );
      final at = _active;
      legend = [
        for (final (i, s) in chart.series.indexed)
          _LegendEntry(
            color: colors[i % colors.length],
            text: at == null ? s.name : '${s.name}: ${s.values[at] == null ? '—' : '${fmt(s.values[at]!)}$unit'}',
          ),
      ];
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Shape.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chart.title != null) ...[
            Text(chart.title!, style: TypeScale.titleSmall.copyWith(color: p.onSurface)),
            const SizedBox(height: 2),
          ],
          Text(
            _active != null && chart.type != CoachChartType.pie
                ? chart.labels[_active!]
                : (chart.unit ?? (chart.type == CoachChartType.pie ? 'Share' : '')),
            style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          plot,
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: legend),
        ],
      ),
    );
  }

  /// Distinct, theme-following colours, in the order the chart's own
  /// sheets use them: the fitness line, the fatigue line, then the rest.
  List<Color> _seriesColors(Palette p) => [
    p.primary.color,
    p.warning.color,
    p.tertiary.color,
    p.success.color,
    p.error.color,
    p.secondary.color,
  ];

  /// As few decimals as the numbers need, at most two.
  int _digits(CoachChart chart) {
    final values = [
      for (final s in chart.series)
        for (final v in s.values) ?v,
    ];
    for (var d = 0; d < 2; d++) {
      final scale = math.pow(10, d);
      if (values.every((v) => ((v * scale) - (v * scale).roundToDouble()).abs() < 1e-9)) return d;
    }
    return 2;
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TypeScale.labelMedium.copyWith(color: p.onSurface, fontFeatures: TypeScale.tabular),
          ),
        ),
      ],
    );
  }
}
