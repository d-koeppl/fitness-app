# ADR-040 — The league table, and opponents rated on points per game

**Status:** Accepted · **Date:** 2026-09-29

## Context

The app knew every match but not how strong the opponent was. The ÖFB
Tabellen page (`…/Mannschaften/Saison-<season>/KM/Tabellen`) carries the
table as JSON in a preload block (`type: "TABELLE"`), behind the same
Anubis challenge as the game pages. The Spiele page the scrape already
reads also lists the games still to play, which it used to throw away.

Two spellings get in the way: the table writes "Kirchberg/D.", the game
list and the game report "Kirchberg / D.".

## Decision

- The nightly ÖFB scrape also stores the overall table, one document per
  local day in `league_tables`, and replaces the fixtures in
  `meta/fixtures`. A failed table fetch is logged and does not fail the
  match scrape.
- Our row is recognised by the club page URL, not the name. Other teams
  are matched on `oefb.parser.team_key` (case folded, no spaces around
  `/`).
- A played match shows the opponent's rank **before kick-off**: the
  newest table from the match day or earlier (the scrape runs at 03:30,
  before any kick-off), if it is at most 21 days old. Otherwise, as for
  every match before the first stored table, it shows today's rank and
  says so (`at_kickoff: false`, "now 3rd" in the app).
- The comparison is **points per game**, not a rank ratio: 1st vs 2nd and
  7th vs 14th are the same ratio and very different games, and teams can
  be apart in games played. More than 0.5 points per game above us is
  "stronger", as far below "weaker", between "level"
  (`STRENGTH_MARGIN_PPG`). No label until both sides have played.
- `GET /league/table` serves the app's Fitness → Football segment: the
  three newest matches (expandable to all), then the table.
  `MatchOut.opponent_standing` feeds the match rows. `GET /league/fixtures`
  feeds Upcoming, where a calendar event within three hours of a
  fixture's kick-off shows the opponent's standing.
- The report context (prompt v6) and the coach, under the matches toggle,
  get the table, the next three fixtures and each recent match's
  standing. The prompt limits them to the physical side (arriving fresh
  for a hard game, reading a result in context); no tactics or score
  predictions.
- Only the overall table is read. The page's home/away and half-season
  tables are ignored.

## Consequences

- One more page fetch and two small writes a night.
- The seven league games played before this shipped show today's rank.
- The strength label is a heuristic for planning recovery. The margin is
  one constant if it needs tuning.
