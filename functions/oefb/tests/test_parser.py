"""Tests for oefb/parser.py.

The site publishes its data as `SG.container.appPreloads['n']=[...]` JSON
blocks embedded in the page, so the fixtures here rebuild that structure
rather than pasting whole pages: the parser's job is to survive an
undocumented, occasionally-changing shape, and small explicit fixtures make
it obvious which field each rule depends on.

The Anubis proof-of-work path in fetch_with_anubis needs a live server and
is not covered here.
"""

from __future__ import annotations

import json
from datetime import UTC, date, datetime

import pytest

from oefb.parser import (
    _extract_preloads,
    _parse_minute,
    parse_fixtures,
    parse_game_list,
    parse_game_report,
    parse_league_table,
    team_key,
)

PLAYER = "Daniel Köppl"
OUR_TEAM = "UnionEidenbergGeng"


def page(*blocks: object) -> str:
    """Render preload blocks the way the site embeds them."""
    parts = [
        f"<script>SG.container.appPreloads['{i}']={json.dumps(block, ensure_ascii=False)}</script>"
        for i, block in enumerate(blocks)
    ]
    return "<html><body>" + "".join(parts) + "</body></html>"


def ts_ms(d: date) -> int:
    return int(datetime(d.year, d.month, d.day, 12, tzinfo=UTC).timestamp() * 1000)


# --- _extract_preloads ------------------------------------------------------


def test_extract_preloads_unwraps_a_single_element_list():
    assert _extract_preloads(page([{"type": "X"}])) == {"0": {"type": "X"}}


def test_extract_preloads_handles_braces_inside_strings():
    """The brace counter must not be fooled by JSON string content, or it
    truncates the block and the whole page silently parses as empty."""
    block = [{"name": 'a } tricky [ value "quoted"', "n": 1}]
    assert _extract_preloads(page(block))["0"]["n"] == 1


def test_extract_preloads_reads_every_block():
    assert set(_extract_preloads(page([{"a": 1}], [{"b": 2}], [{"c": 3}]))) == {"0", "1", "2"}


def test_extract_preloads_of_a_page_without_any():
    assert _extract_preloads("<html><body>nothing here</body></html>") == {}


# --- _parse_minute ----------------------------------------------------------


@pytest.mark.parametrize(
    "raw, expected",
    [("72", 72), ("90+2", 92), (45, 45), ("45+", 45), ("", 0), ("n/a", 0)],
)
def test_parse_minute(raw, expected):
    assert _parse_minute(raw) == expected


# --- parse_game_list --------------------------------------------------------


def spielplan(*spiele: dict) -> dict:
    return {"type": "SPIELPLAN_MANNSCHAFT", "spiele": list(spiele)}


def spiel(game_id="3879319", **overrides) -> dict:
    base = {
        "abgeschlossen": True,
        "abgesagt": False,
        "spielUrl": f"/UnionEidenbergGeng/Spielbericht/?:s={game_id}",
        "datum": ts_ms(date(2026, 8, 8)),
        "heimName": "Eidenberg / Geng",
        "gastName": "SK Admira Juniors",
        "toreHeim": 4,
        "toreGast": 3,
        "art": "Meisterschaft",
    }
    base.update(overrides)
    return base


def test_parse_game_list_extracts_the_game_id_from_the_url():
    games = parse_game_list(page([spielplan(spiel(game_id="123456"))]))
    assert [g["game_id"] for g in games] == ["123456"]


def test_parse_game_list_skips_unplayed_and_cancelled_games():
    html = page(
        [
            spielplan(
                spiel(game_id="1"),
                spiel(game_id="2", abgeschlossen=False),
                spiel(game_id="3", abgesagt=True),
            )
        ]
    )
    assert [g["game_id"] for g in parse_game_list(html)] == ["1"]


def test_parse_game_list_skips_a_game_with_no_id_in_its_url():
    assert parse_game_list(page([spielplan(spiel(spielUrl="/no-id-here"))])) == []


def test_parse_game_list_counts_goals_given_as_scorer_lists():
    """toreHeim is sometimes the number and sometimes a list of scorers."""
    html = page([spielplan(spiel(toreHeim=[{"name": "A"}, {"name": "B"}], toreGast=1))])
    game = parse_game_list(html)[0]
    assert game["tore_heim"] == 2
    assert game["tore_gast"] == 1


def test_parse_game_list_without_the_expected_block():
    assert parse_game_list(page([{"type": "SOMETHING_ELSE"}])) == []


# --- parse_game_report ------------------------------------------------------


