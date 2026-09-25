// Every metric you can tap open, defined once — ported from
// fitness-dashboard's web/lib/key-metrics.ts. The Health tab's cards, the
// Today tab's tiles and (phase 5) the detail sheets read from here, so a
// colour or a unit cannot drift between a summary and its detail.
//
// Colours are named by role (MetricHue), not given as Colors: lib/ui/theme
// resolves them for light and dark, and this file stays free of Flutter.

import 'package:fitness_api/fitness_api.dart';

import 'format.dart';

enum MetricKey { restingHr, hrvMs, steps, sleepMinutes, weightKg, vo2max, readiness, recovery, fitness, fatigue, form }

/// Weight and VO2 max are not recorded every day. A gap in them is "not
/// measured", so a *current* value falls back to the last reading there was
/// (ADR-018); charts still leave the days between readings empty.
bool isSparseMetric(MetricKey key) => key == MetricKey.weightKg || key == MetricKey.vo2max;

/// The palette roles a metric is drawn in; see lib/ui/theme/palette.dart.
enum MetricHue {
  success,

  /// Steps and VO2 max: success mixed 70/30 with tertiary.
  successTertiary,
  tertiary,
  primary,
  secondary,
  warning,
}

/// Which mark a chart draws: a count or a duration is a magnitude and gets
/// bars from zero; a level like resting heart rate gets a line.
enum ChartMark { bar, line }

sealed class MetricDef {
  const MetricDef({
    required this.key,
    required this.title,
    required this.mark,
    required this.color,
    required this.band,
    required this.format,
    required this.formatTick,
    required this.minStep,
    this.domain,
  });

  final MetricKey key;
  final String title;
  final ChartMark mark;
  final MetricHue color;

  /// The container colour of [color]'s role, behind a sparkline.
  final MetricHue band;

  /// With its unit: the headline, a card's big number, the list rows.
  final String Function(num value) format;

  /// Without its unit, and compact, for axis ticks.
  final String Function(num value) formatTick;

  /// The finest axis step [formatTick] renders exactly.
  final double minStep;

  /// A pinned y-axis, only for scores defined on a fixed range.
  final (double, double)? domain;
}

/// Read straight off the watch's daily rows.
class HealthMetricDef extends MetricDef {
  const HealthMetricDef({
    required super.key,
    required super.title,
    required super.mark,
    required super.color,
    required super.band,
    required super.format,
    required super.formatTick,
    required super.minStep,
    required this.pick,
  });

  final num? Function(DailyHealthOut row) pick;
}

/// The training model's 0–100 scores, which end a day later than the load.
class ScoreMetricDef extends MetricDef {
  const ScoreMetricDef({
    required super.key,
    required super.title,
    required super.mark,
    required super.color,
    required super.band,
    required super.format,
    required super.formatTick,
    required super.minStep,
    required super.domain,
    required this.pick,
  });

  final num? Function(ScorePointOut row) pick;
}

/// Fitness, Fatigue and Form, read off the day series.
class LoadMetricDef extends MetricDef {
  const LoadMetricDef({
    required super.key,
    required super.title,
    required super.mark,
    required super.color,
    required super.band,
    required super.format,
    required super.formatTick,
    required super.minStep,
    required this.pick,
  });

  final num? Function(DayPointOut row) pick;
}

String _round(num v) => '${jsRound(v)}';

/// Keeps the "+" on a positive value. Rounds before it decides on the sign,
/// so a value that rounds to nothing is "0" from either side.
String signed(num v) {
  final rounded = jsRound(v);
  if (rounded == 0) return '0';
  return '${rounded > 0 ? '+' : ''}$rounded';
}

/// "12.5k" rather than "12,480" in an axis gutter.
String compact(num v) {
  if (v.abs() < 1000) return _round(v);
  final thousands = v / 1000;
  return '${thousands.toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
}

/// `Number(v.toFixed(1))` written back out: one decimal, trailing zero dropped.
String oneDecimalTrimmed(num v) {
  final fixed = double.parse(v.toStringAsFixed(1));
  return fixed == fixed.truncateToDouble() ? '${fixed.toInt()}' : '$fixed';
}

