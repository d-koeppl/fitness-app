"""api/store/like.py — SQL's ILIKE, for titles Firestore cannot pattern-match.

The calendar settings are SQL LIKE patterns (`CALENDAR_TRAINING_TITLE=
training`, `CALENDAR_MATCH_TITLE=spiel:%`) because Postgres matched them.
Firestore has no pattern queries, so the titles are fetched with their
month and matched here — with the same meaning, so a pattern that worked in
the old .env still selects exactly the same events.
"""

from __future__ import annotations

import functools
import re


@functools.cache
def _compile(pattern: str) -> re.Pattern[str]:
    parts: list[str] = []
    escaped = False
    for char in pattern:
        if escaped:
            parts.append(re.escape(char))
            escaped = False
        elif char == "\\":
            # Postgres' default LIKE escape character.
            escaped = True
        elif char == "%":
            parts.append(".*")
        elif char == "_":
            parts.append(".")
        else:
            parts.append(re.escape(char))
    if escaped:
        parts.append(re.escape("\\"))
    # DOTALL: `%` matches newlines in Postgres too.
    return re.compile("".join(parts), re.IGNORECASE | re.DOTALL)


def ilike(value: str | None, pattern: str) -> bool:
    """`value ILIKE pattern`. NULL never matches, as in SQL."""
    if value is None:
        return False
    return _compile(pattern).fullmatch(value) is not None