def report_page(
    *,
    heimspiel=True,
    starters=None,
    bench=None,
    ticker=None,
    heim=4,
    gast=3,
    match_day=date(2026, 8, 8),
) -> str:
    starters = starters if starters is not None else [{"spielerName": PLAYER, "events": []}]
    bench = bench or []
    header = {"heimErgebnis": heim, "gastErgebnis": gast, "beginnDatumZeit": ts_ms(match_day)}
    context = {"heimspiel": heimspiel, "statistik": {}}
    lineup = {
        "heimMannschaftName": "Eidenberg / Geng" if heimspiel else "SK Admira Juniors",
        "gastMannschaftName": "SK Admira Juniors" if heimspiel else "Eidenberg / Geng",
        "heimMannschaftUrl": f"/{OUR_TEAM}/" if heimspiel else "/Other/",
        "aufstellungenHeimStart": starters if heimspiel else [],
        "aufstellungenHeimErsatz": bench if heimspiel else [],
        "aufstellungenGastStart": [] if heimspiel else starters,
        "aufstellungenGastErsatz": [] if heimspiel else bench,
    }
    blocks = [[header], [context], [lineup]]
    if ticker is not None:
        blocks.append([{"tickerEintraege": ticker}])
    return page(*blocks)


def test_starter_who_plays_the_whole_game():
    perf = parse_game_report(report_page(), PLAYER, OUR_TEAM)
    assert perf["started"] is True
    assert perf["minutes_played"] == 90
    assert perf["home_away"] == "home"
    assert perf["opponent"] == "SK Admira Juniors"
    assert perf["result"] == "4:3"
    assert perf["match_date"] == date(2026, 8, 8)


def test_away_game_reads_the_other_lineup_and_opponent():
    perf = parse_game_report(report_page(heimspiel=False), PLAYER, OUR_TEAM)
    assert perf["home_away"] == "away"
    assert perf["opponent"] == "SK Admira Juniors"


def test_result_is_always_home_goals_first():
    perf = parse_game_report(report_page(heimspiel=False, heim=1, gast=2), PLAYER, OUR_TEAM)
    assert perf["result"] == "1:2"


def test_starter_substituted_off_stops_at_that_minute():
    """In the ticker, spieler2Name is the player going OFF."""
    ticker = [{"type": "Auswechslung", "minute": "72", "spieler1Name": "Someone", "spieler2Name": PLAYER}]
    perf = parse_game_report(report_page(ticker=ticker), PLAYER, OUR_TEAM)
    assert perf["minutes_played"] == 72


def test_bench_player_coming_on_plays_the_remainder():
    """spieler1Name is the player coming ON."""
    ticker = [{"type": "Auswechslung", "minute": "60", "spieler1Name": PLAYER, "spieler2Name": "Someone"}]
    perf = parse_game_report(
        report_page(starters=[{"spielerName": "Someone", "events": []}],
                    bench=[{"spielerName": PLAYER, "events": []}],
                    ticker=ticker),
        PLAYER,
        OUR_TEAM,
    )
    assert perf["started"] is False
    assert perf["minutes_played"] == 30


def test_unused_substitute_plays_nothing():
    perf = parse_game_report(
        report_page(starters=[{"spielerName": "Someone", "events": []}],
                    bench=[{"spielerName": PLAYER, "events": []}],
                    ticker=[]),
        PLAYER,
        OUR_TEAM,
    )
    assert perf["started"] is False
    assert perf["minutes_played"] == 0


def test_stoppage_time_substitution():
    ticker = [{"type": "Auswechslung", "minute": "90+2", "spieler1Name": "Someone", "spieler2Name": PLAYER}]
    assert parse_game_report(report_page(ticker=ticker), PLAYER, OUR_TEAM)["minutes_played"] == 92


def test_goals_and_cards_come_from_the_ticker():
    ticker = [
        {"type": "Tor", "minute": "12", "spieler1Name": PLAYER},
        {"type": "Tor", "minute": "34", "spieler1Name": "Someone Else"},
        {"type": "Tor", "minute": "55", "spieler1Name": PLAYER},
        {"type": "Gelbe Karte", "minute": "70", "spieler1Name": PLAYER},
    ]
    perf = parse_game_report(report_page(ticker=ticker), PLAYER, OUR_TEAM)
    assert perf["goals"] == 2
    assert perf["yellow_card"] is True
    assert perf["red_card"] is False


@pytest.mark.parametrize("card_type", ["Rote Karte", "Gelb/Rote Karte"])
def test_both_kinds_of_dismissal_count_as_a_red(card_type):
    ticker = [{"type": card_type, "minute": "80", "spieler1Name": PLAYER}]
    assert parse_game_report(report_page(ticker=ticker), PLAYER, OUR_TEAM)["red_card"] is True


