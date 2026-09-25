// Turning daily rows into something plottable: the four time periods the
// detail sheets offer, the buckets each one collapses days into, and the
// y-axis the chart draws against. Ported from fitness-dashboard's
// web/lib/series.ts with its tests (test/domain/series_test.dart).
//
// Pure, like format.dart — no widgets and no fetching — so the maths can be
// tested without rendering anything. All date handling is local midnight: a
// "day" here is the user's day.

import 'dart:math' as math;

import 'format.dart';

enum Period { week, month, quarter, year }

/// How the days inside one bucket are collapsed.
enum Aggregate { daily, weekly, monthly }

/// A metric reduced to one number per day — what a sheet plots, whichever
/// source it came from.
typedef SeriesPoint = ({DateTime date, num? value});

class PeriodSpec {
  const PeriodSpec(this.key, this.short, this.long, this.aggregate, this.buckets);

  final Period key;

  /// The segmented selector's label.
  final String short;

  /// Spelled out, for the history list's heading.
  final String long;
  final Aggregate aggregate;

  /// How many buckets the window holds, newest last.
  final int buckets;
}

// 13 weeks and 12 months rather than 90 and 365 days: the bucket is the unit
// once the days are averaged, and a part-week at the left edge would plot a
// noisier point than the full weeks beside it.
const periods = [
  PeriodSpec(Period.week, 'W', 'Last 7 days', Aggregate.daily, 7),
  PeriodSpec(Period.month, 'M', 'Last 30 days', Aggregate.daily, 30),
  PeriodSpec(Period.quarter, '3M', 'Last 13 weeks', Aggregate.weekly, 13),
  PeriodSpec(Period.year, 'Y', 'Last 12 months', Aggregate.monthly, 12),
];

PeriodSpec periodSpec(Period period) => periods.firstWhere((p) => p.key == period);

/// One plotted point: a day, a week or a month, and what it averaged.
class Bucket {
  const Bucket({required this.key, required this.start, required this.end, this.value, this.days = 0});

  /// Stable identity — the bucket's first day, as YYYY-MM-DD.
  final String key;
  final DateTime start;

  /// Inclusive. Equal to [start] for daily buckets.
  final DateTime end;

  /// The mean of the days that carried a reading, or null if none did.
  final double? value;

  /// How many days inside the bucket actually carried a reading.
  final int days;
}

/// The local-midnight date, with any time of day discarded.
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Monday of the week [d] falls in — ISO weeks, as everywhere else here.
DateTime startOfWeek(DateTime d) => addDays(d, -(d.weekday - 1));

String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Whole days from [from] to [to]. Rounded, because a DST boundary makes
/// one of those days 23 or 25 hours long.
int daysBetween(DateTime from, DateTime to) =>
    (startOfDay(to).difference(startOfDay(from)).inMinutes / (24 * 60)).round();

/// The window's buckets, oldest first, whether or not any data lands in them
/// — a gap in the watch's history should read as a gap, not close up.
List<({DateTime start, DateTime end})> bucketWindow(Period period, DateTime today) {
  final spec = periodSpec(period);
  final out = <({DateTime start, DateTime end})>[];
  for (var i = spec.buckets - 1; i >= 0; i--) {
    switch (spec.aggregate) {
      case Aggregate.daily:
        final day = addDays(today, -i);
        out.add((start: day, end: day));
      case Aggregate.weekly:
        final start = addDays(startOfWeek(today), -7 * i);
        out.add((start: start, end: addDays(start, 6)));
      case Aggregate.monthly:
        final start = DateTime(today.year, today.month - i, 1);
        // Day 0 of the next month is the last day of this one.
        out.add((start: start, end: DateTime(start.year, start.month + 1, 0)));
    }
  }
  return out;
}

