"""
firebase/ — Firebase initialization and storage helpers.

This package centralises all Firebase Admin SDK interaction:

    client.py   — Firebase app init, get_db(), get_storage_bucket()
    storage.py  — File upload helpers (imports/, images, etc.)

Usage:
    from firebase.client import get_db, get_storage_bucket
    from firebase.storage import upload_to_firebase_imports
"""

from .client import get_db, get_storage_bucket, init_firebase
from .storage import upload_to_firebase_imports

__all__ = [
    "get_db",
    "get_storage_bucket",
    "init_firebase",
    "upload_to_firebase_imports",
]
