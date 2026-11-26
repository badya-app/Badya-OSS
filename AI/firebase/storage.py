"""
Firebase Storage helper — handles image / file uploads.

This module uses the bucket obtained via firebase.client.get_storage_bucket()
so that all Firebase initialisation is centralised in one place.

Usage:
    from firebase.storage import upload_to_firebase_imports

    url = upload_to_firebase_imports("filename.png", image_bytes, "image/png")
    if url is None:
        # Upload failed (bucket not configured)
"""

import logging

from .client import get_storage_bucket

logger = logging.getLogger(__name__)


def upload_to_firebase_imports(
    filename: str, data: bytes, content_type: str
) -> str | None:
    """
    Upload a binary blob to Firebase Storage under the imports/ prefix.

    Returns the public URL of the uploaded blob, or None if Firebase Storage
    is not configured (e.g. the default bucket is not set).
    """
    try:
        bucket = get_storage_bucket()
        if bucket is None:
            logger.warning(
                "Firebase Storage bucket is not available — upload skipped. "
                "Ensure firebase-admin is initialised with Storage or set "
                "the FIREBASE_STORAGE_BUCKET environment variable."
            )
            return None
        blob = bucket.blob(f"imports/{filename}")
        blob.content_type = content_type
        blob.upload_from_string(data)
        blob.make_public()
        return blob.public_url
    except Exception as e:
        logger.warning(f"Firebase Storage upload failed for {filename}: {e}")
        return None
