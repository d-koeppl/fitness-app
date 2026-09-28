import 'package:fitness/domain/health_chart.dart';
import 'package:fitness/domain/key_metrics.dart';
import 'package:fitness/ui/charts/health_chart.dart';
import 'package:fitness/ui/theme/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpChart(
  WidgetTester tester,
  List<HealthSeries> series, {
  HeroStyle? style,
  NormalRange? normal,
  int? active,
  ValueChanged<int?>? onActiveChange,
}) async {
  final n = series.first.values.length;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Palette.light, Brightness.light),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: HealthChart(
            series: series,
            style: style,
            labels: [for (var i = 0; i < n; i++) '$i'],
            formatTick: (v) => '$v',
            minStep: 1,
            normal: normal,
            active: active,
            onActiveChange: onActiveChange,
            semanticLabel: 'Chart',
          ),
        ),
      ),
    ),
  );
}

void main() {
  const blue = Color(0xFF0B57D0), orange = Color(0xFFE0821C), grey = Color(0xFF888888);

  testWidgets('draws each single-series style, with and without gaps', (tester) async {
    final values = <num?>[53, 54, null, 55, 54, 56, 55];
    for (final style in HeroStyle.values) {
      await pumpChart(
        tester,
        [HealthSeries(values: values, color: blue)],
        style: style,
        normal: const NormalRange(53, 56),
      );
      expect(tester.takeException(), isNull, reason: '$style');
    }
  });

  testWidgets('draws load bars under two lines, as the training sheet does', (tester) async {
    await pumpChart(tester, [
      const HealthSeries(values: [30, null, 45, 20, 60], color: grey, mark: ChartMark.bar),
      const HealthSeries(values: [40, 41, 42, 42, 44], color: blue),
      const HealthSeries(values: [35, 30, 45, 38, 55], color: orange),
    ], active: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draws grouped bars that dip below zero, as a coach chart can', (tester) async {
    await pumpChart(tester, [
      const HealthSeries(values: [-12, 4, 8], color: blue, mark: ChartMark.bar, smooth: false),
      const HealthSeries(values: [3, -7, null], color: orange, mark: ChartMark.bar, smooth: false),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draws nothing but the frame when there is no reading at all', (tester) async {
    await pumpChart(tester, [
      const HealthSeries(values: [null, null, null], color: blue),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap points at the slot under it, and a second tap lets go', (tester) async {
    int? active;
    Future<void> pump() => pumpChart(
      tester,
      [
        const HealthSeries(values: [1, 2, 3, 4], color: blue),
        const HealthSeries(values: [4, 3, 2, 1], color: orange),
      ],
      active: active,
      onActiveChange: (i) => active = i,
    );
    await pump();
    final chart = tester.getRect(find.byType(HealthChart));
    // Four slots over the plot, which leaves the axis gutter on the right.
    final plotWidth = chart.width - 36;
    final third = Offset(chart.left + plotWidth * 2.5 / 4, chart.center.dy);

    await tester.tapAt(third);
    expect(active, 2);
    await pump();
    await tester.tapAt(third);
    expect(active, isNull);
  });
}
