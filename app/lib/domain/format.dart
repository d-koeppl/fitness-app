// Pure display helpers, ported from fitness-dashboard's web/lib/format.ts
// with its tests (test/domain/format_test.dart). No widgets and no colours
// here (those live in lib/ui/theme/), so all of it is testable without
// rendering anything.
//
// Dates and numbers are written out by hand rather than through `intl`:
// the web app formats with the browser's en-GB locale, and hand-rolled
// English is what reproduces it exactly ("Sept", not "Sep") without
// loading locale data at startup.

import 'package:fitness_api/fitness_api.dart';

/// Daily step target the steps tile fills against.
const int stepGoal = 10000;

const String dash = '—';

const weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysNarrow = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
// en-GB's short month names. September is "Sept" there, unlike en-US.
const monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];

/// JavaScript's Math.round: halves go up, towards +∞. Dart's `round()`
/// takes them away from zero, so -2.5 would become -3 where the web shows -2.
int jsRound(num value) => (value + 0.5).floor();

String _two(int n) => n.toString().padLeft(2, '0');

/// A date-only value from the API ("2026-09-25") as a local calendar day.
/// The generated client parses those into local midnight already; this is
/// for the few fields the schema types as plain strings.
DateTime parseDay(String iso) {
  final parts = iso.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

/// A timestamp from the API, in the device's zone.
DateTime local(DateTime value) => value.isUtc ? value.toLocal() : value;

/// "Thu 04 Sept" — the list rows' date.
String fmtDate(DateTime? value) {
  if (value == null) return 'TBD';
  final d = local(value);
  return '${weekdaysShort[d.weekday - 1]} ${_two(d.day)} ${monthsShort[d.month - 1]}';
}

/// "07:52", the local clock time.
String fmtTime(DateTime? value) {
  if (value == null) return dash;
  final d = local(value);
  return '${_two(d.hour)}:${_two(d.minute)}';
}

/// "Thu 24 Sept, 07:52" — the report card's footer.
String fmtDateTime(DateTime value) => '${fmtDate(value)}, ${fmtTime(value)}';

/// "S", "M", … — the weekday row under a sparkline.
String weekdayNarrow(DateTime value) => _weekdaysNarrow[local(value).weekday - 1];

String fmtEventWhen(CalendarEventOut event) {
  final start = event.startTs;
  if (start == null) return 'TBD';
  final datePart = fmtDate(start);
  if (event.allDay) return datePart;
  return '$datePart · ${fmtTime(start)}';
}

String fmtSleep(num? minutes) {
  if (minutes == null) return dash;
  return '${minutes ~/ 60} h ${jsRound(minutes % 60)} m';
}

/// "6h29" — short enough for a tile's subtitle line.
String fmtSleepCompact(num? minutes) {
  if (minutes == null) return dash;
  return '${minutes ~/ 60}h${_two(jsRound(minutes % 60))}';
}

/// "12,480", as en-GB groups thousands.
String fmtInt(num value) {
  final n = jsRound(value);
  final digits = n.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '${n < 0 ? '-' : ''}$grouped';
}

/// A number with exactly [digits] decimals, thousands grouped.
String fmtNumber(num value, int digits) {
  if (digits == 0) return fmtInt(value);
  final fixed = value.abs().toStringAsFixed(digits);
  final point = fixed.indexOf('.');
  final whole = fmtInt(int.parse(fixed.substring(0, point)));
  return '${value < 0 ? '-' : ''}$whole${fixed.substring(point)}';
}

/// Tile subtitle: the metric's name plus its move since yesterday ("Resting HR · ↓2").
String withDelta(String name, num? a, num? b, {int digits = 0}) {
  if (a == null || b == null) return name;
  final d = a - b;
  if (d.abs() < (digits > 0 ? 0.05 : 0.5)) return '$name · flat';
  return '$name · ${d > 0 ? '↑' : '↓'}${d.abs().toStringAsFixed(digits)}';
}

/// What to show as the current value of a metric that is not measured every
/// day, and whether it had to reach back for it (ADR-018).
class Reading {
  const Reading({required this.value, required this.date, required this.carried});

  final num value;
  final DateTime date;

  /// A weight from three days ago is the user's weight and belongs on the
  /// tile, but showing it with no date would pass it off as this morning's.
  final bool carried;

  @override
  bool operator ==(Object other) =>
      other is Reading && other.value == value && other.date == date && other.carried == carried;

  @override
  int get hashCode => Object.hash(value, date, carried);

  @override
  String toString() => 'Reading($value, $date, carried: $carried)';
}

/// Today's own reading when there is one, otherwise the last there was.
/// Null only when the metric has never been recorded at all.
Reading? currentReading(num? todaysValue, DateTime? todaysDate, MeasurementOut? lastKnown) {
  if (todaysValue != null && todaysDate != null) {
    return Reading(value: todaysValue, date: todaysDate, carried: false);
  }
  if (lastKnown == null) return null;
  return Reading(value: lastKnown.value, date: lastKnown.date, carried: true);
}

/// Tile subtitle for a carried-forward reading: "Weight · 29 Aug".
String withMeasuredOn(String name, DateTime date) {
  final d = local(date);
  return '$name · ${d.day} ${monthsShort[d.month - 1]}';
}

/// What a beer count comes to: "1.5 L", "4 L". The size comes from the
/// server (ADR-019), and a round total is not written "2.0 L".
/// "Sat, 20 Jul 2019" — a day that could be in any year, as the beer
/// sheet's day picker confirms it.
String fmtDayFull(DateTime day) =>
    '${weekdaysShort[day.weekday - 1]}, ${day.day} ${monthsShort[day.month - 1]} ${day.year}';

String fmtDrinkVolume(int count, num volumeL) {
  final litres = count * volumeL;
  final whole = (litres - litres.roundToDouble()).abs() < 1e-9;
  return '${whole ? litres.round() : litres.toStringAsFixed(1)} L';
}

double? average(Iterable<num?> values) {
  final nums = values.whereType<num>().toList();
  if (nums.isEmpty) return null;
  return nums.reduce((a, b) => a + b) / nums.length;
}

enum MatchOutcome {
  win('W'),
  draw('D'),
  loss('L'),
  unknown('?');

  const MatchOutcome(this.letter);
  final String letter;
}

/// Win/draw/loss from our side of the scoreline. `result` is always written
/// home-goals-first, so which half is ours depends on where we played.
MatchOutcome matchOutcome(MatchOut match) {
  final result = match.result;
  if (result == null) return MatchOutcome.unknown;
  final parts = result.split(':');
  final home = parts.isNotEmpty ? int.tryParse(parts[0].trim()) : null;
  final away = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;
  if (home == null || away == null) return MatchOutcome.unknown;
  final atHome = match.homeAway == 'home';
  final our = atHome ? home : away;
  final their = atHome ? away : home;
  if (our > their) return MatchOutcome.win;
  if (our < their) return MatchOutcome.loss;
  return MatchOutcome.draw;
}

/// "2W 1D 0L", or a dash when there is nothing to summarise.
String seasonForm(List<MatchOut> matches) {
  if (matches.isEmpty) return dash;
  int count(MatchOutcome o) => matches.where((m) => matchOutcome(m) == o).length;
  return '${count(MatchOutcome.win)}W ${count(MatchOutcome.draw)}D ${count(MatchOutcome.loss)}L';
}

/// The fields of a report's `insights` the dashboard reads.
extension ReportInsights on AiReportOut {
  String? get readiness => _string('readiness');
  String? get readinessReason => _string('readiness_reason');
  List<String> get recommendations => _strings('recommendations');
  List<String> get flags => _strings('flags');

  String? _string(String key) {
    final value = insights[key];
    return value is String ? value : null;
  }

  List<String> _strings(String key) {
    final value = insights[key];
    return value is List ? value.whereType<String>().toList() : const [];
  }
}

/// Splits a leading `# heading` off the report body, if the model wrote one.
({String headline, String body}) splitReport(AiReportOut report) {
  final md = report.summaryMd.trim();
  final match = RegExp(r'^#{1,3}\s+(.+?)(?:\n|$)').firstMatch(md);
  if (match != null) {
    return (headline: match.group(1)!.replaceAll('**', ''), body: md.substring(match.end).trim());
  }

  final reason = report.readinessReason?.trim();
  if (reason != null && reason.isNotEmpty) return (headline: reason, body: md);

  final readiness = report.readiness;
  return (
    headline: readiness != null && readiness.isNotEmpty
        ? '${readiness[0].toUpperCase()}${readiness.substring(1)} readiness today'
        : "Today's readiness",
    body: md,
  );
}

// --- exercise sessions ------------------------------------------------------

/// "48 min" under the hour, "1 h 05 m" over it.
String fmtDuration(num? minutes) {
  if (minutes == null) return dash;
  final total = jsRound(minutes);
  if (total < 60) return '$total min';
  return '${total ~/ 60} h ${_two(total % 60)} m';
}

/// Google's exercise-type enum, made readable: "STRENGTH_TRAINING" →
/// "Strength training". "Workout" for anything with no letters in it.
String exerciseLabel(String? type) {
  final raw = type?.trim();
  if (raw == null || raw.isEmpty || !RegExp('[a-z]', caseSensitive: false).hasMatch(raw)) return 'Workout';
  final words = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim().toLowerCase();
  return words[0].toUpperCase() + words.substring(1);
}

/// A session's title row: the schedule's own name for a match or a training
/// block, Google's prettified activity for a tracked workout.
String sessionTitle(ExerciseSessionOut session) {
  final title = session.title?.trim();
  return title != null && title.isNotEmpty ? title : exerciseLabel(session.exerciseType);
}

/// The load a session carries, and whether anything actually measured it.
({num? azm, bool estimated}) sessionLoad(ExerciseSessionOut session) {
  final measured = session.activeZoneMinutes;
  if (measured != null) return (azm: measured, estimated: false);
  return (azm: session.estimatedLoad, estimated: session.estimatedLoad != null);
}

/// "34 AZM", or "≈224 AZM" when the number is the model's estimate.
String fmtSessionLoad(ExerciseSessionOut session) {
  final (:azm, :estimated) = sessionLoad(session);
  if (azm == null) return dash;
  return '${estimated ? '≈' : ''}${jsRound(azm)} AZM';
}

/// Units Google spells out in the field name itself, longest suffix first so
/// "...Millimeters" is never matched as "...Meters" (ADR-012).
class _MetricUnit {
  const _MetricUnit(this.suffix, {this.metres, this.unit, this.digits, this.format});

  final String suffix;
  final double? metres;
  final String? unit;
  final int? digits;
  final String Function(num value)? format;
}

final _metricUnits = <_MetricUnit>[
  _MetricUnit('SecondsPerMeter', format: (v) => _fmtPace(v * 1000)),
  const _MetricUnit('BeatsPerMinute', unit: 'bpm', digits: 0),
  const _MetricUnit('Millimeters', metres: 0.001),
  const _MetricUnit('Kilocalories', unit: 'kcal', digits: 0),
  const _MetricUnit('Kilometers', metres: 1000),
  const _MetricUnit('Percentage', unit: '%', digits: 0),
  const _MetricUnit('Milliseconds', unit: 'ms', digits: 0),
  const _MetricUnit('Kilograms', unit: 'kg', digits: 1),
  const _MetricUnit('Centimeters', metres: 0.01),
  const _MetricUnit('Percent', unit: '%', digits: 0),
  const _MetricUnit('Minutes', unit: 'min', digits: 0),
  const _MetricUnit('Seconds', unit: 's', digits: 0),
  const _MetricUnit('Meters', metres: 1),
  const _MetricUnit('Grams', unit: 'g', digits: 0),
  const _MetricUnit('Kcal', unit: 'kcal', digits: 0),
];

String _fmtDistance(num metres) {
  if (metres.abs() >= 1000) return '${fmtNumber(metres / 1000, 2)} km';
  if (metres.abs() >= 10) return '${fmtNumber(metres, 0)} m';
  return '${fmtNumber(metres, 1)} m';
}

String _fmtPace(num secondsPerKm) {
  if (!secondsPerKm.isFinite || secondsPerKm <= 0) return dash;
  final total = jsRound(secondsPerKm);
  return '${total ~/ 60}:${_two(total % 60)} min/km';
}

String _humanize(String name) {
  final spaced = name
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();
  if (spaced.isEmpty) return name;
  return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
}

/// One row of a session's open metrics bag, ready to render.
({String label, String value}) fmtSessionMetric(String name, num value) {
  _MetricUnit? match;
  for (final u in _metricUnits) {
    if (name.length > u.suffix.length && name.endsWith(u.suffix)) {
      match = u;
      break;
    }
  }
  if (match == null) return (label: _humanize(name), value: fmtNumber(value, value % 1 == 0 ? 0 : 1));

  final label = _humanize(name.substring(0, name.length - match.suffix.length));
  if (match.format != null) return (label: label, value: match.format!(value));
  if (match.metres != null) return (label: label, value: _fmtDistance(value * match.metres!));

  final text = fmtNumber(value, match.digits ?? 0);
  return (label: label, value: match.unit != null ? '$text ${match.unit}' : text);
}
