// The league table in words: ordinals, an opponent's standing next to ours,
// and which calendar event a fixture is. Pure, like format.dart; the
// comparison itself (points per game, the strength label) is worked out by
// the API (functions/api/services/league.py) and only written out here.

import 'package:fitness_api/fitness_api.dart';

import 'format.dart';

/// "1st", "2nd", "3rd", "11th", "22nd" — en-GB ordinals.
String fmtOrdinal(int n) {
  final lastTwo = n % 100;
  if (lastTwo >= 11 && lastTwo <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// "15 pts", "1 pt".
String fmtPoints(int points) => '$points pt${points == 1 ? '' : 's'}';

/// "3rd · 15 pts" — where an opponent stands.
String fmtStanding(OpponentStandingOut standing) => '${fmtOrdinal(standing.rank)} · ${fmtPoints(standing.points)}';

/// "4 pts ahead of us", "2 pts behind us", "level on points"; null when our
/// own row was not in the table.
String? fmtPointsGap(int? gap) {
  if (gap == null) return null;
  if (gap == 0) return 'level on points';
  return '${fmtPoints(gap.abs())} ${gap > 0 ? 'ahead of' : 'behind'} us';
}

/// How the opponent compares on points per game, for a chip. Null before
/// both sides have played.
String? strengthLabel(String? strength) => switch (strength) {
  'stronger' => 'Stronger',
  'level' => 'Level',
  'weaker' => 'Weaker',
  _ => null,
};

/// "▲2", "▼1", or an en dash when the rank did not move — the ÖFB table's
/// arrows.
String fmtRankChange(int change) => change > 0 ? '▲$change' : (change < 0 ? '▼${-change}' : '–');

/// "+19", "-3", "0" — goal difference as the table shows it.
String fmtGoalDifference(int value) => value > 0 ? '+$value' : '$value';

/// The fixture a calendar event is: kick-off within three hours of the
/// event's start. The calendar entry and the ÖFB schedule are typed by
/// different people, so the time is what they reliably share, not the name.
FixtureOut? fixtureForEvent(CalendarEventOut event, List<FixtureOut> fixtures) {
  final start = event.startTs;
  if (start == null || event.allDay) return null;
  for (final fixture in fixtures) {
    final kickoff = fixture.kickoff;
    if (kickoff != null && kickoff.difference(start).abs() <= const Duration(hours: 3)) return fixture;
  }
  return null;
}

/// "vs Urfahr", "@ Kleinzell" — as matchTitle writes a played match.
String fixtureTitle(FixtureOut fixture) => '${fixture.homeAway == 'home' ? 'vs' : '@'} ${fixture.opponent}';

/// "Sat 03 Oct, 16:00" — a fixture's kick-off.
String fmtKickoff(FixtureOut fixture) => fixture.kickoff == null ? 'TBD' : fmtDateTime(fixture.kickoff!);
