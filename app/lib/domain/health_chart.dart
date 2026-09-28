// What the Health tab's featured chart and its list rows draw, reduced to
// numbers: which of the three chart styles a metric gets, the band a heart
// metric counts as normal, where a value sits in its range, and the dates
// under the chart. Pure, like series.dart; the painting is in
// lib/ui/charts/health_chart.dart.

import 'dart:math' as math;

import 'format.dart';
import 'key_metrics.dart';

/// The featured chart's three styles.
enum HeroStyle {
  /// A smoothed line over a fading wash: a level that drifts.
  area,

  /// A bar per day from zero, the newest lit: a daily amount.
  bars,

  /// A line over the band that is normal for you, days outside it marked:
  /// a heart metric, where the question is "is today unusual".
  band,
}

HeroStyle heroStyleFor(MetricKey key) => switch (key) {
  MetricKey.restingHr || MetricKey.hrvMs => HeroStyle.band,
  MetricKey.steps || MetricKey.sleepMinutes => HeroStyle.bars,
  _ => HeroStyle.area,
};

/// How far back "normal" looks, whatever range is on screen — a normal that
/// moved with the 7/30/90 pills would say a different thing about the same
/// day depending on which one was picked.
const baselineDays = 30;

/// Fewer readings than this and there is no normal to speak of.
const _minBaselineReadings = 7;

class NormalRange {
  const NormalRange(this.lo, this.hi);

  final double lo;
  final double hi;
}

/// How wide normal is, in standard deviations either side of the mean. One
/// would call a third of all days unusual by definition; at one and a half
/// it is about one in eight, which is what "unusual" should mean.
const normalWidth = 1.5;

/// [normalWidth] standard deviations either side of the mean of the
/// measured values, or null when there are too few of them.
NormalRange? normalRange(Iterable<num?> values) {
  final nums = values.whereType<num>().map((v) => v.toDouble()).toList();
  if (nums.length < _minBaselineReadings) return null;
  final mean = nums.reduce((a, b) => a + b) / nums.length;
  final variance = nums.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / nums.length;
  final sd = math.sqrt(variance);
  return NormalRange(mean - normalWidth * sd, mean + normalWidth * sd);
}

enum BandStatus { below, within, above }

BandStatus bandStatus(NormalRange range, num value) {
  if (value < range.lo) return BandStatus.below;
  if (value > range.hi) return BandStatus.above;
  return BandStatus.within;
}

String bandStatusLabel(BandStatus status) => switch (status) {
  BandStatus.below => 'Below your normal range',
  BandStatus.within => 'Within your normal range',
  BandStatus.above => 'Above your normal range',
};

/// Where the current value sits between the range's low and high, and where
/// its average does, both 0–1 along the track.
class RangePosition {
  const RangePosition({required this.low, required this.high, required this.position, required this.meanPosition});

  final num low;
  final num high;
  final double position;
  final double meanPosition;
}

/// Null when nothing was measured. A current value outside the measured
/// values — weight carried forward from before the range — widens the
/// track to hold it rather than pinning the dot to an end.
RangePosition? rangePosition(Iterable<num?> values, num? current) {
  final nums = values.whereType<num>().toList();
  if (nums.isEmpty || current == null) return null;
  final mean = nums.reduce((a, b) => a + b) / nums.length;
  final low = math.min(nums.reduce(math.min), current);
  final high = math.max(nums.reduce(math.max), current);
  final span = high - low;
  double at(num v) => span == 0 ? 0.5 : ((v - low) / span).toDouble();
  return RangePosition(low: low, high: high, position: at(current), meanPosition: at(mean));
}

/// The labels under the featured chart, one per day, null where none is
/// drawn: every weekday for a week, otherwise five dates spread evenly with
/// the newest always among them.
List<String?> heroLabels(List<DateTime> dates) {
  final n = dates.length;
  if (n <= 7) return [for (final d in dates) weekdaysShort[local(d).weekday - 1]];
  const count = 5;
  final picked = {for (var k = 0; k < count; k++) ((n - 1) * k / (count - 1)).round()};
  return [
    for (final (i, d) in dates.indexed)
      picked.contains(i) ? '${local(d).day} ${monthsShort[local(d).month - 1]}' : null,
  ];
}
