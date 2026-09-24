"""api/main.py — FastAPI app wiring.

The routers of the fitness-dashboard backend move here phase by phase
(see the port plan). The app is plain ASGI; functions/main.py is what
adapts it to a Cloud Function, so tests and a local uvicorn run need no
Firebase at all.
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from api.config import settings

app = FastAPI(title="Fitness API")

# Access control moves from the network (Cloudflare Access, ADR-006) to
# Firebase ID tokens in phase 1. The token travels in an Authorization
# header, not a cookie, so credentials stay off.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_origin_regex=settings.cors_allow_origin_regex,
    allow_methods=["*"],
    allow_headers=["*"],
)


class Health(BaseModel):
    status: str


@app.get("/healthz", tags=["meta"], response_model=Health, operation_id="getHealth")
def healthz() -> Health:
    """Liveness probe. Named /healthz, not /health, so it isn't mistaken for
    a sibling of the /health-data routes."""
    return Health(status="ok")