def test_goals_and_cards_fall_back_to_the_player_event_icons():
    """Older reports have no ticker at all, only icons on the player row."""
    starters = [{"spielerName": PLAYER, "events": ["tor", "tor", "gelb"]}]
    perf = parse_game_report(report_page(starters=starters), PLAYER, OUR_TEAM)
    assert perf["goals"] == 2
    assert perf["yellow_card"] is True


def test_player_not_in_the_squad_returns_none():
    starters = [{"spielerName": "Someone Else", "events": []}]
    assert parse_game_report(report_page(starters=starters), PLAYER, OUR_TEAM) is None


def test_page_without_a_lineup_block_returns_none():
    assert parse_game_report(page([{"heimErgebnis": 1, "gastErgebnis": 0}]), PLAYER, OUR_TEAM) is None


# --- team_key ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("table", "game_list"),
    [
        ("Kirchberg/D.", "Kirchberg / D."),
        ("Eidenberg/Geng", "Eidenberg / Geng"),
        ("SPG Hofkirchen/Putzleinsdorf 1b", "SPG Hofkirchen / Putzleinsdorf 1b"),
        ("Herzogsdorf - Neußerling", "Herzogsdorf  -  Neußerling"),
    ],
)
def test_team_key_joins_the_tables_spelling_to_the_game_lists(table, game_list):
    assert team_key(table) == team_key(game_list)


def test_team_key_keeps_different_teams_apart():
    assert team_key("St. Martin i.M 1b") != team_key("St. Martin i.M")


# --- parse_fixtures -----------------------------------------------------------


OURS = f"https://vereine.oefb.at/{OUR_TEAM}/News/"


def test_parse_fixtures_keeps_only_games_still_to_play():
    html = page(
        [
            spielplan(
                spiel(game_id="1", heimUrl=OURS),
                spiel(game_id="2", abgeschlossen=False, heimUrl=OURS, gastName="Urfahr", datum=1791122400000),
                spiel(game_id="3", abgeschlossen=False, heimName="Kleinzell", gastName="Eidenberg / Geng"),
                spiel(game_id="4", abgeschlossen=False, abgesagt=True),
            )
        ]
    )
    fixtures = parse_fixtures(html, OUR_TEAM)
    assert [(f["game_id"], f["opponent"], f["home_away"]) for f in fixtures] == [
        ("2", "Urfahr", "home"),
        ("3", "Kleinzell", "away"),
    ]
    assert fixtures[0]["kickoff_ms"] == 1791122400000
    assert fixtures[0]["art"] == "Meisterschaft"


def test_parse_fixtures_without_the_block():
    assert parse_fixtures(page({"type": "OTHER"}), OUR_TEAM) == []


# --- parse_league_table ---------------------------------------------------------


def eintrag(rang: int, name: str, url: str, punkte: int, tendenz: int = 0) -> dict:
    return {
        "rang": rang,
        "tendenz": tendenz,
        "mannschaftBezeichnung": name,
        "homepageUrl": url,
        "spiele": 7,
        "siege": 5,
        "unentschieden": 2,
        "niederlagen": 0,
        "toreErzielt": 25,
        "toreErhalten": 6,
        "tordifferenz": 19,
        "punkte": punkte,
    }


def table_block(**tabellen: dict) -> dict:
    return {"type": "TABELLE", "bezeichnung": "2. Nordwest", "tabellen": tabellen}


def test_parse_league_table_reads_the_overall_table():
    overall = {
        "bewerbName": "2. Nordwest",
        "eintraege": [
            eintrag(1, "Ottensheim", "https://vereine.oefb.at/TSVOttensheim/News/", 17, tendenz=1),
            eintrag(8, "Eidenberg/Geng", f"https://vereine.oefb.at/{OUR_TEAM}/News/", 11, tendenz=-2),
        ],
    }
    home_only = {"bewerbName": "2. Nordwest", "eintraege": [eintrag(1, "Kleinzell", "", 12)]}
    table = parse_league_table(page(table_block(HEIM=home_only, NORMAL=overall)), OUR_TEAM)

    assert table["league"] == "2. Nordwest"
    assert [(r["rank"], r["team"], r["is_us"], r["rank_change"]) for r in table["rows"]] == [
        (1, "Ottensheim", False, 1),
        (8, "Eidenberg/Geng", True, -2),
    ]
    first = table["rows"][0]
    assert (first["played"], first["won"], first["drawn"], first["lost"]) == (7, 5, 2, 0)
    goals = (first["goals_for"], first["goals_against"], first["goal_difference"])
    assert goals == (25, 6, 19)
    assert first["points"] == 17


def test_parse_league_table_without_one():
    assert parse_league_table(page({"type": "OTHER"}), OUR_TEAM) is None
    assert parse_league_table(page(table_block(NORMAL={"eintraege": []})), OUR_TEAM) is None
