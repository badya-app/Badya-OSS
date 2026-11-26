import json
import os
import uvicorn
import logging
from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
from google.adk.cli.fast_api import get_fast_api_app, create_session_service_from_options

from generators.server import router as generator_router, init_generator_router
from voice_router import router as voice_router, init_voice_router
from rate_limiter import get_video_rate_limiter
from video_agent.video_queue import init_video_queue_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger(__name__)

agents_directory = os.path.dirname(os.path.abspath(__file__))
session_uri = os.environ.get("ADK_SESSION_STORE", None)
artifact_uri = os.environ.get("ADK_ARTIFACT_STORE", None)  # e.g. gs://my-bucket

# ─── ADK Observability Configuration ────────────────────────────────────
# Cloud Trace is configured via OpenTelemetry. The following env vars control
# the behaviour:
#
#   OTEL_EXPORTER_OTLP_PROTOCOL=grpc           (set for Cloud Trace export)
#   OTEL_EXPORTER_OTLP_ENDPOINT=https://...     (Cloud OTLP endpoint)
#   GOOGLE_CLOUD_PROJECT=<project-id>           (required for trace export)
#
# Prompt-response logging:
#   OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=NO_CONTENT
#       → metadata only (privacy-safe, enabled in deployed envs)
#       → true          full content logging
#       → false         disabled
#   LOGS_BUCKET_NAME=<bucket>                    (enables logging; unset = disabled)
#
# In Cloud Run, set these via the --set-env-vars flag or the Cloud Console.

trace_to_cloud = os.environ.get("TRACE_TO_CLOUD", "false").lower() == "true"

logger.info(
    "Starting AI service",
    extra={
        "trace_to_cloud": trace_to_cloud,
        "session_store": session_uri or "in-memory (not shared across workers)",
        "artifact_store": artifact_uri or "local file storage (ephemeral on Cloud Run)",
        "otel_content_capture": os.environ.get(
            "OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT", "NO_CONTENT"
        ),
    },
)

# Create the session service ONCE using the same factory ADK uses internally.
# This ensures the main agent routes and the voice WebSocket share the same store.
shared_session_service = create_session_service_from_options(
    base_dir=agents_directory,
    session_service_uri=session_uri,
)

app = get_fast_api_app(
    agents_dir=agents_directory,
    web=False,
    session_service_uri=session_uri,
    artifact_service_uri=artifact_uri,  # None → local file storage; set ADK_ARTIFACT_STORE=gs://bucket for GCS
    trace_to_cloud=trace_to_cloud,
    otel_to_cloud=trace_to_cloud,  # Enable full OTel export (metrics + traces) when Cloud Trace is on
)

# Exception handler for Vertex AI "already exists" errors
@app.exception_handler(Exception)
async def already_exists_exception_handler(request: Request, exc: Exception):
    exc_str = str(exc).lower()
    if "already exists" in exc_str:
        return JSONResponse(
            status_code=409,
            content={"message": "Session already exists", "error": str(exc)}
        )
    # Allow FastAPI's default handler to take over for other exceptions
    from fastapi.exception_handlers import http_exception_handler
    from starlette.exceptions import HTTPException
    
    # If it's an HTTP exception, handle it properly
    if isinstance(exc, HTTPException):
        return await http_exception_handler(request, exc)
        
    # Re-raise standard exceptions to be handled by the default 500 handler
    raise exc

# Expose on app.state for any future router that needs it
app.state.session_service = shared_session_service


# ---------------------------------------------------------------------------
# Middleware: Per-User Rate Limiting for Video Generation (TASK-09)
# ---------------------------------------------------------------------------
# The ADK exposes a unified POST /run endpoint. Requests to the
# VideoStoryGeneratorSystem agent are identified by the app_name field
# in the JSON request body.

VIDEO_AGENT_APP_NAMES = {"video_agent"}


@app.middleware("http")
async def video_rate_limit_middleware(request: Request, call_next):
    """
    Middleware that checks the per-user daily limit for video generation
    requests before they reach the ADK agent runner.

    Detects video agent runs by inspecting the request body for
    app_name = "video_agent" (the directory containing VideoStoryGeneratorSystem).
    """
    if request.method == "POST" and request.url.path in ("/run", "/run_sse"):
        try:
            body = await request.body()
            if body:
                body_data = json.loads(body)
                app_name = body_data.get("app_name", "")
                if app_name in VIDEO_AGENT_APP_NAMES:
                    user_id = body_data.get("user_id", "")
                    if not user_id:
                        # Fall back to client IP if no user_id provided
                        client_host = request.client.host if request.client else "unknown"
                        user_id = f"ip:{client_host}"
                    get_video_rate_limiter().check(user_id)
        except json.JSONDecodeError:
            # Non-JSON body — not an ADK request, skip rate limiting
            pass
        except HTTPException:
            # Let 429 (rate limit exceeded) propagate — do NOT swallow it
            raise
        except Exception:
            # Log but don't block the request on unexpected middleware errors
            logger.exception("Video rate limit middleware error")

    response = await call_next(request)
    return response

from content_router import recommendation_router, import_router, fetch_transcript
from firebase.client import init_firebase
from embedding_service import init_embedding_service, shutdown_embedding_service
from rate_limiter import get_transcript_rate_limiter
from typing import Optional

@app.on_event("startup")
async def startup_event():
    logger.info("[Startup] Initializing Firebase and EmbeddingService...")
    init_firebase()
    init_embedding_service()
    logger.info("[Startup] Firebase and EmbeddingService initialized.")

@app.on_event("shutdown")
async def shutdown_event():
    logger.info("[Shutdown] Shutting down EmbeddingService...")
    shutdown_embedding_service()

init_generator_router(app)
app.include_router(generator_router)

init_voice_router(app, shared_session_service=shared_session_service)
app.include_router(voice_router)

# Mount content and recommendation routes
app.include_router(recommendation_router)
app.include_router(import_router)

# ---------------------------------------------------------------------------
# Video Queue (TASK-12): Async task queue for video generation (>20 DAU)
# ---------------------------------------------------------------------------
init_video_queue_router(app)

@app.get("/transcript")
async def fetch_transcript_route(
    video_id: str, lang: Optional[str] = None, request: Request = None
):
    # Rate limit per client IP for the standalone endpoint
    client_ip = request.client.host if request and request.client else "unknown"
    get_transcript_rate_limiter().check(client_ip)
    return await fetch_transcript(video_id, lang, request=request)

@app.get("/health")
async def root_health():
    """Root health check endpoint for the AI service."""
    return {"status": "ok", "service": "badya-ai-backend"}

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
