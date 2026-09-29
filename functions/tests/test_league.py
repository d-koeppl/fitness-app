"""The league table: comparing an opponent with us, the table before
kick-off, the endpoints, and the scrape that stores it
(api/services/league.py, api/routers/league.py, oefb/scraper.py)."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime, timedelta

import pytest

from api.config import settings
from api.services.league import standing, strength, table_before
from api.store.rows import Fixture, LeagueRow, LeagueTable, MatchPerformance

OUR_TEAM = "UnionEidenbergGeng"


def row(
    rank: int, team: str, points: int, played: int = 7, *, us: bool = False, change: int = 0
) -> LeagueRow:
    return LeagueRow(rank=rank, team=team, is_us=us, rank_change=change, played=played, points=points)


def table(day: date, *rows: LeagueRow) -> LeagueTable:
    return LeagueTable(day=day, league="2. Nordwest", rows=list(rows))


# The ÖFB page on 2026-09-29, trimmed to the rows the tests read.
TODAY = table(
    date(2026, 9, 29),
    row(1, "Ottensheim", 17, change=1),
    row(3, "Sarleinsbach", 15, change=-2),
    row(8, "Eidenberg/Geng", 11, us=True, change=-2),
    row(9, "Reichenau", 10),
    row(14, "St. Martin i.M 1b", 2),
)


# --- the comparison (pure) ----------------------------------------------------


def test_strength_is_the_points_per_game_difference():
    assert strength(2.43, 1.57) == "stronger"
    assert strength(1.43, 1.57) == "level"
    assert strength(0.29, 1.57) == "weaker"
    assert strength(None, 1.57) is None
    assert strength(1.0, None) is None


def test_standing_puts_the_opponent_next_to_us():
    s = standing(TODAY, "Sarleinsbach")
    assert (s.rank, s.rank_change, s.points, s.points_per_game) == (3, -2, 15, 2.14)
    assert (s.our_rank, s.our_points, s.our_points_per_game) == (8, 11, 1.57)
    assert s.points_gap == 4
    assert s.strength == "stronger"
    assert s.table_day == date(2026, 9, 29)
    assert s.at_kickoff is False


def test_standing_finds_a_team_the_game_list_spells_differently():
    assert standing(TODAY, "St. Martin i.M 1b").strength == "weaker"
    spaced = table(date(2026, 9, 29), row(10, "Kirchberg/D.", 9), row(8, "Eidenberg/Geng", 11, us=True))
    assert standing(spaced, "Kirchberg / D.").rank == 10


def test_standing_of_a_team_outside_the_league_is_none():
    assert standing(TODAY, "Gramastetten") is None  # a friendly
    assert standing(TODAY, "Eidenberg / Geng") is None  # never ourselves


def test_standing_before_anyone_has_played_has_no_strength():
    start = table(
        date(2026, 8, 1), row(1, "Ottensheim", 0, played=0), row(2, "Eidenberg/Geng", 0, 0, us=True)
    )
    s = standing(start, "Ottensheim")
    assert s.points_per_game is None
    assert s.strength is None


def test_table_before_takes_the_match_days_own_copy():
    tables = [table(date(2026, 9, 12)), table(date(2026, 9, 19)), table(date(2026, 9, 26))]
    assert table_before(tables, date(2026, 9, 19)).day == date(2026, 9, 19)
    assert table_before(tables, date(2026, 9, 25)).day == date(2026, 9, 19)
    assert table_before(tables, date(2026, 9, 11)) is None


def test_table_before_ignores_a_copy_from_another_season():
    """A match after the summer break must not be read against the
    previous season's final table."""
    tables = [table(date(2026, 6, 1))]
    assert table_before(tables, date(2026, 6, 20)) is not None
    assert table_before(tables, date(2026, 8, 8)) is None


# --- matches and the endpoints (emulator) -------------------------------------------


def _match(game_id: str, day: date, opponent: str) -> MatchPerformance:
    return MatchPerformance(
        id=int(game_id),
        oefb_game_id=game_id,
        match_date=day,
        opponent=opponent,
        home_away="home",
        result="1:0",
    )


def test_matches_carry_the_opponents_rank_before_kick_off(api_client, store):
    store.put_league_table(
        table(date(2026, 9, 20), row(1, "Reichenau", 9, 3), row(5, "Eidenberg/Geng", 4, 3, us=True))
    )
    store.put_league_table(TODAY)
    store.put_match(_match("1", date(2026, 9, 21), "Reichenau"))  # after the first copy
    store.put_match(_match("2", date(2026, 8, 30), "Ottensheim"))  # before every copy
    store.put_match(_match("3", date(2026, 9, 27), "Gramastetten"))  # not in the league

    body = {m["oefb_game_id"]: m for m in api_client.get("/matches").json()}

    at_kickoff = body["1"]["opponent_standing"]
    assert (at_kickoff["rank"], at_kickoff["our_rank"], at_kickoff["points_gap"]) == (1, 5, 5)
    assert at_kickoff["strength"] == "stronger"
    assert at_kickoff["table_day"] == "2026-09-20"
    assert at_kickoff["at_kickoff"] is True

    now = body["2"]["opponent_standing"]
    assert (now["rank"], now["table_day"], now["at_kickoff"]) == (1, "2026-09-29", False)

    assert body["3"]["opponent_standing"] is None