/// The six the Health tab lays out, in its order.
final healthMetrics = <HealthMetricDef>[
  HealthMetricDef(
    key: MetricKey.restingHr,
    title: 'Resting heart rate',
    mark: ChartMark.line,
    color: MetricHue.success,
    band: MetricHue.success,
    pick: (d) => d.restingHr,
    format: (v) => '${jsRound(v)} bpm',
    formatTick: _round,
    minStep: 1,
  ),
  HealthMetricDef(
    key: MetricKey.hrvMs,
    title: 'Heart rate variability',
    mark: ChartMark.line,
    color: MetricHue.success,
    band: MetricHue.success,
    pick: (d) => d.hrvMs,
    format: (v) => '${jsRound(v)} ms',
    formatTick: _round,
    minStep: 1,
  ),
  HealthMetricDef(
    key: MetricKey.steps,
    title: 'Steps',
    mark: ChartMark.bar,
    color: MetricHue.successTertiary,
    band: MetricHue.success,
    pick: (d) => d.steps,
    format: fmtInt,
    formatTick: compact,
    minStep: 1,
  ),
  HealthMetricDef(
    key: MetricKey.sleepMinutes,
    title: 'Sleep',
    mark: ChartMark.bar,
    color: MetricHue.tertiary,
    band: MetricHue.tertiary,
    // Hours, not the stored minutes, so an axis reads as a night's sleep.
    pick: (d) => d.sleepMinutes == null ? null : d.sleepMinutes! / 60,
    format: (v) => fmtSleep(v * 60),
    formatTick: (v) => '${oneDecimalTrimmed(v)}h',
    minStep: 0.1,
  ),
  HealthMetricDef(
    key: MetricKey.weightKg,
    title: 'Weight',
    mark: ChartMark.line,
    color: MetricHue.primary,
    band: MetricHue.primary,
    pick: (d) => d.weightKg,
    format: (v) => '${v.toStringAsFixed(1)} kg',
    formatTick: oneDecimalTrimmed,
    minStep: 0.1,
  ),
  HealthMetricDef(
    key: MetricKey.vo2max,
    title: 'VO2 max',
    mark: ChartMark.line,
    color: MetricHue.successTertiary,
    band: MetricHue.success,
    pick: (d) => d.vo2max,
    format: (v) => v.toStringAsFixed(1),
    formatTick: oneDecimalTrimmed,
    minStep: 0.1,
  ),
];

/// The two 0–100 scores, pinned to that range: the number only means
/// anything against it.
final scoreMetrics = <ScoreMetricDef>[
  ScoreMetricDef(
    key: MetricKey.readiness,
    title: 'Readiness',
    mark: ChartMark.line,
    color: MetricHue.primary,
    band: MetricHue.primary,
    pick: (p) => p.readiness,
    format: (v) => '${jsRound(v)}/100',
    formatTick: _round,
    minStep: 1,
    domain: (0, 100),
  ),
  ScoreMetricDef(
    key: MetricKey.recovery,
    title: 'Recovery',
    mark: ChartMark.line,
    color: MetricHue.success,
    band: MetricHue.success,
    pick: (p) => p.recovery,
    format: (v) => '${jsRound(v)}/100',
    formatTick: _round,
    minStep: 1,
    domain: (0, 100),
  ),
];

/// The Banister model's outputs, in Active Zone Minutes per day, in the
/// colours they wear on the training-status chart. Form has a meaningful
/// zero, so it carries its sign everywhere.
final loadMetrics = <LoadMetricDef>[
  LoadMetricDef(
    key: MetricKey.fitness,
    title: 'Fitness',
    mark: ChartMark.line,
    color: MetricHue.primary,
    band: MetricHue.primary,
    pick: (p) => p.fitness,
    format: (v) => v.toStringAsFixed(1),
    formatTick: _round,
    minStep: 1,
  ),
  LoadMetricDef(
    key: MetricKey.fatigue,
    title: 'Fatigue',
    mark: ChartMark.line,
    color: MetricHue.warning,
    band: MetricHue.warning,
    pick: (p) => p.fatigue,
    format: (v) => v.toStringAsFixed(1),
    formatTick: _round,
    minStep: 1,
  ),
  LoadMetricDef(
    key: MetricKey.form,
    title: 'Form',
    mark: ChartMark.line,
    color: MetricHue.secondary,
    band: MetricHue.secondary,
    // Derived: the API reports Form only as today's number.
    pick: (p) => p.fitness - p.fatigue,
    format: signed,
    formatTick: signed,
    minStep: 1,
  ),
];

final Map<MetricKey, MetricDef> metricByKey = {
  for (final m in <MetricDef>[...healthMetrics, ...scoreMetrics, ...loadMetrics]) m.key: m,
};
