"""api/store/rows.py — the stored records, as plain dataclasses.

One class per table of fitness-dashboard's api/models/schema.py, with the
same field names and meanings, so the services that read them port over
nearly line for line. What changed is only *where* they live: Firestore
documents laid out by api/store/firestore.py (ADR-031). The long "why"
comments on each table stay in the old schema.py and its ADRs; what is
here is what differs.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime


@dataclass
class DailyHealth:
    date: date
    steps: int | None = None
    resting_hr: int | None = None
    hrv_ms: float | None = None
    sleep_minutes: int | None = None
    active_kcal: int | None = None
    # None means no session was tracked that day, which is not 0 (ADR-009).
    active_zone_minutes: int | None = None
    weight_kg: float | None = None
    vo2max: float | None = None
    source: str = "google_health"
    # The per-source payload, kept whole so a parsing mistake is recoverable
    # (ADR-002). Stored as JSON text: Firestore rejects an array directly
    # inside an array, and nothing here controls Google's shapes.
    raw: dict = field(default_factory=dict)
    updated_at: datetime | None = None


@dataclass
class CalendarEvent:
    id: str  # Google event id
    calendar_id: str
    title: str | None = None
    start_ts: datetime | None = None
    end_ts: datetime | None = None
    all_day: bool = False
    category: str | None = None
    location: str | None = None
    raw: dict = field(default_factory=dict)
    updated_at: datetime | None = None


@dataclass
class MatchPerformance:
    # Postgres' surrogate key; kept because /matches exposes it.
    id: int
    oefb_game_id: str
    match_date: date | None
    opponent: str
    home_away: str
    result: str | None = None
    started: bool = False
    minutes_played: int = 0
    goals: int = 0
    yellow_card: bool = False
    red_card: bool = False
    created_at: datetime | None = None


@dataclass
class ExerciseHeartRate:
    session_start: datetime
    # The local day the session is filed under, as daily_health counted it.
    date: date
    session_end: datetime | None = None
    # [[seconds_from_start, bpm], ...] ascending — stored as two parallel
    # arrays, since Firestore has no arrays of arrays (ADR-031).
    samples: list[list[int]] = field(default_factory=list)
    zone_seconds: dict[str, int] = field(default_factory=dict)
    fetched_at: datetime | None = None


@dataclass
class OAuthToken:
    provider: str
    refresh_token_enc: str
    access_token_enc: str | None = None
    expiry: datetime | None = None
    scopes: str = ""
    updated_at: datetime | None = None


@dataclass
class AiReport:
    id: int
    created_at: datetime
    trigger: str
    model: str
    prompt_version: str
    summary_md: str
    period_start: date | None = None
    period_end: date | None = None
    insights: dict = field(default_factory=dict)
    tokens_used: int | None = None


@dataclass
class PushDevice:
    """A phone or browser that gets the report-ready push (ADR-030). New in
    this repo: fitness-dashboard stored Web Push subscriptions instead."""

    token: str  # the FCM registration token
    platform: str  # "android" | "web"
    registered_at: datetime | None = None


@dataclass
class SkippedActivity:
    source: str  # "match" | "training"
    ref_id: str
    created_at: datetime | None = None


@dataclass
class Conversation:
    id: int
    title: str = "New chat"
    created_at: datetime | None = None
    updated_at: datetime | None = None
    include: dict = field(default_factory=dict)
    lookback_days: int = 14
    session_ids: list[str] = field(default_factory=list)
    # Denormalised so the chat picker needs no count query per chat.
    message_count: int = 0


@dataclass
class ConversationMessage:
    id: int
    conversation_id: int
    role: str  # "user" | "assistant"
    content: str
    created_at: datetime | None = None


@dataclass
class DrinkLog:
    id: int
    logged_at: datetime
    counted_report_id: int | None = None
    drank_on: date | None = None


@dataclass
class LeagueRow:
    """One line of the league table, as the ÖFB Tabellen page has it."""

    rank: int
    team: str
    is_us: bool = False
    rank_change: int = 0  # places gained (+) or lost (−) in the last round
    played: int = 0
    won: int = 0
    drawn: int = 0
    lost: int = 0
    goals_for: int = 0
    goals_against: int = 0
    goal_difference: int = 0
    points: int = 0


@dataclass
class LeagueTable:
    """The overall league table as the nightly scrape found it on `day`.

    New in this repo: fitness-dashboard never read the table. One is kept
    per day rather than only the latest, so a match can be shown against
    the table as it stood before kick-off."""

    day: date
    league: str
    rows: list[LeagueRow] = field(default_factory=list)
    fetched_at: datetime | None = None


@dataclass
class Fixture:
    """A game on the ÖFB schedule that has not been played yet."""

    oefb_game_id: str
    kickoff: datetime | None
    opponent: str
    home_away: str  # "home" | "away"
    art: str | None = None  # "Liga", "Testspiel", "Cup", …