def test_matches_without_a_table(api_client, store):
    store.put_match(_match("1", date(2026, 9, 21), "Reichenau"))
    assert api_client.get("/matches").json()[0]["opponent_standing"] is None


def test_league_table_endpoint(api_client, store):
    assert api_client.get("/league/table").json() is None
    store.put_league_table(table(date(2026, 9, 22), row(1, "Ottensheim", 14)))
    store.put_league_table(TODAY)

    body = api_client.get("/league/table").json()
    assert body["league"] == "2. Nordwest"
    assert body["day"] == "2026-09-29"
    assert [(r["rank"], r["team"], r["is_us"]) for r in body["rows"]][:3] == [
        (1, "Ottensheim", False),
        (3, "Sarleinsbach", False),
        (8, "Eidenberg/Geng", True),
    ]


def test_fixtures_endpoint_lists_games_to_come_with_the_opponents_standing(api_client, store):
    now = datetime.now(UTC)
    store.put_league_table(TODAY)
    store.put_fixtures(
        [
            Fixture(
                oefb_game_id="9", kickoff=now + timedelta(days=9), opponent="Sarleinsbach", home_away="away"
            ),
            Fixture(
                oefb_game_id="8", kickoff=now + timedelta(days=2), opponent="Reichenau", home_away="home"
            ),
            Fixture(
                oefb_game_id="7", kickoff=now - timedelta(days=1), opponent="Ottensheim", home_away="home"
            ),
            Fixture(
                oefb_game_id="6",
                kickoff=now + timedelta(days=5),
                opponent="SPG Aschach / Eferding 1b",
                home_away="away",
                art="Testspiel",
            ),
        ]
    )

    body = api_client.get("/league/fixtures").json()
    assert [f["oefb_game_id"] for f in body] == ["8", "6", "9"]
    assert body[0]["opponent_standing"]["strength"] == "level"
    assert body[1]["opponent_standing"] is None
    assert body[2]["opponent_standing"]["rank"] == 3


# --- the scrape (emulator) ------------------------------------------------------------


class _Response:
    def __init__(self, text: str, status_code: int = 200):
        self.text = text
        self.status_code = status_code


class _Session:
    def __init__(self, response: _Response | Exception):
        self.response = response

    def get(self, url, **kwargs):
        if isinstance(self.response, Exception):
            raise self.response
        return self.response


def _table_page() -> str:
    block = {
        "type": "TABELLE",
        "tabellen": {
            "NORMAL": {
                "bewerbName": "2. Nordwest",
                "eintraege": [
                    {
                        "rang": 1,
                        "tendenz": 1,
                        "mannschaftBezeichnung": "Ottensheim",
                        "spiele": 7,
                        "punkte": 17,
                    },
                    {
                        "rang": 8,
                        "tendenz": -2,
                        "mannschaftBezeichnung": "Eidenberg/Geng",
                        "spiele": 7,
                        "punkte": 11,
                        "homepageUrl": f"https://vereine.oefb.at/{OUR_TEAM}/News/",
                    },
                ],
            }
        },
    }
    return f"<script>SG.container.appPreloads['1']=[{json.dumps(block)}]</script>"


@pytest.fixture
def oefb_settings(monkeypatch):
    monkeypatch.setattr(settings, "oefb_team_url", f"https://vereine.oefb.at/{OUR_TEAM}")
    monkeypatch.setattr(settings, "oefb_season", "2026-27")


def test_the_scrape_keeps_the_table_as_the_local_days(store, oefb_settings):
    from oefb.scraper import store_league_table

    # 23:30 UTC is already the next day in Vienna.
    now = datetime(2026, 9, 28, 23, 30, tzinfo=UTC)
    assert store_league_table(store, _Session(_Response(_table_page())), now=now)

    stored = store.league_table()
    assert stored.day == date(2026, 9, 29)
    assert [(r.rank, r.team, r.is_us, r.points) for r in stored.rows] == [
        (1, "Ottensheim", False, 17),
        (8, "Eidenberg/Geng", True, 11),
    ]


def test_a_failed_table_fetch_stores_nothing(store, oefb_settings):
    from oefb.scraper import store_league_table

    assert not store_league_table(store, _Session(OSError("down")))
    assert not store_league_table(store, _Session(_Response("<html></html>")))
    assert store.league_table() is None


def test_the_scrape_replaces_the_fixtures(store, oefb_settings):
    from oefb.scraper import store_fixtures

    store.put_fixtures([Fixture(oefb_game_id="old", kickoff=None, opponent="X", home_away="home")])
    spiel = {
        "datum": 1791122400000,
        "abgeschlossen": False,
        "abgesagt": False,
        "art": "Liga",
        "spielUrl": f"/{OUR_TEAM}/Spielbericht/?Eidenberg-Geng-vs-Urfahr&:s=4120031",
        "heimName": "Eidenberg / Geng",
        "gastName": "Urfahr",
        "heimUrl": f"https://vereine.oefb.at/{OUR_TEAM}/News/",
    }
    block = json.dumps({"type": "SPIELPLAN_MANNSCHAFT", "spiele": [spiel]})
    html = f"<script>SG.container.appPreloads['1']=[{block}]</script>"

    assert store_fixtures(store, html) == 1
    assert store.fixtures() == [
        Fixture(
            oefb_game_id="4120031",
            kickoff=datetime.fromtimestamp(1791122400, tz=UTC),
            opponent="Urfahr",
            home_away="home",
            art="Liga",
        )
    ]
