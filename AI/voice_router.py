import asyncio
import json
import os
import base64
import uuid
import logging
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

logger = logging.getLogger(__name__)


def _serialize_sets(obj):
    if isinstance(obj, set):
        return list(obj)
    raise TypeError(f"Object of type {type(obj).__name__} is not JSON serializable")


from google.adk.runners import Runner
from google.adk.agents.run_config import RunConfig, StreamingMode
from google.adk.agents.live_request_queue import LiveRequestQueue
from google.adk.sessions import InMemorySessionService
from google.genai import types
from dotenv import load_dotenv

# Load environment variables
load_dotenv(override=True)

# --- Agents ---
from word_smith_agent.agent import root_agent as word_smith_agent
from voice_chat.agent import root_agent as voice_chat_agent
from role_master_agent.agent import root_agent as role_master_agent

router = APIRouter()
session_service = InMemorySessionService()

# Map of available agents - matching app names from Flutter
AGENT_MAP = {
    "word_smith_agent": word_smith_agent,
    "voice_chat": voice_chat_agent,
    "role_master_agent": role_master_agent,
}

# RunConfig for Native Audio models
DEFAULT_RUN_CONFIG = RunConfig(
    streaming_mode=StreamingMode.BIDI,
    input_audio_transcription=types.AudioTranscriptionConfig(),
    output_audio_transcription=types.AudioTranscriptionConfig(),
)

from pydantic import BaseModel
from typing import Optional, Dict, Any


class SessionCreateRequest(BaseModel):
    session_id: Optional[str] = None
    state: Optional[Dict[str, Any]] = None


def init_voice_router(app, shared_session_service=None):
    global session_service
    if shared_session_service:
        session_service = shared_session_service
    else:
        logger.warning(
            "No shared session service provided — using module-level InMemorySessionService. "
            "Sessions will NOT be shared across uvicorn workers. "
            "Pass a shared session service via init_voice_router(app, shared_session_service=...)."
        )

    @router.websocket("/ws/apps/{agent_name}/users/{user_id}/sessions/{session_id}")
    async def websocket_endpoint(
        websocket: WebSocket, agent_name: str, user_id: str, session_id: str
    ) -> None:
        if agent_name not in AGENT_MAP:
            await websocket.accept()
            await websocket.send_text(
                json.dumps({"error": f"Agent '{agent_name}' not found."})
            )
            await websocket.close(code=1008)
            return

        agent = AGENT_MAP[agent_name]
        await websocket.accept()
        logger.info(
            "Voice WebSocket connected",
            extra={"agent": agent_name, "session": session_id},
        )

        runner = Runner(
            app_name=agent_name, agent=agent, session_service=session_service
        )

        live_request_queue = LiveRequestQueue()

        async def upstream_task():
            """Handles incoming binary audio and JSON metadata from client."""
            try:
                while True:
                    message = await websocket.receive()

                    # Handle binary PCM data (Production Ready)
                    if "bytes" in message:
                        audio_data = message["bytes"]
                        audio_blob = types.Blob(
                            mime_type="audio/pcm;rate=16000", data=audio_data
                        )
                        live_request_queue.send_realtime(audio_blob)

                    # Handle JSON metadata
                    elif "text" in message:
                        try:
                            data = json.loads(message["text"])
                            if data.get("type") == "text":
                                content = types.Content(
                                    parts=[types.Part(text=data["text"])]
                                )
                                live_request_queue.send_content(content)
                            elif data.get("type") == "image":
                                image_data = base64.b64decode(data["data"])
                                image_blob = types.Blob(
                                    mime_type=data.get("mimeType", "image/jpeg"),
                                    data=image_data,
                                )
                                live_request_queue.send_realtime(image_blob)
                        except Exception as e:
                            logger.warning(f"Metadata processing error: {e}")
            except WebSocketDisconnect:
                logger.info("WebSocket disconnected (upstream)")
            except RuntimeError as e:
                if 'Cannot call "receive"' in str(e):
                    logger.info(
                        "WebSocket disconnected gracefully (receive after disconnect)"
                    )
                else:
                    logger.exception("Upstream task RuntimeError")
            except Exception as e:
                logger.exception("Upstream task error")

        async def downstream_task():
            """Handles outgoing binary audio and JSON metadata to client."""
            try:
                async for event in runner.run_live(
                    user_id=user_id,
                    session_id=session_id,
                    live_request_queue=live_request_queue,
                    run_config=DEFAULT_RUN_CONFIG,
                ):
                    # 1. Check for audio data and send as binary frame
                    audio_sent = False
                    if event.content and event.content.parts:
                        for part in event.content.parts:
                            if part.inline_data and part.inline_data.data:
                                # Send raw PCM bytes directly (Production Ready)
                                await websocket.send_bytes(part.inline_data.data)
                                audio_sent = True

                    # 2. Send Metadata (Text Frame)
                    # We exclude the raw audio bytes from the JSON to save bandwidth
                    metadata = event.model_dump(
                        exclude={"content": {"parts": {"__all__": {"inline_data"}}}},
                        by_alias=True,
                    )
                    await websocket.send_text(
                        json.dumps(metadata, default=_serialize_sets)
                    )

            except asyncio.CancelledError:
                pass
            except Exception as e:
                # If it's a connection closed exception, handle it silently
                if (
                    "ConnectionClosed" in type(e).__name__
                    or "connection closed" in str(e).lower()
                ):
                    logger.info("WebSocket downstream closed due to ConnectionClosed")
                else:
                    logger.exception("Downstream task error")
                    if "1007" in str(e):
                        logger.warning(
                            "HINT: Error 1007 often means the model or voice configuration is incompatible with the modalities."
                        )

        # Run tasks concurrently. If one finishes or raises an error, cancel the other.
        up_task = asyncio.create_task(upstream_task())
        down_task = asyncio.create_task(downstream_task())
        try:
            done, pending = await asyncio.wait(
                [up_task, down_task], return_when=asyncio.FIRST_COMPLETED
            )
            for t in pending:
                t.cancel()
            await asyncio.gather(*pending, return_exceptions=True)
        finally:
            live_request_queue.close()
            logger.info(f"Voice WebSocket session closed: {session_id}")
