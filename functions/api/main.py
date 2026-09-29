"""api/main.py — FastAPI app wiring.

The routers of the fitness-dashboard backend move here phase by phase
(see the port plan). The app is plain ASGI; functions/main.py is what
adapts it to a Cloud Function, so tests and a local uvicorn run need no
Firebase at all.
"""

from __future__ import annotations

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.routing import APIRoute
from pydantic import BaseModel

from api.auth import User, current_user, require_user
from api.config import settings
from api.routers import calendar as calendar_router
from api.routers import coach as coach_router
from api.routers import drinks as drinks_router
from api.routers import health as health_router
from api.routers import league as league_router
from api.routers import matches as matches_router
from api.routers import oauth as oauth_router
from api.routers import push as push_router
from api.routers import reports as reports_router
from api.routers import sync as sync_router
from api.routers import training as training_router


def operation_id(route: APIRoute) -> str:
    """The handler's name in camelCase: `list_daily_health` becomes
    `listDailyHealth`, which is the method name in the generated Dart
    client. FastAPI's default glues the path and method on as well, and
    would rename the Dart method whenever a path changed."""
    head, *rest = route.name.split("_")
    return head + "".join(word.capitalize() for word in rest)


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
    generate_unique_id_function=operation_id,
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


# Carried over from fitness-dashboard phase by phase (see the port plan).
# Every one of them sits behind require_user above.
for router in (
    health_router.router,
    training_router.router,
    drinks_router.router,
    matches_router.router,
    league_router.router,
    calendar_router.router,
    reports_router.router,
    sync_router.router,
    oauth_router.router,
    push_router.router,
    coach_router.router,
):
    app.include_router(router)


class Health(BaseModel):
    status: str


class Me(BaseModel):
    uid: str
    email: str


@app.get("/healthz", tags=["meta"], response_model=Health)
def get_health() -> Health:
    """Liveness probe. Named /healthz, not /health, so it isn't mistaken for
    a sibling of the /health-data routes."""
    return Health(status="ok")


@app.get("/me", tags=["meta"], response_model=Me)
def get_me(user: User = Depends(current_user)) -> Me:
    """Who the API thinks is calling — the app's check that sign-in worked."""
    return Me(uid=user.uid, email=user.email)
