// The coach's ```chart blocks (ADR-035): what draws, and why the rest does
// not. The model writes these freehand, so the refusals matter as much as
// the charts.
import 'package:fitness/domain/coach_chart.dart';
import 'package:fitness/domain/report_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCoachChart', () {
    test('reads a line chart with a gap', () {
      final result = parseCoachChart(
        '{"type": "line", "title": "Form", "unit": "AZM", "x": ["Mon", "Tue", "Wed"],'
        ' "series": [{"name": "Form", "values": [-5, null, 3.5]}]}',
      );
      final chart = result.chart!;
      expect(result.error, isNull);
      expect(chart.type, CoachChartType.line);
      expect(chart.title, 'Form');
      expect(chart.unit, 'AZM');
      expect(chart.labels, ['Mon', 'Tue', 'Wed']);
      // A missing day stays missing: drawn as a gap, never as zero.
      expect(chart.series.single.values, [-5.0, null, 3.5]);
    });

    test('reads several series of a bar chart', () {
      final chart = parseCoachChart(
        '{"type": "bar", "x": ["W1", "W2"], "series": [{"name": "Load", "values": [1, 2]},'
        ' {"name": "Target", "values": [2, 2]}]}',
      ).chart!;
      expect(chart.series.map((s) => s.name), ['Load', 'Target']);
    });

    test('names an unnamed series rather than leaving the legend blank', () {
      final chart = parseCoachChart('{"type": "bar", "x": ["a"], "series": [{"values": [1]}]}').chart!;
      expect(chart.series.single.name, 'Series 1');
    });

    for (final (why, source, error) in [
      ('not JSON', '{type: line}', 'Not valid JSON'),
      ('not an object', '[1, 2]', 'Expected one JSON object'),
      ('an unknown type', '{"type": "radar", "x": ["a"], "series": [{"values": [1]}]}', 'Unknown chart type "radar"'),
      ('no labels', '{"type": "line", "x": [], "series": [{"values": []}]}', 'No labels in "x"'),
      ('no series', '{"type": "line", "x": ["a"], "series": []}', 'No series'),
      (
        'fewer values than labels',
        '{"type": "line", "x": ["a", "b"], "series": [{"values": [1]}]}',
        'Series 1 has 1 values for 2 labels',
      ),
      (
        'a value that is not a number',
        '{"type": "line", "x": ["a"], "series": [{"values": ["12"]}]}',
        'Series 1 holds "12", not a number',
      ),
      ('only gaps', '{"type": "line", "x": ["a"], "series": [{"values": [null]}]}', 'Series 1 has no values'),
      (
        'a pie with two series',
        '{"type": "pie", "x": ["a"], "series": [{"values": [1]}, {"values": [2]}]}',
        'A pie chart has exactly one series',
      ),
      (
        'a negative share',
        '{"type": "pie", "x": ["a", "b"], "series": [{"values": [3, -1]}]}',
        'A pie chart cannot hold a negative share',
      ),
    ]) {
      test('refuses $why, and says so', () {
        final result = parseCoachChart(source);
        expect(result.chart, isNull);
        expect(result.error, error);
      });
    }

    test('refuses more labels or series than the prompt allows', () {
      final labels = List.generate(coachChartMaxLabels + 1, (i) => '"$i"').join(',');
      final values = List.filled(coachChartMaxLabels + 1, '1').join(',');
      expect(
        parseCoachChart('{"type": "line", "x": [$labels], "series": [{"values": [$values]}]}').error,
        'More than $coachChartMaxLabels labels',
      );
      final five = List.filled(coachChartMaxSeries + 1, '{"values": [1]}').join(',');
      expect(
        parseCoachChart('{"type": "bar", "x": ["a"], "series": [$five]}').error,
        'More than $coachChartMaxSeries series',
      );
    });
  });

  group('parseReportBlocks', () {
    test('a ```chart fence becomes a chart block holding its source', () {
      const source = '{"type": "bar", "x": ["a"], "series": [{"values": [1]}]}';
      expect(parseReportBlocks('Here:\n\n```chart\n$source\n```\n\nDone.'), [
        const ParagraphBlock('Here:'),
        const ChartBlock(source),
        const ParagraphBlock('Done.'),
      ]);
    });

    test('a ```mermaid fence from a web-era chat stays a Mermaid block', () {
      expect(parseReportBlocks('```mermaid\npie\n```'), [const MermaidBlock('pie')]);
    });
  });
}
