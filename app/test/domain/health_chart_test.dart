import 'package:fitness/domain/health_chart.dart';
import 'package:fitness/domain/key_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('heroStyleFor', () {
    test('gives heart metrics the band, daily amounts bars, the rest the area line', () {
      expect(heroStyleFor(MetricKey.restingHr), HeroStyle.band);
      expect(heroStyleFor(MetricKey.hrvMs), HeroStyle.band);
      expect(heroStyleFor(MetricKey.steps), HeroStyle.bars);
      expect(heroStyleFor(MetricKey.sleepMinutes), HeroStyle.bars);
      for (final key in [
        MetricKey.weightKg,
        MetricKey.vo2max,
        MetricKey.fitness,
        MetricKey.fatigue,
        MetricKey.form,
        MetricKey.readiness,
        MetricKey.recovery,
      ]) {
        expect(heroStyleFor(key), HeroStyle.area, reason: '$key');
      }
    });
  });

  test('chartStyleFor gives a chart that is not a key metric the style of its mark', () {
    expect(chartStyleFor(beerMetric), HeroStyle.bars);
    expect(chartStyleFor(metricByKey[MetricKey.hrvMs]!), HeroStyle.band);
  });

  group('normalRange', () {
    test('is one and a half standard deviations either side of the mean', () {
      // Mean 5, standard deviation 2.
      final range = normalRange([2, 4, 4, 4, 5, 5, 7, 9])!;
      expect(range.lo, closeTo(2, 1e-9));
      expect(range.hi, closeTo(8, 1e-9));
    });

    test('ignores days without a reading', () {
      final range = normalRange([2, null, 4, 4, 4, null, 5, 5, 7, 9])!;
      expect(range.lo, closeTo(2, 1e-9));
    });

    test('is null with fewer than a week of readings', () {
      expect(normalRange([54, 55, 56, 55, 54, null, null]), isNull);
    });
  });

  test('bandStatus reads the edges as inside', () {
    const range = NormalRange(52, 56);
    expect(bandStatus(range, 51.9), BandStatus.below);
    expect(bandStatus(range, 52), BandStatus.within);
    expect(bandStatus(range, 56), BandStatus.within);
    expect(bandStatus(range, 56.1), BandStatus.above);
  });

  group('verdictFor', () {
    test('reads a resting heart rate below normal as good and above as worse', () {
      final better = betterFor(MetricKey.restingHr);
      expect(verdictFor(BandStatus.below, better), Verdict.better);
      expect(verdictFor(BandStatus.above, better), Verdict.worse);
      expect(verdictFor(BandStatus.within, better), Verdict.usual);
    });

    test('reads HRV the other way round', () {
      final better = betterFor(MetricKey.hrvMs);
      expect(verdictFor(BandStatus.above, better), Verdict.better);
      expect(verdictFor(BandStatus.below, better), Verdict.worse);
    });

    test('says the side and the reading in words', () {
      expect(bandStatusLabel(BandStatus.below, Better.lower), 'Below your normal range · good');
      expect(bandStatusLabel(BandStatus.below, Better.higher), 'Below your normal range · worse');
      expect(bandStatusLabel(BandStatus.within, Better.higher), 'Within your normal range');
    });
  });

  group('rangePosition', () {
    test('places the value and the mean between the low and the high', () {
      final pos = rangePosition([70, 80, 90, null], 80)!;
      expect(pos.low, 70);
      expect(pos.high, 90);
      expect(pos.position, closeTo(0.5, 1e-9));
      expect(pos.meanPosition, closeTo(0.5, 1e-9));
    });

    test('widens to hold a value carried from before the range', () {
      final pos = rangePosition([79, 80], 81)!;
      expect(pos.high, 81);
      expect(pos.position, 1);
    });

    test('centres a flat series', () {
      expect(rangePosition([5, 5], 5)!.position, 0.5);
    });

    test('is null without a reading or a current value', () {
      expect(rangePosition([null, null], 5), isNull);
      expect(rangePosition([1, 2], null), isNull);
    });
  });

  group('heroLabels', () {
    test('names every weekday of a week', () {
      final week = [for (var d = 22; d <= 28; d++) DateTime(2026, 9, d)];
      expect(heroLabels(week), ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon']);
    });

    test('spreads five dates over a month, ending on the newest', () {
      final month = [for (var i = 0; i < 30; i++) DateTime(2026, 8, 30 + i)];
      final labels = heroLabels(month);
      expect(labels.whereType<String>(), hasLength(5));
      expect(labels.first, '30 Aug');
      expect(labels.last, '28 Sept');
    });
  });
}
