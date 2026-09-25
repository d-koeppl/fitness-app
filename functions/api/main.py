"""api/main.py — FastAPI app wiring.

The routers of the fitness-dashboard backend move here phase by phase
(see the port plan). The app is plain ASGI; functions/main.py is what
adapts it to a Cloud Function, so tests and a local uvicorn run need no
Firebase at all.
"""

from __future__ import annotations

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from api.auth import User, current_user, require_user
from api.config import settings

# Every route requires a signed-in, allowlisted user unless its path is in
# api.auth.PUBLIC_PATHS. The interactive docs and the schema URL are off:
# the schema is exported to openapi/openapi.json with app.openapi(), which
# does not need them, and they would be the only unauthenticated pages.
app = FastAPI(
    title="Fitness API",
    dependencies=[Depends(require_user)],
    openapi_url=None,
    docs_url=None,
    redoc_url=None,
)

# The ID token travels in an Authorization header, not a cookie, so
# credentials stay off. CORS answers preflights before routing, so they
# never reach require_user.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_origin_regex=settings.cors_allow_origin_regex,
    allow_methods=["*"],
    allow_headers=["*"],
)


class Health(BaseModel):
    status: str


class Me(BaseModel):
    uid: str
    email: str


@app.get("/healthz", tags=["meta"], response_model=Health, operation_id="getHealth")
def healthz() -> Health:
    """Liveness probe. Named /healthz, not /health, so it isn't mistaken for
    a sibling of the /health-data routes."""
    return Health(status="ok")


@app.get("/me", tags=["meta"], response_model=Me, operation_id="getMe")
def me(user: User = Depends(current_user)) -> Me:
    """Who the API thinks is calling — the app's check that sign-in worked."""
    return Me(uid=user.uid, email=user.email)
