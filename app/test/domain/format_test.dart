// Ported from fitness-dashboard's web/lib/format.test.ts, case for case.
import 'package:fitness/domain/format.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter_test/flutter_test.dart';

MatchOut match({String homeAway = 'home', String? result = '4:3', int id = 1}) => MatchOut(
      goals: 0,
      homeAway: homeAway,
      id: id,
      matchDate: DateTime(2026, 8, 8),
      minutesPlayed: 90,
      oefbGameId: '1',
      opponent: 'Treffling',
      redCard: false,
      result: result,
      started: true,
      yellowCard: false,
    );

AiReportOut report({String summaryMd = 'Body text.', Map<String, Object> insights = const {}}) => AiReportOut(
      createdAt: DateTime.utc(2026, 8, 19, 7),
      id: 1,
      insights: insights,
      model: 'gemini-3-flash-preview',
      periodEnd: null,
      periodStart: null,
      promptVersion: 'v1',
      summaryMd: summaryMd,
      tokensUsed: null,
      trigger: 'wake',
    );

ExerciseSessionOut exercise({
  String? exerciseType = 'RUNNING',
  num? activeZoneMinutes = 34,
  num? estimatedLoad,
  String source = 'tracked',
  String? title,
}) =>
    ExerciseSessionOut(
      activeZoneMinutes: activeZoneMinutes,
      averageHeartRate: 150,
      date: DateTime(2026, 8, 20),
      durationMinutes: 65,
      endTs: DateTime.parse('2026-08-20T18:05:00+02:00'),
      estimatedLoad: estimatedLoad,
      exerciseType: exerciseType,
      id: '2026-08-20#0',
      metrics: const {},
      refId: null,
      skipped: false,
      source_: source,
      startTs: DateTime.parse('2026-08-20T17:00:00+02:00'),
      title: title,
    );

