from fastapi import FastAPI, APIRouter, HTTPException, Form, Header
from typing import Optional
import base64
from io import BytesIO
import uuid
import logging

from .image_generator import generate_image
from content_router import verify_firebase_token
from rate_limiter import get_image_generation_rate_limiter

logger = logging.getLogger(__name__)

router = APIRouter()


def init_generator_router(app: FastAPI):
    """
    Initializes the generator router.
    Static file mounting is removed as images are now sent as base64.
    """
    pass


@router.post("/generate-image")
async def generate_image_endpoint(
    prompt: str = Form(...),
    width: int = Form(1024),
    height: int = Form(1024),
    user_id: str = Form(...),
    authorization: Optional[str] = Header(None),
):
    # Resolve effective user ID from auth token (preferred) or form field
    effective_user_id = user_id
    if authorization and authorization.startswith("Bearer "):
        token_user_id = await verify_firebase_token(authorization)
        if token_user_id:
            effective_user_id = token_user_id

    if not effective_user_id:
        raise HTTPException(status_code=401, detail="Authentication required")

    # Rate limit: 5 image generations per day per user
    get_image_generation_rate_limiter().check(effective_user_id)

    logger.info(f"Image generation request from {effective_user_id}: {prompt[:60]}...")
    try:
        # Generate the image using Stability AI
        img = await generate_image(prompt=prompt, width=width, height=height)

        # Convert PIL image to base64 string
        buffered = BytesIO()
        img.save(buffered, format="PNG")
        img_base64 = base64.b64encode(buffered.getvalue()).decode()

        # We no longer save locally, just return the data for the client to handle
        return {
            "status": "success",
            "image_data": img_base64,
            "mime_type": "image/png",
            "filename": f"gen_{uuid.uuid4().hex[:10]}.png"
        }
    except Exception as e:
        logger.exception(f"Error in generate_image_endpoint: {e}")
        raise HTTPException(status_code=500, detail=str(e))
