"""oefb/scraper.py — ÖFB match performance scraper.

Fetches the game list from vereine.oefb.at, checks which completed games
are not yet stored, scrapes each new game report, and stores a
MatchPerformance. Alongside, it keeps the games still to play and the
league table as it stands (new here; fitness-dashboard read neither).
Carried over from fitness-dashboard with two changes:
it writes through the store (ADR-031), and its settings come from
api/config.py instead of module-level `os.getenv` (the old repo's own rule,
which this module used to break).

Run nightly by the `jobs` function at OEFB_SYNC_HOUR (api/jobs.py). Locally:

    python -m oefb.scraper --days 30          # look back 30 days
    python -m oefb.scraper --game-id 3879319  # force scrape one game
    python -m oefb.scraper --all              # every completed game not stored
"""

from __future__ import annotations

import argparse
import logging
from datetime import UTC, datetime, timedelta

import requests

from api.config import settings
from api.integrations.google_health import local_tz
from api.store.firestore import FirestoreStore
from api.store.rows import Fixture, LeagueRow, LeagueTable, MatchPerformance
from oefb.parser import (
    fetch_with_anubis,
    parse_fixtures,
    parse_game_list,
    parse_game_report,
    parse_league_table,
)

logger = logging.getLogger("oefb.scraper")

OEFB_BASE_URL = "https://vereine.oefb.at"


def _team_fragment() -> str:
    # e.g. "https://vereine.oefb.at/UnionEidenbergGeng" → "UnionEidenbergGeng"
    return settings.oefb_team_url.rstrip("/").split("/")[-1]


def _game_list_url() -> str:
    return f"{settings.oefb_team_url}/Mannschaften/Saison-{settings.oefb_season}/KM/Spiele"


def _table_url() -> str:
    return f"{settings.oefb_team_url}/Mannschaften/Saison-{settings.oefb_season}/KM/Tabellen"


def _make_session() -> requests.Session:
    session = requests.Session()
    session.headers.update(
        {
            "User-Agent": ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "de-AT,de;q=0.9,en;q=0.8",
        }
    )
    return session


def _absolute_url(spiel_url: str) -> str:
    if spiel_url.startswith("http"):
        return spiel_url
    return f"{OEFB_BASE_URL}{spiel_url}"


def scrape_single_game(session: requests.Session, game_id: str, spiel_url: str) -> dict | None:
    """Fetch and parse one game report.

    Returns the parsed performance dict, or None if the player was not
    in that game or the page could not be fetched.
    """
    url = _absolute_url(spiel_url)
    logger.info("Fetching game %s → %s", game_id, url)

    try:
        resp = fetch_with_anubis(session, url, base_url=OEFB_BASE_URL)
    except Exception as exc:  # noqa: BLE001 — a dead page is one game, not the run
        logger.error("Error fetching game %s: %s", game_id, exc)
        return None

    if resp.status_code != 200:
        logger.warning("Game %s: HTTP %d", game_id, resp.status_code)
        return None

    return parse_game_report(resp.text, settings.oefb_player_name, _team_fragment())


def _persist_performance(store: FirestoreStore, perf: dict, game_id: str) -> None:
    store.put_match(
        MatchPerformance(
            id=store.next_ids("matches")[0],
            oefb_game_id=game_id,
            match_date=perf["match_date"],
            opponent=perf["opponent"],
            home_away=perf["home_away"],
            result=perf["result"],
            started=perf["started"],
            minutes_played=perf["minutes_played"],
            goals=perf["goals"],
            yellow_card=perf["yellow_card"],
            red_card=perf["red_card"],
        )
    )
    logger.info(
        "Saved %-10s  %s vs %-25s  result=%-5s  started=%-5s  mins=%-3d  goals=%d  yellow=%s  red=%s",
        game_id,
        perf.get("match_date"),
        perf["opponent"],
        perf.get("result", "?"),
        perf["started"],
        perf["minutes_played"],
        perf["goals"],
        perf["yellow_card"],
        perf["red_card"],
    )


def store_fixtures(store: FirestoreStore, game_list_html: str) -> int:
    """Replace the stored fixtures with the games the list still has to
    play. Returns how many there are."""
    fixtures = [
        Fixture(
            oefb_game_id=f["game_id"],
            kickoff=datetime.fromtimestamp(f["kickoff_ms"] / 1000, tz=UTC) if f["kickoff_ms"] else None,
            opponent=f["opponent"],
            home_away=f["home_away"],
            art=f["art"],
        )
        for f in parse_fixtures(game_list_html, _team_fragment())
    ]
    store.put_fixtures(fixtures)
    return len(fixtures)