void main() {
  group('fmtSleep', () {
    for (final (minutes, expected) in [(418, '6 h 58 m'), (480, '8 h 0 m'), (59, '0 h 59 m'), (0, '0 h 0 m')]) {
      test('formats $minutes minutes', () => expect(fmtSleep(minutes), expected));
    }

    test('shows a dash rather than 0h for missing data', () {
      expect(fmtSleep(null), '—');
      expect(fmtSleepCompact(null), '—');
    });

    test('zero-pads the compact form so tiles do not jitter', () {
      expect(fmtSleepCompact(389), '6h29');
      expect(fmtSleepCompact(365), '6h05');
    });
  });

  group('withDelta', () {
    test('marks a rise and a fall', () {
      expect(withDelta('Resting HR', 56, 54), 'Resting HR · ↑2');
      expect(withDelta('Resting HR', 54, 56), 'Resting HR · ↓2');
    });

    test('calls a sub-unit move flat rather than rounding it to ↑0', () {
      expect(withDelta('Resting HR', 54.2, 54), 'Resting HR · flat');
    });

    test('respects the requested precision', () {
      expect(withDelta('Weight', 80.4, 80.0, digits: 1), 'Weight · ↑0.4');
      expect(withDelta('Weight', 80.02, 80.0, digits: 1), 'Weight · flat');
    });

    test('falls back to the bare name when either side is missing', () {
      expect(withDelta('Resting HR', null, 54), 'Resting HR');
      expect(withDelta('Resting HR', 54, null), 'Resting HR');
    });
  });

  group('currentReading', () {
    final saturday = MeasurementOut(value: 79.2, date: DateTime(2026, 8, 29));

    test("prefers today's own reading and does not call it carried", () {
      expect(currentReading(78.8, DateTime(2026, 8, 31), saturday),
          Reading(value: 78.8, date: DateTime(2026, 8, 31), carried: false));
    });

    test('reaches back to the last reading on a day nothing was measured', () {
      expect(currentReading(null, DateTime(2026, 8, 31), saturday),
          Reading(value: 79.2, date: DateTime(2026, 8, 29), carried: true));
    });

    test('is null only when the metric has never been recorded', () {
      expect(currentReading(null, DateTime(2026, 8, 31), null), isNull);
      expect(currentReading(null, null, null), isNull);
    });

    test('carries a zero forward rather than treating it as no reading', () {
      expect(currentReading(0, DateTime(2026, 8, 31), saturday)?.value, 0);
    });
  });

  group('withMeasuredOn', () {
    test('names the day the carried-forward reading came from', () {
      expect(withMeasuredOn('Weight', DateTime(2026, 8, 29)), 'Weight · 29 Aug');
      expect(withMeasuredOn('Last', DateTime(2026, 7, 5)), 'Last · 5 Jul');
      expect(withMeasuredOn('Last', DateTime(2026, 9, 4)), 'Last · 4 Sept');
    });
  });

  group('average', () {
    test('ignores gaps in the data instead of counting them as zero', () {
      expect(average([10, null, 20, null]), 15);
    });

    test('returns null when there is nothing to average', () {
      expect(average([]), isNull);
      expect(average([null, null]), isNull);
    });
  });

  group('matchOutcome', () {
    test('reads our side of the scoreline at home', () {
      expect(matchOutcome(match(result: '4:3')), MatchOutcome.win);
      expect(matchOutcome(match(result: '0:2')), MatchOutcome.loss);
    });

    test('reads the other side of the same scoreline away', () {
      expect(matchOutcome(match(homeAway: 'away', result: '4:3')), MatchOutcome.loss);
      expect(matchOutcome(match(homeAway: 'away', result: '0:2')), MatchOutcome.win);
    });

    test('recognizes a draw either way round', () {
      expect(matchOutcome(match(result: '2:2')), MatchOutcome.draw);
      expect(matchOutcome(match(homeAway: 'away', result: '2:2')), MatchOutcome.draw);
    });

    test('returns ? for a game with no or unreadable result', () {
      expect(matchOutcome(match(result: null)), MatchOutcome.unknown);
      expect(matchOutcome(match(result: 'abandoned')), MatchOutcome.unknown);
    });
  });

  group('seasonForm', () {
    test('counts each outcome', () {
      final matches = [
        match(id: 1, result: '4:3'),
        match(id: 2, result: '2:2'),
        match(id: 3, result: '0:1'),
        match(id: 4, result: '3:0'),
      ];
      expect(seasonForm(matches), '2W 1D 1L');
    });

    test('shows a dash when there are no matches', () {
      expect(seasonForm([]), '—');
    });
  });

  group('splitReport', () {
    test('lifts a leading markdown heading out of the body', () {
      final (:headline, :body) = splitReport(report(summaryMd: '## **Strong recovery**\n\nYour HRV is up.'));
      expect(headline, 'Strong recovery');
      expect(body, 'Your HRV is up.');
    });

    test('falls back to the readiness reason when the model wrote no heading', () {
      final (:headline, :body) = splitReport(
        report(summaryMd: 'Your HRV is up.', insights: {'readiness_reason': 'RHR at a two-week low'}),
      );
      expect(headline, 'RHR at a two-week low');
      expect(body, 'Your HRV is up.');
    });

    test('falls back to the readiness word, capitalized', () {
      expect(splitReport(report(insights: {'readiness': 'high'})).headline, 'High readiness today');
    });

    test('always produces some headline', () {
      expect(splitReport(report()).headline, "Today's readiness");
    });
  });

  group('fmtEventWhen', () {
    CalendarEventOut event({bool allDay = false, DateTime? start}) => CalendarEventOut(
          allDay: allDay,
          endTs: null,
          id: '1',
          location: null,
          startTs: start,
          title: 'Training',
        );
    final start = DateTime.parse('2026-08-20T19:00:00+02:00');

    test('omits the time for an all-day event', () {
      expect(fmtEventWhen(event(allDay: true, start: start)), isNot(contains('·')));
    });

    test('includes a time for a timed event', () {
      expect(fmtEventWhen(event(start: start)), contains('·'));
    });

    test('handles an event with no start', () {
      expect(fmtEventWhen(event()), 'TBD');
    });
  });

  group('fmtDate and fmtTime', () {
    test('write the day as en-GB does, September included', () {
      expect(fmtDate(DateTime(2026, 9, 4)), 'Fri 04 Sept');
      expect(fmtDate(null), 'TBD');
    });

    test('write the clock time with two-digit hours', () {
      expect(fmtTime(DateTime(2026, 9, 4, 7, 5)), '07:05');
      expect(fmtDateTime(DateTime(2026, 9, 24, 7, 52)), 'Thu 24 Sept, 07:52');
    });
  });

  group('fmtDuration', () {
    test('stays in minutes under the hour', () {
      expect(fmtDuration(48), '48 min');
      expect(fmtDuration(59.4), '59 min');
    });

    test('rounds before it decides, so 59.6 minutes is an hour', () {
      expect(fmtDuration(59.6), '1 h 00 m');
    });

    test('switches to hours and pads the minutes', () {
      expect(fmtDuration(65), '1 h 05 m');
      expect(fmtDuration(150), '2 h 30 m');
    });

    test('has nothing to say about a session with no interval', () {
      expect(fmtDuration(null), '—');
    });
  });

  group('exerciseLabel', () {
    test("makes Google's enum readable", () {
      expect(exerciseLabel('RUNNING'), 'Running');
      expect(exerciseLabel('STRENGTH_TRAINING'), 'Strength training');
    });

    test('falls back for a missing or non-name type', () {
      expect(exerciseLabel('41'), 'Workout');
      expect(exerciseLabel(null), 'Workout');
      expect(exerciseLabel('  '), 'Workout');
    });
  });

  group('fmtSessionMetric', () {
    test('reads the units the real payload uses', () {
      expect(fmtSessionMetric('caloriesKcal', 874), (label: 'Calories', value: '874 kcal'));
      expect(fmtSessionMetric('distanceMillimeters', 7127000), (label: 'Distance', value: '7.13 km'));
      expect(fmtSessionMetric('averagePaceSecondsPerMeter', 0.7286734611989407),
          (label: 'Average pace', value: '12:09 min/km'));
    });

    test('shows a bare number for a name carrying no unit', () {
      expect(fmtSessionMetric('steps', 8165), (label: 'Steps', value: '8,165'));
      expect(fmtSessionMetric('totalSwimLengths', 3), (label: 'Total swim lengths', value: '3'));
      expect(fmtSessionMetric('intensity', 2.5), (label: 'Intensity', value: '2.5'));
    });

    test('scales a length to whichever unit reads', () {
      expect(fmtSessionMetric('distanceMeters', 840), (label: 'Distance', value: '840 m'));
      expect(fmtSessionMetric('distanceMeters', 8412), (label: 'Distance', value: '8.41 km'));
    });

    test('prefers the longer suffix where two would match', () {
      expect(fmtSessionMetric('climbMillimeters', 1500), (label: 'Climb', value: '1.5 m'));
      expect(fmtSessionMetric('climbKilometers', 1.5), (label: 'Climb', value: '1.50 km'));
    });

    test('keeps a plain unit suffix as a unit', () {
      expect(fmtSessionMetric('averageHeartRateBeatsPerMinute', 137),
          (label: 'Average heart rate', value: '137 bpm'));
    });
  });

  group('sessionTitle', () {
    test('prettifies the activity type of a tracked session', () {
      expect(sessionTitle(exercise(exerciseType: 'STRENGTH_TRAINING')), 'Strength training');
    });

    test("prefers the schedule's own name when there is one", () {
      expect(sessionTitle(exercise(source: 'match', exerciseType: null, title: 'vs Treffling')), 'vs Treffling');
    });

    test('falls back to the activity label when the title is blank', () {
      expect(sessionTitle(exercise(title: '   ')), 'Running');
    });
  });

  group('sessionLoad', () {
    test("reads a tracked session's measured Active Zone Minutes", () {
      expect(sessionLoad(exercise()), (azm: 34, estimated: false));
    });

    test("reads an untracked session's estimate, and says that it is one", () {
      expect(sessionLoad(exercise(source: 'match', activeZoneMinutes: null, estimatedLoad: 224.1)),
          (azm: 224.1, estimated: true));
    });

    test('never calls a measured zero an estimate', () {
      expect(sessionLoad(exercise(activeZoneMinutes: 0, estimatedLoad: 99)), (azm: 0, estimated: false));
    });

    test('reports nothing when neither exists', () {
      expect(sessionLoad(exercise(activeZoneMinutes: null)), (azm: null, estimated: false));
    });
  });

  group('fmtSessionLoad', () {
    test('marks an estimate with a tilde so it cannot read as a measurement', () {
      expect(fmtSessionLoad(exercise()), '34 AZM');
      expect(fmtSessionLoad(exercise(source: 'match', activeZoneMinutes: null, estimatedLoad: 224.1)), '≈224 AZM');
    });

    test('shows a dash when there is no number at all', () {
      expect(fmtSessionLoad(exercise(activeZoneMinutes: null)), '—');
    });
  });

  group('fmtDrinkVolume', () {
    test('says what the count comes to', () => expect(fmtDrinkVolume(3, 0.5), '1.5 L'));
    test('does not write a round total as 2.0 L', () => expect(fmtDrinkVolume(4, 0.5), '2 L'));
    test('reads the size off the server rather than assuming a half litre',
        () => expect(fmtDrinkVolume(2, 0.33), '0.7 L'));
    test('handles an empty counter', () => expect(fmtDrinkVolume(0, 0.5), '0 L'));
  });

  group('jsRound and fmtInt', () {
    test('round halves up, as JavaScript does', () {
      expect(jsRound(2.5), 3);
      expect(jsRound(-2.5), -2);
      expect(jsRound(-2.6), -3);
    });

    test('group thousands the en-GB way', () {
      expect(fmtInt(12480), '12,480');
      expect(fmtInt(746), '746');
      expect(fmtInt(1000000), '1,000,000');
    });
  });
}
