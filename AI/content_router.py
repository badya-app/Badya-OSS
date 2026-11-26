import os
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Optional
import uuid
import time
import aiofiles
from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Header,
    UploadFile,
    File,
    Form,
    BackgroundTasks,
)
from starlette.concurrency import run_in_threadpool
from starlette.requests import Request
from fastapi.responses import JSONResponse

from rate_limiter import get_import_rate_limiter, get_transcript_rate_limiter

from models import RecommendRequest, EmbedRequest, EmbedResponse, SearchRequest, SearchResponse
from embedding_service import (
    EmbeddingService,
    get_embedding_service,
    get_embedding_service_dep,
)
from recommendation_manager import RecommendationManager
from importer import (
    ImportManager,
    fetch_transcript_list,
    ImportProcessingError,
)
from import_models import ImportItem
from firebase.client import get_db, init_firebase
from firebase_admin import firestore as fb_firestore, auth as fb_auth
import numpy as np

logger = logging.getLogger(__name__)

MAX_UPLOAD_SIZE = 50 * 1024 * 1024  # 50 MB
CHUNK_SIZE = 8 * 1024 * 1024  # 8 MB per chunk


async def verify_firebase_token(
    authorization: Optional[str] = Header(None),
) -> Optional[str]:
    """
    Verify a Firebase ID token from the Authorization header.
    Initializes Firebase if not already initialized.
    """
    allow_dev_fallback = os.environ.get("ALLOW_UNAUTHENTICATED_DEV", "false").lower() == "true"

    if not authorization or not authorization.startswith("Bearer "):
        if allow_dev_fallback:
            logger.warning(
                "No Firebase auth token in request — falling back to request-level user_id (dev mode only). "
                "Clients should send 'Authorization: Bearer <id_token>' for authenticated access."
            )
            return None
        else:
            raise HTTPException(
                status_code=401,
                detail="Authentication required. Missing or invalid Authorization header.",
            )

    token = authorization[7:]
    try:
        # Ensure Firebase is initialized before verifying the token.
        # This handles the case where the startup event hasn't completed yet,
        # or when the function is called outside the normal server lifecycle.
        init_firebase()
        decoded_token = fb_auth.verify_id_token(token, check_revoked=True)
        return decoded_token.get("uid")
    except fb_auth.ExpiredIdTokenError:
        logger.warning("Expired Firebase ID token")
        raise HTTPException(status_code=401, detail="Token expired. Re-authenticate.")
    except fb_auth.RevokedIdTokenError:
        logger.warning("Revoked Firebase ID token")
        raise HTTPException(status_code=401, detail="Token revoked. Re-authenticate.")
    except Exception as e:
        logger.warning(f"Invalid Firebase ID token: {e}")
        raise HTTPException(status_code=401, detail="Invalid authentication token")


# ============================================================================
# Router: Recommendations
# ============================================================================

recommendation_router = APIRouter(prefix="/recommendations", tags=["recommendations"])


@recommendation_router.post("/", response_model=List[dict])
async def get_recommendations(
    request: RecommendRequest,
    auth_uid: Optional[str] = Depends(verify_firebase_token),
    db=Depends(get_db),
    service: EmbeddingService = Depends(get_embedding_service_dep),
):
    effective_user_id = auth_uid or request.user_id
    if auth_uid and auth_uid != request.user_id:
        logger.warning(
            f"User ID mismatch: token uid={auth_uid} vs request user_id={request.user_id}. "
            f"Using token uid."
        )

    if not effective_user_id:
        raise HTTPException(status_code=401, detail="Authentication required")

    manager = RecommendationManager(db, embedding_service=service)
    results = await manager.get_recommendations(
        user_id=effective_user_id,
        language=request.language,
        limit=request.limit,
    )
    return results


@recommendation_router.post("/embed", response_model=EmbedResponse)
async def embed_content(
    request: EmbedRequest,
    service: EmbeddingService = Depends(get_embedding_service_dep),
):
    embedding = service.embed_content(
        title=request.title,
        description=request.description,
        tags=request.tags,
    )
    return EmbedResponse(embedding=embedding)


