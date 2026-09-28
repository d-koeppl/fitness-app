// Ported from fitness-dashboard's web/lib/key-metrics.test.ts.
import 'package:fitness/domain/key_metrics.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter_test/flutter_test.dart';

DayPointOut day(num fitness, num fatigue) => DayPointOut(date: '2026-08-22', load: 0, fitness: fitness, fatigue: fatigue);

LoadMetricDef byKey(MetricKey key) => loadMetrics.firstWhere((m) => m.key == key);

void main() {
  group('metricByKey', () {
    test('holds every metric from all three groups, under its own key', () {
      final all = <MetricDef>[...healthMetrics, ...scoreMetrics, ...loadMetrics];
      expect(metricByKey, hasLength(all.length));
      for (final metric in all) {
        expect(identical(metricByKey[metric.key], metric), isTrue);
      }
    });
  });

  group('form', () {
    final form = byKey(MetricKey.form);

    test('is the gap between the two averages, not a field the API sends', () {
      expect(form.pick(day(50, 58)), closeTo(-8, 1e-9));
      expect(form.pick(day(58, 50)), closeTo(8, 1e-9));
    });

    test('keeps the sign on a positive value, everywhere it is written', () {
      expect(form.format(12.4), '+12');
      expect(form.formatTick(12.4), '+12');
    });

    test('leaves the minus sign alone and writes zero bare', () {
      expect(form.format(-8.6), '-9');
      expect(form.format(0), '0');
    });

    test('writes a value that rounds to nothing as plain zero from either side', () {
      expect(form.format(0.2), '0');
      expect(form.format(-0.2), '0');
    });
  });

  group('fitness and fatigue', () {
    test('read their own field off the day series', () {
      expect(byKey(MetricKey.fitness).pick(day(50, 58)), 50);
      expect(byKey(MetricKey.fatigue).pick(day(50, 58)), 58);
    });

    test('keep one decimal, which is the resolution the training card shows', () {
      expect(byKey(MetricKey.fitness).format(50.24), '50.2');
      expect(byKey(MetricKey.fatigue).format(58), '58.0');
    });

    test('does not pin its axis', () {
      expect(byKey(MetricKey.fitness).domain, isNull);
      expect(byKey(MetricKey.fatigue).domain, isNull);
      expect(byKey(MetricKey.form).domain, isNull);
    });
  });

  group('compact axis labels', () {
    test('shorten thousands without collapsing neighbours', () {
      expect(compact(950), '950');
      expect(compact(12000), '12k');
      expect(compact(12500), '12.5k');
    });
  });
}
