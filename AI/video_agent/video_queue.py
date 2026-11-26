"""
Async Task Queue for Video Generation (TASK-12)

IMPORTANT: This module is scaffolding for when video DAU exceeds 20.
See docs/video-agent/IMPLEMENTATION_TASKS.md § TASK-12 for the trigger condition.

Architecture:
    Client → POST /generate-video → Cloud Tasks Queue → Worker (Cloud Run Job)
                                                           │
                                                    ┌──────┴──────┐
                                                    │ Run ADK     │
                                                    │ Pipeline    │
                                                    └──────┬──────┘
                                                           │
                                                    Write status → Firestore

    Client polls: GET /video-status/{task_id}

Prerequisites (GCP Console):
    1. Enable Cloud Tasks API: gcloud services enable cloudtasks.googleapis.com
    2. Create a Cloud Tasks queue:
        gcloud tasks queues create video-generation-queue \
            --max-dispatches-per-second=0.133 \
            --max-concurrent-dispatches=1
       This limits dispatch to ~8/min (0.133/sec) to stay under the 10 RPM TTS quota.
    3. Create a service account for the worker with roles:
       - roles/cloudtasks.enqueuer (for creating tasks)
       - roles/firebase.admin (for Firestore access)
       - roles/aiplatform.user (for Vertex AI)
       - roles/run.invoker (for invoking the worker)
    4. Deploy the worker as a Cloud Run Job or Cloud Run Service.
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
from google.genai import types
from pydantic import BaseModel

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class GenerateVideoRequest(BaseModel):
    """Request payload for the /generate-video endpoint."""

    app_name: str = "video_agent"
    user_id: str
    session_id: str
    callback_url: Optional[str] = None  # Optional webhook for completion


class VideoTaskStatus(BaseModel):
    """Status of a queued video generation task."""

    task_id: str
    user_id: str
    status: str  # "queued" | "processing" | "completed" | "failed"
    created_at: str
    updated_at: str
    video_url: Optional[str] = None
    error: Optional[str] = None


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Cloud Tasks queue configuration (set via env vars in production)
CLOUD_TASKS_PROJECT = None  # e.g., "my-gcp-project"
CLOUD_TASKS_LOCATION = None  # e.g., "us-central1"
CLOUD_TASKS_QUEUE = "video-generation-queue"
CLOUD_TASKS_WORKER_URL = None  # e.g., "https://video-worker-xxxxx-uc.a.run.app/process-video"

# Firestore collection for task status tracking
TASKS_COLLECTION = "video_tasks"


def _is_configured() -> bool:
    """Check if the Cloud Tasks environment is configured."""
    return all([CLOUD_TASKS_PROJECT, CLOUD_TASKS_LOCATION, CLOUD_TASKS_WORKER_URL])


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

router = APIRouter(prefix="/video", tags=["video-generation"])


@router.post("/generate-video", status_code=202)
async def generate_video(req: GenerateVideoRequest):
    """
    Queue a video generation task via Google Cloud Tasks.

    Returns 202 Accepted with a task_id for polling status.
    This endpoint is the entry point for the async task queue architecture.
    """
    if not _is_configured():
        raise HTTPException(
            status_code=501,
            detail=(
                "Async video generation is not yet configured. "
                "Set CLOUD_TASKS_PROJECT, CLOUD_TASKS_LOCATION, and "
                "CLOUD_TASKS_WORKER_URL environment variables, or "
                "use the synchronous ADK endpoint for now."
            ),
        )

    task_id = f"video_{uuid.uuid4().hex[:12]}"

    # Create the Firestore document first (so the worker can find it)
    from firebase.client import get_db

    try:
        db = get_db()
        db.collection(TASKS_COLLECTION).document(task_id).set(
            {
                "task_id": task_id,
                "user_id": req.user_id,
                "app_name": req.app_name,
                "session_id": req.session_id,
                "callback_url": req.callback_url or "",
                "status": "queued",
                "created_at": datetime.now(timezone.utc).isoformat(),
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
    except Exception as e:
        logger.error("Failed to create task document in Firestore: %s", e)
        raise HTTPException(status_code=500, detail="Failed to queue video task")

    # Push to Cloud Tasks
    try:
        await _enqueue_cloud_task(task_id, req)
    except Exception as e:
        # Roll back the Firestore document
        try:
            db.collection(TASKS_COLLECTION).document(task_id).delete()
        except Exception:
            pass
        logger.error("Failed to enqueue Cloud Task: %s", e)
        raise HTTPException(status_code=500, detail="Failed to enqueue video task")

    logger.info(
        "Video task queued",
        extra={
            "task_id": task_id,
            "user_id": req.user_id,
            "session_id": req.session_id,
        },
    )

    return JSONResponse(
        status_code=202,
        content={
            "task_id": task_id,
            "status": "queued",
            "message": "Video generation queued. Poll GET /video/status/{task_id} for updates.",
        },
    )


@router.get("/status/{task_id}", response_model=VideoTaskStatus)
async def get_video_status(task_id: str):
    """
    Poll the status of a queued video generation task.

    Returns the current status, and the video URL if completed.
    """
    from firebase.client import get_db

    try:
        db = get_db()
        doc = db.collection(TASKS_COLLECTION).document(task_id).get()
        if not doc.exists:
            raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
        data = doc.to_dict()
        return VideoTaskStatus(**data)
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to read task status from Firestore: %s", e)
        raise HTTPException(status_code=500, detail="Failed to read task status")


async def _enqueue_cloud_task(task_id: str, req: GenerateVideoRequest):
    """
    Create a Cloud Task that invokes the video worker.

    The worker receives the task_id, user_id, and session_id in the payload
    so it can pull the ADK session state from Firestore.

    NOTE: This is a PLACEHOLDER for when DAU exceeds 20 (see TASK-12).
    The real implementation should use the google-cloud-tasks library:

    ```python
    from google.cloud import tasks_v2

    client = tasks_v2.CloudTasksClient()
    parent = client.queue_path(project, location, queue)
    task = {
        "http_request": {
            "http_method": "POST",
            "url": worker_url,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(payload).encode(),
        }
    }
    response = client.create_task(parent, task)
    task_name = response.name
    logger.info("Cloud Task created: %s", task_name)
    ```

    Prerequisites:
        pip install google-cloud-tasks
        gcloud tasks queues create video-generation-queue \
            --max-dispatches-per-second=0.133 \
            --max-concurrent-dispatches=1
    """
    payload = {
        "task_id": task_id,
        "user_id": req.user_id,
        "app_name": req.app_name,
        "session_id": req.session_id,
        "callback_url": req.callback_url or "",
    }

    if not all([CLOUD_TASKS_PROJECT, CLOUD_TASKS_LOCATION, CLOUD_TASKS_WORKER_URL]):
        raise ValueError(
            "CLOUD_TASKS_PROJECT, CLOUD_TASKS_LOCATION, and CLOUD_TASKS_WORKER_URL "
            "must be configured to enqueue Cloud Tasks."
        )

    # TODO: Replace with google-cloud-tasks library when implementing TASK-12
    # For now, this raises a clear error indicating the feature is not yet active.
    raise NotImplementedError(
        "Async video generation via Cloud Tasks is not yet implemented. "
        "See TASK-12 in docs/video-agent/IMPLEMENTATION_TASKS.md for setup instructions. "
        "Install google-cloud-tasks and configure env vars to enable."
    )


# ---------------------------------------------------------------------------
# Worker Handler
# ---------------------------------------------------------------------------

# This function is the entry point for the Cloud Run worker.
# It loads the ADK session state from Firestore, runs the video pipeline,
# and writes the result back to Firestore.


async def handle_worker_request(
    task_id: str,
    user_id: str,
    app_name: str,
    session_id: str,
    user_message: str = "",
):
    """
    Process a video generation task in the worker.

    This is the core logic that the Cloud Run Job/Service executes.
    It reconstructs the ADK session from Firestore, replays the user's
    message to trigger the video pipeline, and stores the result URL.

    Args:
        task_id: Unique task identifier.
        user_id: The user who requested the video.
        app_name: ADK app name (e.g. "video_agent").
        session_id: The ADK session containing story context.
        user_message: The original user message that triggers generation
                      (e.g. "Create a story about the ocean at beginner level").
                      If empty, the worker attempts to replay the first user
                      event from the session history.
    """
    from firebase.client import get_db
    from google.adk.sessions import InMemorySessionService
    from google.adk.runners import Runner

    db = get_db()
    task_ref = db.collection(TASKS_COLLECTION).document(task_id)

    try:
        # 1. Mark as processing
        task_ref.update(
            {
                "status": "processing",
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )

        # 2. Load the ADK agent
        import sys
        from pathlib import Path

        # Ensure the AI/ directory is on the path for module imports
        agents_dir = Path(__file__).parent.parent.resolve()
        if str(agents_dir) not in sys.path:
            sys.path.insert(0, str(agents_dir))

        from video_agent.agent import root_agent

        session_service = InMemorySessionService()

        # 3. Reconstruct the session from Firestore state
        session_doc = db.collection("sessions").document(session_id).get()
        if not session_doc.exists:
            raise ValueError(f"Session {session_id} not found in Firestore")

        session_data = session_doc.to_dict() or {}
        session_state = session_data.get("state", {})

        # Create the session with the restored state
        await session_service.create_session(
            app_name=app_name,
            user_id=user_id,
            session_id=session_id,
            state=session_state,
        )

        # 4. Determine the message to replay
        if not user_message:
            # Try to extract the first user message from session events
            events = session_data.get("events", [])
            for event in events:
                author = event.get("author", "")
                content = event.get("content", {})
                if author == "user" and content:
                    parts = content.get("parts", [])
                    for part in parts:
                        if "text" in part and part["text"].strip():
                            user_message = part["text"]
                            break
                    if user_message:
                        break

        if not user_message:
            raise ValueError(
                "No user message found in session. "
                "Cannot trigger video generation without input."
            )

        # 5. Run the ADK pipeline with the user's message
        runner = Runner(
            app_name=app_name,
            agent=root_agent,
            session_service=session_service,
        )

        events_generated = 0
        async for event in runner.run_async(
            user_id=user_id,
            session_id=session_id,
            new_message=types.Content(
                parts=[types.Part(text=user_message)],
                role="user",
            ),
        ):
            events_generated += 1

        logger.info(
            "Worker processed %d events for task %s",
            events_generated,
            task_id,
        )

        # 6. Read artifacts from the session using the configured artifact service
        #    (matches the URI set via ADK_ARTIFACT_STORE env var in main.py)
        from google.adk.cli.utils.service_factory import create_artifact_service_from_options

        artifact_uri = os.environ.get("ADK_ARTIFACT_STORE", None)
        artifact_service = create_artifact_service_from_options(
            base_dir=str(agents_dir),
            artifact_service_uri=artifact_uri,
        )

        artifact_keys = await artifact_service.list_artifact_keys(
            app_name=app_name,
            user_id=user_id,
            session_id=session_id,
        )

        video_url = ""
        for key in artifact_keys:
            if key.endswith(".mp4"):
                artifact_part = await artifact_service.load_artifact(
                    app_name=app_name,
                    user_id=user_id,
                    session_id=session_id,
                    filename=key,
                )
                if artifact_part and artifact_part.inline_data:
                    # If using GCS artifact service, the artifact is already persisted.
                    # For now, return a placeholder URL — the Flutter frontend reads
                    # artifacts via the ADK HTTP endpoint, not directly from GCS.
                    video_url = f"gs://{artifact_uri.split('://')[1] if artifact_uri else 'your-bucket'}/videos/{user_id}/{session_id}/output.mp4"
                    logger.info("Video artifact found: %s", key)
                    break

        # 7. Mark as completed with the video URL
        task_ref.update(
            {
                "status": "completed",
                "video_url": video_url,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )

    except Exception as e:
        logger.exception("Video worker failed for task %s", task_id)
        task_ref.update(
            {
                "status": "failed",
                "error": str(e),
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        raise


# ---------------------------------------------------------------------------
# Helper: Initialize router on the app
# ---------------------------------------------------------------------------


def init_video_queue_router(app):
    """Register the video queue endpoints on the FastAPI app."""
    app.include_router(router)
    logger.info(
        "Video queue router initialised",
        extra={
            "configured": _is_configured(),
            "worker_url": CLOUD_TASKS_WORKER_URL,
        },
    )
