// The coach's charts (ADR-035): a fenced ```chart block holding one JSON
// object, which the app draws with fl_chart. It replaces the web app's
// Mermaid diagrams, which had no renderer outside a browser.
//
//   {"type": "line" | "bar" | "pie", "title": "...", "unit": "...",
//    "x": [labels], "series": [{"name": "...", "values": [number | null]}]}
//
// The model writes this freehand, so parsing is strict and says why it
// refused: a chart that cannot be drawn honestly is shown as its source
// with the reason, the same fallback the web gave a Mermaid syntax error.
// The limits are the prompt's own (functions/api/analysis/coach.py).

import 'dart:convert';

enum CoachChartType { line, bar, pie }

class CoachChartSeries {
  const CoachChartSeries(this.name, this.values);

  final String name;

  /// One per label; null where there is no value (a gap, never a zero).
  final List<double?> values;
}

class CoachChart {
  const CoachChart({required this.type, required this.labels, required this.series, this.title, this.unit});

  final CoachChartType type;
  final String? title;
  final String? unit;
  final List<String> labels;
  final List<CoachChartSeries> series;
}

/// Either a chart, or why the source could not be drawn.
typedef CoachChartResult = ({CoachChart? chart, String? error});

const coachChartMaxLabels = 60;
const coachChartMaxSeries = 4;

CoachChartResult parseCoachChart(String source) {
  CoachChartResult fail(String why) => (chart: null, error: why);

  final Object? json;
  try {
    json = jsonDecode(source);
  } on FormatException {
    return fail('Not valid JSON');
  }
  if (json is! Map<String, dynamic>) return fail('Expected one JSON object');

  final type = switch (json['type']) {
    'line' => CoachChartType.line,
    'bar' => CoachChartType.bar,
    'pie' => CoachChartType.pie,
    _ => null,
  };
  if (type == null) return fail('Unknown chart type ${jsonEncode(json['type'])}');

  final x = json['x'];
  if (x is! List || x.isEmpty) return fail('No labels in "x"');
  if (x.length > coachChartMaxLabels) return fail('More than $coachChartMaxLabels labels');
  final labels = [for (final label in x) label is String ? label : jsonEncode(label)];

  final rawSeries = json['series'];
  if (rawSeries is! List || rawSeries.isEmpty) return fail('No series');
  if (rawSeries.length > coachChartMaxSeries) return fail('More than $coachChartMaxSeries series');
  if (type == CoachChartType.pie && rawSeries.length != 1) return fail('A pie chart has exactly one series');

  final series = <CoachChartSeries>[];
  for (final (i, entry) in rawSeries.indexed) {
    if (entry is! Map<String, dynamic>) return fail('Series ${i + 1} is not an object');
    final values = entry['values'];
    if (values is! List) return fail('Series ${i + 1} has no values');
    if (values.length != labels.length) {
      return fail('Series ${i + 1} has ${values.length} values for ${labels.length} labels');
    }
    final numbers = <double?>[];
    for (final value in values) {
      if (value == null) {
        numbers.add(null);
      } else if (value is num && value.isFinite) {
        numbers.add(value.toDouble());
      } else {
        return fail('Series ${i + 1} holds ${jsonEncode(value)}, not a number');
      }
    }
    if (numbers.every((v) => v == null)) return fail('Series ${i + 1} has no values');
    if (type == CoachChartType.pie && numbers.any((v) => v != null && v < 0)) {
      return fail('A pie chart cannot hold a negative share');
    }
    final name = entry['name'];
    series.add(CoachChartSeries(name is String && name.trim().isNotEmpty ? name.trim() : 'Series ${i + 1}', numbers));
  }

  String? text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;
  return (
    chart: CoachChart(type: type, title: text(json['title']), unit: text(json['unit']), labels: labels, series: series),
    error: null,
  );
}
