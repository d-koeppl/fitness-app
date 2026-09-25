// Ported from fitness-dashboard's web/lib/heart-rate.test.ts.
import 'package:fitness/domain/heart_rate.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter_test/flutter_test.dart';

HeartRateZoneOut zone(String name, int? lower, int? upper, num seconds) =>
    HeartRateZoneOut(zone: name, lowerBpm: lower, upperBpm: upper, seconds: seconds);

/// The bands off a resting 56 and a max of 191 — the same ones the server
/// test derives, so the two ends of this feature agree on where a zone
/// starts.
final zones = [
  zone('light', null, 110, 180),
  zone('fat_burn', 110, 137, 2820),
  zone('cardio', 137, 171, 5760),
  zone('peak', 171, null, 240),
];

SessionHeartRateOut trace({List<List<Object>> samples = const [], DateTime? fetchedAt}) => SessionHeartRateOut(
  sessionId: '2026-08-20#0',
  date: DateTime(2026, 8, 20),
  startTs: DateTime.utc(2026, 8, 20, 13, 23),
  endTs: DateTime.utc(2026, 8, 20, 15, 52),
  fetchedAt: fetchedAt,
  samples: samples,
  sampleCount: samples.length,
  minBpm: null,
  maxBpm: null,
  averageBpm: null,
  zones: const [],
  zoneSource: null,
  restingHr: 56,
  maxHr: 191,
);

void main() {
  group('zoneOf', () {
    test('puts a reading exactly on a boundary in the higher zone', () {
      expect(zoneOf(60, zones), 'light');
      expect(zoneOf(109, zones), 'light');
      expect(zoneOf(110, zones), 'fat_burn');
      expect(zoneOf(137, zones), 'cardio');
      expect(zoneOf(171, zones), 'peak');
      expect(zoneOf(210, zones), 'peak');
    });

    test('has no answer when there are no zones', () {
      expect(zoneOf(150, []), isNull);
    });
  });

  group('traceSegments', () {
    test('splits the trace where the zone changes', () {
      final segments = traceSegments([(0, 95), (10, 100), (20, 140), (30, 145)], zones);
      expect(segments.map((s) => s.zone), ['light', 'cardio']);
    });

    test('shares the turning point, so the line has no gap in it', () {
      final segments = traceSegments([(0, 95), (10, 140), (20, 145)], zones);
      expect(segments[0].points, [(0, 95), (10, 140)]);
      expect(segments[1].points.first, (10, 140));
    });

    test('draws every sample, once per segment it belongs to', () {
      const samples = [(0, 95), (10, 120), (20, 175), (30, 100)];
      final drawn = traceSegments(samples, zones).expand((s) => s.points).toList();
      for (final sample in samples) {
        expect(drawn, contains(sample));
      }
    });

    test('is one uncoloured run when there are no zones to colour by', () {
      const samples = [(0, 95), (10, 175)];
      final [only] = traceSegments(samples, []);
      expect((only.zone, only.points), (null, samples));
    });

    test('has nothing to draw for an empty trace', () {
      expect(traceSegments([], zones), isEmpty);
    });
  });

  group('zoneBars', () {
    test('shares out the time the zones account for', () {
      expect(zoneBars(zones).map((b) => (b.label, b.percent)), [
        ('Light', 2),
        ('Moderate', 31),
        ('Vigorous', 64),
        ('Peak', 3),
      ]);
    });

    test('drops a zone nobody spent time in', () {
      final bars = zoneBars([...zones.take(3), zone('peak', 171, null, 0)]);
      expect(bars.map((b) => b.zone), ['light', 'fat_burn', 'cardio']);
    });

    test('has no bars at all when nothing was measured', () {
      expect(zoneBars([for (final z in zones) zone(z.zone, z.lowerBpm, z.upperBpm, 0)]), isEmpty);
      expect(zoneBars([]), isEmpty);
    });
  });

  group('fmtZoneDuration', () {
    test('counts in minutes below the hour and hours above it', () {
      expect(fmtZoneDuration(180), '3 min');
      expect(fmtZoneDuration(2820), '47 min');
      expect(fmtZoneDuration(5760), '1 h 36 min');
      expect(fmtZoneDuration(7200), '2 h');
    });

    test('rounds to the nearest minute rather than hiding a short spell', () {
      expect(fmtZoneDuration(40), '1 min');
      expect(fmtZoneDuration(20), '0 min');
    });
  });

  group('fmtOffsetClock', () {
    test('reads in the clock time the session happened at', () {
      final start = DateTime.utc(2026, 8, 20, 13, 23);
      final local = start.toLocal().add(const Duration(minutes: 1));
      expect(
        fmtOffsetClock(start, 60),
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
      );
    });

    test('says nothing when there is no start to count from', () {
      expect(fmtOffsetClock(null, 60), '');
    });
  });

  group('emptyTraceReason', () {
    test('tells a session nobody measured apart from one nobody has fetched', () {
      expect(emptyTraceReason(trace(fetchedAt: DateTime.utc(2026, 8, 21, 2))), contains('recorded no heart rate'));
      expect(emptyTraceReason(trace()), startsWith('Not synced yet'));
    });

    test('has nothing to apologise for when there is a trace', () {
      expect(
        emptyTraceReason(
          trace(
            samples: [
              [0, 95],
            ],
          ),
        ),
        isNull,
      );
    });
  });

  group('bpmScale', () {
    const samples = [(0, 95), (10, 165)];

    test('pulls in a boundary just above the highest reading, so its line is drawn', () {
      expect(bpmScale(samples, zones).hi, greaterThanOrEqualTo(171));
    });

    test('leaves a boundary far out of reach alone rather than squashing the trace', () {
      expect(bpmScale(samples, [zone('peak', 250, null, 0)]).hi, lessThan(200));
    });

    test('keeps the axis around the readings rather than around zero', () {
      final scale = bpmScale([(0, 86), (10, 194)], zones);
      expect(scale.lo, inInclusiveRange(50, 81));
      expect(scale.hi, greaterThanOrEqualTo(199));
      expect(scale.ticks.length, lessThanOrEqualTo(6));
    });

    test('spaces the rungs evenly and covers the whole range', () {
      final scale = bpmScale(samples, zones);
      final steps = {for (var i = 1; i < scale.ticks.length; i++) scale.ticks[i] - scale.ticks[i - 1]};
      expect(scale.ticks.first, scale.lo);
      expect(scale.ticks.last, scale.hi);
      expect(steps, hasLength(1));
    });

    test('still has a band to draw in for a flat trace', () {
      final scale = bpmScale([(0, 120)], []);
      expect(scale.hi, greaterThan(scale.lo));
      expect(scale.lo, lessThanOrEqualTo(120));
      expect(scale.hi, greaterThanOrEqualTo(120));
    });
  });
}
