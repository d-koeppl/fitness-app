import 'package:fitness/domain/league.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter_test/flutter_test.dart';

OpponentStandingOut standing({int rank = 3, int points = 15, int? gap = 4, String? strength = 'stronger'}) =>
    OpponentStandingOut(
      atKickoff: true,
      goalDifference: 18,
      ourPoints: 11,
      ourPointsPerGame: 1.57,
      ourRank: 8,
      played: 7,
      points: points,
      pointsGap: gap,
      pointsPerGame: 2.14,
      rank: rank,
      rankChange: -2,
      strength: strength,
      tableDay: DateTime(2026, 9, 29),
    );

FixtureOut fixture(DateTime? kickoff, {String homeAway = 'home'}) => FixtureOut(
  art: 'Liga',
  homeAway: homeAway,
  kickoff: kickoff,
  oefbGameId: '4120031',
  opponent: 'Urfahr',
  opponentStanding: null,
);

CalendarEventOut event(DateTime? start, {bool allDay = false}) => CalendarEventOut(
  allDay: allDay,
  endTs: null,
  id: '1',
  location: null,
  startTs: start,
  title: 'Spiel: Eidenberg - Urfahr',
);

void main() {
  test('ordinals read as en-GB writes them', () {
    expect([1, 2, 3, 4, 11, 12, 13, 14, 21, 22, 23, 101, 111].map(fmtOrdinal), [
      '1st',
      '2nd',
      '3rd',
      '4th',
      '11th',
      '12th',
      '13th',
      '14th',
      '21st',
      '22nd',
      '23rd',
      '101st',
      '111th',
    ]);
  });

  test('a standing reads as rank and points', () {
    expect(fmtStanding(standing()), '3rd · 15 pts');
    expect(fmtStanding(standing(rank: 1, points: 1)), '1st · 1 pt');
  });

  test('the points gap says which side is ahead', () {
    expect(fmtPointsGap(4), '4 pts ahead of us');
    expect(fmtPointsGap(-1), '1 pt behind us');
    expect(fmtPointsGap(0), 'level on points');
    expect(fmtPointsGap(null), isNull);
  });

  test('strength labels, and none before anyone has played', () {
    expect(strengthLabel('stronger'), 'Stronger');
    expect(strengthLabel('level'), 'Level');
    expect(strengthLabel('weaker'), 'Weaker');
    expect(strengthLabel(null), isNull);
  });

  test('rank change and goal difference as the ÖFB table shows them', () {
    expect([2, -1, 0].map(fmtRankChange), ['▲2', '▼1', '–']);
    expect([19, -3, 0].map(fmtGoalDifference), ['+19', '-3', '0']);
  });

  group('fixtureForEvent', () {
    final kickoff = DateTime.utc(2026, 10, 3, 14);
    final fixtures = [fixture(kickoff)];

    test('pairs the event that starts near kick-off', () {
      // Meeting an hour before kick-off, in local time.
      expect(fixtureForEvent(event(DateTime.parse('2026-10-03T15:00:00+02:00')), fixtures), fixtures.first);
    });

    test('leaves out a training the same day and all-day events', () {
      expect(fixtureForEvent(event(DateTime.utc(2026, 10, 3, 7)), fixtures), isNull);
      expect(fixtureForEvent(event(kickoff, allDay: true), fixtures), isNull);
      expect(fixtureForEvent(event(null), fixtures), isNull);
    });
  });
}