String _bucketKeyFor(DateTime day, Aggregate aggregate) => switch (aggregate) {
  Aggregate.weekly => dayKey(startOfWeek(day)),
  Aggregate.monthly => dayKey(DateTime(day.year, day.month, 1)),
  Aggregate.daily => dayKey(day),
};

/// Collapse daily points into the period's buckets.
///
/// The value is always a mean of the days that had a reading, never a sum —
/// including for steps, so the number means the same thing ("a typical
/// day") whichever period is selected. Days with no reading are left out of
/// the mean rather than counted as zero, which would drag a week's average
/// down for a day the watch simply was not worn.
List<Bucket> bucketSeries(Iterable<SeriesPoint> points, Period period, DateTime today) {
  final spec = periodSpec(period);
  final totals = <String, ({double sum, int days})>{};
  for (final point in points) {
    final value = point.value;
    if (value == null) continue;
    final key = _bucketKeyFor(startOfDay(point.date), spec.aggregate);
    final seen = totals[key];
    totals[key] = seen == null ? (sum: value.toDouble(), days: 1) : (sum: seen.sum + value, days: seen.days + 1);
  }

  return [
    for (final (:start, :end) in bucketWindow(period, startOfDay(today)))
      if (totals[dayKey(start)] case final hit?)
        Bucket(key: dayKey(start), start: start, end: end, value: hit.sum / hit.days, days: hit.days)
      else
        Bucket(key: dayKey(start), start: start, end: end),
  ];
}

/// The mean of the buckets that have a value, weighted by the days behind
/// each — so a half-recorded week counts for half of a full one.
double? seriesAverage(List<Bucket> buckets) {
  var sum = 0.0;
  var days = 0;
  for (final b in buckets) {
    if (b.value == null) continue;
    sum += b.value! * b.days;
    days += b.days;
  }
  return days == 0 ? null : sum / days;
}

/// The newest bucket that actually holds a reading.
Bucket? latestBucket(List<Bucket> buckets) {
  for (var i = buckets.length - 1; i >= 0; i--) {
    if (buckets[i].value != null) return buckets[i];
  }
  return null;
}

String _dayMonth(DateTime d) => '${d.day} ${monthsShort[d.month - 1]}';

const _monthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// X-axis ticks. Null means "no label here" — 30 day-numbers shoulder to
/// shoulder is unreadable, so the longer periods label a subset, counted
/// back from the newest bucket so the right-hand edge is always labelled.
List<String?> tickLabels(List<Bucket> buckets, Period period) {
  int fromEnd(int i) => buckets.length - 1 - i;
  return [
    for (final (i, b) in buckets.indexed)
      switch (period) {
        Period.week => weekdayNarrow(b.start),
        Period.month => fromEnd(i) % 5 == 0 ? '${b.start.day}' : null,
        Period.quarter => fromEnd(i) % 2 == 0 ? _dayMonth(b.start) : null,
        Period.year => _monthsLong[b.start.month - 1][0],
      },
  ];
}

/// The row label in the history list, and the readout above the chart —
/// long enough to stand on its own, unlike the axis ticks.
String bucketLabel(Bucket bucket, Aggregate aggregate, DateTime today) {
  switch (aggregate) {
    case Aggregate.monthly:
      return '${_monthsLong[bucket.start.month - 1]} ${bucket.start.year}';
    case Aggregate.weekly:
      final sameMonth = bucket.start.month == bucket.end.month;
      final from = sameMonth ? '${bucket.start.day}' : _dayMonth(bucket.start);
      return '$from – ${_dayMonth(bucket.end)}';
    case Aggregate.daily:
      final age = daysBetween(bucket.start, today);
      if (age == 0) return 'Today';
      if (age == 1) return 'Yesterday';
      return '${weekdaysShort[bucket.start.weekday - 1]} ${_dayMonth(bucket.start)}';
  }
}

