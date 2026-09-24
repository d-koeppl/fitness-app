"""Cloud Functions entry point.

Firebase discovers functions by importing this module. `api` serves the
whole FastAPI app: Python Cloud Functions hand over a WSGI (Flask)
request, and a2wsgi bridges that to the ASGI app, so the routers,
schemas and /openapi.json carry over from the old backend unchanged.
"""

from __future__ import annotations

import functools

from a2wsgi import ASGIMiddleware
from firebase_functions import https_fn, options

from api.main import app as fastapi_app

# europe-west1 is one of the two regions behind Firestore's eur3, so
# function-to-database traffic stays in region. max_instances caps what a
# runaway client or retry loop can spend; one user never needs more.
options.set_global_options(region="europe-west1", max_instances=3)

@functools.cache
def _wsgi_app() -> ASGIMiddleware:
    # Built on the first request, not at import. ASGIMiddleware starts its
    # event-loop thread when it is constructed, and the deployed server
    # imports this module and then forks its workers: threads do not
    # survive a fork, so an adapter made at import time left every request
    # waiting on a loop that no longer existed until the 60 s timeout.
    # The emulator does not fork, which is why it worked there.
    return ASGIMiddleware(fastapi_app)


@https_fn.on_request(memory=options.MemoryOption.MB_512)
def api(req: https_fn.Request) -> https_fn.Response:
    # buffered=True reads the body and closes the WSGI iterator here, which
    # is what lets a2wsgi finish the ASGI task; unbuffered, the task is left
    # pending until the host happens to close the response.
    return https_fn.Response.from_app(_wsgi_app(), req.environ, buffered=True)
