// Everything the session heart rate chart needs that is not drawing — which
// zone a reading is in, where one colour of the trace ends and the next
// begins, and how the time-in-zone bars are worded. Ported from
// fitness-dashboard's web/lib/heart-rate.ts with its tests.
//
// Pure and here rather than in the widget for the usual reason: a segment
// that silently drops a sample, or a percentage that does not add up, is
// invisible in a chart and obvious in a test. The zone colours are roles
// the palette resolves (zoneRole in lib/ui/theme/palette.dart).

import 'dart:math' as math;

import 'package:fitness_api/fitness_api.dart';

import 'format.dart';

/// One reading: seconds into the session, and beats per minute.
typedef Sample = (num, num);

/// The API sends each sample as a two-element array.
List<Sample> samplesOf(SessionHeartRateOut trace) => [for (final s in trace.samples) (s[0] as num, s[1] as num)];

/// The Google Health app's own names for the four zones, in English. The
/// API sends Google's enum spellings, which are Fitbit-era and not what the
/// app on the phone says.
const zoneLabel = {'light': 'Light', 'fat_burn': 'Moderate', 'cardio': 'Vigorous', 'peak': 'Peak'};

/// Which zone a reading falls in — the same half-open-upwards rule the
/// server uses (api/analysis/heart_rate.py), so a reading exactly on a
/// boundary is coloured as the higher zone on the chart and counted as the
/// higher zone in the bars.
String? zoneOf(num bpm, List<HeartRateZoneOut> zones) {
  String? found;
  for (final zone in zones) {
    if (zone.lowerBpm == null || bpm >= zone.lowerBpm!) found = zone.zone;
  }
  return found;
}

class TraceSegment {
  TraceSegment(this.zone, this.points);

  final String? zone;
  final List<Sample> points;
}

/// The trace split into runs of one colour.
///
/// Each run carries the first point of the run that follows it, so the
/// lines meet instead of leaving a gap at every colour change. With no zones
/// (nothing to colour by) the whole trace comes back as one uncoloured
/// segment, which is what the chart draws when no max HR is configured.
List<TraceSegment> traceSegments(List<Sample> samples, List<HeartRateZoneOut> zones) {
  if (samples.isEmpty) return [];
  if (zones.isEmpty) return [TraceSegment(null, samples)];

  final segments = <TraceSegment>[];
  var current = TraceSegment(zoneOf(samples.first.$2, zones), [samples.first]);
  for (final sample in samples.skip(1)) {
    final zone = zoneOf(sample.$2, zones);
    current.points.add(sample);
    if (zone == current.zone) continue;
    // Closed *on* the next sample, so the two lines share a point.
    segments.add(current);
    current = TraceSegment(zone, [sample]);
  }
  segments.add(current);
  return segments;
}

class ZoneBar {
  const ZoneBar(this.zone, this.label, this.seconds, this.percent);

  final String zone;
  final String label;
  final num seconds;

  /// Of the time the zones account for, rounded to whole percent.
  final int percent;
}

/// The "time in each zone" bars, in intensity order like the app's. Zones
/// with no time in them are dropped, and an all-zero set comes back empty.
List<ZoneBar> zoneBars(List<HeartRateZoneOut> zones) {
  final total = zones.fold<num>(0, (sum, zone) => sum + zone.seconds);
  if (total <= 0) return [];
  return [
    for (final zone in zones)
      if (zone.seconds > 0)
        ZoneBar(zone.zone, zoneLabel[zone.zone] ?? zone.zone, zone.seconds, jsRound(zone.seconds / total * 100)),
  ];
}

/// "3 min", "1 h 36 min" — the phone app's own wording, rounded to the
/// nearest minute, so a bar reading 0 min held less than half a minute.
String fmtZoneDuration(num seconds) {
  final minutes = jsRound(seconds / 60);
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
}

/// "17:00" from an offset into the session, in the clock time the session
/// happened at.
String fmtOffsetClock(DateTime? start, num offsetSeconds) {
  if (start == null) return '';
  return fmtTime(start.add(Duration(milliseconds: (offsetSeconds * 1000).round())));
}

/// What the sheet says when there is no trace to draw. Null means there is
/// one — the two empty cases are genuinely different.
String? emptyTraceReason(SessionHeartRateOut trace) {
  if (trace.samples.isNotEmpty) return null;
  return trace.fetchedAt != null
      ? 'The watch recorded no heart rate for this session.'
      : 'Not synced yet — heart rate is fetched a few sessions at a time, newest first.';
}

/// The steps a bpm axis reads well at. Not niceScale's ladder: that one
/// pads the data by a tenth before snapping, which on a 60-beat spread
/// rounds out to a 50-bpm step.
const _bpmSteps = [10, 20, 25, 50];

typedef BpmScale = ({int lo, int hi, List<int> ticks});

/// The bpm axis. The readings decide the range, but a zone boundary within
/// [headroom] of it is pulled in too: the dotted line for the zone you did
/// not quite reach is information. Then a few beats of air either side, out
/// to whole multiples of a step that fits in about five rungs.
BpmScale bpmScale(List<Sample> samples, List<HeartRateZoneOut> zones, {int headroom = 12}) {
  var lo = samples.map((s) => s.$2).reduce(math.min);
  var hi = samples.map((s) => s.$2).reduce(math.max);
  for (final zone in zones) {
    final bound = zone.lowerBpm;
    if (bound != null && bound >= lo - headroom && bound <= hi + headroom) {
      lo = math.min(lo, bound);
      hi = math.max(hi, bound);
    }
  }
  lo -= 5;
  hi += 5;

  final step = _bpmSteps.firstWhere((candidate) => (hi - lo) / candidate <= 5, orElse: () => 50);
  final from = (lo / step).floor() * step;
  final to = (hi / step).ceil() * step;
  return (lo: from, hi: to, ticks: [for (var t = from; t <= to; t += step) t]);
}
