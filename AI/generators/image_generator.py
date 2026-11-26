"""
Image generator module using Stability AI API.
Provides image generation for both story and video agents.
"""

import asyncio
import os
import uuid
import base64
import httpx
import logging
from io import BytesIO
from typing import Any, Optional, Dict
from PIL import Image
from google.adk.tools import ToolContext
from google.genai import types

from dotenv import load_dotenv

load_dotenv()

# Configure logging
logger = logging.getLogger(__name__)

# Stability AI API Configuration
STABILITY_ENGINE_ID = "stable-diffusion-xl-1024-v1-0"
STABILITY_API_HOST = os.getenv("STABILITY_API_HOST", "https://api.stability.ai")
STABILITY_API_KEY = os.getenv("STABILITY_API_KEY")

# SDXL 1.0 predefined allowed sizes — the API only accepts these exact dimensions
ALLOWED_SIZES = [
    (1024, 1024),
    (1152, 896),
    (896, 1152),
    (1216, 832),
    (1344, 768),
    (768, 1344),
    (1536, 640),
    (640, 1536),
]


def _match_allowed_size(width: int, height: int) -> tuple[int, int]:
    best = ALLOWED_SIZES[0]
    best_diff = float("inf")
    input_ratio = width / height
    for w, h in ALLOWED_SIZES:
        diff = abs(input_ratio - w / h)
        if diff < best_diff:
            best_diff = diff
            best = (w, h)
    return best


async def generate_image(
    prompt: str,
    height: int = 1024,
    width: int = 1024,
    num_inference_steps: int = 10,
    guidance_scale: float = 7.0,
    style_preset: str = "comic-book",
    max_retries: int = 3,
) -> Image.Image:
    """
    Asynchronous, thread-safe image generation powered by Stability AI using httpx.AsyncClient. (TASK-07)
    """
    if not STABILITY_API_KEY:
        raise ValueError(
            "Stability API key is missing. Set STABILITY_API_KEY environment variable."
        )

    width, height = _match_allowed_size(width, height)
    url = f"{STABILITY_API_HOST}/v1/generation/{STABILITY_ENGINE_ID}/text-to-image"
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Authorization": f"Bearer {STABILITY_API_KEY}",
    }
    payload = {
        "text_prompts": [{"text": prompt}],
        "cfg_scale": guidance_scale,
        "height": height,
        "width": width,
        "samples": 1,
        "steps": num_inference_steps,
        "style_preset": style_preset,
    }

    print(f"[Image Gen] Requesting image from Stability AI ({width}x{height}, style={style_preset})...", flush=True)

    for attempt in range(max_retries):
        try:
            print(f"[Image Gen] Attempt {attempt + 1}/{max_retries} connecting to Stability AI...", flush=True)
            async with httpx.AsyncClient(timeout=90) as client:
                response = await client.post(url, headers=headers, json=payload)
                if response.status_code != 200:
                    error_detail = response.text
                    print(f"[Image Gen] Stability API Error ({response.status_code}): {error_detail[:150]}", flush=True)
                    logger.error(
                        f"Stability API Error: {response.status_code} - {error_detail}"
                    )
                    # Handle content moderation filter gracefully: retry with a safe fallback prompt
                    if response.status_code == 403 and "content_moderation" in error_detail:
                        logger.warning("[Image Gen] Prompt flagged by moderation. Retrying with safe fallback prompt...")
                        safe_fallback_prompt = "Cinematic atmospheric landscape, soft golden hour lighting, peaceful digital painting"
                        payload["text_prompts"] = [{"text": safe_fallback_prompt}]
                        continue

                    # Extract retry_after if present in headers or json
                    retry_after = 5 * (2**attempt)  # Default exponential backoff: 5s, 10s, 20s
                    if "retry-after" in response.headers:
                        try:
                            retry_after = max(int(response.headers["retry-after"]), retry_after)
                        except (ValueError, TypeError):
                            pass
                    raise Exception(
                        f"Stability AI generation failed ({response.status_code}): {error_detail}"
                    )
                data = response.json()
                image_base64 = data["artifacts"][0]["base64"]
                image_bytes = base64.b64decode(image_base64)
                del data, image_base64
                print(f"[Image Gen] Stability AI image received successfully ({len(image_bytes)} bytes).", flush=True)
                return Image.open(BytesIO(image_bytes))
        except Exception as e:
            print(f"[Image Gen] Attempt {attempt + 1} failed: {e}", flush=True)
            if attempt == max_retries - 1:
                raise e
            # Use backoff with jitter
            backoff_time = min(retry_after if 'retry_after' in locals() else (5 * (2**attempt)), 30)
            logger.warning(
                f"Generation attempt {attempt + 1} failed: {e}. Retrying in {backoff_time}s..."
            )
            await asyncio.sleep(backoff_time)


async def generate_image_with_artifact(
    prompt: str, tool_context: ToolContext, **kwargs
) -> Dict[str, Any]:
    """
    Generates an image and saves it as an ADK artifact.
    """
    try:
        image = await generate_image(prompt=prompt, **kwargs)

        buf = BytesIO()
        image_name = f"image_{uuid.uuid4().hex[:8]}.png"
        image.save(buf, format="PNG")

        # Prepare for ADK save
        image_data = buf.getvalue()
        await tool_context.save_artifact(
            image_name,
            types.Part.from_bytes(
                data=base64.b64encode(image_data).decode(),
                mime_type="image/png",
            ),
        )
        logger.info(f"Successfully saved artifact: {image_name}")
        return {"status": "success", "image_path": image_name}

    except Exception as e:
        logger.error(f"Failed to generate artifact image: {e}")
        return {"status": "failed", "error": str(e)}


async def generate_image_tool(prompt: str, tool_context: ToolContext) -> Dict[str, Any]:
    """ADK tool interface for agents."""
    return await generate_image_with_artifact(prompt=prompt, tool_context=tool_context)