@recommendation_router.post("/search", response_model=SearchResponse)
async def search_public_content(
    request: SearchRequest,
    db=Depends(get_db),
    service: EmbeddingService = Depends(get_embedding_service_dep),
):
    """
    Search public content across the library with hybrid (semantic + keyword) scoring.

    Generates a query embedding server-side, fetches public content matching the
    language & type filter, scores each item with the same hybrid formula used
    client-side (0.8 semantic + 0.2 keyword), and returns results sorted by
    relevance.  Falls back to keyword-only matching when the embedding service
    is unavailable.
    """
    try:
        query_embedding = service.embed_content(
            title=request.query,
            description="",
            tags=[],
        )
        semantic_available = len(query_embedding) > 0 and any(v != 0.0 for v in query_embedding)
    except Exception:
        logger.warning("Embedding service unavailable for search; falling back to keyword-only")
        query_embedding = None
        semantic_available = False

    query_lower = request.query.lower()

    # Determine which Firestore queries to run based on type_filter
    type_filter = request.type_filter or []
    is_ai_only = type_filter == ["ai_generated"]
    is_non_ai_only = bool(type_filter) and not is_ai_only

    candidates: list[dict] = []

    # Fetch up to 200 candidates (2× the default 100 limit) for better coverage
    fetch_limit = min(request.limit * 4, 200)

    if not is_non_ai_only:
        # AI query — multilingual, no language filter
        ai_query = db.collection("user_content").where("is_public", "==", True)\
            .where("type", "==", "ai_generated")\
            .order_by("created_at", direction=fb_firestore.Query.DESCENDING)\
            .limit(fetch_limit)
        ai_snapshot = ai_query.stream()
        for doc in ai_snapshot:
            data = doc.to_dict()
            data["id"] = doc.id
            candidates.append(data)

    if not is_ai_only:
        # Non-AI query — filtered by assigned_languages
        non_ai_query = db.collection("user_content").where("is_public", "==", True)\
            .where("assigned_languages", "array_contains", request.language)\
            .order_by("created_at", direction=fb_firestore.Query.DESCENDING)\
            .limit(fetch_limit)

        if type_filter:
            # Apply server-side type filter
            if len(type_filter) == 1:
                non_ai_query = non_ai_query.where("type", "==", type_filter[0])
            else:
                non_ai_query = non_ai_query.where("type", "in", type_filter)

        non_ai_snapshot = non_ai_query.stream()
        for doc in non_ai_snapshot:
            data = doc.to_dict()
            data["id"] = doc.id
            candidates.append(data)

    # Deduplicate by content ID
    seen_ids: set[str] = set()
    unique_candidates: list[dict] = []
    for c in candidates:
        cid = c.get("id")
        if cid and cid not in seen_ids:
            seen_ids.add(cid)
            unique_candidates.append(c)

    if not unique_candidates:
        return SearchResponse(items=[], has_more=False)

    # Score each candidate with hybrid (semantic + keyword) formula
    scored: list[tuple[dict, float]] = []

    for item in unique_candidates:
        # --- Keyword score (same formula as client-side) ---
        title = (item.get("title") or "").lower()
        desc = (item.get("description") or "").lower()
        author = (item.get("author_name") or "").lower()
        tags = [t.lower() for t in (item.get("tags") or [])]

        text_match_score = 0.0
        if query_lower in title:
            text_match_score = 1.0
        elif any(query_lower in t for t in tags):
            text_match_score = 0.7
        elif query_lower in author:
            text_match_score = 0.5
        elif query_lower in desc:
            text_match_score = 0.4

        # --- Semantic score ---
        semantic_score = 0.0
        if semantic_available:
            metadata = item.get("metadata") or {}
            item_embedding = metadata.get("embedding")
            if item_embedding and len(item_embedding) == len(query_embedding):
                try:
                    a = np.array(query_embedding)
                    b = np.array(item_embedding)
                    dot = np.dot(a, b)
                    norm_a = np.linalg.norm(a)
                    norm_b = np.linalg.norm(b)
                    if norm_a > 0 and norm_b > 0:
                        semantic_score = float(dot / (norm_a * norm_b))
                except Exception:
                    pass

        # --- Hybrid score (same weights as client: 0.8 semantic + 0.2 keyword) ---
        if semantic_available and text_match_score > 0:
            final_score = semantic_score * 0.8 + text_match_score * 0.2
        elif semantic_available and semantic_score >= 0.65:
            final_score = semantic_score * 0.8
        else:
            final_score = text_match_score

        # Only include if there's any match
        if final_score > 0.0:
            scored.append((item, final_score))

    # Sort by score descending
    scored.sort(key=lambda x: x[1], reverse=True)

    # Convert to serializable format
    items_out: list[dict] = []
    for item, score in scored[:request.limit]:
        # Convert datetime objects to ISO strings
        for key, value in item.items():
            if isinstance(value, datetime):
                item[key] = value.isoformat()
        item["_score"] = score
        items_out.append(item)

    has_more = len(scored) > request.limit

    return SearchResponse(items=items_out, has_more=has_more)


