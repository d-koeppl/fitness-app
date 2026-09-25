// Ported from fitness-dashboard's web/lib/series.test.ts.
import 'package:fitness/domain/series.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Friday, so the week/month boundaries in these tests are not the same day.
final today = DateTime(2026, 8, 21);

SeriesPoint hr(String date, [num? value]) {
  final [y, m, d] = date.split('-').map(int.parse).toList();
  return (date: DateTime(y, m, d), value: value);
}

List<Bucket> empty(Period period) => bucketSeries(const [], period, today);

void main() {
  group('startOfWeek', () {
    test('goes back to Monday', () {
      expect(startOfWeek(DateTime(2026, 8, 21)).day, 17);
      expect(startOfWeek(DateTime(2026, 8, 17)).day, 17);
    });

    test('treats Sunday as the end of its week, not the start', () {
      expect(startOfWeek(DateTime(2026, 8, 23)).day, 17);
    });
  });

  group('daysBetween', () {
    test('counts whole days across a month boundary', () {
      expect(daysBetween(DateTime(2026, 7, 30), DateTime(2026, 8, 2)), 3);
    });
  });

  group('bucketWindow', () {
    test('gives 7 daily buckets ending today for a week', () {
      final window = bucketWindow(Period.week, today);
      expect(window, hasLength(7));
      expect(window[0].start.day, 15);
      expect(window[6].start.day, 21);
      expect(window[6].end.day, 21);
    });

    test('gives 30 daily buckets for a month', () {
      expect(bucketWindow(Period.month, today), hasLength(30));
    });

    test('gives 13 Monday-to-Sunday weeks for a quarter', () {
      final window = bucketWindow(Period.quarter, today);
      expect(window, hasLength(13));
      expect(window[12].start.day, 17);
      expect(window[12].end.day, 23);
      expect(window[0].start.weekday, DateTime.monday);
    });

    test('gives 12 calendar months for a year, ending with this one', () {
      final window = bucketWindow(Period.year, today);
      expect(window, hasLength(12));
      expect(window[11].start.month, 8);
      expect(window[11].end.day, 31);
      expect(window[0].start.month, 9);
      expect(window[0].start.year, 2025);
    });
  });

  group('bucketSeries', () {
    test('puts each day in its own bucket for a week', () {
      final buckets = bucketSeries([hr('2026-08-21', 54)], Period.week, today);
      expect(buckets.last.value, 54);
      expect(buckets.last.days, 1);
    });

    test('averages the days inside a weekly bucket', () {
      final buckets = bucketSeries(
        [hr('2026-08-17', 50), hr('2026-08-18', 54), hr('2026-08-19', 55)],
        Period.quarter,
        today,
      );
      expect(buckets.last.value, 53);
      expect(buckets.last.days, 3);
    });

    test('averages the days inside a monthly bucket', () {
      expect(bucketSeries([hr('2026-08-01', 60), hr('2026-08-31', 50)], Period.year, today).last.value, 55);
    });

    test('leaves a day with no reading out of the average rather than counting it as zero', () {
      final bucket = bucketSeries(
        [hr('2026-08-17', 50), hr('2026-08-18'), hr('2026-08-19', 60)],
        Period.quarter,
        today,
      ).last;
      expect(bucket.value, 55);
      expect(bucket.days, 2);
    });

    test('reports an empty bucket as null rather than dropping it', () {
      final buckets = bucketSeries([hr('2026-08-21', 54)], Period.week, today);
      expect(buckets, hasLength(7));
      expect(buckets.take(6).every((b) => b.value == null), isTrue);
    });

    test('ignores rows outside the window', () {
      final buckets = bucketSeries([hr('2020-01-01', 99), hr('2026-08-21', 54)], Period.week, today);
      expect(buckets.where((b) => b.value != null), hasLength(1));
    });

    test('ignores the time of day on today', () {
      expect(bucketSeries(const [], Period.week, DateTime(2026, 8, 21, 23, 30)).last.key, '2026-08-21');
    });
  });

  group('seriesAverage', () {
    test('weights each bucket by the days behind it', () {
      final rows = [hr('2026-08-17', 60), hr('2026-08-18', 60), hr('2026-08-19', 60), hr('2026-08-10', 40)];
      // Unweighted this would be (60 + 40) / 2 = 50; weighted it is the mean
      // of the four days themselves.
      expect(seriesAverage(bucketSeries(rows, Period.quarter, today)), 55);
    });

    test('is null when nothing was recorded', () {
      expect(seriesAverage(empty(Period.week)), isNull);
    });
  });

  group('latestBucket', () {
    test('skips trailing empty buckets', () {
      expect(latestBucket(bucketSeries([hr('2026-08-18', 56)], Period.week, today))?.value, 56);
    });

    test('is null for an empty series', () {
      expect(latestBucket(empty(Period.week)), isNull);
    });
  });

  group('tickLabels', () {
    test('labels every day of the week', () {
      final labels = tickLabels(empty(Period.week), Period.week);
      expect(labels, hasLength(7));
      expect(labels.every((l) => l != null), isTrue);
    });

    test('thins the month down to every fifth day, always labelling the newest', () {
      final labels = tickLabels(empty(Period.month), Period.month);
      expect(labels.last, '21');
      expect(labels.whereType<String>(), hasLength(6));
    });

    test('labels every other week over a quarter', () {
      final labels = tickLabels(empty(Period.quarter), Period.quarter);
      expect(labels.whereType<String>(), hasLength(7));
      expect(labels.last, '17 Aug');
    });

    test('labels all twelve months of a year', () {
      expect(tickLabels(empty(Period.year), Period.year).whereType<String>(), hasLength(12));
    });
  });

  group('bucketLabel', () {
    test('names the two most recent days', () {
      final week = empty(Period.week);
      expect(bucketLabel(week[6], Aggregate.daily, today), 'Today');
      expect(bucketLabel(week[5], Aggregate.daily, today), 'Yesterday');
      expect(bucketLabel(week[4], Aggregate.daily, today), 'Wed 19 Aug');
    });

    test('gives a week its day range, dropping the repeated month', () {
      expect(bucketLabel(empty(Period.quarter)[12], Aggregate.weekly, today), '17 – 23 Aug');
    });

    test('keeps both months when a week straddles them', () {
      final straddling = empty(Period.quarter).firstWhere((b) => b.start.month != b.end.month);
      expect(bucketLabel(straddling, Aggregate.weekly, today), matches(RegExp(r'^\d+ \w+ – \d+ \w+$')));
    });

    test('names a month with its year', () {
      expect(bucketLabel(empty(Period.year)[11], Aggregate.monthly, today), 'August 2026');
    });
  });

  group('windowLabel', () {
    test("spans the first bucket's start to the last one's end", () {
      expect(windowLabel(empty(Period.week)), '15 Aug – 21 Aug 2026');
    });

    test('adds the year to both ends when the window crosses one', () {
      expect(windowLabel(empty(Period.year)), '1 Sept 2025 – 31 Aug 2026');
    });
  });

  group('niceScale', () {
    test('rounds the domain out to readable ticks', () {
      final scale = niceScale([53, 54, 55, 56]);
      expect(scale.ticks.every((t) => t == t.roundToDouble()), isTrue);
      expect(scale.lo, lessThanOrEqualTo(53));
      expect(scale.hi, greaterThanOrEqualTo(56));
    });

    test("starts bars at zero, so a bar's length is its value", () {
      expect(niceScale([8000, 12000], zeroBased: true).lo, 0);
    });

    test('does not start a line at zero — it plots a level, not a magnitude', () {
      expect(niceScale([53, 56]).lo, greaterThan(0));
    });

    test('keeps every value inside the domain', () {
      for (final values in [
        [53, 56],
        [0.4, 9.9],
        [8000, 12345],
        [72.1, 75.8],
        [1],
        [-3, 4],
      ]) {
        final scale = niceScale(values);
        for (final v in values) {
          expect(v, inInclusiveRange(scale.lo, scale.hi));
        }
      }
    });

    test('gives a flat series a band to sit in rather than dividing by zero', () {
      final scale = niceScale([55, 55, 55]);
      expect(scale.hi, greaterThan(scale.lo));
    });

    test('survives an all-zero series', () {
      final scale = niceScale([0, 0], zeroBased: true);
      expect(scale.hi, greaterThan(scale.lo));
    });

    test('has a usable domain when there is no data at all', () {
      final scale = niceScale([]);
      expect(scale.hi, greaterThan(scale.lo));
      expect(scale.ticks.length, greaterThan(1));
    });

    test('does not leak floating-point noise into the tick labels', () {
      for (final tick in niceScale([0.1, 0.9]).ticks) {
        expect('$tick', isNot(matches(RegExp(r'\d{6,}'))));
      }
    });

    test("only ever steps by a whole multiple of the label's resolution", () {
      for (final values in [
        [79.9, 80.7],
        [80.3, 80.4],
        [72.1, 75.8],
      ]) {
        final ticks = niceScale(values, minStep: 0.1).ticks;
        final ratio = (ticks[1] - ticks[0]) / 0.1;
        expect(ratio, closeTo(ratio.round(), 1e-6));
        expect(ticks.map((t) => t.toStringAsFixed(1)).toSet(), hasLength(ticks.length));
      }
    });

    test("never picks a step finer than the metric's own resolution", () {
      final ticks = niceScale([80.3, 80.4], minStep: 0.1).ticks;
      expect(ticks[1], closeTo(ticks[0] + 0.1, 1e-6));
    });

    test('still uses the 2.5 rung where the labels can carry it', () {
      final ticks = niceScale([55, 73.3, 86.75, 110.7], minStep: 1).ticks;
      expect(ticks[1] - ticks[0], 25);
      expect(ticks[0], greaterThan(0));
    });

    test('does not strand the data in the bottom half of the plot', () {
      for (final values in [
        [55, 110.7],
        [52, 59],
        [72.1, 75.8],
      ]) {
        final scale = niceScale(values, minStep: 1);
        final dataSpan = values.last - values.first;
        expect(scale.hi - scale.lo, lessThanOrEqualTo(dataSpan * 2.5 + 2));
      }
    });

    test('honours a pinned domain instead of fitting the data', () {
      final scale = niceScale([80, 88, 95], minStep: 1, domain: (0, 100), targetTicks: 5);
      expect((scale.lo, scale.hi), (0, 100));
      expect(scale.ticks, [0, 25, 50, 75, 100]);
    });

    test('pins the domain even when there is no data at all', () {
      expect(niceScale([], domain: (0, 100), targetTicks: 5).ticks, [0, 25, 50, 75, 100]);
    });

    test('steps evenly', () {
      final ticks = niceScale([12, 87]).ticks;
      final step = ticks[1] - ticks[0];
      for (final (i, t) in ticks.indexed) {
        expect(t, closeTo(ticks[0] + i * step, 1e-6));
      }
    });
  });
}
