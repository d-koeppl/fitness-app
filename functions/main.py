"""Cloud Functions entry points.

Firebase discovers functions by importing this module.

- `api` serves the whole FastAPI app. Python Cloud Functions hand over a
  WSGI (Flask) request, and a2wsgi bridges that to the ASGI app, so the
  routers, schemas and /openapi.json carry over from the old backend.
- `jobs` is the hourly sync (api/jobs.py), on Cloud Scheduler.

Both read the same three secrets from Secret Manager: the Fernet key the
Google tokens are encrypted with, and the OAuth client that refreshes
them. Firebase exposes them as environment variables, which is where
api/config.py already looks.
"""

from __future__ import annotations

import functools
import logging
from datetime import datetime

from a2wsgi import ASGIMiddleware
from firebase_functions import https_fn, options, scheduler_fn
from firebase_functions.params import SecretParam

from api.jobs import SCHEDULE
from api.main import app as fastapi_app

# europe-west1 is one of the two regions behind Firestore's eur3, so
# function-to-database traffic stays in region. max_instances caps what a
# runaway client or retry loop can spend; one user never needs more.
options.set_global_options(region="europe-west1", max_instances=3)

# Python's root logger drops INFO, so the hourly job's one-line summary of
# what each source did never reached Cloud Logging (first deploy,
# 2026-09-25). Errors were already visible; this makes a good run visible
# too.
logging.getLogger("api").setLevel(logging.INFO)
logging.basicConfig(format="%(levelname)s %(name)s: %(message)s")

GOOGLE_SECRETS = [
    SecretParam("TOKEN_ENCRYPTION_KEY"),
    SecretParam("GOOGLE_CLIENT_ID"),
    SecretParam("GOOGLE_CLIENT_SECRET"),
]


@functools.cache
def _wsgi_app() -> ASGIMiddleware:
    # Built on the first request, not at import. ASGIMiddleware starts its
    # event-loop thread when it is constructed, and the deployed server
    # imports this module and then forks its workers: threads do not
    # survive a fork, so an adapter made at import time left every request
    # waiting on a loop that no longer existed until the 60 s timeout.
    # The emulator does not fork, which is why it worked there.
    return ASGIMiddleware(fastapi_app)


@https_fn.on_request(
    memory=options.MemoryOption.MB_512,
    secrets=GOOGLE_SECRETS,
    # POST /sync pulls three Google sources in one request; the default
    # 60 s is not always enough for a cold instance.
    timeout_sec=120,
)
def api(req: https_fn.Request) -> https_fn.Response:
    # buffered=True reads the body and closes the WSGI iterator here, which
    # is what lets a2wsgi finish the ASGI task; unbuffered, the task is left
    # pending until the host happens to close the response.
    return https_fn.Response.from_app(_wsgi_app(), req.environ, buffered=True)


@scheduler_fn.on_schedule(
    schedule=SCHEDULE,
    timezone=scheduler_fn.Timezone("Europe/Vienna"),
    memory=options.MemoryOption.MB_512,
    # A whole vCPU rather than the 1/3 a 512 MiB function gets by default:
    # the ÖFB site's proof-of-work challenge is solved in Python, and the
    # health sync parses a month of payloads. Still inside the free tier's
    # CPU allowance at one run an hour (see the port plan).
    cpu=1,
    timeout_sec=540,
    secrets=GOOGLE_SECRETS,
    # A failed run is retried by the next hourly one; Scheduler retries on
    # top would double the Google requests for nothing.
    retry_count=0,
)
def jobs(event: scheduler_fn.ScheduledEvent) -> None:
    from api.integrations.google_health import local_tz
    from api.jobs import run_hourly
    from api.store.firestore import get_store

    run_hourly(get_store(), datetime.now(local_tz()))