# ============================================================================
# Router: Import
# ============================================================================

import_router = APIRouter(prefix="/import", tags=["import"])
import_manager = ImportManager()


@import_router.get("/health")
async def import_health():
    return {"status": "ok"}


def _write_source_data(user_content_id: str, result, db) -> None:
    """Write extracted raw content to user_content/{contentId}/source/raw."""
    if db is None:
        return
    try:
        source_ref = (
            db.collection("user_content")
            .document(user_content_id)
            .collection("source")
            .document("raw")
        )
        source_updates = {
            "source_type": result.source_type,
            "updated_at": fb_firestore.SERVER_TIMESTAMP,
        }
        if result.source_url:
            source_updates["source_url"] = result.source_url
        if result.metadata:
            transcript_json = result.metadata.get("transcript_json")
            if transcript_json:
                source_updates["transcript_json"] = transcript_json
            word_count = result.metadata.get("word_count")
            if word_count is not None:
                source_updates["word_count"] = word_count
        if result.raw_text:
            source_updates["raw_text"] = result.raw_text

        if len(source_updates) > 2:
            source_ref.set(source_updates, merge=True)
        db.collection("user_content").document(user_content_id).update(
            {
                "updated_at": fb_firestore.SERVER_TIMESTAMP,
            }
        )
    except Exception as e:
        logger.error(f"Failed to write source data for {user_content_id}: {e}")


def _write_result_to_firestore(user_id: str, import_id: str, result, db) -> None:
    """Write import result + embedding directly to user_content/{import_id}.

    The `import_id` sent by the client IS the user_content document ID, so
    there is no separate legacy `users/{uid}/imports/` write anymore.
    """
    if not import_id or db is None:
        return
    user_content_id = import_id
    try:
        firestore_status = "ready" if result.status == "completed" else "failed"
        metadata = dict(result.metadata) if result.metadata else {}
        metadata.setdefault("source_type", result.source_type)
        if result.source_url:
            metadata["source_url"] = result.source_url
            if result.metadata is not None:
                result.metadata["source_url"] = result.source_url
        if result.file_path:
            metadata["file_path"] = result.file_path
            if result.metadata is not None:
                result.metadata["file_path"] = result.file_path

        # Write results directly to the user_content document.
        updates = {
            "status": firestore_status,
            "metadata": metadata,
            "updated_at": fb_firestore.SERVER_TIMESTAMP,
        }
        if result.title and result.title != "Untitled Import":
            updates["title"] = result.title
        if firestore_status == "failed":
            updates["error_message"] = metadata.get("error", "Processing failed")

        db.collection("user_content").document(user_content_id).set(
            updates, merge=True
        )

        # Write source data (transcript, raw text) to source/raw subcollection.
        _write_source_data(user_content_id, result, db)

        # Generate and store embedding.
        try:
            embedding_service = get_embedding_service()
            tags = metadata.get("tags", [])
            if isinstance(tags, str):
                tags = [t.strip() for t in tags.split(",") if t.strip()]
            embedding = embedding_service.embed_content(
                title=result.title or "Untitled",
                description=metadata.get("description", ""),
                tags=tags,
            )
            # Store embedding back in the result metadata dict so it returns to the frontend
            if result.metadata is not None:
                result.metadata["embedding"] = embedding
            else:
                result.metadata = {"embedding": embedding}

            db.collection("user_content").document(user_content_id).update(
                {
                    "metadata.embedding": embedding,
                    "updated_at": fb_firestore.SERVER_TIMESTAMP,
                }
            )
        except Exception as e_emb:
            logger.error(
                f"Embedding generation failed for {user_content_id}: {e_emb}"
            )

    except Exception as e:
        logger.error(
            f"Firestore write-back failed for user_content/{user_content_id}: {e}",
            exc_info=True,
        )


