"""In-memory rate limiter for FastAPI endpoints."""

import time
import logging
import threading
from collections import defaultdict
from typing import Optional

from fastapi import HTTPException

logger = logging.getLogger(__name__)


class RateLimiter:
    """Per-user in-memory rate limiter with configurable windows.

    Tracks request timestamps per user_id for both a short window (e.g. 1 minute)
    and a long window (e.g. 1 day). Old entries are pruned on each check.
    Stale user IDs with no activity are removed periodically to prevent
    unbounded memory growth.

    Thread-safe: uses a reentrant lock to protect all shared mutable state.

    Limitations:
    - In-memory only — resets on server restart.
    - Not shared across uvicorn workers (use with single worker or add Redis).
    """

    # Run a full stale-user cleanup every N seconds (default: 1 hour)
    CLEANUP_INTERVAL: float = 3600.0

    def __init__(self, rpm: int = 5, rpd: int = 20):
        """
        Args:
            rpm: Max requests per minute per user.
            rpd: Max requests per day per user.
        """
        self.rpm = rpm
        self.rpd = rpd
        self._minute_buckets: dict[str, list[float]] = defaultdict(list)
        self._day_buckets: dict[str, list[float]] = defaultdict(list)
        self._lock = threading.Lock()
        self._last_cleanup_time: float = time.time()

    def _cleanup_stale_users(self) -> None:
        """Remove user IDs whose timestamp lists are all empty.

        These users have had no requests within the day window, so keeping
        their keys provides no benefit and wastes memory.

        Must be called while holding ``self._lock``.
        """
        stale = [
            uid
            for uid in list(self._minute_buckets.keys())
            if not self._minute_buckets[uid] and not self._day_buckets[uid]
        ]
        for uid in stale:
            del self._minute_buckets[uid]
            del self._day_buckets[uid]
        if stale:
            logger.debug("Cleaned up %d stale rate-limiter user(s)", len(stale))

    def check(self, user_id: str) -> None:
        """Check if *user_id* has exceeded rate limits. Raises 429 if so."""
        with self._lock:
            now = time.time()
            minute_ago = now - 60
            day_ago = now - 86_400

            # Prune stale entries (inside the lock so bucket state is consistent)
            minute_timestamps = self._minute_buckets[user_id]
            self._minute_buckets[user_id] = [t for t in minute_timestamps if t > minute_ago]

            day_timestamps = self._day_buckets[user_id]
            self._day_buckets[user_id] = [t for t in day_timestamps if t > day_ago]

            # Periodic full cleanup of stale user IDs (prevents unbounded memory)
            if now - self._last_cleanup_time > self.CLEANUP_INTERVAL:
                self._cleanup_stale_users()
                self._last_cleanup_time = now

            # Check limits
            if len(self._minute_buckets[user_id]) >= self.rpm:
                logger.warning(
                    "Rate limit exceeded (per-minute)",
                    extra={"user_id": user_id, "limit": self.rpm, "window": "1m"},
                )
                raise HTTPException(
                    status_code=429,
                    detail={
                        "error": "rate_limit_exceeded",
                        "message": f"Too many requests. Max {self.rpm} requests per minute.",
                        "retry_after_seconds": 60,
                    },
                )

            if len(self._day_buckets[user_id]) >= self.rpd:
                logger.warning(
                    "Rate limit exceeded (per-day)",
                    extra={"user_id": user_id, "limit": self.rpd, "window": "1d"},
                )
                raise HTTPException(
                    status_code=429,
                    detail={
                        "error": "rate_limit_exceeded",
                        "message": f"Too many requests. Max {self.rpd} requests per day.",
                        "retry_after_seconds": 86_400,
                    },
                )

            # Record this request
            self._minute_buckets[user_id].append(now)
            self._day_buckets[user_id].append(now)


# ---------------------------------------------------------------------------
# Module-level singleton (so all endpoints share the same limiter instance)
# ---------------------------------------------------------------------------
_import_limiter: Optional[RateLimiter] = None
_image_limiter: Optional[RateLimiter] = None
_transcript_limiter: Optional[RateLimiter] = None
_video_limiter: Optional[RateLimiter] = None


def get_import_rate_limiter() -> RateLimiter:
    """Return the shared /import rate limiter (lazily created)."""
    global _import_limiter
    if _import_limiter is None:
        _import_limiter = RateLimiter(rpm=10, rpd=100)
        logger.info(
            "Import rate limiter initialised",
            extra={"rpm": 5, "rpd": 20},
        )
    return _import_limiter


def get_image_generation_rate_limiter() -> RateLimiter:
    """Return the shared /generate-image rate limiter (lazily created).

    Limits: 5 requests per day, no per-minute limit (image generation is slow).
    """
    global _image_limiter
    if _image_limiter is None:
        _image_limiter = RateLimiter(rpm=9999, rpd=50)
        logger.info(
            "Image generation rate limiter initialised",
            extra={"rpm": 9999, "rpd": 5},
        )
    return _image_limiter


def get_transcript_rate_limiter() -> RateLimiter:
    """Return the shared /transcript rate limiter (lazily created).

    Limits: 20 req/min + 200 req/day per IP.
    The daily limit protects against sustained scraping that could get the
    server's IP blocked by YouTube.
    """
    global _transcript_limiter
    if _transcript_limiter is None:
        _transcript_limiter = RateLimiter(rpm=20, rpd=200)
        logger.info(
            "Transcript rate limiter initialised",
            extra={"rpm": 20, "rpd": 200},
        )
    return _transcript_limiter


def get_video_rate_limiter() -> RateLimiter:
    """Return the shared video generation rate limiter (lazily created).

    Limits: 2 videos per day per user, no per-minute cap (video generation
    is inherently slow, so minute-level limits are not meaningful).
    """
    global _video_limiter
    if _video_limiter is None:
        _video_limiter = RateLimiter(rpm=10, rpd=50)
        logger.info(
            "Video rate limiter initialised",
            extra={"rpm": 9999, "rpd": 2},
        )
    return _video_limiter