/// The span the whole window covers, for the caption under the headline.
String windowLabel(List<Bucket> buckets) {
  if (buckets.isEmpty) return '';
  final first = buckets.first.start;
  final last = buckets.last.end;
  final from = first.year == last.year ? _dayMonth(first) : '${_dayMonth(first)} ${first.year}';
  return '$from – ${_dayMonth(last)} ${last.year}';
}

class Scale {
  const Scale(this.lo, this.hi, this.ticks);

  final double lo;
  final double hi;
  final List<double> ticks;
}

/// The rungs people read without having to do arithmetic, times a power of
/// ten.
const _stepRungs = [1, 2, 2.5, 5];

/// Can [step] be labelled exactly by a formatter whose finest unit is
/// [minStep]? A step of 0.25 on a one-decimal metric cannot: 80.25 prints as
/// "80.3", so the axis shows a gap of 0.3 where it means 0.25.
bool _renderable(double step, double minStep) {
  if (minStep <= 0) return true;
  final ratio = step / minStep;
  return (ratio - ratio.round()).abs() < 1e-9;
}

/// The smallest readable rung that is at least [raw] and can be labelled
/// exactly. Climbs the ladder rather than dropping 2.5 outright, which would
/// cost a heart-rate-variability axis half its plot.
double _niceStep(double raw, double minStep) {
  final target = math.max(raw > 0 ? raw : 1.0, minStep);
  final start = (math.log(target) / math.ln10).floor();
  for (var exponent = start; exponent <= start + 3; exponent++) {
    final magnitude = math.pow(10, exponent).toDouble();
    for (final rung in _stepRungs) {
      final step = rung * magnitude;
      if (step >= target && _renderable(step, minStep)) return step;
    }
  }
  return target;
}

/// A y-axis domain whose ticks are round numbers — the point of the scale is
/// that a glance turns a dot's height into a value.
///
/// [zeroBased] is for bars: a bar's length *is* its value, so a truncated
/// axis makes it lie. A line plots a level, where a zero baseline would
/// spend the whole plot on the 0–50 bpm nobody has, so it gets a padded
/// domain around the data instead. [domain] pins the range, for a score
/// defined on one (readiness and recovery are both 0–100).
Scale niceScale(
  List<num> values, {
  bool zeroBased = false,
  double minStep = 0,
  int targetTicks = 4,
  (double, double)? domain,
}) {
  if (domain != null) {
    final (lo, hi) = domain;
    return Scale(lo, hi, _ticksBetween(lo, hi, _niceStep((hi - lo) / math.max(targetTicks - 1, 1), minStep)));
  }

  final nums = values.where((v) => v.isFinite).map((v) => v.toDouble()).toList();
  if (nums.isEmpty) return const Scale(0, 1, [0, 1]);

  var min = zeroBased ? 0.0 : nums.reduce(math.min);
  var max = nums.reduce(math.max);

  if (max == min) {
    // A flat series still needs a band to sit in, or it divides by zero.
    final pad = max.abs() > 0 ? max.abs() * 0.1 : 1.0;
    max += pad;
    if (!zeroBased) min -= pad;
  } else if (!zeroBased) {
    final pad = (max - min) * 0.1;
    min -= pad;
    max += pad;
  }

  final step = _niceStep((max - min) / math.max(targetTicks - 1, 1), minStep);
  final lo = zeroBased ? 0.0 : (min / step).floor() * step;
  final ticks = _ticksBetween(lo, (max / step).ceil() * step, step);
  return Scale(ticks.first, ticks.last, ticks);
}

/// Every tick from [lo] up to [hi], rounded to the step's own precision —
/// accumulating a step of 0.1 otherwise produces 0.30000000000000004.
List<double> _ticksBetween(double lo, double hi, double step) {
  final count = math.max(1, ((hi - lo) / step).round());
  final decimals = math.min(10, math.max(0, -(math.log(step) / math.ln10).floor()) + 1);
  return [for (var i = 0; i <= count; i++) double.parse((lo + i * step).toStringAsFixed(decimals))];
}