def store_league_table(store: FirestoreStore, session: requests.Session, now: datetime | None = None) -> bool:
    """Fetch the league table and keep it as today's. Returns whether one
    was stored. A failure here is logged and costs only the table: the
    match scrape it runs beside does not depend on it."""
    try:
        resp = fetch_with_anubis(session, _table_url(), base_url=OEFB_BASE_URL)
    except Exception as exc:  # noqa: BLE001
        logger.error("Could not fetch the league table: %s", exc)
        return False
    table = parse_league_table(resp.text, _team_fragment()) if resp.status_code == 200 else None
    if table is None:
        logger.warning("No league table on %s (HTTP %d)", _table_url(), resp.status_code)
        return False
    now = now or datetime.now(UTC)
    store.put_league_table(
        LeagueTable(
            day=now.astimezone(local_tz()).date(),
            league=table["league"],
            rows=[LeagueRow(**row) for row in table["rows"]],
            fetched_at=now,
        )
    )
    logger.info("Stored the %s table (%d teams)", table["league"], len(table["rows"]))
    return True


def run(
    store: FirestoreStore, days: int | None = 3, game_id: str | None = None, scrape_all: bool = False
) -> int:
    """Scrape new games; returns how many performances were stored.

    Args:
        days:       Look back N days from now. Ignored when scrape_all=True.
        game_id:    If set, force-scrape exactly this one game ID.
        scrape_all: If True, scrape every completed game not yet stored.
    """
    if not settings.oefb_player_name or not settings.oefb_team_url:
        logger.warning("OEFB_PLAYER_NAME / OEFB_TEAM_URL not set; skipping the ÖFB scrape")
        return 0

    session = _make_session()
    existing_ids = {m.oefb_game_id for m in store.matches()}
    logger.info("%d games already stored", len(existing_ids))

    try:
        resp = fetch_with_anubis(session, _game_list_url(), base_url=OEFB_BASE_URL)
    except Exception as exc:  # noqa: BLE001
        logger.error("Could not fetch game list: %s", exc)
        return 0
    all_games = parse_game_list(resp.text)
    logger.info("%d game(s) still to play", store_fixtures(store, resp.text))
    store_league_table(store, session)

    if game_id:
        if game_id in existing_ids:
            logger.info("Game %s already stored; skipping (delete it to re-scrape)", game_id)
            return 0
        target = next((g for g in all_games if g["game_id"] == game_id), None)
        if not target:
            logger.error("Game ID %s not found in current game list", game_id)
            return 0
        perf = scrape_single_game(session, game_id, target["spiel_url"])
        if not perf:
            logger.info("Player '%s' not in game %s", settings.oefb_player_name, game_id)
            return 0
        _persist_performance(store, perf, game_id)
        return 1

    logger.info("Found %d completed games in game list", len(all_games))
    if not scrape_all and days is not None:
        cutoff_ms = (datetime.now(UTC) - timedelta(days=days)).timestamp() * 1000
        all_games = [g for g in all_games if (g["date_ts_ms"] or 0) >= cutoff_ms]
        logger.info("After %d-day lookback filter: %d games", days, len(all_games))

    new_games = [g for g in all_games if g["game_id"] not in existing_ids]
    logger.info("%d new game(s) to check", len(new_games))

    found = 0
    for game in new_games:
        perf = scrape_single_game(session, game["game_id"], game["spiel_url"])
        if perf:
            _persist_performance(store, perf, game["game_id"])
            found += 1
        else:
            logger.debug("Player '%s' not in game %s", settings.oefb_player_name, game["game_id"])

    logger.info("Done. %d new performance(s) saved.", found)
    return found


if __name__ == "__main__":
    from api.store.firestore import get_store

    ap = argparse.ArgumentParser(description="ÖFB match performance scraper")
    ap.add_argument("--days", type=int, default=3, metavar="N", help="look back N days (default: 3)")
    ap.add_argument("--game-id", metavar="ID", help="force-scrape one ÖFB game id")
    ap.add_argument("--all", action="store_true", dest="scrape_all", help="scrape every game not yet stored")
    args = ap.parse_args()
    logging.basicConfig(level=settings.log_level)
    run(get_store(), days=args.days, game_id=args.game_id, scrape_all=args.scrape_all)