def _run_import_task_async(
    user_id: str, data: dict, import_id: str, final_file_path: Optional[str], db
):
    """Background task wrapper for import processing."""
    try:
        result = import_manager.process_import(user_id, data, item_id=import_id)
        _write_result_to_firestore(user_id, result.id, result, db)
    except Exception as e:
        logger.error(
            f"Background import task failed for {import_id}: {e}", exc_info=True
        )
        try:
            error_id = import_id if import_id else str(uuid.uuid4())
            _write_result_to_firestore(
                user_id,
                error_id,
                ImportItem(
                    id=error_id,
                    user_id=user_id,
                    title=data.get("title", "Untitled Import"),
                    source_type=data.get("source_type", ""),
                    status="failed",
                    metadata={"error": str(e), "source_type": data.get("source_type")},
                ),
                db,
            )
        except Exception:
            pass
    finally:
        if final_file_path:
            import_manager._cleanup_temp_file(final_file_path)


@import_router.post("", status_code=202)
async def process_import(
    background_tasks: BackgroundTasks,
    auth_uid: Optional[str] = Depends(verify_firebase_token),
    user_id: str = Form(...),
    source_type: str = Form(...),
    source_url: Optional[str] = Form(None),
    title: Optional[str] = Form(None),
    subject_id: Optional[str] = Form(None),
    import_id: Optional[str] = Form(None),
    raw_text: Optional[str] = Form(None),
    target_language: Optional[str] = Form(None),
    run_sync: bool = Form(False),
    file: Optional[UploadFile] = File(None),
):
    effective_user_id = auth_uid or user_id
    if auth_uid and auth_uid != user_id:
        logger.warning(
            f"User ID mismatch: token uid={auth_uid} vs form user_id={user_id}. "
            f"Using token uid."
        )

    if not effective_user_id:
        raise HTTPException(status_code=401, detail="Authentication required")

    # Rate limit check: 5 req/min + 20 req/day per user
    get_import_rate_limiter().check(effective_user_id)

    logger.info(
        f"[Import] Received: type={source_type}, sync={run_sync}, id={import_id}"
    )
    final_file_path: Optional[str] = None
    UPLOAD_DIR = Path(__file__).parent / "temp_uploads"
    UPLOAD_DIR.mkdir(exist_ok=True)

    _sync_cleanup_done = False

    try:
        if file:
            content_length = file.headers.get("content-length")
            if content_length is not None:
                try:
                    if int(content_length) > MAX_UPLOAD_SIZE:
                        raise HTTPException(
                            status_code=413,
                            detail=f"File too large. Maximum size is {MAX_UPLOAD_SIZE // (1024 * 1024)} MB.",
                        )
                except (ValueError, TypeError):
                    pass

            safe_filename = Path(file.filename).name
            temp_path = UPLOAD_DIR / f"{import_id or 'temp'}_{safe_filename}"

            total_size = 0
            async with aiofiles.open(temp_path, "wb") as buffer:
                while chunk := await file.read(CHUNK_SIZE):
                    total_size += len(chunk)
                    if total_size > MAX_UPLOAD_SIZE:
                        import_manager._cleanup_temp_file(str(temp_path.absolute()))
                        raise HTTPException(
                            status_code=413,
                            detail=f"File too large. Maximum size is {MAX_UPLOAD_SIZE // (1024 * 1024)} MB.",
                        )
                    await buffer.write(chunk)

            final_file_path = str(temp_path.absolute())

        data = {
            "source_type": source_type,
            "source_url": source_url,
            "file_path": final_file_path,
            "raw_text": raw_text,
            "title": title,
            "subject_id": subject_id,
            "target_language": target_language,
        }
        db = get_db()

        if run_sync:
            try:
                result = await run_in_threadpool(
                    import_manager.process_import, effective_user_id, data, import_id
                )
                _write_result_to_firestore(effective_user_id, result.id, result, db)
                success = result.status == "completed"
                result_dict = result.to_dict()
                result_dict["status"] = "success" if success else "failed"
                result_dict["message"] = (
                    "Import processed successfully."
                    if success
                    else result.metadata.get("error", "Processing failed")
                )
                return JSONResponse(status_code=200, content=result_dict)
            finally:
                if final_file_path:
                    import_manager._cleanup_temp_file(final_file_path)
                    _sync_cleanup_done = True
        else:
            background_tasks.add_task(
                _run_import_task_async,
                effective_user_id,
                data,
                import_id or "",
                final_file_path,
                db,
            )
            return JSONResponse(
                status_code=202,
                content={
                    "status": "queued",
                    "import_id": import_id,
                    "message": "Import queued. Check Firestore for status updates.",
                },
            )

    except ImportProcessingError as e:
        if final_file_path and not _sync_cleanup_done:
            import_manager._cleanup_temp_file(final_file_path)
        logger.warning(f"[Import] Processing error: {e}")
        return JSONResponse(
            status_code=200,
            content={
                "status": "failed",
                "code": e.code,
                "message": str(e),
            },
        )
    except HTTPException:
        raise
    except Exception as e:
        if final_file_path and not _sync_cleanup_done:
            import_manager._cleanup_temp_file(final_file_path)
        logger.exception(f"[Import] Unexpected error: {e}")
        return JSONResponse(
            status_code=200, content={"status": "failed", "message": str(e)}
        )


