"""oefb/parser.py — HTML/JSON parsing for vereine.oefb.at game pages.

All functions are pure (no HTTP side effects) except fetch_with_anubis
which needs a requests.Session for the challenge exchange.
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
import time
from datetime import UTC, datetime

import requests

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Anubis SHA-256 proof-of-work helpers
# ---------------------------------------------------------------------------

def _solve_anubis(html: str) -> tuple[str, int, str, int]:
    """Solve the Anubis PoW challenge embedded in the page HTML.

    The "fast" algorithm: find nonce N where
    SHA256(randomData + str(N)) has its first `difficulty` hex digits all zero.

    Returns (hash_hex, nonce, challenge_id, elapsed_ms).
    """
    m = re.search(r'id="anubis_challenge"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        raise ValueError("No Anubis challenge block found in HTML")

    challenge_data = json.loads(m.group(1).strip())
    rules = challenge_data["rules"]
    challenge = challenge_data["challenge"]

    random_data: str = challenge["randomData"]
    difficulty: int = rules["difficulty"]
    challenge_id: str = challenge["id"]

    # Number of complete zero bytes required + optional half-byte
    full_bytes = difficulty // 2
    has_half = difficulty % 2 != 0

    start = time.monotonic()
    nonce = 0
    while True:
        digest = hashlib.sha256((random_data + str(nonce)).encode()).digest()

        ok = all(digest[i] == 0 for i in range(full_bytes))
        if ok and has_half and (digest[full_bytes] >> 4) != 0:
            ok = False

        if ok:
            elapsed_ms = int((time.monotonic() - start) * 1000)
            logger.debug(
                "Anubis: solved nonce=%d difficulty=%d in %dms",
                nonce,
                difficulty,
                elapsed_ms,
            )
            return digest.hex(), nonce, challenge_id, elapsed_ms

        nonce += 1


def fetch_with_anubis(
    session: requests.Session,
    url: str,
    base_url: str = "https://vereine.oefb.at",
) -> requests.Response:
    """Fetch URL, solving the Anubis PoW challenge if the server returns one.

    The solved challenge sets a JWT cookie on the session so subsequent
    requests to the same domain don't need to re-solve.
    """
    resp = session.get(url, timeout=20)
    if "anubis_challenge" not in resp.text:
        return resp

    logger.info("Anubis challenge detected for %s — solving...", url)
    hash_hex, nonce, cid, elapsed_ms = _solve_anubis(resp.text)

    pass_url = f"{base_url}/.within.website/x/cmd/anubis/api/pass-challenge"
    session.get(
        pass_url,
        params={
            "id": cid,
            "response": hash_hex,
            "nonce": str(nonce),
            "redir": url,
            "elapsedTime": str(elapsed_ms),
        },
        timeout=15,
        allow_redirects=True,
    )

    # Re-fetch with the auth cookie now set
    resp = session.get(url, timeout=20)
    if "anubis_challenge" in resp.text:
        raise RuntimeError(f"Anubis challenge still present after solving for {url}")
    return resp


# ---------------------------------------------------------------------------
# Internal JSON extraction helpers
# ---------------------------------------------------------------------------

def _extract_preloads(html: str) -> dict[str, dict]:
    """Extract all SG.container.appPreloads[KEY] = [...] JSON blocks.

    Returns a dict mapping string key → first element of the JSON array
    (or the raw value if it's not a list).
    """
    result: dict[str, dict] = {}

    for m in re.finditer(r"SG\.container\.appPreloads\['(-?\d+)'\]=", html):
        key = m.group(1)
        chunk = html[m.end() :]
        if not chunk or chunk[0] not in "[{":
            continue

        depth = 0
        in_str = False
        escape = False
        for i, c in enumerate(chunk):
            if escape:
                escape = False
                continue
            if c == "\\":
                escape = True
                continue
            if c == '"' and not escape:
                in_str = not in_str
            if not in_str:
                if c in "[{":
                    depth += 1
                elif c in "]}":
                    depth -= 1
                    if depth == 0:
                        try:
                            val = json.loads(chunk[: i + 1])
                            result[key] = val[0] if isinstance(val, list) and val else val
                        except json.JSONDecodeError:
                            pass
                        break

    return result


def _parse_minute(minute_str) -> int:
    """Parse ÖFB minute strings like '72' or '90+2' into total minutes."""
    s = str(minute_str).strip()
    if "+" in s:
        parts = s.split("+", 1)
        try:
            return int(parts[0]) + int(parts[1])
        except ValueError:
            return int(parts[0])
    try:
        return int(s)
    except ValueError:
        return 0


# ---------------------------------------------------------------------------
# Game list parsing
# ---------------------------------------------------------------------------

def parse_game_list(html: str) -> list[dict]:
    """Parse the Mannschaften/Saison-{SEASON}/KM/Spiele page.

    Returns a list of dicts, one per completed non-cancelled game:
    {
        "game_id":    "3879319",         # integer string from ":s=" in spielUrl
        "spiel_url":  "/UnionEidenbergGeng/Spielbericht/?...",
        "date_ts_ms": 1757696400000,     # Unix millisecond timestamp
        "heim_name":  "Eidenberg / Geng",
        "gast_name":  "SK Admira Juniors",
        "tore_heim":  4,
        "tore_gast":  3,
        "art":        "Meisterschaft",   # "Testspiel", "Meisterschaft", …
    }
    """
    preloads = _extract_preloads(html)

    for data in preloads.values():
        if not isinstance(data, dict):
            continue
        if data.get("type") != "SPIELPLAN_MANNSCHAFT" or "spiele" not in data:
            continue

        games: list[dict] = []
        for spiel in data["spiele"]:
            if not spiel.get("abgeschlossen"):
                continue
            if spiel.get("abgesagt"):
                continue

            spiel_url = spiel.get("spielUrl", "")
            m = re.search(r":s=(\d+)", spiel_url)
            if not m:
                continue

            # toreHeim/toreGast may be a list of scorer objects — count them
            raw_heim = spiel.get("toreHeim")
            raw_gast = spiel.get("toreGast")
            tore_heim = len(raw_heim) if isinstance(raw_heim, list) else raw_heim
            tore_gast = len(raw_gast) if isinstance(raw_gast, list) else raw_gast

            games.append(
                {
                    "game_id": m.group(1),
                    "spiel_url": spiel_url,
                    "date_ts_ms": spiel.get("datum"),
                    "heim_name": spiel.get("heimName"),
                    "gast_name": spiel.get("gastName"),
                    "tore_heim": tore_heim,
                    "tore_gast": tore_gast,
                    "art": spiel.get("art"),
                }
            )

        return games

    logger.warning("SPIELPLAN_MANNSCHAFT block not found in game list HTML")
    return []


# ---------------------------------------------------------------------------
# Game report parsing
# ---------------------------------------------------------------------------

def parse_game_report(
    html: str,
    player_name: str,
    our_team_url_fragment: str,
) -> dict | None:
    """Parse a Spielbericht page and return player-specific performance data.

    Args:
        html: Raw HTML of the game report page.
        player_name: Full player name as it appears on the site
                     (e.g. "Daniel Köppl").
        our_team_url_fragment: Substring that identifies our team in a URL
                               (e.g. "UnionEidenbergGeng").

    Returns:
        {
            "match_date":    date,
            "opponent":      "SK Admira Juniors",
            "home_away":     "home" | "away",
            "result":        "4:3",          # home_goals:away_goals
            "started":       True,
            "minutes_played": 72,
            "goals":         0,
            "yellow_card":   False,
            "red_card":      False,
        }
        or None if the player did not feature in this game.
    """
    preloads = _extract_preloads(html)

    # --- Locate the four relevant data blocks ---
    header_block: dict | None = None   # team names, final score
    context_block: dict | None = None  # heimspiel, statistik
    lineup_block: dict | None = None   # aufstellungen (player lists)
    ticker_block: dict | None = None   # tickerEintraege (match events)

    for data in preloads.values():
        if not isinstance(data, dict):
            continue
        if "heimErgebnis" in data and header_block is None:
            header_block = data
        if "heimspiel" in data and "statistik" in data and context_block is None:
            context_block = data
        if "aufstellungenHeimStart" in data and lineup_block is None:
            lineup_block = data
        if "tickerEintraege" in data and ticker_block is None:
            ticker_block = data

    if lineup_block is None:
        logger.warning("Lineup block not found in game report HTML")
        return None

    # --- Home / away determination ---
    if context_block is not None:
        heimspiel: bool = bool(context_block.get("heimspiel", False))
    else:
        heim_url = lineup_block.get("heimMannschaftUrl", "")
        heimspiel = our_team_url_fragment in heim_url

    # --- Teams and lineups ---
    if heimspiel:
        home_away = "home"
        opponent = lineup_block.get("gastMannschaftName", "")
        our_start: list[dict] = lineup_block.get("aufstellungenHeimStart", [])
        our_ersatz: list[dict] = lineup_block.get("aufstellungenHeimErsatz", [])
    else:
        home_away = "away"
        opponent = lineup_block.get("heimMannschaftName", "")
        our_start = lineup_block.get("aufstellungenGastStart", [])
        our_ersatz = lineup_block.get("aufstellungenGastErsatz", [])

    # --- Match date ---
    match_date = None
    if header_block and header_block.get("beginnDatumZeit"):
        ts_ms = header_block["beginnDatumZeit"]
        match_date = datetime.fromtimestamp(ts_ms / 1000, tz=UTC).date()

    # --- Result (always home_goals:away_goals) ---
    result: str | None = None
    if header_block:
        heim_goals = header_block.get("heimErgebnis")
        gast_goals = header_block.get("gastErgebnis")
        if heim_goals is not None and gast_goals is not None:
            result = f"{heim_goals}:{gast_goals}"

    # --- Find the player in our starters or bench ---
    player_obj: dict | None = None
    in_start = False

    for p in our_start:
        if p.get("spielerName") == player_name:
            player_obj = p
            in_start = True
            break

    if player_obj is None:
        for p in our_ersatz:
            if p.get("spielerName") == player_name:
                player_obj = p
                break

    if player_obj is None:
        logger.debug("Player '%s' not found in lineup", player_name)
        return None

    player_events: list[str] = player_obj.get("events", [])
    ticker: list[dict] = ticker_block.get("tickerEintraege", []) if ticker_block else []

    # --- Goals ---
    # In tickerEintraege, Tor.spieler1Name is the scorer.
    if ticker:
        goals = sum(
            1
            for ev in ticker
            if ev.get("type") == "Tor" and ev.get("spieler1Name") == player_name
        )
    else:
        # Fallback: count "tor" in player event icons
        goals = player_events.count("tor")

    # --- Cards ---
    # Card events carry the carded player as spieler1Name, same as Tor.
    if ticker:
        yellow_card = any(
            ev.get("type") == "Gelbe Karte" and ev.get("spieler1Name") == player_name
            for ev in ticker
        )
        red_card = any(
            ev.get("type") in ("Rote Karte", "Gelb/Rote Karte")
            and ev.get("spieler1Name") == player_name
            for ev in ticker
        )
    else:
        yellow_card = "gelb" in player_events
        red_card = "rot" in player_events

    # --- Minutes played ---
    if in_start:
        # In tickerEintraege, Auswechslung.spieler1Name is the player COMING ON
        # and spieler2Name is the player going OFF.
        sub_minute: int | None = None
        for ev in ticker:
            if ev.get("type") != "Auswechslung":
                continue
            if ev.get("spieler2Name") == player_name:
                sub_minute = _parse_minute(ev.get("minute", "90"))
                break

        minutes_played = sub_minute if sub_minute is not None else 90

    else:
        # Bench player: find the Auswechslung where they are spieler1Name (coming on)
        came_on: int | None = None
        for ev in ticker:
            if ev.get("type") == "Auswechslung" and ev.get("spieler1Name") == player_name:
                came_on = _parse_minute(ev.get("minute", "90"))
                break

        minutes_played = max(0, 90 - came_on) if came_on is not None else 0

    return {
        "match_date": match_date,
        "opponent": opponent,
        "home_away": home_away,
        "result": result,
        "started": in_start,
        "minutes_played": minutes_played,
        "goals": goals,
        "yellow_card": yellow_card,
        "red_card": red_card,
    }


# ---------------------------------------------------------------------------
# Fixtures and league table
# ---------------------------------------------------------------------------

def team_key(name: str) -> str:
    """A team name reduced to what the site's pages agree on.

    The table spells a team "Kirchberg/D." where the game list and the game
    report say "Kirchberg / D.", so names are compared on this key: case
    folded, runs of whitespace collapsed, no spaces around a slash."""
    collapsed = " ".join(name.split())
    return re.sub(r"\s*/\s*", "/", collapsed).casefold()


def parse_fixtures(html: str, our_team_url_fragment: str) -> list[dict]:
    """The games on the Spiele page that are still to be played.

    Same SPIELPLAN_MANNSCHAFT block as `parse_game_list`, the other half of
    it: not yet completed, not called off. Returns, in the page's order:
    {
        "game_id":    "4120031",
        "kickoff_ms": 1791122400000,     # Unix millisecond timestamp
        "opponent":   "Urfahr",
        "home_away":  "home" | "away",
        "art":        "Liga",            # "Testspiel", "Cup", …
    }
    """
    for data in _extract_preloads(html).values():
        if not isinstance(data, dict):
            continue
        if data.get("type") != "SPIELPLAN_MANNSCHAFT" or "spiele" not in data:
            continue

        fixtures: list[dict] = []
        for spiel in data["spiele"]:
            if spiel.get("abgeschlossen") or spiel.get("abgesagt"):
                continue
            m = re.search(r":s=(\d+)", spiel.get("spielUrl", ""))
            if not m:
                continue
            home = our_team_url_fragment in (spiel.get("heimUrl") or "")
            fixtures.append(
                {
                    "game_id": m.group(1),
                    "kickoff_ms": spiel.get("datum"),
                    "opponent": spiel.get("gastName" if home else "heimName") or "",
                    "home_away": "home" if home else "away",
                    "art": spiel.get("art"),
                }
            )
        return fixtures

    logger.warning("SPIELPLAN_MANNSCHAFT block not found in game list HTML")
    return []


def parse_league_table(html: str, our_team_url_fragment: str) -> dict | None:
    """The overall ("Gesamt") table from the Tabellen page, or None when the
    page has none.

    The page carries five tables (overall, home, away, autumn, spring) under
    `tabellen`; only the overall one is read. Our own row is recognised by
    its club page URL, not its name, which the table spells differently
    from the game list. Returns:
    {
        "league": "2. Nordwest",
        "rows": [{"rank": 1, "rank_change": 1, "team": "Ottensheim",
                  "is_us": False, "played": 7, "won": 5, "drawn": 2,
                  "lost": 0, "goals_for": 25, "goals_against": 6,
                  "goal_difference": 19, "points": 17}, ...],
    }
    """
    for data in _extract_preloads(html).values():
        if not isinstance(data, dict) or data.get("type") != "TABELLE":
            continue
        tables = data.get("tabellen")
        overall = tables.get("NORMAL") if isinstance(tables, dict) else None
        if not isinstance(overall, dict):
            continue

        rows = [
            {
                "rank": entry["rang"],
                "rank_change": entry.get("tendenz") or 0,
                "team": entry["mannschaftBezeichnung"],
                "is_us": our_team_url_fragment in (entry.get("homepageUrl") or ""),
                "played": entry.get("spiele", 0),
                "won": entry.get("siege", 0),
                "drawn": entry.get("unentschieden", 0),
                "lost": entry.get("niederlagen", 0),
                "goals_for": entry.get("toreErzielt", 0),
                "goals_against": entry.get("toreErhalten", 0),
                "goal_difference": entry.get("tordifferenz", 0),
                "points": entry.get("punkte", 0),
            }
            for entry in overall.get("eintraege") or []
        ]
        if not rows:
            continue
        return {"league": overall.get("bewerbName") or data.get("bezeichnung") or "", "rows": rows}

    logger.warning("TABELLE block not found in table HTML")
    return None