@import_router.get("/transcript")
async def fetch_transcript(
    video_id: str,
    lang: Optional[str] = None,
    request: Request = None,
):
    """Fetch a YouTube transcript."""
    # Rate limit per client IP
    client_ip = request.client.host if request and request.client else "unknown"
    get_transcript_rate_limiter().check(client_ip)

    try:
        from youtube_transcript_api import YouTubeTranscriptApi
    except ImportError:
        raise HTTPException(
            status_code=500, detail="youtube_transcript_api not installed"
        )

    try:
        transcript_list_obj = fetch_transcript_list(video_id)
        all_trans = []
        try:
            all_trans = list(transcript_list_obj)
        except Exception:
            if hasattr(transcript_list_obj, "_manually_created_transcripts"):
                all_trans.extend(
                    transcript_list_obj._manually_created_transcripts.values()
                )
                all_trans.extend(transcript_list_obj._generated_transcripts.values())

        if not all_trans:
            raise HTTPException(status_code=404, detail="No transcripts found")

        available = [
            {
                "code": import_manager._clean_lang(t.language_code) or t.language_code,
                "name": t.language,
                "auto": t.is_generated,
            }
            for t in all_trans
        ]

        selected = None
        if lang:
            clean_lang = import_manager._clean_lang(lang)
            for t in all_trans:
                t_code = import_manager._clean_lang(t.language_code) or t.language_code
                if t_code == clean_lang and not t.is_generated:
                    selected = t
                    break
            if selected is None:
                for t in all_trans:
                    t_code = (
                        import_manager._clean_lang(t.language_code) or t.language_code
                    )
                    if t_code == clean_lang:
                        selected = t
                        break

        if selected is None:
            manual = [t for t in all_trans if not t.is_generated]
            selected = manual[0] if manual else all_trans[0]

        entries = import_manager._fetch_transcript_entries(selected)
        if not entries:
            raise HTTPException(status_code=404, detail="Transcript is empty")

        selected_code = (
            import_manager._clean_lang(selected.language_code) or selected.language_code
        )
        return {
            "transcript": entries,
            "language": selected_code,
            "language_name": selected.language,
            "is_auto": selected.is_generated,
            "available": available,
        }
    except HTTPException:
        raise
    except Exception as e:
        err_str = str(e)
        is_ip_blocked = any(
            kw in err_str
            for kw in [
                "IP",
                "blocked",
                "bot",
                "Sign in",
                "RequestBlocked",
                "IPBlocked",
                "Could not retrieve",
                "403",
                "Forbidden",
            ]
        )
        if is_ip_blocked:
            return JSONResponse(
                status_code=502,
                content={
                    "status": "failed",
                    "error": "ip_blocked",
                    "message": "YouTube is blocking transcript requests from this server's IP.",
                    "transcript": [],
                    "available": [],
                },
            )
        return JSONResponse(
            status_code=500,
            content={
                "status": "failed",
                "error": "extraction_failed",
                "message": str(e),
            },
        )
